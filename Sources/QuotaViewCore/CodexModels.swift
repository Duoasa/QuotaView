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
    public let usedPercent: Int
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

public struct CodexSnapshot: Equatable, Sendable {
    public enum Availability: String, Equatable, Sendable {
        case ready
        case limited
        case exhausted

        public var displayName: String {
            switch self {
            case .ready: "可用"
            case .limited: "接近限额"
            case .exhausted: "额度已耗尽"
            }
        }
    }

    public let availability: Availability
    public let planType: String
    public let usedPercent: Int
    public let remainingPercent: Int
    public let windowDurationMinutes: Int?
    public let resetsAt: Date?
    public let creditBalance: String?
    public let hasCredits: Bool
    public let unlimitedCredits: Bool
    public let availableResetCredits: Int
    public let lifetimeTokens: Int64?
    public let recentDailyTokens: Int64?
    public let recentDailyDate: String?
    public let lastUpdatedAt: Date

    public var canUseResetCredit: Bool {
        availableResetCredits > 0
    }

    public var availableResetCreditsAfterOne: Int {
        max(0, availableResetCredits - 1)
    }

    public static func make(
        rateLimits response: AccountRateLimitsResponse,
        usage: AccountUsageResponse,
        now: Date = Date()
    ) -> CodexSnapshot {
        let limits = response.rateLimitsByLimitId?["codex"] ?? response.rateLimits
        let used = min(max(limits.primary?.usedPercent ?? 0, 0), 100)
        let reached = limits.rateLimitReachedType != nil || limits.spendControlReached == true
        let availability: Availability

        if reached || used >= 100 {
            availability = .exhausted
        } else if used >= 85 {
            availability = .limited
        } else {
            availability = .ready
        }

        let latestDailyBucket = usage.dailyUsageBuckets?
            .sorted { $0.startDate < $1.startDate }
            .last

        return CodexSnapshot(
            availability: availability,
            planType: limits.planType ?? "unknown",
            usedPercent: used,
            remainingPercent: max(0, 100 - used),
            windowDurationMinutes: limits.primary?.windowDurationMins,
            resetsAt: limits.primary?.resetsAt.map {
                Date(timeIntervalSince1970: TimeInterval($0))
            },
            creditBalance: limits.credits?.balance,
            hasCredits: limits.credits?.hasCredits ?? false,
            unlimitedCredits: limits.credits?.unlimited ?? false,
            availableResetCredits: response.rateLimitResetCredits?.availableCount ?? 0,
            lifetimeTokens: usage.summary.lifetimeTokens,
            recentDailyTokens: latestDailyBucket?.tokens,
            recentDailyDate: latestDailyBucket?.startDate,
            lastUpdatedAt: now
        )
    }
}
