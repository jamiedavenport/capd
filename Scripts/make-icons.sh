#!/bin/sh
# Regenerates every raster icon from the SVG sources in Assets/:
#   Assets/cap.icns                        app + dmg volume icon
#   Sources/CapApp/Resources/MenuBarIcon*  menu-bar template glyphs
#
# The generated files are committed; run this only when the SVGs change.
# Requires librsvg (brew install librsvg).

set -eu

cd "$(dirname "$0")/.."

command -v rsvg-convert >/dev/null || {
    echo "error: rsvg-convert not found (brew install librsvg)" >&2
    exit 1
}

ICONSET=$(mktemp -d)/cap.iconset
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    double=$((size * 2))
    rsvg-convert -w "$size" -h "$size" Assets/icon.svg \
        -o "$ICONSET/icon_${size}x${size}.png"
    rsvg-convert -w "$double" -h "$double" Assets/icon.svg \
        -o "$ICONSET/icon_${size}x${size}@2x.png"
done
iconutil -c icns "$ICONSET" -o Assets/cap.icns

RES=Sources/CapApp/Resources
rsvg-convert -w 16 -h 16 Assets/logo.svg -o "$RES/MenuBarIcon.png"
rsvg-convert -w 32 -h 32 Assets/logo.svg -o "$RES/MenuBarIcon@2x.png"
rsvg-convert -w 16 -h 16 Assets/menubar-slash.svg -o "$RES/MenuBarIconSlash.png"
rsvg-convert -w 32 -h 32 Assets/menubar-slash.svg -o "$RES/MenuBarIconSlash@2x.png"

echo "regenerated Assets/cap.icns and $RES/MenuBarIcon*"
