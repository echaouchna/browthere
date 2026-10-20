#!/bin/sh
# Packages build/BrowThere-<version>.zip for sharing.
#
#   ./scripts/release.sh             ad-hoc signed: each user unblocks it once
#   ./scripts/release.sh --publish   also uploads it to the GitHub release v<version>
#
# Signed and notarized (opens without warnings), with a Developer ID certificate and
# credentials stored once via `xcrun notarytool store-credentials browthere …`:
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" NOTARY_PROFILE=browthere ./scripts/release.sh
set -eu
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
APP=build/BrowThere.app
ZIP=build/BrowThere-$VERSION.zip

./scripts/build-app.sh

if [ -n "${SIGN_IDENTITY:-}" ] && [ -n "${NOTARY_PROFILE:-}" ]; then
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    NOTES="Download, unzip and move BrowThere to Applications, then open it and click Make Default."
else
    NOTES="This build isn't notarized, so macOS blocks it the first time.

1. Unzip and move BrowThere to Applications.
2. Open it once, then go to System Settings → Privacy & Security and click **Open Anyway**.
   Or run: \`xattr -dr com.apple.quarantine /Applications/BrowThere.app\`
3. Open BrowThere and click **Make Default**."
fi

# ditto keeps the signature intact (plain zip can break it).
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "Packaged $ZIP"

if [ "${1:-}" = "--publish" ]; then
    gh release create "v$VERSION" "$ZIP" --title "BrowThere $VERSION" --notes "$NOTES"
fi
