"""Proves `verify_boundaries.py` can fail on the rule ADR-108 adds: the shared package imports and
depends on nothing that can reach the server. Run by `task verify:boundaries`, first, the way
test_verify_controls.py runs before `verify:controls` — a gate nobody has seen go red is decoration.

Written to the same Python 3.9 floor as the gate, stdlib only.
"""

import io
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

import verify_boundaries as gate

CLEAN_PUBSPEC = "dependencies:\n  flutter:\n    sdk: flutter\n  zen_core:\n    path: x\n"
ADMIN_FILES = {
    "admin/package.json": "{}\n",
    "admin/src/a.ts": "export const a = 1;\n",
}


def run_gate(
    *, shared_lib=None, shared_test=None, shared_pubspec=CLEAN_PUBSPEC, client_lib=None
) -> "tuple[int, str]":
    files = {
        "client/pubspec.yaml": CLEAN_PUBSPEC,
        "client/lib/main.dart": "void main() {}\n",
        "packages/prudent_ui/pubspec.yaml": shared_pubspec,
        "packages/prudent_ui/lib/a.dart": "final a = 1;\n",
        "packages/prudent_ui/test/a_test.dart": "void main() {}\n",
        **ADMIN_FILES,
    }
    files.update({f"packages/prudent_ui/lib/{k}": v for k, v in (shared_lib or {}).items()})
    files.update({f"packages/prudent_ui/test/{k}": v for k, v in (shared_test or {}).items()})
    files.update({f"client/lib/{k}": v for k, v in (client_lib or {}).items()})
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        for rel, text in files.items():
            path = root / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8")
        out = io.StringIO()
        with redirect_stdout(out):
            rc = gate.main(root)
        return rc, out.getvalue()


class SharedPackageIsServerFree(unittest.TestCase):
    def test_a_clean_tree_passes(self) -> None:
        rc, out = run_gate()
        self.assertEqual(rc, 0, out)

    def test_every_server_only_package_is_refused_as_an_import(self) -> None:
        for name in gate.SERVER_ONLY_PACKAGES:
            with self.subTest(package=name):
                rc, out = run_gate(shared_lib={"leak.dart": f"import 'package:{name}/{name}.dart';\n"})
                self.assertEqual(rc, 1, out)
                self.assertIn("packages/prudent_ui/lib/leak.dart:1", out)

    def test_an_export_and_a_double_quoted_import_are_refused_too(self) -> None:
        for line in (
            "export 'package:zen_transport/zen_transport.dart';\n",
            'import "package:zen_identity/zen_identity.dart" as identity;\n',
        ):
            with self.subTest(line=line):
                rc, out = run_gate(shared_lib={"leak.dart": line})
                self.assertEqual(rc, 1, out)

    def test_a_test_in_the_package_is_held_to_the_same_rule(self) -> None:
        rc, out = run_gate(
            shared_test={"leak_test.dart": "import 'package:zen_transport/zen_transport.dart';\n"}
        )
        self.assertEqual(rc, 1, out)
        self.assertIn("packages/prudent_ui/test/leak_test.dart:1", out)

    def test_a_dependency_on_any_of_them_is_refused(self) -> None:
        for name in gate.SERVER_ONLY_PACKAGES:
            with self.subTest(package=name):
                rc, out = run_gate(
                    shared_pubspec=CLEAN_PUBSPEC + f"  {name}:\n    path: ../../jZen/client/{name}\n"
                )
                self.assertEqual(rc, 1, out)
                self.assertIn("packages/prudent_ui/pubspec.yaml", out)

    def test_a_comment_naming_a_package_is_not_a_dependency(self) -> None:
        rc, out = run_gate(
            shared_pubspec=CLEAN_PUBSPEC + "  # zen_transport: never here\n",
            shared_lib={"note.dart": "// import 'package:zen_transport/zen_transport.dart';\n"},
        )
        self.assertEqual(rc, 0, out)

    def test_the_client_may_import_them(self) -> None:
        rc, out = run_gate(
            client_lib={"auth.dart": "import 'package:zen_identity/zen_identity.dart';\n"}
        )
        self.assertEqual(rc, 0, out)

    def test_a_missing_package_fails_rather_than_passes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for rel, text in {
                "client/pubspec.yaml": CLEAN_PUBSPEC,
                "client/lib/main.dart": "void main() {}\n",
                **ADMIN_FILES,
            }.items():
                path = root / rel
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text, encoding="utf-8")
            out = io.StringIO()
            with redirect_stdout(out):
                rc = gate.main(root)
        self.assertEqual(rc, 1)
        self.assertIn("stale", out.getvalue())


class SharedPackageIsScannedByTheOtherChecks(unittest.TestCase):
    def test_a_provider_host_in_the_package_is_refused(self) -> None:
        rc, out = run_gate(shared_lib={"leak.dart": "final h = 'supabase.co';\n"})
        self.assertEqual(rc, 1, out)

    def test_package_http_in_the_package_is_refused(self) -> None:
        rc, out = run_gate(shared_lib={"leak.dart": "import 'package:http/http.dart';\n"})
        self.assertEqual(rc, 1, out)


if __name__ == "__main__":
    unittest.main()
