---
name: weekly-report
description: 커밋과 PR 기록으로 주간 보고서 초안을 만든다. 주간 회고, 진행 상황 공유, 팀 보고가 필요할 때 쓴다.
---

# 주간 보고서 초안

## 자료 수집

```sh
git log --since='7 days ago' --format='%h %an %s' --no-merges
git log --since='7 days ago' --format='%b' --no-merges
gh pr list --state merged --limit 30 --json number,title,mergedAt,author
gh run list --limit 20 --json conclusion,headBranch,createdAt
```

## 작성 형식

```
## 이번 주 한 일
(사람이 아니라 성과 단위로 묶는다. 커밋 나열 금지)

## 지표
- 머지된 PR: N건
- CI 통과율: N%
- develop 빌드 실패: N회

## 다음 주
(README 로드맵의 미완료 항목과 대조해서 제안한다)

## 막힌 것
(커밋 메시지나 PR 본문에서 드러난 것만. 없으면 "없음")
```

## 규칙

- **커밋을 그대로 나열하지 않는다.** 여러 커밋을 하나의 성과로 묶는다
- 숫자는 위 명령으로 실제 집계한 값만 쓴다. 추정하지 않는다
- "막힌 것"을 지어내지 않는다. 근거가 없으면 없다고 쓴다
- 한국어로 쓴다
