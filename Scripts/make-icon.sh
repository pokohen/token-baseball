#!/bin/bash
# 앱 아이콘을 다시 만든다: 로고(Resources/AppLogo.png, 배경이 투명한 PNG)를 둥근 사각형 바탕에 올려
# Resources/AppIcon.icns로 묶는다. 로고를 바꿨을 때만 돌리면 된다. 만든 파일은 저장소에 넣어 둔다.
set -euo pipefail
cd "$(dirname "$0")/.."

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
swift Scripts/make-icon.swift Resources/AppLogo.png "$WORK/icon.png"
SET="$WORK/AppIcon.iconset"
mkdir -p "$SET" Resources
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$WORK/icon.png" --out "$SET/icon_${size}x${size}.png" >/dev/null
    sips -z "$((size * 2))" "$((size * 2))" "$WORK/icon.png" --out "$SET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o Resources/AppIcon.icns
cp "$SET/icon_256x256@2x.png" docs/images/app-icon.png
echo "Resources/AppIcon.icns"
