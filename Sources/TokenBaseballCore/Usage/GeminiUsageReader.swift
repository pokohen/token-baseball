import Foundation

/// Gemini CLI 로컬 대화 기록(`~/.gemini/tmp/<프로젝트>/chats/**/*.jsonl`)에서 토큰 사용량을 읽는다.
/// 파일을 읽기만 하며 외부로 보내지 않는다.
///
/// 형식은 gemini-cli의 `packages/core/src/services/chatRecordingService.ts`를 따른다.
/// - 한 줄에 기록 하나. 첫 줄은 세션 정보(`sessionId`), 나머지는 메시지·`$set`·`$patch`·`$rewindTo` 기록이다.
/// - 응답(`type: "gemini"`)마다 `tokens {input, output, cached, thoughts, tool, total}`이 붙는다.
///   누적값이 아니라 그 응답 한 건의 값이다.
/// - 같은 메시지가 내용이 바뀔 때마다 같은 `id`로 다시 덧붙으므로 `id`로 중복을 없앤다.
/// - 되감기(`$rewindTo`)로 지워진 응답도 토큰은 이미 쓴 것이라 그대로 센다.
/// - 예전 버전은 세션 전체를 `.json` 파일 하나(`{sessionId, messages: [...]}`)로 저장했다. 이것도 읽는다.
public struct GeminiUsageReader: Sendable {
    /// 로그 루트 폴더. 테스트에서는 임시 폴더를 넣는다.
    public let root: URL

    public init(root: URL = GeminiUsageReader.defaultRoot) {
        self.root = root
    }

    /// `~/.gemini/tmp`. Gemini CLI처럼 `GEMINI_CLI_HOME`이 있으면 홈 폴더 대신 그곳을 쓴다.
    public static var defaultRoot: URL {
        let home: URL
        if let custom = ProcessInfo.processInfo.environment["GEMINI_CLI_HOME"], !custom.isEmpty {
            home = URL(fileURLWithPath: custom, isDirectory: true)
        } else {
            home = FileManager.default.homeDirectoryForCurrentUser
        }
        return home.appendingPathComponent(".gemini/tmp", isDirectory: true)
    }

    public func total(since: Date, until: Date = .distantFuture) -> TokenUsage {
        records(since: since, until: until).reduce(.zero) { $0 + $1.usage }
    }

    /// 중복을 없앤 응답별 사용량. 시간순으로 정렬해 돌려준다.
    public func records(since: Date = .distantPast, until: Date = .distantFuture) -> [UsageRecord] {
        var byID: [String: UsageRecord] = [:]
        for file in logFiles(modifiedSince: since) {
            guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { continue }
            let parsed = Self.parse(file: data)
            // 예전 `.json` 세션을 이어 쓰면 같은 내용이 `.jsonl`로 다시 저장된다.
            // 파일 이름이 아니라 세션 ID로 이름을 지어야 두 번 세지 않는다.
            let session = parsed.sessionID ?? Self.sessionName(of: file)
            for message in parsed.messages {
                let record = UsageRecord(
                    id: "gemini:\(session):\(message.id)", timestamp: message.timestamp, usage: message.usage)
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
        }
        return byID.values
            .filter { $0.timestamp >= since && $0.timestamp < until }
            .sorted { ($0.timestamp, $0.id) < ($1.timestamp, $1.id) }
    }

    // MARK: - 파일 찾기

    /// `chats` 폴더 아래의 `.jsonl`·`.json` 파일. 기준 시각 이전에 마지막으로 수정된 파일은 건너뛴다.
    /// (하위 에이전트의 기록은 `chats/<부모 세션>/` 아래에 있다.)
    private func logFiles(modifiedSince since: Date) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) else { return [] }
        let depth = root.standardizedFileURL.pathComponents.count
        var files: [URL] = []
        for case let url as URL in enumerator
        where url.pathExtension == "jsonl" || url.pathExtension == "json" {
            // `tmp/<프로젝트>/` 아래에는 대화 기록 말고도 다른 JSON 파일이 있다.
            let inside = url.standardizedFileURL.pathComponents.dropFirst(depth).dropLast()
            guard inside.contains("chats") else { continue }
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }
            if let modified = values?.contentModificationDate, modified < since { continue }
            files.append(url)
        }
        return files.sorted { $0.path < $1.path }
    }

    private static func sessionName(of file: URL) -> String {
        file.deletingPathExtension().lastPathComponent
    }

    // MARK: - 파일 읽기

    struct Message {
        let id: String
        let timestamp: Date
        let usage: TokenUsage
    }

    private struct Record: Decodable {
        let sessionId: String?
        let id: String?
        let type: String?
        let timestamp: String?
        let tokens: Tokens?
        /// 예전 형식: 세션 정보 안에 메시지 전체가 들어 있다.
        let messages: [Lossy<Record>]?
        /// `{"$set": {...}}` — 세션 정보 갱신. 예전에는 여기에 메시지 전체를 다시 적기도 했다.
        let set: Box?

        enum CodingKeys: String, CodingKey {
            case sessionId, id, type, timestamp, tokens, messages
            case set = "$set"
        }
    }

    /// 자기 자신을 다시 품는 구조라 한 겹 감싼다.
    private final class Box: Decodable {
        let value: Record
        init(from decoder: Decoder) throws { value = try Record(from: decoder) }
    }

    /// 배열 안의 한 항목이 깨져 있어도 나머지는 읽는다.
    private struct Lossy<Value: Decodable>: Decodable {
        let value: Value?
        init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
    }

    private struct Tokens: Decodable {
        let input: Int?
        let output: Int?
        let cached: Int?
        let thoughts: Int?
        let tool: Int?
    }

    private static let tokensMarker = Data(#""tokens""#.utf8)
    private static let sessionMarker = Data(#""sessionId""#.utf8)

    static func parse(file data: Data) -> (sessionID: String?, messages: [Message]) {
        var sessionID: String?
        var messages: [Message] = []
        var decodedAny = false
        let decoder = JSONDecoder()

        func take(_ record: Record) {
            if sessionID == nil { sessionID = record.sessionId ?? record.set?.value.sessionId }
            if let message = message(from: record) { messages.append(message) }
            for nested in record.messages ?? [] {
                if let message = nested.value.flatMap(message(from:)) { messages.append(message) }
            }
            for nested in record.set?.value.messages ?? [] {
                if let message = nested.value.flatMap(message(from:)) { messages.append(message) }
            }
        }

        for line in data.split(separator: UInt8(ascii: "\n")) {
            // 사용자 메시지처럼 토큰이 없는 줄이 많다. JSON으로 풀기 전에 먼저 걸러낸다.
            guard line.range(of: tokensMarker) != nil || line.range(of: sessionMarker) != nil,
                  let record = try? decoder.decode(Record.self, from: line)
            else { continue }
            decodedAny = true
            take(record)
        }
        // 예전 `.json` 파일은 여러 줄에 걸친 JSON 하나라서 줄 단위로는 읽히지 않는다.
        if !decodedAny, let record = try? decoder.decode(Record.self, from: data) {
            take(record)
        }
        return (sessionID, messages)
    }

    private static func message(from record: Record) -> Message? {
        guard record.type == "gemini",
              let id = record.id,
              let tokens = record.tokens,
              let timestamp = record.timestamp.flatMap(ClaudeCodeUsageReader.parseTimestamp)
        else { return nil }
        let prompt = max(0, tokens.input ?? 0)
        // input(promptTokenCount)에는 캐시에서 읽은 토큰이 들어 있다. 겹치지 않게 나눈다.
        let cached = min(prompt, max(0, tokens.cached ?? 0))
        // total = input + output + tool + thoughts 이다.
        // 도구 호출용 프롬프트(tool)는 입력으로, 생각(thoughts)은 출력으로 센다.
        let usage = TokenUsage(
            input: prompt - cached + max(0, tokens.tool ?? 0),
            output: max(0, tokens.output ?? 0) + max(0, tokens.thoughts ?? 0),
            cacheRead: cached
        )
        guard usage.total > 0 else { return nil }
        return Message(id: id, timestamp: timestamp, usage: usage)
    }
}
