import Foundation

/// CPU 팀 맞춰주기 강도.
public enum RubberBand: String, Codable, CaseIterable, Sendable {
    case off = "끄기", weak = "약하게", normal = "보통", strong = "강하게"

    /// 성장 속도 보정 폭.
    var growthSwing: Double {
        switch self {
        case .off: 0
        case .weak: 0.10
        case .normal: 0.15
        case .strong: 0.25
        }
    }

    /// 시즌당 리그 평균 상승 한도.
    var seasonCap: Double {
        switch self {
        case .off: 0
        case .weak: 2
        case .normal: 3
        case .strong: 5
        }
    }

    /// 영입 보정을 하는지.
    var adjustsRecruiting: Bool { self == .normal || self == .strong }
}

/// 상단바에 보일 숫자.
public enum MenuBarDisplay: String, Codable, CaseIterable, Sendable {
    case funds = "구단 자금", today = "오늘 사용량", nextMatch = "다음 경기"
}

public struct Settings: Codable, Equatable, Sendable {
    public var rubberBand = RubberBand.normal
    /// 가격 난이도 (0.1 ~ 2.0). 비용에만 곱한다. 토큰 수는 건드리지 않는다.
    public var priceDifficulty = 1.0
    public var menuBarDisplay = MenuBarDisplay.funds
    public var animationEnabled = true
    public var notificationsEnabled = true

    public init() {}
}

public struct NewsItem: Codable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var season: Int
    public var text: String
}

public enum SeasonPhase: String, Codable, Sendable {
    case regular, playoff, offseason
}

/// 승강 플레이오프 한 시리즈 (3전 2선승, 상위 리그 팀 홈에서 1·3차전).
public struct PlayoffSeries: Codable, Equatable, Sendable {
    public var upperTier: LeagueTier
    public var upperTeam: TeamID
    public var lowerTeam: TeamID
    public var upperWins = 0
    public var lowerWins = 0

    public var gamesPlayed: Int { upperWins + lowerWins }
    public var isDecided: Bool { upperWins >= 2 || lowerWins >= 2 }
    /// 다음 경기의 홈 팀: 1·3차전은 상위 리그 팀.
    public var nextHome: TeamID { gamesPlayed == 1 ? lowerTeam : upperTeam }
    public var nextAway: TeamID { gamesPlayed == 1 ? upperTeam : lowerTeam }
}

/// 리그 이동 예정.
public struct TierMove: Codable, Equatable, Sendable {
    public var team: TeamID
    public var to: LeagueTier
}

public enum MatchKind: String, Codable, Sendable {
    case regular, playoff, friendly

    public var label: String {
        switch self {
        case .regular: "정규시즌"
        case .playoff: "승강 플레이오프"
        case .friendly: "친선 경기"
        }
    }
}

/// 진행 중인 내 경기와, 같은 라운드의 내 리그 다른 경기들.
public struct LiveMatch: Codable, Equatable, Sendable {
    public var kind: MatchKind
    public var state: MatchState
    public var others: [MatchState]
    public var userIsHome: Bool
    public var tier: LeagueTier
}

/// 끝난 내 경기 결과. 상단바의 "경기 종료" 표시에 쓴다.
public struct LastResult: Codable, Equatable, Sendable {
    public var kind: MatchKind
    public var myRuns: Int
    public var theirRuns: Int
    public var opponent: String
    public var wasHome: Bool
    /// 팝오버를 열어 확인했는지.
    public var acknowledged = false
    public var summary: [String]

    public var label: String {
        myRuns > theirRuns ? "승 \(myRuns):\(theirRuns)" : myRuns < theirRuns ? "패 \(myRuns):\(theirRuns)" : "무 \(myRuns):\(theirRuns)"
    }
}

public struct AwardRecord: Codable, Equatable, Sendable {
    public var season: Int
    public var tier: LeagueTier
    public var title: String
    public var playerName: String
    public var teamName: String
    public var detail: String
    public var isMine: Bool
}

/// 해체된 구단의 기록 (명예의 전당).
public struct HallEntry: Codable, Equatable, Sendable {
    public var name: String
    public var foundedSeason: Int
    public var endedSeason: Int
    public var bestTier: LeagueTier
    public var star: String?
}

public struct GameError: Error, Equatable, CustomStringConvertible, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

/// 게임 전체 상태. 이것 하나를 저장하면 그대로 이어서 할 수 있다.
public struct Game: Codable, Equatable, Sendable {
    public var settings = Settings()
    public var funds: FundsLedger

    // 세계
    var rng: SeededRNG
    public internal(set) var season = 1
    /// 이번 정규시즌에서 끝난 라운드 수 (0~36).
    public internal(set) var round = 0
    public internal(set) var phase = SeasonPhase.regular
    public internal(set) var friendliesPlayed = 0
    public internal(set) var players: [PlayerID: Player] = [:]
    var nextPlayerID = 1
    public internal(set) var teams: [Team] = []
    public internal(set) var userTeamID: TeamID = 0
    /// [리그][라운드][경기]
    public internal(set) var schedules: [[[Fixture]]] = []
    /// [리그] 순위표 줄 (정렬 전)
    public internal(set) var standings: [[StandingRow]] = []
    public internal(set) var freeAgents: [PlayerID] = []
    /// 시즌을 시작할 때의 리그별 CPU 팀 평균 강도 (맞춰주기 한도 계산용).
    var leagueStartAverage: [Double] = []
    public internal(set) var news: [NewsItem] = []
    var nextNewsID = 1

    // 경기
    public internal(set) var charges = 1
    public internal(set) var chargeAnchor: Date
    public internal(set) var live: LiveMatch?
    public internal(set) var lastResult: LastResult?
    /// 이번 틱에 뛴 선수의 출전 계수.
    var playedFactor: [PlayerID: Double] = [:]

    // 승강
    public internal(set) var appliedForPromotion = false
    public internal(set) var series: [PlayoffSeries] = []
    var pendingMoves: [TierMove] = []
    /// 지난 시즌 승률 (드래프트 순서용).
    var lastWinRate: [TeamID: Double] = [:]
    public internal(set) var awards: [AwardRecord] = []
    public internal(set) var bestTier = LeagueTier.citizenAmateur
    public internal(set) var relegatedThisOffseason = false

    // 구단
    public internal(set) var promotionUses: [String: Int] = [:]
    /// 재정 위기: 남은 유예 경기 수. 위기가 아니면 nil.
    public internal(set) var crisisMatchesLeft: Int?
    public internal(set) var isBankrupt = false
    /// 강등 뒤 스폰서 수입이 줄어드는 남은 시즌 수.
    public internal(set) var sponsorPenaltySeasons = 0
    public internal(set) var hallOfFame: [HallEntry] = []
    /// 유소년 야구 교실: 다음 입단 테스트에 후보가 더 온다.
    var youthBoost = 0

    // 이적 시장
    public internal(set) var offers: [TransferOffer] = []
    public internal(set) var proposals: [Proposal] = []
    public internal(set) var counters: [Proposal] = []
    public internal(set) var candidates: [Candidate] = []
    public internal(set) var scoutTrip: ScoutTrip?
    var nextMarketID = 1
    var draftDone = false
    var expiryNoticeSent = false

    // MARK: 읽기

    public var userTeam: Team { teams[userTeamID] }
    public var userTier: LeagueTier { teams[userTeamID].tier }

    public func teams(in tier: LeagueTier) -> [Team] {
        teams.filter { $0.tier == tier }
    }

    public func rankedStandings(_ tier: LeagueTier) -> [StandingRow] {
        Standings.ranked(standings[tier.index])
    }

    public func rank(of team: TeamID) -> Int {
        let rows = rankedStandings(teams[team].tier)
        return (rows.firstIndex { $0.teamID == team } ?? 0) + 1
    }

    public func roster(of team: TeamID) -> [Player] {
        teams[team].roster.compactMap { players[$0] }
    }

    public func strength(of team: TeamID) -> Double {
        LineupBuilder.strength(team: teams[team], players: players)
    }

    /// 가격 난이도를 곱한 비용.
    public func price(_ base: Int) -> Int {
        max(0, Int((Double(base) * settings.priceDifficulty).rounded()))
    }

    /// 경기마다 내는 연봉 합계.
    public var salaryPerMatch: Int {
        let season = roster(of: userTeamID).reduce(0) { $0 + $1.contract.salary }
        return price(season / Balance.roundsPerSeason)
    }

    /// 계약이 끝나 떠날 선수인지 (재계약하지 않으면).
    public func isExpiring(_ player: Player) -> Bool {
        phase == .offseason ? player.contract.seasonsLeft <= 0 : player.contract.seasonsLeft <= 1
    }

    public var tradeWindowOpen: Bool {
        phase == .offseason || (phase == .regular && round < Balance.tradeDeadlineRound)
    }

    // MARK: 소식

    mutating func post(_ text: String) {
        news.append(NewsItem(id: nextNewsID, season: season, text: text))
        nextNewsID += 1
        if news.count > 60 { news.removeFirst(news.count - 60) }
    }

    // MARK: 경기 기회

    /// 1시간마다 1개씩, 최대 3개까지 쌓인다.
    public mutating func refreshCharges(now: Date) {
        if charges >= Balance.maxMatchCharges {
            chargeAnchor = now
            return
        }
        while charges < Balance.maxMatchCharges,
              now.timeIntervalSince(chargeAnchor) >= Balance.matchChargeInterval {
            charges += 1
            chargeAnchor = chargeAnchor.addingTimeInterval(Balance.matchChargeInterval)
        }
        if charges >= Balance.maxMatchCharges { chargeAnchor = now }
        if chargeAnchor > now { chargeAnchor = now }
    }

    /// 다음 경기 기회까지 남은 시간. 이미 가득 찼으면 nil.
    public func timeToNextCharge(now: Date) -> TimeInterval? {
        guard charges < Balance.maxMatchCharges else { return nil }
        return max(0, Balance.matchChargeInterval - now.timeIntervalSince(chargeAnchor))
    }

    // MARK: 선수 만들기

    mutating func makePlayer(_ spec: PlayerFactory.Spec) -> Player {
        let player = PlayerFactory.make(id: nextPlayerID, spec: spec, &rng)
        nextPlayerID += 1
        players[player.id] = player
        return player
    }

    mutating func add(_ playerID: PlayerID, to team: TeamID) {
        guard var player = players[playerID] else { return }
        if let old = player.teamID { teams[old].roster.removeAll { $0 == playerID } }
        freeAgents.removeAll { $0 == playerID }
        player.teamID = team
        player.joinedSeason = season
        player.joinedTier = teams[team].tier.rawValue
        player.isFranchiseStar = false
        players[playerID] = player
        teams[team].roster.append(playerID)
    }

    mutating func moveToFreeAgency(_ playerID: PlayerID) {
        guard var player = players[playerID] else { return }
        if let old = player.teamID {
            teams[old].roster.removeAll { $0 == playerID }
            teams[old].lineupOverride.removeAll { $0 == playerID }
            if teams[old].starterOverride == playerID { teams[old].starterOverride = nil }
        }
        player.teamID = nil
        player.contract.seasonsLeft = 0
        players[playerID] = player
        if !freeAgents.contains(playerID) { freeAgents.append(playerID) }
    }

    mutating func removePlayer(_ playerID: PlayerID) {
        if let team = players[playerID]?.teamID {
            teams[team].roster.removeAll { $0 == playerID }
            teams[team].lineupOverride.removeAll { $0 == playerID }
            if teams[team].starterOverride == playerID { teams[team].starterOverride = nil }
        }
        freeAgents.removeAll { $0 == playerID }
        players[playerID] = nil
    }
}

// MARK: - 새 게임

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
    public static func newGame(setup: ClubSetup, now: Date, seed: UInt64) -> Game {
        var game = Game(funds: FundsLedger(startedAt: now), rng: SeededRNG(seed: seed), chargeAnchor: now)
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
                        ? NameGenerator.proTeams[slot]
                        : NameGenerator.cpuTeam(tier: tier, taken: taken, &game.rng)
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

    /// 시작 로스터 14명: 동네 사회인 야구 선수. 숨은 보석은 많아야 1명.
    mutating func fillUserStartRoster() {
        let tier = LeagueTier.citizenAmateur
        let positions = PlayerFactory.rosterPositions(tier)
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
        var needed = PlayerFactory.rosterPositions(tier)
        for player in roster(of: id) {
            if let index = needed.firstIndex(of: player.position) { needed.remove(at: index) }
        }
        let range = Balance.abilityRange(tier)
        for position in needed where teams[id].roster.count < Balance.rosterLimit(tier) {
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
