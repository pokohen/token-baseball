import Foundation

/// 진행 중인 경기 한 판. `step()`을 부를 때마다 공 하나(또는 투구 사이 이벤트 하나)가 진행된다.
/// 난수 상태까지 통째로 저장되므로, 저장했다가 다시 읽어도 똑같이 이어진다.
public struct MatchState: Codable, Equatable, Sendable {
    public var rules: MatchRules
    public var away: MatchTeam
    public var home: MatchTeam
    public var rng: SeededRNG

    public internal(set) var inning = 1
    public internal(set) var isBottom = false
    public internal(set) var outs = 0
    public internal(set) var balls = 0
    public internal(set) var strikes = 0
    /// 1루, 2루, 3루.
    public internal(set) var bases: [Runner?] = [nil, nil, nil]
    /// 양 팀이 던진 공의 수.
    public internal(set) var pitchCount = 0
    public internal(set) var isFinished = false
    /// 최근 문자 중계 (오래된 것부터).
    public internal(set) var log: [MatchEvent] = []

    var pitchesThisPA = 0
    var plateAppearanceStarted = false
    /// 지금 앞서 있는 팀 (true = 홈). 동점이면 nil.
    var leaderIsHome: Bool?
    var winPitcherIndex: Int?
    var lossPitcherIndex: Int?

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

    static func enter(_ team: inout MatchTeam, pitcher index: Int, lead: Int, asStarter: Bool) {
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

    mutating func beginPlateAppearance(_ events: inout [MatchEvent]) {
        while batting.runsByInning.count < inning { batting.runsByInning.append(0) }
        managePitching(&events)
        plateAppearanceStarted = true
        pitchesThisPA = 0
    }

    // MARK: 투수 교체

    func capacity(of pitcher: MatchPitcher) -> Double {
        pitcher.role == .starter ? 35 + pitcher.stamina * 0.8 : 22 + pitcher.stamina * 0.45
    }

    mutating func managePitching(_ events: inout [MatchEvent]) {
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
                pull = current.line.pitches >= 28 || current.line.runs >= 4
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
    mutating func betweenPitches(_ events: inout [MatchEvent]) -> Bool {
        guard bases.contains(where: { $0 != nil }) else { return false }
        let pitcher = currentPitcher

        // 도루: 1루 주자, 2루가 비어 있을 때
        if let runner = bases[0], bases[1] == nil {
            let stealer = batting.batters[runner.batterIndex]
            // 주자의 발과 포수 어깨의 차이로 뛴다. 포수 어깨가 약한 하위 리그에서도 도루가 나온다.
            let catcherArm = fielding.batters.first { $0.position == .catcher }?.arm ?? 40
            let attempt = clamp(
                0.012 + (stealer.speed - catcherArm) * 0.0008 + (stealer.speed - 50) * 0.0001, 0, 0.04)
            if rng.chance(attempt) {
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
}
