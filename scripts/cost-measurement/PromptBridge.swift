import Foundation

/// 앱의 원본 프롬프트와 정답 표시 규칙을 측정에서도 그대로 사용한다.
@main
enum PromptBridge {
    private struct Input: Decodable {
        let kind: String
        let answer: GeneratedAnswer?
    }

    static func main() throws {
        let input = try JSONDecoder().decode(
            Input.self, from: FileHandle.standardInput.readDataToEndOfFile()
        )
        let prompt: String
        if input.kind == "answer" {
            prompt = Prompts.answer(preset: .general)
        } else if input.kind == "explanation", let answer = input.answer, answer.isValid {
            prompt = Prompts.explanation(
                preset: .general, answer: answer.displayText, context: answer.context
            )
        } else {
            throw CocoaError(.coderInvalidValue)
        }
        FileHandle.standardOutput.write(try JSONEncoder().encode(prompt))
    }
}
