import Foundation
import Testing
@testable import TokenBaseballCore

@Suite struct CupTests {
    let start = Date(timeIntervalSince1970: 0)

    func make(_ position: Position, seed: UInt64 = 31) -> Game {
        Game.newCareer(setup: CareerSetup(name: "컵 선수", position: position), now: start, seed: seed)
    }

    /// 경기 기회를 채워 가며 한 경기를 끝까지 치른다.
    func playOne(_ game: inout Game, at index: Int) throws {
        let now = start.addingTimeInterval(Double(index + 1) * 3 * 3600)
        try game.startMatch(now: now)
        game.runMatchToEnd()
    }

    @Test(arguments: [Position.shortstop, .forward])
    func 첫_라운드는_1부의_강팀이_쉬고_나머지가_치른다(position: Position) throws {
        let game = make(position)
        let cup = try #require(game.cup)
        // 야구는 60팀 중 네 팀, 축구는 120팀 중 여덟 팀이 쉰다.
        let football = position.sport == .football
        #expect(cup.byes.count == (football ? 8 : 4) && cup.ties.count == (football ? 56 : 28))
        #expect(cup.byes.allSatisfy { game.teams[$0].tier == .pro })
        let all = Set(cup.byes + cup.ties.flatMap { [$0.home, $0.away] })
        #expect(all.count == game.teams.count)
        // 아랫 리그 구단이 홈에서 치른다.
        #expect(cup.ties.allSatisfy { game.teams[$0.home].tier >= game.teams[$0.away].tier })
        #expect(game.nextMatch()?.kind == .regular)
    }

    @Test(arguments: [Position.shortstop, .starter, .forward, .goalkeeper])
    func 한_시즌_동안_컵대회를_끝까지_치르고_우승팀이_나온다(position: Position) throws {
        var game = make(position)
        var cupMatches = 0
        var kinds: [MatchKind] = []
        var index = 0
        while game.phase == .regular, index < 60 {
            let next = try #require(game.nextMatch())
            kinds.append(next.kind)
            if next.kind == .cup {
                cupMatches += 1
                // 컵 경기는 리그 라운드를 넘기지 않는다.
                let round = game.round
                try playOne(&game, at: index)
                #expect(game.round == round)
                #expect(game.lastResult?.kind == .cup)
                #expect(game.lastResult?.myRuns != game.lastResult?.theirRuns || game.lastResult?.shootoutWon != nil)
            } else {
                try playOne(&game, at: index)
            }
            index += 1
        }
        let cup = try #require(game.cup)
        let sizes = position.sport == .football ? [56, 32, 16, 8, 4, 2, 1] : [28, 16, 8, 4, 2, 1]
        #expect(cup.isFinished && cup.history.count == sizes.count)
        #expect(cup.history.map(\.count) == sizes)
        #expect(cup.history.allSatisfy { $0.allSatisfy(\.isPlayed) })
        #expect(cup.champion == cup.history.last?.first?.winner)
        #expect(cupMatches >= 1 && cupMatches <= sizes.count)
        #expect(kinds.filter { $0 == .regular }.count == Balance.roundsPerSeason(position.sport))
        // 내 구단의 길: 진 경기 뒤로는 더 없다.
        let path = cup.path(of: game.userTeamID)
        #expect(path.count == cupMatches)
        for step in path.dropLast() { #expect(step.tie.winner == game.userTeamID) }
    }

    @Test func 컵_경기는_순위표와_시즌_기록에_들어가지_않는다() throws {
        var game = make(.shortstop)
        var index = 0
        while game.nextMatch()?.kind != .cup, index < 12 {
            try playOne(&game, at: index)
            index += 1
        }
        try #require(game.nextMatch()?.kind == .cup)
        let standings = game.standings
        let line = game.myPlayer!.batting
        try playOne(&game, at: index)
        #expect(game.standings == standings)
        #expect(game.myPlayer!.batting == line)
    }

    @Test func 윗_리그_구단을_잡으면_명성이_더_오른다() {
        var game = make(.shortstop)
        let upper = game.teams.first { $0.tier < game.userTier }!
        let same = game.teams.first { $0.tier == game.userTier && $0.id != game.userTeamID }!
        var plain = game
        _ = plain.settleCareerCupTie(won: true, opponent: same.id, roundName: "1라운드")
        _ = game.settleCareerCupTie(won: true, opponent: upper.id, roundName: "1라운드")
        #expect((plain.career?.fame ?? 0) == Balance.cupWinFame)
        #expect((game.career?.fame ?? 0) > (plain.career?.fame ?? 0))
        var lost = plain
        _ = lost.settleCareerCupTie(won: false, opponent: same.id, roundName: "32강")
        #expect(lost.career?.fame == plain.career?.fame)
    }

    @Test func 우승하면_수상_경력에_남는다() {
        var game = make(.shortstop)
        game.settleCareerCupFinal(champion: game.userTeamID, final: nil)
        #expect(game.career?.awards.contains { $0.contains("컵대회 우승") } == true)
        #expect((game.career?.fame ?? 0) == Balance.cupChampionFame)
    }

    @Test func 새_시즌에는_새_대회가_열린다() throws {
        var game = make(.shortstop)
        var index = 0
        while game.season == 1, index < 80 {
            guard game.nextMatch() != nil else { break }
            try playOne(&game, at: index)
            index += 1
        }
        try #require(game.season == 2)
        try playOne(&game, at: index)
        let cup = try #require(game.cup)
        #expect(cup.season == 2 && cup.roundIndex == 0 && cup.history.isEmpty && !cup.isFinished)
    }

    @Test func 예전_저장_파일처럼_대회가_없어도_시즌_도중에_생기고_끝까지_간다() throws {
        var game = make(.forward)
        for index in 0..<20 { try playOne(&game, at: index) }
        game.cup = nil
        var index = 20
        while game.phase == .regular, index < 80 {
            try playOne(&game, at: index)
            index += 1
        }
        #expect(game.cup?.isFinished == true)
    }
}
