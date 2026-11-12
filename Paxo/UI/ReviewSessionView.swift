import SwiftUI

/// 시작할 때의 오답 목록을 고정해, 채점할 때마다 순서가 바뀌어 문제를 건너뛰지 않게 한다.
struct ReviewSessionView: View {
    @EnvironmentObject private var appState: AppState
    let onClose: () -> Void
    @State private var queue: [SolveResult]
    @State private var index = 0
    @State private var isRevealed = false
    @State private var recoveredCount = 0

    /// 첫 화면부터 문제가 보이도록 목록을 생성 시점에 받는다.
    init(queue: [SolveResult], onClose: @escaping () -> Void) {
        self.onClose = onClose
        _queue = State(initialValue: queue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if index < queue.count {
                problem(queue[index])
            } else {
                summary
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onClose) {
                Label("풀이 기록으로", systemImage: "chevron.left")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            HStack {
                Text("오답 다시 풀기").font(.title2.bold())
                Spacer()
                if index < queue.count {
                    Text("\(index + 1) / \(queue.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    private func problem(_ item: SolveResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    problemImage(item)
                    if isRevealed {
                        answer(item)
                    } else {
                        Text("정답과 해설을 가렸습니다. 먼저 직접 풀어 보세요.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            if isRevealed {
                HStack(spacing: 8) {
                    Text("다시 풀어 보니").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("또 틀렸어요") { grade(.incorrect, item) }
                    Button("맞았어요") { grade(.correct, item) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            } else {
                HStack {
                    if let count = item.reviewCount, count > 0 {
                        Text("지금까지 \(count)번 다시 풀었어요")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("정답 보기") { isRevealed = true }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    @ViewBuilder
    private func problemImage(_ item: SolveResult) -> some View {
        if let image = appState.historyImage(for: item) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel("문제 이미지")
        } else {
            Label("문제 이미지를 불러올 수 없습니다.", systemImage: "photo.badge.exclamationmark")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func answer(_ item: SolveResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("정답").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(item.answer ?? "정답 없음")
                .font(.title3.weight(.semibold))
                .textSelection(.enabled)
            if let explanation = item.explanation {
                Divider()
                MarkdownBlocksView(text: explanation, fontSize: appState.resultFontSize)
            }
        }
    }

    private var summary: some View {
        VStack(spacing: 10) {
            Image(systemName: queue.isEmpty ? "checkmark.circle" : "flag.checkered")
                .font(.largeTitle)
                .foregroundStyle(PaxoStyle.brand)
            Text(queue.isEmpty ? "다시 풀 오답이 없어요" : "\(queue.count)문제 중 \(recoveredCount)문제를 다시 맞혔어요")
                .font(.callout.weight(.medium))
            Text(
                queue.isEmpty
                    ? "기록에서 오답으로 표시한 문제가 여기에 모입니다."
                    : "또 틀린 문제는 다음 다시 풀기에 남아 있습니다."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Button("완료", action: onClose)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func grade(_ correctness: SolveCorrectness, _ item: SolveResult) {
        // 세션 도중 삭제된 기록은 저장하지 않고 다음 문제로 넘어간다.
        if appState.recordReview(correctness, for: item.id), correctness == .correct {
            recoveredCount += 1
        }
        isRevealed = false
        index += 1
    }
}
