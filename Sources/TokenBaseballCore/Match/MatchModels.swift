import Foundation

/// 투수 운용 방침. 경기 전에 정하고, 경기는 이 방침대로 흘러간다.
public struct PitchingPolicy: Codable, Equatable, Sendable {
    /// 선발 투수를 바꾸는 투구 수.
    public var starterPitchLimit = 95
    /// 선발 투수를 바꾸는 실점.
    public var starterRunLimit = 5
    /// 마무리를 올리는 최대 점수 차 (1점 ~ 이 값).
    public var closerMaxLead = 3
    /// 마무리를 올리기 시작하는 이닝.
    public var closerFromInning = 9

    public init() {}
}

public struct MatchBatter: Codable, Equatable, Sendable {
    public var playerID: PlayerID
    public var name: String
    /// 이 경기에서 서는 자리.
    public var position: Position
    public var contact: Double, power: Double, eye: Double, speed: Double, fielding: Double, arm: Double
    public var bats: Hand
    public var traits: [Trait]
    public var line = BattingLine()
}

public struct MatchPitcher: Codable, Equatable, Sendable {
    public var playerID: PlayerID
    public var name: String
    public var role: Position
    public var stuff: Double, control: Double, breaking: Double, stamina: Double
    public var throwsHand: Hand
    public var traits: [Trait]
    public var line = PitchingLine()
    public var hasEntered = false
    /// 등판했을 때 팀이 앞서 있던 점수 (세이브 판정용). 앞서지 않았으면 0 이하.
    public var leadOnEntry = 0
}

public struct MatchTeam: Codable, Equatable, Sendable {
    public var teamID: TeamID
    public var name: String
    public var shortName: String
    /// 타순대로 9명.
    public var batters: [MatchBatter]
    /// 0번이 선발. 나머지는 올릴 순서대로의 불펜.
    public var pitchers: [MatchPitcher]
    public var policy: PitchingPolicy
    public var runsByInning: [Int] = []
    public var hits = 0
    public var errors = 0
    public var battingIndex = 0
    public var pitcherIndex = 0

    public var runs: Int { runsByInning.reduce(0, +) }

    public init(
        teamID: TeamID, name: String, shortName: String,
        batters: [MatchBatter], pitchers: [MatchPitcher], policy: PitchingPolicy
    ) {
        self.teamID = teamID
        self.name = name
        self.shortName = shortName
        self.batters = batters
        self.pitchers = pitchers
        self.policy = policy
    }
}

public struct MatchRules: Codable, Equatable, Sendable {
    /// 콜드게임 (시민 리그만): 5회 이후 10점 차, 7회 이후 7점 차.
    public var coldGame = false
    /// 최대 이닝. 넘어가도 동점이면 무승부. `nil`이면 승부가 날 때까지 한다 (승강 플레이오프).
    public var maxInnings: Int? = 11
    /// 홈 보정 (0.02 = +2%).
    public var homeEdge = 0.02

    public init(coldGame: Bool = false, maxInnings: Int? = 11, homeEdge: Double = 0.02) {
        self.coldGame = coldGame
        self.maxInnings = maxInnings
        self.homeEdge = homeEdge
    }
}

public struct MatchEvent: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case pitch, play, score, inning, change, running, end
    }

    public var kind: Kind
    public var text: String

    public init(_ kind: Kind, _ text: String) {
        self.kind = kind
        self.text = text
    }
}

/// 누상의 주자.
public struct Runner: Codable, Equatable, Sendable {
    /// 공격 팀 타순에서의 위치.
    public var batterIndex: Int
    /// 이 주자를 내보낸 투수 (수비 팀 투수 목록에서의 위치).
    public var pitcherIndex: Int
    /// 실책으로 나간 주자는 자책점이 아니다.
    public var earned: Bool
}

public enum MatchResult: Equatable, Sendable {
    case homeWin, awayWin, draw
}
