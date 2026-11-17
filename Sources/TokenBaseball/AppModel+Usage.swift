import AppKit
import Foundation
import SwiftUI
import TokenBaseballCore

/// 로컬 로그에서 토큰 사용량을 읽어 자금(훈련 포인트)에 반영한다.
extension AppModel {
    /// 로그를 읽어 새 토큰을 자금에 반영한다. 파일 읽기는 백그라운드에서 한다.
    func pollUsage() {
        guard let game, !game.isBankrupt else { return }
        let since = game.funds.collectSince
        // 오늘 사용량은 이 구단이 자금으로 받은 것만 센다 (창단 전, 쉬는 동안 쓴 토큰은 빼고).
        let startedAt = max(game.funds.startedAt, game.funds.resumedAt ?? .distantPast)
        let sources = sources
        let generation = matchGeneration
        Task.detached(priority: .utility) {
            // 읽기 시작한 시각까지만 반영한 것으로 적는다. 읽는 동안 쌓인 기록은 다음에 읽는다.
            let readAt = Date()
            let records = sources.records(since: since)
            let startOfDay = Calendar.current.startOfDay(for: Date())
            let today = sources.total(since: max(startOfDay, startedAt)).total
            await MainActor.run { [weak self] in
                // 읽는 사이에 종목을 바꿨으면 다른 구단의 장부에 넣지 않는다.
                guard let self, self.game != nil, self.matchGeneration == generation else { return }
                let earned = self.game?.collect(records, now: readAt) ?? 0
                self.todayTokens = today
                self.recentRate = earned
                if earned > 0 {
                    self.lastTokenAt = Date()
                    self.save()
                }
            }
        }
    }
}
