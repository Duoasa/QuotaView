import Foundation
import XCTest
@testable import QuotaView
@testable import QuotaViewCore

final class CodexPluginBridgeLiveTests: XCTestCase {
    func testExplicitLivePluginDirectoryUsesProductionReader() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let rootPath = environment[
            "QUOTAVIEW_PLUGIN_DATA_E2E"
        ]?.trimmingCharacters(in: .whitespacesAndNewlines),
        !rootPath.isEmpty else {
            throw XCTSkip(
                "Set QUOTAVIEW_PLUGIN_DATA_E2E for an explicit live plugin check."
            )
        }
        guard rootPath.hasPrefix("/"), !rootPath.contains("\0") else {
            XCTFail("The explicit live plugin path must be absolute and safe.")
            return
        }

        let result = try CodexActivityRuntime.readBridgeDirectory(
            at: URL(fileURLWithPath: rootPath, isDirectory: true),
            cursor: nil,
            consumesEvents: true
        )

        XCTAssertEqual(result.manifest.pluginID, "quotaview")
        XCTAssertEqual(
            result.manifest.distributionChannel,
            "git-marketplace"
        )
        if let expectedVersion = environment[
            "QUOTAVIEW_PLUGIN_EXPECTED_VERSION"
        ], !expectedVersion.isEmpty {
            XCTAssertEqual(
                result.manifest.pluginVersion,
                expectedVersion
            )
        }
        XCTAssertEqual(result.skippedMalformedEvents, 0)
        if environment["QUOTAVIEW_PLUGIN_EXPECT_USAGE"] == "1" {
            let usage = try XCTUnwrap(result.usageSnapshot)
            XCTAssertEqual(usage.source, "codex-app-server")
            XCTAssertEqual(
                usage.installationIdentifier,
                result.manifest.installationIdentifier
            )
        } else {
            XCTAssertFalse(result.envelopes.isEmpty)
            XCTAssertEqual(
                result.status?.latestSequence,
                result.cursor?.sequence
            )
        }

        if let expectedEventList = environment[
            "QUOTAVIEW_PLUGIN_EXPECTED_EVENTS"
        ], !expectedEventList.isEmpty {
            let expectedEvents = expectedEventList
                .split(separator: ",")
                .map(String.init)
            XCTAssertEqual(
                result.envelopes.map(\.activity.event.rawValue),
                expectedEvents
            )
        }
    }
}
