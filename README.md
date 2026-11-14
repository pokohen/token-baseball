# Token Baseball

AI 코딩 도구에서 쓴 토큰이 **구단 자금**이 되는 macOS 메뉴바 야구단 육성 게임.
시민 야구단으로 시작해 6부 리그의 최상위 프로 리그까지 올라가는 것이 목표다.

> Token Baseball은 **KBO 및 각 구단과 무관한 비공식 팬 프로젝트**입니다. 등장하는 구단과 선수는 모두 가상입니다.

## 설치

아직 내려받아 바로 쓰는 배포 파일(.dmg, .zip)은 없다. 소스를 받아 직접 빌드한다.

**필요한 것**

- macOS 14 (Sonoma) 이상
- Xcode 16 이상 (Swift 6). App Store에서 설치한 뒤 한 번 실행해 둔다

**1. 받기**

```sh
git clone https://github.com/pokohen/token-baseball.git
cd token-baseball
```

git을 쓰지 않으면 GitHub 저장소 페이지의 **Code → Download ZIP**으로 받아 압축을 풀어도 된다.

**2. 앱 만들기**

```sh
Scripts/make-app.sh
```

`build/Token Baseball.app`이 생긴다. 처음에는 빌드에 1~2분 걸린다.

**3. 실행**

```sh
open "build/Token Baseball.app"
```

- 상단바(메뉴 막대)에 아이콘이 생긴다. Dock에는 나타나지 않는다.
- 아이콘을 누르면 구단 만들기 화면이 나온다.
- 처음 실행하면 알림을 허용할지 묻는다. 경기 종료와 득점 소식을 알림으로 받는다.
- 계속 쓰려면 앱을 응용 프로그램 폴더로 옮긴다: `cp -R "build/Token Baseball.app" /Applications/`
- 맥을 켤 때 자동으로 실행하려면 **시스템 설정 → 일반 → 로그인 항목**에 앱을 추가한다.
- 끝낼 때는 설정 탭의 **앱 종료**를 누른다.

직접 빌드한 앱이라 보통은 바로 열린다. ZIP으로 받았거나 다른 맥에서 만든 앱을 옮겨 와서 "확인되지 않은 개발자" 경고가 나오면, Finder에서 앱을 **우클릭 → 열기**로 한 번 열어 준다.

**업데이트**

```sh
git pull
Scripts/make-app.sh
```

실행 중인 앱을 끄고 새로 만든 앱으로 바꾼다. 저장 파일은 그대로 이어진다.

**삭제**

앱을 지우고, 저장 파일까지 없애려면 `~/Library/Application Support/TokenBaseball` 폴더를 지운다.

## 알아 둘 것

- 토큰 사용량은 `~/.claude/projects`(Claude Code)와 `~/.codex/sessions`(Codex)의 로컬 로그에서 읽는다. 외부로 보내지 않는다.
- 구단을 만든 뒤에 쓴 토큰만 자금이 된다. 20초마다 반영된다.
- 게임은 `~/Library/Application Support/TokenBaseball/save.json`에 저장된다. 이 파일을 복사해 두면 백업이 된다.
- 경기 기회는 1시간에 하나씩, 최대 3개까지 쌓인다. 경기 한 번은 실시간으로 15분쯤 걸리고 건너뛸 수 없다.

## 개발

```sh
swift run TokenBaseball        # 앱 번들 없이 바로 실행 (알림은 나오지 않음)
swift test                     # 테스트
TB_STRESS=1 swift test --filter StressTests   # 여러 시드 장기 시뮬레이션 (6분쯤)
```

진짜 구단을 건드리지 않고 시험하려면 저장 위치를 바꿔 실행한다.

```sh
TOKEN_BASEBALL_SAVE=/tmp/tb-test.json swift run TokenBaseball
```

## 구조

```
Sources/
  TokenBaseballCore/   게임 로직 (UI 의존 없음)
    Usage/             로컬 로그에서 토큰 사용량 읽기
    League/            리그, 팀, 일정, 순위
    Match/             투구 단위 경기 시뮬레이션
    Players/           선수 생성, 능력·잠재력
    Club/              자금 장부
    Persistence/       저장
    Game*.swift        게임 전체 상태와 명령 (경기, 세계 시뮬레이션, 시즌, 구단, 이적 시장)
    Balance.swift      조정할 수 있는 수치 모음
  TokenBaseball/       macOS 앱 (상단바, 팝오버, 설정)
Tests/
  TokenBaseballCoreTests/
```

기획 문서는 [docs](docs/README.md)에 있다.

## 개발용 환경 변수

| 변수 | 내용 |
|---|---|
| `TOKEN_BASEBALL_SAVE` | 저장 파일 위치를 바꾼다 |
| `TOKEN_BASEBALL_SNAPSHOT` | 각 화면을 이 폴더에 PNG로 그리고 끝낸다 (임시 게임 사용) |
