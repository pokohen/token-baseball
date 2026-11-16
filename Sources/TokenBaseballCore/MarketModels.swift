import Foundation

/// 다른 구단이 내 선수에게 보낸 오퍼. 다음 경기가 끝날 때까지 답하지 않으면 자동 거절된다.
public struct TransferOffer: Codable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var playerID: PlayerID
    public var fromTeam: TeamID
    public var fee: Int
    /// 트레이드면 상대가 내주는 선수.
    public var swapPlayerID: PlayerID?
    /// 금액을 올려 달라고 이미 한 번 했는지.
    public var raised = false
}

/// 내가 보낸 제안. 답은 다음 경기가 끝난 뒤에 온다.
public struct Proposal: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case freeAgent = "FA 영입", renewal = "재계약", transfer = "이적 제안"
    }

    public var id: Int
    public var kind: Kind
    public var playerID: PlayerID
    public var salary: Int
    public var years: Int
    /// 이적 제안일 때 상대 구단에 내는 이적료.
    public var fee: Int
}

/// 영입 후보 (입단 테스트, 스카우트, 드래프트).
public struct Candidate: Codable, Equatable, Identifiable, Sendable {
    public enum Source: String, Codable, Sendable {
        case tryout = "입단 테스트", scout = "스카우트", draft = "신인 드래프트"
    }

    public var id: Int
    public var playerID: PlayerID
    /// 계약금.
    public var fee: Int
    /// 몇 경기 뒤에 사라지는지.
    public var matchesLeft: Int
    public var source: Source
}

public enum ScoutRegion: String, Codable, CaseIterable, Sendable {
    case local = "연고지", national = "전국", overseas = "해외"

    var costFactor: Int {
        switch self {
        case .local: 2
        case .national: 5
        case .overseas: 15
        }
    }
}

public struct ScoutTrip: Codable, Equatable, Sendable {
    public var region: ScoutRegion
    public var matchesLeft: Int
    /// 보낼 때 낸 비용 (취소되면 돌려준다). 예전 저장 파일에는 없다.
    public var cost: Int?
}

public enum OfferResponse: Sendable {
    case accept, reject, askMore
}
