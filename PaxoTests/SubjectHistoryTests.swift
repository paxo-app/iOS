import Foundation
import Testing

@testable import Paxo

struct SubjectHistoryTests {
    @Test func legacyPresetsMigrateOnceWithoutChangingHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let historyStore = HistoryStore(baseURL: directory)
        let subjectStore = SubjectStore(baseURL: directory)
        let math = SolveResult(preset: .math)
        let license = SolveResult(preset: .licenseExam)
        let general = SolveResult(preset: .general)
        historyStore.save([math, license, general])

        var catalog = try subjectStore.load(migrating: historyStore.load())
        #expect(catalog.subject(for: math.id)?.name == "수학")
        #expect(catalog.subject(for: license.id)?.name == "자격시험")
        #expect(catalog.subject(for: general.id) == nil)
        #expect(Set(historyStore.load().map(\.id)) == Set([math.id, license.id, general.id]))

        let mathID = try #require(catalog.subject(for: math.id)?.id)
        try catalog.delete(mathID)
        try subjectStore.save(catalog)
        let reopened = try subjectStore.load(migrating: historyStore.load())
        #expect(reopened.subject(for: math.id) == nil)
        #expect(reopened.subjects.count == 1)
        #expect(historyStore.load().count == 3)
    }

    @Test func createRenameAssignDeleteAndPersist() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SubjectStore(baseURL: directory)
        let resultID = UUID()
        var catalog = try store.load(migrating: [])
        try catalog.create("  물리  ")
        let subjectID = try #require(catalog.subjects.first?.id)
        try catalog.assign(subjectID, to: resultID)
        try catalog.rename(subjectID, to: "과학")
        try catalog.create("영어")
        let secondSubjectID = try #require(catalog.subjects.last?.id)
        try catalog.assign(secondSubjectID, to: resultID)
        #expect(catalog.subject(for: resultID)?.name == "영어")
        try catalog.assign(subjectID, to: resultID)
        try store.save(catalog)
        var reopened = try store.load(migrating: [])
        #expect(reopened.subject(for: resultID)?.name == "과학")
        #expect(throws: SubjectError.self) { try reopened.create("과학") }
        #expect(throws: SubjectError.self) { try reopened.create("  ") }
        #expect(throws: SubjectError.self) { try reopened.create("미분류") }
        try reopened.delete(subjectID)
        try store.save(reopened)
        #expect(try store.load(migrating: []).subject(for: resultID) == nil)
    }

    @Test func freeVisibilityAndSearchCannotExposeOlderSubjects() throws {
        let items = (0..<12).map { offset -> SolveResult in
            var result = SolveResult(preset: .general)
            result.date = Date(timeIntervalSince1970: TimeInterval(12 - offset))
            result.answer = "답 \(offset)"
            return result
        }
        var catalog = SubjectCatalog.migrated(from: [])
        try catalog.create("수학")
        let subjectID = try #require(catalog.subjects.first?.id)
        try catalog.assign(subjectID, to: items[11].id)

        #expect(HistoryBrowser.visible(items.reversed(), tier: .free).map(\.id) == items.prefix(10).map(\.id))
        #expect(HistoryBrowser.visible(items, tier: .free).count == 10)
        #expect(HistoryBrowser.visible(items, tier: .pro).count == 12)
        #expect(HistoryBrowser.recent(items, tier: .free, requestedCount: 100).count == 10)
        #expect(HistoryBrowser.recent(items, tier: .pro, requestedCount: 5).count == 5)
        let freeMatches = HistoryBrowser.filter(HistoryBrowser.visible(items, tier: .free), query: "수학")
        #expect(freeMatches.isEmpty)
        let proMatches = HistoryBrowser.filter(
            items, query: "수학",
            subjectName: { id in
                catalog.subject(for: id)?.name
            })
        #expect(proMatches.map(\.id) == [items[11].id])
    }

    @Test func downgradeClosesOnlyHistoryOutsideFreeRange() {
        let items = (0..<12).map { offset -> SolveResult in
            var result = SolveResult(preset: .general)
            result.date = Date(timeIntervalSince1970: TimeInterval(12 - offset))
            return result
        }

        #expect(!HistoryBrowser.shouldClose(activeResultID: nil, items: items, tier: .free))
        #expect(!HistoryBrowser.shouldClose(activeResultID: items[11].id, items: items, tier: .pro))
        #expect(HistoryBrowser.shouldClose(activeResultID: items[11].id, items: items, tier: .free))
        #expect(!HistoryBrowser.shouldClose(activeResultID: items[0].id, items: items, tier: .free))
    }

    @Test func groupingAndSubjectDeletionKeepRecordsAndImages() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let historyStore = HistoryStore(baseURL: directory)
        let subjectStore = SubjectStore(baseURL: directory)
        var first = SolveResult(preset: .general)
        let second = SolveResult(preset: .general)
        let image = Data("jpeg".utf8)
        first.imageFileName = historyStore.saveImage(image, for: first.id)
        historyStore.save([first, second])
        var catalog = try subjectStore.load(migrating: historyStore.load())
        try catalog.create("수학")
        let subjectID = try #require(catalog.subjects.first?.id)
        try catalog.assign(subjectID, to: first.id)
        #expect(HistoryBrowser.subjects(historyStore.load(), catalog: catalog).map(\.name) == ["수학", "미분류"])
        try catalog.delete(subjectID)
        try subjectStore.save(catalog)
        #expect(HistoryBrowser.subjects(historyStore.load(), catalog: catalog).map(\.name) == ["미분류"])
        #expect(historyStore.load().count == 2)
        #expect(historyStore.loadImage(for: first) == image)
    }
}
