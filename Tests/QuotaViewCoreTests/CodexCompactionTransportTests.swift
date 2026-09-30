import Foundation
import XCTest
@testable import QuotaView
@testable import QuotaViewCore

final class CodexCompactionTransportTests: XCTestCase {
    @MainActor
    func testRealHelperSocketAcknowledgementAndQueueReplayKeepTurnState() async throws {
        let root = URL(fileURLWithPath: "/tmp/qv-compact-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let socket = root.appendingPathComponent("activity.sock")
        let queue = root.appendingPathComponent("queue")
        let bridge = CodexActivityUnixBridge(socketURL: socket,
            authenticationToken: "fixture-token", installationIdentifier: "fixture-install")
        let fileBridge = CodexActivityFileBridge(queueURL: queue,
            authenticationToken: "fixture-token", installationIdentifier: "fixture-install")
        defer { bridge.stop(); fileBridge.stop() }
        let store = CodexActivityStore(titleClient: CodexAppServerClient(executablePath: nil),
            sessionKindResolver: { _ in .user })
        let session = CodexActivityPrivacy.hashIdentifier("fixture-session")
        let turn = CodexActivityPrivacy.hashIdentifier("fixture-turn")
        store.receive(.init(event: .userPromptSubmit, sessionHash: session, turnHash: turn,
                            source: .localRollout, occurredAt: Date().addingTimeInterval(-1)))
        store.receive(CodexActivityTokenUsageUpdate(sessionHash: session, turnHash: turn,
            cumulativeTotalTokens: 500, lastReportedTotalTokens: 20,
            directTurnTotalTokens: 300, occurredAt: Date()))
        let identity = store.snapshot?.taskIdentity
        let sink = CompactionDeliverySink()
        let received = expectation(description: "Actual helper events acknowledged after store admission")
        received.expectedFulfillmentCount = 2
        try bridge.start { delivery, accepted in
            Task { @MainActor in
                await store.receiveClassified(delivery)
                await sink.append(delivery)
                accepted(true)
                received.fulfill()
            }
        }
        for (event, state) in [("PreCompact", CodexActivityVisualState.compactingContext),
                               ("PostCompact", .thinking)] {
            let payload = try JSONSerialization.data(withJSONObject: [
                "hook_event_name": event, "session_id": "fixture-session",
                "trigger": "auto", "cwd": "/private/PRIVATE-PATH/project",
                "transcript_path": "/private/PRIVATE-TRANSCRIPT", "prompt": "PRIVATE-CONTENT"
            ])
            let status = try await Self.runHelper(payload: payload, socket: socket)
            XCTAssertEqual(status, 0)
            XCTAssertEqual(store.snapshot?.state, state)
            XCTAssertEqual(store.snapshot?.taskIdentity, identity)
            XCTAssertEqual(store.currentTurnTokenUsage, 300)
        }
        await fulfillment(of: [received], timeout: 5)
        let deliveries = await sink.deliveries
        XCTAssertEqual(deliveries.count, 2)
        for delivery in deliveries {
            XCTAssertEqual(delivery.source, .liveSocket)
            XCTAssertEqual(delivery.activity.source, .hook)
            XCTAssertNil(delivery.activity.turnHash)
            XCTAssertEqual(delivery.activity.workspaceName, "project")
            let encoded = String(decoding: try JSONEncoder().encode(delivery.activity), as: UTF8.self)
            for privateValue in ["fixture-session", "PRIVATE-PATH", "PRIVATE-TRANSCRIPT", "PRIVATE-CONTENT"] {
                XCTAssertFalse(encoded.contains(privateValue))
            }
        }
        // Re-delivery after an ACK was lost uses the original event ID. Both
        // the real socket and the private file receiver must share deduplication.
        let replayed = expectation(description: "Private queue duplicate acknowledged")
        try fileBridge.start { delivery, accepted in
            Task { @MainActor in
                await store.receiveClassified(delivery)
                accepted(true)
                replayed.fulfill()
            }
        }
        let start = try XCTUnwrap(deliveries.first)
        let envelope = CodexActivityBridgeEnvelope(authenticationToken: "fixture-token",
            installationIdentifier: "fixture-install", eventID: start.eventID, activity: start.activity)
        try JSONEncoder().encode(envelope).write(to: queue.appendingPathComponent("event-replay.json"), options: .atomic)
        await fulfillment(of: [replayed], timeout: 5)
        XCTAssertEqual(store.snapshot?.state, .thinking)
        XCTAssertEqual(store.lifecycle, .active)
        XCTAssertEqual(store.currentTurnTokenUsage, 300)
        await store.stop()
    }

    private static func runHelper(payload: Data, socket: URL) async throws -> Int32 {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let helper = repo.appendingPathComponent(".build/debug/QuotaViewActivityHook")
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            throw XCTSkip("Build QuotaViewActivityHook before running the transport integration test")
        }
        return try await Task.detached {
            let process = Process()
            // Run the unmodified helper binary, while preventing its fixed
            // fallback/log directory from touching the user's live bridge.
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
            let liveQueue = "/tmp/com.quotaview.codex-activity-\(getuid())"
            let profile = "(version 1)(allow default)(deny file-write* (subpath \"\(liveQueue)\") (subpath \"/private\(liveQueue)\"))"
            process.arguments = ["-p", profile, helper.path, "--socket", socket.path,
                "--token", "fixture-token", "--installation-id", "fixture-install"]
            let input = Pipe()
            process.standardInput = input
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            try input.fileHandleForWriting.write(contentsOf: payload)
            try input.fileHandleForWriting.close()
            process.waitUntilExit()
            return process.terminationStatus
        }.value
    }
}

private actor CompactionDeliverySink {
    var deliveries: [CodexActivityDelivery] = []
    func append(_ delivery: CodexActivityDelivery) { deliveries.append(delivery) }
}
