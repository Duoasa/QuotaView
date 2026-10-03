import Foundation
import XCTest
@testable import QuotaView
@testable import QuotaViewCore

final class IslandMemoryActivitySmokeTests: XCTestCase {
    private func message(_ method: String, _ params: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["method": method, "params": params])
    }
    private func snapshot(_ state: CodexActivityVisualState, key: String = "memory", time: Double = 100,
                          operation: CodexActivityOperationKey = .usingTool) -> CodexActivitySnapshot {
        .init(sessionHash: key, state: state, workspaceName: "memories", operationKey: operation,
              toolCategory: nil, approximateProgressFraction: nil, occurredAt: Date(timeIntervalSince1970: time))
    }

    @MainActor func testLateMemoryIdentityRemovesRowAndCannotReenterViaLegacyOrPublicEvents() throws {
        let model = IslandLiveStore()
        try model.receive(message("turn/started", ["threadId": "background", "turn": ["id": "one"]]))
        XCTAssertEqual(model.tasks.count, 1)
        try model.receive(message("thread/snapshot", ["thread": ["id": "background", "source": "unknown",
            "thread_source": "memory_consolidation", "status": ["type": "active"]]]))
        XCTAssertTrue(model.tasks.isEmpty)
        XCTAssertEqual(model.selectedID, 0)
        try model.receive(message("turn/started", ["threadId": "background", "turn": ["id": "two"]]))
        model.receiveLegacy(.init(event: .preToolUse, sessionHash: CodexActivityPrivacy.hashIdentifier("background"),
            sessionKind: .unknown))
        XCTAssertTrue(model.tasks.isEmpty)
        XCTAssertTrue(model.display(english: false, remaining: nil, enabled: true, privacy: false).activeRequestIDs.isEmpty)
        model.reset()
        try model.receive(message("turn/started", ["threadId": "background", "turn": ["id": "new-root"]]))
        XCTAssertEqual(model.tasks.count, 1, "Changing the data-root generation must clear old classification")
    }

    @MainActor func testMemoryTitleDoesNotClassifyAUserConversation() throws {
        let model = IslandLiveStore()
        try model.receive(message("thread/started", ["thread": ["id": "user", "name": "memories",
            "source": "cli", "threadSource": "user", "status": ["type": "active"]]]))
        XCTAssertEqual(model.tasks.count, 1)
        XCTAssertEqual(model.tasks.first?.title, "memories")
    }

    @MainActor func testExecutionMemoryClassificationWithdrawsRequestsAndCanBeRevokedForNextUserTurn() throws {
        let model = IslandLiveStore()
        let thread = "temporary-thread"
        let session = CodexActivityPrivacy.hashIdentifier(thread)
        let turn = CodexActivityPrivacy.hashIdentifier("memory-turn")
        model.receiveLegacy(.init(event: .userPromptSubmit, sessionHash: session, turnHash: turn, sessionKind: .unknown))
        let request: [String: Any] = ["id": "old", "method": "item/tool/requestUserInput", "params": [
            "threadId": thread, "turnId": "memory-turn", "questions": [["id": "q", "question": "Choose?",
                "isOther": true, "options": [["label": "A"], ["label": "B"]]]]]]
        model.receive(try JSONSerialization.data(withJSONObject: request))
        let previousRequest = try XCTUnwrap(model.tasks.first?.requests.first?.value.id)
        model.preservedID = model.selectedID
        model.receiveExecutionSessionKind(.memoryConsolidation, session: session)
        XCTAssertTrue(model.tasks.isEmpty)
        XCTAssertEqual(model.selectedID, 0)
        XCTAssertNil(model.preservedID)
        XCTAssertTrue(model.display(english: false, remaining: nil, enabled: true, privacy: false).activeRequestIDs.isEmpty)
        model.receiveLegacy(.init(event: .preToolUse, sessionHash: session, turnHash: turn, sessionKind: .user))
        try model.receive(message("thread/snapshot", ["thread": ["id": thread, "source": "cli", "status": ["type": "active"]]]))
        XCTAssertTrue(model.tasks.isEmpty, "Sparse user source updates cannot cancel the current execution overlay")
        model.receiveExecutionSessionKind(.user, session: session)
        XCTAssertTrue(model.tasks.isEmpty, "Revocation alone cannot invent another lifecycle or restore an old request")
        let next = CodexActivityPrivacy.hashIdentifier("user-turn")
        model.receiveLegacy(.init(event: .userPromptSubmit, sessionHash: session, turnHash: next, sessionKind: .user))
        XCTAssertEqual(model.tasks.count, 1)
        XCTAssertEqual(model.tasks.first?.turnKey, next)
        XCTAssertTrue(model.tasks.first?.requests.isEmpty == true)
        var nextRequest = request
        nextRequest["id"] = "new"
        var params = try XCTUnwrap(nextRequest["params"] as? [String: Any])
        params["turnId"] = "user-turn"
        nextRequest["params"] = params
        model.receive(try JSONSerialization.data(withJSONObject: nextRequest))
        XCTAssertNotEqual(model.tasks.first?.requests.first?.value.id, previousRequest)
    }

    @MainActor func testExecutionRevocationCannotOverridePersistentMemoryOrInternalIdentity() throws {
        for persistent in [CodexActivitySessionKind.memoryConsolidation, .internalTask] {
            for beforeOverlay in [true, false] {
                let model = IslandLiveStore()
                let session = "persistent"
                if beforeOverlay { model.setSessionKind(persistent, for: session) }
                model.receiveExecutionSessionKind(.memoryConsolidation, session: session)
                if !beforeOverlay { model.setSessionKind(persistent, for: session) }
                model.receiveExecutionSessionKind(.user, session: session)
                model.receiveLegacy(.init(event: .userPromptSubmit, sessionHash: session,
                    turnHash: "later-user-turn", sessionKind: .user))
                XCTAssertTrue(model.tasks.isEmpty, "Execution revocation never overrides persistent source metadata")
            }
        }
    }

    @MainActor func testExecutionClassificationIsIsolatedAndClearedByDataRootReset() {
        let model = IslandLiveStore()
        model.receiveExecutionSessionKind(.memoryConsolidation, session: "memory")
        model.receiveLegacy(.init(event: .userPromptSubmit, sessionHash: "user", turnHash: "turn", sessionKind: .user))
        model.receiveLegacy(.init(event: .userPromptSubmit, sessionHash: "memory", turnHash: "turn", sessionKind: .unknown))
        XCTAssertEqual(model.tasks.map(\.key), ["user"])
        model.reset()
        model.receiveLegacy(.init(event: .userPromptSubmit, sessionHash: "memory", turnHash: "new-root", sessionKind: .user))
        XCTAssertEqual(model.tasks.map(\.key), ["memory"])
    }

    @MainActor func testStoreExecutionScopeCallbacksMoveLateUnknownTaskAndRestoreOnlyNewUserTurn() async throws {
        let model = IslandLiveStore()
        let store = CodexActivityStore(titleClient: .init(executablePath: nil))
        store.admittedActivityDidReceive = { model.receiveLegacy($0) }
        store.activitySessionKindDidResolve = { model.setSessionKind($1, for: $0) }
        var scopes: [CodexActivitySessionKind] = []
        store.activityExecutionKindDidResolve = {
            scopes.append($1)
            model.receiveExecutionSessionKind($1, session: $0)
        }
        let thread = "late-native-start"
        let session = CodexActivityPrivacy.hashIdentifier(thread)
        let turn = CodexActivityPrivacy.hashIdentifier("memory-turn")
        let now = Date()
        store.receive(.init(event: .userPromptSubmit, sessionHash: session, turnHash: turn,
            sessionKind: .unknown, source: .hook, occurredAt: now))
        XCTAssertEqual(model.tasks.count, 1)
        await store.receiveLocalRecord(.init(eventID: nil, update: .sessionMetadata,
            threadIdentity: .init(threadID: thread, sessionHash: session, sessionKind: .memoryConsolidation,
                executionTurnHash: turn)), replay: false)
        XCTAssertTrue(model.tasks.isEmpty)
        XCTAssertEqual(store.backgroundMemorySnapshots.count, 1)
        XCTAssertEqual(scopes, [.memoryConsolidation])
        let next = CodexActivityPrivacy.hashIdentifier("user-turn")
        store.receive(.init(event: .userPromptSubmit, sessionHash: session, turnHash: next,
            sessionKind: .unknown, source: .hook, occurredAt: now.addingTimeInterval(1)))
        XCTAssertEqual(scopes, [.memoryConsolidation, .user])
        XCTAssertTrue(store.backgroundMemorySnapshots.isEmpty)
        XCTAssertEqual(model.tasks.count, 1)
        XCTAssertEqual(model.tasks.first?.turnKey, next)
        await store.stop()
    }

    @MainActor func testEarlyMemoryMetadataIsConsumedOnlyByItsAdmittedTurn() async {
        let model = IslandLiveStore()
        let store = CodexActivityStore(titleClient: .init(executablePath: nil))
        store.admittedActivityDidReceive = { model.receiveLegacy($0) }
        store.activitySessionKindDidResolve = { model.setSessionKind($1, for: $0) }
        var scopes: [CodexActivitySessionKind] = []
        store.activityExecutionKindDidResolve = { scopes.append($1); model.receiveExecutionSessionKind($1, session: $0) }
        let thread = "early-memory"
        let session = CodexActivityPrivacy.hashIdentifier(thread)
        let turn = CodexActivityPrivacy.hashIdentifier("native-start")
        let current = CodexActivityPrivacy.hashIdentifier("current-user")
        let now = Date()
        store.receive(.init(event: .userPromptSubmit, sessionHash: session, turnHash: current,
            sessionKind: .user, source: .hook, occurredAt: now))
        await store.receiveLocalRecord(.init(eventID: nil, update: .sessionMetadata,
            threadIdentity: .init(threadID: thread, sessionHash: session, sessionKind: .memoryConsolidation,
                executionTurnHash: turn)), replay: false)
        XCTAssertEqual(model.tasks.first?.turnKey, current, "Early metadata cannot replace current lifecycle")
        XCTAssertTrue(scopes.isEmpty)
        store.receive(.init(event: .userPromptSubmit, sessionHash: session, turnHash: turn,
            sessionKind: .user, source: .hook, occurredAt: now.addingTimeInterval(-1)))
        XCTAssertTrue(scopes.isEmpty, "A rejected older clock cannot consume proof or withdraw the current card")
        XCTAssertEqual(model.tasks.first?.turnKey, current)
        store.receive(.init(event: .userPromptSubmit, sessionHash: session, turnHash: turn,
            sessionKind: .user, source: .hook, occurredAt: now.addingTimeInterval(1)))
        XCTAssertEqual(scopes, [.memoryConsolidation])
        XCTAssertTrue(model.tasks.isEmpty)
        XCTAssertEqual(store.backgroundMemorySnapshots.first?.taskIdentity?.turnHash, turn)
        await store.stop()
    }

    @MainActor func testMetadataBeforeFirstHookAvoidsAnyUserCardAndSparseContinuationKeepsMemory() async {
        let model = IslandLiveStore()
        let store = CodexActivityStore(titleClient: .init(executablePath: nil))
        var userDeliveries = 0
        store.admittedActivityDidReceive = { userDeliveries += 1; model.receiveLegacy($0) }
        store.activitySessionKindDidResolve = { model.setSessionKind($1, for: $0) }
        store.activityExecutionKindDidResolve = { model.receiveExecutionSessionKind($1, session: $0) }
        let thread = "before-first-hook"
        let session = CodexActivityPrivacy.hashIdentifier(thread)
        let turn = CodexActivityPrivacy.hashIdentifier("memory-turn")
        let now = Date()
        await store.receiveLocalRecord(.init(eventID: nil, update: .sessionMetadata,
            threadIdentity: .init(threadID: thread, sessionHash: session, sessionKind: .memoryConsolidation,
                executionTurnHash: turn)), replay: false)
        XCTAssertTrue(store.backgroundMemorySnapshots.isEmpty, "An identity has no lifecycle to display yet")
        store.receive(.init(event: .userPromptSubmit, sessionHash: session, turnHash: turn,
            sessionKind: .user, source: .hook, occurredAt: now))
        store.receive(.init(event: .preToolUse, sessionHash: session, sessionKind: .user,
            source: .hook, occurredAt: now.addingTimeInterval(1)))
        XCTAssertEqual(userDeliveries, 0, "Missing turn IDs must not forward a known background turn as a user event")
        XCTAssertTrue(model.tasks.isEmpty)
        XCTAssertEqual(store.backgroundMemorySnapshots.first?.taskIdentity?.turnHash, turn)
        XCTAssertTrue(store.multitask.entries.isEmpty)
        await store.stop()
    }

    @MainActor func testPendingMemoryIdentityIsBoundedAndStopRevokesUnconsumedEvidence() async {
        let model = IslandLiveStore()
        let store = CodexActivityStore(titleClient: .init(executablePath: nil))
        store.admittedActivityDidReceive = { model.receiveLegacy($0) }
        store.activityExecutionKindDidResolve = { model.receiveExecutionSessionKind($1, session: $0) }
        let turn = CodexActivityPrivacy.hashIdentifier("turn")
        for index in 0..<129 {
            let thread = "pending-\(index)"
            await store.receiveLocalRecord(.init(eventID: nil, update: .sessionMetadata,
                threadIdentity: .init(threadID: thread, sessionHash: CodexActivityPrivacy.hashIdentifier(thread),
                    sessionKind: .memoryConsolidation, executionTurnHash: turn)), replay: false)
        }
        let oldest = CodexActivityPrivacy.hashIdentifier("pending-0")
        store.receive(.init(event: .userPromptSubmit, sessionHash: oldest, turnHash: turn, sessionKind: .user))
        XCTAssertEqual(model.tasks.map(\.key), [oldest], "The bounded oldest pending identity expires without suppressing a user task")
        let latest = CodexActivityPrivacy.hashIdentifier("pending-128")
        store.receive(.init(event: .userPromptSubmit, sessionHash: latest, turnHash: turn, sessionKind: .user))
        XCTAssertEqual(store.backgroundMemorySnapshots.first?.sessionHash, latest)
        await store.stop()
        model.reset()
        let unconsumed = CodexActivityPrivacy.hashIdentifier("pending-127")
        store.receive(.init(event: .userPromptSubmit, sessionHash: unconsumed, turnHash: turn, sessionKind: .user))
        XCTAssertEqual(model.tasks.map(\.key), [unconsumed], "Stopped/different data-root scopes cannot reuse pending evidence")
        XCTAssertTrue(store.backgroundMemorySnapshots.isEmpty)
        await store.stop()
    }

    @MainActor func testOldGenerationAndRetiredTurnMetadataCannotSuppressCurrentUserTurn() async {
        let model = IslandLiveStore()
        let store = CodexActivityStore(titleClient: .init(executablePath: nil))
        store.admittedActivityDidReceive = { model.receiveLegacy($0) }
        store.activityExecutionKindDidResolve = { model.receiveExecutionSessionKind($1, session: $0) }
        let thread = "retired-memory"
        let session = CodexActivityPrivacy.hashIdentifier(thread)
        let old = CodexActivityPrivacy.hashIdentifier("old-turn")
        let current = CodexActivityPrivacy.hashIdentifier("current-turn")
        let now = Date()
        store.receive(.init(event: .userPromptSubmit, sessionHash: session, turnHash: old,
            sessionKind: .user, source: .hook, occurredAt: now))
        store.receive(.init(event: .userPromptSubmit, sessionHash: session, turnHash: current,
            sessionKind: .user, source: .hook, occurredAt: now.addingTimeInterval(1)))
        await store.receiveLocalRecord(.init(eventID: nil, update: .sessionMetadata,
            threadIdentity: .init(threadID: thread, sessionHash: session, sessionKind: .memoryConsolidation,
                executionTurnHash: old)), replay: false)
        XCTAssertEqual(model.tasks.first?.turnKey, current)
        let generation = await store.stop()
        model.reset()
        await store.receiveLocalRecord(.init(eventID: nil, update: .sessionMetadata,
            threadIdentity: .init(threadID: thread, sessionHash: session, sessionKind: .memoryConsolidation,
                executionTurnHash: current)), replay: false, generation: generation - 1)
        store.receive(.init(event: .userPromptSubmit, sessionHash: session, turnHash: current,
            sessionKind: .user, source: .hook, occurredAt: now.addingTimeInterval(2)))
        XCTAssertEqual(model.tasks.first?.turnKey, current)
        XCTAssertTrue(store.backgroundMemorySnapshots.isEmpty)
        await store.stop()
    }

    @MainActor func testVerifiedChildLifecycleAndProgressRemainOutsideUserAndResponseChannels() async throws {
        let store = CodexActivityStore(titleClient: .init(executablePath: nil))
        store.setMultitaskEnabled(true)
        let child = try XCTUnwrap(CodexActivitySubagentIdentity(threadID: "child", parentThreadID: "parent", nickname: "Worker"))
        let turn = CodexActivityPrivacy.hashIdentifier("one")
        var userEvents = 0, userPublic = 0, childEvents = 0, childPublic = 0, nativePublic = 0
        store.admittedActivityDidReceive = { _ in userEvents += 1 }
        store.localPublicContentDidReceive = { _ in userPublic += 1 }
        store.publicMessageDidReceive = { _ in userPublic += 1 }
        store.subagentActivityDidReceive = { _ in childEvents += 1 }
        store.subagentPublicContentDidReceive = { _ in childPublic += 1 }
        store.subagentPublicMessageDidReceive = { _ in nativePublic += 1 }
        await store.receiveLocalRecord(.init(eventID: nil, update: .sessionMetadata,
            threadIdentity: .init(threadID: child.threadID, sessionHash: child.sessionHash,
                sessionKind: .subagent, subagentIdentity: child)), replay: false)
        XCTAssertEqual(childEvents, 0, "Parent metadata cannot invent running work")
        store.receive(.init(event: .userPromptSubmit, sessionHash: child.sessionHash, turnHash: turn,
            sessionKind: .subagent, source: .localRollout))
        XCTAssertEqual(childEvents, 1)
        XCTAssertTrue(store.multitask.entries.isEmpty)
        XCTAssertNil(store.snapshot)
        for (type, key) in [("message", turn), ("message", "old"), ("questionRequest", turn)] {
            store.receiveLocalPublicContent(.init(sessionHash: child.sessionHash, turnHash: key,
                data: Data("{\"type\":\"\(type)\",\"text\":\"progress\"}".utf8), occurredAt: Date()))
        }
        XCTAssertEqual(childPublic, 1)
        try await store.receiveScopedPublicMessage(message("item/agentMessage/delta", [
            "threadId": child.threadID, "turnId": "one", "itemId": "progress", "delta": "Working"]), connectionEpoch: 1)
        XCTAssertEqual(nativePublic, 1)
        let rpc = try JSONSerialization.data(withJSONObject: ["id": "rpc", "method": "item/tool/requestUserInput",
            "params": ["threadId": child.threadID, "turnId": "one", "questions": []]])
        await store.receiveScopedPublicMessage(rpc, connectionEpoch: 1)
        try await store.receiveScopedPublicMessage(message("item/reasoning/summaryTextDelta", [
            "threadId": child.threadID, "turnId": "one", "delta": "private"]), connectionEpoch: 1)
        try await store.receiveScopedPublicMessage(message("item/agentMessage/delta", [
            "threadId": child.threadID, "turnId": "old", "delta": "wrong turn"]), connectionEpoch: 1)
        XCTAssertEqual(nativePublic, 1, "Child observation cannot forward RPC, reasoning, or another turn")
        XCTAssertEqual(userEvents, 0)
        XCTAssertEqual(userPublic, 0)
        await store.stop()
    }

    @MainActor func testExactChildRelationRefinesGenericInternalWithoutFabricatingLifecycle() async throws {
        let model = IslandLiveStore()
        let store = CodexActivityStore(titleClient: .init(executablePath: nil))
        store.admittedActivityDidReceive = { model.receiveLegacy($0) }
        store.activitySessionKindDidResolve = { model.setSessionKind($1, for: $0) }
        var events: [CodexActivityEvent] = [], unavailable: [CodexActivityEventSource?] = []
        store.subagentActivityDidReceive = { events.append($0) }
        store.subagentSourceUnavailable = { unavailable.append($0) }
        let child = try XCTUnwrap(CodexActivitySubagentIdentity(threadID: "late-child", parentThreadID: "parent"))
        let turn = CodexActivityPrivacy.hashIdentifier("actual")
        let event = CodexActivityEvent(event: .userPromptSubmit, sessionHash: child.sessionHash, turnHash: turn,
            workspaceName: "Existing", sessionKind: .unknown, source: .localRollout)
        store.receive(event)
        let continuation = CodexActivityEvent(event: .postToolUse, sessionHash: child.sessionHash, turnHash: turn,
            sessionKind: .unknown, source: .localRollout, occurredAt: event.occurredAt.addingTimeInterval(1))
        store.receive(continuation)
        await store.receiveLocalRecord(.init(eventID: nil, update: .sessionMetadata,
            threadIdentity: .init(threadID: child.threadID, sessionHash: child.sessionHash, sessionKind: .internalTask)), replay: false)
        XCTAssertTrue(model.tasks.isEmpty)
        let relation = CodexLocalRolloutDecodedRecord(eventID: nil, update: .sessionMetadata,
            threadIdentity: .init(threadID: child.threadID, sessionHash: child.sessionHash,
                sessionKind: .subagent, subagentIdentity: child))
        await store.receiveLocalRecord(relation, replay: false)
        XCTAssertEqual(events, [event.classified(as: .subagent), continuation.classified(as: .subagent)],
            "Late relation binds its original admitted start before replaying the actual continuation")
        store.compactionSourceUnavailable(.localRollout)
        XCTAssertEqual(unavailable, [.localRollout])
        await store.receiveLocalRecord(relation, replay: false)
        XCTAssertEqual(events.count, 2, "Repeating relation metadata cannot revive activity after its source disappears")
        await store.stop()
        XCTAssertEqual(unavailable, [.localRollout, nil], "Scope stop revokes animation without pretending completion")
    }

    @MainActor func testConfirmedCurrentChildTurnKeepsRealEarlierStartAcrossStoreAndUI() async throws {
        let model = IslandLiveStore()
        let store = CodexActivityStore(titleClient: .init(executablePath: nil))
        store.activitySessionKindDidResolve = { model.setSessionKind($1, for: $0) }
        store.subagentIdentityDidReceive = { model.receiveSubagentIdentity($0) }
        store.subagentActivityDidReceive = { model.receiveSubagentActivity($0) }
        store.subagentPublicContentDidReceive = { model.receiveLocalContent($0) }
        let child = try XCTUnwrap(CodexActivitySubagentIdentity(threadID: "current-child", parentThreadID: "parent"))
        let old = CodexActivityPrivacy.hashIdentifier("old")
        let current = CodexActivityPrivacy.hashIdentifier("current")
        await store.receiveLocalRecord(.init(eventID: nil, update: .sessionMetadata,
            threadIdentity: .init(threadID: child.threadID, sessionHash: child.sessionHash,
                sessionKind: .subagent, subagentIdentity: child)), replay: false)
        store.receive(.init(event: .userPromptSubmit, sessionHash: child.sessionHash, turnHash: old,
            sessionKind: .subagent, source: .hook, occurredAt: Date(timeIntervalSince1970: 10)))
        let actualStart = Date(timeIntervalSince1970: 5)
        store.receive(.init(source: .liveSocket, activity: .init(event: .userPromptSubmit,
            sessionHash: child.sessionHash, turnHash: current, sessionKind: .subagent,
            source: .appServer, occurredAt: actualStart)), confirmedCurrentTurn: true)
        XCTAssertEqual(model.subagents[child.sessionHash]?.turn, current)
        XCTAssertEqual(model.subagents[child.sessionHash]?.startedAt, actualStart,
            "Confirmed current-turn admission must preserve the real start, even before the old transport receipt")
        store.receiveLocalPublicContent(.init(sessionHash: child.sessionHash, turnHash: current,
            data: Data("{\"type\":\"message\",\"text\":\"Current public progress\"}".utf8),
            occurredAt: actualStart.addingTimeInterval(1)))
        XCTAssertEqual(model.subagents[child.sessionHash]?.progress, "Current public progress")
        store.receive(.init(event: .preToolUse, sessionHash: child.sessionHash, turnHash: old,
            sessionKind: .subagent, source: .hook, occurredAt: Date(timeIntervalSince1970: 11)))
        XCTAssertEqual(model.subagents[child.sessionHash]?.turn, current, "Retired turn receipts still cannot return")
        await store.stop()
    }

    @MainActor func testChildParentRelationCannotChangeAcrossMetadataBatches() async throws {
        let model = IslandLiveStore()
        let store = CodexActivityStore(titleClient: .init(executablePath: nil))
        var deliveredParents: [String] = []
        store.subagentIdentityDidReceive = { deliveredParents.append($0.parentSessionHash); model.receiveSubagentIdentity($0) }
        store.subagentActivityDidReceive = { model.receiveSubagentActivity($0) }
        let original = try XCTUnwrap(CodexActivitySubagentIdentity(threadID: "fixed-child", parentThreadID: "original-parent"))
        let conflicting = try XCTUnwrap(CodexActivitySubagentIdentity(threadID: original.threadID, parentThreadID: "other-parent"))
        func record(_ child: CodexActivitySubagentIdentity) -> CodexLocalRolloutDecodedRecord {
            .init(eventID: nil, update: .sessionMetadata, threadIdentity: .init(threadID: child.threadID,
                sessionHash: child.sessionHash, sessionKind: .subagent, subagentIdentity: child))
        }
        await store.receiveLocalRecord(record(original), replay: false)
        let turn = CodexActivityPrivacy.hashIdentifier("relation-turn")
        let now = Date()
        store.receive(.init(event: .userPromptSubmit, sessionHash: original.sessionHash, turnHash: turn,
            sessionKind: .subagent, source: .localRollout, occurredAt: now))
        let beforeConflict = deliveredParents.count
        await store.receiveLocalRecord(record(conflicting), replay: false)
        XCTAssertEqual(deliveredParents.count, beforeConflict, "Conflicting relation must be rejected before Store or UI mutation")
        store.receive(.init(event: .postToolUse, sessionHash: original.sessionHash, turnHash: turn,
            sessionKind: .subagent, source: .localRollout, occurredAt: now.addingTimeInterval(1)))
        XCTAssertTrue(deliveredParents.allSatisfy { $0 == original.parentSessionHash },
            "Later lifecycle callbacks must retain the original admitted parent relation")
        XCTAssertEqual(model.subagents[original.sessionHash]?.identity.parentSessionHash, original.parentSessionHash)
        await store.stop()
    }

    @MainActor func testLateChildOriginKeepsCurrentMemoryExecutionAndRestoresOnlyNextChildTurn() async throws {
        let store = CodexActivityStore(titleClient: .init(executablePath: nil))
        let child = try XCTUnwrap(CodexActivitySubagentIdentity(threadID: "memory-child", parentThreadID: "parent"))
        let memoryTurn = CodexActivityPrivacy.hashIdentifier("memory")
        let nextTurn = CodexActivityPrivacy.hashIdentifier("next-child")
        let now = Date()
        var childEvents: [CodexActivityEvent] = [], scopes: [CodexActivitySessionKind] = []
        store.subagentActivityDidReceive = { childEvents.append($0) }
        store.activityExecutionKindDidResolve = { _, kind in scopes.append(kind) }
        store.receive(.init(source: .liveSocket, activity: .init(event: .userPromptSubmit,
            sessionHash: child.sessionHash, turnHash: memoryTurn, sessionKind: .unknown, source: .hook, occurredAt: now)),
            executionMemoryTurnHash: memoryTurn)
        let before = try XCTUnwrap(store.backgroundMemorySnapshots.first)
        await store.receiveLocalRecord(.init(eventID: nil, update: .sessionMetadata,
            threadIdentity: .init(threadID: child.threadID, sessionHash: child.sessionHash,
                sessionKind: .subagent, subagentIdentity: child)), replay: false)
        XCTAssertEqual(store.backgroundMemorySnapshots, [before], "A parent relation changes origin, never the admitted memory execution")
        XCTAssertTrue(childEvents.isEmpty)
        store.receive(.init(event: .preToolUse, sessionHash: child.sessionHash, sessionKind: .unknown,
            source: .hook, occurredAt: now.addingTimeInterval(1)))
        XCTAssertEqual(store.backgroundMemorySnapshots.first?.taskIdentity?.turnHash, memoryTurn)
        XCTAssertTrue(childEvents.isEmpty, "Sparse continuation still belongs to the memory turn")
        store.receive(.init(event: .userPromptSubmit, sessionHash: child.sessionHash, turnHash: nextTurn,
            sessionKind: .unknown, source: .hook, occurredAt: now.addingTimeInterval(2)))
        XCTAssertEqual(childEvents.first?.turnHash, nextTurn)
        XCTAssertTrue(store.backgroundMemorySnapshots.isEmpty)
        XCTAssertNil(store.snapshot)
        XCTAssertEqual(scopes, [.memoryConsolidation, .user])
        await store.stop()
    }

    @MainActor func testBackgroundOnlyDisplayKeepsUserCountsAndPopupEmpty() {
        let model = IslandLiveStore()
        var display = model.display(english: false, remaining: nil, enabled: true, privacy: false)
        let board = IslandBoardState()
        board.update(display, reduceMotion: true)
        display.backgroundMemorySnapshots = [snapshot(.thinking)]
        board.update(display, reduceMotion: true)
        XCTAssertTrue(board.tasks.isEmpty)
        XCTAssertEqual(board.runningCount, 0)
        XCTAssertEqual(board.attentionCount, 0)
        XCTAssertTrue(board.compact, "Background work must not automatically open the island")
        XCTAssertEqual(board.memoryActivity?.visualState, .thinking)
        XCTAssertTrue(board.memoryActivity?.playbackEnabled == true)
        display.backgroundMemorySnapshots = [snapshot(.completed, time: 101, operation: .turnCompleted)]
        board.update(display, reduceMotion: true)
        XCTAssertTrue(board.compact, "Memory completion must not show the user completion popup")
        XCTAssertEqual(board.memoryActivity?.label(english: false), "记忆整理 · 整理完成")
        XCTAssertTrue(board.memoryActivity?.playbackEnabled == false)
    }

    func testRunningMemoryWinsOverNewerCompletedJobAndStaleStateDoesNotAnimate() throws {
        let activity = try XCTUnwrap(IslandMemoryActivity(snapshots: [snapshot(.thinking, key: "active", time: 99),
            snapshot(.completed, key: "finished", time: 101)]))
        XCTAssertEqual(activity.snapshot.sessionHash, "active")
        XCTAssertEqual(activity.count, 2)
        let stale = try XCTUnwrap(IslandMemoryActivity(snapshots: [snapshot(.unavailable)]))
        XCTAssertFalse(stale.playbackEnabled)
        XCTAssertEqual(stale.label(english: false), "记忆整理 · 状态待更新")
        XCTAssertEqual(stale.label(english: true), "Memory consolidation · Status unavailable")
    }

    func testFailureAndInterruptionRetainTheirRealMeaning() throws {
        let failed = try XCTUnwrap(IslandMemoryActivity(snapshots: [snapshot(.error, operation: .turnFailed)]))
        XCTAssertEqual(failed.label(english: false), "记忆整理 · 整理失败")
        XCTAssertFalse(failed.playbackEnabled)
        let interrupted = try XCTUnwrap(IslandMemoryActivity(snapshots: [snapshot(.standby, operation: .turnInterrupted)]))
        XCTAssertEqual(interrupted.label(english: true), "Memory consolidation · Interrupted")
        XCTAssertFalse(interrupted.playbackEnabled)
        XCTAssertNil(IslandMemoryActivity(snapshots: []))
    }
}
