import Foundation
import XCTest
@testable import QuotaViewWidgetContract

final class WidgetContractTests: XCTestCase {
    func testDefaultAppGroupUsesDeveloperTeamPrefix() {
        XCTAssertEqual(
            QuotaViewWidgetConfiguration.defaultAppGroupIdentifier,
            "BUUH229D5Q.com.quotaview.shared"
        )
    }

    func testOfficialOpenAIPlanNamesCoverCodexPlanIdentifiers() {
        let expectedNames = [
            "free": "Free",
            "go": "Go",
            "plus": "Plus",
            "prolite": "Pro 5x",
            "pro": "Pro 20x",
            "team": "Business",
            "self_serve_business_usage_based": "Business",
            "business": "Business",
            "enterprise_cbp_usage_based": "Enterprise",
            "enterprise": "Enterprise",
            "edu": "Edu"
        ]

        for (rawValue, expectedName) in expectedNames {
            XCTAssertEqual(
                OpenAIPlanDisplayName.resolve(rawValue),
                expectedName
            )
        }
        XCTAssertEqual(
            OpenAIPlanDisplayName.resolve("  PRO-LITE  "),
            "Pro 5x"
        )
        XCTAssertNil(OpenAIPlanDisplayName.resolve("unknown"))
        XCTAssertNil(OpenAIPlanDisplayName.resolve("future_plan"))
        XCTAssertNil(OpenAIPlanDisplayName.resolve(nil))
    }

    func testCodecRoundTripsBoundedSnapshot() throws {
        let now = Date(timeIntervalSince1970: 1_785_000_000)
        let snapshot = makeSnapshot(now: now)
        let codec = WidgetSnapshotCodec()

        let data = try codec.encode(snapshot)
        let decoded = try codec.decode(
            data,
            now: now.addingTimeInterval(60)
        )

        XCTAssertEqual(decoded, snapshot)
        XCTAssertLessThan(
            data.count,
            WidgetSnapshotCodec.targetEncodedBytes
        )
        let encodedText = try XCTUnwrap(
            String(data: data, encoding: .utf8)
        )
        XCTAssertFalse(encodedText.contains("accountScope"))
        XCTAssertFalse(encodedText.contains("authorization"))
        XCTAssertFalse(encodedText.contains("prompt"))
    }

    func testFileStoreReadsLegacySchemaOneSnapshot() throws {
        // Written by the 0.2.1 codec (aef6e3c) in Swift 5 mode.
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/widget-schema-1", isDirectory: true)
        let store = WidgetSnapshotFileStore(containerURL: directory)
        let generatedAt = Date(timeIntervalSince1970: 1_785_000_000)
        let snapshot = try store.read(now: generatedAt.addingTimeInterval(60))

        XCTAssertEqual(snapshot.schemaVersion, 1)
        XCTAssertEqual(snapshot.availability, .available)
        XCTAssertEqual(snapshot.generatedAt, generatedAt)
        XCTAssertEqual(snapshot.expiresAt, generatedAt.addingTimeInterval(900))
        XCTAssertNil(snapshot.updatedAt)
        let provider = try XCTUnwrap(snapshot.provider)
        XCTAssertEqual(provider.primaryWindow?.remainingFraction, 0.75)
        XCTAssertEqual(provider.primaryWindow?.resetsAt, generatedAt.addingTimeInterval(3_600))
        XCTAssertEqual(provider.auxiliaryMetrics.first?.formattedValue, "42K")
        XCTAssertNil(provider.plan)
        XCTAssertNil(provider.availableResetCredits)
        let original = try Data(contentsOf: store.fileURL)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let output = WidgetSnapshotFileStore(containerURL: scratch)
        try output.write(snapshot)
        XCTAssertEqual(try Data(contentsOf: output.fileURL), original)
        XCTAssertEqual(try output.read(now: generatedAt), snapshot)
        XCTAssertThrowsError(try output.read(now: snapshot.expiresAt)) {
            XCTAssertEqual($0 as? WidgetSnapshotCodecError, .expired)
        }
        var future = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
        future["schemaVersion"] = 99
        try JSONSerialization.data(withJSONObject: future).write(to: output.fileURL)
        XCTAssertThrowsError(try output.read(now: generatedAt)) {
            XCTAssertEqual($0 as? WidgetSnapshotCodecError, .unsupportedSchema(99))
        }
    }

    func testCodecRejectsExpiredAndUnknownSnapshots() throws {
        let now = Date(timeIntervalSince1970: 1_785_000_000)
        let codec = WidgetSnapshotCodec()
        let validData = try codec.encode(makeSnapshot(now: now))

        XCTAssertThrowsError(
            try codec.decode(
                validData,
                now: now.addingTimeInterval(901)
            )
        ) { error in
            XCTAssertEqual(
                error as? WidgetSnapshotCodecError,
                .expired
            )
        }

        let unknown = QuotaViewWidgetSnapshot(
            schemaVersion: 99,
            generatedAt: now,
            expiresAt: now.addingTimeInterval(900),
            updatedAt: now,
            localeIdentifier: "zh-Hans",
            availability: .unavailable,
            provider: nil
        )
        XCTAssertThrowsError(try codec.encode(unknown)) { error in
            XCTAssertEqual(
                error as? WidgetSnapshotCodecError,
                .unsupportedSchema(99)
            )
        }
    }

    func testCodecRejectsOversizedPayload() {
        let data = Data(
            repeating: 0x20,
            count: WidgetSnapshotCodec.hardMaximumEncodedBytes + 1
        )

        XCTAssertThrowsError(
            try WidgetSnapshotCodec().decode(data, now: Date())
        ) { error in
            XCTAssertEqual(
                error as? WidgetSnapshotCodecError,
                .tooLarge
            )
        }
    }

    private func makeSnapshot(
        now: Date
    ) -> QuotaViewWidgetSnapshot {
        QuotaViewWidgetSnapshot(
            generatedAt: now,
            expiresAt: now.addingTimeInterval(900),
            updatedAt: now,
            localeIdentifier: "zh-Hans",
            availability: .available,
            provider: ProviderWidgetPayload(
                providerID: "codex",
                displayName: "Codex",
                plan: "plus",
                primaryWindow: WidgetQuotaWindow(
                    usedFraction: 0.25,
                    remainingFraction: 0.75,
                    resetsAt: now.addingTimeInterval(3_600)
                ),
                auxiliaryMetrics: [
                    WidgetAuxiliaryMetric(
                        id: WidgetAuxiliaryMetricIdentifier
                            .creditsBalance,
                        label: "Credits 余额",
                        formattedValue: "10"
                    ),
                    WidgetAuxiliaryMetric(
                        id: WidgetAuxiliaryMetricIdentifier.todayTokens,
                        label: "今日 Tokens",
                        formattedValue: "42K"
                    ),
                    WidgetAuxiliaryMetric(
                        id: WidgetAuxiliaryMetricIdentifier
                            .lifetimeTokens,
                        label: "累计 Tokens",
                        formattedValue: "9M"
                    )
                ],
                availableResetCredits: 2
            )
        )
    }
}
