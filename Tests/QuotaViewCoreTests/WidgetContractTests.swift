import Foundation
import XCTest
@testable import QuotaViewWidgetContract

final class WidgetContractTests: XCTestCase {
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
                        id: "credits",
                        label: "Credits",
                        formattedValue: "10"
                    )
                ],
                availableResetCredits: 2
            )
        )
    }
}
