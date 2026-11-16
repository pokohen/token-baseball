import SwiftUI
import TokenBaseballCore

struct MatchTab: View {
    @EnvironmentObject var model: AppModel
    let game: Game

    var body: some View {
        VStack(spacing: 10) {
            if let live = game.live {
                LiveMatchView(
                    live: live, myName: game.myPlayer?.name, myPerformance: game.careerLivePerformance)
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
                if game.sport == .football {
                    TacticCard(game: game)
                } else if game.isCareer {
                    Text("선수 모드에서는 라인업과 투수 운용을 감독이 정합니다. 경기 중에는 개입하지 않습니다.").note()
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    PolicyCard(game: game)
                }
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

/// 축구의 경기 전 방침: 포메이션과 전술 성향.
struct TacticCard: View {
    @EnvironmentObject var model: AppModel
    let game: Game

    var body: some View {
        let formation = game.userTeam.formation ?? .f442
        Card("전술", trailing: formation.label) {
            Picker("포메이션", selection: Binding(
                get: { formation },
                set: { value in model.perform { $0.setFormation(value) } })
            ) {
                ForEach(Formation.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.menu)
            .fixedSize()
            Text(formation.summary).note()
            if let next = game.nextMatch() {
                Text("다음 상대 \(game.teams[next.opponent].shortName)의 예상 포메이션: \(game.formation(of: next.opponent).label)").note()
            }
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
