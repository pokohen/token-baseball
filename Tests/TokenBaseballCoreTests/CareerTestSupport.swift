import Foundation
import Testing
@testable import TokenBaseballCore

enum TestCareer {
    static func make(_ position: Position = .shortstop, seed: UInt64 = 1) -> Game {
        Game.newCareer(
            setup: CareerSetup(name: "김테스트", position: position, bats: .left, throwsHand: .right, hometown: "부산"),
            now: TestGame.start, seed: seed)
    }
}

/// 선수 모드를 자동으로 진행한다: 훈련하고, 제안에 답하고, 경기를 치른다.
struct CareerAuto {
    var clock = TestGame.start
    var tokenID = 0
    var tokensPerMatch = 5_000_000
    /// 윗 리그 구단의 이적 제안을 받아들일지.
    var acceptsTransfers = true

    mutating func playOne(_ game: inout Game) throws {
        clock = clock.addingTimeInterval(3600)
        tokenID += 1
        TestGame.addTokens(&game, tokensPerMatch, id: "c\(tokenID)", at: clock)
        manage(&game)
        try game.startMatch(now: clock)
        game.runMatchToEnd()
    }

    func manage(_ game: inout Game) {
        guard let career = game.career, !career.retired else { return }
        // 제안: 무소속이면 가장 높은 리그의 구단, 재계약은 수락, 이적은 윗 리그만.
        if career.isFreeAgent {
            let best = career.offers.min { game.teams[$0.teamID].tier < game.teams[$1.teamID].tier }
            if let best { try? game.acceptCareerOffer(best.id) }
        } else if let renewal = career.offers.first(where: { $0.kind == .renewal }) {
            try? game.acceptCareerOffer(renewal.id)
        } else if acceptsTransfers,
                  let move = career.offers.first(where: { game.teams[$0.teamID].tier < game.userTier }) {
            try? game.acceptCareerOffer(move.id)
        }
        // 훈련: 값이 가장 낮은 능력치부터.
        for _ in 0..<Balance.careerSessionsPerMatch {
            guard let me = game.myPlayer else { break }
            let keys = game.careerTrainableKeys.sorted { me.attributes[$0] < me.attributes[$1] }
            if let key = keys.first(where: { game.careerTrainingBlockedReason($0) == nil }) {
                try? game.trainCareer(key)
            } else if me.potential - me.ability < 2 {
                try? game.breakThroughCareer()
            }
        }
    }
}
