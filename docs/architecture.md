# 아키텍처

## 구성 요소

| 구성 요소 | 위치 | 역할 |
| --- | --- | --- |
| 메뉴바 앱 | `Paxo/` | 전역 단축키 → 화면 캡처 → 프록시 호출 → 결과 표시. (macOS 14+, SwiftUI + AppKit) |
| API 프록시 | `proxy-vercel/` | 서버에 Gemini API 키를 보관하고 클라이언트 대신 요청을 수행한다. (Vercel iad1 리전) |
| Gemini API | 외부 | 정답 및 해설 생성. 사용할 모델은 프록시 서버에서 결정한다. |
| StoreKit 2 · App Store | 외부 | 소모성 풀이권 결제, 서명 거래·환불 검증, 기존 구독 잔여 기간 검증. |
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
- 무료 2회는 매일 오전 6시(Asia/Seoul)에 초기화한다. 무료분을 먼저 사용하고 충전 풀이권을 차감한다. 충전 잔량에는 만료와 일일 상한이 없다. 기존 구독의 유효 기간에는 일일 100회를 유지한다.
- 횟수는 '정답 요청'이 성공했을 때만 차감한다. 동일 풀이의 해설 1회는 추가 차감하지 않는다.
- 토스트 모드에서는 해설을 요청하지 않는다.
- 정답 · 해설 요청 3초 후부터 취소할 수 있다. 정답 확정 전에 취소하면 무료 횟수를 차감하지 않으며, 취소나 기록 전환 뒤에 도착한 응답은 `SolveRequestGate`가 버린다.

## 앱 ↔ 프록시 API 스펙 (Contract)

핵심 요약만 기재하며, 상세 스펙은 proxy-vercel/AGENTS.md를 정본으로 삼는다.

- 인증 엔드포인트: `POST /session/challenge`, `POST /session`, `POST /session/refresh`
- 충전 엔드포인트: `POST /purchases`. 로그인 세션과 서명 거래를 검증해 한 번만 적립하며 응답의 `creditBalance`를 반영한 뒤 StoreKit 거래를 완료한다.
- 세션의 `remainingToday`는 일일 제공량, `creditBalance`는 별도 충전 잔량이다. 생성 응답도 `x-paxo-remaining`과 `x-paxo-credit-balance`로 구분한다.
- `creditRevision`과 `storeEnvironment`로 같은 계정·결제 환경의 최신 잔액만 반영한다. Production과 Sandbox의 잔량은 합산하지 않는다.
- 생성 엔드포인트: `POST /generate`
- 생성 필수 헤더: `Authorization: Bearer <session>`, `x-paxo-token`
- 구조화 생성: `x-paxo-response-format: structured-v1`. 해설에는 선택지 검증용 `x-paxo-answer-context` JSON 헤더를 추가한다. 앱과 프록시가 같은 응답 규격을 검증하며 표시용 Markdown 제목은 앱이 만든다.
- 생성 완료 검증: `STOP` 및 응답 형식을 검증한 뒤 성공으로 확정한다. 잘림·형식 오류에는 같은 서버 예약 안에서 한 번만 재생성하고, 최종 실패에는 정답 사용량을 차감하지 않는다.
- 생성 본문: `kind`, `solveId`, 텍스트 파트 1개, 이미지 파트 1개만 허용한다. 그 밖의 필드는 400으로 거절한다.
- 변경 규칙: API 스펙 변경 시 Paxo/AI/GeminiService.swift(클라이언트)와 proxy-vercel/api/generate.js(서버)를 반드시 동일한 PR에서 수정한다. 배포는 프록시 서버가 선행되어야 한다.


## 데이터 저장소

| 데이터 | 저장 위치 및 방식 |
| --- | --- |
| 설정 · 단축키 | UserDefaults |
| 최근 풀이 기록 | 앱 컨테이너 내 `Paxo/history.json` (최대 100개, 날짜·정답·해설·자가 채점·이미지 파일명·선택적 문제 유형 및 선택지 번호) |
| 캡처 이미지 | 정답 호출에 성공한 이미지는 `Paxo/HistoryImages/<UUID>.jpg`에 저장한다. 메모리 캐시는 최대 8장이고, 보관 기록에서 빠진 이미지는 정리한다. |
| 로그인 유지 정보 | Mac Keychain의 불투명 갱신 토큰. 서버의 Apple 토큰은 AES-256-GCM 암호화 |
| 세션 · 사용량 · 풀이 상태 | Upstash Redis. Production/Preview 접두사 분리, TTL 적용 |
| 충전 잔량 · 거래 원장 | 서버 Redis에 TTL 없이 저장. 로그인 만료·로그아웃으로 소멸하지 않는다. 중복 거래는 재적립하지 않는다. |
| 기존 구독 상태 | App Store Server API 검증 결과. 기존 구매 기간 보호용이며 신규 판매하지 않는다. |
| Gemini API 키 | Gemini API 키,프록시 서버의 환경 변수로 관리. 클라이언트 앱에는 절대 포함하지 않는다. |

풀이 기록 상세에서 개별 기록을, 설정의 풀이 기록 탭에서 보관된 전체 기록을 삭제한다.
전체 삭제는 검색·날짜·과목 필터와 관계없이 적용하며, 과목 목록과 앱 설정은 유지한다.
`AppState`는 기록 파일을 먼저 저장한 뒤 삭제된 기록의 메모리 캐시와 과목 지정을 정리한다.
이미지 정리는 기록 저장 후 실행하며 실패하면 사용자에게 재시도를 안내한다. 다음 실행에서도 남은 이미지를 다시 정리한다.
기록을 읽지 못하면 기존 데이터 보호를 위해 저장·삭제·이미지 정리를 멈춘다.
삭제된 풀이의 늦은 해설은 버리며 로그아웃·서버 계정 삭제는 로컬 기록과 이미지를 삭제하지 않는다.

Preview 프록시는 Sandbox 거래만 검증한다. Production 프록시는 실제 판매 거래를 Production에서
우선 검증하고 TestFlight와 App Review의 Sandbox 거래는 독립된 Sandbox 검증기와 API 클라이언트로
처리한다. 거래 식별자 해시에는 검증 환경을 포함해 두 환경의 ID 공간을 분리한다.


## 배포 파이프라인

| 대상 | 배포 방식 | 실행 주체 | 
| --- | --- | --- |
| 프록시 | Vercel (Preview는 자동 배포, Production은 수동 배포) | 과금/프록시 담당자 |
| 앱 | develop → main 릴리스 PR 머지 → 태그 생성 → Xcode Archive → App Store Connect | 담당자 직접 실행 (수동) |
