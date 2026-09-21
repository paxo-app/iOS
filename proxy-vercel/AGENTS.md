# proxy-vercel/ — API 프록시 서버 (주요 경로)

> 전역 규칙은 저장소 루트의 `AGENTS.md`를 참조한다.

클라이언트(앱)는 Gemini API를 직접 호출하지 않는다. 본 프록시 서버가 API 키를 은닉한 상태로 요청을 위임(Delegate)받아 처리한다. (릴리스 빌드에는 클라이언트의 직접 호출 경로 자체가 컴파일되지 않는다.)

## 1. 최우선 규칙: API 스펙(Contract) 변경의 동기화

**프록시 서버는 클라이언트의 요청 본문(Body)을 그대로 전달(Bypass)하지 않으며, 허용된 필드만 추출하여 재조립(Build Up)한다.** (`api/generate.js` 내 `buildUpstreamBody` 참조)

현재 허용(Whitelist)되는 페이로드 스펙은 정확히 다음과 같다.

* `text` 파트 1개 (최대 8,000자 제한)
* `inline_data` 파트 1개 (`image/jpeg` 또는 `image/png`, Base64 인코딩 기준 최대 6,000,000자 제한)

`generationConfig`, `systemInstruction`, `safetySettings`, `tools`, 추가 파트(Parts), 다중 텍스트 파트 등은 **구조적으로 전달이 불가능하다.** 클라이언트가 해당 필드를 포함해 요청하더라도 프록시 단에서 무시되거나 HTTP 400 에러를 반환한다.

따라서 `Paxo/AI/GeminiService.swift`의 요청 형태를 변경하려면 반드시 `api/generate.js`의 파싱 로직을 **동일한 PR에서 함께 수정**해야 한다. (예: 스트리밍 응답으로의 전환 시에도 양측 코드의 동시 수정이 필수다.)

## 2. API 요청 및 응답 규격

### 요청 (Request)

```http
POST {proxyURL}/generate
Content-Type: application/json
x-paxo-device: <UUID 포맷, 정규식 검증 수행>
x-paxo-token:  <공유 시크릿(Shared Secret)>

{
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

* HTTP 200(성공)과 429(Rate Limit) 상태 코드만 클라이언트에 그대로 전달한다.
* 그 외 업스트림(Gemini)에서 발생한 모든 에러 상태는 **HTTP 502(Bad Gateway)로 정규화(Normalize)하여 반환**한다.
* 보안을 위해 업스트림의 상세 에러 본문은 클라이언트에 노출하지 않는다.
* 클라이언트가 단일 파서로 에러를 처리할 수 있도록, 에러 반환 포맷은 Gemini 원본과 동일한 `{ "error": { "code", "message" } }` 구조를 유지한다.

## 3. APP_TOKEN 무중단 배포 순서

아래 배포 순서 미준수 시 기존 프로덕션 버전 앱에서 401(Unauthorized) 에러가 대량 발생한다.

1. **프록시 1차 배포**: `APP_TOKEN` 환경 변수 없이 배포한다. (토큰 검증 로직이 우회되어 기존 앱의 무중단 서비스 가능)
2. **클라이언트 배포**: 신규 토큰 값이 하드코딩된 앱 빌드를 릴리스한다.
3. **프록시 환경 변수 주입**: Vercel 콘솔 또는 CLI를 통해 토큰을 등록한다 (`vercel env add APP_TOKEN production`).
4. **프록시 2차 배포(적용)**: `npx vercel --prod` 명령어로 재배포한다. **이 시점부터 토큰이 없거나 불일치하는 클라이언트 요청은 401 에러로 차단된다.**

*토큰 로테이션(Rotation)*: 신규 토큰은 `APP_TOKEN`에, 기존 토큰은 `APP_TOKEN_PREV`에 할당하면 구버전 앱의 하위 호환성을 일정 기간 유지할 수 있다. 이 값은 클라이언트의 `Paxo/Secrets.swift` 내 `appToken` 속성과 정확히 일치해야 한다.

## 4. 환경 변수 (Environment Variables)

| 변수명 | 필수 여부 | 기본값 | 설명 |
| --- | --- | --- | --- |
| `GEMINI_API_KEY` | **필수** | — | 누락 시 서버 구동 불가 (HTTP 500 에러 발생) |
| `APP_TOKEN` | 선택 | 없음 | 설정된 경우에만 클라이언트 토큰 검증 로직이 활성화됨 |
| `APP_TOKEN_PREV` | 선택 | 없음 | 구버전 하위 호환 및 토큰 로테이션 목적의 예비 슬롯 |
| `MODEL` | 선택 | `gemini-3.6-flash` | 호출할 업스트림 LLM 모델 지정 |

## 5. 코드 스타일 (Code Convention)

* **언어 및 포맷팅**: 순수 JavaScript (ESM 기준). 쌍따옴표(`""`), 2 Space 들여쓰기, 문장 끝 세미콜론(`;`) 사용을 엄수한다.
* **명명 규칙**: 모듈 레벨 상수는 `SCREAMING_SNAKE_CASE` 포맷을 사용한다.
* **함수 선언**: 헬퍼 함수는 호이스팅(Hoisting)이 가능하도록 `function` 키워드로 선언하며, 화살표 함수(`=>`)는 범위가 제한적인 작은 콜백이나 익명 함수에만 제한적으로 사용한다.
* **주석**: 로직의 동작 방식(How)이 아닌 '의도(Why)'를 한국어로 작성한다. (본 프로젝트는 TypeScript가 아니므로 타입 정보보다 의도 전달이 더 중요하다.)

## 6. [레거시] proxy/ (Cloudflare Worker) 디렉터리 정책

`proxy/` 디렉터리는 과거 Cloudflare Worker 기반의 백업용 프록시 코드를 담고 있으나, **현재는 폐기(Deprecated)되었다.**

* **폐기 사유**: Gemini API가 Cloudflare Worker 대역의 요청을 지역(Region) 기반으로 차단하는 이슈가 발생하여 운영 환경에서 배제되었다. 현재의 `proxy-vercel/`은 Vercel `iad1` 리전으로 요청을 고정하여 이 문제를 우회한다.
* **유지 보수 금지**: `proxy/` 디렉터리는 본문 재조립 검증 로직이 누락되어 있으며 에러 정규화 포맷도 다르다. **향후 모든 프록시 관련 신규 개발 및 수정은 반드시 본 `proxy-vercel/` 디렉터리에서만 진행한다.**
