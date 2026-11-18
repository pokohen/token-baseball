import Foundation
import Security

/// 앱 안에서 새 버전으로 바꾼다 (배포 파일로 설치한 앱만).
///
/// 순서: 배포 파일(.dmg)을 내려받는다 → 연다 → 안의 앱을 꺼낸다 → **이 앱과 같은 개발자가 서명했고
/// Apple 공증을 받았는지 검사한다** → 이 앱이 꺼진 뒤 자리를 바꾸고 다시 여는 작은 스크립트를 띄운다.
/// 검사에서 하나라도 어긋나면 아무것도 바꾸지 않는다. 저장 파일은 건드리지 않는다.
enum Updater {
    struct Failure: Error, Equatable {
        var message: String
        init(_ message: String) { self.message = message }
    }

    static let appName = "Token Baseball.app"

    /// 지금 실행 중인 앱 번들. 번들 없이 실행했으면 nil.
    static var installedApp: URL? {
        let url = Bundle.main.bundleURL
        return url.pathExtension == "app" ? url : nil
    }

    /// 앱 안에서 업데이트할 수 없는 이유. 할 수 있으면 nil.
    static func blockedReason(app: URL? = installedApp) -> String? {
        guard UpdateChecker.isReleaseBuild, let app else { return "배포 파일로 설치한 앱에서만 됩니다." }
        if app.path.contains("/AppTranslocation/") {
            return "앱을 응용 프로그램 폴더로 옮긴 뒤에 할 수 있습니다."
        }
        if !FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path) {
            return "앱이 있는 폴더를 고칠 권한이 없습니다. 아래 명령으로 업데이트하세요."
        }
        if teamIdentifier(of: app) == nil { return "서명되지 않은 앱이라 앱 안에서 업데이트할 수 없습니다." }
        return nil
    }

    /// 서명한 개발자 팀 ID. 서명이 없거나 깨졌으면 nil.
    static func teamIdentifier(of app: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dictionary = info as? [String: Any] else { return nil }
        return dictionary[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// 서명이 온전하고, 그 팀의 Developer ID로 서명됐는지.
    static func isSigned(_ app: URL, byTeam team: String) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { return false }
        let text = "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess else { return false }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        return SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess
    }

    /// 명령을 실행하고 (종료 코드, 출력)을 돌려준다.
    @discardableResult
    static func run(_ tool: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (-1, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// 배포 파일을 내려받아 검사까지 마친 새 앱을 임시 폴더에 준비한다. 돌려주는 것은 그 앱의 위치.
    static func prepare(
        from download: URL, expectedVersion: String, current app: URL, progress: @Sendable (String) -> Void
    ) async throws -> URL {
        guard download.scheme == "https" || download.isFileURL else { throw Failure("내려받는 주소가 올바르지 않습니다.") }
        guard let team = teamIdentifier(of: app) else { throw Failure("이 앱의 서명을 읽지 못했습니다.") }
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenSportUpdate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        do {
            progress("내려받는 중…")
            let image = work.appendingPathComponent("update.dmg")
            if download.isFileURL {
                try FileManager.default.copyItem(at: download, to: image)
            } else {
                var request = URLRequest(url: download, timeoutInterval: 120)
                request.setValue("TokenSport-update", forHTTPHeaderField: "User-Agent")
                let (file, response) = try await URLSession.shared.download(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure("내려받지 못했습니다.") }
                try FileManager.default.moveItem(at: file, to: image)
            }

            progress("확인하는 중…")
            let mount = work.appendingPathComponent("mnt", isDirectory: true)
            guard run("/usr/bin/hdiutil", ["attach", image.path, "-nobrowse", "-readonly", "-quiet", "-mountpoint", mount.path]).status == 0 else {
                throw Failure("내려받은 파일을 열지 못했습니다.")
            }
            let fresh = work.appendingPathComponent(appName, isDirectory: true)
            let copied = run("/usr/bin/ditto", [mount.appendingPathComponent(appName).path, fresh.path]).status == 0
            run("/usr/bin/hdiutil", ["detach", mount.path, "-quiet", "-force"])
            guard copied else { throw Failure("내려받은 파일 안에 앱이 없습니다.") }

            // 같은 개발자가 서명했는가, Apple 공증을 받았는가, 정말 그 버전인가.
            guard isSigned(fresh, byTeam: team) else { throw Failure("새 버전의 서명이 이 앱과 다릅니다. 업데이트하지 않았습니다.") }
            guard run("/usr/sbin/spctl", ["--assess", "--type", "execute", fresh.path]).status == 0 else {
                throw Failure("새 버전이 Apple 공증 검사를 통과하지 못했습니다. 업데이트하지 않았습니다.")
            }
            let plist = NSDictionary(contentsOf: fresh.appendingPathComponent("Contents/Info.plist"))
            guard plist?["CFBundleShortVersionString"] as? String == expectedVersion else {
                throw Failure("내려받은 앱의 버전이 다릅니다. 업데이트하지 않았습니다.")
            }
            return fresh
        } catch {
            try? FileManager.default.removeItem(at: work)
            throw error
        }
    }

    /// 이 앱이 꺼지면 새 앱으로 자리를 바꾸고 다시 여는 스크립트를 띄운다. 띄운 뒤 곧바로 앱을 꺼야 한다.
    /// 바꾸다 실패하면 예전 앱을 되돌려 놓는다.
    static func swapAfterExit(fresh: URL, into app: URL, reopen: Bool) throws {
        let script = """
        pid="$1"; fresh="$2"; app="$3"; reopen="$4"
        n=0; while kill -0 "$pid" 2>/dev/null && [ $n -lt 100 ]; do sleep 0.2; n=$((n+1)); done
        old="$app.old-$$"
        mv "$app" "$old" || exit 1
        if /usr/bin/ditto "$fresh" "$app"; then rm -rf "$old"; else rm -rf "$app"; mv "$old" "$app"; fi
        rm -rf "$(dirname "$fresh")"
        [ "$reopen" = "1" ] && /usr/bin/open "$app"
        exit 0
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // 한 번 더 띄워서(&) 이 앱이 꺼져도 남아 있게 한다.
        process.arguments = [
            "-c", "/bin/sh -c \"$0\" sh \"$@\" >/dev/null 2>&1 &", script,
            String(ProcessInfo.processInfo.processIdentifier), fresh.path, app.path, reopen ? "1" : "0",
        ]
        try process.run()
        process.waitUntilExit()
    }
}
