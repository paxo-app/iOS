import Foundation

enum GenerationKind: String {
    case answer
    case explanation
}

/// 선택지의 진위와 문제에서 요구한 정답 여부를 분리해 검증한다.
struct AnswerContext: Codable, Equatable {
    enum QuestionType: String, Codable {
        case multipleChoice
        case shortAnswer
    }

    let questionType: QuestionType
    let choices: [Int]
    let selectedChoices: [Int]

    var isValid: Bool {
        switch questionType {
        case .multipleChoice:
            return choices.count >= 2 && choices.count <= 20
                && Set(choices).count == choices.count && choices.allSatisfy { (1...20).contains($0) }
                && !selectedChoices.isEmpty && Set(selectedChoices).count == selectedChoices.count
                && Set(selectedChoices).isSubset(of: Set(choices))
        case .shortAnswer:
            return choices.isEmpty && selectedChoices.isEmpty
        }
    }
}

struct GeneratedAnswer: Decodable {
    let questionType: AnswerContext.QuestionType
    let choices: [Int]
    let selectedChoices: [Int]
    let answer: String

    var context: AnswerContext {
        AnswerContext(questionType: questionType, choices: choices, selectedChoices: selectedChoices)
    }

    var displayText: String {
        questionType == .multipleChoice
            ? selectedChoices.sorted().map(GenerationContract.choiceMarker).joined(separator: ", ")
            : answer.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isValid: Bool {
        context.isValid && (questionType == .multipleChoice ? answer.isEmpty : !displayText.isEmpty)
    }
}

struct GeneratedExplanation: Decodable {
    struct ChoiceReason: Decodable {
        let choice: Int
        let reason: String
    }

    let questionType: AnswerContext.QuestionType
    let choices: [Int]
    let selectedChoices: [Int]
    let coreExplanation: String
    let wrongChoiceReasons: [ChoiceReason]
    let recommendedLearning: String

    var context: AnswerContext {
        AnswerContext(questionType: questionType, choices: choices, selectedChoices: selectedChoices)
    }

    func isValid(expected: AnswerContext?) -> Bool {
        guard context.isValid, !coreExplanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !recommendedLearning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return false }
        if let expected {
            guard questionType == expected.questionType, Set(choices) == Set(expected.choices),
                Set(selectedChoices) == Set(expected.selectedChoices)
            else { return false }
        }
        let others = Set(choices).subtracting(selectedChoices)
        return Set(wrongChoiceReasons.map(\.choice)) == others && wrongChoiceReasons.count == others.count
            && wrongChoiceReasons.allSatisfy { !$0.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// 표시용 제목은 모델 출력에 맡기지 않아 새 응답의 정보 계층을 일정하게 유지한다.
    var markdown: String {
        var sections = ["## 핵심 해설\n\(coreExplanation.trimmingCharacters(in: .whitespacesAndNewlines))"]
        if !wrongChoiceReasons.isEmpty {
            let reasons = wrongChoiceReasons.sorted { $0.choice < $1.choice }.map {
                let reason = $0.reason.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\n", with: "\n  ")
                return "- \(GenerationContract.choiceMarker($0.choice)): \(reason)"
            }.joined(separator: "\n")
            sections.append("## 오답인 이유\n\(reasons)")
        }
        sections.append("## 추천 학습 내용\n\(recommendedLearning.trimmingCharacters(in: .whitespacesAndNewlines))")
        return sections.joined(separator: "\n\n")
    }
}

/// 직접 호출과 프록시 호출 모두 같은 응답 검증을 거쳐야 부분 응답이 기록에 남지 않는다.
enum GenerationContract {
    static let format = "structured-v1"

    static func choiceMarker(_ choice: Int) -> String {
        guard (1...20).contains(choice), let scalar = UnicodeScalar(0x2460 + choice - 1) else { return String(choice) }
        return String(scalar)
    }

    static func configuration(for kind: GenerationKind, retry: Bool = false) -> [String: Any] {
        [
            "maxOutputTokens": (kind == .answer ? 2048 : 4096) * (retry ? 2 : 1),
            "thinkingConfig": ["thinkingLevel": "low"],
            "responseMimeType": "application/json",
            "responseJsonSchema": schema(for: kind),
        ]
    }

    static func decode(
        _ data: Data, kind: GenerationKind, expected: AnswerContext? = nil
    ) throws -> (
        text: String, context: AnswerContext
    ) {
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
            let candidate = response.candidates?.first
        else { throw GeminiError.invalidResponse }
        guard candidate.finishReason != "MAX_TOKENS" else { throw GeminiError.incompleteResponse }
        guard candidate.finishReason == "STOP" else { throw GeminiError.invalidResponse }
        let text =
            candidate.content?.parts?.filter { $0.thought != true }.compactMap(\.text)
            .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { throw GeminiError.emptyResponse }
        let payload = Data(text.utf8)
        switch kind {
        case .answer:
            guard let answer = try? JSONDecoder().decode(GeneratedAnswer.self, from: payload), answer.isValid else {
                throw GeminiError.invalidResponse
            }
            return (answer.displayText, answer.context)
        case .explanation:
            guard let explanation = try? JSONDecoder().decode(GeneratedExplanation.self, from: payload),
                explanation.isValid(expected: expected)
            else { throw GeminiError.invalidResponse }
            return (explanation.markdown, explanation.context)
        }
    }

    private static func schema(for kind: GenerationKind) -> [String: Any] {
        let numbers: [String: Any] = [
            "type": "array", "items": ["type": "integer", "minimum": 1, "maximum": 20], "maxItems": 20,
        ]
        var properties: [String: Any] = [
            "questionType": ["type": "string", "enum": ["multipleChoice", "shortAnswer"]],
            "choices": numbers,
            "selectedChoices": numbers,
        ]
        if kind == .answer {
            properties["answer"] = ["type": "string", "description": "객관식은 빈 문자열, 단답형은 정답만"]
        } else {
            properties["coreExplanation"] = ["type": "string", "minLength": 1]
            properties["recommendedLearning"] = ["type": "string", "minLength": 1]
            properties["wrongChoiceReasons"] = [
                "type": "array", "maxItems": 20,
                "items": [
                    "type": "object",
                    "properties": [
                        "choice": ["type": "integer", "minimum": 1, "maximum": 20],
                        "reason": ["type": "string", "minLength": 1],
                    ],
                    "required": ["choice", "reason"], "additionalProperties": false,
                ],
            ]
        }
        return [
            "type": "object", "properties": properties, "required": properties.keys.sorted(),
            "additionalProperties": false,
        ]
    }

    private struct Response: Decodable {
        struct Candidate: Decodable {
            let finishReason: String?
            let content: Content?
        }
        struct Content: Decodable { let parts: [Part]? }
        struct Part: Decodable {
            let text: String?
            let thought: Bool?
        }
        let candidates: [Candidate]?
    }
}
