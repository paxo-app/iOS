# Paxo 프록시 — Vercel 버전

Cloudflare Workers 버전(`proxy/`)은 아웃바운드 IP가 간헐적으로 Gemini 미지원 지역을 경유해
**"User location is not supported" 오류가 랜덤하게 발생**하는 문제가 있다 (실측 4~8/8 실패).
이 버전은 **미국 리전(iad1) 고정 실행**이라 해당 문제가 구조적으로 발생하지 않는다.

앱 수정은 불필요 — 요청/응답 형식과 경로(`/generate`, `/privacy`)가 워커 버전과 동일하다.

## 배포 (약 5분)

```bash
cd proxy-vercel

# 1. Vercel 로그인 (계정 없으면 무료 가입, 브라우저 인증)
npx vercel login

# 2. 프로젝트 배포 (질문에는 기본값으로 Enter, 프로젝트명: paxo-proxy)
npx vercel --prod

# 3. Gemini API 키 환경변수 등록
npx vercel env add GEMINI_API_KEY production
# → 키 입력 후, 반영을 위해 한 번 더 배포
npx vercel --prod
```

배포 완료 시 출력되는 URL(예: `https://paxo-proxy-xxxx.vercel.app`)을
`Paxo/DefaultConfig.swift`의 `proxyURL`에 넣으면 끝.

## 보안 (APP_TOKEN) — 제출 전 강제화

`api/generate.js`는 다음을 검증한다:
- `x-paxo-token` — `APP_TOKEN`(+로테이션용 `APP_TOKEN_PREV`) 환경변수가 설정돼 있으면 강제. **미설정이면 통과**(무중단 배포용)
- `x-paxo-device` — UUID 형식 필수 + 베스트에포트 인메모리 일일 제한
- 본문 재구성 검증 — text 1개 + inline_data(jpeg/png) 1개만 화이트리스트로 조립. generationConfig·safetySettings 등 주입 차단

```bash
# 앱(DefaultConfig.appToken)과 동일한 토큰을 환경변수로 등록 후 강제화
npx vercel env add APP_TOKEN production
npx vercel --prod
```

배포 순서는 반드시: **프록시 배포(토큰 미설정) → 앱 배포(토큰 전송) → APP_TOKEN 등록·재배포**.
순서를 어기면 토큰을 안 보내는 앱이 401을 받는다.

## 확인

```bash
curl -s https://<배포주소>/privacy | head -5                       # 200 HTML
curl -s -X POST https://<배포주소>/generate -d '{}'               # (강제화 후) 401 또는 400
```

## 참고

- 요청 본문 한도 4.5MB — 앱이 캡처를 최대 2000px JPEG로 압축해 전송하므로 여유 충분
- 인메모리 제한은 warm instance 한정. 정식 기기별 내구성 한도는 `checkDurableLimit()` 자리에 Upstash Redis 연동 예정 (v2)
- 모델 변경: Vercel 대시보드 → 환경변수 `MODEL` 설정 후 재배포
