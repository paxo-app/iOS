import Foundation
import Testing

@testable import Paxo

/// 네트워크를 대체해 실제 서비스의 재생성과 중복 요청 방지 경로를 검증한다.
@Suite(.serialized)
struct GenerationTransportTests {
    #if DEBUG
    @Test func directCallRetriesTruncatedOutputOnce() async throws {
        let payload = try #require(GenerationFixtures.load()["answer"])
        let session = GenerationURLProtocol.session(responses: [
            try GenerationFixtures.envelope(payload, finishReason: "MAX_TOKENS"),
            try GenerationFixtures.envelope(payload),
        ])
        defer { session.invalidateAndCancel() }
        let service = GeminiService(apiKey: "test-key", proxyURL: "", useDirectGemini: true, session: session)
        let result = try await service.answer(
            imageData: Data([0xff, 0xd8, 0xff]), preset: .general, sessionToken: "unused", solveID: UUID()
        )
        #expect(result.text == "③")
        #expect(GenerationURLProtocol.requests.count == 2)
    }
    #endif

    @Test func proxyCallDoesNotRetryAnAlreadyReservedSolve() async throws {
        let payload = try #require(GenerationFixtures.load()["answer"])
        let session = GenerationURLProtocol.session(responses: [
            try GenerationFixtures.envelope(payload, finishReason: "MAX_TOKENS"),
            try GenerationFixtures.envelope(payload),
        ])
        defer { session.invalidateAndCancel() }
        let service = GeminiService(
            apiKey: "", proxyURL: "https://proxy.example.com", useDirectGemini: false, session: session)
        await #expect(throws: GeminiError.self) {
            try await service.answer(
                imageData: Data([0xff, 0xd8, 0xff]), preset: .general, sessionToken: "test-session", solveID: UUID()
            )
        }
        #expect(GenerationURLProtocol.requests.count == 1)
    }

    @Test func sendsExpectedChoicesAndRendersStructuredExplanation() async throws {
        let payload = try #require(GenerationFixtures.load()["explanation"])
        let session = GenerationURLProtocol.session(responses: [try GenerationFixtures.envelope(payload)])
        defer { session.invalidateAndCancel() }
        let context = AnswerContext(questionType: .multipleChoice, choices: [1, 2, 3, 4], selectedChoices: [3])
        let service = GeminiService(
            apiKey: "", proxyURL: "https://proxy.example.com", useDirectGemini: false, session: session)
        let result = try await service.explain(
            imageData: Data([0xff, 0xd8, 0xff]), answer: "③", preset: .general,
            sessionToken: "test-session", solveID: UUID(), answerContext: context
        )
        let request = try #require(GenerationURLProtocol.requests.first)
        let header = try #require(request.value(forHTTPHeaderField: "x-paxo-answer-context"))
        #expect(try JSONDecoder().decode(AnswerContext.self, from: Data(header.utf8)) == context)
        #expect(request.value(forHTTPHeaderField: "x-paxo-response-format") == "structured-v1")
        #expect(result.text.contains("- ①:"))
        #expect(result.text.contains("- ②:"))
        #expect(result.text.contains("- ④:"))
    }

    @Test func paidBalanceRemainsSeparateFromDailyFreeAllowance() async throws {
        let payload = try #require(GenerationFixtures.load()["answer"])
        let session = GenerationURLProtocol.session(
            responses: [try GenerationFixtures.envelope(payload)],
            headers: [
                "x-paxo-remaining": "0", "x-paxo-credit-balance": "499", "x-paxo-credit-revision": "8",
                "x-paxo-tier": "free", "x-paxo-store-environment": "Production",
            ]
        )
        defer { session.invalidateAndCancel() }
        let service = GeminiService(
            apiKey: "", proxyURL: "https://proxy.example.com", useDirectGemini: false, session: session)
        let result = try await service.answer(
            imageData: Data([0xff, 0xd8, 0xff]), preset: .general, sessionToken: "test-session", solveID: UUID()
        )
        #expect(result.remainingToday == 0)
        #expect(result.creditBalance == 499)
        #expect(result.creditRevision == 8)
        #expect(result.storeEnvironment == "Production")
        #expect(result.tier == .free)
    }

    @Test func exhaustedCreditsOpenRechargePathInsteadOfRateLimitError() async throws {
        let session = GenerationURLProtocol.session(
            responses: [Data(#"{"error":{"code":"daily_limit"}}"#.utf8)], statusCode: 429
        )
        defer { session.invalidateAndCancel() }
        let service = GeminiService(
            apiKey: "", proxyURL: "https://proxy.example.com", useDirectGemini: false, session: session)
        do {
            _ = try await service.answer(
                imageData: Data([0xff, 0xd8, 0xff]), preset: .general, sessionToken: "test-session", solveID: UUID()
            )
            Issue.record("풀이권 소진 오류가 필요합니다.")
        } catch GeminiError.creditsExhausted {
            #expect(GenerationURLProtocol.requests.count == 1)
        }
    }
}

private final class GenerationURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var responses: [Data] = []
    private static var capturedRequests: [URLRequest] = []
    private static var responseHeaders: [String: String] = [:]
    private static var responseStatus = 200

    static var requests: [URLRequest] { lock.withLock { capturedRequests } }

    static func session(responses: [Data], headers: [String: String] = [:], statusCode: Int = 200) -> URLSession {
        lock.withLock {
            self.responses = responses
            capturedRequests = []
            responseHeaders = headers
            responseStatus = statusCode
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GenerationURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (data, status, headers) = Self.lock.withLock {
            Self.capturedRequests.append(request)
            let data = Self.responses.isEmpty ? Data() : Self.responses.removeFirst()
            return (data, Self.responseStatus, Self.responseHeaders)
        }
        guard let url = request.url,
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)
        else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
