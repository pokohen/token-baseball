import Foundation

/// 저장 파일의 내용. 구단을 아직 만들지 않았으면 저장 파일 자체가 없다.
public struct GameSave: Codable, Equatable, Sendable {
    public static let currentVersion = 2

    public var version: Int
    public var game: Game

    public init(game: Game) {
        self.version = Self.currentVersion
        self.game = game
    }
}

/// 게임 상태를 로컬 JSON 파일로 저장한다. 서버로 보내지 않는다.
public struct SaveStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL = SaveStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    /// `~/Library/Application Support/TokenBaseball/save.json`
    public static var defaultFileURL: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("TokenBaseball", isDirectory: true)
            .appendingPathComponent("save.json")
    }

    /// 저장 파일이 없으면 `nil`. 파일이 깨졌으면 오류를 던진다 (조용히 새 게임으로 덮어쓰지 않기 위해).
    public func load() throws -> GameSave? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try Self.decoder.decode(GameSave.self, from: data)
    }

    public func save(_ save: GameSave) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        // 쓰는 도중 앱이 꺼져도 기존 파일이 깨지지 않게 통째로 바꿔 쓴다.
        try Self.encoder.encode(save).write(to: fileURL, options: .atomic)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // 초 단위로 줄이지 않는다. 시각이 잘리면 같은 응답을 다시 셀 수 있다.
        encoder.dateEncodingStrategy = .deferredToDate
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        return decoder
    }
}
