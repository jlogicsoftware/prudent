#!/usr/bin/env python3
"""Fail if CocoaPods has come back to an Apple runner. Run by `task verify:swiftpm`.

Prudent's iOS and macOS runners resolve every native dependency through Swift Package Manager
(ADR-083). Flutter falls back to CocoaPods for any plugin that has no Swift package, and when it
does it writes a `Podfile`, adds the `[CP]` build phases to the Xcode project and starts running
`pod install` on every build. That is a second build description beside SwiftPM, and it arrives
silently: the build stays green. This gate turns it into a red build instead.

It fails on, in each runner: a `Podfile` or `Podfile.lock`; a `Pods/` directory; a `Pods-Runner`
or `[CP]` reference in the Xcode project; a `Pods/` include in a Flutter `.xcconfig`; and a
`Pods/` project in the workspace. A scope that matches nothing (a runner or its project missing)
is a failure, not a pass.

Usage: verify_no_cocoapods.py [REPO_ROOT]   (default: the repository this script lives in)
Stdlib only, 3.9 floor.
"""
import re
import sys
from pathlib import Path

RUNNERS = ("client/ios", "client/macos")
FILES = ("Podfile", "Podfile.lock")
# What CocoaPods leaves in a file Xcode reads. `Pods_Runner` is the framework it links.
TRACES = re.compile(r"Pods-Runner|Pods_Runner|\[CP\]|\bPods/")


def main() -> int:
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent
    failures = []
    for runner in RUNNERS:
        base = root / runner
        project = base / "Runner.xcodeproj" / "project.pbxproj"
        if not project.is_file():
            print(f"FAIL  {runner}/Runner.xcodeproj/project.pbxproj does not exist — the scope matches nothing")
            return 1
        for name in FILES:
            if (base / name).exists():
                failures.append(f"{runner}/{name} exists — a plugin without a Swift package brought CocoaPods back")
        if (base / "Pods").exists():
            failures.append(f"{runner}/Pods exists")
        scanned = [project, *sorted((base / "Flutter").glob("*.xcconfig")),
                   base / "Runner.xcworkspace" / "contents.xcworkspacedata"]
        for f in scanned:
            if f.is_file() and TRACES.search(f.read_text()):
                failures.append(f"{f.relative_to(root)} refers to CocoaPods")
    for line in failures:
        print(f"FAIL  {line}")
    if failures:
        print("      Run `flutter pub deps` / `flutter build` to see which plugin has no Swift package; "
              "see docs/native-iphone-build.md.")
        return 1
    print(f"ok    {len(RUNNERS)} runners, no CocoaPods")
    return 0


if __name__ == "__main__":
    sys.exit(main())
