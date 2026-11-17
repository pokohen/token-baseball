import SwiftUI
import TokenBaseballCore

/// 다음 경기와 경기 시작 버튼, 남은 경기 기회.
struct NextMatchCard: View {
    @EnvironmentObject var model: AppModel
    let game: Game
    var goToMatch: () -> Void = {}

    var body: some View {
        Card("다음 경기", trailing: chargeText) {
            if game.isMatchLive {
                Text("경기가 진행 중입니다.").font(.callout)
                Button("중계 보기", action: goToMatch)
            } else if let next = game.nextMatch() {
                let opponent = game.teams[next.opponent]
                HStack {
                    EmblemView(team: opponent, size: 28)
                    VStack(alignment: .leading) {
                        Text("\(next.userIsHome ? "홈" : "원정") vs \(opponent.name)").font(.callout.weight(.medium))
                        Text("\(next.label) · \(opponent.tier.displayName) · 강도 \(Int(game.strength(of: opponent.id)))\(game.sport == .football ? " · \(game.formation(of: opponent.id).label)" : "")").note()
                    }
                    Spacer()
                    Button("경기 시작") {
                        model.startMatch()
                        if model.game?.isMatchLive == true { goToMatch() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(game.charges == 0)
                }
                if game.charges == 0 {
                    if let wait = game.timeToNextCharge(now: model.now) {
                        Text("다음 경기 기회까지 \(Format.countdown(wait))").note()
                    }
                    HStack {
                        Text("기다리지 않고 \(game.isCareer ? "훈련 포인트" : "자금")로 바로 치를 수 있습니다. 연달아 쓰면 두 배씩 비싸지고, 경기 기회가 새로 생기면 처음 값으로 돌아갑니다.").note()
                        Spacer()
                        Button("바로 경기 · \(costText)") {
                            model.buyExtraMatchAndStart()
                            if model.game?.isMatchLive == true { goToMatch() }
                        }
                        .disabled(game.extraMatchBlockedReason != nil)
                        .help(game.extraMatchBlockedReason ?? "경기 기회를 하나 사서 바로 시작합니다")
                    }
                }
            } else {
                Text("지금은 치를 경기가 없습니다.").note()
            }
        }
    }

    private var costText: String {
        game.isCareer ? "\(Format.tokens(game.extraMatchCost)) P" : Format.money(game.extraMatchCost)
    }

    private var chargeText: String {
        game.chargeMarks
    }
}
