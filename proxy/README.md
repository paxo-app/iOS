# Paxo 프록시 (Cloudflare Worker) — 백업

> 현재 기본 프록시는 Vercel(`proxy-vercel/`)이다. Cloudflare Workers는 아웃바운드 IP가
> 간헐적으로 Gemini 미지원 지역을 경유해 "User location is not supported" 오류가 랜덤 발생하는
> 문제가 있어(실측 ~50% 실패) 백업으로 강등됐다. 앱의 기본 URL은 `paxo-proxy.vercel.app`이다.

앱 배포본에 Gemini API 키를 넣지 않기 위한 최소 프록시. 무료 플랜(일 10만 요청)으로 충분하다.

## 배포 (최초 1회, 약 5분)

```bash
cd proxy

# 1. Cloudflare 계정 인증 (브라우저 열림, 계정 없으면 무료 가입)
npx wrangler login

# 2. Gemini API 키를 서버 시크릿으로 등록 (새로 발급한 키 사용!)
npx wrangler secret put GEMINI_API_KEY

# 3. 배포
npx wrangler deploy
```

배포가 끝나면 `https://paxo-proxy.<계정명>.workers.dev` 주소가 출력된다.
→ **Paxo 설정 → AI 연결 → 프록시 URL**에 붙여넣으면 끝. (API 키 필드는 비워도 됨)

이후 코드 수정 시엔 `npx wrangler deploy`만 다시 실행.

## 선택 옵션

**기기별 일일 사용량 제한** (무료 티어/어뷰징 대비):

```bash
npx wrangler kv namespace create USAGE
```

출력된 `id`를 `wrangler.toml`의 `[[kv_namespaces]]` 주석을 해제하고 붙여넣은 뒤 재배포.
한도는 `DAILY_LIMIT`(기본 200회/일)로 조정. 초과 시 앱에 "요청 한도 초과" 메시지가 뜬다.

**앱 토큰** (간단한 접근 제한):

```bash
npx wrangler secret put APP_TOKEN
```

설정하면 워커가 `x-paxo-token` 헤더를 요구한다. 앱에 같은 값을 보내는 코드를 추가해야 하므로,
StoreKit 구독을 붙일 때 영수증 검증으로 함께 처리하는 것을 권장.

**모델 교체**: `wrangler.toml`의 `[vars] MODEL` 수정 후 재배포. 앱 수정 불필요.

## 동작 방식

```
Paxo 앱 ──POST /generate (Gemini 형식 그대로)──▶ Worker ──키 첨부──▶ Gemini API
                                                  │
                                                  ├─ (선택) 기기별 일일 한도 (KV)
                                                  └─ (선택) 앱 토큰 검사
```

응답도 Gemini 형식 그대로 반환하므로 앱의 파싱 코드는 직접 호출과 동일하다.
