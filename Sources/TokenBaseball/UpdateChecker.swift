import Foundation

/// 새 버전이 나왔는지 알아본다.
///
/// 이 앱은 소스를 받아 직접 빌드하므로 "버전"은 빌드한 시점의 커밋이다.
/// `Scripts/make-app.sh`가 앱 번들에 그 커밋과 저장소 이름을 적어 두고,
/// 앱은 GitHub에 "이 커밋 뒤로 기본 브랜치에 몇 개가 더 쌓였는지"만 묻는다.
///
/// 이것이 이 앱이 하는 유일한 네트워크 요청이다. 보내는 것은 저장소 이름과 빌드 커밋뿐이고,
/// 토큰 사용량이나 게임 내용은 보내지 않는다. 설정에서 끌 수 있다.
enum UpdateChecker {
    struct Update: Equatable, Sendable {
        /// 지금 빌드보다 앞선 변경 수.
        var count: Int
        /// 가장 최근 변경의 제목들 (새 것부터, 병합 기록은 뺀다).
        var titles: [String]
        /// 기본 브랜치의 맨 끝 커밋. 같은 업데이트를 두 번 알리지 않으려고 쓴다.
        var head: String
    }

    enum Outcome: Equatable, Sendable {
        case upToDate
        case available(Update)
        /// 확인하지 못했다 (오프라인, 직접 고친 빌드 등). 이유를 담는다.
        case unknown(String)
    }

    /// 빌드한 커밋. 번들 없이 실행하면(`swift run`) 알 수 없다.
    static var buildCommit: String? {
        if let value = ProcessInfo.processInfo.environment["TOKEN_BASEBALL_BUILD_COMMIT"], !value.isEmpty { return value }
        return (Bundle.main.object(forInfoDictionaryKey: "TBCommit") as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// `소유자/저장소`.
    static var repository: String {
        (Bundle.main.object(forInfoDictionaryKey: "TBRepository") as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? "pokohen/token-sport"
    }

    static var isEnabled: Bool {
        get { !UserDefaults.standard.bool(forKey: "updateCheckDisabled") }
        set { UserDefaults.standard.set(!newValue, forKey: "updateCheckDisabled") }
    }

    /// 이미 알린 업데이트의 맨 끝 커밋.
    static var notifiedHead: String? {
        get { UserDefaults.standard.string(forKey: "updateNotifiedHead") }
        set { UserDefaults.standard.set(newValue, forKey: "updateNotifiedHead") }
    }

    static func check() async -> Outcome {
        guard let commit = buildCommit else {
            return .unknown("앱 번들로 실행할 때만 확인할 수 있습니다 (Scripts/make-app.sh로 만든 앱).")
        }
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/compare/\(commit)...HEAD") else {
            return .unknown("저장소 주소가 올바르지 않습니다.")
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("TokenSport-update-check", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 404 { return .unknown("이 빌드의 커밋이 저장소에 없습니다 (직접 고친 빌드).") }
            guard status == 200 else { return .unknown("GitHub가 응답하지 않았습니다 (\(status)).") }
            return parse(data)
        } catch {
            return .unknown("확인하지 못했습니다: \(error.localizedDescription)")
        }
    }

    /// GitHub의 compare 응답을 읽는다.
    static func parse(_ data: Data) -> Outcome {
        struct Response: Decodable {
            struct Entry: Decodable {
                struct Detail: Decodable { let message: String }
                let sha: String
                let commit: Detail
            }
            let ahead_by: Int
            let commits: [Entry]
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            return .unknown("응답을 읽지 못했습니다.")
        }
        guard response.ahead_by > 0, let head = response.commits.last?.sha else { return .upToDate }
        let titles = response.commits.reversed()
            .map { String($0.commit.message.split(separator: "\n").first ?? "") }
            .filter { !$0.hasPrefix("Merge ") && !$0.isEmpty }
        return .available(Update(count: response.ahead_by, titles: Array(titles.prefix(5)), head: head))
    }
}
