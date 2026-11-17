import Foundation
import TokenBaseballCore

/// 앱 흐름 자가 점검 (`TOKEN_BASEBALL_SELFTEST=빈 폴더`).
/// 화면 없이 앱 상태(AppModel)를 직접 몰아서, 만들기 → 훈련 → 경기 → 모드 전환 → 다시 켜기가
/// 실제 저장 파일과 함께 돌아가는지 본다. 진짜 저장 파일은 건드리지 않는다.
@MainActor
enum SelfTest {
    static func run(in directory: URL) -> Bool {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = SaveStore(fileURL: directory.appendingPathComponent("save.json"))
        var failures = 0
        func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
            print("\(ok ? "PASS" : "FAIL") \(name)\(ok ? "" : " — \(detail())")")
            if !ok { failures += 1 }
        }
        func exists(_ name: String) -> Bool {
            FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path)
        }
        /// 토큰을 쓴 것처럼 넣고, 경기 한 번을 끝까지 치른다. 경기 기회가 다시 생기도록 부를 때마다 한 시간씩 흐른다.
        var hours = 0.0
        func playOne(_ model: AppModel, label: String) {
            hours += 1.5
            let now = Date().addingTimeInterval(hours * 3600)
            _ = model.game?.collect(
                [UsageRecord(id: "selftest-\(label)-\(now.timeIntervalSince1970)", timestamp: now, usage: TokenUsage(output: 20_000_000))],
                now: now)
            model.perform { try $0.startMatch(now: now) }
            check("\(label): 경기 시작", model.game?.isMatchLive == true, model.message ?? "경기가 열리지 않음")
            model.game?.runMatchToEnd()
            check("\(label): 경기 종료", model.game?.isMatchLive == false && model.game?.lastResult != nil)
            model.save()
        }

        // 1. 처음 켰을 때
        var model = AppModel(store: store, sources: UsageSources())
        check("처음: 게임 없음", model.game == nil && model.slot == .baseball)

        // 2. 축구 선수 만들기 → 훈련 → 스타일 → 경기
        model.createCareer(CareerSetup(name: "점검 공격수", position: .forward, hometown: "부산"))
        check("축구 선수: 만들어짐", model.game?.myPlayer?.name == "점검 공격수", model.message ?? "")
        check("축구 선수: 칸", model.slot == .footballPlayer && exists("save-football-player.json"))
        check("축구 선수: 종목", model.game?.sport == .football && model.sport == .football)
        playOne(model, label: "축구 선수 1")
        if let key = model.game?.careerTrainableKeys.first {
            let before = model.game?.myPlayer?.ability ?? 0
            model.perform { try $0.trainCareer(key) }
            check("축구 선수: 훈련", (model.game?.myPlayer?.ability ?? 0) > before, model.message ?? "")
        }
        model.perform { $0.setCareerStyle(.greedy) }
        check("축구 선수: 스타일", model.game?.career?.style == .greedy)
        playOne(model, label: "축구 선수 2")
        check("축구 선수: 평점 또는 미출전 기록", model.game?.lastResult?.summary.isEmpty == false)

        // 3. 야구 구단으로 전환 (없음 → 창단)
        model.switchSlot(to: .baseball)
        check("야구 구단: 전환하면 창단 화면", model.game == nil && model.slot == .baseball, model.message ?? "")
        model.createClub(.init(city: "서울", name: "점검 야구단"), sport: .baseball)
        check("야구 구단: 창단", model.game?.userTeam.name == "점검 야구단" && model.game?.isCareer == false, model.message ?? "")
        check("야구 구단: 파일", exists("save.json"))
        playOne(model, label: "야구 구단")

        // 4. 야구 선수 만들기 (다른 칸에서 바로)
        model.createCareer(CareerSetup(name: "점검 투수", position: .starter, bats: .left, throwsHand: .left))
        check("야구 선수: 만들어짐", model.game?.myPlayer?.name == "점검 투수" && model.slot == .baseballPlayer, model.message ?? "")
        check("야구 선수: 파일", exists("save-baseball-player.json"))
        playOne(model, label: "야구 선수")
        if let key = model.game?.careerTrainableKeys.first {
            model.perform { try $0.trainCareer(key) }
            check("야구 선수: 훈련", model.message == nil, model.message ?? "")
        }
        model.save()

        // 5. 축구 구단 창단 (다른 칸에서 바로)
        model.createClub(.init(city: "대전", name: "점검 FC"), sport: .football)
        check("축구 구단: 창단", model.game?.userTeam.name == "점검 FC" && model.slot == .football, model.message ?? "")
        check("축구 구단: 파일", exists("save-football.json"))
        playOne(model, label: "축구 구단")

        // 6. 칸을 오가도 그대로
        model.switchSlot(to: .footballPlayer)
        check("돌아옴: 축구 선수", model.game?.myPlayer?.name == "점검 공격수" && model.game?.career?.style == .greedy)
        model.switchSlot(to: .baseball)
        check("돌아옴: 야구 구단", model.game?.userTeam.name == "점검 야구단")
        model.switchSlot(to: .baseballPlayer)
        check("돌아옴: 야구 선수", model.game?.myPlayer?.name == "점검 투수")
        // 이미 있는 선수를 덮어쓰지 않는다
        model.createCareer(CareerSetup(name: "덮어쓰기", position: .catcher))
        check("덮어쓰지 않음", model.game?.myPlayer?.name == "점검 투수")

        // 7. 앱을 껐다 켰을 때
        model.save()
        model = AppModel(store: store, sources: UsageSources())
        check("다시 켬: 마지막 칸", model.slot == .baseballPlayer && model.game?.myPlayer?.name == "점검 투수", model.loadError ?? "")
        check("다시 켬: 오류 없음", model.loadError == nil, model.loadError ?? "")

        // 8. 경기 도중에 껐다 켰을 때
        model.switchSlot(to: .footballPlayer)
        model.perform { try $0.startMatch(now: Date().addingTimeInterval((hours + 4) * 3600)) }
        for _ in 0..<60 { model.game?.stepMatch() }
        model.save()
        model = AppModel(store: store, sources: UsageSources())
        check("경기 중 다시 켬", model.game?.isMatchLive == true && model.slot == .footballPlayer, model.loadError ?? "")
        model.game?.runMatchToEnd()
        check("이어서 끝까지", model.game?.isMatchLive == false)

        print(failures == 0 ? "SELFTEST 통과" : "SELFTEST 실패 \(failures)건")
        return failures == 0
    }
}
