import Foundation
import Testing

@testable import Paxo

struct ReviewQueueTests {
    private func result(_ correctness: SolveCorrectness?, solvedAt seconds: TimeInterval) -> SolveResult {
        var result = SolveResult(preset: .general)
        result.answer = "③"
        result.correctness = correctness
        result.date = Date(timeIntervalSince1970: seconds)
        return result
    }

    @Test func reviewKeepsFirstGradeAndCountsAttempts() {
        var item = result(.incorrect, solvedAt: 0)
        let first = Date(timeIntervalSince1970: 100)
        let second = Date(timeIntervalSince1970: 200)

        item.recordReview(.incorrect, at: first)
        #expect(item.reviewCount == 1)
        #expect(item.needsReview)

        item.recordReview(.correct, at: second)
        #expect(item.reviewCount == 2)
        #expect(item.lastReviewedAt == second)
        #expect(item.lastReviewCorrectness == .correct)
        #expect(item.correctness == .incorrect)
        #expect(!item.needsReview)
    }

    @Test func queueHoldsOnlyUnrecoveredWrongAnswersOldestReviewFirst() {
        let correct = result(.correct, solvedAt: 1)
        let ungraded = result(nil, solvedAt: 2)
        let newWrong = result(.incorrect, solvedAt: 30)
        let oldWrong = result(.incorrect, solvedAt: 10)
        var reviewedLongAgo = result(.incorrect, solvedAt: 5)
        reviewedLongAgo.recordReview(.incorrect, at: Date(timeIntervalSince1970: 40))
        var reviewedRecently = result(.incorrect, solvedAt: 6)
        reviewedRecently.recordReview(.incorrect, at: Date(timeIntervalSince1970: 50))
        var recovered = result(.incorrect, solvedAt: 7)
        recovered.recordReview(.correct, at: Date(timeIntervalSince1970: 60))

        let queue = HistoryBrowser.reviewQueue([
            correct, ungraded, reviewedRecently, newWrong, recovered, reviewedLongAgo, oldWrong,
        ])
        #expect(queue.map(\.id) == [oldWrong.id, newWrong.id, reviewedLongAgo.id, reviewedRecently.id])
    }

    /// 복습 필드가 없던 버전의 기록이 그대로 열려야 기존 사용자의 기록이 사라지지 않는다.
    @Test func recordsSavedBeforeReviewFieldsStillDecode() throws {
        let legacy = """
            {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","date":0,"preset":"general","answer":"③","correctness":"incorrect"}
            """
        let decoded = try JSONDecoder().decode(SolveResult.self, from: Data(legacy.utf8))
        #expect(decoded.reviewCount == nil)
        #expect(decoded.needsReview)

        var reviewed = decoded
        reviewed.recordReview(.correct)
        let roundTrip = try JSONDecoder().decode(SolveResult.self, from: JSONEncoder().encode(reviewed))
        #expect(roundTrip == reviewed)
    }
}
