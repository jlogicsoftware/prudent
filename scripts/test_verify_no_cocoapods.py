#!/usr/bin/env python3
"""Proves scripts/verify_no_cocoapods.py can fail. Run by `task verify:swiftpm` first.

A gate that stopped matching would read green forever, so each test builds a throwaway tree and
requires the verdict it should give.
"""
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "verify_no_cocoapods.py"
CLEAN_PBX = "// !$*UTF8*$!\n{ objects = { FlutterGeneratedPluginSwiftPackage = {}; }; }\n"
CLEAN_XCCONFIG = '#include "Generated.xcconfig"\n'
CLEAN_WORKSPACE = '<Workspace>\n   <FileRef location = "group:Runner.xcodeproj"></FileRef>\n</Workspace>\n'


def tree(root: Path) -> None:
    for runner in ("client/ios", "client/macos"):
        base = root / runner
        (base / "Runner.xcodeproj").mkdir(parents=True)
        (base / "Runner.xcworkspace").mkdir()
        (base / "Flutter").mkdir()
        (base / "Runner.xcodeproj" / "project.pbxproj").write_text(CLEAN_PBX)
        (base / "Flutter" / "Debug.xcconfig").write_text(CLEAN_XCCONFIG)
        (base / "Runner.xcworkspace" / "contents.xcworkspacedata").write_text(CLEAN_WORKSPACE)


def run(mutate=None) -> subprocess.CompletedProcess:
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        tree(root)
        if mutate:
            mutate(root)
        return subprocess.run([sys.executable, "-I", str(SCRIPT), str(root)], capture_output=True, text=True)


class Gate(unittest.TestCase):
    def test_clean_runners_pass(self):
        r = run()
        self.assertEqual(r.returncode, 0, r.stdout)

    def test_podfile_fails(self):
        r = run(lambda root: (root / "client/ios/Podfile").write_text("platform :ios\n"))
        self.assertEqual(r.returncode, 1)
        self.assertIn("client/ios/Podfile exists", r.stdout)

    def test_macos_podfile_lock_fails(self):
        r = run(lambda root: (root / "client/macos/Podfile.lock").write_text("PODS:\n"))
        self.assertEqual(r.returncode, 1)
        self.assertIn("client/macos/Podfile.lock", r.stdout)

    def test_pods_directory_fails(self):
        r = run(lambda root: (root / "client/macos/Pods").mkdir())
        self.assertEqual(r.returncode, 1)
        self.assertIn("client/macos/Pods exists", r.stdout)

    def test_cocoapods_build_phase_fails(self):
        def plant(root: Path) -> None:
            (root / "client/ios/Runner.xcodeproj/project.pbxproj").write_text(
                CLEAN_PBX + 'name = "[CP] Check Pods Manifest.lock";\n')
        r = run(plant)
        self.assertEqual(r.returncode, 1)
        self.assertIn("client/ios/Runner.xcodeproj/project.pbxproj refers to CocoaPods", r.stdout)

    def test_xcconfig_include_fails(self):
        def plant(root: Path) -> None:
            (root / "client/macos/Flutter/Debug.xcconfig").write_text(
                '#include? "Pods/Target Support Files/Pods-Runner/Pods-Runner.debug.xcconfig"\n')
        r = run(plant)
        self.assertEqual(r.returncode, 1)
        self.assertIn("client/macos/Flutter/Debug.xcconfig refers to CocoaPods", r.stdout)

    def test_workspace_pods_project_fails(self):
        def plant(root: Path) -> None:
            (root / "client/ios/Runner.xcworkspace/contents.xcworkspacedata").write_text(
                '<Workspace><FileRef location = "group:Pods/Pods.xcodeproj"></FileRef></Workspace>\n')
        r = run(plant)
        self.assertEqual(r.returncode, 1)

    def test_missing_runner_is_a_failure_not_a_pass(self):
        def drop(root: Path) -> None:
            (root / "client/ios/Runner.xcodeproj/project.pbxproj").unlink()
        r = run(drop)
        self.assertEqual(r.returncode, 1)
        self.assertIn("matches nothing", r.stdout)


if __name__ == "__main__":
    unittest.main()
