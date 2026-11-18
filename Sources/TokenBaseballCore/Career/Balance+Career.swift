import Foundation

/// 선수 모드에서 조정할 수 있는 수치.
extension Balance {
    public static let careerStartAge = 16
    /// 내 선수의 잠재력. 숨겨져 있다.
    public static let careerPotential = 75.0...90.0
    /// 6부 리그 열 구단 중 몇 번째 구단에 입단하는지 (0이 가장 강한 구단).
    public static let careerStartSlot = 5
    public static let careerStartTrust = 40.0
    /// 경기와 경기 사이에 할 수 있는 훈련 횟수.
    public static let careerSessionsPerMatch = 5
    /// 이 나이부터는 훈련으로 능력치를 올릴 수 없다.
    public static let careerTrainingAgeLimit = 31
    /// 포지션별 훈련 한도 나이: 성장이 멈추는 나이와 같다.
    public static func careerTrainingAgeLimit(_ position: Position) -> Int {
        position == .goalkeeper ? 32 : position.sport == .football ? 29 : careerTrainingAgeLimit
    }
    public static func careerForcedRetirementAge(_ position: Position) -> Int {
        careerForcedRetirementAge + (position == .goalkeeper ? 3 : 0)
    }
    public static let careerVoluntaryRetirementAge = 30
    public static let careerForcedRetirementAge = 38
    /// 잠재력까지 남은 여유가 이 값 이하면 훈련 비용이 두 배가 된다.
    public static let careerNearPotentialRoom = 10.0
    /// 감독 신뢰가 이 값 이상이어야 구단이 재계약을 제안한다.
    public static let careerRenewalTrust = 30.0
    public static let careerFameAward = 8.0
    /// 한계 돌파 훈련: 잠재력을 +1 올리는 데 드는 훈련 포인트.
    public static let careerBreakthroughCost = 30_000_000
    /// 구단을 옮긴 뒤 이 경기 수가 지나야 다른 구단의 제안이 다시 온다.
    public static let careerOfferCooldown = 10
    /// 축구 평점의 포지션별 기준 보정. 시뮬레이션으로 맞춘다.
    public static func careerFootballBaseline(_ position: Position) -> Double {
        switch position {
        case .goalkeeper: 0.1
        case .defender: 0.0
        case .midfielder: -0.1
        default: 0.2
        }
    }
    /// 축구: 주전이 아닌 골키퍼는 이 경기 수마다 한 번 선발로 나온다.
    public static let careerKeeperRotation = 4
    /// 축구: 선발이 아닐 때 교체로 들어가는 시간(분). 감독 신뢰가 높을수록 일찍 들어간다 (신뢰 20이면 80분, 60이면 60분).
    public static func careerSubMinute(trust: Double) -> Int {
        Int(clamp(90 - trust * 0.5, 50, 85))
    }
    /// 훈련하지 않아도 저절로 크는 정도 (다른 선수의 성장에 곱하는 값).
    public static let careerNaturalGrowth = 0.3
    /// 훈련 한 번에 오르는 능력(CA).
    public static let careerTrainingStep = 0.25
    /// 훈련이 "크리티컬"로 터질 확률과, 터졌을 때 오르는 양의 배수. 포인트는 똑같이 든다.
    public static let careerCriticalChance = 0.01
    public static let careerCriticalMultiplier = 3.0
    /// 훈련으로는 지금 리그 강도 범위의 위쪽 끝 + 이 값까지만 오른다.
    public static let careerLeagueHeadroom = 5.0

    /// 능력치 하나를 +1 올리는 데 드는 훈련 포인트.
    /// 훈련할 때마다 그 능력치의 다음 비용이 6%쯤 오른다 (25에서 25만, 50에서 116만, 70에서 397만, 85에서 1,000만).
    public static func careerTrainingCost(value: Double) -> Int {
        let cost = 250_000 * exp((value - 25) * 0.0615)
        return max(100_000, Int(cost / 10_000) * 10_000)
    }

    /// 그 리그에서 뛰는 동안 명성이 오를 수 있는 한도.
    public static func careerFameCap(_ tier: LeagueTier) -> Double {
        switch tier {
        case .citizenAmateur: 20
        case .citizenSemiPro: 30
        case .citizenPro: 40
        case .amateur: 55
        case .semiPro: 75
        case .pro: 100
        }
    }
}
