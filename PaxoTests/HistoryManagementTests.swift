import AppKit
import Foundation
import Testing

@testable import Paxo

@MainActor
struct HistoryManagementTests {
    @Test func deletingOpenRecordRemovesImageAndAssignmentButKeepsOtherData() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HistoryStore(baseURL: directory)
        let subjects = SubjectStore(baseURL: directory)
        let bitmap = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
                bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ))
        let image = try #require(bitmap.representation(using: .jpeg, properties: [:]))
        var first = SolveResult(preset: .general)
        first.answer = "첫 정답"
        first.imageFileName = try store.saveImage(image, for: first.id)
        var second = SolveResult(preset: .general)
        second.answer = "다른 정답"
        second.imageFileName = try store.saveImage(Data("다른 이미지".utf8), for: second.id)
        try store.save([first, second])
        var catalog = try subjects.load(migrating: [first, second])
        try catalog.create("수학")
        let subjectID = try #require(catalog.subjects.first?.id)
        try catalog.assign(subjectID, to: first.id)
        try catalog.assign(subjectID, to: second.id)
        try subjects.save(catalog)

        let state = AppState(historyStore: store, subjectStore: subjects)
        state.loadHistory()
        #expect(state.showFromHistory(first, presentPanel: false, dismissPanel: false))
        #expect(state.historyImage(for: first) != nil)
        #expect(state.currentThumbnail != nil)
        #expect(state.deleteHistory(first.id))
        #expect(state.current == nil)
        #expect(state.phase == .idle)
        #expect(state.historyError == nil)
        #expect(try store.load().map(\.id) == [second.id])
        #expect(store.loadImage(for: first) == nil)
        #expect(state.historyImage(for: first) == nil)
        #expect(state.currentThumbnail == nil)
        #expect(store.loadImage(for: second) == Data("다른 이미지".utf8))
        let reopened = try subjects.load(migrating: store.load())
        #expect(reopened.subjects.map(\.id) == [subjectID])
        #expect(reopened.subject(for: first.id) == nil)
        #expect(reopened.subject(for: second.id)?.id == subjectID)

        state.saveExplanation("늦게 도착한 해설", for: first.id, basedOnAnswer: "첫 정답")
        #expect(state.current == nil)
        #expect(try store.load().map(\.id) == [second.id])
        #expect(state.showFromHistory(second, presentPanel: false, dismissPanel: false))
        state.saveExplanation("늦게 도착한 해설", for: first.id, basedOnAnswer: "첫 정답")
        #expect(state.current?.id == second.id)
        #expect(state.current?.explanation == nil)
    }

    @Test func freeUserCanDeleteAllIncludingHiddenRecordsAndOrphanedImages() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HistoryStore(baseURL: directory)
        let subjects = SubjectStore(baseURL: directory)
        let items = try (0..<12).map { offset in
            var item = SolveResult(preset: .general)
            item.date = Date(timeIntervalSince1970: Double(offset))
            item.imageFileName = try store.saveImage(Data([UInt8(offset)]), for: item.id)
            return item
        }
        try store.save(items)
        let state = AppState(historyStore: store, subjectStore: subjects)
        state.loadHistory()
        #expect(state.serverTier == .free)
        #expect(state.visibleHistory.count == 10)
        #expect(!state.deleteHistory(items[0].id))
        _ = try store.saveImage(Data([42]), for: UUID())
        #expect(state.deleteAllHistory())
        #expect(state.history.isEmpty)
        #expect(try store.load().isEmpty)
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("HistoryImages").path)
                .isEmpty)

        let restarted = AppState(historyStore: store, subjectStore: subjects)
        restarted.loadHistory()
        #expect(restarted.history.isEmpty)
        #expect(restarted.historyError == nil)
    }

    @Test func failedDeletionKeepsRecordImageAndCurrentThenCanRetry() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = FailingHistoryFileManager()
        let store = HistoryStore(baseURL: directory, fileManager: manager)
        var item = SolveResult(preset: .general)
        item.imageFileName = try store.saveImage(Data([1]), for: item.id)
        try store.save([item])
        let state = AppState(historyStore: store, subjectStore: SubjectStore(baseURL: directory))
        state.loadHistory()
        #expect(state.showFromHistory(item, presentPanel: false, dismissPanel: false))
        manager.failsDirectoryCreation = true
        #expect(!state.deleteAllHistory())
        #expect(state.history.map(\.id) == [item.id])
        #expect(state.current?.id == item.id)
        #expect(try store.load().map(\.id) == [item.id])
        #expect(store.loadImage(for: item) == Data([1]))
        #expect(state.historyError != nil)
        manager.failsDirectoryCreation = false
        state.retryHistoryStorage()
        #expect(state.history.isEmpty)
        #expect(try store.load().isEmpty)
        #expect(store.loadImage(for: item) == nil)
        #expect(state.historyError == nil)
    }

    @Test func partialImageDeletionDoesNotRestoreRecordAndCleanupCanRetry() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = FailingHistoryFileManager()
        let store = HistoryStore(baseURL: directory, fileManager: manager)
        var item = SolveResult(preset: .general)
        item.answer = "정답"
        item.imageFileName = try store.saveImage(Data([1]), for: item.id)
        try store.save([item])
        let state = AppState(historyStore: store, subjectStore: SubjectStore(baseURL: directory))
        state.loadHistory()
        manager.blockedRemovalNames = [try #require(item.imageFileName)]
        #expect(state.deleteAllHistory())
        #expect(state.history.isEmpty)
        #expect(try store.load().isEmpty)
        #expect(state.historyError == HistoryStorageError.imageCleanupFailed.errorDescription)
        #expect(store.loadImage(for: item) != nil)
        state.saveExplanation("늦게 온 해설", for: item.id, basedOnAnswer: "정답")
        #expect(try store.load().isEmpty)

        let restarted = AppState(historyStore: store, subjectStore: SubjectStore(baseURL: directory))
        restarted.loadHistory()
        #expect(restarted.historyError != nil)
        manager.blockedRemovalNames = []
        restarted.retryHistoryStorage()
        #expect(restarted.historyError == nil)
        #expect(store.loadImage(for: item) == nil)
    }

    @Test func subjectCleanupFailureIsVisibleToFreeUserAndRetryKeepsSubjectNames() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = FailingHistoryFileManager()
        let store = HistoryStore(baseURL: directory)
        let subjects = SubjectStore(baseURL: directory, fileManager: manager)
        let item = SolveResult(preset: .general)
        try store.save([item])
        var catalog = try subjects.load(migrating: [item])
        try catalog.create("수학")
        let id = try #require(catalog.subjects.first?.id)
        try catalog.assign(id, to: item.id)
        try subjects.save(catalog)
        let state = AppState(historyStore: store, subjectStore: subjects)
        state.loadHistory()
        manager.failsDirectoryCreation = true
        #expect(state.deleteAllHistory())
        #expect(state.subjectCatalog.subject(for: item.id) == nil)
        #expect(state.subjectCatalog.subjects.map(\.id) == [id])
        #expect(state.historyError == HistoryStorageError.subjectCleanupFailed.errorDescription)
        manager.failsDirectoryCreation = false
        state.retryHistoryStorage()
        #expect(state.historyError == nil)
        #expect(try subjects.load(migrating: []).assignments.isEmpty)
        #expect(try subjects.load(migrating: []).subjects.map(\.id) == [id])
    }

    @Test func failedSaveKeepsEditedResultAndRetryPersistsIt() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = FailingHistoryFileManager()
        let store = HistoryStore(baseURL: directory, fileManager: manager)
        var item = SolveResult(preset: .general)
        item.answer = "원래 정답"
        try store.save([item])
        let state = AppState(historyStore: store, subjectStore: SubjectStore(baseURL: directory))
        state.loadHistory()
        #expect(state.showFromHistory(item, presentPanel: false, dismissPanel: false))
        manager.failsDirectoryCreation = true
        #expect(state.updateHistoryAnswer("수정한 정답", for: item.id))
        #expect(state.current?.answer == "수정한 정답")
        #expect(try store.load().first?.answer == "원래 정답")
        #expect(state.historyError == HistoryStorageError.saveFailed.errorDescription)
        manager.failsDirectoryCreation = false
        state.retryHistoryStorage()
        #expect(state.historyError == nil)
        #expect(try store.load().first?.answer == "수정한 정답")
    }

    @Test func unreadableHistoryDoesNotEraseExistingFiles() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HistoryStore(baseURL: directory)
        let fileName = try store.saveImage(Data([1]), for: UUID())
        let fileURL = directory.appendingPathComponent("history.json")
        let corruptData = Data("손상된 기록".utf8)
        try corruptData.write(to: fileURL)
        let state = AppState(historyStore: store, subjectStore: SubjectStore(baseURL: directory))
        state.loadHistory()
        #expect(state.historyError == HistoryStorageError.loadFailed.errorDescription)
        #expect(!state.deleteAllHistory())
        #expect(try Data(contentsOf: fileURL) == corruptData)
        #expect(
            FileManager.default.fileExists(atPath: directory.appendingPathComponent("HistoryImages/\(fileName)").path))
    }

    @Test func imageWriteFailureIsReportedAndRecordSaveDoesNotDeleteImages() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = FailingHistoryFileManager()
        let store = HistoryStore(baseURL: directory, fileManager: manager)
        var item = SolveResult(preset: .general)
        item.imageFileName = try store.saveImage(Data([1]), for: item.id)
        try store.save([item])
        manager.failsDirectoryCreation = true
        #expect(throws: HistoryStorageError.imageSaveFailed) { try store.saveImage(Data([2]), for: UUID()) }
        #expect(throws: HistoryStorageError.saveFailed) { try store.save([]) }
        #expect(store.loadImage(for: item) == Data([1]))
        #expect(try store.load().map(\.id) == [item.id])
    }

    @Test func recoveringReadFailureKeepsUnsavedEdits() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HistoryStore(baseURL: directory)
        var item = SolveResult(preset: .general)
        item.answer = "원래 정답"
        try store.save([item])
        let state = AppState(historyStore: store, subjectStore: SubjectStore(baseURL: directory))
        state.loadHistory()
        #expect(state.showFromHistory(item, presentPanel: false, dismissPanel: false))
        try Data("손상된 기록".utf8).write(to: directory.appendingPathComponent("history.json"))
        state.loadHistory()
        #expect(state.updateHistoryAnswer("수정한 정답", for: item.id))
        try store.save([item])
        state.retryHistoryStorage()
        #expect(state.historyError == nil)
        #expect(state.history.first?.answer == "수정한 정답")
        #expect(try store.load().first?.answer == "수정한 정답")
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }
}

private final class FailingHistoryFileManager: FileManager, @unchecked Sendable {
    var failsDirectoryCreation = false
    var blockedRemovalNames: Set<String> = []

    override func createDirectory(
        at url: URL, withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]? = nil
    ) throws {
        if failsDirectoryCreation { throw CocoaError(.fileWriteNoPermission) }
        try super.createDirectory(at: url, withIntermediateDirectories: createIntermediates, attributes: attributes)
    }

    override func removeItem(at url: URL) throws {
        if blockedRemovalNames.contains(url.lastPathComponent) { throw CocoaError(.fileWriteNoPermission) }
        try super.removeItem(at: url)
    }
}
