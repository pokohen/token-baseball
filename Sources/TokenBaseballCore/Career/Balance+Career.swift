import Foundation

/// 선수 모드에서 조정할 수 있는 수치.
extension Balance {
    // 컵대회

    /// 1라운드를 쉬는 구단 수 (1부에서 강한 순서로): 1라운드가 끝나면 32팀이나 64팀이 남게 맞춘다 (60팀이면 4, 120팀이면 8).
    public static func cupByes(entrants: Int) -> Int {
        var bracket = 1
        while bracket * 2 <= entrants { bracket *= 2 }
        return bracket == entrants ? 0 : bracket * 2 - entrants
    }
    /// 컵 라운드가 열리는 때: 리그를 이만큼 치른 뒤.
    /// 여섯 라운드 대회(60팀: 1라운드, 32강, 16강, 8강, 준결승, 결승)와 일곱 라운드 대회(120팀: 64강이 더 있다).
    public static func cupAfterRounds(total: Int) -> [Int] {
        total >= 7 ? [3, 8, 13, 18, 23, 29, 35] : [4, 10, 16, 22, 28, 33]
    }
    /// 컵 경기에서 이겨 올라갈 때 오르는 명성, 윗 리그 구단을 잡으면 리그 차이 하나마다 더 오르는 명성.
    public static let cupWinFame = 1.0
    public static let cupUpsetFame = 2.0
    public static let cupChampionFame = 12.0
    public static let cupRunnerUpFame = 5.0
    public static let cupChampionTrust = 5.0

    // 컨디션, 기세, 라이벌, 실전 경험

    /// 평점이 이 값 이상이면 "활약", 이 값 이하면 "부진"으로 센다.
    public static let careerStreakGood = 7.0
    public static let careerStreakBad = 5.5
    /// 이 경기 수만큼 이어지면 기세(또는 슬럼프)가 붙는다.
    public static let careerStreakLength = 3
    /// 기세가 능력치에 주는 변화 (0.02 = 2%).
    public static let careerMomentum = 0.02
    /// 기세가 붙어 있을 때 경기로 얻는 명성의 배수.
    public static let careerMomentumFame = 1.25
    /// 라이벌은 내 능력보다 이만큼 높은 선수에 가장 가까운 선수로 고른다.
    public static let careerRivalEdge = 2.0
    /// 라이벌은 나보다 이 나이 차이 안쪽의 또래를 먼저 고른다.
    public static let careerRivalAgeGap = 6
    /// 새 시즌에 내가 이만큼 넘게 앞서 있으면 라이벌을 바꾼다.
    public static let careerRivalOutgrown = 5.0
    /// 라이벌과의 맞대결에서 이기면 오르는 명성.
    public static let careerRivalFame = 1.0
    /// 토큰으로 치른 경기에서 얻는 능력: 기본 + (평점 − 6) × 평점당, 최대까지.
    public static let careerExtraMatchBase = 0.05
    public static let careerExtraMatchPerRating = 0.08
    public static let careerExtraMatchMax = 0.3

    public static let careerStartAge = 16
    /// 내 선수의 타고난 재능: 시작 능력과 잠재력(성장 한계)이 선수마다 이 범위에서 다르게 정해진다.
    /// 잠재력의 숫자는 숨겨져 있고, 재능 등급으로만 알려 준다.
    public static let careerStartAbility = 15.0...30.0
    public static let careerPotential = 68.0...95.0
    /// 선수를 만들 때 직접 나눠 넣는 시작 포인트의 수와, 포인트 하나에 오르는 능력치.
    public static let careerStartPoints = 5
    public static let careerStartPointValue = 3.0
    /// 능력치 하나에 넣을 수 있는 시작 포인트. 비중이 큰 능력치 하나(골키퍼의 골키핑 등)에 몰아넣어
    /// 포지션마다 시작 능력이 크게 벌어지는 것을 막는다 (다섯 개를 가장 좋게 넣으면 능력 +3.5 ~ +5.4).
    public static let careerStartPointsPerStat = 2
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
    /// 스스로 은퇴하려면 끝까지 치른 시즌이 이만큼 있어야 한다.
    public static let careerRetireMinSeasons = 1
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
    /// 추가 훈련(설정에서 켠다): 정해진 횟수를 넘긴 훈련은 한 번마다 비용이 이 배수만큼 더 든다 (1.5배, 2.25배, 3.4배…).
    public static let careerExtraSessionCost = 1.5

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
