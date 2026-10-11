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
}

private final class GenerationURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var responses: [Data] = []
    private static var capturedRequests: [URLRequest] = []

    static var requests: [URLRequest] { lock.withLock { capturedRequests } }

    static func session(responses: [Data]) -> URLSession {
        lock.withLock {
            self.responses = responses
            capturedRequests = []
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GenerationURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let data = Self.lock.withLock {
            Self.capturedRequests.append(request)
            return Self.responses.isEmpty ? Data() : Self.responses.removeFirst()
        }
        guard let url = request.url,
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
