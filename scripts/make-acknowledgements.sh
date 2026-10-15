#!/bin/zsh
# Rebuild Synklok/Acknowledgements.txt (shown in the About window) from
# LICENSE and the resolved Sparkle package's LICENSE, verbatim.
set -euo pipefail
cd "${0:A:h}/.."
SPARKLE_LICENSE="${1:-$HOME/Library/Caches/Synklok/spm/artifacts/sparkle/Sparkle/LICENSE}"
{
  echo "Synklok"
  echo
  cat LICENSE
  echo
  echo "────────────────────────────────────────"
  echo
  echo "Synklok uses Sparkle (https://sparkle-project.org) for software updates."
  echo
  cat "$SPARKLE_LICENSE"
} > Synklok/Acknowledgements.txt
echo "Updated Synklok/Acknowledgements.txt"
