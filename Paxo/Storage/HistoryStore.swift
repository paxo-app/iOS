import Foundation

/// 풀이 기록과 문제 이미지를 Application Support에 저장한다.
struct HistoryStore {
    private let baseURL: URL
    private let fileManager: FileManager

    init(baseURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.baseURL =
            baseURL
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Paxo", isDirectory: true)
    }

    func load() throws -> [SolveResult] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let decoded: LossyArray<SolveResult>
        do {
            decoded = try JSONDecoder().decode(LossyArray<SolveResult>.self, from: Data(contentsOf: fileURL))
        } catch {
            throw HistoryStorageError.loadFailed
        }
        var seen = Set<UUID>()
        return decoded.elements.sorted { $0.date > $1.date }.filter { seen.insert($0.id).inserted }.prefix(100).map {
            $0
        }
    }

    func save(_ items: [SolveResult]) throws {
        do {
            try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
            try JSONEncoder().encode(items).write(to: fileURL, options: .atomic)
        } catch {
            throw HistoryStorageError.saveFailed
        }
    }

    func saveImage(_ data: Data, for id: UUID) throws -> String {
        let fileName = Self.imageFileName(for: id)
        do {
            try fileManager.createDirectory(at: imagesURL, withIntermediateDirectories: true)
            try data.write(to: imagesURL.appendingPathComponent(fileName), options: .atomic)
        } catch {
            throw HistoryStorageError.imageSaveFailed
        }
        return fileName
    }

    /// 기록 저장이 실패했을 때 기존 기록의 이미지를 잃지 않도록 저장과 정리를 분리한다.
    func removeOrphanedImages(keeping items: [SolveResult]) throws {
        guard fileManager.fileExists(atPath: imagesURL.path) else { return }
        let fileNames = Set(items.compactMap(\.imageFileName))
        do {
            let storedURLs = try fileManager.contentsOfDirectory(at: imagesURL, includingPropertiesForKeys: nil)
            var failed = false
            for url in storedURLs where !fileNames.contains(url.lastPathComponent) {
                do {
                    try fileManager.removeItem(at: url)
                } catch {
                    failed = true
                }
            }
            if failed { throw HistoryStorageError.imageCleanupFailed }
        } catch {
            throw HistoryStorageError.imageCleanupFailed
        }
    }

    func loadImage(for item: SolveResult) -> Data? {
        guard item.imageFileName == Self.imageFileName(for: item.id) else { return nil }
        return try? Data(contentsOf: imagesURL.appendingPathComponent(Self.imageFileName(for: item.id)))
    }

    private var fileURL: URL {
        baseURL.appendingPathComponent("history.json")
    }

    private var imagesURL: URL {
        baseURL.appendingPathComponent("HistoryImages", isDirectory: true)
    }

    private static func imageFileName(for id: UUID) -> String {
        "\(id.uuidString.lowercased()).jpg"
    }

}

/// 한 항목의 스키마가 손상돼도 나머지 기록은 복원한다.
private struct LossyArray<Element: Decodable>: Decodable {
    let elements: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                elements.append(element)
            } else {
                _ = try? container.decode(DiscardedJSONValue.self)
            }
        }
        self.elements = elements
    }
}

private struct DiscardedJSONValue: Decodable {
    private struct CodingKey: Swift.CodingKey {
        let stringValue: String
        let intValue: Int? = nil

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            stringValue = String(intValue)
        }
    }

    init(from decoder: Decoder) throws {
        if var array = try? decoder.unkeyedContainer() {
            while !array.isAtEnd {
                _ = try array.decode(DiscardedJSONValue.self)
            }
            return
        }
        if let object = try? decoder.container(keyedBy: CodingKey.self) {
            for key in object.allKeys {
                _ = try object.decode(DiscardedJSONValue.self, forKey: key)
            }
            return
        }
        let value = try decoder.singleValueContainer()
        if value.decodeNil()
            || (try? value.decode(Bool.self)) != nil
            || (try? value.decode(Double.self)) != nil
            || (try? value.decode(String.self)) != nil
        {
            return
        }
        throw DecodingError.dataCorruptedError(in: value, debugDescription: "지원하지 않는 JSON 값입니다.")
    }
}

enum HistoryStorageError: LocalizedError, Equatable {
    case loadFailed
    case saveFailed
    case deleteFailed
    case imageSaveFailed
    case imageCleanupFailed
    case subjectCleanupFailed

    var errorDescription: String? {
        switch self {
        case .loadFailed: "풀이 기록을 불러오지 못했습니다. 기존 기록 보호를 위해 저장과 삭제를 멈췄습니다."
        case .saveFailed: "풀이 기록을 저장하지 못했습니다. 변경한 내용은 앱을 종료하면 사라질 수 있습니다."
        case .deleteFailed: "풀이 기록을 삭제하지 못했습니다. 기존 기록은 유지됩니다. 다시 시도하면 요청한 기록을 삭제합니다."
        case .imageSaveFailed: "문제 이미지를 저장하지 못했습니다. 앱을 종료하기 전에 다시 시도해주세요."
        case .imageCleanupFailed: "기록은 반영했지만 일부 문제 이미지를 정리하지 못했습니다. 다시 시도해주세요."
        case .subjectCleanupFailed: "기록은 반영했지만 과목 연결 정보를 정리하지 못했습니다. 다시 시도해주세요."
        }
    }
}
