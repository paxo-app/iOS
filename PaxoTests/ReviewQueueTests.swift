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

        item.recordReview(.again, at: first)
        #expect(item.reviewCount == 1)
        #expect(item.lastReviewCorrectness == .incorrect)

        item.recordReview(.good, at: second)
        #expect(item.reviewCount == 2)
        #expect(item.lastReviewedAt == second)
        #expect(item.lastReviewCorrectness == .correct)
        #expect(item.correctness == .incorrect)
        // 한 번 맞혀도 간격을 늘려 다시 내야 하므로 복습 대상에 남는다.
        #expect(item.needsReview)
    }

    @Test func queueHoldsUnfinishedWrongAnswersOldestReviewFirst() {
        let correct = result(.correct, solvedAt: 1)
        let ungraded = result(nil, solvedAt: 2)
        let newWrong = result(.incorrect, solvedAt: 30)
        let oldWrong = result(.incorrect, solvedAt: 10)
        var reviewedLongAgo = result(.incorrect, solvedAt: 5)
        reviewedLongAgo.recordReview(.again, at: Date(timeIntervalSince1970: 40))
        var reviewedRecently = result(.incorrect, solvedAt: 6)
        reviewedRecently.recordReview(.again, at: Date(timeIntervalSince1970: 50))
        var recovered = result(.incorrect, solvedAt: 7)
        recovered.recordReview(.good, at: Date(timeIntervalSince1970: 60))
        var finished = result(.incorrect, solvedAt: 8)
        finished.reviewRetiredAt = Date(timeIntervalSince1970: 70)

        let queue = HistoryBrowser.reviewQueue([
            correct, ungraded, reviewedRecently, newWrong, recovered, finished, reviewedLongAgo, oldWrong,
        ])
        #expect(
            queue.map(\.id) == [oldWrong.id, newWrong.id, reviewedLongAgo.id, reviewedRecently.id, recovered.id]
        )
    }

    @Test func summaryCountsThisWeekAndReviewProgress() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Seoul"))
        calendar.firstWeekday = 2
        // 2026-11-11은 수요일이라 같은 주는 11-09(월)부터다.
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 12)))
        let monday = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 0)))
        let lastSunday = monday.addingTimeInterval(-1)

        let thisWeekCorrect = result(.correct, solvedAt: now.timeIntervalSince1970)
        let thisWeekWrong = result(.incorrect, solvedAt: monday.timeIntervalSince1970)
        var lastWeekRecovered = result(.incorrect, solvedAt: lastSunday.timeIntervalSince1970)
        lastWeekRecovered.recordReview(.good, at: now, calendar: calendar)
        var lastWeekFinished = result(.incorrect, solvedAt: lastSunday.timeIntervalSince1970 - 50)
        lastWeekFinished.reviewRetiredAt = now
        let lastWeekUngraded = result(nil, solvedAt: lastSunday.timeIntervalSince1970 - 100)

        let summary = HistoryBrowser.summary(
            [thisWeekCorrect, thisWeekWrong, lastWeekRecovered, lastWeekFinished, lastWeekUngraded],
            now: now, calendar: calendar
        )
        // 월요일에 틀린 문제만 복습 차례다. 오늘 맞힌 문제는 3일 뒤로 밀리고 마친 문제는 빠진다.
        #expect(summary == HistorySummary(solvedThisWeek: 2, incorrect: 3, retired: 1, dueToday: 1))
    }

    @Test func narrowedListReviewsOnlyItsOwnWrongAnswers() {
        let inScope = result(.incorrect, solvedAt: 10)
        let outOfScope = result(.incorrect, solvedAt: 20)
        let group = HistorySubjectGroup(subjectID: UUID(), name: "수학", items: [inScope, result(.correct, solvedAt: 5)])

        #expect(HistoryBrowser.reviewQueue(group.items).map(\.id) == [inScope.id])
        #expect(HistoryBrowser.reviewQueue([inScope, outOfScope]).count == 2)
        #expect(group.incorrectCount == 1)
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
        reviewed.recordReview(.good)
        let roundTrip = try JSONDecoder().decode(SolveResult.self, from: JSONEncoder().encode(reviewed))
        #expect(roundTrip == reviewed)
    }
}
