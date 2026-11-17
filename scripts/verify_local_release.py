#!/usr/bin/env python3
"""Fail when Prudent Local's release rules (ADR-100 T10, T18; plan unit 11) are broken.
Run by `task verify:local-release`.

Four checks over the tree, each failing on a real violation and on a scope that matches nothing:

  A. Android refuses Auto Backup of the store (T10). The app's manifest sets
     `android:allowBackup="false"` and `android:fullBackupContent="false"`, names no
     `android:dataExtractionRules` (the Android 12 route a backup takes), and the debug and profile
     manifests do not set any of them back. Pass the MERGED manifests a build produced
     (`--merged PATH`, repeatable) and they are held to the same rule: a plugin's manifest is merged
     in and can turn a backup back on without the app's own file changing.
  B. `ZEN_SYNC` has one reader (T18). jZen's `ZenSyncPlan` refuses the define in a release build;
     that refusal holds only while nothing else reads the define and decides for itself. No Dart
     source under client/, packages/ or local/ calls `String.fromEnvironment('ZEN_SYNC'...)` or
     names `ZEN_SYNC_FOLDER` that way, so the framework's refusal is the only one there is. Not
     duplicated here, and not bypassable by a second reader.
  C. No CI workflow sets `ZEN_SYNC`. A workflow that baked it in would build the unencrypted
     development transport on the runner that makes the release artifacts.
  D. Prudent Local has no web runner (jZen ADR-073): no `web/` directory beside its other runners.

Usage: verify_local_release.py [--merged MANIFEST]... [REPO_ROOT]
Stdlib only, 3.9 floor.
"""
import re
import sys
from pathlib import Path

APP = "local/prudent_local_client"
MANIFESTS = (
    f"{APP}/android/app/src/main/AndroidManifest.xml",
    f"{APP}/android/app/src/debug/AndroidManifest.xml",
    f"{APP}/android/app/src/profile/AndroidManifest.xml",
)
MAIN_MANIFEST = MANIFESTS[0]
DART_ROOTS = ("client", "packages", "local")
WORKFLOWS = ".github/workflows"

ATTR = r'android:{name}\s*=\s*"([^"]*)"'
ZEN_SYNC_READ = re.compile(r"""fromEnvironment\(\s*['"]ZEN_SYNC""")
DART_COMMENT = re.compile(r"^\s*//")


def attribute(text: str, name: str):
    m = re.search(ATTR.format(name=name), text)
    return m.group(1) if m else None


def check_manifest(label: str, text: str, main: bool) -> "list[str]":
    """The main manifest must refuse backup outright; any other must not undo it."""
    problems = []
    for name, want in (("allowBackup", "false"), ("fullBackupContent", "false")):
        got = attribute(text, name)
        if main and got != want:
            problems.append(f'{label}: android:{name} is {got!r}, must be "{want}" (T10)')
        elif not main and got not in (None, want):
            problems.append(f'{label}: android:{name}="{got}" turns Auto Backup back on (T10)')
    if attribute(text, "dataExtractionRules") is not None:
        problems.append(f"{label}: android:dataExtractionRules names a backup or transfer rule set (T10)")
    # A merge directive that lets another manifest win over the app's own refusal.
    if re.search(r'tools:replace\s*=\s*"[^"]*(allowBackup|fullBackupContent|dataExtractionRules)', text):
        problems.append(f"{label}: tools:replace overrides a backup attribute (T10)")
    return problems


def check_android(root: Path, merged: "list[Path]") -> "list[str]":
    problems = []
    main = root / MAIN_MANIFEST
    if not main.is_file():
        return [f"{MAIN_MANIFEST} does not exist — the scope matches nothing"]
    for rel in MANIFESTS:
        path = root / rel
        if path.is_file():
            problems += check_manifest(rel, path.read_text(), rel == MAIN_MANIFEST)
    for path in merged:
        if not path.is_file():
            problems.append(f"merged manifest {path} does not exist — a build did not produce it")
            continue
        text = path.read_text()
        if "<application" not in text:
            problems.append(f"merged manifest {path} has no <application> — it is not a merged manifest")
            continue
        problems += check_manifest(f"merged manifest {path}", text, True)
    return problems


def check_zen_sync_reader(root: Path) -> "list[str]":
    problems = []
    scanned = 0
    for top in DART_ROOTS:
        for path in sorted((root / top).rglob("*.dart")):
            if any(part in (".dart_tool", "build", "generated") for part in path.parts):
                continue
            scanned += 1
            for number, line in enumerate(path.read_text().splitlines(), 1):
                if DART_COMMENT.match(line):
                    continue
                if ZEN_SYNC_READ.search(line):
                    problems.append(
                        f"{path.relative_to(root)}:{number} reads ZEN_SYNC itself — only jZen's "
                        "ZenSyncPlan may, so its release refusal is the one refusal (T18)")
    if scanned == 0:
        problems.append("no Dart source found under client/, packages/ or local/ — the scope matches nothing")
    return problems


def check_workflows(root: Path) -> "list[str]":
    flows = sorted((root / WORKFLOWS).glob("*.yml"))
    if not flows:
        return [f"{WORKFLOWS} has no workflow — the scope matches nothing"]
    return [f"{f.relative_to(root)}:{n} mentions ZEN_SYNC — CI must not build the development transport (T18)"
            for f in flows
            for n, line in enumerate(f.read_text().splitlines(), 1)
            if "ZEN_SYNC" in line and not line.lstrip().startswith("#")]


def check_no_web(root: Path) -> "list[str]":
    app = root / APP
    if not (app / "android").is_dir():
        return [f"{APP}/android does not exist — the scope matches nothing"]
    return [f"{APP}/web exists — a Local application has no web target (jZen ADR-073)"] if (app / "web").exists() else []


def main(argv: "list[str]") -> int:
    merged: "list[Path]" = []
    positional = []
    it = iter(argv)
    for arg in it:
        if arg == "--merged":
            merged.append(Path(next(it)))
        else:
            positional.append(arg)
    root = Path(positional[0]) if positional else Path(__file__).resolve().parent.parent
    checks = (
        ("Android refuses Auto Backup (T10)", check_android(root, merged)),
        ("ZEN_SYNC has one reader, jZen's (T18)", check_zen_sync_reader(root)),
        ("no workflow sets ZEN_SYNC (T18)", check_workflows(root)),
        ("no web runner", check_no_web(root)),
    )
    failed = False
    for title, problems in checks:
        if problems:
            failed = True
            for p in problems:
                print(f"FAIL  {p}")
        else:
            print(f"ok    {title}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
