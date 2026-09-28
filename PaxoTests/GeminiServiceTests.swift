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

    #if DEBUG
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
