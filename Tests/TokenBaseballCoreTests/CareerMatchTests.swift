import Foundation
import Testing
@testable import TokenBaseballCore

@Suite struct CareerAppearanceTests {
    @Test(arguments: [Position.shortstop, .designated, .left])
    func 타자는_매_경기_선발로_나온다(position: Position) throws {
        var game = TestCareer.make(position, seed: 3)
        var auto = CareerAuto()
        for played in 1...8 {
            try auto.playOne(&game)
            let me = try #require(game.myPlayer)
            #expect(me.batting.games == played)
            #expect(game.career?.lastRating != nil)
        }
        #expect(try #require(game.myPlayer).batting.plateAppearances >= 16)
    }

    @Test func 선발_투수는_쉬는_날을_채우면_반드시_등판한다() throws {
        var game = TestCareer.make(.starter, seed: 4)
        var auto = CareerAuto()
        var starts = 0
        for _ in 0..<9 {
            let expected = game.careerStartsNextMatch
            try auto.playOne(&game)
            let pitched = game.career?.lastRating != nil
            #expect(pitched == expected)
            if pitched { starts += 1 }
        }
        // 시민 리그는 이틀 쉬고 사흘째에 나온다.
        #expect(starts == 3)
        #expect(try #require(game.myPlayer).pitching.starts == 3)
    }

    @Test func 불펜_투수는_선발이_내려가면_가장_먼저_올라온다() throws {
        var game = TestCareer.make(.reliever, seed: 5)
        var auto = CareerAuto()
        for _ in 0..<12 { try auto.playOne(&game) }
        let me = try #require(game.myPlayer)
        #expect(me.pitching.games >= 8)
        #expect(me.pitching.starts == 0)
    }

    @Test func 평점은_잘한_경기가_높다() {
        func batter(_ edit: (inout BattingLine) -> Void) -> MatchTeam {
            var line = BattingLine()
            edit(&line)
            var hitter = MatchBatter(
                playerID: 1, name: "타자", position: .first, contact: 50, power: 50, eye: 50, speed: 50,
                fielding: 50, arm: 50, bats: .right, traits: [])
            hitter.line = line
            return MatchTeam(
                teamID: 0, name: "팀", shortName: "팀", batters: [hitter], pitchers: [], policy: PitchingPolicy())
        }
        let quiet = batter { $0.plateAppearances = 4; $0.atBats = 4; $0.strikeouts = 2 }
        let good = batter {
            $0.plateAppearances = 4; $0.atBats = 4; $0.hits = 2; $0.homeRuns = 1; $0.runsBattedIn = 2; $0.runs = 1
        }
        let bench = batter { _ in }
        let low = Game.careerPerformance(playerID: 1, in: quiet, result: -1)
        let high = Game.careerPerformance(playerID: 1, in: good, result: 1)
        #expect(try! #require(low).rating < 6)
        #expect(try! #require(high).rating > 8)
        #expect(high?.line == "4타수 2안타 1홈런 2타점")
        #expect(Game.careerPerformance(playerID: 1, in: bench, result: 0) == nil)
        #expect(Game.careerPerformance(playerID: 99, in: good, result: 0) == nil)
    }

    @Test func 감독_신뢰가_높으면_선발을_더_오래_맡긴다() {
        #expect(Game.careerPolicy(trust: 90).starterPitchLimit > Game.careerPolicy(trust: 10).starterPitchLimit)
        #expect(Game.careerPolicy(trust: 90).starterRunLimit > Game.careerPolicy(trust: 10).starterRunLimit)
    }
}

@Suite struct CareerPitcherMoveTests {
    @Test(arguments: [Position.starter, .reliever])
    func 투수가_구단을_옮겨도_바로_등판한다(position: Position) throws {
        var game = TestCareer.make(position, seed: 51)
        var auto = CareerAuto()
        auto.acceptsTransfers = false
        // 한 시즌과 오프시즌을 보내 내 구단의 경기 수가 다른 구단보다 앞서게 한다.
        while game.season == 1 { try auto.playOne(&game) }
        let target = try #require(game.teams(in: .citizenSemiPro).first { $0.id != game.userTeamID }).id
        game.career?.offers = [CareerOffer(
            id: 950, kind: .transfer, teamID: target, salary: 1_000_000, years: 3, role: .rotation, matchesLeft: 1)]
        try game.acceptCareerOffer(950)
        #expect(game.userTeamID == target)
        if position == .starter { #expect(game.careerStartsNextMatch) }
        var appearances = 0
        for _ in 0..<6 {
            try auto.playOne(&game)
            if game.career?.lastRating != nil { appearances += 1 }
        }
        #expect(appearances >= 2)
        let me = try #require(game.myPlayer)
        #expect(me.pitching.games >= 2)
    }
}
