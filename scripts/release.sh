#!/bin/zsh
# Build a Developer ID–signed, notarized, stapled Synklok DMG in dist/, then
# add it to the Sparkle update feed in the synklok-web checkout (not pushed).
#
# One-time setup (see SETUP.md → Distribution):
#   1. Xcode → Settings → Accounts: sign in, then Manage Certificates → + → Developer ID Application
#   2. xcrun notarytool store-credentials synklok-notary --apple-id <you> --team-id <TEAMID>
#   3. Sparkle signing key in the keychain under account "synklok" (generate_keys --account synklok)
#
# Usage: scripts/release.sh            (version comes from project.yml)
#        NOTARY_PROFILE=other SYNKLOK_WEB=~/path/to/synklok-web scripts/release.sh
# Optional release notes: release-notes/<version>.html
set -euo pipefail

cd "${0:A:h}/.."
NOTARY_PROFILE="${NOTARY_PROFILE:-synklok-notary}"
# Build outside ~/Documents: iCloud sync adds Finder metadata to new files,
# which codesign --strict rejects.
WORK="$HOME/Library/Caches/Synklok"
BUILD="$WORK/release"
SPM="$WORK/spm"   # kept between runs so Sparkle isn't re-downloaded
DIST=dist
SITE="${SYNKLOK_WEB:-$HOME/Documents/synklok-web}"
FEED_URL_PREFIX="https://synklok.app/downloads/"

# Renewed Developer ID certs share one name, so sign by SHA-1 fingerprint,
# choosing the valid identity that expires last.
read -r IDENTITY_SHA IDENTITY <<<"$(python3 -I - <<'PY'
import re, subprocess
ids = subprocess.run(["security", "find-identity", "-v", "-p", "codesigning"],
                     capture_output=True, text=True).stdout
best = None
for sha, name in re.findall(r'([0-9A-F]{40}) "(Developer ID Application: [^"]+)"', ids):
    certs = subprocess.run(["security", "find-certificate", "-a", "-Z", "-p", "-c", name],
                           capture_output=True, text=True).stdout
    m = re.search(sha + r".*?(-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----)", certs, re.S)
    if not m:
        continue
    end = subprocess.run(["openssl", "x509", "-noout", "-enddate", "-dateopt", "iso_8601"],
                         input=m.group(1), capture_output=True, text=True).stdout.strip()
    if best is None or end > best[0]:
        best = (end, sha, name)
if best:
    print(best[1], best[2])
PY
)"
if [[ -z "$IDENTITY" ]]; then
  echo "No 'Developer ID Application' certificate in the keychain. See SETUP.md → Distribution." >&2
  exit 1
fi
TEAM_ID=$(sed -E 's/.*\(([A-Z0-9]{10})\)$/\1/' <<<"$IDENTITY")
echo "Signing as: $IDENTITY ($IDENTITY_SHA)"

xcodegen generate --quiet
rm -rf "$BUILD" && mkdir -p "$BUILD" "$DIST"

xcodebuild -project Synklok.xcodeproj -scheme Synklok -configuration Release \
  -archivePath "$BUILD/Synklok.xcarchive" -clonedSourcePackagesDirPath "$SPM" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY_SHA" DEVELOPMENT_TEAM="$TEAM_ID" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  archive | grep -E 'error|warning: |ARCHIVE' || true
[[ -d "$BUILD/Synklok.xcarchive" ]] || { echo "Archive failed — rerun xcodebuild without the grep to see why." >&2; exit 1; }

# Export re-signs nested code (Sparkle's Autoupdate, Updater.app, XPC services)
# with our Developer ID, which notarization requires.
cat > "$BUILD/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>$IDENTITY_SHA</string>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$BUILD/Synklok.xcarchive" \
  -exportOptionsPlist "$BUILD/ExportOptions.plist" -exportPath "$BUILD/export" \
  | grep -E 'error|EXPORT' || true

APP="$BUILD/export/Synklok.app"
[[ -d "$APP" ]] || { echo "Export failed — rerun xcodebuild -exportArchive without the grep to see why." >&2; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
BUILDNUM=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist")
xattr -cr "$APP"
codesign --verify --deep --strict "$APP"

# DMG with the app and an /Applications shortcut for drag-to-install.
STAGE="$BUILD/dmg"
mkdir -p "$STAGE" && cp -R "$APP" "$STAGE/" && ln -s /Applications "$STAGE/Applications"
DMG="$DIST/Synklok-$VERSION-$BUILDNUM.dmg"
rm -f "$DMG"
hdiutil create -quiet -volname "Synklok $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
codesign --sign "$IDENTITY_SHA" --timestamp "$DMG"

echo "Notarizing (usually 1–5 minutes)…"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"

spctl --assess --type open --context context:primary-signature -v "$DMG"
echo "\nReady: $DMG"

# Sparkle feed: copy the DMG (and optional notes) into the site and rebuild
# appcast.xml, signing each entry with the EdDSA key from the keychain.
if [[ -d "$SITE/.git" ]]; then
  DL="$SITE/downloads"
  mkdir -p "$DL"
  cp "$DMG" "$DL/"
  NOTES="release-notes/$VERSION.html"
  [[ -f "$NOTES" ]] && cp "$NOTES" "$DL/${DMG:t:r}.html"
  "$SPM/artifacts/sparkle/Sparkle/bin/generate_appcast" --account synklok \
    --download-url-prefix "$FEED_URL_PREFIX" --link https://synklok.app \
    --maximum-deltas 0 --embed-release-notes "$DL"
  # Stable link for the site's Download button. Other lines (the Windows
  # /download-windows link from release-windows.sh) are kept.
  { grep -v '^/download ' "$SITE/_redirects" 2>/dev/null || true; echo "/download /downloads/${DMG:t} 302"; } > "$SITE/_redirects.new"
  mv "$SITE/_redirects.new" "$SITE/_redirects"
  echo "Update feed written to $DL/appcast.xml and /download pointed at ${DMG:t}."
  echo "Review, then commit and push synklok-web to publish."
else
  echo "No synklok-web checkout at $SITE; skipped the update feed." >&2
fi
