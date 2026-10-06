# AI PR Review 파일럿 운영 가이드

Phase 3 구현 범위: GitHub Actions에서 PR diff를 Gemini로 검토하고 PR의 단일 요약 댓글을 갱신한다. 새 commit이 오면 직전 검토 SHA 이후 diff를 우선 사용한다. finding의 사람 판정은 같은 댓글에 유지한다. AI는 승인이나 머지를 수행하지 않는다.

## 활성화 준비

1. 이 변경을 `develop`에 PR로 반영한다. `pull_request_target`과 `issue_comment` 워크플로는 기준 브랜치의 신뢰된 파일을 실행한다. 이 PR 자체의 head 코드는 비밀 키가 있는 job에서 실행하지 않는다.
2. GitHub 저장소 Settings → Secrets and variables → Actions에 `AI_REVIEW_GEMINI_API_KEY` repository secret을 등록한다. 제품 프록시의 `GEMINI_API_KEY`와는 별도로 발급·회전한다.
3. 필요하면 `AI_REVIEW_MODEL` repository variable을 설정한다. 기본값은 저장소에서 사용 중인 `gemini-3.6-flash`이다. 모델 변경은 검토 품질과 비용을 재측정한 뒤 반영한다.
4. 조직/저장소의 Actions 정책에서 `pull_request_target` 실행이 허용되는지 관리자가 확인한다. 공개 저장소에는 GitHub의 기본 제한이 적용될 수 있다. 이 워크플로는 PR head를 checkout하거나 실행하지 않으므로 해당 정책을 완화할지 관리자가 결정한다.
5. 시험용 PR에서 `AI PR Review`가 실행되고 요약 댓글 하나가 생성되는지 확인한다. PR에 새 commit을 push해 같은 댓글이 갱신되는지 확인한다.

워크플로 파일은 `.github/workflows/ai-review.yml`, 엔진은 `.github/ai-review/`에 있다. Node 24의 내장 API만 사용하므로 별도 npm dependency가 없다.

## 처리 범위

- 트리거: PR opened, synchronize, reopened, ready_for_review.
- PR API에서 변경 파일과 patch를 읽는다. 기존 검토 상태가 있으면 GitHub Compare API로 지난 head부터 새 head까지의 diff를 먼저 사용한다. force push나 비교 실패 시 현재 PR 전체 diff로 돌아간다.
- base branch checkout의 루트·영역별 `AGENTS.md`, `docs/architecture.md`, `docs/domain.md`, `docs/decisions.md`를 필요한 범위만 읽는다.
- `Paxo/Secrets.swift`, `.env*`, `docs/private/**`, `docs/hansung/**`, binary/generated 파일, 삭제된 파일, patch가 없는 파일은 모델 입력에서 제외한다. 증분 diff뿐 아니라 PR 전체 파일에서 secret 형태가 의심되면 해당 run의 Gemini 호출을 중단한다. AI 응답에도 의심 값이 있으면 댓글을 쓰지 않는다.
- 한 번에 최대 60개 파일, diff 60,000자, context 24,000자, finding 20개, PR당 성공한 모델 호출 20회로 제한한다. 제외 파일 수와 호출 수를 댓글에 표시한다.
- AI가 반환한 finding은 실제 검토 파일의 추가된 줄만 허용한다. severity, confidence, category, classification, file, line, 원인, 영향, 조치를 검증한다.
- API key와 원문 diff는 Actions 로그에 출력하지 않는다. 요청 실패 시 HTTP 상태만 기록한다.

GitHub의 `pull_request_target` 보안 지침상 [PR head를 checkout하여 실행하는 것은 위험하다](https://docs.github.com/en/actions/reference/security/securely-using-pull_request_target). 이 workflow의 checkout은 기준 브랜치의 스크립트만 가져오고, PR patch는 GitHub API의 데이터로만 처리한다. Workflow나 리뷰 스크립트가 바뀌는 PR은 특히 신중히 검토한다.

## Finding과 사람 판정

요약 댓글에는 `AX-<fingerprint>` ID가 붙는다. 같은 원인을 다시 발견하면 기존 ID와 상태를 갱신하므로 push마다 새 review comment를 쌓지 않는다. 해결 판정은 AI가 `resolvedIds`에 명시하고 그 파일이 이번 증분 diff에 포함된 경우에만 반영된다. 확신하지 못한 문제는 `potential`, `needs-human-review`, `suggestion`으로 표시한다.

저장소에 write, maintain 또는 admin 권한이 있는 사람이 PR 댓글로 판정한다.

```text
/ai-review false-positive AX-0123456789ab 의도된 예외 처리이며 서버에서 이미 검증합니다
/ai-review accepted-risk AX-0123456789ab 이번 릴리스 범위 밖이며 별도 이슈에서 추적합니다
/ai-review reopen AX-0123456789ab
```

오탐과 위험 수용에는 10자 이상의 이유가 필요하다. 댓글 본문을 AI 명령으로 실행하지 않고, 정확한 문법과 GitHub repository 권한을 확인한 뒤 상태만 바꾼다. `false-positive`/`accepted-risk` 판정은 이후 동일 fingerprint 재검토에서도 유지된다. 리뷰 요약의 상태는 GitHub 댓글 내부의 숨김 메타데이터에 저장되며, 공개 저장소의 댓글이므로 민감정보를 포함하지 않는다.

## 검증과 파일럿 판정

로컬 검증:

```sh
node --test .github/ai-review/*.test.mjs
node --check .github/ai-review/core.mjs
node --check .github/ai-review/run.mjs
```

CI의 `AI 리뷰 엔진 테스트` job이 순수 로직을 매 PR에서 검증한다. 실제 Gemini 호출과 GitHub 댓글 쓰기는 repository secret이 설정된 뒤 시험 PR로 확인한다.

초기 20개 PR은 shadow 평가로 운영한다. AI finding은 머지 요구 조건에 넣지 않고, 사람이 각 finding을 `valid/fixed`, `false-positive`, `accepted-risk`, `unresolved`로 판정한다. 오탐률 목표는 첫 20개 PR의 분포를 본 뒤 팀이 합의한다. 다음 수치를 기록한다.

- AI 리뷰 소요 시간과 호출 수
- PR당 검토 파일·제외 파일 수
- 신규·유지·해결 finding 수
- 사람 판정이 있는 finding의 오탐률
- 동일 finding 중복 comment 수
- API 오류와 예산 초과 빈도

파일럿 중 false positive가 과도하거나 비용이 목표를 초과하면 prompt, context 범위, 모델을 조정한다. 결과가 유의미해질 때까지 AI finding은 required check나 Code Owner 승인에 포함하지 않는다.

## 현재 제한

- 별도 DB 없이 bot 댓글에 상태를 보관한다. 댓글이 삭제되면 이전 finding 이력이 사라져 다음 run은 전체 검토를 한다.
- 이름과 코드 위치가 크게 바뀌면 fingerprint가 달라질 수 있다. 동일 의미 중복은 20개 PR 표본에서 측정해 보정한다.
- GitHub Compare API가 fork commit을 비교하지 못하거나 force push가 발생하면 전체 PR diff를 검토한다.
- `pull_request_target`의 check는 PR head의 required status로 사용하지 않는다. Phase 3 결과는 요약 댓글과 Actions run에서 확인한다.
- AI 응답을 실제 Gemini API와 연결하는 end-to-end 검증은 secret 설정 뒤에만 가능하다.

참고: [Gemini 구조화 출력](https://ai.google.dev/gemini-api/docs/generate-content/structured-output), [GitHub PR 이벤트](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows), [GitHub Issue comment API](https://docs.github.com/en/rest/issues/comments).
