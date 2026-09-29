import Foundation
import Testing

@testable import Paxo

/// 토스트의 원은 실제 진행률이 아니라 추정치다. 답이 오기 전에 가득 차거나 뒤로 가면
/// "다 됐는데 왜 안 나오지"라는 오해를 만든다.
struct WaitingProgressTests {
    @Test(arguments: [0.0, -1, -100])
    func 시작_전에는_비어_있다(elapsed: TimeInterval) {
        #expect(WaitingProgress.estimatedFraction(elapsed: elapsed) == 0)
    }

    /// 아주 긴 시간에서는 Double 반올림으로 정확히 상한과 같아질 수 있어 이하로 본다.
    @Test(arguments: [0.1, 1, 3, 8, 15, 60, 600, 1_000_000])
    func 상한을_넘지_않는다(elapsed: TimeInterval) {
        let fraction = WaitingProgress.estimatedFraction(elapsed: elapsed)
        #expect(fraction >= 0)
        #expect(fraction <= WaitingProgress.ceiling)
    }

    @Test func 시간이_지날수록_줄지_않는다() {
        let samples = stride(from: 0.0, through: 120, by: 0.5).map {
            WaitingProgress.estimatedFraction(elapsed: $0)
        }
        for (earlier, later) in zip(samples, samples.dropFirst()) {
            #expect(later >= earlier)
        }
    }

    /// 처음엔 빠르게, 점점 느리게 찬다. 곡선을 바꾸면 이 값도 함께 바꾼다.
    @Test(arguments: [(3.0, 0.41), (8, 0.72), (15, 0.86)])
    func 주요_시점의_진행률(elapsed: TimeInterval, expected: Double) {
        #expect(abs(WaitingProgress.estimatedFraction(elapsed: elapsed) - expected) < 0.01)
    }
}
