import Foundation

/// 선수 모드: 구단을 운영하는 대신 야구 선수 한 명이 되어 커리어를 보낸다.
///
/// 세계는 구단 모드와 똑같이 돌아가고, 60개 구단이 모두 CPU 구단이다.
/// `userTeamID`는 "내 선수가 뛰는 구단"을 가리키고, 그 구단의 경기가 중계된다.
extension Game {
    public var isCareer: Bool { career != nil }

    /// 내 선수. 은퇴했으면 nil.
    public var myPlayer: Player? { career.flatMap { players[$0.playerID] } }

    func isMyPlayer(_ id: PlayerID) -> Bool { career?.playerID == id }

    /// 선수 모드에는 기준이 될 "내 구단"이 없으므로 맞춰주기를 끈다.
    var effectiveRubberBand: RubberBand { isCareer ? .off : settings.rubberBand }

    // MARK: 시작

    /// 새 선수 모드: 6개 리그 60팀을 모두 CPU 구단으로 만들고, 내 선수를 6부 구단에 입단시킨다.
    public static func newCareer(setup: CareerSetup, now: Date, seed: UInt64) -> Game {
        var game = Game(funds: FundsLedger(startedAt: now), rng: SeededRNG(seed: seed), chargeAnchor: now)
        var taken: Set<String> = []
        for tier in LeagueTier.allCases {
            for slot in 0..<Balance.teamsPerLeague {
                let id = game.teams.count
                let identity = tier == .pro
                    ? NameGenerator.proTeams(.baseball)[slot]
                    : NameGenerator.cpuTeam(tier: tier, taken: taken, sport: .baseball, &game.rng)
                taken.insert(identity.name)
                game.teams.append(Team(
                    id: id, name: identity.name, city: identity.city, tier: tier, isUser: false, season: 1))
                game.setUpCPUTeam(id, slot: slot)
            }
        }
        let club = game.teams(in: .citizenAmateur)[Balance.careerStartSlot].id
        game.userTeamID = club
        game.createCareerPlayer(setup, team: club)
        game.startSeasonSchedules()
        game.careerStartSeason()
        game.post("\(setup.name), \(game.teams[club].name)에 입단! \(LeagueTier.citizenAmateur.displayName) 리그에서 커리어를 시작합니다.")
        return game
    }

    /// 내 선수를 만들어 구단에 넣는다. 능력은 같은 포지션에서 가장 약한 선수 바로 아래다.
    mutating func createCareerPlayer(_ setup: CareerSetup, team: TeamID) {
        let tier = teams[team].tier
        let range = Balance.abilityRange(tier)
        let squad = roster(of: team)
        let reference = squad.filter { $0.position == setup.position }.map(\.ability).min()
            ?? squad.filter { $0.isPitcher == setup.position.isPitcher }.map(\.ability).min()
            ?? range.lowerBound
        let ability = clamp(reference - 2, range.lowerBound, range.upperBound)

        var spec = PlayerFactory.Spec(position: setup.position, tier: tier, season: season)
        spec.ability = ability...ability
        spec.age = Balance.careerStartAge...Balance.careerStartAge
        spec.potential = Balance.careerPotential
        spec.scoutBias = 0
        var player = makePlayer(spec)
        player.name = setup.name
        player.bats = setup.bats
        player.throwsHand = setup.throwsHand
        player.origin = "\(setup.hometown) 출신 유망주"
        player.traits = []
        player.contract = Contract(salary: Balance.marketSalary(ability: player.ability), seasonsLeft: 2)
        players[player.id] = player

        career = Career(playerID: player.id, season: season)
        career?.peakAbility = player.ability
        joinCareerClub(team)
    }

    /// 내 선수가 구단에 들어간다. 같은 포지션에서 가장 약한 선수의 자리를 넘겨받아 로스터 구성이 그대로 유지된다.
    mutating func joinCareerClub(_ team: TeamID) {
        guard let career, let me = players[career.playerID] else { return }
        if let old = me.teamID { clearCareerLineup(old) }
        let peers = roster(of: team).filter { $0.position == me.position && $0.id != me.id }
        if let weakest = peers.min(by: { ($0.ability, $0.id) < ($1.ability, $1.id) }) {
            moveToFreeAgency(weakest.id)
        }
        add(me.id, to: team)
        // 등판 간격은 구단마다 따로 세는 경기 수로 잰다. 옮긴 구단에서는 바로 나올 수 있게 한다.
        players[me.id]?.lastStartGame = -99
        userTeamID = team
        if self.career?.clubs.last != teams[team].name { self.career?.clubs.append(teams[team].name) }
        self.career?.matchesAtClub = 0
        if teams[team].tier < career.bestTier { self.career?.bestTier = teams[team].tier }
    }

    /// 내 선수 때문에 정해 둔 출전 지시를 지운다.
    mutating func clearCareerLineup(_ team: TeamID) {
        guard let career else { return }
        teams[team].lineupOverride = []
        teams[team].firstReliever = nil
        if teams[team].starterOverride == career.playerID { teams[team].starterOverride = nil }
        teams[team].policy = PitchingPolicy()
    }

    // MARK: 출전

    /// 감독이 내 선발 투수를 얼마나 오래 맡기는지. 신뢰가 높을수록 길게 던진다.
    static func careerPolicy(trust: Double) -> PitchingPolicy {
        var policy = PitchingPolicy()
        policy.starterPitchLimit = Int(70 + trust * 0.4)
        policy.starterRunLimit = trust >= 70 ? 6 : trust >= 35 ? 5 : 4
        return policy
    }

    /// 다음 경기에 내 선발 투수가 나오는 차례인지.
    public var careerStartsNextMatch: Bool {
        guard let me = myPlayer, me.position == .starter, let team = me.teamID else { return false }
        return teams[team].gamesPlayed - me.lastStartGame > Balance.starterRest(teams[team].tier)
    }

    /// 경기 전에 내 선수의 출전을 정한다.
    /// - 타자: 매 경기 선발로 나온다. 타순은 타격 순이고, 감독 신뢰가 높으면 앞으로 당겨진다.
    /// - 선발 투수: 쉬는 날을 채우면 반드시 선발로 나온다.
    /// - 불펜 투수: 선발이 내려가면 가장 먼저 올라온다.
    mutating func prepareCareerLineup() {
        guard let career, let me = players[career.playerID], me.teamID == userTeamID else { return }
        var team = teams[userTeamID]
        team.lineupOverride = []
        team.firstReliever = nil
        team.policy = PitchingPolicy()
        if team.starterOverride == me.id { team.starterOverride = nil }

        if me.position == .starter {
            if team.gamesPlayed - me.lastStartGame > Balance.starterRest(team.tier) {
                team.starterOverride = me.id
                team.policy = Self.careerPolicy(trust: career.trust)
            }
        } else if me.isPitcher {
            team.firstReliever = me.id
        } else if let lineup = LineupBuilder.build(team: team, players: players) {
            var ids = lineup.batters.map(\.id)
            if !ids.contains(me.id) {
                // 같은 포지션 선수의 자리에 들어가고, 없으면 타격이 가장 약한 선수 대신 나온다.
                let index = ids.lastIndex { players[$0]?.position == me.position } ?? ids.count - 1
                ids[index] = me.id
            }
            let shift = (career.trust - 50) * 0.3
            func value(_ id: PlayerID) -> Double {
                guard let player = players[id] else { return 0 }
                return LineupBuilder.battingValue(player) + (id == me.id ? shift : 0)
            }
            ids.sort { (value($0), -$0) > (value($1), -$1) }
            team.lineupOverride = ids
        }
        teams[userTeamID] = team
    }

    // MARK: 화면에 보일 기록

    /// 통산 기록: 끝난 시즌들에 진행 중인 시즌을 더한 값.
    public var careerTotals: (batting: BattingLine, pitching: PitchingLine, ratedGames: Int, ratingTotal: Double) {
        var batting = BattingLine()
        var pitching = PitchingLine()
        var games = 0
        var total = 0.0
        guard let career else { return (batting, pitching, games, total) }
        for season in career.history {
            batting += season.batting
            pitching += season.pitching
            games += season.ratedGames
            total += season.ratingTotal
        }
        if !career.seasonClosed, let me = players[career.playerID] {
            batting += me.batting
            pitching += me.pitching
            games += career.seasonRatedGames
            total += career.seasonRatingTotal
        }
        return (batting, pitching, games, total)
    }
}
