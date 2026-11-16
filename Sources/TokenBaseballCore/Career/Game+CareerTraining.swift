import Foundation

/// 선수 모드: 훈련 포인트(토큰)로 능력치를 올린다.
extension Game {
    // MARK: 훈련

    /// 훈련으로 올릴 수 있는 능력치 (내 포지션의 능력에 들어가는 것만).
    public var careerTrainableKeys: [Attributes.Key] {
        guard let me = myPlayer else { return [] }
        return Attributes.weights(for: me.position).map(\.0)
    }

    /// 훈련 한 번에 그 능력치가 오르는 양.
    /// 어떤 훈련이든 능력(CA)이 똑같이 오르도록, 포지션에서 덜 중요한 능력치일수록 많이 오른다.
    /// (그러지 않으면 능력치가 적은 투수·골키퍼가 야수·필드 선수보다 훨씬 빨리 큰다.)
    public func careerTrainingGain(_ key: Attributes.Key) -> Double {
        guard let me = myPlayer,
              let weight = Attributes.weights(for: me.position).first(where: { $0.0 == key })?.1, weight > 0
        else { return 0 }
        return min(Balance.careerTrainingStep / weight, 99 - me.attributes[key])
    }

    /// 훈련으로 올릴 수 있는 능력의 한도: 지금 리그 강도 범위의 위쪽 끝보다 조금 위. 1부는 한도가 없다.
    public var careerLeagueCeiling: Double? {
        guard isCareer, userTier != .pro else { return nil }
        return Balance.strengthRange(userTier).upperBound + Balance.careerLeagueHeadroom
    }

    /// 훈련 한 번에 드는 훈련 포인트. 지금 값이 높을수록, 한계에 가까울수록 비싸다.
    public func careerTrainingCost(_ key: Attributes.Key) -> Int {
        guard let me = myPlayer else { return 0 }
        var cost = Balance.careerTrainingCost(value: me.attributes[key])
        if me.potential - me.ability <= Balance.careerNearPotentialRoom { cost *= 2 }
        return price(cost)
    }

    /// 지금 이 훈련을 할 수 없는 이유. 할 수 있으면 nil.
    public func careerTrainingBlockedReason(_ key: Attributes.Key) -> String? {
        guard let career, !career.retired, let me = players[career.playerID] else { return "선수가 없습니다." }
        guard let weight = Attributes.weights(for: me.position).first(where: { $0.0 == key })?.1 else {
            return "이 포지션에서는 올릴 수 없는 능력치입니다."
        }
        if me.age >= Balance.careerTrainingAgeLimit(me.position) {
            return "\(Balance.careerTrainingAgeLimit(me.position))세부터는 훈련으로 능력치를 올릴 수 없습니다."
        }
        if career.sessionsLeft <= 0 { return "다음 경기를 치르면 다시 훈련할 수 있습니다." }
        if me.attributes[key] >= 99 { return "이미 최고치입니다." }
        if me.ability + Balance.careerTrainingStep > me.potential + 0.0001 {
            return "한계에 닿았습니다. 지금은 더 오르지 않습니다."
        }
        // 지금 리그 수준을 크게 넘으면 더 배울 것이 없다. 윗 리그로 올라가야 한다.
        if let ceiling = careerLeagueCeiling, me.ability >= ceiling {
            return "지금 리그에서는 더 오르지 않습니다 (능력 \(Int(ceiling))까지). 윗 리그로 올라가야 합니다."
        }
        _ = weight
        let cost = careerTrainingCost(key)
        if funds.balance < cost { return "훈련 포인트가 모자랍니다. \(Format.tokens(cost)) P가 필요합니다." }
        return nil
    }

    /// 훈련 포인트(토큰)를 써서 능력치 하나를 +1 올린다. 경기와 경기 사이에 세 번까지 할 수 있다.
    public mutating func trainCareer(_ key: Attributes.Key) throws {
        if let reason = careerTrainingBlockedReason(key) { throw GameError(reason) }
        guard var career, var me = players[career.playerID] else { return }
        funds.spend(careerTrainingCost(key), .training)
        me.attributes[key] = min(99, me.attributes[key] + careerTrainingGain(key))
        players[me.id] = me
        career.sessionsLeft -= 1
        career.trainingCount += 1
        // 꾸준히 훈련하면 감독도 조금씩 알아준다.
        career.trust = min(100, career.trust + 0.1)
        career.peakAbility = max(career.peakAbility, me.ability)
        self.career = career
    }

    /// 한계 돌파 훈련에 드는 훈련 포인트.
    public var careerBreakthroughCost: Int { price(Balance.careerBreakthroughCost) }

    public var careerBreakthroughBlockedReason: String? {
        guard let career, !career.retired, let me = players[career.playerID] else { return "선수가 없습니다." }
        if me.age >= Balance.careerTrainingAgeLimit(me.position) {
            return "\(Balance.careerTrainingAgeLimit(me.position))세부터는 한계를 넓힐 수 없습니다."
        }
        if career.sessionsLeft <= 0 { return "다음 경기를 치르면 다시 훈련할 수 있습니다." }
        if me.potential >= 99 { return "더 넓힐 한계가 없습니다." }
        if funds.balance < careerBreakthroughCost {
            return "훈련 포인트가 모자랍니다. \(Format.tokens(careerBreakthroughCost)) P가 필요합니다."
        }
        return nil
    }

    /// 한계 돌파 훈련: 큰 포인트를 들여 잠재력(능력의 한계)을 +1 넓힌다. 훈련 횟수를 한 번 쓴다.
    public mutating func breakThroughCareer() throws {
        if let reason = careerBreakthroughBlockedReason { throw GameError(reason) }
        guard var career, var me = players[career.playerID] else { return }
        funds.spend(careerBreakthroughCost, .training)
        me.potential = min(99, me.potential + 1)
        players[me.id] = me
        career.sessionsLeft -= 1
        career.trainingCount += 1
        self.career = career
    }
}
