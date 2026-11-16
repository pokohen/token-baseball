import Foundation
import SQLite3

/// opencode 로컬 저장소(`~/.local/share/opencode`)에서 토큰 사용량을 읽는다.
/// 읽기 전용으로만 열며 외부로 보내지 않는다.
///
/// opencode는 버전에 따라 저장 방식이 세 가지다. 메시지 ID는 옮겨질 때도 그대로라서
/// 셋을 모두 읽고 ID로 중복을 없앤다.
/// 1. `opencode.db`의 `message` 표 — 현재 배포판(v1). `data`(JSON)의 `role`이 `assistant`인 줄.
/// 2. `opencode.db`의 `session_message` 표 — 다음 세대(v2). `type`이 `assistant`·`compaction`인 줄.
/// 3. `storage/message/<세션>/<메시지>.json` — SQLite로 옮기기 전의 예전 형식.
///
/// 어느 형식이든 `tokens {input, output, reasoning, cache {read, write}}`는 응답 한 건의 값이고
/// 다섯 항목이 서로 겹치지 않는다(input에 캐시가 들어 있지 않고, output에 reasoning이 들어 있지 않다).
public struct OpenCodeUsageReader: Sendable {
    /// opencode 데이터 폴더. 테스트에서는 임시 폴더를 넣는다.
    public let root: URL

    public init(root: URL = OpenCodeUsageReader.defaultRoot) {
        self.root = root
    }

    /// `~/.local/share/opencode`. opencode는 macOS에서도 XDG 경로를 쓰고 `XDG_DATA_HOME`을 따른다.
    public static var defaultRoot: URL {
        let data: URL
        if let custom = ProcessInfo.processInfo.environment["XDG_DATA_HOME"], !custom.isEmpty {
            data = URL(fileURLWithPath: custom, isDirectory: true)
        } else {
            data = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/share", isDirectory: true)
        }
        return data.appendingPathComponent("opencode", isDirectory: true)
    }

    public func total(since: Date, until: Date = .distantFuture) -> TokenUsage {
        records(since: since, until: until).reduce(.zero) { $0 + $1.usage }
    }

    /// 중복을 없앤 응답별 사용량. 시간순으로 정렬해 돌려준다.
    public func records(since: Date = .distantPast, until: Date = .distantFuture) -> [UsageRecord] {
        var byID: [String: UsageRecord] = [:]
        func add(_ record: UsageRecord) {
            if let existing = byID[record.id] {
                byID[record.id] = UsageRecord(
                    id: record.id,
                    timestamp: min(existing.timestamp, record.timestamp),
                    usage: record.usage.total > existing.usage.total ? record.usage : existing.usage
                )
            } else {
                byID[record.id] = record
            }
        }
        for database in databases(modifiedSince: since) {
            Self.read(database: database, since: since).forEach(add)
        }
        for file in legacyFiles(modifiedSince: since) {
            guard let data = try? Data(contentsOf: file, options: .mappedIfSafe),
                  let record = Self.parse(legacy: data)
            else { continue }
            add(record)
        }
        return byID.values
            .filter { $0.timestamp >= since && $0.timestamp < until }
            .sorted { ($0.timestamp, $0.id) < ($1.timestamp, $1.id) }
    }

    // MARK: - 파일 찾기

    /// 데이터 폴더의 `opencode*.db`. 정식판은 `opencode.db`, 개발 채널은 `opencode-<채널>.db`를 쓴다.
    private func databases(modifiedSince since: Date) -> [URL] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries
            .filter { $0.pathExtension == "db" && $0.lastPathComponent.hasPrefix("opencode") }
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true }
            .filter { url in
                // WAL 방식이라 새로 쓴 내용은 `-wal` 파일에 먼저 들어간다. 둘 중 더 최근 시각을 본다.
                let modified = [url, URL(fileURLWithPath: url.path + "-wal")]
                    .compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]) }
                    .compactMap(\.contentModificationDate)
                    .max()
                guard let modified else { return true }
                return modified >= since
            }
            .sorted { $0.path < $1.path }
    }

    /// `storage/message/<세션>/<메시지>.json`. 기준 시각 이전에 마지막으로 수정된 파일은 건너뛴다.
    private func legacyFiles(modifiedSince since: Date) -> [URL] {
        let folder = root.appendingPathComponent("storage/message", isDirectory: true)
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "json" {
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }
            if let modified = values?.contentModificationDate, modified < since { continue }
            files.append(url)
        }
        return files.sorted { $0.path < $1.path }
    }

    // MARK: - SQLite 읽기

    /// 응답 하나가 시작해서 끝나기까지 걸릴 수 있다고 보는 가장 긴 시간(도구 실행·권한 확인 대기 포함).
    private static let startMargin: TimeInterval = 24 * 60 * 60

    private static let tokenColumns = """
        json_extract(data, '$.tokens.input'), json_extract(data, '$.tokens.output'),
        json_extract(data, '$.tokens.reasoning'),
        json_extract(data, '$.tokens.cache.write'), json_extract(data, '$.tokens.cache.read'),
        json_extract(data, '$.time.completed')
        """

    /// 표 이름과 그 표에서 응답만 골라내는 조건. JSON이 깨진 줄은 건너뛴다.
    private static let tables: [(name: String, filter: String)] = [
        ("message", "CASE WHEN json_valid(data) THEN json_extract(data, '$.role') = 'assistant' ELSE 0 END"),
        ("session_message", "type IN ('assistant', 'compaction') AND json_valid(data)"),
    ]

    private static func read(database url: URL, since: Date) -> [UsageRecord] {
        var handle: OpaquePointer?
        // 읽기 전용으로 연다. opencode가 쓰는 중이어도 방해하지 않는다.
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let handle else {
            sqlite3_close(handle)
            return []
        }
        defer { sqlite3_close(handle) }
        sqlite3_busy_timeout(handle, 250)

        // `time_created`는 1970년부터의 밀리초이고 응답이 시작된 시각이다. 오래 걸린 응답을 놓치지 않게
        // 여유를 두고 고른 뒤, 끝난 시각으로 다시 거른다(`records`에서).
        let from = since.timeIntervalSince1970 - startMargin
        let sinceMillis = Int64(min(max(from * 1000, 0), 9e18))
        var records: [UsageRecord] = []
        for table in tables where exists(table: table.name, in: handle) {
            let sql = """
                SELECT id, time_created, \(tokenColumns)
                FROM \(table.name) WHERE time_created >= ?1 AND \(table.filter)
                """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
                sqlite3_finalize(statement)
                continue
            }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int64(statement, 1, sinceMillis)
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let text = sqlite3_column_text(statement, 0) else { continue }
                // 토큰은 응답이 끝날 때 적힌다. 끝난 시각이 있으면 그것을, 없으면 시작 시각을 쓴다.
                let completed = sqlite3_column_double(statement, 7)
                let millis = completed > 0 ? completed : sqlite3_column_double(statement, 1)
                let usage = usage(
                    input: sqlite3_column_double(statement, 2), output: sqlite3_column_double(statement, 3),
                    reasoning: sqlite3_column_double(statement, 4),
                    cacheWrite: sqlite3_column_double(statement, 5), cacheRead: sqlite3_column_double(statement, 6))
                // 응답이 끝나기 전에는 토큰이 아직 0이다.
                guard usage.total > 0 else { continue }
                records.append(UsageRecord(
                    id: "opencode:\(String(cString: text))",
                    timestamp: Date(timeIntervalSince1970: millis / 1000), usage: usage))
            }
        }
        return records
    }

    private static func exists(table: String, in handle: OpaquePointer) -> Bool {
        var statement: OpaquePointer?
        let sql = "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = '\(table)'"
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            sqlite3_finalize(statement)
            return false
        }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW
    }

    /// reasoning은 output과 따로 적혀 있으므로 출력에 더한다. 값이 없으면(NULL) 0이다.
    private static func usage(
        input: Double, output: Double, reasoning: Double, cacheWrite: Double, cacheRead: Double
    ) -> TokenUsage {
        func count(_ value: Double) -> Int {
            value.isFinite && value > 0 ? Int(min(value, 1e15).rounded()) : 0
        }
        return TokenUsage(
            input: count(input), output: count(output) + count(reasoning),
            cacheWrite: count(cacheWrite), cacheRead: count(cacheRead))
    }

    // MARK: - 예전 JSON 파일 읽기

    private struct LegacyMessage: Decodable {
        let id: String?
        let role: String?
        let time: Time?
        let tokens: Tokens?

        struct Time: Decodable {
            let created: Double?
            let completed: Double?
        }

        struct Tokens: Decodable {
            let input: Double?
            let output: Double?
            let reasoning: Double?
            let cache: Cache?
        }

        struct Cache: Decodable {
            let read: Double?
            let write: Double?
        }
    }

    static func parse(legacy data: Data) -> UsageRecord? {
        guard let message = try? JSONDecoder().decode(LegacyMessage.self, from: data),
              message.role == "assistant",
              let id = message.id,
              let created = message.time?.created,
              let tokens = message.tokens
        else { return nil }
        let usage = usage(
            input: tokens.input ?? 0, output: tokens.output ?? 0, reasoning: tokens.reasoning ?? 0,
            cacheWrite: tokens.cache?.write ?? 0, cacheRead: tokens.cache?.read ?? 0)
        guard usage.total > 0 else { return nil }
        let millis = message.time?.completed ?? created
        return UsageRecord(
            id: "opencode:\(id)", timestamp: Date(timeIntervalSince1970: millis / 1000), usage: usage)
    }
}
