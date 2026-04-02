"""
Load test for the PTAX render pipeline.

Two user classes:

  PtaxUser      — load test: random PINs, N concurrent users, think time between tasks.
  PtaxSmokeUser — smoke test: single fixed PIN, 1 user, no wait time, stops after 1 render.

Usage:
    # Web UI (load test, choose class interactively):
    locust -f test_server/locustfile.py --host http://localhost:8000

    # Headless load test — 10 users, ramp 2/sec, 5 min, save CSV:
    locust -f test_server/locustfile.py --host http://localhost:8000 \
        --users 10 --spawn-rate 2 --run-time 5m --headless \
        --csv test_server/results/run

    # Smoke test — 1 user, verify server responds correctly for a single render:
    locust -f test_server/locustfile.py --host http://localhost:8000 \
        --users 1 --spawn-rate 1 --run-time 5m --headless \
        --class-picker PtaxSmokeUser

    # To clear cached renders before a timing run (forces real renders):
    rm -rf outputs/v2.1.2/PTAX/
"""

import random
import time
from pathlib import Path

from locust import HttpUser, between, constant, task

# Load PINs once at import time
_pins_file = Path(__file__).parent / "test_pins.txt"
TEST_PINS = [line.strip() for line in _pins_file.read_text().splitlines() if line.strip()]

# Fixed PIN used by the smoke test — well-known, should always be in the DB
SMOKE_PIN = "20114040030000"

POLL_INTERVAL = 5    # seconds between /check_complete polls
RENDER_TIMEOUT = 300  # seconds before giving up on a single render


def _render_pin(user: HttpUser, pin: str):
    """Submit a PIN and poll until the render completes. Used by both user classes."""
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
            return False

        # Already cached — served immediately
        if "/outputs/" in resp.url and resp.url.endswith(".html"):
            resp.success()
            return True

        resp.success()

    # Poll /check_complete until the render finishes
    deadline = time.time() + RENDER_TIMEOUT
    while time.time() < deadline:
        with user.client.get(
            "/check_complete",
            params={"pin": pin, "mode": "PTAX", "n": 1},
            allow_redirects=True,
            catch_response=True,
            name="GET /check_complete",
        ) as r:
            if "/outputs/" in r.url and r.url.endswith(".html"):
                r.success()
                return True
            if r.status_code >= 500:
                r.failure(f"render failed for PIN {pin}: status {r.status_code}")
                return False
            r.success()

        time.sleep(POLL_INTERVAL)

    # Timed out
    user.environment.events.request.fire(
        request_type="GET",
        name="GET /check_complete",
        response_time=RENDER_TIMEOUT * 1000,
        response_length=0,
        exception=TimeoutError(f"PIN {pin} did not render within {RENDER_TIMEOUT}s"),
        context={},
    )
    return False


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
        success = _render_pin(self, SMOKE_PIN)
        if success:
            print(f"\n[smoke] PIN {SMOKE_PIN} rendered successfully.")
        else:
            print(f"\n[smoke] PIN {SMOKE_PIN} FAILED.")
        self.environment.runner.quit()
