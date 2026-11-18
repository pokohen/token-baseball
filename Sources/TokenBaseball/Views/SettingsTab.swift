import SwiftUI
import TokenBaseballCore

struct SettingsTab: View {
    @EnvironmentObject var model: AppModel
    let game: Game
    @State private var newName = ""
    @State private var confirmReset = false
    @State private var confirmResetAll = false

    var body: some View {
        VStack(spacing: 10) {
            Card("상단바") {
                Picker("보일 숫자", selection: setting(\.menuBarDisplay)) {
                    ForEach(MenuBarDisplay.allCases, id: \.self) {
                        Text(game.isCareer && $0 == .funds ? "훈련 포인트" : $0.rawValue).tag($0)
                    }
                }
                Toggle("훈련 애니메이션", isOn: setting(\.animationEnabled))
                Toggle(game.sport == .football ? "알림 (경기 가능, 골, 경기 종료)" : "알림 (경기 가능, 득점, 경기 종료)", isOn: setting(\.notificationsEnabled))
                if !Notifier.isAvailable {
                    Text("알림은 앱 번들(.app)로 실행할 때만 나옵니다.").note()
                }
                Text("경기 중과 경기 종료 표시는 이 설정과 상관없이 나옵니다.").note()
            }
            .font(.callout)

            Card("모드", trailing: "지금: \(model.slot.label)") {
                SlotSwitcher()
            }
            .font(.callout)

            Card("난이도") {
                if !game.isCareer {
                    Picker("CPU 팀 맞춰주기", selection: setting(\.rubberBand)) {
                        ForEach(RubberBand.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                }
                HStack {
                    Text("가격 난이도")
                    Slider(value: setting(\.priceDifficulty), in: 0.1...2.0, step: 0.1)
                    Text("\(Int((game.settings.priceDifficulty * 100).rounded()))%").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                Text(game.isCareer
                    ? "훈련 비용에 곱합니다. 토큰 수는 그대로입니다."
                    : "시설·홍보·영입·연봉 비용에 곱합니다. 토큰 수는 그대로입니다.").note()
            }
            .font(.callout)

            if game.isCareer, let me = game.myPlayer, game.career?.retired != true {
                Card("선수 이름") {
                    HStack {
                        TextField(me.name, text: $newName).textFieldStyle(.roundedBorder)
                        Button("바꾸기") {
                            model.perform { try $0.renameCareerPlayer(to: newName) }
                            if model.message == nil { newName = "" }
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    Text("12자까지. 지난 기록과 구단 이력은 그대로입니다.").note()
                }
            }

            if !game.isCareer {
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
            }

            UpdateCard()

            Card("토큰 경로") {
                Text(model.sources.claudeCode.root.path).font(.caption.monospaced()).textSelection(.enabled)
                Text(model.sources.codex.root.path).font(.caption.monospaced()).textSelection(.enabled)
                Text(model.sources.gemini.root.path).font(.caption.monospaced()).textSelection(.enabled)
                Text(model.sources.opencode.root.path).font(.caption.monospaced()).textSelection(.enabled)
                Text("이 컴퓨터 안에서만 읽고 외부로 보내지 않습니다. \(game.isCareer ? "선수를" : "구단을") 만든 뒤에 쓴 토큰만 셉니다.").note()
                Text("저장 파일: \(model.store.fileURL.path)").font(.caption2.monospaced()).textSelection(.enabled)
            }

            Card("초기화") {
                HStack {
                    Button("\(model.slot.label) 처음부터 다시") { confirmReset = true }
                        .confirmationDialog(
                            "지금 하던 \(model.slot.label)\(game.isCareer ? "를" : "을") 그만두고 처음부터 다시 시작할까요?",
                            isPresented: $confirmReset, titleVisibility: .visible
                        ) {
                            Button("처음부터 다시", role: .destructive) { model.reset(all: false) }
                        } message: {
                            Text("다른 모드는 그대로입니다. 저장 파일은 지우지 않고 backups 폴더로 옮겨 둡니다.")
                        }
                    Button("전체 초기화") { confirmResetAll = true }
                        .confirmationDialog(
                            "모든 모드를 처음부터 다시 시작할까요?",
                            isPresented: $confirmResetAll, titleVisibility: .visible
                        ) {
                            Button("전체 초기화", role: .destructive) { model.reset(all: true) }
                        } message: {
                            Text("만들어 둔 선수와 구단이 모두 사라집니다. 저장 파일은 지우지 않고 backups 폴더로 옮겨 둡니다.")
                        }
                }
                Text("초기화한 뒤에는 처음 화면에서 새로 만듭니다. 예전 것은 저장 폴더의 backups 안에 날짜별로 남아 있어, 파일을 원래 자리로 옮기면 되살릴 수 있습니다.").note()
                Button("저장 폴더 열기") {
                    NSWorkspace.shared.open(model.baseStore.fileURL.deletingLastPathComponent())
                }
            }
            .font(.callout)

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
