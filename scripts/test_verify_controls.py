#!/usr/bin/env python3
"""Proof that `task verify:controls` can fail, and that its carve-outs are the ones it documents.

A gate that has only ever been seen green is decoration. Every banned control is planted in a
throwaway tree and must turn the gate red; each carve-out must stay green; and a scope that
matches nothing must fail rather than pass. Run by `task verify:controls`, before the gate itself.
"""

from __future__ import annotations

import io
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

import verify_controls as gate


def run_gate(files: "dict[str, str]") -> "tuple[int, str]":
    """Run the gate over a throwaway client tree holding `files` (paths relative to client/lib)."""
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        for rel, text in files.items():
            path = root / "client" / "lib" / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8")
        out = io.StringIO()
        with redirect_stdout(out):
            rc = gate.main(root)
        return rc, out.getvalue()


def screen(body: str) -> "dict[str, str]":
    return {"screen.dart": f"Widget build(BuildContext context) {{\n  return {body};\n}}\n"}


ALERT = """showDialog<void>(
  context: context,
  builder: (ctx) => AlertDialog(
    title: Text(t.title),
    content: Text(t.message),
    actions: [ZenButton(label: t.okay, onPressed: () => Navigator.pop(ctx))],
  ),
)"""


class BannedControls(unittest.TestCase):
    def test_every_banned_control_turns_the_gate_red(self) -> None:
        for name in gate.BANNED_CONTROLS:
            with self.subTest(control=name):
                rc, out = run_gate(screen(f"{name}(onPressed: () {{}}, child: Text('x'))"))
                self.assertEqual(rc, 1, out)
                self.assertIn(f"{name} is a raw Material control", out)
                self.assertIn("screen.dart:2", out)

    def test_named_constructor_is_caught(self) -> None:
        rc, out = run_gate(screen("FilledButton.tonal(onPressed: null, child: Text('x'))"))
        self.assertEqual(rc, 1, out)

    def test_dropdown_form_field_is_reported_as_itself(self) -> None:
        rc, out = run_gate(screen("DropdownButtonFormField<String>(items: [])"))
        self.assertEqual(rc, 1)
        self.assertIn("DropdownButtonFormField is a raw", out)

    def test_a_longer_name_is_not_a_banned_control(self) -> None:
        rc, out = run_gate(screen("MyTextButtonLabel()"))
        self.assertEqual(rc, 0, out)

    def test_a_banned_control_in_a_nested_directory_is_caught(self) -> None:
        rc, _ = run_gate({"a/b/c/deep.dart": "final x = ElevatedButton(onPressed: null);\n"})
        self.assertEqual(rc, 1)

    def test_a_raw_button_inside_an_alert_dialog_is_still_banned(self) -> None:
        body = ALERT.replace("ZenButton(label: t.okay,", "TextButton(child: Text(t.okay),")
        rc, out = run_gate(screen(body))
        self.assertEqual(rc, 1)
        self.assertIn("TextButton", out)


class ShowDialog(unittest.TestCase):
    def test_an_alert_dialog_acknowledgement_is_allowed(self) -> None:
        rc, out = run_gate(screen(ALERT))
        self.assertEqual(rc, 0, out)

    def test_a_typed_alert_dialog_confirmation_is_allowed(self) -> None:
        body = ALERT.replace("showDialog<void>", "showDialog<bool>")
        rc, out = run_gate(screen(body))
        self.assertEqual(rc, 0, out)

    def test_a_dialog_that_is_not_an_alert_dialog_fails(self) -> None:
        rc, out = run_gate(
            screen("showDialog(context: context, builder: (ctx) => Dialog(child: MyForm()))")
        )
        self.assertEqual(rc, 1)
        self.assertIn("showDialog shows something other than an AlertDialog", out)

    def test_a_dialog_hidden_behind_another_widget_fails(self) -> None:
        rc, _ = run_gate(screen("showDialog(context: context, builder: (_) => EditDialog())"))
        self.assertEqual(rc, 1)

    def test_a_tear_off_fails(self) -> None:
        rc, _ = run_gate(screen("showDialog"))
        self.assertEqual(rc, 1)

    def test_an_alert_dialog_with_an_input_is_a_form_and_fails(self) -> None:
        for widget in ("TextField", "TextFormField", "Form"):
            with self.subTest(widget=widget):
                body = ALERT.replace("content: Text(t.message)", f"content: {widget}()")
                rc, out = run_gate(screen(body))
                self.assertEqual(rc, 1, out)
                self.assertIn(f"carries an input ({widget})", out)

    def test_an_input_outside_the_dialog_is_not_charged_to_it(self) -> None:
        source = "final field = TextField();\n" + screen(ALERT)["screen.dart"]
        rc, out = run_gate({"screen.dart": source})
        self.assertEqual(rc, 0, out)


class CarveOutsAndMasking(unittest.TestCase):
    def test_popup_menu_button_is_allowed(self) -> None:
        rc, out = run_gate(screen("PopupMenuButton<int>(itemBuilder: (_) => [])"))
        self.assertEqual(rc, 0, out)

    def test_the_framework_controls_are_allowed(self) -> None:
        rc, out = run_gate(
            screen("Column(children: [ZenButton(label: 'x', onPressed: null), ZenSelect<int>()])")
        )
        self.assertEqual(rc, 0, out)

    def test_a_comment_naming_a_banned_control_is_not_a_violation(self) -> None:
        source = (
            "// ZenButton replaces TextButton and ElevatedButton.\n"
            "/* showDatePicker is gone; /* nested SegmentedButton */ too */\n"
            "/// A DropdownButton used to live here.\n"
            "final ok = 1;\n"
        )
        rc, out = run_gate({"screen.dart": source})
        self.assertEqual(rc, 0, out)

    def test_a_string_naming_a_banned_control_is_not_a_violation(self) -> None:
        source = (
            "final a = 'TextButton';\n"
            'final b = "ElevatedButton and // not a comment";\n'
            "final c = r'showDialog $x';\n"
            "final d = '''\nOutlinedButton\n''';\n"
        )
        rc, out = run_gate({"screen.dart": source})
        self.assertEqual(rc, 0, out)

    def test_code_after_a_string_with_a_comment_marker_is_still_scanned(self) -> None:
        source = "final url = 'a//b'; final w = TextButton(onPressed: null);\n"
        rc, _ = run_gate({"screen.dart": source})
        self.assertEqual(rc, 1)

    def test_code_inside_a_string_interpolation_is_scanned(self) -> None:
        source = "final s = 'x ${TextButton(onPressed: null)} y';\n"
        rc, _ = run_gate({"screen.dart": source})
        self.assertEqual(rc, 1)

    def test_a_banned_control_after_an_interpolated_string_is_scanned(self) -> None:
        source = "final s = 'a ${b} c'; final w = ElevatedButton(onPressed: null);\n"
        rc, _ = run_gate({"screen.dart": source})
        self.assertEqual(rc, 1)

    def test_an_escaped_quote_does_not_end_the_string_early(self) -> None:
        source = "final s = 'it\\'s a TextButton'; final ok = 1;\n"
        rc, out = run_gate({"screen.dart": source})
        self.assertEqual(rc, 0, out)

    def test_line_numbers_survive_masking(self) -> None:
        source = "/* one\ntwo\nthree */\nfinal s = '''a\nb''';\nfinal w = TextButton();\n"
        rc, out = run_gate({"screen.dart": source})
        self.assertEqual(rc, 1)
        self.assertIn("screen.dart:6:", out)


class Scope(unittest.TestCase):
    def test_generated_and_l10n_output_is_not_scanned(self) -> None:
        rc, out = run_gate(
            {
                "ok.dart": "final ok = 1;\n",
                "generated/api.dart": "final x = ElevatedButton();\n",
                "l10n/generated/loc.dart": "final y = TextButton();\n",
            }
        )
        self.assertEqual(rc, 0, out)

    def test_a_directory_merely_named_like_an_excluded_one_is_scanned(self) -> None:
        rc, _ = run_gate({"my_generated/api.dart": "final x = ElevatedButton();\n"})
        self.assertEqual(rc, 1)

    def test_a_missing_client_tree_fails_rather_than_passes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out = io.StringIO()
            with redirect_stdout(out):
                rc = gate.main(Path(tmp))
        self.assertEqual(rc, 1)
        self.assertIn("stale", out.getvalue())

    def test_a_scope_with_only_excluded_sources_fails_rather_than_passes(self) -> None:
        rc, out = run_gate({"generated/api.dart": "final ok = 1;\n"})
        self.assertEqual(rc, 1)
        self.assertIn("stale", out)


class RealTree(unittest.TestCase):
    def test_the_repository_itself_is_clean(self) -> None:
        out = io.StringIO()
        with redirect_stdout(out):
            rc = gate.main()
        self.assertEqual(rc, 0, out.getvalue())


if __name__ == "__main__":
    unittest.main()
