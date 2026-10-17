#!/bin/zsh
# Build the Synklok for Windows installer into dist/windows, Authenticode-sign
# it, and add it to the Windows update feed in the synklok-web checkout.
# Nothing is published: `--publish` uploads the installer to a GitHub release,
# and pushing synklok-web publishes the feed and synklok.app/download-windows.
#
# Version and build number come from project.yml (MARKETING_VERSION /
# CURRENT_PROJECT_VERSION), shared with the Mac app.
#
# The installer (~34 MB) lives on GitHub Releases because Cloudflare Pages
# serves files up to 25 MB; the feed and the download link stay on synklok.app.
#
# One-time setup (SETUP.md → Windows): .NET 10 SDK in ~/.dotnet,
#   brew install makensis jsign azure-cli, Azure Artifact Signing (az login),
#   the Sparkle key in the keychain under account "synklok" (same as the Mac).
#
# Builds the last commit (HEAD), not uncommitted changes: other work in this
# working tree never ends up in an installer.
#
# Usage:
#   scripts/release-windows.sh                  build, sign, write the feed
#   scripts/release-windows.sh --publish        upload that installer to GitHub (public)
#   scripts/release-windows.sh --test-build N   installer that reports build N (lower than the
#                                               current one), for testing updates; feed untouched
#   scripts/release-windows.sh --publish-test N upload that test installer as a GitHub
#                                               pre-release (public), to share for testing
# ALLOW_UNSIGNED=1 skips Authenticode signing (test builds only).
# SYNKLOK_UPDATE_FEED=<url> points a test build at another feed (see test-windows-update.sh).
set -euo pipefail

cd "${0:A:h}/.."
export PATH="$HOME/.dotnet:$PATH" LANG="${LANG:-en_US.UTF-8}"   # makensis crashes without a locale
REPO=blaisjohn/synklok
# Build outside ~/Documents, like release.sh (iCloud sync adds Finder metadata).
WORK="$HOME/Library/Caches/Synklok/windows-release"
DIST=dist/windows
SITE="${SYNKLOK_WEB:-$HOME/Documents/synklok-web}"
SIGN_UPDATE="$HOME/Library/Caches/Synklok/spm/artifacts/sparkle/Sparkle/bin/sign_update"

VERSION=$(git show HEAD:project.yml | sed -nE 's/^ *MARKETING_VERSION: *"?([^"]+)"? *$/\1/p')
BUILD=$(git show HEAD:project.yml | sed -nE 's/^ *CURRENT_PROJECT_VERSION: *"?([^"]+)"? *$/\1/p')
[[ -n "$VERSION" && -n "$BUILD" ]] || { echo "Couldn't read the version from project.yml." >&2; exit 1; }
TAG="windows-$VERSION"
SETUP="Synklok-$VERSION-$BUILD-Setup.exe"
URL="https://github.com/$REPO/releases/download/$TAG/$SETUP"
NOTES="release-notes/$VERSION-windows.html"

# ── --publish / --publish-test: upload an installer as a GitHub release ──
if [[ "${1:-}" == --publish || "${1:-}" == --publish-test ]]; then
  if [[ "$1" == --publish-test ]]; then
    N="${2:?Usage: $0 --publish-test N}"
    FILE="$DIST/test/Synklok-$VERSION-test$N-Setup.exe" RTAG="windows-$VERSION-test$N"
    TITLE="Synklok $VERSION for Windows — test build $N (not signed)"
    BODY="**Test build for trying Synklok on Windows 10 and 11 (64-bit). Not code-signed yet.** Windows will say \"Windows protected your PC\": click **More info → Run anyway**. It updates itself to the finished release when that's out. The finished version will be at https://synklok.app."
    PRE=(--prerelease)
  else
    FILE="$DIST/$SETUP" RTAG="$TAG" TITLE="Synklok $VERSION for Windows" PRE=()
    BODY="Synklok $VERSION for Windows 10 and 11 (64-bit). Download the Setup file below, or from https://synklok.app."
    [[ -f "$NOTES" ]] && BODY+=$'\n\n'"$(python3 -I -c '
import re, sys, html
t = open(sys.argv[1]).read()
t = re.sub(r"<h3>.*?</h3>\s*", "", t)
t = re.sub(r"\s*<li>", "\n- ", t)
t = re.sub(r"</?b>", "**", t)
t = re.sub(r"</?i>", "_", t)
print(html.unescape(re.sub(r"<[^>]+>", "", t)).strip())
' "$NOTES")"
  fi
  [[ -f "$FILE" ]] || { echo "No $FILE yet. Build it first (see Usage)." >&2; exit 1; }
  git fetch -q origin main
  [[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] \
    || { echo "Push the Synklok repo first: the release is tagged at GitHub's main branch." >&2; exit 1; }
  export GH_TOKEN=$(gh auth token -u blaisjohn)   # personal account; jblaiscl can't write here
  if gh release view "$RTAG" -R "$REPO" >/dev/null 2>&1; then
    gh release upload "$RTAG" "$FILE" -R "$REPO" --clobber
  else
    gh release create "$RTAG" "$FILE" -R "$REPO" --target main "${PRE[@]}" --title "$TITLE" --notes "$BODY"
  fi
  DL="https://github.com/$REPO/releases/download/$RTAG/${FILE:t}"
  SIZE=$(curl -sfL -o /dev/null -w '%{size_download}' "$DL") || { echo "Uploaded, but $DL doesn't download yet." >&2; exit 1; }
  [[ "$SIZE" == "$(stat -f %z "$FILE")" ]] || { echo "Download size $SIZE doesn't match the local file." >&2; exit 1; }
  echo "\nOn GitHub: $DL"
  [[ "$1" == --publish ]] && echo "Next: commit and push synklok-web to publish the update feed and synklok.app/download-windows."
  exit 0
fi

# ── Build ──
BUILDNUM=$BUILD DISPLAY=$VERSION OUT="$DIST/$SETUP" TEST=0
if [[ "${1:-}" == --test-build ]]; then
  BUILDNUM="${2:?Usage: $0 --test-build N}"
  (( BUILDNUM < BUILD )) || { echo "Use a build number below $BUILD, so the real release counts as newer." >&2; exit 1; }
  if [[ -n "${SYNKLOK_UPDATE_FEED:-}" ]]; then
    # Reads a local test feed: never share this one.
    DISPLAY="$VERSION-localtest$BUILDNUM" OUT="$DIST/test-local/Synklok-$VERSION-localtest$BUILDNUM-Setup.exe"
  else
    DISPLAY="$VERSION-test$BUILDNUM" OUT="$DIST/test/Synklok-$VERSION-test$BUILDNUM-Setup.exe"
  fi
  TEST=1
fi
DIRTY=$(git status --porcelain -- windows project.yml release-notes LICENSE)
[[ -z "$DIRTY" ]] || echo "Note: building commit $(git rev-parse --short HEAD); uncommitted changes aren't included:\n$DIRTY"

SIGN=1
if [[ "${ALLOW_UNSIGNED:-}" == 1 ]]; then
  SIGN=0
  echo "ALLOW_UNSIGNED=1: building WITHOUT Authenticode signatures (Windows will warn more)."
else
  scripts/sign-windows.sh --check
  export SYNKLOK_SIGN_TOKEN=$(az account get-access-token --resource https://codesigning.azure.net --query accessToken -o tsv)
fi
command -v makensis >/dev/null || { echo "makensis not found: brew install makensis" >&2; exit 1; }
(( TEST )) || [[ -x "$SIGN_UPDATE" ]] || { echo "Sparkle's sign_update not found; run scripts/release.sh once to fetch Sparkle." >&2; exit 1; }

echo "Building Synklok $DISPLAY (build $BUILDNUM) for Windows…"
rm -rf "$WORK" && mkdir -p "$WORK/src" "$WORK/stage" "${OUT:h}"
git archive HEAD | tar -x -C "$WORK/src"
SRC="$WORK/src"
dotnet test "$SRC/windows/Synklok.Core.Tests" --nologo -v q | grep -E 'Passed!|Failed' || { echo "Tests failed." >&2; exit 1; }

# Single file, not compressed: the installer's LZMA squeezes it to ~34 MB,
# better than .NET's own compression, and Synklok starts faster.
dotnet publish "$SRC/windows/Synklok.Tray" -c Release -r win-x64 --self-contained --nologo -v q \
  -p:PublishSingleFile=true -p:DebugType=none \
  -p:Version="$VERSION" -p:SynklokBuild="$BUILDNUM" -p:InformationalVersion="$DISPLAY" \
  ${SYNKLOK_UPDATE_FEED:+-p:SynklokUpdateFeed=$SYNKLOK_UPDATE_FEED} \
  -o "$WORK/publish"
[[ -f "$WORK/publish/Synklok.exe" && -f "$WORK/publish/WinSparkle.dll" ]] || { echo "dotnet publish failed." >&2; exit 1; }

cp "$WORK/publish/Synklok.exe" "$WORK/publish/WinSparkle.dll" "$WORK/stage/"
"$SRC/windows/tools/make-acknowledgements.sh" "$WORK/stage/Acknowledgements.txt" >/dev/null
(( SIGN )) && scripts/sign-windows.sh "$WORK/stage/Synklok.exe" "$WORK/stage/WinSparkle.dll"

NSIS_ARGS=(-V2 -INPUTCHARSET UTF8 -DVERSION="$VERSION" -DBUILD="$BUILDNUM" -DDISPLAY_VERSION="$DISPLAY"
           -DSTAGE="$WORK/stage" -DOUTFILE="$PWD/$OUT")
# The installer and its uninstaller are signed as makensis writes them.
(( SIGN )) && NSIS_ARGS+=(-DSIGN_CMD="\"$PWD/scripts/sign-windows.sh\"")
rm -f "$OUT"
makensis "${NSIS_ARGS[@]}" "$SRC/windows/installer/Synklok.nsi"
[[ -f "$OUT" ]] || { echo "makensis failed." >&2; exit 1; }
if (( SIGN )) && command -v osslsigncode >/dev/null; then
  osslsigncode verify -in "$OUT" 2>/dev/null | grep -E 'Subject:|Signature verification' | head -3
fi
echo "\nReady: $OUT ($(( $(stat -f %z "$OUT") / 1048576 )) MB)"

if (( TEST )); then
  echo "Test build: once $VERSION (build $BUILD) is in its feed, Check for updates… on Windows should offer it."
  exit 0
fi

# ── Update feed + download link in the synklok-web checkout (not pushed) ──
if [[ ! -d "$SITE/.git" ]]; then
  echo "No synklok-web checkout at $SITE; skipped the update feed." >&2
  exit 0
fi
# Same EdDSA key as the Mac feed; WinSparkle checks it before installing.
ED=$("$SIGN_UPDATE" --account synklok "$OUT")
mkdir -p "$SITE/downloads"
python3 -I - "$SITE/downloads/appcast-windows.xml" "$VERSION" "$BUILD" "$URL" "$ED" "$SRC/$NOTES" <<'PY'
import os, re, sys
from email.utils import formatdate
feed, version, build, url, ed, notes = sys.argv[1:]
items = []
if os.path.exists(feed):
    for item in re.findall(r"[ \t]*<item>.*?</item>\n", open(feed).read(), re.S):
        if f"<sparkle:version>{build}</sparkle:version>" not in item:
            items.append(item)
desc = ""
if os.path.exists(notes):
    desc = f"            <description><![CDATA[{open(notes).read()}]]></description>\n"
new = (
    "        <item>\n"
    f"            <title>{version}</title>\n"
    f"            <pubDate>{formatdate(localtime=True)}</pubDate>\n"
    "            <link>https://synklok.app</link>\n"
    f"            <sparkle:version>{build}</sparkle:version>\n"
    f"            <sparkle:shortVersionString>{version}</sparkle:shortVersionString>\n"
    "            <sparkle:minimumSystemVersion>10.0</sparkle:minimumSystemVersion>\n"
    f"{desc}"
    f'            <enclosure url="{url}" sparkle:os="windows-x64" sparkle:installerArguments="/update" '
    f'type="application/octet-stream" {ed.strip()}/>\n'
    "        </item>\n"
)
with open(feed, "w") as f:
    f.write('<?xml version="1.0" encoding="utf-8"?>\n'
            '<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">\n'
            "    <channel>\n"
            "        <title>Synklok for Windows</title>\n"
            + new + "".join(items) +
            "    </channel>\n"
            "</rss>\n")
PY
# Stable link for the site's Windows download button. release.sh keeps this
# line when it rewrites /download for the Mac.
REDIRECTS="$SITE/_redirects"
{ grep -v '^/download-windows ' "$REDIRECTS" 2>/dev/null || true; echo "/download-windows $URL 302"; } > "$REDIRECTS.new"
mv "$REDIRECTS.new" "$REDIRECTS"

echo "Update feed: $SITE/downloads/appcast-windows.xml"
echo "synklok.app/download-windows → $URL"
echo "\nTo publish:"
echo "  1. Push the Synklok repo."
echo "  2. scripts/release-windows.sh --publish   (uploads the installer to GitHub)"
echo "  3. Commit and push synklok-web."
