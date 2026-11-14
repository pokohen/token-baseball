import AppKit
import SwiftUI
import TokenBaseballCore

@main
struct TokenBaseballApp: App {
    @StateObject private var model: AppModel

    init() {
        // Dock 아이콘 없이 상단바에만 뜨는 앱.
        NSApplication.shared.setActivationPolicy(.accessory)
        let model = AppModel()
        _model = StateObject(wrappedValue: model)
        if let directory = ProcessInfo.processInfo.environment["TOKEN_BASEBALL_SNAPSHOT"], !directory.isEmpty {
            Snapshot.renderAll(model: model, to: URL(fileURLWithPath: directory))
            exit(0)
        }
        model.start()
    }

    var body: some Scene {
        MenuBarExtra {
            RootView()
                .environmentObject(model)
                .frame(width: Theme.popoverWidth, height: Theme.popoverHeight)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

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
