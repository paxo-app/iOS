#!/usr/bin/env bash
# 풀이 속도 개선 전에 "지금 어디서 얼마나 걸리는지"를 숫자로 남기기 위한 API 기준선 측정.
# 앱에는 로깅을 넣지 않기로 했으므로(AGENTS.md) 프록시를 직접 호출해 잰다.
# 캡처 · 인코딩 · 화면 렌더링 시간은 포함되지 않는다.
#
# 측정 항목
#   cold  : 새 연결로 정답 요청 → 받은 정답을 넣어 해설 요청 (앱과 같은 2단계)
#   warm  : 같은 연결에서 GET으로 먼저 핸드셰이크 → 정답 요청 (연결 예열 실험)
#   GET은 프록시가 토큰 · 사용량 검사 전에 405로 돌려보내므로 Gemini를 호출하지 않는다.
#
# 주의
#   - 현재 프록시는 Gemini 응답을 전부 받은 뒤 보내므로 TTFB는 "첫 토큰" 시간이 아니다.
#   - 실제 Gemini를 호출한다. 기본 5회 = POST 15회. 프록시 기기당 하루 60회(UTC, best-effort) 안에서 쓴다.
#   - 반복 5회의 p90은 탐색용이다. 원자료 CSV를 함께 본다.
#
# 사용법
#   PAXO_PROXY_URL=https://api.paxo.co.kr PAXO_TOKEN=... scripts/measure-latency.sh [반복 횟수]
#   결과: 현재 디렉터리의 latency-<시각>.csv (토큰은 기록하지 않는다. 커밋하지 않는다)
set -euo pipefail

: "${PAXO_PROXY_URL:?PAXO_PROXY_URL을 지정하세요}"
: "${PAXO_TOKEN:?PAXO_TOKEN을 지정하세요}"

RUNS="${1:-5}"
BASE="${PAXO_PROXY_URL%/}"
URL="$BASE/generate"
# 실제 사용자와 섞이지 않도록 측정 전용 고정 기기 ID를 쓴다
DEVICE="00000000-0000-4000-8000-00000000a11c"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="$ROOT/scripts/fixtures/sample-problem.jpg"
OUT="$PWD/latency-$(date +%Y%m%d-%H%M%S).csv"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
chmod 700 "$WORK"

# 토큰이 프로세스 목록(ps)에 드러나지 않도록 헤더는 파일로 넘긴다
HEADERS="$WORK/headers"
printf 'content-type: application/json\nx-paxo-device: %s\nx-paxo-token: %s\n' "$DEVICE" "$PAXO_TOKEN" >"$HEADERS"
chmod 600 "$HEADERS"

# 프롬프트는 Paxo/AI/Prompts.swift(일반 프리셋)와 같게 유지한다. 바뀌면 여기도 고친다.
build_body() {
  python3 - "$IMAGE" "$1" "${2:-}" <<'PY'
import base64, json, sys
image, kind, answer = sys.argv[1], sys.argv[2], sys.argv[3]
if kind == "answer":
    prompt = (
        "당신은 한국어 학습 도우미입니다. 이미지에 있는 문제를 정확히 풀어주세요.\n\n"
        "출력 형식: 정답만 한 줄로 간결하게 출력하세요. 풀이 과정은 다음 단계에서 별도로 요청됩니다.\n"
        "- 객관식이면 번호만 (예: ③)\n"
        "- 단답형이면 답만\n"
        "- 구해야 하는 답이 여러 개면 순서대로 쉼표로 구분 (예: 첫번째답, 두번째답)"
    )
else:
    prompt = (
        f"당신은 친절한 한국어 과외 선생님입니다. 이미지에 있는 문제의 정답은 \"{answer}\"입니다.\n\n"
        "학생이 이해할 수 있도록 왜 이 답이 되는지 설명해주세요:\n"
        "1. 문제가 묻는 핵심 개념\n"
        "2. 단계별 풀이 과정\n"
        "3. 헷갈리기 쉬운 포인트 (오답 선택지가 있다면 왜 틀렸는지)\n"
        "간결하되 핵심이 빠지지 않게, 읽기 쉬운 짧은 문단으로 작성하세요. "
        "간단한 마크다운(굵게, 목록)을 사용해도 됩니다."
    )
with open(image, "rb") as f:
    data = base64.b64encode(f.read()).decode()
body = {"contents": [{"parts": [{"text": prompt}, {"inline_data": {"mime_type": "image/jpeg", "data": data}}]}]}
print(json.dumps(body, ensure_ascii=False))
PY
}

extract_text() {
  python3 -c '
import json, sys
try:
    parts = json.load(open(sys.argv[1]))["candidates"][0]["content"]["parts"]
    print("\n".join(p.get("text", "") for p in parts).strip())
except Exception:
    print("")
' "$1"
}

FORMAT='%{http_code},%{http_version},%{num_connects},%{time_namelookup},%{time_connect},%{time_appconnect},%{time_starttransfer},%{time_total},%{size_upload},%{size_download}\n'
echo "run,mode,request,http_code,http_version,new_connections,dns_s,tcp_s,tls_s,ttfb_s,total_s,bytes_up,bytes_down" >"$OUT"

build_body answer >"$WORK/answer.json"
echo "측정 대상: $BASE · 반복 ${RUNS}회 · 예상 POST $((RUNS * 3))회"

for run in $(seq 1 "$RUNS"); do
  # cold: 새 프로세스 = 새 연결
  line=$(curl -sS -o "$WORK/answer.out" -w "$FORMAT" -H @"$HEADERS" --data-binary @"$WORK/answer.json" "$URL")
  echo "$run,cold,answer,$line" >>"$OUT"
  answer="$(extract_text "$WORK/answer.out")"
  if [ -z "$answer" ]; then
    echo "  #$run 정답 요청 실패 ($(cut -d, -f1 <<<"$line")) — 해설 측정 건너뜀"
  else
    build_body explanation "$answer" >"$WORK/explanation.json"
    line=$(curl -sS -o "$WORK/explanation.out" -w "$FORMAT" -H @"$HEADERS" --data-binary @"$WORK/explanation.json" "$URL")
    echo "$run,cold,explanation,$line" >>"$OUT"
  fi

  # warm: 같은 curl 실행 안에서 GET으로 연결을 맺고 그 연결로 정답 요청
  curl -sS -o /dev/null -w "GET,$FORMAT" "$URL" \
    --next -o /dev/null -w "POST,$FORMAT" -H @"$HEADERS" --data-binary @"$WORK/answer.json" "$URL" \
    | while IFS= read -r row; do
      kind="${row%%,*}"
      rest="${row#*,}"
      [ "$kind" = "GET" ] && echo "$run,warm,prewarm_get,$rest" >>"$OUT"
      [ "$kind" = "POST" ] && echo "$run,warm,answer,$rest" >>"$OUT"
    done
  echo "  #$run 완료 (정답: ${answer:-없음})"
done

echo
python3 - "$OUT" <<'PY'
import csv, statistics, sys
rows = list(csv.DictReader(open(sys.argv[1])))
def pct(values, p):
    values = sorted(values)
    if not values:
        return float("nan")
    k = (len(values) - 1) * p
    lo, hi = int(k), min(int(k) + 1, len(values) - 1)
    return values[lo] + (values[hi] - values[lo]) * (k - lo)
def sec(value, digits):
    return "-" if value != value else f"{value:.{digits}f}s"
print(f"{'구분':<22}{'성공/전체':>10}{'새 연결':>8}{'TLS까지 p50':>13}{'총 p50':>9}{'총 p90':>9}")
for mode, req in [("cold", "answer"), ("warm", "answer"), ("cold", "explanation"), ("warm", "prewarm_get")]:
    group = [r for r in rows if r["mode"] == mode and r["request"] == req]
    ok = [r for r in group if r["http_code"] in ("200", "405")]
    total = [float(r["total_s"]) for r in ok]
    tls = [float(r["tls_s"]) for r in ok]
    conns = sum(int(r["new_connections"]) for r in group)
    print(
        f"{mode + ' ' + req:<22}{len(ok):>6}/{len(group):<3}{conns:>8}"
        f"{sec(pct(tls, .5), 3):>13}{sec(pct(total, .5), 2):>9}{sec(pct(total, .9), 2):>9}"
    )
print("\nwarm answer의 새 연결이 0이면 예열 연결을 재사용한 것이다. 원자료:", sys.argv[1])
PY
