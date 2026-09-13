import Testing

@testable import Paxo

/// 프롬프트가 조용히 깨지면 앱은 정상 동작하는데 답만 이상해진다.
/// 프록시는 text 파트를 8000자로 제한하므로 길이도 함께 지킨다.
struct PromptsTests {
    /// `.general`의 promptHint는 의도적으로 비어 있다. Swift에서 contains("")는 false이므로
    /// 빈 힌트는 삽입 여부를 검사할 수 없다.
    @Test(arguments: SubjectPreset.allCases)
    func 정답_프롬프트에_프리셋_힌트가_들어간다(preset: SubjectPreset) {
        let prompt = Prompts.answer(preset: preset)
        #expect(!prompt.isEmpty)
        if !preset.promptHint.isEmpty {
            #expect(prompt.contains(preset.promptHint))
        }
    }

    @Test(arguments: SubjectPreset.allCases)
    func 해설_프롬프트에_정답이_삽입된다(preset: SubjectPreset) {
        let answer = "③"
        let prompt = Prompts.explanation(preset: preset, answer: answer)
        #expect(prompt.contains(answer))
        if !preset.promptHint.isEmpty {
            #expect(prompt.contains(preset.promptHint))
        }
    }

    /// 1단계는 정답만 받는다. 여기서 풀이까지 요구하면 2단계 구조가 무의미해진다.
    @Test func 정답_프롬프트는_한_줄_출력을_요구한다() {
        let prompt = Prompts.answer(preset: .general)
        #expect(prompt.contains("한 줄"))
    }

    @Test(arguments: SubjectPreset.allCases)
    func 프롬프트가_프록시_길이_제한_안에_들어온다(preset: SubjectPreset) {
        let limit = 8000
        #expect(Prompts.answer(preset: preset).count < limit)
        #expect(Prompts.explanation(preset: preset, answer: String(repeating: "가", count: 200)).count < limit)
    }
}
