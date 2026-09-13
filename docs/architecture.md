# 아키텍처

> 상태: 초안 — 킥오프 후 전원 검증. AI 리뷰가 읽는 문서다. 코드와 어긋나면 기록성 이슈로 바로 고친다.

## 구성 요소

| 구성 요소 | 위치 | 역할 |
| --- | --- | --- |
| 메뉴바 앱 | `Paxo/` | 전역 단축키 → 화면 캡처 → 프록시 호출 → 결과 표시. macOS 14+, SwiftUI + AppKit |
| API 프록시 | `proxy-vercel/` | Gemini API 키를 서버에 두고 요청을 대신 보낸다. Vercel `iad1` 리전 |
| Gemini API | 외부 | 정답 · 해설 생성. 모델은 프록시가 정한다 |
| StoreKit 2 · App Store | 외부 | Pro 구독(월간 · 연간) 결제와 권한 확인 |
| 레거시 프록시 | `proxy/` | Cloudflare Worker 백업. 신규 작업하지 않는다 |

## 한 번의 풀이 흐름

```
단축키 ⌥⌘S
  → AppState.beginSolve        무료 사용량 · Pro 확인 (부족하면 캡처 전에 페이월)
  → SelectionOverlay           영역 선택 (전체 화면 모드면 생략)
  → ScreenCapturer             ScreenCaptureKit, JPEG q0.82, 최대 2000px
  → GeminiService              POST {프록시}/generate — 정답 요청
  → proxy-vercel/api/generate  헤더 검증 → 본문을 허용 형태로 재조립 → Gemini
  → 결과 패널 · 토스트          정답 표시
  → (필요 시) 해설 요청         같은 경로로 한 번 더
```

- 정답과 해설은 따로 요청한다. 정답을 먼저 보여주기 위해서다
- 무료 사용량은 정답 요청이 성공한 뒤에만 차감한다. 해설 실패는 다시 차감하지 않는다
- 토스트 모드는 해설을 요청하지 않는다

## 앱 ↔ 프록시 계약

요약만 적는다. 정본은 `proxy-vercel/AGENTS.md`.

- `POST /generate`, 헤더 `x-paxo-device`(UUID) · `x-paxo-token`
- 본문은 텍스트 파트 1개 + 이미지 파트 1개만 허용한다. 프록시가 허용 목록으로 다시 조립하므로 다른 필드는 전달되지 않는다
- 계약을 바꾸면 `Paxo/AI/GeminiService.swift`와 `proxy-vercel/api/generate.js`를 **같은 PR**에서 고치고, 배포는 프록시가 먼저다

## 데이터가 있는 곳

| 데이터 | 위치 |
| --- | --- |
| 설정 · 단축키 · 무료 사용량 | UserDefaults |
| 풀이 기록 (최대 100개, 이미지 제외) | 앱 컨테이너의 `history.json` |
| 캡처 이미지 | 메모리에만 최근 8개. 디스크에 쓰지 않는다 |
| 구독 상태 | StoreKit 2 `Transaction.currentEntitlements` |
| Gemini API 키 | 프록시 환경변수. 앱에는 없다 |

## 배포

| 대상 | 방법 | 실행 |
| --- | --- | --- |
| 프록시 | Vercel. 프리뷰는 자동, 프로덕션은 사람이 실행 | 과금 · 프록시 가디언 |
| 앱 | develop → main 릴리즈 PR, 태그, Xcode Archive → App Store Connect | 사람만 |
