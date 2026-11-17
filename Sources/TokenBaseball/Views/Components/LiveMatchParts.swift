import SwiftUI
import TokenBaseballCore

/// 종목과 상관없이 중계 화면에 공통으로 들어가는 조각들.

/// 문자 중계: 최근 여덟 줄. 내 선수가 나온 장면은 눈에 띄게 한다.
struct CommentaryCard: View {
    let log: [MatchEvent]
    var myName: String? = nil

    var body: some View {
        Card("문자 중계") {
            ForEach(Array(log.suffix(8).reversed().enumerated()), id: \.offset) { index, event in
                let mine = myName.map { event.text.contains($0) } ?? false
                Text(event.text)
                    .font(index == 0 || mine ? .callout.weight(.semibold) : .callout)
                    .foregroundStyle(event.kind == .score ? Theme.win : mine ? Color.accentColor : index == 0 ? .primary : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if log.isEmpty { Text("곧 경기가 시작됩니다.").note() }
        }
    }
}

/// 선수 모드: 이 경기에서 지금까지의 내 선수 평점. 아직 나오지 않았으면 `waiting`을 보여 준다.
struct MyPlayerLiveCard: View {
    let name: String
    let performance: Game.CareerPerformance?
    let waiting: String

    var body: some View {
        Card {
            if let performance {
                KeyValueRow(
                    key: "내 선수 \(name)",
                    value: "평점 \(String(format: "%.1f", performance.rating)) · \(performance.line)",
                    valueColor: .accentColor)
            } else {
                KeyValueRow(key: "내 선수 \(name)", value: waiting)
            }
        }
    }
}

/// 같은 라운드의 다른 구장 소식.
struct OtherMatchesCard: View {
    /// (점수 한 줄, 진행 상황)
    let rows: [(score: String, status: String)]

    var body: some View {
        if !rows.isEmpty {
            Card("타 구장 소식") {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    KeyValueRow(key: row.score, value: row.status)
                }
            }
        }
    }
}

/// 끝난 내 경기의 결과와 정산.
struct LastResultCard: View {
    let result: LastResult

    var body: some View {
        Card("지난 경기", trailing: result.kind.label) {
            HStack {
                Text(result.label).font(.title3.bold()).foregroundStyle(color)
                Text("\(result.wasHome ? "홈" : "원정") vs \(result.opponent)").font(.callout)
            }
            ForEach(result.summary, id: \.self) { Text($0).note() }
        }
    }

    private var color: Color {
        if let won = result.shootoutWon { return won ? Theme.win : Theme.loss }
        return result.myRuns > result.theirRuns ? Theme.win : result.myRuns < result.theirRuns ? Theme.loss : .primary
    }
}
