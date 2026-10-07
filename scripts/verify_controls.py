#!/usr/bin/env python3
"""Fail if client screens use raw Material controls the framework replaces. Run by
`task verify:controls`.

CLAUDE.md ("Client UI: the framework's controls first") and ADR-041 say screens are built from
`zen_ui_widgets`. Until this gate existed that was a sentence: an `ElevatedButton` in a new screen
broke nothing, and the control a user reaches by keyboard, the one with the contrast and focus
treatment, silently became the one that does not have it.

THE RULE, in two parts.

1. **Banned** in `client/lib` (generated code and `l10n/` excluded): every name in
   `BANNED_CONTROLS`. Each has a `zen_ui_widgets` counterpart — `ZenButton` (all three variants),
   `ZenSelect`, `ZenSegmentedControl`, `ZenSwitchRow`, `ZenDateField` / `ZenDateRangeField`,
   `ZenTextField`, `ZenIconButton`, `ZenProgressIndicator`, `ZenPageScaffold` (for `Scaffold` and
   `AppBar`), `showZenMessage` (for `SnackBar`) — or, for `showModalBottomSheet`,
   `showAdaptivePresentation`. These are the controls that render Cupertino on iOS and macOS
   (jlogicsoftware/prudent#116): a raw Material one is Material on every platform.

2. **`showDialog` is allowed only to show an `AlertDialog`.** An acknowledgement ("that input was
   invalid — Okay") or a confirmation ("delete this account? Cancel / Delete") is a message with a
   verdict, not a form or a detail, and `zen_ui_widgets` has no counterpart for it. A form or a
   detail opens through `showAdaptivePresentation`, which is a sheet on a phone and a dialog on a
   desktop, and a `showDialog` is how a screen quietly opts out of that. So the argument of every
   `showDialog(...)` must contain an `AlertDialog(...)`, and that `AlertDialog` must not carry an
   input (`TextField`, `TextFormField`, `Form`) — an input in a dialog is a form wearing a
   confirmation's name.

THE EXPLICIT CARVE-OUTS, written down so none of them is implied:

* **Where a counterpart exists but lacks one capability, the carve-out is that capability and
  nothing else** (`CARVE_OUTS`). Each is the one thing the framework control cannot do today, each
  is a gap reported upstream (docs/jzen/README.md), and each goes the day the control gains it:
  a `TextField` / `TextFormField` that asks for `maxLines` / `minLines` (`ZenTextField` is single
  line); an `IconButton` that carries a `Badge` (`ZenIconButton` takes an icon only); a `SnackBar`
  that carries an `action` (`showZenMessage` has none — an undo is the only use); and `Scaffold` /
  `AppBar` in a file that calls `showSnackBar`, because a snack bar needs a `Scaffold` to appear on
  and `ZenPageScaffold` has none on Apple platforms. What an exemption carries is therefore
  checked, not assumed: the same widget without that capability is still a violation.

* `AlertDialog` itself, for the two uses above. What it carries: a title, a message and the verdict
  buttons. What would be lost by forcing it onto `showAdaptivePresentation`: a confirmation turned
  into a bottom sheet on a phone, which is a different and worse interaction for "are you sure".
  Its buttons are `ZenButton`s like any others — the carve-out covers the *dialog*, not a raw
  `TextButton` inside it, so `TextButton` stays banned everywhere.
* `PopupMenuButton`. It is not in the banned list and nothing here inspects it: a menu of verbs
  (the goal screen's lifecycle actions) has no counterpart in the package.

Nothing else is exempt, and there is no allowlist of files. A file that needs one is a framework gap
to report upstream (CLAUDE.md, "A control the package lacks is a framework gap"), not an entry here.

**A scope that matches nothing is a failure, not a pass** — the same StaleScope guard
`verify_boundaries.py` keeps, for the same reason: a renamed directory would read as a clean tree
forever.

Comments and string literals are masked before matching, so prose that names a banned control (a
doc comment explaining why `ZenButton` replaces `TextButton`) is not a violation and code never
hides inside a string. Written to Python 3.9, the CI floor.
"""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path

CLIENT_LIB_SCOPE = "client/lib"
# Generated output is a derived artifact; l10n holds generated accessors and .arb files.
EXCLUDED_DIRS = ("generated", "l10n")

BANNED_CONTROLS = (
    "ElevatedButton",
    "FilledButton",
    "OutlinedButton",
    "TextButton",
    "DropdownButton",
    "DropdownButtonFormField",
    "SegmentedButton",
    "SwitchListTile",
    "showDatePicker",
    "showDateRangePicker",
    "showModalBottomSheet",
    "TextField",
    "TextFormField",
    "IconButton",
    "CircularProgressIndicator",
    "Scaffold",
    "AppBar",
    "SnackBar",
)
BANNED = re.compile(r"\b(" + "|".join(BANNED_CONTROLS) + r")\b")

_MULTILINE = re.compile(r"\b(maxLines|minLines)\s*:")
# control -> ("call" | "file", pattern): the one capability its framework counterpart lacks. "call"
# looks inside the control's own argument list, "file" anywhere in the masked file.
CARVE_OUTS = {
    "TextField": ("call", _MULTILINE),
    "TextFormField": ("call", _MULTILINE),
    "IconButton": ("call", re.compile(r"\bBadge\(")),
    "SnackBar": ("call", re.compile(r"\baction\s*:")),
    "Scaffold": ("file", re.compile(r"\bshowSnackBar\b")),
    "AppBar": ("file", re.compile(r"\bshowSnackBar\b")),
}
SHOW_DIALOG = re.compile(r"\bshowDialog\b")
ALERT_DIALOG = re.compile(r"\bAlertDialog\b")
INPUT_IN_DIALOG = re.compile(r"\b(TextField|TextFormField|ZenTextField|Form)\b")


class StaleScope(Exception):
    """A scan pattern matched nothing — the gate cannot vouch for a tree it never read."""


@dataclass(frozen=True)
class Hit:
    path: str
    line: int
    text: str

    def __str__(self) -> str:
        return f"{self.path}:{self.line}:{self.text}"


def repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


def dart_sources(root: Path) -> "list[Path]":
    lib_dir = root / CLIENT_LIB_SCOPE
    if not lib_dir.is_dir():
        raise StaleScope(f"scope '{CLIENT_LIB_SCOPE}' matched no directory under {root}")
    files = [
        f
        for f in lib_dir.rglob("*.dart")
        if not any(part in EXCLUDED_DIRS for part in f.relative_to(lib_dir).parts[:-1])
    ]
    if not files:
        raise StaleScope(f"scope '{CLIENT_LIB_SCOPE}' matched no Dart source under {root}")
    return sorted(files)


def mask(source: str) -> str:
    """Blank out comments and string literals, keeping every newline and every code character in
    place, so offsets and line numbers of the remaining code are unchanged.

    Code inside a `${...}` interpolation is code and is kept.
    """
    out = list(source)
    n = len(source)

    def blank(a: int, b: int) -> None:
        for k in range(a, b):
            if out[k] != "\n":
                out[k] = " "

    def code(i: int, until_brace: bool) -> int:
        """Scan code from i. Stops at the `}` closing an interpolation when until_brace."""
        depth = 0
        while i < n:
            c = source[i]
            if c == "/" and source.startswith("//", i):
                j = source.find("\n", i)
                j = n if j == -1 else j
                blank(i, j)
                i = j
            elif c == "/" and source.startswith("/*", i):
                # Dart block comments nest.
                j, level = i + 2, 1
                while j < n and level:
                    if source.startswith("/*", j):
                        level, j = level + 1, j + 2
                    elif source.startswith("*/", j):
                        level, j = level - 1, j + 2
                    else:
                        j += 1
                blank(i, j)
                i = j
            elif c in "'\"":
                raw = i > 0 and source[i - 1] == "r" and _is_raw_prefix(source, i - 1)
                i = string(i, raw)
            elif c == "{":
                depth += 1
                i += 1
            elif c == "}":
                if until_brace and depth == 0:
                    return i
                depth -= 1
                i += 1
            else:
                i += 1
        return i

    def string(i: int, raw: bool) -> int:
        quote = source[i]
        triple = source.startswith(quote * 3, i)
        delim = quote * 3 if triple else quote
        start = i
        i += len(delim)
        while i < n:
            if source.startswith(delim, i):
                i += len(delim)
                blank(start, i)
                return i
            c = source[i]
            if c == "\\" and not raw:
                i += 2
            elif c == "\n" and not triple:
                # An unterminated single-line string is not valid Dart; stop rather than swallow
                # the rest of the file and under-report.
                blank(start, i)
                return i
            elif c == "$" and not raw and source.startswith("${", i):
                blank(start, i + 2)
                i = code(i + 2, until_brace=True)
                # `i` is at the interpolation's closing brace; the string body resumes after it.
                start = i
                i += 1
            else:
                i += 1
        blank(start, n)
        return n

    code(0, until_brace=False)
    return "".join(out)


def _is_raw_prefix(source: str, i: int) -> bool:
    """`r'...'` is a raw string only when the `r` is not the tail of an identifier."""
    return i == 0 or not (source[i - 1].isalnum() or source[i - 1] in "_$")


def _skip_ws(code: str, i: int) -> int:
    while i < len(code) and code[i].isspace():
        i += 1
    return i


def _matching(code: str, i: int, open_ch: str, close_ch: str) -> int:
    """Index of the bracket closing the one at `i`, or -1."""
    depth = 0
    for j in range(i, len(code)):
        if code[j] == open_ch:
            depth += 1
        elif code[j] == close_ch:
            depth -= 1
            if depth == 0:
                return j
    return -1


def call_span(code: str, name_end: int) -> "tuple[int, int] | None":
    """The `( ... )` argument span of a call whose name ends at `name_end`, skipping a generic
    argument list (`showDialog<bool>(`). None for a bare reference such as a tear-off."""
    i = _skip_ws(code, name_end)
    if i < len(code) and code[i] == "<":
        close = _matching(code, i, "<", ">")
        if close == -1:
            return None
        i = _skip_ws(code, close + 1)
    if i >= len(code) or code[i] != "(":
        return None
    close = _matching(code, i, "(", ")")
    return None if close == -1 else (i, close)


def _line_of(source: str, offset: int) -> int:
    return source.count("\n", 0, offset) + 1


def scan_file(rel: str, source: str) -> "list[Hit]":
    code = mask(source)
    lines = source.splitlines()
    hits: "list[Hit]" = []

    def add(offset: int, why: str) -> None:
        line = _line_of(source, offset)
        shown = lines[line - 1].strip() if line <= len(lines) else ""
        hits.append(Hit(rel, line, f"{why}  [{shown}]"))

    for m in BANNED.finditer(code):
        name = m.group(1)
        carve = CARVE_OUTS.get(name)
        if carve:
            kind, pattern = carve
            if kind == "file":
                scope = code
            else:
                span = call_span(code, m.end())
                scope = code[span[0] : span[1] + 1] if span else ""
            if pattern.search(scope):
                continue
        add(m.start(), f"{name} is a raw Material control")

    for m in SHOW_DIALOG.finditer(code):
        span = call_span(code, m.end())
        body = code[span[0] : span[1] + 1] if span else ""
        if span is None or not ALERT_DIALOG.search(body):
            add(m.start(), "showDialog shows something other than an AlertDialog")
            continue
        for a in ALERT_DIALOG.finditer(body):
            alert = call_span(body, a.end())
            alert_body = body[alert[0] : alert[1] + 1] if alert else ""
            inp = INPUT_IN_DIALOG.search(alert_body)
            if inp:
                add(
                    m.start() + a.start(),
                    f"AlertDialog carries an input ({inp.group(1)}); a form opens through "
                    "showAdaptivePresentation",
                )
    return hits


def scan(root: Path) -> "list[Hit]":
    hits: "list[Hit]" = []
    for f in dart_sources(root):
        rel = f.relative_to(root).as_posix()
        hits.extend(scan_file(rel, f.read_text(encoding="utf-8", errors="replace")))
    return hits


def main(root: "Path | None" = None) -> int:
    root = root or repo_root()
    print("Checking client screens for raw Material controls...")
    try:
        hits = scan(root)
    except StaleScope as e:
        print(f"  FAIL the scan is stale and checked nothing: {e}")
        return 1

    if not hits:
        print("  ok   no raw Material control in client/lib")
        print()
        print("Controls intact: client screens are built from zen_ui_widgets.")
        return 0

    print("  FAIL client code uses raw Material controls:")
    for h in hits:
        print(f"       {h}")
    print()
    print("Use the zen_ui_widgets control instead (ZenButton, ZenSelect, ZenSegmentedControl,")
    print("ZenSwitchRow, ZenDateField / ZenDateRangeField, ZenTextField, ZenIconButton,")
    print("ZenProgressIndicator, ZenPageScaffold, showZenMessage, showAdaptivePresentation). A control the")
    print("package lacks is a framework gap to report upstream, not an exemption to add here.")
    print("See CLAUDE.md 'Client UI: the framework's controls first' and ADR-041.")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
