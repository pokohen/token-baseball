import AppKit
import SwiftUI
import TokenBaseballCore

/// 화면 확인용: 각 탭을 PNG로 그려 저장한다 (`TOKEN_BASEBALL_SNAPSHOT=폴더`).
/// 실제 저장 파일은 건드리지 않고, 임시로 만든 게임을 쓴다.
@MainActor
enum Snapshot {
    static func renderAll(model: AppModel, to directory: URL) {
        renderAll(model: model, to: directory, sport: .baseball)
        renderAll(model: model, to: directory.appendingPathComponent("football", isDirectory: true), sport: .football)
        renderCareer(model: model, to: directory.appendingPathComponent("career", isDirectory: true), position: .shortstop)
        renderCareer(model: model, to: directory.appendingPathComponent("career-pitcher", isDirectory: true), position: .starter)
        renderCareer(model: model, to: directory.appendingPathComponent("career-football", isDirectory: true), position: .forward)
        renderCareer(model: model, to: directory.appendingPathComponent("career-keeper", isDirectory: true), position: .goalkeeper)
    }

    /// 선수 모드 화면.
    static func renderCareer(model: AppModel, to directory: URL, position: Position) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let now = Date()
        var game = Game.newCareer(
            setup: CareerSetup(name: "김하늘", position: position, bats: .left, hometown: "부산"), now: now, seed: 7)
        game.collect([UsageRecord(id: "demo", timestamp: now, usage: TokenUsage(output: 12_000_000))], now: now)
        for index in 0..<7 {
            for key in game.careerTrainableKeys.prefix(2) { try? game.trainCareer(key) }
            try? game.startMatch(now: now.addingTimeInterval(Double(index) * 3600))
            game.runMatchToEnd()
        }
        game.generateDemoCareerOffer()
        model.game = game
        model.todayTokens = 12_000_000

        render(OnboardingView(bankrupt: false, step: 1), model, directory, "01-onboarding-모드")
        render(
            CareerForm(setup: .constant(CareerSetup(name: "김하늘", position: position)), sport: position.sport).padding(24),
            model, directory, "02-선수-만들기")
        for tab in AppTab.allCases {
            render(TabContent(tab: tab, game: game).padding(12), model, directory, "1-\(tab.title(career: true))")
        }
        try? game.startMatch(now: now.addingTimeInterval(10 * 3600))
        // 축구는 교체로 들어간 뒤의 장면이 나오도록 후반까지 돌린다.
        for _ in 0..<(position.sport == .football ? 255 : 140) { game.stepMatch() }
        model.game = game
        try? SaveStore(fileURL: directory.appendingPathComponent("demo-save.json")).save(GameSave(game: game))
        render(TabContent(tab: .match, game: game).padding(12), model, directory, "3-중계")
        render(Text(model.menuBarText).padding(8), model, directory, "4-상단바", width: nil)
    }

    static func renderAll(model: AppModel, to directory: URL, sport: Sport) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let now = Date()
        var game = Game.newGame(
            setup: .init(
                city: "서울", name: sport == .football ? "서울 시민 FC" : "서울 시민 야구단",
                colorIndex: sport == .football ? 3 : 0, emblemIndex: 1),
            now: now, seed: 7, sport: sport)
        game.collect([UsageRecord(id: "demo", timestamp: now, usage: TokenUsage(output: 60_000_000))], now: now)
        try? game.upgrade(.training)
        try? game.upgrade(.scout)
        try? game.promote(.sns)
        try? game.holdTryout()
        for index in 0..<6 {
            try? game.startMatch(now: now.addingTimeInterval(Double(index) * 3600))
            game.runMatchToEnd()
        }
        game.generateDemoOffer()
        model.game = game
        model.todayTokens = 60_000_000

        render(OnboardingView(bankrupt: false), model, directory, "00-onboarding")
        render(OnboardingView(bankrupt: false, step: 1), model, directory, "01-onboarding-종목")
        for tab in AppTab.allCases {
            render(TabContent(tab: tab, game: game).padding(12), model, directory, "1-\(tab.rawValue)")
        }
        render(LineupView(game: game).padding(12), model, directory, "2-라인업")
        render(MarketView(game: game).padding(12), model, directory, "2-영입")

        try? game.startMatch(now: now.addingTimeInterval(10 * 3600))
        for _ in 0..<140 { game.stepMatch() }
        model.game = game
        // 경기 중인 상태의 저장 파일도 남긴다 (앱을 이 파일로 띄워 중계가 이어지는지 볼 수 있다).
        try? SaveStore(fileURL: directory.appendingPathComponent("demo-save.json")).save(GameSave(game: game))
        render(TabContent(tab: .match, game: game).padding(12), model, directory, "3-중계")
        render(
            HStack(spacing: 4) {
                Image(nsImage: Sprites.image(sport == .football ? .shooting : .batting, frame: 0))
                Text(model.menuBarText)
                ForEach(Array(Sprites.Drill.allCases.enumerated()), id: \.offset) { _, drill in
                    Image(nsImage: Sprites.image(drill, frame: 0))
                    Image(nsImage: Sprites.image(drill, frame: 1))
                }
            }
            .padding(8), model, directory, "4-상단바", width: nil)
    }

    private static func render<Content: View>(
        _ view: Content, _ model: AppModel, _ directory: URL, _ name: String, width: CGFloat? = Theme.popoverWidth
    ) {
        let content = view
            .environmentObject(model)
            .frame(width: width)
            .background(Color(nsColor: .windowBackgroundColor))
        // ImageRenderer는 버튼·입력 칸 같은 AppKit 컨트롤을 그리지 못한다.
        // 화면 밖 창에 올려서 그 창의 내용을 그대로 찍는다.
        let host = NSHostingView(rootView: content)
        // 문서에 넣는 그림이 시스템 설정과 상관없이 같게 나오도록 밝은 모드로 고정한다.
        host.appearance = NSAppearance(named: .aqua)
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: size.width, height: size.height),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        defer { window.orderOut(nil) }
        guard size.width > 0, size.height > 0,
              let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)
        else {
            print("그리지 못함: \(name)")
            return
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            print("그리지 못함: \(name)")
            return
        }
        let url = directory.appendingPathComponent("\(name).png")
        try? png.write(to: url)
        print(url.path)
    }
}
