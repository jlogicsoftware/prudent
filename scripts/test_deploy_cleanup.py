#!/usr/bin/env python3
"""Proof that deploy:cloudrun pins the image, runs jZen's cleanup after the service is accepted,
with Prudent's numbers, and that a cleanup which cannot finish exits non-zero (ADR-087, #165).

Two kinds of case, because the full task builds a native image and cannot run here:

  * `task deploy:pin` and `task deploy:cleanup` are run through `task` itself against a stub
    `gcloud` and `docker` that record every call. The failing case must fail.
  * the order of deploy:cloudrun's steps is read from the Taskfile text: the pin after the push and
    before the first `gcloud run`, the cleanup after deploy:accept-origin.

Nothing touches a cloud or a local Docker daemon. Run by `task test:deploy-origin`, which CI runs.
Written to Python 3.9 like the other scripts.
"""

from __future__ import annotations

import json
import os
import shutil
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Records every call to $STUB_LOG, then answers like an environment whose registry holds one image
# tagged with the commit and nothing else. STUB_FAIL names a `gcloud` subcommand prefix that fails.
GCLOUD_STUB = r"""#!/bin/sh
echo "gcloud $*" >> "$STUB_LOG"
if [ -n "${STUB_FAIL:-}" ]; then
  case "$*" in *"$STUB_FAIL"*) echo "stub: $STUB_FAIL refused" >&2; exit 1 ;; esac
fi
case "$1 $2 $3" in
  "auth print-access-token "*) echo token ;;
  "run revisions list") echo '[]' ;;
  "run jobs list") echo '[]' ;;
  "run services describe") echo '{"status":{"latestReadyRevisionName":"svc-00001"}}' ;;
  "artifacts repositories describe") echo '{}' ;;
  "artifacts docker images") echo "$STUB_IMAGES" ;;
  "artifacts docker tags") ;;
  *) echo "stub gcloud: unexpected call: $*" >&2; exit 99 ;;
esac
"""
# Any docker call is recorded and refused: cleanup is run with CLEANUP_DOCKER=off, so a call here
# means a test is about to touch a real daemon.
DOCKER_STUB = '#!/bin/sh\necho "docker $*" >> "$STUB_LOG"\nexit 97\n'

FACTS = dict(GCP_PROJECT="proj", GCP_REGION="reg", SERVICE_NAME="svc", ARTIFACT_REPO="repo")
PACKAGE = "reg-docker.pkg.dev/proj/repo/prudent-server"


def head():
    return subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT, capture_output=True,
                          text=True, check=True).stdout.strip()


class TaskCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.task = shutil.which("task")
        cls.stubs = tempfile.mkdtemp(prefix="stub-cleanup-")
        for name, body in (("gcloud", GCLOUD_STUB), ("docker", DOCKER_STUB)):
            stub = Path(cls.stubs) / name
            stub.write_text(body)
            stub.chmod(stub.stat().st_mode | stat.S_IXUSR)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.stubs, ignore_errors=True)

    def setUp(self):
        # Missing go-task must FAIL, not skip: a gate that skips itself is decoration.
        self.assertIsNotNone(self.task, "go-task ('task') is required to run these tests")
        self.log = Path(self.stubs) / "calls.log"
        self.log.write_text("")

    def run_task(self, name, images=(), **env):
        base = {"PATH": self.stubs + os.pathsep + os.environ.get("PATH", ""),
                "HOME": os.environ.get("HOME", ""), "STUB_LOG": str(self.log),
                "STUB_IMAGES": json.dumps(list(images)), "CLEANUP_DOCKER": "off"}
        base.update(FACTS)
        base.update({k: v for k, v in env.items() if v is not None})
        p = subprocess.run([self.task, name], cwd=ROOT, env=base, capture_output=True, text=True,
                           timeout=180)
        calls = self.log.read_text().splitlines()
        return p.returncode, p.stdout + p.stderr, calls


def image(tag, digest="sha256:" + "a" * 64):
    return {"package": PACKAGE, "version": digest, "createTime": "2026-01-01T00:00:00+00:00",
            "tags": [tag]}


class Pin(TaskCase):
    def test_the_image_of_this_commit_is_tagged_with_its_pin(self):
        rc, out, calls = self.run_task("deploy:pin", images=[image(head())])
        self.assertEqual(rc, 0, out)
        add = [c for c in calls if c.startswith("gcloud artifacts docker tags add")]
        self.assertEqual(len(add), 1, calls)
        self.assertIn(PACKAGE + "@sha256:" + "a" * 64, add[0])
        self.assertIn("zen-pin-", add[0])

    def test_an_image_that_is_not_in_the_registry_fails(self):
        rc, out, calls = self.run_task("deploy:pin", images=[image("someothercommit")])
        self.assertNotEqual(rc, 0, out)
        self.assertIn("is not in the registry", out)
        self.assertFalse([c for c in calls if " tags add" in c], calls)

    def test_a_failed_tagging_fails(self):
        rc, out, _ = self.run_task("deploy:pin", images=[image(head())], STUB_FAIL="tags add")
        self.assertNotEqual(rc, 0, out)

    def test_a_missing_environment_fact_is_refused_by_name(self):
        rc, out, _ = self.run_task("deploy:pin", images=[image(head())], ARTIFACT_REPO="")
        self.assertNotEqual(rc, 0, out)
        self.assertIn("AR_REPO is not set", out)


class Cleanup(TaskCase):
    def test_it_reads_the_revisions_and_the_registry_of_this_environment(self):
        rc, out, calls = self.run_task("deploy:cleanup")
        self.assertEqual(rc, 0, out)
        self.assertIn("gcloud run revisions list --service=svc --project=proj --region=reg --format=json", calls)
        self.assertTrue(any(c.startswith("gcloud artifacts docker images list %s-docker.pkg.dev/proj/repo"
                                         % "reg") for c in calls), calls)

    def test_it_runs_with_prudents_numbers_not_the_frameworks(self):
        rc, out, _ = self.run_task("deploy:cleanup", CLEANUP_DRY_RUN="1")
        self.assertEqual(rc, 0, out)
        self.assertIn("beyond the newest 5)", out)
        self.assertIn("older than 14d", out)
        self.assertIn("keep the newest 30 per package", out)
        self.assertIn("everything newer than 30d", out)

    def test_a_dry_run_changes_nothing(self):
        rc, out, calls = self.run_task("deploy:cleanup", CLEANUP_DRY_RUN="1")
        self.assertEqual(rc, 0, out)
        for verb in (" tags add", " tags delete", " images delete", "revisions delete", "delete-cleanup-policies"):
            self.assertFalse([c for c in calls if verb in c], (verb, calls))

    def test_a_cleanup_that_cannot_finish_exits_non_zero_and_says_the_deploy_succeeded(self):
        rc, out, _ = self.run_task("deploy:cleanup", STUB_FAIL="artifacts docker images list")
        self.assertNotEqual(rc, 0, out)
        self.assertIn("deploy itself succeeded", out)

    def test_a_failure_in_the_environment_cannot_make_it_warn(self):
        # The mode is Prudent's decision (ADR-087): an exported CLEANUP_ON_FAILURE=warn is ignored.
        rc, out, _ = self.run_task("deploy:cleanup", STUB_FAIL="artifacts docker images list",
                                   CLEANUP_ON_FAILURE="warn")
        self.assertNotEqual(rc, 0, out)

    def test_a_missing_environment_fact_is_refused_by_name(self):
        rc, out, calls = self.run_task("deploy:cleanup", ARTIFACT_REPO="")
        self.assertNotEqual(rc, 0, out)
        self.assertIn("AR_REPO is not set", out)
        self.assertFalse([c for c in calls if " delete" in c], calls)


class TaskfileShape(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        text = (ROOT / "Taskfile.yml").read_text()
        start = text.index("\n  deploy:cloudrun:")
        end = text.index("\n  deploy:pin:")
        body = text[start:end]
        cls.body = body[body.index("    cmds:"):]  # the commands, not the prose of the summary

    def at(self, needle):
        self.assertIn(needle, self.body)
        return self.body.index(needle)

    def test_the_image_is_pinned_after_the_push_and_before_anything_is_pointed_at_it(self):
        pin = self.at("- task: deploy:pin")
        self.assertLess(self.at("docker push"), pin)
        self.assertLess(pin, self.at("gcloud run jobs deploy"))
        self.assertLess(pin, self.at("gcloud run deploy"))

    def test_the_cleanup_runs_last_after_the_service_is_accepted(self):
        cleanup = self.at("- task: deploy:cleanup")
        self.assertLess(self.at("- task: deploy:accept-origin"), cleanup)
        self.assertLess(self.at("gcloud run deploy"), cleanup)
        self.assertNotIn("- task:", self.body[cleanup + 1:], "nothing may follow the cleanup")

    def test_prudents_numbers_and_failure_mode_are_command_line_variables_of_the_cleanup_task(self):
        text = (ROOT / "Taskfile.yml").read_text()
        task = text[text.index("\n  deploy:cleanup:"):text.index("\n  deploy:check-origin-config:")]
        call = task[task.index("    cmds:"):]
        for pair in ("CLEANUP_KEEP_VERSIONS=30", "CLEANUP_IMAGE_DAYS=30", "CLEANUP_KEEP_REVISIONS=5",
                     "CLEANUP_REVISION_DAYS=14", "CLEANUP_ON_FAILURE=fail"):
            self.assertIn(pair, call)

    def test_no_failure_is_swallowed_around_the_calls(self):
        self.assertNotIn("|| true", self.body)
        self.assertNotIn("CLEANUP_ON_FAILURE=warn", self.body)


if __name__ == "__main__":
    unittest.main()
