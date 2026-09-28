import Foundation
import Testing

@testable import Paxo

@MainActor
struct ProxySessionManagerTests {
    @Test("Apple 로그인 증명을 서버 세션으로 교환한다")
    func exchangesAppleIdentityForSession() async throws {
        let credentials = StubCredentialStore()
        let loader = StubLoader { request in
            if request.url?.path == "/session/challenge" {
                return try response(request: request, status: 200, body: #"{"nonce":"raw-nonce"}"#)
            }
            #expect(request.url?.absoluteString == "https://preview-api.paxo.co.kr/session")
            #expect(request.value(forHTTPHeaderField: "x-paxo-token") != nil)
            let requestBody = try #require(request.httpBody)
            let decoded = try JSONSerialization.jsonObject(with: requestBody)
            let object = try #require(decoded as? [String: Any])
            let proof = try #require(object["proof"] as? [String: Any])
            #expect(proof["type"] as? String == "appleIdentity")
            #expect(proof["identityToken"] as? String == "identity-token")
            #expect(proof["authorizationCode"] as? String == "authorization-code")
            #expect(proof["nonce"] as? String == "raw-nonce")
            let storeKitProof = try #require(object["storeKitProof"] as? [String: Any])
            #expect(storeKitProof["type"] as? String == "appTransaction")
            #expect(storeKitProof["jws"] as? String == "header.payload.signature")
            return try sessionResponse(request: request)
        }
        let manager = ProxySessionManager(
            proofProvider: StubProof(
                value: StoreKitProof(jws: "header.payload.signature", type: .appTransaction)
            ),
            credentialStore: credentials,
            loader: loader
        )

        _ = try await manager.prepareChallenge()
        let session = try await manager.signIn(
            identityToken: "identity-token",
            authorizationCode: "authorization-code"
        )

        #expect(session.sessionToken == "opaque-token")
        #expect(session.remainingToday == 2)
        #expect(credentials.value == "refresh-token")
        #expect(loader.callCount == 2)
    }

    @Test("저장된 갱신 토큰으로 세션을 복구하고 메모리에서 재사용한다")
    func restoresAndCachesSession() async throws {
        let credentials = StubCredentialStore(value: "old-refresh-token")
        let loader = StubLoader { request in
            #expect(request.url?.path == "/session/refresh")
            return try sessionResponse(request: request)
        }
        let manager = ProxySessionManager(
            proofProvider: StubProof(value: nil),
            credentialStore: credentials,
            loader: loader,
            clock: { Date(timeIntervalSince1970: 1_758_510_000) }
        )

        _ = try await manager.session()
        _ = try await manager.session()

        #expect(loader.callCount == 1)
        #expect(credentials.value == "refresh-token")
    }

    @Test("갱신 토큰이 없으면 네트워크 요청 전에 로그인을 요구한다")
    func requiresSignInBeforeNetworkRequest() async {
        let loader = StubLoader { request in
            try sessionResponse(request: request)
        }
        let manager = ProxySessionManager(
            proofProvider: StubProof(value: nil),
            credentialStore: StubCredentialStore(),
            loader: loader
        )

        await #expect(throws: ProxySessionError.self) {
            _ = try await manager.session()
        }
        #expect(loader.callCount == 0)
    }

    @Test("동시에 요청한 세션 갱신은 한 번의 네트워크 호출을 공유한다")
    func coalescesConcurrentRefreshes() async throws {
        let loader = StubLoader { request in
            try sessionResponse(request: request)
        }
        let manager = ProxySessionManager(
            proofProvider: StubProof(value: nil),
            credentialStore: StubCredentialStore(value: "old-refresh-token"),
            loader: loader
        )

        async let first = manager.session(forceRefresh: true)
        async let second = manager.session(forceRefresh: true)
        _ = try await (first, second)

        #expect(loader.callCount == 1)
    }

    @Test("401은 세션을 한 번 갱신한 뒤 요청을 한 번만 재시도한다")
    func retriesOnceAfterExpiredSession() async throws {
        let loader = StubLoader { request in
            try sessionResponse(request: request)
        }
        let manager = ProxySessionManager(
            proofProvider: StubProof(value: nil),
            credentialStore: StubCredentialStore(value: "old-refresh-token"),
            loader: loader,
            clock: { Date(timeIntervalSince1970: 1_758_510_000) }
        )
        var operationCount = 0

        let token = try await manager.withSessionRetry { session in
            operationCount += 1
            if operationCount == 1 { throw GeminiError.invalidSession }
            return session.sessionToken
        }

        #expect(operationCount == 2)
        #expect(loader.callCount == 2)
        #expect(token == "opaque-token")
    }
}

private struct StubProof: StoreKitProofProviding {
    let value: StoreKitProof?

    func proof() async -> StoreKitProof? { value }
}

private final class StubCredentialStore: ProxyCredentialStoring {
    var value: String?

    init(value: String? = nil) {
        self.value = value
    }

    func loadRefreshToken() -> String? { value }
    func saveRefreshToken(_ value: String) { self.value = value.isEmpty ? nil : value }
}

private final class StubLoader: HTTPDataLoading {
    private let handler: (URLRequest) throws -> (Data, URLResponse)
    private(set) var callCount = 0

    init(handler: @escaping (URLRequest) throws -> (Data, URLResponse)) {
        self.handler = handler
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        callCount += 1
        return try handler(request)
    }
}

private func sessionResponse(request: URLRequest) throws -> (Data, URLResponse) {
    try response(
        request: request,
        status: 200,
        body: """
            {
              "expiresAt":"2030-01-01T00:00:00.000Z",
              "refreshToken":"refresh-token",
              "remainingToday":2,
              "resetAt":"2030-01-01T15:00:00.000Z",
              "sessionToken":"opaque-token",
              "tier":"free"
            }
            """
    )
}

private func response(request: URLRequest, status: Int, body: String) throws -> (Data, URLResponse) {
    let url = try #require(request.url)
    let value = try #require(
        HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)
    )
    return (Data(body.utf8), value)
}
