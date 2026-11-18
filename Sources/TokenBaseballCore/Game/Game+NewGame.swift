import Foundation

/// 새 게임: 6개 리그 60팀과 내 구단을 만든다.
extension Game {
    public struct ClubSetup: Equatable, Sendable {
        public var city: String
        public var name: String
        public var colorIndex: Int
        public var emblemIndex: Int

        public init(city: String, name: String, colorIndex: Int = 0, emblemIndex: Int = 0) {
            self.city = city
            self.name = name
            self.colorIndex = colorIndex
            self.emblemIndex = emblemIndex
        }
    }

    /// 새 게임: 6개 리그 60팀을 만들고, 내 시민 구단을 6부에 넣는다.
    public static func newGame(setup: ClubSetup, now: Date, seed: UInt64, sport: Sport = .baseball) -> Game {
        var game = Game(funds: FundsLedger(startedAt: now), rng: SeededRNG(seed: seed), chargeAnchor: now)
        if sport != .baseball { game.sportChoice = sport }
        var taken: Set<String> = [setup.name]

        for tier in LeagueTier.allCases {
            for slot in 0..<Balance.teamsPerLeague {
                let id = game.teams.count
                let isUser = tier == .citizenAmateur && slot == Balance.teamsPerLeague - 1
                if isUser {
                    var team = Team(
                        id: id, name: setup.name, city: setup.city, tier: tier, isUser: true, season: 1)
                    team.colorIndex = setup.colorIndex
                    team.emblemIndex = setup.emblemIndex
                    game.teams.append(team)
                    game.userTeamID = id
                    game.fillUserStartRoster()
                } else {
                    let identity = tier == .pro
                        ? NameGenerator.proTeams(sport)[slot]
                        : NameGenerator.cpuTeam(tier: tier, taken: taken, sport: sport, &game.rng)
                    taken.insert(identity.name)
                    game.teams.append(Team(
                        id: id, name: identity.name, city: identity.city, tier: tier, isUser: false, season: 1))
                    game.setUpCPUTeam(id, slot: slot)
                }
            }
        }
        game.startSeasonSchedules()
        game.post("\(setup.name) 창단! \(LeagueTier.citizenAmateur.displayName) 리그에서 첫 시즌을 시작합니다.")
        return game
    }

    init(funds: FundsLedger, rng: SeededRNG, chargeAnchor: Date) {
        self.funds = funds
        self.rng = rng
        self.chargeAnchor = chargeAnchor
    }

    /// 시작 로스터 (야구 14명, 축구 16명): 동네 사회인 선수. 숨은 보석은 많아야 1명.
    mutating func fillUserStartRoster() {
        let tier = LeagueTier.citizenAmateur
        let positions = rosterPositions(tier)
        let gemIndex: Int? = rng.chance(0.5) ? rng.int(0...(positions.count - 1)) : nil
        for (index, position) in positions.enumerated() {
            var spec = PlayerFactory.Spec(position: position, tier: tier, season: season)
            spec.ability = 25...35
            if index == gemIndex {
                // 숨은 보석: 잠재력은 높지만 스카우트 눈에는 별 2개 정도로 낮게 보인다.
                spec.age = 19...22
                spec.potential = 55...65
                spec.scoutBias = -2
            }
            let player = makePlayer(spec)
            add(player.id, to: userTeamID)
        }
    }

    /// CPU 구단 초기 설정: 리그 강도 범위 안에서 강팀·중위권·약팀을 고르게 만든다.
    mutating func setUpCPUTeam(_ id: TeamID, slot: Int) {
        let tier = teams[id].tier
        let offsets: [Double] = [8, 6, 4, 2, 0, -1, -3, -5, -7, -8]
        teams[id].targetOffset = offsets[slot % offsets.count]
        teams[id].style = rng.pick(TeamStyle.allCases)
        teams[id].colorIndex = rng.int(0...7)
        teams[id].emblemIndex = rng.int(0...5)
        let level = [8, 6, 5, 4, 2, 1][tier.index]
        teams[id].trainingLevel = max(1, level + rng.int(-1...1))
        teams[id].stadiumLevel = max(1, level + rng.int(-1...1))
        teams[id].fame = Balance.requiredFame(from: tier == .pro ? .semiPro : tier) * rng.double(0.6...1.4)
        teams[id].funds = Balance.cpuIncomePerMatch(tier) * 5
        fillCPURoster(id, target: mid(Balance.strengthRange(tier)) + teams[id].targetOffset)
        // 무작위로 만들다 보면 강도가 리그 범위를 살짝 벗어날 수 있어 한 번 맞춘다.
        normalizeCPURoster(id, leagueTarget: nil)
    }

    func mid(_ range: ClosedRange<Double>) -> Double { (range.lowerBound + range.upperBound) / 2 }

    /// 목표 강도에 맞는 선수로 로스터의 빈자리를 채운다.
    mutating func fillCPURoster(_ id: TeamID, target: Double) {
        let tier = teams[id].tier
        var needed = rosterPositions(tier)
        for player in roster(of: id) {
            if let index = needed.firstIndex(of: player.position) { needed.remove(at: index) }
        }
        let range = Balance.abilityRange(tier)
        for position in needed where teams[id].roster.count < rosterLimit(tier) {
            var spec = PlayerFactory.Spec(position: position, tier: tier, season: season)
            let center = clamp(target + rng.gaussian() * 4, range.lowerBound, range.upperBound)
            spec.ability = center...center
            switch teams[id].style {
            case .youth: spec.age = 18...27
            case .veteran: spec.age = 26...(Balance.ageRange(tier).upperBound)
            default: break
            }
            let player = makePlayer(spec)
            add(player.id, to: id)
        }
    }

    /// 새 시즌 일정과 순위표.
    mutating func startSeasonSchedules() {
        schedules = []
        standings = []
        leagueStartAverage = []
        for tier in LeagueTier.allCases {
            let ids = teams(in: tier).map(\.id)
            schedules.append(ScheduleBuilder.build(teams: ids, &rng))
            standings.append(ids.map { StandingRow(teamID: $0) })
            leagueStartAverage.append(cpuAverageStrength(tier))
        }
    }

    func cpuAverageStrength(_ tier: LeagueTier) -> Double {
        let cpu = teams(in: tier).filter { !$0.isUser }
        guard !cpu.isEmpty else { return 0 }
        return cpu.reduce(0) { $0 + strength(of: $1.id) } / Double(cpu.count)
    }
}
