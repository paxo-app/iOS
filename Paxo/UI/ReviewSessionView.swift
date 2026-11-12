import SwiftUI

/// 시작할 때의 오답 목록을 고정해, 채점할 때마다 순서가 바뀌어 문제를 건너뛰지 않게 한다.
struct ReviewSessionView: View {
    @EnvironmentObject private var appState: AppState
    let title: String
    let subjectName: (UUID) -> String?
    let onClose: () -> Void
    @State private var queue: [SolveResult]
    @State private var index = 0
    @State private var isRevealed = false
    @State private var recoveredCount = 0
    @State private var skippedCount = 0
    @State private var lastFeedback: String?

    /// 첫 화면부터 문제가 보이도록 목록을 생성 시점에 받는다.
    init(
        title: String = "오답 다시 풀기", queue: [SolveResult],
        subjectName: @escaping (UUID) -> String? = { _ in nil }, onClose: @escaping () -> Void
    ) {
        self.title = title
        self.subjectName = subjectName
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
                Text(title).font(.title2.bold())
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
            if let lastFeedback {
                Label(lastFeedback, systemImage: "calendar.badge.clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        Text(subjectName(item.id) ?? "미분류")
                        Text("·")
                        Text(item.date, format: .dateTime.month().day())
                        Text("에 틀린 문제")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                    Button("또 틀렸어요") { grade(.again, item) }
                        .help("내일 다시 나옵니다.")
                    Button("헷갈렸어요") { grade(.hard, item) }
                        .help("맞혔지만 확신이 없었다면 고르세요. 비슷한 간격으로 다시 나옵니다.")
                    Button("맞았어요") { grade(.good, item) }
                        .help("간격을 늘려 다시 나옵니다.")
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
                    Button("건너뛰기") { skip() }
                        .help("기록을 남기지 않고 다음 문제로 넘어갑니다.")
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
            Text(queue.isEmpty ? "지금 복습할 문제가 없어요" : "\(queue.count)문제 중 \(recoveredCount)문제를 맞혔어요")
                .font(.callout.weight(.medium))
            Text(
                queue.isEmpty
                    ? "오답으로 표시한 문제는 다음 날부터 복습 차례가 됩니다."
                    : skippedCount > 0
                        ? "맞힌 문제는 간격을 늘려, 틀린 문제는 내일 다시 나옵니다. 건너뛴 \(skippedCount)문제는 그대로 남아 있습니다."
                        : "맞힌 문제는 간격을 늘려, 틀린 문제는 내일 다시 나옵니다."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Button("완료", action: onClose)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func grade(_ grade: ReviewGrade, _ item: SolveResult) {
        // 세션 도중 삭제된 기록은 저장하지 않고 다음 문제로 넘어간다.
        if let outcome = appState.recordReview(grade, for: item.id) {
            if grade != .again { recoveredCount += 1 }
            lastFeedback =
                outcome.isRetired
                ? "방금 문제는 복습을 마쳤어요. 더 나오지 않아요."
                : "방금 문제는 \(outcome.intervalDays)일 뒤에 다시 나와요."
        } else {
            lastFeedback = nil
        }
        isRevealed = false
        index += 1
    }

    private func skip() {
        lastFeedback = nil
        skippedCount += 1
        isRevealed = false
        index += 1
    }
}
