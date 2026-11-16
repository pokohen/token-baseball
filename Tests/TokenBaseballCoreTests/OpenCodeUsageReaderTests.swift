import Foundation
import SQLite3
import Testing
@testable import TokenBaseballCore

@Suite struct OpenCodeUsageReaderTests {
    /// 임시 폴더에 opencode 데이터 폴더를 흉내 내고, 테스트가 끝나면 지운다.
    final class Fixture {
        let root: URL
        var databaseURL: URL { root.appendingPathComponent("opencode.db") }

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("token-baseball-tests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        /// opencode처럼 WAL 방식으로 DB를 연다. 닫는 것은 부르는 쪽이 한다.
        func open(named name: String = "opencode.db") throws -> OpaquePointer {
            var handle: OpaquePointer?
            let path = root.appendingPathComponent(name).path
            guard sqlite3_open(path, &handle) == SQLITE_OK, let handle else {
                throw CocoaError(.fileWriteUnknown)
            }
            try Self.run("PRAGMA journal_mode = WAL", on: handle)
            return handle
        }

        static func run(_ sql: String, on handle: OpaquePointer) throws {
            guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
                throw CocoaError(.fileWriteUnknown, userInfo: [
                    NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(handle)),
                ])
            }
        }

        /// SQL을 실행하고 닫는다.
        func execute(_ statements: [String], named name: String = "opencode.db") throws {
            let handle = try open(named: name)
            defer { sqlite3_close(handle) }
            for sql in statements { try Self.run(sql, on: handle) }
        }

        func write(_ text: String, to path: String) throws {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
    }

    // opencode의 마이그레이션이 만드는 표 (외래 키는 뺐다).
    static let messageTable = """
        CREATE TABLE `message` (
          `id` text PRIMARY KEY, `session_id` text NOT NULL,
          `time_created` integer NOT NULL, `time_updated` integer NOT NULL, `data` text NOT NULL
        )
        """
    static let sessionMessageTable = """
        CREATE TABLE `session_message` (
          `id` text PRIMARY KEY, `session_id` text NOT NULL, `type` text NOT NULL, `seq` integer NOT NULL,
          `time_created` integer NOT NULL, `time_updated` integer NOT NULL, `data` text NOT NULL
        )
        """

    static func millis(_ string: String) -> Int {
        Int((try! Date(string, strategy: .iso8601)).timeIntervalSince1970 * 1000)
    }

    static func tokens(input: Int, output: Int, reasoning: Int, cacheRead: Int, cacheWrite: Int) -> String {
        #"{"input":\#(input),"output":\#(output),"reasoning":\#(reasoning),"cache":{"read":\#(cacheRead),"write":\#(cacheWrite)}}"#
    }

    /// 현재 배포판(v1)의 `message` 표에 응답 한 줄을 넣는 SQL.
    static func v1Assistant(
        id: String, at timestamp: String,
        input: Int = 0, output: Int = 0, reasoning: Int = 0, cacheRead: Int = 0, cacheWrite: Int = 0
    ) -> String {
        let created = millis(timestamp)
        let tokens = tokens(input: input, output: output, reasoning: reasoning, cacheRead: cacheRead, cacheWrite: cacheWrite)
        let data = #"{"role":"assistant","time":{"created":\#(created)},"parentID":"msg_u","modelID":"m","providerID":"p","mode":"build","agent":"build","path":{"cwd":"/","root":"/"},"cost":0.01,"tokens":\#(tokens)}"#
        return "INSERT INTO message VALUES ('\(id)', 'ses_1', \(created), \(created), '\(data)')"
    }

    /// 다음 세대(v2)의 `session_message` 표에 한 줄을 넣는 SQL.
    static func v2Message(
        id: String, type: String = "assistant", seq: Int, at timestamp: String,
        input: Int = 0, output: Int = 0, reasoning: Int = 0, cacheRead: Int = 0, cacheWrite: Int = 0
    ) -> String {
        let created = millis(timestamp)
        let tokens = tokens(input: input, output: output, reasoning: reasoning, cacheRead: cacheRead, cacheWrite: cacheWrite)
        let data = #"{"time":{"created":\#(created)},"content":[],"cost":0.01,"tokens":\#(tokens)}"#
        return "INSERT INTO session_message VALUES ('\(id)', 'ses_1', '\(type)', \(seq), \(created), \(created), '\(data)')"
    }

    @Test func message_표에서_응답의_다섯_가지_토큰을_모두_더한다() throws {
        let fixture = try Fixture()
        let created = Self.millis("2026-11-14T01:00:00Z")
        try fixture.execute([
            Self.messageTable,
            "INSERT INTO message VALUES ('msg_u', 'ses_1', \(created), \(created), '{\"role\":\"user\",\"time\":{\"created\":\(created)}}')",
            Self.v1Assistant(id: "msg_1", at: "2026-11-14T01:00:05Z",
                             input: 10, output: 200, reasoning: 30, cacheRead: 40_000, cacheWrite: 3_000),
            // 응답이 아직 끝나지 않아 토큰이 0인 줄, JSON이 깨진 줄.
            Self.v1Assistant(id: "msg_2", at: "2026-11-14T01:00:09Z"),
            "INSERT INTO message VALUES ('msg_3', 'ses_1', \(created), \(created), '{깨진 JSON')",
        ])

        let records = OpenCodeUsageReader(root: fixture.root).records()
        #expect(records.count == 1)
        #expect(records[0].id == "opencode:msg_1")
        #expect(records[0].timestamp == (try Date("2026-11-14T01:00:05Z", strategy: .iso8601)))
        // reasoning은 output에 들어 있지 않으므로 더한다. input에는 캐시가 들어 있지 않다.
        #expect(records[0].usage == TokenUsage(input: 10, output: 230, cacheWrite: 3_000, cacheRead: 40_000))
        #expect(records[0].usage.total == 43_240)
    }

    @Test func session_message_표도_읽고_옮겨진_메시지는_한_번만_센다() throws {
        let fixture = try Fixture()
        try fixture.execute([
            Self.messageTable,
            Self.sessionMessageTable,
            Self.v1Assistant(id: "msg_1", at: "2026-11-14T01:00:00Z", input: 100, output: 10),
            // v1 메시지는 같은 id로 session_message에 복사된다.
            Self.v2Message(id: "msg_1", seq: 0, at: "2026-11-14T01:00:00Z", input: 100, output: 10),
            Self.v2Message(id: "msg_2", seq: 1, at: "2026-11-14T02:00:00Z",
                           input: 200, output: 20, reasoning: 5, cacheRead: 1_000),
            // 요약(compaction) 요청에도 토큰이 든다. 사용자 메시지에는 없다.
            Self.v2Message(id: "msg_3", type: "compaction", seq: 2, at: "2026-11-14T02:30:00Z", input: 300, output: 30),
            Self.v2Message(id: "msg_4", type: "user", seq: 3, at: "2026-11-14T02:40:00Z", input: 999),
        ])

        let reader = OpenCodeUsageReader(root: fixture.root)
        let records = reader.records()
        #expect(records.map(\.id) == ["opencode:msg_1", "opencode:msg_2", "opencode:msg_3"])
        #expect(records[1].usage == TokenUsage(input: 200, output: 25, cacheRead: 1_000))
        #expect(records.map(\.usage.total) == [110, 1_225, 330])
    }

    @Test func 기준_시각_이전은_세지_않고_장부에_두_번_넣어도_한_번만_센다() throws {
        let fixture = try Fixture()
        try fixture.execute([
            Self.messageTable,
            Self.v1Assistant(id: "msg_1", at: "2026-11-14T01:00:00Z", input: 1_000),
            Self.v1Assistant(id: "msg_2", at: "2026-11-14T03:00:00Z", input: 500, output: 50),
        ])
        let reader = OpenCodeUsageReader(root: fixture.root)
        let since = try Date("2026-11-14T02:00:00Z", strategy: .iso8601)
        #expect(reader.total(since: since).total == 550)
        #expect(reader.records(until: since).map(\.id) == ["opencode:msg_1"])

        var ledger = FundsLedger(startedAt: since)
        let now = since.addingTimeInterval(7_200)
        #expect(ledger.collect(reader.records(since: ledger.collectSince), now: now) == 550)
        #expect(ledger.collect(reader.records(since: ledger.collectSince), now: now.addingTimeInterval(60)) == 0)
    }

    @Test func opencode가_쓰는_중이어도_WAL에_있는_새_기록을_읽는다() throws {
        let fixture = try Fixture()
        try fixture.execute([Self.messageTable])
        // DB 파일 자체는 오래전에 수정된 것처럼 보이게 한다. 새 기록은 `-wal` 파일에만 있다.
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -86_400)], ofItemAtPath: fixture.databaseURL.path)

        let writer = try fixture.open()
        defer { sqlite3_close(writer) }
        let recent = Date(timeIntervalSinceNow: -60)
        let created = Int(recent.timeIntervalSince1970 * 1000)
        let data = #"{"role":"assistant","time":{"created":\#(created)},"tokens":\#(Self.tokens(input: 70, output: 7, reasoning: 0, cacheRead: 0, cacheWrite: 0))}"#
        try Fixture.run("INSERT INTO message VALUES ('msg_live', 'ses_1', \(created), \(created), '\(data)')", on: writer)

        let reader = OpenCodeUsageReader(root: fixture.root)
        let records = reader.records(since: Date(timeIntervalSinceNow: -3_600))
        #expect(records.map(\.id) == ["opencode:msg_live"])
        #expect(records.first?.usage.total == 77)

        // 응답이 끝나면서 같은 줄의 토큰이 늘어나면 늘어난 값을 돌려준다.
        let grown = data.replacingOccurrences(of: #""input":70"#, with: #""input":170"#)
        try Fixture.run("UPDATE message SET data = '\(grown)' WHERE id = 'msg_live'", on: writer)
        #expect(reader.records(since: Date(timeIntervalSinceNow: -3_600)).first?.usage.total == 177)
    }

    @Test func 오래_걸린_응답은_끝난_시각으로_센다() throws {
        let fixture = try Fixture()
        // 두 시간 전에 시작해서(도구 실행이 길었다) 방금 끝난 응답. 토큰은 끝날 때 적힌다.
        let created = Int(Date(timeIntervalSinceNow: -7_200).timeIntervalSince1970 * 1000)
        let completed = Int(Date(timeIntervalSinceNow: -30).timeIntervalSince1970 * 1000)
        let tokens = Self.tokens(input: 400, output: 40, reasoning: 0, cacheRead: 0, cacheWrite: 0)
        let v1 = #"{"role":"assistant","time":{"created":\#(created),"completed":\#(completed)},"tokens":\#(tokens)}"#
        let v2 = #"{"time":{"created":\#(created),"completed":\#(completed)},"content":[],"tokens":\#(tokens)}"#
        try fixture.execute([
            Self.messageTable,
            Self.sessionMessageTable,
            "INSERT INTO message VALUES ('msg_slow', 'ses_1', \(created), \(created), '\(v1)')",
            "INSERT INTO session_message VALUES ('msg_slow2', 'ses_1', 'assistant', 0, \(created), \(created), '\(v2)')",
        ])

        let reader = OpenCodeUsageReader(root: fixture.root)
        var ledger = FundsLedger(startedAt: Date(timeIntervalSinceNow: -3_600))
        #expect(ledger.collect(reader.records(since: ledger.collectSince), now: Date()) == 880)
        #expect(ledger.collect(reader.records(since: ledger.collectSince), now: Date()) == 0)
    }

    @Test func 예전_JSON_파일도_읽고_DB와_겹치면_한_번만_센다() throws {
        let fixture = try Fixture()
        let first = Self.millis("2026-11-14T01:00:00Z")
        let second = Self.millis("2026-11-14T01:05:00Z")
        try fixture.write("""
            {
              "id": "msg_1", "sessionID": "ses_1", "role": "assistant",
              "time": { "created": \(first), "completed": \(first + 4_000) },
              "cost": 0.01,
              "tokens": { "input": 100, "output": 10, "reasoning": 1, "cache": { "read": 1000, "write": 0 } }
            }
            """, to: "storage/message/ses_1/msg_1.json")
        try fixture.write("""
            { "id": "msg_2", "sessionID": "ses_1", "role": "assistant", "time": { "created": \(second) },
              "tokens": { "input": 5, "output": 5, "reasoning": 0, "cache": { "read": 0, "write": 0 } } }
            """, to: "storage/message/ses_1/msg_2.json")
        try fixture.write(#"{ "id": "msg_u", "role": "user", "time": { "created": \#(first) } }"#,
                          to: "storage/message/ses_1/msg_u.json")
        try fixture.write("깨진 파일", to: "storage/message/ses_1/msg_x.json")
        // SQLite로 옮겨진 뒤에도 메시지 id는 그대로다.
        try fixture.execute([
            Self.messageTable,
            Self.v1Assistant(id: "msg_1", at: "2026-11-14T01:00:00Z", input: 100, output: 10, reasoning: 1, cacheRead: 1_000),
        ])

        let records = OpenCodeUsageReader(root: fixture.root).records()
        #expect(records.map(\.id) == ["opencode:msg_1", "opencode:msg_2"])
        #expect(records[0].usage == TokenUsage(input: 100, output: 11, cacheRead: 1_000))
        #expect(records.map(\.usage.total) == [1_111, 10])
    }

    @Test func 폴더가_없거나_DB가_아닌_파일이면_빈_목록이다() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("token-baseball-missing-\(UUID().uuidString)", isDirectory: true)
        #expect(OpenCodeUsageReader(root: missing).records().isEmpty)
        #expect(OpenCodeUsageReader(root: missing).total(since: .distantPast) == .zero)

        let fixture = try Fixture()
        try fixture.write("SQLite 파일이 아니다", to: "opencode.db")
        // 표가 하나도 없는 DB.
        try fixture.execute(["CREATE TABLE other (id text)"], named: "opencode-dev.db")
        #expect(OpenCodeUsageReader(root: fixture.root).records().isEmpty)
    }
}
