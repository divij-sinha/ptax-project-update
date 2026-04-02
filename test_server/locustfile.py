"""
Load test for the PTAX render pipeline.

Two user classes:

  PtaxUser      — load test: random PINs, N concurrent users, think time between tasks.
  PtaxSmokeUser — smoke test: single fixed PIN, 1 user, no wait time, stops after 1 render.

Usage:
    # Web UI (load test, all classes selectable):
    locust -f test_server/locustfile.py --host http://localhost:8000 --class-picker

    # Headless load test — 10 users, ramp 2/sec, 5 min, save CSV:
    locust -f test_server/locustfile.py --host http://localhost:8000 \
        --users 10 --spawn-rate 2 --run-time 5m --headless \
        --csv test_server/results/run PtaxUser

    # Smoke test — 1 user, verify server responds correctly for a single render:
    locust -f test_server/locustfile.py --host http://localhost:8000 \
        --users 1 --spawn-rate 1 --run-time 5m --headless \
        PtaxSmokeUser

    # To clear cached renders before a timing run (forces real renders):
    rm -rf outputs/v2.1.2/PTAX/
"""

import random
import time
from pathlib import Path

from locust import HttpUser, between, constant, events, task

# Load PINs once at import time
_pins_file = Path(__file__).parent / "test_pins.txt"
TEST_PINS = [line.strip() for line in _pins_file.read_text().splitlines() if line.strip()]

# Fixed PIN used by the smoke test — well-known, should always be in the DB
SMOKE_PIN = "20114040030000"

POLL_INTERVAL = 5    # seconds between /check_complete polls
RENDER_TIMEOUT = 300  # seconds before giving up on a single render


def _render_pin(user: HttpUser, pin: str):
    """
    Submit a PIN, poll until the render completes, fetch the output HTML.

    Records a synthetic 'GET /render [total]' event covering the full
    wall-clock time from first POST to final HTML fetch.

    Returns the HTML string on success, None on failure.
    """
    t_start = time.time()

    # --- Submit ---
    with user.client.post(
        "/submit",
        data={
            "search_category": "last_assessment_year",
            "search_term": pin,
            "search_term_hidden": pin,
            "mode": "PTAX",
        },
        allow_redirects=True,
        catch_response=True,
        name="POST /submit",
    ) as resp:
        if resp.status_code != 200:
            resp.failure(f"submit failed with status {resp.status_code}")
            return None

        url = resp.url or ""

        # Already cached — /submit redirected straight to the HTML
        if "/outputs/" in url and url.endswith(".html"):
            resp.success()
            output_url = url
        else:
            resp.success()
            output_url = None

    # --- Poll until render finishes (skipped if already cached) ---
    if output_url is None:
        deadline = time.time() + RENDER_TIMEOUT
        while time.time() < deadline:
            with user.client.get(
                "/check_complete",
                params={"pin": pin, "mode": "PTAX", "n": 1},
                allow_redirects=True,
                catch_response=True,
                name="GET /check_complete",
            ) as r:
                url = r.url or ""
                if "/outputs/" in url and url.endswith(".html"):
                    r.success()
                    output_url = url
                    break
                if r.status_code >= 500:
                    r.failure(f"render failed for PIN {pin}: status {r.status_code}")
                    _fire_total(user, pin, t_start, None)
                    return None
                r.success()

            time.sleep(POLL_INTERVAL)
        else:
            # Timed out
            user.environment.events.request.fire(
                request_type="GET",
                name="GET /check_complete",
                response_time=RENDER_TIMEOUT * 1000,
                response_length=0,
                exception=TimeoutError(f"PIN {pin} did not render within {RENDER_TIMEOUT}s"),
                context={},
            )
            _fire_total(user, pin, t_start, None)
            return None

    # --- Fetch the finished output HTML ---
    with user.client.get(
        output_url,
        catch_response=True,
        name="GET /outputs [html]",
    ) as r:
        if r.status_code != 200:
            r.failure(f"output fetch failed: {r.status_code}")
            _fire_total(user, pin, t_start, None)
            return None
        r.success()
        html = r.text

    _fire_total(user, pin, t_start, html)
    return html


def _fire_total(user: HttpUser, pin: str, t_start: float, html: str | None):
    """Fire a synthetic event recording total wall-clock render time."""
    elapsed_ms = (time.time() - t_start) * 1000
    user.environment.events.request.fire(
        request_type="RENDER",
        name="RENDER [total]",
        response_time=elapsed_ms,
        response_length=len(html) if html else 0,
        exception=None if html else Exception(f"PIN {pin} failed"),
        context={},
    )


class PtaxUser(HttpUser):
    """Load test: each user picks a random PIN and renders it, with think time in between."""
    wait_time = between(5, 15)

    @task
    def render_pin(self):
        _render_pin(self, random.choice(TEST_PINS))


class PtaxSmokeUser(HttpUser):
    """Smoke test: 1 user, no wait, renders a single known-good PIN and stops."""
    wait_time = constant(0)

    @task
    def smoke_render(self):
        html = _render_pin(self, SMOKE_PIN)
        if html:
            size_kb = len(html) / 1024
            print(f"\n[smoke] PIN {SMOKE_PIN} rendered successfully ({size_kb:.1f} KB).")
        else:
            print(f"\n[smoke] PIN {SMOKE_PIN} FAILED.")
        self.environment.runner.quit()
