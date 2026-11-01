#!/usr/bin/env python3
"""Keep everything this repository publishes in English.

Documentation, code comments, issues, pull requests and commit messages are
English only. The one thing that is not English on purpose is the product's
Ukrainian localisation (Prudent ships en, uk and pl), so Cyrillic cannot be
banned outright -- it has to be banned *except* where it is locale data.

Two tiers, both read from .claude/hooks/english-rules.json:

  * anywhere else, any Cyrillic letter in text being written is refused;
  * in `locale_paths` (the Ukrainian strings and the tests that assert them)
    Cyrillic is allowed, but the letters Russian has and Ukrainian does not
    (yery, e, hard sign, yo) are refused. That cannot prove a line is Ukrainian, but a
    Russian sentence that avoids all four is rare, and it stops the common
    case of Russian prose sneaking into a locale file or a test.

It runs as a Claude Code PreToolUse hook and checks only what is being
*added*, so editing a file that already holds locale text is not blocked:

  * Edit / Write / MultiEdit / NotebookEdit -- the new content;
  * Bash -- a `gh` command that publishes text (issue, pr, release create /
    edit / comment / review, `gh api` writes), including a literal
    --body-file / -F path.

Commit messages are checked in git_guard.py, which already extracts them and
also runs as a git commit-msg hook.

Limit: a Bash command that writes a file through a redirect (`cat > f <<EOF`)
is not inspected; use Write or Edit, which are.
"""

from __future__ import annotations

import fnmatch
import json
import os
import re
import shlex
import sys

# Cyrillic, Cyrillic Supplement, and the extended blocks.
CYRILLIC = re.compile("[\u0400-\u052f\u1c80-\u1c8f\u2de0-\u2dff\ua640-\ua69f]")
# Letters of Russian that Ukrainian does not use.
RUSSIAN_ONLY = re.compile("[\u044b\u044d\u044a\u0451\u042b\u042d\u042a\u0401]")

DEFAULTS = {"locale_paths": []}

# A `gh` call that publishes text under the user's name.
GH_PUBLISH = re.compile(
    r"\bgh\s+(?:issue|pr|release|discussion)\s+(?:create|edit|comment|review|close|reopen)\b"
    r"|\bgh\s+api\b[^|;&\n]*(?:-X|--method)\s*=?\s*(?:POST|PATCH|PUT)\b",
    re.IGNORECASE,
)
BODY_FILE_FLAGS = ("--body-file", "-F", "--notes-file")


def load_rules(root: str) -> dict:
    rules = dict(DEFAULTS)
    path = os.path.join(root, ".claude", "hooks", "english-rules.json")
    try:
        with open(path, encoding="utf-8") as fh:
            rules.update(json.load(fh))
    except FileNotFoundError:
        pass
    except (OSError, ValueError) as exc:
        # A broken config must not silently disable the guard.
        print(f"english-rules.json is unreadable ({exc}); no locale paths allowed.", file=sys.stderr)
    return rules


def is_locale_path(rel: str, rules: dict) -> bool:
    return any(fnmatch.fnmatch(rel, pat) for pat in rules.get("locale_paths", []))


def first_offence(text: str, locale: bool) -> tuple[int, str] | None:
    """Line number and text of the first line that breaks the rule, or None."""
    pattern = RUSSIAN_ONLY if locale else CYRILLIC
    for number, line in enumerate(text.split("\n"), start=1):
        if pattern.search(line):
            return number, line.strip()
    return None


def written_texts(payload: dict) -> list[str]:
    tool = payload.get("tool_name")
    data = payload.get("tool_input") or {}
    if tool == "Write":
        return [data.get("content") or ""]
    if tool == "Edit":
        return [data.get("new_string") or ""]
    if tool == "MultiEdit":
        return [(e or {}).get("new_string") or "" for e in data.get("edits") or []]
    if tool == "NotebookEdit":
        return [data.get("new_source") or ""]
    return []


def body_files(command: str, cwd: str) -> list[str]:
    """Contents of literal --body-file / -F paths in `command`."""
    try:
        tokens = shlex.split(command, comments=True)
    except ValueError:
        tokens = command.split()
    texts: list[str] = []
    for i, tok in enumerate(tokens):
        path = None
        if tok in BODY_FILE_FLAGS and i + 1 < len(tokens):
            path = tokens[i + 1]
        elif tok.startswith("--body-file="):
            path = tok.split("=", 1)[1]
        if not path or path == "-" or any(ch in path for ch in "$`*?"):
            continue
        full = path if os.path.isabs(path) else os.path.join(cwd, path)
        try:
            with open(full, encoding="utf-8") as fh:
                texts.append(fh.read())
        except OSError:
            continue
    return texts


def refuse(lines: list[str]) -> int:
    print("Blocked by the English-only guard (.claude/hooks/english_guard.py):\n", file=sys.stderr)
    for line in lines:
        print(f"  {line}", file=sys.stderr)
    print(
        "\nEverything this repository publishes is English: docs, comments, issues,\n"
        "PRs and commit messages. Translate it and retry. Ukrainian is allowed only\n"
        "as product localisation (see locale_paths in english-rules.json).",
        file=sys.stderr,
    )
    return 2


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except (ValueError, OSError):
        return 0  # never break the session over a malformed payload

    cwd = payload.get("cwd") or os.getcwd()
    root = os.environ.get("CLAUDE_PROJECT_DIR") or cwd
    rules = load_rules(root)
    tool = payload.get("tool_name")
    data = payload.get("tool_input") or {}

    if tool == "Bash":
        command = data.get("command") or ""
        if not GH_PUBLISH.search(command):
            return 0
        for text in [command, *body_files(command, cwd)]:
            hit = first_offence(text, locale=False)
            if hit:
                return refuse([f"This `gh` command would publish non-English text, line {hit[0]}:", f"    {hit[1][:120]}"])
        return 0

    path = data.get("file_path") or data.get("notebook_path") or ""
    if not path:
        return 0
    rel = os.path.relpath(path, root) if os.path.isabs(path) else path
    locale = is_locale_path(rel, rules)
    for text in written_texts(payload):
        hit = first_offence(text, locale)
        if hit:
            what = "Russian-only letters (yery, e, hard sign, yo) in a locale file" if locale else "Cyrillic text"
            return refuse([f"{rel}: {what}, line {hit[0]} of the new content:", f"    {hit[1][:120]}"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
