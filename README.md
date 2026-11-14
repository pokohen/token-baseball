# Token Baseball

AI 코딩 도구에서 쓴 토큰이 **구단 자금**이 되는 macOS 메뉴바 야구단 육성 게임.
시민 야구단으로 시작해 6부 리그의 최상위 프로 리그까지 올라가는 것이 목표다.

> Token Baseball은 **KBO 및 각 구단과 무관한 비공식 팬 프로젝트**입니다. 등장하는 구단과 선수는 모두 가상입니다.

## 실행

macOS 14 이상, Swift 6 (Xcode 16 이상)이 필요하다.

```sh
swift run TokenBaseball        # 바로 실행 (알림은 나오지 않음)
Scripts/make-app.sh            # build/Token Baseball.app 만들기 (알림 포함)
swift test                     # 테스트
```

- 토큰 사용량은 `~/.claude/projects`(Claude Code)와 `~/.codex/sessions`(Codex)의 로컬 로그에서 읽는다. 외부로 보내지 않는다.
- 게임은 `~/Library/Application Support/TokenBaseball/save.json`에 저장된다.
- 구단을 만든 뒤에 쓴 토큰만 센다.

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
