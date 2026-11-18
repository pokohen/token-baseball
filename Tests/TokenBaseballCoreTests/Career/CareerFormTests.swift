import Foundation
import Testing
@testable import TokenBaseballCore

@Suite struct CareerFormTests {
    let start = Date(timeIntervalSince1970: 0)

    func make(_ position: Position = .shortstop, seed: UInt64 = 91) -> Game {
        var game = Game.newCareer(setup: CareerSetup(name: "폼 선수", position: position), now: start, seed: seed)
        game.funds.earn(1_000_000_000, .tokens)
        return game
    }

    func performance(_ rating: Double, scored: Bool? = true) -> Game.CareerPerformance {
        Game.CareerPerformance(rating: rating, line: "테스트", scored: scored)
    }

    @Test func 컨디션은_경기마다_새로_정해지고_능력치에_반영된다() throws {
        var game = make()
        #expect(game.careerCondition == .normal)
        var seen = Set<CareerCondition>()
        for _ in 0..<200 {
            _ = game.settleCareer(kind: .regular, performance: performance(6.2))
            seen.insert(game.careerCondition)
        }
        #expect(seen.count == CareerCondition.allCases.count)

        game.career?.condition = .best
        game.career?.streak = 0
        let me = game.myPlayer!
        try game.startMatch(now: start)
        let side = game.live!.userIsHome ? game.live!.state.home : game.live!.state.away
        let batter = side.batters.first { $0.playerID == me.id }!
        #expect(abs(batter.contact - min(99, me.attributes[.contact] * 1.06)) < 0.0001)
        // 선수 본래 능력치는 그대로다.
        #expect(game.myPlayer!.attributes[.contact] == me.attributes[.contact])
    }

    @Test func 세_경기_연속_활약하면_기세가_붙고_부진하면_끊긴다() {
        var game = make()
        for _ in 0..<2 { _ = game.settleCareer(kind: .regular, performance: performance(7.5)) }
        #expect(game.careerMomentum == 0)
        let lines = game.settleCareer(kind: .regular, performance: performance(7.5))
        #expect(game.careerStreak == 3 && game.careerMomentum == Balance.careerMomentum)
        #expect(lines.contains { $0.contains("기세") })
        _ = game.settleCareer(kind: .regular, performance: performance(6.2))
        #expect(game.careerStreak == 0 && game.careerMomentum == 0)
        for _ in 0..<3 { _ = game.settleCareer(kind: .regular, performance: performance(5.0)) }
        #expect(game.careerStreak == -3 && game.careerMomentum == -Balance.careerMomentum)
        // 친선 경기는 세지 않는다.
        _ = game.settleCareer(kind: .friendly, performance: performance(9.0))
        #expect(game.careerStreak == -3)
    }

    @Test func 연속_기록을_세고_개인_최고를_남긴다() {
        var game = make()
        for _ in 0..<4 { _ = game.settleCareer(kind: .regular, performance: performance(6.5, scored: true)) }
        _ = game.settleCareer(kind: .regular, performance: performance(6.5, scored: false))
        #expect(game.career?.run == 0 && game.career?.bestRun == 4)
        #expect(game.careerRunLabel == "연속 안타")
    }

    @Test(arguments: [Position.shortstop, .starter, .reliever, .forward, .goalkeeper])
    func 라이벌은_같은_리그_다른_구단의_같은_역할_선수다(position: Position) throws {
        let game = make(position)
        let me = try #require(game.myPlayer)
        let rival = try #require(game.careerRival)
        let team = try #require(rival.teamID)
        #expect(team != game.userTeamID && game.teams[team].tier == game.userTier)
        #expect(rival.position.sport == me.position.sport && rival.isPitcher == me.isPitcher)
        if me.position.sport == .football { #expect(rival.position == me.position) }
    }

    @Test func 라이벌보다_평점이_높으면_맞대결에서_이기고_명성이_오른다() {
        var game = make()
        let fame = game.career?.fame ?? 0
        let lines = game.settleCareer(kind: .regular, performance: performance(6.4), rival: performance(6.0))
        #expect(game.career?.rival?.wins == 1)
        #expect((game.career?.fame ?? 0) >= fame + Balance.careerRivalFame - 0.0001)
        #expect(lines.contains { $0.contains("라이벌") })
        _ = game.settleCareer(kind: .regular, performance: performance(5.8), rival: performance(7.0))
        #expect(game.career?.rival?.losses == 1)
        // 한쪽이 뛰지 않았으면 세지 않는다.
        _ = game.settleCareer(kind: .regular, performance: performance(7.0), rival: nil)
        #expect(game.career?.rival?.wins == 1 && game.career?.rival?.losses == 1)
    }

    @Test func 리그가_달라지면_라이벌이_새로_정해진다() throws {
        var game = make()
        let first = try #require(game.career?.rival?.playerID)
        let upper = try #require(game.teams.first { $0.tier != game.userTier })
        game.joinCareerClub(upper.id)
        let second = try #require(game.careerRival)
        #expect(second.id != first)
        #expect(second.teamID.map { game.teams[$0].tier } == game.userTier)
        #expect(game.career?.rival?.wins == 0)
    }

    @Test func 토큰으로_치른_경기는_평점에_따라_능력이_조금_오른다() throws {
        #expect(Game.careerExtraMatchGain(rating: 4) == Balance.careerExtraMatchBase)
        #expect(Game.careerExtraMatchGain(rating: 10) == Balance.careerExtraMatchMax)
        #expect(Game.careerExtraMatchGain(rating: 8) > Game.careerExtraMatchGain(rating: 6.5))

        var game = make()
        while game.charges > 0 {
            try game.startMatch(now: start)
            game.runMatchToEnd()
        }
        #expect(game.extraMatchPending == nil)
        let before = game.myPlayer!.ability
        try game.buyExtraMatch(now: start)
        #expect(game.extraMatchPending == true)
        try game.startMatch(now: start)
        game.runMatchToEnd()
        #expect(game.extraMatchPending == nil)
        let gained = game.myPlayer!.ability - before
        #expect(gained > 0 && gained <= Balance.careerExtraMatchMax + 0.2)

        // 평소 경기에서는 이 보너스가 없다.
        var plain = make()
        let lines = plain.settleCareer(kind: .regular, performance: performance(9))
        #expect(!lines.contains { $0.contains("실전 경험") })
    }

    @Test func 실전_경험도_한계를_넘지_못한다() {
        var game = make()
        var me = game.myPlayer!
        me.potential = me.ability + 0.01
        game.players[me.id] = me
        let gained = game.applyCareerExtraMatchGain(rating: 10)
        #expect(gained <= 0.0101)
        #expect(game.myPlayer!.ability <= game.myPlayer!.potential + 0.0001)
    }

    @Test func 새_시즌에_내가_크게_앞서_있으면_라이벌이_바뀐다() throws {
        var game = make()
        let first = try #require(game.careerRival)
        // 시즌 중에는 앞서 있어도 그대로다.
        var me = game.myPlayer!
        for key in game.careerTrainableKeys { me.attributes[key] += 10 }
        me.potential = 99
        game.players[me.id] = me
        #expect(game.refreshCareerRival() == nil)
        #expect(game.careerRival?.id == first.id)
        #expect(game.refreshCareerRival(seasonStart: true) != nil)
        #expect(game.careerRival?.id != first.id)
    }
}
