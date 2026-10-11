import Foundation
import Testing

/// 앱과 프록시의 회귀 테스트에서 같은 응답 사례를 사용한다.
enum GenerationFixtures {
    static func load() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("proxy-vercel/test/fixtures/case-question.json")
        return try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    static func envelope(_ payload: Any?, finishReason: String = "STOP", thoughts: Bool = false) throws -> Data {
        let payload = try #require(payload)
        let text: String
        if let raw = payload as? String {
            text = raw
        } else {
            text = String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self)
        }
        var parts: [[String: Any]] = []
        if thoughts { parts.append(["thought": true, "text": "생각 중"]) }
        parts.append(["text": text])
        return try JSONSerialization.data(withJSONObject: [
            "candidates": [["finishReason": finishReason, "content": ["parts": parts]]]
        ])
    }
}
