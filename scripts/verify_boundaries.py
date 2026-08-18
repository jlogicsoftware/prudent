#!/usr/bin/env python3
"""Fail if the client reaches past Prudent's own server. Run by `task verify:boundaries`.

PRUDENT'S OWN GATE, not a copy of jZen's `scripts/verify-boundaries.py` — that script's scopes
(`DART_LIB_SCOPES`, `TS_SRC_SCOPES`, `PUBSPEC_ROOTS`, ...) are module-level constants with no CLI
or env override, so it cannot be pointed at another repository (docs/prudent-migration-plan.md
§3.7, finding 2). The duplication below is deliberate — reported upstream, not worked around here.

**A scope that matches nothing is a failure, not a pass.** A renamed directory that leaves a scan
empty reads as a clean repository and reports green forever; jZen's own StaleScope guard exists
for exactly that reason, and this script keeps it.

Four checks. A, B, C are the shape jZen's gate proves (no provider SDK; no provider host or
credential; no absolute URL outside the one compile-time base) — B additionally names Prudent's
own retired Firebase project (`firebaseio.com`, `prudent-60fcf`), which a generic "provider" scan
would not catch since Firebase Realtime Database is not an identity provider. D is Prudent's own:
no direct `package:http` import outside the composition root, and no `google_fonts`.

Written to the 3.9 floor, stdlib only — Prudent has no Python elsewhere, but this is Rule-3 work
(reads source, returns a verdict), the same reasoning jZen's STANDARDS "Scripting" gives for why
its own equivalent is Python rather than sh.
"""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path

# Only the client's own source is in scope. Not `client/test`: a test double's fake server URL is
# not a call the product makes. Not `client/lib/src/generated`: generated code is a derived
# artifact, and editing it is already a defect `task sync:contracts` catches.
CLIENT_LIB_SCOPE = "client/lib"
GENERATED_DIR = "/generated/"

# The one file allowed to name the compile-time API base — the Dart analogue of jZen's
# `zen_identity_config.dart` exemption, which is where `zenApiUrl` itself is DEFINED (a
# `String.fromEnvironment` default literal, not a call the product makes).
CONFIG_FILE_SUFFIX = "zen_identity_config.dart"

# The composition root is the ONE place Prudent's own code may import `package:http` directly —
# it exists solely to TYPE the shared session client `createSessionClient()` returns (see
# lib/main.dart's own comment). Every actual request goes through ZenClient.
COMPOSITION_ROOT = "lib/main.dart"

PROVIDER_SDK = re.compile(
    r"^[ \t]{2}(supabase|gotrue|postgrest|realtime_client|storage_client|functions_client"
    r"|firebase[a-z_]*)[a-z_]*[ \t]*:"
)
PROVIDER_SECRET = re.compile(
    r"supabase\.co|:54321|apikey|anon_key|service_role|SUPABASE_(URL|KEY)"
    # Prudent's own retired backend (docs/DECISIONS.md ADR-004): the project this client used to
    # talk to directly, before the one-server rule was enforced by construction rather than by
    # convention.
    r"|firebaseio\.com|prudent-60fcf",
    re.IGNORECASE,
)
ABSOLUTE_URL = re.compile(r"['\"]https?://")
DART_COMMENT = re.compile(r"^\s*//")
HTTP_IMPORT = re.compile(r"""^\s*import\s+['"]package:http/http\.dart['"]""")
GOOGLE_FONTS_IMPORT = re.compile(r"""^\s*import\s+['"]package:google_fonts/""")
GOOGLE_FONTS_DEP = re.compile(r"^[ \t]{2}google_fonts[ \t]*:")


class StaleScope(Exception):
    """A scan pattern matched nothing — the gate cannot vouch for a tree it never read."""


@dataclass(frozen=True)
class Hit:
    path: str
    line: int
    text: str

    def __str__(self) -> str:
        return f"{self.path}:{self.line}:{self.text.strip()}"


def repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


def _read_lines(path: Path) -> "list[str]":
    return path.read_text(encoding="utf-8", errors="replace").splitlines()


def dart_sources(root: Path) -> "list[Path]":
    """Every Dart library source under the client tier, generated output excluded."""
    lib_dir = root / CLIENT_LIB_SCOPE
    if not lib_dir.is_dir():
        raise StaleScope(f"scope '{CLIENT_LIB_SCOPE}' matched no directory under {root}")
    files = [f for f in lib_dir.rglob("*.dart") if GENERATED_DIR not in f.as_posix()]
    if not files:
        raise StaleScope(f"scope '{CLIENT_LIB_SCOPE}' matched no Dart source under {root}")
    return sorted(files)


def pubspecs(root: Path) -> "list[Path]":
    client_dir = root / "client"
    if not client_dir.is_dir():
        raise StaleScope(f"tree 'client/' does not exist under {root}")
    found = [p for p in client_dir.rglob("pubspec.yaml") if ".dart_tool" not in p.as_posix()]
    if not found:
        raise StaleScope(f"no pubspec.yaml found under 'client/' in {root}")
    return sorted(found)


def _scan(files: "list[Path]", root: Path, keep) -> "list[Hit]":
    hits: "list[Hit]" = []
    for f in files:
        rel = f.relative_to(root).as_posix()
        for n, text in enumerate(_read_lines(f), start=1):
            if keep(rel, text):
                hits.append(Hit(rel, n, text))
    return hits


def check_provider_sdk(root: Path) -> "list[Hit]":
    """A. No client package depends on an identity-provider SDK or on `firebase_*`."""
    return _scan(pubspecs(root), root, lambda rel, t: PROVIDER_SDK.search(t) is not None)


def check_provider_secret(root: Path) -> "list[Hit]":
    """B. No client source names a provider host or credential — Prudent's own Firebase included."""
    return _scan(dart_sources(root), root, lambda rel, t: PROVIDER_SECRET.search(t) is not None)


def check_absolute_url(root: Path) -> "list[Hit]":
    """C. No absolute URL literal in client source, except the one compile-time base."""

    def keep(rel: str, text: str) -> bool:
        if rel.endswith(CONFIG_FILE_SUFFIX) or DART_COMMENT.match(text):
            return False
        return ABSOLUTE_URL.search(text) is not None

    return _scan(dart_sources(root), root, keep)


def check_prudent_own(root: Path) -> "list[Hit]":
    """D. Prudent's own: no direct `package:http` import outside the composition root, and no
    `google_fonts` anywhere (dependency or import)."""

    def keep_http(rel: str, text: str) -> bool:
        if rel == COMPOSITION_ROOT:
            return False
        return HTTP_IMPORT.match(text) is not None

    http_hits = _scan(dart_sources(root), root, keep_http)
    font_import_hits = _scan(
        dart_sources(root), root, lambda rel, t: GOOGLE_FONTS_IMPORT.match(t) is not None
    )
    font_dep_hits = _scan(
        pubspecs(root), root, lambda rel, t: GOOGLE_FONTS_DEP.match(t) is not None
    )
    return http_hits + font_import_hits + font_dep_hits


CHECKS = (
    (check_provider_sdk, "a client package depends on a provider SDK or firebase_*:",
     "no client package depends on a provider SDK or firebase_*"),
    (check_provider_secret, "client code names a provider host or credential:",
     "no provider host or credential in client code"),
    (check_absolute_url, "client code hard-codes an absolute URL (the base is zenApiUrl):",
     "the only base URL in client code is the compile-time zenApiUrl"),
    (check_prudent_own, "package:http used outside the composition root, or google_fonts present:",
     "package:http stays in the composition root; google_fonts is gone"),
)


def ok(msg: str) -> None:
    print(f"  ok   {msg}")


def fail(msg: str, hits: "list[str] | None" = None) -> None:
    print(f"  FAIL {msg}")
    for hit in hits or []:
        print(f"       {hit}")


def main(root: "Path | None" = None) -> int:
    root = root or repo_root()
    print("Checking the client/server boundary...")

    failed = False
    for check, bad, good in CHECKS:
        try:
            hits = check(root)
        except StaleScope as e:
            fail(f"the scan is stale and checked nothing: {e}")
            failed = True
            continue
        if hits:
            fail(bad, [str(h) for h in hits])
            failed = True
        else:
            ok(good)

    print()
    if not failed:
        print("Boundary intact: the client talks to Prudent's server and nothing else.")
        return 0
    print("The client/server boundary is broken. Prudent's server is the ONLY thing a client may")
    print("call: it is where a session is minted, where Supabase's credentials live, and where")
    print("rows are scoped to the caller. See CLAUDE.md 'The client talks to one server'.")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
