import Foundation
import TokenBaseballCore

/// 새 버전 확인과 알림.
extension AppModel {
    /// 새 버전이 있는지 확인한다. `manual`이면 설정에서 꺼 두었어도 확인한다.
    func checkForUpdate(manual: Bool = false) {
        guard manual || UpdateChecker.isEnabled, !checkingUpdate else { return }
        // 번들 없이 실행한 개발 빌드는 조용히 넘어간다.
        guard manual || UpdateChecker.buildCommit != nil else { return }
        checkingUpdate = true
        Task { [weak self] in
            let outcome = await UpdateChecker.check()
            self?.apply(outcome)
        }
    }

    func apply(_ outcome: UpdateChecker.Outcome) {
        checkingUpdate = false
        switch outcome {
        case .upToDate:
            update = nil
            updateStatus = "최신 버전입니다."
        case .available(let found):
            update = found
            updateStatus = "새 버전이 있습니다 (변경 \(found.count)건)."
            // 같은 업데이트는 한 번만 알린다.
            if UpdateChecker.notifiedHead != found.head {
                UpdateChecker.notifiedHead = found.head
                if game?.settings.notificationsEnabled ?? true {
                    Notifier.send(
                        title: "Token Sport 새 버전",
                        body: (found.titles.first ?? "변경 \(found.count)건") + " — 설정 탭에서 업데이트 방법을 확인하세요")
                }
            }
        case .unknown(let reason):
            updateStatus = reason
        }
    }

    func setUpdateCheckEnabled(_ enabled: Bool) {
        UpdateChecker.isEnabled = enabled
        objectWillChange.send()
        if enabled { checkForUpdate() } else { update = nil; updateStatus = nil }
    }
}
