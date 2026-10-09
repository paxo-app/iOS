import Foundation
import Testing

@testable import Paxo

struct ResultFontSizeTests {
    @Test(arguments: [nil, "", "unknown"] as [String?])
    func restoresMissingOrInvalidSettingsToMedium(rawValue: String?) {
        #expect(ResultFontSize.restored(from: rawValue) == .medium)
    }

    @Test(arguments: ResultFontSize.allCases)
    func restoresPersistedValues(size: ResultFontSize) throws {
        let name = "ResultFontSizeTests.\(UUID().uuidString)"
        let writer = try #require(UserDefaults(suiteName: name))
        defer { writer.removePersistentDomain(forName: name) }
        writer.set(size.rawValue, forKey: "resultFontSize")
        let reader = try #require(UserDefaults(suiteName: name))
        #expect(ResultFontSize.restored(from: reader.string(forKey: "resultFontSize")) == size)
    }

    @Test func sizesIncreaseAcrossAllThreeOptions() {
        #expect(ResultFontSize.allCases.map(\.rawValue) == ["small", "medium", "large"])
        #expect(ResultFontSize.small.bodySize < ResultFontSize.medium.bodySize)
        #expect(ResultFontSize.medium.bodySize < ResultFontSize.large.bodySize)
    }
}
