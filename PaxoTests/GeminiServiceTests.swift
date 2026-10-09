import Foundation
import Testing

@testable import Paxo

struct GeminiServiceTests {
    @Test("프록시 요청은 앱 토큰과 Bearer 세션을 사용한다")
    func proxyRequestUsesSessionHeaders() throws {
        let service = GeminiService(
            apiKey: "development-key",
            proxyURL: "https://proxy.example.com/",
            useDirectGemini: false
        )

        let request = try service.makeRequest(sessionToken: "session-token")

        #expect(request.url?.absoluteString == "https://proxy.example.com/generate")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer session-token")
        #expect(request.value(forHTTPHeaderField: "x-paxo-token") != nil)
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == nil)
        #expect(request.value(forHTTPHeaderField: "x-paxo-device") == nil)
    }

    /// 취소를 네트워크 오류로 감싸면 사용자가 누른 취소가 "네트워크 오류" 화면으로 보인다.
    @Test func 취소된_요청은_취소로_분류된다() {
        let error = GeminiService.classify(URLError(.cancelled))
        #expect(error is CancellationError)
    }

    @Test func 다른_네트워크_오류는_그대로_네트워크_오류다() {
        let error = GeminiService.classify(URLError(.timedOut))
        guard case GeminiError.network(let underlying)? = error as? GeminiError else {
            Issue.record("GeminiError.network가 아니다: \(error)")
            return
        }
        #expect(underlying.code == .timedOut)
    }

    #if DEBUG
    @Test("개발 프록시 주소가 비어 있으면 Preview를 사용한다")
    func emptyDevelopmentProxyUsesPreview() throws {
        let service = GeminiService(
            apiKey: "",
            proxyURL: "",
            useDirectGemini: false
        )

        let request = try service.makeRequest(sessionToken: "session-token")

        #expect(request.url?.absoluteString == "https://preview-api.paxo.co.kr/generate")
    }

    @Test("개발용 직접 호출은 프록시를 우회한다")
    func directRequestUsesGeminiKey() throws {
        let service = GeminiService(
            apiKey: "development-key",
            proxyURL: "https://proxy.example.com",
            useDirectGemini: true
        )

        let request = try service.makeRequest(sessionToken: "unused")

        #expect(request.url?.host == "generativelanguage.googleapis.com")
        #expect(request.url?.path.contains("gemini-3.6-flash:generateContent") == true)
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "development-key")
        #expect(request.value(forHTTPHeaderField: "x-paxo-token") == nil)
    }

    @Test("개발용 직접 호출은 키가 없으면 실패한다")
    func directRequestRequiresKey() {
        let service = GeminiService(
            apiKey: "",
            proxyURL: "https://proxy.example.com",
            useDirectGemini: true
        )

        #expect(throws: GeminiError.self) {
            _ = try service.makeRequest(sessionToken: "unused")
        }
    }
    #endif
}
