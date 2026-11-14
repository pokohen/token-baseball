import Foundation
import Testing
@testable import TokenBaseballCore

@Suite struct FundsLedgerTests {
    static let start = Date(timeIntervalSince1970: 1_800_000_000)

    static func at(_ minutes: Double) -> Date {
        start.addingTimeInterval(minutes * 60)
    }

    static func record(_ id: String, at minutes: Double, tokens: Int) -> UsageRecord {
        UsageRecord(id: id, timestamp: at(minutes), usage: TokenUsage(output: tokens))
    }

    @Test func 시작_자금은_10만원이다() {
        let ledger = FundsLedger(startedAt: Self.start)

        #expect(ledger.balance == 100_000)
        #expect(ledger.tokenIncome == 0)
    }

    @Test func 토큰_수만큼_자금이_는다() {
        var ledger = FundsLedger(startedAt: Self.start)

        let earned = ledger.collect([
            Self.record("a", at: 1, tokens: 3_000),
            Self.record("b", at: 2, tokens: 500),
        ], now: Self.at(5))

        #expect(earned == 3_500)
        #expect(ledger.balance == 103_500)
        #expect(ledger.tokenIncome == 3_500)
        #expect(ledger.checkpoint == Self.at(5))
    }

    @Test func 같은_기록을_다시_넣어도_한_번만_센다() {
        var ledger = FundsLedger(startedAt: Self.start)
        let records = [Self.record("a", at: 1, tokens: 3_000)]

        ledger.collect(records, now: Self.at(5))
        let again = ledger.collect(records, now: Self.at(6))

        #expect(again == 0)
        #expect(ledger.balance == 103_000)
    }

    @Test func 응답이_끝나며_늘어난_사용량은_차이만_더한다() {
        var ledger = FundsLedger(startedAt: Self.start)

        ledger.collect([Self.record("a", at: 1, tokens: 100)], now: Self.at(2))
        let earned = ledger.collect([Self.record("a", at: 1, tokens: 900)], now: Self.at(3))

        #expect(earned == 800)
        #expect(ledger.balance == 100_900)
    }

    @Test func 구단을_만들기_전_사용량은_소급하지_않는다() {
        var ledger = FundsLedger(startedAt: Self.start)

        let earned = ledger.collect([
            Self.record("old", at: -1, tokens: 9_999_999),
            Self.record("new", at: 0, tokens: 10),
        ], now: Self.at(1))

        #expect(earned == 10)
    }

    @Test func 로그가_지워져도_자금은_줄지_않는다() {
        var ledger = FundsLedger(startedAt: Self.start)
        ledger.collect([Self.record("a", at: 1, tokens: 3_000)], now: Self.at(5))

        // 한참 뒤, 예전 로그는 사라지고 새 기록만 남았다.
        let muchLater = 60.0 * 24 * 40
        let earned = ledger.collect(
            [Self.record("b", at: muchLater - 1, tokens: 200)], now: Self.at(muchLater))

        #expect(earned == 200)
        #expect(ledger.balance == 103_200)
    }

    @Test func 오래_지난_기록이_다시_들어와도_세지_않는다() {
        var ledger = FundsLedger(startedAt: Self.start)
        let old = Self.record("a", at: 1, tokens: 3_000)
        ledger.collect([old], now: Self.at(5))
        ledger.collect([], now: Self.at(600))

        // 기억해 두는 시간(1시간)이 지나 "a"는 잊었지만, 읽기 시작점보다 앞이라 다시 세지 않는다.
        let earned = ledger.collect([old], now: Self.at(601))

        #expect(earned == 0)
        #expect(ledger.collectSince == Self.at(601 - 60))
    }

    @Test func 지난_반영_직전에_시작해_뒤늦게_기록된_응답도_센다() {
        var ledger = FundsLedger(startedAt: Self.start)
        ledger.collect([Self.record("a", at: 100, tokens: 10)], now: Self.at(101))

        // 100.5분에 시작한 응답이 101분 반영 때는 아직 로그에 없었다.
        let earned = ledger.collect([
            Self.record("a", at: 100, tokens: 10),
            Self.record("late", at: 100.5, tokens: 70),
        ], now: Self.at(102))

        #expect(earned == 70)
    }

    @Test func 시계가_뒤로_가도_반영_시점은_되돌아가지_않는다() {
        var ledger = FundsLedger(startedAt: Self.start)
        ledger.collect([], now: Self.at(500))
        ledger.collect([], now: Self.at(10))

        #expect(ledger.checkpoint == Self.at(500))
    }
}

@Suite struct SaveStoreTests {
    static func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("token-baseball-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("save.json")
    }

    @Test func 저장_파일이_없으면_nil이다() throws {
        #expect(try SaveStore(fileURL: Self.temporaryFile()).load() == nil)
    }

    @Test func 저장한_것을_그대로_다시_읽는다() throws {
        let file = Self.temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = SaveStore(fileURL: file)

        let start = Date(timeIntervalSince1970: 1_800_000_000.123)
        var game = Game.newGame(setup: .init(city: "부산", name: "부산 시민 야구단"), now: start, seed: 5)
        let record = UsageRecord(
            id: "a", timestamp: start.addingTimeInterval(1.456), usage: TokenUsage(output: 3_000))
        game.funds.collect([record], now: start.addingTimeInterval(10))
        try store.save(GameSave(game: game))

        var loaded = try #require(try store.load()).game
        #expect(loaded == game)
        // 다시 읽은 뒤에도 같은 응답을 또 세지 않는다.
        #expect(loaded.funds.collect([record], now: start.addingTimeInterval(20)) == 0)
        #expect(loaded.funds.balance == 103_000)
    }

    @Test func 깨진_저장_파일은_오류를_던진다() throws {
        let file = Self.temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ 깨짐".utf8).write(to: file)

        #expect(throws: (any Error).self) { try SaveStore(fileURL: file).load() }
    }
}
