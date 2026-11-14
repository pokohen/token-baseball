import Foundation

/// Claude Code 로컬 로그(`~/.claude/projects/**/*.jsonl`)에서 토큰 사용량을 읽는다.
/// 파일을 읽기만 하며 외부로 보내지 않는다.
public struct ClaudeCodeUsageReader: Sendable {
    /// 로그 루트 폴더. 테스트에서는 임시 폴더를 넣는다.
    public let root: URL

    public init(root: URL = ClaudeCodeUsageReader.defaultRoot) {
        self.root = root
    }

    public static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
    }

    /// `since` 이후(같은 시각 포함)의 사용량 합계. 설치 이전 사용량을 소급하지 않기 위해 기준 시각을 꼭 받는다.
    public func total(since: Date, until: Date = .distantFuture) -> TokenUsage {
        records(since: since, until: until).reduce(.zero) { $0 + $1.usage }
    }

    /// 중복을 없앤 응답별 사용량. 시간순으로 정렬해 돌려준다.
    public func records(since: Date = .distantPast, until: Date = .distantFuture) -> [UsageRecord] {
        var byID: [String: UsageRecord] = [:]
        for file in logFiles(modifiedSince: since) {
            guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { continue }
            for line in data.split(separator: UInt8(ascii: "\n")) {
                guard let record = Self.parse(line: line) else { continue }
                if let existing = byID[record.id] {
                    // 같은 응답이 스트리밍 도중 여러 번 기록된다. 가장 큰 사용량과 가장 이른 시각을 남긴다.
                    byID[record.id] = UsageRecord(
                        id: record.id,
                        timestamp: min(existing.timestamp, record.timestamp),
                        usage: record.usage.total > existing.usage.total ? record.usage : existing.usage
                    )
                } else {
                    byID[record.id] = record
                }
            }
        }
        return byID.values
            .filter { $0.timestamp >= since && $0.timestamp < until }
            .sorted { ($0.timestamp, $0.id) < ($1.timestamp, $1.id) }
    }

    // MARK: - 파일 찾기

    /// 루트 아래의 모든 `.jsonl` 파일. 기준 시각 이전에 마지막으로 수정된 파일은 건너뛴다.
    private func logFiles(modifiedSince since: Date) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }
            if let modified = values?.contentModificationDate, modified < since { continue }
            files.append(url)
        }
        return files
    }

    // MARK: - 한 줄 읽기

    private struct Line: Decodable {
        let type: String?
        let timestamp: String?
        let message: Message?

        struct Message: Decodable {
            let id: String?
            let usage: Usage?
        }

        struct Usage: Decodable {
            let input_tokens: Int?
            let output_tokens: Int?
            let cache_creation_input_tokens: Int?
            let cache_read_input_tokens: Int?
        }
    }

    private static let usageMarker = Data(#""usage""#.utf8)

    static func parse(line: Data) -> UsageRecord? {
        // 대부분의 줄에는 사용량이 없다. JSON으로 풀기 전에 먼저 걸러낸다.
        guard line.range(of: usageMarker) != nil,
              let decoded = try? JSONDecoder().decode(Line.self, from: line),
              decoded.type == "assistant",
              let id = decoded.message?.id,
              let usage = decoded.message?.usage,
              let timestamp = decoded.timestamp.flatMap(parseTimestamp)
        else { return nil }

        return UsageRecord(
            id: id,
            timestamp: timestamp,
            usage: TokenUsage(
                input: usage.input_tokens ?? 0,
                output: usage.output_tokens ?? 0,
                cacheWrite: usage.cache_creation_input_tokens ?? 0,
                cacheRead: usage.cache_read_input_tokens ?? 0
            )
        )
    }

    static func parseTimestamp(_ string: String) -> Date? {
        if let date = try? Date(string, strategy: .iso8601.year().month().day()
            .time(includingFractionalSeconds: true).timeZone(separator: .omitted)) {
            return date
        }
        return try? Date(string, strategy: .iso8601)
    }
}
