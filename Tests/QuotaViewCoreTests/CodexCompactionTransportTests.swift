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
                            sessionKind: .user, source: .localRollout, occurredAt: Date().addingTimeInterval(-1)))
        store.receive(CodexActivityTokenUsageUpdate(sessionHash: session, turnHash: turn,
            cumulativeTotalTokens: 500, lastReportedTotalTokens: 20,
            directTurnTotalTokens: 300, occurredAt: Date()))
        let identity = try XCTUnwrap(store.snapshot?.taskIdentity)
        let sink = CompactionDeliverySink()
        let received = expectation(description: "Two distinct helper events reach the domain through either transport")
        received.expectedFulfillmentCount = 2
        let preApplied = expectation(description: "This helper PreCompact reaches its domain state")
        let postApplied = expectation(description: "This helper PostCompact reaches its domain state")
        let replayed = expectation(description: "Private queue duplicate acknowledged")
        var replayTargetID: String?
        let handler: CodexActivityDeliveryHandler = { delivery, accepted in
            Task { @MainActor in
                await store.receiveClassified(delivery)
                let first = await sink.appendUnique(delivery)
                // ACK every authenticated delivery. A lost socket ACK can cause
                // the same event ID to arrive again through the durable queue.
                accepted(true)
                if first {
                    received.fulfill()
                    switch delivery.activity.event {
                    case .preCompact: preApplied.fulfill()
                    case .postCompact: postApplied.fulfill()
                    default: XCTFail("Unexpected helper event in compaction fixture")
                    }
                } else if delivery.source == .liveQueue, delivery.eventID == replayTargetID {
                    replayTargetID = nil
                    replayed.fulfill()
                }
            }
        }
        // Both reliable paths are ready before launching any helper. Busy CI
        // may exceed the production ACK budget and legitimately use fallback.
        try fileBridge.start(handler: handler)
        try bridge.start(handler: handler)
        for (event, state, applied) in [("PreCompact", CodexActivityVisualState.compactingContext, preApplied),
                                      ("PostCompact", .thinking, postApplied)] {
            let payload = try JSONSerialization.data(withJSONObject: [
                "hook_event_name": event, "session_id": "fixture-session",
                "trigger": "auto", "cwd": "/private/PRIVATE-PATH/project",
                "transcript_path": "/private/PRIVATE-TRANSCRIPT", "prompt": "PRIVATE-CONTENT"
            ])
            let status = try await Self.runHelper(payload: payload, socket: socket, queue: queue)
            XCTAssertEqual(status, 0)
            // Helper exit is fail-open and is not a domain-application barrier.
            // Wait for this exact event, not a retry or an unrelated next event.
            await fulfillment(of: [applied], timeout: 8)
            XCTAssertEqual(store.snapshot?.state, state)
            XCTAssertEqual(store.snapshot?.taskIdentity, identity)
            XCTAssertEqual(store.currentTurnTokenUsage, 300)
        }
        await fulfillment(of: [received], timeout: 1)
        let deliveries = await sink.deliveries
        XCTAssertEqual(deliveries.count, 2)
        for delivery in deliveries {
            XCTAssertTrue([.liveSocket, .liveQueue].contains(delivery.source))
            XCTAssertNotNil(delivery.eventID)
            XCTAssertEqual(delivery.activity.source, .hook)
            XCTAssertNil(delivery.activity.turnHash)
            XCTAssertEqual(delivery.activity.workspaceName, "project")
            let encoded = String(decoding: try JSONEncoder().encode(delivery.activity), as: UTF8.self)
            for privateValue in ["fixture-session", "PRIVATE-PATH", "PRIVATE-TRANSCRIPT", "PRIVATE-CONTENT"] {
                XCTAssertFalse(encoded.contains(privateValue))
            }
        }
        // Finish any real helper fallback/duplicate cleanup before introducing
        // a deliberate replay. Both helpers have already exited, so no helper
        // can later create another fallback file for this phase.
        try await waitForQueueToDrain(queue)
        let start = try XCTUnwrap(deliveries.first { $0.activity.event == .preCompact })
        replayTargetID = try XCTUnwrap(start.eventID)
        let envelope = CodexActivityBridgeEnvelope(authenticationToken: "fixture-token",
            installationIdentifier: "fixture-install", eventID: start.eventID, activity: start.activity)
        try JSONEncoder().encode(envelope).write(to: queue.appendingPathComponent("event-replay.json"), options: .atomic)
        await fulfillment(of: [replayed], timeout: 8)
        try await waitForQueueToDrain(queue)
        XCTAssertEqual(store.snapshot?.state, .thinking)
        XCTAssertEqual(store.snapshot?.taskIdentity, identity)
        XCTAssertEqual(store.lifecycle, .active)
        XCTAssertEqual(store.currentTurnTokenUsage, 300)
        let finalDeliveries = await sink.deliveries
        XCTAssertEqual(finalDeliveries.count, 2, "Duplicate replay is acknowledged without becoming another domain event")
        await store.stop()
    }

    @MainActor
    private func waitForQueueToDrain(_ queue: URL) async throws {
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            let events = try FileManager.default.contentsOfDirectory(at: queue, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasPrefix("event-") && $0.pathExtension == "json" }
            if events.isEmpty { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Accepted private queue events were not cleaned up within the bounded delivery phase")
    }

    private static func runHelper(payload: Data, socket: URL, queue: URL) async throws -> Int32 {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let helper = repo.appendingPathComponent(".build/debug/QuotaViewActivityHook")
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            throw XCTSkip("Build QuotaViewActivityHook before running the transport integration test")
        }
        return try await Task.detached {
            let process = Process()
            // Run the unmodified helper. Its explicit fallback/log path belongs
            // to this fixture; the user's real global queue remains forbidden.
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
            let liveQueue = "/tmp/com.quotaview.codex-activity-\(getuid())"
            let profile = "(version 1)(allow default)(deny file-write* (subpath \"\(liveQueue)\") (subpath \"/private\(liveQueue)\"))"
            process.arguments = ["-p", profile, helper.path, "--socket", socket.path,
                "--token", "fixture-token", "--installation-id", "fixture-install", "--queue", queue.path]
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
    private var eventIDs: Set<String> = []
    func appendUnique(_ delivery: CodexActivityDelivery) -> Bool {
        guard let id = delivery.eventID, !id.isEmpty, eventIDs.insert(id).inserted else { return false }
        deliveries.append(delivery)
        return true
    }
}
