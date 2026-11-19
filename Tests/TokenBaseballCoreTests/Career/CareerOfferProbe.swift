import Foundation
import Testing
@testable import TokenBaseballCore

/// 이적 제안이 얼마나 자주 오고 선수가 얼마나 빨리 올라가는지 재는 도구.
/// 평소에는 돌지 않는다: `TB_PROBE=1 swift test --filter CareerOfferProbe`
@Suite(.enabled(if: ProcessInfo.processInfo.environment["TB_PROBE"] != nil))
struct CareerOfferProbe {
    @Test func 세_시즌_동안의_제안과_승격() throws {
        var out = ""
        let cases: [(Position, Int)] = [(.shortstop, 5_000_000), (.starter, 5_000_000), (.forward, 5_000_000), (.smallForward, 5_000_000), (.smallForward, 500_000)]
        for (position, tokens) in cases {
            for seed in [51, 52] as [UInt64] {
                var game = TestCareer.make(position, seed: seed)
                var auto = CareerAuto()
                auto.tokensPerMatch = tokens
                var offers = 0, moves = 0, seen: Set<Int> = [], guardCount = 0
                var lastTeam = game.userTeamID
                while game.season <= 3, guardCount < 260 {
                    guardCount += 1
                    guard game.nextMatch() != nil || game.career?.isFreeAgent == true else { break }
                    for offer in game.career?.offers ?? [] where offer.kind == .transfer && !seen.contains(offer.id) {
                        seen.insert(offer.id)
                        offers += 1
                    }
                    if game.career?.isFreeAgent == true { auto.manage(&game); continue }
                    try auto.playOne(&game)
                    if game.userTeamID != lastTeam { moves += 1; lastTeam = game.userTeamID }
                }
                let c = game.career!
                out += "\n\(position.rawValue) \(tokens / 1_000_000)M s\(seed): 제안 \(offers) 이적 \(moves) 리그 \(game.userTier.rawValue)부 능력 \(Int(game.myPlayer?.ability ?? 0)) 신뢰 \(Int(c.trust)) 명성 \(Int(c.fame)) 스카우트 \(scoutText(game))"
            }
        }
        print("OFFERPROBE\(out)")
    }

    func scoutText(_ game: Game) -> String {
        game.careerScouts.map { "\(Int($0.interest))" }.joined(separator: "/")
    }
}
