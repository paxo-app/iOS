import Foundation

/// 출시 빌드에 내장되는 기본 설정.
/// 심사원과 일반 사용자는 설정을 건드리지 않아도 이 프록시로 바로 동작한다.
enum DefaultConfig {
    /// 기본 프록시 URL (설정에서 사용자가 입력하면 그 값이 우선)
    /// Vercel(미국 리전 고정) — Cloudflare Workers는 Gemini 지역 차단이 간헐 발생해 백업으로만 유지
    static let proxyURL = "https://api.paxo.co.kr"

    /// 개인정보 처리방침 (프록시 워커가 /privacy 경로로 서빙)
    static let privacyPolicyURL = proxyURL + "/privacy"

    /// 이용약관 — Apple 표준 EULA
    static let termsOfUseURL = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"

    /// 프록시 접근 토큰 (x-paxo-token 헤더). 값은 Git에 올라가지 않는 `Paxo/Secrets.swift`에 있다
    /// (클론했다면 `Config/Secrets.example.swift`를 복사할 것 — README '개발 셋업' 참고).
    /// 바이너리에서 추출 가능한 공유 시크릿이므로 완전한 방어가 아니라
    /// 드라이브바이 어뷰징 차단용이다. 정식 방어는 향후 영수증 검증.
    static let appToken: String = Secrets.appToken
}
