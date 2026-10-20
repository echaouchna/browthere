#!/bin/sh
# Builds build/BrowThere.app. Pass --install to copy it to /Applications.
set -eu
cd "$(dirname "$0")/.."

# SwiftUI macros ship with Xcode, not the Command Line Tools.
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

swift build -c release --arch arm64 --arch x86_64
BIN=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/BrowThere

APP=build/BrowThere.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/BrowThere"
strip -x "$APP/Contents/MacOS/BrowThere"
cp Resources/Info.plist "$APP/Contents/Info.plist"

ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET"
swift scripts/make-icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# SIGN_IDENTITY="Developer ID Application: …" signs for distribution; ad-hoc otherwise.
if [ -n "${SIGN_IDENTITY:-}" ]; then
    codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp --entitlements Resources/BrowThere.entitlements "$APP"
else
    codesign --force --sign - --options runtime --entitlements Resources/BrowThere.entitlements "$APP"
fi
echo "Built $APP"

if [ "${1:-}" = "--install" ]; then
    pkill -x BrowThere 2>/dev/null || true
    rm -rf /Applications/BrowThere.app
    cp -R "$APP" /Applications/
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/BrowThere.app
    echo "Installed to /Applications/BrowThere.app"
fi
