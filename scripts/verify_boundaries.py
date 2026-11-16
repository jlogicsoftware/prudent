#!/usr/bin/env python3
"""Fail if the client reaches past Prudent's own server. Run by `task verify:boundaries`.

PRUDENT'S OWN GATE, not a copy of jZen's `scripts/verify-boundaries.py` — that script's scopes
(`DART_LIB_SCOPES`, `TS_SRC_SCOPES`, `PUBSPEC_ROOTS`, ...) are module-level constants with no CLI
or env override, so it cannot be pointed at another repository (docs/prudent-migration-plan.md
§3.7, finding 2). The duplication below is deliberate — reported upstream, not worked around here.

**A scope that matches nothing is a failure, not a pass.** A renamed directory that leaves a scan
empty reads as a clean repository and reports green forever; jZen's own StaleScope guard exists
for exactly that reason, and this script keeps it.

Eight checks. A, B, C are the shape jZen's gate proves (no provider SDK; no provider host or
credential; no absolute URL outside the one compile-time base) — B additionally names Prudent's
own retired Firebase project (`firebaseio.com`, `prudent-60fcf`), which a generic "provider" scan
would not catch since Firebase Realtime Database is not an identity provider. D is Prudent's own:
no direct `package:http` import outside the composition root, and no `google_fonts`.

A, B and C ALSO run over the admin panel (`admin/src`, TypeScript), added in Phase 5. The admin
panel is a client too, by the same one-server rule — `@supabase/supabase-js` is one `pnpm add`
away and better documented than the Dart SDK, and a panel that used it would lose the session, the
roles and the enforcement point exactly as silently. Two exemptions, both named once so a
StaleScope run can still see the tree: `admin/src/api/schema.generated.ts` (generated, describes
the API rather than calling it) and `admin/src/config.ts` (the one file allowed to name the API
base — the analogue of `zen_identity_config.dart`). D does not apply to TypeScript: it names two
Dart-specific dependencies (`package:http`, `google_fonts`) that have no TypeScript equivalent.

Written to the 3.9 floor, stdlib only — Prudent has no Python elsewhere, but this is Rule-3 work
(reads source, returns a verdict), the same reasoning jZen's STANDARDS "Scripting" gives for why
its own equivalent is Python rather than sh.
"""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path

# Only the apps' own source is in scope: the server-connected app and the shared package its screens
# live in (ADR-108). Not the tests: a test double's fake server URL is not a call the product makes.
# Not `generated/`: generated code is a derived artifact, and editing it is already a defect
# `task verify:contracts` catches.
DART_LIB_SCOPES = ("client/lib", "packages/prudent_ui/lib")

# The shared package every Prudent app links, Local included (ADR-101). It must not be able to reach
# the server: no dependency on the transport or on identity, and no import of either — nor of
# `zen_ui_identity` (which renders sign-in over `zen_identity`) or `zen_secure_store` (the refresh
# token's keystore). Tests count too: a test that needs one is a test that belongs in `client/`.
SHARED_PACKAGE = "packages/prudent_ui"
SERVER_ONLY_PACKAGES = ("zen_transport", "zen_identity", "zen_ui_identity", "zen_secure_store")
GENERATED_DIR = "/generated/"

# The one file allowed to name the compile-time API base — the Dart analogue of jZen's
# `zen_identity_config.dart` exemption, which is where `zenApiUrl` itself is DEFINED (a
# `String.fromEnvironment` default literal, not a call the product makes).
CONFIG_FILE_SUFFIX = "zen_identity_config.dart"

# The composition root is the ONE place Prudent's own code may import `package:http` directly —
# it exists solely to TYPE the shared session client `createSessionClient()` returns (see
# lib/main.dart's own comment). Every actual request goes through ZenClient.
COMPOSITION_ROOT = "lib/main.dart"

# The admin panel's TypeScript scope (Phase 5). Both exemptions live directly under it, so a typo
# in either constant below shows up as the exempted file suddenly failing check B/C rather than as
# a silent no-op — there is no separate "does the exemption path exist" assertion needed.
ADMIN_SRC_SCOPE = "admin/src"
ADMIN_GENERATED_FILE = "admin/src/api/schema.generated.ts"
ADMIN_CONFIG_FILE = "admin/src/config.ts"

TS_PROVIDER_SDK = re.compile(
    r"""^\s*"(@supabase/supabase-js|gotrue-js|@supabase/postgrest-js|@supabase/realtime-js"""
    r"""|@supabase/storage-js|@supabase/functions-js|firebase|@firebase/[a-z-]+)"\s*:""",
)
TS_COMMENT = re.compile(r"^\s*//")

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
    """Every Dart library source of the apps and the shared package, generated output excluded."""
    found: "list[Path]" = []
    for scope in DART_LIB_SCOPES:
        lib_dir = root / scope
        if not lib_dir.is_dir():
            raise StaleScope(f"scope '{scope}' matched no directory under {root}")
        files = [f for f in lib_dir.rglob("*.dart") if GENERATED_DIR not in f.as_posix()]
        if not files:
            raise StaleScope(f"scope '{scope}' matched no Dart source under {root}")
        found.extend(files)
    return sorted(found)


def pubspecs(root: Path) -> "list[Path]":
    client_dir = root / "client"
    if not client_dir.is_dir():
        raise StaleScope(f"tree 'client/' does not exist under {root}")
    found = [p for p in client_dir.rglob("pubspec.yaml") if ".dart_tool" not in p.as_posix()]
    if not found:
        raise StaleScope(f"no pubspec.yaml found under 'client/' in {root}")
    shared = root / SHARED_PACKAGE / "pubspec.yaml"
    if not shared.is_file():
        raise StaleScope(f"no pubspec.yaml at '{SHARED_PACKAGE}' in {root}")
    return sorted(found + [shared])


def shared_package_sources(root: Path) -> "list[Path]":
    """The shared package's own sources and tests: what must stay free of the server."""
    found: "list[Path]" = []
    for scope in ("lib", "test"):
        d = root / SHARED_PACKAGE / scope
        if not d.is_dir():
            raise StaleScope(f"scope '{SHARED_PACKAGE}/{scope}' matched no directory under {root}")
        files = [f for f in d.rglob("*.dart") if GENERATED_DIR not in f.as_posix()]
        if not files:
            raise StaleScope(f"scope '{SHARED_PACKAGE}/{scope}' matched no Dart source under {root}")
        found.extend(files)
    return sorted(found)


def ts_sources(root: Path) -> "list[Path]":
    """Every TypeScript/TSX source under the admin panel's own scope, generated output excluded."""
    src_dir = root / ADMIN_SRC_SCOPE
    if not src_dir.is_dir():
        raise StaleScope(f"scope '{ADMIN_SRC_SCOPE}' matched no directory under {root}")
    files = [
        f
        for f in list(src_dir.rglob("*.ts")) + list(src_dir.rglob("*.tsx"))
        if f.relative_to(root).as_posix() != ADMIN_GENERATED_FILE
    ]
    if not files:
        raise StaleScope(f"scope '{ADMIN_SRC_SCOPE}' matched no TypeScript source under {root}")
    return sorted(files)


def admin_package_jsons(root: Path) -> "list[Path]":
    admin_dir = root / "admin"
    if not admin_dir.is_dir():
        raise StaleScope(f"tree 'admin/' does not exist under {root}")
    package_json = admin_dir / "package.json"
    if not package_json.is_file():
        raise StaleScope(f"no package.json found under 'admin/' in {root}")
    return [package_json]


def _scan(files: "list[Path]", root: Path, keep) -> "list[Hit]":
    hits: "list[Hit]" = []
    for f in files:
        rel = f.relative_to(root).as_posix()
        for n, text in enumerate(_read_lines(f), start=1):
            if keep(rel, text):
                hits.append(Hit(rel, n, text))
    return hits


def check_provider_sdk(root: Path) -> "list[Hit]":
    """A. No client package depends on an identity-provider SDK or on `firebase_*`/`firebase`."""
    dart_hits = _scan(pubspecs(root), root, lambda rel, t: PROVIDER_SDK.search(t) is not None)
    ts_hits = _scan(
        admin_package_jsons(root), root, lambda rel, t: TS_PROVIDER_SDK.search(t) is not None
    )
    return dart_hits + ts_hits


def check_provider_secret(root: Path) -> "list[Hit]":
    """B. No client source names a provider host or credential — Prudent's own Firebase included."""
    dart_hits = _scan(
        dart_sources(root), root, lambda rel, t: PROVIDER_SECRET.search(t) is not None
    )
    ts_hits = _scan(ts_sources(root), root, lambda rel, t: PROVIDER_SECRET.search(t) is not None)
    return dart_hits + ts_hits


def check_absolute_url(root: Path) -> "list[Hit]":
    """C. No absolute URL literal in client source, except the one compile-time base."""

    def keep_dart(rel: str, text: str) -> bool:
        if rel.endswith(CONFIG_FILE_SUFFIX) or DART_COMMENT.match(text):
            return False
        return ABSOLUTE_URL.search(text) is not None

    def keep_ts(rel: str, text: str) -> bool:
        if rel == ADMIN_CONFIG_FILE or TS_COMMENT.match(text):
            return False
        return ABSOLUTE_URL.search(text) is not None

    dart_hits = _scan(dart_sources(root), root, keep_dart)
    ts_hits = _scan(ts_sources(root), root, keep_ts)
    return dart_hits + ts_hits


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


_SERVER_ONLY = "|".join(SERVER_ONLY_PACKAGES)
SERVER_ONLY_IMPORT = re.compile(
    r"^\s*(?:import|export)\s+['\"]package:(" + _SERVER_ONLY + r")/"
)
SERVER_ONLY_DEP = re.compile(r"^[ \t]{2}(" + _SERVER_ONLY + r")[ \t]*:")


def check_shared_package_is_server_free(root: Path) -> "list[Hit]":
    """E. The shared package depends on, and imports, nothing that can reach the server."""
    import_hits = _scan(
        shared_package_sources(root), root, lambda rel, t: SERVER_ONLY_IMPORT.match(t) is not None
    )
    dep_hits = _scan(
        [root / SHARED_PACKAGE / "pubspec.yaml"],
        root,
        lambda rel, t: SERVER_ONLY_DEP.match(t) is not None,
    )
    return import_hits + dep_hits


# Prudent Local's code (ADR-101, plan unit 11): every package under `local/` — present and future —
# is built into an app that has no server, so none of them may depend on or import the server's
# packages. The list is the shared package's (ADR-108): the wrappers count as well as the two
# the plan names, since `zen_ui_identity` and `zen_secure_store` pull them in.
LOCAL_SCOPE = "local"
LOCAL_DART_DIRS = ("lib", "bin", "test", "integration_test")

# The server half of the parity harness (ADR-107) drives the LIVE server through the real transport
# and identity packages, so it needs exactly what Local must not have. It therefore lives OUTSIDE
# `local/`, in `tools/` (ADR-109) — it is a test, not Local code — and check F has no exemption.
# Nothing under `local/` may depend on it, or the transport would be one hop away.
LOCAL_SERVER_HARNESS = "prudent_parity_server"

# The core is pure Dart (ADR-101): the parity suite runs it on the plain VM, without Flutter.
LOCAL_CORE = "local/prudent_local_core"
FLUTTER_ONLY_PACKAGES = ("flutter", "flutter_test", "flutter_localizations")
LOCAL_FLUTTER_DEP = re.compile(r"^(?:flutter[ \t]*:|[ \t]+sdk[ \t]*:[ \t]*flutter\b)")
LOCAL_FLUTTER_IMPORT = re.compile(
    r"^\s*(?:import|export)\s+['\"](?:package:(?:" + "|".join(FLUTTER_ONLY_PACKAGES) + r")/|dart:ui['\"])"
)
LOCAL_FLUTTER_NAMED_DEP = re.compile(r"^[ \t]{2}(" + "|".join(FLUTTER_ONLY_PACKAGES) + r")[ \t]*:")


def local_packages(root: Path) -> "list[Path]":
    """Every package directory under `local/`: one that holds a pubspec.yaml."""
    local_dir = root / LOCAL_SCOPE
    if not local_dir.is_dir():
        raise StaleScope(f"scope '{LOCAL_SCOPE}' matched no directory under {root}")
    found = sorted(p.parent for p in local_dir.glob("*/pubspec.yaml"))
    if not found:
        raise StaleScope(f"scope '{LOCAL_SCOPE}' matched no package under {root}")
    return found


def package_sources(package: Path) -> "list[Path]":
    return sorted(
        f
        for d in LOCAL_DART_DIRS
        if (package / d).is_dir()
        for f in (package / d).rglob("*.dart")
        if GENERATED_DIR not in f.as_posix()
    )


def check_local_is_server_free(root: Path) -> "list[Hit]":
    """F. No package under `local/` depends on, or imports, anything that can reach the server —
    in `dependencies`, `dev_dependencies` or `dependency_overrides` alike (the pattern is
    section-blind on purpose: a dev dependency is in the graph the tests and the parity suite run
    in, and an override can swap a clean dependency for the transport). There is no exemption: the
    parity harness, which needs the transport, lives in `tools/` (ADR-109), and nothing under
    `local/` may depend on it."""
    packages = local_packages(root)
    sources = [f for p in packages for f in package_sources(p)]
    if not sources:
        raise StaleScope(f"scope '{LOCAL_SCOPE}' matched no Dart source under {root}")
    hits = _scan(sources, root, lambda rel, t: SERVER_ONLY_IMPORT.match(t) is not None)
    hits += _scan(
        [p / "pubspec.yaml" for p in packages],
        root,
        lambda rel, t: SERVER_ONLY_DEP.match(t) is not None,
    )
    harness_dep = re.compile(r"^[ \t]{2}" + LOCAL_SERVER_HARNESS + r"[ \t]*:")
    hits += _scan(
        [p / "pubspec.yaml" for p in packages],
        root,
        lambda rel, t: harness_dep.match(t) is not None,
    )
    return hits


def check_local_core_is_pure_dart(root: Path) -> "list[Hit]":
    """G. `local/prudent_local_core` does not depend on, or import, Flutter."""
    core = root / LOCAL_CORE
    if not (core / "pubspec.yaml").is_file():
        raise StaleScope(f"no pubspec.yaml at '{LOCAL_CORE}' in {root}")
    sources = package_sources(core)
    if not sources:
        raise StaleScope(f"scope '{LOCAL_CORE}' matched no Dart source under {root}")
    hits = _scan(sources, root, lambda rel, t: LOCAL_FLUTTER_IMPORT.match(t) is not None)
    hits += _scan(
        [core / "pubspec.yaml"],
        root,
        lambda rel, t: LOCAL_FLUTTER_DEP.match(t) is not None
        or LOCAL_FLUTTER_NAMED_DEP.match(t) is not None,
    )
    return hits


def _package_name(pubspec: Path) -> str:
    for line in _read_lines(pubspec):
        m = re.match(r"^name[ \t]*:[ \t]*([A-Za-z0-9_]+)", line)
        if m:
            return m.group(1)
    raise StaleScope(f"{pubspec} names no package")


def check_nothing_outside_local_uses_local(root: Path) -> "list[Hit]":
    """H. Nothing in `client/` or `packages/` depends on, or imports, a package under `local/`
    (ADR-101: the server-connected app and the shared package must not carry Local code, and the
    web build must not link the local store). Matched by package name and by a `path:` into
    `local/`, so a renamed dependency still shows."""
    names = [_package_name(p / "pubspec.yaml") for p in local_packages(root)]
    alt = "|".join(re.escape(n) for n in names)
    dep = re.compile(r"^[ \t]{2}(" + alt + r")[ \t]*:")
    path_into_local = re.compile(r"^[ \t]+path[ \t]*:.*(?:^|[/\\'\" ])local/")
    imp = re.compile(r"^\s*(?:import|export)\s+['\"]package:(" + alt + r")/")

    packages_dir = root / "packages"
    if not packages_dir.is_dir():
        raise StaleScope(f"scope 'packages' matched no directory under {root}")
    pkgs = sorted(p.parent for p in packages_dir.glob("*/pubspec.yaml"))
    if not pkgs:
        raise StaleScope(f"scope 'packages' matched no package under {root}")
    pubs = [p for p in pubspecs(root)] + [p / "pubspec.yaml" for p in pkgs]
    pubs = sorted({p for p in pubs})
    dart: "list[Path]" = []
    for base in [root / "client"] + pkgs:
        for d in LOCAL_DART_DIRS:
            if (base / d).is_dir():
                dart.extend(
                    f
                    for f in (base / d).rglob("*.dart")
                    if GENERATED_DIR not in f.as_posix() and ".dart_tool" not in f.as_posix()
                )
    if not dart:
        raise StaleScope(f"scopes 'client' and 'packages' matched no Dart source under {root}")
    hits = _scan(pubs, root, lambda rel, t: dep.match(t) or path_into_local.match(t))
    hits += _scan(sorted(dart), root, lambda rel, t: imp.match(t) is not None)
    return hits


CHECKS = (
    (check_provider_sdk, "a client package depends on a provider SDK or firebase_*:",
     "no client package depends on a provider SDK or firebase_*"),
    (check_provider_secret, "client code names a provider host or credential:",
     "no provider host or credential in client code"),
    (check_absolute_url, "client code hard-codes an absolute URL (the base is zenApiUrl):",
     "the only base URL in client code is the compile-time zenApiUrl"),
    (check_prudent_own, "package:http used outside the composition root, or google_fonts present:",
     "package:http stays in the composition root; google_fonts is gone"),
    (check_shared_package_is_server_free,
     "packages/prudent_ui depends on or imports the transport, identity or the keystore:",
     "packages/prudent_ui imports neither zen_transport nor zen_identity (nor what wraps them)"),
    (check_local_is_server_free,
     "a package under local/ depends on or imports the server's packages, or on the parity harness:",
     "no package under local/ reaches the server (no exemption)"),
    (check_local_core_is_pure_dart,
     "local/prudent_local_core depends on or imports Flutter:",
     "local/prudent_local_core is pure Dart"),
    (check_nothing_outside_local_uses_local,
     "client/ or packages/ depends on or imports a package under local/:",
     "client/ and packages/ name no package under local/"),
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
