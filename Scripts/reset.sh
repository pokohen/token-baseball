#!/bin/bash
# 초기화: 저장 파일을 치우고, 코드를 원격 저장소의 최신 상태로 새로 받아 앱을 다시 만든다.
# 구단과 선수가 모두 사라지고 처음 화면부터 다시 시작한다.
#
# - 저장 파일은 지우지 않고 백업 폴더로 옮긴다 (되돌리려면 그 폴더 이름을 원래대로 바꾼다).
# - 코드는 원격 저장소의 기본 브랜치와 똑같이 맞춘다. 직접 고친 파일이나 올리지 않은 커밋이 있으면 멈춘다.
#
# 사용법: Scripts/reset.sh          (확인을 묻는다)
#         Scripts/reset.sh --yes    (묻지 않는다)
set -euo pipefail
cd "$(dirname "$0")/.."

# 저장 폴더. 확인용으로 다른 폴더를 가리킬 수 있다.
DATA="${TOKEN_BASEBALL_DATA_DIR:-$HOME/Library/Application Support/TokenBaseball}"
YES="${1:-}"

if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    echo "직접 고친 파일이 있어 초기화를 멈춥니다. 아래 파일을 되돌리거나 커밋한 뒤 다시 실행하세요:"
    git status --short --untracked-files=no
    exit 1
fi

# 원격 저장소에 올리지 않은 커밋이 있으면 코드를 새로 받으면서 사라진다.
git fetch --quiet --prune origin
UNPUSHED="$(git log --oneline HEAD --not --remotes | head -5)"
if [ -n "$UNPUSHED" ]; then
    echo "원격 저장소에 올리지 않은 커밋이 있어 초기화를 멈춥니다. 먼저 올리거나(git push) 따로 보관하세요:"
    echo "$UNPUSHED"
    exit 1
fi

echo "초기화하면:"
if [ -d "$DATA" ]; then
    echo "  1. 저장 파일(구단·선수)을 백업 폴더로 옮깁니다 → 처음 화면부터 다시 시작"
    ls "$DATA" | sed 's/^/       /'
else
    echo "  1. 저장 파일이 없습니다 (옮길 것 없음)"
fi
echo "  2. 코드를 원격 저장소의 최신 상태로 새로 받습니다"
echo "  3. 빌드 결과를 지우고 앱을 처음부터 다시 만듭니다"
if [ "$YES" != "--yes" ]; then
    printf "계속할까요? (y/N) "
    read -r answer
    case "$answer" in
        y|Y|yes) ;;
        *) echo "취소했습니다."; exit 0 ;;
    esac
fi

if [ -d "$DATA" ]; then
    BACKUP="$DATA-backup-$(date +%Y%m%d-%H%M%S)"
    mv "$DATA" "$BACKUP"
    echo "저장 파일을 옮겼습니다: $BACKUP"
fi

echo "코드를 새로 받는 중…"
DEFAULT="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@' || true)"
DEFAULT="${DEFAULT:-main}"
git checkout -q "$DEFAULT"
git reset -q --hard "origin/$DEFAULT"
echo "코드: $DEFAULT $(git rev-parse --short HEAD)"

echo "앱을 처음부터 다시 만드는 중… (1~2분)"
rm -rf .build build
Scripts/make-app.sh >/dev/null
echo
echo "완료. 실행 중인 앱이 있으면 설정 탭의 '앱 종료'로 끈 뒤 새 앱을 여세요:"
echo "  open \"build/Token Baseball.app\""
