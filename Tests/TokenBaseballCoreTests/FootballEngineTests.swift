import Foundation
import Testing
@testable import TokenBaseballCore

enum FootballSample {
    /// 모든 선수의 능력이 `ability`인 팀.
    static func side(
        id: TeamID, ability: Double, tier: LeagueTier = .amateur, tactic: Tactic = .balanced,
        formation: Formation? = nil, _ rng: inout SeededRNG
    ) -> FootballSide {
        var team = Team(id: id, name: "팀\(id) FC", city: "", tier: tier, isUser: false, season: 1)
        team.tactic = tactic
        team.formation = formation
        var players: [PlayerID: Player] = [:]
        for (index, position) in PlayerFactory.rosterPositions(tier, sport: .football).enumerated() {
            var spec = PlayerFactory.Spec(position: position, tier: tier, season: 1)
            spec.ability = ability...ability
            let player = PlayerFactory.make(id: id * 100 + index, spec: spec, &rng)
            players[player.id] = player
            team.roster.append(player.id)
        }
        return FootballLineupBuilder.side(team: team, players: players)!
    }

    struct Stats {
        var games = 0, homeWins = 0, awayWins = 0, draws = 0
        var homeGoals = 0, awayGoals = 0, shots = 0, onTarget = 0, corners = 0, fouls = 0
        var yellows = 0, reds = 0, offsides = 0, steps = 0, subs = 0, shootouts = 0
        var goalsPerGame: Double { Double(homeGoals + awayGoals) / Double(games) }
        func per(_ value: Int) -> Double { Double(value) / Double(games) }
    }

    static func run(
        away: Double, home: Double, games: Int, rules: FootballRules = FootballRules(),
        awayTactic: Tactic = .balanced, homeTactic: Tactic = .balanced,
        awayFormation: Formation? = nil, homeFormation: Formation? = nil, seed: UInt64 = 7
    ) -> Stats {
        var rng = SeededRNG(seed: seed)
        var stats = Stats()
        for _ in 0..<games {
            let a = side(id: 1, ability: away, tactic: awayTactic, formation: awayFormation, &rng)
            let h = side(id: 2, ability: home, tactic: homeTactic, formation: homeFormation, &rng)
            var match = FootballMatch(away: a, home: h, rules: rules, seed: rng.next())
            var steps = 0
            while !match.isFinished {
                match.step()
                steps += 1
                if steps > 2000 { break }
            }
            stats.games += 1
            stats.steps += steps
            switch match.result {
            case .homeWin: stats.homeWins += 1
            case .awayWin: stats.awayWins += 1
            default: stats.draws += 1
            }
            stats.homeGoals += match.home.goals
            stats.awayGoals += match.away.goals
            for side in [match.home, match.away] {
                stats.shots += side.shots
                stats.onTarget += side.shotsOnTarget
                stats.corners += side.corners
                stats.fouls += side.fouls
                stats.yellows += side.yellowCards
                stats.reds += side.redCards
                stats.offsides += side.offsides
                stats.subs += side.subsUsed
            }
            if match.wentToShootout { stats.shootouts += 1 }
        }
        return stats
    }
}

@Suite struct FootballEngineTests {
    @Test func 전력이_같으면_실제_축구와_비슷한_수치가_나온다() {
        for ability in [30.0, 50.0, 80.0] {
            let s = FootballSample.run(away: ability, home: ability, games: 500)
            #expect((2.3...3.1).contains(s.goalsPerGame), "능력 \(ability): 경기당 \(s.goalsPerGame)골")
            #expect((0.20...0.34).contains(s.per(s.draws)), "능력 \(ability): 무승부 \(s.per(s.draws))")
            #expect(s.homeWins > s.awayWins, "능력 \(ability): 홈 \(s.homeWins) 원정 \(s.awayWins)")
            #expect(s.per(s.homeWins) < 0.56, "능력 \(ability): 홈 승률 \(s.per(s.homeWins))")
            #expect((18...30).contains(s.per(s.shots)), "슈팅 \(s.per(s.shots))")
            #expect((5...12).contains(s.per(s.corners)), "코너킥 \(s.per(s.corners))")
            #expect((14...28).contains(s.per(s.fouls)), "반칙 \(s.per(s.fouls))")
            #expect((2...5).contains(s.per(s.yellows)), "경고 \(s.per(s.yellows))")
            #expect(s.per(s.reds) < 0.4, "퇴장 \(s.per(s.reds))")
        }
    }

    @Test func 강한_팀이_더_자주_이기지만_늘_이기지는_않는다() {
        let homeStrong = FootballSample.run(away: 45, home: 55, games: 500)
        #expect((0.55...0.80).contains(homeStrong.per(homeStrong.homeWins)), "\(homeStrong.per(homeStrong.homeWins))")
        let awayStrong = FootballSample.run(away: 55, home: 45, games: 500)
        #expect(awayStrong.awayWins > awayStrong.homeWins * 2)
        #expect(awayStrong.homeWins > 0)
        let mismatch = FootballSample.run(away: 30, home: 60, games: 200)
        #expect(mismatch.per(mismatch.homeWins) > 0.9)
    }

    @Test func 한_경기는_약_15분_길이다() {
        let s = FootballSample.run(away: 50, home: 50, games: 200)
        // 3초에 한 틱: 276~306틱이면 13.8~15.3분.
        #expect((276...306).contains(s.per(s.steps)), "\(s.per(s.steps))틱")
    }

    @Test func 승강_플레이오프는_연장과_승부차기로_반드시_승부가_난다() {
        let s = FootballSample.run(
            away: 50, home: 50, games: 400, rules: FootballRules(mustHaveWinner: true))
        #expect(s.draws == 0)
        #expect(s.shootouts > 0)
        #expect(s.per(s.shootouts) < 0.25, "승부차기 \(s.per(s.shootouts))")
    }

    @Test func 같은_시드면_같은_경기가_되고_저장했다_읽어도_이어진다() throws {
        var rng = SeededRNG(seed: 3)
        let away = FootballSample.side(id: 1, ability: 50, &rng)
        let home = FootballSample.side(id: 2, ability: 50, &rng)
        var first = FootballMatch(away: away, home: home, rules: FootballRules(mustHaveWinner: true), seed: 99)
        var second = FootballMatch(away: away, home: home, rules: FootballRules(mustHaveWinner: true), seed: 99)
        for _ in 0..<150 { first.step() }
        var restored = try JSONDecoder().decode(FootballMatch.self, from: JSONEncoder().encode(first))
        #expect(restored == first)
        first.runToEnd()
        second.runToEnd()
        restored.runToEnd()
        #expect(first == second)
        #expect(first == restored)
    }

    @Test func 경기_기록의_앞뒤가_맞는다() {
        var rng = SeededRNG(seed: 12)
        for round in 0..<300 {
            let away = FootballSample.side(id: 1, ability: 40, &rng)
            let home = FootballSample.side(id: 2, ability: 45, &rng)
            var match = FootballMatch(
                away: away, home: home, rules: FootballRules(mustHaveWinner: round % 2 == 0), seed: rng.next())
            match.runToEnd()
            for (side, other) in [(match.home, match.away), (match.away, match.home)] {
                let played = side.players.filter(\.hasPlayed)
                #expect(played.reduce(0) { $0 + $1.line.goals } == side.goals)
                #expect(played.reduce(0) { $0 + $1.line.shots } == side.shots)
                #expect(played.reduce(0) { $0 + $1.line.assists } <= side.goals)
                #expect(played.reduce(0) { $0 + $1.line.conceded } == other.goals)
                #expect(played.reduce(0) { $0 + $1.line.saves } <= other.shotsOnTarget - other.goals)
                #expect(side.shotsOnTarget >= side.goals && side.shots >= side.shotsOnTarget)
                #expect(side.subsUsed <= Balance.footballMaxSubs)
                #expect(played.count == 11 + side.subsUsed)
                #expect(side.onPitchCount == 11 - side.redCards)
                #expect(side.players.filter { $0.isOnPitch && $0.slot == .goalkeeper }.count == 1)
                #expect(side.players.filter(\.sentOff).count == side.redCards)
                #expect(played.allSatisfy { $0.line.games == 1 })
                let clean = played.reduce(0) { $0 + $1.line.cleanSheets }
                #expect(clean == (other.goals == 0 ? 1 : 0))
            }
            #expect(match.log.last?.kind == .end)
        }
    }

    @Test func 공격적인_전술은_골도_실점도_늘린다() {
        let open = FootballSample.run(away: 50, home: 50, games: 500, awayTactic: .attacking, homeTactic: .attacking)
        let closed = FootballSample.run(away: 50, home: 50, games: 500, awayTactic: .defensive, homeTactic: .defensive)
        #expect(open.goalsPerGame > closed.goalsPerGame + 0.3, "\(open.goalsPerGame) vs \(closed.goalsPerGame)")
    }

    @Test(arguments: [true, false])
    func 골키퍼가_퇴장당해도_골문은_비지_않는다(benchKeeper: Bool) {
        var rng = SeededRNG(seed: 21)
        for _ in 0..<40 {
            let away = FootballSample.side(id: 1, ability: 50, &rng)
            var home = FootballSample.side(id: 2, ability: 50, &rng)
            if !benchKeeper {
                // 벤치에 골키퍼가 없는 팀
                home.players.removeAll { !$0.isOnPitch && $0.natural == .goalkeeper }
            }
            var match = FootballMatch(away: away, home: home, rules: FootballRules(mustHaveWinner: true), seed: rng.next())
            for _ in 0..<rng.int(1...200) { match.step() }
            guard !match.isFinished, let keeper = match.home.keeperIndex else { continue }
            // 그 전에 다른 선수가 퇴장당했을 수도 있다.
            let before = match.home.onPitchCount
            var events: [MatchEvent] = []
            match.sendOff(home: true, index: keeper, &events)
            #expect(match.home.onPitchCount == before - 1)
            #expect(match.home.players.filter { $0.isOnPitch && $0.slot == .goalkeeper }.count == 1)
            #expect(match.home.players[keeper].sentOff && !match.home.players[keeper].isOnPitch)
            #expect(events.contains { $0.kind == .change })
            if benchKeeper {
                #expect(match.home.players[match.home.keeperIndex!].natural == .goalkeeper)
                #expect(match.home.subsUsed >= 1)
            }
            match.runToEnd()
            #expect(match.result != nil && match.result != .draw)
            #expect(match.home.players.filter { $0.isOnPitch && $0.slot == .goalkeeper }.count == 1)
            #expect(match.home.onPitchCount == 11 - match.home.redCards)
            #expect(match.home.subsUsed <= Balance.footballMaxSubs)
        }
    }
}
