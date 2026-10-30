#!/usr/bin/env python3
"""Proves scripts/hosted_mail_templates.py can fail. Run by `task verify:mail-templates:hosted` first.

Against a stub of the Management API's `config/auth` endpoint on a local port, never the real one:
the stub keeps whatever it is PATCHed (or, in one test, quietly does not), so each verdict the
script gives is checked against a project that is in sync, one that differs, one that lost the
write, and one that refuses the token.
"""
import json
import os
import subprocess
import sys
import threading
import unittest
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SCRIPT = REPO / "scripts" / "hosted_mail_templates.py"
sys.path.insert(0, str(REPO / "scripts"))
from hosted_mail_templates import wanted  # noqa: E402

REF = "testprojectref"


class Project:
    """A stub hosted project: `state` is its auth config; `keeps` says whether a PATCH sticks."""

    def __init__(self, state, keeps=True, status=200):
        self.state, self.keeps, self.status, self.requests = dict(state), keeps, status, []
        project = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def reply(self, payload):
                body = json.dumps(payload).encode()
                self.send_response(project.status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def do_GET(self):
                project.requests.append(("GET", self.path, self.headers.get("Authorization")))
                self.reply(project.state)

            def do_PATCH(self):
                project.requests.append(("PATCH", self.path, self.headers.get("Authorization")))
                body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                if project.keeps:
                    project.state.update(body)
                self.reply(project.state)

        self.server = HTTPServer(("127.0.0.1", 0), Handler)
        self.url = f"http://127.0.0.1:{self.server.server_port}"

    def __enter__(self):
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        return self

    def __exit__(self, *exc):
        self.server.shutdown()
        self.server.server_close()


def run(mode, project=None, env=None):
    environment = {"PATH": os.environ["PATH"]}
    if project:
        environment["SUPABASE_API_URL"] = project.url
    environment.update(env if env is not None else {"SUPABASE_ACCESS_TOKEN": "tok", "SUPABASE_PROJECT_REF": REF})
    return subprocess.run([sys.executable, "-I", str(SCRIPT), mode], capture_output=True, text=True, env=environment)


class Hosted(unittest.TestCase):
    def setUp(self):
        self.want = wanted(REPO)

    def test_in_sync_passes_and_changes_nothing(self):
        with Project(self.want) as p:
            r = run("check", p)
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            self.assertEqual([m for m, *_ in p.requests], ["GET"])
            self.assertEqual(p.requests[0][1], f"/v1/projects/{REF}/config/auth")
            self.assertEqual(p.requests[0][2], "Bearer tok")

    def test_a_different_body_fails_and_names_the_field(self):
        state = dict(self.want, mailer_templates_recovery_content="<p>Supabase default</p>")
        with Project(state) as p:
            r = run("check", p)
            self.assertEqual(r.returncode, 1, r.stdout)
            self.assertIn("mailer_templates_recovery_content", r.stdout)
            self.assertNotIn("mailer_templates_confirmation_content", r.stdout)
            self.assertEqual([m for m, *_ in p.requests], ["GET"], "check must not write")

    def test_a_different_subject_fails(self):
        with Project(dict(self.want, mailer_subjects_confirmation="Confirm Your Signup")) as p:
            r = run("check", p)
            self.assertEqual(r.returncode, 1)
            self.assertIn("mailer_subjects_confirmation", r.stdout)

    def test_a_field_the_api_did_not_return_fails(self):
        state = {k: v for k, v in self.want.items() if k != "mailer_subjects_recovery"}
        with Project(state) as p:
            r = run("check", p)
            self.assertEqual(r.returncode, 1)
            self.assertIn("mailer_subjects_recovery", r.stdout)

    def test_a_trailing_newline_is_not_a_difference(self):
        state = {k: v + "\n" for k, v in self.want.items()}
        with Project(state) as p:
            self.assertEqual(run("check", p).returncode, 0)

    def test_apply_writes_then_reads_back(self):
        with Project({"mailer_templates_recovery_content": "old"}) as p:
            r = run("apply", p)
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            self.assertEqual([m for m, *_ in p.requests], ["PATCH", "GET"])
            self.assertEqual(p.state["mailer_subjects_confirmation"], self.want["mailer_subjects_confirmation"])

    def test_apply_that_the_api_did_not_keep_fails(self):
        with Project({}, keeps=False) as p:
            r = run("apply", p)
            self.assertEqual(r.returncode, 1, r.stdout)
            self.assertIn("mailer_templates_confirmation_content", r.stdout)

    def test_a_refused_token_fails_without_echoing_the_response(self):
        with Project({"secret": "do-not-print"}, status=401) as p:
            r = run("check", p)
            self.assertEqual(r.returncode, 1)
            self.assertIn("401", r.stdout + r.stderr)
            self.assertNotIn("do-not-print", r.stdout + r.stderr)

    def test_missing_token_is_not_a_skip(self):
        r = run("check", env={"SUPABASE_PROJECT_REF": REF})
        self.assertEqual(r.returncode, 2)
        self.assertIn("SUPABASE_ACCESS_TOKEN", r.stdout)

    def test_missing_reference_is_not_a_skip(self):
        r = run("check", env={"SUPABASE_ACCESS_TOKEN": "tok"})
        self.assertEqual(r.returncode, 2)
        self.assertIn("SUPABASE_PROJECT_REF", r.stdout)

    def test_unknown_mode_fails(self):
        self.assertEqual(run("delete").returncode, 2)


if __name__ == "__main__":
    unittest.main()
