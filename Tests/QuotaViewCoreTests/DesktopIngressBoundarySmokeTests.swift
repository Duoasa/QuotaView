import Foundation
import XCTest
@testable import QuotaView
@testable import QuotaViewCore

@MainActor
final class DesktopIngressBoundarySmokeTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_790_888_000)
    private func hash(_ value: String) -> String { CodexActivityPrivacy.hashIdentifier(value) }
    private func makeStore(resolver: (@Sendable (CodexActivityEvent) async -> CodexActivitySessionKind)? = nil) -> CodexActivityStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return CodexActivityStore(titleClient: .init(executablePath: nil),
            sharedActivityClient: .init(configuration: .init(isEnabled: false,
                socketURL: root.appendingPathComponent("unused.sock"), executablePath: nil)),
            localRolloutActivityClient: .init(configuration: .init(isEnabled: false, codexHomeURL: root)),
            sessionDirectory: root, sessionKindResolver: resolver ?? { $0.sessionKind ?? .user })
    }
    private func pair(conversation: String = "task", turn: String = "turn", status: String = "inProgress", epoch: UInt64 = 9,
                      revision: Int64 = 1, owner: String = "owner", source: Any = "appServer",
                      requests: [[String: Any]] = [], items: [[String: Any]] = [], at: Date? = nil)
        throws -> (CodexDesktopInteractionProjection, CodexDesktopConversationSnapshot) {
        let state: [String: Any] = ["id": conversation, "source": source, "title": "Real task", "requests": requests,
            "turns": [["turnId": turn, "status": status, "turnStartedAtMs": (at ?? base).timeIntervalSince1970 * 1_000, "items": items]]]
        let data = try JSONSerialization.data(withJSONObject: state)
        let projection = try CodexDesktopRequestProjector.project(conversationID: conversation, conversationStateData: data)
        let snapshot = CodexDesktopConversationSnapshot(conversationID: conversation, hostID: "local", ownerClientID: owner,
            connectionEpoch: epoch, revision: revision, conversationState: data, supportsUntrustedAppInput: true, requests: [])
        return (projection, snapshot)
    }
    private func admit(_ pair: (CodexDesktopInteractionProjection, CodexDesktopConversationSnapshot),
                       store: CodexActivityStore, at: Date? = nil) async -> Bool {
        await store.receiveDesktopProjection(pair.0, snapshot: pair.1, at: at ?? base)
    }
    private func assertAdmission(_ expected: Bool,
                                 _ pair: (CodexDesktopInteractionProjection, CodexDesktopConversationSnapshot),
                                 store: CodexActivityStore, at: Date? = nil,
                                 file: StaticString = #filePath, line: UInt = #line) async {
        let actual = await admit(pair, store: store, at: at)
        XCTAssertEqual(actual, expected, file: file, line: line)
    }
    private func rpc(_ id: String = "request", turn: String = "turn", question: Bool = false) -> [String: Any] {
        let params: [String: Any] = question
            ? ["threadId": "task", "turnId": turn, "itemId": "call", "questions": [["id": "scope", "question": "Choose scope", "options": [["label": "Current module"]]]]]
            : ["threadId": "task", "turnId": turn, "itemId": "call", "command": "swift build", "availableDecisions": ["accept", "decline"]]
        return ["id": id, "method": question ? "item/tool/requestUserInput" : "item/commandExecution/requestApproval", "params": params]
    }
    private func localQuestion(turn: String) throws -> CodexLocalPublicContent {
        let arguments = String(decoding: try JSONSerialization.data(withJSONObject: ["questions": [["id": "scope", "question": "Choose scope", "options": [["label": "Current module"]]]]]), as: UTF8.self)
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let data = try JSONSerialization.data(withJSONObject: ["type": "response_item", "timestamp": formatter.string(from: base),
            "payload": ["type": "function_call", "name": "functions.request_user_input", "call_id": "call", "arguments": arguments]])
        return try XCTUnwrap(CodexLocalPublicContent.decode(data, sessionHash: hash("task"), activeTurnHash: hash(turn)))
    }
    private func sharedSnapshot(flags: [String]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["method": "thread/snapshot", "params": [
            "thread": ["id": "task", "source": "cli", "status": ["type": "active", "activeFlags": flags]],
            "currentTurn": ["id": "turn", "status": "inProgress", "startedAtMs": base.timeIntervalSince1970 * 1_000]]])
    }

    func testDesktopLeadingCurrentProofReleasesOnlyMatchingBufferedLocalDetail() async throws {
        let store = makeStore(); var localTurns: [String] = []; var callbacks = 0
        store.localPublicContentDidReceive = { localTurns.append($0.turnHash) }
        store.desktopProjectionDidReceive = { _, _ in callbacks += 1 }
        store.receive(.init(event: .userPromptSubmit, sessionHash: hash("task"), turnHash: hash("old"),
            sessionKind: .user, source: .localRollout, occurredAt: base.addingTimeInterval(-1)))
        store.receiveLocalPublicContent(try localQuestion(turn: "new"))
        store.receiveLocalPublicContent(try localQuestion(turn: "future"))
        XCTAssertTrue(localTurns.isEmpty)
        let admitted = await admit(try pair(turn: "new"), store: store)
        XCTAssertTrue(admitted)
        XCTAssertEqual(store.snapshot?.taskIdentity?.turnHash, hash("new"))
        XCTAssertEqual(localTurns, [hash("new")])
        XCTAssertEqual(callbacks, 1)
        await store.stop()
    }

    func testOldTurnAndNonIncreasingRevisionNeverReachPublicProjection() async throws {
        let store = makeStore(); var revisions: [Int64] = []
        store.desktopProjectionDidReceive = { _, snapshot in revisions.append(snapshot.revision) }
        await assertAdmission(true, try pair(turn: "old", revision: 1), store: store)
        await assertAdmission(true, try pair(turn: "new", revision: 2, at: base.addingTimeInterval(1)), store: store, at: base.addingTimeInterval(1))
        await assertAdmission(false, try pair(turn: "new", revision: 1), store: store, at: base.addingTimeInterval(2))
        await assertAdmission(false, try pair(turn: "old", revision: 3), store: store, at: base.addingTimeInterval(3))
        XCTAssertEqual(store.snapshot?.taskIdentity?.turnHash, hash("new"))
        XCTAssertEqual(revisions, [1, 2])
        await store.stop()
    }

    func testDisconnectRejectsOldEpochButFreshEpochRestoresProjection() async throws {
        let store = makeStore(); var epochs: [UInt64] = []
        store.desktopProjectionDidReceive = { _, snapshot in epochs.append(snapshot.connectionEpoch) }
        await assertAdmission(true, try pair(epoch: 9), store: store)
        store.setDesktopConnection(connected: false)
        await assertAdmission(false, try pair(epoch: 9, revision: 2), store: store)
        await assertAdmission(false, try pair(epoch: 8, revision: 100), store: store)
        await assertAdmission(true, try pair(epoch: 10), store: store)
        XCTAssertEqual(epochs, [9, 10])
        await store.stop()
    }

    func testUnknownAndInternalExecutionSourcesCannotOpenUserConfirmation() async throws {
        let store = makeStore(); var callbacks = 0
        store.desktopProjectionDidReceive = { _, _ in callbacks += 1 }
        await assertAdmission(false, try pair(source: "unknown", requests: [rpc()]), store: store)
        await assertAdmission(false, try pair(source: ["subagent": ["thread_spawn": ["parent_thread_id": "parent"]]], requests: [rpc()]), store: store)
        XCTAssertNil(store.snapshot); XCTAssertEqual(callbacks, 0)
        await store.stop()
    }

    func testRPCQuestionBlocksExecutionWhileNativeAsyncQuestionDoesNot() async throws {
        let synchronous = makeStore()
        await assertAdmission(true, try pair(requests: [rpc(question: true)]), store: synchronous)
        XCTAssertEqual(synchronous.snapshot?.state, .awaitingConfirmation)
        let asynchronous = makeStore()
        let question: [String: Any] = ["id": "message", "type": "agentMessage", "questions": [["title": "Choose scope", "options": ["Current module"]]]]
        await assertAdmission(true, try pair(items: [question]), store: asynchronous)
        XCTAssertNotEqual(asynchronous.snapshot?.state, .awaitingConfirmation)
        XCTAssertEqual(asynchronous.lifecycle, .active)
        await synchronous.stop(); await asynchronous.stop()
    }

    func testExactOwnerRemovalSettlesCoreButForeignEpochOrTurnDoesNot() async throws {
        let store = makeStore()
        await assertAdmission(true, try pair(requests: [rpc()]), store: store)
        for (turn, epoch, remaining) in [("other-turn", UInt64(9), false), ("turn", UInt64(3), false), ("turn", UInt64(9), true)] {
            store.receiveDesktopRequestSettlement(sessionHash: hash("task"), turnHash: hash(turn), epoch: epoch, stillWaiting: remaining, at: base.addingTimeInterval(1))
            XCTAssertEqual(store.snapshot?.state, .awaitingConfirmation)
        }
        store.desktopProjectionDidReceive = { projection, snapshot in
            if projection.pendingRequestsAreAuthoritative && projection.authoritativePendingIdentities.isEmpty {
                store.receiveDesktopRequestSettlement(sessionHash: CodexActivityPrivacy.hashIdentifier(snapshot.conversationID),
                    turnHash: CodexActivityPrivacy.hashIdentifier(projection.currentTurnID!), epoch: snapshot.connectionEpoch,
                    stillWaiting: false, at: self.base.addingTimeInterval(2))
            }
        }
        await assertAdmission(true, try pair(revision: 2), store: store, at: base.addingTimeInterval(2))
        XCTAssertNotEqual(store.snapshot?.state, .awaitingConfirmation)
        XCTAssertEqual(store.lifecycle, .active)
        await store.stop()
    }

    func testSharedEpochCannotClearIndependentDesktopWaitEvidence() async throws {
        let store = makeStore()
        await store.receiveScopedPublicMessage(try sharedSnapshot(flags: ["waitingOnApproval"]), connectionEpoch: 3, at: base)
        await assertAdmission(true, try pair(requests: [rpc()]), store: store, at: base.addingTimeInterval(1))
        await store.receiveScopedPublicMessage(try sharedSnapshot(flags: []), connectionEpoch: 3, at: base.addingTimeInterval(2))
        XCTAssertEqual(store.snapshot?.state, .awaitingConfirmation, "An observer's empty flags cannot settle a different Desktop owner's real request")
        store.receiveRequestSettlement(.init(sessionHash: hash("task"), turnHash: hash("turn"), connectionEpoch: 3, stillWaiting: false), at: base.addingTimeInterval(3))
        XCTAssertEqual(store.snapshot?.state, .awaitingConfirmation)
        await store.stop()
    }

    func testLateClassificationCannotOverwriteNewerDesktopRevision() async throws {
        let gate = DesktopIngressClassifierGate()
        let oldTurn = hash("old")
        let store = makeStore { event in
            if event.event == .userPromptSubmit && event.turnHash == oldTurn { await gate.block() }
            return event.sessionKind ?? .user
        }
        var revisions: [Int64] = []
        store.desktopProjectionDidReceive = { _, snapshot in revisions.append(snapshot.revision) }
        let oldPair = try pair(turn: "old", revision: 1)
        let oldAdmission = Task { await self.admit(oldPair, store: store) }
        await gate.waitUntilEntered()
        await assertAdmission(true, try pair(turn: "new", revision: 2, at: base.addingTimeInterval(1)), store: store, at: base.addingTimeInterval(1))
        await gate.release()
        let oldAccepted = await oldAdmission.value
        XCTAssertFalse(oldAccepted)
        XCTAssertEqual(store.snapshot?.taskIdentity?.turnHash, hash("new"))
        XCTAssertEqual(revisions, [2])
        await store.stop()
    }

    func testResourceRevocationCancelsOnlyMatchingScopeWhileClassificationAwaits() async throws {
        let oldEpochGate = DesktopIngressClassifierGate()
        let currentEpochGate = DesktopIngressClassifierGate()
        let firstTurn = hash("first"), revokedTurn = hash("revoked")
        let store = makeStore { event in
            if event.event == .userPromptSubmit && event.turnHash == firstTurn { await oldEpochGate.block() }
            if event.event == .userPromptSubmit && event.turnHash == revokedTurn { await currentEpochGate.block() }
            return event.sessionKind ?? .user
        }
        var publicScopes: [String] = [], admittedTurns: [String] = [], localTurns: [String] = []
        store.desktopProjectionDidReceive = { projection, snapshot in
            publicScopes.append(snapshot.conversationID + "/" + (projection.currentTurnID ?? ""))
        }
        store.admittedActivityDidReceive = { if $0.event == .userPromptSubmit { admittedTurns.append($0.turnHash!) } }
        store.localPublicContentDidReceive = { localTurns.append($0.turnHash) }

        // An old connection cannot revoke a receipt being classified on epoch 9.
        let firstPair = try pair(turn: "first", epoch: 9, requests: [rpc(turn: "first")])
        let firstAdmission = Task { await self.admit(firstPair, store: store) }
        await oldEpochGate.waitUntilEntered()
        store.invalidateDesktopProjection(conversationID: "task", epoch: 8)
        await oldEpochGate.release()
        let firstAccepted = await firstAdmission.value
        XCTAssertTrue(firstAccepted)
        XCTAssertEqual(store.snapshot?.taskIdentity?.turnHash, firstTurn)
        XCTAssertEqual(store.snapshot?.state, .awaitingConfirmation)

        let revokedPair = try pair(turn: "revoked", revision: 2, at: base.addingTimeInterval(1))
        let revokedAdmission = Task { await self.admit(revokedPair, store: store, at: self.base.addingTimeInterval(1)) }
        await currentEpochGate.waitUntilEntered()
        await assertAdmission(true, try pair(conversation: "other", turn: "b", at: base.addingTimeInterval(2)),
                              store: store, at: base.addingTimeInterval(2))
        store.invalidateDesktopProjection(conversationID: "task", epoch: 9)
        await currentEpochGate.release()
        let revokedAccepted = await revokedAdmission.value
        XCTAssertFalse(revokedAccepted)
        XCTAssertEqual(store.snapshot?.taskIdentity?.turnHash, hash("b"))
        XCTAssertEqual(admittedTurns, [firstTurn, hash("b")])
        XCTAssertEqual(publicScopes, ["task/first", "other/b"])

        // The previously admitted task is retained; revocation did not settle or
        // move its Registry identity, and the independent scope still updates.
        store.receiveLocalPublicContent(try localQuestion(turn: "first"))
        XCTAssertEqual(localTurns, [firstTurn])
        await assertAdmission(true, try pair(conversation: "other", turn: "b", revision: 2, at: base.addingTimeInterval(2)),
                              store: store, at: base.addingTimeInterval(3))
        XCTAssertEqual(publicScopes, ["task/first", "other/b", "other/b"])
        await store.stop()
    }

    func testDisconnectDuringClassificationCannotCreateLateCoreTask() async throws {
        let gate = DesktopIngressClassifierGate()
        let store = makeStore { event in
            if event.event == .userPromptSubmit { await gate.block() }
            return event.sessionKind ?? .user
        }
        var callbacks = 0; store.desktopProjectionDidReceive = { _, _ in callbacks += 1 }
        let first = try pair()
        let admission = Task { await self.admit(first, store: store) }
        await gate.waitUntilEntered()
        store.setDesktopConnection(connected: false)
        await gate.release()
        let accepted = await admission.value
        XCTAssertFalse(accepted)
        XCTAssertNil(store.snapshot)
        XCTAssertEqual(callbacks, 0)
        await store.stop()
    }
}

private actor DesktopIngressClassifierGate {
    private var entered = false
    private var continuation: CheckedContinuation<Void, Never>?
    func block() async { entered = true; await withCheckedContinuation { continuation = $0 } }
    func waitUntilEntered() async { while !entered { await Task.yield() } }
    func release() { continuation?.resume(); continuation = nil }
}
