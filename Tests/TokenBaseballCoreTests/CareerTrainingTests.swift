import Foundation
import Testing
@testable import TokenBaseballCore

@Suite struct CareerTrainingTests {
    @Test func 훈련_포인트를_써서_능력치를_올린다() throws {
        var game = TestCareer.make(.shortstop)
        #expect(Set(game.careerTrainableKeys) == [.contact, .power, .eye, .speed, .fielding, .arm])
        // 시작 포인트(10만)로는 첫 훈련을 할 수 없다.
        #expect(throws: GameError.self) { try game.trainCareer(.contact) }

        TestGame.addTokens(&game, 10_000_000, id: "a", at: TestGame.hours(1))
        let before = try #require(game.myPlayer)
        let cost = game.careerTrainingCost(.contact)
        #expect(cost == Balance.careerTrainingCost(value: before.attributes.contact))
        let balance = game.funds.balance
        try game.trainCareer(.contact)
        let after = try #require(game.myPlayer)
        #expect(after.attributes.contact == before.attributes.contact + 1)
        #expect(after.ability > before.ability)
        #expect(game.funds.balance == balance - cost)
        #expect(game.funds.seasonExpense[FundsLedger.Category.training.rawValue] == cost)
    }

    @Test func 경기_사이에_정해진_횟수만_훈련한다() throws {
        var game = TestCareer.make(.starter)
        #expect(Set(game.careerTrainableKeys) == [.stuff, .control, .breaking, .stamina])
        TestGame.addTokens(&game, 50_000_000, id: "a", at: TestGame.hours(1))
        for _ in 0..<Balance.careerSessionsPerMatch { try game.trainCareer(.stuff) }
        #expect(game.career?.sessionsLeft == 0)
        #expect(throws: GameError.self) { try game.trainCareer(.control) }
        // 타자 능력치는 투수가 올릴 수 없다.
        #expect(game.careerTrainingBlockedReason(.contact) != nil)

        try TestGame.playOne(&game, at: TestGame.hours(2))
        #expect(game.career?.sessionsLeft == Balance.careerSessionsPerMatch)
        try game.trainCareer(.control)
    }

    @Test func 가격_난이도가_훈련_비용에도_적용된다() {
        var game = TestCareer.make(.first)
        let normal = game.careerTrainingCost(.power)
        game.settings.priceDifficulty = 0.5
        #expect(game.careerTrainingCost(.power) == normal / 2)
    }

    @Test func 잠재력과_나이가_훈련의_한계다() throws {
        var game = TestCareer.make(.first)
        TestGame.addTokens(&game, 500_000_000, id: "a", at: TestGame.hours(1))
        let id = try #require(game.career?.playerID)

        // 한계에 가까우면 비용이 두 배.
        let cost = game.careerTrainingCost(.power)
        let ability = try #require(game.myPlayer).ability
        game.players[id]?.potential = ability + 5
        #expect(game.careerTrainingCost(.power) == cost * 2)
        // 한계에 닿으면 오르지 않는다.
        game.players[id]?.potential = ability
        #expect(throws: GameError.self) { try game.trainCareer(.power) }

        game.players[id]?.potential = 90
        game.players[id]?.age = Balance.careerTrainingAgeLimit
        #expect(throws: GameError.self) { try game.trainCareer(.power) }
        game.players[id]?.age = Balance.careerTrainingAgeLimit - 1
        try game.trainCareer(.power)
    }
}

@Suite struct CareerCostTests {
    @Test func 훈련할_때마다_비용이_조금씩_오른다() throws {
        var game = TestCareer.make(.starter)
        TestGame.addTokens(&game, 50_000_000, id: "a", at: TestGame.hours(1))
        let first = game.careerTrainingCost(.stuff)
        try game.trainCareer(.stuff)
        let second = game.careerTrainingCost(.stuff)
        #expect(second > first)
        #expect(Double(second) < Double(first) * 1.15)
        // 값이 오를수록 계속 비싸진다.
        let costs = stride(from: 1.0, through: 99.0, by: 1).map { Balance.careerTrainingCost(value: $0) }
        #expect(zip(costs, costs.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(Balance.careerTrainingCost(value: 25) == 250_000)
    }
}
