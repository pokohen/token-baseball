import Foundation
import Testing
@testable import TokenBaseballCore

@Suite struct ScheduleTests {
    @Test(arguments: [1, 2, 3, 99, 12345] as [UInt64])
    func 모든_팀과_홈_2경기_원정_2경기를_치른다(seed: UInt64) {
        var rng = SeededRNG(seed: seed)
        let teams = Array(10..<20)
        let schedule = ScheduleBuilder.build(teams: teams, &rng)

        #expect(schedule.count == 36)
        var homeGames: [String: Int] = [:]
        for round in schedule {
            #expect(round.count == 5)
            // 한 라운드에 모든 팀이 한 번씩만 나온다.
            #expect(Set(round.flatMap { [$0.home, $0.away] }) == Set(teams))
            for fixture in round { homeGames["\(fixture.home)-\(fixture.away)", default: 0] += 1 }
        }
        for a in teams {
            for b in teams where a != b {
                #expect(homeGames["\(a)-\(b)"] == 2)
            }
        }
    }

    @Test func 같은_상대와_연속으로_붙지_않는다() {
        var rng = SeededRNG(seed: 5)
        let teams = Array(0..<10)
        let schedule = ScheduleBuilder.build(teams: teams, &rng)
        for team in teams {
            let opponents = schedule.map { round in round.first { $0.involves(team) }!.opponent(of: team) }
            for index in 1..<opponents.count {
                #expect(opponents[index] != opponents[index - 1])
            }
        }
    }

    @Test func 홈과_원정이_18경기씩이다() {
        var rng = SeededRNG(seed: 8)
        let schedule = ScheduleBuilder.build(teams: Array(0..<10), &rng)
        for team in 0..<10 {
            #expect(schedule.flatMap { $0 }.filter { $0.home == team }.count == 18)
        }
    }
}

@Suite struct StandingsTests {
    static func row(_ id: Int, _ wins: Int, _ losses: Int, draws: Int = 0, runs: Int = 0) -> StandingRow {
        var row = StandingRow(teamID: id)
        row.wins = wins
        row.losses = losses
        row.draws = draws
        row.runsFor = runs
        return row
    }

    @Test func 승률은_무승부를_빼고_계산한다() {
        // 6승 0패 4무(승률 1.000)가 8승 2패(승률 .800)보다 위다.
        let ranked = Standings.ranked([Self.row(1, 8, 2), Self.row(2, 6, 0, draws: 4)])
        #expect(ranked.map(\.teamID) == [2, 1])
        #expect(ranked[0].winRate == 1.0)
    }

    @Test func 승률이_같으면_상대_전적을_본다() {
        var a = Self.row(1, 10, 10, runs: 50)
        var b = Self.row(2, 10, 10, runs: 90)
        a.winsAgainst[2] = 3
        b.winsAgainst[1] = 1
        #expect(Standings.ranked([b, a]).map(\.teamID) == [1, 2])
    }

    @Test func 상대_전적도_같으면_다득점이다() {
        var a = Self.row(1, 10, 10, runs: 50)
        var b = Self.row(2, 10, 10, runs: 90)
        a.winsAgainst[2] = 2
        b.winsAgainst[1] = 2
        #expect(Standings.ranked([a, b]).map(\.teamID) == [2, 1])
    }
}
