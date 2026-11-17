import SwiftUI
import TokenBaseballCore

/// 은퇴한 뒤: 커리어 기록을 보여 주고 같은 세계에서 새 선수를 만든다.
struct CareerRetiredView: View {
    @EnvironmentObject var model: AppModel
    let game: Game
    @State private var setup = CareerSetup(name: "", position: .shortstop)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("은퇴").font(.title2.bold())
                if let record = game.careerHall?.last { CareerRecordCard(record: record) }
                Card("새 선수") {
                    Text("같은 세계에서 새 선수로 다시 시작합니다. 은퇴한 선수의 기록은 기록실에 남습니다.").note()
                    CareerForm(setup: $setup, sport: game.sport)
                    Button("새 커리어 시작") { model.createCareer(setup) }
                        .buttonStyle(.borderedProminent)
                }
                if let message = model.message {
                    Text(message).font(.callout).foregroundStyle(Theme.loss)
                }
                Card("다른 모드") { SlotSwitcher() }
            }
            .padding(16)
        }
    }
}
