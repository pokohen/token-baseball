import Foundation

/// 설치된 도구들의 사용량을 한꺼번에 읽는다.
public struct UsageSources: Sendable {
    public var claudeCode: ClaudeCodeUsageReader
    public var codex: CodexUsageReader
    public var gemini: GeminiUsageReader
    public var opencode: OpenCodeUsageReader

    public init(
        claudeCode: ClaudeCodeUsageReader = .init(), codex: CodexUsageReader = .init(),
        gemini: GeminiUsageReader = .init(), opencode: OpenCodeUsageReader = .init()
    ) {
        self.claudeCode = claudeCode
        self.codex = codex
        self.gemini = gemini
        self.opencode = opencode
    }

    public func records(since: Date, until: Date = .distantFuture) -> [UsageRecord] {
        claudeCode.records(since: since, until: until) + codex.records(since: since, until: until)
            + gemini.records(since: since, until: until) + opencode.records(since: since, until: until)
    }

    public func total(since: Date, until: Date = .distantFuture) -> TokenUsage {
        records(since: since, until: until).reduce(.zero) { $0 + $1.usage }
    }
}
