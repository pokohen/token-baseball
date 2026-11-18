import SwiftUI
import TokenBaseballCore

/// 커리어 탭: 훈련 포인트를 들여 명성을 올리는 활동. 경기 사이에 한 번.
struct CareerActivityCard: View {
    @EnvironmentObject var model: AppModel
    let game: Game
    let career: Career

    var body: some View {
        let cap = Balance.careerFameCap(game.userTier)
        return Card("명성 활동", trailing: "명성 \(Int(career.fame)) / 이 리그 한도 \(Int(cap))") {
            Text("훈련 포인트를 들여 명성을 올립니다. 경기 사이에 한 번 할 수 있고, 명성이 높을수록 더 큰 구단에서 제안이 옵니다.").note()
            ForEach(CareerActivity.allCases, id: \.self) { activity in
                let blocked = game.careerActivityBlockedReason(activity)
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(activity.label).font(.callout.weight(.medium))
                        Text(activity.detail).note()
                    }
                    Spacer()
                    Button("명성 +\(String(format: "%.1f", game.careerActivityGain(activity))) · \(Format.tokens(game.careerActivityCost(activity))) P") {
                        model.perform { try $0.doCareerActivity(activity) }
                    }
                    .disabled(blocked != nil)
                    .help(blocked ?? activity.detail)
                }
            }
            if let reason = CareerActivity.allCases.compactMap({ game.careerActivityBlockedReason($0) }).first,
               career.activityDone == true || career.isFreeAgent || career.fame >= cap {
                Text(reason).note()
            }
        }
    }
}
