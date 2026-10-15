#!/bin/zsh
# Regenerate Synklok/Assets.xcassets/AppIcon.appiconset from scripts/make-icon.swift.
set -euo pipefail
cd "${0:A:h}/.."
SET=Synklok/Assets.xcassets/AppIcon.appiconset
mkdir -p "$SET"
swift scripts/make-icon.swift "$SET/icon_1024.png" >/dev/null

images=""
for pt in 16 32 128 256 512; do
  for scale in 1 2; do
    px=$((pt * scale))
    name="icon_${pt}x${pt}@${scale}x.png"
    sips -z $px $px "$SET/icon_1024.png" --out "$SET/$name" >/dev/null
    images+="    { \"idiom\": \"mac\", \"size\": \"${pt}x${pt}\", \"scale\": \"${scale}x\", \"filename\": \"$name\" },\n"
  done
done
rm "$SET/icon_1024.png"
printf '{\n  "images": [\n%b  ],\n  "info": { "author": "xcode", "version": 1 }\n}\n' "${images%,\\n}\n" > "$SET/Contents.json"
printf '{\n  "info": { "author": "xcode", "version": 1 }\n}\n' > Synklok/Assets.xcassets/Contents.json
echo "Updated $SET"
