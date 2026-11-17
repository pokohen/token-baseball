import Foundation
import Testing
@testable import TokenBaseballCore

@Suite struct ExtraMatchTests {
    @Test func 경기_기회가_없을_때_토큰으로_하나_살_수_있다() throws {
        var game = TestGame.make(seed: 95)
        // 기회가 남아 있으면 살 수 없다.
        #expect(game.charges == 1)
        #expect(throws: GameError.self) { try game.buyExtraMatch(now: TestGame.start) }

        try TestGame.playOne(&game, at: TestGame.start)
        #expect(game.charges == 0)
        // 자금이 모자라면 살 수 없다.
        #expect(game.extraMatchBlockedReason != nil)
        #expect(throws: GameError.self) { try game.buyExtraMatch(now: TestGame.start.addingTimeInterval(60)) }

        TestGame.addTokens(&game, 50_000_000, id: "a", at: TestGame.start.addingTimeInterval(60))
        let balance = game.funds.balance
        #expect(game.extraMatchCost == Balance.extraMatchCost)
        try game.buyExtraMatch(now: TestGame.start.addingTimeInterval(120))
        #expect(game.charges == 1)
        #expect(game.funds.balance == balance - Balance.extraMatchCost)
        #expect(game.funds.seasonExpense[FundsLedger.Category.extraMatch.rawValue] == Balance.extraMatchCost)

        // 산 기회로 바로 경기를 치른다.
        try TestGame.playOne(&game, at: TestGame.start.addingTimeInterval(180))
        #expect(game.round == 2)
        // 연달아 사면 두 배.
        #expect(game.extraMatchCost == Balance.extraMatchCost * 2)
        try game.buyExtraMatch(now: TestGame.start.addingTimeInterval(240))
        #expect(game.extraMatchCost == Balance.extraMatchCost * 4)
    }

    @Test func 경기_기회가_저절로_생기면_값이_처음으로_돌아간다() throws {
        var game = TestGame.make(seed: 96)
        try TestGame.playOne(&game, at: TestGame.start)
        TestGame.addTokens(&game, 50_000_000, id: "a", at: TestGame.start.addingTimeInterval(60))
        try game.buyExtraMatch(now: TestGame.start.addingTimeInterval(120))
        try TestGame.playOne(&game, at: TestGame.start.addingTimeInterval(180))
        #expect(game.extraMatchCost == Balance.extraMatchCost * 2)
        game.refreshCharges(now: TestGame.hours(1.5))
        #expect(game.charges == 1)
        #expect(game.extraMatchCost == Balance.extraMatchCost)
    }

    @Test func 값에는_가격_난이도가_적용되고_끝없이_오르지_않는다() {
        var game = TestGame.make(seed: 97)
        game.settings.priceDifficulty = 0.5
        #expect(game.extraMatchCost == Balance.extraMatchCost / 2)
        game.settings.priceDifficulty = 1
        game.extraMatchesBought = 50
        #expect(game.extraMatchCost == Balance.extraMatchCost << Balance.extraMatchMaxDoublings)
    }

    @Test func 선수_모드에서는_훈련_포인트로_산다() throws {
        var game = TestCareer.make(.shortstop, seed: 98)
        try TestGame.playOne(&game, at: TestGame.start)
        TestGame.addTokens(&game, 10_000_000, id: "a", at: TestGame.start.addingTimeInterval(60))
        let points = game.funds.balance
        try game.buyExtraMatch(now: TestGame.start.addingTimeInterval(120))
        #expect(game.funds.balance == points - Balance.extraMatchCost)
        try TestGame.playOne(&game, at: TestGame.start.addingTimeInterval(180))
        #expect(game.myPlayer?.batting.games == 2)
    }
}
