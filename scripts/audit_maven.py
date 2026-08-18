#!/usr/bin/env python3
"""Fail if any Java dependency Prudent ships has a known CVE. Run by `task audit:server`.

PRUDENT'S OWN SCRIPT, in the same shape as jZen's `scripts/audit-maven.py` (which is not
app-agnostic: it is invoked from jZen's own root Taskfile.yml against zen_demo's paths, not
reusable through the include this repository consumes — docs/prudent-migration-plan.md §3.7).
Written fresh rather than copied, per CLAUDE.md "jZen is a dependency, not a donor".

WHY THIS ASKS OSV DIRECTLY RATHER THAN A MAVEN PLUGIN — the same two failure modes jZen measured
apply here unchanged: `ossindex-maven-plugin` answers an anonymous request with 401 and lets the
build SUCCEED regardless (a vacuous gate), and `dependency-check-maven` needs an NVD API key that
cannot be committed. So Maven only resolves the dependency tree (`mvn dependency:list`); this
script understands the result and queries the OSV database (api.osv.dev), which needs no key.

WHY THIS STANDS OUTSIDE `task test`. It asks a REMOTE service a question that changes when
nothing in this repository changed — a new advisory published overnight must not turn `task test`
red on an unrelated PR. It fails on a finding AND fails when it cannot reach the database:
CLAUDE.md "nothing swallows a failure" applies to "we could not check" exactly as it does to a
failed assertion, because a script that reports clean when it never actually asked is worse than
one that fails loudly.

Suppressions live in scripts/audit-suppressions.txt, one `<ADVISORY-ID>  <reason>` per line — the
reason is not optional, and a line without one is a parse error, not a silent skip.
"""

from __future__ import annotations

import json
import re
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path

OSV_BATCH_URL = "https://api.osv.dev/v1/querybatch"
OSV_VULN_URL = "https://api.osv.dev/v1/vulns/{id}"

# `mvn dependency:list` emits lines like:
#   "[INFO]    org.postgresql:postgresql:jar:42.7.4:runtime"
#   "[INFO]    zen:zen-core:jar:0.1.0-SNAPSHOT:compile -- module zen.core (auto)"
# — an "[INFO]" prefix (unless -q suppressed it), no tree characters (unlike dependency:tree),
# and sometimes a trailing "-- module ..." JPMS comment. The pattern is searched rather than
# anchored to the whole line for that reason. Header/footer lines ("The following files have been
# resolved:") do not match and are skipped rather than erroring, since this script is fed the raw
# combined mvn output.
DEPENDENCY_LINE = re.compile(
    r"([\w.\-]+):([\w.\-]+):[\w.\-]+:([\w.\-]+):(?:compile|runtime|provided|test|system|import)\b"
)

SUPPRESSIONS_PATH = Path(__file__).resolve().parent / "audit-suppressions.txt"


@dataclass(frozen=True)
class MavenDependency:
    group_id: str
    artifact_id: str
    version: str

    @property
    def osv_name(self) -> str:
        return f"{self.group_id}:{self.artifact_id}"


def parse_dependencies(text: str) -> "list[MavenDependency]":
    seen: "set[tuple[str, str, str]]" = set()
    deps: "list[MavenDependency]" = []
    for line in text.splitlines():
        m = DEPENDENCY_LINE.search(line)
        if not m:
            continue
        group_id, artifact_id, version = m.groups()
        key = (group_id, artifact_id, version)
        if key in seen:
            continue
        seen.add(key)
        deps.append(MavenDependency(group_id, artifact_id, version))
    return deps


def load_suppressions(path: Path) -> "dict[str, str]":
    if not path.is_file():
        return {}
    suppressions: "dict[str, str]" = {}
    for lineno, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split(None, 1)
        if len(parts) != 2:
            raise ValueError(
                f"{path}:{lineno}: suppression has no reason — "
                f"every entry must be '<ADVISORY-ID>  <reason>': {raw!r}"
            )
        advisory_id, reason = parts
        suppressions[advisory_id] = reason
    return suppressions


def query_osv_batch(deps: "list[MavenDependency]") -> "dict[MavenDependency, list[str]]":
    if not deps:
        return {}
    body = json.dumps(
        {
            "queries": [
                {"package": {"name": d.osv_name, "ecosystem": "Maven"}, "version": d.version}
                for d in deps
            ]
        }
    ).encode("utf-8")
    req = urllib.request.Request(
        OSV_BATCH_URL, data=body, headers={"Content-Type": "application/json"}, method="POST"
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            payload = json.loads(resp.read())
    except (urllib.error.URLError, TimeoutError) as e:
        raise RuntimeError(f"could not reach {OSV_BATCH_URL}: {e}") from e
    results = payload.get("results", [])
    if len(results) != len(deps):
        raise RuntimeError(
            f"OSV returned {len(results)} results for {len(deps)} queries — response shape "
            "changed; refusing to silently under-check."
        )
    findings: "dict[MavenDependency, list[str]]" = {}
    for dep, result in zip(deps, results):
        ids = [v["id"] for v in result.get("vulns", [])]
        if ids:
            findings[dep] = ids
    return findings


def main(argv: "list[str]") -> int:
    if len(argv) != 2:
        print(f"usage: {argv[0]} <dependency-list-file>", file=sys.stderr)
        return 2
    text = Path(argv[1]).read_text(encoding="utf-8")
    deps = parse_dependencies(text)
    if not deps:
        print("No Maven dependencies parsed from the input — refusing to report success having "
              "checked nothing.", file=sys.stderr)
        return 1

    try:
        suppressions = load_suppressions(SUPPRESSIONS_PATH)
    except ValueError as e:
        print(str(e), file=sys.stderr)
        return 1

    try:
        findings = query_osv_batch(deps)
    except RuntimeError as e:
        print(f"AUDIT FAILED (could not check): {e}", file=sys.stderr)
        return 1

    failed = False
    for dep, ids in sorted(findings.items(), key=lambda kv: kv[0].osv_name):
        unsuppressed = [i for i in ids if i not in suppressions]
        if not unsuppressed:
            continue
        failed = True
        print(f"  FAIL {dep.osv_name}:{dep.version}", file=sys.stderr)
        for vid in unsuppressed:
            print(f"       {vid}  ({OSV_VULN_URL.format(id=vid)})", file=sys.stderr)

    if failed:
        print(file=sys.stderr)
        print(
            f"Checked {len(deps)} Java dependencies against OSV. Unsuppressed findings above.",
            file=sys.stderr,
        )
        print(
            "Suppress only with a reason in scripts/audit-suppressions.txt, or upgrade the "
            "dependency.",
            file=sys.stderr,
        )
        return 1

    print(f"Checked {len(deps)} Java dependencies against OSV. No unsuppressed findings.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
