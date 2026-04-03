"""
Compare rendered HTML outputs between a local server and production.

Submits 5 PINs in PTAX mode and 5 in TIF mode to both hosts, waits for all
renders to complete, then reports what percentage of output files differ.

Usage:
    python test_server/compare_outputs.py --host-a http://localhost:8000

    # Override the pins (comma-separated, 5 each):
    python test_server/compare_outputs.py --host-a http://localhost:8000 \
        --ptax-pins 31221020050000,13122220591004,17044240511030,11311130330000,16212230090000 \
        --tif-pins  29204110140000,05063010170000,14202210431001,17101320371648,13031140020000
"""

import argparse
import difflib
import re
import sys
import time

import requests

POLL_INTERVAL = 5
RENDER_TIMEOUT = 300

PROD_PTAX_HOST = "https://ptaxexplainer.miurban-dashboards.org"
PROD_TIF_HOST = "https://tifexplainer.miurban-dashboards.org"

DEFAULT_PTAX_PINS = [
    "31221020050000",
    "13122220591004",
    "17044240511030",
    "11311130330000",
    "16212230090000",
]
DEFAULT_TIF_PINS = [
    "29204110140000",
    "05063010170000",
    "14202210431001",
    "17101320371648",
    "13031140020000",
]


def strip_noise(html: str) -> str:
    """Remove script, style, and image tags, then strip all remaining HTML tags,
    leaving only the text content (numbers, tables, prose)."""
    html = re.sub(r"<script[^>]*>.*?</script>", "", html, flags=re.DOTALL)
    html = re.sub(r"<style[^>]*>.*?</style>", "", html, flags=re.DOTALL)
    html = re.sub(r"<img[^>]*>", "", html)
    html = re.sub(r"<[^>]+>", "", html)
    # Collapse whitespace so minor spacing differences don't show as diffs
    lines = []
    for line in html.splitlines():
        line = line.strip()
        if not line:
            continue
        # Quarto callout block labels (Note, Tip, Important, Warning, Caution)
        # appear as prefixes in some versions but not others
        for prefix in ("Note", "Tip", "Important", "Warning", "Caution"):
            if line.startswith(prefix) and len(line) > len(prefix) and line[len(prefix)].isupper():
                line = line[len(prefix):]
                break
        # Normalise address-not-found fallback strings across versions
        line = line.replace("\u2013NOT FOUND\u2013", "(Address not found)")
        lines.append(line)
    return "\n".join(lines)


def fetch_render(host: str, pin: str, mode: str) -> tuple[str | None, float]:
    """Submit a PIN and poll until the HTML is returned.
    Returns (html, elapsed_seconds) — html is None on failure."""
    session = requests.Session()
    t_start = time.time()

    resp = session.post(
        f"{host}/submit",
        data={
            "search_category": "three_years",
            "search_term": pin,
            "search_term_hidden": pin,
            "mode": mode,
        },
        allow_redirects=True,
        timeout=30,
    )

    if resp.status_code != 200:
        print(f"  [{host}] {mode}/{pin}: submit failed ({resp.status_code})")
        return None, time.time() - t_start

    if "/outputs/" in resp.url and resp.url.endswith(".html"):
        return resp.text, time.time() - t_start

    deadline = time.time() + RENDER_TIMEOUT
    n = 1
    while time.time() < deadline:
        r = session.get(
            f"{host}/check_complete",
            params={"pin": pin, "mode": mode, "n": n},
            allow_redirects=True,
            timeout=30,
        )
        if "/outputs/" in r.url and r.url.endswith(".html"):
            return r.text, time.time() - t_start
        if r.status_code >= 500:
            print(f"  [{host}] {mode}/{pin}: server error ({r.status_code})")
            return None, time.time() - t_start
        n += 1
        time.sleep(POLL_INTERVAL)

    print(f"  [{host}] {mode}/{pin}: timed out after {RENDER_TIMEOUT}s")
    return None, time.time() - t_start


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host-a", required=True, help="Local server to test (e.g. http://localhost:8000)")
    parser.add_argument("--ptax-pins", default=",".join(DEFAULT_PTAX_PINS))
    parser.add_argument("--tif-pins", default=",".join(DEFAULT_TIF_PINS))
    args = parser.parse_args()

    ptax_pins = args.ptax_pins.split(",")
    tif_pins = args.tif_pins.split(",")

    # (pin, mode, host_b)
    jobs = (
        [(pin, "PTAX", PROD_PTAX_HOST) for pin in ptax_pins]
        + [(pin, "TIF", PROD_TIF_HOST) for pin in tif_pins]
    )

    total = 0
    different = 0
    failed = 0
    times: dict[str, list[float]] = {"PTAX_local": [], "PTAX_prod": [], "TIF_local": [], "TIF_prod": []}

    for pin, mode, host_b in jobs:
        print(f"Rendering {mode}/{pin} ...")
        html_a, t_a = fetch_render(args.host_a, pin, mode)
        html_b, t_b = fetch_render(host_b, pin, mode)

        times[f"{mode}_local"].append(t_a)
        times[f"{mode}_prod"].append(t_b)
        print(f"  local={t_a:.1f}s  prod={t_b:.1f}s")

        total += 1
        if html_a is None or html_b is None:
            failed += 1
            print(f"  SKIP (render failed on one or both hosts)")
            continue

        text_a = strip_noise(html_a)
        text_b = strip_noise(html_b)
        if text_a == text_b:
            print(f"  SAME")
        else:
            different += 1
            lines_a = text_a.splitlines()
            lines_b = text_b.splitlines()
            diff = list(difflib.unified_diff(lines_a, lines_b, fromfile=f"local/{pin}.html", tofile=f"prod/{pin}.html", lineterm=""))
            print(f"  DIFFERENT ({len(diff)} diff lines)")
            print("\n".join(diff[:50]))
            if len(diff) > 50:
                print(f"  ... ({len(diff) - 50} more lines)")

    print(f"\nResults: {total} renders, {different} different, {failed} failed")
    if total > 0:
        print(f"  {different / total * 100:.0f}% of outputs differ")

    print(f"\nAverage render times:")
    for key, vals in times.items():
        if vals:
            print(f"  {key}: {sum(vals) / len(vals):.1f}s")

    sys.exit(1 if different > 0 else 0)


if __name__ == "__main__":
    main()
