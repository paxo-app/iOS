import Foundation

/// 오답을 간격을 늘려 가며 다시 내는 일정을 계산한다. 같은 날 반복보다 날을 바꿔 다시 푸는 쪽이 오래 남는다.
enum ReviewScheduler {
    /// 맞혔을 때 간격을 늘리는 비율
    static let goodFactor = 2.5
    /// 맞혔지만 확신이 없을 때는 간격을 거의 유지한다
    static let hardFactor = 1.2
    static let relearnIntervalDays = 1
    /// 하루 이상 지나 맞힌 문제에 보장하는 최소 간격
    static let firstGoodIntervalDays = 3
    /// 이보다 긴 간격이 나오면 충분히 익힌 것으로 보고 복습을 마친다
    static let retireAfterDays = 30

    static func next(
        grade: ReviewGrade, for item: SolveResult, now: Date = Date(), calendar: Calendar = .current
    ) -> ReviewOutcome {
        let today = calendar.startOfDay(for: now)
        let lastStudied = calendar.startOfDay(for: item.lastStudiedAt)
        let elapsed = max(calendar.dateComponents([.day], from: lastStudied, to: today).day ?? 0, 0)
        let current = item.reviewIntervalDays ?? 0
        // 예정일 전에 다시 풀면 실제로 지난 날수만큼만 기억을 유지한 것으로 인정한다.
        let isEarly = today < dueDate(for: item, calendar: calendar)
        let credited = Double(isEarly ? min(current, elapsed) : current)

        let interval: Int
        switch grade {
        case .again:
            interval = relearnIntervalDays
        case .hard:
            interval = max(relearnIntervalDays, Int((credited * hardFactor).rounded()))
        case .good:
            let floor = elapsed >= 1 ? firstGoodIntervalDays : relearnIntervalDays
            interval = max(floor, Int((credited * goodFactor).rounded()))
        }
        guard interval <= retireAfterDays else {
            return ReviewOutcome(intervalDays: interval, dueAt: nil, isRetired: true)
        }
        return ReviewOutcome(
            intervalDays: interval, dueAt: calendar.date(byAdding: .day, value: interval, to: today),
            isRetired: false
        )
    }

    /// 일정 필드가 없던 기록도 같은 규칙으로 복습일을 정한다.
    static func dueDate(for item: SolveResult, calendar: Calendar = .current) -> Date {
        if let stored = item.nextReviewAt { return calendar.startOfDay(for: stored) }
        let base = calendar.startOfDay(for: item.lastStudiedAt)
        let days =
            item.lastReviewedAt != nil && item.lastReviewCorrectness == .correct
            ? firstGoodIntervalDays : relearnIntervalDays
        return calendar.date(byAdding: .day, value: days, to: base) ?? base
    }

    static func statusText(for item: SolveResult, now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard item.correctness == .incorrect else { return nil }
        if item.reviewRetiredAt != nil { return "복습 완료" }
        let due = dueDate(for: item, calendar: calendar)
        return due <= now ? "오늘 복습" : "다음 복습 \(due.formatted(.dateTime.month().day()))"
    }

    static func isDue(_ item: SolveResult, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        item.needsReview && dueDate(for: item, calendar: calendar) <= now
    }
}

enum ReviewGrade: String, Codable {
    case again
    case hard
    case good
}

struct ReviewOutcome: Equatable {
    let intervalDays: Int
    let dueAt: Date?
    let isRetired: Bool
}
