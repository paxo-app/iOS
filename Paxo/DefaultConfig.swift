import Foundation

/// 출시 빌드에 내장되는 기본 설정.
/// 심사원과 일반 사용자는 설정을 건드리지 않아도 이 프록시로 바로 동작한다.
enum DefaultConfig {
    /// Release 빌드는 이 주소만 사용하며 사용자 설정으로 바꿀 수 없다.
    static let proxyURL = "https://api.paxo.co.kr"

    /// 개인정보 처리방침 (프록시 워커가 /privacy 경로로 서빙)
    static let privacyPolicyURL = proxyURL + "/privacy"

    /// 이용약관 — Apple 표준 EULA
    static let termsOfUseURL = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"

    /// 바이너리에서 추출 가능한 앱 버전 필터이며 실제 권한은 Apple 로그인 세션으로 검증한다.
    static let appToken: String = Secrets.appToken
}
