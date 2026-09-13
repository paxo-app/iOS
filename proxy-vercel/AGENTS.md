# proxy-vercel/ — API 프록시 (기본 경로)

전역 규칙은 저장소 루트의 `AGENTS.md`를 따른다.

앱은 Gemini를 직접 호출하지 않는다. 이 프록시가 API 키를 쥐고 대신 호출한다.
릴리스 빌드에는 직접 호출 경로가 아예 컴파일되지 않는다.

## 가장 중요한 규칙 — 계약은 양쪽을 동시에 고친다

**프록시는 요청 본문을 통과시키지 않고 화이트리스트로 재조립한다** (`api/generate.js`의 `buildUpstreamBody`).

허용되는 것은 정확히 이것뿐이다.

- `text` 파트 1개 (8000자 이하)
- `inline_data` 파트 1개 (`image/jpeg` 또는 `image/png`, base64 6,000,000자 이하)

`generationConfig`, `systemInstruction`, `safetySettings`, `tools`, 추가 파트, 두 번째 텍스트 파트는
**구조적으로 전달이 불가능하다.** 클라이언트에서 넣으면 400이 돌아온다.

따라서 `Paxo/AI/GeminiService.swift`의 요청 형태를 바꾸려면 `api/generate.js`를 **같은 PR에서 함께** 고쳐야 한다.
스트리밍 전환도 마찬가지로 양쪽 변경이 필요하다.

## 요청·응답 계약

```
POST {proxyURL}/generate
  content-type: application/json
  x-paxo-device: <UUID 형식, 정규식 검증됨>
  x-paxo-token:  <공유 시크릿>

{"contents":[{"parts":[{"text":"..."},
                       {"inline_data":{"mime_type":"image/jpeg","data":"<base64>"}}]}]}
```

응답: 200과 429만 그대로 전달하고, 나머지 상태는 전부 502로 정규화한다.
업스트림 에러 본문은 클라이언트에 노출하지 않는다.
에러 형태는 Gemini와 동일한 `{error:{code,message}}` — 클라이언트가 파서 하나로 처리하기 위해서다.

## APP_TOKEN 배포 순서

순서를 어기면 기존 사용자 앱이 401을 맞는다.

1. `APP_TOKEN` 없이 프록시 배포 (검증 생략 = 무중단)
2. 토큰이 들어간 앱 빌드 배포
3. `vercel env add APP_TOKEN production`
4. `npx vercel --prod` 재배포 — 이때부터 토큰 없는 요청이 401

로테이션은 새 토큰을 `APP_TOKEN`, 기존 것을 `APP_TOKEN_PREV`에 두면 구버전 앱도 한동안 동작한다.
값은 `Paxo/Secrets.swift`의 `appToken`과 정확히 일치해야 한다.

## 환경변수

| 이름 | 필수 | 기본값 |
|---|---|---|
| `GEMINI_API_KEY` | **필수** — 없으면 500 | — |
| `APP_TOKEN` | 선택 — 설정 시에만 검증 | 없음 |
| `APP_TOKEN_PREV` | 선택 — 로테이션용 | 없음 |
| `MODEL` | 선택 | `gemini-2.5-flash` |

## 코드 스타일

ESM, 큰따옴표, 2칸 들여쓰기, 세미콜론 항상. 모듈 상수는 SCREAMING_SNAKE.
헬퍼는 호이스팅되는 `function` 선언으로, 작은 지역 함수만 화살표 함수로.
주석은 한국어로 *왜*를 적는다. TypeScript가 아니다.

## proxy/ (Cloudflare Worker)는 폐기된 백업이다

Gemini가 Workers 요청을 지역 차단하는 문제로 강등됐다. Vercel은 `iad1` 리전에 고정해 이를 피한다.
신규 작업은 이 디렉토리에만 한다. `proxy/`는 본문 검증이 없고 에러 형태도 다르다.
