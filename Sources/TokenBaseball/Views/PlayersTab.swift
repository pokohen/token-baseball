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

/// 라인업과 선발 투수. 경기 전에 정한다.
struct LineupView: View {
    @EnvironmentObject var model: AppModel
    let game: Game

    var body: some View {
        if game.sport == .football {
            FootballLineupView(game: game)
        } else {
            baseball
        }
    }

    @ViewBuilder private var baseball: some View {
        if let lineup = game.currentLineup {
            let custom = !game.userTeam.lineupOverride.isEmpty
            Card("타순", trailing: custom ? "직접 정함" : "자동") {
                let ids = lineup.batters.map(\.id)
                let bench = game.roster(of: game.userTeamID).filter { !$0.isPitcher && !ids.contains($0.id) }
                ForEach(Array(lineup.batters.enumerated()), id: \.element.id) { index, entry in
                    if let player = game.players[entry.id] {
                        HStack(spacing: 6) {
                            Text("\(index + 1)").font(.callout.monospacedDigit()).frame(width: 14)
                            Text(entry.position.rawValue).font(.caption.monospaced()).frame(width: 26, alignment: .leading)
                                .foregroundStyle(entry.position == player.position || entry.position == .designated ? Color.primary : Theme.warn)
                            Text(player.name).font(.callout)
                            Spacer()
                            Text("\(Int(player.ability.rounded()))").font(.callout.monospacedDigit())
                            Button { move(ids, from: index, to: index - 1) } label: { Image(systemName: "chevron.up") }
                                .disabled(index == 0)
                            Button { move(ids, from: index, to: index + 1) } label: { Image(systemName: "chevron.down") }
                                .disabled(index == ids.count - 1)
                            Menu("교체") {
                                ForEach(bench) { sub in
                                    Button("\(sub.position.label) \(sub.name) (\(Int(sub.ability.rounded())))") {
                                        var next = ids
                                        next[index] = sub.id
                                        model.perform { try $0.setLineup(next) }
                                    }
                                }
                            }
                            .fixedSize()
                            .disabled(bench.isEmpty)
                        }
                        .controlSize(.small)
                    }
                }
                if custom {
                    Button("자동 구성으로 되돌리기") { model.perform { try $0.setLineup([]) } }.controlSize(.small)
                }
                Text("주황색 자리는 제 포지션이 아니라 수비가 깎입니다.").note()
            }
            Card("투수") {
                let pitchers = game.roster(of: game.userTeamID).filter(\.isPitcher)
                Picker("다음 경기 선발", selection: Binding(
                    get: { game.userTeam.starterOverride },
                    set: { value in model.perform { try $0.setNextStarter(value) } })
                ) {
                    Text("자동 (\(game.players[lineup.starter]?.name ?? ""))").tag(PlayerID?.none)
                    ForEach(pitchers) { Text("\($0.position.label) \($0.name)").tag(PlayerID?.some($0.id)) }
                }
                .font(.callout)
                ForEach(lineup.bullpen, id: \.self) { id in
                    if let player = game.players[id] {
                        KeyValueRow(key: "\(player.position.label) \(player.name)", value: "\(Int(player.ability.rounded()))")
                    }
                }
                Text("선발 투수는 등판 후 \(Balance.starterRest(game.userTier))경기를 쉬어야 다시 선발로 나옵니다.").note()
            }
        } else {
            Card { Text("야수 9명과 투수 1명 이상이 있어야 라인업을 짤 수 있습니다.").font(.callout) }
        }
    }

    private func move(_ ids: [PlayerID], from: Int, to: Int) {
        guard ids.indices.contains(to) else { return }
        var next = ids
        next.swapAt(from, to)
        model.perform { try $0.setLineup(next) }
    }
}

/// 축구 선발 11명과 벤치. 경기 전에 정한다.
struct FootballLineupView: View {
    @EnvironmentObject var model: AppModel
    let game: Game

    var body: some View {
        if let lineup = game.currentFootballLineup {
            let custom = !game.userTeam.lineupOverride.isEmpty
            let ids = lineup.starters.map(\.id)
            let bench = lineup.bench.compactMap { game.players[$0] }
            Card("선발 11명 (\((game.userTeam.formation ?? .f442).label))", trailing: custom ? "직접 정함" : "자동") {
                ForEach(Array(lineup.starters.enumerated()), id: \.element.id) { index, entry in
                    if let player = game.players[entry.id] {
                        HStack(spacing: 6) {
                            Text(entry.slot.rawValue).font(.caption.monospaced()).frame(width: 26, alignment: .leading)
                                .foregroundStyle(entry.slot == player.position ? Color.primary : Theme.warn)
                            Text(player.name).font(.callout)
                            if player.isHot { Image(systemName: "flame.fill").foregroundStyle(Theme.loss).font(.caption2) }
                            Spacer()
                            Text("\(Int(player.ability.rounded()))").font(.callout.monospacedDigit())
                            Menu("교체") {
                                ForEach(bench) { sub in
                                    Button("\(sub.position.label) \(sub.name) (\(Int(sub.ability.rounded())))") {
                                        var next = ids
                                        next[index] = sub.id
                                        model.perform { try $0.setLineup(next) }
                                    }
                                }
                            }
                            .fixedSize()
                            .disabled(bench.isEmpty)
                        }
                        .controlSize(.small)
                    }
                }
                if custom {
                    Button("자동 구성으로 되돌리기") { model.perform { try $0.setLineup([]) } }.controlSize(.small)
                }
                Text("주황색 자리는 제 포지션이 아니라 능력이 깎입니다. 골키퍼는 반드시 1명 들어가야 합니다. 포메이션은 경기 탭에서 바꿉니다.").note()
            }
            Card("벤치", trailing: "\(bench.count)명") {
                if bench.isEmpty { Text("벤치에 선수가 없습니다.").note() }
                ForEach(bench) { player in
                    KeyValueRow(key: "\(player.position.label) \(player.name)", value: "\(Int(player.ability.rounded()))")
                }
                Text("한 경기에 5명까지, 60분 이후 지친 선수부터 같은 포지션의 벤치 선수로 자동 교체됩니다.").note()
            }
        } else {
            Card { Text("골키퍼 1명을 포함해 11명이 있어야 선발을 짤 수 있습니다.").font(.callout) }
        }
    }
}

/// 영입 경로와 이적 시장.
struct MarketView: View {
    @EnvironmentObject var model: AppModel
    let game: Game

    var body: some View {
        VStack(spacing: 10) {
            Card("이적 시장", trailing: game.tradeWindowOpen ? "열림" : "닫힘") {
                Text(windowText).note()
            }

            if !game.offers.isEmpty {
                Card("들어온 오퍼") {
                    ForEach(game.offers) { offer in
                        if let player = game.players[offer.playerID] {
                            VStack(alignment: .leading, spacing: 4) {
                                if let swapID = offer.swapPlayerID, let swap = game.players[swapID] {
                                    Text("\(game.teams[offer.fromTeam].name): \(player.name) ↔ \(swap.position.label) \(swap.name) (\(swap.grade) \(Int(swap.ability.rounded())), \(swap.age)세)").font(.callout)
                                } else {
                                    Text("\(game.teams[offer.fromTeam].name): \(player.name)에게 \(Format.money(offer.fee))").font(.callout)
                                }
                                HStack {
                                    Button("수락") { model.perform { try $0.respond(to: offer.id, .accept) } }
                                    Button("거절") { model.perform { try $0.respond(to: offer.id, .reject) } }
                                    if offer.swapPlayerID == nil, !offer.raised {
                                        Button("금액 올려 달라고 하기") { model.perform { try $0.respond(to: offer.id, .askMore) } }
                                    }
                                }
                                .controlSize(.small)
                            }
                        }
                    }
                    Text("다음 경기가 끝날 때까지 답하지 않으면 자동으로 거절됩니다.").note()
                }
            }

            if !game.proposals.isEmpty {
                Card("보낸 제안") {
                    ForEach(game.proposals) { proposal in
                        HStack {
                            Text("\(proposal.kind.rawValue) · \(game.players[proposal.playerID]?.name ?? "")").font(.callout)
                            Spacer()
                            Button("취소") { model.perform { $0.withdrawProposal(proposal.id) } }.controlSize(.small)
                        }
                    }
                    Text("답은 다음 경기가 끝난 뒤에 옵니다.").note()
                }
            }

            Card("입단 테스트") {
                HStack {
                    Text("지역 선수 후보 3~5명이 옵니다. 능력은 낮지만 잠재력 높은 선수가 가끔 섞여 있습니다.").note()
                    Spacer()
                    Button("테스트 열기 \(Format.money(game.tryoutFee))") { model.perform { try $0.holdTryout() } }
                        .disabled(game.candidates.contains { $0.source == .tryout })
                }
            }

            Card("스카우트", trailing: "시설 Lv\(game.userTeam.scoutLevel)") {
                if game.userTeam.scoutLevel == 0 {
                    Text("구단 탭에서 스카우트 시설을 지으면 보낼 수 있습니다.").note()
                } else if let trip = game.scoutTrip {
                    Text("\(trip.region.rawValue) 스카우트가 \(trip.matchesLeft)경기 뒤에 돌아옵니다.").font(.callout)
                } else {
                    HStack {
                        ForEach(ScoutRegion.allCases, id: \.self) { region in
                            Button("\(region.rawValue) \(Format.money(game.scoutCost(region)))") {
                                model.perform { try $0.sendScout(region) }
                            }
                            .disabled(region == .overseas && game.userTier > .semiPro)
                        }
                    }
                    .controlSize(.small)
                    Text("해외 스카우트와 외국인 선수(팀당 3명)는 1~2부에서만.").note()
                }
            }

            if !game.candidates.isEmpty {
                Card("영입 후보") {
                    ForEach(game.candidates) { candidate in
                        if let player = game.players[candidate.playerID] {
                            HStack {
                                PlayerRow(
                                    game: game, player: player,
                                    trailing: "\(candidate.source.rawValue) · 연봉 \(Format.money(player.contract.salary))")
                                Button(candidate.fee > 0 ? "계약 \(Format.money(game.price(candidate.fee)))" : "계약") {
                                    model.perform { try $0.sign(candidate: candidate.id) }
                                }
                                .controlSize(.small)
                            }
                        }
                    }
                }
            }

            if game.phase == .offseason {
                Card("자유계약 (FA)", trailing: "\(game.freeAgentMarket.count)명") {
                    ForEach(game.freeAgentMarket.prefix(15)) { player in
                        let market = Balance.marketSalary(ability: player.ability)
                        HStack {
                            PlayerRow(game: game, player: player, trailing: "시장가 \(Format.money(market))")
                            if game.proposals.contains(where: { $0.playerID == player.id }) {
                                Text("제안함").note()
                            } else {
                                Menu("제안") {
                                    Button("시장가 (\(Format.money(market)), 2시즌)") {
                                        model.perform { try $0.proposeFreeAgent(player.id, salary: market, years: 2) }
                                    }
                                    Button("20% 더 (\(Format.money(market * 12 / 10)), 2시즌)") {
                                        model.perform { try $0.proposeFreeAgent(player.id, salary: market * 12 / 10, years: 2) }
                                    }
                                    Button("50% 더 (\(Format.money(market * 15 / 10)), 2시즌)") {
                                        model.perform { try $0.proposeFreeAgent(player.id, salary: market * 15 / 10, years: 2) }
                                    }
                                }
                                .fixedSize()
                                .controlSize(.small)
                            }
                        }
                    }
                    Text("인지도가 높고 리그가 높을수록, 많이 줄수록 영입 성공률이 올라갑니다.").note()
                }
            }
            Text("다른 구단 선수에게 이적 제안을 하려면 리그 탭에서 팀을 누르세요.").note()
        }
    }

    private var windowText: String {
        switch game.phase {
        case .offseason:
            "오프시즌 이적 시장입니다. FA 영입, 이적 오퍼, 재계약을 할 수 있고, 친선 경기가 끝날 때마다 소식이 들어옵니다."
        case .regular where game.round < Balance.tradeDeadlineRound:
            "시즌 중 트레이드 기간입니다 (\(Balance.tradeDeadlineRound)라운드까지). 가끔 트레이드 제안이 옵니다."
        default:
            "트레이드 마감이 지났습니다. 다음 이적 시장은 시즌이 끝난 뒤에 열립니다."
        }
    }
}
