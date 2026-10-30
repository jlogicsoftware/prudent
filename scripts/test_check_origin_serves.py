#!/usr/bin/env python3
"""Proof that scripts/check_origin_serves.sh can fail, and that it passes only for Prudent.

A deploy check that has only ever been seen green is decoration. Each case starts a throwaway HTTP
server on 127.0.0.1 that plays one kind of host and runs the real script against it:

  * a host that answers as prudent-server            -> exit 0
  * a trailing slash on the origin                   -> exit 0 (normalised)
  * a host that answers 200 as something else        -> exit 1 (a stale host after a teardown)
  * a host that answers 404 / 500                    -> exit 1
  * a host that never answers (nothing listening)    -> exit 1
  * a host that is cold for two tries, then serves   -> exit 0 (retry is real)
  * a host that redirects elsewhere                  -> exit 1 (redirects are not followed)
  * a malformed origin / no argument                 -> exit 1

Run by `task test:deploy-origin`, which CI runs. Written to Python 3.9 like the other scripts.
"""

from __future__ import annotations

import socket
import subprocess
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "check_origin_serves.sh"
HEALTH = b'{"status":"ok","service":"prudent-server","timestampMs":"1"}'


def make_handler(behaviour):
    class Handler(BaseHTTPRequestHandler):
        hits = 0
        # What the probe asked for. Recorded here, not handed to `behaviour`, so nothing the client
        # sent can reach the response a behaviour builds.
        transports = []

        def do_GET(self):  # noqa: N802 - http.server's naming
            type(self).hits += 1
            type(self).transports.append(self.headers.get("X-Zen-Transport"))
            if self.path != "/api/v1/health":
                self.send_response(404)
                self.end_headers()
                return
            status, headers, body = behaviour(type(self).hits)
            self.send_response(status)
            for k, v in headers.items():
                self.send_header(k, v)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):  # keep test output quiet
            pass

    return Handler


class Host:
    """A throwaway server for the length of a `with` block; `.origin` is its base URL."""

    def __init__(self, behaviour):
        self.handler = make_handler(behaviour)
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), self.handler)
        self.origin = f"http://127.0.0.1:{self.server.server_address[1]}"

    def __enter__(self):
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        return self

    def __exit__(self, *exc):
        self.server.shutdown()
        self.server.server_close()


def run(origin, attempts="2"):
    args = ["sh", str(SCRIPT)] + ([origin] if origin is not None else [])
    env = {"PATH": "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin", "ORIGIN_ATTEMPTS": attempts,
           "ORIGIN_RETRY_SECONDS": "0"}
    p = subprocess.run(args, env=env, capture_output=True, text=True, timeout=120)
    return p.returncode, p.stdout + p.stderr


def serving(_hits):
    return 200, {"Content-Type": "application/json"}, HEALTH


class CheckOriginServes(unittest.TestCase):
    def test_a_host_that_answers_as_prudent_passes(self):
        with Host(serving) as h:
            rc, out = run(h.origin)
        self.assertEqual(rc, 0, out)
        self.assertIn("answers as prudent-server", out)

    def test_the_probe_asks_for_the_json_transport(self):
        with Host(serving) as h:
            rc, out = run(h.origin)
            seen = h.handler.transports
        self.assertEqual(rc, 0, out)
        self.assertEqual(seen, ["json"])

    def test_a_trailing_slash_is_normalised(self):
        with Host(serving) as h:
            rc, out = run(h.origin + "/")
        self.assertEqual(rc, 0, out)

    def test_a_200_from_something_else_fails(self):
        with Host(lambda *_: (200, {}, b"<html>placeholder</html>")) as h:
            rc, out = run(h.origin)
        self.assertEqual(rc, 1, out)
        self.assertIn("something else answers there", out)

    def test_a_404_fails(self):
        with Host(lambda *_: (404, {}, b"nope")) as h:
            rc, out = run(h.origin)
        self.assertEqual(rc, 1, out)
        self.assertIn("HTTP 404", out)

    def test_a_500_fails(self):
        with Host(lambda *_: (500, {}, b"boom")) as h:
            rc, out = run(h.origin)
        self.assertEqual(rc, 1, out)
        self.assertIn("HTTP 500", out)

    def test_a_host_that_never_serves_fails(self):
        # Bind then close, so the port is known to have nothing listening on it.
        s = socket.socket()
        s.bind(("127.0.0.1", 0))
        port = s.getsockname()[1]
        s.close()
        rc, out = run(f"http://127.0.0.1:{port}")
        self.assertEqual(rc, 1, out)
        self.assertIn("no HTTP answer", out)

    def test_a_cold_host_is_retried(self):
        with Host(lambda hits: (503, {}, b"cold") if hits < 3 else serving(hits)) as h:
            rc, out = run(h.origin, attempts="4")
        self.assertEqual(rc, 0, out)

    def test_a_host_that_stays_cold_fails_after_the_attempts(self):
        with Host(lambda *_: (503, {}, b"cold")) as h:
            rc, out = run(h.origin, attempts="3")
            hits = h.handler.hits
        self.assertEqual(rc, 1, out)
        self.assertEqual(hits, 3)

    def test_a_redirect_is_not_followed(self):
        with Host(serving) as target:
            with Host(lambda *_: (302, {"Location": target.origin + "/api/v1/health"}, b"")) as h:
                rc, out = run(h.origin)
        self.assertEqual(rc, 1, out)
        self.assertIn("HTTP 302", out)

    def test_a_malformed_origin_fails(self):
        rc, out = run("example.com")
        self.assertEqual(rc, 1, out)
        self.assertIn("must start with http", out)

    def test_no_argument_fails(self):
        rc, out = run(None)
        self.assertEqual(rc, 1, out)
        self.assertIn("usage", out)


if __name__ == "__main__":
    unittest.main()
