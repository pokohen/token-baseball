import Foundation

/// 시즌 흐름: 정규시즌 → 시상 → 승강 플레이오프 → 오프시즌 → 다음 시즌.
extension Game {
    // MARK: 정규시즌 끝

    mutating func endRegularSeason() {
        for tier in LeagueTier.allCases {
            for row in standings[tier.index] { lastWinRate[row.teamID] = row.winRate }
        }
        giveAwards()

        // 순위 상금
        let myRank = rank(of: userTeamID)
        let prize = isBankrupt ? 0 : Balance.prizeMoney(userTier, rank: myRank)
        if !isBankrupt {
            post("정규시즌 종료. \(userTeam.name)은(는) \(userTier.displayName) \(myRank)위로 마쳤습니다.")
        }
        if prize > 0 {
            funds.earn(prize, .prize)
            post("순위 상금 ₩\(prize.formatted())을 받았습니다.")
        }

        // 승강: 리그 경계마다 자동 승격·강등과 플레이오프를 정한다.
        series = []
        pendingMoves = []
        for upper in LeagueTier.allCases {
            guard let lower = upper.lower else { continue }
            let upperRanked = rankedStandings(upper).map(\.teamID)
            let eligible = rankedStandings(lower).map(\.teamID).filter { canPromote($0) }
            guard upperRanked.count >= 2 else { continue }
            let tenth = upperRanked[upperRanked.count - 1]
            let ninth = upperRanked[upperRanked.count - 2]

            if let champion = eligible.first {
                // 상위 리그 10위는 자동 강등, 하위 리그 1위 자리는 자동 승격
                pendingMoves.append(TierMove(team: tenth, to: lower))
                pendingMoves.append(TierMove(team: champion, to: upper))
            }
            if eligible.count >= 2 {
                series.append(PlayoffSeries(upperTier: upper, upperTeam: ninth, lowerTeam: eligible[1]))
            }
        }

        if !isBankrupt, !appliedForPromotion, myRank <= 2, userTier != .pro {
            post("승강 플레이오프를 신청하지 않아 승격 자격이 다음 순위 팀으로 넘어갔습니다.")
        }

        // 내 팀이 없는 시리즈는 바로 치른다.
        // (구단이 해체된 상태면 그 자리를 이어받은 CPU 구단의 시리즈도 바로 치른다.)
        for index in series.indices
        where isBankrupt || (series[index].upperTeam != userTeamID && series[index].lowerTeam != userTeamID) {
            while !series[index].isDecided {
                let home = series[index].nextHome
                let away = series[index].nextAway
                ensurePlayable(home)
                ensurePlayable(away)
                guard var game = makeMatch(
                    home: home, away: away, kind: .playoff, tier: series[index].upperTier, seed: rng.next())
                else { series[index].upperWins = 2; break }
                game.runToEnd()
                let winner = game.home.runs > game.away.runs ? home : away
                if winner == series[index].upperTeam { series[index].upperWins += 1 } else { series[index].lowerWins += 1 }
            }
        }

        if series.contains(where: { !$0.isDecided }) {
            phase = .playoff
            post("승강 플레이오프에 나갑니다. 3전 2선승입니다.")
        } else {
            finishPlayoffs()
        }
    }

    /// 승격 자격: CPU 팀은 항상 신청한 것으로 본다. 내 팀은 신청해야 한다.
    func canPromote(_ id: TeamID) -> Bool {
        teams[id].isUser ? appliedForPromotion : true
    }

    mutating func finishPlayoffs() {
        for entry in series {
            if entry.lowerWins > entry.upperWins, let lower = entry.upperTier.lower {
                pendingMoves.append(TierMove(team: entry.lowerTeam, to: entry.upperTier))
                pendingMoves.append(TierMove(team: entry.upperTeam, to: lower))
            }
        }
        series = []
        relegatedThisOffseason = false

        for move in pendingMoves {
            let from = teams[move.team].tier
            teams[move.team].tier = move.to
            guard teams[move.team].isUser else { continue }
            if move.to < from {
                userPromoted(to: move.to)
            } else {
                userRelegated(to: move.to)
            }
        }
        pendingMoves = []
        startOffseason()
    }

    mutating func userPromoted(to tier: LeagueTier) {
        let grant = Balance.promotionGrant(to: tier)
        let fame = Balance.famePromotion(to: tier)
        funds.earn(grant, .prize)
        teams[userTeamID].fame += fame
        if tier < bestTier { bestTier = tier }
        post("승격! 다음 시즌은 \(tier.displayName) 리그입니다. 승격 지원금 ₩\(grant.formatted()), 인지도 +\(Int(fame)).")

        // 승격하면 연봉이 리그에 맞춰 한 번 더 오른다.
        for id in teams[userTeamID].roster {
            guard var player = players[id] else { continue }
            player.contract.salary = Int(Double(player.contract.salary) * 1.1)
            players[id] = player
        }
        // 프랜차이즈 스타: 시민 구단 때부터 함께한 선수가 프로 리그까지 왔다.
        if tier == .pro {
            for id in teams[userTeamID].roster {
                guard var player = players[id], player.joinedTier >= 4, !player.isFranchiseStar else { continue }
                player.isFranchiseStar = true
                players[id] = player
                teams[userTeamID].fame += Balance.fameFranchiseStar
                post("\(player.name), 시민 구단 시절부터 함께해 프로까지 온 프랜차이즈 스타가 되었습니다. 인지도 +\(Int(Balance.fameFranchiseStar)).")
            }
        }
    }

    mutating func userRelegated(to tier: LeagueTier) {
        relegatedThisOffseason = true
        sponsorPenaltySeasons = 1
        teams[userTeamID].fame *= 1 - Balance.fameRelegationDrop
        post("강등되었습니다. 다음 시즌은 \(tier.displayName) 리그입니다. 인지도가 크게 떨어지고 스폰서 수입이 줄어듭니다.")

        // 강등 조항: 다른 구단이 정해진 이적료를 내고 데려간다. 거절할 수 없다.
        for player in roster(of: userTeamID) where player.contract.relegationClause && rng.chance(0.6) {
            let buyers = teams.filter { !$0.isUser && $0.tier < tier }
            guard !buyers.isEmpty else { continue }
            let buyer = rng.pick(buyers)
            let fee = Int(Double(Balance.transferValue(
                ability: player.ability, potential: player.potential, age: player.age)) * 0.8)
            add(player.id, to: buyer.id)
            funds.earn(fee, .sales)
            post("강등 조항 발동: \(player.name)이(가) \(buyer.name)(으)로 떠났습니다. 이적료 ₩\(fee.formatted()).")
        }
    }

    // MARK: 시상

    mutating func giveAwards() {
        awards.removeAll { $0.season < season - 1 }
        for tier in LeagueTier.allCases {
            let everyone = teams(in: tier).flatMap { roster(of: $0.id) }
            let batters = everyone.filter { !$0.isPitcher && $0.batting.plateAppearances >= 80 }
            let pitchers = everyone.filter { $0.isPitcher && $0.pitching.outs >= 90 }

            func record(_ title: String, _ player: Player?, _ detail: (Player) -> String) -> Player? {
                guard let player, let teamID = player.teamID else { return nil }
                awards.append(AwardRecord(
                    season: season, tier: tier, title: title, playerName: player.name,
                    teamName: teams[teamID].name, detail: detail(player), isMine: teamID == userTeamID))
                return player
            }

            let mvp = record("MVP", batters.max { ($0.batting.ops, $0.id) < ($1.batting.ops, $1.id) }) {
                "OPS \(String(format: "%.3f", $0.batting.ops))"
            }
            _ = record("타격왕", batters.max { ($0.batting.average, $0.id) < ($1.batting.average, $1.id) }) {
                "타율 \(String(format: "%.3f", $0.batting.average))"
            }
            _ = record("홈런왕", batters.max { ($0.batting.homeRuns, $0.id) < ($1.batting.homeRuns, $1.id) }) {
                "\($0.batting.homeRuns)홈런"
            }
            _ = record("다승왕", pitchers.max { ($0.pitching.wins, $0.id) < ($1.pitching.wins, $1.id) }) {
                "\($0.pitching.wins)승"
            }
            _ = record("평균자책점 1위", pitchers.min { ($0.pitching.era, $0.id) < ($1.pitching.era, $1.id) }) {
                "평균자책점 \(String(format: "%.2f", $0.pitching.era))"
            }
            _ = record("탈삼진왕", pitchers.max { ($0.pitching.strikeouts, $0.id) < ($1.pitching.strikeouts, $1.id) }) {
                "\($0.pitching.strikeouts)탈삼진"
            }

            // 각성: MVP는 잠재력이 조금 오른다.
            if let mvp, var player = players[mvp.id] {
                player.potential = min(99, player.potential + rng.double(3...8))
                players[player.id] = player
            }
        }
        let mine = awards.filter { $0.season == season && $0.isMine }
        for award in mine {
            teams[userTeamID].fame += Balance.fameAward
            post("\(award.tier.displayName) \(award.title): \(award.playerName) (\(award.detail)). 인지도 +\(Int(Balance.fameAward)).")
        }
    }

    // MARK: 오프시즌

    mutating func startOffseason() {
        phase = .offseason
        friendliesPlayed = 0
        draftDone = false
        offers = []
        proposals = []
        counters = []

        // 나이 +1, 하락, 은퇴
        var retired: [String] = []
        for team in teams {
            for id in team.roster {
                guard var player = players[id] else { continue }
                player.age += 1
                if player.age >= Balance.declineStartAge {
                    // 체력·주력부터 떨어진다.
                    for key in Attributes.Key.allCases {
                        let drop = key == .stamina || key == .speed ? rng.double(2.5...5) : rng.double(0.5...2)
                        player.attributes[key] = max(1, player.attributes[key] - drop)
                    }
                    player.potential = max(player.ability, player.potential - 2)
                }
                players[id] = player

                let start = Balance.retirementAge(team.tier)
                if player.age >= start, rng.chance(min(1, 0.12 * Double(player.age - start + 1))) {
                    if team.isUser { retired.append(player.name) }
                    removePlayer(id)
                }
            }
        }
        if !retired.isEmpty { post("은퇴: \(retired.joined(separator: ", "))") }

        // 연봉 인상 (내려가지 않는다)과 계약 기간 한 시즌 줄이기
        for team in teams {
            for id in team.roster {
                guard var player = players[id] else { continue }
                let improvement = max(0, player.ability - player.abilityAtSeasonStart)
                let performance = player.isPitcher
                    ? Double(player.pitching.wins + player.pitching.saves) / 15
                    : max(0, player.batting.ops - 0.7)
                let bonus = min(Balance.raiseMaxBonus, improvement * 0.02 + performance * 0.15)
                player.contract.salary = Int(Double(player.contract.salary) * (1 + rng.double(Balance.raiseBase) + bonus))
                player.contract.seasonsLeft -= 1
                players[id] = player
            }
        }

        // CPU 구단: 계약이 끝난 선수는 대부분 재계약하고, 나머지는 FA로 나온다.
        for team in teams where !team.isUser {
            for player in roster(of: team.id) where player.contract.seasonsLeft <= 0 {
                if rng.chance(0.75) {
                    players[player.id]?.contract.seasonsLeft = rng.int(1...3)
                } else {
                    moveToFreeAgency(player.id)
                }
            }
        }

        // FA 시장에 새 얼굴
        for tier in LeagueTier.allCases {
            for _ in 0..<6 {
                let positions = PlayerFactory.rosterPositions(tier)
                let player = makePlayer(PlayerFactory.Spec(position: rng.pick(positions), tier: tier, season: season))
                players[player.id]?.contract.seasonsLeft = 0
                freeAgents.append(player.id)
            }
        }

        // 인지도는 시즌이 바뀔 때 조금 줄고, 홍보 효과는 초기화된다.
        teams[userTeamID].fame *= 1 - Balance.fameSeasonDecay
        promotionUses = [:]

        // 맞춰주기: 강팀·약팀을 시즌마다 다시 정한다.
        for tier in LeagueTier.allCases {
            let offsets = rng.shuffled([8.0, 6, 4, 2, 0, -1, -3, -5, -7, -8])
            for (index, team) in teams(in: tier).filter({ !$0.isUser }).enumerated() {
                teams[team.id].targetOffset = offsets[index % offsets.count]
            }
        }

        let leaving = roster(of: userTeamID).filter { isExpiring($0) }.map(\.name)
        post("오프시즌 시작. 친선 경기 \(Balance.friendliesPerOffseason)경기 동안 이적 시장이 열립니다.")
        if !leaving.isEmpty {
            post("계약 만료: \(leaving.joined(separator: ", ")). 오프시즌이 끝나기 전에 재계약하지 않으면 떠납니다.")
        }
        if relegatedThisOffseason { generateIncomingOffers(count: 3) }
        // 은퇴나 강등 조항으로 인원이 모자라면 친선 경기를 치를 수 있게 채운다.
        fillUserMinimumRoster()
    }

    /// 신인 드래프트 (3부 이상): 지난 시즌 순위 역순으로 지명한다.
    mutating func runDraft() {
        draftDone = true
        for tier in [LeagueTier.pro, .semiPro, .amateur] {
            let range = Balance.abilityRange(tier)
            var pool: [PlayerID] = []
            for _ in 0..<14 {
                var spec = PlayerFactory.Spec(
                    position: rng.pick(PlayerFactory.rosterPositions(tier)), tier: tier, season: season)
                spec.age = 18...22
                spec.ability = (range.lowerBound - 8)...(range.lowerBound + 6)
                spec.potential = (range.lowerBound + 8)...(range.upperBound + 5)
                pool.append(makePlayer(spec).id)
            }
            func value(_ id: PlayerID) -> Double {
                guard let player = players[id] else { return 0 }
                return player.potential * 0.6 + player.ability * 0.4
            }
            pool.sort { (value($0), -$0) > (value($1), -$1) }

            let order = teams(in: tier).sorted {
                (lastWinRate[$0.id] ?? 0, $0.id) < (lastWinRate[$1.id] ?? 0, $1.id)
            }
            for team in order {
                guard !pool.isEmpty else { break }
                if team.isUser {
                    // 내 차례: 남은 선수 중 다섯 명이 지명 후보로 온다. 한 명만 고를 수 있다.
                    let board = pool.prefix(5)
                    candidates += board.map {
                        Candidate(id: newMarketID(), playerID: $0, fee: 0, matchesLeft: 99, source: .draft)
                    }
                    pool.removeFirst(board.count)
                    post("신인 드래프트: 지명 후보 \(board.count)명이 왔습니다. 선수 탭에서 한 명을 고르세요.")
                } else if teams[team.id].roster.count < Balance.rosterLimit(tier) {
                    add(pool.removeFirst(), to: team.id)
                }
            }
            pool.forEach { removePlayer($0) }
        }
    }

    mutating func endOffseason() {
        // 재계약하지 않은 계약 만료 선수는 떠난다.
        let leaving = roster(of: userTeamID).filter { $0.contract.seasonsLeft <= 0 }
        for player in leaving { moveToFreeAgency(player.id) }
        if !leaving.isEmpty {
            post("계약이 끝나 떠난 선수: \(leaving.map(\.name).joined(separator: ", "))")
        }

        // 남은 후보·제안 정리
        for candidate in candidates { removePlayer(candidate.playerID) }
        candidates = []
        offers = []
        proposals = []
        counters = []
        scoutTrip = nil

        // CPU 구단: FA에서 약한 자리를 채우고, 로스터를 리그에 맞게 정리한다.
        let targets = LeagueTier.allCases.map { leagueTargetAverage($0) }
        for team in teams where !team.isUser {
            signFreeAgentForCPU(team.id)
            normalizeCPURoster(team.id, leagueTarget: targets[team.tier.index])
        }
        fillUserMinimumRoster()
        trimFreeAgents()

        // 새 시즌
        season += 1
        round = 0
        phase = .regular
        appliedForPromotion = false
        expiryNoticeSent = false
        relegatedThisOffseason = false
        if sponsorPenaltySeasons > 0 { sponsorPenaltySeasons -= 1 }
        funds.startNewSeason()
        for team in teams {
            teams[team.id].streak = 0
            for id in team.roster {
                guard var player = players[id] else { continue }
                player.batting = BattingLine()
                player.pitching = PitchingLine()
                player.abilityAtSeasonStart = player.ability
                player.isHot = false
                players[id] = player
            }
        }
        startSeasonSchedules()
        post("\(season)번째 시즌 시작! \(userTier.displayName) 리그.")
    }

    /// CPU 구단이 FA 시장에서 가장 약한 자리를 한 명 보강한다.
    mutating func signFreeAgentForCPU(_ id: TeamID) {
        let tier = teams[id].tier
        let range = Balance.abilityRange(tier)
        guard teams[id].roster.count < Balance.rosterLimit(tier),
              let weakest = coreRoster(id).min(by: { ($0.ability, $0.id) < ($1.ability, $1.id) })
        else { return }
        let options = freeAgents.compactMap { players[$0] }.filter {
            $0.position == weakest.position && $0.ability > weakest.ability + 2
                && range.contains($0.ability) && $0.age < Balance.retirementAge(tier)
        }
        guard let pick = options.max(by: { ($0.ability, $0.id) < ($1.ability, $1.id) }) else { return }
        add(pick.id, to: id)
        players[pick.id]?.contract = Contract(
            salary: Balance.marketSalary(ability: pick.ability), seasonsLeft: rng.int(1...3))
    }

    /// 내 팀에 경기를 치를 최소 인원이 없으면 임시 선수를 데려온다.
    mutating func fillUserMinimumRoster() {
        var added: [String] = []
        func count(_ pitcher: Bool) -> Int { roster(of: userTeamID).filter { $0.isPitcher == pitcher }.count }
        while count(false) < Balance.minBatters || count(true) < Balance.minPitchers {
            let needPitcher = count(true) < Balance.minPitchers
            let have = Set(roster(of: userTeamID).map(\.position))
            let position: Position = needPitcher
                ? (have.contains(.starter) ? .reliever : .starter)
                : (Position.fieldPositions.first { !have.contains($0) } ?? .designated)
            var spec = PlayerFactory.Spec(position: position, tier: userTier, season: season)
            let low = Balance.abilityRange(userTier).lowerBound
            spec.ability = low...(low + 5)
            let player = makePlayer(spec)
            players[player.id]?.contract.seasonsLeft = 1
            add(player.id, to: userTeamID)
            added.append(player.name)
        }
        if !added.isEmpty {
            post("선수가 모자라 임시 선수를 데려왔습니다: \(added.joined(separator: ", "))")
        }
    }

    mutating func trimFreeAgents() {
        let limit = 120
        guard freeAgents.count > limit else { return }
        let sorted = freeAgents.compactMap { players[$0] }
            .sorted { ($0.ability - Double($0.age), $0.id) > ($1.ability - Double($1.age), $1.id) }
        for player in sorted.dropFirst(limit) { removePlayer(player.id) }
    }
}
