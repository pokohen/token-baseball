#!/bin/bash
# 업데이트: 최신 코드를 받아 앱을 다시 만든다. 저장 파일(구단·선수)은 건드리지 않는다.
# 사용법: Scripts/update.sh
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    echo "직접 고친 파일이 있어 업데이트를 멈춥니다. 아래 파일을 되돌리거나 커밋한 뒤 다시 실행하세요:"
    git status --short --untracked-files=no
    exit 1
fi

BEFORE="$(git rev-parse --short HEAD)"
echo "최신 코드를 받는 중…"
git pull --ff-only
AFTER="$(git rev-parse --short HEAD)"
if [ "$BEFORE" = "$AFTER" ]; then
    echo "이미 최신입니다 ($AFTER). 앱만 다시 만듭니다."
else
    echo "업데이트: $BEFORE → $AFTER"
fi

echo "앱을 만드는 중… (1~2분)"
Scripts/make-app.sh >/dev/null
echo
echo "완료. 저장 파일은 그대로입니다."
echo "실행 중인 앱이 있으면 설정 탭의 '앱 종료'로 끈 뒤 새 앱을 여세요:"
echo "  open \"build/Token Baseball.app\""
