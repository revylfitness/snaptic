#!/usr/bin/env bash
# Builds Snaptic.app from source.
#
#   ./scripts/build-app.sh                     # build for this Mac (ad hoc, without Sparkle: it can't update itself)
#   ARCHS="arm64 x86_64" ./scripts/build-app.sh   # universal build (needs full Xcode)
#   SIGN_IDENTITY="Developer ID Application: You (TEAMID)" ./scripts/build-app.sh   # also embeds and signs Sparkle
#   INSTALL=1 ./scripts/build-app.sh           # also install to /Applications, owned by root (asks for your password)
#   RELEASE_BUNDLE=1 ./scripts/build-app.sh    # CI: also build/release/Snaptic.app, unsigned, with Sparkle
#
# Sparkle (PLAN 0.3.1 E2, E4) is weak-linked: an ad hoc build has no Team ID, so the hardened runtime's library
# validation would refuse the framework, and the app runs without it. Only a build signed with a real identity
# (Developer ID, or Apple Development for testing) carries Sparkle and can update itself.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
FLAGS=(-c "$CONFIG")
if [[ -n "${ARCHS:-}" ]]; then
  read -r -a ARCH_LIST <<< "$ARCHS"
  for arch in "${ARCH_LIST[@]}"; do
    [[ "$arch" =~ ^(arm64|x86_64)$ ]] || { echo "Unsupported arch: $arch" >&2; exit 1; }
    FLAGS+=(--arch "$arch")
  done
fi

IDENTITY="${SIGN_IDENTITY:--}"
if [[ "${RELEASE_BUNDLE:-0}" == "1" && "$IDENTITY" != "-" ]]; then
  # The release bundle is signed only by CI's sign job, from the ad hoc build's binary.
  echo "RELEASE_BUNDLE=1 builds an unsigned bundle; don't combine it with SIGN_IDENTITY." >&2
  exit 1
fi

echo "==> Compiling ($CONFIG)"
swift build "${FLAGS[@]}"
BIN_DIR="$(swift build "${FLAGS[@]}" --show-bin-path)"

# The Sparkle framework from the SwiftPM binary target (exact 2.10.0; SwiftPM verified the artifact's checksum).
sparkle_framework() {
  local found=()
  while IFS= read -r -d '' path; do found+=("$path"); done < <(
    find .build/artifacts -type d -path '*/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework' -print0 2>/dev/null)
  if [[ ${#found[@]} -ne 1 ]]; then
    echo "Expected exactly one Sparkle.framework under .build/artifacts, found ${#found[@]}." >&2
    return 1
  fi
  printf '%s\n' "${found[0]}"
}

# The executable must reference Sparkle only through LC_LOAD_WEAK_DYLIB, in every architecture.
check_weak_link() {
  local bin="$1" commands
  commands="$(otool -arch all -l "$bin")"
  if ! awk '
      $1 == "cmd" { cmd = $2 }
      $1 == "name" && index($2, "@rpath/Sparkle.framework/") == 1 { if (cmd == "LC_LOAD_WEAK_DYLIB") weak++; else strong++ }
      END { exit !(weak > 0 && strong == 0) }' <<< "$commands"; then
    echo "$bin must load @rpath/Sparkle.framework weakly (LC_LOAD_WEAK_DYLIB) and never strongly." >&2
    return 1
  fi
}

# Copies Sparkle into the bundle, drops the XPC services (only sandboxed apps need them), and adds the rpath that
# finds Contents/Frameworks. Nothing here signs.
embed_sparkle() {
  local app="$1" framework
  framework="$(sparkle_framework)"
  mkdir -p "$app/Contents/Frameworks"
  ditto "$framework" "$app/Contents/Frameworks/Sparkle.framework"
  rm -rf "$app/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices"
  rm -f "$app/Contents/Frameworks/Sparkle.framework/XPCServices"
  if [[ -e "$app/Contents/Frameworks/Sparkle.framework/XPCServices" || -L "$app/Contents/Frameworks/Sparkle.framework/XPCServices" ]]; then
    echo "Sparkle's XPCServices are still in $app." >&2
    return 1
  fi
  install_name_tool -add_rpath @executable_path/../Frameworks "$app/Contents/MacOS/Snaptic"
  local commands
  commands="$(otool -arch all -l "$app/Contents/MacOS/Snaptic")"
  if ! awk '
      $1 == "cmd" { cmd = $2 }
      cmd == "LC_RPATH" && $1 == "path" && $2 == "@executable_path/../Frameworks" { found++ }
      END { exit !(found > 0) }' <<< "$commands"; then
    echo "The @executable_path/../Frameworks rpath is missing from $app." >&2
    return 1
  fi
  check_weak_link "$app/Contents/MacOS/Snaptic"
}

assemble() {
  local app="$1"
  rm -rf "$app"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
  cp "$BIN_DIR/Snaptic" "$app/Contents/MacOS/Snaptic"
  cp Resources/Info.plist "$app/Contents/Info.plist"
  # MIT asks that the notices travel with the bundled code (Sparkle in release builds).
  cp THIRD_PARTY_NOTICES.md "$app/Contents/Resources/THIRD_PARTY_NOTICES.md"
}

check_weak_link "$BIN_DIR/Snaptic"

APP="build/Snaptic.app"
echo "==> Assembling $APP"
assemble "$APP"

echo "==> Signing (identity: $IDENTITY)"
# Always use the hardened runtime: it stops other programs from injecting code
# (DYLD_INSERT_LIBRARIES) into Snaptic and inheriting its Accessibility and
# Screen Recording permissions. Never add entitlements that weaken it.
if [[ "$IDENTITY" == "-" ]]; then
  codesign --force --options runtime --sign - "$APP"
else
  # A real identity has a Team ID, so library validation accepts a Sparkle signed by the same team. Inside out, no
  # --deep (Sparkle's documentation): Autoupdate, Updater.app, the framework, then the app.
  embed_sparkle "$APP"
  TIMESTAMP=(--timestamp=none)
  [[ "$IDENTITY" == "Developer ID Application: "* ]] && TIMESTAMP=(--timestamp)
  SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
  for item in "$SPARKLE/Versions/B/Autoupdate" "$SPARKLE/Versions/B/Updater.app" "$SPARKLE" "$APP"; do
    codesign --force --options runtime "${TIMESTAMP[@]}" --sign "$IDENTITY" "$item"
  done
fi
codesign --verify --strict --deep "$APP"
# Capture first: piping into `grep -q` under pipefail fails spuriously when
# grep stops reading early.
SIGNATURE_INFO="$(codesign -d --verbose=2 "$APP" 2>&1)"
if ! grep -q 'flags=.*runtime' <<< "$SIGNATURE_INFO"; then
  echo "Hardened runtime is missing from the signature; refusing to continue." >&2
  exit 1
fi
ENTITLEMENTS="$(codesign -d --entitlements - --xml "$APP" 2>/dev/null || true)"
if grep -q '<key>' <<< "$ENTITLEMENTS"; then
  echo "Snaptic must have no entitlements; refusing to continue." >&2
  exit 1
fi

if [[ "${RELEASE_BUNDLE:-0}" == "1" ]]; then
  # E3: the same binary with Sparkle embedded, never run or signed here (CI's sign job signs it; rehearse signs a
  # copy ad hoc on every push).
  RELEASE_APP="build/release/Snaptic.app"
  echo "==> Assembling $RELEASE_APP (unsigned, with Sparkle)"
  mkdir -p build/release
  assemble "$RELEASE_APP"
  embed_sparkle "$RELEASE_APP"
fi

if [[ "${INSTALL:-0}" == "1" ]]; then
  # Root-owned so another process running as you can't swap the binary that holds
  # your Accessibility/Screen Recording grants (PLAN R5.7). Sparkle then asks for an
  # administrator password for every update (PLAN 0.3.1 E8).
  echo "==> Installing to /Applications (root-owned; sudo will ask for your password)"
  pkill -x Snaptic 2>/dev/null || true
  sudo rm -rf /Applications/Snaptic.app
  sudo ditto "$APP" /Applications/Snaptic.app
  sudo chown -R root:wheel /Applications/Snaptic.app
  sudo chmod -R go-w /Applications/Snaptic.app
  echo "Done. Open /Applications/Snaptic.app"
else
  echo "Done. Open $APP"
fi
