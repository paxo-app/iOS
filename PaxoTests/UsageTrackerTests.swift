import Foundation
import Testing

@testable import Paxo

/// 무료 사용량 차감은 매출에 직결된다. 날짜 롤오버가 깨지면 무제한으로 쓰이거나
/// 반대로 결제한 적 없는 사용자가 조기에 막힌다.
struct UsageTrackerTests {
    /// 매 테스트마다 격리된 UserDefaults. suite 이름이 겹치면 서로 간섭한다.
    private func makeDefaults(_ name: String) throws -> UserDefaults {
        let defaults = try #require(UserDefaults(suiteName: "PaxoTests.\(name).\(UUID().uuidString)"))
        defaults.removePersistentDomain(forName: defaults.description)
        return defaults
    }

    private var today: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    @Test func 초기_상태는_한도_전체가_남는다() throws {
        let tracker = UsageTracker(defaults: try makeDefaults("fresh"))
        #expect(tracker.usedToday() == 0)
        #expect(tracker.remainingToday() == UsageTracker.dailyFreeLimit)
    }

    @Test func 사용할수록_남은_횟수가_줄어든다() throws {
        let tracker = UsageTracker(defaults: try makeDefaults("decrement"))
        for used in 1...UsageTracker.dailyFreeLimit {
            tracker.recordUse()
            #expect(tracker.usedToday() == used)
            #expect(tracker.remainingToday() == UsageTracker.dailyFreeLimit - used)
        }
    }

    /// 한도를 넘겨도 remainingToday가 음수가 되면 안 된다.
    @Test func 한도를_넘겨도_남은_횟수는_0_아래로_안_간다() throws {
        let tracker = UsageTracker(defaults: try makeDefaults("overflow"))
        for _ in 0..<(UsageTracker.dailyFreeLimit + 5) {
            tracker.recordUse()
        }
        #expect(tracker.remainingToday() == 0)
    }

    /// 저장된 날짜가 오늘이 아니면 사용량은 0으로 보여야 한다.
    @Test func 날짜가_바뀌면_사용량이_리셋된다() throws {
        let defaults = try makeDefaults("rollover")
        defaults.set("2020-01-01", forKey: "usage.day")
        defaults.set(UsageTracker.dailyFreeLimit, forKey: "usage.count")

        let tracker = UsageTracker(defaults: defaults)
        #expect(tracker.usedToday() == 0)
        #expect(tracker.remainingToday() == UsageTracker.dailyFreeLimit)
    }

    /// 롤오버 후 첫 사용은 1회여야 한다. 이전 카운트가 이어지면 안 된다.
    @Test func 롤오버_후_첫_사용은_1회로_기록된다() throws {
        let defaults = try makeDefaults("rollover-record")
        defaults.set("2020-01-01", forKey: "usage.day")
        defaults.set(99, forKey: "usage.count")

        let tracker = UsageTracker(defaults: defaults)
        tracker.recordUse()
        #expect(tracker.usedToday() == 1)
        #expect(defaults.string(forKey: "usage.day") == today)
    }

    @Test func 무료_한도는_하루_3회다() {
        #expect(UsageTracker.dailyFreeLimit == 3)
    }
}
