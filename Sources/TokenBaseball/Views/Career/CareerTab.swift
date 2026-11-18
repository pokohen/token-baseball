import SwiftUI
import TokenBaseballCore

struct CareerTab: View {
    @EnvironmentObject var model: AppModel
    let game: Game
    @State private var confirmRetire = false

    var body: some View {
        VStack(spacing: 10) {
            if let career = game.career, let me = game.myPlayer {
                if !career.offers.isEmpty { offers(career) }
                contract(career, me)
                CareerRivalCard(game: game, career: career, me: me)
                CareerActivityCard(game: game, career: career)
                season(career, me)
                history(career, me)
                rivals(me)
            }
            if let hall = game.careerHall, !hall.isEmpty {
                Card("기록실") {
                    ForEach(Array(hall.enumerated()), id: \.offset) { _, record in
                        Text("\(record.name) · \(record.position.label) · \(record.firstSeason)~\(record.lastSeason)시즌 · 최고 \(record.bestTier.displayName)")
                            .font(.callout)
                    }
                }
            }
        }
    }

    private func offers(_ career: Career) -> some View {
        Card(career.isFreeAgent ? "입단 제안" : "들어온 제안") {
            ForEach(career.offers) { offer in
                CareerOfferRow(game: game, offer: offer)
                if offer.id != career.offers.last?.id { Divider() }
            }
        }
    }

    private func contract(_ career: Career, _ me: Player) -> some View {
        Card("계약") {
            KeyValueRow(key: "소속", value: career.isFreeAgent ? "무소속" : game.userTeam.name)
            KeyValueRow(key: "연봉", value: Format.money(me.contract.salary))
            KeyValueRow(
                key: "남은 계약", value: me.contract.seasonsLeft <= 0 ? "만료" : "\(me.contract.seasonsLeft)시즌",
                valueColor: me.contract.seasonsLeft <= 1 ? Theme.warn : .primary)
            KeyValueRow(key: "통산 수입", value: Format.money(career.earnings))
            if !career.isFreeAgent {
                HStack {
                    Button("이적 요청") { model.perform { try $0.requestCareerTransfer() } }
                        .disabled(!game.tradeWindowOpen || career.transferRequested)
                    if game.canRetireCareer {
                        Button("은퇴") { confirmRetire = true }.disabled(confirmRetire)
                    }
                }
                if confirmRetire {
                    InlineConfirm(
                        message: "은퇴할까요? 되돌릴 수 없습니다. 기록은 기록실에 남고, 같은 세계에서 새 선수로 시작할 수 있습니다.",
                        confirmTitle: "은퇴", cancel: { confirmRetire = false }
                    ) {
                        confirmRetire = false
                        model.perform { try $0.retireCareer() }
                    }
                }
                Text(career.transferRequested
                    ? "이적을 요청해 두었습니다. 이적 기간 동안 제안이 더 자주 옵니다."
                    : game.tradeWindowOpen
                    ? "이적을 요청하면 제안이 더 자주 오지만 감독 신뢰가 10 떨어집니다. 이적 기간마다 한 번."
                    : "지금은 이적 기간이 아닙니다 (정규시즌 \(Balance.tradeDeadlineRound)라운드까지, 그리고 오프시즌).").note()
            }
        }
    }

    private func season(_ career: Career, _ me: Player) -> some View {
        Card("이번 시즌", trailing: game.userTier.displayName) {
            KeyValueRow(key: "기록", value: CareerText.record(me, batting: me.batting, pitching: me.pitching, football: me.football))
            if let line = me.football {
                KeyValueRow(key: "유효 슈팅 · 경고 · 퇴장", value: "\(line.shotsOnTarget) · \(line.yellowCards) · \(line.redCards)")
            } else if me.isPitcher {
                KeyValueRow(key: "이닝 · 탈삼진", value: "\(me.pitching.innings)이닝 · \(me.pitching.strikeouts)개")
            } else {
                KeyValueRow(key: "OPS · 도루", value: "\(String(format: "%.3f", me.batting.ops)) · \(me.batting.steals)개")
            }
            KeyValueRow(key: "평균 평점", value: CareerText.rating(career.seasonAverageRating))
        }
    }

    private func history(_ career: Career, _ me: Player) -> some View {
        let totals = game.careerTotals
        return Card("통산") {
            KeyValueRow(key: "기록", value: CareerText.record(
                me, batting: totals.batting, pitching: totals.pitching, football: game.careerFootballTotals))
            KeyValueRow(
                key: "평균 평점",
                value: CareerText.rating(totals.ratedGames == 0 ? nil : totals.ratingTotal / Double(totals.ratedGames)))
            KeyValueRow(key: "가장 높이 오른 리그", value: career.bestTier.displayName)
            if !career.clubs.isEmpty { Text(career.clubs.joined(separator: " → ")).note() }
            if !career.awards.isEmpty { Text("수상: " + career.awards.joined(separator: " · ")).note() }
            if !career.history.isEmpty {
                Divider()
                ForEach(career.history.reversed(), id: \.season) { item in
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(item.season)시즌 · \(item.age)세 · \(item.teamName) (\(item.tier.rawValue)부)").font(.caption.weight(.semibold))
                        Text(CareerText.record(me, batting: item.batting, pitching: item.pitching, football: item.football)
                            + " · 평점 \(CareerText.rating(item.averageRating))").note()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder private func rivals(_ me: Player) -> some View {
        if let team = me.teamID {
            let football = me.position.sport == .football
            let peers = game.roster(of: team).filter { football ? $0.position == me.position : $0.isPitcher == me.isPitcher }
                .sorted { ($0.ability, -$0.id) > ($1.ability, -$1.id) }
            Card(football ? "주전 경쟁 (\(me.position.label))" : me.isPitcher ? "팀 투수진" : "팀 타선") {
                if football {
                    let quota = game.formation(of: team).slots.filter { $0 == me.position }.count
                    Text("포메이션 \(game.formation(of: team).label): \(me.position.label) 선발은 \(quota)명입니다. 감독 신뢰가 높으면 능력이 조금 낮아도 선발로 나옵니다.").note()
                }
                ForEach(peers) { player in
                    PlayerLine(player: player, highlighted: player.id == me.id)
                }
            }
        }
    }
}
