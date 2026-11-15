import SwiftUI
import TokenBaseballCore

struct LeagueTab: View {
    @EnvironmentObject var model: AppModel
    let game: Game
    @State private var tier: LeagueTier?
    @State private var openTeam: TeamID?

    private var shown: LeagueTier { tier ?? game.userTier }

    var body: some View {
        VStack(spacing: 10) {
            Picker("리그", selection: Binding(get: { shown }, set: { tier = $0; openTeam = nil })) {
                ForEach(LeagueTier.allCases, id: \.self) { Text("\($0.rawValue)부").tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Card(shown.displayName, trailing: "강도 범위 \(Int(Balance.strengthRange(shown).lowerBound))~\(Int(Balance.strengthRange(shown).upperBound))") {
                standings
            }
            if shown == game.userTier { promotion }
            leaders
            awards
        }
    }

    private var standings: some View {
        let rows = game.rankedStandings(shown)
        return VStack(spacing: 4) {
            HStack {
                Text("순위").frame(width: 28, alignment: .leading)
                Text("팀")
                Spacer()
                Text("승").frame(width: 24)
                Text("무").frame(width: 24)
                Text("패").frame(width: 24)
                if game.sport == .football {
                    Text("득실").frame(width: 32, alignment: .trailing)
                    Text("승점").frame(width: 32, alignment: .trailing)
                } else {
                    Text("승률").frame(width: 44, alignment: .trailing)
                }
            }
            .note()
            ForEach(Array(rows.enumerated()), id: \.element.teamID) { index, row in
                let team = game.teams[row.teamID]
                Button {
                    openTeam = openTeam == team.id ? nil : team.id
                } label: {
                    HStack {
                        Text("\(index + 1)").frame(width: 28, alignment: .leading)
                        Text(team.name).fontWeight(team.isUser ? .bold : .regular).lineLimit(1)
                        Spacer()
                        Text("\(row.wins)").frame(width: 24)
                        Text("\(row.draws)").frame(width: 24)
                        Text("\(row.losses)").frame(width: 24)
                        if game.sport == .football {
                            Text("\(row.goalDifference > 0 ? "+" : "")\(row.goalDifference)").frame(width: 32, alignment: .trailing)
                            Text("\(row.points)").bold().frame(width: 32, alignment: .trailing)
                        } else {
                            Text(String(format: "%.3f", row.winRate)).frame(width: 44, alignment: .trailing)
                        }
                    }
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(team.isUser ? Color.accentColor : .primary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if openTeam == team.id { TeamDetail(game: game, team: team, row: row) }
            }
            Text("팀을 누르면 선수단을 볼 수 있습니다. 10위는 자동 강등, 9위는 승강 플레이오프.").note()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var promotion: some View {
        if let requirement = game.promotionRequirement {
            Card("승강 플레이오프 신청") {
                KeyValueRow(
                    key: "필요 인지도", value: "\(Int(game.userTeam.fame)) / \(Int(requirement.fame))",
                    valueColor: game.userTeam.fame >= requirement.fame ? Theme.win : Theme.loss)
                KeyValueRow(key: "신청비", value: Format.money(requirement.fee))
                KeyValueRow(key: "신청 마감", value: "\(Balance.applicationDeadlineRound)라운드 (지금 \(game.round)라운드 종료)")
                if game.appliedForPromotion {
                    Label("신청 완료. 시즌이 끝났을 때 1위면 자동 승격, 2위면 승강 플레이오프에 나갑니다.", systemImage: "checkmark.seal.fill")
                        .font(.callout).foregroundStyle(Theme.win)
                } else {
                    Button("신청하기") { model.perform { try $0.applyForPromotion() } }
                        .disabled(game.phase != .regular)
                    Text("신청하지 않으면 1~2위를 해도 승격할 수 없고, 그 자리는 다음 순위 팀이 이어받습니다.").note()
                }
            }
        }
    }

    private var leaders: some View {
        Card("기록 순위") {
            let groups = game.leaders(shown, count: 3)
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)], spacing: 10) {
                ForEach(groups, id: \.title) { group in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.title).font(.caption.bold())
                        if group.rows.isEmpty { Text("—").note() }
                        ForEach(Array(group.rows.enumerated()), id: \.offset) { _, row in
                            HStack {
                                Text(row.playerName).fontWeight(row.isMine ? .bold : .regular).lineLimit(1)
                                Spacer()
                                Text(row.value).monospacedDigit()
                            }
                            .font(.caption)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var awards: some View {
        let list = game.awards.filter { $0.tier == shown }
        if !list.isEmpty {
            Card("지난 시즌 시상") {
                ForEach(Array(list.enumerated()), id: \.offset) { _, award in
                    KeyValueRow(
                        key: "\(award.title) · \(award.playerName) (\(award.teamName))", value: award.detail,
                        valueColor: award.isMine ? Theme.win : .primary)
                }
            }
        }
    }
}

/// 순위표에서 팀을 눌렀을 때: 팀 정보와 선수단, 이적 제안.
struct TeamDetail: View {
    @EnvironmentObject var model: AppModel
    let game: Game
    let team: Team
    let row: StandingRow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("강도 \(Int(game.strength(of: team.id))) · 훈련소 Lv\(team.trainingLevel) · 경기장 Lv\(team.stadiumLevel)\(team.isUser ? "" : " · \(team.style.label(game.sport))")").note()
            if game.sport == .football {
                Text("득점 \(row.runsFor) · 실점 \(row.runsAgainst) · 골득실 \(row.goalDifference > 0 ? "+" : "")\(row.goalDifference) · 승점 \(row.points)").note()
            } else {
                Text("득점 \(row.runsFor) · 실점 \(row.runsAgainst) · 팀 타율 \(String(format: "%.3f", row.battingAverage)) · 팀 평균자책점 \(String(format: "%.2f", row.era))").note()
            }
            ForEach(game.roster(of: team.id).sorted { $0.ability > $1.ability }.prefix(8)) { player in
                HStack {
                    Text(player.position.rawValue).font(.caption.monospaced()).frame(width: 26, alignment: .leading)
                    Text("\(player.name) (\(player.age))").font(.caption)
                    Spacer()
                    Text("\(player.grade) \(Int(player.ability))").font(.caption.monospacedDigit())
                    if !team.isUser, game.tradeWindowOpen {
                        let fee = game.value(for: player) * 13 / 10
                        Button("제안 \(Format.money(fee))") {
                            model.perform { try $0.proposeTransfer(player.id, fee: fee) }
                        }
                        .controlSize(.mini)
                        .disabled(game.proposals.contains { $0.playerID == player.id })
                    }
                }
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }
}
