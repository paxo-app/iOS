import AppKit
import Foundation

/// 실제 사용자 자료를 보내지 않고 측정할 수 있도록 직접 작성한 합성 문제를 이미지로 만든다.
struct CostProblem: Decodable {
    let id: String
    let category: String
    let text: String
    let expectedAnswer: String
}

enum FixtureRenderError: LocalizedError {
    case invalidArguments
    case invalidProblems
    case bitmapUnavailable
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            return "사용법: swift scripts/cost-fixtures.swift <문제 JSON 경로> <이미지 출력 디렉터리>"
        case .invalidProblems:
            return "문제 목록이 비어 있거나 식별자·문제·정답 형식이 올바르지 않습니다."
        case .bitmapUnavailable:
            return "문제 이미지를 그릴 메모리를 준비하지 못했습니다."
        case .encodingFailed:
            return "문제 이미지를 JPEG로 변환하지 못했습니다."
        }
    }
}

enum FixtureRenderer {
    private static let canvasWidth: CGFloat = 1400
    private static let margin: CGFloat = 64
    private static let maximumDimension: CGFloat = 2000

    static func render(_ problem: CostProblem, index: Int, to outputDirectory: URL) throws {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 9
        paragraph.paragraphSpacing = 12
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 30),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph,
        ]
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22, weight: .medium),
            .foregroundColor: NSColor.darkGray,
        ]
        let bodyWidth = canvasWidth - 2 * margin
        let body = NSAttributedString(string: problem.text, attributes: textAttributes)
        let bodyHeight = ceil(
            body.boundingRect(
                with: NSSize(width: bodyWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            ).height
        )
        let titleHeight: CGFloat = 32
        let titleGap: CGFloat = 28
        let canvasHeight = max(420, margin * 2 + titleHeight + titleGap + bodyHeight)
        let scale = min(1, maximumDimension / max(canvasWidth, canvasHeight))
        let pixelWidth = Int(ceil(canvasWidth * scale))
        let pixelHeight = Int(ceil(canvasHeight * scale))
        guard
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixelWidth,
                pixelsHigh: pixelHeight,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 32
            ), let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else {
            throw FixtureRenderError.bitmapUnavailable
        }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: scale, y: scale)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight).fill()
        let title = "측정용 합성 문제 \(index + 1) · \(problem.category)"
        (title as NSString).draw(
            in: NSRect(
                x: margin, y: canvasHeight - margin - titleHeight, width: bodyWidth, height: titleHeight
            ),
            withAttributes: titleAttributes
        )
        body.draw(
            with: NSRect(x: margin, y: margin, width: bodyWidth, height: bodyHeight),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        // 앱의 캡처 인코딩 조건과 맞춰 이미지 크기가 비용 차이를 만들지 않게 한다.
        guard let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.82]) else {
            throw FixtureRenderError.encodingFailed
        }
        try jpeg.write(to: outputDirectory.appendingPathComponent(problem.id + ".jpg"), options: .atomic)
    }
}

do {
    let arguments = CommandLine.arguments
    guard arguments.count == 3 else { throw FixtureRenderError.invalidArguments }
    let inputURL = URL(fileURLWithPath: arguments[1])
    let outputDirectory = URL(fileURLWithPath: arguments[2], isDirectory: true)
    let problems = try JSONDecoder().decode([CostProblem].self, from: Data(contentsOf: inputURL))
    guard !problems.isEmpty,
        Set(problems.map(\.id)).count == problems.count,
        problems.allSatisfy({
            $0.id.range(of: "^[a-z0-9]+(?:-[a-z0-9]+)*$", options: .regularExpression) != nil
                && !$0.category.isEmpty && !$0.text.isEmpty && !$0.expectedAnswer.isEmpty
        })
    else { throw FixtureRenderError.invalidProblems }
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    for (index, problem) in problems.enumerated() {
        try FixtureRenderer.render(problem, index: index, to: outputDirectory)
    }
} catch {
    let detail =
        (error as? FixtureRenderError)?.errorDescription
        ?? "문제 JSON 형식과 파일 읽기·쓰기 권한을 확인해주세요."
    let message = "문제 이미지 생성 실패: \(detail)\n"
    FileHandle.standardError.write(Data(message.utf8))
    exit(1)
}
