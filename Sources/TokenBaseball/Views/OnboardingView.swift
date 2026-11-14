import SwiftUI
import TokenBaseballCore

/// 첫 실행: 환영 → 연고지 → 팀 이름 → 색상·엠블럼 → 시작. 파산 뒤 새 구단을 만들 때도 쓴다.
struct OnboardingView: View {
    @EnvironmentObject var model: AppModel
    let bankrupt: Bool

    @State private var step = 0
    @State private var city = NameGenerator.userCities[0]
    @State private var name = ""
    @State private var colorIndex = 0
    @State private var emblemIndex = 0

    private var defaultName: String { "\(city) 시민 야구단" }
    private var finalName: String { name.trimmingCharacters(in: .whitespaces).isEmpty ? defaultName : name }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if step == 0 { welcome } else { form }
            if let message = model.message {
                Text(message).font(.callout).foregroundStyle(Theme.loss)
            }
            Spacer()
            HStack {
                if step > 0 { Button("이전") { step -= 1 } }
                Spacer()
                if step < 3 {
                    Button("다음") { step += 1 }.keyboardShortcut(.defaultAction)
                } else {
                    Button("구단 창단") {
                        model.createClub(.init(
                            city: city, name: finalName, colorIndex: colorIndex, emblemIndex: emblemIndex))
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "baseball.fill").font(.system(size: 40)).foregroundStyle(Color.accentColor)
            if bankrupt {
                Text("팀을 새로 키워주세요").font(.title2.bold())
                Text("구단이 파산해 해체되었습니다. 세계는 그대로 이어지고, 6부 시민 아마추어에서 새 시민 구단으로 다시 시작합니다.")
                if let last = model.game?.hallOfFame.last {
                    Card("명예의 전당") {
                        Text("\(last.name) · \(last.foundedSeason)~\(last.endedSeason)시즌 · 최고 \(last.bestTier.displayName)")
                        if let star = last.star { Text("간판 선수 \(star)").note() }
                    }
                }
            } else {
                Text("Token Baseball").font(.title2.bold())
                Text("평소처럼 AI 코딩을 하면 쓴 토큰이 구단 자금으로 쌓입니다. 그 돈으로 시민 야구단을 프로 구단으로 키워 보세요.")
                Card("토큰 사용량을 읽는 곳") {
                    Text(model.sources.claudeCode.root.path).font(.caption.monospaced()).textSelection(.enabled)
                    Text(model.sources.codex.root.path).font(.caption.monospaced()).textSelection(.enabled)
                    Text("이 컴퓨터 안에서만 읽습니다. 외부로 보내지 않습니다. 설치 이전 사용량은 세지 않습니다.").note()
                }
            }
            Text("KBO 및 각 구단과 무관한 비공식 팬 프로젝트입니다.").note()
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(["", "연고지를 골라 주세요", "팀 이름을 정해 주세요", "팀 색상과 엠블럼"][step]).font(.title3.bold())
            switch step {
            case 1:
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                    ForEach(NameGenerator.userCities, id: \.self) { item in
                        Button(item) { city = item }
                            .buttonStyle(.bordered)
                            .tint(city == item ? Color.accentColor : .secondary)
                    }
                }
            case 2:
                TextField(defaultName, text: $name).textFieldStyle(.roundedBorder)
                Text("비워 두면 \"\(defaultName)\"이 됩니다. 나중에 설정에서 바꿀 수 있습니다.").note()
            default:
                HStack(spacing: 8) {
                    ForEach(Theme.teamColors.indices, id: \.self) { index in
                        Circle().fill(Theme.teamColors[index]).frame(width: 30, height: 30)
                            .overlay(Circle().stroke(.primary, lineWidth: colorIndex == index ? 3 : 0))
                            .onTapGesture { colorIndex = index }
                            .accessibilityLabel(Theme.teamColorNames[index])
                    }
                }
                HStack(spacing: 8) {
                    ForEach(Theme.emblems.indices, id: \.self) { index in
                        Image(systemName: Theme.emblems[index]).font(.title2)
                            .frame(width: 40, height: 40)
                            .background(emblemIndex == index ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 8))
                            .onTapGesture { emblemIndex = index }
                            .accessibilityLabel(Theme.emblemNames[index])
                    }
                }
                Card {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(Theme.teamColors[colorIndex])
                            Image(systemName: Theme.emblems[emblemIndex]).font(.title2.bold()).foregroundStyle(.white)
                        }
                        .frame(width: 48, height: 48)
                        VStack(alignment: .leading) {
                            Text(finalName).font(.headline)
                            Text("\(LeagueTier.citizenAmateur.displayName) · 선수 14명 · 시작 자금 ₩\(FundsLedger.startingFunds.formatted())").note()
                        }
                    }
                }
            }
        }
    }
}
