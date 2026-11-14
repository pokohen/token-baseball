import Foundation

/// 진행 중인 경기 한 판. `step()`을 부를 때마다 공 하나(또는 투구 사이 이벤트 하나)가 진행된다.
/// 난수 상태까지 통째로 저장되므로, 저장했다가 다시 읽어도 똑같이 이어진다.
public struct MatchState: Codable, Equatable, Sendable {
    public var rules: MatchRules
    public var away: MatchTeam
    public var home: MatchTeam
    public var rng: SeededRNG

    public private(set) var inning = 1
    public private(set) var isBottom = false
    public private(set) var outs = 0
    public private(set) var balls = 0
    public private(set) var strikes = 0
    /// 1루, 2루, 3루.
    public private(set) var bases: [Runner?] = [nil, nil, nil]
    /// 양 팀이 던진 공의 수.
    public private(set) var pitchCount = 0
    public private(set) var isFinished = false
    /// 최근 문자 중계 (오래된 것부터).
    public private(set) var log: [MatchEvent] = []

    private var pitchesThisPA = 0
    private var plateAppearanceStarted = false
    /// 지금 앞서 있는 팀 (true = 홈). 동점이면 nil.
    private var leaderIsHome: Bool?
    private var winPitcherIndex: Int?
    private var lossPitcherIndex: Int?

    static let logLimit = 80

    public init(away: MatchTeam, home: MatchTeam, rules: MatchRules, seed: UInt64) {
        self.rules = rules
        self.away = away
        self.home = home
        self.rng = SeededRNG(seed: seed)
        for index in self.away.batters.indices { self.away.batters[index].line.games = 1 }
        for index in self.home.batters.indices { self.home.batters[index].line.games = 1 }
        Self.enter(&self.away, pitcher: 0, lead: 0, asStarter: true)
        Self.enter(&self.home, pitcher: 0, lead: 0, asStarter: true)
    }

    private static func enter(_ team: inout MatchTeam, pitcher index: Int, lead: Int, asStarter: Bool) {
        team.pitcherIndex = index
        team.pitchers[index].hasEntered = true
        team.pitchers[index].line.games = 1
        team.pitchers[index].line.starts = asStarter ? 1 : 0
        team.pitchers[index].leadOnEntry = lead
    }

    // MARK: 읽기

    public var result: MatchResult? {
        guard isFinished else { return nil }
        if home.runs > away.runs { return .homeWin }
        if away.runs > home.runs { return .awayWin }
        return .draw
    }

    public var inningLabel: String { "\(inning)회\(isBottom ? "말" : "초")" }

    public var batting: MatchTeam {
        get { isBottom ? home : away }
        set { if isBottom { home = newValue } else { away = newValue } }
    }

    public var fielding: MatchTeam {
        get { isBottom ? away : home }
        set { if isBottom { away = newValue } else { home = newValue } }
    }

    public var currentBatter: MatchBatter { batting.batters[batting.battingIndex] }
    public var currentPitcher: MatchPitcher { fielding.pitchers[fielding.pitcherIndex] }

    // MARK: 진행

    /// 공 하나를 진행하고, 그동안 일어난 일을 돌려준다.
    @discardableResult
    public mutating func step() -> [MatchEvent] {
        guard !isFinished else { return [] }
        var events: [MatchEvent] = []

        if !plateAppearanceStarted {
            beginPlateAppearance(&events)
        }
        if !betweenPitches(&events) {
            throwPitch(&events)
        }

        log.append(contentsOf: events)
        if log.count > Self.logLimit { log.removeFirst(log.count - Self.logLimit) }
        return events
    }

    /// 화면 없이 끝까지 돌린다 (다른 구장 경기와 테스트용).
    public mutating func runToEnd() {
        while !isFinished { step() }
    }

    private mutating func beginPlateAppearance(_ events: inout [MatchEvent]) {
        while batting.runsByInning.count < inning { batting.runsByInning.append(0) }
        managePitching(&events)
        plateAppearanceStarted = true
        pitchesThisPA = 0
    }

    // MARK: 투수 교체

    private func capacity(of pitcher: MatchPitcher) -> Double {
        pitcher.role == .starter ? 35 + pitcher.stamina * 0.8 : 22 + pitcher.stamina * 0.45
    }

    private mutating func managePitching(_ events: inout [MatchEvent]) {
        var team = fielding
        let current = team.pitchers[team.pitcherIndex]
        let lead = team.runs - batting.runs
        let cleanStart = outs == 0 && bases.allSatisfy { $0 == nil }
        var next: Int?

        if let closer = team.pitchers.firstIndex(where: { $0.role == .closer && !$0.hasEntered }),
           inning >= team.policy.closerFromInning, lead >= 1, lead <= team.policy.closerMaxLead, cleanStart {
            next = closer
        } else {
            let pull: Bool
            if team.pitcherIndex == 0 {
                let limit = min(team.policy.starterPitchLimit, Int(capacity(of: current)) + 15)
                pull = current.line.pitches >= limit || current.line.runs >= team.policy.starterRunLimit
            } else if current.role == .closer {
                pull = current.line.pitches >= 45
            } else {
                pull = current.line.pitches >= 38 || current.line.runs >= 4
            }
            if pull {
                next = team.pitchers.firstIndex { !$0.hasEntered && $0.role != .closer }
                    ?? team.pitchers.firstIndex { !$0.hasEntered }
            }
        }

        guard let next, next != team.pitcherIndex else { return }
        Self.enter(&team, pitcher: next, lead: lead, asStarter: false)
        fielding = team
        events.append(MatchEvent(
            .change, "\(team.shortName) 투수 교체: \(current.name) → \(team.pitchers[next].name)"))
    }

    // MARK: 투구 사이 이벤트

    /// 도루, 폭투. 일이 일어났으면 true (이번 스텝에는 공을 던지지 않는다).
    private mutating func betweenPitches(_ events: inout [MatchEvent]) -> Bool {
        guard bases.contains(where: { $0 != nil }) else { return false }
        let pitcher = currentPitcher

        // 도루: 1루 주자, 2루가 비어 있을 때
        if let runner = bases[0], bases[1] == nil {
            let stealer = batting.batters[runner.batterIndex]
            let attempt = max(0, stealer.speed - 50) * 0.0012
            if rng.chance(attempt) {
                let catcherArm = fielding.batters.first { $0.position == .catcher }?.arm ?? 40
                let success = clamp(0.62 + (stealer.speed - catcherArm) * 0.006, 0.3, 0.92)
                if rng.chance(success) {
                    bases[1] = runner
                    bases[0] = nil
                    batting.batters[runner.batterIndex].line.steals += 1
                    events.append(MatchEvent(.running, "\(stealer.name) 2루 도루 성공!"))
                } else {
                    bases[0] = nil
                    recordOut()
                    events.append(MatchEvent(.running, "\(stealer.name) 2루 도루 실패, 아웃"))
                    if outs >= 3 { endHalfInning(&events) }
                }
                return true
            }
        }

        // 폭투
        let wild = 0.003 + max(0, 60 - pitcher.control) * 0.0002
        if rng.chance(wild) {
            events.append(MatchEvent(.running, "폭투! 주자들이 한 베이스씩 진루"))
            advanceAll(by: 1, rbiTo: nil, events: &events)
            checkWalkOff(&events)
            return true
        }
        return false
    }

    // MARK: 투구

    private enum PitchType: CaseIterable {
        case fastball, slider, curve, changeup, fork

        var name: String {
            switch self {
            case .fastball: "직구"
            case .slider: "슬라이더"
            case .curve: "커브"
            case .changeup: "체인지업"
            case .fork: "포크"
            }
        }

        var speedDrop: Double {
            switch self {
            case .fastball: 0
            case .slider: 12
            case .curve: 22
            case .changeup: 14
            case .fork: 10
            }
        }
    }

    private mutating func throwPitch(_ events: inout [MatchEvent]) {
        let batterIndex = batting.battingIndex
        let pitcherIndex = fielding.pitcherIndex
        let batter = batting.batters[batterIndex]
        let pitcher = fielding.pitchers[pitcherIndex]

        pitchCount += 1
        pitchesThisPA += 1
        fielding.pitchers[pitcherIndex].line.pitches += 1

        // 체력: 한계 투구 수를 넘기면 구위와 제구가 떨어진다.
        let over = max(0, Double(pitcher.line.pitches) - capacity(of: pitcher))
        var stuff = pitcher.stuff - over * 0.35
        var control = pitcher.control - over * 0.45
        var contact = batter.contact
        var power = batter.power
        let eye = batter.eye

        let scoringPosition = bases[1] != nil || bases[2] != nil
        if scoringPosition, pitcher.traits.contains(.coolHead) { stuff += 4; control += 4 }
        if scoringPosition, batter.traits.contains(.clutch) { contact += 5; power += 3 }
        if batter.traits.contains(.slowStarter), batter.line.plateAppearances == 0 { contact -= 6 }
        if batter.traits.contains(.leftyKiller), pitcher.throwsHand == .left { contact += 6; power += 4 }

        // 홈 보정
        let edge = rules.homeEdge * 100
        if isBottom {
            contact += edge
            power += edge * 0.5
        } else {
            stuff += edge
            control += edge * 0.5
        }

        // 구종과 구속
        let fastballWeight = max(0.3, 0.65 - pitcher.breaking * 0.003)
        let rest = 1 - fastballWeight
        let type = PitchType.allCases[rng.weighted([
            fastballWeight, rest * 0.40, rest * 0.24, rest * 0.24, rest * 0.12,
        ])]
        let isBreaking = type != .fastball
        let velocity = Int((108 + stuff * 0.48 - type.speedDrop + rng.gaussian() * 2).rounded())

        // 코스: 볼카운트가 불리하면 존 안쪽을 노린다.
        var intent = 0.50 + Double(balls - strikes) * 0.07
        if balls == 3 { intent += 0.12 }
        if strikes == 2, balls < 2 { intent -= 0.12 }
        intent = clamp(intent, 0.25, 0.85)
        let aimedInZone = rng.chance(intent)
        let inZone = aimedInZone
            ? rng.chance(clamp(0.66 + control * 0.003, 0.4, 0.95))
            : rng.chance(clamp(0.10 + (50 - control) * 0.001, 0.02, 0.2))
        let location = rng.pick(inZone
            ? ["한가운데", "몸쪽", "바깥쪽", "높은 코스", "낮은 코스"]
            : ["바깥쪽 빠지는", "몸쪽 깊은", "높은", "원바운드성"])
        let lead = "\(pitchesThisPA)구째 \(type.name) \(velocity)km, \(location)"

        // 스윙 판단
        let swings: Bool
        if inZone {
            var probability = 0.64
            if strikes == 2 { probability += 0.24 }
            if balls == 3, strikes < 2 { probability -= 0.10 }
            swings = rng.chance(probability)
        } else {
            var chase = 0.30 - (eye - 50) * 0.003
            if isBreaking { chase += 0.03 + (pitcher.breaking - 50) * 0.0015 }
            if strikes == 2 { chase += 0.10 }
            swings = rng.chance(clamp(chase, 0.05, 0.6))
        }

        if !swings {
            if inZone {
                strikes += 1
                if strikes >= 3 {
                    events.append(MatchEvent(.play, "\(lead) 루킹 삼진! \(batter.name) 아웃"))
                    strikeout(batterIndex, pitcherIndex, &events)
                } else {
                    events.append(MatchEvent(.pitch, "\(lead) 스트라이크 (루킹)"))
                }
            } else {
                balls += 1
                if balls >= 4 {
                    events.append(MatchEvent(.play, "\(lead) 볼넷. \(batter.name) 출루"))
                    walk(batterIndex, pitcherIndex, &events)
                } else {
                    events.append(MatchEvent(.pitch, "\(lead) 볼"))
                }
            }
            return
        }

        // 맞히기
        var contactChance = (inZone ? 0.84 : 0.60) + (contact - stuff) * 0.004
        if isBreaking { contactChance -= 0.03 + (pitcher.breaking - 50) * 0.001 }
        if !rng.chance(clamp(contactChance, 0.3, 0.97)) {
            strikes += 1
            if strikes >= 3 {
                events.append(MatchEvent(.play, "\(lead) 헛스윙 삼진! \(batter.name) 아웃"))
                strikeout(batterIndex, pitcherIndex, &events)
            } else {
                events.append(MatchEvent(.pitch, "\(lead) 헛스윙!"))
            }
            return
        }

        if rng.chance(inZone ? 0.42 : 0.50) {
            if strikes < 2 { strikes += 1 }
            events.append(MatchEvent(.pitch, "\(lead) 파울"))
            return
        }

        inPlay(
            lead: lead, batterIndex: batterIndex, pitcherIndex: pitcherIndex,
            contact: contact, power: power, stuff: stuff, speed: batter.speed, &events)
    }

    // MARK: 타석 결과

    private mutating func strikeout(_ batterIndex: Int, _ pitcherIndex: Int, _ events: inout [MatchEvent]) {
        batting.batters[batterIndex].line.atBats += 1
        batting.batters[batterIndex].line.strikeouts += 1
        fielding.pitchers[pitcherIndex].line.strikeouts += 1
        recordOut()
        endPlateAppearance(&events)
    }

    private mutating func walk(_ batterIndex: Int, _ pitcherIndex: Int, _ events: inout [MatchEvent]) {
        batting.batters[batterIndex].line.walks += 1
        fielding.pitchers[pitcherIndex].line.walks += 1
        // 밀어내기: 앞이 다 차 있는 주자만 움직인다.
        let batterRunner = Runner(batterIndex: batterIndex, pitcherIndex: pitcherIndex, earned: true)
        if bases[0] != nil {
            if bases[1] != nil {
                if let third = bases[2] {
                    score(third, rbiTo: batterIndex, &events)
                }
                bases[2] = bases[1]
            }
            bases[1] = bases[0]
        }
        bases[0] = batterRunner
        endPlateAppearance(&events)
    }

    private enum BallType { case ground, fly, line }

    private mutating func inPlay(
        lead: String, batterIndex: Int, pitcherIndex: Int,
        contact: Double, power: Double, stuff: Double, speed: Double,
        _ events: inout [MatchEvent]
    ) {
        let batter = batting.batters[batterIndex]
        let advantage = contact - stuff
        let batterRunner = Runner(batterIndex: batterIndex, pitcherIndex: pitcherIndex, earned: true)

        // 홈런
        let homeRunChance = clamp(0.034 * exp((power - 50) / 30) * (1 - (stuff - 50) * 0.006), 0.002, 0.15)
        if rng.chance(homeRunChance) {
            let runnersOn = bases.compactMap { $0 }.count
            events.append(MatchEvent(.play, "\(lead) 쳤습니다! \(batter.name)의 \(runnersOn == 3 ? "만루 " : "")홈런!"))
            hit(batterIndex, pitcherIndex, bases: 4)
            advanceAll(by: 4, rbiTo: batterIndex, events: &events)
            score(batterRunner, rbiTo: batterIndex, &events)
            endPlateAppearance(&events)
            return
        }

        let type: BallType = [.ground, .fly, .line][rng.weighted([0.44, 0.33, 0.23])]
        let position: Position
        switch type {
        case .ground: position = rng.pick(Position.infield)
        case .fly: position = rng.pick(Position.outfield)
        case .line: position = rng.pick(Position.infield + Position.outfield)
        }
        let fielder = fielding.batters.first { $0.position == position }
        let defense = fielder?.fielding ?? 35
        let arm = fielder?.arm ?? 35

        var hitChance: Double
        switch type {
        case .ground: hitChance = 0.235 + advantage * 0.0015 - (defense - 50) * 0.002 + (speed - 50) * 0.0012
        case .line: hitChance = 0.66 + advantage * 0.0015 - (defense - 50) * 0.0015
        case .fly: hitChance = 0.13 + advantage * 0.001 - (defense - 50) * 0.002 + (power - 50) * 0.001
        }

        if rng.chance(clamp(hitChance, 0.03, 0.9)) {
            let basesGained: Int
            switch type {
            case .ground:
                basesGained = 1
            case .line:
                basesGained = [1, 2, 3][rng.weighted([0.74, 0.23 + (power - 50) * 0.002, 0.03])]
            case .fly:
                basesGained = [1, 2, 3][rng.weighted([0.40, 0.50, 0.10 + (speed - 50) * 0.001])]
            }
            let label = ["안타", "2루타", "3루타"][basesGained - 1]
            let direction = type == .ground ? "\(position.label) 옆을 빠지는" : "\(position.label) 쪽"
            events.append(MatchEvent(.play, "\(lead) 쳤습니다! \(direction) \(label)"))
            hit(batterIndex, pitcherIndex, bases: basesGained)
            advanceOnHit(basesGained, batterIndex: batterIndex, arm: arm, &events)
            bases[basesGained - 1] = batterRunner
            endPlateAppearance(&events)
            return
        }

        // 실책
        var errorChance = clamp(0.05 - (defense - 50) * 0.0006, 0.005, 0.09)
        if fielder?.traits.contains(.ironGlove) == true { errorChance *= 0.5 }
        if rng.chance(errorChance) {
            events.append(MatchEvent(.play, "\(lead) \(position.label) 실책! \(batter.name) 출루"))
            batting.batters[batterIndex].line.atBats += 1
            fielding.errors += 1
            advanceAll(by: 1, rbiTo: nil, events: &events)
            bases[0] = Runner(batterIndex: batterIndex, pitcherIndex: pitcherIndex, earned: false)
            endPlateAppearance(&events)
            return
        }

        // 아웃
        switch type {
        case .ground:
            let doublePlay = clamp(0.42 - (speed - 50) * 0.004 + (defense - 50) * 0.003, 0.1, 0.7)
            if bases[0] != nil, outs < 2, rng.chance(doublePlay) {
                events.append(MatchEvent(.play, "\(lead) \(position.label) 땅볼, 병살타!"))
                batting.batters[batterIndex].line.atBats += 1
                bases[0] = nil
                recordOut()
                recordOut()
                if outs < 3 {
                    if let third = bases[2] { score(third, rbiTo: nil, &events); bases[2] = nil }
                    if let second = bases[1] { bases[2] = second; bases[1] = nil }
                }
            } else {
                events.append(MatchEvent(.play, "\(lead) \(position.label) 땅볼 아웃"))
                batting.batters[batterIndex].line.atBats += 1
                recordOut()
                if outs < 3 {
                    if let third = bases[2], rng.chance(0.5) {
                        score(third, rbiTo: batterIndex, &events)
                        bases[2] = nil
                    }
                    if let second = bases[1], bases[2] == nil, rng.chance(0.55) {
                        bases[2] = second
                        bases[1] = nil
                    }
                    if let first = bases[0], bases[1] == nil {
                        bases[1] = first
                        bases[0] = nil
                    }
                }
            }
        case .fly:
            recordOut()
            var sacrifice = false
            if outs < 3, let third = bases[2] {
                let runnerSpeed = batting.batters[third.batterIndex].speed
                if rng.chance(clamp(0.5 + (runnerSpeed - arm) * 0.005, 0.1, 0.9)) {
                    sacrifice = true
                    events.append(MatchEvent(.play, "\(lead) \(position.label) 뜬공, 희생플라이"))
                    score(third, rbiTo: batterIndex, &events)
                    bases[2] = nil
                }
            }
            if !sacrifice {
                events.append(MatchEvent(.play, "\(lead) \(position.label) 뜬공 아웃"))
                batting.batters[batterIndex].line.atBats += 1
                if outs < 3, let second = bases[1], bases[2] == nil, rng.chance(0.2) {
                    bases[2] = second
                    bases[1] = nil
                }
            }
        case .line:
            events.append(MatchEvent(.play, "\(lead) \(position.label) 직선타 아웃"))
            batting.batters[batterIndex].line.atBats += 1
            recordOut()
        }
        endPlateAppearance(&events)
    }

    private mutating func hit(_ batterIndex: Int, _ pitcherIndex: Int, bases gained: Int) {
        var team = batting
        team.hits += 1
        team.batters[batterIndex].line.atBats += 1
        team.batters[batterIndex].line.hits += 1
        switch gained {
        case 2: team.batters[batterIndex].line.doubles += 1
        case 3: team.batters[batterIndex].line.triples += 1
        case 4: team.batters[batterIndex].line.homeRuns += 1
        default: break
        }
        batting = team
        fielding.pitchers[pitcherIndex].line.hits += 1
        if gained == 4 { fielding.pitchers[pitcherIndex].line.homeRuns += 1 }
    }

    // MARK: 주루

    /// 안타 때 주자 진루. 주력과 외야수 어깨에 따라 한 베이스 더 간다.
    private mutating func advanceOnHit(_ gained: Int, batterIndex: Int, arm: Double, _ events: inout [MatchEvent]) {
        guard gained < 3 else {
            advanceAll(by: 3, rbiTo: batterIndex, events: &events)
            return
        }
        for base in stride(from: 2, through: 0, by: -1) {
            guard let runner = bases[base] else { continue }
            bases[base] = nil
            let runnerSpeed = batting.batters[runner.batterIndex].speed
            let extraBase: Double
            if gained == 1 {
                extraBase = base == 1 ? 0.60 : 0.28
            } else {
                extraBase = base == 0 ? 0.42 : 1.0
            }
            var target = base + gained
            if target < 3, rng.chance(clamp(extraBase + (runnerSpeed - arm) * 0.004, 0.1, 0.95)) {
                target += 1
            }
            // 앞 주자가 서 있는 베이스로는 가지 못한다.
            while target < 3, bases[target] != nil { target -= 1 }
            if target >= 3 {
                score(runner, rbiTo: batterIndex, &events)
            } else {
                bases[max(target, base + 1)] = runner
            }
        }
    }

    /// 모든 주자가 같은 수만큼 진루한다.
    private mutating func advanceAll(by count: Int, rbiTo batterIndex: Int?, events: inout [MatchEvent]) {
        for base in stride(from: 2, through: 0, by: -1) {
            guard let runner = bases[base] else { continue }
            bases[base] = nil
            if base + count >= 3 {
                score(runner, rbiTo: batterIndex, &events)
            } else {
                bases[base + count] = runner
            }
        }
    }

    private mutating func score(_ runner: Runner, rbiTo batterIndex: Int?, _ events: inout [MatchEvent]) {
        var offense = batting
        while offense.runsByInning.count < inning { offense.runsByInning.append(0) }
        offense.runsByInning[inning - 1] += 1
        offense.batters[runner.batterIndex].line.runs += 1
        if let batterIndex { offense.batters[batterIndex].line.runsBattedIn += 1 }
        batting = offense

        var defense = fielding
        defense.pitchers[runner.pitcherIndex].line.runs += 1
        if runner.earned { defense.pitchers[runner.pitcherIndex].line.earnedRuns += 1 }
        fielding = defense

        events.append(MatchEvent(
            .score, "\(offense.batters[runner.batterIndex].name) 홈인! \(away.shortName) \(away.runs) : \(home.runs) \(home.shortName)"))

        // 승리·패전 투수: 리드가 바뀔 때마다 다시 정한다.
        let difference = home.runs - away.runs
        let leader: Bool? = difference > 0 ? true : difference < 0 ? false : nil
        if leader != leaderIsHome {
            if leader == nil {
                winPitcherIndex = nil
                lossPitcherIndex = nil
            } else {
                winPitcherIndex = batting.pitcherIndex
                lossPitcherIndex = runner.pitcherIndex
            }
            leaderIsHome = leader
        }
    }

    private mutating func recordOut() {
        outs += 1
        fielding.pitchers[fielding.pitcherIndex].line.outs += 1
    }

    // MARK: 타석·이닝·경기 끝

    private mutating func endPlateAppearance(_ events: inout [MatchEvent]) {
        var team = batting
        team.batters[team.battingIndex].line.plateAppearances += 1
        team.battingIndex = (team.battingIndex + 1) % team.batters.count
        batting = team
        balls = 0
        strikes = 0
        pitchesThisPA = 0
        plateAppearanceStarted = false

        if checkWalkOff(&events) { return }
        if outs >= 3 { endHalfInning(&events) }
    }

    /// 말 공격 중에 경기가 끝나는 경우.
    /// 끝내기: 9회말 이후 홈팀이 앞서는 순간. 콜드게임: 홈팀이 기준 점수 차를 넘기는 순간.
    @discardableResult
    private mutating func checkWalkOff(_ events: inout [MatchEvent]) -> Bool {
        guard !isFinished, isBottom, home.runs > away.runs else { return false }
        if inning >= 9 {
            events.append(MatchEvent(.play, "끝내기! \(home.name)의 승리"))
        } else if coldGameReached(lead: home.runs - away.runs) {
            events.append(MatchEvent(.inning, "콜드게임이 선언됩니다"))
        } else {
            return false
        }
        finish(&events)
        return true
    }

    private func coldGameReached(lead: Int) -> Bool {
        guard rules.coldGame else { return false }
        if inning >= 7 { return lead >= 7 }
        if inning >= 5 { return lead >= 10 }
        return false
    }

    private mutating func endHalfInning(_ events: inout [MatchEvent]) {
        outs = 0
        balls = 0
        strikes = 0
        pitchesThisPA = 0
        plateAppearanceStarted = false
        bases = [nil, nil, nil]

        let homeLead = home.runs - away.runs
        if !isBottom {
            // 초 공격 끝: 9회 이후 홈팀이 앞서 있으면 말 공격을 하지 않는다.
            if inning >= 9, homeLead > 0 { finish(&events); return }
            if coldGameReached(lead: homeLead) {
                events.append(MatchEvent(.inning, "콜드게임이 선언됩니다"))
                finish(&events)
                return
            }
            isBottom = true
        } else {
            if inning >= 9, homeLead != 0 { finish(&events); return }
            if coldGameReached(lead: abs(homeLead)) {
                events.append(MatchEvent(.inning, "콜드게임이 선언됩니다"))
                finish(&events)
                return
            }
            if inning >= 9, let limit = rules.maxInnings, inning >= limit { finish(&events); return }
            inning += 1
            isBottom = false
        }
        events.append(MatchEvent(.inning, "\(inningLabel) \(batting.shortName) 공격"))
    }

    private mutating func finish(_ events: inout [MatchEvent]) {
        isFinished = true
        if let leaderIsHome {
            var winner = leaderIsHome ? home : away
            var loser = leaderIsHome ? away : home
            if let winPitcherIndex { winner.pitchers[winPitcherIndex].line.wins += 1 }
            if let lossPitcherIndex { loser.pitchers[lossPitcherIndex].line.losses += 1 }
            let last = winner.pitcherIndex
            if last != winPitcherIndex, (1...3).contains(winner.pitchers[last].leadOnEntry) {
                winner.pitchers[last].line.saves += 1
            }
            if leaderIsHome { home = winner; away = loser } else { away = winner; home = loser }
        }
        let summary: String
        switch result {
        case .homeWin: summary = "\(home.name) 승리"
        case .awayWin: summary = "\(away.name) 승리"
        default: summary = "무승부"
        }
        events.append(MatchEvent(
            .end, "경기 종료. \(away.shortName) \(away.runs) : \(home.runs) \(home.shortName), \(summary)"))
    }
}
