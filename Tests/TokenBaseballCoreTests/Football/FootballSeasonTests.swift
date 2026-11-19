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
        #expect(game.teams.count == 120)
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
        for _ in 0..<38 { try manager.playOne(&game) }
        #expect(game.round == 38 || game.phase != .regular)
        for tier in LeagueTier.allCases {
            let rows = game.rankedStandings(tier)
            #expect(rows.allSatisfy { $0.games == 38 })
            #expect(zip(rows, rows.dropFirst()).allSatisfy { $0.points >= $1.points })
            // 한 리그의 승·패 수는 같고, 득점과 실점의 합도 같다.
            #expect(rows.reduce(0) { $0 + $1.wins } == rows.reduce(0) { $0 + $1.losses })
            #expect(rows.reduce(0) { $0 + $1.runsFor } == rows.reduce(0) { $0 + $1.runsAgainst })
            // 20팀이 38라운드를 치르면 380경기다.
            let matches = Double(rows.count / 2 * game.roundsPerSeason)
            let goals = Double(rows.reduce(0) { $0 + $1.runsFor }) / matches
            #expect((1.8...3.8).contains(goals), "\(tier.displayName) 경기당 \(goals)골")
            let draws = Double(rows.reduce(0) { $0 + $1.draws }) / (matches * 2)
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

@Suite struct SportSwitchTests {
    static func temporaryStore() -> SaveStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tb-sport-\(UUID().uuidString)", isDirectory: true)
        return SaveStore(fileURL: directory.appendingPathComponent("save.json"))
    }

    @Test func 종목별_저장_파일은_같은_폴더에_따로_있다() throws {
        let store = Self.temporaryStore()
        #expect(store.sibling(for: .baseball).fileURL == store.fileURL)
        #expect(store.sibling(for: .football).fileURL.lastPathComponent == "save-football.json")
        #expect(store.sibling(for: .football).fileURL.deletingLastPathComponent() == store.fileURL.deletingLastPathComponent())

        #expect(store.loadActiveSport() == .baseball)
        try store.sibling(for: .football).save(GameSave(game: FootballGame.make()))
        #expect(!store.exists)
        #expect(try store.load() == nil)
        #expect(try store.sibling(for: .football).load()?.game.sport == .football)
        try store.saveActiveSport(.football)
        #expect(store.loadActiveSport() == .football)
        try FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent())
    }

    @Test func 쉬는_동안_쓴_토큰은_돌아와도_자금이_되지_않는다() {
        var game = TestGame.make()
        TestGame.addTokens(&game, 1_000, id: "before", at: TestGame.hours(1))
        let before = game.funds.balance
        // 다른 종목을 하는 동안 쓴 토큰 (3시간째), 돌아온 시각 (5시간째)
        let away = UsageRecord(id: "away", timestamp: TestGame.hours(3), usage: TokenUsage(output: 50_000))
        let justBefore = UsageRecord(
            id: "just", timestamp: TestGame.hours(5).addingTimeInterval(-30), usage: TokenUsage(output: 7_000))
        game.resume(now: TestGame.hours(5))
        game.collect([away, justBefore], now: TestGame.hours(5).addingTimeInterval(10))
        #expect(game.funds.balance == before)
        // 돌아온 뒤에 쓴 토큰은 센다.
        let after = UsageRecord(id: "after", timestamp: TestGame.hours(5).addingTimeInterval(60), usage: TokenUsage(output: 2_000))
        game.collect([away, justBefore, after], now: TestGame.hours(6))
        #expect(game.funds.balance == before + 2_000)
    }

    @Test func 쉬는_동안에는_경기_기회가_쌓이지_않는다() throws {
        var game = FootballGame.make()
        try TestGame.playOne(&game, at: TestGame.hours(0.1))
        #expect(game.charges == 0)
        game.resume(now: TestGame.hours(10))
        game.refreshCharges(now: TestGame.hours(10))
        #expect(game.charges == 0)
        game.refreshCharges(now: TestGame.hours(11.01))
        #expect(game.charges == 1)
    }

    @Test func 상단바에_축구_점수와_경기_시간이_나온다() throws {
        var game = FootballGame.make(seed: 9)
        #expect(game.menuBarTooltip(now: TestGame.start, todayTokens: 0).contains("⚽○○"))
        try game.startMatch(now: TestGame.hours(1))
        for _ in 0..<30 { game.stepMatch() }
        let text = game.menuBarText(now: TestGame.hours(1), todayTokens: 0)
        #expect(text.hasPrefix("⚽ "))
        #expect(text.hasSuffix("'"))
        game.runMatchToEnd()
        #expect(game.menuBarText(now: TestGame.hours(1), todayTokens: 0).hasPrefix("⚽ 경기 종료"))
    }
}

@Suite struct FootballLeagueSizeTests {
    @Test func 축구는_리그마다_스무_팀이_38라운드를_치른다() throws {
        let game = Game.newCareer(
            setup: CareerSetup(name: "스무팀", position: .midfielder), now: TestGame.start, seed: 11)
        #expect(game.teams.count == 120)
        #expect(Set(game.teams.map(\.name)).count == 120)
        for tier in LeagueTier.allCases {
            #expect(game.teams(in: tier).count == 20)
            let schedule = game.schedules[tier.index]
            #expect(schedule.count == 38)
            #expect(schedule.allSatisfy { $0.count == 10 })
            // 모든 팀이 다른 모든 팀과 홈에서 한 번, 원정에서 한 번 만난다.
            var pairs: [String: Int] = [:]
            for fixture in schedule.flatMap({ $0 }) { pairs["\(fixture.home)-\(fixture.away)", default: 0] += 1 }
            #expect(pairs.count == 20 * 19)
            #expect(pairs.values.allSatisfy { $0 == 1 })
        }
        #expect(game.roundsPerSeason == 38)
        // 6부의 가운데 구단에 입단한다.
        #expect(game.userTier == .citizenAmateur)
        // 야구는 그대로다.
        let baseball = TestCareer.make(.shortstop)
        #expect(baseball.teams.count == 60)
        #expect(baseball.roundsPerSeason == 36)
    }

    @Test func 컵대회는_120팀이_일곱_라운드를_치른다() throws {
        var game = Game.newCareer(
            setup: CareerSetup(name: "컵", position: .forward), now: TestGame.start, seed: 12)
        game.ensureCup()
        var cup = try #require(game.cup)
        #expect(cup.byes.count == 8)
        #expect(cup.ties.count == 56)
        #expect(cup.totalRounds == 7)
        #expect(cup.roundName == "1라운드")
        var names: [String] = []
        while let now = game.cup, !now.isFinished {
            names.append(now.roundName)
            #expect(now.totalRounds == 7)
            game.finishCupRound()
        }
        #expect(names == ["1라운드", "64강", "32강", "16강", "8강", "준결승", "결승"])
        cup = try #require(game.cup)
        let champion = try #require(cup.champion)
        #expect(cup.path(of: champion).map(\.round).suffix(6) == ["64강", "32강", "16강", "8강", "준결승", "결승"])
        #expect(Balance.cupByes(entrants: 60) == 4)
        #expect(Balance.cupByes(entrants: 120) == 8)
        #expect(Balance.cupByes(entrants: 64) == 0)
    }

    @Test func 열_팀_리그로_만든_저장은_다음_시즌에_스무_팀으로_채워진다() throws {
        var game = Game.newCareer(
            setup: CareerSetup(name: "옛 선수", position: .forward), now: TestGame.start, seed: 13, leagueSize: 10)
        #expect(game.teams.count == 60)
        #expect(game.roundsPerSeason == 36)
        let oldNames = game.teams.map(\.name)
        var auto = CareerAuto()
        // 시즌 도중: 저장했다가 불러와도 열 팀 36라운드로 그 시즌을 끝까지 치른다.
        var regular = 0
        var cupRounds = 0
        for _ in 0..<5 {
            if game.nextMatch()?.kind == .regular { regular += 1 }
            try auto.playOne(&game)
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("legacy-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SaveStore(fileURL: url)
        try store.save(GameSave(game: game))
        game = try #require(try store.load()).game
        var guardCount = 0
        while game.season == 1, guardCount < 80 {
            guardCount += 1
            #expect(game.teams.count == 60)
            if game.nextMatch()?.kind == .regular { regular += 1 }
            try auto.playOne(&game)
            if let cup = game.cup, cup.season == 1 { cupRounds = cup.history.count }
        }
        #expect(regular == 36)
        #expect(cupRounds == 6)

        // 새 시즌: 리그마다 열 팀이 채워진다.
        #expect(game.season == 2)
        #expect(game.teams.count == 120)
        #expect(Array(game.teams.map(\.name).prefix(60)) == oldNames)
        #expect(Set(game.teams.map(\.name)).count == 120)
        for tier in LeagueTier.allCases {
            #expect(game.teams(in: tier).count == 20)
            #expect(game.schedules[tier.index].count == 38)
            #expect(game.standings[tier.index].count == 20)
            for team in game.teams(in: tier) {
                #expect(game.roster(of: team.id).count >= Balance.footballStarters)
                #expect(Balance.strengthRange(tier).contains(game.strength(of: team.id).rounded()))
            }
        }
        #expect(game.roundsPerSeason == 38)
        #expect(game.news.contains { $0.text.contains("리그 확장") })
        #expect(game.myPlayer?.name == "옛 선수")
        for _ in 0..<6 { try auto.playOne(&game) }
        #expect(game.cup?.totalRounds == 7)
        try store.save(GameSave(game: game))
        #expect(try store.load()?.game == game)
        // 다시 채우지 않는다.
        #expect(game.expandLeaguesIfNeeded() == 0)
    }
}
