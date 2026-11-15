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
        render(PlayersTabSections(game: game).padding(12), model, directory, "2-선수-라인업-영입")

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
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            print("그리지 못함: \(name)")
            return
        }
        let url = directory.appendingPathComponent("\(name).png")
        try? png.write(to: url)
        print(url.path)
    }
}

/// 선수 탭의 나머지 두 화면을 한 번에 본다.
struct PlayersTabSections: View {
    let game: Game

    var body: some View {
        VStack(spacing: 10) {
            LineupView(game: game)
            MarketView(game: game)
        }
    }
}
