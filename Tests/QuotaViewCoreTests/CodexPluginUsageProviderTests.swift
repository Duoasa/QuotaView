import Foundation
import XCTest
@testable import QuotaViewCore

final class CodexPluginUsageProviderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_786_000_000)
    private let installationID = "install-usage-1234"

    func testDecoderAcceptsSanitizedSnapshot() throws {
        let snapshot = try CodexPluginUsageSnapshotDecoder.snapshot(
            from: usageData(),
            manifest: manifest(),
            now: now
        )

        XCTAssertEqual(snapshot.planType, "plus")
        XCTAssertEqual(snapshot.primary.usedPercent, 5)
        XCTAssertEqual(snapshot.lifetimeTokens, 12_345)
        XCTAssertEqual(snapshot.recentDailyTokens, 678)
    }

    func testDecoderRejectsUnapprovedIdentityFields() {
        let unsafe = Data(
            String(data: usageData(), encoding: .utf8)!
                .replacingOccurrences(
                    of: "\"planType\": \"plus\",",
                    with: "\"planType\": \"plus\", \"email\": \"person@example.com\","
                )
                .utf8
        )

        XCTAssertThrowsError(
            try CodexPluginUsageSnapshotDecoder.snapshot(
                from: unsafe,
                manifest: manifest(),
                now: now
            )
        ) { error in
            XCTAssertEqual(
                error as? CodexPluginBridgeValidationError,
                .invalidUsageSnapshot
            )
        }
    }

    func testProviderMapsSnapshotWithoutAccountScope() throws {
        let usage = try CodexPluginUsageSnapshotDecoder.snapshot(
            from: usageData(),
            manifest: manifest(),
            now: now
        )
        let result = try CodexPluginUsageProviderAdapter.makeResult(
            usage: usage
        )

        XCTAssertNil(result.snapshot.accountScope)
        XCTAssertEqual(result.snapshot.plan?.rawValue, "plus")
        XCTAssertEqual(result.snapshot.rateWindows.first?.usedFraction, 0.05)
        XCTAssertEqual(
            result.snapshot.rateWindows.first?.remainingFraction,
            0.95
        )
        XCTAssertEqual(result.historicalObservations.count, 1)
        XCTAssertEqual(
            result.diagnostics.sourceLabel,
            "codex-plugin-snapshot"
        )
    }

    func testMissingUsageSnapshotRequestsOfficialCodexSignIn() async {
        let adapter = CodexPluginUsageProviderAdapter(
            loadSnapshot: {
                throw CodexPluginBridgeValidationError
                    .usageSnapshotMissing
            }
        )
        let request = ProviderFetchRequest(
            generation: 1,
            enablementRevision: 0,
            configurationRevision: 0,
            reason: .manual,
            deadline: Date().addingTimeInterval(5),
            capabilities: .currentQuotaViewFeatures,
            expectedAccountScope: nil,
            correlationID: "usage-missing"
        )

        do {
            _ = try await adapter.fetch(request)
            XCTFail("A missing plugin snapshot must require Codex sign-in.")
        } catch let error as ProviderError {
            XCTAssertEqual(error, .authenticationRequired)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func manifest() -> CodexPluginBridgeManifest {
        CodexPluginBridgeManifest(
            pluginID: CodexPluginBridgeContract.pluginID,
            pluginVersion: "1.0.0-preview.3",
            distributionChannel: "git-marketplace",
            bridgeProtocolVersion:
                CodexPluginBridgeContract.protocolVersion,
            eventSchemaVersion:
                CodexPluginBridgeContract.eventSchemaVersion,
            installationIdentifier: installationID,
            createdAt: now,
            capabilities: [
                CodexPluginBridgeContract.activityCapability,
                CodexPluginBridgeContract.usageCapability
            ]
        )
    }

    private func usageData() -> Data {
        Data(
            """
            {
              "bridgeProtocolVersion": 1,
              "installationIdentifier": "\(installationID)",
              "usageSchemaVersion": 1,
              "capturedAt": "2026-08-06T00:53:20Z",
              "source": "codex-app-server",
              "planType": "plus",
              "primary": {
                "usedPercent": 5,
                "windowDurationMins": 10080,
                "resetsAt": 1786600000
              },
              "credits": {
                "hasCredits": true,
                "unlimited": false,
                "balance": "10.5"
              },
              "limitReached": false,
              "lifetimeTokens": 12345,
              "recentDailyTokens": 678,
              "recentDailyDate": "2026-08-06"
            }
            """.utf8
        )
    }
}
