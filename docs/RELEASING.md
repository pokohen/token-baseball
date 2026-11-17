# 배포 파일 만들기

받아서 바로 열 수 있는 `.dmg`를 만들어 GitHub Releases에 올리는 방법이다. 인증서가 있는 맥에서 한다.

## 한 번만 준비하는 것

1. **Developer ID Application 인증서**가 키체인에 있어야 한다.
   - 계정 소유자만 만들 수 있다. Xcode에서 "계정 소유자만 할 수 있다"고 막히면 웹에서 만든다: 키체인 접근 → 인증서 지원 → "인증 기관에서 인증서 요청…"으로 요청 파일을 저장하고, developer.apple.com → Certificates → `+` → Developer ID Application에 올린 뒤 받은 `.cer`를 더블클릭한다.
   - 확인: `security find-identity -v -p codesigning`에 `Developer ID Application: …`이 나온다.
2. **공증용 로그인 정보**를 키체인에 넣는다. 암호는 account.apple.com에서 만든 **앱 암호**다 (Apple ID 로그인 암호가 아니다). 암호를 타이핑해야 하므로 터미널 앱에서 실행한다.

   ```sh
   xcrun notarytool store-credentials "token-sport" --apple-id "애플ID" --team-id "팀ID"
   ```

## 새 버전 내기

```sh
Scripts/release.sh 0.2.0            # build/TokenSport-0.2.0.dmg 를 만든다
Scripts/release.sh 0.2.0 --publish  # 만든 뒤 GitHub Releases에 v0.2.0으로 올린다
```

스크립트가 하는 일:

1. 커밋하지 않은 변경이 있으면 멈춘다 (배포 파일은 커밋된 코드로만 만든다).
2. 인텔 맥과 애플 실리콘 맥 모두에서 도는 앱을 만들고, 버전을 적는다.
3. Developer ID로 서명한다 (hardened runtime, 타임스탬프).
4. 앱과 응용 프로그램 폴더 바로가기를 담은 `.dmg`를 만들고 서명한다.
5. Apple에 공증을 요청하고 끝날 때까지 기다린 뒤, 공증 표를 `.dmg`에 붙인다. 보통 1~5분이지만 계정에서 처음 할 때는 훨씬 오래 걸릴 수 있다.
6. `spctl`로 다른 맥에서 열리는 상태인지 검사한다.
7. `--publish`를 주면 `gh release create`로 올린다. 변경 내용은 GitHub가 자동으로 적는다.

공증이 오래 걸려 스크립트가 끊겼으면 상태를 보고, 끝난 뒤 이어서 한다.

```sh
xcrun notarytool history --keychain-profile "token-sport"
xcrun stapler staple build/TokenSport-0.2.0.dmg
```

## 올린 뒤에 일어나는 일

- **설치 명령**(`curl … install.sh | bash`)이 이 `.dmg`를 내려받아 설치한다. Xcode가 없어도 된다.
- **배포 파일로 설치한 앱**은 켤 때와 여섯 시간마다 최신 배포 버전을 확인한다. 더 높은 버전이 올라와 있으면 알림과 함께 설정 탭에 표시한다.
- 소스로 직접 만든 앱(`Scripts/make-app.sh`)은 예전처럼 `main`의 최신 커밋과 비교한다.

`main`에 올리는 것만으로는 배포 파일로 설치한 사람에게 새 버전이 가지 않는다. **새 버전을 낼 때마다 이 스크립트를 돌려야 한다.**

## 버전 번호

`주.부.수` 세 자리 (예: `0.2.0`). 태그는 앞에 `v`가 붙는다 (`v0.2.0`). 앱은 숫자로 비교하므로 `0.10.0`이 `0.9.3`보다 높다.
