import Foundation
import Testing
@testable import TokenBaseballCore

@Suite struct CareerContractTests {
    @Test func 이적_제안을_받아들이면_구단을_옮긴다() throws {
        var game = TestCareer.make(.center, seed: 11)
        let id = try #require(game.career?.playerID)
        let old = game.userTeamID
        let target = try #require(game.teams(in: .citizenSemiPro).first).id
        let size = game.teams[target].roster.count
        game.career?.offers = [CareerOffer(
            id: 900, kind: .transfer, teamID: target, salary: 5_000_000, years: 3, role: .rotation, matchesLeft: 1)]
        game.career?.trust = 80

        try game.acceptCareerOffer(900)
        let me = try #require(game.myPlayer)
        #expect(game.userTeamID == target)
        #expect(me.teamID == target)
        #expect(me.contract == Contract(salary: 5_000_000, seasonsLeft: 3))
        #expect(game.teams[target].roster.count == size)
        #expect(!game.teams[old].roster.contains(id))
        #expect(game.career?.trust == Balance.careerStartTrust)
        #expect(game.career?.offers.isEmpty == true)
        #expect(game.career?.clubs.count == 2)
        #expect(game.career?.bestTier == .citizenSemiPro)

        // 옮긴 구단에서도, 떠난 구단도 경기를 치른다.
        var auto = CareerAuto()
        for _ in 0..<3 { try auto.playOne(&game) }
        #expect(try #require(game.myPlayer).batting.games == 3)
    }

    @Test func 연봉_인상은_제안마다_한_번만_요구한다() throws {
        var game = TestCareer.make(.center, seed: 12)
        let target = try #require(game.teams(in: .citizenAmateur).first { $0.id != game.userTeamID }).id
        game.career?.offers = [CareerOffer(
            id: 901, kind: .renewal, teamID: target, salary: 1_000_000, years: 1, role: .starter, matchesLeft: 99)]
        try game.negotiateCareerOffer(901)
        let offer = try #require(game.career?.offers.first)
        #expect(offer.negotiated)
        #expect(offer.salary == 1_000_000 || offer.salary == 1_150_000)
        #expect(throws: GameError.self) { try game.negotiateCareerOffer(901) }
    }

    @Test func 이적_요청은_이적_기간마다_한_번이고_신뢰가_떨어진다() throws {
        var game = TestCareer.make(.center)
        let trust = try #require(game.career?.trust)
        try game.requestCareerTransfer()
        #expect(game.career?.trust == trust - 10)
        #expect(throws: GameError.self) { try game.requestCareerTransfer() }
    }

    @Test func 계약이_끝나고_재계약하지_않으면_무소속이_되어_입단_제안을_고른다() throws {
        var game = TestCareer.make(.second, seed: 13)
        var auto = CareerAuto()
        auto.acceptsTransfers = false
        let id = try #require(game.career?.playerID)
        // 신뢰가 바닥이면 구단이 재계약을 제안하지 않는다.
        while game.season == 1 {
            if game.phase == .regular { game.players[id]?.contract.seasonsLeft = 1 }
            game.career?.trust = 0
            game.career?.offers = []
            clockStep(&auto, &game)
        }
        let career = try #require(game.career)
        #expect(career.isFreeAgent)
        #expect(game.myPlayer?.teamID == nil)
        #expect(career.offers.count >= 2)
        #expect(career.offers.allSatisfy { $0.kind == .tryout })
        #expect(game.nextMatch() == nil)
        #expect(throws: GameError.self) { try game.startMatch(now: auto.clock.addingTimeInterval(7200)) }
        #expect(throws: GameError.self) { try game.declineCareerOffer(career.offers[0].id) }

        try game.acceptCareerOffer(career.offers[0].id)
        #expect(game.career?.isFreeAgent == false)
        #expect(game.myPlayer?.teamID == career.offers[0].teamID)
        try auto.playOne(&game)
        #expect(game.myPlayer?.batting.games == 1)
    }

    /// 제안을 건드리지 않고 한 경기만 치른다.
    private func clockStep(_ auto: inout CareerAuto, _ game: inout Game) {
        auto.clock = auto.clock.addingTimeInterval(3600)
        try? game.startMatch(now: auto.clock)
        game.runMatchToEnd()
    }
}
