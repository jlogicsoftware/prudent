#!/usr/bin/env python3
"""Fail if a sign-up or recovery mail template is not safe to send. Run by `task verify:mail-templates`.

GoTrue renders `supabase/templates/*.html` with Go's template engine, and what it does with a
placeholder it does not know is silent: an unknown field renders as an empty string, so a link
becomes `href=""` and the mail goes out looking fine. The mail is also the first thing a new person
sees from Prudent, and its link is the one that was mistaken for phishing (ADR-079), so this gate
pins what the templates may contain instead of trusting a reader to notice.

It fails on, in each template named by `[auth.email.template.*]` in `supabase/config.toml`:

* a `{{ … }}` that is not in `ALLOWED_PLACEHOLDERS` (including one left unclosed). Until
  jlogicsoftware/prudent#188 the link is GoTrue's own `{{ .ConfirmationURL }}`, so `.SiteURL`,
  `.TokenHash` and the rest are refused here; #188 widens the set when it points the link at
  Prudent's own origin;
* an `href` whose value is anything but the link placeholder, and a literal `http://`, `https://` or
  `//` address anywhere in the file, so a hard-coded host (`supabase.co` or any other) cannot appear;
* `<img`, `<script`, `<link`, `<iframe`, `@import`, `url(` or a `src` attribute: no remote image, so
  no open pixel of our own and nothing a mail client fetches on its own;
* a body that lacks one of the `lang="en"`, `lang="uk"`, `lang="pl"` blocks (one body per mail type
  carries all three, ADR-079), that never names Prudent, or that has no plain-text link, the
  anchor whose visible text is the link placeholder itself;
* a subject that is empty, takes a placeholder, never names Prudent or does not name three languages
  (`en · uk · pl`).

It also fails when `config.toml` wires no template, wires a file that does not exist, or when a file
in `supabase/templates/` is wired by nothing, so a template cannot be added and forgotten. A scope
that matches nothing is a failure, not a pass.

Usage: verify_mail_templates.py [REPO_ROOT]   (default: the repository this script lives in)
Stdlib only, 3.9 floor (so no `tomllib`: the sections are read by pattern).
"""
import re
import sys
from pathlib import Path

CONFIG = "supabase/config.toml"
TEMPLATES = "supabase/templates"
LINK = "{{ .ConfirmationURL }}"
# What a template may interpolate. Whitespace inside the braces is not significant to GoTrue.
ALLOWED_PLACEHOLDERS = {"{{ .ConfirmationURL }}", "{{ .Email }}"}
LANGUAGES = ("en", "uk", "pl")

SECTION = re.compile(r"^\[auth\.email\.template\.([a-z_]+)\]\s*$", re.M)
PLACEHOLDER = re.compile(r"\{\{(.*?)\}\}", re.S)
HREF = re.compile(r"""href\s*=\s*(?:"([^"]*)"|'([^']*)')""", re.I)
ANCHOR = re.compile(r"<a\b[^>]*>(.*?)</a>", re.S | re.I)
LITERAL_ADDRESS = re.compile(r"(?:https?:)?//[^\s\"'<>]+", re.I)
FORBIDDEN = re.compile(r"<\s*(?:img|script|link|iframe)\b|@import|url\s*\(|\bsrc\s*=", re.I)


def normalise(placeholder: str) -> str:
    return "{{ " + " ".join(placeholder.split()) + " }}"


def canon(text: str) -> str:
    """`text` with every placeholder spelled one way, so spacing inside the braces cannot matter."""
    return PLACEHOLDER.sub(lambda m: normalise(m.group(1)), text.strip())


def sections(config: str) -> dict:
    """`{name: {"content_path": …, "subject": …}}` for every uncommented template section."""
    found = {}
    matches = list(SECTION.finditer(config))
    for i, m in enumerate(matches):
        end = matches[i + 1].start() if i + 1 < len(matches) else len(config)
        # Stop at the next table of any kind, not only at the next template.
        body = re.split(r"^\[", config[m.end():end], maxsplit=1, flags=re.M)[0]
        keys = {}
        for key in ("content_path", "subject"):
            kv = re.search(rf'^{key}\s*=\s*"([^"]*)"\s*$', body, re.M)
            if kv:
                keys[key] = kv.group(1)
        found[m.group(1)] = keys
    return found


def check_text(name: str, label: str, text: str, failures: list) -> None:
    """Placeholders shared by a subject and a body."""
    for m in PLACEHOLDER.finditer(text):
        if normalise(m.group(1)) not in ALLOWED_PLACEHOLDERS:
            failures.append(f"{name}: {label} uses `{{{{{m.group(1)}}}}}`, which is not one of "
                            f"{sorted(ALLOWED_PLACEHOLDERS)}")
    stripped = PLACEHOLDER.sub("", text)
    if "{{" in stripped or "}}" in stripped:
        failures.append(f"{name}: {label} has an unclosed or stray `{{{{` / `}}}}`")


def check_body(name: str, body: str, failures: list) -> None:
    check_text(name, "the body", body, failures)
    for m in HREF.finditer(body):
        value = m.group(1) if m.group(1) is not None else m.group(2)
        if canon(value) != LINK:
            failures.append(f"{name}: an href is `{value}`; it must be exactly `{LINK}` (a link to a "
                            "foreign host is what made the first mail look like phishing, ADR-079)")
    for m in LITERAL_ADDRESS.finditer(PLACEHOLDER.sub("", body)):
        failures.append(f"{name}: a hard-coded address `{m.group(0)}`; the templates carry only GoTrue placeholders")
    for m in FORBIDDEN.finditer(body):
        failures.append(f"{name}: `{m.group(0)}` fetches something on its own or hides a pixel; a mail carries no "
                        "remote content and no tracking")
    for lang in LANGUAGES:
        if not re.search(rf'lang\s*=\s*"{lang}"', body):
            failures.append(f'{name}: no lang="{lang}" block; one body carries en, uk and pl')
    if "Prudent" not in body:
        failures.append(f"{name}: the body never names Prudent")
    plain = [a for a in ANCHOR.findall(body) if canon(a) == LINK] if "{{" in body else []
    if not plain:
        failures.append(f"{name}: no anchor whose visible text is `{LINK}`; the plain link beside the button is missing")


def check_subject(name: str, subject: str, failures: list) -> None:
    if not subject.strip():
        failures.append(f"{name}: the subject is empty")
        return
    check_text(name, "the subject", subject, failures)
    if PLACEHOLDER.search(subject):
        failures.append(f"{name}: the subject takes a placeholder; GoTrue's subject is shown before the person trusts the mail")
    if "Prudent" not in subject:
        failures.append(f"{name}: the subject never names Prudent")
    if len(subject.split(" · ")) != len(LANGUAGES):
        failures.append(f"{name}: the subject must name {len(LANGUAGES)} languages, separated by ` · `")


def main() -> int:
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent
    config_file = root / CONFIG
    if not config_file.is_file():
        print(f"FAIL  {CONFIG} does not exist — the scope matches nothing")
        return 1
    wired = sections(config_file.read_text())
    if not wired:
        print(f"FAIL  {CONFIG} wires no [auth.email.template.*] — the scope matches nothing")
        return 1

    failures = []
    used = set()
    for name, keys in sorted(wired.items()):
        path = keys.get("content_path")
        if not path:
            failures.append(f"{name}: no content_path in {CONFIG}")
            continue
        file = (root / path).resolve()
        used.add(file)
        if not file.is_file():
            failures.append(f"{name}: content_path `{path}` does not exist")
        else:
            check_body(name, file.read_text(), failures)
        check_subject(name, keys.get("subject", ""), failures)

    directory = root / TEMPLATES
    for file in sorted(directory.glob("*.html")) if directory.is_dir() else []:
        if file.resolve() not in used:
            failures.append(f"{TEMPLATES}/{file.name} is wired by no [auth.email.template.*] in {CONFIG}")

    for line in failures:
        print(f"FAIL  {line}")
    if failures:
        print("      See ADR-079 and docs/persistent-environment.md section 3.")
        return 1
    print(f"ok    {len(wired)} templates ({', '.join(sorted(wired))}), subjects and bodies clean")
    return 0


if __name__ == "__main__":
    sys.exit(main())
