import Foundation
import Testing
@testable import TokenBaseballCore

@Suite struct GeminiUsageReaderTests {
    /// 임시 폴더에 로그 파일을 만들고, 테스트가 끝나면 지운다.
    final class Fixture {
        let root: URL

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("token-baseball-tests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        func write(_ text: String, to path: String) throws {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }

        func write(_ lines: [String], to path: String) throws {
            try write(lines.joined(separator: "\n") + "\n", to: path)
        }
    }

    static func header(session: String) -> String {
        #"{"sessionId":"\#(session)","projectHash":"abc","startTime":"2026-11-14T00:59:00.000Z","lastUpdated":"2026-11-14T00:59:00.000Z","kind":"main"}"#
    }

    /// Gemini CLI가 적는 응답 한 줄. total = input + output + thoughts + tool.
    static func gemini(
        id: String, at timestamp: String,
        input: Int, output: Int, cached: Int = 0, thoughts: Int = 0, tool: Int = 0
    ) -> String {
        """
        {"id":"\(id)","timestamp":"\(timestamp)","type":"gemini","content":"답","thoughts":[],"tokens":{"input":\(input),"output":\(output),"cached":\(cached),"thoughts":\(thoughts),"tool":\(tool),"total":\(input + output + thoughts + tool)},"model":"gemini-3-pro"}
        """
    }

    @Test func 캐시는_입력에서_떼어내고_생각과_도구_토큰도_센다() throws {
        let fixture = try Fixture()
        try fixture.write([
            Self.header(session: "s1"),
            #"{"id":"u1","timestamp":"2026-11-14T01:00:00.000Z","type":"user","content":[{"text":"tokens 라는 글자"}]}"#,
            Self.gemini(id: "m1", at: "2026-11-14T01:00:05.000Z",
                        input: 10_000, output: 200, cached: 4_000, thoughts: 300, tool: 50),
            #"{"$set":{"lastUpdated":"2026-11-14T01:00:05.000Z"}}"#,
            "깨진 줄 {\"tokens\"",
        ], to: "project-a/chats/session-2026-11-14T01-00-s1.jsonl")

        let records = GeminiUsageReader(root: fixture.root).records()
        #expect(records.count == 1)
        #expect(records[0].id == "gemini:s1:m1")
        #expect(records[0].usage == TokenUsage(input: 6_050, output: 500, cacheRead: 4_000))
        // 합계는 로그의 total과 같다. 캐시를 두 번 세지 않는다.
        #expect(records[0].usage.total == 10_550)
    }

    @Test func 같은_메시지가_다시_덧붙어도_한_번만_센다() throws {
        let fixture = try Fixture()
        try fixture.write([
            Self.header(session: "s1"),
            // 처음에는 토큰 없이 적히고, 토큰이 붙은 뒤와 도구 결과가 붙은 뒤에 같은 id로 다시 적힌다.
            #"{"id":"m1","timestamp":"2026-11-14T01:00:05.000Z","type":"gemini","content":"","tokens":null}"#,
            Self.gemini(id: "m1", at: "2026-11-14T01:00:05.000Z", input: 1_000, output: 100),
            Self.gemini(id: "m1", at: "2026-11-14T01:00:05.000Z", input: 1_000, output: 100),
            Self.gemini(id: "m2", at: "2026-11-14T01:00:09.000Z", input: 2_000, output: 50),
            // 되감아서 지운 응답도 토큰은 이미 썼다.
            #"{"$rewindTo":"m2"}"#,
        ], to: "project-a/chats/session-a.jsonl")

        let reader = GeminiUsageReader(root: fixture.root)
        #expect(reader.records().map(\.id) == ["gemini:s1:m1", "gemini:s1:m2"])
        #expect(reader.total(since: .distantPast).total == 3_150)
    }

    @Test func 기준_시각_이전은_세지_않고_장부에_두_번_넣어도_한_번만_센다() throws {
        let fixture = try Fixture()
        try fixture.write([
            Self.header(session: "s1"),
            Self.gemini(id: "m1", at: "2026-11-14T01:00:00.000Z", input: 1_000, output: 0),
            Self.gemini(id: "m2", at: "2026-11-14T03:00:00.000Z", input: 500, output: 50),
        ], to: "project-a/chats/session-a.jsonl")
        let reader = GeminiUsageReader(root: fixture.root)
        let since = try Date("2026-11-14T02:00:00Z", strategy: .iso8601)
        #expect(reader.total(since: since).total == 550)

        var ledger = FundsLedger(startedAt: since)
        let now = since.addingTimeInterval(7_200)
        #expect(ledger.collect(reader.records(since: ledger.collectSince), now: now) == 550)
        #expect(ledger.collect(reader.records(since: ledger.collectSince), now: now.addingTimeInterval(60)) == 0)
    }

    @Test func 예전_json_세션과_이어_쓴_jsonl을_두_번_세지_않는다() throws {
        let fixture = try Fixture()
        // 예전 형식: 세션 전체가 여러 줄에 걸친 JSON 하나다.
        try fixture.write("""
            {
              "sessionId": "old",
              "projectHash": "abc",
              "startTime": "2026-11-14T01:00:00.000Z",
              "lastUpdated": "2026-11-14T01:00:05.000Z",
              "messages": [
                { "id": "u1", "timestamp": "2026-11-14T01:00:00.000Z", "type": "user", "content": "안녕" },
                {
                  "id": "m1", "timestamp": "2026-11-14T01:00:05.000Z", "type": "gemini", "content": "답",
                  "tokens": { "input": 800, "output": 20, "cached": 300, "total": 820 }
                },
                { "id": 7 }
              ]
            }
            """, to: "project-a/chats/session-old.json")
        // 이어 쓰면 같은 내용이 `.jsonl`로 다시 저장되고 그 뒤에 새 응답이 붙는다.
        try fixture.write([
            Self.header(session: "old"),
            Self.gemini(id: "m1", at: "2026-11-14T01:00:05.000Z", input: 800, output: 20, cached: 300),
            Self.gemini(id: "m2", at: "2026-11-14T01:10:00.000Z", input: 900, output: 30),
        ], to: "project-a/chats/session-old.jsonl")

        let records = GeminiUsageReader(root: fixture.root).records()
        #expect(records.map(\.id) == ["gemini:old:m1", "gemini:old:m2"])
        #expect(records[0].usage == TokenUsage(input: 500, output: 20, cacheRead: 300))
        #expect(records.map(\.usage.total) == [820, 930])
    }

    @Test func chats_폴더_밖의_파일과_임시_파일은_읽지_않는다() throws {
        let fixture = try Fixture()
        let lines = [
            Self.header(session: "s1"),
            Self.gemini(id: "m1", at: "2026-11-14T01:00:00.000Z", input: 100, output: 10),
        ]
        try fixture.write(lines, to: "project-a/logs.json")
        try fixture.write(lines, to: "project-a/chats/session-a.jsonl.tmp-123")
        try fixture.write(lines, to: "project-a/chats/session-a.jsonl.unreadable-1")
        // 하위 에이전트의 기록은 부모 세션 폴더 아래에 따로 있다.
        try fixture.write([
            Self.header(session: "sub"),
            Self.gemini(id: "m1", at: "2026-11-14T01:00:01.000Z", input: 7, output: 3),
        ], to: "project-a/chats/s1/sub.jsonl")

        let records = GeminiUsageReader(root: fixture.root).records()
        #expect(records.map(\.id) == ["gemini:sub:m1"])
    }

    @Test func 폴더가_없으면_빈_목록이다() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("token-baseball-missing-\(UUID().uuidString)", isDirectory: true)
        #expect(GeminiUsageReader(root: missing).records().isEmpty)
        #expect(GeminiUsageReader(root: missing).total(since: .distantPast) == .zero)
    }
}
