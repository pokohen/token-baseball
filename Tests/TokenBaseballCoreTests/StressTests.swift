import Foundation
import Testing
@testable import TokenBaseballCore

/// 여러 시드·여러 리그·여러 운영 방식으로 길게 돌려 보는 검사.
/// 오래 걸리므로 `TB_STRESS=1 swift test --filter StressTests`로만 돈다.
@Suite struct StressTests {
    static var enabled: Bool { ProcessInfo.processInfo.environment["TB_STRESS"] == "1" }

    /// 순위표의 모든 팀이 같은 수의 경기를 치렀는지 (건너뛴 경기가 없는지).
    /// `resetAt`: 시즌 중에 재창단해 순위표를 0부터 다시 센 자리와 그때의 라운드.
    static func checkRounds(_ game: Game, resetAt: [TeamID: Int], _ comment: Comment) {
        guard game.phase == .regular else { return }
        for tier in LeagueTier.allCases {
            for row in game.standings[tier.index] {
                let played = row.wins + row.losses + row.draws
                let expected = game.round - (resetAt[row.teamID] ?? 0)
                #expect(played == expected, "\(comment) \(game.teams[row.teamID].name) \(played)/\(expected)")
            }
        }
    }

    static func run(
        tier: LeagueTier, seed: UInt64, active: Bool, tokens: Int, seasons: Int, sport: Sport = .baseball
    ) throws {
        var game = sport == .football
            ? FootballGame.make(seed: seed)
            : tier == .citizenAmateur
            ? TestGame.make(seed: seed)
            : UpperLeagueTests.game(in: tier, ability: mid(Balance.abilityRange(tier)), seed: seed)
        var manager = AutoManager(tokensPerMatch: tokens)
        let label = "\(sport.label) \(tier.displayName) 시드 \(seed) \(active ? "적극" : "방치") 토큰 \(tokens)"
        var refounded = 0
        var resetAt: [TeamID: Int] = [:]
        while game.season <= seasons {
            if game.isBankrupt {
                refounded += 1
                try game.foundNewClub(setup: .init(city: "대전", name: "재창단 \(seed)-\(refounded)"), now: manager.clock)
                if game.phase == .regular { resetAt[game.userTeamID] = game.round }
            }
            manager.clock = manager.clock.addingTimeInterval(3600)
            manager.tokenID += 1
            if tokens > 0 {
                TestGame.addTokens(&game, tokens, id: "t\(manager.tokenID)", at: manager.clock)
            }
            if active { manager.manage(&game) }
            let season = game.season
            do {
                try game.startMatch(now: manager.clock)
            } catch {
                Issue.record("\(label): \(game.season)시즌 \(game.phase) \(game.round)라운드에서 멈춤: \(error)")
                return
            }
            game.runMatchToEnd()
            if game.season != season {
                resetAt = [:]
                Invariants.check(game, "\(label) \(game.season)시즌 시작")
            }
            checkRounds(game, resetAt: resetAt, "\(label)")
            // 저장했다 불러와도 같은 상태여야 한다.
            if manager.tokenID % 25 == 0 {
                let data = try JSONEncoder().encode(game)
                let loaded = try JSONDecoder().decode(Game.self, from: data)
                #expect(loaded == game, "\(label) 저장·불러오기")
            }
        }
    }

    /// 축구는 6부에서 시작해 길게 돌린다. 토큰을 많이 쓰는 쪽은 여러 리그를 거쳐 올라간다.
    @Test(.enabled(if: StressTests.enabled), arguments: [UInt64(1), 2, 3, 4, 5, 6])
    func 축구도_여러_시드로_돌려도_멈추거나_무너지지_않는다(seed: UInt64) throws {
        try Self.run(tier: .citizenAmateur, seed: seed, active: false, tokens: 0, seasons: 3, sport: .football)
        try Self.run(tier: .citizenAmateur, seed: seed &+ 100, active: false, tokens: 30_000_000, seasons: 4, sport: .football)
        try Self.run(tier: .citizenAmateur, seed: seed &+ 200, active: true, tokens: 300_000_000, seasons: 8, sport: .football)
    }

    static func mid(_ range: ClosedRange<Double>) -> Double { (range.lowerBound + range.upperBound) / 2 }

    @Test(.enabled(if: StressTests.enabled), arguments: LeagueTier.allCases)
    func 여러_시드로_돌려도_멈추거나_무너지지_않는다(tier: LeagueTier) throws {
        for seed in UInt64(1)...6 {
            // 방치: 아무것도 누르지 않는다. 돈이 없으면 파산과 재창단을 거친다.
            try Self.run(tier: tier, seed: seed, active: false, tokens: 0, seasons: 3)
            try Self.run(tier: tier, seed: seed &+ 100, active: false, tokens: 30_000_000, seasons: 3)
            try Self.run(tier: tier, seed: seed &+ 200, active: true, tokens: 300_000_000, seasons: 3)
        }
    }
}
