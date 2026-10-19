#!/usr/bin/env bash
# Repository lints that catch whole classes of compile and safety problems
# before the (slow) macOS build runs. Runs on Linux and macOS.
set -euo pipefail
cd "$(dirname "$0")/.."

# 0.3 options: --write-ratchet regenerates scripts/lint-legacy.tsv from the tree (lead only);
# --strict also fails on ratchet rows whose count went down (CI from the 0.3 step-3 exit on).
LINT_MODE=check
LINT_STRICT=0
for arg in "$@"; do
    case "$arg" in
        --write-ratchet) LINT_MODE=write ;;
        --strict) LINT_STRICT=1 ;;
        *) echo "usage: lint.sh [--strict] [--write-ratchet]" >&2; exit 64 ;;
    esac
done
export LINT_MODE LINT_STRICT

status=0
fail() { echo "lint: $*" >&2; status=1; }

# 1. Unique file basenames per target directory (Swift rejects duplicates in a
#    module; duplicate .m basenames collide as object files).
for dir in Sources/Snaptic Sources/SnapticKit Sources/SnapticShims Tests/SnapticKitTests; do
    [ -d "$dir" ] || continue
    dups=$(find "$dir" \( -name '*.swift' -o -name '*.m' \) -exec basename {} \; | sed 's/\.[^.]*$//' | sort | uniq -d)
    [ -z "$dups" ] || fail "duplicate basenames in $dir: $dups"
done

# 2. Patterns banned everywhere in our sources.
banned='@_silgen_name|#if arch|#Preview|@Observable|@Entry|URLSession|NWConnection|import Network'
if grep -rnE "$banned" Sources Tests --include='*.swift' --include='*.m' --include='*.h'; then
    fail "banned pattern found (see above)"
fi
if grep -nE 'resources:' Package.swift; then
    fail "Package.swift must not declare resources (build-app.sh doesn't copy SwiftPM bundles)"
fi

# 3. SnapticKit must stay Foundation-only and build on Linux with Swift 5.10.
kitbanned='import (AppKit|CoreGraphics|CryptoKit|SwiftUI|Combine|IOKit|os)\b|\.formatted\(|FormatStyle|String\(localized:|Logger\(|os_log|OSAllocatedUnfairLock|URL\(filePath:|\.withLock|Bundle\.module'
if grep -rnE "$kitbanned" Sources/SnapticKit Tests/SnapticKitTests; then
    fail "SnapticKit must be Foundation-only and Linux-compatible (see above)"
fi

# 4. Every SnapticKit declaration that other modules use must be `package`.
#    Cheap heuristic: no top-level internal types in Kit.
if grep -rnE '^(struct|enum|class|protocol|func|extension [A-Za-z]+ *: |let|var) ' Sources/SnapticKit; then
    fail "top-level SnapticKit declarations must be 'package' (see above)"
fi

# 5. No private Apple frameworks linked by name.
if grep -nE 'linkedFramework\("(SkyLight|CoreDisplay|DisplayServices|MonitorPanel|OSD|CoreBrightness)"' Package.swift; then
    fail "private frameworks must be loaded at runtime, never linked"
fi

# 6. scripts/stubs.tsv and the tree match both ways (PLAN §13, R5.1).
python3 - <<'PY' || status=1
import os, sys
listed = set()
for line in open("scripts/stubs.tsv"):
    line = line.rstrip("\n")
    if not line or line.startswith("#"):
        continue
    path, owner, kind = line.split("\t")[:3]
    listed.add(path)
    if kind == "K4":
        d, f = os.path.split(path)
        listed.add(os.path.join(d, "include", f[:-2] + ".h"))
bad = 0
for p in sorted(listed):
    if not os.path.exists(p):
        print(f"lint: {p} is in scripts/stubs.tsv but missing", file=sys.stderr); bad = 1
for root in ("Sources", "Tests"):
    for dirpath, _, files in os.walk(root):
        for f in files:
            if f.endswith((".swift", ".m", ".h")):
                p = os.path.join(dirpath, f)
                if p not in listed:
                    print(f"lint: {p} is not listed in scripts/stubs.tsv", file=sys.stderr); bad = 1
sys.exit(bad)
PY

# 7. Crash/deadlock patterns (R3C m5). FileHandle.write raises ObjC exceptions;
#    readLine/waitUntilExit/waitpid(-1)/main.sync block or reap the wrong child.
if grep -rnE 'FileHandle|readLine\(|waitpid\(-1|waitUntilExit|DispatchQueue\.main\.sync|main\.sync\b' Sources --include='*.swift'; then
    fail "banned blocking/exception-prone API (see above); use HelperPipeWriter / LineSplitter / HelperSpawner"
fi
# Any spelling of a shared instance: `static let shared`, `static var shared: T`, `class var sharedInstance`, ….
if grep -rnE '\b(static|class)[[:space:]]+(let|var)[[:space:]]+(shared|sharedInstance|instance)\b' Sources/Snaptic/Displays --include='*.swift'; then
    fail "no singletons in Displays (rule 7); reach services through DisplaysContext"
fi
if grep -rnE 'passUnretained\(self\)' Sources/Snaptic/Displays --include='*.swift'; then
    fail "C callbacks in Displays use CallbackTarget, never passUnretained(self)"
fi

# 8. Logging rule (R5.7): no print/NSLog outside the CLI client.
if grep -rnE '\bprint\(|NSLog\(' Sources --include='*.swift' | grep -v '^Sources/Snaptic/Core/CLIClient.swift:'; then
    fail "print/NSLog are only allowed in CLIClient.swift (use EventLog)"
fi

# 9. Helper, CLI and self-test code never touches TCC-guarded APIs (R5.5).
tcc='AXIsProcessTrusted|CGRequestScreenCaptureAccess|CGPreflight|SCShareableContent|SCStream|AXUIElement'
for f in Sources/Snaptic/Safety/DisplayGuardMain.swift Sources/Snaptic/Displays/Safety/DisplayGuardMain.swift \
         Sources/Snaptic/Displays/Management/VirtualHostMain.swift Sources/Snaptic/Core/CLIClient.swift \
         Sources/Snaptic/Core/SelfTest.swift Sources/Snaptic/Core/SelfTestLaunch.swift \
         Sources/Snaptic/Core/HelperPrologue.swift; do
    [ -f "$f" ] || continue
    if grep -nE "$tcc" "$f"; then fail "$f must not reference TCC-guarded APIs"; fi
done

# 10. Extensions of types declared in another file are fileprivate/private (rule 4).
#     SharedExtensions.swift is the shared home; PrivateSymbol ids are open by design.
python3 - <<'PY' || status=1
import os, re, sys
# Only top-level declarations count (a nested `struct State` must not exempt `extension State` of another type);
# attributes may take arguments (`@available(macOS 14.4, *) extension NSMenuItem`).
attrs = r'(?:@\w+(?:\([^)]*\))?\s+)*'
decl = re.compile(r'^' + attrs + r'(?:public |package |internal |fileprivate |private )?(?:final )?(?:class|struct|enum|protocol|actor)\s+(\w+)')
ext = re.compile(r'^\s*' + attrs + r'(?:(fileprivate|private)\s+|(?:public|package|internal)\s+)?extension\s+([\w.]+)')
exempt = {"PrivateSymbol"}
bad = 0
for dirpath, _, files in os.walk("Sources/Snaptic"):
    for f in files:
        if not f.endswith(".swift") or f == "SharedExtensions.swift":
            continue
        p = os.path.join(dirpath, f)
        lines = open(p, encoding="utf-8").read().splitlines()
        declared = {m.group(1) for l in lines if (m := decl.match(l))}
        for n, l in enumerate(lines, 1):
            m = ext.match(l)
            if not m or m.group(1):
                continue
            base = m.group(2).split(".")[0]
            if base in declared or base in exempt:
                continue
            print(f"lint: {p}:{n}: extension of {base} (declared elsewhere) must be fileprivate", file=sys.stderr)
            bad = 1
sys.exit(bad)
PY

# 11. Private symbol lookups only in PrivateDisplayAPI, the switcher's PrivateAPIs and
#     the shims (so kill switches and availability can't be bypassed).
if grep -rnE '\bdlsym\(|\bdlopen\(|NSClassFromString|NSSelectorFromString' Sources/Snaptic --include='*.swift' \
    | grep -vE '^Sources/Snaptic/(Displays/Platform/PrivateDisplayAPI|Switcher/PrivateAPIs)\.swift:'; then
    fail "private symbol lookup outside PrivateDisplayAPI.swift (see above)"
fi

# 12. Processes are spawned only by HelperSpawner (Swift) and SNSpawn (shim); no in-process script runners either
#     (0.3.1 B6: lid-closed mode goes through HelperSpawner.spawnAdminScript and /usr/bin/osascript only).
if grep -rnE '\bProcess\(|NSTask|posix_spawn|\bpopen\(|[^.]\bsystem\(|\bfork\(|execv|NSAppleScript|NSUserScriptTask|OSAScript' \
    Sources --include='*.swift' --include='*.m' \
    | grep -vE '^Sources/(Snaptic/Core/HelperSpawner\.swift|SnapticShims/SNSpawn\.m):'; then
    fail "process spawning outside HelperSpawner/SNSpawn (see above)"
fi

# 13. No traps or ad-hoc logging (rule 8, R5.7).
if grep -rnE '\bfatalError\(|\bpreconditionFailure\(|\btry!|\bdebugPrint\(|\bdump\(|os_log|\bLogger\(' Sources --include='*.swift'; then
    fail "fatalError/preconditionFailure/try!/debugPrint/dump/os_log/Logger are banned (use safe returns and EventLog)"
fi

# 14. PLAN 0.3 §6.3 lints L1–L17 (L3, L8, L11 were dropped) and PLAN 0.3.1's L18, L19 and workflow rules. L1–L14
#     are ratcheted by scripts/lint-legacy.tsv (rule, path, occurrences, permanent|step); L15–L19 have no ratchet.
python3 scripts/lint03.py || status=1

exit $status
