import Foundation

/// 날짜 경계는 기기의 달력을 사용해 자정과 시간대 변경에도 기록을 정확히 묶는다.
enum HistoryBrowser {
    static func filter(
        _ items: [SolveResult], query: String, date: Date? = nil, calendar: Calendar = .current
    ) -> [SolveResult] {
        let terms = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return items.filter { item in
            if let date, !calendar.isDate(item.date, inSameDayAs: date) { return false }
            let text = [item.answer ?? "", item.explanation ?? "", item.preset.displayName].joined(separator: " ")
            return terms.allSatisfy {
                text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }.sorted { $0.date > $1.date }
    }

    static func days(_ items: [SolveResult], calendar: Calendar = .current) -> [HistoryDay] {
        Dictionary(grouping: items) { calendar.startOfDay(for: $0.date) }
            .map { HistoryDay(date: $0.key, items: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.date > $1.date }
    }
}

struct HistoryDay: Identifiable {
    let date: Date
    let items: [SolveResult]
    var id: Date { date }
}
