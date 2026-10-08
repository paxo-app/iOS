import AppKit
import SwiftUI

struct ResultView: View {
    @EnvironmentObject private var appState: AppState
    @State private var copiedField: String?
    @State private var showsProblemImage = false
    @State private var showsSavedExplanation = false
    var onBack: (() -> Void)? = nil
    var backTitle = "최근 풀이로"
    var isHistory = false

    var body: some View {
        VStack(spacing: 0) {
            if let onBack {
                HStack {
                    Button(action: onBack) {
                        Label(backTitle, systemImage: "chevron.left")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(isSolving)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                Divider()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .id(appState.current?.id)
        }
        .frame(minWidth: 340, minHeight: 200)
        .paxoSurface()
        .onAppear { showsSavedExplanation = appState.historyShowsExplanation }
        .onChange(of: appState.historyShowsExplanation) {
            showsSavedExplanation = appState.historyShowsExplanation
        }
        .onChange(of: appState.current?.id) {
            showsProblemImage = false
            copiedField = nil
            showsSavedExplanation = appState.historyShowsExplanation
        }
    }

    private var isSolving: Bool {
        appState.isSolving
    }

    @ViewBuilder
    private var content: some View {
        switch appState.phase {
        case .idle:
            placeholder("\(appState.hotkey.display) 를 눌러 화면 속 문제를 풀어보세요.")
        case .checkingAccess:
            loading("사용 가능 횟수를 확인하는 중…")
        case .capturing:
            placeholder(
                appState.captureMode == .fullScreen
                    ? "화면을 캡처하는 중…"
                    : "풀이할 영역을 드래그하세요. (Esc 취소)"
            )
        case .solvingAnswer:
            loading("문제를 푸는 중…")
        case .answerReady, .solvingExplanation, .done, .failedExplanation:
            // 해설만 실패한 경우에도 정답은 보존해서 보여준다
            resultBody
        case .failedAnswer(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label("오류", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                Text(message)
                    .font(.callout)
                    .textSelection(.enabled)
                Button("다시 시도") {
                    appState.beginSolve()
                }
            }
        }
    }

    @ViewBuilder
    private var resultBody: some View {
        if let result = appState.current {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(result.preset.displayName)
                    Spacer()
                    Text(result.date, format: .dateTime.year().month().day().hour().minute())
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("정답")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let answer = result.answer {
                            copyButton(text: answer, field: "answer")
                        }
                    }
                    Text(result.answer ?? "—")
                        .font(.title2.bold())
                        .textSelection(.enabled)
                }

                correctnessSection(result)

                Divider()
                explanationSection(result)

                Divider()
                DisclosureGroup("문제 이미지 보기", isExpanded: $showsProblemImage) {
                    if showsProblemImage {
                        problemImageSection(result)
                            .padding(.top, 8)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func problemImageSection(_ result: SolveResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let image = appState.historyImage(for: result) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Label(
                    result.imageFileName == nil ? "저장된 문제 이미지가 없습니다." : "문제 이미지를 불러올 수 없습니다.",
                    systemImage: "photo.badge.exclamationmark"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func correctnessSection(_ result: SolveResult) -> some View {
        HStack(spacing: 8) {
            Text("자가 채점")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            correctnessButton(.correct, selected: result.correctness == .correct)
            correctnessButton(.incorrect, selected: result.correctness == .incorrect)
        }
    }

    private func correctnessButton(_ correctness: SolveCorrectness, selected: Bool) -> some View {
        Button {
            appState.updateCorrectness(correctness)
        } label: {
            Text(correctness == .correct ? "O 정답" : "X 오답")
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(selected ? .white : .secondary)
                .background(
                    selected ? (correctness == .correct ? PaxoStyle.brand : Color.red) : Color.primary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 8)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("내 풀이를 \(correctness.displayName)으로 채점")
        .accessibilityValue(selected ? "선택됨" : "선택 안 됨")
        .help("한 번 더 누르면 채점이 취소됩니다.")
    }

    @ViewBuilder
    private func explanationSection(_ result: SolveResult) -> some View {
        if let explanation = result.explanation {
            if isHistory {
                DisclosureGroup(isExpanded: $showsSavedExplanation) {
                    savedExplanation(explanation)
                        .padding(.top, 8)
                } label: {
                    Text("저장된 해설 보기")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                savedExplanation(explanation)
            }
        } else if appState.phase == .solvingExplanation {
            loading("해설을 작성하는 중…")
        } else if case .failedExplanation(let message) = appState.phase {
            // 정답은 위에 그대로 있고, 해설만 재시도
            VStack(alignment: .leading, spacing: 6) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    appState.requestExplanation()
                } label: {
                    Label("해설 다시 시도", systemImage: "arrow.clockwise")
                }
            }
        } else if appState.canRequestExplanation {
            Button {
                appState.requestExplanation()
            } label: {
                Label("해설 보기", systemImage: "text.book.closed")
            }
        } else {
            Text("이 기록에는 저장된 해설이 없습니다.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func savedExplanation(_ explanation: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("해설")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                copyButton(text: explanation, field: "explanation")
            }
            MarkdownBlocksView(text: explanation)
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func copyButton(text: String, field: String) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copiedField = field
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if copiedField == field { copiedField = nil }
            }
        } label: {
            Image(systemName: copiedField == field ? "checkmark" : "doc.on.doc")
                .foregroundStyle(copiedField == field ? PaxoStyle.brand : Color.secondary)
        }
        .buttonStyle(.plain)
        .help("복사")
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    private func loading(_ text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
