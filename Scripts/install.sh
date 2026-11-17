#!/bin/bash
# Token Sport 설치·업데이트. 저장소를 직접 받을 필요 없이 이 한 줄이면 된다:
#
#   curl -fsSL https://raw.githubusercontent.com/pokohen/token-sport/main/Scripts/install.sh | bash
#
# 하는 일:
#   - 배포 파일(서명·공증된 .dmg)이 올라와 있으면 그것을 내려받아 응용 프로그램 폴더에 넣는다. Xcode가 없어도 된다.
#   - 배포 파일이 없거나 --build 를 주면, 소스를 ~/.token-sport 에 받아 이 맥에서 앱을 만든다 (Xcode 16 이상 필요).
#   - 끝나면 "Token Baseball.app"을 실행한다.
#
# 다시 실행하면 업데이트다. 구단·선수 저장 파일(~/Library/Application Support/TokenBaseball)은 건드리지 않는다.
#   --build      배포 파일 대신 최신 소스로 직접 만든다 (아직 배포되지 않은 변경까지 들어간다)
#   --uninstall  앱과 받아 둔 소스를 지운다 (저장 파일은 남긴다)
set -euo pipefail

SLUG="${TOKEN_SPORT_SLUG:-pokohen/token-sport}"
REPO_URL="${TOKEN_SPORT_REPO:-https://github.com/$SLUG.git}"
SRC="${TOKEN_SPORT_HOME:-$HOME/.token-sport}"
APP_NAME="Token Baseball.app"
# 확인용: 설치할 폴더를 바꾸고, 앱을 끄거나 열지 않게 할 수 있다.
APP_DIR="${TOKEN_SPORT_APP_DIR:-}"
NO_OPEN="${TOKEN_SPORT_NO_OPEN:-}"

if [ -z "$APP_DIR" ]; then
    if [ -w /Applications ]; then APP_DIR="/Applications"; else APP_DIR="$HOME/Applications"; fi
fi

if [ "${1:-}" = "--uninstall" ]; then
    [ -z "$NO_OPEN" ] && pkill -x TokenBaseball 2>/dev/null || true
    rm -rf "$APP_DIR/$APP_NAME" "$SRC"
    echo "지웠습니다: $APP_DIR/$APP_NAME, $SRC"
    echo "구단·선수 저장 파일은 남아 있습니다: ~/Library/Application Support/TokenBaseball"
    exit 0
fi

# 설치할 앱이 놓일 곳.
BUILT=""
WORK="$(mktemp -d)"
trap 'hdiutil detach "$WORK/mnt" -quiet 2>/dev/null || true; rm -rf "$WORK"' EXIT

# 1. 배포 파일이 있으면 내려받는다.
if [ "${1:-}" != "--build" ]; then
    DMG_URL="${TOKEN_SPORT_DMG_URL:-$(curl -fsSL "https://api.github.com/repos/$SLUG/releases/latest" 2>/dev/null \
        | sed -n 's/.*"browser_download_url": *"\([^"]*\.dmg\)".*/\1/p' | head -1 || true)}"
    if [ -n "$DMG_URL" ]; then
        echo "배포 파일을 내려받는 중… ($(basename "$DMG_URL"))"
        if curl -fL --progress-bar -o "$WORK/app.dmg" "$DMG_URL" \
            && hdiutil attach "$WORK/app.dmg" -nobrowse -readonly -quiet -mountpoint "$WORK/mnt" \
            && [ -d "$WORK/mnt/$APP_NAME" ]; then
            cp -R "$WORK/mnt/$APP_NAME" "$WORK/$APP_NAME"
            hdiutil detach "$WORK/mnt" -quiet || true
            BUILT="$WORK/$APP_NAME"
        else
            echo "배포 파일을 쓰지 못했습니다. 소스로 직접 만듭니다."
        fi
    fi
fi

# 2. 없으면 소스를 받아 이 맥에서 만든다.
if [ -z "$BUILT" ]; then
    if ! command -v swift >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
        echo "Xcode가 필요합니다. App Store에서 Xcode(16 이상)를 설치하고 한 번 실행한 뒤 다시 시도하세요."
        exit 1
    fi

    if [ -d "$SRC/.git" ]; then
        echo "최신 코드를 받는 중… ($SRC)"
        BEFORE="$(git -C "$SRC" rev-parse --short HEAD)"
        git -C "$SRC" fetch --quiet --prune origin
        DEFAULT="$(git -C "$SRC" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@' || true)"
        DEFAULT="${DEFAULT:-main}"
        # 이 폴더는 설치 전용이라 원격 저장소와 똑같이 맞춘다.
        git -C "$SRC" checkout --quiet "$DEFAULT"
        git -C "$SRC" reset --quiet --hard "origin/$DEFAULT"
        AFTER="$(git -C "$SRC" rev-parse --short HEAD)"
        if [ "$BEFORE" = "$AFTER" ]; then echo "이미 최신입니다 ($AFTER)."; else echo "업데이트: $BEFORE → $AFTER"; fi
    else
        if [ -e "$SRC" ]; then
            echo "$SRC 가 이미 있는데 Token Sport 소스가 아닙니다. 옮기거나 지운 뒤 다시 실행하세요."
            exit 1
        fi
        echo "소스를 받는 중… ($SRC)"
        git clone --quiet "$REPO_URL" "$SRC"
    fi

    echo "앱을 만드는 중… (처음에는 1~2분)"
    "$SRC/Scripts/make-app.sh" >/dev/null
    BUILT="$SRC/build/$APP_NAME"
fi

mkdir -p "$APP_DIR"
# 실행 중이면 끄고 바꾼다. 앱은 끌 때 스스로 저장한다.
if [ -z "$NO_OPEN" ] && pgrep -x TokenBaseball >/dev/null 2>&1; then
    echo "실행 중인 앱을 끄는 중…"
    pkill -x TokenBaseball || true
    sleep 1
fi
rm -rf "$APP_DIR/$APP_NAME"
cp -R "$BUILT" "$APP_DIR/$APP_NAME"

echo
echo "설치했습니다: $APP_DIR/$APP_NAME"
echo "구단·선수 저장 파일은 그대로입니다."
if [ -z "$NO_OPEN" ]; then
    open "$APP_DIR/$APP_NAME"
    echo "앱을 실행했습니다. 화면 맨 위 상단바의 아이콘을 누르세요."
fi
echo "업데이트할 때도 같은 명령을 다시 실행하면 됩니다."
