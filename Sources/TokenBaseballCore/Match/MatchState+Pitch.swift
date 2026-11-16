import Foundation

/// 야구 경기 엔진: 공 하나를 던진다.
extension MatchState {
    // MARK: 투구

    enum PitchType: CaseIterable {
        case fastball, slider, curve, changeup, fork

        var name: String {
            switch self {
            case .fastball: "직구"
            case .slider: "슬라이더"
            case .curve: "커브"
            case .changeup: "체인지업"
            case .fork: "포크"
            }
        }

        var speedDrop: Double {
            switch self {
            case .fastball: 0
            case .slider: 12
            case .curve: 22
            case .changeup: 14
            case .fork: 10
            }
        }
    }

    mutating func throwPitch(_ events: inout [MatchEvent]) {
        let batterIndex = batting.battingIndex
        let pitcherIndex = fielding.pitcherIndex
        let batter = batting.batters[batterIndex]
        let pitcher = fielding.pitchers[pitcherIndex]

        pitchCount += 1
        pitchesThisPA += 1
        fielding.pitchers[pitcherIndex].line.pitches += 1

        // 체력: 한계 투구 수를 넘기면 구위와 제구가 떨어진다.
        let over = max(0, Double(pitcher.line.pitches) - capacity(of: pitcher))
        var stuff = pitcher.stuff - over * 0.35
        var control = pitcher.control - over * 0.45
        var contact = batter.contact
        var power = batter.power
        let eye = batter.eye

        let scoringPosition = bases[1] != nil || bases[2] != nil
        if scoringPosition, pitcher.traits.contains(.coolHead) { stuff += 4; control += 4 }
        if scoringPosition, batter.traits.contains(.clutch) { contact += 5; power += 3 }
        if batter.traits.contains(.slowStarter), batter.line.plateAppearances == 0 { contact -= 6 }
        if batter.traits.contains(.leftyKiller), pitcher.throwsHand == .left { contact += 6; power += 4 }

        // 홈 보정
        let edge = rules.homeEdge * 100
        if isBottom {
            contact += edge
            power += edge * 0.5
        } else {
            stuff += edge
            control += edge * 0.5
        }

        // 구종과 구속
        let fastballWeight = max(0.3, 0.65 - pitcher.breaking * 0.003)
        let rest = 1 - fastballWeight
        let type = PitchType.allCases[rng.weighted([
            fastballWeight, rest * 0.40, rest * 0.24, rest * 0.24, rest * 0.12,
        ])]
        let isBreaking = type != .fastball
        let velocity = Int((108 + stuff * 0.48 - type.speedDrop + rng.gaussian() * 2).rounded())

        // 코스: 볼카운트가 불리하면 존 안쪽을 노린다.
        var intent = 0.50 + Double(balls - strikes) * 0.07
        if balls == 3 { intent += 0.12 }
        if strikes == 2, balls < 2 { intent -= 0.12 }
        intent = clamp(intent, 0.25, 0.85)
        let aimedInZone = rng.chance(intent)
        let inZone = aimedInZone
            ? rng.chance(clamp(0.66 + control * 0.003, 0.4, 0.95))
            : rng.chance(clamp(0.10 + (50 - control) * 0.001, 0.02, 0.2))
        let location = rng.pick(inZone
            ? ["한가운데", "몸쪽", "바깥쪽", "높은 코스", "낮은 코스"]
            : ["바깥쪽 빠지는", "몸쪽 깊은", "높은", "원바운드성"])
        let lead = "\(pitchesThisPA)구째 \(type.name) \(velocity)km, \(location)"

        // 스윙 판단
        let swings: Bool
        if inZone {
            var probability = 0.64
            if strikes == 2 { probability += 0.24 }
            if balls == 3, strikes < 2 { probability -= 0.10 }
            swings = rng.chance(probability)
        } else {
            var chase = 0.30 - (eye - 50) * 0.003
            if isBreaking { chase += 0.03 + (pitcher.breaking - 50) * 0.0015 }
            if strikes == 2 { chase += 0.10 }
            swings = rng.chance(clamp(chase, 0.05, 0.6))
        }

        if !swings {
            if inZone {
                strikes += 1
                if strikes >= 3 {
                    events.append(MatchEvent(.play, "\(lead) 루킹 삼진! \(batter.name) 아웃"))
                    strikeout(batterIndex, pitcherIndex, &events)
                } else {
                    events.append(MatchEvent(.pitch, "\(lead) 스트라이크 (루킹)"))
                }
            } else {
                balls += 1
                if balls >= 4 {
                    events.append(MatchEvent(.play, "\(lead) 볼넷. \(batter.name) 출루"))
                    walk(batterIndex, pitcherIndex, &events)
                } else {
                    events.append(MatchEvent(.pitch, "\(lead) 볼"))
                }
            }
            return
        }

        // 맞히기
        var contactChance = (inZone ? 0.84 : 0.60) + (contact - stuff) * 0.004
        if isBreaking { contactChance -= 0.03 + (pitcher.breaking - 50) * 0.001 }
        if !rng.chance(clamp(contactChance, 0.3, 0.97)) {
            strikes += 1
            if strikes >= 3 {
                events.append(MatchEvent(.play, "\(lead) 헛스윙 삼진! \(batter.name) 아웃"))
                strikeout(batterIndex, pitcherIndex, &events)
            } else {
                events.append(MatchEvent(.pitch, "\(lead) 헛스윙!"))
            }
            return
        }

        if rng.chance(inZone ? 0.42 : 0.50) {
            if strikes < 2 { strikes += 1 }
            events.append(MatchEvent(.pitch, "\(lead) 파울"))
            return
        }

        inPlay(
            lead: lead, batterIndex: batterIndex, pitcherIndex: pitcherIndex,
            contact: contact, power: power, stuff: stuff, speed: batter.speed, &events)
    }
}
