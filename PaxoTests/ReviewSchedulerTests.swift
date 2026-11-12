import Foundation
import Testing

@testable import Paxo

struct ReviewSchedulerTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .gmt
        return calendar
    }()

    /// 2026-11-01을 0일째로 센 날짜
    private func day(_ offset: Int, hour: Int = 10, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 1 + offset, hour: hour, minute: minute))
            ?? Date(timeIntervalSince1970: 0)
    }

    private func wrongAnswer(solvedOn offset: Int) -> SolveResult {
        var item = SolveResult(preset: .general)
        item.answer = "③"
        item.correctness = .incorrect
        item.date = day(offset)
        return item
    }

    @Test func answeringCorrectlyOnScheduleGrowsIntervalUntilFinished() {
        var item = wrongAnswer(solvedOn: 0)
        #expect(ReviewScheduler.dueDate(for: item, calendar: calendar) == day(1, hour: 0))

        var intervals: [Int] = []
        var reviewDay = 1
        for _ in 0..<3 {
            let outcome = item.recordReview(.good, at: day(reviewDay), calendar: calendar)
            intervals.append(outcome.intervalDays)
            #expect(item.nextReviewAt == day(reviewDay + outcome.intervalDays, hour: 0))
            #expect(item.needsReview)
            reviewDay += outcome.intervalDays
        }
        #expect(intervals == [3, 8, 20])

        let last = item.recordReview(.good, at: day(reviewDay), calendar: calendar)
        #expect(last.isRetired)
        #expect(item.nextReviewAt == nil)
        #expect(!item.needsReview)
        #expect(ReviewScheduler.statusText(for: item, now: day(reviewDay), calendar: calendar) == "복습 완료")
    }

    @Test func wrongAgainResetsToNextDayAndUnsureKeepsSimilarInterval() {
        var item = wrongAnswer(solvedOn: 0)
        item.recordReview(.good, at: day(1), calendar: calendar)
        item.recordReview(.good, at: day(4), calendar: calendar)
        #expect(item.reviewIntervalDays == 8)

        var unsure = item
        unsure.recordReview(.hard, at: day(12), calendar: calendar)
        #expect(unsure.reviewIntervalDays == 10)
        #expect(unsure.lastReviewCorrectness == .correct)

        item.recordReview(.again, at: day(12), calendar: calendar)
        #expect(item.reviewIntervalDays == 1)
        #expect(item.nextReviewAt == day(13, hour: 0))
        #expect(item.lastReviewCorrectness == .incorrect)
    }

    /// 해설을 방금 본 문제를 바로 맞힌 것은 기억했다는 근거가 약하다.
    @Test func reviewingBeforeDueDateOnlyCreditsDaysActuallyPassed() {
        var sameDay = wrongAnswer(solvedOn: 0)
        sameDay.recordReview(.good, at: day(0, hour: 11), calendar: calendar)
        #expect(sameDay.reviewIntervalDays == 1)
        #expect(sameDay.nextReviewAt == day(1, hour: 0))

        var early = wrongAnswer(solvedOn: 0)
        early.recordReview(.good, at: day(1), calendar: calendar)
        early.recordReview(.good, at: day(4), calendar: calendar)
        // 8일 간격 중 2일만 지나 다시 풀었으므로 2일 × 2.5를 인정한다.
        early.recordReview(.good, at: day(6), calendar: calendar)
        #expect(early.reviewIntervalDays == 5)
    }

    @Test func problemBecomesDueFromMidnightOfItsReviewDay() {
        var item = wrongAnswer(solvedOn: 0)
        item.recordReview(.good, at: day(1), calendar: calendar)

        #expect(!ReviewScheduler.isDue(item, now: day(3, hour: 23, minute: 59), calendar: calendar))
        #expect(ReviewScheduler.isDue(item, now: day(4, hour: 0, minute: 1), calendar: calendar))

        let fresh = wrongAnswer(solvedOn: 3)
        let overdue = wrongAnswer(solvedOn: 1)
        let queue = HistoryBrowser.dueQueue([fresh, item, overdue], now: day(4), calendar: calendar)
        #expect(queue.map(\.id) == [overdue.id, item.id, fresh.id])
        #expect(HistoryBrowser.dueQueue([fresh], now: day(3, hour: 23), calendar: calendar).isEmpty)
    }

    /// 한 번 맞히면 복습에서 영구히 빠지던 이전 버전의 기록도 일정에 편입한다.
    @Test func recordsReviewedBeforeSchedulingExistedGetDefaultDueDates() {
        var recovered = wrongAnswer(solvedOn: 0)
        recovered.reviewCount = 1
        recovered.lastReviewedAt = day(2)
        recovered.lastReviewCorrectness = .correct
        #expect(recovered.needsReview)
        #expect(ReviewScheduler.dueDate(for: recovered, calendar: calendar) == day(5, hour: 0))

        var stillWrong = recovered
        stillWrong.lastReviewCorrectness = .incorrect
        #expect(ReviewScheduler.dueDate(for: stillWrong, calendar: calendar) == day(3, hour: 0))

        var gradedCorrect = wrongAnswer(solvedOn: 0)
        gradedCorrect.correctness = .correct
        #expect(!ReviewScheduler.isDue(gradedCorrect, now: day(9), calendar: calendar))
        #expect(ReviewScheduler.statusText(for: gradedCorrect, now: day(9), calendar: calendar) == nil)
    }
}
