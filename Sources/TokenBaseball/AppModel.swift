import AppKit
import Foundation
import SwiftUI
import TokenBaseballCore

/// 앱 상태: 게임을 들고 있고, 토큰을 읽고, 경기를 한 구씩 진행하고, 저장한다.
@MainActor
final class AppModel: ObservableObject {
    @Published var game: Game?
    @Published var todayTokens = 0
    @Published var now = Date()
    @Published var message: String?
    @Published var loadError: String?
    /// 상단바 훈련 애니메이션 프레임.
    @Published var frame = 0
    /// 최근에 토큰을 쓴 시각 (쉬는 모습으로 바꿀지 판단).
    @Published var lastTokenAt: Date?
    @Published var recentRate = 0

    let store: SaveStore
    let sources: UsageSources
    private var matchTask: Task<Void, Never>?
    private var pendingSave: Task<Void, Never>?
    private var timers: [Timer] = []
    private var pitchesSinceSave = 0
    private var wasMatchReady = false

    /// 공 하나에 걸리는 시간. 배속과 건너뛰기는 없다.
    static let pitchInterval: Duration = .seconds(3)

    init(store: SaveStore = AppModel.defaultStore(), sources: UsageSources = UsageSources()) {
        self.store = store
        self.sources = sources
        do {
            game = try store.load()?.game
        } catch {
            loadError = "저장 파일을 읽지 못했습니다.\n\(store.fileURL.path)\n\(error.localizedDescription)"
        }
    }

    /// `TOKEN_BASEBALL_SAVE` 환경 변수로 저장 위치를 바꿀 수 있다 (개발·확인용).
    static func defaultStore() -> SaveStore {
        if let path = ProcessInfo.processInfo.environment["TOKEN_BASEBALL_SAVE"], !path.isEmpty {
            return SaveStore(fileURL: URL(fileURLWithPath: path))
        }
        return SaveStore()
    }

    func start() {
        guard timers.isEmpty else { return }
        timers.append(Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.everySecond() }
        })
        timers.append(Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollUsage() }
        })
        scheduleAnimation()
        pollUsage()
        if game?.live != nil { runMatchLoop() }
        Notifier.requestPermission()
        // 앱이 꺼질 때 마지막 상태를 저장한다.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.save() }
        }
    }

    // MARK: 주기 작업

    private func everySecond() {
        now = Date()
        guard game != nil else { return }
        game?.refreshCharges(now: now)
        let ready = (game?.charges ?? 0) > 0 && game?.nextMatch() != nil && game?.live == nil
        if ready, !wasMatchReady { notify("경기를 치를 수 있습니다", "상단바를 눌러 경기를 시작하세요.") }
        wasMatchReady = ready
    }

    private func scheduleAnimation() {
        // 토큰을 많이 쓰는 중이면 애니메이션이 빨라진다 (사용량 = 훈련 강도).
        let interval = recentRate > 2_000_000 ? 0.18 : recentRate > 200_000 ? 0.28 : 0.45
        Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.game?.settings.animationEnabled == true { self.frame &+= 1 }
                self.scheduleAnimation()
            }
        }
    }

    /// 로그를 읽어 새 토큰을 자금에 반영한다. 파일 읽기는 백그라운드에서 한다.
    func pollUsage() {
        guard let game, !game.isBankrupt else { return }
        let since = game.funds.collectSince
        let startedAt = game.funds.startedAt
        let sources = sources
        Task.detached(priority: .utility) {
            let records = sources.records(since: since)
            let startOfDay = Calendar.current.startOfDay(for: Date())
            let today = sources.total(since: max(startOfDay, startedAt)).total
            await MainActor.run { [weak self] in
                guard let self, self.game != nil else { return }
                let earned = self.game?.collect(records, now: Date()) ?? 0
                self.todayTokens = today
                self.recentRate = earned
                if earned > 0 {
                    self.lastTokenAt = Date()
                    self.save()
                }
            }
        }
    }

    // MARK: 저장

    func save() {
        guard let game else { return }
        do {
            try store.save(GameSave(game: game))
        } catch {
            message = "저장하지 못했습니다: \(error.localizedDescription)"
        }
    }

    /// 잠깐 모았다가 저장한다. 슬라이더처럼 연달아 바뀌는 값마다 파일을 쓰지 않기 위해서다.
    func saveSoon() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    // MARK: 명령

    /// 게임 상태를 바꾸는 명령을 실행하고 저장한다. 실패하면 이유를 보여준다.
    func perform(_ action: (inout Game) throws -> Void) {
        guard var copy = game else { return }
        do {
            try action(&copy)
            game = copy
            message = nil
            saveSoon()
        } catch let error as GameError {
            message = error.message
        } catch {
            message = error.localizedDescription
        }
    }

    func createClub(_ setup: Game.ClubSetup) {
        let name = setup.name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { message = "팀 이름을 입력해 주세요."; return }
        if game?.isBankrupt == true {
            perform { try $0.foundNewClub(setup: setup, now: Date()) }
        } else {
            let seed = UInt64.random(in: 1...UInt64.max)
            game = Game.newGame(setup: setup, now: Date(), seed: seed)
            message = nil
            save()
        }
        pollUsage()
    }

    func startMatch() {
        perform { try $0.startMatch(now: Date()) }
        save()
        if game?.live != nil { runMatchLoop() }
    }

    func acknowledgeResult() {
        guard game?.lastResult?.acknowledged == false else { return }
        game?.acknowledgeResult()
        save()
    }

    // MARK: 실시간 중계

    private func runMatchLoop() {
        guard matchTask == nil else { return }
        matchTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.game?.live != nil else { break }
                let events = self.game?.stepMatch() ?? []
                self.handle(events)
                // 이닝 교대, 투수 교체, 득점 장면에서는 잠깐 멈췄다 간다.
                var pause = Self.pitchInterval
                if events.contains(where: { $0.kind == .inning }) { pause += .seconds(4) }
                if events.contains(where: { $0.kind == .change }) { pause += .seconds(3) }
                if events.contains(where: { $0.kind == .score }) { pause += .seconds(2) }
                if self.game?.live == nil { break }
                try? await Task.sleep(for: pause)
            }
            self?.matchTask = nil
        }
    }

    private func handle(_ events: [MatchEvent]) {
        pitchesSinceSave += 1
        let finished = game?.live == nil
        if finished, let result = game?.lastResult {
            notify("경기 종료", "\(result.opponent)전 \(result.label)")
        } else if events.contains(where: { $0.kind == .score }), let live = game?.live {
            let battingIsMine = live.state.isBottom == live.userIsHome
            if battingIsMine { notify("득점!", events.last { $0.kind == .score }?.text ?? "") }
        }
        if finished || pitchesSinceSave >= 15 || events.contains(where: { $0.kind == .inning }) {
            pitchesSinceSave = 0
            save()
        }
    }

    private func notify(_ title: String, _ body: String) {
        guard game?.settings.notificationsEnabled == true else { return }
        Notifier.send(title: title, body: body)
    }

    // MARK: 상단바

    var menuBarText: String {
        guard let game else { return "Token Baseball" }
        return game.menuBarText(now: now, todayTokens: todayTokens)
    }

    var tooltip: String {
        game?.menuBarTooltip(now: now, todayTokens: todayTokens) ?? "Token Baseball"
    }

    /// 지금 보여줄 훈련 모습.
    var drill: Sprites.Drill {
        guard let game, !game.isBankrupt else { return .rest }
        if game.live != nil { return .batting }
        // 토큰 사용이 일정 시간 없으면 쉰다.
        if let lastTokenAt, now.timeIntervalSince(lastTokenAt) > 600 { return .rest }
        if lastTokenAt == nil, now.timeIntervalSince(game.funds.checkpoint) > 600 { return .rest }
        var drills: [Sprites.Drill] = [.batting, .pitching, .fielding, .running]
        if game.userTeam.trainingLevel >= 3 { drills.append(.weights) }
        return drills[(Int(now.timeIntervalSince1970) / 8) % drills.count]
    }
}
