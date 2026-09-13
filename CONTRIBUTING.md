# 기여 가이드

AI 에이전트용 규칙은 [`AGENTS.md`](AGENTS.md)에 있다. 사람이 처음 합류할 때 필요한 것만 여기 적는다.

## 처음 한 번

```sh
git clone https://github.com/paxo-app/iOS.git
cd iOS
cp Config/Secrets.example.swift Paxo/Secrets.swift   # 없으면 빌드 실패
# 만든 파일의 appToken 에 팀에서 받은 토큰 값을 채운다 (비우면 AI 호출이 401)
open Paxo.xcodeproj
```

Xcode에서 Signing & Capabilities → Team을 본인 계정으로 바꾸고 Run.
첫 캡처 시 **화면 기록 권한**을 허용한 뒤 앱을 재실행해야 한다 (macOS TCC 특성).

⚠️ **프록시에는 이미 `APP_TOKEN` 검증이 켜져 있다.** `Paxo/Secrets.swift`의 `appToken`을
비워두면 빌드·실행은 되지만 AI 호출이 전부 401로 실패한다. 토큰 값은 팀에 요청한다.
팀 테스트용 토큰은 프로덕션과 분리된 `APP_TOKEN_PREV` 슬롯을 쓴다.

맥북·Xcode가 처음이라면 main의 `docs/team-onboarding.md`를 먼저 본다.

## 작업 흐름

```sh
git switch -c feat/무엇을-한다
# 작업
xcodebuild -project Paxo.xcodeproj -scheme Paxo -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO test
xcrun swift-format lint --recursive --strict --configuration .swift-format Paxo PaxoTests
git push -u origin HEAD
gh pr create
```

`main`은 보호돼 있다. 직접 푸시할 수 없고 PR과 CI 통과가 필요하다.
리뷰어 승인은 필수가 아니므로 CI가 초록이면 본인이 머지한다.

## 커밋

Conventional Commits 접두사 + 한국어 제목.

```
feat: 캡처 영역을 마지막 선택으로 기억

- 재캡처 시 이전 영역을 기본값으로 제시
- 화면이 바뀌면 무시하고 전체 화면으로 폴백
```

**AI가 초안을 썼는지는 적지 않는다.** 커밋한 사람이 전적으로 책임진다.
자세한 내용은 [`docs/ai-usage-rules.md`](docs/ai-usage-rules.md).

## 자주 걸리는 것

| 증상 | 원인 |
|---|---|
| `cannot find 'Secrets' in scope` | `Paxo/Secrets.swift`를 안 만들었다 |
| AI 호출이 401 | `Paxo/Secrets.swift`의 `appToken`이 비었거나 값이 틀렸다 |
| `Secrets` 중복 선언 | 템플릿을 `Paxo/` 안에 복사했다. `Config/`에 둬야 한다 |
| 캡처 시 권한 오류 반복 | 권한 허용 후 앱을 재실행해야 한다 |
| 결과 패널이 캡처 이미지에 찍힘 | `ScreenCapturer`의 PID 필터나 sleep을 건드렸다 |
| 뷰에서 런타임 크래시 | 주입받지 않는 `@EnvironmentObject`를 선언했다 — [`Paxo/AGENTS.md`](Paxo/AGENTS.md) 표 확인 |

## 지표

```sh
scripts/ax-metrics.sh 30
```

PR 리드타임과 CI 통과율을 집계한다. 체감이 아니라 숫자로 본다.
