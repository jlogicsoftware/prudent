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


CORE_PUBSPEC = "name: prudent_local_core\ndependencies:\n  crypto: ^3.0.6\ndev_dependencies:\n  test: ^1.25.0\n"
LOCAL_FILES = {
    "local/prudent_local_core/pubspec.yaml": CORE_PUBSPEC,
    "local/prudent_local_core/lib/a.dart": "final a = 1;\n",
    "local/prudent_local_store/pubspec.yaml": "name: prudent_local_store\ndependencies:\n  zen_store:\n    path: x\n",
    "local/prudent_local_store/lib/a.dart": "final a = 1;\n",
    # The wire messages (ADR-111): generated code only, pure Dart.
    "packages/prudent_proto/pubspec.yaml": "name: prudent_proto\ndependencies:\n  protobuf: ^6.0.0\n",
    "packages/prudent_proto/lib/generated/prudent/v1/a.pb.dart": "import 'package:protobuf/protobuf.dart';\n",
    # The parity harness lives outside local/ (ADR-109), where it may name the transport.
    "tools/prudent_parity_server/pubspec.yaml": CLEAN_PUBSPEC
    + "  zen_transport:\n    path: x\n  zen_identity:\n    path: y\n  prudent_local_core:\n    path: ../../local/prudent_local_core\n",
    "tools/prudent_parity_server/test/a_test.dart": "import 'package:zen_transport/zen_transport.dart';\n",
}


def run_gate(
    *,
    shared_lib=None,
    shared_test=None,
    shared_pubspec=CLEAN_PUBSPEC,
    client_lib=None,
    local=None,
    drop_local=False,
    extra=None,
) -> "tuple[int, str]":
    """`local` maps a path under local/ to its text and overrides the clean Local tree."""
    files = {
        "client/pubspec.yaml": CLEAN_PUBSPEC,
        "client/lib/main.dart": "void main() {}\n",
        "packages/prudent_ui/pubspec.yaml": shared_pubspec,
        "packages/prudent_ui/lib/a.dart": "final a = 1;\n",
        "packages/prudent_ui/test/a_test.dart": "void main() {}\n",
        **ADMIN_FILES,
        **({} if drop_local else LOCAL_FILES),
    }
    files.update({f"local/{k}": v for k, v in (local or {}).items()})
    files.update({f"packages/prudent_ui/lib/{k}": v for k, v in (shared_lib or {}).items()})
    files.update({f"packages/prudent_ui/test/{k}": v for k, v in (shared_test or {}).items()})
    files.update({f"client/lib/{k}": v for k, v in (client_lib or {}).items()})
    files.update(extra or {})
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
                **LOCAL_FILES,
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


class LocalCodeIsServerFree(unittest.TestCase):
    def test_every_server_only_package_is_refused_as_an_import(self) -> None:
        for name in gate.SERVER_ONLY_PACKAGES:
            for d in ("lib", "bin", "test"):
                with self.subTest(package=name, dir=d):
                    rc, out = run_gate(
                        local={f"prudent_local_core/{d}/leak.dart": f"import 'package:{name}/x.dart';\n"}
                    )
                    self.assertEqual(rc, 1, out)
                    self.assertIn(f"local/prudent_local_core/{d}/leak.dart:1", out)

    def test_an_export_and_a_double_quoted_import_are_refused_too(self) -> None:
        for line in (
            "export 'package:zen_transport/zen_transport.dart';\n",
            'import "package:zen_identity/zen_identity.dart" as identity;\n',
        ):
            with self.subTest(line=line):
                rc, out = run_gate(local={"prudent_local_core/lib/leak.dart": line})
                self.assertEqual(rc, 1, out)

    def test_a_package_added_later_is_covered(self) -> None:
        rc, out = run_gate(
            local={
                "prudent_local_client/pubspec.yaml": "name: prudent_local_client\n",
                "prudent_local_client/lib/a.dart": "import 'package:zen_transport/zen_transport.dart';\n",
            }
        )
        self.assertEqual(rc, 1, out)
        self.assertIn("local/prudent_local_client/lib/a.dart:1", out)

    def test_a_dependency_in_any_section_is_refused(self) -> None:
        for section in ("dependencies", "dev_dependencies", "dependency_overrides"):
            with self.subTest(section=section):
                rc, out = run_gate(
                    local={
                        "prudent_local_core/pubspec.yaml": CORE_PUBSPEC
                        + f"{section}:\n  zen_identity:\n    path: ../x\n"
                    }
                )
                self.assertEqual(rc, 1, out)
                self.assertIn("local/prudent_local_core/pubspec.yaml", out)

    def test_the_parity_harness_outside_local_may_name_them(self) -> None:
        rc, out = run_gate()  # the clean tree's harness, under tools/, already does
        self.assertEqual(rc, 0, out)

    def test_the_harness_gets_no_exemption_under_local(self) -> None:
        rc, out = run_gate(
            local={
                "prudent_parity_server/pubspec.yaml": "name: prudent_parity_server\n  zen_transport:\n    path: x\n",
                "prudent_parity_server/test/a_test.dart": "import 'package:zen_transport/zen_transport.dart';\n",
            }
        )
        self.assertEqual(rc, 1, out)
        self.assertIn("local/prudent_parity_server/test/a_test.dart:1", out)

    def test_nothing_may_depend_on_the_parity_harness(self) -> None:
        rc, out = run_gate(
            local={
                "prudent_local_core/pubspec.yaml": CORE_PUBSPEC
                + "  prudent_parity_server:\n    path: ../prudent_parity_server\n"
            }
        )
        self.assertEqual(rc, 1, out)
        self.assertIn("local/prudent_local_core/pubspec.yaml", out)

    def test_a_comment_naming_a_package_is_not_a_dependency(self) -> None:
        rc, out = run_gate(
            local={
                "prudent_local_core/pubspec.yaml": CORE_PUBSPEC + "  # zen_transport: never\n",
                "prudent_local_core/lib/n.dart": "// import 'package:zen_transport/zen_transport.dart';\n",
            }
        )
        self.assertEqual(rc, 0, out)

    def test_a_missing_local_tree_fails_rather_than_passes(self) -> None:
        rc, out = run_gate(drop_local=True)
        self.assertEqual(rc, 1)
        self.assertIn("stale", out)


class LocalCoreIsPureDart(unittest.TestCase):
    def test_flutter_as_a_dependency_is_refused(self) -> None:
        for dep in (
            "  flutter:\n    sdk: flutter\n",
            "  flutter_test:\n    sdk: flutter\n",
            "  some_plugin:\n    sdk: flutter\n",
        ):
            with self.subTest(dep=dep):
                rc, out = run_gate(
                    local={"prudent_local_core/pubspec.yaml": CORE_PUBSPEC + dep}
                )
                self.assertEqual(rc, 1, out)
                self.assertIn("local/prudent_local_core/pubspec.yaml", out)

    def test_a_flutter_section_is_refused(self) -> None:
        rc, out = run_gate(
            local={"prudent_local_core/pubspec.yaml": CORE_PUBSPEC + "flutter:\n  uses-material-design: true\n"}
        )
        self.assertEqual(rc, 1, out)

    def test_flutter_imports_are_refused(self) -> None:
        for line in (
            "import 'package:flutter/foundation.dart';\n",
            "import 'package:flutter_test/flutter_test.dart';\n",
            "import 'dart:ui';\n",
            "export 'package:flutter/widgets.dart';\n",
        ):
            with self.subTest(line=line):
                rc, out = run_gate(local={"prudent_local_core/lib/leak.dart": line})
                self.assertEqual(rc, 1, out)
                self.assertIn("local/prudent_local_core/lib/leak.dart:1", out)

    def test_another_local_package_may_use_flutter(self) -> None:
        rc, out = run_gate(
            local={
                "prudent_local_client/pubspec.yaml": "name: c\ndependencies:\n  flutter:\n    sdk: flutter\n",
                "prudent_local_client/lib/a.dart": "import 'package:flutter/widgets.dart';\n",
            }
        )
        self.assertEqual(rc, 0, out)

    def test_a_comment_naming_flutter_is_not_a_dependency(self) -> None:
        rc, out = run_gate(
            local={"prudent_local_core/lib/n.dart": "// import 'package:flutter/widgets.dart';\n"}
        )
        self.assertEqual(rc, 0, out)


class NothingOutsideLocalUsesLocal(unittest.TestCase):
    def test_imports_of_a_local_package_are_refused(self) -> None:
        for kw in ("import", "export"):
            with self.subTest(kw=kw):
                rc, out = run_gate(client_lib={"x.dart": f"{kw} 'package:prudent_local_core/money.dart';\n"})
                self.assertEqual(rc, 1, out)
                self.assertIn("client/lib/x.dart:1", out)
        rc, out = run_gate(shared_lib={"x.dart": "import 'package:prudent_local_core/a.dart';\n"})
        self.assertEqual(rc, 1, out)
        self.assertIn("packages/prudent_ui/lib/x.dart:1", out)

    def test_a_package_added_to_local_later_is_covered(self) -> None:
        rc, out = run_gate(
            local={"prudent_local_client/pubspec.yaml": "name: prudent_local_client\n"},
            client_lib={"x.dart": "import 'package:prudent_local_client/a.dart';\n"},
        )
        self.assertEqual(rc, 1, out)

    def test_a_dependency_by_name_is_refused(self) -> None:
        rc, out = run_gate(shared_pubspec=CLEAN_PUBSPEC + "  prudent_local_core:\n    path: ../x\n")
        self.assertEqual(rc, 1, out)
        self.assertIn("packages/prudent_ui/pubspec.yaml", out)

    def test_a_path_into_local_is_refused_whatever_it_is_called(self) -> None:
        rc, out = run_gate(
            shared_pubspec=CLEAN_PUBSPEC + "  renamed:\n    path: ../../local/prudent_local_core\n"
        )
        self.assertEqual(rc, 1, out)

    def test_a_test_in_the_shared_package_is_held_to_it(self) -> None:
        rc, out = run_gate(shared_test={"t.dart": "import 'package:prudent_local_core/a.dart';\n"})
        self.assertEqual(rc, 1, out)

    def test_a_comment_is_not_a_dependency(self) -> None:
        rc, out = run_gate(
            shared_pubspec=CLEAN_PUBSPEC + "  # prudent_local_core: never\n",
            client_lib={"x.dart": "// import 'package:prudent_local_core/a.dart';\n"},
        )
        self.assertEqual(rc, 0, out)


class WirePackageAndStoreAreGuarded(unittest.TestCase):
    """ADR-111: the store and the wire messages are pure Dart, and the wire messages reach no server."""

    def test_flutter_in_the_store_is_refused(self) -> None:
        for path, text in (
            ("prudent_local_store/pubspec.yaml", "name: s\ndependencies:\n  flutter:\n    sdk: flutter\n"),
            ("prudent_local_store/lib/leak.dart", "import 'package:flutter/foundation.dart';\n"),
            ("prudent_local_store/test/leak_test.dart", "import 'package:flutter_test/flutter_test.dart';\n"),
        ):
            with self.subTest(path=path):
                rc, out = run_gate(local={path: text})
                self.assertEqual(rc, 1, out)
                self.assertIn(f"local/{path}", out)

    def test_flutter_in_the_wire_messages_is_refused_even_in_generated_code(self) -> None:
        for path, text in (
            ("packages/prudent_proto/pubspec.yaml", "name: p\ndependencies:\n  flutter:\n    sdk: flutter\n"),
            ("packages/prudent_proto/lib/generated/prudent/v1/leak.pb.dart", "import 'dart:ui';\n"),
        ):
            with self.subTest(path=path):
                rc, out = run_gate(extra={path: text})
                self.assertEqual(rc, 1, out)
                self.assertIn(path, out)

    def test_the_transport_in_the_wire_messages_is_refused(self) -> None:
        rc, out = run_gate(
            extra={"packages/prudent_proto/pubspec.yaml": "name: p\ndependencies:\n  zen_transport:\n    path: x\n"}
        )
        self.assertEqual(rc, 1, out)
        self.assertIn("packages/prudent_proto/pubspec.yaml", out)

    def test_a_missing_store_or_wire_package_fails_rather_than_passes(self) -> None:
        for missing in ("local/prudent_local_store/pubspec.yaml", "packages/prudent_proto/pubspec.yaml"):
            with self.subTest(missing=missing):
                with tempfile.TemporaryDirectory() as tmp:
                    root = Path(tmp)
                    files = {
                        "client/pubspec.yaml": CLEAN_PUBSPEC,
                        "client/lib/main.dart": "void main() {}\n",
                        "packages/prudent_ui/pubspec.yaml": CLEAN_PUBSPEC,
                        "packages/prudent_ui/lib/a.dart": "final a = 1;\n",
                        "packages/prudent_ui/test/a_test.dart": "void main() {}\n",
                        **ADMIN_FILES,
                        **LOCAL_FILES,
                    }
                    del files[missing]
                    for rel, text in files.items():
                        path = root / rel
                        path.parent.mkdir(parents=True, exist_ok=True)
                        path.write_text(text, encoding="utf-8")
                    out = io.StringIO()
                    with redirect_stdout(out):
                        rc = gate.main(root)
                    self.assertEqual(rc, 1, out.getvalue())
                    self.assertIn("stale", out.getvalue())


if __name__ == "__main__":
    unittest.main()
