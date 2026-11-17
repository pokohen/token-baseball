import SwiftUI
import TokenBaseballCore

/// 구단 엠블럼: 팀 색 동그라미에 문양.
struct EmblemView: View {
    let team: Team
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            Circle().fill(Theme.color(team))
            Image(systemName: Theme.emblem(team))
                .font(.system(size: size * 0.48, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}
