import SwiftUI

/// 날짜와 검색 조건은 상세 화면에서 돌아와도 유지한다.
struct HistoryArchiveView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showsDetail = false
    @State private var selectedDate: Date?
    @State private var selectedSubjectKey: String?
    @State private var grouping: HistoryGrouping = .date
    @State private var showsSubjectManager = false
    @State private var query = ""

    private var rootMatches: [SolveResult] {
        HistoryBrowser.filter(appState.visibleHistory, query: query) { id in
            appState.subject(for: id)?.name
        }
    }

    private var matchingItems: [SolveResult] {
        rootMatches.filter { item in
            if let selectedDate, !Calendar.current.isDate(item.date, inSameDayAs: selectedDate) {
                return false
            }
            if let selectedSubjectKey {
                let key = appState.subject(for: item.id)?.id.uuidString ?? "unclassified"
                return key == selectedSubjectKey
            }
            return true
        }
    }

    var body: some View {
        Group {
            if showsDetail {
                ResultView(onBack: { showsDetail = false }, backTitle: "풀이 기록으로", isHistory: true)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    searchField
                    if appState.serverTier == .pro {
                        proControls
                    }
                    if let subjectError = appState.subjectError, appState.serverTier == .pro {
                        Text(subjectError).font(.caption).foregroundStyle(.red)
                    }
                    Text(
                        appState.serverTier == .pro
                            ? "최근 100개의 풀이와 문제 이미지를 이 Mac에서 다시 볼 수 있습니다."
                            : "무료 플랜에서는 최신 10개를 볼 수 있습니다. 이전 기록은 이 Mac에 보관되며 Pro에서 다시 볼 수 있습니다."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    if matchingItems.isEmpty {
                        emptyState
                    } else if selectedDate != nil || selectedSubjectKey != nil {
                        HistoryListView(
                            items: matchingItems,
                            showsExplanation: appState.historyShowsExplanation,
                            isBusy: appState.isSolving
                        ) { item in
                            if appState.showFromHistory(item, presentPanel: false) {
                                showsDetail = true
                            }
                        }
                    } else if grouping == .subject && appState.serverTier == .pro {
                        subjectList
                    } else {
                        dateList
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .tint(PaxoStyle.brand)
        .sheet(isPresented: $showsSubjectManager) {
            SubjectManagementView().environmentObject(appState)
        }
        .onChange(of: appState.serverTier) {
            if appState.serverTier != .pro {
                grouping = .date
                selectedDate = nil
                selectedSubjectKey = nil
                showsDetail = false
                showsSubjectManager = false
            }
        }
        .onChange(of: appState.subjectCatalog) {
            if let selectedSubjectKey, selectedSubjectKey != "unclassified",
                !appState.historySubjects.contains(where: { $0.id.uuidString == selectedSubjectKey })
            {
                self.selectedSubjectKey = nil
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            if selectedDate != nil || selectedSubjectKey != nil {
                Button {
                    selectedDate = nil
                    selectedSubjectKey = nil
                } label: {
                    Label(grouping == .date ? "날짜 목록으로" : "과목 목록으로", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            HStack {
                if let selectedDate {
                    Text(selectedDate, format: .dateTime.year().month().day())
                        .font(.title2.bold())
                } else if let selectedSubjectKey {
                    Text(
                        selectedSubjectKey == "unclassified"
                            ? "미분류"
                            : appState.historySubjects.first(where: { $0.id.uuidString == selectedSubjectKey })?.name
                                ?? "미분류"
                    )
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
            TextField(appState.serverTier == .pro ? "정답, 해설, 과목 검색" : "정답, 해설 검색", text: $query)
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

    private var proControls: some View {
        HStack {
            Picker("묶음", selection: $grouping) {
                Text("날짜별").tag(HistoryGrouping.date)
                Text("과목별").tag(HistoryGrouping.subject)
            }
            .pickerStyle(.segmented)
            .onChange(of: grouping) {
                selectedDate = nil
                selectedSubjectKey = nil
            }
            Button("과목 관리") { showsSubjectManager = true }
                .disabled(!appState.subjectCatalogReady)
        }
    }

    private var dateList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(HistoryBrowser.days(rootMatches)) { day in
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

    private var subjectList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(HistoryBrowser.subjects(rootMatches, catalog: appState.subjectCatalog)) { group in
                    Button {
                        selectedSubjectKey = group.id
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "folder")
                                .font(.title2)
                                .foregroundStyle(PaxoStyle.brand)
                                .frame(width: 36)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(group.name).font(.callout.weight(.semibold))
                                Text("풀이 \(group.items.count)개")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
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

private enum HistoryGrouping: String {
    case date
    case subject
}
