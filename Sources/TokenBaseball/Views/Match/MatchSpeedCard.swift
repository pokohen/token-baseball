import SwiftUI
import TokenBaseballCore

/// 중계 배속 고르기. 경기 도중에도 바꿀 수 있다.
struct MatchSpeedCard: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Card {
            HStack {
                Text("배속").font(.callout).foregroundStyle(.secondary)
                Picker("배속", selection: $model.matchSpeed) {
                    ForEach(AppModel.matchSpeeds, id: \.self) { Text("\($0)×").tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }
}
