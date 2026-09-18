# 아키텍처

## 구성 요소

| 구성 요소 | 위치 | 역할 |
| --- | --- | --- |
| 메뉴바 앱 | `Paxo/` | 전역 단축키 → 화면 캡처 → 프록시 호출 → 결과 표시. (macOS 14+, SwiftUI + AppKit) |
| API 프록시 | `proxy-vercel/` | 서버에 Gemini API 키를 보관하고 클라이언트 대신 요청을 수행한다. (Vercel iad1 리전) |
| Gemini API | 외부 | 정답 및 해설 생성. 사용할 모델은 프록시 서버에서 결정한다. |
| StoreKit 2 · App Store | 외부 | Pro 요금제(월간/연간) 결제 처리 및 구독 상태 검증. |
| 레거시 프록시 | `proxy/` | Cloudflare Worker 기반의 백업용 프록시. 신규 개발은 진행하지 않는다. |

## 단일 풀이 흐름 (Solve Flow)

```
단축키 ⌥⌘S 입력
  → AppState.beginSolve        무료 제공량 및 Pro 구독 여부 확인 (한도 초과 시 캡처 전 결제 화면 노출)
  → SelectionOverlay           캡처 영역 선택 (전체 화면 모드일 경우 생략)
  → ScreenCapturer             ScreenCaptureKit 사용 (JPEG q0.82, 최대 2000px)
  → GeminiService              POST {프록시}/generate — 프록시 서버에 정답 요청
  → proxy-vercel/api/generate  요청 헤더 검증 → 본문을 허용된 스펙으로 재조립 후 Gemini 호출
  → 결과 패널 및 토스트           UI에 정답 표시
  → (필요 시) 해설 요청          동일한 경로로 해설 추가 요청
```

- 정답과 해설은 각각 별도의 API 요청으로 처리한다.
- 무료 횟수는 '정답 요청'이 성공했을 때만 차감한다. 해설 요청 실패 시에는 추가로 차감하지 않는다.
- 토스트 모드에서는 해설을 요청하지 않는다.

## 앱 ↔ 프록시 API 스펙 (Contract)

핵심 요약만 기재하며, 상세 스펙은 proxy-vercel/AGENTS.md를 정본으로 삼는다.

- 엔드포인트: POST /generate
- 필수 헤더: x-paxo-device (UUID), x-paxo-token
- 본문(Body): 텍스트 파트 1개, 이미지 파트 1개만 허용한다. 프록시 서버에서 허용된 필드만 추출해 재조립하므로, 이외의 필드는 전송해도 무시된다.
- 변경 규칙: API 스펙 변경 시 Paxo/AI/GeminiService.swift(클라이언트)와 proxy-vercel/api/generate.js(서버)를 반드시 동일한 PR에서 수정한다. 배포는 프록시 서버가 선행되어야 한다.


## 데이터 저장소

| 데이터 | 저장 위치 및 방식 |
| --- | --- |
| 설정 · 단축키 · 무료 사용량 | UserDefaults |
| 최근 풀이 기록 | 앱 컨테이너 내 `history.json` (최대 100개, 이미지는 제외) |
| 캡처 이미지 | 최근 8장만 메모리에 유지. 디스크에 저장(I/O)하지 않는다. |
| 구독 상태 | StoreKit 2 `Transaction.currentEntitlements` |
| Gemini API 키 | Gemini API 키,프록시 서버의 환경 변수로 관리. 클라이언트 앱에는 절대 포함하지 않는다. |


## 배포 파이프라인

| 대상 | 배포 방식 | 실행 주체 | 
| --- | --- | --- |
| 프록시 | Vercel (Preview는 자동 배포, Production은 수동 배포) | 과금/프록시 담당자 |
| 앱 | develop → main 릴리스 PR 머지 → 태그 생성 → Xcode Archive → App Store Connect | 담당자 직접 실행 (수동) |
