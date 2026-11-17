#!/bin/bash
# 배포 파일 만들기: 서명하고 공증받은 .dmg를 만든다. 받아서 바로 열 수 있는 파일이다.
#
#   Scripts/release.sh 0.2.0            build/TokenSport-0.2.0.dmg 를 만든다
#   Scripts/release.sh 0.2.0 --publish  만든 뒤 GitHub Releases에 v0.2.0으로 올린다
#
# 준비물 (이 맥에 한 번만):
#   1. 키체인에 "Developer ID Application" 인증서
#   2. 공증용 로그인 정보:
#        xcrun notarytool store-credentials "token-sport" --apple-id "애플ID" --team-id "팀ID"
#      (암호는 appleid.apple.com에서 만든 앱 암호)
#
# 확인용: TB_SKIP_NOTARIZE=1 이면 서명까지만 하고 공증은 건너뛴다 (그 파일은 다른 맥에서 열리지 않는다).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
PUBLISH="${2:-}"
PROFILE="${TB_NOTARY_PROFILE:-token-sport}"
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "사용법: Scripts/release.sh 버전 [--publish]   (예: Scripts/release.sh 0.2.0)"
    exit 1
fi

if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    echo "커밋하지 않은 변경이 있습니다. 배포 파일은 커밋된 코드로만 만듭니다."
    git status --short --untracked-files=no
    exit 1
fi

IDENTITY="${TB_SIGN:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}"
if [ -z "$IDENTITY" ]; then
    echo "키체인에 Developer ID Application 인증서가 없습니다."
    exit 1
fi
echo "서명: $IDENTITY"

echo "앱을 만드는 중… (인텔 맥과 애플 실리콘 맥 모두)"
TB_ARCHS="arm64 x86_64" TB_VERSION="$VERSION" TB_SIGN="$IDENTITY" Scripts/make-app.sh >/dev/null
APP="build/Token Baseball.app"
codesign --verify --strict --deep "$APP"
# 배포 빌드 표시와 버전이 제대로 들어갔는지 확인한다 (빠지면 새 버전 알림이 어긋난다).
[ "$(/usr/libexec/PlistBuddy -c "Print :TBRelease" "$APP/Contents/Info.plist")" = "true" ] \
    && [ "$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")" = "$VERSION" ] \
    || { echo "앱에 배포 버전 정보가 제대로 들어가지 않았습니다."; exit 1; }

DMG="build/TokenSport-$VERSION.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -quiet -volname "Token Sport $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

if [ -n "${TB_SKIP_NOTARIZE:-}" ]; then
    echo "공증을 건너뛰었습니다. 이 파일은 이 맥에서만 확인용으로 쓰세요: $DMG"
    exit 0
fi

echo "Apple에 공증을 요청하는 중… (보통 1~5분)"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature "$DMG"
echo "만들었습니다: $DMG"

if [ "$PUBLISH" = "--publish" ]; then
    TAG="v$VERSION"
    echo "GitHub Releases에 $TAG 로 올리는 중…"
    gh release create "$TAG" "$DMG" --title "Token Sport $VERSION" --generate-notes --target "$(git rev-parse HEAD)"
    echo "올렸습니다."
fi
