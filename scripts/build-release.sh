#!/usr/bin/env bash
# Build a redistributable Hopet.app bundle and DMG.
#
# Usage:
#   scripts/build-release.sh [VERSION] [--universal]
#
# Output:
#   dist/Hopet.app
#   dist/Hopet-<version>.dmg
#
# Default builds for the host architecture only (works with Command Line
# Tools alone). Pass --universal to produce an arm64+x86_64 fat binary —
# this requires a full Xcode install, not just Command Line Tools.
#
# The .app bundle is ad-hoc signed (no Apple Developer ID required). Users
# will see Gatekeeper warnings on first launch — see the install section
# of README.md for the workaround.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="0.1.0"
UNIVERSAL=0
for arg in "$@"; do
    case "$arg" in
        --universal) UNIVERSAL=1 ;;
        *)           VERSION="$arg" ;;
    esac
done

BUNDLE_ID="com.hopet.app"
APP_NAME="Hopet"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

echo "==> Hopet release build (version: $VERSION)"

rm -rf "$DIST"
mkdir -p "$DIST"

if [ "$UNIVERSAL" -eq 1 ]; then
    echo "==> swift build -c release (universal arm64 + x86_64)"
    swift build -c release --arch arm64 --arch x86_64 --product Hopet
    swift build -c release --arch arm64 --arch x86_64 --product hopet-emit
    BUILT_DIR="$ROOT/.build/apple/Products/Release"
else
    HOST_ARCH="$(uname -m)"
    echo "==> swift build -c release (host arch: $HOST_ARCH)"
    swift build -c release --product Hopet
    swift build -c release --product hopet-emit
    BUILT_DIR="$ROOT/.build/release"
fi

if [ ! -x "$BUILT_DIR/Hopet" ] || [ ! -x "$BUILT_DIR/hopet-emit" ]; then
    echo "error: could not locate built binaries under $BUILT_DIR" >&2
    exit 1
fi
echo "==> Built binaries:"
file "$BUILT_DIR/Hopet" "$BUILT_DIR/hopet-emit"

echo "==> Assembling $APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BUILT_DIR/Hopet"      "$APP/Contents/MacOS/Hopet"
cp "$BUILT_DIR/hopet-emit" "$APP/Contents/MacOS/hopet-emit"
chmod 0755 "$APP/Contents/MacOS/Hopet" "$APP/Contents/MacOS/hopet-emit"

# Resources: SwiftPM bundles them into Hopet_Hopet.bundle next to the binary.
# Copy the whole bundle into Contents/Resources so Bundle.module resolves at
# runtime exactly like during `swift run`.
RESOURCE_BUNDLE_NAME="Hopet_Hopet.bundle"
if [ -d "$BUILT_DIR/$RESOURCE_BUNDLE_NAME" ]; then
    cp -R "$BUILT_DIR/$RESOURCE_BUNDLE_NAME" "$APP/Contents/Resources/"
else
    echo "warning: $RESOURCE_BUNDLE_NAME not found in $BUILT_DIR" >&2
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Hopet</string>
    <key>CFBundleDisplayName</key>
    <string>Hopet</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleExecutable</key>
    <string>Hopet</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>© 2026 BinaryFroggy. MIT License.</string>
</dict>
</plist>
PLIST

echo "==> ad-hoc codesign"
# Sign the helper binary first, then the app bundle (deep so resources are
# covered too). Ad-hoc identity "-" means no Developer ID; users will need
# to bypass Gatekeeper on first launch.
codesign --force --sign - --timestamp=none \
    "$APP/Contents/MacOS/hopet-emit"
codesign --force --deep --sign - --timestamp=none \
    "$APP"
codesign --verify --deep --strict "$APP"

echo "==> Building DMG"
DMG="$DIST/Hopet-$VERSION.dmg"
STAGE="$DIST/dmg-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create \
    -volname "Hopet $VERSION" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    "$DMG" >/dev/null

rm -rf "$STAGE"

echo
echo "==> Done"
echo "    App:  $APP"
echo "    DMG:  $DMG"
ls -lh "$DMG"
