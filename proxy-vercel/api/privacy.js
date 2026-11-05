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
<p>시행일: 2026년 9월 25일 · 최종 수정일: 2026년 11월 3일</p>

<h2>처리하는 정보</h2>
<ul>
  <li><strong>화면 캡처 이미지와 풀이 요청</strong>: 사용자가 풀이를 실행할 때 Google Gemini API로
      전달됩니다. Paxo 서버는 이 콘텐츠를 파일이나 데이터베이스에 보관하지 않습니다.
      정답 생성에 성공한 문제 이미지와 풀이 기록은 아래 안내에 따라 사용자 Mac에 저장됩니다. 요청 처리를 위해
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
<p>최근 최대 100개의 풀이 기록(정답·해설, 풀이 시각, 자가 채점 결과, 직접 수정한 내용과 문제 유형·선택지 정보)과
정답 생성에 성공한 문제의 JPEG 이미지를 사용자 Mac의 앱 데이터 영역에 보관합니다.
앱 설정과 사용자가 만든 과목 이름·기록의 과목 지정 정보도 이 Mac에 저장됩니다.
무료 플랜의 최신 10개 열람 제한은 보관 개수와 다르며 구독 종료만으로 이전 기록을 삭제하지 않습니다.
100개를 초과해 보관 대상에서 빠진 기록의 문제 이미지는 정리합니다.</p>
<p>풀이 기록 상세 화면의 ‘기록 삭제…’에서 해당 기록과 문제 이미지를 삭제할 수 있습니다.
설정 → 풀이 기록 → ‘모든 기록 삭제…’에서는 검색·날짜·과목 필터와 무료 플랜의 열람 범위에 관계없이
이 Mac에 보관된 모든 풀이 기록과 문제 이미지를 삭제합니다. 삭제한 기록의 과목 지정 정보도 정리하며,
사용자가 만든 과목 목록과 앱 설정은 유지합니다. 과목 목록은 과목 관리에서 별도로 삭제할 수 있습니다.
저장·삭제에 실패하면 앱에 안내하며 다시 시도할 수 있습니다.</p>
<p>로그아웃이나 서버 계정 삭제만으로 로컬 풀이 기록과 문제 이미지는 삭제되지 않습니다.
로컬 기록 삭제는 서버 계정이나 구독을 삭제·해지하거나 이미 처리한 풀이 사용량을 되돌리는 동작이 아닙니다.</p>

<h2>계정 삭제</h2>
<p>앱 설정의 ‘계정 삭제’를 사용하면 Apple 로그인 토큰을 폐기하고 Paxo 서버의 계정·세션·사용량
정보를 삭제합니다. 기기에 저장된 풀이 기록과 문제 이미지, 과목 목록·지정 정보, 앱 설정은 별도로 유지됩니다.
로컬 풀이 기록과 문제 이미지는 설정의 풀이 기록 탭에서 삭제할 수 있습니다.</p>

<h2>문의</h2>
<p>개인정보 관련 문의: <a href="mailto:kimsonghansung@gmail.com">kimsonghansung@gmail.com</a></p>

<hr>
<h2>Privacy Policy (English Summary)</h2>
<p>Paxo uses Sign in with Apple without requesting name or email. The Apple user identifier is
pseudonymized, and the Apple refresh token is encrypted for up to 30 days. Screen captures are sent
through Vercel to Google Gemini to generate answers and explanations; Paxo servers do not persist their content.
The app stores up to 100 recent solve records and their JPEG captures locally on your Mac, along with
settings, subject names, and subject assignments. Free access to the latest 10 records is a viewing limit,
not a retention limit. Images belonging to records removed by the 100-record limit are cleaned up.
Delete an individual record from its detail screen, or delete all local records and images from
Settings → Solve History, including older records hidden by the free plan and records outside the current filter.
Record deletion removes subject assignments but keeps subject names and settings. Failed storage or cleanup
is shown in the app and can be retried. Signing out or deleting your account keeps local data;
deleting local records does not delete your server account, cancel your subscription, or refund used solves.
Session, quota, and solve-state records contain no image or prompt content and expire within 48 hours;
login continuity records expire within 30 days. Free accounts receive 3 solves per day and Pro accounts
receive up to 100. Account deletion is available in the app. Contact: kimsonghansung@gmail.com</p>
</body>
</html>`;
