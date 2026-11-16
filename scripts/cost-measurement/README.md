# 정답·해설 API 비용 측정

실제 Gemini API 요청에서 반환한 토큰 사용량으로 표준 유료 단가 기준 비용을 계산한다.
앱의 `Prompts.swift`, 정답 표시·컨텍스트 규칙, 서버의 생성 설정·응답 검증을 재사용하고 동일한 재시도 정책을 적용한다.
서버·Redis·Apple 수수료·세금은 별도다. Google 청구서의 실제 결제액과도 구분한다.

## 준비 및 실행

앱 개발 설정에 Gemini API 키를 저장하거나 `GEMINI_API_KEY` 환경 변수로 전달한다.
키를 커맨드 인자에 넣지 않는다. 원본 키·프롬프트·모델 응답은 결과 파일에 기록하지 않는다.

```sh
swift -module-cache-path /tmp/paxo-cost-swift-module-cache \
  scripts/cost-fixtures.swift scripts/fixtures/cost-problems.json /tmp/paxo-cost-fixtures

node scripts/measure-api-cost.mjs --dry-run \
  --images /tmp/paxo-cost-fixtures --output /tmp/paxo-cost-dry-run

node scripts/measure-api-cost.mjs \
  --images /tmp/paxo-cost-fixtures --output /tmp/paxo-cost-run-01 \
  --repeats 2 --max-solves 26 --budget-usd 1
```

출력 디렉터리는 실행마다 새 경로를 사용한다. 기존 결과는 덮어쓰지 않는다.
`--budget-usd`는 응답에서 관측한 누적 비용을 기준으로 다음 요청을 차단하는 상한이다.
이미 진행 중인 한 요청의 비용만큼 초과할 수 있다. 사용량을 알 수 없는 응답이나 타임아웃에는 중단한다.

## 집계 규칙

- 1세트는 정답과 해당 정답을 전달한 해설이다. 정답 생성 성공만으로 세트 완료로 세지 않는다.
- 최초 요청과 재시도의 비용을 모두 기록한다. 실패 세트의 관측 비용도 전체 지출에 포함한다.
- 추론 토큰은 출력 단가로 계산하고 캐시 입력에는 할인 단가를 적용한다.
- 응답 사용량이 누락되거나 입력·출력·추론의 합계가 일치하지 않으면 비용 미확인으로 표시한다.
- 문제별 평균 외에 전체 관측 비용을 완료 세트 수로 나눈 비용도 확인한다.
- 모델은 `gemini-3.6-flash`, 단가는 2026-12-31까지의 Standard 요금이다. 이후 실행 전 공식 가격을 확인한다.

표본은 기존 사칙연산 이미지 1개와 직접 만든 합성 문제 12개다.
사용자 문제·개인정보를 사용하지 않으며 실제 문제 분포, 복잡한 도표나 흐린 사진을 대표하지 않는다.
같은 이미지의 반복 호출은 캐시 영향을 받을 수 있어 캐시 토큰도 별도로 기록한다.

공식 출처는 [Google 가격](https://ai.google.dev/gemini-api/docs/pricing),
[토큰 사용량 정의](https://ai.google.dev/api/generate-content),
[과금 안내](https://ai.google.dev/gemini-api/docs/billing)다.
