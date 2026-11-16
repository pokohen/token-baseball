import SwiftUI
import TokenBaseballCore

struct CareerHomeTab: View {
    @EnvironmentObject var model: AppModel
    let game: Game
    var goToMatch: () -> Void = {}
    var goToCareer: () -> Void = {}

    var body: some View {
        VStack(spacing: 10) {
            if let career = game.career, let me = game.myPlayer {
                playerCard(career, me)
                notices(career)
                Card("훈련 포인트", trailing: "남은 훈련 \(career.sessionsLeft)/\(Balance.careerSessionsPerMatch)") {
                    Text("\(game.funds.balance.formatted()) P").font(.title2.bold().monospacedDigit())
                    KeyValueRow(key: "오늘 번 포인트 (오늘 쓴 토큰)", value: "\(model.todayTokens.formatted()) P")
                    KeyValueRow(key: "누적 포인트", value: "\(Format.tokens(game.funds.tokenIncome)) P")
                    Text("AI 코딩에 쓴 토큰이 그대로 훈련 포인트가 됩니다. 훈련 탭에서 능력치를 올리세요.").note()
                }
                if let goal = career.goal {
                    Card("시즌 목표") {
                        KeyValueRow(
                            key: goal.label,
                            value: goal.achieved.map { $0 ? "달성" : "실패" } ?? "\(goal.progress(of: me)) / \(goal.target)",
                            valueColor: goal.achieved == true ? Theme.win : goal.achieved == false ? Theme.loss : .primary)
                        Text("채우면 감독 신뢰 +10, 명성 +3. 채우지 못하면 감독 신뢰 −5.").note()
                    }
                }
                NextMatchCard(game: game, goToMatch: goToMatch)
                if let note = appearanceNote(me) { Text(note).note().frame(maxWidth: .infinity, alignment: .leading) }
            }
            Card("소식") {
                if game.news.isEmpty { Text("아직 소식이 없습니다.").note() }
                ForEach(game.news.suffix(12).reversed()) { item in
                    Text(item.text).font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                    if item.id != game.news.suffix(12).first?.id { Divider() }
                }
            }
        }
    }

    private func playerCard(_ career: Career, _ me: Player) -> some View {
        Card {
            HStack(spacing: 12) {
                EmblemView(team: game.userTeam, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(me.name).font(.headline)
                    Text("\(me.age)세 · \(me.position.label) · \(me.throwsHand.rawValue)투\(me.bats.rawValue)타").note()
                    Text(career.isFreeAgent
                        ? "무소속 · \(game.season)시즌"
                        : "\(game.userTeam.name) · \(game.userTier.displayName)").note()
                    Text("\(game.season)시즌 · \(CareerText.phase(game))").note()
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text(me.grade).font(.title.bold())
                    Text("능력 \(Int(me.ability))").note()
                }
            }
            Meter(label: "감독 신뢰", value: career.trust, color: career.trust < Balance.careerRenewalTrust ? Theme.loss : .accentColor)
            Meter(label: "명성", value: career.fame, color: Theme.warn)
            if let rating = career.lastRating, let line = career.lastLine {
                KeyValueRow(key: "지난 경기", value: "평점 \(String(format: "%.1f", rating)) · \(line)")
            }
        }
    }

    @ViewBuilder private func notices(_ career: Career) -> some View {
        if career.isFreeAgent {
            notice("무소속입니다. 입단 제안 중 하나를 골라야 경기에 나설 수 있습니다.", Theme.loss)
        } else if !career.offers.isEmpty {
            notice("답할 계약 제안이 \(career.offers.count)건 있습니다.", Theme.warn)
        } else if career.trust < Balance.careerRenewalTrust, game.myPlayer?.contract.seasonsLeft ?? 9 <= 1 {
            notice("감독 신뢰가 낮습니다. 계약이 끝나면 재계약 제안을 받지 못할 수 있습니다.", Theme.warn)
        }
    }

    private func notice(_ text: String, _ color: Color) -> some View {
        Button(action: goToCareer) {
            HStack(alignment: .top) {
                Image(systemName: "envelope.fill")
                Text(text).font(.callout)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
            }
            .padding(10)
            .foregroundStyle(.white)
            .background(color, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func appearanceNote(_ me: Player) -> String? {
        guard game.nextMatch() != nil, !game.isMatchLive else { return nil }
        switch me.position {
        case .starter:
            return game.careerStartsNextMatch ? "다음 경기에 선발로 등판합니다." : "다음 경기는 등판하지 않는 날입니다. 팀 경기를 지켜봅니다."
        case .reliever, .closer:
            return "선발이 내려가면 가장 먼저 올라옵니다."
        default:
            return "다음 경기에 선발로 나섭니다."
        }
    }
}
