import XCTest
@testable import CodexPulseCore

final class CodexModelsTests: XCTestCase {
    func testSnapshotMapsRateLimitAndUsageFields() throws {
        let rateLimits = try decodeRateLimits(
            usedPercent: 34,
            reachedType: nil,
            resetCredits: 2
        )
        let usage = try decodeUsage()
        let now = Date(timeIntervalSince1970: 1_785_000_000)

        let snapshot = CodexSnapshot.make(
            rateLimits: rateLimits,
            usage: usage,
            now: now
        )

        XCTAssertEqual(snapshot.availability, .ready)
        XCTAssertEqual(snapshot.planType, "plus")
        XCTAssertEqual(snapshot.usedPercent, 34)
        XCTAssertEqual(snapshot.remainingPercent, 66)
        XCTAssertEqual(snapshot.windowDurationMinutes, 10_080)
        XCTAssertEqual(
            snapshot.resetsAt,
            Date(timeIntervalSince1970: 1_785_303_228)
        )
        XCTAssertEqual(snapshot.creditBalance, "0")
        XCTAssertFalse(snapshot.hasCredits)
        XCTAssertEqual(snapshot.availableResetCredits, 2)
        XCTAssertTrue(snapshot.canUseResetCredit)
        XCTAssertEqual(snapshot.availableResetCreditsAfterOne, 1)
        XCTAssertEqual(snapshot.lifetimeTokens, 123_456)
        XCTAssertEqual(snapshot.recentDailyDate, "2026-07-25")
        XCTAssertEqual(snapshot.recentDailyTokens, 2_500)
        XCTAssertEqual(snapshot.lastUpdatedAt, now)
    }

    func testSnapshotMarksHighUsageAsLimited() throws {
        let rateLimits = try decodeRateLimits(
            usedPercent: 91,
            reachedType: nil,
            resetCredits: 0
        )

        let snapshot = CodexSnapshot.make(
            rateLimits: rateLimits,
            usage: try decodeUsage()
        )

        XCTAssertEqual(snapshot.availability, .limited)
        XCTAssertEqual(snapshot.remainingPercent, 9)
        XCTAssertFalse(snapshot.canUseResetCredit)
        XCTAssertEqual(snapshot.availableResetCreditsAfterOne, 0)
    }

    func testSnapshotMarksBackendLimitAsExhausted() throws {
        let rateLimits = try decodeRateLimits(
            usedPercent: 72,
            reachedType: "rate_limit_reached",
            resetCredits: 0
        )

        let snapshot = CodexSnapshot.make(
            rateLimits: rateLimits,
            usage: try decodeUsage()
        )

        XCTAssertEqual(snapshot.availability, .exhausted)
    }

    private func decodeRateLimits(
        usedPercent: Int,
        reachedType: String?,
        resetCredits: Int
    ) throws -> AccountRateLimitsResponse {
        let reachedValue = reachedType.map { "\"\($0)\"" } ?? "null"
        let json = """
        {
          "rateLimits": {
            "limitId": "codex",
            "limitName": null,
            "primary": {
              "usedPercent": \(usedPercent),
              "windowDurationMins": 10080,
              "resetsAt": 1785303228
            },
            "secondary": null,
            "credits": {
              "hasCredits": false,
              "unlimited": false,
              "balance": "0"
            },
            "individualLimit": null,
            "spendControlReached": false,
            "planType": "plus",
            "rateLimitReachedType": \(reachedValue)
          },
          "rateLimitsByLimitId": null,
          "rateLimitResetCredits": {
            "availableCount": \(resetCredits),
            "credits": []
          }
        }
        """

        return try JSONDecoder().decode(
            AccountRateLimitsResponse.self,
            from: Data(json.utf8)
        )
    }

    private func decodeUsage() throws -> AccountUsageResponse {
        let json = """
        {
          "summary": {
            "lifetimeTokens": 123456,
            "peakDailyTokens": 2500,
            "longestRunningTurnSec": 600,
            "currentStreakDays": 3,
            "longestStreakDays": 5
          },
          "dailyUsageBuckets": [
            { "startDate": "2026-07-24", "tokens": 1000 },
            { "startDate": "2026-07-25", "tokens": 2500 }
          ]
        }
        """

        return try JSONDecoder().decode(
            AccountUsageResponse.self,
            from: Data(json.utf8)
        )
    }
}
