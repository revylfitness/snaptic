#!/usr/bin/env bash
# Builds Snaptic.app from source.
#
#   ./scripts/build-app.sh                     # build for this Mac
#   ARCHS="arm64 x86_64" ./scripts/build-app.sh   # universal build (needs full Xcode)
#   SIGN_IDENTITY="Apple Development: You (TEAMID)" ./scripts/build-app.sh
#   INSTALL=1 ./scripts/build-app.sh           # also install to /Applications, owned by root (asks for your password)
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

echo "==> Compiling ($CONFIG)"
swift build "${FLAGS[@]}"
BIN_DIR="$(swift build "${FLAGS[@]}" --show-bin-path)"

APP="build/Snaptic.app"
echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Snaptic" "$APP/Contents/MacOS/Snaptic"
cp Resources/Info.plist "$APP/Contents/Info.plist"

IDENTITY="${SIGN_IDENTITY:--}"
echo "==> Signing (identity: $IDENTITY)"
# Always use the hardened runtime: it stops other programs from injecting code
# (DYLD_INSERT_LIBRARIES) into Snaptic and inheriting its Accessibility and
# Screen Recording permissions. Never add entitlements that weaken it.
codesign --force --options runtime --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"
# Capture first: piping into `grep -q` under pipefail fails spuriously when
# grep stops reading early.
SIGNATURE_INFO="$(codesign -d --verbose=2 "$APP" 2>&1)"
if ! grep -q 'flags=.*runtime' <<< "$SIGNATURE_INFO"; then
  echo "Hardened runtime is missing from the signature; refusing to continue." >&2
  exit 1
fi

if [[ "${INSTALL:-0}" == "1" ]]; then
  # Root-owned so another process running as you can't swap the binary that holds
  # your Accessibility/Screen Recording grants (PLAN R5.7).
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
