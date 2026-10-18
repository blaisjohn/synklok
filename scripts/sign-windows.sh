#!/bin/zsh
# Authenticode-sign Windows files (Synklok.exe, WinSparkle.dll, the installer
# and its uninstaller) with Azure Artifact Signing, from the Mac, via jsign.
# Microsoft issues a fresh 3-day certificate for John Blais behind the scenes;
# jsign timestamps every signature so it stays valid after that expires.
#
# One-time setup (SETUP.md → Windows → Code signing):
#   brew install jsign azure-cli, then `az login` with the account that holds
#   the Artifact Signing account below (it needs the
#   "Artifact Signing Certificate Profile Signer" role).
#
# Usage: scripts/sign-windows.sh FILE...
#        scripts/sign-windows.sh --check       (set up and signed in? signs nothing)
#        scripts/sign-windows.sh --configured  (exit 0 if ACCOUNT/PROFILE are filled in)
#
# Not set up as of October 2026: John chose to ship Windows builds unsigned
# for now ($9.99/month didn't pay off for a small audience; SmartScreen warns
# new publishers either way). Filling in ACCOUNT and PROFILE turns signing on.
# scripts/release-windows.sh exports SYNKLOK_SIGN_TOKEN so each file doesn't
# fetch a new token; on its own this script fetches one from the Azure CLI.
set -euo pipefail

# Artifact Signing account (portal.azure.com → Artifact Signing Accounts).
# Not secrets: who may sign is controlled by the Azure login.
ENDPOINT="${SYNKLOK_SIGN_ENDPOINT:-eus.codesigning.azure.net}"   # East US
ACCOUNT="${SYNKLOK_SIGN_ACCOUNT:-}"
PROFILE="${SYNKLOK_SIGN_PROFILE:-}"

if [[ "${1:-}" == --configured ]]; then
  [[ -n "$ACCOUNT" && -n "$PROFILE" ]]; exit
fi
if [[ -z "$ACCOUNT" || -z "$PROFILE" ]]; then
  echo "sign-windows.sh: set ACCOUNT and PROFILE at the top of this script (SETUP.md → Windows → Code signing)." >&2
  exit 1
fi
(( $# )) || { echo "Usage: $0 FILE... | --check" >&2; exit 2; }
command -v jsign >/dev/null || { echo "jsign not found: brew install jsign" >&2; exit 1; }

TOKEN="${SYNKLOK_SIGN_TOKEN:-}"
if [[ -z "$TOKEN" ]]; then
  command -v az >/dev/null || { echo "Azure CLI not found: brew install azure-cli" >&2; exit 1; }
  TOKEN=$(az account get-access-token --resource https://codesigning.azure.net --query accessToken -o tsv) \
    || { echo "No Azure sign-in. Run: az login" >&2; exit 1; }
fi
[[ "$1" == --check ]] && { echo "Windows signing ready: $ACCOUNT/$PROFILE at $ENDPOINT"; exit 0; }

jsign --storetype TRUSTEDSIGNING --keystore "$ENDPOINT" --storepass "$TOKEN" \
  --alias "$ACCOUNT/$PROFILE" --alg SHA-256 \
  --tsaurl http://timestamp.acs.microsoft.com --tsmode RFC3161 \
  --name Synklok --url https://synklok.app \
  "$@"
