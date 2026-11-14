import Foundation

/// Codex CLI 로컬 로그(`~/.codex/sessions/**/*.jsonl`)에서 토큰 사용량을 읽는다.
///
/// Codex는 `token_count` 이벤트에 세션 누적 사용량을 적고, 같은 값이 여러 번 반복해서 기록된다.
/// 그래서 이벤트마다의 값을 더하지 않고, 누적값이 늘어난 만큼만 센다.
public struct CodexUsageReader: Sendable {
    public let root: URL

    public init(root: URL = CodexUsageReader.defaultRoot) {
        self.root = root
    }

    public static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true)
    }

    public func total(since: Date, until: Date = .distantFuture) -> TokenUsage {
        records(since: since, until: until).reduce(.zero) { $0 + $1.usage }
    }

    public func records(since: Date = .distantPast, until: Date = .distantFuture) -> [UsageRecord] {
        var result: [UsageRecord] = []
        for file in logFiles(modifiedSince: since) {
            guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { continue }
            let session = file.deletingPathExtension().lastPathComponent
            var previous = Totals()
            for line in data.split(separator: UInt8(ascii: "\n")) {
                guard let event = Self.parse(line: line) else { continue }
                let now = event.totals
                // 누적값이 줄어들면 (세션이 새로 시작되면) 처음부터 다시 센다.
                if now.input < previous.input || now.output < previous.output { previous = Totals() }
                let input = now.input - previous.input
                let cached = min(input, max(0, now.cached - previous.cached))
                let output = now.output - previous.output
                previous = now
                guard input + output > 0 else { continue }
                // Codex의 input에는 캐시에서 읽은 토큰이 들어 있다. 겹치지 않게 나눈다.
                let usage = TokenUsage(input: input - cached, output: output, cacheRead: cached)
                result.append(UsageRecord(
                    id: "codex:\(session):\(now.input + now.output)", timestamp: event.timestamp, usage: usage))
            }
        }
        return result
            .filter { $0.timestamp >= since && $0.timestamp < until }
            .sorted { ($0.timestamp, $0.id) < ($1.timestamp, $1.id) }
    }

    private func logFiles(modifiedSince since: Date) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }
            if let modified = values?.contentModificationDate, modified < since { continue }
            files.append(url)
        }
        return files.sorted { $0.path < $1.path }
    }

    private struct Totals {
        var input = 0, cached = 0, output = 0
    }

    private struct Line: Decodable {
        let timestamp: String?
        let payload: Payload?

        struct Payload: Decodable {
            let type: String?
            let info: Info?
        }

        struct Info: Decodable {
            let total_token_usage: Usage?
        }

        struct Usage: Decodable {
            let input_tokens: Int?
            let cached_input_tokens: Int?
            let output_tokens: Int?
        }
    }

    private static let marker = Data(#""token_count""#.utf8)

    private static func parse(line: Data) -> (timestamp: Date, totals: Totals)? {
        guard line.range(of: marker) != nil,
              let decoded = try? JSONDecoder().decode(Line.self, from: line),
              decoded.payload?.type == "token_count",
              let usage = decoded.payload?.info?.total_token_usage,
              let timestamp = decoded.timestamp.flatMap(ClaudeCodeUsageReader.parseTimestamp)
        else { return nil }
        return (timestamp, Totals(
            input: usage.input_tokens ?? 0, cached: usage.cached_input_tokens ?? 0,
            output: usage.output_tokens ?? 0))
    }
}

/// 설치된 도구들의 사용량을 한꺼번에 읽는다.
public struct UsageSources: Sendable {
    public var claudeCode: ClaudeCodeUsageReader
    public var codex: CodexUsageReader

    public init(claudeCode: ClaudeCodeUsageReader = .init(), codex: CodexUsageReader = .init()) {
        self.claudeCode = claudeCode
        self.codex = codex
    }

    public func records(since: Date, until: Date = .distantFuture) -> [UsageRecord] {
        claudeCode.records(since: since, until: until) + codex.records(since: since, until: until)
    }

    public func total(since: Date, until: Date = .distantFuture) -> TokenUsage {
        records(since: since, until: until).reduce(.zero) { $0 + $1.usage }
    }
}
