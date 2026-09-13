#!/usr/bin/env bash
# AX 도입 효과를 체감이 아니라 실측으로 확인하기 위한 지표 수집.
# METR 연구에서 개발자들은 19% 느려졌는데도 빨라졌다고 느꼈다. 그래서 숫자를 남긴다.
#
# 사용법: scripts/ax-metrics.sh [기간(일), 기본 30]
set -euo pipefail

DAYS="${1:-30}"
SINCE="$(date -v-"${DAYS}"d +%Y-%m-%d 2>/dev/null || date -d "${DAYS} days ago" +%Y-%m-%d)"

echo "# AX 지표 — 최근 ${DAYS}일 (${SINCE} 이후)"
echo "# 수집 시각: $(date '+%Y-%m-%d %H:%M')"
echo

echo "## 커밋"
echo "총 커밋: $(git log --since="$SINCE" --no-merges --oneline | wc -l | tr -d ' ')"
echo "기여자:"
git shortlog -sn --since="$SINCE" --no-merges HEAD | sed 's/^/  /' || echo "  (없음)"
echo

if ! gh auth status >/dev/null 2>&1; then
  echo "## PR / CI"
  echo "  gh 로그인이 필요합니다: gh auth login"
  exit 0
fi

echo "## PR 리드타임 (생성 → 머지)"
gh pr list --state merged --limit 100 \
  --json number,title,createdAt,mergedAt \
  --jq "[.[] | select(.mergedAt > \"${SINCE}\")]" > /tmp/ax-prs.json

count=$(python3 -c "import json;print(len(json.load(open('/tmp/ax-prs.json'))))")
if [ "$count" -eq 0 ]; then
  echo "  머지된 PR 없음 — 기준선 측정 시점입니다"
else
  python3 - <<'PY'
import json, statistics
from datetime import datetime
prs = json.load(open('/tmp/ax-prs.json'))
def hrs(p):
    f = "%Y-%m-%dT%H:%M:%SZ"
    return (datetime.strptime(p["mergedAt"], f) - datetime.strptime(p["createdAt"], f)).total_seconds() / 3600
d = sorted(hrs(p) for p in prs)
print(f"  머지된 PR: {len(d)}건")
print(f"  중앙값: {statistics.median(d):.1f}시간")
print(f"  평균:   {statistics.mean(d):.1f}시간")
print(f"  최대:   {d[-1]:.1f}시간")
PY
fi
echo

echo "## CI 통과율"
gh run list --limit 100 --json conclusion,createdAt \
  --jq "[.[] | select(.createdAt > \"${SINCE}\")] | group_by(.conclusion) | map({(.[0].conclusion // \"진행중\"): length}) | add" \
  || echo "  (워크플로우 실행 기록 없음)"
