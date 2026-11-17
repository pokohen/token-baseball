import SwiftUI
import TokenBaseballCore

/// 다른 저장 칸(구단 모드, 선수 모드)으로 옮기는 버튼들.
struct SlotSwitcher: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(model.selectableSlots.filter { $0 != model.slot }, id: \.self) { slot in
                HStack {
                    Text("\(slot.sport.symbol) \(slot.label)")
                    Text(model.hasSave(slot: slot) ? "저장되어 있음" : "아직 없음").note()
                    Spacer()
                    Button(model.hasSave(slot: slot) ? "이어서 하기" : "새로 만들기") { model.switchSlot(to: slot) }
                }
            }
            Text("모드마다 따로 저장됩니다. 한 번에 하나만 진행하고, 쉬는 쪽은 그동안 쓴 토큰을 받지 않으며 경기 기회도 쌓이지 않습니다.").note()
            Toggle("구단 경영 모드 보이기 (준비 중)", isOn: $model.showsClubModes)
            if !model.showsClubModes {
                Text("지금은 선수 키우기를 먼저 다듬고 있습니다. 구단 경영(야구 구단, 축구 구단)은 켜면 고를 수 있지만 아직 덜 다듬어져 있습니다.").note()
            }
        }
        .font(.callout)
    }
}
