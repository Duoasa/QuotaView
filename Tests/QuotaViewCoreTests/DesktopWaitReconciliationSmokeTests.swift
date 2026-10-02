import Foundation
import XCTest
@testable import QuotaView
@testable import QuotaViewCore

@MainActor
final class DesktopWaitReconciliationSmokeTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_790_888_000)
    private func hash(_ text: String) -> String { CodexActivityPrivacy.hashIdentifier(text) }
    private func setup() -> (CodexActivityStore, IslandLiveStore) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = CodexActivityStore(titleClient: .init(executablePath: nil),
            sharedActivityClient: .init(configuration: .init(isEnabled: false,
                socketURL: root.appendingPathComponent("unused.sock"), executablePath: nil)),
            localRolloutActivityClient: .init(configuration: .init(isEnabled: false, codexHomeURL: root)),
            sessionDirectory: root, sessionKindResolver: { $0.sessionKind ?? .user })
        let island = IslandLiveStore()
        island.setDesktopConnection(connected: true, epoch: 9)
        store.admittedActivityDidReceive = { island.receiveLegacy($0) }
        store.publicMessageDidReceive = { island.receive($0) }
        var ownerTime = base
        store.desktopProjectionDidReceive = { projection, snapshot in
            ownerTime = self.base.addingTimeInterval(Double(snapshot.revision))
            island.receiveDesktopProjection(projection, snapshot: snapshot)
        }
        island.desktopRequestSettlementDidReceive = { session, turn, epoch, remaining in
            store.receiveDesktopRequestSettlement(sessionHash: session, turnHash: turn,
                epoch: epoch, stillWaiting: remaining, at: ownerTime)
        }
        return (store, island)
    }
    private func pair(revision: Int64, flags: [String]? = [], requests: [[String: Any]] = [],
                      items: [[String: Any]] = [], authoritative: Bool = true,
                      epoch: UInt64 = 9, turn: String = "turn", owner: String = "owner") throws
        -> (CodexDesktopInteractionProjection, CodexDesktopConversationSnapshot) {
        var state: [String: Any] = ["id": "task", "source": "appServer", "requests": requests,
            "turns": [["turnId": turn, "status": "inProgress", "turnStartedAtMs": base.timeIntervalSince1970 * 1_000,
                "items": items]]]
        if let flags { state["threadRuntimeStatus"] = ["type": "active", "activeFlags": flags] }
        let data = try JSONSerialization.data(withJSONObject: state)
        let full = try CodexDesktopRequestProjector.project(conversationID: "task", conversationStateData: data)
        let projection = CodexDesktopInteractionProjection(currentTurnID: full.currentTurnID,
            status: full.status, title: full.title, sourceKind: full.sourceKind, startedAt: full.startedAt,
            requests: full.requests, authoritativePendingIdentities: full.authoritativePendingIdentities,
            pendingRequestsAreAuthoritative: authoritative && full.pendingRequestsAreAuthoritative,
            asyncQuestions: full.asyncQuestions, authoritativeAsyncQuestionIDs: full.authoritativeAsyncQuestionIDs,
            threadWaitStatus: full.threadWaitStatus)
        let snapshot = CodexDesktopConversationSnapshot(conversationID: "task", hostID: "local", ownerClientID: owner,
            connectionEpoch: epoch, revision: revision, conversationState: data,
            supportsUntrustedAppInput: true, requests: [])
        return (projection, snapshot)
    }
    private func apply(_ store: CodexActivityStore, _ pair: (CodexDesktopInteractionProjection, CodexDesktopConversationSnapshot)) async -> Bool {
        await store.receiveDesktopProjection(pair.0, snapshot: pair.1, at: base.addingTimeInterval(Double(pair.1.revision)))
    }
    private func hookWait(_ store: CodexActivityStore) {
        store.receive(.init(event: .permissionRequest, sessionHash: hash("task"), turnHash: hash("turn"),
            sessionKind: .user, source: .hook, waitReason: .approval, occurredAt: base.addingTimeInterval(1)))
    }
    private func request(_ id: String, method: String = "item/commandExecution/requestApproval") -> [String: Any] {
        ["id": id, "method": method, "params": ["threadId": "task", "turnId": "turn", "itemId": id,
            "command": "fixture command", "availableDecisions": ["accept", "decline"]]]
    }
    private func assertRunning(_ store: CodexActivityStore, _ island: IslandLiveStore,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNotEqual(store.snapshot?.state, .awaitingConfirmation, file: file, line: line)
        XCTAssertNotEqual(island.tasks.first?.status, .waiting, file: file, line: line)
        XCTAssertFalse(island.tasks.first?.requestLifecycle.waitingOnSource ?? true, file: file, line: line)
    }

    func testExplicitOwnerContinuationClearsAnonymousHookWaitInBothStoresAndOrdinaryActivityKeepsRunning() async throws {
        let (store, island) = setup()
        let initial = await apply(store, try pair(revision: 1, flags: nil)); XCTAssertTrue(initial)
        hookWait(store)
        XCTAssertEqual(store.snapshot?.state, .awaitingConfirmation)
        XCTAssertEqual(island.tasks.first?.requests.first?.key, "observer-placeholder")
        let continued = await apply(store, try pair(revision: 2)); XCTAssertTrue(continued)
        assertRunning(store, island)
        XCTAssertTrue(island.tasks[0].requests.isEmpty)
        XCTAssertTrue(island.tasks[0].requestLifecycle.resolvedCallHashes.isEmpty,
            "Clearing anonymous evidence never fabricates an answered call")
        store.receive(.init(event: .preToolUse, sessionHash: hash("task"), turnHash: hash("turn"),
            sessionKind: .user, source: .hook, toolCallHash: hash("ordinary"), occurredAt: base.addingTimeInterval(3)))
        assertRunning(store, island)
        await store.stop()
    }

    func testSharedUnidentifiedWaitWithoutTypedRemovalReconcilesBothStoresAndDoesNotResurrect() async throws {
        let (store, island) = setup()
        _ = await apply(store, try pair(revision: 1, flags: nil))
        let shared = try JSONSerialization.data(withJSONObject: ["method": "thread/snapshot", "params": [
            "thread": ["id": "task", "source": "cli", "status": ["type": "active", "activeFlags": ["waitingOnUserInput"]]],
            "currentTurn": ["id": "turn", "status": "inProgress", "startedAtMs": base.timeIntervalSince1970 * 1_000]]])
        await store.receiveScopedPublicMessage(shared, connectionEpoch: 3, at: base.addingTimeInterval(2))
        XCTAssertEqual(store.snapshot?.state, .awaitingConfirmation)
        XCTAssertEqual(island.tasks[0].sourceWaitReason, .userInput)
        _ = await apply(store, try pair(revision: 3)); assertRunning(store, island)
        store.receive(.init(event: .preToolUse, sessionHash: hash("task"), turnHash: hash("turn"),
            sessionKind: .user, source: .hook, toolCallHash: hash("ordinary"), occurredAt: base.addingTimeInterval(4)))
        assertRunning(store, island)
        await store.stop()
    }

    func testLateAnonymousWaitRemainsAdmissibleAndNextOwnerProofReconcilesWithoutBlockingFutureTypedRequest() async throws {
        let (store, island) = setup()
        _ = await apply(store, try pair(revision: 1))
        hookWait(store)
        XCTAssertEqual(island.tasks[0].status, .waiting, "Independent channels do not share a causal clock")
        _ = await apply(store, try pair(revision: 2)); assertRunning(store, island)
        _ = await apply(store, try pair(revision: 3, requests: [request("new")]))
        XCTAssertEqual(store.snapshot?.state, .awaitingConfirmation)
        XCTAssertEqual(island.tasks[0].status, .waiting)
        XCTAssertEqual(island.tasks[0].requests.first?.value.protocolRequest?.params["itemId"].text, "new")
        await store.stop()
    }

    func testEmptyRequestsWithExplicitWaitingFlagsRemainWaitingUntilRealContinuation() async throws {
        let (store, island) = setup()
        _ = await apply(store, try pair(revision: 1, flags: ["waitingOnApproval"]))
        XCTAssertEqual(store.snapshot?.state, .awaitingConfirmation)
        XCTAssertEqual(island.tasks[0].status, .waiting)
        XCTAssertEqual(island.tasks[0].requests.first?.key, "observer-placeholder")
        _ = await apply(store, try pair(revision: 2, flags: ["waitingOnUserInput"]))
        XCTAssertEqual(island.tasks[0].sourceWaitReason, .userInput)
        _ = await apply(store, try pair(revision: 3)); assertRunning(store, island)
        await store.stop()
    }

    func testMissingRuntimeAndPartialProjectionCannotClearAnonymousWait() async throws {
        let (store, island) = setup()
        _ = await apply(store, try pair(revision: 1, flags: nil)); hookWait(store)
        _ = await apply(store, try pair(revision: 2, flags: nil))
        XCTAssertEqual(island.tasks[0].status, .waiting)
        _ = await apply(store, try pair(revision: 3, authoritative: false))
        XCTAssertEqual(store.snapshot?.state, .awaitingConfirmation)
        XCTAssertEqual(island.tasks[0].status, .waiting)
        _ = await apply(store, try pair(revision: 4, flags: ["futureWaitingFlag"]))
        XCTAssertEqual(store.snapshot?.state, .awaitingConfirmation)
        XCTAssertEqual(island.tasks[0].status, .waiting)
        _ = await apply(store, try pair(revision: 5)); assertRunning(store, island)
        await store.stop()
    }

    func testUnknownConcurrentRequestPreventsTypedSettlementFromErasingIndependentWait() async throws {
        let (store, island) = setup()
        let known = request("known"), future = request("future", method: "future/approval/request")
        _ = await apply(store, try pair(revision: 1, requests: [known, future]))
        _ = await apply(store, try pair(revision: 2, requests: [future]))
        XCTAssertEqual(store.snapshot?.state, .awaitingConfirmation)
        XCTAssertEqual(island.tasks[0].status, .waiting)
        XCTAssertEqual(island.tasks[0].requests.first?.key, "observer-placeholder")
        _ = await apply(store, try pair(revision: 3)); assertRunning(store, island)
        await store.stop()
    }

    func testUnknownRPCAloneDoesNotInventANewUserWaitButCannotEraseAnObservedOne() async throws {
        let (store, island) = setup()
        let future = request("future", method: "future/approval/request")
        _ = await apply(store, try pair(revision: 1, requests: [future])); assertRunning(store, island)
        hookWait(store)
        _ = await apply(store, try pair(revision: 2, requests: [future]))
        XCTAssertEqual(island.tasks[0].status, .waiting)
        _ = await apply(store, try pair(revision: 3)); assertRunning(store, island)
        await store.stop()
    }

    func testContinuationClearsOnlyAnonymousEvidenceAndKeepsNativeAsyncQuestionUnanswered() async throws {
        let (store, island) = setup()
        let async: [String: Any] = ["id": "message", "type": "agentMessage", "questions": [[
            "title": "Which target?", "options": ["A", "B"]]]]
        _ = await apply(store, try pair(revision: 1, flags: nil, items: [async])); hookWait(store)
        _ = await apply(store, try pair(revision: 2, items: [async])); assertRunning(store, island)
        XCTAssertEqual(island.tasks[0].requests.count, 1)
        XCTAssertEqual(island.tasks[0].requests[0].mode, .asynchronous)
        XCTAssertTrue(island.tasks[0].requestLifecycle.resolvedCallHashes.isEmpty)
        await store.stop()
    }

    func testTypedAndAsyncParallelQuestionOnlySettlesTypedBlocker() async throws {
        let (store, island) = setup()
        let async: [String: Any] = ["id": "message", "type": "agentMessage", "questions": [[
            "title": "Which target?", "options": ["A", "B"]]]]
        _ = await apply(store, try pair(revision: 1, requests: [request("typed")], items: [async]))
        XCTAssertEqual(island.tasks[0].requests.count, 2)
        XCTAssertEqual(store.snapshot?.state, .awaitingConfirmation)
        _ = await apply(store, try pair(revision: 2, items: [async])); assertRunning(store, island)
        XCTAssertEqual(island.tasks[0].requests.count, 1)
        XCTAssertEqual(island.tasks[0].requests.first?.mode, .asynchronous)
        XCTAssertFalse(island.tasks[0].requestLifecycle.resolvedCallHashes.contains(hash("message")))
        await store.stop()
    }

    func testNewOwnerEmptySnapshotCannotSettleOldTypedRequestButReobservedIdentityMigrates() async throws {
        let (store, island) = setup()
        let known = request("known")
        _ = await apply(store, try pair(revision: 1, requests: [known]))
        let original = try XCTUnwrap(island.tasks[0].requests.first?.value.id)
        _ = await apply(store, try pair(revision: 1, owner: "new-owner"))
        XCTAssertEqual(island.tasks[0].requests.first?.value.id, original)
        XCTAssertEqual(island.tasks[0].requests.first?.desktopOwner, "owner")
        XCTAssertFalse(island.tasks[0].requests.first?.value.canRespond ?? true)
        XCTAssertEqual(island.tasks[0].status, .waiting)
        XCTAssertEqual(store.snapshot?.state, .awaitingConfirmation)
        _ = await apply(store, try pair(revision: 2, requests: [known], owner: "new-owner"))
        XCTAssertEqual(island.tasks[0].requests.first?.value.id, original)
        XCTAssertEqual(island.tasks[0].requests.first?.desktopOwner, "new-owner")
        _ = await apply(store, try pair(revision: 3, owner: "new-owner"))
        assertRunning(store, island)
        XCTAssertTrue(island.tasks[0].requests.isEmpty)
        await store.stop()
    }

    func testReobservedBlockingRequestMigratesRuntimeWaitWithoutRequiringWaitingFlags() async throws {
        let (store, island) = setup()
        let known = request("known")
        _ = await apply(store, try pair(revision: 1, flags: ["waitingOnApproval"], requests: [known]))
        let original = try XCTUnwrap(island.tasks[0].requests.first?.value.id)
        _ = await apply(store, try pair(revision: 1, requests: [known], owner: "new-owner"))
        XCTAssertEqual(island.tasks[0].requests.first?.value.id, original)
        XCTAssertEqual(island.tasks[0].requests.first?.desktopOwner, "new-owner")
        XCTAssertEqual(island.tasks[0].status, .waiting)
        _ = await apply(store, try pair(revision: 2, owner: "new-owner"))
        assertRunning(store, island)
        XCTAssertTrue(island.tasks[0].requests.isEmpty,
            "Typed identity migration cannot strand aggregate waiting in an old owner scope")
        await store.stop()
    }

    func testNewConnectionEmptySnapshotCannotSettleOldTypedRequestUntilIdentityIsReobserved() async throws {
        let (store, island) = setup()
        let known = request("known")
        _ = await apply(store, try pair(revision: 1, requests: [known]))
        let original = try XCTUnwrap(island.tasks[0].requests.first?.value.id)
        island.setDesktopConnection(connected: false, epoch: nil)
        island.setDesktopConnection(connected: true, epoch: 10)
        _ = await apply(store, try pair(revision: 1, epoch: 10))
        XCTAssertEqual(island.tasks[0].requests.first?.value.id, original)
        XCTAssertEqual(island.tasks[0].requests.first?.desktopEpoch, 9)
        XCTAssertEqual(island.tasks[0].status, .waiting)
        _ = await apply(store, try pair(revision: 2, requests: [known], epoch: 10))
        XCTAssertEqual(island.tasks[0].requests.first?.value.id, original)
        XCTAssertEqual(island.tasks[0].requests.first?.desktopEpoch, 10)
        _ = await apply(store, try pair(revision: 3, epoch: 10))
        assertRunning(store, island)
        await store.stop()
    }

    func testOldOwnerAnonymousRuntimeWaitNeedsPositiveReobservationBeforeNewScopeContinuation() async throws {
        let (store, island) = setup()
        _ = await apply(store, try pair(revision: 1, flags: ["waitingOnApproval"]))
        _ = await apply(store, try pair(revision: 1, owner: "new-owner"))
        XCTAssertEqual(island.tasks[0].status, .waiting)
        XCTAssertEqual(store.snapshot?.state, .awaitingConfirmation)
        _ = await apply(store, try pair(revision: 2, flags: ["waitingOnUserInput"], owner: "new-owner"))
        XCTAssertEqual(island.tasks[0].sourceWaitReason, .userInput)
        _ = await apply(store, try pair(revision: 3, owner: "new-owner"))
        assertRunning(store, island)
        await store.stop()
    }

    func testOldConnectionOrRevisionAndDifferentTurnCannotSupplyContinuationProof() async throws {
        let (store, island) = setup()
        _ = await apply(store, try pair(revision: 1, flags: nil)); hookWait(store)
        _ = await apply(store, try pair(revision: 2, flags: ["waitingOnApproval"]))
        let old = try pair(revision: 1)
        island.receiveDesktopProjection(old.0, snapshot: old.1)
        let previousEpoch = try pair(revision: 100, epoch: 8)
        island.receiveDesktopProjection(previousEpoch.0, snapshot: previousEpoch.1)
        let differentTurn = try pair(revision: 100, turn: "other")
        island.receiveDesktopProjection(differentTurn.0, snapshot: differentTurn.1)
        XCTAssertEqual(island.tasks[0].status, .waiting)
        let admitted = await apply(store, old); XCTAssertFalse(admitted)
        _ = await apply(store, try pair(revision: 3)); assertRunning(store, island)
        await store.stop()
    }
}
