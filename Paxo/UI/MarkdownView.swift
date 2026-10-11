import SwiftUI

/// 문단의 호흡을 유지하고 너비가 긴 코드와 수식만 별도로 스크롤한다.
struct MarkdownBlocksView: View {
    let blocks: [MarkdownDocument.Block]
    var fontSize: ResultFontSize = .medium

    init(text: String, fontSize: ResultFontSize = .medium) {
        self.blocks = MarkdownDocument.parse(text)
        self.fontSize = fontSize
    }

    init(blocks: [MarkdownDocument.Block], fontSize: ResultFontSize = .medium) {
        self.blocks = blocks
        self.fontSize = fontSize
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .font(fontSize.bodyFont)
        .lineSpacing(fontSize.lineSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func view(for block: MarkdownDocument.Block) -> some View {
        switch block {
        case .heading(let level, let text):
            prose(text)
                .font(fontSize.headingFont(level: level))
                .padding(.top, 4)
                .accessibilityAddTraits(.isHeader)
        case .listItem(let marker, let text, let indentation):
            HStack(alignment: .top, spacing: 8) {
                Text(marker)
                    .fixedSize()
                prose(text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, CGFloat(min(indentation, 12)) * 4)
        case .paragraph(let text):
            prose(text)
        case .code(let text), .formula(let text):
            ScrollView(.horizontal) {
                Text(verbatim: text)
                    .font(fontSize.codeFont)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(12)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel(block.isCode ? "코드" : "수식")
        case .divider:
            Divider()
        }
    }

    private func prose(_ text: String) -> some View {
        Text(MarkdownDocument.inline(text))
            .fixedSize(horizontal: false, vertical: true)
    }
}

private extension MarkdownDocument.Block {
    var isCode: Bool {
        if case .code = self { return true }
        return false
    }
}

/// 제목이 없는 기존 기록은 일반 해설 카드로 표시한다.
struct ExplanationView: View {
    let text: String
    let fontSize: ResultFontSize

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(MarkdownDocument.sections(from: text).enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: 12) {
                    Label(section.kind.rawValue, systemImage: section.kind.symbolName)
                        .font(fontSize.titleFont)
                        .accessibilityAddTraits(.isHeader)
                    MarkdownBlocksView(blocks: section.blocks, fontSize: fontSize)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
