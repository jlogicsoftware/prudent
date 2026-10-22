#!/usr/bin/env python3
"""Proves scripts/verify_proto_reflection.py can fail. Run by `task verify:reflection` first.

A gate that stopped matching would read green forever, so each test builds a throwaway tree and
requires the verdict it should give.
"""
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "verify_proto_reflection.py"


def run(proto: str, java: str | None) -> subprocess.CompletedProcess:
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        (root / "proto/prudent/v1").mkdir(parents=True)
        (root / "proto/prudent/v1/a.proto").write_text(proto)
        if java is not None:
            p = root / "server/src/main/java/prudent/proto"
            p.mkdir(parents=True)
            (p / "PrudentProtoReflection.java").write_text(java)
        return subprocess.run([sys.executable, "-I", str(SCRIPT), str(root)], capture_output=True, text=True)


def java(*names: str) -> str:
    body = "".join(f"      {n}.class,\n" for n in names)
    return "// mentions Ghost.class, in prose, which is not a target\n@RegisterForReflection(\n    targets = {\n" + body + "    })\nclass X {}\n"


class Gate(unittest.TestCase):
    def test_agreement_passes(self):
        r = run("message A {}\nmessage B {}\nenum E {}\n", java("A", "B"))
        self.assertEqual(r.returncode, 0, r.stdout)

    def test_unregistered_message_fails(self):
        r = run("message A {}\nmessage B {}\n", java("A"))
        self.assertEqual(r.returncode, 1)
        self.assertIn("message B", r.stdout)

    def test_stale_entry_fails(self):
        r = run("message A {}\n", java("A", "Gone"))
        self.assertEqual(r.returncode, 1)
        self.assertIn("Gone", r.stdout)

    def test_missing_class_file_fails(self):
        self.assertEqual(run("message A {}\n", None).returncode, 1)

    def test_empty_scope_fails(self):
        self.assertEqual(run("// no messages\n", java("A")).returncode, 1)
        self.assertEqual(run("message A {}\n", java()).returncode, 1)


if __name__ == "__main__":
    unittest.main()
