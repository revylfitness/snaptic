#!/usr/bin/env bash
# Repository lints that catch whole classes of compile and safety problems
# before the (slow) macOS build runs. Runs on Linux and macOS.
set -euo pipefail
cd "$(dirname "$0")/.."

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

exit $status
