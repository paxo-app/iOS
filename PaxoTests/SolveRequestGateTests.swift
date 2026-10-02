import Foundation
import Testing

@testable import Paxo

/// 게이트가 늦은 응답을 통과시키면 취소한 풀이가 무료 횟수를 깎거나 다른 문제의 결과를 덮어쓴다.
@MainActor
struct SolveRequestGateTests {
    @Test func 새_요청을_시작하면_이전_요청은_무효가_된다() {
        let gate = SolveRequestGate()
        let first = gate.begin()
        let second = gate.begin()

        #expect(!gate.isCurrent(first))
        #expect(gate.isCurrent(second))
    }

    @Test func 취소하면_날아가던_응답은_버려진다() {
        let gate = SolveRequestGate()
        let id = gate.begin()

        gate.invalidate()

        #expect(!gate.isCurrent(id))
        #expect(!gate.isActive)
    }

    @Test func 늦게_끝난_이전_요청은_새_요청을_지우지_못한다() {
        let gate = SolveRequestGate()
        let old = gate.begin()
        let new = gate.begin()

        gate.finish(old)

        #expect(gate.isCurrent(new))
        #expect(gate.isActive)
    }

    @Test func 자기_요청을_끝내면_비활성이_된다() {
        let gate = SolveRequestGate()
        let id = gate.begin()

        gate.finish(id)

        #expect(!gate.isActive)
    }
}
