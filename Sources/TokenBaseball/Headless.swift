import Foundation
import TokenBaseballCore

/// 화면 없이 한 가지 일만 하고 끝내는 확인용 실행 방식. 환경 변수로 고른다.
///
/// - `TOKEN_BASEBALL_SELFTEST=폴더`: 앱의 흐름을 임시 폴더에서 끝까지 돌려 본다.
/// - `TOKEN_BASEBALL_SELF_UPDATE=1`: 앱 안 업데이트를 끝까지 해 본다 (바꾼 뒤 다시 열지는 않는다).
/// - `TOKEN_BASEBALL_CHECK_UPDATE=1`: 새 버전이 있는지만 확인한다.
@MainActor
enum Headless {
    private static var environment: [String: String] { ProcessInfo.processInfo.environment }

    /// 해당하는 환경 변수가 있으면 그 일을 하고 앱을 끝낸다. 없으면 그냥 돌아온다.
    static func runIfRequested() {
        if let directory = environment["TOKEN_BASEBALL_SELFTEST"], !directory.isEmpty {
            exit(SelfTest.run(in: URL(fileURLWithPath: directory)) ? 0 : 1)
        }
        if environment["TOKEN_BASEBALL_SELF_UPDATE"] != nil { runToEnd { await selfUpdate() } }
        if environment["TOKEN_BASEBALL_CHECK_UPDATE"] != nil { runToEnd { await checkUpdate() } }
    }

    /// 비동기 작업을 끝까지 돌리고 그 종료 코드로 앱을 끝낸다.
    private static func runToEnd(_ work: @escaping @Sendable () async -> Int32) -> Never {
        Task.detached { exit(await work()) }
        RunLoop.main.run()
        exit(0)
    }

    private static func selfUpdate() async -> Int32 {
        guard case .available(let update) = await UpdateChecker.check(), let version = update.version,
              let download = update.download, let app = Updater.installedApp else {
            print("업데이트할 것이 없습니다.")
            return 0
        }
        if let reason = Updater.blockedReason() {
            print("할 수 없음: \(reason)")
            return 1
        }
        do {
            let override = ProcessInfo.processInfo.environment["TOKEN_BASEBALL_UPDATE_DMG"].map { URL(fileURLWithPath: $0) }
            let fresh = try await Updater.prepare(from: override ?? download, expectedVersion: version, current: app) { print($0) }
            try Updater.swapAfterExit(fresh: fresh, into: app, reopen: false)
            print("검사 통과: \(version)(으)로 바꿉니다.")
            return 0
        } catch {
            print("실패: \((error as? Updater.Failure)?.message ?? error.localizedDescription)")
            return 1
        }
    }

    private static func checkUpdate() async -> Int32 {
        switch await UpdateChecker.check() {
        case .upToDate: print("최신 버전입니다.")
        case .available(let update):
            print("새 버전이 있습니다 (변경 \(update.count)건).")
            update.titles.forEach { print("· \($0)") }
        case .unknown(let reason): print(reason)
        }
        return 0
    }
}
