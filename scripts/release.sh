#!/bin/zsh
# Build a Developer ID–signed, notarized, stapled Synklok DMG in dist/.
#
# One-time setup (see SETUP.md → Distribution):
#   1. Xcode → Settings → Accounts: sign in, then Manage Certificates → + → Developer ID Application
#   2. xcrun notarytool store-credentials synklok-notary --apple-id <you> --team-id <TEAMID>
#
# Usage: scripts/release.sh            (version comes from project.yml)
#        NOTARY_PROFILE=other scripts/release.sh
set -euo pipefail

cd "${0:A:h}/.."
NOTARY_PROFILE="${NOTARY_PROFILE:-synklok-notary}"
BUILD=build/release
DIST=dist

IDENTITY=$(security find-identity -v -p codesigning | grep -m1 -o '"Developer ID Application: [^"]*"' | tr -d '"') || true
if [[ -z "$IDENTITY" ]]; then
  echo "No 'Developer ID Application' certificate in the keychain. See SETUP.md → Distribution." >&2
  exit 1
fi
TEAM_ID=$(sed -E 's/.*\(([A-Z0-9]{10})\)$/\1/' <<<"$IDENTITY")
echo "Signing as: $IDENTITY"

xcodegen generate --quiet
rm -rf "$BUILD" && mkdir -p "$BUILD" "$DIST"

xcodebuild -project Synklok.xcodeproj -scheme Synklok -configuration Release \
  -archivePath "$BUILD/Synklok.xcarchive" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application" DEVELOPMENT_TEAM="$TEAM_ID" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  archive | grep -E 'error|warning: |ARCHIVE' || true

APP="$BUILD/Synklok.xcarchive/Products/Applications/Synklok.app"
[[ -d "$APP" ]] || { echo "Archive failed — rerun xcodebuild without the grep to see why." >&2; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
BUILDNUM=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist")
codesign --verify --deep --strict "$APP"

# DMG with the app and an /Applications shortcut for drag-to-install.
STAGE="$BUILD/dmg"
mkdir -p "$STAGE" && cp -R "$APP" "$STAGE/" && ln -s /Applications "$STAGE/Applications"
DMG="$DIST/Synklok-$VERSION-$BUILDNUM.dmg"
rm -f "$DMG"
hdiutil create -quiet -volname "Synklok $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
codesign --sign "$IDENTITY" --timestamp "$DMG"

echo "Notarizing (usually 1–5 minutes)…"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"

spctl --assess --type open --context context:primary-signature -v "$DMG"
echo "\nReady: $DMG"
