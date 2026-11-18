import Foundation

/// 선수 모드: 이적·재계약·입단 제안과 그에 대한 답.
extension Game {
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
        case .goalkeeper, .defender, .midfielder, .forward:
            slots = formation(of: team).slots.filter { $0 == me.position }.count
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
            } else if team.tier < myTier, me.age <= 23, career.fame >= Balance.careerFameCap(myTier) * 0.8,
                      me.ability >= Balance.abilityRange(team.tier).lowerBound - 8 {
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

        let club = teams[offer.teamID]
        if offer.kind == .renewal {
            players[me.id]?.contract = Contract(salary: offer.salary, seasonsLeft: offer.years)
            post("\(club.name)과(와) \(offer.years)시즌 재계약했습니다. 연봉 ₩\(offer.salary.formatted()).")
        } else {
            // 소속이 생긴 것으로 먼저 적어야, 구단에 들어갈 때 라이벌이 새 리그에 맞게 정해진다.
            let wasFreeAgent = career.isFreeAgent
            self.career?.isFreeAgent = false
            joinCareerClub(offer.teamID)
            players[me.id]?.contract = Contract(salary: offer.salary, seasonsLeft: offer.years)
            self.career?.trust = Balance.careerStartTrust
            // 무소속으로 시즌을 맞았으면 목표가 예전 구단 기준이다. 새 구단에 맞게 다시 받는다.
            if wasFreeAgent, phase == .regular { assignCareerGoal(announce: true) }
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
}
