import AppKit
import SwiftUI
import TokenBaseballCore

/// 상단바: 훈련 애니메이션 + 숫자 하나.
struct MenuBarLabel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        // 경기 중·경기 종료 표시에는 글자 앞에 공 그림 문자가 붙어 온다. 그 자리에 도트 공을 그린다.
        let text = model.menuBarText
        let sport = model.game?.sport ?? model.sport
        let marked = text.hasPrefix(sport.symbol + " ")
        HStack(spacing: 4) {
            if marked || !(model.game?.settings.animationEnabled ?? true) {
                // 훈련 애니메이션을 껐거나 경기 중이면 공이 나온다.
                Image(nsImage: BallSprite.menuBarImage(sport))
            } else {
                Image(nsImage: Sprites.image(model.drill, frame: model.frame))
            }
            Text(marked ? String(text.dropFirst(sport.symbol.count + 1)) : text)
                .monospacedDigit()
        }
    }
}
