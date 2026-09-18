# Paxo/ — Swift 앱 코드 작성 가이드

> 전역 규칙은 저장소 루트의 `AGENTS.md`를 참조한다. 본 문서에는 `Paxo/` 디렉터리 내 코드 작업 시 **실제로 밟기 쉬운 크리티컬한 함정(Gotchas)**만 기록한다.
> 코드베이스를 읽으면 파악할 수 있는 단순 구조나 타입 목록은 생략한다.

## 1. 아키텍처 및 코딩 컨벤션

* **상태 관리**: `@MainActor final class ... ObservableObject`와 `@Published` 속성 래퍼를 사용한다. (**Swift 5.9의 `@Observable` 매크로는 사용하지 않는다.**) 신규 코드 또한 기존 방식을 엄격히 따른다. 섞어 쓸 경우 의존성 주입 경로가 깨진다.
* **단일 원본 (Single Source of Truth)**: `AppState.shared` 싱글턴 객체가 앱 상태의 단일 원본 역할을 수행하며, `StoreManager`는 `AppState.store` 프로퍼티에 의해 소유된다.
* **에러 핸들링**: 도메인 에러는 `LocalizedError`를 채택한 `enum`으로 정의하고, `errorDescription`은 **반드시 한국어**로 작성한다 (`GeminiError`, `CaptureError` 참조).
* **파일 구조 표준**: `import` 구문 → 주 타입의 `///` 문서 주석 → 주 타입 정의 → `private` 헬퍼 메서드 → 파일 최하단 에러 `enum` 배치 순서를 엄수한다.

## 2. 빌드 시스템 주의사항

**`Paxo/` 디렉터리는 `PBXFileSystemSynchronizedRootGroup`으로 설정되어 있다.** 즉, 해당 디렉터리에 `.swift` 파일을 생성하면 자동으로 컴파일 대상에 포함된다.

* `project.pbxproj`의 `Sources` 빌드 페이즈는 의도적으로 비워두었다. **수동으로 파일을 추가하지 않는다.**
* 특정 파일을 빌드 대상에서 개별적으로 제외할 방법이 없으므로, 시크릿 템플릿 등 제외가 필요한 파일은 `Config/` 디렉터리에 둔다.
* 예제 코드나 백업용 `.swift` 파일을 해당 디렉터리에 방치하면 중복 선언 오류로 빌드가 깨진다.
* **소스 코드가 아닌 일반 파일도 앱 번들의 `Resources`에 자동으로 포함된다.** 현재 `.md` 파일만 `EXCLUDED_SOURCE_FILE_NAMES = "*.md"` 설정으로 방어해 둔 상태다. 다른 확장자의 비공개 파일을 잘못 추가하면 사용자와 App Store 심사관에게 그대로 노출되므로, 각별히 주의한다.

## 3. 런타임 크래시 유발 요인 (의존성 주입)

각 호스팅 뷰에는 필요한 객체만 **선택적으로 주입**된다.

| 뷰 (View) | 주입 객체 (`@EnvironmentObject`) |
| --- | --- |
| `MenuContentView`, `SettingsView` | `appState` + `store` |
| `ResultView`, `ToastView`, `OnboardingView` | `appState` **만 주입** |
| `PaywallView` | `store` **만 주입** |

**위 표에 명시되지 않은 객체를 뷰에서 `@EnvironmentObject`로 선언할 경우 런타임 크래시가 발생한다.** 의존성 추가가 불가피하다면 해당 컨트롤러(`ResultPanelController`, `ToastController` 등)의 뷰 초기화/주입 로직을 함께 수정해야 한다.

## 4. 로직 삭제 및 수정 엄금 (Do Not Remove)

* `AppState.hotkey`의 `didSet`에 포함된 `isRevertingHotkey` 플래그: 단축키 등록 실패 시 상태를 롤백하는 역할을 하며, 해당 플래그가 없으면 무한 재귀(Infinite Recursion)에 빠진다. `launchAtLogin`의 `isSyncingLaunchAtLogin` 플래그도 동일한 이유로 유지해야 한다.
* `ScreenCapturer`의 **PID 필터링과 150ms Sleep 로직**: 둘 모두 앱 자신의 윈도우(패널)를 캡처 영역에서 제외하기 위한 필수 방어 장치다. 하나라도 누락되면 캡처된 이미지 안에 결과 패널이 찍혀 나오는 버그가 발생한다.

## 5. 도메인 특수성 및 기술적 함정 (Gotchas)

* **이미지 포맷**: 캡처 결과물은 항상 **JPEG** 포맷이다 (PNG 가정 금지). 용량 최적화를 위해 `compressionFactor 0.82`, 최대 2000px로 리사이징(축소)한다.
* **이중 좌표계**: AppKit은 좌하단(Bottom-Left)이 원점이고, 디스플레이 로컬 좌표계는 좌상단(Top-Left)이 원점이다. `ScreenCapturer`에서 이를 변환하여 사용하며, `PanelPosition.origin`은 AppKit 기준을 가정한다. 이는 다중 모니터 대응 시 가장 잦은 버그 발생 원인이므로 주의한다.
* **백그라운드 실행 (`LSUIElement = true`)**: Dock 아이콘이 없는 백그라운드 앱이므로 창을 화면에 띄우려면 `NSApp.activate(ignoringOtherApps:)`, `.nonactivatingPanel`, `orderFrontRegardless()` 등의 명시적 호출이 필수다. `SettingsLink` 조차 활성화 제스처를 덧붙여야 정상 작동한다.
* **화면 기록 권한(TCC) 정책**: 권한 승인 플로우 특성상 **앱을 2회 실행해야 정상 작동**한다. `CGRequestScreenCaptureAccess()`는 권한 요청만 띄우고 즉시 `false`를 반환하므로 최초 캡처 시도는 항상 실패하는 것이 시스템 정상 스펙이다. (Xcode 재빌드 시 권한이 조용히 말소될 수 있음에 유의한다.)
* **이미지 캐시 무상태성**: `imageCache`는 인메모리 상에서 최대 8개까지만 유지되며 디스크에 영속화(Persist)하지 않는다. 과거 히스토리 항목에서 해설을 재생성할 수 없는 것은 버그가 아니라 의도된 설계다.
* **단축키 API**: 손쉬운 사용(Accessibility) 권한 요구를 피하고 Mac App Store 심사를 통과하기 위해 Carbon의 `RegisterEventHotKey` API를 사용한다. 절대 다른 API로 교체하지 않는다.

## 6. 과금 비즈니스 로직 (수정 전 필독)

무료 사용량 차감 규칙은 비대칭적이며, 이는 서비스 매출과 직결되는 핵심 경로(Critical Path)다.

* 무료 횟수는 **API 정답 호출이 성공한 직후에만** 1회 차감한다.
* 해설 생성(2차 호출)이 실패하더라도 **횟수를 재차감하지 않는다.** (정답을 이미 제공받았기 때문)
* 무료 횟수 소진 여부 및 페이월(Paywall) 표시는 **캡처를 실행하기 전**에 사전 검증한다.
* 토스트 모드(Toast Mode)에서는 의도적으로 해설 API를 호출하지 않도록 제어해야 한다.
