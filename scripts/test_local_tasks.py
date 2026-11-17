#!/usr/bin/env python3
"""Proof that `task` runs Prudent Local with no server and refuses the web (plan unit 11, ADR-124).

The tasks are jZen's, included a third time as `zenlocal` and told the app has no server module, so
what is proven here is the wiring: Prudent's Taskfile reaches the framework's Local behaviour and
cannot reach it by accident. `task` is run for real, against a stub `flutter` that records its
arguments; nothing is built.

  * `run:local DEVICE=chrome` fails and says why (the web has no durable place for the store).
  * `run:local DEVICE=macos` reaches `flutter run` for the Local app with no backend probe (no
    server is running) and no ZEN_API_URL or auth redirect define.
  * the same task for the server-connected app, `run:client DEVICE=macos`, does probe a backend and
    so fails here — the control that says the first success is not an accident of the stub.
  * with a server module present at the Local include's path the web refusal disappears: the refusal
    rests on one fact of the tree, and the gate `verify:local-release` and this case keep it true.
  * the release build carries no ZEN_SYNC unless one is given; given one, it is passed through
    unchanged (the refusal is jZen's, at run time: `task test:local-release-refusal`).

A throwaway copy of the Taskfile points `../jZen` at the framework checkout by absolute path, so the
suite also runs from a git worktree (where the relative include does not resolve, ADR-065).
Needs go-task and a jZen checkout (JZEN_DIR, else ../jZen of the main checkout). Python 3.9.
"""
from __future__ import annotations

import os
import re
import shutil
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def jzen_dir() -> Path:
    if os.environ.get("JZEN_DIR"):
        return Path(os.environ["JZEN_DIR"])
    common = subprocess.run(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
                            cwd=ROOT, capture_output=True, text=True, check=True).stdout.strip()
    for base in (ROOT, Path(common).parent):
        if (base.parent / "jZen" / "Taskfile.app.yml").is_file():
            return base.parent / "jZen"
    raise unittest.SkipTest("no jZen checkout found; set JZEN_DIR")


FLUTTER_STUB = '#!/bin/sh\necho "flutter $*" >> "$STUB_LOG"\nexit 0\n'
CURL_STUB = '#!/bin/sh\necho "curl $*" >> "$STUB_LOG"\nexit 7\n'


class LocalTasks(unittest.TestCase):
    def setUp(self):
        if shutil.which("task") is None:
            self.skipTest("go-task is not installed")
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        text = (ROOT / "Taskfile.yml").read_text().replace("../jZen/", f"{jzen_dir()}/")
        (self.tmp / "Taskfile.yml").write_text(text)
        bin_dir = self.tmp / "bin"
        bin_dir.mkdir()
        for name, body in (("flutter", FLUTTER_STUB), ("curl", CURL_STUB)):
            stub = bin_dir / name
            stub.write_text(body)
            stub.chmod(stub.stat().st_mode | stat.S_IXUSR)
        self.log = self.tmp / "calls.log"
        self.log.write_text("")
        self.env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}", STUB_LOG=str(self.log))

    def task(self, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run(["task", "-t", str(self.tmp / "Taskfile.yml"), "-d", str(ROOT), *args],
                              capture_output=True, text=True, env=self.env)

    def calls(self) -> str:
        return self.log.read_text()

    def test_web_is_refused_for_the_local_app(self):
        for device in ("chrome", "edge", "web-server"):
            r = self.task("run:local", f"DEVICE={device}")
            self.assertNotEqual(r.returncode, 0, device)
            self.assertIn("no web target", r.stdout + r.stderr)
        self.assertNotIn("flutter run", self.calls())

    def test_web_platform_is_refused_on_any_device(self):
        r = self.task("run:local", "DEVICE=emulator-5554", "CLIENT_PLATFORM=web")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("no web target", r.stdout + r.stderr)

    def test_native_run_needs_no_server_and_bakes_in_no_api(self):
        r = self.task("run:local", "DEVICE=macos")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        calls = self.calls()
        self.assertNotIn("curl", calls, "a Local app has no backend to probe")
        run = [line for line in calls.splitlines() if line.startswith("flutter run")]
        self.assertEqual(len(run), 1, calls)
        self.assertIn("-d macos", run[0])
        self.assertIn("--dart-define=ZEN_PLATFORM=macos", run[0])
        self.assertNotIn("ZEN_API_URL", run[0])
        self.assertNotIn("ZEN_AUTH_REDIRECT_URI", run[0])
        self.assertNotIn("ZEN_SYNC", run[0])

    def test_runs_the_local_app_not_the_server_connected_one(self):
        # The stub cannot show the working directory, so ask the shell what `flutter run` ran in.
        stub = self.tmp / "bin" / "flutter"
        stub.write_text('#!/bin/sh\necho "flutter $* @ $(pwd)" >> "$STUB_LOG"\nexit 0\n')
        r = self.task("run:local", "DEVICE=macos")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        run = [l for l in self.calls().splitlines() if l.startswith("flutter run")][0]
        self.assertTrue(run.endswith("local/prudent_local_client"), run)

    def test_the_server_connected_app_does_probe_a_backend(self):
        r = self.task("run:client", "DEVICE=macos")
        self.assertNotEqual(r.returncode, 0, "the control: with no backend it must fail")
        self.assertIn("curl", self.calls())
        self.assertNotIn("flutter run", self.calls())

    def test_a_server_module_removes_the_web_refusal(self):
        # The Local include's one fact: no pom at local/no_server. Put one there and the framework
        # treats the app as server-connected — so the path must stay empty.
        pom = ROOT / "local" / "no_server" / "pom.xml"
        self.assertFalse(pom.exists(), "local/no_server must not exist")
        text = (self.tmp / "Taskfile.yml").read_text().replace("local/no_server", "server")
        (self.tmp / "Taskfile.yml").write_text(text)
        r = self.task("run:local", "DEVICE=chrome")
        self.assertNotIn("no web target", r.stdout + r.stderr)

    def test_release_build_passes_no_zen_sync_by_default(self):
        r = self.task("build:local:runners:release")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        builds = [l for l in self.calls().splitlines() if l.startswith("flutter build")]
        self.assertTrue(builds, self.calls())
        for line in builds:
            self.assertIn("--release", line)
            self.assertNotIn("ZEN_SYNC", line)
            self.assertNotIn("ZEN_API_URL", line)

    def test_release_build_given_zen_sync_passes_it_on_unchanged(self):
        r = self.task("build:local:runners:release", "ZEN_SYNC=folder", "ZEN_SYNC_FOLDER=/abs/x")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        builds = [l for l in self.calls().splitlines() if l.startswith("flutter build")]
        self.assertTrue(any(re.search(r"--dart-define=ZEN_SYNC=folder", l) for l in builds), self.calls())

    def test_release_build_refuses_an_unknown_zen_sync(self):
        r = self.task("build:local:runners:release", "ZEN_SYNC=bogus")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("neither folder nor cloudkit", r.stdout + r.stderr)


if __name__ == "__main__":
    unittest.main()
