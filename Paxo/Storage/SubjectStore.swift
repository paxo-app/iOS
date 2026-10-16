import Foundation

/// 기록의 과목 이름과 지정 관계를 풀이 본문과 별도로 보관한다.
struct HistorySubject: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

struct SubjectCatalog: Codable, Equatable {
    private(set) var subjects: [HistorySubject] = []
    private(set) var assignments: [String: UUID] = [:]
    private(set) var didMigrateLegacyPresets = false

    static func migrated(from history: [SolveResult]) -> SubjectCatalog {
        var catalog = SubjectCatalog()
        for preset in [SubjectPreset.math, .licenseExam] {
            let items = history.filter { $0.preset == preset }
            guard !items.isEmpty else { continue }
            let subject = HistorySubject(name: preset.displayName)
            catalog.subjects.append(subject)
            for item in items {
                catalog.assignments[item.id.uuidString] = subject.id
            }
        }
        catalog.didMigrateLegacyPresets = true
        return catalog
    }

    func subject(for resultID: UUID) -> HistorySubject? {
        guard let id = assignments[resultID.uuidString] else { return nil }
        return subjects.first { $0.id == id }
    }

    mutating func create(_ name: String) throws {
        let name = try validatedName(name)
        subjects.append(HistorySubject(name: name))
    }

    mutating func rename(_ id: UUID, to name: String) throws {
        guard let index = subjects.firstIndex(where: { $0.id == id }) else {
            throw SubjectError.notFound
        }
        subjects[index].name = try validatedName(name, excluding: id)
    }

    mutating func delete(_ id: UUID) throws {
        guard subjects.contains(where: { $0.id == id }) else { throw SubjectError.notFound }
        subjects.removeAll { $0.id == id }
        assignments = assignments.filter { $0.value != id }
    }

    mutating func assign(_ subjectID: UUID?, to resultID: UUID) throws {
        if let subjectID {
            guard subjects.contains(where: { $0.id == subjectID }) else { throw SubjectError.notFound }
            assignments[resultID.uuidString] = subjectID
        } else {
            assignments.removeValue(forKey: resultID.uuidString)
        }
    }

    mutating func prune(keeping resultIDs: Set<UUID>) {
        let keys = Set(resultIDs.map(\.uuidString))
        assignments = assignments.filter { keys.contains($0.key) }
    }

    private func validatedName(_ raw: String, excluding id: UUID? = nil) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 30, name != "미분류" else {
            throw SubjectError.invalidName
        }
        guard
            !subjects.contains(where: {
                $0.id != id
                    && $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            })
        else { throw SubjectError.duplicateName }
        return name
    }
}

struct SubjectStore {
    private let fileURL: URL
    private let fileManager: FileManager

    init(baseURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let directory =
            baseURL
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Paxo", isDirectory: true)
        fileURL = directory.appendingPathComponent("subjects.json")
    }

    func load(migrating history: [SolveResult]) throws -> SubjectCatalog {
        if fileManager.fileExists(atPath: fileURL.path) {
            return try JSONDecoder().decode(SubjectCatalog.self, from: Data(contentsOf: fileURL))
        }
        let catalog = SubjectCatalog.migrated(from: history)
        try save(catalog)
        return catalog
    }

    func save(_ catalog: SubjectCatalog) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try JSONEncoder().encode(catalog).write(to: fileURL, options: .atomic)
    }
}

enum SubjectError: LocalizedError {
    case invalidName
    case duplicateName
    case notFound

    var errorDescription: String? {
        switch self {
        case .invalidName: "과목 이름은 1~30자로 입력하고 '미분류'는 사용할 수 없습니다."
        case .duplicateName: "이미 같은 이름의 과목이 있습니다."
        case .notFound: "과목을 찾을 수 없습니다. 다시 선택해주세요."
        }
    }
}
