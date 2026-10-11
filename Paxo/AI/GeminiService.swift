import Foundation

struct GenerationResult {
    let answerContext: AnswerContext
    let remainingToday: Int?
    let resetAt: Date?
    let text: String
    let tier: ProxyTier?
}

struct GeminiService {
    let apiKey: String
    let proxyURL: String
    let useDirectGemini: Bool
    var session: URLSession = GeminiService.defaultSession

    #if DEBUG
    private static let model = "gemini-3.6-flash"
    #endif

    private static let defaultSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 90
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    func answer(
        imageData: Data,
        preset: SubjectPreset,
        sessionToken: String,
        solveID: UUID
    ) async throws -> GenerationResult {
        try await generate(
            kind: .answer,
            prompt: Prompts.answer(preset: preset),
            imageData: imageData,
            sessionToken: sessionToken,
            solveID: solveID
        )
    }

    func explain(
        imageData: Data,
        answer: String,
        preset: SubjectPreset,
        sessionToken: String,
        solveID: UUID,
        answerContext: AnswerContext? = nil
    ) async throws -> GenerationResult {
        try await generate(
            kind: .explanation,
            prompt: Prompts.explanation(preset: preset, answer: answer, context: answerContext),
            imageData: imageData,
            sessionToken: sessionToken,
            solveID: solveID,
            expected: answerContext
        )
    }

    func makeRequest(sessionToken: String) throws -> URLRequest {
        #if DEBUG
        if useDirectGemini {
            return try makeDirectRequest()
        }
        let candidate = proxyURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let proxy = candidate.isEmpty ? DefaultConfig.developmentProxyURL : candidate
        #else
        let proxy = DefaultConfig.proxyURL
        #endif
        let base = proxy.hasSuffix("/") ? String(proxy.dropLast()) : proxy
        guard let url = URL(string: base + "/generate"), url.scheme == "https" else {
            throw GeminiError.badURL
        }
        var request = URLRequest(url: url)
        request.setValue(GenerationContract.format, forHTTPHeaderField: "x-paxo-response-format")
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        request.setValue(DefaultConfig.appToken, forHTTPHeaderField: "x-paxo-token")
        return request
    }

    #if DEBUG
    private func makeDirectRequest() throws -> URLRequest {
        guard !apiKey.isEmpty else { throw GeminiError.missingKey }
        guard
            let url = URL(
                string: "https://generativelanguage.googleapis.com/v1beta/models/\(Self.model):generateContent"
            )
        else { throw GeminiError.badURL }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        return request
    }
    #endif

    private func generate(
        kind: GenerationKind,
        prompt: String,
        imageData: Data,
        sessionToken: String,
        solveID: UUID,
        expected: AnswerContext? = nil
    ) async throws -> GenerationResult {
        var request = try makeRequest(sessionToken: sessionToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let expected {
            let context = try JSONEncoder().encode(expected)
            request.setValue(String(decoding: context, as: UTF8.self), forHTTPHeaderField: "x-paxo-answer-context")
        }
        var body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt],
                        [
                            "inline_data": [
                                "mime_type": "image/jpeg",
                                "data": imageData.base64EncodedString(),
                            ]
                        ],
                    ]
                ]
            ]
        ]
        #if DEBUG
        let isDirect = useDirectGemini
        let attempts = isDirect ? 2 : 1
        #else
        let isDirect = false
        let attempts = 1
        #endif
        if !isDirect {
            body["kind"] = kind.rawValue
            body["solveId"] = solveID.uuidString.lowercased()
        }
        // 프록시는 같은 예약 안에서 재생성한다. 앱이 중복 요청해 재차감하지 않는다.
        for attempt in 0..<attempts {
            #if DEBUG
            if isDirect { body["generationConfig"] = GenerationContract.configuration(for: kind, retry: attempt > 0) }
            #endif
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: request)
            } catch let error as URLError {
                throw Self.classify(error)
            }
            guard let http = response as? HTTPURLResponse else { throw GeminiError.http(-1, nil) }
            guard http.statusCode == 200 else {
                let code = Self.serverCode(from: data)
                switch (http.statusCode, code) {
                case (401, _): throw GeminiError.invalidSession
                case (429, "daily_limit"):
                    if http.value(forHTTPHeaderField: "x-paxo-tier") == ProxyTier.pro.rawValue {
                        throw GeminiError.proDailyLimit
                    }
                    throw GeminiError.freeDailyLimit
                case (429, _): throw GeminiError.rateLimited
                case (502, "incomplete_response"): throw GeminiError.incompleteResponse
                case (502, "invalid_response"): throw GeminiError.invalidResponse
                case (502, _), (503, _), (504, _): throw GeminiError.serviceUnavailable
                default: throw GeminiError.http(http.statusCode, Self.serverMessage(from: data))
                }
            }
            do {
                let generated = try GenerationContract.decode(data, kind: kind, expected: expected)
                return GenerationResult(
                    answerContext: generated.context,
                    remainingToday: http.value(forHTTPHeaderField: "x-paxo-remaining").flatMap(Int.init),
                    resetAt: Self.date(from: http.value(forHTTPHeaderField: "x-paxo-reset-at")),
                    text: generated.text,
                    tier: http.value(forHTTPHeaderField: "x-paxo-tier").flatMap(ProxyTier.init)
                )
            } catch let error as GeminiError {
                guard attempt + 1 < attempts else { throw error }
                switch error {
                case .incompleteResponse, .invalidResponse, .emptyResponse: continue
                default: throw error
                }
            }
        }
        throw GeminiError.invalidResponse
    }

    private static func serverCode(from data: Data) -> String? {
        errorEnvelope(from: data)?.error?.code
    }

    /// 사용자가 취소한 요청은 네트워크 오류가 아니다. 오류 화면으로 보내지 않도록 취소로 구분한다.
    static func classify(_ error: URLError) -> Error {
        error.code == .cancelled ? CancellationError() : GeminiError.network(error)
    }

    private static func serverMessage(from data: Data) -> String? {
        errorEnvelope(from: data)?.error?.message
    }

    private static func errorEnvelope(from data: Data) -> ErrorEnvelope? {
        try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
    }

    private static func date(from value: String?) -> Date? {
        guard let value else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

private struct ErrorEnvelope: Decodable {
    struct Inner: Decodable {
        let code: String?
        let message: String?
    }

    let error: Inner?
}

enum GeminiError: LocalizedError {
    case badURL
    case emptyResponse
    case freeDailyLimit
    case http(Int, String?)
    case invalidSession
    case incompleteResponse
    case invalidResponse
    case missingKey
    case network(URLError)
    case proDailyLimit
    case rateLimited
    case serviceUnavailable

    var errorDescription: String? {
        switch self {
        case .badURL:
            return "AI 연결 설정에 문제가 있습니다. 잠시 후 다시 시도해주세요."
        case .emptyResponse:
            return "AI 응답이 비어 있습니다. 다시 시도해주세요."
        case .freeDailyLimit:
            return "오늘 무료 풀이 3회를 모두 사용했습니다. Pro로 업그레이드하거나 내일 다시 이용해주세요."
        case .http(let code, let message):
            if let message, !message.isEmpty { return message }
            return "서버 오류가 발생했습니다. (HTTP \(code)) 잠시 후 다시 시도해주세요."
        case .incompleteResponse:
            return "AI 응답이 중간에 끊겼습니다. 다시 시도해주세요."
        case .invalidResponse:
            return "AI 답변의 형식이나 선택지 설명을 확인할 수 없습니다. 다시 시도해주세요."
        case .invalidSession:
            return "로그인 세션이 만료되었습니다. 다시 시도해주세요."
        case .missingKey:
            return "개발용 Gemini API 키가 설정되지 않았습니다."
        case .network(let error):
            switch error.code {
            case .notConnectedToInternet, .dataNotAllowed:
                return "인터넷에 연결되어 있지 않습니다. 네트워크 연결을 확인해주세요."
            case .timedOut:
                return "응답 시간이 초과되었습니다. 네트워크 상태를 확인하고 다시 시도해주세요."
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return "서버에 연결할 수 없습니다. 네트워크 연결을 확인해주세요."
            default:
                return "네트워크 오류가 발생했습니다. 다시 시도해주세요."
            }
        case .proDailyLimit:
            return "Pro의 일일 안전 한도 100회를 모두 사용했습니다. 내일 다시 이용해주세요."
        case .rateLimited:
            return "요청이 너무 많습니다. 잠시 후 다시 시도해주세요."
        case .serviceUnavailable:
            return "AI 서버를 일시적으로 사용할 수 없습니다. 잠시 후 다시 시도해주세요."
        }
    }
}
