import SwiftUI
import TokenBaseballCore

struct PlayersTab: View {
    @EnvironmentObject var model: AppModel
    let game: Game
    @State private var section = Section.roster
    @State private var openPlayer: PlayerID?
    @State private var expiringOnly = false

    enum Section: String, CaseIterable {
        case roster = "로스터", lineup = "라인업", market = "영입·이적"
    }

    var body: some View {
        VStack(spacing: 10) {
            Picker("", selection: $section) {
                ForEach(Section.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch section {
            case .roster: roster
            case .lineup: LineupView(game: game)
            case .market: MarketView(game: game)
            }
        }
    }

    private var roster: some View {
        let all = game.roster(of: game.userTeamID)
        let shown = all.filter { !expiringOnly || game.isExpiring($0) }
            .sorted { (Self.group($0), -$0.ability) < (Self.group($1), -$1.ability) }
        return Card("선수단", trailing: "\(all.count) / \(game.rosterLimit(game.userTier))명") {
            Toggle("계약 만료 예정만 보기 (\(all.filter { game.isExpiring($0) }.count)명)", isOn: $expiringOnly)
                .font(.callout)
            ForEach(shown) { player in
                Button {
                    openPlayer = openPlayer == player.id ? nil : player.id
                } label: {
                    PlayerRow(game: game, player: player)
                }
                .buttonStyle(.plain)
                if openPlayer == player.id { PlayerDetail(game: game, player: player) }
            }
            Text("⏳ 이번 시즌이 계약 마지막. 재계약하지 않으면 오프시즌이 끝날 때 떠납니다.").note()
        }
    }
}

extension PlayersTab {
    /// 로스터를 묶어 보여줄 순서: 야구는 야수 → 투수, 축구는 골키퍼 → 수비 → 미드필더 → 공격.
    static func group(_ player: Player) -> Int {
        if player.position.sport == .football { return Position.football.firstIndex(of: player.position) ?? 0 }
        return player.isPitcher ? 1 : 0
    }
}

struct PlayerRow: View {
    let game: Game
    let player: Player
    var trailing: String?

    var body: some View {
        HStack(spacing: 6) {
            Text(player.position.rawValue).font(.caption.monospaced()).frame(width: 26, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(player.name).font(.callout.weight(.medium))
                    if player.teamID == game.userTeamID, game.isExpiring(player) { Text("⏳").font(.caption) }
                    if player.isFranchiseStar { Image(systemName: "star.circle.fill").foregroundStyle(Theme.warn).font(.caption) }
                    if player.isHot { Image(systemName: "flame.fill").foregroundStyle(Theme.loss).font(.caption2) }
                    if player.isForeign { Text("외").font(.caption2).padding(.horizontal, 3).background(.quaternary, in: Capsule()) }
                }
                Text("\(player.age)세 · \(player.position.sport == .football ? player.position.label : "\(player.throwsHand.rawValue)투\(player.bats.rawValue)타") · \(trailing ?? "연봉 \(Format.money(player.contract.salary))")").note()
            }
            Spacer()
            Stars(count: player.scoutStars(scoutLevel: game.userTeam.scoutLevel))
            Text("\(player.grade) \(Int(player.ability.rounded()))").font(.callout.monospacedDigit().weight(.semibold))
                .frame(width: 44, alignment: .trailing)
        }
        .contentShape(Rectangle())
    }
}

struct PlayerDetail: View {
    @EnvironmentObject var model: AppModel
    let game: Game
    let player: Player

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(player.origin + (player.traits.isEmpty ? "" : " · " + player.traits.map(\.rawValue).joined(separator: ", "))).note()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), alignment: .leading, spacing: 2) {
                ForEach(Attributes.weights(for: player.position).map(\.0), id: \.self) { key in
                    Text("\(key.label) \(Int(player.attributes[key].rounded()))").font(.caption.monospacedDigit())
                }
            }
            if let line = player.football {
                if player.position == .goalkeeper {
                    Text("\(line.games)경기 · 무실점 \(line.cleanSheets)경기 · 선방 \(line.saves) · 실점 \(line.conceded) · 경고 \(line.yellowCards) · 퇴장 \(line.redCards)").note()
                } else {
                    Text("\(line.games)경기 · \(line.goals)골 \(line.assists)도움 · 슈팅 \(line.shots) (유효 \(line.shotsOnTarget)) · 경고 \(line.yellowCards) · 퇴장 \(line.redCards)").note()
                }
            } else if player.isPitcher {
                Text("\(player.pitching.games)경기 \(player.pitching.wins)승 \(player.pitching.losses)패 \(player.pitching.saves)세 · 평균자책점 \(String(format: "%.2f", player.pitching.era)) · \(player.pitching.innings)이닝 · 탈삼진 \(player.pitching.strikeouts) · \(player.pitching.pitches)구").note()
            } else {
                Text("\(player.batting.games)경기 타율 \(String(format: "%.3f", player.batting.average)) · \(player.batting.homeRuns)홈런 · \(player.batting.runsBattedIn)타점 · \(player.batting.steals)도루 · OPS \(String(format: "%.3f", player.batting.ops))").note()
            }
            let left = player.contract.seasonsLeft
            Text("계약 \(game.phase == .offseason ? (left <= 0 ? "만료 (오프시즌이 끝나면 떠남)" : "\(left)시즌 남음") : (left <= 1 ? "이번 시즌까지" : "\(left)시즌 남음"))\(player.contract.relegationClause ? " · 강등 조항 있음" : "")").note()

            if game.isExpiring(player) {
                let demand = game.renewalDemand(player)
                if let counter = game.counters.first(where: { $0.playerID == player.id }) {
                    Text("역제안: \(counter.years)시즌, 연봉 \(Format.money(counter.salary))").font(.caption.bold())
                    HStack {
                        Button("수락") { model.perform { try $0.acceptCounter(counter.id) } }
                        Button("거절") { model.perform { $0.declineCounter(counter.id) } }
                    }
                    .controlSize(.small)
                } else if game.proposals.contains(where: { $0.playerID == player.id }) {
                    Text("재계약 제안을 보냈습니다. 다음 경기 뒤에 답이 옵니다.").font(.caption.bold())
                } else {
                    Text("재계약 요구: \(demand.years)시즌, 연봉 \(Format.money(demand.salary))").font(.caption.bold())
                    HStack {
                        Button("요구대로 제안") {
                            model.perform { try $0.proposeRenewal(player.id, salary: demand.salary, years: demand.years) }
                        }
                        Button("10% 낮게 제안") {
                            model.perform { try $0.proposeRenewal(player.id, salary: demand.salary * 9 / 10, years: demand.years) }
                        }
                    }
                    .controlSize(.small)
                }
            }
            Button("방출", role: .destructive) { model.perform { try $0.release(player.id) } }
                .controlSize(.small)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }
}
