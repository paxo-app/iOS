# Paxo App Store 제출 플레이북 (macOS)

클릭 단위 실전 절차. 위에서 아래로 순서대로. ⏱ = 대기 시간이 있어 먼저 걸어둘 것.

---

## ⚠️ 시작 전 반드시 해결할 2가지

### A. 버전 번호 (현재 0.1.0 → 1.0.0 권장)
`Paxo.xcodeproj`의 `MARKETING_VERSION`이 **0.1.0**이다. App Store 첫 출시는 관례상 **1.0.0**으로 올린다.
- Xcode → 프로젝트 Paxo 선택 → TARGETS Paxo → General → **Version = 1.0.0**, **Build = 1**
- (또는 Identity 탭에서 동일)

### B. 서명 팀 확인 (제출 최대 함정)
프로젝트 `DEVELOPMENT_TEAM = L3JLLU88WG`인데, 이 맥의 로컬 인증서는 `tell280@naver.com (Y3XK4D7J7S)` **개발용 하나뿐**이고 배포용(Apple Distribution) 인증서가 없다. 즉 **두 팀이 섞여 있고 배포 서명이 준비 안 됨.**
- **먼저 정할 것**: 유료 Apple Developer Program($99/년)에 가입된 Apple ID가 무엇인가?
  - Cardly를 이미 냈다면 그 팀이 유료 팀 → Paxo도 **같은 팀**으로 맞춘다.
  - 아직 유료 미가입이면 → developer.apple.com에서 가입(⏱ 승인에 몇 시간~하루).
- **Xcode 설정**: Xcode → Settings → Accounts에 그 Apple ID 로그인 → 프로젝트 → Signing & Capabilities → **Team = 유료 팀** 선택, "Automatically manage signing" 켜기.
  - Automatic signing이면 Archive 시 Xcode가 **Apple Distribution 인증서 + App Store 프로비저닝**을 자동 생성한다. 수동으로 인증서 만들 필요 없음.
- 번들 ID `com.hyeseong.Paxo`가 그 팀의 Identifiers에 등록돼 있어야 함(Automatic signing이 알아서 등록하기도 함).

> 이 둘을 안 맞추면 Archive는 되지만 "No account / No profile" 또는 업로드 거부가 난다.

### C. 클린 동작 점검 (제출 빌드로 1회)
```bash
defaults delete com.hyeseong.Paxo   # 온보딩부터 새로 보기
```
Xcode에서 Run → 온보딩 → 화면 기록 권한 → ⌥⌘S 캡처 → 정답+해설 확인. **APP_TOKEN 강제화가 켜져 있으므로 프록시 200 확인이 곧 토큰 정상 동작 확인.**

---

## 1. ⏱ 유료 앱 계약 + 세금·금융 (제일 먼저 — 승인 지연)

App Store Connect(appstoreconnect.apple.com) → **비즈니스(Business)** 또는 계약·세금·금융(Agreements, Tax, and Banking):
1. **유료 앱(Paid Applications) 계약** 동의 — 구독 판매 필수.
2. **은행 계좌** 정보 입력 (정산 받을 계좌).
3. **세금 양식** 작성 (한국 거주자: W-8BEN 등 미국 세금 원천징수 서식).
- 이게 "활성(Active)"이 되기 전엔 유료/구독 상품을 제출해도 판매가 안 걸린다. 며칠 걸릴 수 있으니 **지금 바로** 시작.

---

## 2. 앱 등록 (ASC → 앱 → ➕ 신규 앱)

- 플랫폼: **macOS**
- 이름: **Paxo** (선점 시 `docs/app-store-copy.md`의 대체안, 예 "Paxo: 화면 문제 AI 풀이")
- 기본 언어: **한국어**
- 번들 ID: **com.hyeseong.Paxo** (드롭다운에 없으면 developer.apple.com → Identifiers에서 먼저 등록)
- SKU: `paxo-mac` (내부 식별자, 아무 문자열)
- 사용자 액세스: 전체

앱 생성 후 좌측 **가격 및 사용 가능 여부**:
- 가격: **무료** (수익은 인앱 구독)
- 판매 지역: 대한민국 (원하면 전체)

---

## 3. 구독 상품 (앱 → 수익화 → 구독)

1. **구독 그룹** 생성: 이름 `Paxo Pro` (사용자에게 안 보이는 그룹명)
2. **상품 1 추가** — 참조 이름 `Pro Monthly`, 제품 ID **`com.hyeseong.Paxo.pro.monthly`** ⚠️ 코드와 정확히 일치
   - 구독 기간: **1개월**
   - 구독 가격: **₩6,900** (전 지역 자동 환산)
   - 현지화(한국어): 표시 이름 **Paxo Pro 월간**, 설명 **풀이와 해설 무제한**
   - 프로모션 혜택 → **입문 혜택(Introductory Offer)** → 무료 → 기간 **1주** (7일 무료 체험)
3. **상품 2 추가** — 참조 이름 `Pro Yearly`, 제품 ID **`com.hyeseong.Paxo.pro.yearly`**
   - 기간 **1년** / 가격 **₩49,000** / 표시 이름 **Paxo Pro 연간** / 입문 혜택 7일 무료 동일
4. 각 상품에 **심사용 스크린샷**(페이월 캡처 1장)과 심사 메모 첨부 — 없으면 구독이 "제출 준비 안 됨" 상태.

> ⚠️ 로컬 테스트용 `Config/Paxo.storekit`은 $4.99로 떠 있지만 그건 시뮬레이션 값일 뿐, **실제 판매가는 여기 ASC에서 정한 ₩6,900/₩49,000**을 따른다.

가격 근거: 콴다 프리미엄 18,500원 대비 저렴한 진입가. AI 원가 1회 약 6원이라 마진 충분. 반응 보고 조정.

---

## 4. 앱 개인정보 (앱 → 앱 개인정보 보호)

"데이터 수집" → 예. 아래대로 답변(정직하게, 프록시 실제 동작과 일치):

| 데이터 유형 | 수집 | 용도 | 사용자 신원 연결 | 추적 |
|---|---|---|---|---|
| 사용자 콘텐츠(화면 캡처 이미지) | 예 | 앱 기능 | 아니오 | 아니오 |
| 식별자(익명 기기 ID) | 예 | 앱 기능(사용량 제한) | 아니오 | 아니오 |

- 캡처 이미지는 "전송 후 저장 안 함"이므로, 애플 질문에서 "앱 기능에만 사용, 사용자와 연결 안 함, 추적 안 함"으로 답.
- **개인정보 처리방침 URL**: `https://paxo-proxy.vercel.app/privacy`

---

## 5. 스토어 페이지 (앱 → macOS 앱 → 1.0 준비 중 버전)

`docs/app-store-copy.md`에서 그대로 붙여넣기:
- **이름/부제/프로모션 텍스트/설명/키워드** — 각 칸에 해당 블록 복사
- **지원 URL**: `https://paxo-proxy.vercel.app/privacy` (연락처 이메일 포함돼 있어 지원 URL로 사용 가능)
- **마케팅 URL**: (선택, 없으면 비움)
- **저작권**: `2026 Hyeseong Yun`

### 스크린샷 (macOS: 최소 1장, 4장 권장)
- 허용 크기(정확히 일치해야 업로드됨): **1280×800, 1440×900, 2560×1600, 2880×1800** 중 하나로 통일.
- 레티나 맥 전체 캡처(⇧⌘3)는 크기가 안 맞으니 크롭/리사이즈:
  ```bash
  # 16:10 비율로 맞춘 뒤(또는 창만 캡처 후 캔버스 배치), 정확한 픽셀로 리사이즈
  sips -z 1800 2880 원본.png --out 제출용_2880x1800.png
  ```
- **추천 4컷**: ① 문제 화면 위 결과 패널(정답+해설) ② 빠른 채점 모드/토스트 ③ 온보딩 환영 ④ 페이월
- ⚠️ **스크린샷 속 문제는 직접 만든 예제**만 (교재·기출 캡처 = 저작권 리스크). `problem.png`처럼 자작 문제 사용.

---

## 6. 심사 정보 (버전 페이지 하단 App Review Information)

- 연락처: 이름/이메일/전화
- **데모 계정 필요? → 아니오** (로그인 없음)
- **메모(Notes)**: `docs/app-store-copy.md`의 **Review Notes**(영문) 통째로 붙여넣기 — 화면 기록 권한 사유·AI 사용 고지·테스트 방법이 다 들어 있어 심사 왕복을 줄인다.
- 첨부: 필요 시 짧은 시연 영상/스크린샷(선택).

---

## 7. 빌드 아카이브 & 업로드 (Xcode)

전제: §A 버전 1.0.0, §B 팀·서명 정리 완료.
1. Xcode 상단 스킴을 **Paxo**, 대상 **My Mac (Any Mac)** 으로.
2. **Product → Archive** (Archive는 자동으로 **Release** 구성 사용 → `#if DEBUG` 직접호출 경로 없이, 내장 Vercel 프록시+토큰으로만 동작).
   - Archive 메뉴가 비활성이면 대상이 시뮬레이터/특정 기기로 돼 있는 것 → "My Mac"으로.
3. Organizer 창 → 해당 아카이브 선택 → **Distribute App** → **App Store Connect** → **Upload**.
   - 서명: **Automatically manage signing** 선택 → 유료 팀으로 Distribution 서명 자동.
   - 업로드 완료까지 몇 분. "Upload Successful".
4. ASC → 앱 → 빌드 처리 대기(⏱ 처리에 5~30분, 이메일 옴). 처리되면 버전 페이지 **빌드** 섹션에서 그 빌드 선택.
   - 수출 규정: Info.plist에 `ITSAppUsesNonExemptEncryption=false` 넣어둬서 추가 질문 없이 통과.

---

## 8. 제출

버전 페이지 상단 **심사에 제출(Submit for Review)**:
- 구독 상품 2개가 이 버전과 함께 제출되는지 확인(첫 구독은 앱과 함께 심사).
- 제출 → 상태 "심사 대기 중(Waiting for Review)".

---

## 9. 심사 대응

- 보통 **1~3일** 내 결과(이메일).
- 리젝 시: Resolution Center에서 사유 확인 → 수정 → 재제출. **왕복 1~2회는 정상.**
- 이 앱 예상 쟁점과 대응:
  - **화면 기록 권한**: "사용자가 단축키를 눌렀을 때만 캡처, 상시 녹화 없음, 서버 무저장" — Review Notes에 이미 명시.
  - **AI 정확성/성격**: "학습 도우미, 해설 항상 제공(빠른 채점 모드도 해설을 숨기지 않고 접을 뿐)" 강조. 커닝툴 아님.
  - **인앱 구매 관련**: 구독 조건(자동 갱신, 해지 방법)이 앱 설명·페이월에 명시돼 있음(copy 문서에 포함).

---

## 부록: 값 요약

| 항목 | 값 |
|---|---|
| 번들 ID | `com.hyeseong.Paxo` |
| 월 구독 ID | `com.hyeseong.Paxo.pro.monthly` — ₩6,900 |
| 연 구독 ID | `com.hyeseong.Paxo.pro.yearly` — ₩49,000 |
| 무료 체험 | 7일 (양쪽) |
| 개인정보/지원 URL | `https://paxo-proxy.vercel.app/privacy` |
| 카테고리 | 교육 |
| 버전 | 1.0.0 (빌드 1) |
| 서명 | Automatic, 유료 Developer 팀 |
