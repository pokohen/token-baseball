import Foundation

/// 종목. 구단을 만들 때 고르고, 세이브는 종목별로 따로 둔다.
public enum Sport: String, Codable, CaseIterable, Sendable {
    case baseball, football

    public var label: String {
        switch self {
        case .baseball: "야구"
        case .football: "축구"
        }
    }

    public var symbol: String {
        switch self {
        case .baseball: "⚾"
        case .football: "⚽"
        }
    }

    /// 한 경기에 나서는 선수 수 (야구는 야수 9명 + 투수).
    public var clubWord: String {
        switch self {
        case .baseball: "야구단"
        case .football: "축구단"
        }
    }
}

/// 축구 전술 성향. 슈팅 기회와 실점 위험이 함께 오르내린다.
public enum Tactic: String, Codable, CaseIterable, Sendable {
    case attacking = "공격적", balanced = "균형", defensive = "수비적"

    /// 공격 쪽 능력에 더하는 값. 수비 쪽에는 같은 크기를 뺀다.
    var attackShift: Double {
        switch self {
        case .attacking: 4
        case .balanced: 0
        case .defensive: -4
        }
    }
}

/// 축구 선수의 시즌 기록 (경기 중에는 그 경기의 기록).
public struct FootballLine: Codable, Equatable, Sendable {
    public var games = 0, goals = 0, assists = 0
    public var shots = 0, shotsOnTarget = 0
    public var yellowCards = 0, redCards = 0
    /// 골키퍼 기록.
    public var saves = 0, conceded = 0, cleanSheets = 0

    public init() {}

    public var points: Int { goals + assists }

    public static func += (lhs: inout FootballLine, rhs: FootballLine) {
        lhs.games += rhs.games
        lhs.goals += rhs.goals
        lhs.assists += rhs.assists
        lhs.shots += rhs.shots
        lhs.shotsOnTarget += rhs.shotsOnTarget
        lhs.yellowCards += rhs.yellowCards
        lhs.redCards += rhs.redCards
        lhs.saves += rhs.saves
        lhs.conceded += rhs.conceded
        lhs.cleanSheets += rhs.cleanSheets
    }
}
