#!/usr/bin/env python3
"""Proof that the Taskfile's origin checks can fail, run through `task` itself.

scripts/test_check_origin_serves.py proves the probe script. This proves the glue around it, which
is where a later edit can quietly turn a failing check into a passing one while the probe's own
tests stay green: a discarded exit code, a dropped `fail=1`, a reordered URL resolution.

Every case runs the real task (`task verify:deploy`, `task deploy:accept-origin`,
`task deploy:check-origin-config`) against throwaway servers on 127.0.0.1 playing a Prudent, and a
stub `gcloud` that answers from environment variables, so nothing here touches a cloud. The failing
cases must fail. go-task wraps a failing script's exit code, so they assert "non-zero", not a number.

Run by `task test:deploy-origin`, which CI runs. Written to Python 3.9 like the other scripts.
"""

from __future__ import annotations

import os
import shutil
import socket
import stat
import subprocess
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HEALTH = b'{"status":"ok","service":"prudent-server","timestampMs":"1"}'

# What `gcloud` is made to say. Each is read from the environment of the task under test. There is
# deliberately no `secrets` case: the origin checks no longer read a secret (#166), so a call to one
# reaches the catch-all and fails the task, which is how these tests would notice it coming back.
GCLOUD_STUB = """#!/bin/sh
case "$1 $2" in
  "auth print-access-token") echo token ;;
  "projects describe")
    [ -z "${STUB_FAIL_DESCRIBE:-}" ] || { echo "stub: describe failed" >&2; exit 1; }
    echo "${STUB_PROJECT_NUMBER:-}" ;;
  "scheduler jobs")
    [ -z "${STUB_NO_SCHEDULER:-}" ] || exit 1 ;;
  "run services")
    [ -z "${STUB_FAIL_RUN:-}" ] || { echo "stub: run describe failed" >&2; exit 1; }
    case "$*" in
      *--flatten*) printf '%s\n' "${STUB_SERVICE_ENV:-}" ;;  # the NAME,VALUE lines of the env
      *) echo "${STUB_STATUS_URL:-}" ;;
    esac ;;
  *) echo "stub gcloud: unexpected call: $*" >&2; exit 99 ;;
esac
"""


PUBLIC = ("SUPABASE_URL", "SITE_URL", "CORS_ORIGINS", "AUTH_REDIRECT_URI", "AUTH_REDIRECT_URIS",
          "SMTP_HOST", "SMTP_PORT", "SMTP_FROM")
MAIL_SECRETS = ("SMTP_USERNAME", "SMTP_PASSWORD")


def service_env(site_url, secret=(), absent=(), plain=(), missing_secret=()):
    """What `gcloud run services describe --flatten=...env[] --format=csv` prints for the service.

    One `NAME,VALUE,SECRET` line each. A variable that is a Secret Manager reference has no value
    of its own and names its secret in the third field (`NAME,,SECRET`); a plain one has a value and
    an empty third field. One in `absent` is not there at all; one in `plain` is a mail secret held
    as a literal (the wrong way round), and one in `missing_secret` is not bound."""
    values = {
        "SUPABASE_URL": "https://ref.supabase.co",
        "SITE_URL": site_url,
        "CORS_ORIGINS": site_url,
        "AUTH_REDIRECT_URI": site_url + "/auth/callback",
        "AUTH_REDIRECT_URIS": '"prudent://auth-callback,other://x"',  # csv quotes a comma
        "SMTP_HOST": "smtp.example.org",
        "SMTP_PORT": "587",
        "SMTP_FROM": "noreply@prudent.example.org",
    }
    lines = ["ZEN_I18N_SUPPORTED," + '"en,uk,pl",', "SUPABASE_KEY,,SUPABASE_KEY"]
    for name in PUBLIC:
        if name in absent:
            continue
        lines.append(name + (",," + name if name in secret else "," + values[name] + ","))
    for name in MAIL_SECRETS:
        if name in missing_secret:
            continue
        lines.append(name + ("," + "literal-value," if name in plain else ",," + name))
    return "\n".join(lines)


class Prudent(BaseHTTPRequestHandler):
    """The endpoints verify:deploy asserts, answering as a healthy Prudent."""

    def _answer(self, status, body=b""):
        self.send_response(status)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):  # noqa: N802 - http.server's naming
        routes = {
            "/api/v1/health": (200, HEALTH),
            "/api/v1/records": (401, b""),
            "/": (200, b"<html></html>"),
            "/main.dart.wasm": (200, b"\0asm"),
            "/admin/": (200, b"<html></html>"),
        }
        status, body = routes.get(self.path, (404, b""))
        self._answer(status, body)

    def do_POST(self):  # noqa: N802
        length = int(self.headers.get("Content-Length") or 0)
        self.rfile.read(length)
        self._answer(204 if self.path == "/api/v1/auth/restore-password" else 404)

    def log_message(self, *args):
        pass


class Elsewhere(Prudent):
    """A host that answers 200 as something that is not Prudent."""

    def do_GET(self):  # noqa: N802
        self._answer(200, b"hi")


class Server:
    def __init__(self, handler):
        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), handler)
        self.origin = f"http://127.0.0.1:{self.httpd.server_address[1]}"

    def __enter__(self):
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()
        return self

    def __exit__(self, *exc):
        self.httpd.shutdown()
        self.httpd.server_close()


def dead_origin():
    """An origin with nothing listening on it."""
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return f"http://127.0.0.1:{port}"


class TaskCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.task = shutil.which("task")
        cls.stubs = tempfile.mkdtemp(prefix="stub-gcloud-")
        stub = Path(cls.stubs) / "gcloud"
        stub.write_text(GCLOUD_STUB)
        stub.chmod(stub.stat().st_mode | stat.S_IXUSR)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.stubs, ignore_errors=True)

    def setUp(self):
        # Missing go-task must FAIL, not skip: a gate that skips itself is decoration.
        self.assertIsNotNone(self.task, "go-task ('task') is required to run these tests")

    def run_task(self, name, **env):
        base = {
            "PATH": self.stubs + os.pathsep + os.environ.get("PATH", ""),
            "HOME": os.environ.get("HOME", ""),
            # Failing probes must not wait out the retry schedule.
            "ORIGIN_ATTEMPTS": "1",
            "ORIGIN_RETRY_SECONDS": "0",
        }
        base.update({k: v for k, v in env.items() if v is not None})
        p = subprocess.run([self.task, name], cwd=ROOT, env=base, capture_output=True, text=True,
                           timeout=180)
        return p.returncode, p.stdout + p.stderr


class VerifyDeployOrigin(TaskCase):
    def test_web_api_url_alone_is_verified(self):
        with Server(Prudent) as s:
            rc, out = self.run_task("verify:deploy", WEB_API_URL=s.origin)
        self.assertEqual(rc, 0, out)
        self.assertIn("health names prudent-server", out)

    def test_with_nothing_to_go_on_it_stops(self):
        rc, out = self.run_task("verify:deploy")
        self.assertNotEqual(rc, 0, out)
        self.assertIn("Set SERVICE_URL, or WEB_API_URL", out)

    def test_service_url_alone_says_the_bundle_origin_is_unchecked(self):
        with Server(Prudent) as s:
            rc, out = self.run_task("verify:deploy", SERVICE_URL=s.origin)
        self.assertEqual(rc, 0, out)
        self.assertIn("SKIP  bundle origin", out)

    def test_a_good_alias_cannot_hide_a_bundle_origin_that_never_serves(self):
        with Server(Prudent) as s:
            rc, out = self.run_task("verify:deploy", SERVICE_URL=s.origin, WEB_API_URL=dead_origin())
        self.assertNotEqual(rc, 0, out)
        self.assertIn("does not answer as Prudent", out)

    def test_a_good_alias_cannot_hide_a_bundle_origin_that_is_something_else(self):
        with Server(Prudent) as s, Server(Elsewhere) as other:
            rc, out = self.run_task("verify:deploy", SERVICE_URL=s.origin, WEB_API_URL=other.origin)
        self.assertNotEqual(rc, 0, out)
        self.assertIn("something else answers there", out)

    def test_the_same_origin_is_checked_once_not_probed_twice(self):
        with Server(Prudent) as s:
            rc, out = self.run_task("verify:deploy", SERVICE_URL=s.origin + "/", WEB_API_URL=s.origin)
        self.assertEqual(rc, 0, out)
        self.assertNotIn("answers as prudent-server", out)  # the separate probe's line
        self.assertIn("health names prudent-server", out)

    def test_a_host_that_is_not_prudent_fails_the_health_body_check(self):
        with Server(Elsewhere) as s:
            rc, out = self.run_task("verify:deploy", SERVICE_URL=s.origin, WEB_API_URL=s.origin)
        self.assertNotEqual(rc, 0, out)
        self.assertIn("FAIL  health names prudent-server", out)

    SERVICE = dict(GCP_PROJECT="p", GCP_REGION="r", SERVICE_NAME="svc")

    def test_the_bundle_origin_is_read_from_the_running_service_when_it_is_named(self):
        with Server(Prudent) as s:
            rc, out = self.run_task("verify:deploy", STUB_SERVICE_ENV=service_env(s.origin), **self.SERVICE)
        self.assertEqual(rc, 0, out)
        self.assertIn("taken from the running service's SITE_URL", out)
        self.assertIn("ok    SITE_URL of the running service is the bundle origin", out)

    def test_only_a_project_cannot_say_which_service_to_read(self):
        rc, out = self.run_task("verify:deploy", GCP_PROJECT="p")
        self.assertNotEqual(rc, 0, out)
        self.assertIn("GCP_REGION and SERVICE_NAME are needed", out)

    def test_an_unreadable_service_stops_rather_than_guessing_the_origin(self):
        rc, out = self.run_task("verify:deploy", STUB_FAIL_RUN="1", **self.SERVICE)
        self.assertNotEqual(rc, 0, out)
        self.assertIn("Could not read the configuration of svc", out)

    def test_a_site_url_that_is_still_a_secret_reference_stops_and_names_the_rebind(self):
        with Server(Prudent) as s:
            rc, out = self.run_task("verify:deploy", STUB_SERVICE_ENV=service_env(s.origin, secret=("SITE_URL",)),
                                    **self.SERVICE)
        self.assertNotEqual(rc, 0, out)
        self.assertIn("no plain value", out)
        self.assertIn("persistent-environment.md", out)

    def test_a_service_without_a_site_url_stops(self):
        with Server(Prudent) as s:
            rc, out = self.run_task("verify:deploy", STUB_SERVICE_ENV=service_env(s.origin, absent=("SITE_URL",)),
                                    **self.SERVICE)
        self.assertNotEqual(rc, 0, out)
        self.assertIn("no plain value", out)


class PublicConfigOnTheService(TaskCase):
    """verify:deploy asserts the public values of the RUNNING service are plain values and the mail
    relay's login is bound as secrets."""

    SERVICE = dict(GCP_PROJECT="p", GCP_REGION="r", SERVICE_NAME="svc")

    def run_verify(self, origin, **kw):
        return self.run_task("verify:deploy", WEB_API_URL=origin, SERVICE_URL=origin, **self.SERVICE, **kw)

    def test_the_plain_values_pass(self):
        with Server(Prudent) as s:
            rc, out = self.run_verify(s.origin, STUB_SERVICE_ENV=service_env(s.origin))
        self.assertEqual(rc, 0, out)
        for name in PUBLIC:
            self.assertIn(f"ok    {name} is a plain value", out)

    def test_each_value_that_is_still_a_secret_reference_fails_by_name(self):
        for name in PUBLIC:
            with self.subTest(name=name), Server(Prudent) as s:
                rc, out = self.run_verify(s.origin, STUB_SERVICE_ENV=service_env(s.origin, secret=(name,)))
                self.assertNotEqual(rc, 0, out)
                self.assertIn(f"FAIL  {name} is absent or still a Secret Manager reference", out)

    def test_the_relay_login_is_checked_as_secret_references(self):
        with Server(Prudent) as s:
            rc, out = self.run_verify(s.origin, STUB_SERVICE_ENV=service_env(s.origin))
        self.assertEqual(rc, 0, out)
        for name in MAIL_SECRETS:
            self.assertIn(f"ok    {name} is a Secret Manager reference", out)

    def test_a_relay_login_that_is_not_bound_fails_by_name(self):
        # Without it the service cannot send a dormancy warning, and no dormant account is erased.
        for name in MAIL_SECRETS:
            with self.subTest(name=name), Server(Prudent) as s:
                rc, out = self.run_verify(s.origin, STUB_SERVICE_ENV=service_env(s.origin, missing_secret=(name,)))
                self.assertNotEqual(rc, 0, out)
                self.assertIn(f"FAIL  {name} is absent or a plain value", out)

    def test_a_relay_login_held_as_a_plain_value_fails_by_name(self):
        for name in MAIL_SECRETS:
            with self.subTest(name=name), Server(Prudent) as s:
                rc, out = self.run_verify(s.origin, STUB_SERVICE_ENV=service_env(s.origin, plain=(name,)))
                self.assertNotEqual(rc, 0, out)
                self.assertIn(f"FAIL  {name} is absent or a plain value", out)

    def test_a_value_that_is_absent_fails(self):
        with Server(Prudent) as s:
            rc, out = self.run_verify(s.origin, STUB_SERVICE_ENV=service_env(s.origin, absent=("CORS_ORIGINS",)))
        self.assertNotEqual(rc, 0, out)
        self.assertIn("FAIL  CORS_ORIGINS is absent", out)

    def test_a_service_built_for_another_origin_fails_even_though_it_answers(self):
        with Server(Prudent) as s:
            rc, out = self.run_verify(s.origin, STUB_SERVICE_ENV=service_env("https://elsewhere.example.org"))
        self.assertNotEqual(rc, 0, out)
        self.assertIn("FAIL  SITE_URL of the running service is the bundle origin", out)

    def test_an_unreadable_service_fails_when_the_origin_was_given(self):
        with Server(Prudent) as s:
            rc, out = self.run_verify(s.origin, STUB_FAIL_RUN="1")
        self.assertNotEqual(rc, 0, out)
        self.assertIn("could not read the configuration of svc", out)

    def test_without_a_service_name_it_is_announced_as_skipped_never_silent(self):
        with Server(Prudent) as s:
            rc, out = self.run_task("verify:deploy", WEB_API_URL=s.origin, GCP_PROJECT="p", GCP_REGION="r")
        self.assertEqual(rc, 0, out)
        self.assertIn("SKIP  public configuration", out)


class AcceptOrigin(TaskCase):
    def test_a_serving_origin_is_named_and_the_alias_is_shown_as_one(self):
        with Server(Prudent) as s:
            rc, out = self.run_task(
                "deploy:accept-origin", WEB_API_URL=s.origin, GCP_PROJECT="p", GCP_REGION="r",
                SERVICE_NAME="svc", STUB_STATUS_URL="https://svc-abc-ew.a.run.app")
        self.assertEqual(rc, 0, out)
        self.assertIn("OPEN THAT ONE", out)
        self.assertIn("https://svc-abc-ew.a.run.app", out)
        self.assertIn(f"SERVICE_URL={s.origin} task verify:deploy", out)

    def test_an_unreadable_status_url_is_said_and_does_not_fail_a_deploy_that_passed(self):
        with Server(Prudent) as s:
            rc, out = self.run_task(
                "deploy:accept-origin", WEB_API_URL=s.origin, GCP_PROJECT="p", GCP_REGION="r",
                SERVICE_NAME="svc", STUB_FAIL_RUN="1")
        self.assertEqual(rc, 0, out)
        self.assertIn("status.url could not be read", out)

    def test_an_origin_that_never_serves_fails_the_deploy_and_names_both_ways_forward(self):
        rc, out = self.run_task("deploy:accept-origin", WEB_API_URL=dead_origin())
        self.assertNotEqual(rc, 0, out)
        self.assertIn("DEPLOY NOT ACCEPTED", out)
        self.assertIn("task verify:deploy", out)  # the cheap re-probe, before a rebuild
        self.assertIn("rebuild", out)

    def test_an_origin_that_is_something_else_fails_the_deploy(self):
        with Server(Elsewhere) as s:
            rc, out = self.run_task("deploy:accept-origin", WEB_API_URL=s.origin)
        self.assertNotEqual(rc, 0, out)
        self.assertIn("DEPLOY NOT ACCEPTED", out)

    def test_without_web_api_url_it_refuses_to_pass(self):
        rc, out = self.run_task("deploy:accept-origin")
        self.assertNotEqual(rc, 0, out)
        self.assertIn("WEB_API_URL is required", out)


class CheckOriginConfig(TaskCase):
    HOST = "https://svc-123.europe-west1.run.app"
    COMMON = dict(GCP_PROJECT="p", GCP_REGION="europe-west1", SERVICE_NAME="svc",
                  STUB_PROJECT_NUMBER="123")

    def test_the_deterministic_host_passes(self):
        rc, out = self.run_task("deploy:check-origin-config", WEB_API_URL=self.HOST, **self.COMMON)
        self.assertEqual(rc, 0, out)
        self.assertIn("deterministic Cloud Run host", out)

    def test_it_reads_no_secret(self):
        # The stub has no `secrets` case: a call to one exits 99 and fails the task. Passing here is
        # what proves SITE_URL is no longer read from Secret Manager (#166).
        rc, out = self.run_task("deploy:check-origin-config", WEB_API_URL=self.HOST + "/", **self.COMMON)
        self.assertEqual(rc, 0, out)
        self.assertNotIn("unexpected call", out)

    def test_any_other_host_fails_before_the_build_and_says_which_one_is_right(self):
        wrong = "https://svc-999.europe-west1.run.app"
        rc, out = self.run_task("deploy:check-origin-config", WEB_API_URL=wrong, **self.COMMON)
        self.assertNotEqual(rc, 0, out)
        self.assertIn(f"Cloud Run serves this service on {self.HOST}", out)

    def test_another_origin_needs_an_explicit_override(self):
        other = "https://prudent.example.org"
        rc, out = self.run_task("deploy:check-origin-config", WEB_API_URL=other,
                                WEB_API_URL_ALLOW_OTHER="1", **self.COMMON)
        self.assertEqual(rc, 0, out)
        self.assertIn("NOTE  WEB_API_URL is not the deterministic Cloud Run host", out)

    def test_an_unreadable_project_number_fails(self):
        rc, out = self.run_task("deploy:check-origin-config", WEB_API_URL=self.HOST,
                                STUB_FAIL_DESCRIBE="1", **self.COMMON)
        self.assertNotEqual(rc, 0, out)
        self.assertIn("Could not read the project number", out)

    def test_a_missing_variable_is_named(self):
        rc, out = self.run_task("deploy:check-origin-config", WEB_API_URL=self.HOST)
        self.assertNotEqual(rc, 0, out)
        self.assertIn("MISSING: GCP_PROJECT", out)


if __name__ == "__main__":
    unittest.main()
