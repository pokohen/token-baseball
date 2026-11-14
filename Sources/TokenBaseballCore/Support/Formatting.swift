import Foundation

public enum Format {
    /// 자금을 줄여서: `₩3.2억`, `₩8,500만`, `₩12,345`.
    public static func money(_ amount: Int) -> String {
        let sign = amount < 0 ? "−" : ""
        let value = abs(amount)
        if value >= 100_000_000 {
            let eok = Double(value) / 100_000_000
            let text = eok >= 100 ? Int(eok).formatted() : String(format: "%.1f", (eok * 10).rounded(.down) / 10)
            return "\(sign)₩\(text)억"
        }
        if value >= 10_000 {
            return "\(sign)₩\((value / 10_000).formatted())만"
        }
        return "\(sign)₩\(value.formatted())"
    }

    /// 토큰 수: `120.5M`, `950.2K`, `812`.
    public static func tokens(_ count: Int) -> String {
        // 반올림해서 1000.0K가 되는 수는 M으로 넘긴다.
        if count >= 999_950 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return "\(count)"
    }

    /// 남은 시간: `0:23`.
    public static func countdown(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded(.up))
        return "\(minutes / 60):\(String(format: "%02d", minutes % 60))"
    }
}

extension Game {
    /// 로그에서 읽은 사용량을 자금에 반영한다. 번 금액을 돌려준다.
    @discardableResult
    public mutating func collect(_ records: [UsageRecord], now: Date) -> Int {
        guard !isBankrupt else { return 0 }
        let earned = funds.collect(records, now: now)
        refreshFinancialState()
        return earned
    }

    /// 상단바에 띄울 글자. 경기 상황은 설정과 상관없이 보여준다.
    public func menuBarText(now: Date, todayTokens: Int) -> String {
        if isBankrupt { return "구단 해체" }
        if let live {
            let mine = live.userIsHome ? live.state.home.runs : live.state.away.runs
            let theirs = live.userIsHome ? live.state.away.runs : live.state.home.runs
            return "⚾ \(mine):\(theirs) \(live.state.inningLabel)"
        }
        if let lastResult, !lastResult.acknowledged {
            return "⚾ 경기 종료 \(lastResult.label)"
        }
        let ready = charges > 0 && nextMatch() != nil
        switch settings.menuBarDisplay {
        case .funds:
            return Format.money(funds.balance) + (ready ? " •" : "")
        case .today:
            return Format.tokens(todayTokens) + (ready ? " •" : "")
        case .nextMatch:
            if ready { return "경기 가능" }
            guard nextMatch() != nil, let wait = timeToNextCharge(now: now) else { return "—" }
            return Format.countdown(wait)
        }
    }

    /// 상단바 툴팁: 자금, 오늘 사용량, 다음 경기를 모두 보여준다.
    public func menuBarTooltip(now: Date, todayTokens: Int) -> String {
        var lines = ["구단 자금 \(Format.money(funds.balance))", "오늘 사용량 \(Format.tokens(todayTokens))"]
        let marks = String(repeating: "⚾", count: charges)
            + String(repeating: "○", count: Balance.maxMatchCharges - charges)
        if let wait = timeToNextCharge(now: now) {
            lines.append("경기 기회 \(marks) (다음 \(Format.countdown(wait)))")
        } else {
            lines.append("경기 기회 \(marks)")
        }
        switch financialState {
        case .warning: lines.append("재정 경고: 자금이 다음 5경기 연봉보다 적습니다")
        case .crisis(let left): lines.append("재정 위기: 유예 \(left)경기")
        default: break
        }
        return lines.joined(separator: "\n")
    }

    /// 팝오버를 열어 경기 결과를 확인했다.
    public mutating func acknowledgeResult() {
        lastResult?.acknowledged = true
    }
}
