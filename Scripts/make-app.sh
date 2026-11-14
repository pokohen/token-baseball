#!/bin/bash
# Token Baseball.app 번들을 만든다. 번들로 실행해야 알림이 나온다.
# 사용법: Scripts/make-app.sh  →  build/Token Baseball.app
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/TokenBaseball"
APP="build/Token Baseball.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/TokenBaseball"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Token Baseball</string>
    <key>CFBundleDisplayName</key><string>Token Baseball</string>
    <key>CFBundleIdentifier</key><string>app.tokenbaseball.TokenBaseball</string>
    <key>CFBundleExecutable</key><string>TokenBaseball</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>KBO 및 각 구단과 무관한 비공식 팬 프로젝트</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "$APP"
