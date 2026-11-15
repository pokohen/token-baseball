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

/// 축구 포메이션. 줄마다 서는 인원이 달라지고, 강한 곳과 약한 곳이 생긴다.
public enum Formation: String, Codable, CaseIterable, Sendable {
    case f442 = "4-4-2", f433 = "4-3-3", f41212 = "4-1-2-1-2"

    public var label: String { rawValue }

    /// 수비, 미드필더, 공격 인원.
    public var shape: (defenders: Int, midfielders: Int, forwards: Int) {
        switch self {
        case .f442, .f41212: (4, 4, 2)
        case .f433: (4, 3, 3)
        }
    }

    /// 열한 자리. 골키퍼 → 수비 → 미드필더 → 공격 순.
    public var slots: [Position] {
        let s = shape
        return [.goalkeeper] + Array(repeating: .defender, count: s.defenders)
            + Array(repeating: .midfielder, count: s.midfielders) + Array(repeating: .forward, count: s.forwards)
    }

    /// 중원 싸움에 더하는 값 (공격할 때도 수비할 때도).
    var midfieldShift: Double {
        switch self {
        case .f442: 0
        case .f433: -2
        case .f41212: 2
        }
    }

    /// 상대 진영에서 기회를 만들 때 더하는 값.
    var attackShift: Double {
        switch self {
        case .f433: 3
        default: 0
        }
    }

    /// 우리 진영에서 막을 때 더하는 값.
    var defenseShift: Double {
        switch self {
        case .f41212: -5
        default: 0
        }
    }

    public var summary: String {
        switch self {
        case .f442: "기본형. 강한 곳도 약한 곳도 없습니다."
        case .f433: "공격수 3명. 상대 진영에서 기회를 더 만들지만 중원 싸움에서 밀립니다."
        case .f41212: "다이아몬드 중원. 중원을 장악하지만 측면이 비어 우리 진영 수비가 약해집니다."
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
