import Foundation

/// AI 응답과 과거 기록을 같은 규칙으로 읽으며 알 수 없는 내용도 본문으로 보존한다.
enum MarkdownDocument {
    enum Block: Equatable {
        case heading(level: Int, text: String)
        case listItem(marker: String, text: String, indentation: Int)
        case paragraph(text: String)
        case code(text: String)
        case formula(text: String)
        case divider
    }

    enum SectionKind: String, CaseIterable {
        case explanation = "해설"
        case core = "핵심 해설"
        case alternatives = "오답인 이유"
        case learning = "추천 학습 내용"

        var symbolName: String {
            switch self {
            case .explanation: return "text.book.closed"
            case .core: return "lightbulb"
            case .alternatives: return "questionmark.circle"
            case .learning: return "book"
            }
        }
    }

    struct Section: Equatable {
        var kind: SectionKind
        var blocks: [Block]
    }

    static func sections(from text: String) -> [Section] {
        var sections: [Section] = []
        var current = Section(kind: .explanation, blocks: [])
        for block in parse(text) {
            if case .heading(let level, let title) = block, level == 2,
                let kind = SectionKind(rawValue: title), kind != .explanation
            {
                if !current.blocks.isEmpty { sections.append(current) }
                current = Section(kind: kind, blocks: [])
            } else {
                current.blocks.append(block)
            }
        }
        if !current.blocks.isEmpty { sections.append(current) }
        return sections
    }

    static func parse(_ text: String) -> [Block] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        var blocks: [Block] = []
        var paragraph: [String] = []
        var index = 0

        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(text: paragraph.joined(separator: "\n")))
                paragraph.removeAll()
            }
        }

        while index < lines.count {
            let rawLine = lines[index]
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            if let fence = openingFence(line) {
                flushParagraph()
                index += 1
                var content: [String] = []
                // 응답이 중간에 끝나 닫는 fence가 없어도 코드 본문을 잃지 않는다.
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    if candidate.count >= fence.count, candidate.allSatisfy({ $0 == fence.character }) {
                        index += 1
                        break
                    }
                    content.append(lines[index])
                    index += 1
                }
                blocks.append(.code(text: content.joined(separator: "\n")))
                continue
            }

            if let closing = formulaClosing(for: line) {
                flushParagraph()
                var content = [rawLine]
                index += 1
                if !(line.count > 2 && line.hasSuffix(closing)) {
                    while index < lines.count {
                        let next = lines[index]
                        content.append(next)
                        index += 1
                        if next.trimmingCharacters(in: .whitespaces).hasSuffix(closing) { break }
                    }
                }
                blocks.append(.formula(text: content.joined(separator: "\n")))
                continue
            }

            if let heading = heading(line) {
                flushParagraph()
                blocks.append(.heading(level: heading.level, text: heading.text))
            } else if ["---", "***", "___"].contains(line) {
                flushParagraph()
                blocks.append(.divider)
            } else if let item = listPrefix(rawLine) {
                flushParagraph()
                var content = [item.text]
                index += 1
                while index < lines.count {
                    let next = lines[index]
                    let trimmed = next.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty, indentation(of: next) > item.indentation,
                        listPrefix(next) == nil, heading(trimmed) == nil,
                        openingFence(trimmed) == nil, formulaClosing(for: trimmed) == nil
                    else { break }
                    content.append(trimmed)
                    index += 1
                }
                blocks.append(
                    .listItem(
                        marker: item.marker, text: content.joined(separator: "\n"), indentation: item.indentation
                    )
                )
                continue
            } else {
                paragraph.append(rawLine)
            }
            index += 1
        }
        flushParagraph()
        return blocks
    }

    /// 수식 안의 밑줄과 별표가 Markdown 강조로 해석되지 않게 원문을 보존한다.
    static func inline(_ text: String) -> AttributedString {
        let pattern = #"`+[^`\n]*`+|\$[^$\n]+\$|\\\([^\n]*?\\\)"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return markdown(text) }
        let prefix = "\u{E000}\(UUID().uuidString)"
        var replacements: [(token: String, formula: String)] = []
        var protected = ""
        var start = text.startIndex
        for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            protected += text[start..<range.lowerBound]
            let fragment = String(text[range])
            if fragment.hasPrefix("`") {
                protected += fragment
            } else {
                let token = "\(prefix)\(replacements.count)\u{E001}"
                protected += token
                replacements.append((token, fragment))
            }
            start = range.upperBound
        }
        protected += text[start...]
        var result = markdown(protected)
        for replacement in replacements {
            guard let range = result.range(of: replacement.token) else { continue }
            let attributes = result[range].runs.first?.attributes ?? AttributeContainer()
            result.replaceSubrange(range, with: AttributedString(replacement.formula, attributes: attributes))
        }
        return result
    }

    private static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }

    private static func openingFence(_ line: String) -> (character: Character, count: Int)? {
        guard let character = line.first, character == "`" || character == "~" else { return nil }
        let count = line.prefix(while: { $0 == character }).count
        return count >= 3 ? (character, count) : nil
    }

    private static func formulaClosing(for line: String) -> String? {
        if line.hasPrefix("$$") { return "$$" }
        if line.hasPrefix(#"\["#) { return #"\]"# }
        return nil
    }

    private static func heading(_ line: String) -> (level: Int, text: String)? {
        let level = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(level) else { return nil }
        let rest = line.dropFirst(level)
        guard rest.first?.isWhitespace == true else { return nil }
        var title = rest.trimmingCharacters(in: .whitespaces)
        if let closing = title.range(of: #"\s+#+$"#, options: .regularExpression) {
            title.removeSubrange(closing)
        }
        return (level, title)
    }

    private static func indentation(of line: String) -> Int {
        line.prefix(while: { $0 == " " || $0 == "\t" }).reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
    }

    private static func listPrefix(_ rawLine: String) -> (marker: String, text: String, indentation: Int)? {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        let indent = indentation(of: rawLine)
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") || line.hasPrefix("• ") {
            return ("•", String(line.dropFirst(2)), indent)
        }
        let digits = line.prefix(while: { $0.isNumber })
        let rest = line.dropFirst(digits.count)
        guard !digits.isEmpty, let separator = rest.first, separator == "." || separator == ")",
            rest.dropFirst().first?.isWhitespace == true
        else { return nil }
        return (
            String(digits) + String(separator), rest.dropFirst().trimmingCharacters(in: .whitespaces), indent
        )
    }
}
