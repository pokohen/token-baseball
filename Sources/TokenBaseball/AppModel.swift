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

    /// 야구 저장 파일의 위치. 축구 저장 파일은 같은 폴더에 따로 둔다.
    let baseStore: SaveStore
    /// 지금 진행 중인 저장 칸 (야구 구단 / 축구 구단 / 야구 선수).
    @Published private(set) var slot: SaveSlot
    /// 지금 종목.
    var sport: Sport { slot.sport }
    /// 지금 저장 칸의 파일.
    var store: SaveStore { baseStore.sibling(slot: slot) }
    let sources: UsageSources
    private var matchGeneration = 0
    private var matchTask: Task<Void, Never>?
    private var pendingSave: Task<Void, Never>?
    private var timers: [Timer] = []
    private var pitchesSinceSave = 0
    /// 직전에 경기를 치를 수 있는 상태였는지. 앱을 켠 직후에는 아직 모른다 (nil).
    private var wasMatchReady: Bool?
    /// 팝오버가 열려 있는지. 열려 있을 때 끝난 경기는 바로 확인한 것으로 본다.
    private var popoverVisible = false
    private let launchedAt = Date()

    /// 공 하나에 걸리는 시간. 배속과 건너뛰기는 없다.
    static let pitchInterval: Duration = .seconds(3)

    init(store: SaveStore = AppModel.defaultStore(), sources: UsageSources = UsageSources()) {
        self.baseStore = store
        self.sources = sources
        self.slot = store.loadActiveSlot()
        loadGame()
    }

    private func loadGame() {
        loadError = nil
        do {
            game = try store.load()?.game
        } catch {
            game = nil
            loadError = "저장 파일을 읽지 못했습니다.\n\(store.fileURL.path)\n\(error.localizedDescription)"
        }
    }

    /// 그 종목의 구단을 이미 만들어 두었는지.
    func hasSave(for sport: Sport) -> Bool { baseStore.sibling(for: sport).exists }
    func hasSave(slot: SaveSlot) -> Bool { baseStore.sibling(slot: slot).exists }

    func switchSport(to target: Sport) { switchSlot(to: SaveSlot(sport: target)) }

    /// 저장 칸을 바꾼다. 지금 것은 저장해 두고, 그 칸의 구단·선수를 불러온다 (없으면 만들기 화면).
    /// 쉬는 구단·선수는 그동안 쓴 토큰과 흐른 시간을 받지 않는다.
    func switchSlot(to target: SaveSlot) {
        guard target != slot else { return }
        pendingSave?.cancel()
        save()
        matchTask?.cancel()
        matchTask = nil
        matchGeneration += 1
        do {
            try baseStore.saveActiveSlot(target)
        } catch {
            message = "바꾸지 못했습니다: \(error.localizedDescription)"
            return
        }
        slot = target
        message = nil
        wasMatchReady = nil
        todayTokens = 0
        recentRate = 0
        loadGame()
        if game != nil {
            game?.resume(now: Date())
            save()
        }
        if game?.isMatchLive == true { runMatchLoop() }
        pollUsage()
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
        if game?.isMatchLive == true { runMatchLoop() }
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
        let ready = (game?.charges ?? 0) > 0 && game?.nextMatch() != nil && game?.isMatchLive != true
        // 경기 기회가 새로 생겼을 때만 알린다. 앱을 켤 때마다 알리지 않는다.
        if ready, wasMatchReady == false { notify("경기를 치를 수 있습니다", "상단바를 눌러 경기를 시작하세요.") }
        wasMatchReady = ready
        updateStatusTooltip()
    }

    /// 상단바 아이콘의 툴팁. MenuBarExtra의 라벨에 붙인 `.help`는 상단바 버튼까지 전달되지 않아서
    /// 버튼에 직접 넣는다.
    private func updateStatusTooltip() {
        let text = tooltip
        for window in NSApp.windows {
            guard let button = Self.statusButton(in: window.contentView), button.toolTip != text else { continue }
            button.toolTip = text
        }
    }

    private static func statusButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton { return button }
        for child in view.subviews {
            if let button = statusButton(in: child) { return button }
        }
        return nil
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

    func createClub(_ setup: Game.ClubSetup, sport chosen: Sport? = nil) {
        let name = setup.name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { message = "팀 이름을 입력해 주세요."; return }
        if game?.isBankrupt == true {
            perform { try $0.foundNewClub(setup: setup, now: Date()) }
        } else {
            let target = SaveSlot(sport: chosen ?? sport)
            // 이미 있는 구단을 덮어쓰지 않는다.
            guard !hasSave(slot: target) else {
                switchSlot(to: target)
                return
            }
            guard activate(target) else { return }
            let seed = UInt64.random(in: 1...UInt64.max)
            game = Game.newGame(setup: setup, now: Date(), seed: seed, sport: target.sport)
            message = nil
            save()
        }
        pollUsage()
    }

    /// 새로 만들 저장 칸으로 옮긴다. 실패하면 false.
    private func activate(_ target: SaveSlot) -> Bool {
        guard target != slot else { return true }
        // 지금 진행하던 것은 저장해 두고 떠난다.
        pendingSave?.cancel()
        save()
        matchTask?.cancel()
        matchTask = nil
        do {
            try baseStore.saveActiveSlot(target)
        } catch {
            message = "만들지 못했습니다: \(error.localizedDescription)"
            return false
        }
        matchGeneration += 1
        slot = target
        game = nil
        todayTokens = 0
        recentRate = 0
        wasMatchReady = nil
        return true
    }

    /// 선수 모드: 내 선수를 만든다. 은퇴한 뒤라면 같은 세계에서 새 선수로 시작한다.
    func createCareer(_ setup: CareerSetup) {
        var setup = setup
        setup.name = setup.name.trimmingCharacters(in: .whitespaces)
        guard !setup.name.isEmpty else { message = "선수 이름을 입력해 주세요."; return }
        if slot.isCareer, game?.career?.retired == true {
            perform { try $0.startNewCareer(setup: setup, now: Date()) }
        } else {
            // 이미 있는 선수를 덮어쓰지 않는다.
            let target = SaveSlot.career(for: setup.sport)
            guard !hasSave(slot: target) else {
                switchSlot(to: target)
                return
            }
            guard activate(target) else { return }
            game = Game.newCareer(setup: setup, now: Date(), seed: UInt64.random(in: 1...UInt64.max))
            message = nil
            save()
        }
        pollUsage()
    }

    func startMatch() {
        perform { try $0.startMatch(now: Date()) }
        save()
        if game?.isMatchLive == true { runMatchLoop() }
    }

    func acknowledgeResult() {
        guard game?.lastResult?.acknowledged == false else { return }
        game?.acknowledgeResult()
        save()
    }

    /// 팝오버가 열리고 닫힐 때 부른다.
    func setPopoverVisible(_ visible: Bool) {
        popoverVisible = visible
        if visible { acknowledgeResult() }
    }

    // MARK: 실시간 중계

    private func runMatchLoop() {
        guard matchTask == nil else { return }
        let generation = matchGeneration
        matchTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.matchGeneration == generation, self.game?.isMatchLive == true else { break }
                let before = self.game?.liveScore?.mine
                let events = self.game?.stepMatch() ?? []
                let after = self.game?.liveScore?.mine
                self.handle(events, iScored: before != nil && after != nil && after! > before!)
                // 이닝 교대, 투수 교체, 득점 장면에서는 잠깐 멈췄다 간다.
                var pause = Self.pitchInterval
                if events.contains(where: { $0.kind == .inning }) { pause += .seconds(4) }
                if events.contains(where: { $0.kind == .change }) { pause += .seconds(3) }
                if events.contains(where: { $0.kind == .score }) { pause += .seconds(2) }
                if self.game?.isMatchLive != true { break }
                try? await Task.sleep(for: pause)
            }
            if let self, self.matchGeneration == generation { self.matchTask = nil }
        }
    }

    private func handle(_ events: [MatchEvent], iScored: Bool) {
        pitchesSinceSave += 1
        let finished = game?.isMatchLive != true
        if finished, let result = game?.lastResult {
            notify("경기 종료", "\(result.opponent)전 \(result.label)")
            // 팝오버로 결과를 보고 있었으면 상단바에 "경기 종료"를 남기지 않는다.
            if popoverVisible { game?.acknowledgeResult() }
        } else if iScored {
            notify(sport == .football ? "골!" : "득점!", events.last { $0.kind == .score }?.text ?? "")
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
        if game.isMatchLive { return game.sport == .football ? .shooting : .batting }
        // 토큰 사용이 일정 시간 없으면 쉰다.
        // (장부의 반영 시각은 토큰을 안 써도 계속 갱신되므로 기준으로 쓸 수 없다.)
        if now.timeIntervalSince(lastTokenAt ?? launchedAt) > 600 { return .rest }
        if let me = game.myPlayer {
            // 선수 모드: 내 선수가 하는 훈련만 보여 준다.
            let mine: [Sprites.Drill] = me.position == .goalkeeper ? [.keeping, .running, .weights]
                : me.position.sport == .football ? [.dribbling, .shooting, .running, .weights]
                : me.isPitcher ? [.pitching, .running, .weights] : [.batting, .fielding, .running, .weights]
            return mine[(Int(now.timeIntervalSince1970) / 8) % mine.count]
        }
        var drills: [Sprites.Drill] = game.sport == .football
            ? [.dribbling, .shooting, .keeping, .running]
            : [.batting, .pitching, .fielding, .running]
        if game.userTeam.trainingLevel >= 3 { drills.append(.weights) }
        return drills[(Int(now.timeIntervalSince1970) / 8) % drills.count]
    }
}
