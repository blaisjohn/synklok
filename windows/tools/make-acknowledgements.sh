#!/bin/zsh
# Writes the Windows app's Acknowledgements.txt (Settings → Acknowledgements):
# Synklok's LICENSE plus the notices of what ships inside it, verbatim —
# WinSparkle (and the Expat parser it includes) and the .NET runtime.
# Called by scripts/release-windows.sh after `dotnet publish`, which fills
# the NuGet cache these come from. Output uses Windows line endings for Notepad.
#
# Usage: windows/tools/make-acknowledgements.sh <output file>
set -euo pipefail
cd "${0:A:h}/../.."
OUT="$1"
NUGET="${NUGET_PACKAGES:-$HOME/.nuget/packages}"
WINSPARKLE_VERSION=$(sed -nE 's/.*Include="WinSparkle" Version="([^"]+)".*/\1/p' windows/Synklok.Tray/Synklok.Tray.csproj)
RUNTIME=$(ls -d "$NUGET"/microsoft.netcore.app.runtime.win-x64/*/ | sort -V | tail -1)

rule() { echo; echo "────────────────────────────────────────"; echo; }
{
  echo "Synklok for Windows"
  echo
  cat LICENSE
  rule
  echo "Synklok uses WinSparkle $WINSPARKLE_VERSION (https://winsparkle.org) for software updates."
  echo
  cat "$NUGET/winsparkle/$WINSPARKLE_VERSION/COPYING"
  rule
  echo "WinSparkle includes the Expat XML parser (https://libexpat.github.io)."
  echo
  cat windows/tools/licenses/expat-COPYING.txt
  rule
  echo "Synklok includes the .NET runtime $(basename "$RUNTIME") and Windows Forms (https://dot.net)."
  echo
  cat "$RUNTIME/LICENSE.TXT"
  rule
  cat "$RUNTIME/THIRD-PARTY-NOTICES.TXT"
} | tr -d '\r' | sed 's/$/\r/' > "$OUT"
echo "Wrote $OUT"
