import SwiftUI
import TokenBaseballCore

enum CareerText {
    static func batting(_ line: BattingLine) -> String {
        "\(line.games)경기 타율 \(String(format: "%.3f", line.average)) \(line.homeRuns)홈런 \(line.runsBattedIn)타점"
    }

    static func pitching(_ line: PitchingLine) -> String {
        "\(line.games)경기 \(line.wins)승 \(line.losses)패 \(line.saves)세 평균자책점 \(String(format: "%.2f", line.era))"
    }

    static func football(_ line: FootballLine, keeper: Bool) -> String {
        keeper
            ? "\(line.games)경기 무실점 \(line.cleanSheets)경기 선방 \(line.saves) 실점 \(line.conceded)"
            : "\(line.games)경기 \(line.goals)골 \(line.assists)도움 슈팅 \(line.shots)"
    }

    /// 종목과 포지션에 맞는 기록 한 줄.
    static func record(_ me: Player, batting: BattingLine, pitching: PitchingLine, football: FootballLine?) -> String {
        if me.position.sport == .football {
            return CareerText.football(football ?? FootballLine(), keeper: me.position == .goalkeeper)
        }
        return me.isPitcher ? CareerText.pitching(pitching) : CareerText.batting(batting)
    }

    static func rating(_ value: Double?) -> String { value.map { String(format: "%.2f", $0) } ?? "—" }

    static func phase(_ game: Game) -> String {
        switch game.phase {
        case .regular: "정규시즌 \(game.round)/\(Balance.roundsPerSeason)"
        case .playoff: "승강 플레이오프"
        case .offseason: "오프시즌 (친선 \(game.friendliesPlayed)/\(Balance.friendliesPerOffseason))"
        }
    }
}

/// 0~100 값을 막대로 보여 준다.
struct Meter: View {
    let label: String
    let value: Double
    var color: Color = .accentColor

    var body: some View {
        HStack(spacing: 8) {
            Text(label).foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
            Bar(fraction: value / 100, color: color)
            Text("\(Int(value.rounded()))").monospacedDigit().frame(width: 28, alignment: .trailing)
        }
        .font(.callout)
    }
}

/// 채워지는 막대.
struct Bar: View {
    let fraction: Double
    var color: Color = .accentColor

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.2))
                Capsule().fill(color).frame(width: proxy.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: 6)
    }
}

/// 다른 저장 칸(구단 모드, 선수 모드)으로 옮기는 버튼들.
struct SlotSwitcher: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(SaveSlot.allCases.filter { $0 != model.slot }, id: \.self) { slot in
                HStack {
                    Text("\(slot.sport.symbol) \(slot.label)")
                    Text(model.hasSave(slot: slot) ? "저장되어 있음" : "아직 없음").note()
                    Spacer()
                    Button(model.hasSave(slot: slot) ? "이어서 하기" : "새로 만들기") { model.switchSlot(to: slot) }
                }
            }
            Text("구단과 선수는 따로 저장됩니다. 한 번에 하나만 진행하고, 쉬는 쪽은 그동안 쓴 토큰을 받지 않으며 경기 기회도 쌓이지 않습니다.").note()
        }
        .font(.callout)
    }
}
