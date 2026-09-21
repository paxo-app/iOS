import Foundation

/// AI 호출 서비스.
///
/// 릴리즈 빌드는 항상 프록시(api.paxo.co.kr) 경유로 호출한다 — 앱에 Gemini 키를 두지 않는다.
/// 개발(DEBUG) 빌드에서만 명시적으로 직접 호출을 선택하면 Gemini API를 호출할 수 있다.
struct GeminiService {
    let apiKey: String
    let proxyURL: String
    let deviceID: String
    let useDirectGemini: Bool

    #if DEBUG
    private static let model = "gemini-3.6-flash"
    #endif

    /// 타임아웃을 설정한 공용 세션 (요청 30s / 리소스 90s)
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 90
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    func answer(imageData: Data, preset: SubjectPreset) async throws -> String {
        try await generate(prompt: Prompts.answer(preset: preset), imageData: imageData)
    }

    func explain(imageData: Data, answer: String, preset: SubjectPreset) async throws -> String {
        try await generate(prompt: Prompts.explanation(preset: preset, answer: answer), imageData: imageData)
    }

    /// 우선순위: 사용자가 설정한 프록시 → 내장 기본 프록시
    private var effectiveProxyURL: String {
        let user = proxyURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return user.isEmpty ? DefaultConfig.proxyURL : user
    }

    func makeRequest() throws -> URLRequest {
        #if DEBUG
        if useDirectGemini {
            return try makeDirectRequest()
        }
        #endif

        let proxy = effectiveProxyURL
        let base = proxy.hasSuffix("/") ? String(proxy.dropLast()) : proxy
        guard let url = URL(string: base + "/generate") else {
            throw GeminiError.badURL
        }
        var request = URLRequest(url: url)
        request.setValue(deviceID, forHTTPHeaderField: "x-paxo-device")
        request.setValue(DefaultConfig.appToken, forHTTPHeaderField: "x-paxo-token")
        return request
    }

    #if DEBUG
    private func makeDirectRequest() throws -> URLRequest {
        guard !apiKey.isEmpty else {
            throw GeminiError.missingKey
        }
        guard
            let url = URL(
                string: "https://generativelanguage.googleapis.com/v1beta/models/\(Self.model):generateContent"
            )
        else {
            throw GeminiError.badURL
        }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        return request
    }
    #endif

    private func generate(prompt: String, imageData: Data) async throws -> String {
        var request = try makeRequest()
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
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
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await Self.session.data(for: request)
        } catch let error as URLError {
            throw GeminiError.network(error)
        }

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            if code == 429 {
                throw GeminiError.rateLimited
            }
            throw GeminiError.http(code, Self.serverMessage(from: data))
        }

        let decoded = try JSONDecoder().decode(GenerateContentResponse.self, from: data)
        let text =
            decoded.candidates?
            .first?
            .content?
            .parts?
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !text.isEmpty else {
            throw GeminiError.emptyResponse
        }
        return text
    }

    private static func serverMessage(from data: Data) -> String? {
        struct ErrorEnvelope: Decodable {
            struct Inner: Decodable { let message: String? }
            let error: Inner?
        }
        return (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.error?.message
    }
}

private struct GenerateContentResponse: Decodable {
    struct Candidate: Decodable { let content: Content? }
    struct Content: Decodable { let parts: [Part]? }
    struct Part: Decodable { let text: String? }
    let candidates: [Candidate]?
}

enum GeminiError: LocalizedError {
    case missingKey
    case badURL
    case http(Int, String?)
    case rateLimited
    case emptyResponse
    case network(URLError)

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "AI 연결이 설정되지 않았습니다. 설정에서 프록시 URL 또는 API 키를 입력해주세요."
        case .badURL:
            return "AI 연결 설정에 문제가 있습니다. 잠시 후 다시 시도해주세요."
        case .http(let code, let message):
            if let message, !message.isEmpty {
                return message
            }
            return "서버 오류가 발생했습니다. (HTTP \(code)) 잠시 후 다시 시도해주세요."
        case .rateLimited:
            return "오늘 사용량을 다 썼거나 요청이 너무 많습니다. 잠시 후 다시 시도해주세요."
        case .emptyResponse:
            return "AI 응답이 비어 있습니다. 다시 시도해주세요."
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
        }
    }
}
