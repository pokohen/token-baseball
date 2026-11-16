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
                let team = game.teams[offer.teamID]
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        EmblemView(team: team, size: 24)
                        VStack(alignment: .leading) {
                            Text(team.name).font(.callout.weight(.medium))
                            Text("\(kindLabel(offer.kind)) · \(team.tier.displayName) · \(game.rank(of: team.id))위").note()
                        }
                        Spacer()
                    }
                    KeyValueRow(key: "연봉 · 기간", value: "\(Format.money(offer.salary)) · \(offer.years)시즌")
                    KeyValueRow(key: "예상 입지", value: offer.role.rawValue)
                    HStack {
                        Button("수락") { model.perform { try $0.acceptCareerOffer(offer.id) } }
                            .buttonStyle(.borderedProminent)
                        Button("연봉 올려 달라고 하기") { model.perform { try $0.negotiateCareerOffer(offer.id) } }
                            .disabled(offer.negotiated)
                        if offer.kind != .tryout {
                            Button("거절") { model.perform { try $0.declineCareerOffer(offer.id) } }
                        }
                    }
                    if offer.kind == .transfer { Text("다음 경기가 끝나면 사라집니다.").note() }
                }
                if offer.id != career.offers.last?.id { Divider() }
            }
        }
    }

    private func kindLabel(_ kind: CareerOffer.Kind) -> String {
        switch kind {
        case .transfer: "이적 제안"
        case .renewal: "재계약 제안"
        case .tryout: "입단 제안"
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
                        Button("은퇴") { confirmRetire = true }
                            .confirmationDialog("은퇴할까요? 되돌릴 수 없습니다.", isPresented: $confirmRetire) {
                                Button("은퇴", role: .destructive) { model.perform { try $0.retireCareer() } }
                            }
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
            KeyValueRow(key: "기록", value: me.isPitcher ? CareerText.pitching(me.pitching) : CareerText.batting(me.batting))
            if me.isPitcher {
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
            KeyValueRow(key: "기록", value: me.isPitcher ? CareerText.pitching(totals.pitching) : CareerText.batting(totals.batting))
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
                        Text((me.isPitcher ? CareerText.pitching(item.pitching) : CareerText.batting(item.batting))
                            + " · 평점 \(CareerText.rating(item.averageRating))").note()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder private func rivals(_ me: Player) -> some View {
        if let team = me.teamID {
            let peers = game.roster(of: team).filter { $0.isPitcher == me.isPitcher }
                .sorted { ($0.ability, -$0.id) > ($1.ability, -$1.id) }
            Card(me.isPitcher ? "팀 투수진" : "팀 타선") {
                ForEach(peers) { player in
                    HStack {
                        Text(player.position.rawValue).font(.caption.monospaced()).frame(width: 26, alignment: .leading)
                        Text(player.name).fontWeight(player.id == me.id ? .bold : .regular)
                        Text("\(player.age)세").note()
                        Spacer()
                        Text("\(Int(player.ability))").monospacedDigit()
                    }
                    .font(.callout)
                    .foregroundStyle(player.id == me.id ? Color.accentColor : .primary)
                }
            }
        }
    }
}
