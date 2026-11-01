#!/usr/bin/env python3
"""Tests for english_guard.py. Run: python3 test_english_guard.py

Non-English text is built from \\u escapes so this file stays ASCII.
"""
import json, os, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
GUARD = os.path.join(HERE, "english_guard.py")
FAILURES = []

RU = "\u041f\u0440\u0438\u0432\u0435\u0442 \u043c\u0438\u0440"          # Russian greeting
RU_ONLY = "\u044d\u0442\u043e"                                          # contains a Russian-only letter
UK = "\u0412\u0430\u0448\u0456 \u0434\u0430\u043d\u0456"                # Ukrainian, no Russian-only letters


def check(name, cond, detail=""):
    print(("  ok   " if cond else "  FAIL ") + name + ("" if cond else " " + str(detail)))
    if not cond:
        FAILURES.append(name)


def run(root, payload):
    payload = {"cwd": root, **payload}
    env = dict(os.environ, CLAUDE_PROJECT_DIR=root)
    p = subprocess.run([sys.executable, GUARD], input=json.dumps(payload),
                       capture_output=True, text=True, env=env)
    return p.returncode, p.stderr


def write(root, rel, content):
    return {"tool_name": "Write", "tool_input": {"file_path": os.path.join(root, rel), "content": content}}


def edit(root, rel, new):
    return {"tool_name": "Edit", "tool_input": {"file_path": os.path.join(root, rel), "old_string": "x", "new_string": new}}


def bash(cmd):
    return {"tool_name": "Bash", "tool_input": {"command": cmd}}


with tempfile.TemporaryDirectory() as root:
    os.makedirs(os.path.join(root, ".claude", "hooks"))
    with open(os.path.join(root, ".claude", "hooks", "english-rules.json"), "w") as fh:
        json.dump({"locale_paths": ["client/lib/l10n/*_uk.arb", "client/test/*"]}, fh)

    print("files")
    rc, err = run(root, write(root, "docs/a.md", "# Title\n\nPlain English.\n"))
    check("english doc passes", rc == 0, err)
    rc, err = run(root, write(root, "docs/a.md", "# Title\n\n" + RU))
    check("russian doc is blocked", rc == 2 and "docs/a.md" in err and "line 3" in err, err)
    rc, err = run(root, write(root, "docs/a.md", "# Title\n\n" + UK))
    check("ukrainian doc is blocked outside locale paths", rc == 2, err)
    rc, err = run(root, edit(root, "client/lib/foo.dart", "// " + RU))
    check("russian comment in code is blocked", rc == 2, err)
    rc, err = run(root, {"tool_name": "MultiEdit", "tool_input": {
        "file_path": os.path.join(root, "a.md"),
        "edits": [{"old_string": "a", "new_string": "ok"}, {"old_string": "b", "new_string": RU}]}})
    check("multiedit checks every edit", rc == 2, err)
    rc, err = run(root, {"tool_name": "NotebookEdit", "tool_input": {
        "notebook_path": os.path.join(root, "n.ipynb"), "new_source": RU}})
    check("notebook edit is checked", rc == 2, err)
    rc, err = run(root, write(root, "docs/pl.md", "Zażółć gęślą jaźń"))
    check("polish diacritics pass", rc == 0, err)

    print("locale paths")
    rc, err = run(root, write(root, "client/lib/l10n/prudent_uk.arb", '{"a": "' + UK + '"}'))
    check("ukrainian in the uk arb passes", rc == 0, err)
    rc, err = run(root, write(root, "client/lib/l10n/prudent_uk.arb", '{"a": "' + RU_ONLY + '"}'))
    check("russian-only letters in the uk arb are blocked", rc == 2 and "Russian-only" in err, err)
    rc, err = run(root, write(root, "client/lib/l10n/prudent_en.arb", '{"a": "' + UK + '"}'))
    check("ukrainian in the en arb is blocked", rc == 2, err)
    rc, err = run(root, edit(root, "client/test/x_test.dart", "expect(find.text('" + UK + "'))"))
    check("ukrainian fixture in a test passes", rc == 0, err)

    print("bash")
    rc, err = run(root, bash("ls -la"))
    check("unrelated command passes", rc == 0, err)
    rc, err = run(root, bash('echo "' + RU + '"'))
    check("non-publishing command with cyrillic is not inspected", rc == 0, err)
    rc, err = run(root, bash('gh issue create --title "Bug" --body "Plain English"'))
    check("english issue passes", rc == 0, err)
    rc, err = run(root, bash('gh issue create --title "' + RU + '" --body "x"'))
    check("russian issue title is blocked", rc == 2, err)
    rc, err = run(root, bash("gh pr create --title T --body-file - <<'EOF'\n" + RU + "\nEOF"))
    check("russian heredoc body is blocked", rc == 2, err)
    rc, err = run(root, bash('gh issue comment 5 --body "' + RU + '"'))
    check("russian comment is blocked", rc == 2, err)
    rc, err = run(root, bash('gh issue edit 5 --title "' + UK + '"'))
    check("ukrainian issue text is blocked", rc == 2, err)
    with open(os.path.join(root, "body.md"), "w", encoding="utf-8") as fh:
        fh.write("## Heading\n\n" + RU + "\n")
    rc, err = run(root, bash("gh pr create --title T --body-file body.md"))
    check("russian --body-file is blocked", rc == 2, err)
    with open(os.path.join(root, "ok.md"), "w") as fh:
        fh.write("## Heading\n\nEnglish\n")
    rc, err = run(root, bash("gh pr create --title T --body-file ok.md"))
    check("english --body-file passes", rc == 0, err)
    rc, err = run(root, bash('gh api repos/o/r/issues/1 -X PATCH -f body="' + RU + '"'))
    check("gh api write with cyrillic is blocked", rc == 2, err)
    rc, err = run(root, bash('gh issue view 5 --json body'))
    check("reading an issue is not inspected", rc == 0, err)

    print("robustness")
    p = subprocess.run([sys.executable, GUARD], input="not json", capture_output=True, text=True)
    check("malformed payload never blocks", p.returncode == 0)

print()
if FAILURES:
    print(f"{len(FAILURES)} FAILED: {FAILURES}")
    sys.exit(1)
print("all tests passed")
