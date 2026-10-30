#!/usr/bin/env python3
"""Proves scripts/verify_mail_templates.py can fail. Run by `task verify:mail-templates` first.

A gate that stopped matching would read green forever, so each test copies the real templates into
a throwaway tree, plants one defect and requires the verdict it should give.
"""
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SCRIPT = REPO / "scripts" / "verify_mail_templates.py"


def run(mutate=None) -> subprocess.CompletedProcess:
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        (root / "supabase").mkdir()
        shutil.copy(REPO / "supabase" / "config.toml", root / "supabase" / "config.toml")
        shutil.copytree(REPO / "supabase" / "templates", root / "supabase" / "templates")
        if mutate:
            mutate(root)
        return subprocess.run([sys.executable, "-I", str(SCRIPT), str(root)], capture_output=True, text=True)


def edit(name: str, old: str, new: str):
    def apply(root: Path) -> None:
        f = root / "supabase" / "templates" / name
        text = f.read_text()
        assert old in text, f"{old!r} is not in {name}; the test is out of date"
        f.write_text(text.replace(old, new, 1))
    return apply


def edit_config(old: str, new: str):
    def apply(root: Path) -> None:
        f = root / "supabase" / "config.toml"
        text = f.read_text()
        assert old in text, f"{old!r} is not in config.toml; the test is out of date"
        f.write_text(text.replace(old, new, 1))
    return apply


class Gate(unittest.TestCase):
    def fails(self, mutate, message: str) -> None:
        r = run(mutate)
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertIn(message, r.stdout)

    def test_the_repository_templates_pass(self):
        r = run()
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_unknown_placeholder_fails(self):
        self.fails(edit("confirmation.html", "{{ .Email }}", "{{ .Emial }}"), "{{ .Emial }}")

    def test_site_url_placeholder_fails_until_188(self):
        self.fails(edit("recovery.html", "{{ .Email }}", "{{ .SiteURL }}"), "{{ .SiteURL }}")

    def test_unclosed_placeholder_fails(self):
        # It swallows text up to the next `}}`, so the verdict names an unknown placeholder.
        self.fails(edit("recovery.html", "{{ .Email }}", "{{ .Email }"), "which is not one of")

    def test_stray_closing_braces_fail(self):
        self.fails(edit("recovery.html", "Prudent</div>", "Prudent }}</div>"), "unclosed or stray")

    def test_spacing_inside_the_braces_is_not_a_difference(self):
        r = run(edit("recovery.html", 'href="{{ .ConfirmationURL }}"', 'href="{{.ConfirmationURL}}"'))
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_foreign_host_in_an_href_fails(self):
        self.fails(edit("confirmation.html", 'href="{{ .ConfirmationURL }}"', 'href="https://abc.supabase.co/auth/v1/verify"'),
                   "an href is `https://abc.supabase.co/auth/v1/verify`")

    def test_hard_coded_host_in_the_text_fails(self):
        self.fails(edit("recovery.html", "Prudent</div>", "Prudent https://example.com</div>"), "https://example.com")

    def test_protocol_relative_address_fails(self):
        self.fails(edit("recovery.html", "Prudent</div>", "Prudent //example.com</div>"), "//example.com")

    def test_remote_image_fails(self):
        self.fails(edit("confirmation.html", '<div class="card"', '<img alt="" width="1" height="1"><div class="card"'), "<img")

    def test_background_image_fails(self):
        self.fails(edit("confirmation.html", "background:#f4f6f3;", "background:url(x);"), "url(")

    def test_missing_language_block_fails(self):
        self.fails(edit("confirmation.html", '<div lang="pl">', "<div>"), 'no lang="pl" block')

    def test_missing_plain_link_fails(self):
        r = run(edit("recovery.html", ">{{ .ConfirmationURL }}</a>", ">the link</a>"))
        self.assertEqual(r.returncode, 1, r.stdout)
        self.assertIn("plain link beside the button is missing", r.stdout)

    def test_missing_product_name_fails(self):
        def strip(root: Path) -> None:
            f = root / "supabase" / "templates" / "recovery.html"
            f.write_text(f.read_text().replace("Prudent", "Product"))
        self.fails(strip, "the body never names Prudent")

    def test_subject_with_a_placeholder_fails(self):
        self.fails(edit_config("Reset hasła Prudent\"", "Reset hasła Prudent {{ .Email }}\""), "the subject takes a placeholder")

    def test_subject_with_one_language_fails(self):
        self.fails(edit_config("Confirm your Prudent email · Підтвердіть пошту Prudent · Potwierdź e-mail w Prudent",
                               "Confirm your Prudent email"), "must name 3 languages")

    def test_empty_subject_fails(self):
        self.fails(edit_config('subject = "Reset your Prudent password · Скидання пароля Prudent · Reset hasła Prudent"',
                               'subject = ""'), "the subject is empty")

    def test_missing_template_file_fails(self):
        def remove(root: Path) -> None:
            (root / "supabase" / "templates" / "recovery.html").unlink()
        self.fails(remove, "does not exist")

    def test_unwired_template_fails(self):
        def add(root: Path) -> None:
            shutil.copy(root / "supabase" / "templates" / "recovery.html", root / "supabase" / "templates" / "magic_link.html")
        self.fails(add, "is wired by no [auth.email.template.*]")

    def test_no_wired_template_fails(self):
        def comment(root: Path) -> None:
            f = root / "supabase" / "config.toml"
            f.write_text(f.read_text().replace("[auth.email.template.", "# [auth.email.template."))
        self.fails(comment, "wires no [auth.email.template.*]")

    def test_missing_config_fails(self):
        def remove(root: Path) -> None:
            (root / "supabase" / "config.toml").unlink()
        self.fails(remove, "the scope matches nothing")


if __name__ == "__main__":
    unittest.main()
