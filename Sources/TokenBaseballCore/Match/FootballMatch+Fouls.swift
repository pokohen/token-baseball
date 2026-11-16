import Foundation

/// 축구 경기 엔진: 반칙과 카드, 체력과 교체.
extension FootballMatch {
    // MARK: 반칙

    /// 수비 팀의 반칙. 공격 팀이 공을 그대로 갖는다.
    mutating func foul(dangerous: Bool, penalty: Bool = false, _ events: inout [MatchEvent]) {
        var indices: [Int] = []
        var weights: [Double] = []
        for (index, player) in defending.players.enumerated() where player.isOnPitch {
            indices.append(index)
            weights.append(player.slot == .goalkeeper ? (penalty ? 0.4 : 0.02) : player.slot == .forward ? 1 : 2)
        }
        guard !indices.isEmpty else { return }
        let index = indices[rng.weighted(weights)]
        let fouler = defending.players[index]
        let victim = holder(zone == 2 ? [.forward, .midfielder] : [.midfielder])
        defending.fouls += 1

        var text = "\(defending.shortName) \(fouler.name), \(victim)에게 반칙"
        var sentOff = false
        let roll = rng.unit()
        if roll < (penalty ? 0.02 : 0.001) {
            sentOff = true
            text += ". 곧바로 퇴장!"
        } else if roll < (dangerous ? 0.24 : 0.13) {
            defending.yellowCards += 1
            defending.players[index].line.yellowCards += 1
            if defending.players[index].line.yellowCards >= 2 {
                sentOff = true
                text += ". 두 번째 경고로 퇴장!"
            } else {
                text += ". 경고"
            }
        }
        if penalty { text += " — 페널티킥!" } else if dangerous { text += " — 위험한 위치의 프리킥" }
        say(&events, sentOff ? .change : .play, text)

        if sentOff { sendOff(home: !homeHasBall, index: index, &events) }
        if penalty {
            zone = 2
            pending = .penalty
        } else if dangerous {
            zone = 2
            pending = .freeKick
        }
    }

    /// 퇴장 처리: 선수가 나가고, 골키퍼였으면 골문을 지킬 선수를 정한다.
    mutating func sendOff(home isHome: Bool, index: Int, _ events: inout [MatchEvent]) {
        var side = isHome ? home : away
        let wasKeeper = side.players[index].slot == .goalkeeper
        side.redCards += 1
        side.players[index].line.redCards += 1
        side.players[index].isOnPitch = false
        side.players[index].sentOff = true
        if isHome { home = side } else { away = side }
        if wasKeeper { replaceKeeper(home: isHome, &events) }
    }

    /// 골키퍼가 퇴장당했을 때: 벤치 골키퍼를 넣거나, 필드 선수가 장갑을 낀다.
    mutating func replaceKeeper(home isHome: Bool, _ events: inout [MatchEvent]) {
        var side = isHome ? home : away
        defer { if isHome { home = side } else { away = side } }
        let bench = side.players.indices.first {
            !side.players[$0].hasPlayed && side.players[$0].natural == .goalkeeper
        }
        if let bench, side.subsUsed < Balance.footballMaxSubs,
           let out = side.players.indices.filter({ side.players[$0].isOnPitch && side.players[$0].slot == .forward })
            .min(by: { side.players[$0].energy < side.players[$1].energy })
            ?? side.players.indices.filter({ side.players[$0].isOnPitch }).min(by: { side.players[$0].energy < side.players[$1].energy }) {
            side.players[out].isOnPitch = false
            side.players[bench].isOnPitch = true
            side.players[bench].hasPlayed = true
            side.players[bench].slot = .goalkeeper
            side.players[bench].line.games = 1
            side.subsUsed += 1
            say(&events, .change, "\(side.shortName) 교체: \(side.players[out].name) 나가고 골키퍼 \(side.players[bench].name) 들어옵니다")
        } else if let stand = side.players.indices.filter({ side.players[$0].isOnPitch })
            .max(by: { side.players[$0].keeping < side.players[$1].keeping }) {
            side.players[stand].slot = .goalkeeper
            say(&events, .change, "\(side.shortName) \(side.players[stand].name), 골키퍼 장갑을 낍니다")
        }
    }

    // MARK: 체력과 교체

    mutating func tire() {
        for index in home.players.indices where home.players[index].isOnPitch { Self.drain(&home.players[index]) }
        for index in away.players.indices where away.players[index].isOnPitch { Self.drain(&away.players[index]) }
    }

    static func drain(_ player: inout FootballPlayerState) {
        var amount = 0.0019 * (1.25 - player.stamina / 100 * 0.7)
        if player.traits.contains(.ironLungs) { amount *= 0.7 }
        if player.slot == .goalkeeper { amount *= 0.3 }
        player.energy = max(0.2, player.energy - amount)
    }

    /// 60분 이후 지친 선수부터 같은 포지션의 벤치 선수로 바꾼다. 한 틱에 한 팀 한 명.
    mutating func substitute(_ events: inout [MatchEvent]) {
        guard minute >= 60 else { return }
        let threshold = 0.66
        // 한꺼번에 바꾸지 않고 6분에 한 명꼴로 바꾼다.
        let allowed = min(Balance.footballMaxSubs, (minute - 55) / 6)
        for isHome in [true, false] {
            var side = isHome ? home : away
            guard side.subsUsed < allowed else { continue }
            guard let out = side.players.indices
                .filter({ side.players[$0].isOnPitch && side.players[$0].slot != .goalkeeper && side.players[$0].energy < threshold })
                .min(by: { (side.players[$0].energy, $0) < (side.players[$1].energy, $1) })
            else { continue }
            let slot = side.players[out].slot
            let bench = side.players.indices.filter {
                !side.players[$0].hasPlayed && side.players[$0].natural != .goalkeeper
            }
            guard let incoming = bench.first(where: { side.players[$0].natural == slot }) ?? bench.first else { continue }
            side.players[out].isOnPitch = false
            side.players[incoming].isOnPitch = true
            side.players[incoming].hasPlayed = true
            side.players[incoming].slot = slot
            side.players[incoming].line.games = 1
            side.subsUsed += 1
            say(&events, .change, "\(side.shortName) 교체: \(side.players[out].name) 나가고 \(side.players[incoming].name) 들어옵니다")
            if isHome { home = side } else { away = side }
        }
    }
}
