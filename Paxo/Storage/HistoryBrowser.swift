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

    /// 한 번도 다시 풀지 않은 오답을 먼저, 그다음 복습한 지 오래된 순으로 내보낸다.
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
            recovered: shown.filter { $0.correctness == .incorrect && $0.lastReviewCorrectness == .correct }.count,
            pendingReview: shown.filter(\.needsReview).count
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
    let recovered: Int
    let pendingReview: Int
}
