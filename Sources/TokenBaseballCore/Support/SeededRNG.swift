import Foundation

/// 시드를 넣으면 항상 같은 순서로 난수를 내는 생성기 (SplitMix64).
/// 시뮬레이션에서는 시스템 난수를 쓰지 않고 이것만 쓴다. 같은 시드면 같은 결과가 나와야 하기 때문이다.
public struct SeededRNG: Codable, Equatable, Sendable {
    public private(set) var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 0 이상 1 미만.
    public mutating func unit() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    public mutating func chance(_ probability: Double) -> Bool {
        unit() < probability
    }

    public mutating func int(_ range: ClosedRange<Int>) -> Int {
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % span)
    }

    public mutating func double(_ range: ClosedRange<Double>) -> Double {
        range.lowerBound + unit() * (range.upperBound - range.lowerBound)
    }

    /// 평균 0, 표준편차 1인 정규분포.
    public mutating func gaussian() -> Double {
        let u1 = max(unit(), 1e-12)
        let u2 = unit()
        return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }

    public mutating func pick<T>(_ items: [T]) -> T {
        items[int(0...(items.count - 1))]
    }

    /// 가중치에 비례해 인덱스를 고른다.
    public mutating func weighted(_ weights: [Double]) -> Int {
        let total = weights.reduce(0, +)
        var roll = unit() * total
        for (index, weight) in weights.enumerated() {
            roll -= weight
            if roll < 0 { return index }
        }
        return weights.count - 1
    }

    public mutating func shuffled<T>(_ items: [T]) -> [T] {
        var result = items
        guard result.count > 1 else { return result }
        for i in stride(from: result.count - 1, to: 0, by: -1) {
            result.swapAt(i, int(0...i))
        }
        return result
    }

    /// 독립된 흐름을 하나 떼어 낸다 (경기마다 시드를 따로 주기 위해).
    public mutating func fork() -> SeededRNG {
        SeededRNG(seed: next())
    }
}

func clamp<T: Comparable>(_ value: T, _ low: T, _ high: T) -> T {
    min(max(value, low), high)
}
