import Foundation

/// 축구 한 경기에 나서는 선수 구성.
public struct FootballLineup: Equatable, Sendable {
    /// 선발 11명과 서는 자리. 골키퍼 → 수비 → 미드필더 → 공격 순.
    public var starters: [(id: PlayerID, slot: Position)]
    /// 벤치. 능력 순.
    public var bench: [PlayerID]

    public static func == (lhs: FootballLineup, rhs: FootballLineup) -> Bool {
        lhs.bench == rhs.bench && lhs.starters.map(\.id) == rhs.starters.map(\.id)
            && lhs.starters.map(\.slot) == rhs.starters.map(\.slot)
    }
}

public enum FootballLineupBuilder {
    /// 제 포지션이 아닌 자리에 서면 능력이 이만큼만 나온다.
    static let outOfPosition = 0.88

    /// 능력 순으로 자동 구성한다. 내가 정한 선발 11명이 있고 쓸 수 있으면 그것을 따른다.
    /// 골키퍼 1명을 포함해 11명이 있어야 한다.
    public static func build(team: Team, players: [PlayerID: Player]) -> FootballLineup? {
        let roster = team.roster.compactMap { players[$0] }.filter { $0.position.sport == .football }
        guard roster.count >= Balance.footballStarters,
              roster.contains(where: { $0.position == .goalkeeper })
        else { return nil }
        let formation = (team.formation ?? .f442).slots
        let ranked = roster.sorted { ($0.ability, -$0.id) > ($1.ability, -$1.id) }

        var chosen: [Player]
        let override = team.lineupOverride.compactMap { players[$0] }.filter { team.roster.contains($0.id) }
        if override.count == Balance.footballStarters, Set(override.map(\.id)).count == override.count,
           override.contains(where: { $0.position == .goalkeeper }) {
            chosen = override
        } else {
            chosen = []
            var remaining = ranked
            for slot in Position.football {
                let quota = formation.filter { $0 == slot }.count
                for _ in 0..<quota {
                    if let index = remaining.firstIndex(where: { $0.position == slot }) {
                        chosen.append(remaining.remove(at: index))
                    }
                }
            }
            // 모자란 자리는 남은 필드 선수 중 능력이 좋은 순으로 메운다.
            while chosen.count < Balance.footballStarters,
                  let index = remaining.firstIndex(where: { $0.position != .goalkeeper }) ?? remaining.indices.first {
                chosen.append(remaining.remove(at: index))
            }
        }
        guard chosen.count == Balance.footballStarters else { return nil }

        // 자리 나누기: 제 포지션부터 채우고, 남은 선수가 빈자리를 메운다.
        var open = formation
        var assigned: [PlayerID: Position] = [:]
        for player in chosen {
            if let index = open.firstIndex(of: player.position) {
                assigned[player.id] = player.position
                open.remove(at: index)
            }
        }
        for player in chosen where assigned[player.id] == nil {
            // 골키퍼 자리가 비었으면 골키핑이 가장 나은 선수가 선다.
            assigned[player.id] = open.isEmpty ? .midfielder : open.removeFirst()
        }
        let order = Position.football
        let starters = chosen
            .sorted {
                let a = order.firstIndex(of: assigned[$0.id] ?? .forward) ?? 0
                let b = order.firstIndex(of: assigned[$1.id] ?? .forward) ?? 0
                return (a, -$0.ability, $0.id) < (b, -$1.ability, $1.id)
            }
            .map { (id: $0.id, slot: assigned[$0.id] ?? $0.position) }
        let ids = Set(chosen.map(\.id))
        return FootballLineup(starters: starters, bench: ranked.filter { !ids.contains($0.id) }.map(\.id))
    }

    /// 경기 엔진에 넘길 팀 구성.
    public static func side(team: Team, players: [PlayerID: Player]) -> FootballSide? {
        guard let lineup = build(team: team, players: players) else { return nil }
        func state(_ id: PlayerID, slot: Position, starts: Bool) -> FootballPlayerState? {
            guard let player = players[id] else { return nil }
            let a = player.attributes
            let factor = slot == player.position ? 1.0 : outOfPosition
            let hot = player.isHot ? 3.0 : 0.0
            return FootballPlayerState(
                playerID: player.id, name: player.name, natural: player.position, slot: slot,
                shooting: a.shooting * factor + (player.position == .goalkeeper ? 0 : hot),
                passing: a.passing * factor, dribbling: a.dribbling * factor,
                tackling: a.tackling * factor + (player.traits.contains(.ironGlove) ? 5 : 0),
                speed: a.speed * factor, physical: a.physical * factor,
                keeping: a.keeping + (player.position == .goalkeeper ? hot : 0), stamina: a.stamina,
                traits: player.traits, starts: starts)
        }
        let starters = lineup.starters.compactMap { state($0.id, slot: $0.slot, starts: true) }
        let bench = lineup.bench.compactMap { id in
            players[id].flatMap { state(id, slot: $0.position, starts: false) }
        }
        guard starters.count == Balance.footballStarters else { return nil }
        return FootballSide(
            teamID: team.id, name: team.name, shortName: team.shortName,
            players: starters + bench, tactic: team.tactic ?? .balanced, formation: team.formation)
    }

    /// 팀 강도를 정하는 선수들: 자동으로 짠 선발 11명.
    public static func core(team: Team, players: [PlayerID: Player]) -> [Player] {
        var auto = team
        auto.lineupOverride = []
        if let lineup = build(team: auto, players: players) {
            return lineup.starters.compactMap { players[$0.id] }
        }
        return team.roster.compactMap { players[$0] }
            .sorted { ($0.ability, -$0.id) > ($1.ability, -$1.id) }
            .prefix(Balance.footballStarters).map { $0 }
    }

    /// 팀 강도 = 선발 11명의 평균 능력.
    public static func strength(team: Team, players: [PlayerID: Player]) -> Double {
        let eleven = core(team: team, players: players)
        return eleven.isEmpty ? 0 : eleven.reduce(0) { $0 + $1.ability } / Double(eleven.count)
    }
}
