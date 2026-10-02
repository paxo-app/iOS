import Foundation
import Testing

@testable import Paxo

/// 단계 경계가 조용히 바뀌면 "멈춘 것 같은" 대기 화면이 되거나 취소 버튼이 너무 늦게 뜬다.
struct WaitingStageTests {
    @Test(arguments: [
        (-1.0, WaitingStage.reading),
        (0, .reading),
        (2.9, .reading),
        (3, .thinking),
        (7.9, .thinking),
        (8, .finishing),
        (14.9, .finishing),
        (15, .slow),
        (60, .slow),
    ])
    func 정답_대기는_경과_시간에_따라_단계가_바뀐다(elapsed: TimeInterval, expected: WaitingStage) {
        #expect(WaitingStage.answerStage(elapsed: elapsed) == expected)
    }

    @Test(arguments: [
        (0.0, WaitingStage.explaining),
        (14.9, .explaining),
        (15, .slow),
        (90, .slow),
    ])
    func 해설_대기는_오래_걸릴_때만_느림_단계가_된다(elapsed: TimeInterval, expected: WaitingStage) {
        #expect(WaitingStage.explanationStage(elapsed: elapsed) == expected)
    }

    @Test(arguments: WaitingStage.allCases)
    func 모든_단계에_문구와_아이콘이_있다(stage: WaitingStage) {
        #expect(!stage.message.isEmpty)
        #expect(!stage.symbolName.isEmpty)
    }

    /// 취소는 3초부터 연다. 캡처 직후 바로 보이면 실수로 눌러 멀쩡한 요청이 끊긴다.
    /// 정답 대기와 해설 대기가 같은 기준을 쓴다.
    @Test(arguments: [
        (-1.0, false),
        (0, false),
        (2.9, false),
        (3, true),
        (15, true),
        (60, true),
    ])
    func 취소는_3초부터_열린다(elapsed: TimeInterval, expected: Bool) {
        #expect(WaitingStage.allowsCancel(elapsed: elapsed) == expected)
    }

    /// 실제 진행률을 모르므로 곧 끝난다고 약속하는 문구를 쓰지 않는다.
    @Test(arguments: WaitingStage.allCases)
    func 완료를_약속하는_문구가_없다(stage: WaitingStage) {
        #expect(!stage.message.contains("다 됐"))
    }

    /// 오래 걸린다는 설명은 취소와 별개로 15초부터만 보여준다.
    @Test(arguments: WaitingStage.allCases)
    func 설명은_느림_단계에서만_있다(stage: WaitingStage) {
        #expect((stage.detail != nil) == (stage == .slow))
    }
}
