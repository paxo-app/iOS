import CryptoKit
import Foundation
import StoreKit

enum ProxyTier: String, Codable {
    case free
    case pro

    var dailyLimit: Int {
        switch self {
        case .free: UsagePolicy.dailyFreeLimit
        case .pro: UsagePolicy.dailyProLimit
        }
    }
}

struct CreditBalance: Decodable, Equatable {
    let creditBalance: Int
    let creditRevision: Int
    let storeEnvironment: String

    init(creditBalance: Int, creditRevision: Int = 0, storeEnvironment: String = "Production") {
        self.creditBalance = max(0, creditBalance)
        self.creditRevision = max(0, creditRevision)
        self.storeEnvironment = storeEnvironment
    }
}

struct ProxySession: Decodable {
    let expiresAt: Date
    let creditBalance: Int
    let creditRevision: Int
    let storeEnvironment: String
    let appAccountToken: UUID?
    let refreshToken: String
    let remainingToday: Int
    let resetAt: Date
    let sessionToken: String
    let tier: ProxyTier

    private enum CodingKeys: String, CodingKey {
        case expiresAt, creditBalance, creditRevision, storeEnvironment, appAccountToken, refreshToken, remainingToday,
            resetAt,
            sessionToken, tier
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        expiresAt = try container.decode(Date.self, forKey: .expiresAt)
        creditBalance = max(0, try container.decodeIfPresent(Int.self, forKey: .creditBalance) ?? 0)
        creditRevision = max(0, try container.decodeIfPresent(Int.self, forKey: .creditRevision) ?? 0)
        storeEnvironment = try container.decodeIfPresent(String.self, forKey: .storeEnvironment) ?? "Production"
        appAccountToken = try container.decodeIfPresent(UUID.self, forKey: .appAccountToken)
        refreshToken = try container.decode(String.self, forKey: .refreshToken)
        remainingToday = try container.decode(Int.self, forKey: .remainingToday)
        resetAt = try container.decode(Date.self, forKey: .resetAt)
        sessionToken = try container.decode(String.self, forKey: .sessionToken)
        tier = try container.decode(ProxyTier.self, forKey: .tier)
    }
}

struct StoreKitProof: Codable, Equatable {
    enum Kind: String, Codable {
        case appTransaction
        case transaction
    }

    let jws: String
    let type: Kind
}

protocol StoreKitProofProviding {
    func proof() async -> StoreKitProof?
}

protocol HTTPDataLoading {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPDataLoading {}

protocol ProxyCredentialStoring {
    func loadRefreshToken() -> String?
    func saveRefreshToken(_ value: String)
}

struct KeychainProxyCredentialStore: ProxyCredentialStoring {
    private let key = "proxy-refresh-token"

    func loadRefreshToken() -> String? {
        KeychainHelper.load(key: key)
    }

    func saveRefreshToken(_ value: String) {
        KeychainHelper.save(key: key, value: value)
    }
}

struct StoreKitProofProvider: StoreKitProofProviding {
    func proof() async -> StoreKitProof? {
        // 구독 계정과 앱 다운로드 계정이 다를 수 있어 현재 구독 거래를 먼저 증명한다.
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement,
                StoreProducts.legacySubscriptionIdentifiers.contains(transaction.productID),
                transaction.revocationDate == nil
            else { continue }
            return StoreKitProof(jws: entitlement.jwsRepresentation, type: .transaction)
        }
        if let result = try? await AppTransaction.shared,
            case .verified = result
        {
            return StoreKitProof(jws: result.jwsRepresentation, type: .appTransaction)
        }
        return nil
    }
}

@MainActor
final class ProxySessionManager {
    private let clock: () -> Date
    private let credentialStore: ProxyCredentialStoring
    private let loader: HTTPDataLoading
    private let proofProvider: StoreKitProofProviding
    private var cachedSession: ProxySession?
    private var refreshTask: Task<ProxySession, Error>?
    private var credentialEpoch = 0
    private var refreshIdentifier: UUID?
    private var refreshProof: StoreKitProof?
    private(set) var pendingNonce: String?

    #if DEBUG
    var developmentProxyURL = ""
    #endif

    init(
        proofProvider: StoreKitProofProviding = StoreKitProofProvider(),
        credentialStore: ProxyCredentialStoring = KeychainProxyCredentialStore(),
        loader: HTTPDataLoading = URLSession.shared,
        clock: @escaping () -> Date = Date.init
    ) {
        self.proofProvider = proofProvider
        self.credentialStore = credentialStore
        self.loader = loader
        self.clock = clock
    }

    var sessionSnapshot: ProxySession? { cachedSession }

    static func nonceDigest(_ nonce: String) -> String {
        SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func prepareChallenge() async throws -> String {
        let epoch = credentialEpoch
        var request = try makeRequest(path: "/session/challenge")
        request.httpMethod = "POST"
        request.setValue(DefaultConfig.appToken, forHTTPHeaderField: "x-paxo-token")
        let (data, response) = try await load(request)
        try requireCurrentCredentials(epoch)
        try requireStatus(response, data: data, expected: 200)
        let challenge = try decode(ChallengeResponse.self, from: data)
        guard !challenge.nonce.isEmpty else { throw ProxySessionError.invalidResponse }
        try requireCurrentCredentials(epoch)
        pendingNonce = challenge.nonce
        return challenge.nonce
    }

    func signIn(identityToken: String, authorizationCode: String) async throws -> ProxySession {
        let epoch = credentialEpoch
        guard let nonce = pendingNonce else { throw ProxySessionError.challengeRequired }
        pendingNonce = nil
        let body = SignInRequest(
            proof: .init(
                authorizationCode: authorizationCode,
                identityToken: identityToken,
                nonce: nonce
            ),
            storeKitProof: await proofProvider.proof()
        )
        let session = try await sendSessionRequest(path: "/session", body: body, epoch: epoch)
        try requireCurrentCredentials(epoch)
        remember(session)
        return session
    }

    func session(forceRefresh: Bool = false, storeKitProof: StoreKitProof? = nil) async throws -> ProxySession {
        let epoch = credentialEpoch
        let now = clock()
        if !forceRefresh, storeKitProof == nil,
            let cachedSession,
            cachedSession.expiresAt.timeIntervalSince(now) > 15,
            cachedSession.resetAt > now
        {
            return cachedSession
        }
        if let refreshTask {
            let identifier = refreshIdentifier
            let matchesProof = storeKitProof == nil || storeKitProof == refreshProof
            let session = try await refreshTask.value
            try requireCurrentCredentials(epoch)
            if matchesProof { return session }
            if refreshIdentifier == identifier {
                self.refreshTask = nil
                refreshIdentifier = nil
                refreshProof = nil
            }
            return try await self.session(forceRefresh: true, storeKitProof: storeKitProof)
        }
        let identifier = UUID()
        let task = Task { @MainActor in
            guard let refreshToken = credentialStore.loadRefreshToken(),
                !refreshToken.isEmpty
            else {
                throw ProxySessionError.signInRequired
            }
            let proof: StoreKitProof?
            if let storeKitProof { proof = storeKitProof } else { proof = await proofProvider.proof() }
            let body = RefreshRequest(refreshToken: refreshToken, storeKitProof: proof)
            let session = try await sendSessionRequest(path: "/session/refresh", body: body, epoch: epoch)
            try requireCurrentCredentials(epoch)
            remember(session)
            return session
        }
        refreshTask = task
        refreshIdentifier = identifier
        refreshProof = storeKitProof
        defer {
            if refreshIdentifier == identifier {
                refreshTask = nil
                refreshIdentifier = nil
                refreshProof = nil
            }
        }
        let session = try await task.value
        try requireCurrentCredentials(epoch)
        return session
    }

    func withSessionRetry<T>(
        storeKitProof: StoreKitProof? = nil,
        _ operation: (ProxySession) async throws -> T
    ) async throws -> T {
        let epoch = credentialEpoch
        let current = try await session(forceRefresh: storeKitProof != nil, storeKitProof: storeKitProof)
        do {
            let value = try await operation(current)
            try requireCurrentCredentials(epoch)
            return value
        } catch GeminiError.invalidSession {
            try requireCurrentCredentials(epoch)
            cachedSession = nil
            let refreshed = try await session(forceRefresh: true, storeKitProof: storeKitProof)
            let value = try await operation(refreshed)
            try requireCurrentCredentials(epoch)
            return value
        }
    }

    func redeemPurchase(signedTransactionInfo: String) async throws -> CreditBalance {
        let epoch = credentialEpoch
        let proof = StoreKitProof(jws: signedTransactionInfo, type: .transaction)
        let balance = try await withSessionRetry(storeKitProof: proof) { session in
            try requireCurrentCredentials(epoch)
            var request = try makeRequest(path: "/purchases")
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(DefaultConfig.appToken, forHTTPHeaderField: "x-paxo-token")
            request.setValue("Bearer \(session.sessionToken)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONEncoder().encode(PurchaseRequest(signedTransactionInfo: signedTransactionInfo))
            let (data, response) = try await load(request)
            try requireCurrentCredentials(epoch)
            if let http = response as? HTTPURLResponse,
                http.statusCode == 401, Self.errorCode(from: data) == "invalid_session"
            {
                throw GeminiError.invalidSession
            }
            try requireStatus(response, data: data, expected: 200)
            return try decode(CreditBalance.self, from: data)
        }
        try requireCurrentCredentials(epoch)
        // 다음 풀이 사전 검증이 충전 전 잔량을 재사용하지 않도록 한다.
        cachedSession = nil
        return balance
    }

    func logout() async {
        let refreshToken = credentialStore.loadRefreshToken()
        let sessionToken = cachedSession?.sessionToken
        clearCredentials()
        guard let refreshToken, var request = try? makeRequest(path: "/session/logout") else { return }
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let sessionToken {
            request.setValue(
                "Bearer \(sessionToken)",
                forHTTPHeaderField: "Authorization"
            )
        }
        request.setValue(DefaultConfig.appToken, forHTTPHeaderField: "x-paxo-token")
        request.httpBody = try? JSONEncoder().encode(LogoutRequest(refreshToken: refreshToken))
        _ = try? await loader.data(for: request)
    }

    func deleteAccount() async throws {
        let session = try await session()
        var request = try makeRequest(path: "/account")
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(session.sessionToken)", forHTTPHeaderField: "Authorization")
        request.setValue(DefaultConfig.appToken, forHTTPHeaderField: "x-paxo-token")
        let (data, response) = try await load(request)
        try requireStatus(response, data: data, expected: 204)
        clearCredentials()
    }

    func clearCredentials() {
        credentialEpoch &+= 1
        refreshTask?.cancel()
        refreshTask = nil
        refreshIdentifier = nil
        refreshProof = nil
        cachedSession = nil
        pendingNonce = nil
        credentialStore.saveRefreshToken("")
    }

    private func requireCurrentCredentials(_ epoch: Int) throws {
        guard epoch == credentialEpoch else { throw ProxySessionError.signInRequired }
    }

    private func remember(_ session: ProxySession) {
        cachedSession = session
        credentialStore.saveRefreshToken(session.refreshToken)
    }

    private func sendSessionRequest<Body: Encodable>(path: String, body: Body, epoch: Int) async throws -> ProxySession
    {
        try requireCurrentCredentials(epoch)
        var request = try makeRequest(path: path)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(DefaultConfig.appToken, forHTTPHeaderField: "x-paxo-token")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await load(request)
        try requireCurrentCredentials(epoch)
        try requireStatus(response, data: data, expected: 200)
        return try decode(ProxySession.self, from: data)
    }

    private func load(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await loader.data(for: request)
        } catch let error as URLError {
            throw ProxySessionError.network(error)
        } catch let error as ProxySessionError {
            throw error
        } catch {
            throw ProxySessionError.serviceUnavailable
        }
    }

    private func requireStatus(_ response: URLResponse, data: Data, expected: Int) throws {
        guard let http = response as? HTTPURLResponse else { throw ProxySessionError.invalidResponse }
        guard http.statusCode == expected else {
            let code = Self.errorCode(from: data)
            switch (http.statusCode, code) {
            case (401, "invalid_refresh"), (401, "apple_credential_revoked"):
                clearCredentials()
                throw ProxySessionError.signInRequired
            case (401, "invalid_challenge"):
                throw ProxySessionError.challengeRequired
            case (401, _):
                throw ProxySessionError.appleVerificationFailed
            case (409, "purchase_revoked"):
                throw ProxySessionError.purchaseRevoked
            case (409, "storekit_environment_mismatch"):
                throw ProxySessionError.storeKitEnvironmentMismatch
            case (409, "storekit_account_mismatch"), (409, "purchase_account_mismatch"):
                throw ProxySessionError.storeKitAccountMismatch
            case (503, _):
                throw ProxySessionError.serviceUnavailable
            default:
                throw ProxySessionError.invalidResponse
            }
        }
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let withFraction = ISO8601DateFormatter()
            withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let withoutFraction = ISO8601DateFormatter()
            guard let date = withFraction.date(from: value) ?? withoutFraction.date(from: value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid date"
                )
            }
            return date
        }
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw ProxySessionError.invalidResponse
        }
    }

    private func makeRequest(path: String) throws -> URLRequest {
        #if DEBUG
        let candidate = developmentProxyURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURL = candidate.isEmpty ? DefaultConfig.developmentProxyURL : candidate
        #else
        let baseURL = DefaultConfig.proxyURL
        #endif
        let normalized = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        guard let url = URL(string: normalized + path), url.scheme == "https" else {
            throw ProxySessionError.invalidURL
        }
        return URLRequest(url: url)
    }

    private static func errorCode(from data: Data) -> String? {
        struct ErrorEnvelope: Decodable {
            struct Inner: Decodable { let code: String? }
            let error: Inner?
        }
        return (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.error?.code
    }
}

private struct ChallengeResponse: Decodable {
    let nonce: String
}

private struct SignInRequest: Encodable {
    struct Proof: Encodable {
        let type = "appleIdentity"
        let authorizationCode: String
        let identityToken: String
        let nonce: String
    }

    let proof: Proof
    let storeKitProof: StoreKitProof?
}

private struct RefreshRequest: Encodable {
    let refreshToken: String
    let storeKitProof: StoreKitProof?
}

private struct PurchaseRequest: Encodable {
    let signedTransactionInfo: String
}

private struct LogoutRequest: Encodable {
    let refreshToken: String
}

enum ProxySessionError: LocalizedError {
    case appleVerificationFailed
    case challengeRequired
    case invalidResponse
    case invalidURL
    case network(URLError)
    case purchaseRevoked
    case serviceUnavailable
    case signInRequired
    case storeKitAccountMismatch
    case storeKitEnvironmentMismatch

    var errorDescription: String? {
        switch self {
        case .appleVerificationFailed:
            return "Apple 로그인을 확인하지 못했습니다. 다시 로그인해주세요."
        case .challengeRequired:
            return "로그인 준비 시간이 만료되었습니다. 잠시 후 다시 시도해주세요."
        case .invalidResponse, .serviceUnavailable:
            return "사용 권한을 확인할 수 없습니다. 네트워크 상태를 확인하고 잠시 후 다시 시도해주세요."
        case .invalidURL:
            return "서버 연결 설정에 문제가 있습니다."
        case .network(let error):
            switch error.code {
            case .notConnectedToInternet, .dataNotAllowed:
                return "인터넷에 연결되어 있지 않습니다. 네트워크 연결을 확인해주세요."
            case .timedOut:
                return "사용 권한 확인 시간이 초과되었습니다. 잠시 후 다시 시도해주세요."
            default:
                return "사용 권한을 확인하지 못했습니다. 네트워크 상태를 확인하고 다시 시도해주세요."
            }
        case .signInRequired:
            return "Paxo를 사용하려면 Apple로 로그인해주세요."
        case .purchaseRevoked:
            return "환불되었거나 취소된 구매여서 풀이권을 적립할 수 없습니다."
        case .storeKitAccountMismatch:
            return "이 App Store 구매는 다른 Paxo 계정에 연결되어 있습니다."
        case .storeKitEnvironmentMismatch:
            return "구매 환경을 확인하지 못했습니다. 잔액을 새로고침한 뒤 다시 시도해주세요."
        }
    }
}
