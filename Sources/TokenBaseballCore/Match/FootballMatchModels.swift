import Foundation

/// 축구 경기에 나선 선수 한 명. 능력치는 경기를 시작할 때의 값이고, 체력(`energy`)에 따라 깎여 쓰인다.
public struct FootballPlayerState: Codable, Equatable, Sendable {
    public var playerID: PlayerID
    public var name: String
    /// 원래 포지션.
    public var natural: Position
    /// 이 경기에서 서는 자리.
    public var slot: Position
    public var shooting: Double, passing: Double, dribbling: Double, tackling: Double
    public var speed: Double, physical: Double, keeping: Double, stamina: Double
    public var traits: [Trait]
    /// 남은 체력 (1 = 가득).
    public var energy = 1.0
    public var isOnPitch: Bool
    public var hasPlayed: Bool
    public var sentOff = false
    public var line = FootballLine()

    public init(
        playerID: PlayerID, name: String, natural: Position, slot: Position,
        shooting: Double, passing: Double, dribbling: Double, tackling: Double,
        speed: Double, physical: Double, keeping: Double, stamina: Double,
        traits: [Trait], starts: Bool
    ) {
        self.playerID = playerID
        self.name = name
        self.natural = natural
        self.slot = slot
        self.shooting = shooting
        self.passing = passing
        self.dribbling = dribbling
        self.tackling = tackling
        self.speed = speed
        self.physical = physical
        self.keeping = keeping
        self.stamina = stamina
        self.traits = traits
        self.isOnPitch = starts
        self.hasPlayed = starts
        if starts { line.games = 1 }
    }

    /// 지치면 모든 능력이 조금씩 깎인다.
    var fatigue: Double { 0.75 + 0.25 * energy }
}

public struct FootballSide: Codable, Equatable, Sendable {
    public var teamID: TeamID
    public var name: String
    public var shortName: String
    /// 앞의 11명이 선발, 나머지가 벤치.
    public var players: [FootballPlayerState]
    public var tactic: Tactic
    /// nil이면 4-4-2 (이 값이 없던 때의 저장 파일도 그렇게 읽는다).
    public var formation: Formation?
    public var goals = 0
    public var shots = 0, shotsOnTarget = 0, corners = 0, fouls = 0, offsides = 0
    public var yellowCards = 0, redCards = 0
    /// 공을 갖고 있던 틱 수 (점유율 계산용).
    public var possession = 0
    public var subsUsed = 0
    public var shootoutGoals = 0, shootoutKicks = 0

    public init(teamID: TeamID, name: String, shortName: String, players: [FootballPlayerState], tactic: Tactic,
        formation: Formation? = nil
    ) {
        self.teamID = teamID
        self.name = name
        self.shortName = shortName
        self.players = players
        self.tactic = tactic
        self.formation = formation
    }

    public var shape: Formation { formation ?? .f442 }

    var onPitchCount: Int { players.filter(\.isOnPitch).count }

    /// 해당 자리에 선 선수들의 평균. 아무도 없으면 아주 낮은 값.
    func mean(
        _ slots: [Position], weights: [Position: Double] = [:], _ value: (FootballPlayerState) -> Double
    ) -> Double {
        var total = 0.0, weight = 0.0
        for player in players where player.isOnPitch && slots.contains(player.slot) {
            let w = weights[player.slot] ?? 1
            total += value(player) * player.fatigue * w
            weight += w
        }
        return weight > 0 ? total / weight : 10
    }

    /// 퇴장으로 모자란 인원만큼 깎이는 값.
    var shortHanded: Double { Double(max(0, 11 - onPitchCount)) * 4 }

    var keeperIndex: Int? { players.firstIndex { $0.isOnPitch && $0.slot == .goalkeeper } }
}

public struct FootballRules: Codable, Equatable, Sendable {
    /// 승부가 나야 하는 경기 (승강 플레이오프): 연장과 승부차기를 쓴다.
    public var mustHaveWinner = false
    /// 홈 보정 (0.02 = +2%).
    public var homeEdge = 0.02

    public init(mustHaveWinner: Bool = false, homeEdge: Double = 0.02) {
        self.mustHaveWinner = mustHaveWinner
        self.homeEdge = homeEdge
    }
}
