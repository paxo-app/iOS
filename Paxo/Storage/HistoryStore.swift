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

    func load() -> [SolveResult] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        guard let decoded = try? JSONDecoder().decode(LossyArray<SolveResult>.self, from: data) else {
            return []
        }
        var seen = Set<UUID>()
        return decoded.elements.sorted { $0.date > $1.date }.filter { seen.insert($0.id).inserted }.prefix(100).map {
            $0
        }
    }

    func save(_ items: [SolveResult]) {
        guard prepareDirectory(baseURL) else { return }
        guard let data = try? JSONEncoder().encode(items) else { return }
        guard (try? data.write(to: fileURL, options: .atomic)) != nil else { return }
        removeOrphanedImages(keeping: Set(items.compactMap(\.imageFileName)))
    }

    func saveImage(_ data: Data, for id: UUID) -> String? {
        guard prepareDirectory(imagesURL) else { return nil }
        let fileName = Self.imageFileName(for: id)
        let destination = imagesURL.appendingPathComponent(fileName)
        guard (try? data.write(to: destination, options: .atomic)) != nil else { return nil }
        return fileName
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

    private func prepareDirectory(_ url: URL) -> Bool {
        (try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)) != nil
    }

    private func removeOrphanedImages(keeping fileNames: Set<String>) {
        guard
            let storedURLs = try? fileManager.contentsOfDirectory(
                at: imagesURL,
                includingPropertiesForKeys: nil
            )
        else { return }
        for url in storedURLs where !fileNames.contains(url.lastPathComponent) {
            try? fileManager.removeItem(at: url)
        }
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
