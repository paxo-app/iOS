# proxy-vercel/ — Vercel 기반 API 프록시 서버

기존 Cloudflare Workers 버전(`proxy/`)의 아웃바운드 IP가 간헐적으로 Gemini 미지원 지역을 경유하여 "User location is not supported" 에러가 발생하는 치명적 결함을 해결하기 위해 도입된 아키텍처다.
본 Vercel 버전은 **실행 리전을 미국(`iad1`)으로 강제 고정**하여 해당 문제를 구조적으로 원천 차단한다.

> **클라이언트 하위 호환성**: 라우팅 경로(`/generate`, `/privacy`) 및 요청/응답 스펙이 기존 Worker 버전과 100% 동일하므로, 프록시 전환에 따른 앱(클라이언트) 코드 수정은 불필요하다.

## 1. 배포 파이프라인 (Deployment)

소요 시간은 약 5분 내외이며, Vercel CLI를 통해 진행한다.

```bash
# 1. Vercel CLI 로그인 (계정이 없을 경우 브라우저 창에서 무료 가입/인증 진행)
npx vercel login

# 2. 프로젝트 최초 배포 (프롬프트 질의 시 모두 기본값(Enter) 사용, 프로젝트명: paxo-proxy)
npx vercel --prod

# 3. Gemini API 키 환경 변수 주입
npx vercel env add GEMINI_API_KEY production

# 4. 환경 변수 적용을 위한 운영(Production) 환경 재배포
npx vercel --prod

```

배포 완료 후 콘솔에 출력되는 운영 URL(예: `[https://paxo-proxy-xxxx.vercel.app](https://paxo-proxy-xxxx.vercel.app)`)을 클라이언트 프로젝트의 `Paxo/DefaultConfig.swift` 내 `proxyURL` 값으로 설정한다.

## 2. 보안 정책 및 APP_TOKEN 강제화

App Store 심사 제출 전, API 어뷰징을 방지하기 위해 클라이언트 검증 로직을 반드시 강제화(Enforce)해야 한다. `api/generate.js`는 다음 3가지 보안 검증을 수행한다.

1. **토큰 검증 (`x-paxo-token`)**: 서버 측 `APP_TOKEN` (및 로테이션용 `APP_TOKEN_PREV`) 환경 변수가 설정된 경우에만 일치 여부를 검사한다. **미설정 상태에서는 무조건 통과(Bypass)** 시키므로 무중단 배포에 활용된다.
2. **디바이스 검증 (`x-paxo-device`)**: UUID 포맷 준수 여부를 검사하며, 메모리 기반의 일일 베스트 에포트(Best-effort) 사용량 제한을 적용한다.
3. **페이로드 화이트리스트**: 요청 본문을 분해 후 조립하여 `text` 파트 1개, `inline_data` (jpeg/png) 파트 1개만 허용한다. 클라이언트가 변조한 `generationConfig`나 `safetySettings` 등은 원천 차단된다.

### ⚠️ 무중단 보안 적용 순서 (Critical)

**순서를 위반할 경우 구버전 앱에서 401(Unauthorized) 에러가 대량 발생하므로 절대 엄수한다.**

1. 프록시 최초 배포 (토큰 환경 변수 **미설정** 상태)
2. 클라이언트(앱) 코드에 토큰 값을 주입하여 앱 배포 (`DefaultConfig.appToken`)
3. 프록시 서버에 토큰 환경 변수 등록 및 재배포 수행

```bash
# 앱에 내장된 토큰과 동일한 값을 프록시에 등록 후 검증 로직 활성화
npx vercel env add APP_TOKEN production
npx vercel --prod

```

## 3. 헬스 체크 (Health Check)

프록시 서버 정상 구동 여부 및 권한 제어 로직을 아래 명령어로 검증한다.

```bash
# 1. 서버 구동 및 정상 라우팅 확인 (200 OK, HTML 반환)
curl -s https://<배포주소>/privacy | head -5

# 2. 보안 토큰 검증 로직 작동 확인 (APP_TOKEN 강제화 이후 401 또는 400 반환)
curl -s -X POST https://<배포주소>/generate -d '{}'

```

## 4. 기술 스펙 및 v2 로드맵

* **페이로드 한도**: Vercel의 요청 본문 한도는 4.5MB다. 앱에서 캡처 이미지를 최대 2000px의 JPEG 포맷으로 압축(0.82)하여 전송하므로 해당 제한 내에서 안정적으로 동작한다.
* **Rate Limit 한계점**: 현재 구현된 인메모리(In-memory) 사용량 제한은 컨테이너가 웜(Warm) 상태일 때만 유지되는 임시 조치다. 향후 v2에서는 `checkDurableLimit()` 위치에 Upstash Redis를 연동하여 영속적인 기기별 Rate Limit을 구축할 예정이다.
* **LLM 모델 교체**: 호출 대상 모델을 변경하려면 Vercel 대시보드 또는 CLI를 통해 `MODEL` 환경 변수(예: `gemini-2.5-pro`)를 수정하고 재배포한다.
