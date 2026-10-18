#!/bin/zsh
# Try a Windows update end to end before anything is public. Serves the
# installer from scripts/release-windows.sh, plus a copy of its feed, from
# this Mac on the local network, and builds an older "test" installer that
# reads that feed. Install the test build on a PC, then Check for updates…
# should offer, download, verify and install the real build.
#
# Usage: scripts/release-windows.sh && scripts/test-windows-update.sh
#        (Ctrl-C stops the server)
set -euo pipefail
cd "${0:A:h}/.."
SITE="${SYNKLOK_WEB:-$HOME/Documents/synklok-web}"
VERSION=$(git show HEAD:project.yml | sed -nE 's/^ *MARKETING_VERSION: *"?([^"]+)"? *$/\1/p')
BUILD=$(git show HEAD:project.yml | sed -nE 's/^ *CURRENT_PROJECT_VERSION: *"?([^"]+)"? *$/\1/p')
SETUP="dist/windows/Synklok-$VERSION-$BUILD-Setup.exe"
FEED="$SITE/downloads/appcast-windows.xml"
[[ -f "$SETUP" ]] && grep -q "<sparkle:version>$BUILD</sparkle:version>" "$FEED" 2>/dev/null \
  || { echo "Run scripts/release-windows.sh first (no $SETUP in the feed)." >&2; exit 1; }

IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1)
PORT=8091
LAN="$HOME/Library/Caches/Synklok/windows-update-test"
rm -rf "$LAN" && mkdir -p "$LAN"
cp "$SETUP" "$LAN/"
# Same items and signatures; downloads come from this Mac instead of GitHub.
sed -E "s#https://github.com/blaisjohn/synklok/releases/download/[^/\"]+/#http://$IP:$PORT/#" "$FEED" > "$LAN/appcast-windows.xml"

OLD=$(( BUILD - 1 ))
SYNKLOK_UPDATE_FEED="http://$IP:$PORT/appcast-windows.xml" scripts/release-windows.sh --test-build "$OLD"
TEST_SETUP="Synklok-$VERSION-localtest$OLD-Setup.exe"
cp "dist/windows/test-local/$TEST_SETUP" "$LAN/"

cat <<EOF

On the Windows PC (same network as this Mac):
  1. Download and run  http://$IP:$PORT/$TEST_SETUP
  2. Synklok starts as $VERSION-localtest$OLD. Right-click the metronome → Check for updates…
  3. It should offer $VERSION, install it, and restart; Settings shows Synklok for Windows $VERSION.
Serving $LAN on port $PORT — Ctrl-C to stop.
EOF
exec python3 -m http.server "$PORT" --bind 0.0.0.0 --directory "$LAN"
