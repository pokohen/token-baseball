import SwiftUI
import TokenBaseballCore

struct MatchTab: View {
    @EnvironmentObject var model: AppModel
    let game: Game

    var body: some View {
        VStack(spacing: 10) {
            if let live = game.live {
                LiveMatchView(live: live)
            } else if let live = game.liveFootball {
                FootballLiveView(live: live)
            } else {
                if let result = game.lastResult {
                    Card("지난 경기", trailing: result.kind.label) {
                        HStack {
                            Text(result.label).font(.title3.bold())
                                .foregroundStyle(resultColor(result))
                            Text("\(result.wasHome ? "홈" : "원정") vs \(result.opponent)").font(.callout)
                        }
                        ForEach(result.summary, id: \.self) { Text($0).note() }
                    }
                }
                NextMatchCard(game: game)
                schedule
                if game.sport == .football { TacticCard(game: game) } else { PolicyCard(game: game) }
            }
        }
    }

    private func resultColor(_ result: LastResult) -> Color {
        if let won = result.shootoutWon { return won ? Theme.win : Theme.loss }
        return result.myRuns > result.theirRuns ? Theme.win : result.myRuns < result.theirRuns ? Theme.loss : .primary
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

/// 축구 실시간 중계 화면. 배속과 건너뛰기는 없다.
struct FootballLiveView: View {
    let live: LiveFootballMatch

    private var state: FootballMatch { live.state }
    private var mine: FootballSide { live.userIsHome ? state.home : state.away }
    private var theirs: FootballSide { live.userIsHome ? state.away : state.home }

    var body: some View {
        VStack(spacing: 10) {
            Card(live.kind.label, trailing: "\(state.periodLabel) \(state.clockLabel)") {
                HStack(alignment: .firstTextBaseline) {
                    Text(state.away.name).font(.callout.weight(.semibold)).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text("\(state.away.goals) : \(state.home.goals)").font(.title.bold().monospacedDigit())
                    Text(state.home.name).font(.callout.weight(.semibold)).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Text("원정").frame(maxWidth: .infinity, alignment: .trailing)
                    Text(state.wentToShootout ? "승부차기 \(state.away.shootoutGoals) : \(state.home.shootoutGoals)" : " ")
                    Text("홈").frame(maxWidth: .infinity, alignment: .leading)
                }
                .note()
            }
            Card {
                pitch
                let share = Int(((live.userIsHome ? state.homePossession : 1 - state.homePossession) * 100).rounded())
                Grid(horizontalSpacing: 8, verticalSpacing: 3) {
                    statRow("점유율", "\(share)%", "\(100 - share)%")
                    statRow("슈팅 (유효)", "\(mine.shots) (\(mine.shotsOnTarget))", "\(theirs.shots) (\(theirs.shotsOnTarget))")
                    statRow("코너킥", "\(mine.corners)", "\(theirs.corners)")
                    statRow("반칙", "\(mine.fouls)", "\(theirs.fouls)")
                    statRow("경고 · 퇴장", "\(mine.yellowCards) · \(mine.redCards)", "\(theirs.yellowCards) · \(theirs.redCards)")
                }
                .font(.caption.monospacedDigit())
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
                            key: "\(other.away.shortName) \(other.away.goals) : \(other.home.goals) \(other.home.shortName)",
                            value: other.isFinished ? "종료" : other.clockLabel)
                    }
                }
            }
        }
    }

    /// 경기장: 왼쪽이 내 진영, 오른쪽이 상대 진영.
    private var pitch: some View {
        let fromMine = live.userIsHome ? state.ballZoneFromHome : 2 - state.ballZoneFromHome
        let myBall = state.homeHasBall == live.userIsHome
        let labels = ["우리 진영", "중원", "상대 진영"]
        return VStack(spacing: 4) {
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { zone in
                    ZStack {
                        Rectangle().fill(Theme.win.opacity(zone == fromMine ? 0.30 : 0.12))
                        VStack(spacing: 2) {
                            Image(systemName: "soccerball").font(.callout)
                                .opacity(zone == fromMine && !state.isFinished ? 1 : 0)
                            Text(labels[zone]).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: 54)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("공 위치: \(labels[fromMine])")
            if state.period != .shootout, !state.isFinished {
                Text(myBall ? "\(mine.shortName) 공격 →" : "← \(theirs.shortName) 공격")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(myBall ? Theme.win : Theme.loss)
                    .frame(maxWidth: .infinity, alignment: myBall ? .trailing : .leading)
            }
        }
    }

    private func statRow(_ label: String, _ left: String, _ right: String) -> some View {
        GridRow {
            Text(left).frame(maxWidth: .infinity, alignment: .trailing)
            Text(label).foregroundStyle(.secondary).frame(width: 84)
            Text(right).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// 축구의 경기 전 방침: 전술 성향.
struct TacticCard: View {
    @EnvironmentObject var model: AppModel
    let game: Game

    var body: some View {
        Card("전술", trailing: "4-4-2") {
            Picker("전술 성향", selection: Binding(
                get: { game.userTeam.tactic ?? .balanced },
                set: { value in model.perform { $0.setTactic(value) } })
            ) {
                ForEach(Tactic.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text("공격적이면 슈팅 기회가 늘지만 실점 위험도 커집니다. 수비적이면 그 반대입니다.").note()
            Text("경기 중에는 개입하지 않습니다. 선발 11명은 선수 탭에서 정합니다. 지친 선수는 60분 이후 자동으로 교체됩니다.").note()
        }
        .font(.callout)
    }
}
