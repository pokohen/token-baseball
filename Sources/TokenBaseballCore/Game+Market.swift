import Foundation

/// 다른 구단이 내 선수에게 보낸 오퍼. 다음 경기가 끝날 때까지 답하지 않으면 자동 거절된다.
public struct TransferOffer: Codable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var playerID: PlayerID
    public var fromTeam: TeamID
    public var fee: Int
    /// 트레이드면 상대가 내주는 선수.
    public var swapPlayerID: PlayerID?
    /// 금액을 올려 달라고 이미 한 번 했는지.
    public var raised = false
}

/// 내가 보낸 제안. 답은 다음 경기가 끝난 뒤에 온다.
public struct Proposal: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case freeAgent = "FA 영입", renewal = "재계약", transfer = "이적 제안"
    }

    public var id: Int
    public var kind: Kind
    public var playerID: PlayerID
    public var salary: Int
    public var years: Int
    /// 이적 제안일 때 상대 구단에 내는 이적료.
    public var fee: Int
}

/// 영입 후보 (입단 테스트, 스카우트, 드래프트).
public struct Candidate: Codable, Equatable, Identifiable, Sendable {
    public enum Source: String, Codable, Sendable {
        case tryout = "입단 테스트", scout = "스카우트", draft = "신인 드래프트"
    }

    public var id: Int
    public var playerID: PlayerID
    /// 계약금.
    public var fee: Int
    /// 몇 경기 뒤에 사라지는지.
    public var matchesLeft: Int
    public var source: Source
}

public enum ScoutRegion: String, Codable, CaseIterable, Sendable {
    case local = "연고지", national = "전국", overseas = "해외"

    var costFactor: Int {
        switch self {
        case .local: 2
        case .national: 5
        case .overseas: 15
        }
    }
}

public struct ScoutTrip: Codable, Equatable, Sendable {
    public var region: ScoutRegion
    public var matchesLeft: Int
    /// 보낼 때 낸 비용 (취소되면 돌려준다). 예전 저장 파일에는 없다.
    public var cost: Int?
}

public enum OfferResponse: Sendable {
    case accept, reject, askMore
}

extension Game {
    mutating func newMarketID() -> Int {
        nextMarketID += 1
        return nextMarketID
    }

    func value(of player: Player) -> Int {
        Balance.transferValue(ability: player.ability, potential: player.potential, age: player.age)
    }

    func checkRosterRoom() throws {
        guard userTeam.roster.count < rosterLimit(userTier) else {
            throw GameError("로스터가 가득 찼습니다 (\(rosterLimit(userTier))명). 선수를 내보내야 영입할 수 있습니다.")
        }
    }

    func checkForeignLimit(_ player: Player) throws {
        guard player.isForeign else { return }
        guard userTier <= .semiPro else { throw GameError("외국인 선수는 1~2부에서만 영입할 수 있습니다.") }
        let count = roster(of: userTeamID).filter(\.isForeign).count
        guard count < Balance.foreignPlayerLimit else {
            throw GameError("외국인 선수는 팀당 \(Balance.foreignPlayerLimit)명까지입니다.")
        }
    }

    // MARK: 입단 테스트

    public var tryoutFee: Int { price(Balance.tryoutFee(userTier)) }

    /// 돈을 내고 테스트를 열면 지역 선수 후보 3~5명이 온다.
    public mutating func holdTryout() throws {
        guard !candidates.contains(where: { $0.source == .tryout }) else {
            throw GameError("지난 테스트 후보가 아직 남아 있습니다.")
        }
        let cost = tryoutFee
        try checkCanSpend(cost)
        funds.spend(cost, .recruit)

        let tier = userTier
        let range = Balance.abilityRange(tier)
        let count = rng.int(3...5) + (youthBoost > 0 ? 2 : 0)
        for _ in 0..<count {
            var spec = PlayerFactory.Spec(
                position: rng.pick(rosterPositions(tier)), tier: tier, season: season)
            // 싸고 능력치가 낮지만, 잠재력이 높은 선수가 가끔 섞여 있다.
            spec.ability = range.lowerBound...(range.lowerBound + (range.upperBound - range.lowerBound) * 0.6)
            if rng.chance(youthBoost > 0 ? 0.35 : 0.15) {
                spec.age = 18...22
                spec.potential = (range.upperBound - 5)...(range.upperBound + 15)
            }
            let player = makePlayer(spec)
            candidates.append(Candidate(
                id: newMarketID(), playerID: player.id, fee: 0, matchesLeft: 1, source: .tryout))
        }
        if youthBoost > 0 { youthBoost -= 1 }
        post("입단 테스트에 \(count)명이 왔습니다. 다음 경기가 끝나기 전에 계약하세요.")
    }

    // MARK: 스카우트

    public func scoutCost(_ region: ScoutRegion) -> Int {
        price(Balance.tryoutFee(userTier) * region.costFactor)
    }

    /// 지역을 정해 스카우트를 보낸다. 몇 경기 뒤 후보 목록이 온다.
    public mutating func sendScout(_ region: ScoutRegion) throws {
        guard userTeam.scoutLevel >= 1 else { throw GameError("스카우트 시설이 필요합니다.") }
        guard scoutTrip == nil else { throw GameError("스카우트가 이미 나가 있습니다.") }
        if region == .overseas, userTier > .semiPro {
            throw GameError("해외 스카우트는 1~2부에서만 보낼 수 있습니다.")
        }
        let cost = scoutCost(region)
        try checkCanSpend(cost)
        funds.spend(cost, .recruit)
        scoutTrip = ScoutTrip(region: region, matchesLeft: 3, cost: cost)
        post("\(region.rawValue) 스카우트를 보냈습니다. 3경기 뒤에 돌아옵니다.")
    }

    mutating func scoutReturns(_ trip: ScoutTrip) {
        let tier = userTier
        let range = Balance.abilityRange(tier)
        let level = userTeam.scoutLevel
        let count = 3 + level / 2
        let lift: Double = trip.region == .local ? 0 : trip.region == .national ? 4 : 8
        for _ in 0..<count {
            var spec = PlayerFactory.Spec(
                position: rng.pick(rosterPositions(tier)), tier: tier, season: season)
            let low = range.lowerBound + lift + Double(level)
            spec.ability = low...(range.upperBound + lift)
            spec.foreign = trip.region == .overseas
            if !spec.foreign, rng.chance(0.15 + 0.05 * Double(level)) {
                spec.age = 18...23
                spec.potential = (range.upperBound)...(range.upperBound + 18)
            }
            let player = makePlayer(spec)
            let fee = Balance.marketSalary(ability: player.ability) / 2
            candidates.append(Candidate(
                id: newMarketID(), playerID: player.id, fee: fee, matchesLeft: 2, source: .scout))
        }
        post("\(trip.region.rawValue) 스카우트가 후보 \(count)명을 데려왔습니다.")
    }

    /// 후보와 계약한다.
    public mutating func sign(candidate id: Int) throws {
        guard let candidate = candidates.first(where: { $0.id == id }),
              let player = players[candidate.playerID]
        else { throw GameError("후보를 찾을 수 없습니다.") }
        try checkRosterRoom()
        try checkForeignLimit(player)
        let fee = price(candidate.fee)
        try checkCanSpend(fee)
        funds.spend(fee, .recruit)
        add(player.id, to: userTeamID)
        candidates.removeAll { $0.id == id }
        if candidate.source == .draft {
            // 드래프트는 한 명만 지명한다.
            for other in candidates where other.source == .draft { removePlayer(other.playerID) }
            candidates.removeAll { $0.source == .draft }
        }
        post("\(player.name)(\(player.position.label))와(과) 계약했습니다.")
    }

    // MARK: 방출

    public mutating func release(_ id: PlayerID) throws {
        guard let player = players[id], player.teamID == userTeamID else {
            throw GameError("내 팀 선수가 아닙니다.")
        }
        guard !isMatchLive else { throw GameError("경기 중에는 방출할 수 없습니다.") }
        guard canSpare(id) else {
            throw GameError(sport == .football
                ? "골키퍼 1명을 포함해 \(Balance.footballStarters)명은 남아 있어야 합니다."
                : "야수 \(Balance.minBatters)명, 투수 \(Balance.minPitchers)명은 남아 있어야 합니다.")
        }
        moveToFreeAgency(id)
        offers.removeAll { $0.playerID == id }
        proposals.removeAll { $0.playerID == id }
        counters.removeAll { $0.playerID == id }
        // 오래 뛴 선수를 방출하면 인지도가 조금 떨어진다.
        if season - player.joinedSeason >= 3 {
            teams[userTeamID].fame = max(0, teams[userTeamID].fame - 5)
            post("\(player.name) 방출. 오래 뛴 선수를 내보내 인지도가 조금 떨어졌습니다.")
        } else {
            post("\(player.name) 방출.")
        }
    }

    // MARK: 재계약

    /// 선수가 재계약 조건으로 요구하는 연봉과 기간.
    public func renewalDemand(_ player: Player) -> (salary: Int, years: Int) {
        let market = Balance.marketSalary(ability: player.ability)
        let performance = player.position.sport == .football
            ? Self.footballPerformance(player)
            : player.isPitcher
            ? Double(player.pitching.wins + player.pitching.saves) / 20
            : max(0, player.batting.ops - 0.7) * 0.5
        let asked = max(Double(player.contract.salary) * 1.08, Double(market) * (1 + min(0.3, performance)))
        let years = player.age >= 32 ? 1 : player.age <= 25 ? 3 : 2
        return (Int(asked / 1_000) * 1_000, userTier.isCitizen ? min(years, 2) : years)
    }

    /// 재계약 제안. 계약 마지막 시즌 중 아무 때나, 그리고 오프시즌이 끝나기 전까지 할 수 있다.
    public mutating func proposeRenewal(_ id: PlayerID, salary: Int, years: Int) throws {
        guard let player = players[id], player.teamID == userTeamID else {
            throw GameError("내 팀 선수가 아닙니다.")
        }
        guard isExpiring(player) else { throw GameError("계약 마지막 시즌인 선수만 재계약할 수 있습니다.") }
        guard phase == .offseason || player.contract.seasonsLeft > 0 else {
            throw GameError("협상 기간이 끝났습니다. 선수의 역제안을 받아들일지만 정할 수 있습니다.")
        }
        guard (1...3).contains(years), salary > 0 else { throw GameError("조건이 올바르지 않습니다.") }
        guard !proposals.contains(where: { $0.playerID == id }) else {
            throw GameError("이미 제안을 보냈습니다. 다음 경기 뒤에 답이 옵니다.")
        }
        counters.removeAll { $0.playerID == id }
        proposals.append(Proposal(
            id: newMarketID(), kind: .renewal, playerID: id, salary: salary, years: years, fee: 0))
    }

    // MARK: FA와 이적 제안

    /// FA 시장에 나와 있는 선수 (오프시즌에만 열린다).
    public var freeAgentMarket: [Player] {
        guard phase == .offseason else { return [] }
        return freeAgents.compactMap { players[$0] }
            .sorted { ($0.ability, -$0.id) > ($1.ability, -$1.id) }
    }

    public mutating func proposeFreeAgent(_ id: PlayerID, salary: Int, years: Int) throws {
        guard phase == .offseason else { throw GameError("FA 영입은 오프시즌 이적 시장에서만 할 수 있습니다.") }
        guard let player = players[id], player.teamID == nil, freeAgents.contains(id) else {
            throw GameError("FA 선수가 아닙니다.")
        }
        guard (1...3).contains(years), salary > 0 else { throw GameError("조건이 올바르지 않습니다.") }
        guard !proposals.contains(where: { $0.playerID == id }) else {
            throw GameError("이미 제안을 보냈습니다. 다음 경기 뒤에 답이 옵니다.")
        }
        try checkForeignLimit(player)
        try checkCanSpend(0)
        proposals.append(Proposal(
            id: newMarketID(), kind: .freeAgent, playerID: id, salary: salary, years: years, fee: 0))
    }

    /// 다른 구단 선수에게 이적 제안을 넣는다.
    public mutating func proposeTransfer(_ id: PlayerID, fee: Int) throws {
        guard tradeWindowOpen else { throw GameError("지금은 이적 시장이 닫혀 있습니다.") }
        guard let player = players[id], let team = player.teamID, team != userTeamID else {
            throw GameError("다른 구단 선수가 아닙니다.")
        }
        guard fee > 0 else { throw GameError("이적료를 입력해 주세요.") }
        guard !proposals.contains(where: { $0.playerID == id }) else {
            throw GameError("이미 제안을 보냈습니다. 다음 경기 뒤에 답이 옵니다.")
        }
        try checkCanSpend(fee)
        proposals.append(Proposal(
            id: newMarketID(), kind: .transfer, playerID: id,
            salary: player.contract.salary, years: max(1, player.contract.seasonsLeft), fee: fee))
    }

    /// 선수가 내 팀에 올 마음이 있는지: 인지도, 리그, 제시 금액을 본다.
    func joinChance(_ player: Player, salary: Int) -> Double {
        let range = Balance.abilityRange(userTier)
        // 리그 수준을 한참 넘는 선수는 오지 않는다.
        if player.ability > range.upperBound + 5 { return 0 }
        let reference = max(100, Balance.requiredFame(from: userTier == .pro ? .semiPro : userTier))
        let fame = min(1, userTeam.fame / reference)
        let money = Double(salary) / Double(max(1, Balance.marketSalary(ability: player.ability))) - 1
        let reach = max(0, player.ability - mid(range)) * 0.01
        return clamp(0.35 + 0.4 * fame + 0.5 * money - reach, 0.03, 0.95)
    }

    /// 역제안을 받아들인다.
    public mutating func acceptCounter(_ id: Int) throws {
        guard let counter = counters.first(where: { $0.id == id }), let player = players[counter.playerID] else {
            throw GameError("제안을 찾을 수 없습니다.")
        }
        counters.removeAll { $0.id == id }
        players[player.id]?.contract = Contract(
            salary: counter.salary, seasonsLeft: counter.years + max(0, player.contract.seasonsLeft),
            relegationClause: player.contract.relegationClause)
        post("\(player.name)와(과) 재계약했습니다 (\(counter.years)시즌, 연봉 ₩\(counter.salary.formatted())).")
    }

    public mutating func declineCounter(_ id: Int) {
        counters.removeAll { $0.id == id }
    }

    public mutating func withdrawProposal(_ id: Int) {
        proposals.removeAll { $0.id == id }
    }

    // MARK: 들어온 오퍼에 답하기

    public mutating func respond(to offerID: Int, _ response: OfferResponse) throws {
        guard let index = offers.firstIndex(where: { $0.id == offerID }) else {
            throw GameError("오퍼를 찾을 수 없습니다.")
        }
        let offer = offers[index]
        guard let player = players[offer.playerID], player.teamID == userTeamID else {
            offers.remove(at: index)
            throw GameError("이미 팀을 떠난 선수입니다.")
        }
        let buyer = teams[offer.fromTeam]

        switch response {
        case .reject:
            offers.remove(at: index)
            post("\(buyer.name)의 \(player.name) 오퍼를 거절했습니다.")
        case .askMore:
            guard !offer.raised else { throw GameError("이미 한 번 올려 달라고 했습니다.") }
            if rng.chance(0.5) {
                offers[index].fee = Int(Double(offer.fee) * rng.double(1.15...1.3) / 1_000) * 1_000
                offers[index].raised = true
                post("\(buyer.name)이(가) \(player.name) 이적료를 ₩\(offers[index].fee.formatted())으로 올렸습니다.")
            } else {
                offers.remove(at: index)
                post("\(buyer.name)이(가) \(player.name) 오퍼를 거두었습니다.")
            }
        case .accept:
            guard !isMatchLive else { throw GameError("경기 중에는 선수를 보낼 수 없습니다.") }
            if offer.swapPlayerID == nil {
                // 선수를 팔고 나서도 경기를 치를 인원은 남아야 한다.
                guard canSpare(player.id) else { throw GameError("이 선수를 보내면 경기를 치를 인원이 모자랍니다.") }
            }
            offers.remove(at: index)
            add(player.id, to: buyer.id)
            teams[userTeamID].lineupOverride.removeAll { $0 == player.id }
            if offer.fee > 0 { funds.earn(offer.fee, .sales) }
            if let swapID = offer.swapPlayerID, players[swapID]?.teamID == buyer.id {
                add(swapID, to: userTeamID)
                post("트레이드 성사: \(player.name) ↔ \(players[swapID]?.name ?? "") (\(buyer.name))")
            } else {
                post("\(player.name)이(가) \(buyer.name)(으)로 이적했습니다. 이적료 ₩\(offer.fee.formatted()).")
            }
            offers.removeAll { $0.playerID == player.id }
            proposals.removeAll { $0.playerID == player.id }
            counters.removeAll { $0.playerID == player.id }
        }
    }

    // MARK: 경기가 끝날 때마다

    mutating func resolveMarketAfterMatch() {
        guard !isBankrupt else { return }

        // 지난 경기 뒤에 온 오퍼에 답하지 않았으면 자동 거절
        for offer in offers {
            if let player = players[offer.playerID] {
                post("\(teams[offer.fromTeam].name)의 \(player.name) 오퍼가 답이 없어 사라졌습니다.")
            }
        }
        offers = []

        // 오프시즌 끝에 역제안 때문에 기다려 준 선수: 새 시즌 첫 경기까지 답이 없으면 떠난다.
        if phase == .regular {
            let gone = roster(of: userTeamID).filter { $0.contract.seasonsLeft <= 0 }
            for player in gone {
                moveToFreeAgency(player.id)
                counters.removeAll { $0.playerID == player.id }
            }
            if !gone.isEmpty {
                post("재계약하지 못해 떠난 선수: \(gone.map(\.name).joined(separator: ", "))")
                fillUserMinimumRoster()
            }
        }

        // 후보 만료
        for index in candidates.indices { candidates[index].matchesLeft -= 1 }
        for candidate in candidates where candidate.matchesLeft <= 0 { removePlayer(candidate.playerID) }
        candidates.removeAll { $0.matchesLeft <= 0 }

        // 스카우트 복귀
        if var trip = scoutTrip {
            trip.matchesLeft -= 1
            if trip.matchesLeft <= 0 {
                scoutTrip = nil
                scoutReturns(trip)
            } else {
                scoutTrip = trip
            }
        }

        // 내가 보낸 제안에 답이 온다
        let pending = proposals
        proposals = []
        for proposal in pending { answer(proposal) }

        // 새 오퍼
        guard tradeWindowOpen else { return }
        if phase == .offseason {
            // 마지막 친선 경기 뒤에는 곧바로 새 시즌이라 답할 틈이 없다.
            guard friendliesPlayed < Balance.friendliesPerOffseason else { return }
            // 오프시즌에는 경기가 끝날 때마다 오퍼가 들어온다. 강등됐으면 몰려온다.
            let count = relegatedThisOffseason ? rng.int(2...3) : 1
            generateIncomingOffers(count: count)
        } else if rng.chance(0.12) {
            generateIncomingOffers(count: 1)
        }
    }

    mutating func answer(_ proposal: Proposal) {
        guard let player = players[proposal.playerID] else { return }
        switch proposal.kind {
        case .renewal:
            guard player.teamID == userTeamID else { return }
            let demand = renewalDemand(player)
            let starter = sport == .football
                ? (currentFootballLineup.map { lineup in lineup.starters.contains { $0.id == player.id } } ?? true)
                : currentLineup.map { lineup in
                    lineup.batters.contains { $0.id == player.id } || lineup.starter == player.id
                        || lineup.bullpen.contains(player.id)
                } ?? true
            var chance = proposal.salary >= demand.salary
                ? 0.9 : 0.55 + (Double(proposal.salary) / Double(demand.salary) - 1) * 1.5
            if relegatedThisOffseason { chance -= 0.3 }
            if !starter { chance -= 0.15 }
            if rng.chance(clamp(chance, 0.02, 0.95)) {
                players[player.id]?.contract = Contract(
                    salary: proposal.salary, seasonsLeft: proposal.years + max(0, player.contract.seasonsLeft),
                    relegationClause: player.contract.relegationClause)
                post("\(player.name)이(가) 재계약에 합의했습니다 (\(proposal.years)시즌, 연봉 ₩\(proposal.salary.formatted())).")
            } else if rng.chance(0.6) {
                counters.append(Proposal(
                    id: newMarketID(), kind: .renewal, playerID: player.id,
                    salary: demand.salary, years: demand.years, fee: 0))
                let raise = Int((Double(demand.salary) / Double(max(1, player.contract.salary)) - 1) * 100)
                post("\(player.name)이(가) 재계약 조건으로 연봉 \(raise)% 인상(₩\(demand.salary.formatted()))을 요구합니다.")
            } else {
                post("\(player.name)이(가) 재계약 제안을 거절했습니다.")
            }

        case .freeAgent:
            guard player.teamID == nil, freeAgents.contains(player.id) else {
                post("FA \(player.name)은(는) 이미 다른 팀과 계약했습니다.")
                return
            }
            let full = userTeam.roster.count >= rosterLimit(userTier)
            let foreignOK = (try? checkForeignLimit(player)) != nil
            if !full, foreignOK, crisisMatchesLeft == nil, rng.chance(joinChance(player, salary: proposal.salary)) {
                add(player.id, to: userTeamID)
                players[player.id]?.contract = Contract(salary: proposal.salary, seasonsLeft: proposal.years)
                post("FA \(player.name)이(가) 우리 제안을 받아들였습니다.")
            } else {
                post("FA \(player.name)이(가) 우리 제안을 거절했습니다.")
            }

        case .transfer:
            guard let seller = player.teamID, seller != userTeamID else { return }
            let asking = Double(value(of: player)) * rng.double(1.1...1.5)
            let full = userTeam.roster.count >= rosterLimit(userTier)
            let affordable = funds.balance >= proposal.fee && crisisMatchesLeft == nil
            let foreignOK = (try? checkForeignLimit(player)) != nil
            if !full, affordable, foreignOK, Double(proposal.fee) >= asking,
               rng.chance(joinChance(player, salary: player.contract.salary) + 0.2) {
                funds.spend(proposal.fee, .recruit)
                teams[seller].funds += proposal.fee
                add(player.id, to: userTeamID)
                post("\(teams[seller].name)이(가) \(player.name) 이적에 합의했습니다. 이적료 ₩\(proposal.fee.formatted()).")
            } else {
                post("\(teams[seller].name)이(가) \(player.name) 이적 제안을 거절했습니다.")
            }
        }
    }

    /// 다른 구단이 내 선수에게 오퍼를 보낸다. 활약이 좋거나 잠재력이 높은 선수일수록 오퍼가 많다.
    mutating func generateIncomingOffers(count: Int) {
        guard count > 0 else { return }
        for _ in 0..<count {
            let mine = roster(of: userTeamID).filter { player in !offers.contains { $0.playerID == player.id } }
            guard !mine.isEmpty else { return }
            let weights = mine.map { pow(max(1, $0.ability + ($0.potential - $0.ability) * 0.5), 2) }
            let player = mine[rng.weighted(weights)]

            // 같은 리그나 상위 리그 구단이 관심을 보인다.
            let buyers = teams.filter {
                !$0.isUser && $0.tier <= userTier && $0.tier.rawValue >= userTier.rawValue - 1
            }
            guard !buyers.isEmpty else { return }
            let buyer = rng.pick(buyers)
            let fee = Int(Double(value(of: player)) * rng.double(0.9...1.4) / 1_000) * 1_000

            // 시즌 중에는 선수 ↔ 선수 트레이드 제안도 온다.
            var swap: PlayerID?
            if phase == .regular, rng.chance(0.4) {
                swap = roster(of: buyer.id)
                    .filter {
                        (sport == .football ? $0.position == player.position : $0.isPitcher == player.isPitcher)
                            && abs($0.ability - player.ability) <= 6
                    }
                    .min { (abs($0.ability - player.ability), $0.id) < (abs($1.ability - player.ability), $1.id) }?.id
            }
            offers.append(TransferOffer(
                id: newMarketID(), playerID: player.id, fromTeam: buyer.id,
                fee: swap == nil ? max(fee, 1_000) : 0, swapPlayerID: swap))
            if let swap, let other = players[swap] {
                post("\(buyer.name)이(가) 트레이드를 제안했습니다: \(player.name) ↔ \(other.name)")
            } else {
                post("\(buyer.name)이(가) \(player.name)에게 ₩\(max(fee, 1_000).formatted()) 이적 오퍼를 보냈습니다.")
            }
        }
    }
}

extension Game {
    /// 이 선수의 이적료 시장가.
    public func value(for player: Player) -> Int { value(of: player) }
}

extension Game {
    /// 화면 확인용: 오퍼를 하나 만든다.
    public mutating func generateDemoOffer() {
        generateIncomingOffers(count: 1)
    }
}
