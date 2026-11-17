import AppKit
import SwiftUI
import TokenBaseballCore

/// 상단바: 훈련 애니메이션 + 숫자 하나.
struct MenuBarLabel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 4) {
            if model.game?.settings.animationEnabled ?? true {
                Image(nsImage: Sprites.image(model.drill, frame: model.frame))
            }
            Text(model.menuBarText)
                .monospacedDigit()
        }
    }
}
