export default function handler(req, res) {
  if (req.method !== "GET") return res.status(405).send("method not allowed");
  res.setHeader("content-type", "text/html; charset=utf-8").send(SERVICE_HTML);
}

const SERVICE_HTML = `<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="description" content="Paxo의 디지털 서비스 제공 방식, 풀이권 충전, 결제 및 이용 권한 안내입니다.">
<title>Paxo 서비스·충전 안내</title>
<style>
  :root { color-scheme: light; font-family: -apple-system, BlinkMacSystemFont,
    "Apple SD Gothic Neo", sans-serif; color: #192840; background: #f4f7fc; }
  * { box-sizing: border-box; }
  body { margin: 0; font-size: 16px; line-height: 1.8; }
  main { max-width: 900px; margin: 0 auto; padding: 48px 24px; }
  header, section { background: #fff; border: 1px solid #dce4f0; border-radius: 18px;
    padding: 28px 32px; margin-bottom: 20px; }
  .brand { color: #1761d7; font-weight: 700; letter-spacing: .04em; }
  h1 { font-size: clamp(25px, 4vw, 34px); line-height: 1.4; margin: 8px 0 12px; }
  h2 { font-size: 21px; line-height: 1.5; margin: 0 0 14px; }
  p { margin: 10px 0; }
  .muted, footer { color: #54647c; font-size: 14px; }
  .notice { border-left: 3px solid #1761d7; padding-left: 14px; }
  ol, ul { margin: 10px 0; padding-left: 24px; }
  li { margin-bottom: 8px; }
  .plans { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }
  .plan { border: 1px solid #dce4f0; background: #f8faff; border-radius: 12px; padding: 20px; }
  .plan h3 { font-size: 17px; margin: 0 0 8px; }
  .price { font-size: 25px; font-weight: 700; margin: 0; }
  a { color: #145bc9; text-underline-offset: 3px; overflow-wrap: anywhere; }
  footer { padding: 0 8px; }
  @media (max-width: 560px) {
    main { padding: 20px 14px; }
    header, section { padding: 22px 20px; }
    .plans { grid-template-columns: 1fr; }
  }
  @media print {
    :root { background: #fff; }
    main { padding: 0; }
    header, section { break-inside: avoid; }
  }
</style>
</head>
<body>
<main>
<header>
  <div class="brand">Paxo</div>
  <h1>서비스·충전 안내</h1>
  <p>화면 속 문제를 캡처하면 AI가 정답과 해설을 제공하는 macOS용 디지털 서비스입니다.</p>
  <p class="muted">안내 기준일: 2026년 11월 6일 · macOS 14 이상 · 인터넷 연결 필요</p>
  <p class="notice">현재 App Store 출시 준비 중입니다. 아래는 대한민국 기준 충전 상품 구성이며, 실제 구매 시 Apple 결제 화면의 조건을 확인해 주세요.</p>
</header>

<section aria-labelledby="delivery">
  <h2 id="delivery">디지털 서비스 제공 방식</h2>
  <ol>
    <li><strong>앱 설치 및 로그인:</strong> App Store에서 Paxo를 다운로드하여 Mac에 설치하고
    Apple 계정으로 로그인합니다. 화면 캡처 기능을 이용하려면 macOS 화면 기록 권한이 필요합니다.</li>
    <li><strong>풀이권 충전:</strong> 앱의 ‘풀이권 충전’에서 원하는 수량을 선택하고
    Apple의 App Store 인앱결제 절차를 진행합니다. 자동 갱신되지 않는 일회성 구매입니다.</li>
    <li><strong>잔액 반영:</strong> Apple 구매 승인과 서버 검증이 완료되면 로그인한 Paxo 계정에
    풀이권이 적립됩니다. 잔액이 반영되지 않으면 같은 Paxo 계정으로 로그인한 상태에서 충전 내역을 다시 확인해 주세요.
    앱 재설치 뒤에도 같은 계정의 서버 잔액을 불러옵니다.</li>
    <li><strong>온라인 제공:</strong> 단축키로 문제 영역을 선택하면 요청을 서버에서 처리하고,
    정답과 해설을 앱 안의 결과 화면으로 제공합니다. 빠른 채점 모드에서는 정답을 먼저 확인할 수 있습니다.</li>
  </ol>
  <p class="notice"><strong>실물 상품의 배송은 없습니다.</strong> 구매 대상은 앱 내 AI 풀이 서비스를
  필요할 때 이용할 수 있는 풀이권입니다. 별도 택배 발송이나 실물 인도 절차는 없습니다.</p>
</section>

<section aria-labelledby="plans">
  <h2 id="plans">무료 이용 및 풀이권 충전</h2>
  <p>무료로 하루 2회 풀이를 제공합니다. 무료분은 매일 오전 6시(한국 시간)에 초기화되며 남은 무료분은 이월되지 않습니다.
  충전한 풀이권에는 유효기간이 없으며 매일 무료분을 먼저 사용합니다.
  정답 제공에 성공했을 때 1회 차감하며, 해당 풀이의 해설은 추가 차감하지 않습니다.</p>
  <div class="plans">
    <div class="plan"><h3>풀이권 30회</h3><p class="price">990원</p><p>유효기간 없는 일회성 충전</p></div>
    <div class="plan"><h3>풀이권 100회</h3><p class="price">2,900원</p><p>유효기간 없는 일회성 충전</p></div>
    <div class="plan"><h3>풀이권 500회</h3><p class="price">13,900원</p><p>유효기간 없는 일회성 충전</p></div>
    <div class="plan"><h3>풀이권 1,000회</h3><p class="price">26,900원</p><p>유효기간 없는 일회성 충전</p></div>
  </div>
  <p>충전분에는 일일 사용 상한이 없습니다. 다만 비정상적인 동시 요청이나 자동화 요청을 제한할 수 있습니다.
  기존 풀이 기록 열람에는 풀이권을 사용하지 않습니다.</p>
  <p class="muted">가격과 통화는 국가 및 계정에 따라 다를 수 있습니다.
  결제 전 앱에 표시되는 가격과 Apple 결제 확인 화면이 최종 적용 조건입니다.</p>
</section>

<section aria-labelledby="management">
  <h2 id="management">구매 확인 및 환불 문의</h2>
  <p>풀이권은 구입할 때만 결제되며 자동 갱신되지 않습니다. 구매한 풀이권은 로그인한 Paxo 계정에 연결되며 다른 계정으로 양도할 수 없습니다.
  계정 삭제 시 남은 풀이권도 삭제되므로 삭제 전에 잔액과 환불 가능 여부를 확인해 주세요.</p>
  <p>결제 취소·환불은 Apple의 환불 요청 절차에서 신청할 수 있으며 처리 결과는 Apple의 심사와 관련 법령에 따릅니다.
  환불된 상품의 풀이권은 회수됩니다. 이미 사용한 환불분은 이후 충전분에서 상계될 수 있으며 무료 제공은 유지됩니다.</p>
  <p>이전에 구매한 유효한 구독은 기존 이용 기간 동안 제공량을 유지합니다. 기존 구독의 자동 갱신 해지는 Apple 구독 관리에서 진행합니다.
  앱 삭제나 Paxo 계정 삭제만으로 기존 App Store 구독이 해지되지는 않습니다.</p>
  <p><a href="https://apps.apple.com/account/subscriptions">기존 Apple 구독 관리</a> ·
  <a href="https://reportaproblem.apple.com/">Apple 환불 요청</a></p>
</section>

<section aria-labelledby="help">
  <h2 id="help">이용 전 확인 및 문의</h2>
  <p>AI의 정답과 해설에는 오류가 있을 수 있으므로 학습 참고자료로 활용하고 중요한 내용은 직접 확인해 주세요.
  인터넷 연결, Apple 계정 상태 또는 서버 장애로 이용이 지연될 수 있습니다.</p>
  <p>서비스·충전 문의: <a href="mailto:paxo.app.official@gmail.com">paxo.app.official@gmail.com</a></p>
  <p><a href="/privacy">개인정보 처리방침</a> ·
  <a href="https://www.apple.com/legal/internet-services/itunes/dev/stdeula/">Apple 표준 이용약관</a></p>
</section>
<footer>이 페이지는 Paxo의 디지털 서비스 제공 방식과 충전 조건을 안내합니다.</footer>
</main>
</body>
</html>`;
