import Foundation
import XCTest
@testable import QuotaView
@testable import QuotaViewCore

final class CodexCompactionTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 2_000_000_000)
    private var session: String { CodexActivityPrivacy.hashIdentifier("thread") }
    private var turn: String { CodexActivityPrivacy.hashIdentifier("turn") }

    private func native(_ method: String, item: String = "compact-1", turn: String = "turn",
                        type: String = "contextCompaction", at: TimeInterval) throws -> CodexActivityEvent? {
        let timeKey = method == "item/started" ? "startedAtMs" : "completedAtMs"
        let data = try JSONSerialization.data(withJSONObject: [
            "method": method, "params": [
                "threadId": "thread", "turnId": turn,
                timeKey: (base.timeIntervalSince1970 + at) * 1_000,
                "item": ["type": type, "id": item, "text": "PRIVATE CONTENT"]
            ]
        ])
        return CodexAppServerActivityNotificationDecoder.decode(data: data)
    }

    func testNativeLifecycleUsesItemTimestampsAndOnlyRetainsHashedMetadata() throws {
        for (method, expected) in [("item/started", CodexActivityHookEvent.preCompact),
                                   ("item/completed", .postCompact)] {
            let event = try XCTUnwrap(native(method, at: 3))
            XCTAssertEqual(event.event, expected)
            XCTAssertEqual(event.source, .appServer)
            XCTAssertEqual(event.occurredAt, base.addingTimeInterval(3))
            XCTAssertEqual(event.compactionItemHash, CodexActivityPrivacy.hashIdentifier("compact-1"))
            XCTAssertEqual(event.classified(as: .user).compactionItemHash, event.compactionItemHash)
            let encoded = String(decoding: try JSONEncoder().encode(event), as: UTF8.self)
            XCTAssertFalse(encoded.contains("PRIVATE CONTENT"))
            XCTAssertFalse(encoded.contains("compact-1"))
        }
        for type in ["agentMessage", "reasoning", "commandExecution", "ContextCompaction"] {
            XCTAssertNil(try native("item/started", type: type, at: 1))
        }
        XCTAssertNil(try native("item/started", item: "", at: 1))
        XCTAssertNil(try native("item/started", turn: "", at: 1))
    }

    @MainActor
    func testNativeStartAndEndOnlyRolloutPreserveProgressAndDoNotCompleteTurn() async throws {
        let store = CodexActivityStore(titleClient: CodexAppServerClient(executablePath: nil))
        store.receive(.init(event: .userPromptSubmit, sessionHash: session, turnHash: turn,
                            source: .localRollout, occurredAt: base))
        store.receive(.init(event: .preToolUse, sessionHash: session, turnHash: turn,
                            planProgress: .init(completedSteps: 1, inProgressSteps: 1, pendingSteps: 2),
                            source: .localRollout, planSource: .localRollout,
                            occurredAt: base.addingTimeInterval(1)))
        store.receive(CodexActivityTokenUsageUpdate(sessionHash: session, turnHash: turn,
            cumulativeTotalTokens: 20_000, lastReportedTotalTokens: 100,
            directTurnTotalTokens: 10_000, occurredAt: base.addingTimeInterval(1)))
        let progress = store.snapshot?.approximateProgressFraction
        let start = try XCTUnwrap(native("item/started", at: 2))
        store.receive(start)
        XCTAssertEqual(store.snapshot?.state, .compactingContext)
        XCTAssertEqual(store.currentTurnTokenUsage, 10_000)
        XCTAssertEqual(store.snapshot?.approximateProgressFraction, progress)

        var rollout = CodexLocalRolloutLineDecoder(sessionHash: session)
        _ = rollout.decode(line: Data(#"{"type":"event_msg","payload":{"type":"task_started","turn_id":"turn"}}"#.utf8), now: base)
        // Real rollout shape: a completed item without a preceding item_started.
        let line = Data(#"{"type":"event_msg","payload":{"type":"item_completed","thread_id":"thread","turn_id":"turn","started_at_ms":2000000002000,"completed_at_ms":2000000005000,"item":{"type":"ContextCompaction","id":"compact-1"}}}"#.utf8)
        let decoded = try XCTUnwrap(rollout.decode(line: line, now: base.addingTimeInterval(5)))
        guard case .activity(let end) = decoded.update else { return XCTFail("Expected compaction end") }
        store.receive(end)
        XCTAssertEqual(store.snapshot?.state, .thinking)
        XCTAssertEqual(store.lifecycle, .active)
        XCTAssertEqual(store.currentTurnTokenUsage, 10_000)
        XCTAssertEqual(store.snapshot?.approximateProgressFraction, progress)

        store.receive(start) // Delayed duplicate must not re-enter compaction.
        XCTAssertEqual(store.snapshot?.state, .thinking)
        store.receive(.init(event: .stop, sessionHash: session, turnHash: turn,
                            source: .localRollout, turnCompletionStatus: .completed,
                            occurredAt: base.addingTimeInterval(6)))
        store.receive(try XCTUnwrap(native("item/started", item: "late", at: 7)))
        XCTAssertEqual(store.lifecycle, .completed)
        await store.stop()
    }

    func testCompletionBeforeStartAndMismatchedItemsCannotCorruptCompaction() throws {
        var registry = CodexActivityTaskRegistry()
        func admit(_ event: CodexActivityEvent) -> CodexActivityTaskRegistry.Admission? {
            registry.admit(event, kind: .user, selectedSession: session)
        }
        XCTAssertNil(admit(try XCTUnwrap(native("item/completed", at: 3))))
        XCTAssertNotNil(admit(.init(event: .userPromptSubmit, sessionHash: session, turnHash: turn,
                                    source: .localRollout, occurredAt: base)))
        XCTAssertNotNil(admit(try XCTUnwrap(native("item/completed", at: 3))))
        XCTAssertNil(admit(try XCTUnwrap(native("item/started", at: 1))))
        XCTAssertNil(admit(try XCTUnwrap(native("item/started", at: 4))))
        XCTAssertNotNil(admit(try XCTUnwrap(native("item/started", item: "compact-2", at: 5))))
        XCTAssertNil(admit(try XCTUnwrap(native("item/completed", item: "compact-1", at: 6))))
        XCTAssertNil(admit(try XCTUnwrap(native("item/started", item: "wrong-turn", turn: "other", at: 7))))
        XCTAssertNotNil(admit(try XCTUnwrap(native("item/completed", item: "compact-2", at: 8))))
    }

    func testSharedIngressForwardsCompactionOnlyForUserTasks() async throws {
        let sink = CompactionEventSink()
        let client = CodexSharedAppServerActivityClient(configuration: .init(isEnabled: false,
            socketURL: URL(fileURLWithPath: "/tmp/unused-compaction.sock"), executablePath: nil))
        await client.start(handler: { await sink.append($0) }, connectionStateHandler: { _ in })
        for (id, source) in [("user", "vscode" as Any), ("internal", ["subagent": ["other": "reviewer"]] as Any)] {
            try await client.handleJSONMessage(JSONSerialization.data(withJSONObject: [
                "method": "thread/started", "params": ["thread": ["id": id, "source": source]]
            ]))
            for method in ["item/started", "item/completed"] {
                try await client.handleJSONMessage(JSONSerialization.data(withJSONObject: [
                    "method": method, "params": ["threadId": id, "turnId": "turn",
                        "item": ["type": "contextCompaction", "id": "compact-1"]]
                ]))
            }
        }
        let events = await sink.events
        XCTAssertEqual(events.map(\.event), [.preCompact, .postCompact])
        XCTAssertTrue(events.allSatisfy { $0.sessionKind == .user && $0.compactionItemHash != nil })
        await client.stop()
    }

    @MainActor
    func testHookWithoutTurnPairsWithRolloutAndSurvivesUnrelatedDisconnect() async {
        let store = CodexActivityStore(titleClient: CodexAppServerClient(executablePath: nil))
        store.receive(.init(event: .postCompact, sessionHash: session, source: .hook, occurredAt: base))
        XCTAssertNil(store.snapshot)
        store.receive(.init(event: .userPromptSubmit, sessionHash: session, turnHash: turn,
                            source: .localRollout, occurredAt: base))
        store.receive(CodexActivityTokenUsageUpdate(sessionHash: session, turnHash: turn,
            cumulativeTotalTokens: 20_000, lastReportedTotalTokens: 100,
            directTurnTotalTokens: 10_000, occurredAt: base))
        let identity = store.snapshot?.taskIdentity
        store.receive(.init(event: .preCompact, sessionHash: session,
                            source: .hook, occurredAt: base.addingTimeInterval(1)))
        XCTAssertEqual(store.snapshot?.state, .compactingContext)
        XCTAssertEqual(store.snapshot?.taskIdentity, identity)
        XCTAssertEqual(store.currentTurnTokenUsage, 10_000)
        store.compactionSourceUnavailable(.appServer)
        XCTAssertEqual(store.snapshot?.state, .compactingContext)
        store.compactionSourceUnavailable(.hook)
        XCTAssertEqual(store.snapshot?.state, .unavailable)
        XCTAssertEqual(store.lifecycle, .unconfirmed)
        XCTAssertFalse(store.shouldPlayVisualEffects)
        XCTAssertEqual(store.currentTurnTokenUsage, 10_000)
        store.receive(.init(event: .postCompact, sessionHash: session, turnHash: turn,
                            source: .localRollout, occurredAt: base.addingTimeInterval(2)))
        XCTAssertEqual(store.snapshot?.state, .thinking)
        XCTAssertEqual(store.lifecycle, .active)
        XCTAssertEqual(store.snapshot?.taskIdentity, identity)
        XCTAssertEqual(store.currentTurnTokenUsage, 10_000)
        store.receive(.init(event: .preCompact, sessionHash: session,
                            source: .hook, occurredAt: base.addingTimeInterval(1)))
        XCTAssertEqual(store.snapshot?.state, .thinking)
        await store.stop()
    }

    @MainActor
    func testMissingEndRecoversOnActivityAndCancellationCannotBeRevived() async throws {
        let store = CodexActivityStore(titleClient: CodexAppServerClient(executablePath: nil))
        store.receive(.init(event: .userPromptSubmit, sessionHash: session, turnHash: turn,
                            source: .localRollout, occurredAt: base))
        store.receive(try XCTUnwrap(native("item/started", at: 1)))
        store.compactionSourceUnavailable(.appServer)
        XCTAssertEqual(store.snapshot?.state, .unavailable)
        store.receive(.init(event: .preToolUse, sessionHash: session, turnHash: turn,
                            source: .localRollout, occurredAt: base.addingTimeInterval(3)))
        XCTAssertEqual(store.snapshot?.state, .working)
        store.receive(try XCTUnwrap(native("item/started", at: 2)))
        XCTAssertEqual(store.snapshot?.state, .working)
        store.receive(try XCTUnwrap(native("item/started", item: "compact-2", at: 4)))
        XCTAssertEqual(store.snapshot?.state, .compactingContext)
        store.receive(.init(event: .interrupt, sessionHash: session, turnHash: turn,
                            source: .localRollout, occurredAt: base.addingTimeInterval(5)))
        XCTAssertEqual(store.snapshot?.state, .standby)
        XCTAssertEqual(store.lifecycle, .idle)
        store.receive(.init(event: .postCompact, sessionHash: session,
                            source: .hook, occurredAt: base.addingTimeInterval(6)))
        store.receive(.init(event: .preCompact, sessionHash: session,
                            source: .hook, occurredAt: base.addingTimeInterval(7)))
        XCTAssertEqual(store.snapshot?.state, .standby)
        XCTAssertEqual(store.lifecycle, .idle)
        await store.stop()
    }

    func testCompactionOnlyInstallationPreservesThirdPartyAndCanUpgradeOrRemove() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let helper = root.appendingPathComponent("QuotaViewActivityHook")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        let hooksURL = root.appendingPathComponent("hooks.json")
        let thirdParty: [String: Any] = ["matcher": "manual|auto", "hooks": [
            ["type": "command", "command": "/path/to/vibe-island-bridge", "timeout": 10]
        ]]
        let original: [String: Any] = ["description": "Keep me", "hooks": [
            "PreCompact": [thirdParty], "PostCompact": [thirdParty], "Stop": [thirdParty]
        ]]
        try JSONSerialization.data(withJSONObject: original).write(to: hooksURL)
        let installer = CodexActivityHookInstaller(socketURL: root.appendingPathComponent("bridge.sock"),
            authenticationToken: "private-token", hooksURL: hooksURL, helperURL: helper)
        XCTAssertTrue(try installer.install(scope: .compaction).hookDefinitionChanged)
        XCTAssertTrue(try installer.isInstalled())
        XCTAssertEqual(try installer.installedScope(), .compaction)
        XCTAssertFalse(try installer.install(scope: .compaction).hookDefinitionChanged)
        let installed = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: hooksURL)) as? [String: Any])
        XCTAssertEqual(installed["description"] as? String, "Keep me")
        let hooks = try XCTUnwrap(installed["hooks"] as? [String: [[String: Any]]])
        XCTAssertEqual(Set(hooks.keys), ["PreCompact", "PostCompact", "Stop"])
        for event in ["PreCompact", "PostCompact"] {
            XCTAssertEqual(hooks[event]?.count, 2)
            XCTAssertTrue(NSDictionary(dictionary: try XCTUnwrap(hooks[event]?.first)).isEqual(to: thirdParty))
        }
        XCTAssertEqual(hooks["Stop"]?.count, 1)
        XCTAssertTrue(try installer.install().hookDefinitionChanged)
        XCTAssertTrue(try installer.isInstalled())
        XCTAssertEqual(try installer.installedScope(), .all)
        XCTAssertFalse(try installer.install().hookDefinitionChanged)
        XCTAssertTrue(try installer.install(scope: .compaction).hookDefinitionChanged)
        // A damaged pair must not look connected simply because one Hook exists.
        var damaged = installed
        var damagedHooks = hooks
        damagedHooks["PostCompact"] = [thirdParty]
        damaged["hooks"] = damagedHooks
        try JSONSerialization.data(withJSONObject: damaged).write(to: hooksURL)
        XCTAssertFalse(try installer.isInstalled())
        XCTAssertNil(try installer.installedScope())
        _ = try installer.install(scope: .compaction)
        try installer.uninstall()
        XCTAssertNil(try installer.installedScope())
        let restored = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: hooksURL)) as? [String: Any])
        XCTAssertTrue(NSDictionary(dictionary: restored).isEqual(to: original))
        for event in [CodexActivityHookEvent.preCompact, .postCompact] {
            var evidence = CodexActivityConnectionEvidence()
            evidence.record(event: event, installationID: "fixture")
            XCTAssertEqual(evidence.status(for: "fixture"), .connected)
            XCTAssertEqual(evidence.status(for: "different"), .awaitingTrust)
        }
    }
}

private actor CompactionEventSink {
    var events: [CodexActivityEvent] = []
    func append(_ event: CodexActivityEvent) { events.append(event) }
}
