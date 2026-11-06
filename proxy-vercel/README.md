# proxy-vercel — Paxo API 서버

Vercel `iad1` 리전에서 Apple 로그인, App Store 구매 검증, 영속 사용량 제한과 Gemini 호출을
처리한다. Release 앱은 `https://api.paxo.co.kr`만 사용한다.

## 요청 흐름

1. 앱이 `/session/challenge`에서 일회용 nonce를 받는다.
2. Apple 로그인 결과를 `/session`으로 보내 15분 세션과 30일 갱신 토큰을 받는다.
3. 앱이 Bearer 세션으로 `/generate`를 호출한다.
4. 서버가 Redis에서 무료 2회를 먼저 예약하고 소진 후 충전분을 예약한 뒤 Gemini를 호출한다. 무료분은 매일 오전 6시(Asia/Seoul)에 초기화하며 충전분은 만료되지 않는다. 기존 유효 구독에는 기존 하루 100회를 유지한다.
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
지갑·충전 예약·잔액 버전도 환경별로 분리한다. 등록된 번들 ID와 상품 ID가 일치하지 않으면 모두 거절한다.

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


## 충전 상품 배포 준비

- App Store Connect에 소모성 상품 `com.hyeseong.Paxo.credits.30`, `.100`, `.500`, `.1000`을 등록한다. 한국 가격은 각각 990원, 2,900원, 13,900원, 26,900원이며 최종 결제 가격은 StoreKit 조회값을 사용한다.
- App Store Server Notifications V2의 Production·Sandbox URL을 해당 프록시의 `/store/notifications`로 등록한다. 서명 검증이 인증 수단이므로 Apple 알림에는 앱 토큰을 요구하지 않는다. 지연 알림도 최신 거래 API를 확인한다.
- 기존 구독의 신규 판매를 중단하는 App Store Connect 작업과 이미 결제한 기간의 처리 정책을 확인한다. 코드에서 신규 구독을 판매하지 않아도 Apple의 자동 갱신이 자동으로 중단되지는 않는다.
- 서버를 먼저 배포한 뒤 Sandbox에서 충전·재전달·환불·환불 취소·로그아웃/재로그인·재설치를 확인하고 앱을 배포한다. 소모성 거래는 서버 적립 성공 뒤에만 `finish`한다.
- 지갑·거래 원장은 TTL 없이 보관한다. Redis의 용량과 백업 정책을 운영 저장소에 맞게 설정한다. 계정 삭제는 잔액을 삭제하지만 최소 거래 원장은 보존한다.
- 48시간이 지난 풀이에는 새 해설 생성 권한이 만료될 수 있다. 이미 로컬에 저장된 정답·해설은 추가 과금 없이 열람한다.

## 실제 Redis 원자성 검증

`npm test`는 `redis-server`와 `redis-cli`가 있으면 임시 Unix 소켓 Redis를 띄워 실제 Lua를 검증한다. 없으면 해당 통합 테스트를 명시적으로 건너뛴다. CI에는 두 실행 파일을 설치한다. 별도 경로는 다음처럼 지정할 수 있다.

```bash
PAXO_REDIS_SERVER=/path/to/redis-server PAXO_REDIS_CLI=/path/to/redis-cli npm test
```

중복 충전, 마지막 잔액 동시 예약, 오전 6시 경계, 만료 예약의 늦은 응답, 환불·취소·역순 알림, 환경 분리, 계정 삭제 뒤 거래 재전달을 검증한다.
