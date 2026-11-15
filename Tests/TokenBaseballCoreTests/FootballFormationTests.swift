import Foundation
import Testing
@testable import TokenBaseballCore

@Suite struct FootballFormationTests {
    /// 포지션별 인원을 정해 만든 팀.
    private func squad(
        keepers: Int = 2, defenders: Int = 6, midfielders: Int = 6, forwards: Int = 4,
        formation: Formation?, forwardAbility: Double = 50, seed: UInt64 = 3
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
            let ability = position == .forward ? forwardAbility : 50
            spec.ability = ability...ability
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
    @Test(arguments: Formation.allCases.filter { $0 != .f442 })
    func 어느_포메이션도_442를_일방적으로_이기지_않는다(a: Formation) {
        let b = Formation.f442
        let x = FootballSample.run(away: 50, home: 50, games: 300, awayFormation: b, homeFormation: a, seed: 31)
        let y = FootballSample.run(away: 50, home: 50, games: 300, awayFormation: a, homeFormation: b, seed: 32)
        let aWins = x.homeWins + y.awayWins, bWins = x.awayWins + y.homeWins
        let gap = Double(aWins - bWins) / 600
        #expect(abs(gap) < 0.1, "\(a.label) \(aWins)승, \(b.label) \(bWins)승")
    }

    @Test func 고른_포메이션으로_경기에_나서고_저장했다_읽어도_이어진다() throws {
        var game = FootballGame.make(seed: 5)
        game.setFormation(.f433)
        #expect(game.currentFootballLineup?.starters.map(\.slot) == Formation.f433.slots)
        let opponent = try #require(game.nextMatch()).opponent
        let expected = game.formation(of: opponent)
        try game.startMatch(now: TestGame.hours(1))
        let live = try #require(game.liveFootball)
        let mine = live.userIsHome ? live.state.home : live.state.away
        let theirs = live.userIsHome ? live.state.away : live.state.home
        #expect(mine.shape == .f433)
        #expect(mine.players.filter { $0.isOnPitch && $0.slot == .forward }.count == 3)
        #expect(theirs.shape == expected)

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

    // MARK: CPU 구단의 포메이션

    @Test func 공격수가_좋은_구단은_공격수_셋을_세운다() {
        // 공격수만 눈에 띄게 좋다.
        let (team, players) = squad(defenders: 5, midfielders: 5, forwards: 4, formation: nil, forwardAbility: 70)
        for season in 1...6 {
            let chosen = FootballLineupBuilder.fitted(team: team, players: players, season: season)
            #expect(chosen.shape.forwards == 3, "\(chosen.label)")
        }
    }

    @Test func 수비수가_셋뿐이면_스리백을_쓴다() {
        let (team, players) = squad(defenders: 3, midfielders: 7, forwards: 4, formation: nil)
        for season in 1...6 {
            let chosen = FootballLineupBuilder.fitted(team: team, players: players, season: season)
            #expect(chosen.shape.defenders == 3, "\(chosen.label)")
        }
    }

    @Test func 상대_구단은_포메이션이_여러_가지고_난수를_쓰지_않는다() {
        let game = FootballGame.make(seed: 4)
        let before = game
        let cpu = game.teams.filter { !$0.isUser }
        let chosen = cpu.map { game.formation(of: $0.id) }
        #expect(Set(chosen).count >= 3, "\(Set(chosen).map(\.label))")
        // 같은 시즌, 같은 선수단이면 다시 물어도 같다.
        #expect(chosen == cpu.map { game.formation(of: $0.id) })
        #expect(game == before)
        // 고른 포메이션은 그 구단에 가장 잘 맞는 것과 거의 차이가 없다.
        for team in cpu {
            let fits = Formation.allCases.compactMap {
                FootballLineupBuilder.fit($0, team: team, players: game.players)
            }
            let mine = FootballLineupBuilder.fit(game.formation(of: team.id), team: team, players: game.players)
            #expect((mine ?? 0) >= (fits.max() ?? 0) - FootballLineupBuilder.fitTolerance - 0.0001)
        }
        // 내 구단은 고르지 않으면 4-4-2다.
        #expect(game.formation(of: game.userTeamID) == .f442)
    }
}
