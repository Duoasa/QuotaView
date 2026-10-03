import Foundation
import XCTest
@testable import QuotaView
@testable import QuotaViewCore

/// Bounded fixtures only: no Codex connection, real answer or UI automation.
final class CodexBackgroundMemorySmokeTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    @MainActor private func store() -> CodexActivityStore {
        CodexActivityStore(titleClient: .init(executablePath: nil))
    }

    private func event(_ type: CodexActivityHookEvent, session: String = "memory", turn: String? = "turn",
                       kind: CodexActivitySessionKind = .memoryConsolidation,
                       source: CodexActivityEventSource = .localRollout,
                       completion: CodexActivityTurnCompletionStatus? = nil, offset: TimeInterval = 0) -> CodexActivityEvent {
        .init(event: type, sessionHash: session, turnHash: turn, sessionKind: kind, source: source,
              turnCompletionStatus: completion, occurredAt: base.addingTimeInterval(offset))
    }

    private func metadata(thread: String, current: [String: Any]? = nil) throws -> Data {
        var params: [String: Any] = ["thread": ["id": thread, "source": "unknown",
            "thread_source": "memory_consolidation", "status": ["type": "active", "activeFlags": []]]]
        if let current { params["currentTurn"] = current }
        return try JSONSerialization.data(withJSONObject: ["method": "thread/snapshot", "params": params])
    }

    @MainActor
    func testMemoryUsesIndependentStateWithoutSelectingOrWaitingOnUser() async throws {
        let store = store()
        store.setMultitaskEnabled(true)
        store.receive(event(.userPromptSubmit, session: "user", kind: .user))
        let userSnapshot = store.snapshot
        var admitted: [CodexActivityEvent] = []
        store.admittedActivityDidReceive = { admitted.append($0) }
        for source in [CodexActivityEventSource.hook, .appServer, .localRollout] {
            let session = "memory-\(source.rawValue)"
            store.receive(event(.userPromptSubmit, session: session, source: source, offset: 1))
            store.receive(event(.permissionRequest, session: session, source: source, offset: 2))
        }
        XCTAssertEqual(store.backgroundMemorySnapshots.count, 3)
        XCTAssertTrue(store.backgroundMemorySnapshots.allSatisfy { $0.state == .awaitingConfirmation })
        XCTAssertEqual(store.snapshot, userSnapshot)
        XCTAssertEqual(store.multitask.entries.map { $0.snapshot.sessionHash }, ["user"])
        XCTAssertEqual(store.lifecycle, .active)
        XCTAssertFalse(store.isConfirmationReminderActive)
        XCTAssertTrue(admitted.isEmpty)
        await store.stop()
    }

    @MainActor
    func testLateLocalIdentityMigratesGenericWaitWithoutAnotherStart() async throws {
        let store = store()
        let thread = "formerly-generic", session = CodexActivityPrivacy.hashIdentifier(thread)
        store.setMultitaskEnabled(true)
        store.receive(event(.userPromptSubmit, session: session, kind: .user))
        store.receive(event(.permissionRequest, session: session, kind: .user, offset: 1))
        let original = try XCTUnwrap(store.snapshot)
        var resolved: [(String, CodexActivitySessionKind)] = []
        store.activitySessionKindDidResolve = { resolved.append(($0, $1)) }
        await store.receiveLocalRecord(.init(eventID: nil, update: .sessionMetadata,
            threadIdentity: .init(threadID: thread, sessionHash: session, sessionKind: .memoryConsolidation)), replay: false)
        XCTAssertEqual(store.backgroundMemorySnapshots, [original])
        XCTAssertNil(store.snapshot)
        XCTAssertEqual(store.presentation, .hidden)
        XCTAssertTrue(store.multitask.entries.isEmpty)
        XCTAssertFalse(store.isConfirmationReminderActive)
        XCTAssertEqual(resolved.map { $0.0 }, [session])
        XCTAssertEqual(resolved.map { $0.1 }, [.memoryConsolidation])
        // Sparse host fallbacks cannot reintroduce the migrated record.
        store.receive(event(.postToolUse, session: session, kind: .user, offset: 2))
        XCTAssertNil(store.snapshot)
        XCTAssertEqual(store.backgroundMemorySnapshots.first?.state, .thinking)
        await store.stop()
    }

    @MainActor
    func testSharedMemorySnapshotHasLifecycleButNoPublicQuestionCapability() async throws {
        let store = store()
        let thread = "native-memory", session = CodexActivityPrivacy.hashIdentifier(thread)
        var publicCount = 0, contentCount = 0, tokenCount = 0
        store.publicMessageDidReceive = { _ in publicCount += 1 }
        store.localPublicContentDidReceive = { _ in contentCount += 1 }
        store.cumulativeTokensDidReceive = { _ in tokenCount += 1 }
        await store.receiveScopedPublicMessage(try metadata(thread: thread, current: ["id": "native-turn",
            "status": "inProgress", "startedAtMs": base.timeIntervalSince1970 * 1_000]), connectionEpoch: 3, at: base)
        XCTAssertNil(store.snapshot)
        XCTAssertEqual(store.backgroundMemorySnapshots.first?.sessionHash, session)
        XCTAssertEqual(store.backgroundMemorySnapshots.first?.state, .thinking)
        let approval = try JSONSerialization.data(withJSONObject: ["id": 8,
            "method": "item/tool/requestUserInput", "params": ["threadId": thread, "turnId": "native-turn",
                "questions": [["id": "question", "question": "Fixture", "options": []]]]])
        await store.receiveScopedPublicMessage(approval, connectionEpoch: 3, at: base.addingTimeInterval(1))
        store.receive(.init(sessionHash: session, turnHash: CodexActivityPrivacy.hashIdentifier("native-turn"),
            cumulativeTotalTokens: 100, lastReportedTotalTokens: 100, occurredAt: base))
        XCTAssertEqual(publicCount, 0)
        XCTAssertEqual(contentCount, 0)
        XCTAssertEqual(tokenCount, 0)
        XCTAssertNil(store.snapshot)
        await store.stop()
    }

    @MainActor
    func testMemoryCompletionFailureInterruptAndSessionEndUseRealEvents() async throws {
        let store = store()
        for (status, expected) in [(CodexActivityTurnCompletionStatus.completed, CodexActivityVisualState.completed),
                                   (.failed, .error), (.interrupted, .standby)] {
            let session = "memory-\(status.rawValue)"
            store.receive(event(.userPromptSubmit, session: session))
            store.receive(event(.stop, session: session, completion: status, offset: 1))
            XCTAssertEqual(store.backgroundMemorySnapshots.first { $0.sessionHash == session }?.state, expected)
            store.receive(event(.permissionRequest, session: session, offset: 2))
            XCTAssertEqual(store.backgroundMemorySnapshots.first { $0.sessionHash == session }?.state, expected)
            store.receive(event(.sessionEnd, session: session, turn: nil, offset: 3))
            XCTAssertNil(store.backgroundMemorySnapshots.first { $0.sessionHash == session })
        }
        XCTAssertNil(store.snapshot)
        await store.stop()
    }

    @MainActor
    func testSourceLossPreservesIdentityAndCannotFabricateCompletion() async throws {
        let store = store()
        store.receive(event(.userPromptSubmit, source: .appServer))
        let original = try XCTUnwrap(store.backgroundMemorySnapshots.first)
        store.compactionSourceUnavailable(.localRollout)
        XCTAssertEqual(store.backgroundMemorySnapshots, [original])
        store.compactionSourceUnavailable(.appServer)
        let uncertain = try XCTUnwrap(store.backgroundMemorySnapshots.first)
        XCTAssertEqual(uncertain.state, .unavailable)
        XCTAssertEqual(uncertain.operationKey, .bridgeUnavailable)
        XCTAssertEqual(uncertain.taskIdentity, original.taskIdentity)
        XCTAssertEqual(uncertain.occurredAt, original.occurredAt)
        store.receive(event(.postToolUse, source: .appServer, offset: 1))
        XCTAssertEqual(store.backgroundMemorySnapshots.first?.state, .thinking)
        store.receive(event(.stop, source: .appServer, completion: .completed, offset: 2))
        store.compactionSourceUnavailable(.appServer)
        XCTAssertEqual(store.backgroundMemorySnapshots.first?.state, .completed)
        await store.stop()
        XCTAssertTrue(store.backgroundMemorySnapshots.isEmpty)
    }

    @MainActor
    func testOldEpochAndMalformedEventsCannotMigrateCurrentUser() async throws {
        let store = store()
        let thread = "user", session = CodexActivityPrivacy.hashIdentifier(thread)
        store.receive(event(.userPromptSubmit, session: session, kind: .user))
        let user = try XCTUnwrap(store.snapshot)
        let current = try JSONSerialization.data(withJSONObject: ["method": "thread/snapshot", "params":
            ["thread": ["id": thread, "source": "vscode", "threadSource": "user"]]])
        await store.receiveScopedPublicMessage(current, connectionEpoch: 5, at: base)
        await store.receiveScopedPublicMessage(try metadata(thread: thread), connectionEpoch: 4, at: base)
        store.receive(.init(schemaVersion: 999, event: .userPromptSubmit, sessionHash: session,
            turnHash: "next", sessionKind: .memoryConsolidation, source: .appServer, occurredAt: base))
        XCTAssertEqual(store.snapshot, user)
        XCTAssertTrue(store.backgroundMemorySnapshots.isEmpty)
        await store.stop()
    }
    @MainActor
    func testReconnectedSameTurnSnapshotRestoresMemoryWithoutAnotherStart() async throws {
        let store = store(), thread = "reconnecting-memory"
        let active = try metadata(thread: thread, current: ["id": "turn", "status": "inProgress",
            "startedAtMs": base.timeIntervalSince1970 * 1_000])
        await store.receiveScopedPublicMessage(active, connectionEpoch: 2, at: base)
        let before = try XCTUnwrap(store.backgroundMemorySnapshots.first)
        store.compactionSourceUnavailable(.appServer)
        XCTAssertEqual(store.backgroundMemorySnapshots.first?.state, .unavailable)
        await store.receiveScopedPublicMessage(active, connectionEpoch: 3, at: base.addingTimeInterval(1))
        XCTAssertEqual(store.backgroundMemorySnapshots, [before])
        await store.stop()
    }

    @MainActor
    func testDesktopObservesMemoryThroughCompletionWithoutGrantingQuestionCapability() async throws {
        let store = store()
        var ownerCallbacks = 0
        store.desktopProjectionDidReceive = { _, _ in ownerCallbacks += 1 }
        func pair(status: String, revision: Int64, epoch: UInt64 = 9)
            throws -> (CodexDesktopInteractionProjection, CodexDesktopConversationSnapshot) {
            let state: [String: Any] = ["id": "desktop-memory", "source": ["internal": "memory_consolidation"],
                "requests": [], "turns": [["turnId": "turn", "status": status,
                    "turnStartedAtMs": base.timeIntervalSince1970 * 1_000, "items": []]]]
            let data = try JSONSerialization.data(withJSONObject: state)
            return (try CodexDesktopRequestProjector.project(conversationID: "desktop-memory", conversationStateData: data),
                .init(conversationID: "desktop-memory", hostID: "local", ownerClientID: "owner", connectionEpoch: epoch,
                      revision: revision, conversationState: data, supportsUntrustedAppInput: true, requests: []))
        }
        let first = try pair(status: "inProgress", revision: 1)
        let accepted = await store.receiveDesktopProjection(first.0, snapshot: first.1, at: base)
        XCTAssertTrue(accepted, "Accepted read-only observation keeps following for the real end event")
        XCTAssertNil(store.snapshot)
        XCTAssertEqual(ownerCallbacks, 0)
        let identity = store.backgroundMemorySnapshots.first?.taskIdentity
        store.setDesktopConnection(connected: false)
        XCTAssertEqual(store.backgroundMemorySnapshots.first?.state, .unavailable)
        let reopened = try pair(status: "inProgress", revision: 1, epoch: 10)
        let restored = await store.receiveDesktopProjection(reopened.0, snapshot: reopened.1, at: base.addingTimeInterval(1))
        XCTAssertTrue(restored)
        XCTAssertEqual(store.backgroundMemorySnapshots.first?.state, .thinking)
        XCTAssertEqual(store.backgroundMemorySnapshots.first?.taskIdentity, identity)
        let terminal = try pair(status: "completed", revision: 2, epoch: 10)
        let ended = await store.receiveDesktopProjection(terminal.0, snapshot: terminal.1, at: base.addingTimeInterval(2))
        XCTAssertTrue(ended)
        XCTAssertEqual(store.backgroundMemorySnapshots.first?.state, .completed)
        XCTAssertNil(store.snapshot)
        XCTAssertEqual(ownerCallbacks, 0)
        await store.stop()
    }

    @MainActor
    func testExplicitNonMemoryInternalMetadataWithdrawsBackgroundPresentation() async throws {
        let store = store()
        store.receive(event(.userPromptSubmit))
        XCTAssertEqual(store.backgroundMemorySnapshots.count, 1)
        store.receive(event(.preToolUse, kind: .internalTask, offset: 1))
        XCTAssertTrue(store.backgroundMemorySnapshots.isEmpty)
        XCTAssertNil(store.snapshot)
        await store.stop()
    }

    private func desktopMemoryPair(thread: String = "desktop-memory", status: String = "inProgress",
                                   revision: Int64 = 1) throws
        -> (CodexDesktopInteractionProjection, CodexDesktopConversationSnapshot) {
        let state: [String: Any] = ["id": thread, "source": ["internal": "memory_consolidation"],
            "requests": [], "turns": [["turnId": "turn", "status": status,
                "turnStartedAtMs": base.timeIntervalSince1970 * 1_000, "items": []]]]
        let data = try JSONSerialization.data(withJSONObject: state)
        return (try CodexDesktopRequestProjector.project(conversationID: thread, conversationStateData: data),
            .init(conversationID: thread, hostID: "local", ownerClientID: "owner", connectionEpoch: 9,
                  revision: revision, conversationState: data, supportsUntrustedAppInput: true, requests: []))
    }

    @MainActor
    func testHookDetailsDoNotEraseDesktopDisconnectEvidence() async throws {
        let store = store(), pair = try desktopMemoryPair()
        let accepted = await store.receiveDesktopProjection(pair.0, snapshot: pair.1, at: base)
        XCTAssertTrue(accepted)
        let identity = try XCTUnwrap(store.backgroundMemorySnapshots.first?.taskIdentity)
        store.receive(event(.preToolUse, session: identity.sessionHash, turn: identity.turnHash,
            source: .hook, offset: 1))
        XCTAssertEqual(store.backgroundMemorySnapshots.first?.state, .working)
        store.setDesktopConnection(connected: false)
        XCTAssertEqual(store.backgroundMemorySnapshots.first?.state, .unavailable)
        XCTAssertEqual(store.backgroundMemorySnapshots.first?.taskIdentity, identity)
        await store.stop()
    }

    @MainActor
    func testRejectedTerminalSnapshotCannotReserveRevisionOrCreateBackgroundTask() async throws {
        let store = store(), terminal = try desktopMemoryPair(status: "completed", revision: 100)
        let rejected = await store.receiveDesktopProjection(terminal.0, snapshot: terminal.1, at: base)
        XCTAssertFalse(rejected)
        XCTAssertTrue(store.backgroundMemorySnapshots.isEmpty)
        let active = try desktopMemoryPair(revision: 1)
        let accepted = await store.receiveDesktopProjection(active.0, snapshot: active.1, at: base.addingTimeInterval(1))
        XCTAssertTrue(accepted, "Failed terminal-only admission cannot poison a fresh lower receipt revision")
        XCTAssertEqual(store.backgroundMemorySnapshots.first?.state, .thinking)
        await store.stop()
    }

    @MainActor
    func testMetadataFloodEvictsOnlyUnobservedClassificationAndPreservesActiveMemory() async throws {
        let store = store(), forgottenThread = "metadata-only-memory"
        store.receive(event(.userPromptSubmit, session: "active-memory"))
        await store.receiveScopedPublicMessage(try metadata(thread: forgottenThread), connectionEpoch: 1, at: base)
        for index in 0..<1_030 {
            let data = try JSONSerialization.data(withJSONObject: ["method": "thread/started", "params":
                ["thread": ["id": "internal-\(index)", "source": ["internal": "guardian"], "threadSource": "guardian_review"]]])
            await store.receiveScopedPublicMessage(data, connectionEpoch: 1, at: base)
        }
        store.receive(event(.userPromptSubmit, session: CodexActivityPrivacy.hashIdentifier(forgottenThread), kind: .user, offset: 1))
        XCTAssertEqual(store.snapshot?.sessionHash, CodexActivityPrivacy.hashIdentifier(forgottenThread),
            "Old metadata-only classification must leave the bounded LRU")
        store.receive(event(.postToolUse, session: "active-memory", kind: .user, source: .hook, offset: 2))
        XCTAssertEqual(store.backgroundMemorySnapshots.first { $0.sessionHash == "active-memory" }?.state, .thinking,
            "Still admitted memory cannot become a user task when sparse host metadata arrives")
        XCTAssertEqual(store.snapshot?.sessionHash, CodexActivityPrivacy.hashIdentifier(forgottenThread))
        await store.stop()
    }

    @MainActor
    func testAuthoritativeEmptyWaitFlagsClearMigratedGenericWait() async throws {
        let store = store(), thread = "old-generic-wait", session = CodexActivityPrivacy.hashIdentifier(thread)
        let turn = CodexActivityPrivacy.hashIdentifier("turn")
        store.receive(event(.userPromptSubmit, session: session, turn: turn, kind: .user, source: .appServer))
        store.receive(event(.permissionRequest, session: session, turn: turn, kind: .user, source: .hook, offset: 1))
        await store.receiveScopedPublicMessage(try metadata(thread: thread, current: ["id": "turn", "status": "inProgress",
            "startedAtMs": base.timeIntervalSince1970 * 1_000]), connectionEpoch: 1, at: base.addingTimeInterval(2))
        XCTAssertEqual(store.backgroundMemorySnapshots.first?.state, .thinking)
        XCTAssertNil(store.snapshot)
        XCTAssertFalse(store.isConfirmationReminderActive)
        await store.stop()
    }

}
