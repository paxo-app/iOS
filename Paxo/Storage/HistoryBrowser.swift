import Foundation

/// 날짜 경계는 기기의 달력을 사용해 자정과 시간대 변경에도 기록을 정확히 묶는다.
enum HistoryBrowser {
    static func visible(_ items: [SolveResult]) -> [SolveResult] {
        Array(items.sorted { $0.date > $1.date }.prefix(100))
    }

    static func recent(_ items: [SolveResult], requestedCount: Int) -> [SolveResult] {
        Array(visible(items).prefix(max(requestedCount, 1)))
    }

    static func shouldClose(activeResultID: UUID?, items: [SolveResult]) -> Bool {
        guard let activeResultID else { return false }
        return !visible(items).contains { $0.id == activeResultID }
    }

    static func filter(
        _ items: [SolveResult], query: String, date: Date? = nil,
        subjectName: (UUID) -> String? = { _ in nil }, calendar: Calendar = .current
    ) -> [SolveResult] {
        let terms = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return items.filter { item in
            if let date, !calendar.isDate(item.date, inSameDayAs: date) { return false }
            let text = [item.answer ?? "", item.explanation ?? "", subjectName(item.id) ?? ""].joined(separator: " ")
            return terms.allSatisfy {
                text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }.sorted { $0.date > $1.date }
    }

    /// 오늘까지 예정된 문제만, 가장 오래 밀린 것부터 내보낸다.
    static func dueQueue(_ items: [SolveResult], now: Date = Date(), calendar: Calendar = .current) -> [SolveResult] {
        visible(items)
            .filter { ReviewScheduler.isDue($0, now: now, calendar: calendar) }
            .sorted {
                let left = ReviewScheduler.dueDate(for: $0, calendar: calendar)
                let right = ReviewScheduler.dueDate(for: $1, calendar: calendar)
                return left == right ? $0.date < $1.date : left < right
            }
    }

    /// 일정과 무관하게 복습을 마치지 않은 오답 전체. 한 번도 다시 풀지 않은 것을 먼저 낸다.
    static func reviewQueue(_ items: [SolveResult]) -> [SolveResult] {
        visible(items).filter(\.needsReview).sorted { left, right in
            switch (left.lastReviewedAt, right.lastReviewedAt) {
            case (nil, nil): return left.date < right.date
            case (nil, _): return true
            case (_, nil): return false
            case (let leftDate?, let rightDate?): return leftDate < rightDate
            }
        }
    }

    /// 주의 시작 요일은 기기의 달력을 따른다.
    static func summary(_ items: [SolveResult], now: Date = Date(), calendar: Calendar = .current) -> HistorySummary {
        let shown = visible(items)
        let week = calendar.dateInterval(of: .weekOfYear, for: now)
        return HistorySummary(
            solvedThisWeek: shown.filter { week?.contains($0.date) == true }.count,
            incorrect: shown.filter { $0.correctness == .incorrect }.count,
            retired: shown.filter { $0.correctness == .incorrect && $0.reviewRetiredAt != nil }.count,
            dueToday: shown.filter { ReviewScheduler.isDue($0, now: now, calendar: calendar) }.count
        )
    }

    static func days(_ items: [SolveResult], calendar: Calendar = .current) -> [HistoryDay] {
        Dictionary(grouping: items) { calendar.startOfDay(for: $0.date) }
            .map { HistoryDay(date: $0.key, items: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.date > $1.date }
    }

    static func subjects(_ items: [SolveResult], catalog: SubjectCatalog) -> [HistorySubjectGroup] {
        let grouped = Dictionary(grouping: items) { catalog.subject(for: $0.id)?.id }
        let assigned = catalog.subjects
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .compactMap { subject -> HistorySubjectGroup? in
                guard let results = grouped[subject.id], !results.isEmpty else { return nil }
                return HistorySubjectGroup(subjectID: subject.id, name: subject.name, items: results)
            }
        guard let unclassified = grouped[nil], !unclassified.isEmpty else { return assigned }
        return assigned + [HistorySubjectGroup(subjectID: nil, name: "미분류", items: unclassified)]
    }
}

struct HistoryDay: Identifiable {
    let date: Date
    let items: [SolveResult]
    var id: Date { date }
}

struct HistorySubjectGroup: Identifiable {
    let subjectID: UUID?
    let name: String
    let items: [SolveResult]
    var id: String { subjectID?.uuidString ?? "unclassified" }
    var incorrectCount: Int { items.filter { $0.correctness == .incorrect }.count }
}

struct HistorySummary: Equatable {
    let solvedThisWeek: Int
    let incorrect: Int
    let retired: Int
    let dueToday: Int
}
