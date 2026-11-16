import Foundation

/// 축구 경기 엔진: 전·후반과 연장의 끝, 승부차기, 중계 문장.
extension FootballMatch {
    // MARK: 전·후반 끝

    mutating func endPeriod(_ events: inout [MatchEvent]) {
        // 두 경기 합산이면 1차전 골을 더해서 비교한다.
        let tied = home.goals + (rules.firstLegHome ?? 0) == away.goals + (rules.firstLegAway ?? 0)
        switch period {
        case .firstHalf:
            say(&events, .inning, "전반 종료. \(scoreText)")
            start(.secondHalf, homeKicksOff: true)
        case .secondHalf:
            if rules.mustHaveWinner, tied {
                say(&events, .inning, "90분 종료. \(scoreText) — 연장전으로 갑니다")
                start(.extraFirst, homeKicksOff: false)
            } else {
                finish(&events)
            }
        case .extraFirst:
            say(&events, .inning, "연장 전반 종료. \(scoreText)")
            start(.extraSecond, homeKicksOff: true)
        case .extraSecond:
            if tied {
                say(&events, .inning, "연장 종료. \(scoreText) — 승부차기로 갑니다")
                period = .shootout
                homeKicksNext = rng.chance(0.5)
            } else {
                finish(&events)
            }
        default:
            finish(&events)
        }
    }

    mutating func start(_ next: Period, homeKicksOff: Bool) {
        period = next
        clock = 0
        added = rng.int(next == .secondHalf ? 2...5 : 1...3) * 60
        announcedAdded = false
        pending = nil
        homeHasBall = homeKicksOff
        zone = 1
    }

    // MARK: 승부차기

    mutating func takeShootoutKick(_ events: inout [MatchEvent]) {
        let isHome = homeKicksNext
        homeHasBall = isHome
        var side = isHome ? home : away
        let kickers = side.players.indices.filter { side.players[$0].isOnPitch }
            .sorted { (side.players[$0].shooting, -$0) > (side.players[$1].shooting, -$1) }
        guard !kickers.isEmpty else {
            finish(&events)
            return
        }
        let kicker = side.players[kickers[side.shootoutKicks % kickers.count]]
        let power = kicker.shooting + (kicker.traits.contains(.setPiece) ? 8 : 0)
        let scored = rng.chance(clamp(0.75 + (power - keepingValue(penalty: true)) / 250, 0.5, 0.92))
        side.shootoutKicks += 1
        if scored { side.shootoutGoals += 1 }
        if isHome { home = side } else { away = side }
        events.append(MatchEvent(
            scored ? .score : .play,
            "승부차기 \(side.shortName) \(side.shootoutKicks)번 \(kicker.name), \(scored ? "성공" : "실축") — \(away.shootoutGoals):\(home.shootoutGoals)"))
        homeKicksNext.toggle()

        let hk = home.shootoutKicks, ak = away.shootoutKicks
        let hg = home.shootoutGoals, ag = away.shootoutGoals
        if hk <= 5, ak <= 5 {
            if hg > ag + (5 - ak) || ag > hg + (5 - hk) { finish(&events) }
        }
        if !isFinished, hk == ak, hk >= 5, hg != ag { finish(&events) }
    }

    mutating func finish(_ events: inout [MatchEvent]) {
        isFinished = true
        // 무실점 경기: 끝까지 골문을 지킨 골키퍼에게 준다.
        for isHome in [true, false] {
            let conceded = isHome ? away.goals : home.goals
            guard conceded == 0 else { continue }
            if isHome, let index = home.keeperIndex { home.players[index].line.cleanSheets += 1 }
            if !isHome, let index = away.keeperIndex { away.players[index].line.cleanSheets += 1 }
        }
        let summary: String
        switch result {
        case .homeWin: summary = "\(home.name) 승리"
        case .awayWin: summary = "\(away.name) 승리"
        default: summary = "무승부"
        }
        period = .finished
        events.append(MatchEvent(.end, "경기 종료. \(scoreText), \(summary)"))
    }

    // MARK: 중계 문장

    static let buildUpLines = ["전방으로 패스를 연결합니다", "측면으로 공을 풀어 나옵니다", "길게 넘겨 줍니다", "차분하게 올라옵니다"]
    static let advanceLines = ["오른쪽을 돌파합니다", "왼쪽 측면을 파고듭니다", "스루패스!", "수비 사이로 찔러 줍니다", "드리블로 치고 들어갑니다"]
    static let interceptLines = ["패스를 가로챕니다", "태클로 공을 따냅니다", "몸싸움에서 이겨 공을 뺏습니다"]
    static let clearLines = ["걷어냅니다", "태클 성공", "크로스를 머리로 끊어냅니다", "공을 뺏어냅니다"]
    static let probeLines = ["크로스를 노립니다", "페널티 박스 앞에서 공을 돌립니다", "수비를 앞에 두고 틈을 봅니다", "원투 패스를 주고받습니다"]
    static let missLines = ["슈팅, 골대 옆으로 벗어납니다", "중거리 슛! 크게 뜹니다", "슈팅, 골대를 살짝 넘어갑니다", "발리슛, 빗맞았습니다"]
    static let saveLines = ["정면에서 잡아냅니다", "몸을 날려 막아냅니다", "안전하게 품에 안습니다"]
    static let goalLines = ["오른발 슛이 구석에 꽂힙니다!", "침착하게 밀어 넣습니다!", "중거리 슛이 그물을 흔듭니다!", "골키퍼를 넘기는 슛!", "왼발로 마무리합니다!"]
}
