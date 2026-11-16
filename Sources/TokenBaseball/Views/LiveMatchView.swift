import SwiftUI
import TokenBaseballCore

/// 실시간 중계 화면. 배속과 건너뛰기는 없다.
struct LiveMatchView: View {
    let live: LiveMatch
    /// 선수 모드: 내 선수 이름과 이 경기에서 지금까지의 평점.
    var myName: String? = nil
    var myPerformance: Game.CareerPerformance? = nil

    private var state: MatchState { live.state }

    var body: some View {
        VStack(spacing: 10) {
            Card(live.kind.label, trailing: state.inningLabel) {
                scoreboard
            }
            if let myName {
                Card {
                    if let myPerformance {
                        KeyValueRow(
                            key: "내 선수 \(myName)",
                            value: "평점 \(String(format: "%.1f", myPerformance.rating)) · \(myPerformance.line)",
                            valueColor: .accentColor)
                    } else {
                        KeyValueRow(key: "내 선수 \(myName)", value: "아직 나오지 않았습니다")
                    }
                }
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
                    // 내 선수가 나온 장면은 눈에 띄게 한다.
                    let mine = myName.map { event.text.contains($0) } ?? false
                    Text(event.text)
                        .font(index == 0 || mine ? .callout.weight(.semibold) : .callout)
                        .foregroundStyle(event.kind == .score ? Theme.win : mine ? Color.accentColor : index == 0 ? .primary : .secondary)
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
