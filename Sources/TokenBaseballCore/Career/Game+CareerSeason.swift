import Foundation

/// 선수 모드: 시즌 목표, 시즌 기록, 승격·강등, 계약 만료, 은퇴.
extension Game {
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
            if me.position.sport == .football { players[me.id]?.football = FootballLine() }
            players[me.id]?.abilityAtSeasonStart = me.ability
            players[me.id]?.isHot = false
        }
        let tier = teams[userTeamID].tier
        switch me.position {
        case .starter:
            career.goal = CareerGoal(kind: .wins, target: tier.isCitizen ? 3 : 2)
        case .reliever, .closer:
            career.goal = CareerGoal(kind: .appearances, target: 18)
        case .forward:
            career.goal = CareerGoal(kind: .goals, target: 6 + clamp(Int(me.ability - mid(Balance.strengthRange(tier))) / 3, -3, 6))
        case .midfielder:
            career.goal = CareerGoal(kind: .points, target: 6 + clamp(Int(me.ability - mid(Balance.strengthRange(tier))) / 3, -3, 6))
        case .defender:
            career.goal = CareerGoal(kind: .matches, target: 24)
        case .goalkeeper:
            career.goal = CareerGoal(kind: .matches, target: 10)
        default:
            let edge = Int(me.ability - mid(Balance.strengthRange(tier)))
            career.goal = CareerGoal(kind: .hits, target: 26 + clamp(edge, -6, 10))
        }
        self.career = career
        if let goal = career.goal, !career.isFreeAgent { post("시즌 목표: \(goal.label).") }
        if let line = refreshCareerRival(seasonStart: true) { post(line) }
        ensureCup()
    }

    /// 정규시즌이 끝날 때: 시즌 기록을 커리어에 옮기고 목표를 채웠는지 본다.
    mutating func closeCareerSeason() {
        guard var career, !career.retired, !career.seasonClosed, let me = players[career.playerID] else { return }
        let won = awards.filter { $0.season == season && $0.isMine }
        career.history.append(CareerSeason(
            season: season, age: me.age, teamName: teams[userTeamID].name, tier: teams[userTeamID].tier,
            batting: me.batting, pitching: me.pitching, football: me.football,
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

        if me.age >= Balance.careerForcedRetirementAge(me.position) {
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

    /// 지금 은퇴할 수 없는 이유. 할 수 있으면 nil.
    /// 한 시즌을 끝까지 치른 뒤부터, 오프시즌에 할 수 있다 (나이는 상관없다).
    public var careerRetireBlockedReason: String? {
        guard let career, !career.retired, players[career.playerID] != nil else { return "선수가 없습니다." }
        if isMatchLive { return "경기가 끝난 뒤에 은퇴할 수 있습니다." }
        if career.history.count < Balance.careerRetireMinSeasons {
            return "한 시즌을 끝까지 치른 뒤부터 은퇴할 수 있습니다."
        }
        if phase != .offseason { return "은퇴는 시즌이 끝난 오프시즌에 할 수 있습니다." }
        return nil
    }

    public var canRetireCareer: Bool { careerRetireBlockedReason == nil }

    /// 스스로 은퇴한다.
    public mutating func retireCareer() throws {
        if let reason = careerRetireBlockedReason { throw GameError(reason) }
        finishCareer()
    }

    /// 은퇴: 커리어 기록을 명예의 전당에 남기고 선수를 세계에서 내린다.
    mutating func finishCareer() {
        guard var career, !career.retired, let me = players[career.playerID] else { return }
        var batting = BattingLine()
        var pitching = PitchingLine()
        var ratedGames = 0
        var ratingTotal = 0.0
        var football = FootballLine()
        for season in career.history {
            football += season.football ?? FootballLine()
            batting += season.batting
            pitching += season.pitching
            ratedGames += season.ratedGames
            ratingTotal += season.ratingTotal
        }
        let record = CareerRecord(
            name: me.name, position: me.position, firstSeason: career.firstSeason, lastSeason: season,
            retiredAge: me.age, clubs: career.clubs, batting: batting, pitching: pitching,
            football: me.position.sport == .football ? football : nil,
            ratedGames: ratedGames, ratingTotal: ratingTotal, awards: career.awards,
            peakAbility: career.peakAbility, bestTier: career.bestTier, earnings: career.earnings)
        careerHall = (careerHall ?? []) + [record]
        if let team = me.teamID { clearCareerLineup(team) }
        removePlayer(me.id)
        career.retired = true
        career.isFreeAgent = false
        career.offers = []
        self.career = career
        post("\(me.name) 은퇴. \(career.history.count)시즌의 커리어가 명예의 전당에 남습니다.")
    }

    /// 은퇴 뒤 같은 세계에서 새 선수로 다시 시작한다.
    public mutating func startNewCareer(setup: CareerSetup, now: Date) throws {
        guard career?.retired == true else { throw GameError("지금은 새 선수를 만들 수 없습니다.") }
        let name = setup.name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { throw GameError("선수 이름을 입력해 주세요.") }
        guard setup.sport == sport else { throw GameError("이 세계에서는 \(sport.label) 선수만 만들 수 있습니다.") }
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
}
