#!/usr/bin/env python3
"""Proof that the committed deploy configuration of the persistent environment can only carry
public values and identifiers (ADR-131), and that its loader behaves.

  * scripts/with_env_file.sh: loads KEY=value lines, lets the caller's shell win, takes values
    literally, and refuses by line number a malformed line, an invalid name, a secret-looking name
    and an `sb_secret_` value, before it runs anything.
  * deploy/persistent.env itself: it passes the same refusals, names every variable
    `deploy:cloudrun` requires, and holds no secret shape.

Run by `task test:public-config`, which CI runs. Written to Python 3.9 like the other scripts.
"""

from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from typing import Dict, Optional, Tuple

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "with_env_file.sh"
COMMITTED = ROOT / "deploy" / "persistent.env"
REQUIRED = (
    "GCP_PROJECT", "GCP_REGION", "SERVICE_NAME", "ARTIFACT_REPO", "RUNTIME_SERVICE_ACCOUNT",
    "WEB_API_URL", "SUPABASE_URL", "SUPABASE_KEY", "AUTH_REDIRECT_URIS", "SMTP_HOST", "SMTP_FROM",
)


def run(text: str, env: Optional[Dict[str, str]] = None, show: str = "FOO") -> Tuple[int, str, str]:
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "x.env"
        path.write_text(text)
        base = {"PATH": os.environ["PATH"]}
        base.update(env or {})
        done = subprocess.run(
            ["sh", str(SCRIPT), str(path), "sh", "-c", 'printf "%s" "${' + show + '-UNSET}"'],
            env=base, capture_output=True, text=True,
        )
        return done.returncode, done.stdout, done.stderr


class Loader(unittest.TestCase):
    def test_loads_a_value_and_skips_comments_and_blank_lines(self):
        code, out, _ = run("# note\n\nFOO=bar\n")
        self.assertEqual((code, out), (0, "bar"))

    def test_the_callers_shell_wins(self):
        code, out, _ = run("FOO=from-file\n", env={"FOO": "from-shell"})
        self.assertEqual((code, out), (0, "from-shell"))

    def test_an_empty_value_set_in_the_shell_still_wins(self):
        code, out, _ = run("FOO=from-file\n", env={"FOO": ""})
        self.assertEqual((code, out), (0, ""))

    def test_values_are_literal_not_expanded_and_may_hold_equals(self):
        code, out, _ = run("FOO=$HOME/`id`=x y\n")
        self.assertEqual((code, out), (0, "$HOME/`id`=x y"))

    def test_a_line_that_is_not_key_value_is_refused_by_number(self):
        code, _, err = run("FOO=bar\njust words\n")
        self.assertEqual(code, 65)
        self.assertIn(":2 ", err)

    def test_an_invalid_name_is_refused(self):
        for bad in ("foo=1", "1FOO=1", "FO-O=1", "FOO BAR=1", "=1"):
            code, _, err = run(bad + "\n")
            self.assertEqual(code, 65, bad)
            self.assertIn("invalid name", err, bad)

    def test_a_secret_looking_name_is_refused_and_runs_nothing(self):
        for name in ("SUPABASE_SECRET_KEY", "DB_PASSWORD", "ZEN_JOBS_TRIGGER_TOKEN", "DB_URL",
                     "APP_DB_USERNAME", "SMTP_PASSWORD", "SOME_PRIVATE_THING"):
            code, out, err = run("FOO=ok\n%s=x\n" % name)
            self.assertEqual(code, 65, name)
            self.assertEqual(out, "", name)
            self.assertIn("looks like a secret", err, name)

    def test_a_secret_key_value_is_refused_under_any_name(self):
        code, _, err = run("SUPABASE_KEY=sb_secret_abc\n")
        self.assertEqual(code, 65)
        self.assertIn("sb_secret_", err)

    def test_a_missing_file_and_missing_arguments_fail(self):
        gone = subprocess.run(["sh", str(SCRIPT), "/nonexistent.env", "true"], capture_output=True, text=True)
        self.assertEqual(gone.returncode, 66)
        few = subprocess.run(["sh", str(SCRIPT), "only-one"], capture_output=True, text=True)
        self.assertEqual(few.returncode, 64)

    def test_the_command_exit_code_is_the_commands(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "x.env"
            path.write_text("FOO=1\n")
            done = subprocess.run(["sh", str(SCRIPT), str(path), "sh", "-c", "exit 7"])
            self.assertEqual(done.returncode, 7)


class CommittedFile(unittest.TestCase):
    def test_it_passes_the_loader_and_names_every_required_variable(self):
        values = {}
        for line in COMMITTED.read_text().splitlines():
            if line and not line.startswith("#"):
                key, _, value = line.partition("=")
                values[key] = value
        for name in REQUIRED:
            self.assertTrue(values.get(name), "deploy/persistent.env must set %s" % name)
        # The loader's own refusals, applied to the real file: nothing secret-shaped is committed.
        done = subprocess.run(["sh", str(SCRIPT), str(COMMITTED), "true"], capture_output=True, text=True)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertTrue(values["SUPABASE_KEY"].startswith("sb_publishable_"))

    def test_it_is_not_a_place_for_the_mail_relays_login(self):
        keys = {l.partition("=")[0] for l in COMMITTED.read_text().splitlines() if l and not l.startswith("#")}
        self.assertFalse({"SMTP_USERNAME", "SMTP_PASSWORD"} & keys)


if __name__ == "__main__":
    unittest.main()
