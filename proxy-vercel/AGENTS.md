# proxy-vercel/ — API 프록시 서버 (주요 경로)

> 전역 규칙은 저장소 루트의 `AGENTS.md`를 참조한다.

클라이언트(앱)는 Gemini API를 직접 호출하지 않는다. 본 프록시 서버가 API 키를 은닉한 상태로 요청을 위임(Delegate)받아 처리한다. (릴리스 빌드에는 클라이언트의 직접 호출 경로 자체가 컴파일되지 않는다.)

## 1. 최우선 규칙: API 스펙(Contract) 변경의 동기화

**프록시 서버는 클라이언트의 요청 본문(Body)을 그대로 전달(Bypass)하지 않으며, 허용된 필드만 추출하여 재조립(Build Up)한다.** (`api/generate.js` 내 `buildUpstreamBody` 참조)

`/generate`에서 허용(Whitelist)되는 페이로드 스펙은 정확히 다음과 같다.

* `kind`: `answer` 또는 `explanation`
* `solveId`: UUID v4
* `text` 파트 1개 (최대 8,000자 제한)
* `inline_data` 파트 1개 (`image/jpeg` 또는 `image/png`, Base64 인코딩 기준 최대 4,000,000자 제한)

`generationConfig`, `systemInstruction`, `safetySettings`, `tools`, 추가 파트(Parts), 다중 텍스트 파트 등은 **구조적으로 전달이 불가능하다.** 클라이언트가 해당 필드를 포함해 요청하더라도 프록시 단에서 무시되거나 HTTP 400 에러를 반환한다.

따라서 `Paxo/AI/GeminiService.swift`의 요청 형태를 변경하려면 반드시 `api/generate.js`의 파싱 로직을 **동일한 PR에서 함께 수정**해야 한다. (예: 스트리밍 응답으로의 전환 시에도 양측 코드의 동시 수정이 필수다.)

## 2. API 요청 및 응답 규격

### 요청 (Request)

```http
POST {proxyURL}/generate
Content-Type: application/json
Authorization: Bearer <15분 세션 토큰>
x-paxo-token:  <공유 시크릿(Shared Secret)>

{
  "kind": "answer | explanation",
  "solveId": "<UUID v4>",
  "contents": [
    {
      "parts": [
        { "text": "..." },
        { "inline_data": { "mime_type": "image/jpeg", "data": "<base64_string>" } }
      ]
    }
  ]
}

```

### 응답 (Response)

* 새 앱은 `x-paxo-response-format: structured-v1` 헤더로 구조화 생성을 요청한다. 헤더가 없는 구버전 요청에는 기존 텍스트 형식을 유지한다.
* 구조화 해설에는 `x-paxo-answer-context` 헤더로 `{ questionType, choices, selectedChoices }` JSON을 전달할 수 있다. 정답 단계의 선택지와 해설의 선택지를 대조하며, 이 헤더는 구조화 해설 요청에서만 허용한다.
* 구조화 정답은 `{ questionType, choices, selectedChoices, answer }`, 해설은 `{ questionType, choices, selectedChoices, coreExplanation, wrongChoiceReasons, recommendedLearning }` JSON을 Gemini 응답의 text에 담는다. 객관식 answer는 빈 문자열이며 앱이 selectedChoices를 번호로 표시한다.
* 서버는 JSON 스키마와 `thinkingLevel: low`, 정답 2,048·해설 4,096토큰 한도를 적용한다. 잘림이나 형식 오류에는 동일 예약 안에서 한 번만 한도를 두 배로 늘려 재생성한다. 전체 업스트림 시간 한도는 45초다.
* `finishReason: STOP`과 비어 있지 않은 최종 텍스트를 확인한 뒤에만 정답 사용량 또는 해설 완료를 확정한다. 구조화 응답은 유형·선택 번호·필수 해설·모든 비정답 선택지의 이유까지 검증한다.
* 재생성 후에도 잘리면 502 `incomplete_response`, 형식 검증이 실패하면 502 `invalid_response`로 반환하고 예약을 해제한다. 정답은 차감하지 않고, 해설 실패에는 추가 차감이 없다.
* 성공 응답은 `x-paxo-tier`, `x-paxo-remaining`, `x-paxo-reset-at` 헤더를 포함한다.
* Gemini 오류는 502, 타임아웃은 504로 정규화하며 원문 오류는 노출하지 않는다.
* Redis나 Apple 상태 확인 실패는 503으로 fail-closed 한다.
* 보안을 위해 업스트림의 상세 에러 본문은 클라이언트에 노출하지 않는다.
* 클라이언트가 단일 파서로 에러를 처리할 수 있도록, 에러 반환 포맷은 Gemini 원본과 동일한 `{ "error": { "code", "message" } }` 구조를 유지한다.

## 3. 인증·사용량 정책

* `/session/challenge`의 일회용 nonce와 Apple identity token·authorization code로 로그인한다.
* Apple 사용자 식별자는 HMAC 처리하고, Apple 갱신 토큰은 AES-256-GCM으로 암호화한다.
* 무료는 하루 3회, Pro는 하루 100회이며 정답 성공 때만 차감한다.
* 같은 `solveId`의 해설은 정답 성공 후 한 번만 허용하며 추가 차감하지 않는다.
* `APP_TOKEN`은 반드시 설정한다. 누락 상태에서 인증을 우회하는 배포는 금지한다.
* Production과 Preview가 Redis를 공유할 때 `REDIS_KEY_PREFIX`를 각각 `paxo:prod`, `paxo:preview`로 강제한다.

`APP_TOKEN_PREV`는 짧은 로테이션 기간에만 사용하고 제거한다.

## 4. 환경 변수 (Environment Variables)

| 변수명 | 필수 여부 | 기본값 | 설명 |
| --- | --- | --- | --- |
| `GEMINI_API_KEY` | **필수** | — | 누락 시 서버 구동 불가 (HTTP 500 에러 발생) |
| `APP_TOKEN` | **필수** | — | 앱 버전 필터용 공유 토큰 |
| `APP_TOKEN_PREV` | 선택 | 없음 | 구버전 하위 호환 및 토큰 로테이션 목적의 예비 슬롯 |
| `MODEL` | **필수** | — | 허용 목록 내 Gemini 모델 |
| `UPSTASH_REDIS_REST_URL`, `UPSTASH_REDIS_REST_TOKEN` | **필수** | — | 영속 사용량·세션 저장소 |
| `REDIS_KEY_PREFIX` | **필수** | — | `paxo:prod`, `paxo:preview`, 로컬은 `paxo:dev` |
| `APP_STORE_PRIVATE_KEY`, `APP_STORE_KEY_ID`, `APP_STORE_ISSUER_ID` | **필수** | — | In-App Purchase 서버 API 키 |
| `APP_APPLE_ID`, `APP_BUNDLE_ID`, `APP_STORE_ENVIRONMENT` | **필수** | — | 앱 및 StoreKit 검증 환경 |
| `APPLE_SIGN_IN_PRIVATE_KEY`, `APPLE_SIGN_IN_KEY_ID`, `APPLE_TEAM_ID`, `APPLE_CLIENT_ID` | **필수** | — | Apple 로그인 서버 키 |
| `IDENTITY_HASH_SECRET` | **필수** | — | Apple 식별자 HMAC 비밀값 |
| `AUTH_TOKEN_ENCRYPTION_KEY` | **필수** | — | 64자리 hex AES-256 키 |

## 5. 코드 스타일 (Code Convention)

* **언어 및 포맷팅**: 순수 JavaScript (ESM 기준). 쌍따옴표(`""`), 2 Space 들여쓰기, 문장 끝 세미콜론(`;`) 사용을 엄수한다.
* **명명 규칙**: 모듈 레벨 상수는 `SCREAMING_SNAKE_CASE` 포맷을 사용한다.
* **함수 선언**: 헬퍼 함수는 호이스팅(Hoisting)이 가능하도록 `function` 키워드로 선언하며, 화살표 함수(`=>`)는 범위가 제한적인 작은 콜백이나 익명 함수에만 제한적으로 사용한다.
* **주석**: 로직의 동작 방식(How)이 아닌 '의도(Why)'를 한국어로 작성한다. (본 프로젝트는 TypeScript가 아니므로 타입 정보보다 의도 전달이 더 중요하다.)

## 6. 로그 금지 데이터

raw Apple JWS, identity token, authorization code, 세션·갱신 토큰, App Transaction ID,
프롬프트, 이미지, Gemini 응답은 로그에 남기지 않는다. 가명 subject 앞 12자, 상태 코드,
지연 시간, 요청 크기만 운영 로그에 허용한다.
