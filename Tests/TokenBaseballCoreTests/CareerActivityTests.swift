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
}
