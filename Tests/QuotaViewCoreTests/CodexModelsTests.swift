import XCTest
@testable import QuotaViewCore

final class CodexModelsTests: XCTestCase {
    func testProviderMapsCurrentAndHistoricalUsage() throws {
        let now = Date(timeIntervalSince1970: 1_785_000_000)
        let result = try makeResult(
            usedPercent: 34,
            reachedType: nil,
            resetCredits: 2,
            now: now
        )
        let snapshot = result.snapshot
        let primary = try XCTUnwrap(snapshot.rateWindows.first)
        let usedFraction = try XCTUnwrap(primary.usedFraction)
        let remainingFraction = try XCTUnwrap(
            primary.remainingFraction
        )

        XCTAssertEqual(snapshot.availability, .available)
        XCTAssertEqual(snapshot.plan?.rawValue, "plus")
        XCTAssertEqual(usedFraction, 0.34, accuracy: 0.0001)
        XCTAssertEqual(
            remainingFraction,
            0.66,
            accuracy: 0.0001
        )
        XCTAssertEqual(primary.quotaRisk, .normal)
        XCTAssertEqual(
            primary.resetsAt,
            Date(timeIntervalSince1970: 1_785_303_228)
        )
        XCTAssertEqual(
            count(
                CodexDomainCatalog.resetCreditsID,
                in: snapshot
            ),
            2
        )
        XCTAssertEqual(
            count(
                CodexDomainCatalog.lifetimeTokensID,
                in: snapshot
            ),
            123_456
        )
        XCTAssertEqual(result.historicalObservations.count, 2)
        XCTAssertEqual(
            result.historicalObservations.last?.source,
            .providerHistoricalBucket
        )
        XCTAssertEqual(
            result.historicalObservations.last?.value,
            .count(2_500)
        )
        XCTAssertEqual(snapshot.capturedAt, now)
    }

    func testProviderMarksHighUsageAsWarning() throws {
        let result = try makeResult(
            usedPercent: 91,
            reachedType: nil,
            resetCredits: 0
        )

        XCTAssertEqual(
            result.snapshot.rateWindows.first?.quotaRisk,
            .warning
        )
    }

    func testProviderMarksBackendLimitAsExhausted() throws {
        let result = try makeResult(
            usedPercent: 72,
            reachedType: "rate_limit_reached",
            resetCredits: 0
        )

        XCTAssertEqual(
            result.snapshot.rateWindows.first?.quotaRisk,
            .exhausted
        )
    }

    func testMissingPrimaryWindowIsNotConvertedToZero() throws {
        let rateLimits = try JSONDecoder().decode(
            AccountRateLimitsResponse.self,
            from: Data(
                """
                {
                  "rateLimits": {
                    "limitId": "codex",
                    "primary": null,
                    "secondary": null,
                    "credits": null,
                    "individualLimit": null,
                    "spendControlReached": false,
                    "planType": "plus",
                    "rateLimitReachedType": null
                  },
                  "rateLimitsByLimitId": null,
                  "rateLimitResetCredits": null
                }
                """.utf8
            )
        )
        let payload = CodexProviderPayload(
            rateLimits: rateLimits,
            usage: nil,
            capturedAt: Date(),
            optionalIssues: []
        )

        XCTAssertThrowsError(
            try CodexProviderAdapter.makeResult(payload: payload)
        ) { error in
            XCTAssertEqual(
                error as? ProviderError,
                .protocolViolation
            )
        }
    }

    func testOutOfRangeUsageIsRejected() throws {
        XCTAssertThrowsError(
            try makeResult(
                usedPercent: 101,
                reachedType: nil,
                resetCredits: 0
            )
        ) { error in
            XCTAssertEqual(
                error as? ProviderError,
                .protocolViolation
            )
        }
    }

    private func makeResult(
        usedPercent: Int,
        reachedType: String?,
        resetCredits: Int,
        now: Date = Date(timeIntervalSince1970: 1_785_000_000)
    ) throws -> ProviderFetchResult {
        let payload = CodexProviderPayload(
            rateLimits: try decodeRateLimits(
                usedPercent: usedPercent,
                reachedType: reachedType,
                resetCredits: resetCredits
            ),
            usage: try decodeUsage(),
            capturedAt: now,
            optionalIssues: []
        )
        return try CodexProviderAdapter.makeResult(
            payload: payload
        )
    }

    private func decodeRateLimits(
        usedPercent: Int,
        reachedType: String?,
        resetCredits: Int
    ) throws -> AccountRateLimitsResponse {
        let reachedValue = reachedType.map {
            "\"\($0)\""
        } ?? "null"
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

    private func count(
        _ id: MetricID,
        in snapshot: ProviderSnapshot
    ) -> Int64? {
        guard case .count(let value) = snapshot.currentMetrics
            .first(where: { $0.definitionID == id })?
            .value else {
            return nil
        }
        return value
    }
}
