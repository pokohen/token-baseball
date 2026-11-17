import SwiftUI
import TokenBaseballCore

/// 축구 실시간 중계 화면. 배속과 건너뛰기는 없다.
struct FootballLiveView: View {
    let live: LiveFootballMatch
    /// 선수 모드: 내 선수 이름과 이 경기에서 지금까지의 평점.
    var myName: String? = nil
    var myPerformance: Game.CareerPerformance? = nil

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
                    Text("원정 · \(state.away.shape.label)").frame(maxWidth: .infinity, alignment: .trailing)
                    Text(state.wentToShootout ? "승부차기 \(state.away.shootoutGoals) : \(state.home.shootoutGoals)" : " ")
                    Text("홈 · \(state.home.shape.label)").frame(maxWidth: .infinity, alignment: .leading)
                }
                .note()
            }
            if let myName {
                MyPlayerLiveCard(name: myName, performance: myPerformance, waiting: "벤치에서 대기 중")
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
            CommentaryCard(log: state.log, myName: myName)
            OtherMatchesCard(rows: live.others.map { ("\($0.away.shortName) \($0.away.goals) : \($0.home.goals) \($0.home.shortName)", $0.isFinished ? "종료" : $0.clockLabel) })
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
