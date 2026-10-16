import Foundation
import Testing

@testable import Paxo

struct SolveResultEditTests {
    @Test func answerEditKeepsExplanationAndClearsAIContext() {
        var result = SolveResult(preset: .general)
        result.answer = "③"
        result.answerContext = AnswerContext(questionType: .multipleChoice, choices: [1, 2, 3], selectedChoices: [3])
        result.explanation = "기존 해설"

        let saved = result.replaceAnswer(with: " ② ")
        #expect(saved)
        #expect(result.answer == "②")
        #expect(result.answerContext == nil)
        #expect(result.explanation == "기존 해설")
        #expect(result.explanationNeedsReview == true)
    }

    @Test func explanationCanBeAddedAndEditedIndependently() {
        var result = SolveResult(preset: .general)
        result.answer = "42"
        result.explanationNeedsReview = true

        let added = result.replaceExplanation(with: " 첫 해설 ")
        #expect(added)
        #expect(result.explanation == "첫 해설")
        #expect(result.answer == "42")
        #expect(result.explanationNeedsReview == false)
        let updated = result.replaceExplanation(with: "수정한 해설")
        #expect(updated)
        #expect(result.explanation == "수정한 해설")
    }

    @Test func blankEditsDoNotChangeRecord() {
        var result = SolveResult(preset: .general)
        result.answer = "③"
        result.explanation = "기존 해설"
        let original = result

        let savedAnswer = result.replaceAnswer(with: " \n ")
        let savedExplanation = result.replaceExplanation(with: "\t")
        #expect(!savedAnswer)
        #expect(!savedExplanation)
        #expect(result == original)
    }

    @Test func delayedAIExplanationDoesNotOverwriteManualEdit() {
        var result = SolveResult(preset: .general)
        result.answer = "수정한 정답"
        let added = result.replaceExplanation(with: "직접 쓴 해설")
        #expect(added)

        let accepted = result.acceptGeneratedExplanation("늦게 온 AI 해설", basedOnAnswer: "이전 정답")
        #expect(!accepted)
        #expect(result.explanation == "직접 쓴 해설")
        #expect(result.explanationNeedsReview == false)
    }

    @Test func delayedAIExplanationForOldAnswerNeedsReview() {
        var result = SolveResult(preset: .general)
        result.answer = "수정한 정답"

        let accepted = result.acceptGeneratedExplanation("이전 정답의 AI 해설", basedOnAnswer: "이전 정답")
        #expect(accepted)
        #expect(result.explanationNeedsReview == true)
    }

    @Test func editedRecordPersistsAndLegacyRecordDecodes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HistoryStore(baseURL: directory)
        var edited = SolveResult(preset: .general)
        edited.answer = "③"
        edited.explanation = "기존 해설"
        let saved = edited.replaceAnswer(with: "②")
        #expect(saved)
        store.save([edited])

        let restored = try #require(store.load().first)
        #expect(restored.answer == "②")
        #expect(restored.explanation == "기존 해설")
        #expect(restored.explanationNeedsReview == true)

        let legacy = SolveResult(preset: .general)
        let decoded = try JSONDecoder().decode(SolveResult.self, from: JSONEncoder().encode(legacy))
        #expect(decoded.explanationNeedsReview == nil)
    }
}
