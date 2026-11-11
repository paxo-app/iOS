import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 오답을 문제마다 한 장씩 담아 앱 밖에서도 다시 볼 수 있는 PDF로 만든다.
@MainActor
enum WrongNoteExporter {
    static let pageWidth: CGFloat = 595
    static let minimumPageHeight: CGFloat = 842

    static func pdf(
        items: [SolveResult], image: (SolveResult) -> NSImage?, subjectName: (UUID) -> String?
    ) throws -> Data {
        guard !items.isEmpty else { throw WrongNoteExportError.noItems }
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
            let context = CGContext(consumer: consumer, mediaBox: nil, nil)
        else { throw WrongNoteExportError.renderFailed }
        for (offset, item) in items.enumerated() {
            let page = WrongNotePage(
                item: item, number: offset + 1, total: items.count,
                image: image(item), subjectName: subjectName(item.id)
            )
            let renderer = ImageRenderer(content: page)
            renderer.proposedSize = ProposedViewSize(width: pageWidth, height: nil)
            var didRender = false
            // 해설 길이가 문제마다 달라 쪽을 나누지 않고 내용 높이에 맞춘 한 장으로 그린다.
            renderer.render { size, draw in
                var box = CGRect(origin: .zero, size: size)
                context.beginPage(mediaBox: &box)
                draw(context)
                context.endPage()
                didRender = true
            }
            guard didRender else { throw WrongNoteExportError.renderFailed }
        }
        context.closePDF()
        return data as Data
    }
}

/// 저장 창에 넘길 수 있게 만든 PDF 데이터를 문서로 감싼다.
struct WrongNoteDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.pdf]
    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw WrongNoteExportError.saveFailed }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private struct WrongNotePage: View {
    let item: SolveResult
    let number: Int
    let total: Int
    let image: NSImage?
    let subjectName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Paxo 오답노트").font(.headline)
                Spacer()
                Text("\(number) / \(total)").font(.caption).monospacedDigit()
            }
            HStack(spacing: 6) {
                Text(subjectName ?? "미분류")
                Text("·")
                Text(item.date, format: .dateTime.year().month().day())
                if let count = item.reviewCount, count > 0 {
                    Text("·")
                    Text(item.lastReviewCorrectness == .correct ? "다시 풀어 맞힘" : "다시 풀기 \(count)회")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Divider()
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: imageSize(image).width, height: imageSize(image).height)
            } else {
                Text("저장된 문제 이미지가 없습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("정답").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(item.answer ?? "정답 없음").font(.title3.weight(.semibold))
            }
            if let explanation = item.explanation {
                VStack(alignment: .leading, spacing: 6) {
                    Text("해설").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    MarkdownBlocksView(text: explanation, fontSize: .medium, wrapsWideBlocks: true)
                }
            }
        }
        .padding(40)
        .frame(
            width: WrongNoteExporter.pageWidth, alignment: .topLeading
        )
        .frame(minHeight: WrongNoteExporter.minimumPageHeight, alignment: .top)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    /// 비율을 유지한 실제 크기를 지정해 이미지 위아래에 빈 여백이 생기지 않게 한다.
    private func imageSize(_ image: NSImage) -> CGSize {
        let limit = CGSize(width: WrongNoteExporter.pageWidth - 80, height: 420)
        guard image.size.width > 0, image.size.height > 0 else { return .zero }
        let scale = min(limit.width / image.size.width, limit.height / image.size.height, 1)
        return CGSize(width: image.size.width * scale, height: image.size.height * scale)
    }
}

enum WrongNoteExportError: LocalizedError, Equatable {
    case noItems
    case renderFailed
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .noItems: return "내보낼 오답이 없습니다."
        case .renderFailed: return "오답노트를 만들지 못했습니다. 다시 시도해주세요."
        case .saveFailed: return "오답노트를 저장하지 못했습니다. 저장 위치를 확인해주세요."
        }
    }
}
