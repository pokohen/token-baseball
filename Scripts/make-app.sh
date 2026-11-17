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
# 새 버전 확인에 쓰는 정보: 빌드한 커밋과 저장소 (소유자/이름).
# 직접 고친 파일이 있으면 커밋을 적지 않는다 (그런 빌드는 새 버전 확인을 하지 않는다).
COMMIT=""
if [ -z "$(git status --porcelain --untracked-files=no 2>/dev/null)" ]; then
    COMMIT="$(git rev-parse HEAD 2>/dev/null || true)"
fi
REPO="$(git remote get-url origin 2>/dev/null | sed -E 's#^(https://github.com/|git@github.com:)##; s#\.git$##' || true)"
/usr/libexec/PlistBuddy -c "Add :TBCommit string $COMMIT" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :TBRepository string $REPO" "$APP/Contents/Info.plist"

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "$APP"
