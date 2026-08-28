import Foundation

/// 풀이 기록을 Application Support에 JSON으로 저장한다. (샌드박스 컨테이너 내부)
struct HistoryStore {
    private var fileURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Paxo", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("history.json")
    }

    func load() -> [SolveResult] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([SolveResult].self, from: data)) ?? []
    }

    func save(_ items: [SolveResult]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
