import Foundation
import Testing
@testable import TokenBaseballCore

enum TestGame {
    static let start = Date(timeIntervalSince1970: 1_800_000_000)

    static func make(seed: UInt64 = 1) -> Game {
        Game.newGame(setup: .init(city: "서울", name: "서울 테스트 야구단"), now: start, seed: seed)
    }

    static func hours(_ count: Double) -> Date { start.addingTimeInterval(count * 3600) }

    /// 토큰을 쓴 것처럼 자금을 넣는다.
    static func addTokens(_ game: inout Game, _ amount: Int, id: String, at date: Date) {
        game.funds.collect(
            [UsageRecord(id: id, timestamp: date, usage: TokenUsage(output: amount))],
            now: date.addingTimeInterval(1))
    }

    /// 경기 한 번을 끝까지 치른다.
    static func playOne(_ game: inout Game, at date: Date) throws {
        try game.startMatch(now: date)
        game.runMatchToEnd()
    }
}

@Suite struct NewGameTests {
    @Test func 여섯_리그에_열_팀씩_있다() {
        let game = TestGame.make()
        #expect(game.teams.count == 60)
        for tier in LeagueTier.allCases {
            #expect(game.teams(in: tier).count == 10)
        }
        #expect(game.userTier == .citizenAmateur)
        #expect(game.userTeam.name == "서울 테스트 야구단")
        #expect(game.funds.balance == 100_000)
    }

    @Test func 일부_프로_구단_이름은_정해진_가상_구단이다() {
        let names = TestGame.make().teams(in: .pro).map(\.name)
        #expect(names == [
            "광주 호랑이", "대구 사자", "부산 거인", "대전 독수리", "잠실 곰",
            "서울 쌍둥이", "고척 영웅", "인천 상륙단", "수원 마법사", "창원 공룡",
        ])
        #expect(Set(TestGame.make().teams.map(\.name)).count == 60)
    }

    @Test(arguments: 1...30 as ClosedRange<UInt64>)
    func 시작_로스터는_14명이고_잠재력이_높지_않다(seed: UInt64) {
        let game = TestGame.make(seed: seed)
        let roster = game.roster(of: game.userTeamID)
        #expect(roster.count == 14)
        #expect(roster.filter { !$0.isPitcher }.count == 9)
        #expect(Set(roster.filter { !$0.isPitcher }.map(\.position)).count == 9)
        #expect(roster.allSatisfy { (25.0...35.0).contains($0.ability.rounded()) })
        // 숨은 보석은 많아야 1명
        let gems = roster.filter { $0.potential > 45 }
        #expect(gems.count <= 1)
        for gem in gems {
            #expect((55.0...65.0).contains(gem.potential))
            #expect(gem.scoutStars(scoutLevel: 0) <= 2)
        }
        #expect(game.currentLineup != nil)
    }

    @Test(arguments: 1...40 as ClosedRange<UInt64>)
    func 모든_팀_강도가_리그_범위_안이고_능력은_잠재력을_넘지_않는다(seed: UInt64) {
        let game = TestGame.make(seed: seed)
        for team in game.teams {
            #expect(Balance.strengthRange(team.tier).contains(game.strength(of: team.id)), "\(team.name)")
            for player in game.roster(of: team.id) {
                #expect(player.ability <= player.potential + 0.001)
            }
        }
    }

    @Test func 같은_시드면_같은_세계가_만들어진다() {
        #expect(TestGame.make(seed: 77) == TestGame.make(seed: 77))
        #expect(TestGame.make(seed: 77) != TestGame.make(seed: 78))
    }
}

@Suite struct MatchChargeTests {
    @Test func 경기_기회는_1시간마다_하나씩_최대_3개까지_쌓인다() throws {
        var game = TestGame.make()
        #expect(game.charges == 1)
        try TestGame.playOne(&game, at: TestGame.hours(0))
        #expect(game.charges == 0)
        #expect(throws: GameError.self) { try game.startMatch(now: TestGame.hours(0.5)) }

        game.refreshCharges(now: TestGame.hours(0.99))
        #expect(game.charges == 0)
        game.refreshCharges(now: TestGame.hours(1))
        #expect(game.charges == 1)
        game.refreshCharges(now: TestGame.hours(2.5))
        #expect(game.charges == 2)
        #expect(game.timeToNextCharge(now: TestGame.hours(2.5)) == 1800)
        game.refreshCharges(now: TestGame.hours(40))
        #expect(game.charges == 3)
        #expect(game.timeToNextCharge(now: TestGame.hours(40)) == nil)
    }

    @Test func 가득_찬_상태에서_쓰면_그때부터_1시간을_센다() throws {
        var game = TestGame.make()
        game.refreshCharges(now: TestGame.hours(100))
        #expect(game.charges == 3)
        try TestGame.playOne(&game, at: TestGame.hours(100))
        #expect(game.charges == 2)
        game.refreshCharges(now: TestGame.hours(100.5))
        #expect(game.charges == 2)
        game.refreshCharges(now: TestGame.hours(101))
        #expect(game.charges == 3)
    }

    @Test func 한_경기가_끝나야_다음_경기를_시작할_수_있다() throws {
        var game = TestGame.make()
        game.refreshCharges(now: TestGame.hours(10))
        try game.startMatch(now: TestGame.hours(10))
        #expect(throws: GameError.self) { try game.startMatch(now: TestGame.hours(10)) }
        game.runMatchToEnd()
        try game.startMatch(now: TestGame.hours(10))
    }
}

@Suite struct RoundTests {
    @Test func 내가_한_경기_하면_모든_리그가_한_라운드씩_진행된다() throws {
        var game = TestGame.make()
        try game.startMatch(now: TestGame.start)
        #expect(game.live?.others.count == 4)
        // 내 경기가 진행되는 동안에는 순위표가 바뀌지 않는다.
        for _ in 0..<50 { game.stepMatch() }
        #expect(game.standings.flatMap { $0 }.allSatisfy { $0.games == 0 })
        game.runMatchToEnd()

        #expect(game.round == 1)
        #expect(game.live == nil)
        for tier in LeagueTier.allCases {
            #expect(game.standings[tier.index].allSatisfy { $0.games == 1 })
        }
        let result = try #require(game.lastResult)
        #expect(result.kind == .regular)
        #expect(!result.acknowledged)
    }

    @Test func 경기_중에_저장했다_읽어도_똑같이_끝난다() throws {
        var game = TestGame.make(seed: 9)
        try game.startMatch(now: TestGame.start)
        for _ in 0..<100 { game.stepMatch() }

        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("token-baseball-tests-\(UUID().uuidString)/save.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = SaveStore(fileURL: file)
        try store.save(GameSave(game: game))
        var restored = try #require(try store.load()?.game)
        #expect(restored == game)

        game.runMatchToEnd()
        restored.runMatchToEnd()
        #expect(restored == game)
    }

    @Test func 경기마다_연봉이_나가고_홈_경기는_관중_수입이_들어온다() throws {
        var game = TestGame.make()
        let salary = game.salaryPerMatch
        #expect(salary > 0)
        let home = try #require(game.nextMatch()).userIsHome
        try TestGame.playOne(&game, at: TestGame.start)

        #expect(game.funds.seasonExpense["선수 연봉"] == salary)
        #expect((game.funds.seasonIncome["관중 수입"] ?? 0 > 0) == home)
    }

    @Test func 가격_난이도는_비용에만_곱한다() {
        var game = TestGame.make()
        let base = game.upgradeCost(.training)
        game.settings.priceDifficulty = 0.1
        #expect(game.upgradeCost(.training) == base.map { $0 / 10 })
        #expect(game.tryoutFee == 20_000)
        TestGame.addTokens(&game, 5_000, id: "a", at: TestGame.hours(1))
        #expect(game.funds.balance == 105_000)
    }
}

@Suite struct ClubTests {
    @Test func 시설을_올리면_돈이_나가고_레벨이_오른다() throws {
        var game = TestGame.make()
        #expect(throws: GameError.self) { try game.upgrade(.training) }
        TestGame.addTokens(&game, 100_000_000, id: "a", at: TestGame.hours(1))

        try game.upgrade(.training)
        #expect(game.userTeam.trainingLevel == 2)
        #expect(game.funds.balance == 100_100_000 - 10_000_000)

        let fame = game.userTeam.fame
        try game.upgrade(.stadium)
        #expect(game.userTeam.stadiumLevel == 2)
        #expect(game.userTeam.fame == fame + 40)
    }

    @Test func 같은_홍보는_쓸수록_효과가_줄어든다() throws {
        var game = TestGame.make()
        TestGame.addTokens(&game, 100_000_000, id: "a", at: TestGame.hours(1))
        try game.promote(.flyer)
        #expect(game.userTeam.fame == 5)
        try game.promote(.flyer)
        #expect(game.userTeam.fame == 9)
        #expect(game.promotionEffect(.flyer) == 3)

        #expect(throws: GameError.self) { try game.promote(.tv) }
        try game.promote(.festival)
        #expect(throws: GameError.self) { try game.promote(.festival) }
    }

    @Test func 승강_신청은_인지도와_신청비가_있어야_한다() throws {
        var game = TestGame.make()
        TestGame.addTokens(&game, 100_000_000, id: "a", at: TestGame.hours(1))
        #expect(throws: GameError.self) { try game.applyForPromotion() }
        try game.promote(.festival)
        try game.promote(.sns)
        #expect(game.userTeam.fame >= 100)
        let before = game.funds.balance
        try game.applyForPromotion()
        #expect(game.appliedForPromotion)
        #expect(game.funds.balance == before - 1_000_000)
        #expect(throws: GameError.self) { try game.applyForPromotion() }
    }

    @Test func 입단_테스트_후보와_계약하고_방출할_수_있다() throws {
        var game = TestGame.make()
        TestGame.addTokens(&game, 10_000_000, id: "a", at: TestGame.hours(1))
        // 처음에는 딱 최소 인원이라 방출할 수 없다.
        #expect(throws: GameError.self) { try game.release(game.userTeam.roster[0]) }

        try game.holdTryout()
        #expect((3...5).contains(game.candidates.count))
        let candidate = game.candidates[0]
        try game.sign(candidate: candidate.id)
        #expect(game.userTeam.roster.count == 15)
        #expect(game.players[candidate.playerID]?.teamID == game.userTeamID)

        // 남은 후보는 다음 경기가 끝나면 사라진다.
        let leftover = game.candidates.map(\.playerID)
        try TestGame.playOne(&game, at: TestGame.hours(2))
        #expect(game.candidates.isEmpty)
        #expect(leftover.allSatisfy { game.players[$0] == nil })

        try game.release(candidate.playerID)
        #expect(game.userTeam.roster.count == 14)
        #expect(game.freeAgents.contains(candidate.playerID))
    }

    @Test func 타순과_선발을_직접_정할_수_있다() throws {
        var game = TestGame.make()
        let batters = game.roster(of: game.userTeamID).filter { !$0.isPitcher }.map(\.id)
        let order = Array(batters.reversed())
        try game.setLineup(order)
        #expect(game.currentLineup?.batters.map(\.id) == order)
        #expect(throws: GameError.self) { try game.setLineup(Array(order.prefix(8))) }

        let reliever = try #require(game.roster(of: game.userTeamID).first { $0.position == .reliever })
        try game.setNextStarter(reliever.id)
        #expect(game.currentLineup?.starter == reliever.id)
        try TestGame.playOne(&game, at: TestGame.start)
        // 한 경기 쓰고 나면 지정이 풀린다.
        #expect(game.userTeam.starterOverride == nil)
    }

    @Test func 팀_이름은_언제든_바꿀_수_있다() throws {
        var game = TestGame.make()
        try game.renameTeam(game.userTeamID, to: "서울 야구단")
        #expect(game.userTeam.name == "서울 야구단")
        #expect(throws: GameError.self) { try game.renameTeam(game.userTeamID, to: "광주 호랑이") }
    }
}

@Suite struct GrowthTests {
    @Test func 스무_살_능력_30_잠재력_60_주전은_네댓_시즌에_잠재력_근처까지_큰다() {
        var rng = SeededRNG(seed: 1)
        var spec = PlayerFactory.Spec(position: .shortstop, tier: .citizenAmateur, season: 1)
        spec.ability = 30...30
        spec.age = 20...20
        spec.potential = 60...60
        var player = PlayerFactory.make(id: 1, spec: spec, &rng)

        var seasonsToNear: Int?
        for season in 1...8 {
            for _ in 0..<Balance.roundsPerSeason {
                Game.grow(&player, teamFactor: 1, playFactor: Balance.playFactorStarter, focus: TrainingFocus())
            }
            player.age += 1
            #expect(player.ability <= player.potential + 0.001)
            if seasonsToNear == nil, player.ability >= 56 { seasonsToNear = season }
        }
        #expect(seasonsToNear == 4 || seasonsToNear == 5)
    }

    @Test func 서른한_살부터는_크지_않고_잠재력에_닿으면_멈춘다() {
        var rng = SeededRNG(seed: 2)
        var spec = PlayerFactory.Spec(position: .starter, tier: .amateur, season: 1)
        spec.ability = 50...50
        spec.age = 31...31
        spec.potential = 70...70
        var veteran = PlayerFactory.make(id: 1, spec: spec, &rng)
        let before = veteran.ability
        Game.grow(&veteran, teamFactor: 2.5, playFactor: 1.2, focus: TrainingFocus())
        #expect(veteran.ability == before)

        spec.age = 20...20
        spec.potential = 50...50
        var capped = PlayerFactory.make(id: 2, spec: spec, &rng)
        Game.grow(&capped, teamFactor: 2.5, playFactor: 1.2, focus: TrainingFocus())
        #expect(capped.ability <= 50.001)
    }

    @Test func 훈련소_레벨이_높으면_더_빨리_큰다() {
        var rng = SeededRNG(seed: 3)
        var spec = PlayerFactory.Spec(position: .center, tier: .citizenAmateur, season: 1)
        spec.ability = 30...30
        spec.age = 20...20
        spec.potential = 60...60
        var slow = PlayerFactory.make(id: 1, spec: spec, &rng)
        var fast = slow
        Game.grow(&slow, teamFactor: 1.0, playFactor: 1.0, focus: TrainingFocus())
        Game.grow(&fast, teamFactor: 2.5, playFactor: 1.0, focus: TrainingFocus())
        #expect(fast.ability - 30 > (slow.ability - 30) * 2.4)
    }
}
