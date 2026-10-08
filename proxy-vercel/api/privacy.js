export default function handler(req, res) {
  if (req.method !== "GET") return res.status(405).send("method not allowed");
  res.setHeader("content-type", "text/html; charset=utf-8").send(PRIVACY_HTML);
}

const PRIVACY_HTML = `<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Paxo 개인정보 처리방침</title>
<style>
  body { font-family: -apple-system, "Apple SD Gothic Neo", sans-serif; line-height: 1.7;
         max-width: 720px; margin: 0 auto; padding: 40px 20px; color: #222; }
  h1 { font-size: 1.6em; } h2 { font-size: 1.15em; margin-top: 2em; }
  @media (prefers-color-scheme: dark) { body { background: #1a1a1a; color: #ddd; } }
</style>
</head>
<body>
<h1>Paxo 개인정보 처리방침</h1>
<p>시행일: 2026년 9월 25일</p>

<h2>처리하는 정보</h2>
<ul>
  <li><strong>화면 캡처 이미지와 풀이 요청</strong>: 사용자가 풀이를 실행할 때 Google Gemini API로
      전달됩니다. Paxo는 이 콘텐츠를 파일이나 데이터베이스에 저장하지 않습니다. 요청 처리를 위해
      Vercel과 Google이 일시적으로 데이터를 처리할 수 있으며 각 제공자의 정책이 적용됩니다.</li>
  <li><strong>Apple 로그인 정보</strong>: Apple이 발급한 사용자 식별자는 HMAC으로 가명화한 뒤
      사용합니다. 이름과 이메일 권한은 요청하지 않습니다. 로그인 유지용 Apple 토큰은 암호화해
      최대 30일 보관하며 계정 사용 시 갱신됩니다.</li>
  <li><strong>구독 확인 정보</strong>: App Store가 서명한 앱·구독 정보를 검증합니다. 원본 App
      Transaction ID는 저장하지 않고 가명화한 연결 정보만 사용합니다.</li>
  <li><strong>사용량·보안 정보</strong>: 세션, 일일 사용량, 풀이 요청 상태는 콘텐츠 없이 Redis에
      저장됩니다. 풀이 상태와 사용량은 최대 48시간, 로그인 유지 정보는 최대 30일 보관합니다.
      Vercel 방화벽은 악용 방지를 위해 IP 주소와 요청 메타데이터를 처리할 수 있습니다.</li>
</ul>

<h2>이용 목적과 제공량</h2>
<p>위 정보는 로그인, 무료·Pro 권한 확인, 일일 사용량 제한, 중복 요청 방지와 AI 풀이 생성에만
사용합니다. 무료 사용자는 하루 3회, Pro 사용자는 비용 보호를 위해 하루 최대 100회 풀이할 수
있으며 해설 1회는 해당 풀이에 포함됩니다.</p>

<h2>제3자 처리</h2>
<p>서비스 제공을 위해 Apple(App Store 및 Apple 로그인), Vercel(서버 호스팅), Upstash(Redis),
Google(Gemini API)이 요청을 처리합니다. 각 제공자의 보관·처리 정책은 해당 서비스의 약관과
개인정보 처리방침을 따릅니다.</p>

<h2>로컬 저장 데이터</h2>
<p>최근 풀이의 정답·해설 텍스트와 앱 설정은 사용자 Mac에 저장됩니다. 캡처 이미지는 디스크에
저장하지 않습니다. 로그아웃이나 서버 계정 삭제만으로 로컬 풀이 기록은 삭제되지 않으며 사용자가
앱 데이터를 제거해 삭제할 수 있습니다.</p>

<h2>계정 삭제</h2>
<p>앱 설정의 ‘계정 삭제’를 사용하면 Apple 로그인 토큰을 폐기하고 Paxo 서버의 계정·세션·사용량
정보를 삭제합니다. 기기에 저장된 풀이 기록은 별도로 유지됩니다.</p>

<h2>문의</h2>
<p>개인정보 관련 문의: <a href="mailto:kimsonghansung@gmail.com">kimsonghansung@gmail.com</a></p>

<hr>
<h2>Privacy Policy (English Summary)</h2>
<p>Paxo uses Sign in with Apple without requesting name or email. The Apple user identifier is
pseudonymized, and the Apple refresh token is encrypted for up to 30 days. Screen captures are sent
through Vercel to Google Gemini only to generate an answer and are not persistently stored by Paxo.
Session, quota, and solve-state records contain no image or prompt content and expire within 48 hours;
login continuity records expire within 30 days. Free accounts receive 3 solves per day and Pro accounts
receive up to 100. Account deletion is available in the app. Contact: kimsonghansung@gmail.com</p>
</body>
</html>`;
