import SwiftUI
import TokenBaseballCore

struct MatchTab: View {
    @EnvironmentObject var model: AppModel
    let game: Game

    var body: some View {
        VStack(spacing: 10) {
            if let live = game.live {
                LiveMatchView(live: live)
            } else {
                if let result = game.lastResult {
                    Card("지난 경기", trailing: result.kind.label) {
                        HStack {
                            Text(result.label).font(.title3.bold())
                                .foregroundStyle(result.myRuns > result.theirRuns ? Theme.win : result.myRuns < result.theirRuns ? Theme.loss : .primary)
                            Text("\(result.wasHome ? "홈" : "원정") vs \(result.opponent)").font(.callout)
                        }
                        ForEach(result.summary, id: \.self) { Text($0).note() }
                    }
                }
                NextMatchCard(game: game)
                schedule
                PolicyCard(game: game)
            }
        }
    }

    @ViewBuilder private var schedule: some View {
        if game.phase == .regular, game.round < Balance.roundsPerSeason {
            Card("일정") {
                let upcoming = Array(game.schedules[game.userTier.index].enumerated())
                    .filter { $0.offset >= game.round }.prefix(6)
                ForEach(Array(upcoming), id: \.offset) { index, fixtures in
                    if let fixture = fixtures.first(where: { $0.involves(game.userTeamID) }) {
                        let opponent = game.teams[fixture.opponent(of: game.userTeamID)]
                        KeyValueRow(
                            key: "\(index + 1)라운드 · \(fixture.home == game.userTeamID ? "홈" : "원정")",
                            value: opponent.name)
                    }
                }
            }
        }
    }
}

/// 실시간 중계 화면. 배속과 건너뛰기는 없다.
struct LiveMatchView: View {
    let live: LiveMatch

    private var state: MatchState { live.state }

    var body: some View {
        VStack(spacing: 10) {
            Card(live.kind.label, trailing: state.inningLabel) {
                scoreboard
            }
            Card {
                HStack(alignment: .center, spacing: 16) {
                    diamond.frame(width: 110, height: 100)
                    VStack(alignment: .leading, spacing: 6) {
                        dots("B", filled: state.balls, of: 3, color: Theme.win)
                        dots("S", filled: state.strikes, of: 2, color: Theme.warn)
                        dots("O", filled: state.outs, of: 2, color: Theme.loss)
                    }
                    Spacer()
                }
            }
            Card {
                let pitcher = state.currentPitcher
                let batter = state.currentBatter
                KeyValueRow(key: "투수 \(pitcher.name)", value: "\(pitcher.line.pitches)구")
                KeyValueRow(key: "타자 \(batter.name)", value: "\(batter.line.atBats)타수 \(batter.line.hits)안타")
            }
            Card("문자 중계") {
                ForEach(Array(state.log.suffix(8).reversed().enumerated()), id: \.offset) { index, event in
                    Text(event.text)
                        .font(index == 0 ? .callout.weight(.semibold) : .callout)
                        .foregroundStyle(event.kind == .score ? Theme.win : index == 0 ? .primary : .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if state.log.isEmpty { Text("곧 경기가 시작됩니다.").note() }
            }
            if !live.others.isEmpty {
                Card("타 구장 소식") {
                    ForEach(Array(live.others.enumerated()), id: \.offset) { _, other in
                        KeyValueRow(
                            key: "\(other.away.shortName) \(other.away.runs) : \(other.home.runs) \(other.home.shortName)",
                            value: other.isFinished ? "종료" : other.inningLabel)
                    }
                }
            }
        }
    }

    private var scoreboard: some View {
        let innings = max(9, state.inning)
        return Grid(horizontalSpacing: 6, verticalSpacing: 4) {
            GridRow {
                Text("").gridColumnAlignment(.leading)
                ForEach(1...innings, id: \.self) { Text("\($0)").foregroundStyle(.secondary) }
                Text("R").bold()
                Text("H").foregroundStyle(.secondary)
                Text("E").foregroundStyle(.secondary)
            }
            row(state.away, opponentErrors: state.away.errors, innings: innings)
            row(state.home, opponentErrors: state.home.errors, innings: innings)
        }
        .font(.caption.monospacedDigit())
    }

    private func row(_ team: MatchTeam, opponentErrors: Int, innings: Int) -> some View {
        GridRow {
            Text(team.shortName).font(.caption.weight(.semibold)).lineLimit(1)
            ForEach(0..<innings, id: \.self) { index in
                Text(index < team.runsByInning.count ? "\(team.runsByInning[index])" : " ")
            }
            Text("\(team.runs)").bold()
            Text("\(team.hits)")
            Text("\(opponentErrors)")
        }
    }

    private var diamond: some View {
        ZStack {
            base(filled: state.bases[1] != nil, label: "2루").offset(y: -34)
            base(filled: state.bases[2] != nil, label: "3루").offset(x: -38)
            base(filled: state.bases[0] != nil, label: "1루").offset(x: 38)
            Image(systemName: "house.fill").font(.caption).foregroundStyle(.secondary).offset(y: 34)
        }
    }

    private func base(filled: Bool, label: String) -> some View {
        Rectangle()
            .fill(filled ? Theme.warn : Color.secondary.opacity(0.25))
            .frame(width: 18, height: 18)
            .rotationEffect(.degrees(45))
            .accessibilityLabel("\(label) \(filled ? "주자 있음" : "비어 있음")")
    }

    private func dots(_ label: String, filled: Int, of total: Int, color: Color) -> some View {
        HStack(spacing: 5) {
            Text(label).font(.caption.bold()).frame(width: 12)
            ForEach(0..<total, id: \.self) { index in
                Circle().fill(index < filled ? color : Color.secondary.opacity(0.25)).frame(width: 11, height: 11)
            }
        }
    }
}

/// 경기 전 방침: 투수 운용. 경기는 이 방침대로 흘러간다.
struct PolicyCard: View {
    @EnvironmentObject var model: AppModel
    let game: Game

    var body: some View {
        Card("투수 운용 방침") {
            let policy = game.userTeam.policy
            Stepper("선발 교체 투구 수: \(policy.starterPitchLimit)구", value: binding(\.starterPitchLimit), in: 50...130, step: 5)
            Stepper("선발 교체 실점: \(policy.starterRunLimit)점", value: binding(\.starterRunLimit), in: 2...10)
            Stepper("마무리 투입: \(policy.closerFromInning)회부터", value: binding(\.closerFromInning), in: 7...9)
            Stepper("마무리 투입 점수 차: \(policy.closerMaxLead)점 이내", value: binding(\.closerMaxLead), in: 1...5)
            Text("경기 중에는 개입하지 않습니다. 라인업과 선발은 선수 탭에서 정합니다.").note()
        }
        .font(.callout)
    }

    private func binding(_ keyPath: WritableKeyPath<PitchingPolicy, Int>) -> Binding<Int> {
        Binding(
            get: { game.userTeam.policy[keyPath: keyPath] },
            set: { value in
                model.perform {
                    var policy = $0.userTeam.policy
                    policy[keyPath: keyPath] = value
                    $0.setPitchingPolicy(policy)
                }
            })
    }
}
