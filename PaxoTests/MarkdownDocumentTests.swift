import Foundation
import Testing

@testable import Paxo

/// 표시 형식이 바뀌어도 저장된 해설과 AI가 생성한 원문이 누락되지 않도록 검증한다.
struct MarkdownDocumentTests {
    @Test func preservesParagraphBreaksAndLineBreaks() {
        #expect(
            MarkdownDocument.parse("첫 줄\n이어지는 줄\n\n다음 문단\n\n\n마지막 문단") == [
                .paragraph(text: "첫 줄\n이어지는 줄"),
                .paragraph(text: "다음 문단"),
                .paragraph(text: "마지막 문단"),
            ]
        )
        #expect(String(MarkdownDocument.inline("첫 줄\n이어지는 줄").characters) == "첫 줄\n이어지는 줄")
    }

    @Test func preservesCodeIndentationAndBlankLines() {
        let source = "## 핵심 해설\n```swift\nif ready {\n    work()\n\n    finish()\n}\n```\n설명"
        #expect(
            MarkdownDocument.parse(source) == [
                .heading(level: 2, text: "핵심 해설"),
                .code(text: "if ready {\n    work()\n\n    finish()\n}"),
                .paragraph(text: "설명"),
            ]
        )
    }

    @Test func handlesLongerTildeAndUnclosedFences() {
        #expect(MarkdownDocument.parse("````\n```\n````") == [.code(text: "```")])
        #expect(MarkdownDocument.parse("~~~text\n내용\n~~~") == [.code(text: "내용")])
        #expect(MarkdownDocument.parse("```\n    남은 코드\n\n마지막") == [.code(text: "    남은 코드\n\n마지막")])
    }

    @Test func keepsListContinuationsWithTheirItem() {
        #expect(
            MarkdownDocument.parse("- 첫 항목\n  이어지는 설명\n  - 하위 항목\n10. 다음 항목\n    이어지는 설명\n\n문단") == [
                .listItem(marker: "•", text: "첫 항목\n이어지는 설명", indentation: 0),
                .listItem(marker: "•", text: "하위 항목", indentation: 2),
                .listItem(marker: "10.", text: "다음 항목\n이어지는 설명", indentation: 0),
                .paragraph(text: "문단"),
            ]
        )
    }

    @Test func doesNotMistakeOrdinaryTextForHeadingsOrLists() {
        #expect(MarkdownDocument.parse("#태그\n3.14는 원주율") == [.paragraph(text: "#태그\n3.14는 원주율")])
        #expect(MarkdownDocument.parse("### 소제목 ###") == [.heading(level: 3, text: "소제목")])
    }

    @Test func preservesDisplayFormulas() {
        let source = #"$$x_i + x_j$$"# + "\n\n" + #"\["# + "\nx_i * y_i\n" + #"\]"#
        #expect(
            MarkdownDocument.parse(source) == [
                .formula(text: #"$$x_i + x_j$$"#),
                .formula(text: #"\["# + "\nx_i * y_i\n" + #"\]"#),
            ]
        )
        #expect(MarkdownDocument.parse("$$\nx_i\n$$\n설명") == [.formula(text: "$$\nx_i\n$$"), .paragraph(text: "설명")])
    }

    @Test func preservesInlineMathWithoutLosingSurroundingMarkdown() {
        let result = MarkdownDocument.inline(#"**계산 $x_i * y_i$**과 `a_b` 및 \(x_i\)"#)
        #expect(String(result.characters) == #"계산 $x_i * y_i$과 a_b 및 \(x_i\)"#)
        #expect(result.runs.first?.inlinePresentationIntent?.contains(.stronglyEmphasized) == true)
        #expect(String(MarkdownDocument.inline("**강조 `코드` 유지**").characters) == "강조 코드 유지")
    }

    @Test func groupsKnownSectionsAndOmitsEmptyAlternatives() {
        let source = "## 핵심 해설\n풀이\n\n## 오답인 이유\n\n## 추천 학습 내용\n복습"
        #expect(
            MarkdownDocument.sections(from: source) == [
                .init(kind: .core, blocks: [.paragraph(text: "풀이")]),
                .init(kind: .learning, blocks: [.paragraph(text: "복습")]),
            ]
        )
        #expect(MarkdownDocument.sections(from: "## 오답인 이유\n\n").isEmpty)
        #expect(MarkdownDocument.sections(from: " \n").isEmpty)
    }

    @Test func preservesLegacyUnknownAndDuplicateSections() {
        let source = "기존 설명\n\n### 풀이 과정\n과정\n\n## 핵심 해설\n첫 풀이\n\n## 핵심 해설\n추가 풀이"
        #expect(
            MarkdownDocument.sections(from: source) == [
                .init(
                    kind: .explanation,
                    blocks: [.paragraph(text: "기존 설명"), .heading(level: 3, text: "풀이 과정"), .paragraph(text: "과정")]),
                .init(kind: .core, blocks: [.paragraph(text: "첫 풀이")]),
                .init(kind: .core, blocks: [.paragraph(text: "추가 풀이")]),
            ]
        )
    }

    @Test func ignoresSectionHeadingsInsideCode() {
        let source = "## 핵심 해설\n```markdown\n## 오답인 이유\n```\n\n## 추천 학습 내용\n복습"
        #expect(
            MarkdownDocument.sections(from: source) == [
                .init(kind: .core, blocks: [.code(text: "## 오답인 이유")]),
                .init(kind: .learning, blocks: [.paragraph(text: "복습")]),
            ]
        )
    }

    @Test func normalizesWindowsLineEndings() {
        #expect(
            MarkdownDocument.parse("첫 줄\r\n다음 줄\r\n\r\n마지막") == [
                .paragraph(text: "첫 줄\n다음 줄"), .paragraph(text: "마지막"),
            ])
    }
}
