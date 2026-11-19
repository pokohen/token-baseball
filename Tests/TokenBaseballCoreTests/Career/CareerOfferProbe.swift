import Foundation
import Testing
@testable import TokenBaseballCore

/// 이적 제안이 얼마나 자주 오고 선수가 얼마나 빨리 올라가는지 재는 도구.
/// 평소에는 돌지 않는다: `TB_PROBE=1 swift test --filter CareerOfferProbe`
@Suite(.enabled(if: ProcessInfo.processInfo.environment["TB_PROBE"] != nil))
struct CareerOfferProbe {
    @Test func 세_시즌_동안의_제안과_승격() throws {
        var out = ""
        // `TB_PROBE=low`면 토큰을 적게 쓰는 경우만 본다.
        let all: [(Position, Int)] = [(.shortstop, 5_000_000), (.starter, 5_000_000), (.forward, 5_000_000), (.smallForward, 5_000_000), (.smallForward, 500_000)]
        let cases = ProcessInfo.processInfo.environment["TB_PROBE"] == "low" ? [(.smallForward, 500_000), (.starter, 5_000_000)] : all
        for (position, tokens) in cases {
            for seed in [51, 52] as [UInt64] {
                var game = TestCareer.make(position, seed: seed)
                var auto = CareerAuto()
                auto.tokensPerMatch = tokens
                var offers = 0, moves = 0, seen: Set<Int> = [], guardCount = 0
                var lastTeam = game.userTeamID
                // 세 자리가 다 찼는데 문턱에 닿은 곳이 없는 경기 수, 문턱을 넘었는데 제안이 못 나간 경기 수.
                var clogged = 0, blocked = 0, starterGames = 0
                while game.season <= 3, guardCount < 260 {
                    guardCount += 1
                    guard game.nextMatch() != nil || game.career?.isFreeAgent == true else { break }
                    for offer in game.career?.offers ?? [] where offer.kind == .transfer && !seen.contains(offer.id) {
                        seen.insert(offer.id)
                        offers += 1
                    }
                    if game.career?.isFreeAgent == true { auto.manage(&game); continue }
                    try auto.playOne(&game)
                    let threshold = game.careerScoutOfferThreshold
                    let scouts = game.careerScouts
                    if scouts.count >= Balance.careerScoutMax, !scouts.contains(where: { $0.interest >= threshold }) { clogged += 1 }
                    if scouts.contains(where: { $0.interest >= threshold }), game.career?.offers.isEmpty == true { blocked += 1 }
                    if game.careerRole(on: game.userTeamID) == .starter { starterGames += 1 }
                    if game.userTeamID != lastTeam { moves += 1; lastTeam = game.userTeamID }
                }
                let c = game.career!
                out += "\n\(position.rawValue) \(tokens / 1_000_000)M s\(seed): 제안 \(offers) 이적 \(moves) 리그 \(game.userTier.rawValue)부 능력 \(Int(game.myPlayer?.ability ?? 0)) 신뢰 \(Int(c.trust)) 명성 \(Int(c.fame)) 스카우트 \(scoutText(game)) 막힘 \(clogged) 대기 \(blocked) 주전 \(starterGames)/\(guardCount)"
            }
        }
        print("OFFERPROBE\(out)")
    }

    func scoutText(_ game: Game) -> String {
        game.careerScouts.map { "\(Int($0.interest))" }.joined(separator: "/")
    }
}
