import SwiftUI
import TokenBaseballCore

// MARK: - 선수 만들기

/// 내 선수를 만들 때 정하는 값을 고르는 화면 조각. 첫 시작과 은퇴 뒤 새 선수 만들기에 같이 쓴다.
struct CareerForm: View {
    @Binding var setup: CareerSetup
    @State private var pitcher = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("선수 이름", text: $setup.name).textFieldStyle(.roundedBorder)

            Picker("유형", selection: Binding(
                get: { pitcher },
                set: { value in
                    pitcher = value
                    setup.position = value ? .starter : .shortstop
                })) {
                Text("타자").tag(false)
                Text("투수").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            let positions = pitcher ? CareerSetup.pitcherPositions : CareerSetup.batterPositions
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: pitcher ? 2 : 3), spacing: 6) {
                ForEach(positions, id: \.self) { position in
                    Button(position.label) { setup.position = position }
                        .buttonStyle(.bordered)
                        .tint(setup.position == position ? Color.accentColor : .secondary)
                }
            }
            Text(positionNote).note()

            HStack {
                Picker("타석", selection: $setup.bats) {
                    Text("우타").tag(Hand.right)
                    Text("좌타").tag(Hand.left)
                }
                Picker("투구", selection: $setup.throwsHand) {
                    Text("우투").tag(Hand.right)
                    Text("좌투").tag(Hand.left)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Picker("출신", selection: $setup.hometown) {
                ForEach(NameGenerator.userCities, id: \.self) { Text($0).tag($0) }
            }
        }
        .font(.callout)
        .onAppear { pitcher = setup.position.isPitcher }
    }

    private var positionNote: String {
        switch setup.position {
        case .starter:
            "선발 투수: 쉬는 날을 채우면 반드시 선발로 나옵니다 (시민 리그는 3경기에 한 번, 3부부터는 5경기에 한 번). 나오지 않는 날은 팀 경기를 지켜봅니다."
        case .reliever:
            "불펜 투수: 선발이 내려가면 가장 먼저 올라옵니다. 거의 매 경기 나오지만 짧게 던집니다."
        case .designated:
            "지명타자: 매 경기 타석에 서고 수비는 하지 않습니다. 컨택·파워·선구안·주력만 훈련합니다."
        default:
            "타자: 매 경기 선발로 나옵니다. 포지션은 커리어 중에 바꿀 수 없습니다."
        }
    }
}

/// 은퇴한 뒤: 커리어 기록을 보여 주고 같은 세계에서 새 선수를 만든다.
struct CareerRetiredView: View {
    @EnvironmentObject var model: AppModel
    let game: Game
    @State private var setup = CareerSetup(name: "", position: .shortstop)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("은퇴").font(.title2.bold())
                if let record = game.careerHall?.last { CareerRecordCard(record: record) }
                Card("새 선수") {
                    Text("같은 세계에서 새 선수로 다시 시작합니다. 은퇴한 선수의 기록은 기록실에 남습니다.").note()
                    CareerForm(setup: $setup)
                    Button("새 커리어 시작") { model.createCareer(setup) }
                        .buttonStyle(.borderedProminent)
                }
                if let message = model.message {
                    Text(message).font(.callout).foregroundStyle(Theme.loss)
                }
                Card("다른 모드") { SlotSwitcher() }
            }
            .padding(16)
        }
    }
}

struct CareerRecordCard: View {
    let record: CareerRecord

    var body: some View {
        Card("\(record.name) · \(record.position.label)", trailing: "\(record.firstSeason)~\(record.lastSeason)시즌") {
            KeyValueRow(key: "은퇴 나이", value: "\(record.retiredAge)세")
            KeyValueRow(key: "거쳐 간 구단", value: "\(record.clubs.count)곳")
            Text(record.clubs.joined(separator: " → ")).note()
            KeyValueRow(key: "가장 높이 오른 리그", value: record.bestTier.displayName)
            KeyValueRow(key: "최고 능력", value: "\(Int(record.peakAbility))")
            if record.position.isPitcher {
                KeyValueRow(key: "통산", value: CareerText.pitching(record.pitching))
            } else {
                KeyValueRow(key: "통산", value: CareerText.batting(record.batting))
            }
            if let rating = record.averageRating {
                KeyValueRow(key: "평균 평점", value: String(format: "%.2f", rating))
            }
            KeyValueRow(key: "통산 수입", value: Format.money(record.earnings))
            if !record.awards.isEmpty { Text(record.awards.joined(separator: " · ")).note() }
        }
    }
}

enum CareerText {
    static func batting(_ line: BattingLine) -> String {
        "\(line.games)경기 타율 \(String(format: "%.3f", line.average)) \(line.homeRuns)홈런 \(line.runsBattedIn)타점"
    }

    static func pitching(_ line: PitchingLine) -> String {
        "\(line.games)경기 \(line.wins)승 \(line.losses)패 \(line.saves)세 평균자책점 \(String(format: "%.2f", line.era))"
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

// MARK: - 홈

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

// MARK: - 훈련

struct CareerTrainingTab: View {
    @EnvironmentObject var model: AppModel
    let game: Game

    var body: some View {
        VStack(spacing: 10) {
            if let career = game.career, let me = game.myPlayer {
                Card("훈련", trailing: "남은 횟수 \(career.sessionsLeft)/\(Balance.careerSessionsPerMatch)") {
                    KeyValueRow(key: "훈련 포인트", value: "\(game.funds.balance.formatted()) P")
                    Divider()
                    ForEach(game.careerTrainableKeys, id: \.self) { key in
                        drillRow(key, me)
                    }
                    Text(trainingNote(career, me)).note().fixedSize(horizontal: false, vertical: true)
                }

                Card("한계 돌파 훈련") {
                    Text("큰 포인트를 들여 능력의 한계를 조금 넓힙니다. 능력치가 더 오르지 않을 때 씁니다. 훈련 횟수를 한 번 씁니다.").note()
                    HStack {
                        Text("한계 +1").font(.callout)
                        Spacer()
                        Button("\(Format.tokens(game.careerBreakthroughCost)) P") {
                            model.perform { try $0.breakThroughCareer() }
                        }
                        .disabled(game.careerBreakthroughBlockedReason != nil)
                    }
                    if let reason = game.careerBreakthroughBlockedReason { Text(reason).note() }
                }

                Card("내 선수") {
                    KeyValueRow(key: "능력", value: "\(Int(me.ability)) (\(me.grade))")
                    KeyValueRow(key: "시즌 시작 때보다", value: String(format: "%+.1f", me.ability - me.abilityAtSeasonStart))
                    KeyValueRow(key: "최고 능력", value: "\(Int(career.peakAbility))")
                    KeyValueRow(key: "지금까지 훈련", value: "\(career.trainingCount)회")
                    Text("능력은 포지션에 중요한 능력치일수록 크게 반영됩니다. 훈련하지 않아도 경기를 뛰면 조금씩 큽니다. 34세부터는 시즌마다 능력치가 떨어집니다.").note()
                }
            }
        }
    }

    private func drillRow(_ key: Attributes.Key, _ me: Player) -> some View {
        let value = me.attributes[key]
        let blocked = game.careerTrainingBlockedReason(key)
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(CareerDrill.name(key)).font(.callout.weight(.medium))
                Text("\(key.label) \(Int(value))").note()
            }
            .frame(width: 118, alignment: .leading)
            Bar(fraction: value / 99, color: .accentColor)
            Button("+1 · \(Format.tokens(game.careerTrainingCost(key))) P") {
                model.perform { try $0.trainCareer(key) }
            }
            .disabled(blocked != nil)
            .help(blocked ?? "\(key.label) +1")
        }
    }

    private func trainingNote(_ career: Career, _ me: Player) -> String {
        if me.age >= Balance.careerTrainingAgeLimit {
            return "\(Balance.careerTrainingAgeLimit)세부터는 훈련으로 능력치를 올릴 수 없습니다."
        }
        if career.sessionsLeft <= 0 { return "오늘 훈련을 마쳤습니다. 다음 경기를 치르면 다시 \(Balance.careerSessionsPerMatch)번 훈련할 수 있습니다." }
        return "경기와 경기 사이에 \(Balance.careerSessionsPerMatch)번까지 훈련합니다. 능력치가 높을수록 포인트가 많이 듭니다. 쓰지 않은 포인트는 그대로 남습니다."
    }
}

// MARK: - 커리어

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
