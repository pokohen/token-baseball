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

    // MARK: 경기 평점

    public struct CareerPerformance: Equatable, Sendable {
        public var rating: Double
        public var line: String
    }

    /// 이 경기에서 내 선수가 한 일과 평점 (1.0~10.0, 6.0이 "무난했다"). 나오지 않았으면 nil.
    /// `result`: 팀이 이겼으면 1, 졌으면 −1, 비겼으면 0.
    static func careerPerformance(playerID: PlayerID, in side: MatchTeam, result: Int) -> CareerPerformance? {
        let teamShift = Double(result) * 0.2
        if let batter = side.batters.first(where: { $0.playerID == playerID }) {
            let line = batter.line
            guard line.plateAppearances > 0 else { return nil }
            let singles = line.hits - line.doubles - line.triples - line.homeRuns
            let quietOuts = max(0, line.atBats - line.hits - line.strikeouts)
            var rating = 6.0
            rating += Double(singles) * 0.55 + Double(line.doubles) * 0.8
            rating += Double(line.triples) * 1.0 + Double(line.homeRuns) * 1.4
            rating += Double(line.runsBattedIn) * 0.3 + Double(line.runs) * 0.2
            rating += Double(line.walks) * 0.25 + Double(line.steals) * 0.3
            rating -= Double(line.strikeouts) * 0.2 + Double(quietOuts) * 0.15
            var text = "\(line.atBats)타수 \(line.hits)안타"
            if line.homeRuns > 0 { text += " \(line.homeRuns)홈런" }
            if line.runsBattedIn > 0 { text += " \(line.runsBattedIn)타점" }
            if line.walks > 0 { text += " \(line.walks)볼넷" }
            if line.steals > 0 { text += " \(line.steals)도루" }
            return CareerPerformance(rating: clamp(rating + teamShift, 1, 10), line: text)
        }
        if let index = side.pitchers.firstIndex(where: { $0.playerID == playerID && $0.hasEntered }) {
            let line = side.pitchers[index].line
            let unearned = max(0, line.runs - line.earnedRuns)
            var rating = 6.0
            if index == 0 {
                // 선발은 점수를 주는 것이 보통이라 기준을 조금 높게 잡는다.
                rating += 0.3
                rating += Double(line.outs) * 0.12 - Double(line.earnedRuns) * 0.45 - Double(unearned) * 0.2
                rating += Double(line.strikeouts) * 0.08 - Double(line.walks) * 0.12
                rating -= Double(line.hits) * 0.06 + Double(line.homeRuns) * 0.2
                rating += Double(line.wins) * 0.5
            } else {
                rating += Double(line.outs) * 0.25 - Double(line.earnedRuns) * 0.9 - Double(unearned) * 0.3
                rating += Double(line.strikeouts) * 0.1 - Double(line.walks) * 0.15 - Double(line.hits) * 0.1
                rating += Double(line.saves) * 1.0 + Double(line.wins) * 0.3
            }
            var text = "\(line.innings)이닝 \(line.runs)실점 \(line.strikeouts)탈삼진"
            if line.wins > 0 { text += " 승리" }
            if line.losses > 0 { text += " 패전" }
            if line.saves > 0 { text += " 세이브" }
            return CareerPerformance(rating: clamp(rating + teamShift, 1, 10), line: text)
        }
        return nil
    }

    /// 평점에 따른 감독 신뢰 변화: 7.0 이상이면 오르고 6.0 아래면 내린다.
    static func careerTrustChange(rating: Double) -> Double {
        if rating >= 7 { return min(6, 1 + (rating - 7) * 3) }
        if rating < 6 { return max(-6, -1 - (6 - rating) * 3) }
        return 0
    }

    /// 진행 중인 경기에서 지금까지의 내 선수 평점.
    public var careerLivePerformance: CareerPerformance? {
        guard let career, let live else { return nil }
        let mine = live.userIsHome ? live.state.home : live.state.away
        return Self.careerPerformance(playerID: career.playerID, in: mine, result: 0)
    }

    /// 내 경기 정산: 평점, 감독 신뢰, 명성, 연봉. 훈련 횟수도 다시 채운다.
    mutating func settleCareerMatch(kind: MatchKind, state: MatchState, userIsHome: Bool) -> [String] {
        guard var career, !career.retired, let me = players[career.playerID] else { return [] }
        let mine = userIsHome ? state.home : state.away
        let theirs = userIsHome ? state.away : state.home
        let result = mine.runs > theirs.runs ? 1 : mine.runs < theirs.runs ? -1 : 0
        var lines: [String] = []

        career.sessionsLeft = Balance.careerSessionsPerMatch
        career.matchesAtClub += 1
        let performance = Self.careerPerformance(playerID: me.id, in: mine, result: result)
        career.lastRating = performance?.rating
        career.lastLine = performance?.line
        if let performance {
            lines.append("\(me.name) 평점 \(String(format: "%.1f", performance.rating)) · \(performance.line)")
            // 친선 경기는 절반만 반영한다.
            let weight = kind == .friendly ? 0.5 : 1.0
            let before = career.trust
            career.trust = clamp(career.trust + Self.careerTrustChange(rating: performance.rating) * weight, 0, 100)
            let moved = Int((career.trust - before).rounded())
            if moved != 0 { lines.append("감독 신뢰 \(moved > 0 ? "+" : "")\(moved)") }
            if kind != .friendly {
                let cap = Balance.careerFameCap(teams[userTeamID].tier)
                // 선발 투수는 나오는 경기가 적어서 한 경기가 더 크게 반영된다.
                let rarity = me.position == .starter ? 3.0 : 1.0
                if career.fame < cap {
                    career.fame += max(0, performance.rating - 6.5) * 0.8 * rarity * (cap - career.fame) / cap
                }
            }
            if kind == .regular {
                career.seasonRatedGames += 1
                career.seasonRatingTotal += performance.rating
            }
        } else {
            lines.append(me.position == .starter
                ? "\(me.name): 등판하지 않는 날입니다." : "\(me.name): 출전하지 않았습니다.")
        }
        if kind == .regular {
            let pay = me.contract.salary / Balance.roundsPerSeason
            career.earnings += pay
            lines.append("연봉 ₩\(pay.formatted())")
        }
        career.peakAbility = max(career.peakAbility, me.ability)
        self.career = career
        return lines
    }

    // MARK: 훈련

    /// 훈련으로 올릴 수 있는 능력치 (내 포지션의 능력에 들어가는 것만).
    public var careerTrainableKeys: [Attributes.Key] {
        guard let me = myPlayer else { return [] }
        return Attributes.weights(for: me.position).map(\.0)
    }

    /// 능력치 하나를 +1 올리는 데 드는 훈련 포인트. 지금 값이 높을수록, 한계에 가까울수록 비싸다.
    public func careerTrainingCost(_ key: Attributes.Key) -> Int {
        guard let me = myPlayer else { return 0 }
        var cost = Balance.careerTrainingCost(value: me.attributes[key])
        if me.potential - me.ability <= Balance.careerNearPotentialRoom { cost *= 2 }
        return price(cost)
    }

    /// 지금 이 훈련을 할 수 없는 이유. 할 수 있으면 nil.
    public func careerTrainingBlockedReason(_ key: Attributes.Key) -> String? {
        guard let career, !career.retired, let me = players[career.playerID] else { return "선수가 없습니다." }
        guard let weight = Attributes.weights(for: me.position).first(where: { $0.0 == key })?.1 else {
            return "이 포지션에서는 올릴 수 없는 능력치입니다."
        }
        if me.age >= Balance.careerTrainingAgeLimit {
            return "\(Balance.careerTrainingAgeLimit)세부터는 훈련으로 능력치를 올릴 수 없습니다."
        }
        if career.sessionsLeft <= 0 { return "다음 경기를 치르면 다시 훈련할 수 있습니다." }
        if me.attributes[key] >= 99 { return "이미 최고치입니다." }
        if me.ability + weight > me.potential + 0.0001 { return "한계에 닿았습니다. 지금은 더 오르지 않습니다." }
        let cost = careerTrainingCost(key)
        if funds.balance < cost { return "훈련 포인트가 모자랍니다. \(Format.tokens(cost)) P가 필요합니다." }
        return nil
    }

    /// 훈련 포인트(토큰)를 써서 능력치 하나를 +1 올린다. 경기와 경기 사이에 세 번까지 할 수 있다.
    public mutating func trainCareer(_ key: Attributes.Key) throws {
        if let reason = careerTrainingBlockedReason(key) { throw GameError(reason) }
        guard var career, var me = players[career.playerID] else { return }
        funds.spend(careerTrainingCost(key), .training)
        me.attributes[key] = min(99, me.attributes[key] + 1)
        players[me.id] = me
        career.sessionsLeft -= 1
        career.trainingCount += 1
        // 꾸준히 훈련하면 감독도 조금씩 알아준다.
        career.trust = min(100, career.trust + 0.5)
        career.peakAbility = max(career.peakAbility, me.ability)
        self.career = career
    }

    /// 한계 돌파 훈련에 드는 훈련 포인트.
    public var careerBreakthroughCost: Int { price(Balance.careerBreakthroughCost) }

    public var careerBreakthroughBlockedReason: String? {
        guard let career, !career.retired, let me = players[career.playerID] else { return "선수가 없습니다." }
        if me.age >= Balance.careerTrainingAgeLimit {
            return "\(Balance.careerTrainingAgeLimit)세부터는 한계를 넓힐 수 없습니다."
        }
        if career.sessionsLeft <= 0 { return "다음 경기를 치르면 다시 훈련할 수 있습니다." }
        if me.potential >= 99 { return "더 넓힐 한계가 없습니다." }
        if funds.balance < careerBreakthroughCost {
            return "훈련 포인트가 모자랍니다. \(Format.tokens(careerBreakthroughCost)) P가 필요합니다."
        }
        return nil
    }

    /// 한계 돌파 훈련: 큰 포인트를 들여 잠재력(능력의 한계)을 +1 넓힌다. 훈련 횟수를 한 번 쓴다.
    public mutating func breakThroughCareer() throws {
        if let reason = careerBreakthroughBlockedReason { throw GameError(reason) }
        guard var career, var me = players[career.playerID] else { return }
        funds.spend(careerBreakthroughCost, .training)
        me.potential = min(99, me.potential + 1)
        players[me.id] = me
        career.sessionsLeft -= 1
        career.trainingCount += 1
        self.career = career
    }

    // MARK: 계약 제안

    /// 그 구단에 갔을 때의 입지: 같은 포지션 선수들과 능력을 비교한다.
    public func careerRole(on team: TeamID) -> CareerRole {
        guard let me = myPlayer else { return .prospect }
        let peers = roster(of: team).filter { $0.position == me.position && $0.id != me.id }
            .map(\.ability).sorted(by: >)
        let slots: Int
        switch me.position {
        case .starter: slots = Balance.starterRest(teams[team].tier) + 1
        case .reliever: slots = max(1, peers.count)
        default: slots = 1
        }
        guard peers.count >= slots else { return .starter }
        let bar = peers[slots - 1]
        if me.ability >= bar { return .starter }
        return me.ability >= bar - 6 ? .rotation : .prospect
    }

    mutating func newCareerOfferID() -> Int {
        let id = career?.nextOfferID ?? 1
        career?.nextOfferID = id + 1
        return id
    }

    /// 경기가 끝날 때마다: 답하지 않은 제안은 사라지고, 이적 기간이면 새 제안이 올 수 있다.
    mutating func resolveCareerMarketAfterMatch() {
        guard var career, !career.retired, players[career.playerID] != nil else { return }
        var kept: [CareerOffer] = []
        for var offer in career.offers {
            guard offer.kind == .transfer else { kept.append(offer); continue }
            offer.matchesLeft -= 1
            if offer.matchesLeft > 0 {
                kept.append(offer)
            } else {
                post("\(teams[offer.teamID].name)의 이적 제안이 답이 없어 사라졌습니다.")
            }
        }
        career.offers = kept
        if !tradeWindowOpen { career.transferRequested = false }
        self.career = career

        guard !career.isFreeAgent, tradeWindowOpen else { return }
        // 마지막 친선 경기 뒤에는 곧바로 새 시즌이라 답할 틈이 없다.
        if phase == .offseason, friendliesPlayed >= Balance.friendliesPerOffseason { return }
        guard career.matchesAtClub >= Balance.careerOfferCooldown,
              career.offers.filter({ $0.kind == .transfer }).isEmpty
        else { return }
        let chance = (phase == .offseason ? 0.20 : 0.05) + career.fame / 400
            + (career.transferRequested ? 0.35 : 0)
        if rng.chance(min(0.9, chance)) { makeCareerTransferOffer() }
    }

    /// 같은 리그나 한 단계 위 리그에서, 내 능력이 통할 만한 구단이 제안한다.
    mutating func makeCareerTransferOffer() {
        guard let career, let me = players[career.playerID], let myTeam = me.teamID else { return }
        let myTier = teams[myTeam].tier
        let tiers = [myTier.upper, myTier].compactMap { $0 }
        let already = Set(career.offers.map(\.teamID))
        var options: [(team: TeamID, role: CareerRole)] = []
        for team in teams where team.id != myTeam && tiers.contains(team.tier) && !already.contains(team.id) {
            let role = careerRole(on: team.id)
            if role != .prospect {
                options.append((team.id, role))
            } else if team.tier < myTier, me.age <= 23, career.fame >= Balance.careerFameCap(myTier) * 0.8 {
                // 이름이 알려진 어린 선수는 윗 리그에서 유망주로 데려가려 한다.
                options.append((team.id, role))
            }
        }
        guard !options.isEmpty else { return }
        let upper = options.filter { teams[$0.team].tier < myTier }
        let pick = rng.pick(upper.isEmpty || rng.chance(0.3) ? options : upper)
        let bump = teams[pick.team].tier < myTier ? 1.3 : 1.1
        let base = max(me.contract.salary, Balance.marketSalary(ability: me.ability))
        let salary = Int(Double(base) * bump * rng.double(1.0...1.15) / 1_000) * 1_000
        let offer = CareerOffer(
            id: newCareerOfferID(), kind: .transfer, teamID: pick.team, salary: salary,
            years: rng.int(1...3), role: pick.role, matchesLeft: 1)
        self.career?.offers.append(offer)
        post("\(teams[pick.team].tier.displayName) \(teams[pick.team].name)에서 이적 제안이 왔습니다. 다음 경기가 끝나기 전에 답하세요.")
    }

    /// 무소속이 됐을 때 받는 입단 제안. 지금 능력에 맞는 리그의 구단 두세 곳이다.
    mutating func makeCareerTryoutOffers() -> [CareerOffer] {
        guard let me = myPlayer else { return [] }
        let lastTier = teams[userTeamID].tier
        // 리그 강도의 가운데가 내 능력과 가장 가까운 리그. 방출된 선수가 윗 리그로 올라가지는 않는다.
        var fit = LeagueTier.allCases.min {
            abs(mid(Balance.strengthRange($0)) - me.ability) < abs(mid(Balance.strengthRange($1)) - me.ability)
        } ?? lastTier
        if fit < lastTier { fit = lastTier }
        var offers: [CareerOffer] = []
        for (tier, count) in [(fit, 2), (fit.lower ?? fit, 1)] {
            let pool = rng.shuffled(teams(in: tier).filter { team in
                team.id != userTeamID && !offers.contains { $0.teamID == team.id }
            })
            for team in pool.prefix(count) {
                offers.append(CareerOffer(
                    id: newCareerOfferID(), kind: .tryout, teamID: team.id,
                    salary: Balance.marketSalary(ability: me.ability), years: rng.int(1...2),
                    role: careerRole(on: team.id), matchesLeft: 99))
            }
        }
        return offers
    }

    // MARK: 제안에 답하기

    public mutating func acceptCareerOffer(_ id: Int) throws {
        guard !isMatchLive else { throw GameError("경기가 끝난 뒤에 답할 수 있습니다.") }
        guard let career, !career.retired, let offer = career.offers.first(where: { $0.id == id }),
              let me = players[career.playerID]
        else { throw GameError("이미 사라진 제안입니다.") }

        players[me.id]?.contract = Contract(salary: offer.salary, seasonsLeft: offer.years)
        let club = teams[offer.teamID]
        if offer.kind == .renewal {
            post("\(club.name)과(와) \(offer.years)시즌 재계약했습니다. 연봉 ₩\(offer.salary.formatted()).")
        } else {
            joinCareerClub(offer.teamID)
            players[me.id]?.contract = Contract(salary: offer.salary, seasonsLeft: offer.years)
            self.career?.trust = Balance.careerStartTrust
            self.career?.isFreeAgent = false
            post("\(club.tier.displayName) \(club.name)(으)로 옮겼습니다. \(offer.years)시즌, 연봉 ₩\(offer.salary.formatted()). 예상 입지: \(offer.role.rawValue).")
        }
        self.career?.offers = []
        self.career?.transferRequested = false
    }

    public mutating func declineCareerOffer(_ id: Int) throws {
        guard let offer = career?.offers.first(where: { $0.id == id }) else { return }
        guard offer.kind != .tryout else { throw GameError("입단 제안 중 하나는 골라야 합니다.") }
        career?.offers.removeAll { $0.id == id }
        post("\(teams[offer.teamID].name)의 \(offer.kind == .renewal ? "재계약" : "이적") 제안을 거절했습니다.")
    }

    /// 연봉을 올려 달라고 한다. 제안마다 한 번만 할 수 있고, 이적 제안은 거절당하면 사라진다.
    public mutating func negotiateCareerOffer(_ id: Int) throws {
        guard let career, let index = career.offers.firstIndex(where: { $0.id == id }) else {
            throw GameError("이미 사라진 제안입니다.")
        }
        var offer = career.offers[index]
        guard !offer.negotiated else { throw GameError("이미 한 번 요구했습니다.") }
        offer.negotiated = true
        let name = teams[offer.teamID].name
        if rng.chance(min(0.9, 0.45 + career.fame / 200)) {
            offer.salary = Int(Double(offer.salary) * 1.15 / 1_000) * 1_000
            self.career?.offers[index] = offer
            post("\(name)이(가) 연봉을 ₩\(offer.salary.formatted())(으)로 올려 주었습니다.")
        } else if offer.kind == .transfer {
            self.career?.offers.remove(at: index)
            post("\(name)이(가) 연봉 인상을 거절하고 제안을 거두었습니다.")
        } else {
            self.career?.offers[index] = offer
            post("\(name)이(가) 연봉 인상을 거절했습니다. 처음 조건은 그대로입니다.")
        }
    }

    /// 이적 요청: 제안이 올 확률이 오르지만 감독 신뢰가 떨어진다. 이적 기간마다 한 번.
    public mutating func requestCareerTransfer() throws {
        guard let career, !career.retired, !career.isFreeAgent else { throw GameError("지금은 요청할 수 없습니다.") }
        guard tradeWindowOpen else { throw GameError("이적 기간이 아닙니다.") }
        guard !career.transferRequested else { throw GameError("이번 이적 기간에 이미 요청했습니다.") }
        self.career?.transferRequested = true
        self.career?.trust = max(0, career.trust - 10)
        post("구단에 이적을 요청했습니다. 감독 신뢰 −10.")
    }

    // MARK: 시즌 흐름

    /// 새 시즌(또는 커리어)을 시작할 때: 감독이 시즌 목표를 준다.
    mutating func careerStartSeason() {
        guard var career, !career.retired, let me = players[career.playerID] else { return }
        career.seasonClosed = false
        career.seasonRatedGames = 0
        career.seasonRatingTotal = 0
        career.sessionsLeft = Balance.careerSessionsPerMatch
        if me.teamID == nil {
            // 무소속 선수는 구단 로스터에 없어서 시즌 기록이 따로 비워지지 않는다.
            players[me.id]?.batting = BattingLine()
            players[me.id]?.pitching = PitchingLine()
            players[me.id]?.abilityAtSeasonStart = me.ability
            players[me.id]?.isHot = false
        }
        let tier = teams[userTeamID].tier
        switch me.position {
        case .starter:
            career.goal = CareerGoal(kind: .wins, target: tier.isCitizen ? 4 : 3)
        case .reliever, .closer:
            career.goal = CareerGoal(kind: .appearances, target: 18)
        default:
            let edge = Int(me.ability - mid(Balance.strengthRange(tier)))
            career.goal = CareerGoal(kind: .hits, target: 26 + clamp(edge, -6, 10))
        }
        self.career = career
        if let goal = career.goal, !career.isFreeAgent { post("시즌 목표: \(goal.label).") }
    }

    /// 정규시즌이 끝날 때: 시즌 기록을 커리어에 옮기고 목표를 채웠는지 본다.
    mutating func closeCareerSeason() {
        guard var career, !career.retired, !career.seasonClosed, let me = players[career.playerID] else { return }
        let won = awards.filter { $0.season == season && $0.isMine }
        career.history.append(CareerSeason(
            season: season, age: me.age, teamName: teams[userTeamID].name, tier: teams[userTeamID].tier,
            batting: me.batting, pitching: me.pitching,
            ratedGames: career.seasonRatedGames, ratingTotal: career.seasonRatingTotal,
            awards: won.map(\.title)))
        career.seasonClosed = true
        for award in won {
            career.awards.append("\(season)시즌 \(award.tier.displayName) \(award.title)")
            career.fame = min(100, career.fame + Balance.careerFameAward)
            post("\(award.tier.displayName) \(award.title) 수상! (\(award.detail)) 명성 +\(Int(Balance.careerFameAward)).")
        }
        if var goal = career.goal {
            let done = goal.progress(of: me) >= goal.target
            goal.achieved = done
            career.goal = goal
            if done {
                career.trust = min(100, career.trust + 10)
                career.fame = min(100, career.fame + 3)
                post("시즌 목표(\(goal.label))를 채웠습니다. 감독 신뢰 +10, 명성 +3.")
            } else {
                career.trust = max(0, career.trust - 5)
                post("시즌 목표(\(goal.label))를 채우지 못했습니다. 감독 신뢰 −5.")
            }
        }
        self.career = career
    }

    /// 내 구단이 승격하거나 강등됐다. 계약은 이어진다.
    mutating func careerClubMoved(from: LeagueTier, to: LeagueTier) {
        guard let career, !career.retired else { return }
        if to < from {
            if var me = players[career.playerID] {
                me.contract.salary = Int(Double(me.contract.salary) * 1.1)
                players[me.id] = me
            }
            if to < career.bestTier { self.career?.bestTier = to }
            post("\(teams[userTeamID].name) 승격! 다음 시즌은 \(to.displayName) 리그에서 뜁니다.")
        } else {
            post("\(teams[userTeamID].name) 강등. 다음 시즌은 \(to.displayName) 리그에서 뜁니다.")
        }
    }

    /// 오프시즌이 시작될 때 (나이를 먹고 계약 기간이 줄어든 뒤).
    mutating func careerStartOffseason() {
        guard var career, !career.retired, let me = players[career.playerID] else { return }
        career.transferRequested = false
        career.fame *= 1 - Balance.fameSeasonDecay
        self.career = career

        if me.age >= Balance.careerForcedRetirementAge {
            finishCareer()
            return
        }
        guard me.contract.seasonsLeft <= 0, let team = me.teamID else { return }
        if career.trust >= Balance.careerRenewalTrust {
            let offer = CareerOffer(
                id: newCareerOfferID(), kind: .renewal, teamID: team,
                salary: Int(Double(me.contract.salary) * 1.05 / 1_000) * 1_000,
                years: me.age <= 30 ? rng.int(1...3) : 1, role: careerRole(on: team), matchesLeft: 99)
            self.career?.offers.append(offer)
            post("계약이 끝났습니다. \(teams[team].name)이(가) 재계약을 제안했습니다. 오프시즌이 끝나기 전에 답하세요.")
        } else {
            post("계약이 끝났습니다. \(teams[team].name)은(는) 재계약을 제안하지 않았습니다. 오프시즌 동안 다른 구단의 제안을 기다립니다.")
        }
    }

    /// 오프시즌이 끝날 때: 이적 기간이 닫히고, 계약이 없으면 무소속이 된다.
    mutating func careerEndOffseason() {
        guard let career, !career.retired, let me = players[career.playerID] else { return }
        self.career?.offers = []
        self.career?.transferRequested = false
        guard me.contract.seasonsLeft <= 0 else { return }
        if let old = me.teamID {
            clearCareerLineup(old)
            teams[old].roster.removeAll { $0 == me.id }
            players[me.id]?.teamID = nil
        }
        self.career?.isFreeAgent = true
        let tryouts = makeCareerTryoutOffers()
        self.career?.offers = tryouts
        post("계약이 끝나 무소속이 되었습니다. 입단 제안 중 하나를 골라야 경기에 나설 수 있습니다.")
    }

    // MARK: 은퇴

    public var canRetireCareer: Bool {
        guard let career, !career.retired, let me = players[career.playerID] else { return false }
        return phase == .offseason && !isMatchLive && me.age >= Balance.careerVoluntaryRetirementAge
    }

    /// 스스로 은퇴한다. 30세부터, 오프시즌에만 할 수 있다.
    public mutating func retireCareer() throws {
        guard canRetireCareer else {
            throw GameError("\(Balance.careerVoluntaryRetirementAge)세부터, 오프시즌에만 은퇴할 수 있습니다.")
        }
        finishCareer()
    }

    /// 은퇴: 커리어 기록을 기록실에 남기고 선수를 세계에서 내린다.
    mutating func finishCareer() {
        guard var career, !career.retired, let me = players[career.playerID] else { return }
        var batting = BattingLine()
        var pitching = PitchingLine()
        var ratedGames = 0
        var ratingTotal = 0.0
        for season in career.history {
            batting += season.batting
            pitching += season.pitching
            ratedGames += season.ratedGames
            ratingTotal += season.ratingTotal
        }
        let record = CareerRecord(
            name: me.name, position: me.position, firstSeason: career.firstSeason, lastSeason: season,
            retiredAge: me.age, clubs: career.clubs, batting: batting, pitching: pitching,
            ratedGames: ratedGames, ratingTotal: ratingTotal, awards: career.awards,
            peakAbility: career.peakAbility, bestTier: career.bestTier, earnings: career.earnings)
        careerHall = (careerHall ?? []) + [record]
        if let team = me.teamID { clearCareerLineup(team) }
        removePlayer(me.id)
        career.retired = true
        career.isFreeAgent = false
        career.offers = []
        self.career = career
        post("\(me.name) 은퇴. \(career.history.count)시즌의 커리어가 기록실에 남습니다.")
    }

    /// 은퇴 뒤 같은 세계에서 새 선수로 다시 시작한다.
    public mutating func startNewCareer(setup: CareerSetup, now: Date) throws {
        guard career?.retired == true else { throw GameError("지금은 새 선수를 만들 수 없습니다.") }
        let name = setup.name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { throw GameError("선수 이름을 입력해 주세요.") }
        let ranked = rankedStandings(.citizenAmateur)
        let club = ranked[min(Balance.careerStartSlot, ranked.count - 1)].teamID
        var cleaned = setup
        cleaned.name = name
        createCareerPlayer(cleaned, team: club)
        funds = FundsLedger(startedAt: now)
        lastResult = nil
        charges = max(charges, 1)
        chargeAnchor = now
        careerStartSeason()
        post("\(name), \(teams[club].name)에 입단! \(LeagueTier.citizenAmateur.displayName) 리그에서 새 커리어를 시작합니다.")
    }

    /// 화면 확인용: 이적 제안을 하나 만든다.
    public mutating func generateDemoCareerOffer() {
        guard let career, let me = players[career.playerID], let myTeam = me.teamID,
              let team = teams.first(where: { $0.tier == teams[myTeam].tier.upper ?? .pro && $0.id != myTeam })
        else { return }
        let offer = CareerOffer(
            id: newCareerOfferID(), kind: .transfer, teamID: team.id,
            salary: Balance.marketSalary(ability: me.ability) * 2, years: 2, role: careerRole(on: team.id),
            matchesLeft: 1)
        self.career?.offers.append(offer)
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
