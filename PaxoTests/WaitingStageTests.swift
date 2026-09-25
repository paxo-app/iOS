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

    /// 취소는 오래 걸릴 때만 연다. 처음부터 보이면 누르기 쉬워 멀쩡한 요청이 끊긴다.
    @Test(arguments: WaitingStage.allCases)
    func 취소는_느림_단계에서만_보인다(stage: WaitingStage) {
        #expect(stage.allowsCancel == (stage == .slow))
    }
}
