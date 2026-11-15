import SwiftUI
import TokenBaseballCore

struct HomeTab: View {
    @EnvironmentObject var model: AppModel
    let game: Game
    var goToMatch: () -> Void = {}

    var body: some View {
        VStack(spacing: 10) {
            Card {
                HStack(spacing: 12) {
                    EmblemView(team: game.userTeam, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(game.userTeam.name).font(.headline)
                        Text("\(game.userTier.displayName) · \(game.season)시즌 · \(phaseText)").note()
                    }
                    Spacer()
                    if game.phase == .regular {
                        VStack(alignment: .trailing) {
                            Text("\(game.rank(of: game.userTeamID))위").font(.title3.bold())
                            Text(record).note()
                        }
                    }
                }
            }

            warning

            Card("구단 자금") {
                Text("₩\(game.funds.balance.formatted())").font(.title2.bold().monospacedDigit())
                    .foregroundStyle(game.funds.balance < 0 ? Theme.loss : .primary)
                KeyValueRow(key: "오늘 번 자금 (오늘 쓴 토큰)", value: "₩\(model.todayTokens.formatted())")
                KeyValueRow(key: "누적 토큰 수입", value: Format.money(game.funds.tokenIncome))
                KeyValueRow(key: "경기당 연봉", value: "−₩\(game.salaryPerMatch.formatted())")
                KeyValueRow(key: "인지도", value: "\(Int(game.userTeam.fame))")
            }

            NextMatchCard(game: game, goToMatch: goToMatch)

            Card("소식") {
                if game.news.isEmpty { Text("아직 소식이 없습니다.").note() }
                ForEach(game.news.suffix(12).reversed()) { item in
                    Text(item.text).font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                    if item.id != game.news.suffix(12).first?.id { Divider() }
                }
            }
        }
    }

    private var phaseText: String {
        switch game.phase {
        case .regular: "정규시즌 \(game.round)/\(Balance.roundsPerSeason)"
        case .playoff: "승강 플레이오프"
        case .offseason: "오프시즌 (친선 \(game.friendliesPlayed)/\(Balance.friendliesPerOffseason))"
        }
    }

    private var record: String {
        guard let row = game.standings[game.userTier.index].first(where: { $0.teamID == game.userTeamID }) else { return "" }
        return "\(row.wins)승 \(row.draws)무 \(row.losses)패" + (game.sport == .football ? " · 승점 \(row.points)" : "")
    }

    @ViewBuilder private var warning: some View {
        switch game.financialState {
        case .warning:
            banner("재정 경고: 자금이 다음 5경기 연봉보다 적습니다.", Theme.warn)
        case .crisis(let left):
            banner("재정 위기: 자금이 0 아래입니다. 유예 \(left)경기 안에 메우지 못하면 구단이 해체됩니다. 시설 업그레이드와 영입은 할 수 없습니다.", Theme.loss)
        default:
            EmptyView()
        }
    }

    private func banner(_ text: String, _ color: Color) -> some View {
        HStack(alignment: .top) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text).font(.callout)
            Spacer(minLength: 0)
        }
        .padding(10)
        .foregroundStyle(.white)
        .background(color, in: RoundedRectangle(cornerRadius: 10))
    }
}

/// 다음 경기와 경기 시작 버튼, 남은 경기 기회.
struct NextMatchCard: View {
    @EnvironmentObject var model: AppModel
    let game: Game
    var goToMatch: () -> Void = {}

    var body: some View {
        Card("다음 경기", trailing: chargeText) {
            if game.isMatchLive {
                Text("경기가 진행 중입니다.").font(.callout)
                Button("중계 보기", action: goToMatch)
            } else if let next = game.nextMatch() {
                let opponent = game.teams[next.opponent]
                HStack {
                    EmblemView(team: opponent, size: 28)
                    VStack(alignment: .leading) {
                        Text("\(next.userIsHome ? "홈" : "원정") vs \(opponent.name)").font(.callout.weight(.medium))
                        Text("\(next.label) · \(opponent.tier.displayName) · 강도 \(Int(game.strength(of: opponent.id)))\(game.sport == .football ? " · \(game.formation(of: opponent.id).label)" : "")").note()
                    }
                    Spacer()
                    Button("경기 시작") {
                        model.startMatch()
                        if model.game?.isMatchLive == true { goToMatch() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(game.charges == 0)
                }
                if game.charges == 0, let wait = game.timeToNextCharge(now: model.now) {
                    Text("다음 경기 기회까지 \(Format.countdown(wait))").note()
                }
            } else {
                Text("지금은 치를 경기가 없습니다.").note()
            }
        }
    }

    private var chargeText: String {
        game.chargeMarks
    }
}
