import SwiftUI

/// Pro 사용자가 로컬 과목을 관리한다.
struct SubjectManagementView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var editing: SubjectEditorMode?
    @State private var deletingSubject: HistorySubject?
    @State private var showsDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("과목 관리").font(.title2.bold())
                Spacer()
                Button("완료") { dismiss() }
            }
            Text("과목을 삭제해도 풀이 기록은 남고 미분류로 이동합니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
            List {
                ForEach(appState.historySubjects) { subject in
                    HStack {
                        Text(subject.name)
                        Spacer()
                        Button("이름 수정") { editing = .rename(subject) }
                        Button("삭제", role: .destructive) {
                            deletingSubject = subject
                            showsDeleteConfirmation = true
                        }
                    }
                }
            }
            Button {
                editing = .create
            } label: {
                Label("새 과목 만들기", systemImage: "plus")
            }
            if let error = appState.subjectError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(20)
        .frame(width: 430, height: 380)
        .sheet(item: $editing) { mode in
            SubjectEditorView(mode: mode)
                .environmentObject(appState)
        }
        .alert("과목을 삭제할까요?", isPresented: $showsDeleteConfirmation) {
            Button("삭제", role: .destructive) {
                if let deletingSubject { appState.deleteSubject(deletingSubject.id) }
                deletingSubject = nil
            }
            Button("취소", role: .cancel) { deletingSubject = nil }
        } message: {
            Text("이 과목의 풀이 기록은 미분류로 이동하며 삭제되지 않습니다.")
        }
        .onChange(of: appState.serverTier) {
            if appState.serverTier != .pro { dismiss() }
        }
    }
}

enum SubjectEditorMode: Identifiable {
    case create
    case rename(HistorySubject)

    var id: String {
        switch self {
        case .create: "create"
        case .rename(let subject): subject.id.uuidString
        }
    }

    var title: String {
        switch self {
        case .create: "새 과목"
        case .rename: "과목 이름 수정"
        }
    }

    var initialName: String {
        switch self {
        case .create: ""
        case .rename(let subject): subject.name
        }
    }
}

private struct SubjectEditorView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let mode: SubjectEditorMode
    @State private var name = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(mode.title).font(.title2.bold())
            TextField("과목 이름", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            Text("1~30자 · 같은 이름은 사용할 수 없습니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("취소") { dismiss() }
                Button("저장", action: save)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 350)
        .onAppear { name = mode.initialName }
        .onChange(of: appState.serverTier) {
            if appState.serverTier != .pro { dismiss() }
        }
    }

    private func save() {
        let saved: Bool
        switch mode {
        case .create: saved = appState.createSubject(name)
        case .rename(let subject): saved = appState.renameSubject(subject.id, to: name)
        }
        if saved { dismiss() } else { errorMessage = appState.subjectError }
    }
}

/// 기록 상세의 과목 선택은 로컬 기록에만 반영한다.
struct SubjectPickerView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let resultID: UUID

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("과목 지정").font(.title2.bold())
                Spacer()
                Button("닫기") { dismiss() }
            }
            List {
                Button("미분류") { select(nil) }
                ForEach(appState.historySubjects) { subject in
                    Button(subject.name) { select(subject.id) }
                }
            }
            if let error = appState.subjectError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(20)
        .frame(width: 330, height: 360)
        .onChange(of: appState.serverTier) {
            if appState.serverTier != .pro { dismiss() }
        }
    }

    private func select(_ subjectID: UUID?) {
        if appState.assignSubject(subjectID, to: resultID) { dismiss() }
    }
}
