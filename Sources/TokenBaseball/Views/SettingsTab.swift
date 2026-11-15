import SwiftUI
import TokenBaseballCore

struct SettingsTab: View {
    @EnvironmentObject var model: AppModel
    let game: Game
    @State private var newName = ""

    var body: some View {
        VStack(spacing: 10) {
            Card("상단바") {
                Picker("보일 숫자", selection: setting(\.menuBarDisplay)) {
                    ForEach(MenuBarDisplay.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Toggle("훈련 애니메이션", isOn: setting(\.animationEnabled))
                Toggle(game.sport == .football ? "알림 (경기 가능, 골, 경기 종료)" : "알림 (경기 가능, 득점, 경기 종료)", isOn: setting(\.notificationsEnabled))
                if !Notifier.isAvailable {
                    Text("알림은 앱 번들(.app)로 실행할 때만 나옵니다.").note()
                }
                Text("경기 중과 경기 종료 표시는 이 설정과 상관없이 나옵니다.").note()
            }
            .font(.callout)

            Card("종목", trailing: "지금: \(game.sport.label)") {
                let other: Sport = game.sport == .football ? .baseball : .football
                Text(model.hasSave(for: other)
                    ? "\(other.label) 구단이 저장되어 있습니다."
                    : "\(other.label) 구단은 아직 없습니다. 바꾸면 창단 화면이 나옵니다.").font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("\(other.symbol) \(other.label)로 바꾸기") { model.switchSport(to: other) }
                Text("구단은 종목별로 따로 저장됩니다. 쉬는 구단은 그동안 쓴 토큰을 받지 않고, 경기 기회도 쌓이지 않습니다.").note()
            }
            .font(.callout)

            Card("난이도") {
                Picker("CPU 팀 맞춰주기", selection: setting(\.rubberBand)) {
                    ForEach(RubberBand.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                HStack {
                    Text("가격 난이도")
                    Slider(value: setting(\.priceDifficulty), in: 0.1...2.0, step: 0.1)
                    Text("\(Int((game.settings.priceDifficulty * 100).rounded()))%").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                Text("시설·홍보·영입·연봉 비용에 곱합니다. 토큰 수는 그대로입니다.").note()
            }
            .font(.callout)

            Card("팀 이름") {
                HStack {
                    TextField(game.userTeam.name, text: $newName).textFieldStyle(.roundedBorder)
                    Button("바꾸기") {
                        model.perform { try $0.renameTeam($0.userTeamID, to: newName) }
                        if model.message == nil { newName = "" }
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Card("토큰 경로") {
                Text(model.sources.claudeCode.root.path).font(.caption.monospaced()).textSelection(.enabled)
                Text(model.sources.codex.root.path).font(.caption.monospaced()).textSelection(.enabled)
                Text("이 컴퓨터 안에서만 읽고 외부로 보내지 않습니다. 구단을 만든 뒤에 쓴 토큰만 셉니다.").note()
                Text("저장 파일: \(model.store.fileURL.path)").font(.caption2.monospaced()).textSelection(.enabled)
            }

            if !game.hallOfFame.isEmpty {
                Card("명예의 전당") {
                    ForEach(Array(game.hallOfFame.enumerated()), id: \.offset) { _, entry in
                        Text("\(entry.name) · \(entry.foundedSeason)~\(entry.endedSeason)시즌 · 최고 \(entry.bestTier.displayName)\(entry.star.map { " · 간판 \($0)" } ?? "")").font(.callout)
                    }
                }
            }

            Card {
                Text(game.sport == .football
                    ? "Token Baseball은 실제 리그·구단과 무관한 비공식 팬 프로젝트입니다. 등장하는 구단과 선수는 모두 가상입니다."
                    : "Token Baseball은 KBO 및 각 구단과 무관한 비공식 팬 프로젝트입니다. 등장하는 구단과 선수는 모두 가상입니다.").note()
                Button("앱 종료") {
                    model.save()
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }

    private func setting<Value>(_ keyPath: WritableKeyPath<TokenBaseballCore.Settings, Value>) -> Binding<Value> {
        Binding(
            get: { game.settings[keyPath: keyPath] },
            set: { value in model.perform { $0.settings[keyPath: keyPath] = value } })
    }
}
