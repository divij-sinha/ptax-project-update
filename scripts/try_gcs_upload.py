"""
try_gcs_upload.py — Smoke test: upload a small sample of HTML files from NAS to GCS.

Usage:
    GCS_BUCKET=<bucket> python scripts/try_gcs_upload.py [--count N] [--mode TIF]

Uploads to gs://$GCS_BUCKET/$GCS_PREFIX/v{VERSION}/{mode}/{pin}/{fname}.
GCS_PREFIX defaults to "ptax-project/outputs".

Requires:
    - google-cloud-storage installed
    - Application Default Credentials set up (gcloud auth application-default login
      on dev, or a service account on the batch machine)
    - OUTPUT_ROOT in .env pointing at the NAS mount root
"""

import argparse
import os
import sqlite3
import sys
import time
from pathlib import Path

from dotenv import load_dotenv
from google.cloud import storage

load_dotenv(dotenv_path=os.path.join(os.path.dirname(__file__), "..", ".env"))

VERSION = "2.3"
PRIOR_YEAR = 2023
DEFAULT_PREFIX = "ptax-project/outputs"
TRACKING_DB = os.path.join(os.path.dirname(__file__), "..", "batch_tracking.db")


def find_nas_root() -> Path:
    root = os.getenv("OUTPUT_ROOT")
    if not root:
        sys.exit("OUTPUT_ROOT not set in .env")
    nas = Path(root) / "ptax-project-update" / "outputs" / f"v{VERSION}"
    if not nas.is_dir():
        sys.exit(f"NAS path not found: {nas}")
    return nas


def _expected_filename(mode: str, pin: str) -> str:
    if mode == "TIF":
        return f"{pin}.html"
    return f"{pin}_{PRIOR_YEAR}.html"


def pick_sample(nas_root: Path, mode: str, count: int) -> list[Path]:
    """Query tracking DB for `count` completed PINs of `mode` and return their NAS paths.

    Avoids rglob/listdir on huge NAS directories, which hang on SMB.
    """
    if not os.path.exists(TRACKING_DB):
        sys.exit(f"Tracking DB not found: {TRACKING_DB}")
    conn = sqlite3.connect(f"file:{TRACKING_DB}?mode=ro", uri=True)
    rows = conn.execute(
        "SELECT pin FROM jobs WHERE mode = ? AND status = 'done' LIMIT ?",
        (mode, count),
    ).fetchall()
    conn.close()
    if not rows:
        sys.exit(f"No completed {mode} jobs in tracking DB")
    out: list[Path] = []
    for (pin,) in rows:
        p = nas_root / mode / pin / _expected_filename(mode, pin)
        out.append(p)
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--count", type=int, default=10, help="Number of files to upload.")
    ap.add_argument("--mode", default="TIF", choices=["TIF", "PTAX"], help="Which report type to sample.")
    ap.add_argument("--dry-run", action="store_true", help="Print what would upload; don't upload.")
    args = ap.parse_args()

    bucket_name = os.getenv("GCS_BUCKET")
    if not bucket_name:
        sys.exit("GCS_BUCKET not set in env")
    gcs_prefix = os.getenv("GCS_PREFIX", DEFAULT_PREFIX).strip("/")

    nas_root = find_nas_root()
    sample = pick_sample(nas_root, args.mode, args.count)

    dest_root = f"{gcs_prefix}/v{VERSION}"
    print(f"NAS root:  {nas_root}")
    print(f"Dest:      gs://{bucket_name}/{dest_root}/")
    print(f"Sampled {len(sample)} files under {args.mode}:")
    for p in sample:
        rel = p.relative_to(nas_root)
        print(f"  {rel}")

    if args.dry_run:
        print("\nDry run — not uploading.")
        return

    client = storage.Client()
    bucket = client.bucket(bucket_name)

    ok = 0
    failed = 0
    t0 = time.time()
    for src in sample:
        rel = src.relative_to(nas_root)
        blob_name = f"{dest_root}/{rel.as_posix()}"
        blob = bucket.blob(blob_name)
        try:
            blob.upload_from_filename(str(src), content_type="text/html")
            print(f"  ✓ gs://{bucket_name}/{blob_name}  ({src.stat().st_size} bytes)")
            ok += 1
        except Exception as e:
            print(f"  ✗ {blob_name}: {e}")
            failed += 1

    dt = time.time() - t0
    print(f"\nDone: {ok} uploaded, {failed} failed in {dt:.1f}s")

    if ok:
        print("\nVerify with:")
        print(f"  gsutil ls gs://{bucket_name}/{dest_root}/{args.mode}/ | head")


if __name__ == "__main__":
    main()
