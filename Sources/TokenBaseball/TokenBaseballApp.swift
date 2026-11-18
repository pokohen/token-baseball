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
        if ProcessInfo.processInfo.environment["TOKEN_BASEBALL_SELF_UPDATE"] != nil {
            // 화면 없이 앱 안 업데이트를 끝까지 해 본다 (확인용). 바꾼 뒤 다시 열지는 않는다.
            Task.detached {
                guard case .available(let update) = await UpdateChecker.check(), let version = update.version,
                      let download = update.download, let app = Updater.installedApp else {
                    print("업데이트할 것이 없습니다."); exit(0)
                }
                if let reason = Updater.blockedReason() { print("할 수 없음: \(reason)"); exit(1) }
                do {
                    let override = ProcessInfo.processInfo.environment["TOKEN_BASEBALL_UPDATE_DMG"].map { URL(fileURLWithPath: $0) }
                    let fresh = try await Updater.prepare(from: override ?? download, expectedVersion: version, current: app) { print($0) }
                    try Updater.swapAfterExit(fresh: fresh, into: app, reopen: false)
                    print("검사 통과: \(version)(으)로 바꿉니다."); exit(0)
                } catch {
                    print("실패: \((error as? Updater.Failure)?.message ?? error.localizedDescription)"); exit(1)
                }
            }
            RunLoop.main.run()
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
