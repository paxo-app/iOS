import Foundation

/// 2단계 호출 구조:
/// 1) answer — 정답만 짧게 (빠르고 저렴)
/// 2) explanation — 사용자가 해설을 볼 때 생성 (기본 모드에서는 자동 연속 호출)
enum Prompts {
    static func answer(preset: SubjectPreset) -> String {
        """
        당신은 한국어 학습 도우미입니다. 이미지에 있는 문제를 정확히 풀어주세요.
        \(preset.promptHint)
        출력 형식: 정답만 한 줄로 간결하게 출력하세요. 풀이 과정은 다음 단계에서 별도로 요청됩니다.
        - 객관식이면 번호만 (예: ③)
        - 단답형이면 답만
        - 구해야 하는 답이 여러 개면 순서대로 쉼표로 구분 (예: 첫번째답, 두번째답)
        """
    }

    static func explanation(preset: SubjectPreset, answer: String) -> String {
        """
        당신은 친절한 한국어 과외 선생님입니다. 이미지에 있는 문제의 정답은 "\(answer)"입니다.
        \(preset.promptHint)
        학생이 이해할 수 있도록 왜 이 답이 되는지 설명해주세요:
        1. 문제가 묻는 핵심 개념
        2. 단계별 풀이 과정
        3. 헷갈리기 쉬운 포인트 (오답 선택지가 있다면 왜 틀렸는지)
        간결하되 핵심이 빠지지 않게, 읽기 쉬운 짧은 문단으로 작성하세요. 간단한 마크다운(굵게, 목록)을 사용해도 됩니다.
        """
    }
}
