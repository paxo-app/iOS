import SwiftUI

/// LLM이 출력하는 가벼운 마크다운(제목, 목록, 굵게)을 블록 단위로 렌더링한다.
/// AttributedString(markdown:)만으로는 제목/목록/문단 줄바꿈이 살지 않아 직접 블록을 나눈다.
struct MarkdownBlocksView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
    }

    private enum Block {
        case heading(level: Int, text: String)
        case bullet(text: String)
        case numbered(marker: String, text: String)
        case paragraph(text: String)
    }

    private var blocks: [Block] {
        text.split(separator: "\n", omittingEmptySubsequences: true).map { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("#") {
                let level = line.prefix(while: { $0 == "#" }).count
                let content = line.drop(while: { $0 == "#" })
                    .trimmingCharacters(in: .whitespaces)
                return .heading(level: min(level, 3), text: content)
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
                return .bullet(text: String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces))
            }
            if let (marker, rest) = numberedPrefix(line) {
                return .numbered(marker: marker, text: rest)
            }
            return .paragraph(text: line)
        }
    }

    @ViewBuilder
    private func view(for block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(level == 1 ? .title3.bold() : .headline)
                .padding(.top, 2)
        case .bullet(let text):
            HStack(alignment: .top, spacing: 6) {
                Text("•")
                Text(inline(text))
            }
        case .numbered(let marker, let text):
            HStack(alignment: .top, spacing: 6) {
                Text(marker)
                Text(inline(text))
            }
        case .paragraph(let text):
            Text(inline(text))
        }
    }

    /// 한 줄 안의 **굵게**, *기울임*, `코드` 처리
    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }

    /// "1." / "2)" 같은 번호 목록 접두사 감지
    private func numberedPrefix(_ line: String) -> (String, String)? {
        var digits = ""
        var index = line.startIndex
        while index < line.endIndex, line[index].isNumber {
            digits.append(line[index])
            index = line.index(after: index)
        }
        guard !digits.isEmpty, index < line.endIndex,
              line[index] == "." || line[index] == ")" else { return nil }
        let marker = digits + String(line[index])
        let rest = line[line.index(after: index)...].trimmingCharacters(in: .whitespaces)
        guard !rest.isEmpty else { return nil }
        return (marker, rest)
    }
}
