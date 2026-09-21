import Foundation
import Testing

@testable import Paxo

struct GeminiServiceTests {
    private let deviceID = "123E4567-E89B-12D3-A456-426614174000"

    @Test func 기본_요청은_프록시와_인증_헤더를_사용한다() throws {
        let service = GeminiService(
            apiKey: "development-key",
            proxyURL: "https://proxy.example.com/",
            deviceID: deviceID,
            useDirectGemini: false
        )

        let request = try service.makeRequest()

        #expect(request.url?.absoluteString == "https://proxy.example.com/generate")
        #expect(request.value(forHTTPHeaderField: "x-paxo-device") == deviceID)
        #expect(request.value(forHTTPHeaderField: "x-paxo-token") != nil)
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == nil)
    }

    #if DEBUG
    @Test func 직접_호출은_프록시를_우회하고_Gemini_키를_사용한다() throws {
        let service = GeminiService(
            apiKey: "development-key",
            proxyURL: "https://proxy.example.com",
            deviceID: deviceID,
            useDirectGemini: true
        )

        let request = try service.makeRequest()

        #expect(request.url?.host == "generativelanguage.googleapis.com")
        #expect(request.url?.path.contains("gemini-3.6-flash:generateContent") == true)
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "development-key")
        #expect(request.value(forHTTPHeaderField: "x-paxo-token") == nil)
    }

    @Test func 직접_호출은_키가_없으면_설정_오류를_반환한다() {
        let service = GeminiService(
            apiKey: "",
            proxyURL: "https://proxy.example.com",
            deviceID: deviceID,
            useDirectGemini: true
        )

        #expect(throws: GeminiError.self) {
            _ = try service.makeRequest()
        }
    }
    #endif
}
