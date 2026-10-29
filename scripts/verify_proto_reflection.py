#!/usr/bin/env python3
"""Fail if the native-image reflection list and the proto contract disagree. Run by
`task verify:reflection`.

`server/src/main/java/prudent/proto/PrudentProtoReflection.java` lists every generated message and enum so a
native image keeps the accessors canonical proto3 JSON reads by reflection. A message missing from
that list is invisible to every check that does not run authenticated JSON against a native build:
the service starts, answers /health, rejects with 401, and returns 500 for the first screen a
signed-in user opens (found on the first persistent deploy, #46). This gate makes the list follow
the contract instead of memory.

Two failures, both fatal: a `message` or `enum` declared in `proto/prudent/v1/*.proto` that the class does not
name, and a class named in the list that no `.proto` declares any more. A scope that matches nothing
(no proto files, no entries) is a failure, not a pass.

Usage: verify_proto_reflection.py [REPO_ROOT]   (default: the repository this script lives in)
Stdlib only, 3.9 floor.
"""
import re
import sys
from pathlib import Path

PROTO_GLOB = "proto/prudent/v1/*.proto"
REFLECTION = "server/src/main/java/prudent/proto/PrudentProtoReflection.java"


def main() -> int:
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent
    declared = set()
    files = sorted(root.glob(PROTO_GLOB))
    for f in files:
        declared |= set(re.findall(r"^(?:message|enum)\s+(\w+)", f.read_text(), re.M))
    path = root / REFLECTION
    if not files or not declared:
        print(f"FAIL  no proto messages or enums found under {PROTO_GLOB} — the scope matches nothing")
        return 1
    if not path.is_file():
        print(f"FAIL  {REFLECTION} does not exist")
        return 1
    # Only the annotation's targets: the `X.class,` lines, not prose in the class comment.
    registered = set(re.findall(r"^\s+(\w+)\.class,?\s*$", path.read_text(), re.M))
    if not registered:
        print(f"FAIL  {REFLECTION} names no classes — the scope matches nothing")
        return 1

    missing = sorted(declared - registered)
    stale = sorted(registered - declared)
    for name in missing:
        print(f"FAIL  type {name} is declared in proto but not registered in {REFLECTION}")
    for name in stale:
        print(f"FAIL  {name} is registered in {REFLECTION} but no .proto declares it")
    if missing or stale:
        return 1
    print(f"ok    {len(declared)} proto messages and enums, all registered for native reflection")
    return 0


if __name__ == "__main__":
    sys.exit(main())
