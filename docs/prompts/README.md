# 프롬프트 라이브러리

두 번 이상 같은 프롬프트를 입력했다면 여기 저장한다. 개인 것이 아니라 팀 자산이다.

## 개발용 (이 디렉토리, 버전 관리)

| 파일 | 언제 쓰나 |
|---|---|
| [pr-description.md](pr-description.md) | PR 설명 초안 |
| [bug-to-repro.md](bug-to-repro.md) | 버그 리포트를 재현 코드·테스트로 |
| [refactor-review.md](refactor-review.md) | 머지 전 셀프 리뷰 |
| [release-notes.md](release-notes.md) | 커밋 기록으로 릴리스 노트 |

## 실행형 워크플로우 (Claude Code 스킬)

`/` 로 바로 호출한다. Codex를 쓴다면 아래 문서 경로를 직접 참조하면 된다.

| 명령 | 하는 일 | 근거 문서 |
|---|---|---|
| `/release-check` | App Store 제출 전 검사 | `docs/private/app-store-submission.md` (비공개) |
| `/proxy-change` | 클라이언트·프록시 동시 변경 절차 | `proxy-vercel/AGENTS.md` |
| `/weekly-report` | 커밋 기반 주간 보고서 | — |

## 비개발용 (노션)

마케팅 문구, 인터뷰 분석, 회의록 요약, 설문 문항은 노션 프롬프트 DB에 둔다.
코드와 함께 버전 관리할 필요가 없고, 비개발 맥락에서 더 자주 손대기 때문이다.

> 노션 DB 링크: _(팀 워크스페이스 생성 후 여기 채울 것)_
