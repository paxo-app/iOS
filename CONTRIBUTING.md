# 기여 가이드 (Contributing Guide)

AI 에이전트 전용 규칙은 [`AGENTS.md`](AGENTS.md)를 참조한다. 본 문서는 팀에 새로 합류한 개발자가 초기 셋업 및 기여를 위해 알아야 할 필수 사항만 다룬다.

## 1. 초기 셋업 (Initial Setup)

```sh
git clone https://github.com/paxo-app/iOS.git
cd iOS
cp Config/Secrets.example.swift Paxo/Secrets.swift   # 누락 시 빌드 실패
# 생성된 파일의 appToken 필드에 발급받은 팀 토큰 값을 입력한다 (비워둘 경우 AI 호출 401 에러)
open Paxo.
```

1. Xcode의 **Signing & Capabilities → Team**을 본인 계정으로 변경한 후 앱을 실행(Run)한다.
2. macOS TCC(투명성, 동의 및 제어) 정책에 따라, 최초 캡처 시 '화면 기록 권한'을 허용한 후 **반드시 앱을 완전히 종료하고 재실행**해야 정상 동작한다.

⚠️ **주의: 프록시 서버에는 이미 `APP_TOKEN` 검증이 활성화되어 있다.**
`Paxo/Secrets.swift` 내의 `appToken` 값을 비워두면 앱 빌드와 실행은 성공하지만, AI API 호출 시 전부 401(Unauthorized) 에러가 발생한다. 토큰 값은 팀 내 담당자에게 요청한다. (팀 내부 테스트용 토큰은 프로덕션과 분리된 `APP_TOKEN_PREV` 슬롯을 사용한다.)

> **정식 팀원 온보딩**
> 정규 팀원인 경우 운영 규칙과 온보딩 문서가 포함된 사내 비공개 저장소도 클론해야 한다. 클론 후 `docs/private/README.md`를 최우선으로 확인한다.
> `git clone [https://github.com/paxo-app/internal.git](https://github.com/paxo-app/internal.git) docs/private`

## 2. 작업 흐름 (Workflow)

```sh
git fetch origin
git switch -c feat/feature-name origin/develop
# 코드 작업 진행
xcodebuild -project Paxo.xcodeproj -scheme Paxo -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO test
xcrun swift-format lint --recursive --strict --configuration .swift-format Paxo PaxoTests
git push -u origin HEAD
gh pr create --base develop

```

`develop` 및 `main` 브랜치는 보호(Protected)되어 있으므로 직접 푸시(Direct Push)가 불가하며 반드시 PR을 거쳐야 한다.

* **`develop`**: 신규 기능 PR은 **Squash and Merge** 방식으로 병합한다. 일반적인 변경 사항은 리뷰어 승인 없이 CI를 통과(Green)하면 작성자가 직접 머지할 수 있다. 단, **과금, 프록시, 릴리스 설정 파일 등 핵심(위험) 경로 수정 시에는 반드시 CODEOWNERS의 승인이 필요**하다.
* **`main`**: 릴리스 PR(`develop` → `main`)만 허용하며, **Create a merge commit (Regular Merge)** 방식으로 병합한다. 배포 전 리뷰어 최소 1명의 승인이 필수다. (Squash 병합 시 커밋 히스토리가 꼬여 다음 릴리스 PR에 이전 변경 사항이 중복 노출되므로 절대 금지한다.)

## 3. 커밋 메시지 컨벤션

`Conventional Commits` 표준 접두사 + **한국어 제목** 형태로 작성한다.

```text
feat: 캡처 영역을 마지막 선택으로 기억

- 재캡처 시 이전 영역을 기본값으로 제시
- 화면이 바뀌면 무시하고 전체 화면으로 폴백

```

**커밋 메시지에 AI 사용 여부나 초안 작성 내역을 표기하지 않는다.**
코드의 초안을 누가 작성했든, 이를 커밋(반영)한 담당자가 최종 결과물에 대한 모든 책임을 진다. 상세 원칙은 [`docs/ai-usage-rules.md`](docs/ai-usage-rules.md)를 참고한다.

## 4. 트러블슈팅 (Troubleshooting)

| 증상 | 원인 및 해결 |
| --- | --- |
| `cannot find 'Secrets' in scope` | `Paxo/Secrets.swift` 파일이 생성되지 않음 |
| AI API 호출 시 401 에러 발생 | `Paxo/Secrets.swift` 내 `appToken` 값이 누락되었거나 불일치함 |
| `Secrets` 중복 선언 빌드 에러 | 템플릿 원본을 `Paxo/` 내부에 중복으로 복사함 (템플릿은 `Config/` 에 유지해야 함) |
| 캡처 시 화면 기록 권한 오류 반복 | 시스템 권한 허용 후 앱을 완전히 종료(Quit)하고 재실행하지 않음 |
| 캡처 이미지에 결과 패널이 찍힘 | `ScreenCapturer`의 PID 필터 로직이나 sleep 타이밍을 잘못 수정함 |
| 뷰 진입 시 런타임 크래시 발생 | 상위 뷰에서 주입하지 않은 `@EnvironmentObject`를 선언함. 상세 의존성은 [`Paxo/AGENTS.md`](Paxo/AGENTS.md) 표 참조 |

## 5. 프로젝트 지표 (Metrics)

```sh
scripts/ax-metrics.sh 30

```

PR 리드 타임(Lead Time)과 CI 통과율 등 프로젝트 건전성을 집계한다. 팀의 퍼포먼스는 막연한 체감이 아닌 **실제 데이터(숫자)를 기반으로 평가하고 개선**한다.

## 6. 라이선스 (License)

본 저장소에 기여한 모든 코드는 [MIT 라이선스](LICENSE) 정책을 따른다.
