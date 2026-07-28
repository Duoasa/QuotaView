import Foundation

public struct AccountRateLimitsResponse: Decodable, Sendable {
    public let rateLimits: RateLimitSnapshot
    public let rateLimitsByLimitId: [String: RateLimitSnapshot]?
    public let rateLimitResetCredits: RateLimitResetCreditsSummary?
}

public struct RateLimitSnapshot: Decodable, Sendable {
    public let limitId: String?
    public let limitName: String?
    public let primary: RateLimitWindow?
    public let secondary: RateLimitWindow?
    public let credits: CreditsSnapshot?
    public let individualLimit: SpendControlLimitSnapshot?
    public let spendControlReached: Bool?
    public let planType: String?
    public let rateLimitReachedType: String?
}

public struct RateLimitWindow: Decodable, Sendable {
    public let usedPercent: Int?
    public let windowDurationMins: Int?
    public let resetsAt: Int?
}

public struct CreditsSnapshot: Decodable, Sendable {
    public let hasCredits: Bool
    public let unlimited: Bool
    public let balance: String?
}

public struct SpendControlLimitSnapshot: Decodable, Sendable {
    public let limit: String
    public let used: String
    public let remainingPercent: Int
    public let resetsAt: Int
}

public struct RateLimitResetCreditsSummary: Decodable, Sendable {
    public let availableCount: Int
    public let credits: [RateLimitResetCredit]?
}

public struct RateLimitResetCredit: Decodable, Sendable {
    public let id: String
    public let resetType: String
    public let status: String
    public let grantedAt: Int
    public let expiresAt: Int?
    public let title: String?
    public let description: String?
}

public struct AccountUsageResponse: Decodable, Sendable {
    public let summary: AccountTokenUsageSummary
    public let dailyUsageBuckets: [AccountTokenUsageDailyBucket]?
}

public struct AccountTokenUsageSummary: Decodable, Sendable {
    public let lifetimeTokens: Int64?
    public let peakDailyTokens: Int64?
    public let longestRunningTurnSec: Int64?
    public let currentStreakDays: Int?
    public let longestStreakDays: Int?
}

public struct AccountTokenUsageDailyBucket: Decodable, Sendable {
    public let startDate: String
    public let tokens: Int64
}

public struct CodexProviderPayload: Sendable {
    public let rateLimits: AccountRateLimitsResponse
    public let usage: AccountUsageResponse?
    public let capturedAt: Date
    public let optionalIssues: [SanitizedErrorSummary]

    public init(
        rateLimits: AccountRateLimitsResponse,
        usage: AccountUsageResponse?,
        capturedAt: Date,
        optionalIssues: [SanitizedErrorSummary]
    ) {
        self.rateLimits = rateLimits
        self.usage = usage
        self.capturedAt = capturedAt
        self.optionalIssues = optionalIssues
    }
}
