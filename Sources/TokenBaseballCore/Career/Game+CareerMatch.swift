import Foundation

/// 선수 모드: 경기 평점과 경기 뒤 정산.
extension Game {
    // MARK: 경기 평점

    public struct CareerPerformance: Equatable, Sendable {
        public var rating: Double
        public var line: String
    }

    /// 이 경기에서 내 선수가 한 일과 평점 (1.0~10.0, 6.0이 "무난했다"). 나오지 않았으면 nil.
    /// `result`: 팀이 이겼으면 1, 졌으면 −1, 비겼으면 0.
    static func careerPerformance(playerID: PlayerID, in side: MatchTeam, result: Int) -> CareerPerformance? {
        let teamShift = Double(result) * 0.2
        if let batter = side.batters.first(where: { $0.playerID == playerID }) {
            let line = batter.line
            guard line.plateAppearances > 0 else { return nil }
            let singles = line.hits - line.doubles - line.triples - line.homeRuns
            let quietOuts = max(0, line.atBats - line.hits - line.strikeouts)
            var rating = 6.0
            rating += Double(singles) * 0.55 + Double(line.doubles) * 0.8
            rating += Double(line.triples) * 1.0 + Double(line.homeRuns) * 1.4
            rating += Double(line.runsBattedIn) * 0.3 + Double(line.runs) * 0.2
            rating += Double(line.walks) * 0.25 + Double(line.steals) * 0.3
            rating -= Double(line.strikeouts) * 0.2 + Double(quietOuts) * 0.15
            var text = "\(line.atBats)타수 \(line.hits)안타"
            if line.homeRuns > 0 { text += " \(line.homeRuns)홈런" }
            if line.runsBattedIn > 0 { text += " \(line.runsBattedIn)타점" }
            if line.walks > 0 { text += " \(line.walks)볼넷" }
            if line.steals > 0 { text += " \(line.steals)도루" }
            return CareerPerformance(rating: clamp(rating + teamShift, 1, 10), line: text)
        }
        if let index = side.pitchers.firstIndex(where: { $0.playerID == playerID && $0.hasEntered }) {
            let line = side.pitchers[index].line
            let unearned = max(0, line.runs - line.earnedRuns)
            var rating = 6.0
            if index == 0 {
                // 선발은 점수를 주는 것이 보통이라 기준을 조금 높게 잡는다.
                rating += 0.3
                rating += Double(line.outs) * 0.12 - Double(line.earnedRuns) * 0.45 - Double(unearned) * 0.2
                rating += Double(line.strikeouts) * 0.08 - Double(line.walks) * 0.12
                rating -= Double(line.hits) * 0.06 + Double(line.homeRuns) * 0.2
                rating += Double(line.wins) * 0.5
            } else {
                rating += Double(line.outs) * 0.25 - Double(line.earnedRuns) * 0.9 - Double(unearned) * 0.3
                rating += Double(line.strikeouts) * 0.1 - Double(line.walks) * 0.15 - Double(line.hits) * 0.1
                rating += Double(line.saves) * 1.0 + Double(line.wins) * 0.3
            }
            var text = "\(line.innings)이닝 \(line.runs)실점 \(line.strikeouts)탈삼진"
            if line.wins > 0 { text += " 승리" }
            if line.losses > 0 { text += " 패전" }
            if line.saves > 0 { text += " 세이브" }
            return CareerPerformance(rating: clamp(rating + teamShift, 1, 10), line: text)
        }
        return nil
    }

    /// 평점에 따른 감독 신뢰 변화: 7.0 이상이면 오르고 6.0 아래면 내린다.
    static func careerTrustChange(rating: Double) -> Double {
        if rating >= 7 { return min(6, 1 + (rating - 7) * 3) }
        if rating < 6 { return max(-6, -1 - (6 - rating) * 3) }
        return 0
    }

    /// 진행 중인 경기에서 지금까지의 내 선수 평점.
    public var careerLivePerformance: CareerPerformance? {
        guard let career, let live else { return nil }
        let mine = live.userIsHome ? live.state.home : live.state.away
        return Self.careerPerformance(playerID: career.playerID, in: mine, result: 0)
    }

    /// 내 경기 정산: 평점, 감독 신뢰, 명성, 연봉. 훈련 횟수도 다시 채운다.
    mutating func settleCareerMatch(kind: MatchKind, state: MatchState, userIsHome: Bool) -> [String] {
        guard var career, !career.retired, let me = players[career.playerID] else { return [] }
        let mine = userIsHome ? state.home : state.away
        let theirs = userIsHome ? state.away : state.home
        let result = mine.runs > theirs.runs ? 1 : mine.runs < theirs.runs ? -1 : 0
        var lines: [String] = []

        career.sessionsLeft = Balance.careerSessionsPerMatch
        career.matchesAtClub += 1
        let performance = Self.careerPerformance(playerID: me.id, in: mine, result: result)
        career.lastRating = performance?.rating
        career.lastLine = performance?.line
        if let performance {
            lines.append("\(me.name) 평점 \(String(format: "%.1f", performance.rating)) · \(performance.line)")
            // 친선 경기는 절반만 반영한다.
            let weight = kind == .friendly ? 0.5 : 1.0
            let before = career.trust
            career.trust = clamp(career.trust + Self.careerTrustChange(rating: performance.rating) * weight, 0, 100)
            let moved = Int((career.trust - before).rounded())
            if moved != 0 { lines.append("감독 신뢰 \(moved > 0 ? "+" : "")\(moved)") }
            if kind != .friendly {
                let cap = Balance.careerFameCap(teams[userTeamID].tier)
                // 선발 투수는 나오는 경기가 적어서 한 경기가 더 크게 반영된다.
                let rarity = me.position == .starter ? 3.0 : 1.0
                if career.fame < cap {
                    career.fame += max(0, performance.rating - 6.5) * 0.8 * rarity * (cap - career.fame) / cap
                }
            }
            if kind == .regular {
                career.seasonRatedGames += 1
                career.seasonRatingTotal += performance.rating
            }
        } else {
            lines.append(me.position == .starter
                ? "\(me.name): 등판하지 않는 날입니다." : "\(me.name): 출전하지 않았습니다.")
        }
        if kind == .regular {
            let pay = me.contract.salary / Balance.roundsPerSeason
            career.earnings += pay
            lines.append("연봉 ₩\(pay.formatted())")
        }
        career.peakAbility = max(career.peakAbility, me.ability)
        self.career = career
        return lines
    }
}
