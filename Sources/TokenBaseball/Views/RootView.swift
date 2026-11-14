import SwiftUI
import TokenBaseballCore

enum AppTab: String, CaseIterable {
    case home = "홈", match = "경기", league = "리그", club = "구단", players = "선수", settings = "설정"

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .match: "baseball.fill"
        case .league: "list.number"
        case .club: "building.2.fill"
        case .players: "person.3.fill"
        case .settings: "gearshape.fill"
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @State private var tab = AppTab.home

    var body: some View {
        Group {
            if let error = model.loadError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundStyle(Theme.warn)
                    Text(error).multilineTextAlignment(.center).textSelection(.enabled)
                    Text("파일을 옮기거나 지운 뒤 앱을 다시 실행해 주세요. 덮어쓰지 않도록 게임을 시작하지 않았습니다.").note()
                        .multilineTextAlignment(.center)
                    Button("종료") { NSApplication.shared.terminate(nil) }
                }
                .padding(24)
            } else if let game = model.game, !game.isBankrupt {
                main(game)
            } else {
                OnboardingView(bankrupt: model.game?.isBankrupt == true)
            }
        }
        .onAppear { model.setPopoverVisible(true) }
        .onDisappear { model.setPopoverVisible(false) }
    }

    private func main(_ game: Game) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(AppTab.allCases, id: \.self) { item in
                    Button {
                        tab = item
                        model.message = nil
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: item.icon).font(.system(size: 14))
                            Text(item.rawValue).font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .foregroundStyle(tab == item ? Color.accentColor : .secondary)
                        .background(tab == item ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            Divider()

            if let message = model.message {
                HStack {
                    Image(systemName: "exclamationmark.circle.fill")
                    Text(message).font(.callout)
                    Spacer()
                    Button { model.message = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }
                .padding(8)
                .foregroundStyle(.white)
                .background(Theme.loss)
            }

            ScrollView {
                TabContent(tab: tab, game: game, startMatchTab: { tab = .match })
                    .padding(12)
            }
        }
    }
}

/// 탭 내용. 스크롤 없이 그릴 수 있게 따로 둔다 (화면 확인용 스냅샷에서도 쓴다).
struct TabContent: View {
    let tab: AppTab
    let game: Game
    var startMatchTab: () -> Void = {}

    var body: some View {
        switch tab {
        case .home: HomeTab(game: game, goToMatch: startMatchTab)
        case .match: MatchTab(game: game)
        case .league: LeagueTab(game: game)
        case .club: ClubTab(game: game)
        case .players: PlayersTab(game: game)
        case .settings: SettingsTab(game: game)
        }
    }
}
