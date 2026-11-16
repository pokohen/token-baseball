import Foundation

/// 야구 경기 엔진: 삼진, 볼넷, 타구의 결과.
extension MatchState {
    // MARK: 타석 결과

    mutating func strikeout(_ batterIndex: Int, _ pitcherIndex: Int, _ events: inout [MatchEvent]) {
        batting.batters[batterIndex].line.atBats += 1
        batting.batters[batterIndex].line.strikeouts += 1
        fielding.pitchers[pitcherIndex].line.strikeouts += 1
        recordOut()
        endPlateAppearance(&events)
    }

    mutating func walk(_ batterIndex: Int, _ pitcherIndex: Int, _ events: inout [MatchEvent]) {
        batting.batters[batterIndex].line.walks += 1
        fielding.pitchers[pitcherIndex].line.walks += 1
        // 밀어내기: 앞이 다 차 있는 주자만 움직인다.
        let batterRunner = Runner(batterIndex: batterIndex, pitcherIndex: pitcherIndex, earned: true)
        if bases[0] != nil {
            if bases[1] != nil {
                if let third = bases[2] {
                    score(third, rbiTo: batterIndex, &events)
                }
                bases[2] = bases[1]
            }
            bases[1] = bases[0]
        }
        bases[0] = batterRunner
        endPlateAppearance(&events)
    }

    enum BallType { case ground, fly, line }

    mutating func inPlay(
        lead: String, batterIndex: Int, pitcherIndex: Int,
        contact: Double, power: Double, stuff: Double, speed: Double,
        _ events: inout [MatchEvent]
    ) {
        let batter = batting.batters[batterIndex]
        let advantage = contact - stuff
        let batterRunner = Runner(batterIndex: batterIndex, pitcherIndex: pitcherIndex, earned: true)

        // 홈런
        let homeRunChance = clamp(0.034 * exp((power - 50) / 30) * (1 - (stuff - 50) * 0.006), 0.002, 0.15)
        if rng.chance(homeRunChance) {
            let runnersOn = bases.compactMap { $0 }.count
            events.append(MatchEvent(.play, "\(lead) 쳤습니다! \(batter.name)의 \(runnersOn == 3 ? "만루 " : "")홈런!"))
            hit(batterIndex, pitcherIndex, bases: 4)
            advanceAll(by: 4, rbiTo: batterIndex, events: &events)
            score(batterRunner, rbiTo: batterIndex, &events)
            endPlateAppearance(&events)
            return
        }

        let type: BallType = [.ground, .fly, .line][rng.weighted([0.44, 0.33, 0.23])]
        let position: Position
        switch type {
        case .ground: position = rng.pick(Position.infield)
        case .fly: position = rng.pick(Position.outfield)
        case .line: position = rng.pick(Position.infield + Position.outfield)
        }
        let fielder = fielding.batters.first { $0.position == position }
        let defense = fielder?.fielding ?? 35
        let arm = fielder?.arm ?? 35

        var hitChance: Double
        switch type {
        case .ground: hitChance = 0.235 + advantage * 0.0015 - (defense - 50) * 0.002 + (speed - 50) * 0.0012
        case .line: hitChance = 0.66 + advantage * 0.0015 - (defense - 50) * 0.0015
        case .fly: hitChance = 0.13 + advantage * 0.001 - (defense - 50) * 0.002 + (power - 50) * 0.001
        }

        if rng.chance(clamp(hitChance, 0.03, 0.9)) {
            let basesGained: Int
            switch type {
            case .ground:
                basesGained = 1
            case .line:
                basesGained = [1, 2, 3][rng.weighted([0.74, 0.23 + (power - 50) * 0.002, 0.03])]
            case .fly:
                basesGained = [1, 2, 3][rng.weighted([0.40, 0.50, 0.10 + (speed - 50) * 0.001])]
            }
            let label = ["안타", "2루타", "3루타"][basesGained - 1]
            let direction = type == .ground ? "\(position.label) 옆을 빠지는" : "\(position.label) 쪽"
            events.append(MatchEvent(.play, "\(lead) 쳤습니다! \(direction) \(label)"))
            hit(batterIndex, pitcherIndex, bases: basesGained)
            advanceOnHit(basesGained, batterIndex: batterIndex, arm: arm, &events)
            bases[basesGained - 1] = batterRunner
            endPlateAppearance(&events)
            return
        }

        // 실책
        var errorChance = clamp(0.05 - (defense - 50) * 0.0006, 0.005, 0.09)
        if fielder?.traits.contains(.ironGlove) == true { errorChance *= 0.5 }
        if rng.chance(errorChance) {
            events.append(MatchEvent(.play, "\(lead) \(position.label) 실책! \(batter.name) 출루"))
            batting.batters[batterIndex].line.atBats += 1
            fielding.errors += 1
            advanceAll(by: 1, rbiTo: nil, events: &events)
            bases[0] = Runner(batterIndex: batterIndex, pitcherIndex: pitcherIndex, earned: false)
            endPlateAppearance(&events)
            return
        }

        // 아웃
        switch type {
        case .ground:
            let doublePlay = clamp(0.42 - (speed - 50) * 0.004 + (defense - 50) * 0.003, 0.1, 0.7)
            if bases[0] != nil, outs < 2, rng.chance(doublePlay) {
                events.append(MatchEvent(.play, "\(lead) \(position.label) 땅볼, 병살타!"))
                batting.batters[batterIndex].line.atBats += 1
                bases[0] = nil
                recordOut()
                recordOut()
                if outs < 3 {
                    if let third = bases[2] { score(third, rbiTo: nil, &events); bases[2] = nil }
                    if let second = bases[1] { bases[2] = second; bases[1] = nil }
                }
            } else {
                events.append(MatchEvent(.play, "\(lead) \(position.label) 땅볼 아웃"))
                batting.batters[batterIndex].line.atBats += 1
                recordOut()
                if outs < 3 {
                    if let third = bases[2], rng.chance(0.5) {
                        score(third, rbiTo: batterIndex, &events)
                        bases[2] = nil
                    }
                    if let second = bases[1], bases[2] == nil, rng.chance(0.55) {
                        bases[2] = second
                        bases[1] = nil
                    }
                    if let first = bases[0], bases[1] == nil {
                        bases[1] = first
                        bases[0] = nil
                    }
                }
            }
        case .fly:
            recordOut()
            var sacrifice = false
            if outs < 3, let third = bases[2] {
                let runnerSpeed = batting.batters[third.batterIndex].speed
                if rng.chance(clamp(0.5 + (runnerSpeed - arm) * 0.005, 0.1, 0.9)) {
                    sacrifice = true
                    events.append(MatchEvent(.play, "\(lead) \(position.label) 뜬공, 희생플라이"))
                    score(third, rbiTo: batterIndex, &events)
                    bases[2] = nil
                }
            }
            if !sacrifice {
                events.append(MatchEvent(.play, "\(lead) \(position.label) 뜬공 아웃"))
                batting.batters[batterIndex].line.atBats += 1
                if outs < 3, let second = bases[1], bases[2] == nil, rng.chance(0.2) {
                    bases[2] = second
                    bases[1] = nil
                }
            }
        case .line:
            events.append(MatchEvent(.play, "\(lead) \(position.label) 직선타 아웃"))
            batting.batters[batterIndex].line.atBats += 1
            recordOut()
        }
        endPlateAppearance(&events)
    }

    mutating func hit(_ batterIndex: Int, _ pitcherIndex: Int, bases gained: Int) {
        var team = batting
        team.hits += 1
        team.batters[batterIndex].line.atBats += 1
        team.batters[batterIndex].line.hits += 1
        switch gained {
        case 2: team.batters[batterIndex].line.doubles += 1
        case 3: team.batters[batterIndex].line.triples += 1
        case 4: team.batters[batterIndex].line.homeRuns += 1
        default: break
        }
        batting = team
        fielding.pitchers[pitcherIndex].line.hits += 1
        if gained == 4 { fielding.pitchers[pitcherIndex].line.homeRuns += 1 }
    }
}
