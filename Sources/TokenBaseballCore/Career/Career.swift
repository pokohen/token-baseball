import Foundation

/// 선수 모드에서 내 선수를 만들 때 정하는 것.
public struct CareerSetup: Equatable, Sendable {
    public var name: String
    public var position: Position
    public var bats: Hand
    public var throwsHand: Hand
    /// 출신 도시. 선수 소개에만 쓴다.
    public var hometown: String

    public init(
        name: String, position: Position, bats: Hand = .right, throwsHand: Hand = .right, hometown: String = "서울"
    ) {
        self.name = name
        self.position = position
        self.bats = bats
        self.throwsHand = throwsHand
        self.hometown = hometown
    }

    /// 선수 모드에서 고를 수 있는 포지션. 마무리는 세이브 상황에만 나와서 뺐다.
    public static let batterPositions: [Position] = Position.fieldPositions + [.designated]
    public static let pitcherPositions: [Position] = [.starter, .reliever]
    /// 축구 선수 모드의 포지션.
    public static let footballPositions: [Position] = Position.football

    public var sport: Sport { position.sport }
}

/// 다른 구단이 본 내 입지.
public enum CareerRole: String, Codable, Sendable {
    case starter = "주전", rotation = "주전 경쟁", prospect = "유망주"
}

/// 내 선수에게 온 계약 제안.
public struct CareerOffer: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// 다른 구단의 이적 제안.
        case transfer
        /// 지금 구단의 재계약 제안.
        case renewal
        /// 무소속일 때 받는 입단 제안.
        case tryout
    }

    public var id: Int
    public var kind: Kind
    public var teamID: TeamID
    public var salary: Int
    public var years: Int
    public var role: CareerRole
    /// 이 경기 수가 지나면 사라진다.
    public var matchesLeft: Int
    /// 연봉을 올려 달라고 이미 한 번 말했는지.
    public var negotiated = false
}

/// 감독이 시즌을 시작할 때 주는 목표.
public struct CareerGoal: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case hits, homeRuns, wins, strikeouts, appearances
        // 축구
        case goals, points, cleanSheets, matches
    }

    public var kind: Kind
    public var target: Int
    /// 시즌이 끝나고 채웠는지. 시즌 중에는 nil.
    public var achieved: Bool?

    public var label: String {
        switch kind {
        case .hits: "안타 \(target)개"
        case .homeRuns: "홈런 \(target)개"
        case .wins: "\(target)승"
        case .strikeouts: "탈삼진 \(target)개"
        case .appearances: "\(target)경기 등판"
        case .goals: "\(target)골"
        case .points: "공격 포인트 \(target)개 (골 + 도움)"
        case .cleanSheets: "무실점 \(target)경기"
        case .matches: "\(target)경기 출전"
        }
    }

    public func progress(of player: Player) -> Int {
        switch kind {
        case .hits: player.batting.hits
        case .homeRuns: player.batting.homeRuns
        case .wins: player.pitching.wins
        case .strikeouts: player.pitching.strikeouts
        case .appearances: player.pitching.games
        case .goals: player.football?.goals ?? 0
        case .points: player.football?.points ?? 0
        case .cleanSheets: player.football?.cleanSheets ?? 0
        case .matches: player.football?.games ?? 0
        }
    }
}

/// 끝난 시즌 하나의 기록.
public struct CareerSeason: Codable, Equatable, Sendable {
    public var season: Int
    public var age: Int
    public var teamName: String
    public var tier: LeagueTier
    public var batting: BattingLine
    public var pitching: PitchingLine
    /// 축구 선수의 시즌 기록. 야구 선수는 nil.
    public var football: FootballLine? = nil
    /// 평점이 매겨진 경기 수와 평점 합.
    public var ratedGames: Int
    public var ratingTotal: Double
    public var awards: [String]

    public var averageRating: Double? { ratedGames == 0 ? nil : ratingTotal / Double(ratedGames) }
}

/// 은퇴한 선수의 커리어 기록 (명예의 전당).
public struct CareerRecord: Codable, Equatable, Sendable {
    public var name: String
    public var position: Position
    public var firstSeason: Int
    public var lastSeason: Int
    public var retiredAge: Int
    public var clubs: [String]
    public var batting: BattingLine
    public var pitching: PitchingLine
    public var football: FootballLine? = nil
    public var ratedGames: Int
    public var ratingTotal: Double
    public var awards: [String]
    public var peakAbility: Double
    public var bestTier: LeagueTier
    public var earnings: Int
    /// 끝까지 치른 시즌 수. (예전 기록에는 없어서 시즌 번호로 어림한다.)
    public var seasonsPlayed: Int? = nil

    public var averageRating: Double? { ratedGames == 0 ? nil : ratingTotal / Double(ratedGames) }

    public var seasons: Int { seasonsPlayed ?? max(1, lastSeason - firstSeason + 1) }

    /// 명예의 전당에 적히는 칭호: 얼마나 높이 올라갔고 무엇을 받았는지로 정한다.
    public var honor: String {
        switch bestTier {
        case .pro: awards.isEmpty ? "1부 스타" : "전설"
        case .semiPro, .amateur: awards.isEmpty ? "프로 선수" : "프로 스타"
        default: awards.isEmpty ? "동네 스타" : "시민 리그의 영웅"
        }
    }
}

/// 선수 모드의 상태. 구단 모드에서는 `Game.career`가 nil이다.
public struct Career: Codable, Equatable, Sendable {
    public var playerID: PlayerID
    /// 감독 신뢰 (0~100).
    public var trust: Double
    /// 명성 (0~100).
    public var fame = 0.0
    /// 다음 경기까지 남은 훈련 횟수.
    public var sessionsLeft: Int
    /// 받은 연봉의 합.
    public var earnings = 0
    public var trainingCount = 0
    /// 지금 구단에 온 뒤 치른 경기 수.
    public var matchesAtClub = 0

    /// 직전 경기 평점과 한 줄 기록. 나오지 않았으면 nil.
    public var lastRating: Double?
    public var lastLine: String?
    /// 이번 시즌 평점 (정규시즌만).
    public var seasonRatedGames = 0
    public var seasonRatingTotal = 0.0
    /// 이번 시즌 기록을 `history`에 옮겼는지 (정규시즌이 끝나면 true, 새 시즌이 시작되면 false).
    public var seasonClosed = false

    public var history: [CareerSeason] = []
    public var clubs: [String] = []
    public var awards: [String] = []
    public var firstSeason: Int
    public var peakAbility = 0.0
    public var bestTier = LeagueTier.citizenAmateur

    public var offers: [CareerOffer] = []
    var nextOfferID = 1
    /// 이번 이적 기간에 이적을 요청했는지.
    public var transferRequested = false
    /// 무소속: 입단 제안 중 하나를 골라야 경기를 할 수 있다.
    public var isFreeAgent = false
    public var retired = false
    public var goal: CareerGoal?
    /// 축구: 경기 전에 고른 플레이 스타일. nil이면 균형.
    public var style: PlayStyle?
    /// 다음 경기의 컨디션. nil이면 보통. (이 아래 값들은 예전 저장 파일에 없어서 Optional이다.)
    public var condition: CareerCondition?
    /// 연속 활약(+) 또는 연속 부진(−) 경기 수.
    public var streak: Int?
    /// 연속 기록 (타자: 안타, 투수: 무자책, 축구: 공격포인트, 골키퍼: 무실점)과 개인 최고.
    public var run: Int?
    public var bestRun: Int?
    public var rival: CareerRival?
    /// 방금 한 훈련이 크리티컬이었으면 그 내용 한 줄. 다음 훈련이나 경기 뒤에 지워진다. (예전 저장 파일에는 없다.)
    public var lastCritical: String?
    /// 지금까지 터진 크리티컬 횟수.
    public var criticalCount: Int?
    /// 이번 경기 사이에 명성 활동을 했는지. (예전 저장 파일에는 없어서 Optional이다.)
    public var activityDone: Bool?
    /// 축구: 이번 경기에 선발이 아니면 교체로 들어갈 시간(분). 선발이거나 야구면 nil.
    var subMinute: Int?

    init(playerID: PlayerID, season: Int) {
        self.playerID = playerID
        self.trust = Balance.careerStartTrust
        self.sessionsLeft = Balance.careerSessionsPerMatch
        self.firstSeason = season
    }

    public var seasonAverageRating: Double? {
        seasonRatedGames == 0 ? nil : seasonRatingTotal / Double(seasonRatedGames)
    }
}

/// 능력치 하나를 올리는 훈련.
public enum CareerDrill {
    public static func name(_ key: Attributes.Key, sport: Sport = .baseball) -> String {
        if sport == .football {
            switch key {
            case .shooting: return "슈팅 연습"
            case .passing: return "패스 훈련"
            case .dribbling: return "드리블 훈련"
            case .tackling: return "수비 훈련"
            case .speed: return "스프린트"
            case .physical: return "웨이트 트레이닝"
            case .keeping: return "골키핑 훈련"
            case .stamina: return "러닝"
            default: return key.label
            }
        }
        switch key {
        case .contact: return "티 배팅"
        case .power: return "웨이트 트레이닝"
        case .eye: return "선구안 훈련"
        case .speed: return "주루 훈련"
        case .fielding: return "펑고"
        case .arm: return "롱토스"
        case .stuff: return "불펜 피칭"
        case .control: return "제구 훈련"
        case .breaking: return "변화구 연마"
        case .stamina: return "러닝"
        default: return key.label
        }
    }
}
