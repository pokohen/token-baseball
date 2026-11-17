import AppKit
import SwiftUI
import TokenBaseballCore

@main
struct TokenBaseballApp: App {
    @StateObject private var model: AppModel

    init() {
        // Dock 아이콘 없이 상단바에만 뜨는 앱.
        NSApplication.shared.setActivationPolicy(.accessory)
        if let directory = ProcessInfo.processInfo.environment["TOKEN_BASEBALL_SELFTEST"], !directory.isEmpty {
            exit(SelfTest.run(in: URL(fileURLWithPath: directory)) ? 0 : 1)
        }
        if ProcessInfo.processInfo.environment["TOKEN_BASEBALL_CHECK_UPDATE"] != nil {
            // 새 버전 확인만 하고 끝낸다 (확인용).
            Task.detached {
                switch await UpdateChecker.check() {
                case .upToDate: print("최신 버전입니다.")
                case .available(let update):
                    print("새 버전이 있습니다 (변경 \(update.count)건).")
                    update.titles.forEach { print("· \($0)") }
                case .unknown(let reason): print(reason)
                }
                exit(0)
            }
            RunLoop.main.run()
        }
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
