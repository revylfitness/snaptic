#!/usr/bin/env bash
# Regenerate the committed app icon from its SVG master. Requires macOS,
# Python with CairoSVG, and Cairo (brew install cairo).
# Normal app builds use the committed .icns and need no image tooling.
set -euo pipefail
cd "$(dirname "$0")/.."

command -v iconutil >/dev/null || { echo "Icon generation requires macOS iconutil." >&2; exit 1; }
# Invoke the actual Python binary: Apple's /usr/bin launcher strips DYLD paths.
PYTHON_BIN="$(python3 -c 'import sys; print(sys.executable)')"
if command -v brew >/dev/null; then
  export DYLD_FALLBACK_LIBRARY_PATH="$(brew --prefix)/lib${DYLD_FALLBACK_LIBRARY_PATH:+:$DYLD_FALLBACK_LIBRARY_PATH}"
fi

ICONSET="build/AppIcon.iconset"
mkdir -p "$ICONSET"
# Render at twice the master resolution, then downsample for smooth curves.
"$PYTHON_BIN" -m cairosvg Resources/AppIcon.svg -s 2 -o build/AppIcon-2048.png
sips -z 1024 1024 build/AppIcon-2048.png --out Resources/AppIcon.png >/dev/null
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" Resources/AppIcon.png \
    --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  retina=$((size * 2))
  sips -z "$retina" "$retina" Resources/AppIcon.png \
    --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
echo "Generated Resources/AppIcon.png and Resources/AppIcon.icns"
