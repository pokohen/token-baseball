#!/bin/bash
# Token Sport 설치·업데이트. 저장소를 직접 받을 필요 없이 이 한 줄이면 된다:
#
#   curl -fsSL https://raw.githubusercontent.com/pokohen/token-sport/main/Scripts/install.sh | bash
#
# 하는 일:
#   1. 소스를 ~/.token-sport 에 받는다 (이미 있으면 최신으로 고친다).
#   2. 앱을 만든다. (Xcode 16 이상이 있어야 한다. 처음에는 1~2분 걸린다.)
#   3. 응용 프로그램 폴더에 "Token Baseball.app"을 넣고 실행한다.
#
# 다시 실행하면 업데이트다. 구단·선수 저장 파일(~/Library/Application Support/TokenBaseball)은 건드리지 않는다.
# 지우려면: Scripts/install.sh --uninstall  (저장 파일은 남긴다)
set -euo pipefail

REPO_URL="${TOKEN_SPORT_REPO:-https://github.com/pokohen/token-sport.git}"
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

mkdir -p "$APP_DIR"
# 실행 중이면 끄고 바꾼다. 앱은 끌 때 스스로 저장한다.
if [ -z "$NO_OPEN" ] && pgrep -x TokenBaseball >/dev/null 2>&1; then
    echo "실행 중인 앱을 끄는 중…"
    pkill -x TokenBaseball || true
    sleep 1
fi
rm -rf "$APP_DIR/$APP_NAME"
cp -R "$SRC/build/$APP_NAME" "$APP_DIR/$APP_NAME"

echo
echo "설치했습니다: $APP_DIR/$APP_NAME"
echo "구단·선수 저장 파일은 그대로입니다."
if [ -z "$NO_OPEN" ]; then
    open "$APP_DIR/$APP_NAME"
    echo "앱을 실행했습니다. 화면 맨 위 상단바의 아이콘을 누르세요."
fi
echo "업데이트할 때도 같은 명령을 다시 실행하면 됩니다."
