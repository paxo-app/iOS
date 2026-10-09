import Foundation
import Testing

@testable import Paxo

/// 앱과 프록시가 같은 객관식 회귀 사례를 사용해 선택지 누락과 부분 응답을 막는다.
struct GenerationContractTests {
    @Test func rendersMultipleChoiceAsNumberAndAllOtherReasons() throws {
        let fixture = try GenerationFixtures.load()
        let answer = try GenerationContract.decode(GenerationFixtures.envelope(fixture["answer"]), kind: .answer)
        #expect(answer.text == "③")
        #expect(answer.context.selectedChoices == [3])
        let explanation = try GenerationContract.decode(
            GenerationFixtures.envelope(fixture["explanation"]), kind: .explanation, expected: answer.context
        )
        #expect(explanation.text.contains("## 핵심 해설"))
        #expect(explanation.text.contains("## 오답인 이유"))
        #expect(explanation.text.contains("## 추천 학습 내용"))
        for marker in ["①", "②", "④"] { #expect(explanation.text.contains("- \(marker):")) }
        #expect(!explanation.text.contains("- ③:"))
    }

    @Test func rejectsMissingDuplicateAndSelectedChoiceReasons() throws {
        let original = try #require(GenerationFixtures.load()["explanation"] as? [String: Any])
        let reasons = try #require(original["wrongChoiceReasons"] as? [[String: Any]])
        for invalid in [Array(reasons.dropLast()), reasons + [reasons[0]], reasons + [["choice": 3, "reason": "정답"]]] {
            var payload = original
            payload["wrongChoiceReasons"] = invalid
            #expect(throws: GeminiError.self) {
                try GenerationContract.decode(GenerationFixtures.envelope(payload), kind: .explanation)
            }
        }
    }

    @Test func rejectsChangedAnswerContextAndMissingLearning() throws {
        var payload = try #require(GenerationFixtures.load()["explanation"] as? [String: Any])
        let expected = AnswerContext(questionType: .multipleChoice, choices: [1, 2, 3, 4], selectedChoices: [1])
        #expect(throws: GeminiError.self) {
            try GenerationContract.decode(GenerationFixtures.envelope(payload), kind: .explanation, expected: expected)
        }
        payload["recommendedLearning"] = " \n"
        #expect(throws: GeminiError.self) {
            try GenerationContract.decode(GenerationFixtures.envelope(payload), kind: .explanation)
        }
    }

    @Test func rejectsTruncatedBlockedMissingAndUnstructuredResponses() throws {
        let payload = try #require(GenerationFixtures.load()["answer"])
        for finishReason in ["MAX_TOKENS", "SAFETY", "", "OTHER"] {
            #expect(throws: GeminiError.self) {
                try GenerationContract.decode(
                    GenerationFixtures.envelope(payload, finishReason: finishReason), kind: .answer)
            }
        }
        #expect(throws: GeminiError.self) {
            try GenerationContract.decode(GenerationFixtures.envelope("소프트웨어 사용자들에게 사용 방법을 신속히 숙"), kind: .answer)
        }
        #expect(throws: GeminiError.self) {
            try GenerationContract.decode(Data(#"{"candidates":[]}"#.utf8), kind: .answer)
        }
    }

    @Test func filtersThoughtParts() throws {
        let answer = try GenerationContract.decode(
            GenerationFixtures.envelope(GenerationFixtures.load()["answer"], thoughts: true), kind: .answer)
        #expect(answer.text == "③")
    }

    @Test func shortAnswersDoNotInventAlternativeSections() throws {
        let answer: [String: Any] = [
            "questionType": "shortAnswer", "choices": [], "selectedChoices": [], "answer": "42",
        ]
        let decoded = try GenerationContract.decode(GenerationFixtures.envelope(answer), kind: .answer)
        let explanation: [String: Any] = [
            "questionType": "shortAnswer", "choices": [], "selectedChoices": [],
            "coreExplanation": "계산 결과는 42입니다.\n\n```swift\nlet result = 42\n```",
            "wrongChoiceReasons": [], "recommendedLearning": "계산 과정을 검산하세요.",
        ]
        let result = try GenerationContract.decode(
            GenerationFixtures.envelope(explanation), kind: .explanation, expected: decoded.context)
        #expect(decoded.text == "42")
        #expect(!result.text.contains("## 오답인 이유"))
        #expect(result.text.contains("```swift\nlet result = 42\n```"))
    }

    @Test func persistsContextWithoutBreakingOldHistory() throws {
        var result = SolveResult(preset: .general)
        result.answerContext = AnswerContext(
            questionType: .multipleChoice, choices: [1, 2, 3, 4], selectedChoices: [3])
        let data = try JSONEncoder().encode(result)
        #expect(try JSONDecoder().decode(SolveResult.self, from: data) == result)
        var legacy = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "answerContext")
        #expect(
            try JSONDecoder().decode(SolveResult.self, from: JSONSerialization.data(withJSONObject: legacy))
                .answerContext == nil)
    }

    @Test func rejectsInvalidChoiceNumbersAndFormatsMultipleAnswers() throws {
        var payload = try #require(GenerationFixtures.load()["answer"] as? [String: Any])
        payload["selectedChoices"] = [4, 1]
        #expect(try GenerationContract.decode(GenerationFixtures.envelope(payload), kind: .answer).text == "①, ④")
        for invalid in [[0], [5], [3, 3], []] {
            payload["selectedChoices"] = invalid
            #expect(throws: GeminiError.self) {
                try GenerationContract.decode(GenerationFixtures.envelope(payload), kind: .answer)
            }
        }
    }

}
