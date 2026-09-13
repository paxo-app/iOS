---
name: proxy-change
description: GeminiService의 요청 형태나 프록시 API를 바꿀 때의 절차. 클라이언트와 서버를 같은 PR에서 함께 고치도록 강제한다. 모델 변경, 프롬프트 파라미터 추가, 스트리밍 전환에 쓴다.
---

# 클라이언트 · 프록시 동시 변경

## 왜 이 스킬이 있나

프록시는 요청 본문을 통과시키지 않고 **화이트리스트로 재조립한다.**
클라이언트만 고치면 조용히 400이 돌아온다. 로컬에서는 DEBUG 직접 호출 경로 때문에
동작하는 것처럼 보일 수도 있어 더 위험하다.

## 절차

### 1. 양쪽을 먼저 읽는다

- `Paxo/AI/GeminiService.swift` — 요청 조립, 응답 파싱, 에러 매핑
- `proxy-vercel/api/generate.js` — `buildUpstreamBody`의 화이트리스트
- `proxy-vercel/AGENTS.md` — 계약 요약

### 2. 무엇이 막히는지 확인한다

현재 통과 가능한 것은 `text` 파트 1개와 `inline_data` 파트 1개뿐이다.
`generationConfig`, `systemInstruction`, `safetySettings`, `tools`, 추가 파트는 전달되지 않는다.

추가하려는 필드가 여기 걸리면 **프록시를 먼저 고쳐야 한다.**

### 3. 순서대로 바꾼다

1. `proxy-vercel/api/generate.js`의 화이트리스트를 넓힌다
2. 로컬에서 프록시를 돌려 확인하거나, 프리뷰 배포로 확인한다
3. `GeminiService.swift`를 바꾼다
4. 앱을 빌드해 실제 호출이 200을 받는지 확인한다

### 4. 배포 순서를 지킨다

**프록시를 먼저 배포하고 앱을 나중에 배포한다.** 반대로 하면 구버전 프록시가 새 요청을 거부한다.

### 5. 같은 PR에 넣는다

두 변경을 나누면 중간 상태에서 앱이 깨진다. PR 템플릿의 해당 체크박스를 확인한다.

## 스트리밍으로 바꾸려면

지금은 `:generateContent` 일회성 요청이다. `:streamGenerateContent`로 바꾸려면
프록시의 응답 전달 방식과 클라이언트의 파싱을 **둘 다** 다시 써야 한다.
"정답 먼저, 해설 나중"은 스트리밍이 아니라 요청 2회로 구현돼 있다는 점을 먼저 이해할 것.
