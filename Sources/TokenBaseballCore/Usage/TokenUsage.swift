import Foundation

/// 토큰 사용량. 네 가지를 가중치 없이 더한 값이 구단 자금이 된다.
public struct TokenUsage: Equatable, Sendable {
    public var input: Int
    public var output: Int
    public var cacheWrite: Int
    public var cacheRead: Int

    public init(input: Int = 0, output: Int = 0, cacheWrite: Int = 0, cacheRead: Int = 0) {
        self.input = input
        self.output = output
        self.cacheWrite = cacheWrite
        self.cacheRead = cacheRead
    }

    public static let zero = TokenUsage()

    /// 자금(원) = input + output + cache_write + cache_read
    public var total: Int { input + output + cacheWrite + cacheRead }

    public static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        TokenUsage(
            input: lhs.input + rhs.input,
            output: lhs.output + rhs.output,
            cacheWrite: lhs.cacheWrite + rhs.cacheWrite,
            cacheRead: lhs.cacheRead + rhs.cacheRead
        )
    }

    public static func += (lhs: inout TokenUsage, rhs: TokenUsage) {
        lhs = lhs + rhs
    }
}

/// API 응답 한 건의 사용량.
public struct UsageRecord: Equatable, Sendable {
    /// 응답 ID (`message.id`). 같은 응답이 로그에 여러 줄로 남으므로 이 값으로 중복을 없앤다.
    public let id: String
    public let timestamp: Date
    public let usage: TokenUsage

    public init(id: String, timestamp: Date, usage: TokenUsage) {
        self.id = id
        self.timestamp = timestamp
        self.usage = usage
    }
}
