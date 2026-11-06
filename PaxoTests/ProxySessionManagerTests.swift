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
        #expect(session.creditBalance == 100)
        #expect(session.appAccountToken?.uuidString == "00000000-0000-4000-8000-000000000001")
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

    @Test("강제 갱신은 캐시 대신 서버의 최신 사용량을 읽는다")
    func forceRefreshesCachedUsage() async throws {
        let trackingLoader = SequencedSessionLoader()
        let manager = ProxySessionManager(
            proofProvider: StubProof(value: nil),
            credentialStore: StubCredentialStore(value: "old-refresh-token"),
            loader: trackingLoader
        )

        let cached = try await manager.session()
        let refreshed = try await manager.session(forceRefresh: true)

        #expect(cached.remainingToday == 2)
        #expect(refreshed.remainingToday == 1)
        #expect(trackingLoader.callCount == 2)
    }

    @Test("초기화 직전까지 캐시를 쓰고 오전 6시부터 서버 사용량을 한 번만 갱신한다", arguments: [0.0, 1.0])
    func refreshesUsageAtResetBoundary(secondsAfterReset: TimeInterval) async throws {
        let resetAt = try #require(ISO8601DateFormatter().date(from: "2026-11-04T21:00:00Z"))
        var now = resetAt.addingTimeInterval(-1)
        var requestCount = 0
        let loader = StubLoader { request in
            requestCount += 1
            return try sessionResponse(
                request: request,
                remainingToday: requestCount == 1 ? 0 : 2,
                resetAt: requestCount == 1 ? "2026-11-04T21:00:00.000Z" : "2026-11-05T21:00:00.000Z"
            )
        }
        let manager = ProxySessionManager(
            proofProvider: StubProof(value: nil),
            credentialStore: StubCredentialStore(value: "old-refresh-token"),
            loader: loader,
            clock: { now }
        )

        _ = try await manager.session()
        now = resetAt.addingTimeInterval(-0.001)
        let beforeReset = try await manager.session()
        #expect(beforeReset.remainingToday == 0)
        #expect(loader.callCount == 1)

        now = resetAt.addingTimeInterval(secondsAfterReset)
        async let first = manager.session()
        async let second = manager.session()
        let refreshed = try await (first, second)

        #expect(refreshed.0.remainingToday == 2)
        #expect(refreshed.1.remainingToday == 2)
        #expect(refreshed.0.resetAt == resetAt.addingTimeInterval(24 * 60 * 60))
        #expect(loader.callCount == 2)
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

    @Test("구매 적립에 로그인 세션과 거래 증명을 전달하고 기존 잔액 캐시를 버린다")
    func redeemsPurchaseWithAuthenticatedProof() async throws {
        var purchaseCalls = 0
        let loader = StubLoader { request in
            if request.url?.path == "/purchases" {
                purchaseCalls += 1
                #expect(request.httpMethod == "POST")
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer opaque-token")
                #expect(request.value(forHTTPHeaderField: "x-paxo-token") != nil)
                let data = try #require(request.httpBody)
                let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: String])
                #expect(body == ["signedTransactionInfo": "header.payload.signature"])
                return try response(
                    request: request, status: 200,
                    body: #"{"creditBalance":130,"creditRevision":2,"storeEnvironment":"Production"}"#)
            }
            let data = try #require(request.httpBody)
            let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let proof = try #require(body["storeKitProof"] as? [String: String])
            #expect(proof == ["type": "transaction", "jws": "header.payload.signature"])
            return try sessionResponse(request: request)
        }
        let manager = ProxySessionManager(
            proofProvider: StubProof(value: nil),
            credentialStore: StubCredentialStore(value: "refresh-token"),
            loader: loader
        )

        let balance = try await manager.redeemPurchase(signedTransactionInfo: "header.payload.signature")

        #expect(balance == CreditBalance(creditBalance: 130, creditRevision: 2))
        #expect(purchaseCalls == 1)
        #expect(manager.sessionSnapshot == nil)
    }

    @Test("구매 적립 중 세션 만료는 한 번만 갱신해 같은 거래를 재전송한다")
    func retriesPurchaseAfterSessionExpiry() async throws {
        var purchaseCalls = 0
        var refreshCalls = 0
        let loader = StubLoader { request in
            if request.url?.path == "/purchases" {
                purchaseCalls += 1
                return try response(
                    request: request,
                    status: purchaseCalls == 1 ? 401 : 200,
                    body: purchaseCalls == 1
                        ? #"{"error":{"code":"invalid_session"}}"#
                        : #"{"creditBalance":30,"creditRevision":2,"storeEnvironment":"Production"}"#
                )
            }
            refreshCalls += 1
            return try sessionResponse(request: request)
        }
        let manager = ProxySessionManager(
            proofProvider: StubProof(value: nil),
            credentialStore: StubCredentialStore(value: "refresh-token"),
            loader: loader
        )

        let balance = try await manager.redeemPurchase(signedTransactionInfo: "header.payload.signature")

        #expect(balance == CreditBalance(creditBalance: 30, creditRevision: 2))
        #expect(purchaseCalls == 2)
        #expect(refreshCalls == 2)
    }

    @Test("다른 계정의 거래는 재시도하지 않고 거절한다")
    func rejectsPurchaseAccountMismatch() async {
        var purchaseCalls = 0
        let loader = StubLoader { request in
            if request.url?.path == "/purchases" {
                purchaseCalls += 1
                return try response(
                    request: request, status: 409, body: #"{"error":{"code":"purchase_account_mismatch"}}"#)
            }
            return try sessionResponse(request: request)
        }
        let manager = ProxySessionManager(
            proofProvider: StubProof(value: nil),
            credentialStore: StubCredentialStore(value: "refresh-token"),
            loader: loader
        )

        do {
            _ = try await manager.redeemPurchase(signedTransactionInfo: "header.payload.signature")
            Issue.record("다른 계정 거래가 승인됨")
        } catch ProxySessionError.storeKitAccountMismatch {
            #expect(purchaseCalls == 1)
        } catch {
            Issue.record("예상하지 않은 오류")
        }
    }

    @Test("로그아웃 뒤 늦게 도착한 세션 갱신은 토큰을 다시 저장하지 않는다")
    func doesNotRestoreCredentialsFromCancelledRefresh() async throws {
        let credentials = StubCredentialStore(value: "old-refresh-token")
        let loader = DeferredLoader(path: "/session/refresh")
        let manager = ProxySessionManager(
            proofProvider: StubProof(value: nil), credentialStore: credentials, loader: loader
        )
        let request = Task { try await manager.session() }
        await loader.waitForRequest()

        manager.clearCredentials()
        try loader.respondWithSession()

        await #expect(throws: ProxySessionError.self) { _ = try await request.value }
        #expect(credentials.value == nil)
        #expect(manager.sessionSnapshot == nil)
    }

    @Test("로그아웃 중 완료된 적립 응답은 이전 계정의 잔액으로 반환하지 않는다")
    func discardsPurchaseResponseAfterSignOut() async throws {
        let credentials = StubCredentialStore(value: "old-refresh-token")
        let loader = DeferredLoader(path: "/purchases")
        let manager = ProxySessionManager(
            proofProvider: StubProof(value: nil), credentialStore: credentials, loader: loader
        )
        let request = Task { try await manager.redeemPurchase(signedTransactionInfo: "signed-purchase") }
        await loader.waitForRequest()

        manager.clearCredentials()
        try loader.respond(body: #"{"creditBalance":130,"creditRevision":2,"storeEnvironment":"Production"}"#)

        await #expect(throws: ProxySessionError.self) { _ = try await request.value }
        #expect(credentials.value == nil)
        #expect(manager.sessionSnapshot == nil)
    }

    @Test("이전 계정의 갱신 실패 응답이 새 계정의 자격 증명을 지우지 않는다")
    func ignoresOldAuthenticationFailureAfterAccountSwitch() async throws {
        let credentials = StubCredentialStore(value: "old-refresh-token")
        let loader = DeferredLoader(path: "/session/refresh")
        let manager = ProxySessionManager(
            proofProvider: StubProof(value: nil), credentialStore: credentials, loader: loader
        )
        let request = Task { try await manager.session() }
        await loader.waitForRequest()

        manager.clearCredentials()
        credentials.saveRefreshToken("new-account-refresh-token")
        try loader.respond(status: 401, body: #"{"error":{"code":"invalid_refresh"}}"#)

        await #expect(throws: ProxySessionError.self) { _ = try await request.value }
        #expect(credentials.value == "new-account-refresh-token")
    }

    @Test("일반 갱신이 진행 중이어도 충전 거래 증명으로 환경을 다시 확인한다")
    func refreshesWithPurchaseProofAfterUnrelatedRefresh() async throws {
        let loader = DeferredLoader(path: "/session/refresh")
        let manager = ProxySessionManager(
            proofProvider: StubProof(value: nil),
            credentialStore: StubCredentialStore(value: "refresh-token"),
            loader: loader
        )
        let regular = Task { try await manager.session() }
        await loader.waitForRequest()
        let proof = StoreKitProof(jws: "signed-consumable", type: .transaction)
        let purchase = Task { try await manager.session(forceRefresh: true, storeKitProof: proof) }
        try loader.respondWithSession()
        _ = try await regular.value
        await loader.waitForRequest()
        let request = try #require(loader.lastRequest)
        let body = try #require(request.httpBody)
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let sentProof = try #require(object["storeKitProof"] as? [String: String])
        #expect(sentProof == ["type": "transaction", "jws": "signed-consumable"])
        try loader.respondWithSession()

        _ = try await purchase.value
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

private final class SequencedSessionLoader: HTTPDataLoading {
    private(set) var callCount = 0

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        callCount += 1
        return try sessionResponse(
            request: request,
            remainingToday: callCount == 1 ? 2 : 1
        )
    }
}

private func sessionResponse(
    request: URLRequest,
    remainingToday: Int = 2,
    resetAt: String = "2030-01-01T21:00:00.000Z"
) throws -> (Data, URLResponse) {
    try response(
        request: request,
        status: 200,
        body: """
            {
              "expiresAt":"2030-01-01T00:00:00.000Z",
              "refreshToken":"refresh-token",
              "remainingToday":\(remainingToday),
              "creditBalance":100,
              "creditRevision":1,
              "storeEnvironment":"Production",
              "appAccountToken":"00000000-0000-4000-8000-000000000001",
              "resetAt":"\(resetAt)",
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

@MainActor
private final class DeferredLoader: HTTPDataLoading {
    private let path: String
    private var request: URLRequest?
    var lastRequest: URLRequest? { request }
    private var responseContinuation: CheckedContinuation<(Data, URLResponse), Error>?
    private var requestContinuation: CheckedContinuation<Void, Never>?

    init(path: String) { self.path = path }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard request.url?.path == path else { return try sessionResponse(request: request) }
        self.request = request
        return try await withCheckedThrowingContinuation { continuation in
            responseContinuation = continuation
            requestContinuation?.resume()
            requestContinuation = nil
        }
    }

    func waitForRequest() async {
        guard responseContinuation == nil else { return }
        await withCheckedContinuation { requestContinuation = $0 }
    }

    func respondWithSession() throws {
        let request = try #require(request)
        let result = try sessionResponse(request: request)
        responseContinuation?.resume(returning: result)
        responseContinuation = nil
    }

    func respond(status: Int = 200, body: String) throws {
        let request = try #require(request)
        let result = try response(request: request, status: status, body: body)
        responseContinuation?.resume(returning: result)
        responseContinuation = nil
    }
}
