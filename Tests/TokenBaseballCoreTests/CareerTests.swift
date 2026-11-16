import Foundation
import Testing
@testable import TokenBaseballCore

enum TestCareer {
    static func make(_ position: Position = .shortstop, seed: UInt64 = 1) -> Game {
        Game.newCareer(
            setup: CareerSetup(name: "김테스트", position: position, bats: .left, throwsHand: .right, hometown: "부산"),
            now: TestGame.start, seed: seed)
    }
}

/// 선수 모드를 자동으로 진행한다: 훈련하고, 제안에 답하고, 경기를 치른다.
struct CareerAuto {
    var clock = TestGame.start
    var tokenID = 0
    var tokensPerMatch = 5_000_000
    /// 윗 리그 구단의 이적 제안을 받아들일지.
    var acceptsTransfers = true

    mutating func playOne(_ game: inout Game) throws {
        clock = clock.addingTimeInterval(3600)
        tokenID += 1
        TestGame.addTokens(&game, tokensPerMatch, id: "c\(tokenID)", at: clock)
        manage(&game)
        try game.startMatch(now: clock)
        game.runMatchToEnd()
    }

    func manage(_ game: inout Game) {
        guard let career = game.career, !career.retired else { return }
        // 제안: 무소속이면 가장 높은 리그의 구단, 재계약은 수락, 이적은 윗 리그만.
        if career.isFreeAgent {
            let best = career.offers.min { game.teams[$0.teamID].tier < game.teams[$1.teamID].tier }
            if let best { try? game.acceptCareerOffer(best.id) }
        } else if let renewal = career.offers.first(where: { $0.kind == .renewal }) {
            try? game.acceptCareerOffer(renewal.id)
        } else if acceptsTransfers,
                  let move = career.offers.first(where: { game.teams[$0.teamID].tier < game.userTier }) {
            try? game.acceptCareerOffer(move.id)
        }
        // 훈련: 값이 가장 낮은 능력치부터.
        for _ in 0..<Balance.careerSessionsPerMatch {
            guard let me = game.myPlayer else { break }
            let keys = game.careerTrainableKeys.sorted { me.attributes[$0] < me.attributes[$1] }
            if let key = keys.first(where: { game.careerTrainingBlockedReason($0) == nil }) {
                try? game.trainCareer(key)
            } else if me.potential - me.ability < 2 {
                try? game.breakThroughCareer()
            }
        }
    }
}

@Suite struct CareerStartTests {
    @Test func 구단_모드에는_선수_모드_상태가_없다() {
        let game = TestGame.make()
        #expect(game.career == nil)
        #expect(!game.isCareer)
        #expect(game.myPlayer == nil)
    }

    @Test(arguments: [Position.shortstop, .catcher, .designated, .starter, .reliever])
    func 열여섯_살에_6부_구단에_입단한다(position: Position) throws {
        let game = TestCareer.make(position)
        let me = try #require(game.myPlayer)
        #expect(game.teams.count == 60)
        #expect(game.teams.allSatisfy { !$0.isUser })
        #expect(me.name == "김테스트")
        #expect(me.age == 16)
        #expect(me.position == position)
        #expect(me.bats == .left)
        #expect(me.teamID == game.userTeamID)
        #expect(game.userTier == .citizenAmateur)
        #expect(Balance.careerPotential.contains(me.potential))
        #expect(game.funds.balance == FundsLedger.startingFunds)
        // 같은 포지션 선수의 자리를 넘겨받으므로 로스터 구성은 그대로다.
        let roster = game.roster(of: game.userTeamID)
        #expect(roster.count == PlayerFactory.rosterPositions(.citizenAmateur).count)
        #expect(roster.map(\.position).sorted { $0.rawValue < $1.rawValue }
            == PlayerFactory.rosterPositions(.citizenAmateur).sorted { $0.rawValue < $1.rawValue })
        #expect(game.career?.clubs == [game.userTeam.name])
        #expect(game.career?.goal != nil)
    }

    @Test func 저장했다가_불러와도_그대로다() throws {
        var game = TestCareer.make(.starter, seed: 7)
        var auto = CareerAuto()
        for _ in 0..<3 { try auto.playOne(&game) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("career-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SaveStore(fileURL: url)
        try store.save(GameSave(game: game))
        #expect(try store.load()?.game == game)
    }
}

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

@Suite struct CareerTrainingTests {
    @Test func 훈련_포인트를_써서_능력치를_올린다() throws {
        var game = TestCareer.make(.shortstop)
        #expect(Set(game.careerTrainableKeys) == [.contact, .power, .eye, .speed, .fielding, .arm])
        // 시작 포인트(10만)로는 첫 훈련을 할 수 없다.
        #expect(throws: GameError.self) { try game.trainCareer(.contact) }

        TestGame.addTokens(&game, 10_000_000, id: "a", at: TestGame.hours(1))
        let before = try #require(game.myPlayer)
        let cost = game.careerTrainingCost(.contact)
        #expect(cost == Balance.careerTrainingCost(value: before.attributes.contact))
        let balance = game.funds.balance
        try game.trainCareer(.contact)
        let after = try #require(game.myPlayer)
        #expect(after.attributes.contact == before.attributes.contact + 1)
        #expect(after.ability > before.ability)
        #expect(game.funds.balance == balance - cost)
        #expect(game.funds.seasonExpense[FundsLedger.Category.training.rawValue] == cost)
    }

    @Test func 경기_사이에_정해진_횟수만_훈련한다() throws {
        var game = TestCareer.make(.starter)
        #expect(Set(game.careerTrainableKeys) == [.stuff, .control, .breaking, .stamina])
        TestGame.addTokens(&game, 50_000_000, id: "a", at: TestGame.hours(1))
        for _ in 0..<Balance.careerSessionsPerMatch { try game.trainCareer(.stuff) }
        #expect(game.career?.sessionsLeft == 0)
        #expect(throws: GameError.self) { try game.trainCareer(.control) }
        // 타자 능력치는 투수가 올릴 수 없다.
        #expect(game.careerTrainingBlockedReason(.contact) != nil)

        try TestGame.playOne(&game, at: TestGame.hours(2))
        #expect(game.career?.sessionsLeft == Balance.careerSessionsPerMatch)
        try game.trainCareer(.control)
    }

    @Test func 가격_난이도가_훈련_비용에도_적용된다() {
        var game = TestCareer.make(.first)
        let normal = game.careerTrainingCost(.power)
        game.settings.priceDifficulty = 0.5
        #expect(game.careerTrainingCost(.power) == normal / 2)
    }

    @Test func 잠재력과_나이가_훈련의_한계다() throws {
        var game = TestCareer.make(.first)
        TestGame.addTokens(&game, 500_000_000, id: "a", at: TestGame.hours(1))
        let id = try #require(game.career?.playerID)

        // 한계에 가까우면 비용이 두 배.
        let cost = game.careerTrainingCost(.power)
        let ability = try #require(game.myPlayer).ability
        game.players[id]?.potential = ability + 5
        #expect(game.careerTrainingCost(.power) == cost * 2)
        // 한계에 닿으면 오르지 않는다.
        game.players[id]?.potential = ability
        #expect(throws: GameError.self) { try game.trainCareer(.power) }

        game.players[id]?.potential = 90
        game.players[id]?.age = Balance.careerTrainingAgeLimit
        #expect(throws: GameError.self) { try game.trainCareer(.power) }
        game.players[id]?.age = Balance.careerTrainingAgeLimit - 1
        try game.trainCareer(.power)
    }
}

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

@Suite struct CareerSeasonTests {
    @Test(arguments: [(Position.shortstop, UInt64(21)), (.starter, 22), (.reliever, 23), (.catcher, 24)])
    func 세_시즌을_보내도_멈추지_않고_선수가_자란다(position: Position, seed: UInt64) throws {
        var game = TestCareer.make(position, seed: seed)
        var auto = CareerAuto()
        let start = try #require(game.myPlayer).ability
        var guardCount = 0
        while game.season <= 3 {
            try auto.playOne(&game)
            guardCount += 1
            #expect(guardCount < 400)
            let career = try #require(game.career)
            if !career.isFreeAgent {
                let me = try #require(game.myPlayer)
                #expect(me.teamID == game.userTeamID)
                #expect(game.teams[game.userTeamID].roster.contains(me.id))
            }
            #expect(game.teams.allSatisfy { !$0.isUser })
            #expect((0.0...100.0).contains(career.trust))
            #expect((0.0...100.0).contains(career.fame))
        }
        let career = try #require(game.career)
        let me = try #require(game.myPlayer)
        #expect(career.history.count == 3)
        #expect(me.age == 19)
        #expect(me.ability > start + 10)
        #expect(me.ability <= me.potential + 0.001)
        #expect(career.earnings > 0)
        #expect(career.trainingCount > 60)
        #expect(career.history.allSatisfy { $0.ratedGames > 0 })
        let totals = game.careerTotals
        #expect(totals.ratedGames == career.history.reduce(0) { $0 + $1.ratedGames } + career.seasonRatedGames)
    }

    @Test func 은퇴하면_기록실에_남고_같은_세계에서_새_선수로_시작한다() throws {
        var game = TestCareer.make(.third, seed: 31)
        var auto = CareerAuto()
        let id = try #require(game.career?.playerID)
        #expect(!game.canRetireCareer)
        while game.phase != .offseason { try auto.playOne(&game) }
        #expect(throws: GameError.self) { try game.retireCareer() }

        game.players[id]?.age = Balance.careerVoluntaryRetirementAge
        #expect(game.canRetireCareer)
        let club = game.userTeamID
        try game.retireCareer()
        #expect(game.career?.retired == true)
        #expect(game.myPlayer == nil)
        #expect(game.players[id] == nil)
        #expect(!game.teams[club].roster.contains(id))
        #expect(game.nextMatch() == nil)
        let record = try #require(game.careerHall?.last)
        #expect(record.name == "김테스트")
        #expect(record.batting.games == Balance.roundsPerSeason)
        #expect(record.clubs.count >= 1)

        let teams = game.teams.map(\.name)
        try game.startNewCareer(
            setup: CareerSetup(name: "이새싹", position: .reliever), now: auto.clock.addingTimeInterval(60))
        let rookie = try #require(game.myPlayer)
        #expect(rookie.name == "이새싹")
        #expect(rookie.age == Balance.careerStartAge)
        #expect(game.career?.retired == false)
        #expect(game.career?.history.isEmpty == true)
        #expect(game.teams.map(\.name) == teams)
        #expect(game.funds.balance == FundsLedger.startingFunds)
        #expect(game.careerHall?.count == 1)
        for _ in 0..<8 { try auto.playOne(&game) }
        #expect(game.season == 2)
    }

    @Test func 서른여덟_살_시즌이_끝나면_은퇴한다() throws {
        var game = TestCareer.make(.first, seed: 32)
        var auto = CareerAuto()
        let id = try #require(game.career?.playerID)
        game.players[id]?.age = Balance.careerForcedRetirementAge - 1
        while game.career?.retired != true {
            try auto.playOne(&game)
            #expect(game.season == 1)
        }
        #expect(game.careerHall?.last?.retiredAge == Balance.careerForcedRetirementAge)
    }

    @Test func 구단이_승격하면_내_선수도_윗_리그에서_뛴다() throws {
        var game = TestCareer.make(.center, seed: 33)
        let salary = try #require(game.myPlayer).contract.salary
        game.careerClubMoved(from: .citizenAmateur, to: .citizenSemiPro)
        #expect(try #require(game.myPlayer).contract.salary > salary)
        #expect(game.career?.bestTier == .citizenSemiPro)
    }
}

@Suite struct CareerExtraTests {
    @Test func 한계_돌파_훈련은_잠재력을_넓힌다() throws {
        var game = TestCareer.make(.starter)
        #expect(throws: GameError.self) { try game.breakThroughCareer() }
        TestGame.addTokens(&game, 100_000_000, id: "a", at: TestGame.hours(1))
        let before = try #require(game.myPlayer).potential
        let balance = game.funds.balance
        try game.breakThroughCareer()
        #expect(try #require(game.myPlayer).potential == min(99, before + 1))
        #expect(game.funds.balance == balance - Balance.careerBreakthroughCost)
        #expect(game.career?.sessionsLeft == Balance.careerSessionsPerMatch - 1)
    }

    @Test func 선수_모드는_저장_파일을_따로_쓴다() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("slot-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = SaveStore(fileURL: folder.appendingPathComponent("save.json"))
        #expect(store.sibling(slot: SaveSlot.baseball).fileURL.lastPathComponent == "save.json")
        #expect(store.sibling(slot: SaveSlot.football).fileURL.lastPathComponent == "save-football.json")
        #expect(store.sibling(slot: SaveSlot.baseballPlayer).fileURL.lastPathComponent == "save-baseball-player.json")
        #expect(store.sibling(for: Sport.football).fileURL == store.sibling(slot: SaveSlot.football).fileURL)

        #expect(store.loadActiveSlot() == .baseball)
        try store.saveActiveSlot(.baseballPlayer)
        #expect(store.loadActiveSlot() == .baseballPlayer)
        #expect(store.loadActiveSport() == .baseball)
        // 예전에 종목 이름으로 적어 둔 파일도 그대로 읽힌다.
        try store.saveActiveSport(.football)
        #expect(store.loadActiveSlot() == .football)
    }

    @Test func 상단바에는_훈련_포인트가_나온다() {
        let game = TestCareer.make(.center)
        #expect(game.menuBarText(now: TestGame.start, todayTokens: 0) == "100.0K P •")
        #expect(game.menuBarTooltip(now: TestGame.start, todayTokens: 0).contains("훈련 포인트"))
    }

    @Test func 수상하면_명성이_오르고_커리어에_남는다() throws {
        var game = TestCareer.make(.center, seed: 41)
        let id = try #require(game.career?.playerID)
        var auto = CareerAuto()
        // 리그를 압도하는 타자로 만든다.
        for key in [Attributes.Key.contact, .power, .eye] { game.players[id]?.attributes[key] = 95 }
        game.players[id]?.potential = 99
        while game.phase == .regular { try auto.playOne(&game) }
        let career = try #require(game.career)
        #expect(!career.awards.isEmpty)
        #expect(career.history.first?.awards.isEmpty == false)
        #expect(game.awards.contains { $0.isMine && $0.playerName == "김테스트" })
        #expect(game.awards.filter(\.isMine).allSatisfy { $0.playerName == "김테스트" })
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

@Suite struct CareerCostTests {
    @Test func 훈련할_때마다_비용이_조금씩_오른다() throws {
        var game = TestCareer.make(.starter)
        TestGame.addTokens(&game, 50_000_000, id: "a", at: TestGame.hours(1))
        let first = game.careerTrainingCost(.stuff)
        try game.trainCareer(.stuff)
        let second = game.careerTrainingCost(.stuff)
        #expect(second > first)
        #expect(Double(second) < Double(first) * 1.15)
        // 값이 오를수록 계속 비싸진다.
        let costs = stride(from: 1.0, through: 99.0, by: 1).map { Balance.careerTrainingCost(value: $0) }
        #expect(zip(costs, costs.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(Balance.careerTrainingCost(value: 25) == 250_000)
    }
}
