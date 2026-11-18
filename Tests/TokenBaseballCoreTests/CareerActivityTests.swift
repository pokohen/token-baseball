import Foundation
import Testing
@testable import TokenBaseballCore

@Suite struct CareerActivityTests {
    func make() -> Game {
        var game = Game.newCareer(
            setup: CareerSetup(name: "활동 선수", position: .shortstop), now: Date(timeIntervalSince1970: 0), seed: 91)
        game.funds.earn(100_000_000, .tokens)
        return game
    }

    @Test func 명성_활동은_포인트를_쓰고_명성을_올린다() throws {
        var game = make()
        let before = (game.funds.balance, game.career?.fame ?? 0)
        let gain = game.careerActivityGain(.interview)
        try game.doCareerActivity(.interview)
        #expect(gain > 0)
        #expect(abs((game.career?.fame ?? 0) - before.1 - gain) < 0.0001)
        #expect(game.funds.balance == before.0 - game.careerActivityCost(.interview))
    }

    @Test func 경기_사이에_한_번만_하고_경기를_치르면_다시_할_수_있다() throws {
        var game = make()
        try game.doCareerActivity(.fanMeeting)
        #expect(throws: GameError.self) { try game.doCareerActivity(.fanMeeting) }
        try game.startMatch(now: Date(timeIntervalSince1970: 0))
        game.runMatchToEnd()
        #expect(game.careerActivityBlockedReason(.fanMeeting) == nil)
    }

    @Test func 리그의_명성_한도를_넘지_못하고_가까울수록_덜_오른다() throws {
        var game = make()
        let cap = Balance.careerFameCap(game.userTier)
        let first = game.careerActivityGain(.youthClinic)
        game.career?.fame = cap - 1
        #expect(game.careerActivityGain(.youthClinic) < first)
        try game.doCareerActivity(.youthClinic)
        #expect((game.career?.fame ?? 0) <= cap)
        game.career?.fame = cap
        game.career?.activityDone = nil
        #expect(game.careerActivityBlockedReason(.fanMeeting) != nil)
    }

    @Test func 유소년_교실은_감독_신뢰도_올린다() throws {
        var game = make()
        let trust = game.career?.trust ?? 0
        try game.doCareerActivity(.youthClinic)
        #expect(game.career?.trust == trust + 1)
    }

    @Test func 포인트가_모자라면_할_수_없다() {
        var game = make()
        game.funds.spend(game.funds.balance - 10, .training)
        #expect(throws: GameError.self) { try game.doCareerActivity(.fanMeeting) }
    }

    @Test func 선수_이름을_바꿀_수_있다() throws {
        var game = make()
        try game.renameCareerPlayer(to: "  새 이름 ")
        #expect(game.myPlayer?.name == "새 이름")
        #expect(throws: GameError.self) { try game.renameCareerPlayer(to: "   ") }
        #expect(throws: GameError.self) { try game.renameCareerPlayer(to: String(repeating: "가", count: 13)) }
        #expect(game.myPlayer?.name == "새 이름")
    }

    @Test func 크리티컬이_터지면_같은_포인트로_세_배_오른다() throws {
        var normal = make()
        var lucky = normal
        let key = normal.careerTrainableKeys[0]
        let before = normal.myPlayer!.attributes[key]
        let gain = normal.careerTrainingGain(key)
        try normal.trainCareer(key, critical: false)
        try lucky.trainCareer(key, critical: true)
        #expect(abs(normal.myPlayer!.attributes[key] - before - gain) < 0.0001)
        #expect(abs(lucky.myPlayer!.attributes[key] - before - gain * Balance.careerCriticalMultiplier) < 0.0001)
        #expect(lucky.funds.balance == normal.funds.balance)
        #expect(lucky.career?.lastCritical != nil && lucky.career?.criticalCount == 1)
        #expect(normal.career?.lastCritical == nil)
        // 다음 훈련이 보통이면 표시가 지워진다.
        try lucky.trainCareer(key, critical: false)
        #expect(lucky.career?.lastCritical == nil && lucky.career?.criticalCount == 1)
    }

    @Test func 크리티컬도_한계를_넘지_못한다() throws {
        var game = make()
        let key = game.careerTrainableKeys[0]
        var me = game.myPlayer!
        me.potential = me.ability + Balance.careerTrainingStep * 1.5
        game.players[me.id] = me
        try game.trainCareer(key, critical: true)
        #expect(game.myPlayer!.ability <= game.myPlayer!.potential + 0.0001)
    }

    @Test func 크리티컬은_백_번에_한_번쯤_터진다() throws {
        var game = make()
        game.funds.earn(2_000_000_000_000, .tokens)
        var count = 0
        let total = 20_000
        for _ in 0..<total where game.rng.chance(Balance.careerCriticalChance) { count += 1 }
        #expect(count > total / 200 && count < total / 50)
    }
}
