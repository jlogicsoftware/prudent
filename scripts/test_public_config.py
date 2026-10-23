#!/usr/bin/env python3
"""Proof that the public configuration of the Cloud Run deploy is checked, derived and wired as
plain values (jlogicsoftware/prudent#166).

Two halves, because the risk is in two places:

  * scripts/public_config.sh, sourced the way the Taskfile sources it: what it accepts, what it
    refuses by name, and that the three derived values cannot disagree with WEB_API_URL.
  * the Taskfile text of `deploy:cloudrun`, which cannot be run here (it builds a native image and
    calls a cloud). What it can be held to is the shape the acceptance criteria name: the secret
    list holds only genuine secrets, and the migration job AND the service both receive all five
    public values as literals. A value slipping back into --set-secrets, or onto only one of the
    two, deploys green and is found by a configuration check or not at all.

Run by `task test:public-config`, which CI runs. Written to Python 3.9 like the other scripts.
"""

from __future__ import annotations

import re
import subprocess
import unittest
from pathlib import Path
from typing import Dict, Optional, Tuple

ROOT = Path(__file__).resolve().parent.parent
PUBLIC = ("SUPABASE_URL", "SITE_URL", "CORS_ORIGINS", "AUTH_REDIRECT_URI", "AUTH_REDIRECT_URIS")
SECRETS = ("SUPABASE_KEY", "DB_URL", "DB_USERNAME", "DB_PASSWORD", "ZEN_JOBS_TRIGGER_TOKEN")
APP_DB = ("APP_DB_USERNAME", "APP_DB_PASSWORD")

GOOD = {
    "WEB_API_URL": "https://svc-123.europe-west1.run.app",
    "SUPABASE_URL": "https://ref.supabase.co",
    "AUTH_REDIRECT_URIS": "prudent://auth-callback",
}


def source(env_overrides: Optional[Dict[str, Optional[str]]] = None) -> Tuple[int, str, str]:
    """Source the script in a clean shell and print the three derived values, one per line."""
    env = {"PATH": "/usr/bin:/bin"}
    env.update(GOOD)
    for k, v in (env_overrides or {}).items():
        if v is None:
            env.pop(k, None)
        else:
            env[k] = v
    p = subprocess.run(
        ["sh", "-c", '. scripts/public_config.sh; printf "%s\\n%s\\n%s\\n" '
                     '"$SITE_URL" "$CORS_ORIGINS" "$AUTH_REDIRECT_URI"'],
        cwd=ROOT, env=env, capture_output=True, text=True, timeout=30)
    return p.returncode, p.stdout, p.stderr


class Accepts(unittest.TestCase):
    def test_derives_the_three_values_from_the_web_api_url(self):
        rc, out, err = source()
        self.assertEqual(rc, 0, err)
        self.assertEqual(out.split("\n")[:3], [
            GOOD["WEB_API_URL"], GOOD["WEB_API_URL"], GOOD["WEB_API_URL"] + "/auth/callback"])

    def test_a_trailing_slash_is_not_carried_into_the_origin(self):
        rc, out, err = source({"WEB_API_URL": GOOD["WEB_API_URL"] + "/"})
        self.assertEqual(rc, 0, err)
        self.assertEqual(out.split("\n")[0], GOOD["WEB_API_URL"])

    def test_several_redirect_uris_are_accepted(self):
        rc, _, err = source({"AUTH_REDIRECT_URIS": "prudent://auth-callback,https://x.example/cb"})
        self.assertEqual(rc, 0, err)

    def test_a_derived_value_exported_as_the_same_thing_is_accepted(self):
        rc, _, err = source({"SITE_URL": GOOD["WEB_API_URL"]})
        self.assertEqual(rc, 0, err)


class Refuses(unittest.TestCase):
    def refused(self, overrides, *fragments):
        rc, out, err = source(overrides)
        self.assertNotEqual(rc, 0, "it accepted: %r" % (overrides,))
        self.assertEqual(out, "", "it printed values although it refused")
        for f in fragments:
            self.assertIn(f, err)

    def test_each_missing_input_is_named(self):
        for name in ("WEB_API_URL", "SUPABASE_URL", "AUTH_REDIRECT_URIS"):
            with self.subTest(name=name):
                self.refused({name: None}, "MISSING: " + name)

    def test_a_blank_input_is_missing_not_empty(self):
        self.refused({"AUTH_REDIRECT_URIS": ""}, "MISSING: AUTH_REDIRECT_URIS")

    def test_every_missing_input_is_named_at_once(self):
        self.refused({"SUPABASE_URL": None, "AUTH_REDIRECT_URIS": None},
                     "MISSING: SUPABASE_URL", "MISSING: AUTH_REDIRECT_URIS")

    def test_supabase_url_must_be_https(self):
        self.refused({"SUPABASE_URL": "http://ref.supabase.co"}, "SUPABASE_URL must be an https:// URL")
        self.refused({"SUPABASE_URL": "ref.supabase.co"}, "SUPABASE_URL must be an https:// URL")

    def test_a_comma_in_a_single_valued_url_would_split_it_in_two(self):
        self.refused({"SUPABASE_URL": "https://a.example,https://b.example"}, "plain URL")
        self.refused({"WEB_API_URL": "https://a.example,x"}, "plain URL")

    def test_whitespace_is_never_part_of_a_url(self):
        self.refused({"SUPABASE_URL": "https://a.example "}, "plain URL")

    def test_an_at_sign_would_break_the_list_delimiter(self):
        self.refused({"AUTH_REDIRECT_URIS": "prudent://a@b"}, "must not contain @")

    def test_a_redirect_entry_needs_a_scheme_and_a_target(self):
        for bad in ("callback", "prudent://", "://x", "prudent://ok,callback"):
            with self.subTest(value=bad):
                self.refused({"AUTH_REDIRECT_URIS": bad}, "AUTH_REDIRECT_URIS")

    def test_an_empty_list_entry_is_refused(self):
        for bad in ("prudent://a,", ",prudent://a", "prudent://a,,prudent://b"):
            with self.subTest(value=bad):
                self.refused({"AUTH_REDIRECT_URIS": bad}, "AUTH_REDIRECT_URIS")

    def test_a_derived_value_exported_as_something_else_is_refused_not_ignored(self):
        for name in ("SITE_URL", "CORS_ORIGINS", "AUTH_REDIRECT_URI"):
            with self.subTest(name=name):
                self.refused({name: "https://elsewhere.example.org"},
                             name + " is set to https://elsewhere.example.org", "derived from WEB_API_URL")


class TaskfileShape(unittest.TestCase):
    """What `deploy:cloudrun` hands gcloud, read from its text."""

    @classmethod
    def setUpClass(cls):
        text = (ROOT / "Taskfile.yml").read_text()
        start = text.index("\n  deploy:cloudrun:")
        end = text.index("\n  deploy:check-origin-config:")
        body = text[start:end]
        cls.body = body[body.index("    cmds:"):]  # the commands, not the prose of the summary

    def secrets_line(self, name):
        m = re.search(r'^\s*%s="([^"]*)"' % name, self.body, re.M)
        self.assertIsNotNone(m, "no %s= line in deploy:cloudrun" % name)
        return [pair.split("=")[0] for pair in m.group(1).split(",")]

    def gcloud_call(self, subcommand):
        m = re.search(r"gcloud run %s .*?--quiet" % re.escape(subcommand), self.body, re.S)
        self.assertIsNotNone(m, "no `gcloud run %s` call" % subcommand)
        return m.group(0)

    def test_the_secret_list_holds_the_seven_genuine_secrets_and_no_public_value(self):
        names = self.secrets_line("SECRETS") + self.secrets_line("APP_DB")
        self.assertEqual(sorted(names), sorted(SECRETS + APP_DB))
        for public in PUBLIC:
            self.assertNotIn(public, names)

    def test_the_migration_job_gets_the_secrets_but_not_the_runtime_login(self):
        job = self.gcloud_call("jobs deploy")
        self.assertIn('--set-secrets="${SECRETS}"', job)
        self.assertNotIn("APP_DB", job)

    def test_the_service_gets_the_runtime_login_as_well(self):
        self.assertIn('--set-secrets="${SECRETS},${APP_DB}"', self.gcloud_call("deploy"))

    def test_the_job_and_the_service_both_get_all_five_public_values_as_literals(self):
        for where, call in (("migration job", self.gcloud_call("jobs deploy")), ("service", self.gcloud_call("deploy"))):
            for name in PUBLIC:
                with self.subTest(where=where, name=name):
                    self.assertRegex(call, r'--set-env-vars="(\^@\^)?%s=\$\{%s\}"' % (name, name))

    def test_the_comma_list_has_its_own_delimiter_and_no_other_value_does(self):
        for call in (self.gcloud_call("jobs deploy"), self.gcloud_call("deploy")):
            self.assertIn('--set-env-vars="^@^AUTH_REDIRECT_URIS=${AUTH_REDIRECT_URIS}"', call)
            for name in PUBLIC[:-1]:
                self.assertNotIn("^@^%s=" % name, call)

    def test_the_public_values_come_from_the_checked_script_before_the_build(self):
        # Once in the preflight (before ten minutes of build) and once where the values are used.
        self.assertGreaterEqual(self.body.count(". scripts/public_config.sh"), 2)
        self.assertLess(self.body.index(". scripts/public_config.sh"), self.body.index("task: build:web"))


if __name__ == "__main__":
    unittest.main()
