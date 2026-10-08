import SwiftUI

/// 날짜와 검색 조건은 상세 화면에서 돌아와도 유지한다.
struct HistoryArchiveView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showsDetail = false
    @State private var selectedDate: Date?
    @State private var query = ""

    private var matchingItems: [SolveResult] {
        HistoryBrowser.filter(appState.history, query: query, date: selectedDate)
    }

    var body: some View {
        Group {
            if showsDetail {
                ResultView(onBack: { showsDetail = false }, backTitle: "풀이 기록으로", isHistory: true)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    searchField
                    Text("최근 100개의 풀이와 문제 이미지를 이 Mac에서 다시 볼 수 있습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if matchingItems.isEmpty {
                        emptyState
                    } else if selectedDate != nil {
                        HistoryListView(
                            items: matchingItems,
                            showsExplanation: appState.historyShowsExplanation,
                            isBusy: appState.isSolving
                        ) { item in
                            if appState.showFromHistory(item, presentPanel: false) {
                                showsDetail = true
                            }
                        }
                    } else {
                        dateList
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .tint(PaxoStyle.brand)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            if selectedDate != nil {
                Button {
                    selectedDate = nil
                } label: {
                    Label("날짜 목록으로", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            HStack {
                if let selectedDate {
                    Text(selectedDate, format: .dateTime.year().month().day())
                        .font(.title2.bold())
                } else {
                    Text("풀이 기록").font(.title2.bold())
                }
                Spacer()
                Text("\(matchingItems.count)개")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("정답, 해설, 과목 검색", text: $query)
                .textFieldStyle(.plain)
                .accessibilityLabel("풀이 기록 검색")
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("검색어 지우기")
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    private var dateList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(HistoryBrowser.days(matchingItems)) { day in
                    Button {
                        selectedDate = day.date
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "calendar")
                                .font(.title2)
                                .foregroundStyle(PaxoStyle.brand)
                                .frame(width: 36)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(day.date, format: .dateTime.year().month().day().weekday(.wide))
                                    .font(.callout.weight(.semibold))
                                Text(
                                    "풀이 \(day.items.count)개 · 정답 \(day.items.filter { $0.correctness == .correct }.count)개 · 오답 \(day.items.filter { $0.correctness == .incorrect }.count)개"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: query.isEmpty ? "calendar" : "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(query.isEmpty ? "아직 풀이 기록이 없어요" : "검색 결과가 없어요")
                .font(.callout.weight(.medium))
            Text(query.isEmpty ? "문제를 풀면 날짜별로 기록이 모입니다." : "다른 검색어를 입력하거나 검색어를 지워보세요.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if !query.isEmpty {
                Button("검색 초기화") { query = "" }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
