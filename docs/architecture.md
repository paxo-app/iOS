# 아키텍처

## 구성 요소

| 구성 요소 | 위치 | 역할 |
| --- | --- | --- |
| 메뉴바 앱 | `Paxo/` | 전역 단축키 → 화면 캡처 → 프록시 호출 → 결과 표시. (macOS 14+, SwiftUI + AppKit) |
| API 프록시 | `proxy-vercel/` | 서버에 Gemini API 키를 보관하고 클라이언트 대신 요청을 수행한다. (Vercel iad1 리전) |
| Gemini API | 외부 | 정답 및 해설 생성. 사용할 모델은 프록시 서버에서 결정한다. |
| StoreKit 2 · App Store | 외부 | Pro 요금제(월간/연간) 결제 처리 및 구독 상태 검증. |
| Apple 로그인 | 외부 | 사용자 인증. 이름·이메일 권한은 요청하지 않는다. |
| Upstash Redis | 외부 | 세션, 일일 사용량, 중복 요청 예약을 TTL과 함께 저장한다. |

## 단일 풀이 흐름 (Solve Flow)

```
단축키 ⌥⌘S 입력
  → ProxySessionManager        Apple 로그인 세션 및 서버 잔여량 확인
  → AppState.beginSolve        한도 초과 시 캡처 전 결제 화면 또는 안전 한도 안내 노출
  → SelectionOverlay           캡처 영역 선택 (전체 화면 모드일 경우 생략)
  → ScreenCapturer             ScreenCaptureKit 사용 (JPEG q0.82, 최대 2000px)
  → GeminiService              POST {프록시}/generate — 프록시 서버에 정답 요청
  → proxy-vercel/api/generate  Bearer 세션과 Redis 한도 검증 → 허용된 본문만 재조립 후 Gemini 호출
  → 결과 패널 및 토스트           UI에 정답 표시
  → (필요 시) 해설 요청          동일한 경로로 해설 추가 요청
```

- 정답과 해설은 각각 별도의 API 요청으로 처리한다.
- 무료 3회와 Pro 100회 한도는 Asia/Seoul 날짜 기준으로 서버에서 원자적으로 적용한다.
- 횟수는 '정답 요청'이 성공했을 때만 차감한다. 동일 풀이의 해설 1회는 추가 차감하지 않는다.
- 토스트 모드에서는 해설을 요청하지 않는다.

## 앱 ↔ 프록시 API 스펙 (Contract)

핵심 요약만 기재하며, 상세 스펙은 proxy-vercel/AGENTS.md를 정본으로 삼는다.

- 인증 엔드포인트: `POST /session/challenge`, `POST /session`, `POST /session/refresh`
- 생성 엔드포인트: `POST /generate`
- 생성 필수 헤더: `Authorization: Bearer <session>`, `x-paxo-token`
- 생성 본문: `kind`, `solveId`, 텍스트 파트 1개, 이미지 파트 1개만 허용한다. 그 밖의 필드는 400으로 거절한다.
- 변경 규칙: API 스펙 변경 시 Paxo/AI/GeminiService.swift(클라이언트)와 proxy-vercel/api/generate.js(서버)를 반드시 동일한 PR에서 수정한다. 배포는 프록시 서버가 선행되어야 한다.


## 데이터 저장소

| 데이터 | 저장 위치 및 방식 |
| --- | --- |
| 설정 · 단축키 | UserDefaults |
| 최근 풀이 기록 | 앱 컨테이너 내 `history.json` (최대 100개, 이미지는 제외) |
| 캡처 이미지 | 최근 8장만 메모리에 유지. 디스크에 저장(I/O)하지 않는다. |
| 로그인 유지 정보 | Mac Keychain의 불투명 갱신 토큰. 서버의 Apple 토큰은 AES-256-GCM 암호화 |
| 세션 · 사용량 · 풀이 상태 | Upstash Redis. Production/Preview 접두사 분리, TTL 적용 |
| 구독 상태 | 앱 UI는 StoreKit 2, 실제 AI 권한은 App Store Server API 검증 결과 |
| Gemini API 키 | Gemini API 키,프록시 서버의 환경 변수로 관리. 클라이언트 앱에는 절대 포함하지 않는다. |


## 배포 파이프라인

| 대상 | 배포 방식 | 실행 주체 | 
| --- | --- | --- |
| 프록시 | Vercel (Preview는 자동 배포, Production은 수동 배포) | 과금/프록시 담당자 |
| 앱 | develop → main 릴리스 PR 머지 → 태그 생성 → Xcode Archive → App Store Connect | 담당자 직접 실행 (수동) |
