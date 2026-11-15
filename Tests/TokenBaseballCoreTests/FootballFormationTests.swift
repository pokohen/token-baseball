import Foundation
import Testing
@testable import TokenBaseballCore

@Suite struct FootballFormationTests {
    /// 포지션별 인원을 정해 만든 팀.
    private func squad(
        keepers: Int = 2, defenders: Int = 6, midfielders: Int = 6, forwards: Int = 4,
        formation: Formation?, seed: UInt64 = 3
    ) -> (Team, [PlayerID: Player]) {
        var rng = SeededRNG(seed: seed)
        var team = Team(id: 1, name: "시험 FC", city: "", tier: .amateur, isUser: false, season: 1)
        team.formation = formation
        var players: [PlayerID: Player] = [:]
        let positions = Array(repeating: Position.goalkeeper, count: keepers)
            + Array(repeating: .defender, count: defenders)
            + Array(repeating: .midfielder, count: midfielders) + Array(repeating: .forward, count: forwards)
        for (index, position) in positions.enumerated() {
            var spec = PlayerFactory.Spec(position: position, tier: .amateur, season: 1)
            spec.ability = 50...50
            let player = PlayerFactory.make(id: 100 + index, spec: spec, &rng)
            players[player.id] = player
            team.roster.append(player.id)
        }
        return (team, players)
    }

    @Test(arguments: Formation.allCases)
    func 포메이션대로_선발을_짠다(formation: Formation) throws {
        let (team, players) = squad(formation: formation)
        let lineup = try #require(FootballLineupBuilder.build(team: team, players: players))
        let slots = lineup.starters.map(\.slot)
        #expect(slots == formation.slots)
        #expect(slots.count == 11)
        // 인원이 넉넉하면 모두 제 포지션에 선다.
        #expect(lineup.starters.allSatisfy { players[$0.id]?.position == $0.slot })
        let side = try #require(FootballLineupBuilder.side(team: team, players: players))
        #expect(side.shape == formation)
    }

    @Test func 포메이션을_정하지_않으면_442다() throws {
        let (team, players) = squad(formation: nil)
        let lineup = try #require(FootballLineupBuilder.build(team: team, players: players))
        #expect(lineup.starters.map(\.slot) == Formation.f442.slots)
    }

    @Test func 공격수가_모자라도_433을_짤_수_있다() throws {
        let (team, players) = squad(forwards: 2, formation: .f433)
        let lineup = try #require(FootballLineupBuilder.build(team: team, players: players))
        #expect(lineup.starters.map(\.slot) == Formation.f433.slots)
        let misplaced = lineup.starters.filter { players[$0.id]?.position != $0.slot }
        #expect(misplaced.count == 1)
        #expect(misplaced.first?.slot == .forward)
    }

    @Test func 직접_정한_선발은_포메이션을_바꿔도_남는다() throws {
        var (team, players) = squad(formation: .f442)
        let first = try #require(FootballLineupBuilder.build(team: team, players: players))
        team.lineupOverride = first.starters.map(\.id)
        team.formation = .f433
        let second = try #require(FootballLineupBuilder.build(team: team, players: players))
        #expect(Set(second.starters.map(\.id)) == Set(first.starters.map(\.id)))
        #expect(second.starters.map(\.slot) == Formation.f433.slots)
        // 미드필더 한 명이 공격수 자리에 선다.
        #expect(second.starters.filter { players[$0.id]?.position != $0.slot }.count == 1)
    }

    @Test func 포메이션_442는_정하지_않은_것과_똑같이_흐른다() {
        var rng = SeededRNG(seed: 5)
        var plain = FootballMatch(
            away: FootballSample.side(id: 1, ability: 50, &rng),
            home: FootballSample.side(id: 2, ability: 50, &rng), rules: FootballRules(), seed: 99)
        rng = SeededRNG(seed: 5)
        var explicit = FootballMatch(
            away: FootballSample.side(id: 1, ability: 50, formation: .f442, &rng),
            home: FootballSample.side(id: 2, ability: 50, formation: .f442, &rng), rules: FootballRules(), seed: 99)
        plain.runToEnd()
        explicit.runToEnd()
        #expect(plain.log == explicit.log)
        #expect(plain.home.goals == explicit.home.goals && plain.away.goals == explicit.away.goals)
    }

    @Test func 포메이션이_없던_저장_파일도_읽는다() throws {
        // 팀
        var (team, players) = squad(formation: .f433)
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(team)) as? [String: Any])
        #expect(object["formation"] as? String == "4-3-3")
        object["formation"] = nil
        let oldTeam = try JSONDecoder().decode(Team.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(oldTeam.formation == nil)

        // 진행 중인 경기
        team.formation = .f41212
        let side = try #require(FootballLineupBuilder.side(team: team, players: players))
        players = [:]
        var match = FootballMatch(away: side, home: side, rules: FootballRules(), seed: 1)
        for _ in 0..<50 { match.step() }
        var saved = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(match)) as? [String: Any])
        for key in ["home", "away"] {
            var one = try #require(saved[key] as? [String: Any])
            #expect(one["formation"] as? String == "4-1-2-1-2")
            one["formation"] = nil
            saved[key] = one
        }
        var old = try JSONDecoder().decode(FootballMatch.self, from: JSONSerialization.data(withJSONObject: saved))
        #expect(old.home.shape == .f442)
        old.runToEnd()
        #expect(old.isFinished)

        // 새 값은 저장했다 읽어도 그대로다.
        let again = try JSONDecoder().decode(FootballMatch.self, from: JSONEncoder().encode(match))
        #expect(again == match)
    }

    @Test func 공격수가_셋이면_공격수의_슈팅_몫이_커진다() {
        func forwardShare(_ formation: Formation) -> Double {
            var rng = SeededRNG(seed: 17)
            var forward = 0, total = 0
            for _ in 0..<150 {
                let away = FootballSample.side(id: 1, ability: 50, &rng)
                let home = FootballSample.side(id: 2, ability: 50, formation: formation, &rng)
                var match = FootballMatch(away: away, home: home, rules: FootballRules(), seed: rng.next())
                match.runToEnd()
                for player in match.home.players {
                    total += player.line.shots
                    if player.slot == .forward { forward += player.line.shots }
                }
            }
            return Double(forward) / Double(max(1, total))
        }
        let two = forwardShare(.f442), three = forwardShare(.f433)
        #expect(three > two + 0.08, "\(two) → \(three)")
    }

    /// 어느 포메이션도 다른 포메이션을 일방적으로 이기지 않는다 (홈과 원정을 바꿔 가며 같은 전력으로).
    @Test(arguments: [
        [Formation.f442, .f433], [.f442, .f41212], [.f433, .f41212],
    ])
    func 포메이션끼리_전력이_비슷하다(pair: [Formation]) {
        let a = pair[0], b = pair[1]
        let x = FootballSample.run(away: 50, home: 50, games: 400, awayFormation: b, homeFormation: a, seed: 31)
        let y = FootballSample.run(away: 50, home: 50, games: 400, awayFormation: a, homeFormation: b, seed: 32)
        let aWins = x.homeWins + y.awayWins, bWins = x.awayWins + y.homeWins
        let gap = Double(aWins - bWins) / 800
        #expect(abs(gap) < 0.1, "\(a.label) \(aWins)승, \(b.label) \(bWins)승")
    }

    @Test func 고른_포메이션으로_경기에_나서고_저장했다_읽어도_이어진다() throws {
        var game = FootballGame.make(seed: 5)
        game.setFormation(.f433)
        #expect(game.currentFootballLineup?.starters.map(\.slot) == Formation.f433.slots)
        try game.startMatch(now: TestGame.hours(1))
        let live = try #require(game.liveFootball)
        let mine = live.userIsHome ? live.state.home : live.state.away
        let theirs = live.userIsHome ? live.state.away : live.state.home
        #expect(mine.shape == .f433)
        #expect(mine.players.filter { $0.isOnPitch && $0.slot == .forward }.count == 3)
        #expect(theirs.shape == .f442)

        for _ in 0..<100 { game.stepMatch() }
        // 경기 중에 바꾼 포메이션은 이 경기에 영향을 주지 않는다.
        var changed = game
        changed.setFormation(.f41212)
        let loaded = try JSONDecoder().decode(Game.self, from: JSONEncoder().encode(game))
        #expect(loaded == game)
        #expect(loaded.userTeam.formation == .f433)
        var a = game, b = loaded
        a.runMatchToEnd()
        b.runMatchToEnd()
        changed.runMatchToEnd()
        #expect(a == b)
        #expect(a.lastResult == changed.lastResult)
        #expect(changed.userTeam.formation == .f41212)
    }
}
