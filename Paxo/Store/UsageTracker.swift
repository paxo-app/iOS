import Foundation

/// 무료 사용량 (하루 N회) 추적. 날짜가 바뀌면 리셋.
///
/// v1은 클라이언트 카운트 + 프록시의 기기별 일일 한도(KV)를 백스톱으로 쓴다.
/// 정식 서버 검증(StoreKit 영수증 JWS를 프록시에서 확인)은 출시 전 TODO.
struct UsageTracker {
    static let dailyFreeLimit = 3

    private let countKey = "usage.count"
    private let dayKey = "usage.day"

    /// 테스트에서 격리된 저장소를 주입하기 위한 지점. 앱에서는 항상 기본값을 쓴다.
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private var today: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    func usedToday() -> Int {
        guard defaults.string(forKey: dayKey) == today else { return 0 }
        return defaults.integer(forKey: countKey)
    }

    func remainingToday() -> Int {
        max(0, Self.dailyFreeLimit - usedToday())
    }

    func recordUse() {
        if defaults.string(forKey: dayKey) != today {
            defaults.set(today, forKey: dayKey)
            defaults.set(0, forKey: countKey)
        }
        defaults.set(defaults.integer(forKey: countKey) + 1, forKey: countKey)
    }
}
