import Foundation

/// 축구 경기에 나선 선수 한 명. 능력치는 경기를 시작할 때의 값이고, 체력(`energy`)에 따라 깎여 쓰인다.
public struct FootballPlayerState: Codable, Equatable, Sendable {
    public var playerID: PlayerID
    public var name: String
    /// 원래 포지션.
    public var natural: Position
    /// 이 경기에서 서는 자리.
    public var slot: Position
    public var shooting: Double, passing: Double, dribbling: Double, tackling: Double
    public var speed: Double, physical: Double, keeping: Double, stamina: Double
    public var traits: [Trait]
    /// 남은 체력 (1 = 가득).
    public var energy = 1.0
    public var isOnPitch: Bool
    public var hasPlayed: Bool
    public var sentOff = false
    public var line = FootballLine()

    public init(
        playerID: PlayerID, name: String, natural: Position, slot: Position,
        shooting: Double, passing: Double, dribbling: Double, tackling: Double,
        speed: Double, physical: Double, keeping: Double, stamina: Double,
        traits: [Trait], starts: Bool
    ) {
        self.playerID = playerID
        self.name = name
        self.natural = natural
        self.slot = slot
        self.shooting = shooting
        self.passing = passing
        self.dribbling = dribbling
        self.tackling = tackling
        self.speed = speed
        self.physical = physical
        self.keeping = keeping
        self.stamina = stamina
        self.traits = traits
        self.isOnPitch = starts
        self.hasPlayed = starts
        if starts { line.games = 1 }
    }

    /// 지치면 모든 능력이 조금씩 깎인다.
    var fatigue: Double { 0.75 + 0.25 * energy }
}

public struct FootballSide: Codable, Equatable, Sendable {
    public var teamID: TeamID
    public var name: String
    public var shortName: String
    /// 앞의 11명이 선발, 나머지가 벤치.
    public var players: [FootballPlayerState]
    public var tactic: Tactic
    public var goals = 0
    public var shots = 0, shotsOnTarget = 0, corners = 0, fouls = 0, offsides = 0
    public var yellowCards = 0, redCards = 0
    /// 공을 갖고 있던 틱 수 (점유율 계산용).
    public var possession = 0
    public var subsUsed = 0
    public var shootoutGoals = 0, shootoutKicks = 0

    public init(teamID: TeamID, name: String, shortName: String, players: [FootballPlayerState], tactic: Tactic) {
        self.teamID = teamID
        self.name = name
        self.shortName = shortName
        self.players = players
        self.tactic = tactic
    }

    var onPitchCount: Int { players.filter(\.isOnPitch).count }

    /// 해당 자리에 선 선수들의 평균. 아무도 없으면 아주 낮은 값.
    func mean(
        _ slots: [Position], weights: [Position: Double] = [:], _ value: (FootballPlayerState) -> Double
    ) -> Double {
        var total = 0.0, weight = 0.0
        for player in players where player.isOnPitch && slots.contains(player.slot) {
            let w = weights[player.slot] ?? 1
            total += value(player) * player.fatigue * w
            weight += w
        }
        return weight > 0 ? total / weight : 10
    }

    /// 퇴장으로 모자란 인원만큼 깎이는 값.
    var shortHanded: Double { Double(max(0, 11 - onPitchCount)) * 4 }

    var keeperIndex: Int? { players.firstIndex { $0.isOnPitch && $0.slot == .goalkeeper } }
}

public struct FootballRules: Codable, Equatable, Sendable {
    /// 승부가 나야 하는 경기 (승강 플레이오프): 연장과 승부차기를 쓴다.
    public var mustHaveWinner = false
    /// 홈 보정 (0.02 = +2%).
    public var homeEdge = 0.02

    public init(mustHaveWinner: Bool = false, homeEdge: Double = 0.02) {
        self.mustHaveWinner = mustHaveWinner
        self.homeEdge = homeEdge
    }
}

/// 진행 중인 축구 경기 한 판. `step()`을 부를 때마다 경기 시간 20초(승부차기는 한 번의 킥)가 흐른다.
/// 난수 상태까지 통째로 저장되므로, 저장했다가 다시 읽어도 똑같이 이어진다.
public struct FootballMatch: Codable, Equatable, Sendable {
    public enum Period: String, Codable, Sendable {
        case firstHalf, secondHalf, extraFirst, extraSecond, shootout, finished

        var length: Int {
            switch self {
            case .firstHalf, .secondHalf: 45 * 60
            case .extraFirst, .extraSecond: 15 * 60
            default: 0
            }
        }

        var startMinute: Int {
            switch self {
            case .firstHalf: 0
            case .secondHalf: 45
            case .extraFirst: 90
            case .extraSecond: 105
            default: 120
            }
        }
    }

    enum SetPiece: String, Codable, Sendable { case corner, freeKick, penalty }

    public static let secondsPerStep = 20
    static let logLimit = 80

    public var rules: FootballRules
    public var home: FootballSide
    public var away: FootballSide
    public var rng: SeededRNG

    public private(set) var period = Period.firstHalf
    /// 이번 전·후반에서 흐른 시간(초).
    public private(set) var clock = 0
    /// 이번 전·후반의 추가시간(초).
    public private(set) var added = 0
    public private(set) var homeHasBall = false
    /// 공이 있는 구역. 공을 가진 팀 기준으로 0 = 자기 진영, 1 = 중원, 2 = 상대 진영.
    public private(set) var zone = 1
    public private(set) var isFinished = false
    /// 최근 문자 중계 (오래된 것부터).
    public private(set) var log: [MatchEvent] = []

    private var pending: SetPiece?
    private var announcedAdded = false
    private var homeKicksNext = false

    public init(away: FootballSide, home: FootballSide, rules: FootballRules, seed: UInt64) {
        self.rules = rules
        self.away = away
        self.home = home
        self.rng = SeededRNG(seed: seed)
        self.added = rng.int(1...4) * 60
    }

    // MARK: 읽기

    public var result: MatchResult? {
        guard isFinished else { return nil }
        if home.goals != away.goals { return home.goals > away.goals ? .homeWin : .awayWin }
        if home.shootoutGoals != away.shootoutGoals {
            return home.shootoutGoals > away.shootoutGoals ? .homeWin : .awayWin
        }
        return .draw
    }

    public var wentToShootout: Bool { home.shootoutKicks > 0 }

    /// "67'", "45+2'", "승부차기" 같은 경기 시간 표시.
    public var clockLabel: String {
        switch period {
        case .shootout: return "승부차기"
        case .finished: return "종료"
        default:
            let length = period.length
            if clock >= length {
                return "\(period.startMinute + length / 60)+\((clock - length) / 60 + 1)'"
            }
            return "\(period.startMinute + clock / 60 + 1)'"
        }
    }

    public var periodLabel: String {
        switch period {
        case .firstHalf: "전반"
        case .secondHalf: "후반"
        case .extraFirst: "연장 전반"
        case .extraSecond: "연장 후반"
        case .shootout: "승부차기"
        case .finished: "경기 종료"
        }
    }

    /// 지금까지 흐른 경기 시간(분).
    public var minute: Int { period.startMinute + min(clock, period.length) / 60 }

    /// 홈 팀 점유율 (0~1).
    public var homePossession: Double {
        let total = home.possession + away.possession
        return total == 0 ? 0.5 : Double(home.possession) / Double(total)
    }

    /// 홈 팀 기준으로 공이 있는 구역 (0 = 홈 진영, 2 = 원정 진영).
    public var ballZoneFromHome: Int { homeHasBall ? zone : 2 - zone }

    public var scoreText: String {
        var text = "\(away.shortName) \(away.goals) : \(home.goals) \(home.shortName)"
        if wentToShootout { text += " (승부차기 \(away.shootoutGoals):\(home.shootoutGoals))" }
        return text
    }

    private var attacking: FootballSide {
        get { homeHasBall ? home : away }
        set { if homeHasBall { home = newValue } else { away = newValue } }
    }

    private var defending: FootballSide {
        get { homeHasBall ? away : home }
        set { if homeHasBall { away = newValue } else { home = newValue } }
    }

    // MARK: 진행

    /// 한 틱을 진행하고, 그동안 일어난 일을 돌려준다.
    @discardableResult
    public mutating func step() -> [MatchEvent] {
        guard !isFinished else { return [] }
        var events: [MatchEvent] = []

        if period == .shootout {
            takeShootoutKick(&events)
        } else if clock >= period.length + added {
            endPeriod(&events)
        } else {
            if clock >= period.length, !announcedAdded {
                announcedAdded = true
                say(&events, .inning, "추가시간 \(added / 60)분")
            }
            substitute(&events)
            if let piece = pending {
                pending = nil
                resolve(piece, &events)
            } else {
                play(&events)
            }
            tire()
            attacking.possession += 1
            clock += Self.secondsPerStep
        }

        log.append(contentsOf: events)
        if log.count > Self.logLimit { log.removeFirst(log.count - Self.logLimit) }
        return events
    }

    /// 화면 없이 끝까지 돌린다 (다른 구장 경기와 테스트용).
    public mutating func runToEnd() {
        while !isFinished { step() }
    }

    private func say(_ events: inout [MatchEvent], _ kind: MatchEvent.Kind, _ text: String) {
        events.append(MatchEvent(kind, "\(clockLabel) \(text)"))
    }

    // MARK: 능력 비교

    private var edgePoints: Double { 2.0 + rules.homeEdge * 100 }

    private func bonus(home isHome: Bool) -> Double { isHome ? edgePoints : 0 }

    /// 공격 쪽이 수비 쪽보다 나은 정도를 확률 배율로 바꾼다.
    private func ratio(_ attack: Double, _ defense: Double) -> Double {
        let a = attack + attacking.tactic.attackShift - attacking.shortHanded + bonus(home: homeHasBall)
        let d = defense - defending.tactic.attackShift - defending.shortHanded + bonus(home: !homeHasBall)
        return clamp(exp((a - d) / 90), 0.4, 2.5)
    }

    private mutating func flip(to newZone: Int) {
        homeHasBall.toggle()
        zone = newZone
    }

    // MARK: 한 틱

    private mutating func play(_ events: inout [MatchEvent]) {
        let roll = rng.unit()
        switch zone {
        case 0:
            let m = ratio(
                attacking.mean([.defender, .midfielder]) { $0.passing },
                defending.mean([.forward, .midfielder]) { $0.tackling * 0.5 + $0.speed * 0.5 })
            let advance = clamp(0.58 * m, 0.25, 0.85)
            let lose = clamp(0.08 / m, 0.02, 0.25)
            if roll < advance {
                zone = 1
                say(&events, .play, "\(attacking.shortName) \(holder([.defender, .midfielder])) \(rng.pick(Self.buildUpLines))")
            } else if roll < advance + lose {
                let thief = name(of: defending, in: [.forward, .midfielder])
                flip(to: 2)
                say(&events, .play, "\(attacking.shortName) \(thief), 높은 위치에서 공을 뺏습니다!")
            } else {
                say(&events, .play, "\(attacking.shortName), 뒤에서 공을 돌립니다")
            }
        case 1:
            let m = ratio(
                attacking.mean([.midfielder]) { $0.passing * 0.6 + $0.dribbling * 0.4 },
                defending.mean([.midfielder]) { $0.tackling * 0.7 + $0.physical * 0.3 })
            let advance = clamp(0.34 * m, 0.12, 0.7)
            let lose = clamp(0.27 / m, 0.08, 0.5)
            if roll < advance {
                zone = 2
                say(&events, .play, "\(attacking.shortName) \(holder([.midfielder, .forward])) \(rng.pick(Self.advanceLines))")
            } else if roll < advance + lose {
                if rng.chance(0.42) {
                    foul(dangerous: false, &events)
                } else {
                    let thief = name(of: defending, in: [.midfielder, .defender])
                    flip(to: 1)
                    say(&events, .play, "\(attacking.shortName) \(thief) \(rng.pick(Self.interceptLines))")
                }
            } else {
                say(&events, .play, "\(attacking.shortName), 중원에서 기회를 엿봅니다")
            }
        default:
            let m = ratio(
                attacking.mean([.forward, .midfielder], weights: [.forward: 2]) {
                    $0.dribbling * 0.4 + $0.speed * 0.3 + $0.passing * 0.3
                },
                defending.mean([.defender]) { $0.tackling * 0.6 + $0.physical * 0.2 + $0.speed * 0.2 })
            let shot = clamp(0.21 * m, 0.07, 0.5)
            let penalty = clamp(0.006 * m, 0.002, 0.015)
            let offside = 0.035
            let lose = clamp(0.33 / m, 0.12, 0.6)
            if roll < shot {
                shoot(&events)
            } else if roll < shot + penalty {
                foul(dangerous: true, penalty: true, &events)
            } else if roll < shot + penalty + offside {
                let runner = holder([.forward])
                attacking.offsides += 1
                say(&events, .play, "\(attacking.shortName) \(runner), 오프사이드")
                flip(to: 0)
            } else if roll < shot + penalty + offside + lose {
                let kind = rng.unit()
                if kind < 0.22 {
                    foul(dangerous: true, &events)
                } else if kind < 0.36 {
                    say(&events, .play, "\(defending.shortName) \(name(of: defending, in: [.defender])), 크로스를 걷어내 코너킥")
                    awardCorner()
                } else {
                    let thief = name(of: defending, in: [.defender])
                    let counter = rng.chance(0.2)
                    flip(to: counter ? 1 : 0)
                    say(&events, .play, "\(attacking.shortName) \(thief) \(counter ? "끊어내고 역습!" : rng.pick(Self.clearLines))")
                }
            } else {
                say(&events, .play, "\(attacking.shortName) \(holder([.forward, .midfielder])) \(rng.pick(Self.probeLines))")
            }
        }
    }

    /// 공을 가진 팀에서 이 자리의 선수 이름을 하나 고른다.
    private mutating func holder(_ slots: [Position]) -> String {
        name(of: attacking, in: slots)
    }

    private mutating func name(of side: FootballSide, in slots: [Position]) -> String {
        let names = side.players.filter { $0.isOnPitch && slots.contains($0.slot) }.map(\.name)
        let fallback = side.players.filter { $0.isOnPitch }.map(\.name)
        let pool = names.isEmpty ? fallback : names
        return pool.isEmpty ? side.shortName : rng.pick(pool)
    }

    /// 가중치로 공격 팀 선수 한 명을 고른다.
    private mutating func pickAttacker(
        excluding: Int? = nil, _ weight: (FootballPlayerState) -> Double
    ) -> Int? {
        let side = attacking
        var indices: [Int] = []
        var weights: [Double] = []
        for (index, player) in side.players.enumerated()
        where player.isOnPitch && player.slot != .goalkeeper && index != excluding {
            indices.append(index)
            weights.append(max(0.01, weight(player)))
        }
        guard !indices.isEmpty else { return nil }
        return indices[rng.weighted(weights)]
    }

    private static func slotWeight(_ slot: Position, forward: Double, midfielder: Double, defender: Double) -> Double {
        switch slot {
        case .forward: forward
        case .midfielder: midfielder
        default: defender
        }
    }

    private var isTightForAttacker: Bool {
        let diff = attacking.goals - defending.goals
        return diff == 0 || diff == -1
    }

    private func shootingValue(_ player: FootballPlayerState) -> Double {
        var value = player.shooting * player.fatigue
        if player.traits.contains(.clutch), isTightForAttacker { value += 6 }
        return value + bonus(home: homeHasBall)
    }

    private func keepingValue(penalty: Bool = false) -> Double {
        let side = defending
        guard let index = side.keeperIndex else { return 8 }
        let keeper = side.players[index]
        var value = keeper.keeping * keeper.fatigue
        if penalty, keeper.traits.contains(.coolHead) { value += 8 }
        return value + bonus(home: !homeHasBall)
    }

    // MARK: 슈팅

    private mutating func shoot(_ events: inout [MatchEvent]) {
        guard let shooterIndex = pickAttacker({
            Self.slotWeight($0.slot, forward: 3, midfielder: 1.4, defender: 0.35) * (0.5 + $0.shooting / 100)
        }) else { return }
        var assistIndex: Int?
        if rng.chance(0.7) {
            assistIndex = pickAttacker(excluding: shooterIndex) {
                Self.slotWeight($0.slot, forward: 1.5, midfielder: 2, defender: 0.8) * (0.5 + $0.passing / 100)
            }
        }
        let shooter = attacking.players[shooterIndex]
        let power = shootingValue(shooter)
        attacking.shots += 1
        attacking.players[shooterIndex].line.shots += 1

        let wall = defending.mean([.defender]) { $0.tackling } - defending.shortHanded
        if rng.chance(clamp(0.24 * exp((wall - power) / 100), 0.08, 0.5)) {
            let blocker = name(of: defending, in: [.defender])
            if rng.chance(0.45) {
                say(&events, .play, "\(shooter.name) 슛! \(blocker) 몸으로 막아 코너킥")
                awardCorner()
            } else {
                say(&events, .play, "\(shooter.name) 슛! \(blocker) 막아냅니다")
                flip(to: 0)
            }
            return
        }
        guard rng.chance(clamp(0.41 + (power - keepingValue()) / 300, 0.2, 0.65)) else {
            say(&events, .play, "\(shooter.name) \(rng.pick(Self.missLines))")
            flip(to: 0)
            return
        }
        attacking.shotsOnTarget += 1
        attacking.players[shooterIndex].line.shotsOnTarget += 1
        let keeping = keepingValue()
        if rng.chance(clamp(0.335 * exp((power - keeping) / 90), 0.06, 0.6)) {
            score(shooterIndex, assist: assistIndex, how: rng.pick(Self.goalLines), &events)
        } else {
            saved(by: shooter.name, &events)
        }
    }

    private mutating func saved(by shooterName: String, _ events: inout [MatchEvent]) {
        var keeperName = "골키퍼"
        if let index = defending.keeperIndex {
            defending.players[index].line.saves += 1
            keeperName = defending.players[index].name
        }
        if rng.chance(0.3) {
            say(&events, .play, "\(shooterName) 유효 슈팅! \(keeperName) 쳐내서 코너킥")
            awardCorner()
        } else {
            say(&events, .play, "\(shooterName) 슈팅, \(keeperName) \(rng.pick(Self.saveLines))")
            flip(to: 0)
        }
    }

    private mutating func awardCorner() {
        attacking.corners += 1
        zone = 2
        pending = .corner
    }

    private mutating func score(_ scorerIndex: Int, assist: Int?, how: String, _ events: inout [MatchEvent]) {
        attacking.goals += 1
        attacking.players[scorerIndex].line.goals += 1
        var text = "골! \(attacking.shortName) \(attacking.players[scorerIndex].name) \(how)"
        if let assist {
            attacking.players[assist].line.assists += 1
            text += " (도움 \(attacking.players[assist].name))"
        }
        if let keeper = defending.keeperIndex { defending.players[keeper].line.conceded += 1 }
        say(&events, .score, "\(text) — \(scoreText)")
        // 실점한 팀의 킥오프
        flip(to: 1)
    }

    // MARK: 세트피스

    private mutating func resolve(_ piece: SetPiece, _ events: inout [MatchEvent]) {
        switch piece {
        case .corner:
            let taker = holder([.midfielder])
            if rng.chance(0.16) {
                header(from: taker, what: "코너킥", &events)
            } else if rng.chance(0.7) {
                say(&events, .play, "\(attacking.shortName) \(taker) 코너킥, 수비가 걷어냅니다")
                flip(to: 0)
            } else {
                say(&events, .play, "\(attacking.shortName) \(taker) 코너킥, 흘러나온 공을 다시 잡습니다")
            }
        case .freeKick:
            guard let takerIndex = bestTaker() else { return }
            let taker = attacking.players[takerIndex]
            if rng.chance(0.35) {
                attacking.shots += 1
                attacking.players[takerIndex].line.shots += 1
                let power = shootingValue(taker) + (taker.traits.contains(.setPiece) ? 8 : 0)
                if rng.chance(clamp(0.36 + (power - keepingValue()) / 300, 0.15, 0.6)) {
                    attacking.shotsOnTarget += 1
                    attacking.players[takerIndex].line.shotsOnTarget += 1
                    if rng.chance(clamp(0.20 * exp((power - keepingValue()) / 90), 0.04, 0.45)) {
                        score(takerIndex, assist: nil, how: "프리킥 직접 골!", &events)
                    } else {
                        saved(by: "\(taker.name) 프리킥", &events)
                    }
                } else {
                    say(&events, .play, "\(taker.name) 프리킥, 벽을 넘겼지만 골대를 벗어납니다")
                    flip(to: 0)
                }
            } else if rng.chance(0.14) {
                header(from: taker.name, what: "프리킥", &events)
            } else {
                say(&events, .play, "\(taker.name) 프리킥을 올렸지만 수비가 먼저 걷어냅니다")
                flip(to: 0)
            }
        case .penalty:
            guard let takerIndex = bestTaker() else { return }
            let taker = attacking.players[takerIndex]
            attacking.shots += 1
            attacking.players[takerIndex].line.shots += 1
            let power = shootingValue(taker) + (taker.traits.contains(.setPiece) ? 8 : 0)
            if rng.chance(clamp(0.76 + (power - keepingValue(penalty: true)) / 250, 0.55, 0.92)) {
                attacking.shotsOnTarget += 1
                attacking.players[takerIndex].line.shotsOnTarget += 1
                score(takerIndex, assist: nil, how: "페널티킥 성공!", &events)
            } else if rng.chance(0.7) {
                attacking.shotsOnTarget += 1
                attacking.players[takerIndex].line.shotsOnTarget += 1
                var keeperName = "골키퍼"
                if let index = defending.keeperIndex {
                    defending.players[index].line.saves += 1
                    keeperName = defending.players[index].name
                }
                say(&events, .play, "\(taker.name) 페널티킥, \(keeperName) 막았습니다!")
                flip(to: 0)
            } else {
                say(&events, .play, "\(taker.name) 페널티킥, 골대를 벗어납니다!")
                flip(to: 0)
            }
        }
    }

    private func bestTaker() -> Int? {
        let side = attacking
        return side.players.indices
            .filter { side.players[$0].isOnPitch && side.players[$0].slot != .goalkeeper }
            .max {
                let a = side.players[$0], b = side.players[$1]
                let av = a.shooting + (a.traits.contains(.setPiece) ? 8 : 0)
                let bv = b.shooting + (b.traits.contains(.setPiece) ? 8 : 0)
                return (av, -a.playerID) < (bv, -b.playerID)
            }
    }

    private mutating func header(from taker: String, what: String, _ events: inout [MatchEvent]) {
        guard let index = pickAttacker({
            Self.slotWeight($0.slot, forward: 2, midfielder: 1, defender: 1.5) * (0.4 + $0.physical / 100)
        }) else { return }
        let player = attacking.players[index]
        attacking.shots += 1
        attacking.players[index].line.shots += 1
        let power = (player.physical * 0.6 + player.shooting * 0.4) * player.fatigue + bonus(home: homeHasBall)
        guard rng.chance(0.42) else {
            say(&events, .play, "\(taker) \(what), \(player.name) 헤더! 골대 위로 넘어갑니다")
            flip(to: 0)
            return
        }
        attacking.shotsOnTarget += 1
        attacking.players[index].line.shotsOnTarget += 1
        if rng.chance(clamp(0.28 * exp((power - keepingValue()) / 90), 0.06, 0.55)) {
            let assist = attacking.players.firstIndex { $0.isOnPitch && $0.name == taker && $0.playerID != player.playerID }
            score(index, assist: assist, how: "헤더 골!", &events)
        } else {
            saved(by: "\(player.name) 헤더", &events)
        }
    }

    // MARK: 반칙

    /// 수비 팀의 반칙. 공격 팀이 공을 그대로 갖는다.
    private mutating func foul(dangerous: Bool, penalty: Bool = false, _ events: inout [MatchEvent]) {
        var indices: [Int] = []
        var weights: [Double] = []
        for (index, player) in defending.players.enumerated() where player.isOnPitch {
            indices.append(index)
            weights.append(player.slot == .goalkeeper ? (penalty ? 0.4 : 0.02) : player.slot == .forward ? 1 : 2)
        }
        guard !indices.isEmpty else { return }
        let index = indices[rng.weighted(weights)]
        let fouler = defending.players[index]
        let victim = holder(zone == 2 ? [.forward, .midfielder] : [.midfielder])
        defending.fouls += 1

        var text = "\(defending.shortName) \(fouler.name), \(victim)에게 반칙"
        var sentOff = false
        let roll = rng.unit()
        if roll < (penalty ? 0.02 : 0.001) {
            sentOff = true
            text += ". 곧바로 퇴장!"
        } else if roll < (dangerous ? 0.24 : 0.13) {
            defending.yellowCards += 1
            defending.players[index].line.yellowCards += 1
            if defending.players[index].line.yellowCards >= 2 {
                sentOff = true
                text += ". 두 번째 경고로 퇴장!"
            } else {
                text += ". 경고"
            }
        }
        if penalty { text += " — 페널티킥!" } else if dangerous { text += " — 위험한 위치의 프리킥" }
        say(&events, sentOff ? .change : .play, text)

        if sentOff { sendOff(home: !homeHasBall, index: index, &events) }
        if penalty {
            zone = 2
            pending = .penalty
        } else if dangerous {
            zone = 2
            pending = .freeKick
        }
    }

    /// 퇴장 처리: 선수가 나가고, 골키퍼였으면 골문을 지킬 선수를 정한다.
    mutating func sendOff(home isHome: Bool, index: Int, _ events: inout [MatchEvent]) {
        var side = isHome ? home : away
        let wasKeeper = side.players[index].slot == .goalkeeper
        side.redCards += 1
        side.players[index].line.redCards += 1
        side.players[index].isOnPitch = false
        side.players[index].sentOff = true
        if isHome { home = side } else { away = side }
        if wasKeeper { replaceKeeper(home: isHome, &events) }
    }

    /// 골키퍼가 퇴장당했을 때: 벤치 골키퍼를 넣거나, 필드 선수가 장갑을 낀다.
    private mutating func replaceKeeper(home isHome: Bool, _ events: inout [MatchEvent]) {
        var side = isHome ? home : away
        defer { if isHome { home = side } else { away = side } }
        let bench = side.players.indices.first {
            !side.players[$0].hasPlayed && side.players[$0].natural == .goalkeeper
        }
        if let bench, side.subsUsed < Balance.footballMaxSubs,
           let out = side.players.indices.filter({ side.players[$0].isOnPitch && side.players[$0].slot == .forward })
            .min(by: { side.players[$0].energy < side.players[$1].energy })
            ?? side.players.indices.filter({ side.players[$0].isOnPitch }).min(by: { side.players[$0].energy < side.players[$1].energy }) {
            side.players[out].isOnPitch = false
            side.players[bench].isOnPitch = true
            side.players[bench].hasPlayed = true
            side.players[bench].slot = .goalkeeper
            side.players[bench].line.games = 1
            side.subsUsed += 1
            say(&events, .change, "\(side.shortName) 교체: \(side.players[out].name) 나가고 골키퍼 \(side.players[bench].name) 들어옵니다")
        } else if let stand = side.players.indices.filter({ side.players[$0].isOnPitch })
            .max(by: { side.players[$0].keeping < side.players[$1].keeping }) {
            side.players[stand].slot = .goalkeeper
            say(&events, .change, "\(side.shortName) \(side.players[stand].name), 골키퍼 장갑을 낍니다")
        }
    }

    // MARK: 체력과 교체

    private mutating func tire() {
        for index in home.players.indices where home.players[index].isOnPitch { Self.drain(&home.players[index]) }
        for index in away.players.indices where away.players[index].isOnPitch { Self.drain(&away.players[index]) }
    }

    private static func drain(_ player: inout FootballPlayerState) {
        var amount = 0.0019 * (1.25 - player.stamina / 100 * 0.7)
        if player.traits.contains(.ironLungs) { amount *= 0.7 }
        if player.slot == .goalkeeper { amount *= 0.3 }
        player.energy = max(0.2, player.energy - amount)
    }

    /// 60분 이후 지친 선수부터 같은 포지션의 벤치 선수로 바꾼다. 한 틱에 한 팀 한 명.
    private mutating func substitute(_ events: inout [MatchEvent]) {
        guard minute >= 60 else { return }
        let threshold = 0.66
        // 한꺼번에 바꾸지 않고 6분에 한 명꼴로 바꾼다.
        let allowed = min(Balance.footballMaxSubs, (minute - 55) / 6)
        for isHome in [true, false] {
            var side = isHome ? home : away
            guard side.subsUsed < allowed else { continue }
            guard let out = side.players.indices
                .filter({ side.players[$0].isOnPitch && side.players[$0].slot != .goalkeeper && side.players[$0].energy < threshold })
                .min(by: { (side.players[$0].energy, $0) < (side.players[$1].energy, $1) })
            else { continue }
            let slot = side.players[out].slot
            let bench = side.players.indices.filter {
                !side.players[$0].hasPlayed && side.players[$0].natural != .goalkeeper
            }
            guard let incoming = bench.first(where: { side.players[$0].natural == slot }) ?? bench.first else { continue }
            side.players[out].isOnPitch = false
            side.players[incoming].isOnPitch = true
            side.players[incoming].hasPlayed = true
            side.players[incoming].slot = slot
            side.players[incoming].line.games = 1
            side.subsUsed += 1
            say(&events, .change, "\(side.shortName) 교체: \(side.players[out].name) 나가고 \(side.players[incoming].name) 들어옵니다")
            if isHome { home = side } else { away = side }
        }
    }

    // MARK: 전·후반 끝

    private mutating func endPeriod(_ events: inout [MatchEvent]) {
        let tied = home.goals == away.goals
        switch period {
        case .firstHalf:
            say(&events, .inning, "전반 종료. \(scoreText)")
            start(.secondHalf, homeKicksOff: true)
        case .secondHalf:
            if rules.mustHaveWinner, tied {
                say(&events, .inning, "90분 종료. \(scoreText) — 연장전으로 갑니다")
                start(.extraFirst, homeKicksOff: false)
            } else {
                finish(&events)
            }
        case .extraFirst:
            say(&events, .inning, "연장 전반 종료. \(scoreText)")
            start(.extraSecond, homeKicksOff: true)
        case .extraSecond:
            if tied {
                say(&events, .inning, "연장 종료. \(scoreText) — 승부차기로 갑니다")
                period = .shootout
                homeKicksNext = rng.chance(0.5)
            } else {
                finish(&events)
            }
        default:
            finish(&events)
        }
    }

    private mutating func start(_ next: Period, homeKicksOff: Bool) {
        period = next
        clock = 0
        added = rng.int(next == .secondHalf ? 2...5 : 1...3) * 60
        announcedAdded = false
        pending = nil
        homeHasBall = homeKicksOff
        zone = 1
    }

    // MARK: 승부차기

    private mutating func takeShootoutKick(_ events: inout [MatchEvent]) {
        let isHome = homeKicksNext
        homeHasBall = isHome
        var side = isHome ? home : away
        let kickers = side.players.indices.filter { side.players[$0].isOnPitch }
            .sorted { (side.players[$0].shooting, -$0) > (side.players[$1].shooting, -$1) }
        guard !kickers.isEmpty else {
            finish(&events)
            return
        }
        let kicker = side.players[kickers[side.shootoutKicks % kickers.count]]
        let power = kicker.shooting + (kicker.traits.contains(.setPiece) ? 8 : 0)
        let scored = rng.chance(clamp(0.75 + (power - keepingValue(penalty: true)) / 250, 0.5, 0.92))
        side.shootoutKicks += 1
        if scored { side.shootoutGoals += 1 }
        if isHome { home = side } else { away = side }
        events.append(MatchEvent(
            scored ? .score : .play,
            "승부차기 \(side.shortName) \(side.shootoutKicks)번 \(kicker.name), \(scored ? "성공" : "실축") — \(away.shootoutGoals):\(home.shootoutGoals)"))
        homeKicksNext.toggle()

        let hk = home.shootoutKicks, ak = away.shootoutKicks
        let hg = home.shootoutGoals, ag = away.shootoutGoals
        if hk <= 5, ak <= 5 {
            if hg > ag + (5 - ak) || ag > hg + (5 - hk) { finish(&events) }
        }
        if !isFinished, hk == ak, hk >= 5, hg != ag { finish(&events) }
    }

    private mutating func finish(_ events: inout [MatchEvent]) {
        isFinished = true
        // 무실점 경기: 끝까지 골문을 지킨 골키퍼에게 준다.
        for isHome in [true, false] {
            let conceded = isHome ? away.goals : home.goals
            guard conceded == 0 else { continue }
            if isHome, let index = home.keeperIndex { home.players[index].line.cleanSheets += 1 }
            if !isHome, let index = away.keeperIndex { away.players[index].line.cleanSheets += 1 }
        }
        let summary: String
        switch result {
        case .homeWin: summary = "\(home.name) 승리"
        case .awayWin: summary = "\(away.name) 승리"
        default: summary = "무승부"
        }
        period = .finished
        events.append(MatchEvent(.end, "경기 종료. \(scoreText), \(summary)"))
    }

    // MARK: 중계 문장

    static let buildUpLines = ["전방으로 패스를 연결합니다", "측면으로 공을 풀어 나옵니다", "길게 넘겨 줍니다", "차분하게 올라옵니다"]
    static let advanceLines = ["오른쪽을 돌파합니다", "왼쪽 측면을 파고듭니다", "스루패스!", "수비 사이로 찔러 줍니다", "드리블로 치고 들어갑니다"]
    static let interceptLines = ["패스를 가로챕니다", "태클로 공을 따냅니다", "몸싸움에서 이겨 공을 뺏습니다"]
    static let clearLines = ["걷어냅니다", "태클 성공", "크로스를 머리로 끊어냅니다", "공을 뺏어냅니다"]
    static let probeLines = ["크로스를 노립니다", "페널티 박스 앞에서 공을 돌립니다", "수비를 앞에 두고 틈을 봅니다", "원투 패스를 주고받습니다"]
    static let missLines = ["슈팅, 골대 옆으로 벗어납니다", "중거리 슛! 크게 뜹니다", "슈팅, 골대를 살짝 넘어갑니다", "발리슛, 빗맞았습니다"]
    static let saveLines = ["정면에서 잡아냅니다", "몸을 날려 막아냅니다", "안전하게 품에 안습니다"]
    static let goalLines = ["오른발 슛이 구석에 꽂힙니다!", "침착하게 밀어 넣습니다!", "중거리 슛이 그물을 흔듭니다!", "골키퍼를 넘기는 슛!", "왼발로 마무리합니다!"]
}
