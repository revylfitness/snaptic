#!/usr/bin/env bash
# Packs a built Snaptic.app into a disk image people open and drag to Applications.
#
#   ./scripts/build-app.sh && ./scripts/make-dmg.sh            # writes build/Snaptic.dmg
#   ./scripts/make-dmg.sh path/to/Snaptic.app out/Snaptic.dmg
#
# The image holds the app and a shortcut to /Applications, nothing else. It is
# compressed (UDZO) and read-only; the app inside keeps its own signature.
set -euo pipefail

cd "$(dirname "$0")/.."

APP="${1:-build/Snaptic.app}"
OUT="${2:-build/Snaptic.dmg}"

if [[ ! -d "$APP" ]]; then
  echo "make-dmg: $APP not found; run ./scripts/build-app.sh first" >&2
  exit 1
fi
codesign --verify --strict "$APP" || { echo "make-dmg: $APP fails signature verification" >&2; exit 1; }

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/snaptic-dmg.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

ditto "$APP" "$STAGE/Snaptic.app"
ln -s /Applications "$STAGE/Applications"

mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
hdiutil create -volname "Snaptic" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$OUT" >/dev/null
hdiutil verify "$OUT" >/dev/null

echo "make-dmg: wrote $OUT"
