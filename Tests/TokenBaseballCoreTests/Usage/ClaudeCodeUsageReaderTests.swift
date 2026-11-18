import Foundation
import Testing
@testable import TokenBaseballCore

@Suite struct ClaudeCodeUsageReaderTests {
    /// 임시 폴더에 로그 파일을 만들고, 테스트가 끝나면 지운다.
    final class Fixture {
        let root: URL

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("token-baseball-tests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        func write(_ lines: [String], to path: String) throws {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
        }
    }

    static func assistant(
        id: String, at timestamp: String,
        input: Int = 0, output: Int = 0, cacheWrite: Int = 0, cacheRead: Int = 0
    ) -> String {
        """
        {"type":"assistant","timestamp":"\(timestamp)","requestId":"req_\(id)","message":{"id":"\(id)","model":"claude-opus-5-5","usage":{"input_tokens":\(input),"output_tokens":\(output),"cache_creation_input_tokens":\(cacheWrite),"cache_read_input_tokens":\(cacheRead),"service_tier":"standard"}}}
        """
    }

    static func date(_ string: String) -> Date {
        try! Date(string, strategy: .iso8601)
    }

    @Test func 네_가지_토큰을_모두_더한다() throws {
        let fixture = try Fixture()
        try fixture.write([
            Self.assistant(id: "msg_1", at: "2026-11-14T01:00:00.000Z",
                           input: 10, output: 200, cacheWrite: 3_000, cacheRead: 40_000),
        ], to: "project-a/session-1.jsonl")

        let usage = ClaudeCodeUsageReader(root: fixture.root).total(since: .distantPast)

        #expect(usage == TokenUsage(input: 10, output: 200, cacheWrite: 3_000, cacheRead: 40_000))
        #expect(usage.total == 43_210)
    }

    @Test func 같은_응답이_여러_줄이면_한_번만_센다() throws {
        let fixture = try Fixture()
        try fixture.write([
            // 스트리밍 도중 기록된 줄은 사용량이 더 적을 수 있다. 가장 큰 값을 쓴다.
            Self.assistant(id: "msg_1", at: "2026-11-14T01:00:00.100Z", input: 5, output: 1),
            Self.assistant(id: "msg_1", at: "2026-11-14T01:00:01.200Z", input: 5, output: 100),
            Self.assistant(id: "msg_1", at: "2026-11-14T01:00:02.300Z", input: 5, output: 100),
            Self.assistant(id: "msg_2", at: "2026-11-14T01:05:00.000Z", input: 7, output: 50),
        ], to: "project-a/session-1.jsonl")
        // 이어서 연 세션 파일에 같은 응답이 다시 들어 있는 경우
        try fixture.write([
            Self.assistant(id: "msg_2", at: "2026-11-14T01:05:00.000Z", input: 7, output: 50),
        ], to: "project-a/session-2.jsonl")

        let records = ClaudeCodeUsageReader(root: fixture.root).records()

        #expect(records.map(\.id) == ["msg_1", "msg_2"])
        #expect(records.map(\.usage.total) == [105, 57])
        #expect(records[0].timestamp == Self.date("2026-11-14T01:00:00Z").addingTimeInterval(0.1))
    }

    @Test func 기준_시각_이전_사용량은_세지_않는다() throws {
        let fixture = try Fixture()
        try fixture.write([
            Self.assistant(id: "msg_before", at: "2026-11-13T23:59:59.999Z", output: 1_000),
            Self.assistant(id: "msg_exact", at: "2026-11-14T00:00:00.000Z", output: 20),
            Self.assistant(id: "msg_after", at: "2026-11-14T09:30:00.000Z", output: 3),
        ], to: "project-a/session-1.jsonl")
        let reader = ClaudeCodeUsageReader(root: fixture.root)

        let installedAt = Self.date("2026-11-14T00:00:00Z")
        #expect(reader.total(since: installedAt).total == 23)
        #expect(reader.total(since: installedAt, until: Self.date("2026-11-14T09:00:00Z")).total == 20)
    }

    @Test func 하위_에이전트_로그도_읽는다() throws {
        let fixture = try Fixture()
        try fixture.write([
            Self.assistant(id: "msg_main", at: "2026-11-14T01:00:00.000Z", output: 10),
        ], to: "project-a/session-1.jsonl")
        try fixture.write([
            Self.assistant(id: "msg_sub", at: "2026-11-14T01:01:00.000Z", output: 5),
        ], to: "project-a/session-1/subagents/agent-abc.jsonl")

        #expect(ClaudeCodeUsageReader(root: fixture.root).total(since: .distantPast).total == 15)
    }

    @Test func 사용량이_없는_줄과_깨진_줄은_건너뛴다() throws {
        let fixture = try Fixture()
        try fixture.write([
            #"{"type":"user","timestamp":"2026-11-14T01:00:00.000Z","message":{"role":"user","content":"\"usage\" 라는 글자가 들어간 사용자 메시지"}}"#,
            #"{"type":"system","timestamp":"2026-11-14T01:00:00.000Z"}"#,
            #"{"type":"assistant","timestamp":"2026-11-14T01:00:00.000Z","message":{"id":"msg_no_usage"}}"#,
            #"{"type":"assistant","message":{"id":"msg_cut","usage":{"input_tok"#,
            "",
            Self.assistant(id: "msg_ok", at: "2026-11-14T01:00:00.000Z", output: 42),
        ], to: "project-a/session-1.jsonl")
        try fixture.write(["jsonl이 아닌 파일"], to: "project-a/notes.txt")

        let records = ClaudeCodeUsageReader(root: fixture.root).records()

        #expect(records.map(\.id) == ["msg_ok"])
        #expect(records.first?.usage.total == 42)
    }

    @Test func 로그_폴더가_없으면_0이다() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("token-baseball-missing-\(UUID().uuidString)")

        #expect(ClaudeCodeUsageReader(root: missing).total(since: .distantPast) == .zero)
    }
}
