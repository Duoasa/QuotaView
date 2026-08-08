import Foundation
import XCTest
@testable import QuotaViewCore

final class CodexPluginBridgeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_786_000_000)
    private let installationID = "install-12345678"
    private let activityHash = String(repeating: "a", count: 64)

    func testValidManifestAndEventDecode() throws {
        let manifest = try CodexPluginBridgeDecoder.manifest(
            from: manifestData()
        )
        let envelope = try XCTUnwrap(
            CodexPluginBridgeDecoder.activityEnvelope(
                from: eventData(occurredAt: now),
                fileSequence: 42,
                manifest: manifest,
                cursor: nil,
                now: now
            )
        )

        XCTAssertEqual(manifest.pluginID, "quotaview")
        XCTAssertEqual(envelope.sequence, 42)
        XCTAssertEqual(envelope.activity.event, .preToolUse)
        XCTAssertEqual(envelope.activity.workspaceName, "QuotaView")
        XCTAssertEqual(envelope.activity.toolCategory, .fileEdit)
    }

    func testCursorPreventsDuplicateReplay() throws {
        let manifest = try CodexPluginBridgeDecoder.manifest(
            from: manifestData()
        )
        let cursor = CodexPluginBridgeCursor(
            installationIdentifier: installationID,
            sequence: 42
        )

        XCTAssertNil(
            try CodexPluginBridgeDecoder.activityEnvelope(
                from: eventData(occurredAt: now),
                fileSequence: 42,
                manifest: manifest,
                cursor: cursor,
                now: now
            )
        )
    }

    func testRejectsSensitiveLookingWorkspacePathAndOldEvent() throws {
        let manifest = try CodexPluginBridgeDecoder.manifest(
            from: manifestData()
        )
        XCTAssertThrowsError(
            try CodexPluginBridgeDecoder.activityEnvelope(
                from: eventData(
                    workspaceName: "/Users/example/QuotaView",
                    occurredAt: now
                ),
                fileSequence: 42,
                manifest: manifest,
                cursor: nil,
                now: now
            )
        ) { error in
            XCTAssertEqual(
                error as? CodexPluginBridgeValidationError,
                .invalidWorkspaceName
            )
        }
        XCTAssertThrowsError(
            try CodexPluginBridgeDecoder.activityEnvelope(
                from: eventData(
                    occurredAt: now.addingTimeInterval(-86_401)
                ),
                fileSequence: 42,
                manifest: manifest,
                cursor: nil,
                now: now
            )
        ) { error in
            XCTAssertEqual(
                error as? CodexPluginBridgeValidationError,
                .eventExpired
            )
        }
    }

    func testRejectsMismatchedSequenceAndInstallation() throws {
        let manifest = try CodexPluginBridgeDecoder.manifest(
            from: manifestData()
        )
        XCTAssertThrowsError(
            try CodexPluginBridgeDecoder.activityEnvelope(
                from: eventData(occurredAt: now),
                fileSequence: 41,
                manifest: manifest,
                cursor: nil,
                now: now
            )
        ) { error in
            XCTAssertEqual(
                error as? CodexPluginBridgeValidationError,
                .sequenceMismatch
            )
        }
        XCTAssertThrowsError(
            try CodexPluginBridgeDecoder.activityEnvelope(
                from: eventData(
                    installationIdentifier: "other-installation",
                    occurredAt: now
                ),
                fileSequence: 42,
                manifest: manifest,
                cursor: nil,
                now: now
            )
        ) { error in
            XCTAssertEqual(
                error as? CodexPluginBridgeValidationError,
                .installationMismatch
            )
        }
    }

    func testPairingURLUsesStrictAllowlist() throws {
        let request = try CodexPluginPairingRequest(
            url: URL(
                string: "quotaview://pair?protocol=1&plugin=quotaview&pathHint=%2Ftmp%2Fplugin"
            )!
        )
        XCTAssertEqual(request.pathHint, "/tmp/plugin")

        XCTAssertThrowsError(
            try CodexPluginPairingRequest(
                url: URL(
                    string: "quotaview://pair?protocol=1&plugin=quotaview&token=secret"
                )!
            )
        )
        XCTAssertThrowsError(
            try CodexPluginPairingRequest(
                url: URL(
                    string: "quotaview://pair:444?protocol=1&plugin=quotaview"
                )!
            )
        )
        XCTAssertThrowsError(
            try CodexPluginPairingRequest(
                url: URL(
                    string: "quotaview://pair?protocol=1&plugin=quotaview&pathHint=relative"
                )!
            )
        )
    }

    func testRejectsFutureBridgeMetadataAndBidirectionalNames()
        throws
    {
        let futureManifest = Data(
            String(
                data: manifestData(),
                encoding: .utf8
            )!.replacingOccurrences(
                of: "2026-08-06T00:00:00Z",
                with: "2036-08-06T00:00:00Z"
            ).utf8
        )
        XCTAssertThrowsError(
            try CodexPluginBridgeDecoder.manifest(
                from: futureManifest,
                now: now
            )
        ) { error in
            XCTAssertEqual(
                error as? CodexPluginBridgeValidationError,
                .invalidMetadata
            )
        }

        let manifest = try CodexPluginBridgeDecoder.manifest(
            from: manifestData(),
            now: now
        )
        XCTAssertThrowsError(
            try CodexPluginBridgeDecoder.activityEnvelope(
                from: eventData(
                    workspaceName: "Quota\u{202E}View",
                    occurredAt: now
                ),
                fileSequence: 42,
                manifest: manifest,
                cursor: nil,
                now: now
            )
        ) { error in
            XCTAssertEqual(
                error as? CodexPluginBridgeValidationError,
                .invalidWorkspaceName
            )
        }
    }

    func testEventFileNameRequiresFixedWidthMonotonicSequence() {
        XCTAssertEqual(
            CodexPluginBridgeDecoder.eventSequence(
                fromFileName: "000000000042.json"
            ),
            42
        )
        XCTAssertNil(
            CodexPluginBridgeDecoder.eventSequence(
                fromFileName: "42.json"
            )
        )
        XCTAssertNil(
            CodexPluginBridgeDecoder.eventSequence(
                fromFileName: "000000000000.json"
            )
        )
    }

    private func manifestData() -> Data {
        Data(
            """
            {
              "pluginId": "quotaview",
              "pluginVersion": "1.0.0-preview.1",
              "distributionChannel": "git-marketplace",
              "bridgeProtocolVersion": 1,
              "eventSchemaVersion": 1,
              "installationIdentifier": "\(installationID)",
              "createdAt": "2026-08-06T00:00:00Z",
              "capabilities": ["codex-activity-events"]
            }
            """.utf8
        )
    }

    private func eventData(
        installationIdentifier: String? = nil,
        workspaceName: String = "QuotaView",
        occurredAt: Date
    ) -> Data {
        let formatter = ISO8601DateFormatter()
        return Data(
            """
            {
              "bridgeProtocolVersion": 1,
              "installationIdentifier": "\(installationIdentifier ?? installationID)",
              "sequence": 42,
              "activity": {
                "schemaVersion": 1,
                "event": "PreToolUse",
                "sessionHash": "\(activityHash)",
                "turnHash": null,
                "workspaceName": "\(workspaceName)",
                "toolCategory": "fileEdit",
                "sessionStartSource": null,
                "occurredAt": "\(formatter.string(from: occurredAt))"
              }
            }
            """.utf8
        )
    }
}
