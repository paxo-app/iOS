export default function handler(req, res) {
  if (req.method !== "GET") return res.status(405).send("method not allowed");
  res.setHeader("content-type", "text/html; charset=utf-8").send(SERVICE_HTML);
}

const SERVICE_HTML = `<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="description" content="Paxo의 디지털 서비스 제공 방식, Pro 구독, 결제 및 이용 권한 안내입니다.">
<title>Paxo 서비스·구독 안내</title>
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
  <h1>서비스·구독 안내</h1>
  <p>화면 속 문제를 캡처하면 AI가 정답과 해설을 제공하는 macOS용 디지털 서비스입니다.</p>
  <p class="muted">안내 기준일: 2026년 10월 12일 · macOS 14 이상 · 인터넷 연결 필요</p>
  <p class="notice">현재 App Store 출시 준비 중입니다. 아래 구독 가격과 무료 체험은
  App Store Connect에 등록된 대한민국 기준 설정이며, 실제 구매 시 Apple 결제 화면의 조건을 확인해 주세요.</p>
</header>

<section aria-labelledby="delivery">
  <h2 id="delivery">디지털 서비스 제공 방식</h2>
  <ol>
    <li><strong>앱 설치 및 로그인:</strong> App Store에서 Paxo를 다운로드하여 Mac에 설치하고
    Apple 계정으로 로그인합니다. 화면 캡처 기능을 이용하려면 macOS 화면 기록 권한이 필요합니다.</li>
    <li><strong>구독 신청 및 결제:</strong> 앱의 ‘Pro 알아보기’에서 월간 또는 연간 상품을 선택하고
    Apple의 App Store 인앱결제 절차를 진행합니다.</li>
    <li><strong>Pro 권한 활성화:</strong> Apple의 구매 승인과 구독 정보 검증이 완료되면
    유효한 구독 기간 동안 Pro 이용 권한이 활성화됩니다. 앱 설정의 ‘구독’에서 Pro 상태를 확인할 수 있습니다.
    권한이 반영되지 않으면 인터넷 연결을 확인한 뒤 ‘구매 복원’을 이용해 주세요.</li>
    <li><strong>온라인 제공:</strong> 단축키로 문제 영역을 선택하면 요청을 서버에서 처리하고,
    정답과 해설을 앱 안의 결과 화면으로 제공합니다. 빠른 채점 모드에서는 정답을 먼저 확인할 수 있습니다.</li>
  </ol>
  <p class="notice"><strong>실물 상품의 배송은 없습니다.</strong> 구매 대상은 앱 내 AI 풀이 서비스를
  구독 기간 동안 이용할 수 있는 디지털 서비스 이용 권한입니다. 별도 택배 발송이나 실물 인도 절차는 없습니다.</p>
</section>

<section aria-labelledby="plans">
  <h2 id="plans">무료 이용 및 Pro 구독상품</h2>
  <p>무료 이용은 하루 3회, Pro는 하루 최대 100회 풀이를 제공합니다.
  정답 제공에 성공했을 때 1회 차감하며, 해당 풀이의 해설은 추가 차감하지 않습니다.</p>
  <div class="plans">
    <div class="plan"><h3>Paxo Pro 월간</h3><p class="price">5,500원 / 1개월</p>
      <p>월 단위 자동 갱신 구독<br>하루 최대 100회 AI 풀이 및 해설</p></div>
    <div class="plan"><h3>Paxo Pro 연간</h3><p class="price">55,000원 / 1년</p>
      <p>연 단위 자동 갱신 구독<br>하루 최대 100회 AI 풀이 및 해설</p></div>
  </div>
  <p><strong>무료 체험:</strong> 대상 신규 구독자에게 첫 3일 무료 체험을 제공합니다.
  같은 구독 그룹에서 한 번만 적용되며, 자격 여부는 Apple이 확인합니다.
  무료 체험 후 구독을 유지하면 선택한 상품의 요금으로 자동 갱신됩니다.</p>
  <p class="muted">가격·통화·체험 자격은 국가 및 계정에 따라 다를 수 있습니다.
  결제 전 앱에 표시되는 가격과 Apple 결제 확인 화면이 최종 적용 조건입니다.</p>
</section>

<section aria-labelledby="management">
  <h2 id="management">구독 관리·해지 및 환불 문의</h2>
  <p>구독은 사용자가 해지하지 않으면 자동 갱신됩니다. App Store 계정의 구독 관리에서
  갱신을 해지할 수 있으며, 정확한 만료일과 이용 가능 기간은 Apple의 구독 관리 화면에서 확인할 수 있습니다.</p>
  <p>앱 삭제나 Paxo 계정 삭제만으로 App Store 구독이 자동 해지되지는 않습니다.
  결제 취소·환불은 Apple의 환불 요청 절차에서 신청할 수 있으며 처리 결과는 Apple의 심사와 관련 법령에 따릅니다.</p>
  <p><a href="https://apps.apple.com/account/subscriptions">Apple 구독 관리</a> ·
  <a href="https://reportaproblem.apple.com/">Apple 환불 요청</a></p>
</section>

<section aria-labelledby="help">
  <h2 id="help">이용 전 확인 및 문의</h2>
  <p>AI의 정답과 해설에는 오류가 있을 수 있으므로 학습 참고자료로 활용하고 중요한 내용은 직접 확인해 주세요.
  인터넷 연결, Apple 계정 상태 또는 서버 장애로 이용이 지연될 수 있습니다.</p>
  <p>서비스·구독 문의: <a href="mailto:paxo.app.official@gmail.com">paxo.app.official@gmail.com</a></p>
  <p><a href="/privacy">개인정보 처리방침</a> ·
  <a href="https://www.apple.com/legal/internet-services/itunes/dev/stdeula/">Apple 표준 이용약관</a></p>
</section>
<footer>이 페이지는 Paxo의 디지털 서비스 제공 방식과 구독 조건을 안내합니다.</footer>
</main>
</body>
</html>`;
