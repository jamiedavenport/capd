#!/bin/sh
# Builds the universal cap.app bundle and .dmg into dist/.
#
# CODESIGN_IDENTITY selects the Developer ID signing identity. Unset means
# ad-hoc, which is enough to run the bundle locally but won't pass Gatekeeper.

set -eu

cd "$(dirname "$0")/.."

VERSION=$(sed -n 's/.*static let version = "\(.*\)".*/\1/p' Sources/CapKit/CapKit.swift)
test -n "$VERSION" || { echo "error: could not read version from CapKit.swift" >&2; exit 1; }

IDENTITY="${CODESIGN_IDENTITY:--}"
# Ad-hoc signatures cannot carry a secure timestamp, and notarization requires one.
if [ "$IDENTITY" = "-" ]; then
    TIMESTAMP=--timestamp=none
else
    TIMESTAMP=--timestamp
fi

swift build -c release --arch arm64 --arch x86_64

BIN=.build/apple/Products/Release
APP=dist/cap.app

rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

sed "s/CAP_VERSION/$VERSION/g" Scripts/Info.plist > "$APP/Contents/Info.plist"
cp Assets/cap.icns "$APP/Contents/Resources/"

# cap and cap-agent ship next to the app executable: AgentBootstrap and
# `cap doctor` both resolve them relative to their own binary, and the
# Homebrew cask symlinks the CLI from here into PATH.
cp "$BIN/CapApp" "$BIN/cap" "$BIN/cap-agent" "$APP/Contents/MacOS/"

APPEX="$APP/Contents/PlugIns/CapShareExtension.appex"
mkdir -p "$APPEX/Contents/MacOS" "$APPEX/Contents/Resources"
sed "s/CAP_VERSION/$VERSION/g" Scripts/ShareExtension-Info.plist > "$APPEX/Contents/Info.plist"
cp Assets/cap.icns "$APPEX/Contents/Resources/"
cp "$BIN/CapShareExtension" "$APPEX/Contents/MacOS/"
# Dependency resource bundles (GRDB, KeyboardShortcuts) ship too, but a stale
# build dir can also hold test-target bundles, which must not.
for bundle in "$BIN"/*.bundle; do
    case "$bundle" in *Tests.bundle) continue ;; esac
    cp -R "$bundle" "$APP/Contents/Resources/"
done

for binary in "$APP/Contents/MacOS/CapApp" "$APP/Contents/MacOS/cap" \
    "$APP/Contents/MacOS/cap-agent" "$APPEX/Contents/MacOS/CapShareExtension"; do
    lipo "$binary" -verify_arch arm64 x86_64 || {
        echo "error: $(basename "$binary") is not a universal binary" >&2
        exit 1
    }
    lipo -info "$binary"
done

codesign --force --options runtime "$TIMESTAMP" --sign "$IDENTITY" \
    "$APP/Contents/MacOS/cap" "$APP/Contents/MacOS/cap-agent"
# Nested code signs inside-out: the appex's seal is part of the app's.
codesign --force --options runtime "$TIMESTAMP" \
    --entitlements Scripts/cap-share.entitlements --sign "$IDENTITY" "$APPEX"
codesign --force --options runtime "$TIMESTAMP" \
    --entitlements Scripts/cap.entitlements --sign "$IDENTITY" "$APP"

codesign --verify --strict --deep "$APP"

STAGING=$(mktemp -d)
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
# SetFile ships with the full Xcode CLT; the volume icon is cosmetic, so its
# absence must not fail packaging.
cp Assets/cap.icns "$STAGING/.VolumeIcon.icns"
SetFile -a C "$STAGING" 2>/dev/null || true
# hdiutil intermittently fails with "Resource busy" on CI runners.
for attempt in 1 2 3; do
    if hdiutil create -volname cap -srcfolder "$STAGING" -ov -format UDZO \
        "dist/cap-$VERSION.dmg"; then
        break
    fi
    test "$attempt" -lt 3 || exit 1
    sleep 5
done
rm -rf "$STAGING"

# Gatekeeper's dmg assessment (spctl -t open) requires a signature on the
# image itself; notarizing and stapling it is not enough.
codesign --force "$TIMESTAMP" --sign "$IDENTITY" "dist/cap-$VERSION.dmg"

echo "packaged dist/cap-$VERSION.dmg"
