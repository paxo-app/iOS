import Foundation

/// 시크릿 템플릿. 이 파일을 `Paxo/Secrets.swift`로 복사한 뒤 값을 채우면 빌드된다.
///
///     cp Config/Secrets.example.swift Paxo/Secrets.swift
///
/// ⚠️ 이 파일을 `Paxo/` 안에 두지 말 것. Xcode 프로젝트가 `Paxo/` 디렉토리를
///    파일시스템 동기화로 자동 컴파일하기 때문에 `Secrets` 중복 선언으로 빌드가 실패한다.
///    그래서 템플릿은 컴파일 대상이 아닌 `Config/`에 둔다.
enum Secrets {
    /// 프록시 접근 토큰 (x-paxo-token 헤더). Vercel `APP_TOKEN` 환경변수와 값이 일치해야 한다.
    ///
    /// 빈 문자열로 두어도 빌드와 실행은 된다. 단 프록시에 `APP_TOKEN`이 설정된 뒤에는
    /// 토큰 없는 요청이 401로 거부되므로, 그 시점부터는 실제 값을 채워야 한다.
    static let appToken: String = ""
}
