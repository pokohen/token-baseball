import SwiftUI
import TokenBaseballCore

struct CareerTrainingTab: View {
    @EnvironmentObject var model: AppModel
    let game: Game

    var body: some View {
        VStack(spacing: 10) {
            if let career = game.career, let me = game.myPlayer {
                Card("훈련", trailing: "남은 횟수 \(career.sessionsLeft)/\(Balance.careerSessionsPerMatch)") {
                    KeyValueRow(key: "훈련 포인트", value: "\(game.funds.balance.formatted()) P")
                    Divider()
                    ForEach(game.careerTrainableKeys, id: \.self) { key in
                        drillRow(key, me)
                    }
                    Text(trainingNote(career, me)).note().fixedSize(horizontal: false, vertical: true)
                }

                Card("한계 돌파 훈련") {
                    Text("큰 포인트를 들여 능력의 한계를 조금 넓힙니다. 능력치가 더 오르지 않을 때 씁니다. 훈련 횟수를 한 번 씁니다.").note()
                    HStack {
                        Text("한계 +1").font(.callout)
                        Spacer()
                        Button("\(Format.tokens(game.careerBreakthroughCost)) P") {
                            model.perform { try $0.breakThroughCareer() }
                        }
                        .disabled(game.careerBreakthroughBlockedReason != nil)
                    }
                    if let reason = game.careerBreakthroughBlockedReason { Text(reason).note() }
                }

                Card("내 선수") {
                    KeyValueRow(key: "능력", value: "\(Int(me.ability)) (\(me.grade))")
                    KeyValueRow(key: "시즌 시작 때보다", value: String(format: "%+.1f", me.ability - me.abilityAtSeasonStart))
                    KeyValueRow(key: "최고 능력", value: "\(Int(career.peakAbility))")
                    KeyValueRow(key: "지금까지 훈련", value: "\(career.trainingCount)회")
                    Text("어떤 훈련이든 능력은 같은 양만큼 오릅니다. 훈련하지 않아도 경기를 뛰면 조금씩 큽니다. \(Balance.declineStartAge(me.position))세부터는 시즌마다 능력치가 크게 떨어집니다.").note()
                }
            }
        }
    }

    private func drillRow(_ key: Attributes.Key, _ me: Player) -> some View {
        let value = me.attributes[key]
        let blocked = game.careerTrainingBlockedReason(key)
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(CareerDrill.name(key, sport: game.sport)).font(.callout.weight(.medium))
                Text("\(label(key)) \(String(format: "%.1f", value))").note()
            }
            .frame(width: 118, alignment: .leading)
            Bar(fraction: value / 99, color: .accentColor)
            Button("+\(String(format: "%.1f", game.careerTrainingGain(key))) · \(Format.tokens(game.careerTrainingCost(key))) P") {
                model.perform { try $0.trainCareer(key) }
            }
            .disabled(blocked != nil)
            .help(blocked ?? "\(label(key)) +\(String(format: "%.1f", game.careerTrainingGain(key)))")
        }
    }

    /// 주력과 스피드는 같은 능력치다. 종목에 맞는 이름으로 보여 준다.
    private func label(_ key: Attributes.Key) -> String {
        game.sport == .football && key == .speed ? "스피드" : key.label
    }

    private func trainingNote(_ career: Career, _ me: Player) -> String {
        if me.age >= Balance.careerTrainingAgeLimit(me.position) {
            return "\(Balance.careerTrainingAgeLimit(me.position))세부터는 훈련으로 능력치를 올릴 수 없습니다."
        }
        if let ceiling = game.careerLeagueCeiling, me.ability >= ceiling {
            return "지금 리그에서 배울 수 있는 만큼 다 배웠습니다 (능력 \(Int(ceiling))). 윗 리그 구단으로 옮기거나 구단이 승격하면 다시 훈련할 수 있습니다."
        }
        if career.sessionsLeft <= 0 { return "오늘 훈련을 마쳤습니다. 다음 경기를 치르면 다시 \(Balance.careerSessionsPerMatch)번 훈련할 수 있습니다." }
        return "경기와 경기 사이에 \(Balance.careerSessionsPerMatch)번까지 훈련합니다. 어떤 훈련이든 능력이 \(Balance.careerTrainingStep)씩 오르고, 그 능력치가 높을수록 포인트가 많이 듭니다. 쓰지 않은 포인트는 그대로 남습니다."
    }
}
