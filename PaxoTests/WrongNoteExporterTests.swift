import AppKit
import Foundation
import PDFKit
import Testing

@testable import Paxo

@MainActor
struct WrongNoteExporterTests {
    private func wrongAnswer(_ answer: String, explanation: String?) -> SolveResult {
        var result = SolveResult(preset: .general)
        result.answer = answer
        result.explanation = explanation
        result.correctness = .incorrect
        return result
    }

    @Test func eachWrongAnswerBecomesOnePageWithItsAnswerText() throws {
        let image = NSImage(size: NSSize(width: 320, height: 180), flipped: false) { rect in
            NSColor.systemBlue.setFill()
            rect.fill()
            return true
        }
        let withImage = wrongAnswer("③", explanation: "## 핵심 해설\n**개방-폐쇄 원칙(OCP)**을 묻는 문제다.\n\n```\nlet x = 1\n```")
        let withoutImage = wrongAnswer("42", explanation: nil)

        let data = try WrongNoteExporter.pdf(
            items: [withImage, withoutImage],
            image: { $0.id == withImage.id ? image : nil },
            subjectName: { _ in "소프트웨어 설계" }
        )
        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount == 2)
        // PDF에서 꺼낸 한글은 띄어쓰기가 빠질 수 있어 공백을 지우고 비교한다.
        let firstPage = try #require(document.page(at: 0)?.string).filter { !$0.isWhitespace }
        #expect(firstPage.contains("소프트웨어설계"))
        #expect(firstPage.contains("letx=1"))
        let secondPage = try #require(document.page(at: 1)?.string).filter { !$0.isWhitespace }
        #expect(secondPage.contains("42"))
        #expect(secondPage.contains("저장된문제이미지가없습니다."))
    }

    @Test func emptyListIsRejectedInsteadOfSavingBlankFile() {
        #expect(throws: WrongNoteExportError.noItems) {
            try WrongNoteExporter.pdf(items: [], image: { _ in nil }, subjectName: { _ in nil })
        }
    }
}
