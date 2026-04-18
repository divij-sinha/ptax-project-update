"""
batch_generate.py — Pre-generate all residential (200s/300s) PTAX and TIF explainers.

Tracks progress in a local SQLite DB (batch_tracking.db) and enqueues jobs via
Redis/RQ so workers can run them in parallel. Outputs go to the NAS mount defined
by OUTPUT_ROOT in .env.

Usage
-----
  python batch_generate.py init                  # Populate tracking DB from ptaxsim DB (one-time)
  python batch_generate.py enqueue               # Enqueue all pending jobs
  python batch_generate.py enqueue --class 203   # Enqueue only class 203
  python batch_generate.py enqueue --retry-failed # Also re-enqueue failed jobs
  python batch_generate.py sync                  # Update tracking DB from RQ + output file presence
  python batch_generate.py status                # Print progress summary by class
"""

import argparse
import logging
import os
import sqlite3
import sys
from datetime import datetime, timedelta, timezone

import polars as pl
from dotenv import load_dotenv
from redis import Redis
from rq import Queue

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

load_dotenv(dotenv_path=os.path.join(os.path.dirname(__file__), ".env"))

VERSION = "2.3"
PRIOR_YEAR = 2023
MODES = ["TIF", "PTAX"]

PTAX_DB_PATH = "data/ptaxsim-2024.0.0-alpha.1.db"
ADDRESS_PARQUET = "data/address_points.parquet"
TRACKING_DB = "batch_tracking.db"
LOG_FILE = "batch_generate.log"

PENDING = "pending"
QUEUED  = "queued"
DONE    = "done"
FAILED  = "failed"

# ---------------------------------------------------------------------------
# Logging — both console (INFO) and rotating log file (DEBUG)
# ---------------------------------------------------------------------------

logger = logging.getLogger("batch_generate")
logger.setLevel(logging.DEBUG)

_fmt = logging.Formatter("%(asctime)s  %(levelname)-7s  %(message)s", datefmt="%Y-%m-%d %H:%M:%S")

_fh = logging.FileHandler(LOG_FILE, encoding="utf-8")
_fh.setLevel(logging.DEBUG)
_fh.setFormatter(_fmt)

_ch = logging.StreamHandler(sys.stdout)
_ch.setLevel(logging.INFO)
_ch.setFormatter(_fmt)

logger.addHandler(_fh)
logger.addHandler(_ch)

OUTPUT_ROOT_ENV = os.getenv("OUTPUT_ROOT")
if OUTPUT_ROOT_ENV:
    NAS_OUTPUT_ROOT = os.path.join(OUTPUT_ROOT_ENV, "ptax-project-update", "outputs")
else:
    NAS_OUTPUT_ROOT = None

QMD_FILES = {
    "TIF": os.path.abspath("ptaxsim_explainer_tif.qmd"),
    "PTAX": os.path.abspath("ptaxsim_explainer.qmd"),
}

redis_conn = Redis()
queue = Queue(connection=redis_conn)

# ---------------------------------------------------------------------------
# Tracking DB helpers
# ---------------------------------------------------------------------------


def get_tracking_conn() -> sqlite3.Connection:
    conn = sqlite3.connect(TRACKING_DB, timeout=60)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    return conn


def init_tracking_db(conn: sqlite3.Connection):
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS jobs (
            pin       TEXT    NOT NULL,
            class     TEXT    NOT NULL,
            address   TEXT    NOT NULL,
            mode      TEXT    NOT NULL,
            status    TEXT    NOT NULL DEFAULT 'pending',
            job_id    TEXT,
            queued_at TEXT,
            updated_at TEXT,
            PRIMARY KEY (pin, mode)
        );
        CREATE INDEX IF NOT EXISTS idx_jobs_class  ON jobs(class);
        CREATE INDEX IF NOT EXISTS idx_jobs_status ON jobs(status);
        CREATE INDEX IF NOT EXISTS idx_jobs_mode   ON jobs(mode);
    """)
    conn.commit()


# ---------------------------------------------------------------------------
# Address lookup (vectorised — load parquet once)
# ---------------------------------------------------------------------------


_address_lookup: dict[str, str] | None = None


def load_address_lookup() -> dict[str, str]:
    global _address_lookup
    if _address_lookup is None:
        print("Loading address parquet…")
        df = pl.read_parquet(ADDRESS_PARQUET, columns=["PIN", "ADDRDELIV"])
        _address_lookup = dict(zip(df["PIN"].to_list(), df["ADDRDELIV"].to_list()))
        print(f"  {len(_address_lookup):,} addresses loaded.")
    return _address_lookup


# ---------------------------------------------------------------------------
# Output path helper
# ---------------------------------------------------------------------------


def output_html_filename(mode: str, pin: str) -> str:
    if mode == "TIF":
        return f"{pin}.html"
    return f"{pin}_{PRIOR_YEAR}.html"


def output_html_path(mode: str, pin: str, root: str | None = None) -> str:
    fname = output_html_filename(mode, pin)
    nas = root or NAS_OUTPUT_ROOT
    if nas:
        return os.path.join(nas, f"v{VERSION}", mode, pin, fname)
    return os.path.join(f"outputs/v{VERSION}", mode, pin, fname)


def output_exists(mode: str, pin: str) -> bool:
    return os.path.exists(output_html_path(mode, pin))


# ---------------------------------------------------------------------------
# Throughput helper
# ---------------------------------------------------------------------------


def _throughput_stats(conn: sqlite3.Connection) -> None:
    cur = conn.cursor()
    now = datetime.now(timezone.utc)

    windows = [
        ("1 min",  timedelta(minutes=1)),
        ("5 min",  timedelta(minutes=5)),
        ("15 min", timedelta(minutes=15)),
        ("1 hour", timedelta(hours=1)),
    ]
    cutoffs = [(now - d).isoformat() for _, d in windows]

    cur.execute("""
        SELECT
            SUM(CASE WHEN status = ? AND updated_at >= ? THEN 1 ELSE 0 END),
            SUM(CASE WHEN status = ? AND updated_at >= ? THEN 1 ELSE 0 END),
            SUM(CASE WHEN status = ? AND updated_at >= ? THEN 1 ELSE 0 END),
            SUM(CASE WHEN status = ? AND updated_at >= ? THEN 1 ELSE 0 END),
            SUM(CASE WHEN status != ? THEN 1 ELSE 0 END)
        FROM jobs
    """, [v for c in cutoffs for v in (DONE, c)] + [DONE])
    row = cur.fetchone()
    counts = [row[0] or 0, row[1] or 0, row[2] or 0, row[3] or 0]
    remaining = row[4] or 0

    print("\nThroughput (pins marked done per window):")
    fifteen_min_rate = None
    for (label, delta), count in zip(windows, counts):
        rate = count / (delta.total_seconds() / 60)
        print(f"  Last {label:6s}: {count:>7,} pins  ({rate:6.1f} pins/min)")
        if label == "15 min":
            fifteen_min_rate = rate

    print(f"\n  Remaining: {remaining:,} jobs")
    if fifteen_min_rate and fifteen_min_rate > 0:
        eta_min = remaining / fifteen_min_rate
        eta_h, eta_m = divmod(int(eta_min), 60)
        print(f"  ETA (at 15-min rate): ~{eta_h}h {eta_m:02d}m")
    else:
        print("  ETA: insufficient recent activity to estimate")


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------


def cmd_init(args):
    """Populate tracking DB with all residential PINs (both modes)."""
    conn = get_tracking_conn()
    init_tracking_db(conn)

    cur = conn.cursor()
    cur.execute("SELECT COUNT(*) FROM jobs")
    existing = cur.fetchone()[0]
    if existing > 0 and not args.force:
        print(f"Tracking DB already has {existing:,} rows. Use --force to re-init.")
        return

    print("Loading residential PINs from ptaxsim DB…")
    ptax = sqlite3.connect(PTAX_DB_PATH)
    ptax_cur = ptax.cursor()
    ptax_cur.execute("""
        SELECT DISTINCT pin, class
        FROM pin
        WHERE year = 2024
          AND (class LIKE '2%' OR class LIKE '3%')
        ORDER BY class, pin
    """)
    pins = ptax_cur.fetchall()
    ptax.close()
    print(f"  {len(pins):,} residential PINs found.")

    print("Loading addresses…")
    lookup = load_address_lookup()

    now = datetime.now(timezone.utc).isoformat()
    rows = []
    for pin, cls in pins:
        addr = lookup.get(pin) or lookup.get(pin[:-4] + "0000") or "--NOT FOUND--"
        for mode in MODES:
            rows.append((pin, str(cls), addr, mode, PENDING, None, None, now))

    total = len(rows)
    print(f"Inserting {total:,} job rows ({len(pins):,} PINs × {len(MODES)} modes)…")
    CHUNK = 50_000
    sql = "INSERT OR REPLACE INTO jobs (pin, class, address, mode, status, job_id, queued_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
    for i in range(0, total, CHUNK):
        conn.executemany(sql, rows[i : i + CHUNK])
        conn.commit()
        print(f"  {min(i + CHUNK, total):,} / {total:,}…", end="\r")
    print()
    conn.close()
    print("Done — tracking DB initialised.")


def cmd_enqueue(args):
    """Enqueue pending (and optionally failed) jobs."""
    conn = get_tracking_conn()
    init_tracking_db(conn)

    statuses = [PENDING]
    if args.retry_failed:
        statuses.append(FAILED)

    placeholders = ",".join("?" * len(statuses))
    query = f"SELECT pin, class, address, mode FROM jobs WHERE status IN ({placeholders})"
    params = statuses

    if args.class_code:
        query += " AND class = ?"
        params.append(args.class_code)

    query += " ORDER BY class, pin, mode"

    cur = conn.cursor()
    cur.execute(query, params)
    pending = cur.fetchall()

    if not pending:
        print("No jobs to enqueue.")
        conn.close()
        return

    print(f"Enqueueing {len(pending):,} jobs…")
    if args.dry_run:
        dry_q = f"SELECT class, COUNT(*) FROM jobs WHERE status IN ({placeholders})"
        dry_params = list(statuses)
        if args.class_code:
            dry_q += " AND class = ?"
            dry_params.append(args.class_code)
        dry_q += " GROUP BY class ORDER BY class"
        for cls, cnt in cur.execute(dry_q, dry_params):
            print(f"  class {cls}: {cnt:,}")
        print("(dry run — nothing enqueued)")
        conn.close()
        return

    if not NAS_OUTPUT_ROOT:
        print("ERROR: OUTPUT_ROOT is not set in .env. Cannot determine NAS output path.")
        sys.exit(1)

    now = datetime.now(timezone.utc).isoformat()
    # Group by class for progress reporting
    current_class = None
    enqueued = 0

    for pin, cls, addr, mode in pending:
        if cls != current_class:
            if current_class is not None:
                print(f"  class {current_class} done.")
            current_class = cls
            print(f"  class {cls}…", end="", flush=True)

        # Skip if output already exists on NAS
        if output_exists(mode, pin):
            conn.execute("UPDATE jobs SET status=?, updated_at=? WHERE pin=? AND mode=?", (DONE, now, pin, mode))
            logger.debug("SKIPPED  pin=%s mode=%s  output already exists", pin, mode)
            continue

        job = queue.enqueue(
            "app.main.run_quarto",
            QMD_FILES[mode],
            pin,
            PRIOR_YEAR,
            addr,
            mode,
            output_root=NAS_OUTPUT_ROOT,
            result_ttl=86400,
            job_timeout=600,
        )
        conn.execute(
            "UPDATE jobs SET status=?, job_id=?, queued_at=?, updated_at=? WHERE pin=? AND mode=?",
            (QUEUED, job.id, now, now, pin, mode),
        )
        logger.debug("ENQUEUED pin=%s mode=%s class=%s job_id=%s", pin, mode, cls, job.id)
        enqueued += 1
        if enqueued % 500 == 0:
            conn.commit()  # commit in batches to avoid huge transactions

    if current_class:
        print(f"  class {current_class} done.")

    conn.commit()
    conn.close()
    logger.info("Enqueue complete: %d jobs enqueued. Queue depth: %d", enqueued, len(queue))


def cmd_sync(args):
    """
    Sync tracking DB:
      1. For 'queued' jobs: check RQ status + output file presence.
      2. For 'pending' jobs: check if output already exists (e.g. from a prior run).
    """
    conn = get_tracking_conn()
    init_tracking_db(conn)
    cur = conn.cursor()
    now = datetime.now(timezone.utc).isoformat()

    cur2 = conn.cursor()
    cur2.execute("SELECT COUNT(*) FROM jobs WHERE status = ?", (QUEUED,))
    total_queued = cur2.fetchone()[0]
    done_count = failed_count = still_running = 0

    logger.info("Syncing %d queued jobs…", total_queued)
    cur2.execute("SELECT pin, mode, job_id FROM jobs WHERE status = ?", (QUEUED,))
    for i, (pin, mode, job_id) in enumerate(cur2):
        if output_exists(mode, pin):
            conn.execute("UPDATE jobs SET status=?, updated_at=? WHERE pin=? AND mode=?", (DONE, now, pin, mode))
            logger.debug("DONE     pin=%s mode=%s  output file found", pin, mode)
            done_count += 1
        elif job_id:
            job = queue.fetch_job(job_id)
            if job is None:
                conn.execute("UPDATE jobs SET status=?, updated_at=? WHERE pin=? AND mode=?", (FAILED, now, pin, mode))
                logger.warning("FAILED   pin=%s mode=%s job_id=%s  job expired from Redis", pin, mode, job_id)
                failed_count += 1
            elif job.is_finished:
                conn.execute("UPDATE jobs SET status=?, updated_at=? WHERE pin=? AND mode=?", (DONE, now, pin, mode))
                logger.debug("DONE     pin=%s mode=%s job_id=%s  RQ finished", pin, mode, job_id)
                done_count += 1
            elif job.is_failed:
                conn.execute("UPDATE jobs SET status=?, updated_at=? WHERE pin=? AND mode=?", (FAILED, now, pin, mode))
                logger.warning("FAILED   pin=%s mode=%s job_id=%s  RQ job failed", pin, mode, job_id)
                failed_count += 1
            else:
                still_running += 1

        if i % 1000 == 0 and i > 0:
            conn.commit()
            print(f"  {i:,} / {total_queued:,}…", end="\r")

    pre_done = 0
    if args.check_pending:
        cur2.execute("SELECT COUNT(*) FROM jobs WHERE status = ?", (PENDING,))
        total_pending = cur2.fetchone()[0]
        print(f"\nChecking {total_pending:,} pending jobs for existing output…")
        cur2.execute("SELECT pin, mode FROM jobs WHERE status = ?", (PENDING,))
        for i, (pin, mode) in enumerate(cur2):
            if output_exists(mode, pin):
                conn.execute("UPDATE jobs SET status=?, updated_at=? WHERE pin=? AND mode=?", (DONE, now, pin, mode))
                pre_done += 1
            if i % 5000 == 0 and i > 0:
                conn.commit()
                print(f"  {i:,} / {total_pending:,}…", end="\r")

    conn.commit()
    logger.info(
        "Sync complete — done: %d  failed: %d  still running: %d",
        done_count + pre_done,
        failed_count,
        still_running,
    )
    _throughput_stats(conn)
    conn.close()


def cmd_status(args):
    """Print progress summary grouped by class code."""
    conn = get_tracking_conn()
    init_tracking_db(conn)
    cur = conn.cursor()

    if args.class_code:
        cur.execute(
            """
            SELECT mode, status, COUNT(*) as cnt
            FROM jobs WHERE class = ?
            GROUP BY mode, status ORDER BY mode, status
            """,
            (args.class_code,),
        )
        rows = cur.fetchall()
        if not rows:
            print(f"No jobs found for class {args.class_code}.")
        else:
            print(f"\nClass {args.class_code}:")
            for r in rows:
                print(f"  {r['mode']:4s}  {r['status']:8s}  {r['cnt']:>8,}")
    else:
        cur.execute("""
            SELECT class, mode, status, COUNT(*) as cnt
            FROM jobs
            GROUP BY class, mode, status
            ORDER BY class, mode, status
        """)
        rows = cur.fetchall()

        cur.execute("SELECT status, COUNT(*) FROM jobs GROUP BY status")
        totals = {r[0]: r[1] for r in cur.fetchall()}

        print(f"\n{'Class':>6}  {'Mode':4}  {'Pending':>8}  {'Queued':>8}  {'Done':>8}  {'Failed':>8}")
        print("-" * 56)

        by_class: dict[str, dict[str, dict[str, int]]] = {}
        for r in rows:
            by_class.setdefault(r["class"], {}).setdefault(r["mode"], {})[r["status"]] = r["cnt"]

        for cls in sorted(by_class):
            for mode in MODES:
                s = by_class[cls].get(mode, {})
                print(
                    f"{cls:>6}  {mode:4}  "
                    f"{s.get(PENDING, 0):>8,}  "
                    f"{s.get(QUEUED,  0):>8,}  "
                    f"{s.get(DONE,    0):>8,}  "
                    f"{s.get(FAILED,  0):>8,}"
                )

        print("-" * 56)
        print(
            f"{'TOTAL':>6}  {'ALL ':4}  "
            f"{totals.get(PENDING, 0):>8,}  "
            f"{totals.get(QUEUED,  0):>8,}  "
            f"{totals.get(DONE,    0):>8,}  "
            f"{totals.get(FAILED,  0):>8,}"
        )

    _throughput_stats(conn)
    conn.close()


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(
        description="Batch pre-generate PTAX/TIF explainers for all residential PINs."
    )
    sub = parser.add_subparsers(dest="command", required=True)

    # init
    p_init = sub.add_parser("init", help="Populate tracking DB from ptaxsim DB (run once).")
    p_init.add_argument("--force", action="store_true", help="Re-init even if rows already exist.")

    # enqueue
    p_enqueue = sub.add_parser("enqueue", help="Enqueue pending jobs into RQ.")
    p_enqueue.add_argument("--class", dest="class_code", metavar="CODE", help="Limit to one class code.")
    p_enqueue.add_argument("--retry-failed", action="store_true", help="Also re-enqueue failed jobs.")
    p_enqueue.add_argument("--dry-run", action="store_true", help="Show counts without enqueueing.")

    # sync
    p_sync = sub.add_parser("sync", help="Update tracking DB from RQ statuses and output files.")
    p_sync.add_argument("--check-pending", action="store_true", help="Also scan pending jobs for existing output on NAS (slow).")

    # status
    p_status = sub.add_parser("status", help="Print progress summary.")
    p_status.add_argument("--class", dest="class_code", metavar="CODE", help="Limit to one class code.")

    args = parser.parse_args()

    if args.command == "init":
        cmd_init(args)
    elif args.command == "enqueue":
        cmd_enqueue(args)
    elif args.command == "sync":
        cmd_sync(args)
    elif args.command == "status":
        cmd_status(args)


if __name__ == "__main__":
    main()
