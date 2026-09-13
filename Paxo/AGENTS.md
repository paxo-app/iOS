# Paxo/ — Swift 앱 코드

전역 규칙은 저장소 루트의 `AGENTS.md`를 따른다. 여기에는 **이 디렉토리에서 실제로 밟게 되는 함정**만 적는다.
구조나 타입 목록은 코드를 읽으면 알 수 있으므로 적지 않는다.

## 아키텍처 관례

- 상태 관리는 `@MainActor final class ... ObservableObject` + `@Published`다. **`@Observable`이 아니다.**
  새 코드도 기존 방식을 따른다. 섞으면 주입 경로가 깨진다.
- `AppState.shared` 싱글턴이 앱 상태의 단일 원본이고, `StoreManager`는 `AppState.store`로 소유된다.
- 도메인 에러는 `enum: LocalizedError` + **한국어 `errorDescription`**으로 만든다 (`GeminiError`, `CaptureError` 참고).
- 파일 배치: import → 주 타입의 `///` 문서 주석 → 타입 → `private` 헬퍼 → 파일 맨 아래 에러 enum.

## 빌드 시스템

**`Paxo/`는 `PBXFileSystemSynchronizedRootGroup`이다.**
이 디렉토리에 `.swift` 파일을 넣으면 자동으로 컴파일 대상이 된다.

- `project.pbxproj`의 `Sources` 빌드 페이즈는 의도적으로 비어 있다. **채우려 하지 말 것.**
- 파일을 빌드에서 제외할 방법이 없다. 그래서 시크릿 템플릿이 `Config/`에 있다.
- 예제·백업 `.swift` 파일을 이 디렉토리에 두면 중복 선언으로 빌드가 깨진다.
- **소스가 아닌 파일도 자동으로 앱 번들 Resources에 들어간다.** 이 디렉토리의 `.md`는
  `EXCLUDED_SOURCE_FILE_NAMES = "*.md"` 빌드 설정으로 막아뒀다. 다른 확장자의 내부 파일을
  여기 두면 사용자와 심사원에게 배포되므로, 넣기 전에 번들에 들어가는지 확인한다.

## 크래시로 이어지는 것

**`@EnvironmentObject`는 호스팅 뷰마다 선택적으로 주입된다.**

| 뷰 | 주입받는 것 |
|---|---|
| `MenuContentView`, `SettingsView` | `appState` + `store` |
| `ResultView`, `ToastView`, `OnboardingView` | `appState` **만** |
| `PaywallView` | `store` **만** |

오른쪽 열에 없는 것을 `@EnvironmentObject`로 선언하면 **런타임에 크래시한다.**
필요하면 해당 컨트롤러(`ResultPanelController`, `ToastController` 등)의 주입 지점을 함께 고쳐야 한다.

## 제거하면 안 되는 것

- `AppState.hotkey`의 `didSet`에 있는 `isRevertingHotkey` 플래그 — 단축키 등록 실패 시 되돌리는데,
  이 플래그가 없으면 `didSet`이 무한 재귀한다. `launchAtLogin`의 `isSyncingLaunchAtLogin`도 같다.
- `ScreenCapturer`의 **PID 필터와 150ms sleep 두 가지 모두** — 자기 창을 캡처에서 빼는 장치다.
  하나만 빼도 결과 패널이 캡처 이미지 안에 찍힌다.

## 알아야 사고를 피하는 것

- **캡처 결과는 JPEG다.** PNG를 가정하지 않는다. `compressionFactor 0.82`, 최대 2000px로 축소한다.
- **좌표계가 2개다.** AppKit은 좌하단 원점, 디스플레이 로컬은 좌상단 원점이다.
  `ScreenCapturer`에서 변환하고, `PanelPosition.origin`은 AppKit 기준을 가정한다. 다중 모니터 버그의 단골 원인.
- **`LSUIElement = true`**라 Dock 아이콘이 없다. 창을 띄우려면 `NSApp.activate(ignoringOtherApps:)`,
  `.nonactivatingPanel`, `orderFrontRegardless()`가 필요하다. `SettingsLink`조차 활성화 제스처를 덧붙여야 열린다.
- **화면 기록 권한(TCC)은 2회 실행이 필요하다.** `CGRequestScreenCaptureAccess()`는 요청만 하고 `false`를 반환한다.
  첫 캡처는 항상 실패하는 것이 정상이다. Xcode에서 재빌드하면 권한이 조용히 풀릴 수 있다.
- **`imageCache`는 인메모리 8개 한도이고 영속화하지 않는다.** 이전 실행의 히스토리 항목은
  해설을 재생성할 수 없다. 버그가 아니라 설계다.
- 단축키는 Carbon `RegisterEventHotKey`를 쓴다. 손쉬운 사용 권한이 필요 없고 MAS 심사를 통과하기 때문이다.
  다른 API로 바꾸지 말 것.

## 과금 로직 — 건드리기 전에 읽을 것

무료 사용량 차감 규칙이 비대칭이고, 이건 매출에 직결된다.

- 차감은 **정답 호출이 성공한 뒤에만** 일어난다.
- 해설 생성이 실패해도 **재차감하지 않는다.** 정답은 이미 받았기 때문이다.
- 페이월은 **캡처 전에** 검사한다. 캡처 후가 아니다.
- 토스트 모드는 **의도적으로 해설을 생성하지 않는다.**

## App Store 심사 제약

포지셔닝은 "풀이·해설 학습 도우미"다. **해설은 접을 수는 있어도 제거할 수 없다.**
빠른 채점 모드도 해설을 숨기는 게 아니라 클릭 뒤로 접어두는 것뿐이다. 이 성질을 깨는 변경은 심사에서 문제가 된다.
