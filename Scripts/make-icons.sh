#!/bin/sh
# Regenerates every raster icon from the SVG sources in Assets/:
#   Assets/capd.icns                        app + dmg volume icon
#   Sources/CapdApp/Resources/MenuBarIcon*  menu-bar template glyphs
#   raycast/assets/extension-icon.png       Raycast Store icon
#
# The generated files are committed; run this only when the SVGs change.
# Requires librsvg (brew install librsvg).

set -eu

cd "$(dirname "$0")/.."

command -v rsvg-convert >/dev/null || {
    echo "error: rsvg-convert not found (brew install librsvg)" >&2
    exit 1
}

ICONSET=$(mktemp -d)/capd.iconset
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    double=$((size * 2))
    rsvg-convert -w "$size" -h "$size" Assets/icon.svg \
        -o "$ICONSET/icon_${size}x${size}.png"
    rsvg-convert -w "$double" -h "$double" Assets/icon.svg \
        -o "$ICONSET/icon_${size}x${size}@2x.png"
done
iconutil -c icns "$ICONSET" -o Assets/capd.icns

RES=Sources/CapdApp/Resources
rsvg-convert -w 16 -h 16 Assets/logo.svg -o "$RES/MenuBarIcon.png"
rsvg-convert -w 32 -h 32 Assets/logo.svg -o "$RES/MenuBarIcon@2x.png"
rsvg-convert -w 16 -h 16 Assets/menubar-slash.svg -o "$RES/MenuBarIconSlash.png"
rsvg-convert -w 32 -h 32 Assets/menubar-slash.svg -o "$RES/MenuBarIconSlash@2x.png"

# Raycast draws the icon with no container of its own, so it needs the tile alone.
# icon.svg insets the tile by 100 units on each side because macOS reserves that
# margin for its icon grid and drop shadow; cropping the viewBox to the tile keeps
# the artwork edge to edge instead of 20% smaller than its neighbours.
RAYCAST_ICON=raycast/assets/extension-icon.png
TILE=$(mktemp -d)/tile.svg
sed 's|viewBox="0 0 1024 1024"|viewBox="100 100 824 824"|' Assets/icon.svg >"$TILE"
rsvg-convert -w 512 -h 512 "$TILE" -o "$RAYCAST_ICON"

echo "regenerated Assets/capd.icns, $RES/MenuBarIcon*, and $RAYCAST_ICON"
