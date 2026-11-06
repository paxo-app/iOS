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
        try historyStore.save([math, license, general])

        var catalog = try subjectStore.load(migrating: try historyStore.load())
        #expect(catalog.subject(for: math.id)?.name == "수학")
        #expect(catalog.subject(for: license.id)?.name == "자격시험")
        #expect(catalog.subject(for: general.id) == nil)
        #expect(Set(try historyStore.load().map(\.id)) == Set([math.id, license.id, general.id]))

        let mathID = try #require(catalog.subject(for: math.id)?.id)
        try catalog.delete(mathID)
        try subjectStore.save(catalog)
        let reopened = try subjectStore.load(migrating: try historyStore.load())
        #expect(reopened.subject(for: math.id) == nil)
        #expect(reopened.subjects.count == 1)
        #expect(try historyStore.load().count == 3)
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

    @Test func historyAndSubjectSearchRemainAvailableWithoutSubscription() throws {
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

        #expect(HistoryBrowser.visible(items.reversed()).map(\.id) == items.map(\.id))
        #expect(HistoryBrowser.recent(items, requestedCount: 100).count == 12)
        #expect(HistoryBrowser.recent(items, requestedCount: 5).count == 5)
        let matches = HistoryBrowser.filter(
            HistoryBrowser.visible(items), query: "수학",
            subjectName: { id in
                catalog.subject(for: id)?.name
            })
        #expect(matches.map(\.id) == [items[11].id])
    }

    @Test func closesHistoryOnlyAfterItsRecordIsRemoved() {
        let items = (0..<12).map { offset -> SolveResult in
            var result = SolveResult(preset: .general)
            result.date = Date(timeIntervalSince1970: TimeInterval(12 - offset))
            return result
        }

        #expect(!HistoryBrowser.shouldClose(activeResultID: nil, items: items))
        #expect(!HistoryBrowser.shouldClose(activeResultID: items[11].id, items: items))
        #expect(HistoryBrowser.shouldClose(activeResultID: items[11].id, items: Array(items.prefix(11))))
        #expect(!HistoryBrowser.shouldClose(activeResultID: items[0].id, items: items))
    }

    @Test func groupingAndSubjectDeletionKeepRecordsAndImages() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let historyStore = HistoryStore(baseURL: directory)
        let subjectStore = SubjectStore(baseURL: directory)
        var first = SolveResult(preset: .general)
        let second = SolveResult(preset: .general)
        let image = Data("jpeg".utf8)
        first.imageFileName = try historyStore.saveImage(image, for: first.id)
        try historyStore.save([first, second])
        var catalog = try subjectStore.load(migrating: try historyStore.load())
        try catalog.create("수학")
        let subjectID = try #require(catalog.subjects.first?.id)
        try catalog.assign(subjectID, to: first.id)
        #expect(HistoryBrowser.subjects(try historyStore.load(), catalog: catalog).map(\.name) == ["수학", "미분류"])
        try catalog.delete(subjectID)
        try subjectStore.save(catalog)
        #expect(HistoryBrowser.subjects(try historyStore.load(), catalog: catalog).map(\.name) == ["미분류"])
        #expect(try historyStore.load().count == 2)
        #expect(historyStore.loadImage(for: first) == image)
    }
}
