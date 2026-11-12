import SwiftUI

/// 기록을 열자마자 복습할 양이 보이도록 숫자만 한 줄로 요약한다.
struct HistorySummaryView: View {
    let summary: HistorySummary

    var body: some View {
        HStack(spacing: 8) {
            tile("이번 주 풀이", summary.solvedThisWeek)
            tile("오답", summary.incorrect)
            tile("복습 완료", summary.retired)
            tile("오늘 복습", summary.dueToday, isEmphasized: summary.dueToday > 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func tile(_ title: String, _ value: Int, isEmphasized: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(isEmphasized ? PaxoStyle.brand : .primary)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
    }
}
