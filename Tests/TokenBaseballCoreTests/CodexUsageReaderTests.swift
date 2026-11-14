import Foundation
import Testing
@testable import TokenBaseballCore

@Suite struct CodexUsageReaderTests {
    static func tokenCount(at timestamp: String, input: Int, cached: Int, output: Int) -> String {
        """
        {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\(input),"cached_input_tokens":\(cached),"output_tokens":\(output),"reasoning_output_tokens":0,"total_tokens":\(input + output)},"last_token_usage":{"input_tokens":\(input),"cached_input_tokens":\(cached),"output_tokens":\(output),"total_tokens":\(input + output)}}}}
        """
    }

    func write(_ lines: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("token-baseball-tests-\(UUID().uuidString)", isDirectory: true)
        let file = root.appendingPathComponent("2026/11/14/rollout-a.jsonl")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: file)
        return root
    }

    @Test func 반복해서_기록된_누적값은_늘어난_만큼만_센다() throws {
        let root = try write([
            #"{"timestamp":"2026-11-14T01:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":null}}"#,
            Self.tokenCount(at: "2026-11-14T01:00:01.000Z", input: 9_000, cached: 3_000, output: 40),
            Self.tokenCount(at: "2026-11-14T01:00:02.000Z", input: 9_000, cached: 3_000, output: 40),
            Self.tokenCount(at: "2026-11-14T01:00:09.000Z", input: 20_000, cached: 12_000, output: 100),
            Self.tokenCount(at: "2026-11-14T01:00:10.000Z", input: 20_000, cached: 12_000, output: 100),
            #"{"timestamp":"2026-11-14T01:00:11.000Z","type":"event_msg","payload":{"type":"agent_message","message":"token_count 라는 글자"}}"#,
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let records = CodexUsageReader(root: root).records()
        #expect(records.count == 2)
        // input에는 캐시 읽기가 들어 있으므로 합계는 input + output과 같다.
        #expect(records.reduce(0) { $0 + $1.usage.total } == 20_100)
        #expect(records[0].usage == TokenUsage(input: 6_000, output: 40, cacheRead: 3_000))
        #expect(records[1].usage == TokenUsage(input: 2_000, output: 60, cacheRead: 9_000))
    }

    @Test func 기준_시각_이전은_세지_않고_장부에_두_번_넣어도_한_번만_센다() throws {
        let root = try write([
            Self.tokenCount(at: "2026-11-14T01:00:00.000Z", input: 1_000, cached: 0, output: 0),
            Self.tokenCount(at: "2026-11-14T03:00:00.000Z", input: 1_500, cached: 0, output: 50),
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let reader = CodexUsageReader(root: root)
        let since = try Date("2026-11-14T02:00:00Z", strategy: .iso8601)
        #expect(reader.total(since: since).total == 550)

        var ledger = FundsLedger(startedAt: since)
        let now = since.addingTimeInterval(7_200)
        #expect(ledger.collect(reader.records(since: ledger.collectSince), now: now) == 550)
        #expect(ledger.collect(reader.records(since: ledger.collectSince), now: now.addingTimeInterval(60)) == 0)
    }
}
