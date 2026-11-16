import Foundation

/// 게임 전체 상태. 이것 하나를 저장하면 그대로 이어서 할 수 있다.
public struct Game: Codable, Equatable, Sendable {
    public var settings = Settings()
    public var funds: FundsLedger
    /// 종목. 종목을 나누기 전의 저장 파일에는 없고, 없으면 야구다.
    public internal(set) var sportChoice: Sport?

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
    /// 진행 중인 축구 경기. 야구는 `live`를 쓴다.
    public internal(set) var liveFootball: LiveFootballMatch?
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

    // 선수 모드. 구단 모드와 예전 저장 파일에는 없다.
    public internal(set) var career: Career?
    /// 은퇴한 내 선수들의 기록실.
    public internal(set) var careerHall: [CareerRecord]?

    // MARK: 읽기

    public var sport: Sport { sportChoice ?? .baseball }
    /// 내 경기가 진행 중인지 (종목과 상관없이).
    public var isMatchLive: Bool { live != nil || liveFootball != nil }

    public func rosterLimit(_ tier: LeagueTier) -> Int { Balance.rosterLimit(tier, sport: sport) }
    func rosterPositions(_ tier: LeagueTier) -> [Position] { PlayerFactory.rosterPositions(tier, sport: sport) }

    /// 이 구단이 지금 경기를 치를 수 있는 구성인지.
    public func canField(_ team: Team) -> Bool {
        sport == .football
            ? FootballLineupBuilder.build(team: team, players: players) != nil
            : LineupBuilder.build(team: team, players: players) != nil
    }

    public var userTeam: Team { teams[userTeamID] }
    public var userTier: LeagueTier { teams[userTeamID].tier }

    public func teams(in tier: LeagueTier) -> [Team] {
        teams.filter { $0.tier == tier }
    }

    public func rankedStandings(_ tier: LeagueTier) -> [StandingRow] {
        Standings.ranked(standings[tier.index], sport: sport)
    }

    public func rank(of team: TeamID) -> Int {
        let rows = rankedStandings(teams[team].tier)
        return (rows.firstIndex { $0.teamID == team } ?? 0) + 1
    }

    public func roster(of team: TeamID) -> [Player] {
        teams[team].roster.compactMap { players[$0] }
    }

    public func strength(of team: TeamID) -> Double {
        sport == .football
            ? FootballLineupBuilder.strength(team: teams[team], players: players)
            : LineupBuilder.strength(team: teams[team], players: players)
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
        // 구단을 옮긴 선수는 적어도 이번 시즌은 뛴다. (계약이 끝난 채로 팔려 간 선수가
        // 시즌 중에 트레이드로 돌아왔다가 곧바로 떠나는 일이 없게 한다.)
        player.contract.seasonsLeft = max(1, player.contract.seasonsLeft)
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
