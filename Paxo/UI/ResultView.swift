import AppKit
import SwiftUI

struct ResultView: View {
    @EnvironmentObject private var appState: AppState
    @State private var copiedField: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(minWidth: 340, minHeight: 200)
    }

    @ViewBuilder
    private var content: some View {
        switch appState.phase {
        case .idle:
            placeholder("\(appState.hotkey.display) 를 눌러 화면 속 문제를 풀어보세요.")
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

                Divider()
                explanationSection(result)

                HStack {
                    Text(result.preset.displayName)
                    Spacer()
                    Text(result.date, style: .time)
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private func explanationSection(_ result: SolveResult) -> some View {
        if let explanation = result.explanation {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("해설")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    copyButton(text: explanation, field: "explanation")
                }
                ScrollView {
                    MarkdownBlocksView(text: explanation)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
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
                .foregroundStyle(copiedField == field ? Color.green : Color.secondary)
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
