import Foundation
import Testing
@testable import TokenBaseballCore

enum FootballGame {
    static func make(seed: UInt64 = 1) -> Game {
        Game.newGame(
            setup: .init(city: "수원", name: "수원 테스트 FC"), now: TestGame.start, seed: seed, sport: .football)
    }
}

@Suite struct FootballNewGameTests {
    @Test func 축구로_창단하면_모든_구단이_축구_선수로_채워진다() {
        let game = FootballGame.make()
        #expect(game.sport == .football)
        #expect(game.teams.count == 60)
        #expect(game.roster(of: game.userTeamID).count == 16)
        #expect(game.teams(in: .pro).map(\.name).contains("울산 고래"))
        Invariants.check(game, "축구 새 게임")
        for tier in LeagueTier.allCases {
            for team in game.teams(in: tier) where !team.isUser {
                #expect(team.roster.count == PlayerFactory.rosterPositions(tier, sport: .football).count)
            }
        }
    }

    @Test func 야구로_창단하면_종목_정보_없이_저장된다() throws {
        let game = TestGame.make()
        #expect(game.sport == .baseball)
        let json = String(decoding: try JSONEncoder().encode(game), as: UTF8.self)
        #expect(!json.contains("sportChoice"))
    }

    @Test func 축구_세이브는_저장했다_읽어도_같다() throws {
        var game = FootballGame.make(seed: 5)
        try game.startMatch(now: TestGame.hours(1))
        for _ in 0..<120 { game.stepMatch() }
        #expect(game.liveFootball != nil)
        let loaded = try JSONDecoder().decode(Game.self, from: JSONEncoder().encode(game))
        #expect(loaded == game)
        var a = game, b = loaded
        a.runMatchToEnd()
        b.runMatchToEnd()
        #expect(a == b)
        #expect(a.lastResult != nil)
    }
}

@Suite struct FootballSeasonTests {
    @Test func 한_시즌을_치르면_승점으로_순위가_정해지고_다음_시즌이_시작된다() throws {
        var game = FootballGame.make(seed: 21)
        var manager = AutoManager(tokensPerMatch: 300_000)
        for _ in 0..<36 { try manager.playOne(&game) }
        #expect(game.round == 36 || game.phase != .regular)
        for tier in LeagueTier.allCases {
            let rows = game.rankedStandings(tier)
            #expect(rows.allSatisfy { $0.games == 36 })
            #expect(zip(rows, rows.dropFirst()).allSatisfy { $0.points >= $1.points })
            // 한 리그의 승·패 수는 같고, 득점과 실점의 합도 같다.
            #expect(rows.reduce(0) { $0 + $1.wins } == rows.reduce(0) { $0 + $1.losses })
            #expect(rows.reduce(0) { $0 + $1.runsFor } == rows.reduce(0) { $0 + $1.runsAgainst })
            let goals = Double(rows.reduce(0) { $0 + $1.runsFor }) / 180
            #expect((1.8...3.8).contains(goals), "\(tier.displayName) 경기당 \(goals)골")
            let draws = Double(rows.reduce(0) { $0 + $1.draws }) / 360
            #expect((0.12...0.42).contains(draws), "\(tier.displayName) 무승부 \(draws)")
        }
        #expect(game.awards.contains { $0.title == "득점왕" })
        #expect(game.awards.contains { $0.title == "최우수 골키퍼" })
        while game.season == 1 { try manager.playOne(&game) }
        #expect(game.phase == .regular)
        #expect(game.round == 0)
        Invariants.check(game, "축구 2시즌 시작")
        #expect(game.players.values.allSatisfy { $0.football?.games == 0 || $0.teamID == nil })
    }

    @Test(arguments: [UInt64(31), 32, 33])
    func 세_시즌을_돌려도_멈추지_않는다(seed: UInt64) throws {
        var game = FootballGame.make(seed: seed)
        var manager = AutoManager(tokensPerMatch: seed == 31 ? 0 : 40_000_000)
        var refounded = 0
        while game.season <= 3 {
            if game.isBankrupt {
                refounded += 1
                try game.foundNewClub(setup: .init(city: "대전", name: "대전 재창단 \(refounded) FC"), now: manager.clock)
            }
            let season = game.season
            try manager.playOne(&game)
            if game.season != season { Invariants.check(game, "축구 시드 \(seed) \(game.season)시즌") }
        }
        #expect(game.sport == .football)
    }

    @Test func 성적이_좋으면_승격한다() throws {
        // 토큰을 넉넉히 쓰는 구단은 몇 시즌 안에 6부를 벗어난다.
        var game = FootballGame.make(seed: 44)
        var manager = AutoManager(tokensPerMatch: 300_000_000)
        while game.season <= 4, game.userTier == .citizenAmateur { try manager.playOne(&game) }
        #expect(game.userTier < .citizenAmateur)
    }
}
