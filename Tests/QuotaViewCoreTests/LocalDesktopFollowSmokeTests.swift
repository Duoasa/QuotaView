import Foundation
import XCTest
@testable import QuotaView
@testable import QuotaViewCore

@MainActor
final class LocalDesktopFollowSmokeTests: XCTestCase {
    private func hash(_ value: String) -> String { CodexActivityPrivacy.hashIdentifier(value) }
    private func root() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        return root
    }
    private func store(_ root: URL, localEnabled: Bool = false) -> CodexActivityStore {
        .init(titleClient: .init(executablePath: nil),
              sharedActivityClient: .init(configuration: .init(isEnabled: false,
                  socketURL: root.appendingPathComponent("unused.sock"), executablePath: nil)),
              localRolloutActivityClient: .init(configuration: .init(isEnabled: localEnabled, codexHomeURL: root)),
              sessionDirectory: root, sessionKindResolver: { $0.sessionKind ?? .unknown })
    }
    private func write(_ root: URL, id: String, source: Any = "cli", completed: Bool = false, asyncQuestion: Bool = false) throws {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let old = Date().addingTimeInterval(-120)
        var records: [[String: Any]] = [
            ["type": "session_meta", "payload": ["id": id, "source": source, "cwd": "/fixture/project"]],
            ["type": "event_msg", "timestamp": formatter.string(from: old), "payload": ["type": "task_started", "turn_id": "turn"]]
        ]
        if asyncQuestion {
            let args = String(decoding: CodexDesktopIPCClientTests.data(["questions": [["title": "Rollout source?", "options": ["A", "B"]]]]), as: UTF8.self)
            records.append(["type": "response_item", "timestamp": formatter.string(from: old.addingTimeInterval(1)),
                "payload": ["type": "function_call", "name": "functions.request_user_input_async", "call_id": "rollout-launch-id", "arguments": args]])
        }
        if completed { records.append(["type": "event_msg", "timestamp": formatter.string(from: old.addingTimeInterval(2)),
            "payload": ["type": "task_complete", "turn_id": "turn"]]) }
        var data = Data()
        for record in records { data.append(CodexDesktopIPCClientTests.data(record)); data.append(10) }
        try data.write(to: root.appendingPathComponent("sessions/\(id).jsonl"))
    }
    private func wait(_ predicate: () -> Bool) async throws {
        for _ in 0..<500 { if predicate() { return }; try await Task.sleep(nanoseconds: 10_000_000) }
        throw CodexDesktopIPCError.unavailable
    }
    private func record(id: String = "conversation", turn: String = "turn", event: CodexActivityHookEvent = .userPromptSubmit,
                        kind: CodexActivitySessionKind = .user, identitySession: String? = nil,
                        pending: Bool = true, date: Date = Date()) -> CodexLocalRolloutDecodedRecord {
        .init(eventID: nil, update: .activity(.init(event: event, sessionHash: hash(id), turnHash: hash(turn),
            sessionKind: kind, source: .localRollout, occurredAt: date)), requiresLiveConfirmation: pending,
            threadIdentity: .init(threadID: id, sessionHash: identitySession ?? hash(id), sessionKind: kind))
    }

    func testLocalOnlyPausedUnknownSourceOwnerFollowsAndReplacesReadonlyAsyncQuestion() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        try write(root, id: "conversation", asyncQuestion: true)
        let native: [String: Any] = ["type": "agentMessage", "id": "native-message",
            "questions": [["title": "Native question?", "options": ["A", "B"]]]]
        var ownerState = CodexDesktopIPCClientTests.state(requests: [], items: [native])
        ownerState.removeValue(forKey: "source")
        ownerState.removeValue(forKey: "threadSource")
        let fixture = CodexDesktopIPCFixture(state: ownerState)
        let desktop = fixture.client(), store = store(root, localEnabled: true), island = IslandLiveStore()
        let recorder = CodexDesktopIPCSnapshotRecorder()
        var localCount = 0; var rawSharedCount = 0; var followedWithoutTask = false
        store.admittedActivityDidReceive = { island.receiveLegacy($0) }
        store.localPublicContentDidReceive = { localCount += 1; island.receiveLocalContent($0) }
        store.publicMessageDidReceive = { _ in rawSharedCount += 1 }
        store.desktopProjectionDidReceive = { island.receiveDesktopProjection($0, snapshot: $1) }
        store.localThreadActivityDidReceive = { identity, active in
            if active {
                if store.snapshot == nil { followedWithoutTask = true }
                Task { try? await desktop.follow(conversationID: identity.threadID) }
            } else { Task { await desktop.unfollow(conversationID: identity.threadID) } }
        }
        island.responseCapability = { $0.desktopHandle != nil }
        island.respond = { wire, result in _ = try await desktop.submit(handle: try XCTUnwrap(wire.desktopHandle), result: result.data) }
        await desktop.start(snapshotHandler: { snapshot in
            await recorder.record(snapshot)
            guard let projection = try? CodexDesktopRequestProjector.project(conversationID: snapshot.conversationID, conversationStateData: snapshot.conversationState) else { return }
            _ = await store.receiveDesktopProjection(projection, snapshot: snapshot)
        }, stateHandler: { state in
            await recorder.recordState(state)
            await MainActor.run { island.setDesktopConnection(connected: state == .connected, epoch: nil) }
        })
        try await recorder.waitForConnection()
        store.startNativeActivityNotifications()
        try await wait { island.tasks.first?.requests.first?.value.canRespond == true }
        XCTAssertTrue(followedWithoutTask, "Discovery requests an owner proof before historical disk context can create a task")
        XCTAssertEqual(rawSharedCount, 0, "Local-only ingress does not depend on a Shared public envelope")
        XCTAssertGreaterThanOrEqual(localCount, 1)
        XCTAssertEqual(island.tasks[0].requests.count, 1)
        let wire = try XCTUnwrap(island.tasks[0].requests[0].value.protocolRequest)
        XCTAssertFalse(wire.observationOnly)
        XCTAssertEqual(wire.questions.first?.title, "Native question?")
        XCTAssertTrue(wire.questions.first?.other == true, "The real native async form includes its freeform route")
        XCTAssertEqual(wire.desktopHandle?.kind, .asynchronousQuestion)
        XCTAssertNotEqual(island.tasks[0].status, .waiting)
        let ownerSnapshot = try await recorder.wait(after: 0)
        let ownerProjection = try CodexDesktopRequestProjector.project(conversationID: ownerSnapshot.conversationID,
            conversationStateData: ownerSnapshot.conversationState)
        XCTAssertEqual(ownerProjection.sourceKind, .unknown, "Only verified local metadata supplies task kind")
        let questionID = try XCTUnwrap(wire.questions.first?.id)
        let answer = String(decoding: CodexDesktopIPCClientTests.data([["questionItemId": questionID,
            "question": "Native question?", "answer": "A"]]), as: UTF8.self)
        let reply: [String: Any] = ["type": "steeringUserMessage", "id": "external", "status": "accepted", "input": [[
            "type": "text", "text": CodexDesktopRequestProjector.asyncReplyOpeningTag + answer + CodexDesktopRequestProjector.asyncReplyClosingTag]]]
        ownerState["turns"] = (CodexDesktopIPCClientTests.state(requests: [], items: [native, reply]))["turns"]
        fixture.setState(ownerState, revision: 8)
        try await wait { island.tasks[0].requests.isEmpty }
        XCTAssertTrue(fixture.submissions.isEmpty, "External Codex answers synchronize without submitting a response")
        await store.stop(); await desktop.stop()
    }


    func testUnknownOwnerSourceRejectsMissingInvalidInternalWithdrawnAndOldDirectoryIdentity() async throws {
        var state = CodexDesktopIPCClientTests.state(requests: [])
        state.removeValue(forKey: "source")
        state.removeValue(forKey: "threadSource")
        let fixture = CodexDesktopIPCFixture(state: state)
        let (client, _, ownerSnapshot) = try await fixture.connectedClient()
        let projection = try CodexDesktopRequestProjector.project(conversationID: ownerSnapshot.conversationID,
            conversationStateData: ownerSnapshot.conversationState)
        XCTAssertEqual(projection.sourceKind, .unknown)
        for scenario in ["missing", "invalid", "internal", "withdrawn", "old-directory"] {
            let root = try root()
            let store = store(root)
            switch scenario {
            case "invalid":
                await store.receiveLocalRecord(record(identitySession: hash("different")), replay: true)
            case "internal":
                await store.receiveLocalRecord(record(kind: .internalTask), replay: true)
            case "withdrawn":
                await store.receiveLocalRecord(record(), replay: true)
                for index in 0..<100 { await store.receiveLocalRecord(record(id: "eviction-\(index)"), replay: true) }
            case "old-directory":
                await store.receiveLocalRecord(record(), replay: true)
                let run = await store.stop()
                await store.receiveLocalRecord(record(), replay: true, generation: run - 1)
            default: break
            }
            XCTAssertFalse(store.localDesktopFollowIdentities.contains { $0.threadID == "conversation" }, scenario)
            let admitted = await store.receiveDesktopProjection(projection, snapshot: ownerSnapshot)
            XCTAssertFalse(admitted, scenario)
            XCTAssertNil(store.snapshot, scenario)
            await store.stop()
            try? FileManager.default.removeItem(at: root)
        }
        XCTAssertTrue(fixture.submissions.isEmpty)
        await client.stop()
    }

    func testExplicitDesktopInternalSourceCannotBorrowVerifiedLocalUserIdentity() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let store = store(root)
        await store.receiveLocalRecord(record(), replay: true)
        XCTAssertEqual(store.localDesktopFollowIdentities.map(\.threadID), ["conversation"])
        var state = CodexDesktopIPCClientTests.state(requests: [])
        state["source"] = ["subagent": ["other": "guardian"]]
        let fixture = CodexDesktopIPCFixture(state: state)
        let (client, _, ownerSnapshot) = try await fixture.connectedClient()
        let projection = try CodexDesktopRequestProjector.project(conversationID: ownerSnapshot.conversationID,
            conversationStateData: ownerSnapshot.conversationState)
        XCTAssertEqual(projection.sourceKind, .internalTask)
        let admitted = await store.receiveDesktopProjection(projection, snapshot: ownerSnapshot)
        XCTAssertFalse(admitted)
        XCTAssertNil(store.snapshot)
        XCTAssertTrue(fixture.submissions.isEmpty)
        await store.stop(); await client.stop()
    }

    func testFollowIntentRejectsUnverifiedIdentityInternalSourceAndOldGeneration() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let store = store(root); var ids: [String] = []
        store.localThreadActivityDidReceive = { identity, _ in ids.append(identity.threadID) }
        await store.receiveLocalRecord(record(identitySession: hash("different")), replay: true)
        await store.receiveLocalRecord(record(id: "internal", kind: .internalTask), replay: true)
        await store.receiveLocalRecord(record(id: "unknown", kind: .unknown), replay: true)
        XCTAssertTrue(ids.isEmpty)
        XCTAssertTrue(store.localDesktopFollowIdentities.isEmpty)
        XCTAssertNil(store.snapshot)
        let run = await store.stop()
        await store.receiveLocalRecord(record(), replay: true, generation: run - 1)
        XCTAssertTrue(ids.isEmpty, "An old directory callback cannot seed the new Desktop scope")
        await store.receiveLocalRecord(record(), replay: true, generation: run)
        XCTAssertEqual(ids, ["conversation"])
        XCTAssertEqual(store.localDesktopFollowIdentities.map(\.threadID), ["conversation"])
        XCTAssertNil(store.snapshot, "Read-only follow intent is not lifecycle admission")
        await store.stop()
        XCTAssertTrue(store.localDesktopFollowIdentities.isEmpty)
    }

    func testDiscoveryOnlyFollowsUnfinishedVerifiedUserRollout() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        try write(root, id: "paused")
        try write(root, id: "completed", completed: true)
        try write(root, id: "internal", source: ["subagent": ["other": "guardian"]])
        try write(root, id: "unknown", source: "unknown-future-source")
        let store = store(root, localEnabled: true); var ids: [String] = []
        store.localThreadActivityDidReceive = { identity, active in if active { ids.append(identity.threadID) } }
        store.startNativeActivityNotifications()
        try await wait { store.localHealth == .ready }
        XCTAssertEqual(ids, ["paused"])
        XCTAssertEqual(store.localDesktopFollowIdentities.map(\.threadID), ["paused"])
        XCTAssertNil(store.snapshot, "An unfinished historical rollout still requires current owner evidence")
        await store.stop()
    }

    func testBoundedIntentEvictionWithdrawsOldObservationBeforeFollowingNewThread() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let store = store(root); var events: [(String, Bool)] = []
        store.localThreadActivityDidReceive = { identity, active in events.append((identity.threadID, active)) }
        for index in 0..<101 { await store.receiveLocalRecord(record(id: "thread-\(index)"), replay: true) }
        XCTAssertEqual(store.localDesktopFollowIdentities.count, 100)
        XCTAssertFalse(store.localDesktopFollowIdentities.contains { $0.threadID == "thread-0" })
        XCTAssertEqual(events[events.count - 2].0, "thread-0")
        XCTAssertFalse(events[events.count - 2].1)
        XCTAssertEqual(events.last?.0, "thread-100")
        XCTAssertTrue(events.last?.1 == true)
        XCTAssertNil(store.snapshot, "Evicting a discovery intent does not manufacture task completion")
        await store.stop()
    }

    func testOnlyAdmittedCurrentTerminalWithdrawsRetainedFollowIntent() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let store = store(root); var states: [Bool] = []
        store.localThreadActivityDidReceive = { _, active in states.append(active) }
        let now = Date()
        await store.receiveLocalRecord(record(pending: false, date: now), replay: false)
        await store.receiveLocalRecord(record(event: .stop, pending: false, date: now.addingTimeInterval(1)), replay: false)
        XCTAssertEqual(states, [true, false])
        XCTAssertTrue(store.localDesktopFollowIdentities.isEmpty)
        await store.receiveLocalRecord(record(event: .preToolUse, pending: false, date: now.addingTimeInterval(2)), replay: false)
        XCTAssertEqual(states, [true, false], "Same-turn late activity cannot reacquire a completed intent")
        await store.receiveLocalRecord(record(turn: "new", pending: false, date: now.addingTimeInterval(3)), replay: false)
        await store.receiveLocalRecord(record(event: .stop, pending: false, date: now.addingTimeInterval(4)), replay: false)
        XCTAssertEqual(states, [true, false, true], "An old terminal cannot detach the newer current turn")
        XCTAssertEqual(store.localDesktopFollowIdentities.map(\.threadID), ["conversation"])
        await store.stop()
    }
}
