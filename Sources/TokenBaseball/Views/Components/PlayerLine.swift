import SwiftUI
import TokenBaseballCore

/// 선수 한 줄: 포지션, 이름, 나이, 능력. 목록에서 쓴다.
struct PlayerLine<Trailing: View>: View {
    enum Style {
        /// 작은 글씨로 "이름 (나이)"와 "등급 능력" (리그 탭의 선수단).
        case compact
        /// 보통 글씨로 이름, 나이, 능력 (커리어 탭의 팀 동료).
        case regular
    }

    let player: Player
    var style = Style.regular
    /// 내 선수처럼 눈에 띄어야 하는 줄.
    var highlighted = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        switch style {
        case .compact:
            HStack {
                PositionTag(position: player.position)
                Text("\(player.name) (\(player.age))").font(.caption)
                Spacer()
                Text("\(player.grade) \(Int(player.ability))").font(.caption.monospacedDigit())
                trailing
            }
        case .regular:
            HStack {
                PositionTag(position: player.position)
                Text(player.name).fontWeight(highlighted ? .bold : .regular)
                Text("\(player.age)세").note()
                Spacer()
                Text("\(Int(player.ability))").monospacedDigit()
                trailing
            }
            .font(.callout)
            .foregroundStyle(highlighted ? Color.accentColor : .primary)
        }
    }
}

extension PlayerLine where Trailing == EmptyView {
    init(player: Player, style: Style = .regular, highlighted: Bool = false) {
        self.init(player: player, style: style, highlighted: highlighted) { EmptyView() }
    }
}
