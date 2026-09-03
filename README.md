# Paxo

화면 속 문제를 단축키 한 번으로 캡처하면 AI가 정답과 해설을 알려주는 macOS 메뉴바 학습 도우미.

## 사용법

1. 메뉴바의 Paxo 아이콘 클릭 또는 전역 단축키 **⌥⌘S** (설정에서 변경 가능)
2. 풀이할 문제 영역을 드래그로 선택 (Esc 취소) — 설정에서 **전체 화면** 모드로 바꾸면 드래그 없이 즉시 캡처
3. 정답이 먼저 뜨고, 해설이 이어서 표시됨
4. **빠른 채점 모드** (설정): 정답만 먼저 크게 표시, 해설은 "해설 보기" 클릭 시 생성 — 문제집 셀프 채점용
5. **결과 표시** (설정): 창 위치 7곳 중 선택, 또는 **토스트 모드**(정답만 2~10초 떴다 사라짐, 해설 생성 안 함)

## 개발 셋업

- 요구사항: macOS 14+, Xcode 16+
- **시크릿 파일 생성 (클론 직후 1회 필수)** — `Paxo/Secrets.swift`는 Git에 올라가지 않으므로 직접 만들어야 한다:

  ```sh
  cp Config/Secrets.example.swift Paxo/Secrets.swift
  ```

  이 파일이 없으면 `Secrets` 심볼을 못 찾아 빌드가 실패한다.
  배포된 프록시에는 이미 `APP_TOKEN`이 설정돼 있다. 토큰을 빈 값으로 두면 빌드·실행은 되지만
  AI 호출이 전부 401로 실패한다. 값은 팀에서 받는다 (아래 '프록시 보안' 참고).
  템플릿을 `Paxo/` 안에 복사본으로 남겨두지 말 것 — 이 디렉토리는 파일시스템 동기화로
  자동 컴파일되므로 `Secrets`가 중복 선언되어 빌드가 깨진다.
- `Paxo.xcodeproj` 열기 → Signing & Capabilities에서 Team 선택 → Run
- 첫 캡처 시 **화면 기록 권한** 허용 필요 (시스템 설정 → 개인정보 보호 및 보안 → 화면 및 시스템 오디오 녹음). 권한 허용 후 앱 재실행 필요할 수 있음
- AI 연결:
  - **프록시 (기본)**: 앱에 내장된 Vercel 프록시(`https://paxo-proxy.vercel.app`)를 통해 호출한다. 앱에 Gemini 키가 없다. 배포 방법은 [proxy-vercel/README.md](proxy-vercel/README.md) 참고
  - **직접 호출 (개발 빌드 전용)**: DEBUG 빌드에서만, 설정에서 프록시 URL을 비우고 Gemini API 키를 넣으면 직접 호출. 릴리즈 빌드에는 이 경로가 컴파일되지 않음

## 구독 테스트 (로컬, App Store Connect 불필요)

1. Xcode에서 Product → Scheme → Edit Scheme… → Run → Options
2. **StoreKit Configuration**에서 `Config/Paxo.storekit` 선택
3. 실행하면 무료 하루 3회 소진 시 페이월이 뜨고, 테스트 결제(실제 과금 없음)로 Pro 흐름 확인 가능
4. 테스트 거래 초기화: Xcode → Debug → StoreKit → Manage Transactions

실제 출시 시에는 App Store Connect에 동일한 product ID(`com.hyeseong.Paxo.pro.monthly` / `.yearly`)로
구독 상품을 만들고, 스킴의 StoreKit Configuration을 None으로 되돌리면 된다.

## 구조

```
Paxo/
  PaxoApp.swift            앱 진입점 (MenuBarExtra + Settings)
  AppState.swift           상태 머신: 캡처 → 정답 → 해설, 히스토리
  HotkeyManager.swift      전역 단축키 ⌥⌘S (Carbon, MAS 허용 API)
  DefaultConfig.swift      프록시 URL 등 내장 기본 설정
  Secrets.swift            로컬 시크릿 (Git 제외 — Config/Secrets.example.swift 복사해서 생성)
  Capture/
    SelectionOverlay.swift 드래그 영역 선택 오버레이
    ScreenCapturer.swift   ScreenCaptureKit 캡처 (샌드박스 OK)
  AI/
    GeminiService.swift    2단계 호출: 정답(빠름) → 해설(필요 시)
    Prompts.swift
  UI/                      메뉴바 팝업 / 결과 패널 / 토스트 / 설정 / 페이월 / 마크다운 렌더러
  Store/                   StoreKit 2 구독 + 무료 사용량 추적
  Storage/                 히스토리 JSON, 키체인
Config/                    Info.plist, entitlements (샌드박스), StoreKit 테스트 설정, 시크릿 템플릿
proxy-vercel/              Vercel API 프록시 (기본 — 키 보호 + 토큰·본문 검증 + 사용량 제한)
proxy/                     Cloudflare Worker 프록시 (백업 — Gemini 지역 차단 이슈로 강등)
```

## 로드맵

- [x] v0.1 — 캡처(영역/전체 화면) → 정답+해설, 빠른 채점 모드, 토스트 모드, 결과 위치 선택, 히스토리
- [x] API 프록시 서버 (proxy-vercel/, 배포 완료 — 토큰·본문 검증 포함)
- [x] StoreKit 2 구독 — 무료 하루 3회 → Pro(월간/연간, 7일 무료 체험) 무제한
- [x] 단축키 변경, 복사 버튼, 로그인 시 자동 실행, 다중 모니터 대응
- [ ] App Store Connect에 구독 상품 생성 (product ID 동일하게)
- [ ] 서버 측 구독 검증 — StoreKit 영수증(JWS)을 프록시에서 확인, 클라이언트 카운트 대체
- [x] 앱 아이콘 (Assets.xcassets — 원본 스크립트로 재생성 가능) + 온보딩(환영·권한·시작 3단계)
- [ ] App Store 제출 (제출 전 `vercel env add APP_TOKEN production` 강제화 — 아래 '프록시 보안' 참고)
- [ ] v2 — 오답노트 자동 축적, 복습 알림(SRS)

## 프록시 보안 (APP_TOKEN)

앱은 프록시에 `x-paxo-token` 헤더로 공유 토큰을 보내고, 프록시는 `APP_TOKEN` 환경변수가 설정돼 있으면 이를 검증한다.

- 토큰 값은 `Paxo/Secrets.swift`의 `appToken`과 Vercel `APP_TOKEN` 환경변수가 **일치**해야 한다.
  이 저장소는 공개되어 있으므로 `Paxo/Secrets.swift`는 `.gitignore` 대상이며, 커밋되는 것은
  값이 빈 템플릿(`Config/Secrets.example.swift`)뿐이다.
- **배포 순서 (401 사고 방지)**: 프록시 배포(토큰 미설정 → 무중단) → 앱 빌드 배포 → `vercel env add APP_TOKEN production` 입력 → `npx vercel --prod` 재배포 → 이때부터 토큰 없는 요청 401.
- 로테이션: 새 토큰을 `APP_TOKEN`, 기존을 `APP_TOKEN_PREV`로 두면 구버전 앱도 한동안 동작.
- 팀 테스트용 토큰은 `APP_TOKEN_PREV` 슬롯에 둔다. 프로덕션 토큰과 분리돼 있어, 유출되거나
  테스트가 끝나면 `APP_TOKEN_PREV`만 지우고 재배포해 출시 앱에 영향 없이 회수할 수 있다.
- 배포 직후 검증은 몇 초 기다린다. `vercel --prod` 반환 시점과 별칭이 새 배포로
  전환되는 시점 사이에 짧은 지연이 있어, 바로 확인하면 아직 옛 배포가 응답해 401이 난다.
  값이 틀린 걸로 오해하기 쉬우니 `sleep 10` 후 재확인한다.
- 검증 curl은 `x-paxo-device`를 일부러 UUID가 아닌 값으로 보낸다. `400 bad device id`가 뜨면 성공
  (토큰 검사를 통과하고 다음 단계에서 걸린 것). Gemini를 호출하지 않아 비용도 들지 않는다.
  배포 직통 URL(`paxo-proxy-xxxx.vercel.app`)은 Deployment Protection 때문에 별도로 401이 나므로
  반드시 별칭(`paxo-proxy.vercel.app`)으로 확인한다.
- 바이너리에서 추출 가능한 공유 시크릿이므로 완전한 방어는 아니다. 드라이브바이 어뷰징 차단용이며, 정식 방어(기기별 내구성 한도·영수증 검증)는 v2 과제.

## App Store 메모

- 샌드박스 필수 — 현재 entitlements 구성 완료 (`app-sandbox` + `network.client`)
- 화면 캡처(ScreenCaptureKit + TCC)와 전역 단축키(RegisterEventHotKey)는 MAS 심사 허용 범위
- 구독은 Apple IAP 의무 (Small Business Program 수수료 15%)
- 포지셔닝: "풀이·해설 학습 도우미" — 해설은 항상 접근 가능해야 함 (빠른 채점 모드도 해설을 숨기지 않고 접어둘 뿐)
