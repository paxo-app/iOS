# proxy-vercel — Paxo API 서버

Vercel `iad1` 리전에서 Apple 로그인, App Store 구독 검증, 영속 사용량 제한과 Gemini 호출을
처리한다. Release 앱은 `https://api.paxo.co.kr`만 사용한다.

## 요청 흐름

1. 앱이 `/session/challenge`에서 일회용 nonce를 받는다.
2. Apple 로그인 결과를 `/session`으로 보내 15분 세션과 30일 갱신 토큰을 받는다.
3. 앱이 Bearer 세션으로 `/generate`를 호출한다.
4. 서버가 Redis에서 무료 2회 또는 Pro 100회 한도를 예약한 뒤 Gemini를 호출한다. 일일 한도는 매일 오전 6시(Asia/Seoul)에 초기화한다.
5. 정답 성공 시에만 사용량을 확정하며 같은 `solveId`의 해설 1회는 추가 차감하지 않는다.

Apple 사용자 식별자는 HMAC 처리하며 Apple 갱신 토큰은 AES-256-GCM으로 암호화한다. 프롬프트,
이미지, AI 응답과 원본 Apple 식별자는 로그나 Redis에 저장하지 않는다.

## 환경 변수

실제 값은 모두 Vercel Sensitive 변수로 등록한다. 전체 목록은 `.env.example`을 기준으로 한다.

- Production: `APP_STORE_ENVIRONMENT=PRODUCTION`, `REDIS_KEY_PREFIX=paxo:prod`
- Preview: `APP_STORE_ENVIRONMENT=SANDBOX`, `REDIS_KEY_PREFIX=paxo:preview`
- 로컬: `APP_STORE_ENVIRONMENT=SANDBOX`, `REDIS_KEY_PREFIX=paxo:dev`

Preview는 Apple 서명이 검증된 Sandbox 거래만 허용한다. Production은 실제 판매 거래를 우선
Production에서 검증하고, TestFlight와 App Review가 사용하는 Apple 서명 Sandbox 거래만 별도
Sandbox 검증기로 허용한다. 두 환경은 App Store Server API 클라이언트와 거래 바인딩 키를 분리하며,
등록된 번들 ID와 월간·연간 상품 ID가 일치하지 않으면 모두 거절한다.

`APP_STORE_*`는 App Store Connect In-App Purchase API 키이고, `APPLE_SIGN_IN_*`는 Apple
Developer에서 만든 Sign in with Apple 키다. 두 개인 키는 서로 바꿔 쓰지 않는다.

무작위 비밀값은 다음처럼 생성할 수 있다.

```bash
openssl rand -hex 32 | npx vercel env add IDENTITY_HASH_SECRET production --sensitive
openssl rand -hex 32 | npx vercel env add AUTH_TOKEN_ENCRYPTION_KEY production --sensitive
```

Preview에는 위 명령의 환경 이름만 `preview`로 바꾸고 반드시 새 값을 생성한다. `APP_TOKEN`은
앱의 `Secrets.appToken`과 같아야 하지만 인증 수단이 아니라 버전 필터일 뿐이다.

## 검증과 배포

```bash
npm ci
npm run check
npm test
npx vercel
npx vercel --prod
```

배포 후 `/privacy`는 200, 인증 없는 `/generate`는 401이어야 한다. Preview에서 Sandbox Apple
로그인과 구매·복원을 먼저 확인한 뒤 Production을 배포한다. Vercel Firewall은 처음에 로그 모드로
`/session` 10회/분/IP, `/generate` 60회/분/IP를 관찰하고 정상 요청을 확인한 뒤 Enforce로 바꾼다.

자정 초기화에서 오전 6시 초기화로 전환하는 첫 배포는 한국 시간 오전 6시 이후에 진행한다.
기존 날짜별 Redis 키를 유지하므로 그날 누적 사용량을 이어 쓰고 다음 날 오전 6시부터 초기화한다.
오전 0시부터 6시 전에는 두 정책이 서로 다른 날짜 키를 사용하므로 첫 전환 배포를 피한다.
정책 변경은 프록시를 먼저 배포한 뒤 앱을 배포한다.
