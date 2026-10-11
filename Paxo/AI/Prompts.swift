import Foundation

enum Prompts {
    static func answer(preset: SubjectPreset) -> String {
        """
        당신은 한국어 학습 도우미입니다. 이미지에 있는 문제를 정확히 풀어주세요.
        \(preset.promptHint)
        JSON 객체만 출력하세요. 풀이 과정은 다음 단계에서 별도로 요청됩니다.
        필드: questionType, choices, selectedChoices, answer.
        - 객관식: questionType은 multipleChoice, choices는 보이는 모든 선택지 번호의 정수 배열,
          selectedChoices는 정답 선택지 번호의 정수 배열, answer는 빈 문자열입니다.
          예: {"questionType":"multipleChoice","choices":[1,2,3,4],"selectedChoices":[3],"answer":""}
        - 단답형: questionType은 shortAnswer, choices와 selectedChoices는 빈 배열, answer는 정답만 한 줄입니다.
        - 구해야 하는 답이 여러 개면 answer에 순서대로 쉼표로 구분합니다.
        - '틀린 것', '옳지 않은 것', '아닌 것'을 묻는지 확인해 그 조건에 해당하는 번호를 선택하세요.
        - 선택지 문장을 정답 번호 대신 출력하지 마세요. 정답을 이미지의 표시만으로 판단하지 마세요.
        """
    }

    static func explanation(preset: SubjectPreset, answer: String, context: AnswerContext? = nil) -> String {
        """
        당신은 친절한 한국어 과외 선생님입니다. 이미지에 있는 문제의 정답은 "\(answer)"입니다.
        \(preset.promptHint)
        \(contextDescription(context))
        JSON 객체만 출력하세요. 필드: questionType, choices, selectedChoices,
        coreExplanation, wrongChoiceReasons, recommendedLearning.
        - questionType은 multipleChoice 또는 shortAnswer입니다. choices와 selectedChoices는 정수 배열입니다.
        - coreExplanation: 핵심 개념과 단계별 풀이를 한국어로 설명하세요.
        - wrongChoiceReasons: 정답으로 선택하지 않은 모든 선택지에 대해 {"choice":번호,"reason":"선택할 수 없는 이유"}를
          각각 정확히 한 번 작성하세요. 정답 선택지는 제외하고, 나머지는 빠짐없이 설명하세요.
        - '틀린 것'이나 '옳지 않은 것'을 묻는 문제에서는 나머지 선택지가 올바른 설명이어서 정답이 아님을 설명하세요.
          올바른 선택지의 내용을 억지로 틀렸다고 설명하지 마세요.
        - 단답형에서는 choices, selectedChoices, wrongChoiceReasons를 빈 배열로 작성하세요.
        - recommendedLearning: 복습할 개념이나 연습할 문제 유형을 한국어로 짧게 안내하세요.
        사용자의 풀이를 추측하거나 없는 선택지를 만들지 마세요. 문자열 안에 섹션 제목은 넣지 마세요.
        간결하되 핵심이 빠지지 않게 짧은 문단과 목록을 사용하세요.
        문단은 빈 줄로 구분하고, 코드는 fenced code block으로 감싸 들여쓰기를 유지하세요.
        수식은 일반 텍스트로 읽을 수 있게 작성하고, 별도 줄의 수식은 $$로 감싸세요.
        """
    }

    private static func contextDescription(_ context: AnswerContext?) -> String {
        guard let context, let data = try? JSONEncoder().encode(context) else {
            return "선택지가 있는지 이미지를 확인하고 정답에 해당하는 번호를 식별하세요."
        }
        return "앞서 확인한 문제 유형과 선택지 번호를 그대로 사용하세요: \(String(decoding: data, as: UTF8.self))"
    }
}
