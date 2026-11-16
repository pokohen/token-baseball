import Foundation

/// 야구 경기 엔진: 주루와 득점, 타석·이닝·경기의 끝.
extension MatchState {
    // MARK: 주루

    /// 안타 때 주자 진루. 주력과 외야수 어깨에 따라 한 베이스 더 간다.
    mutating func advanceOnHit(_ gained: Int, batterIndex: Int, arm: Double, _ events: inout [MatchEvent]) {
        guard gained < 3 else {
            advanceAll(by: 3, rbiTo: batterIndex, events: &events)
            return
        }
        for base in stride(from: 2, through: 0, by: -1) {
            guard let runner = bases[base] else { continue }
            bases[base] = nil
            let runnerSpeed = batting.batters[runner.batterIndex].speed
            let extraBase: Double
            if gained == 1 {
                extraBase = base == 1 ? 0.60 : 0.28
            } else {
                extraBase = base == 0 ? 0.42 : 1.0
            }
            var target = base + gained
            if target < 3, rng.chance(clamp(extraBase + (runnerSpeed - arm) * 0.004, 0.1, 0.95)) {
                target += 1
            }
            // 앞 주자가 서 있는 베이스로는 가지 못한다.
            while target < 3, bases[target] != nil { target -= 1 }
            if target >= 3 {
                score(runner, rbiTo: batterIndex, &events)
            } else {
                bases[max(target, base + 1)] = runner
            }
        }
    }

    /// 모든 주자가 같은 수만큼 진루한다.
    mutating func advanceAll(by count: Int, rbiTo batterIndex: Int?, events: inout [MatchEvent]) {
        for base in stride(from: 2, through: 0, by: -1) {
            guard let runner = bases[base] else { continue }
            bases[base] = nil
            if base + count >= 3 {
                score(runner, rbiTo: batterIndex, &events)
            } else {
                bases[base + count] = runner
            }
        }
    }

    mutating func score(_ runner: Runner, rbiTo batterIndex: Int?, _ events: inout [MatchEvent]) {
        var offense = batting
        while offense.runsByInning.count < inning { offense.runsByInning.append(0) }
        offense.runsByInning[inning - 1] += 1
        offense.batters[runner.batterIndex].line.runs += 1
        if let batterIndex { offense.batters[batterIndex].line.runsBattedIn += 1 }
        batting = offense

        var defense = fielding
        defense.pitchers[runner.pitcherIndex].line.runs += 1
        if runner.earned { defense.pitchers[runner.pitcherIndex].line.earnedRuns += 1 }
        fielding = defense

        events.append(MatchEvent(
            .score, "\(offense.batters[runner.batterIndex].name) 홈인! \(away.shortName) \(away.runs) : \(home.runs) \(home.shortName)"))

        // 승리·패전 투수: 리드가 바뀔 때마다 다시 정한다.
        let difference = home.runs - away.runs
        let leader: Bool? = difference > 0 ? true : difference < 0 ? false : nil
        if leader != leaderIsHome {
            if leader == nil {
                winPitcherIndex = nil
                lossPitcherIndex = nil
            } else {
                winPitcherIndex = batting.pitcherIndex
                lossPitcherIndex = runner.pitcherIndex
            }
            leaderIsHome = leader
        }
    }

    mutating func recordOut() {
        outs += 1
        fielding.pitchers[fielding.pitcherIndex].line.outs += 1
    }

    // MARK: 타석·이닝·경기 끝

    mutating func endPlateAppearance(_ events: inout [MatchEvent]) {
        var team = batting
        team.batters[team.battingIndex].line.plateAppearances += 1
        team.battingIndex = (team.battingIndex + 1) % team.batters.count
        batting = team
        balls = 0
        strikes = 0
        pitchesThisPA = 0
        plateAppearanceStarted = false

        if checkWalkOff(&events) { return }
        if outs >= 3 { endHalfInning(&events) }
    }

    /// 말 공격 중에 경기가 끝나는 경우.
    /// 끝내기: 9회말 이후 홈팀이 앞서는 순간. 콜드게임: 홈팀이 기준 점수 차를 넘기는 순간.
    @discardableResult
    mutating func checkWalkOff(_ events: inout [MatchEvent]) -> Bool {
        guard !isFinished, isBottom, home.runs > away.runs else { return false }
        if inning >= 9 {
            events.append(MatchEvent(.play, "끝내기! \(home.name)의 승리"))
        } else if coldGameReached(lead: home.runs - away.runs) {
            events.append(MatchEvent(.inning, "콜드게임이 선언됩니다"))
        } else {
            return false
        }
        finish(&events)
        return true
    }

    func coldGameReached(lead: Int) -> Bool {
        guard rules.coldGame else { return false }
        if inning >= 7 { return lead >= 7 }
        if inning >= 5 { return lead >= 10 }
        return false
    }

    mutating func endHalfInning(_ events: inout [MatchEvent]) {
        outs = 0
        balls = 0
        strikes = 0
        pitchesThisPA = 0
        plateAppearanceStarted = false
        bases = [nil, nil, nil]

        let homeLead = home.runs - away.runs
        if !isBottom {
            // 초 공격 끝: 9회 이후 홈팀이 앞서 있으면 말 공격을 하지 않는다.
            if inning >= 9, homeLead > 0 { finish(&events); return }
            if coldGameReached(lead: homeLead) {
                events.append(MatchEvent(.inning, "콜드게임이 선언됩니다"))
                finish(&events)
                return
            }
            isBottom = true
        } else {
            if inning >= 9, homeLead != 0 { finish(&events); return }
            if coldGameReached(lead: abs(homeLead)) {
                events.append(MatchEvent(.inning, "콜드게임이 선언됩니다"))
                finish(&events)
                return
            }
            if inning >= 9, let limit = rules.maxInnings, inning >= limit { finish(&events); return }
            inning += 1
            isBottom = false
        }
        events.append(MatchEvent(.inning, "\(inningLabel) \(batting.shortName) 공격"))
    }

    mutating func finish(_ events: inout [MatchEvent]) {
        isFinished = true
        if let leaderIsHome {
            var winner = leaderIsHome ? home : away
            var loser = leaderIsHome ? away : home
            if let winPitcherIndex { winner.pitchers[winPitcherIndex].line.wins += 1 }
            if let lossPitcherIndex { loser.pitchers[lossPitcherIndex].line.losses += 1 }
            let last = winner.pitcherIndex
            if last != winPitcherIndex, (1...3).contains(winner.pitchers[last].leadOnEntry) {
                winner.pitchers[last].line.saves += 1
            }
            if leaderIsHome { home = winner; away = loser } else { away = winner; home = loser }
        }
        let summary: String
        switch result {
        case .homeWin: summary = "\(home.name) 승리"
        case .awayWin: summary = "\(away.name) 승리"
        default: summary = "무승부"
        }
        events.append(MatchEvent(
            .end, "경기 종료. \(away.shortName) \(away.runs) : \(home.runs) \(home.shortName), \(summary)"))
    }
}
