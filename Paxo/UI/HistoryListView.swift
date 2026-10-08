import AppKit
import SwiftUI

/// 메뉴와 설정의 기록 보관함이 동일한 카드와 빈 상태를 사용한다.
struct HistoryListView: View {
    let items: [SolveResult]
    let showsExplanation: Bool
    var showsThumbnail = true
    var isBusy = false
    let onSelect: (SolveResult) -> Void

    var body: some View {
        if items.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("아직 풀이 기록이 없어요")
                    .font(.callout.weight(.medium))
                Text("문제를 풀면 이미지와 해설이 여기에 저장됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(items) { item in
                        Button {
                            onSelect(item)
                        } label: {
                            HistoryCard(item: item, showsExplanation: showsExplanation, showsThumbnail: showsThumbnail)
                        }
                        .buttonStyle(.plain)
                        .disabled(isBusy)
                    }
                }
            }
        }
    }
}

struct HistoryCard: View {
    let item: SolveResult
    var showsExplanation = true
    var showsThumbnail = true
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                correctnessBadge
                Spacer(minLength: 4)
                Text(item.date, format: .dateTime.year().month(.twoDigits).day(.twoDigits).hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack(alignment: .top, spacing: 10) {
                if showsThumbnail {
                    HistoryThumbnail(item: item)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.answer ?? "정답 없음")
                        .font(.callout.weight(.semibold))
                        .lineLimit(2)
                    if showsExplanation {
                        Text(item.explanationSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.primary.opacity(isHovered ? 0.09 : 0.045),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onHover { isHovered = $0 }
    }

    private var correctnessBadge: some View {
        let title = item.correctness.map { $0 == .correct ? "O 정답" : "X 오답" } ?? "미채점"
        let color: Color =
            switch item.correctness {
            case .correct: PaxoStyle.brand
            case .incorrect: .red
            case nil: .secondary
            }
        return Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }
}

private struct HistoryThumbnail: View {
    let item: SolveResult
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: item.imageFileName == nil ? "photo" : "photo.badge.exclamationmark")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 52, height: 48)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityLabel(image == nil ? "저장된 이미지 없음" : "문제 이미지")
        .task(id: item.imageFileName) {
            image = nil
            let data = await Task.detached(priority: .utility) {
                HistoryStore().loadImage(for: item)
            }.value
            guard !Task.isCancelled else { return }
            image = data.flatMap { NSImage(data: $0) }
        }
    }
}
