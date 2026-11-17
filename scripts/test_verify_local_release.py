#!/usr/bin/env python3
"""Proves scripts/verify_local_release.py can fail. Run by `task verify:local-release` first.

Each test builds a throwaway tree and plants one violation of one rule; the gate must go red and
name it. A gate that stopped matching would read green forever.
"""
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "verify_local_release.py"
APP = "local/prudent_local_client"
GOOD_MANIFEST = (
    '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'
    '  <application android:allowBackup="false" android:fullBackupContent="false"/>\n'
    "</manifest>\n"
)
PLAIN_MANIFEST = '<manifest xmlns:android="http://schemas.android.com/apk/res/android"/>\n'


def tree(root: Path) -> None:
    for rel, text in (
        (f"{APP}/android/app/src/main/AndroidManifest.xml", GOOD_MANIFEST),
        (f"{APP}/android/app/src/debug/AndroidManifest.xml", PLAIN_MANIFEST),
        (f"{APP}/android/app/src/profile/AndroidManifest.xml", PLAIN_MANIFEST),
        (f"{APP}/lib/main.dart", "void main() {}\n"),
        (f"{APP}/lib/core/sync_starter.dart", "// ZenSync.start(store) is here\nfinal x = ZenSync.start(s);\n"),
        ("client/lib/main.dart", "void main() {}\n"),
        ("packages/prudent_ui/lib/a.dart", "const a = 1;\n"),
        (".github/workflows/ci.yml", "name: CI\n# ZEN_SYNC is a comment here\n"),
    ):
        path = root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)


def run(mutate=None, *extra) -> subprocess.CompletedProcess:
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        tree(root)
        if mutate:
            mutate(root)
        args = [a(root) if callable(a) else a for a in extra]
        return subprocess.run([sys.executable, "-I", str(SCRIPT), *args, str(root)],
                              capture_output=True, text=True)


def write(rel: str, text: str):
    def go(root: Path) -> None:
        path = root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
    return go


MAIN = f"{APP}/android/app/src/main/AndroidManifest.xml"


class Gate(unittest.TestCase):
    def test_clean_tree_passes(self):
        r = run()
        self.assertEqual(r.returncode, 0, r.stdout)

    # T10
    def test_allow_backup_true_fails(self):
        r = run(write(MAIN, GOOD_MANIFEST.replace('allowBackup="false"', 'allowBackup="true"')))
        self.assertEqual(r.returncode, 1)
        self.assertIn("android:allowBackup", r.stdout)

    def test_allow_backup_removed_fails(self):
        r = run(write(MAIN, PLAIN_MANIFEST))
        self.assertEqual(r.returncode, 1)
        self.assertIn("android:allowBackup", r.stdout)

    def test_full_backup_content_rules_file_fails(self):
        r = run(write(MAIN, GOOD_MANIFEST.replace('fullBackupContent="false"', 'fullBackupContent="@xml/rules"')))
        self.assertEqual(r.returncode, 1)
        self.assertIn("android:fullBackupContent", r.stdout)

    def test_data_extraction_rules_fail(self):
        r = run(write(MAIN, GOOD_MANIFEST.replace("<application ", '<application android:dataExtractionRules="@xml/x" ')))
        self.assertEqual(r.returncode, 1)
        self.assertIn("dataExtractionRules", r.stdout)

    def test_tools_replace_fails(self):
        r = run(write(MAIN, GOOD_MANIFEST.replace("<application ", '<application tools:replace="android:allowBackup" ')))
        self.assertEqual(r.returncode, 1)
        self.assertIn("tools:replace", r.stdout)

    def test_debug_manifest_turning_backup_on_fails(self):
        r = run(write(f"{APP}/android/app/src/debug/AndroidManifest.xml",
                      GOOD_MANIFEST.replace('allowBackup="false"', 'allowBackup="true"')))
        self.assertEqual(r.returncode, 1)
        self.assertIn("debug/AndroidManifest.xml", r.stdout)

    def test_merged_manifest_with_backup_on_fails(self):
        def plant(root: Path) -> None:
            (root / "merged.xml").write_text(GOOD_MANIFEST.replace('allowBackup="false"', 'allowBackup="true"'))
        r = run(plant, "--merged", lambda root: str(root / "merged.xml"))
        self.assertEqual(r.returncode, 1)
        self.assertIn("merged manifest", r.stdout)

    def test_clean_merged_manifest_passes(self):
        def plant(root: Path) -> None:
            (root / "merged.xml").write_text(GOOD_MANIFEST)
        r = run(plant, "--merged", lambda root: str(root / "merged.xml"))
        self.assertEqual(r.returncode, 0, r.stdout)

    def test_missing_merged_manifest_fails(self):
        r = run(None, "--merged", lambda root: str(root / "nope.xml"))
        self.assertEqual(r.returncode, 1)
        self.assertIn("did not produce it", r.stdout)

    def test_missing_manifest_is_a_failure_not_a_pass(self):
        def drop(root: Path) -> None:
            (root / MAIN).unlink()
        r = run(drop)
        self.assertEqual(r.returncode, 1)
        self.assertIn("matches nothing", r.stdout)

    # T18
    def test_a_second_zen_sync_reader_fails(self):
        r = run(write(f"{APP}/lib/sync.dart", "const s = String.fromEnvironment('ZEN_SYNC');\n"))
        self.assertEqual(r.returncode, 1)
        self.assertIn("names ZEN_SYNC in code", r.stdout)

    def test_a_zen_sync_reader_in_client_fails(self):
        r = run(write("client/lib/x.dart", 'const s = String.fromEnvironment( "ZEN_SYNC_FOLDER");\n'))
        self.assertEqual(r.returncode, 1)

    def test_has_environment_fails(self):
        r = run(write(f"{APP}/lib/a.dart", "const on = bool.hasEnvironment('ZEN_SYNC');\n"))
        self.assertEqual(r.returncode, 1)
        self.assertIn("names ZEN_SYNC in code", r.stdout)

    def test_multiline_from_environment_fails(self):
        r = run(write(f"{APP}/lib/b.dart", "const s = String.fromEnvironment(\n  'ZEN_SYNC',\n);\n"))
        self.assertEqual(r.returncode, 1)
        self.assertIn("b.dart:2", r.stdout)

    def test_block_comment_mention_passes_but_code_after_it_fails(self):
        self.assertEqual(run(write(f"{APP}/lib/c.dart", "/* ZEN_SYNC\n is jZen's */\n")).returncode, 0)
        r = run(write(f"{APP}/lib/c.dart", "/* x */ const k = 'ZEN_SYNC';\n"))
        self.assertEqual(r.returncode, 1)

    def test_a_test_may_name_zen_sync(self):
        r = run(write(f"{APP}/test/t_test.dart", "const s = 'ZEN_SYNC';\n"))
        self.assertEqual(r.returncode, 0, r.stdout)

    # T18: one starter
    def test_folder_cloud_built_outside_the_starter_fails(self):
        r = run(write(f"{APP}/lib/x.dart", "final t = ZenFolderCloud(store: s);\n"))
        self.assertEqual(r.returncode, 1)
        self.assertIn("only local/prudent_local_client/lib/core/sync_starter.dart", r.stdout)

    def test_zen_sync_start_for_outside_the_starter_fails(self):
        r = run(write(f"{APP}/lib/y.dart", "final t = ZenSync.startFor(plan, s);\n"))
        self.assertEqual(r.returncode, 1)

    def test_a_plan_built_outside_the_starter_fails(self):
        r = run(write("packages/prudent_ui/lib/p.dart", "const p = ZenSyncPlan('macos', '');\n"))
        self.assertEqual(r.returncode, 1)

    def test_a_type_check_on_a_transport_passes(self):
        r = run(write(f"{APP}/lib/z.dart", "bool f(Object t) => t is ZenSharedFolderSync;\n"))
        self.assertEqual(r.returncode, 0, r.stdout)

    def test_missing_starter_fails(self):
        def go(root):
            (root / APP / "lib/core/sync_starter.dart").unlink()
        r = run(go)
        self.assertEqual(r.returncode, 1)
        self.assertIn("does not exist", r.stdout)

    def test_a_commented_mention_passes(self):
        r = run(write(f"{APP}/lib/doc.dart", "// String.fromEnvironment('ZEN_SYNC') is jZen's\n"))
        self.assertEqual(r.returncode, 0, r.stdout)

    def test_workflow_setting_zen_sync_fails(self):
        r = run(write(".github/workflows/ci.yml", "jobs:\n  b:\n    run: task zen:build:runners:release ZEN_SYNC=folder\n"))
        self.assertEqual(r.returncode, 1)
        self.assertIn("ci.yml:3", r.stdout)

    # No web
    def test_a_web_runner_fails(self):
        r = run(write(f"{APP}/web/index.html", "<html/>\n"))
        self.assertEqual(r.returncode, 1)
        self.assertIn("no web target", r.stdout)


if __name__ == "__main__":
    unittest.main()
