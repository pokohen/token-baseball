import Foundation

/// 조정할 수 있는 수치를 한곳에 모았다. 문서의 💡 수치와, 문서에 "…"로 비어 있던 칸을 채운 값이다.
public enum Balance {
    // MARK: 리그

    public static let teamsPerLeague = 10
    public static let roundsPerSeason = 36
    /// 승강 플레이오프 신청 마감 라운드.
    public static let applicationDeadlineRound = 27
    /// 시즌 중 트레이드 마감 (이 라운드까지 가능).
    public static let tradeDeadlineRound = 24
    public static let friendliesPerOffseason = 5
    /// 신인 드래프트는 친선 몇 경기 뒤에 여는지.
    public static let draftAfterFriendly = 3

    /// 새로 생성되는 선수의 능력 범위.
    public static func abilityRange(_ tier: LeagueTier) -> ClosedRange<Double> {
        switch tier {
        case .citizenAmateur: 15...35
        case .citizenSemiPro: 25...45
        case .citizenPro: 35...55
        case .amateur: 45...65
        case .semiPro: 55...72
        case .pro: 62...90
        }
    }

    /// 잠재력 = 능력 + 0...이 값.
    public static func potentialBonus(_ tier: LeagueTier) -> Double {
        switch tier {
        case .citizenAmateur: 10
        case .citizenSemiPro: 12
        case .citizenPro: 15
        case .amateur: 20
        case .semiPro: 20
        case .pro: 15
        }
    }

    public static func ageRange(_ tier: LeagueTier) -> ClosedRange<Int> {
        switch tier {
        case .citizenAmateur: 20...45
        case .citizenSemiPro: 20...40
        case .citizenPro: 19...37
        case .amateur: 19...33
        case .semiPro: 19...34
        case .pro: 19...36
        }
    }

    /// 리그별 팀 강도 범위.
    public static func strengthRange(_ tier: LeagueTier) -> ClosedRange<Double> {
        switch tier {
        case .citizenAmateur: 20...40
        case .citizenSemiPro: 30...50
        case .citizenPro: 40...60
        case .amateur: 50...70
        case .semiPro: 60...80
        case .pro: 70...92
        }
    }

    /// 승격에 필요한 인지도 (이 리그에서 위 리그로).
    public static func requiredFame(from tier: LeagueTier) -> Double {
        switch tier {
        case .citizenAmateur: 100
        case .citizenSemiPro: 300
        case .citizenPro: 700
        case .amateur: 1_500
        case .semiPro: 3_000
        case .pro: 0
        }
    }

    /// 승강 플레이오프 신청비.
    public static func applicationFee(from tier: LeagueTier) -> Int {
        switch tier {
        case .citizenAmateur: 1_000_000
        case .citizenSemiPro: 5_000_000
        case .citizenPro: 20_000_000
        case .amateur: 80_000_000
        case .semiPro: 300_000_000
        case .pro: 0
        }
    }

    // MARK: 로스터

    public static func rosterLimit(_ tier: LeagueTier, sport: Sport = .baseball) -> Int {
        if sport == .football {
            switch tier {
            case .pro: return 28
            case .semiPro, .amateur: return 24
            default: return 20
            }
        }
        switch tier {
        case .pro: return 28
        case .semiPro, .amateur: return 22
        default: return 18
        }
    }

    /// 새 팀을 만들 때의 (야수, 선발, 불펜) 수. 불펜 중 한 명은 마무리다.
    public static func rosterShape(_ tier: LeagueTier) -> (batters: Int, starters: Int, relievers: Int) {
        switch tier {
        case .pro: (15, 5, 8)
        case .semiPro, .amateur: (12, 5, 5)
        default: (9, 3, 2)
        }
    }

    /// 축구 CPU 구단의 포지션별 인원.
    public static func footballShape(
        _ tier: LeagueTier
    ) -> (keepers: Int, defenders: Int, midfielders: Int, forwards: Int) {
        switch tier {
        case .pro: (3, 8, 9, 6)
        case .semiPro, .amateur: (3, 7, 7, 5)
        default: (2, 5, 5, 4)
        }
    }

    /// 축구: 이 인원 아래로 내려가면 빈자리를 자동으로 채운다.
    public static let footballMinSquad = 14
    public static let footballStarters = 11
    public static let footballMaxSubs = 5

    public static let minBatters = 9
    public static let minPitchers = 5
    /// 선발 투수가 다시 선발로 나오기까지 쉬는 경기 수.
    public static func starterRest(_ tier: LeagueTier) -> Int { tier.isCitizen ? 2 : 4 }
    public static let foreignPlayerLimit = 3

    // MARK: 시설

    public static let maxFacilityLevel = 10
    public static let trainingNames = [
        "동네 공터", "학교 운동장 대여", "실내 연습장", "전용 훈련장", "웨이트장 추가",
        "비디오 분석실", "2군 전용 구장", "재활·회복 센터", "데이터 랩", "첨단 퍼포먼스 센터",
    ]
    public static let trainingMultiplier = [1.0, 1.1, 1.2, 1.35, 1.5, 1.7, 1.9, 2.1, 2.3, 2.5]
    /// 레벨 n → n+1 업그레이드 비용 (index 0 = Lv1 → Lv2).
    public static let trainingCost = [
        10_000_000, 30_000_000, 80_000_000, 200_000_000, 400_000_000,
        800_000_000, 1_500_000_000, 3_000_000_000, 6_000_000_000,
    ]

    public static let stadiumNames = [
        "동네 야구장", "간이 관중석", "구립 야구장", "시립 야구장", "외야석 증축",
        "조명탑 설치", "종합운동장 야구장", "전용 야구장", "신축 야구장", "돔구장",
    ]
    public static let footballTrainingNames = [
        "동네 풋살장", "학교 운동장 대여", "인조잔디 연습장", "전용 훈련장", "웨이트장 추가",
        "비디오 분석실", "2군 전용 구장", "재활·회복 센터", "데이터 랩", "첨단 퍼포먼스 센터",
    ]
    public static let footballStadiumNames = [
        "동네 운동장", "간이 관중석", "구립 축구장", "시립 축구장", "관중석 증축",
        "조명탑 설치", "종합운동장", "전용 축구 경기장", "신축 경기장", "대형 전용 구장",
    ]
    public static func trainingNames(_ sport: Sport) -> [String] {
        sport == .football ? footballTrainingNames : trainingNames
    }
    public static func stadiumNames(_ sport: Sport) -> [String] {
        sport == .football ? footballStadiumNames : stadiumNames
    }

    public static let stadiumCapacity = [100, 500, 2_000, 5_000, 8_000, 12_000, 15_000, 18_000, 22_000, 25_000]
    /// 홈 보정 (0.01 = +1%).
    public static let stadiumHomeEdge = [0.01, 0.015, 0.02, 0.025, 0.03, 0.035, 0.04, 0.045, 0.0475, 0.05]
    public static let stadiumCost = [
        15_000_000, 50_000_000, 150_000_000, 300_000_000, 600_000_000,
        1_200_000_000, 2_500_000_000, 5_000_000_000, 10_000_000_000,
    ]
    /// 경기장 레벨이 오를 때 받는 인지도 (도달한 레벨 × 이 값).
    public static let stadiumFamePerLevel = 20.0

    public static let maxScoutLevel = 5
    /// 스카우트 시설 Lv0 → Lv1 ... 비용.
    public static let scoutCost = [5_000_000, 20_000_000, 60_000_000, 200_000_000, 500_000_000]

    // MARK: 수입

    public static func ticketPrice(_ tier: LeagueTier) -> Int {
        switch tier {
        case .citizenAmateur: 500
        case .citizenSemiPro: 800
        case .citizenPro: 1_200
        case .amateur: 2_000
        case .semiPro: 3_500
        case .pro: 6_000
        }
    }

    /// 관중 비율: 리그별 필요 인지도 대비 내 인지도로 정한다.
    public static func attendanceRatio(fame: Double, tier: LeagueTier) -> Double {
        let reference = max(100, requiredFame(from: tier == .pro ? .semiPro : tier))
        return clamp(0.15 + 0.7 * fame / reference, 0.15, 1.0)
    }

    /// 스폰서: 경기마다 인지도 1당 받는 금액.
    public static func sponsorPerFame(_ tier: LeagueTier) -> Int {
        switch tier {
        case .citizenAmateur: 300
        case .citizenSemiPro: 600
        case .citizenPro: 1_200
        case .amateur: 3_000
        case .semiPro: 8_000
        case .pro: 20_000
        }
    }

    /// 시즌 순위 상금 (1위 기준). 순위가 내려갈수록 줄고 6위부터는 없다.
    public static func prizeMoney(_ tier: LeagueTier, rank: Int) -> Int {
        let top: Int
        switch tier {
        case .citizenAmateur: top = 2_000_000
        case .citizenSemiPro: top = 6_000_000
        case .citizenPro: top = 20_000_000
        case .amateur: top = 80_000_000
        case .semiPro: top = 300_000_000
        case .pro: top = 1_000_000_000
        }
        let share = [1.0, 0.6, 0.4, 0.25, 0.15]
        return rank >= 1 && rank <= share.count ? Int(Double(top) * share[rank - 1]) : 0
    }

    /// 승격 지원금 (올라간 리그 기준).
    public static func promotionGrant(to tier: LeagueTier) -> Int {
        prizeMoney(tier, rank: 1) / 2 + 3_000_000
    }

    /// CPU 구단의 경기당 기본 수입.
    public static func cpuIncomePerMatch(_ tier: LeagueTier) -> Int {
        switch tier {
        case .citizenAmateur: 300_000
        case .citizenSemiPro: 900_000
        case .citizenPro: 2_500_000
        case .amateur: 8_000_000
        case .semiPro: 25_000_000
        case .pro: 80_000_000
        }
    }

    // MARK: 연봉과 이적료

    /// 능력에 맞는 시즌 연봉 (시장가).
    public static func marketSalary(ability: Double) -> Int {
        let perMatch = 40 * exp(ability * 0.13)
        let season = perMatch * Double(roundsPerSeason)
        return max(10_000, Int(season / 1_000) * 1_000)
    }

    /// 이적료 시장가.
    public static func transferValue(ability: Double, potential: Double, age: Int) -> Int {
        let ageFactor: Double = age <= 24 ? 1.5 : age <= 29 ? 1.2 : age <= 32 ? 0.8 : 0.4
        let upside = 1 + max(0, potential - ability) * 0.03
        return Int(Double(marketSalary(ability: ability)) * 2.5 * ageFactor * upside / 1_000) * 1_000
    }

    public static let raiseBase = 0.03...0.05
    public static let raiseMaxBonus = 0.20

    // MARK: 인지도

    public static let fameWin = 3.0
    public static let fameDraw = 1.0
    /// 3연승부터 승리마다 추가.
    public static let fameWinStreakBonus = 1.0
    /// 5연패부터 패배마다 감소.
    public static let fameLosingStreakPenalty = 2.0
    public static let fameSeasonDecay = 0.10
    public static let fameRelegationDrop = 0.30
    public static let fameAward = 30.0
    public static func famePromotion(to tier: LeagueTier) -> Double { requiredFame(from: tier.lower ?? tier) * 0.3 }
    public static let fameFriendlyUpset = 2.0
    public static let fameFranchiseStar = 200.0

    // MARK: 성장

    /// 틱(경기 한 번)마다의 기본 성장 포인트.
    public static let growthBase = 0.5
    public static func ageGrowthFactor(_ age: Int) -> Double {
        switch age {
        case ...22: 1.5
        case 23...26: 1.0
        case 27...30: 0.4
        default: 0
        }
    }
    public static let playFactorStarter = 1.2
    public static let playFactorSub = 1.0
    public static let playFactorBench = 0.6
    public static let friendlyGrowthFactor = 0.5
    /// 은퇴를 생각하기 시작하는 나이.
    public static func retirementAge(_ tier: LeagueTier) -> Int { tier.isCitizen ? 42 : 34 }
    public static let declineStartAge = 34

    // MARK: 선수 모드

    public static let careerStartAge = 16
    /// 내 선수의 잠재력. 숨겨져 있다.
    public static let careerPotential = 75.0...90.0
    /// 6부 리그 열 구단 중 몇 번째 구단에 입단하는지 (0이 가장 강한 구단).
    public static let careerStartSlot = 5
    public static let careerStartTrust = 40.0
    /// 경기와 경기 사이에 할 수 있는 훈련 횟수.
    public static let careerSessionsPerMatch = 2
    /// 이 나이부터는 훈련으로 능력치를 올릴 수 없다.
    public static let careerTrainingAgeLimit = 31
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
    /// 훈련하지 않아도 저절로 크는 정도 (다른 선수의 성장에 곱하는 값).
    public static let careerNaturalGrowth = 0.3

    /// 능력치 하나를 +1 올리는 데 드는 훈련 포인트.
    /// 훈련할 때마다 그 능력치의 다음 비용이 6%쯤 오른다 (25에서 25만, 50에서 116만, 70에서 397만, 85에서 1,000만).
    public static func careerTrainingCost(value: Double) -> Int {
        let cost = 250_000 * exp((value.rounded(.down) - 25) * 0.0615)
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

    // MARK: 재정 위기

    public static let bankruptcyGraceMatches = 5
    public static let warningMatches = 5

    // MARK: 경기 기회

    public static let matchChargeInterval: TimeInterval = 60 * 60
    public static let maxMatchCharges = 3

    // MARK: 영입

    public static func tryoutFee(_ tier: LeagueTier) -> Int {
        switch tier {
        case .citizenAmateur: 200_000
        case .citizenSemiPro: 600_000
        case .citizenPro: 2_000_000
        case .amateur: 6_000_000
        case .semiPro: 20_000_000
        case .pro: 60_000_000
        }
    }
}
