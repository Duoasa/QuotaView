import Foundation
import XCTest
@testable import QuotaView
@testable import QuotaViewCore

@MainActor
final class IslandThreadMetadataRecoverySmokeTests: XCTestCase {
    private func hash(_ value: String) -> String { CodexActivityPrivacy.hashIdentifier(value) }
    private func store() -> CodexActivityStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return .init(titleClient: .init(executablePath: nil),
            sharedActivityClient: .init(configuration: .init(isEnabled: false,
                socketURL: root.appendingPathComponent("unused.sock"), executablePath: nil)),
            localRolloutActivityClient: .init(configuration: .init(isEnabled: false, codexHomeURL: root)),
            sessionDirectory: root, sessionKindResolver: { $0.sessionKind ?? .unknown })
    }
    private func event(_ kind: CodexActivityHookEvent = .userPromptSubmit, turn: String = "one", at date: Date = Date()) -> CodexActivityEvent {
        .init(event: kind, sessionHash: hash("chat"), turnHash: hash(turn), workspaceName: "widget", sessionKind: .user,
            source: .hook, occurredAt: date)
    }
    private func metadata(_ value: CodexLocalRolloutThreadMetadata, id: String = "chat") -> CodexLocalRolloutDecodedRecord {
        .init(eventID: nil, update: .sessionMetadata, threadIdentity: .init(threadID: id,
            sessionHash: hash(id), sessionKind: .user, threadMetadata: value))
    }
    private func content(_ fields: [String: Any], turn: String = "one") throws -> CodexLocalPublicContent {
        .init(sessionHash: hash("chat"), turnHash: hash(turn),
            data: try JSONSerialization.data(withJSONObject: fields), occurredAt: Date())
    }
    private func connect(_ store: CodexActivityStore, _ model: IslandLiveStore) {
        store.admittedActivityDidReceive = { model.receiveLegacy($0) }
        store.threadMetadataDidReceive = { identity, value in model.receiveThreadMetadata(value, identity: identity) }
        store.cumulativeTokensDidReceive = { model.receiveToken($0) }
        store.localPublicContentDidReceive = { model.receiveLocalContent($0) }
    }

    func testThreadMetadataEnrichesHookTaskWithoutCreatingExecutionOrTurnUsage() async throws {
        let store = store(), model = IslandLiveStore(); connect(store, model)
        let fields = CodexLocalRolloutThreadMetadata(title: "QuotaView development", titleIsExplicitName: true,
            model: "gpt-6.1-sol", reasoningEffort: "ultra", cumulativeTotalTokens: 286_605_242)
        await store.receiveLocalRecord(metadata(fields), replay: true)
        XCTAssertNil(store.snapshot); XCTAssertTrue(model.tasks.isEmpty)
        XCTAssertNil(store.title(for: hash("chat")), "Metadata alone does not admit a task")
        store.receive(event())
        let task = try XCTUnwrap(model.tasks.first)
        XCTAssertEqual(task.title, "QuotaView development"); XCTAssertEqual(task.model, "gpt-6.1-sol")
        XCTAssertEqual(task.effort, "ultra"); XCTAssertEqual(task.tokens, 286_605_242)
        XCTAssertEqual(task.turnKey, hash("one")); XCTAssertEqual(task.status, .thinking)
        XCTAssertTrue(task.requests.isEmpty); XCTAssertTrue(task.entries.isEmpty)
        XCTAssertNil(store.currentTurnTokenUsage, "Thread cumulative totals never become consumed turn usage")
        XCTAssertEqual(store.titleSource(for: hash("chat")), .explicitName)
        await store.receiveLocalRecord(metadata(.init(title: "Old first prompt", model: "", reasoningEffort: "",
            cumulativeTotalTokens: 10)), replay: true)
        model.setTitle("widget", for: hash("chat"), source: .fallback)
        XCTAssertEqual(model.tasks[0].title, "QuotaView development")
        XCTAssertEqual(model.tasks[0].model, "gpt-6.1-sol"); XCTAssertEqual(model.tasks[0].tokens, 286_605_242)
        await store.receiveLocalRecord(metadata(.init(title: "Wrong root", titleIsExplicitName: true)), replay: true, generation: 99)
        XCTAssertEqual(model.tasks[0].title, "QuotaView development")
        _ = await store.stop()
    }

    func testStartlessExactTurnTokenReplayUsesActiveHookProofAndKeepsState() async throws {
        let store = store(), model = IslandLiveStore(); connect(store, model)
        var follows: [CodexLocalRolloutThreadIdentity] = []
        store.localThreadActivityDidReceive = { identity, active in if active { follows.append(identity) } }
        let now = Date(); store.receive(event(at: now))
        let update = CodexActivityTokenUsageUpdate(sessionHash: hash("chat"), turnHash: hash("one"),
            cumulativeTotalTokens: 295_897_857, lastReportedTotalTokens: 100,
            directTurnTotalTokens: 17_441_511, occurredAt: now.addingTimeInterval(1))
        let replay = CodexLocalRolloutDecodedRecord(eventID: nil, update: .tokenUsageReplay([update]),
            requiresLiveConfirmation: true, threadIdentity: .init(threadID: "chat", sessionHash: hash("chat"), sessionKind: .user))
        await store.receiveLocalRecord(replay, replay: true)
        XCTAssertEqual(store.currentTurnTokenUsage, 17_441_511)
        XCTAssertEqual(follows.map(\.threadID), ["chat"], "Exact active proof also restores read-only owner discovery")
        XCTAssertEqual(model.tasks[0].tokens, 295_897_857)
        XCTAssertEqual(model.tasks[0].turnKey, hash("one")); XCTAssertEqual(model.tasks[0].status, .thinking)
        XCTAssertEqual(model.tasks.count, 1); XCTAssertTrue(model.tasks[0].requests.isEmpty)
        let progress = try content(["type": "message", "id": "public", "text": "Checking bounded current data", "presentationRecovery": true])
        store.receiveLocalPublicContent(progress)
        XCTAssertEqual(model.tasks[0].publicProgress, "Checking bounded current data")
        store.receive(event(.stop, at: now.addingTimeInterval(2)))
        let oldCount = model.tasks[0].entries.count
        store.receiveLocalPublicContent(try content(["type": "message", "id": "late", "text": "Late replay", "presentationRecovery": true]))
        XCTAssertEqual(model.tasks[0].entries.count, oldCount, "A finished execution no longer authorizes recovery")
        _ = await store.stop()
    }

    func testLateHookFirstObservationAcceptsEarlierExactTurnCumulativeDisplayWithoutRegression() async throws {
        let store = store(), model = IslandLiveStore(); connect(store, model)
        let observedAt = Date(); store.receive(event(.preToolUse, at: observedAt))
        XCTAssertEqual(model.tasks[0].startedAt, observedAt)
        let earlier = CodexActivityTokenUsageUpdate(sessionHash: hash("chat"), turnHash: hash("one"),
            cumulativeTotalTokens: 295_897_857, lastReportedTotalTokens: 100,
            directTurnTotalTokens: 17_441_511, occurredAt: observedAt.addingTimeInterval(-60))
        await store.receiveLocalRecord(.init(eventID: nil, update: .tokenUsageReplay([earlier]), requiresLiveConfirmation: true,
            threadIdentity: .init(threadID: "chat", sessionHash: hash("chat"), sessionKind: .user)), replay: true)
        XCTAssertEqual(model.tasks[0].tokens, 295_897_857)
        XCTAssertEqual(model.tasks[0].turnKey, hash("one")); XCTAssertEqual(model.tasks[0].activityStatus, .working)
        XCTAssertEqual(store.currentTurnTokenUsage, 17_441_511)
        model.receiveToken(.init(sessionHash: hash("chat"), turnHash: hash("one"),
            cumulativeTotalTokens: 286_605_242, lastReportedTotalTokens: 10, occurredAt: observedAt.addingTimeInterval(-120)))
        XCTAssertEqual(model.tasks[0].tokens, 295_897_857, "Older cumulative snapshots never reduce the display")
        model.receiveToken(.init(sessionHash: hash("chat"), turnHash: hash("another-turn"),
            cumulativeTotalTokens: 400_000_000, lastReportedTotalTokens: 10, occurredAt: observedAt))
        XCTAssertEqual(model.tasks[0].tokens, 295_897_857, "A different turn cannot attach through an earlier timestamp exception")
        _ = await store.stop()
    }

    func testOldTurnReplayCannotRestoreTokensOrPublicProgressIntoNewTurn() async throws {
        let store = store(), model = IslandLiveStore(); connect(store, model)
        let now = Date(); store.receive(event(at: now))
        store.receive(event(.stop, at: now.addingTimeInterval(1)))
        store.receive(event(turn: "two", at: now.addingTimeInterval(2)))
        let old = CodexActivityTokenUsageUpdate(sessionHash: hash("chat"), turnHash: hash("one"),
            cumulativeTotalTokens: 300, lastReportedTotalTokens: 10, directTurnTotalTokens: 20,
            occurredAt: now.addingTimeInterval(3))
        await store.receiveLocalRecord(.init(eventID: nil, update: .tokenUsageReplay([old]), requiresLiveConfirmation: true,
            threadIdentity: .init(threadID: "chat", sessionHash: hash("chat"), sessionKind: .user)), replay: true)
        store.receiveLocalPublicContent(try content(["type": "message", "id": "old", "text": "Old turn", "presentationRecovery": true]))
        model.receiveThreadMetadata(.init(title: "Stale title", titleIsExplicitName: true, model: "old", cumulativeTotalTokens: 300),
            identity: .init(sessionHash: hash("chat"), turnHash: hash("one")))
        XCTAssertEqual(model.tasks[0].turnKey, hash("two")); XCTAssertEqual(model.tasks[0].title, "widget")
        XCTAssertTrue(model.tasks[0].publicProgress.isEmpty); XCTAssertTrue(model.tasks[0].model.isEmpty)
        XCTAssertNil(store.currentTurnTokenUsage); XCTAssertNil(model.tasks[0].tokens)
        _ = await store.stop()
    }

    func testSparseNativeAndLocalMetadataPreserveExactTurnLabelsAndRankedTitle() throws {
        let model = IslandLiveStore(), session = hash("chat"), turn = hash("one")
        model.receiveLegacy(event())
        model.receiveLocalContent(try content(["type": "metadata", "title": "Actual task", "model": "gpt-6.1-sol", "effort": "ultra"]))
        model.setTitle("widget", for: session, source: .fallback)
        XCTAssertEqual(model.tasks[0].title, "Actual task")
        func wire(_ method: String, _ params: [String: Any]) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["method": method, "params": params])
        }
        model.receive(try wire("thread/snapshot", ["thread": ["id": "chat", "source": "cli", "name": "Explicit name",
            "model": "old-thread-model", "reasoningEffort": "low", "status": ["type": "active"]]]))
        XCTAssertEqual(model.tasks[0].title, "Explicit name")
        XCTAssertEqual(model.tasks[0].model, "gpt-6.1-sol"); XCTAssertEqual(model.tasks[0].effort, "ultra")
        model.receive(try wire("turn/started", ["threadId": "chat", "turn": ["id": "one"], "model": "", "reasoningEffort": " "]))
        model.receive(try wire("thread/snapshot", ["thread": ["id": "chat", "source": "cli", "name": "", "title": "Old first prompt",
            "model": " ", "reasoningEffort": "", "status": ["type": "active"]]]))
        model.receiveLocalContent(try content(["type": "metadata", "title": " ", "model": "", "effort": " "]))
        model.receiveThreadMetadata(.init(title: "Old first prompt", model: "old", reasoningEffort: "low"),
            identity: .init(sessionHash: session, turnHash: turn))
        XCTAssertEqual(model.tasks[0].title, "Explicit name")
        XCTAssertEqual(model.tasks[0].model, "gpt-6.1-sol"); XCTAssertEqual(model.tasks[0].effort, "ultra")
    }

    func testPresentationRecoveryToolsAndOutputsDoNotChangeLiveWorkOrSettleRequests() throws {
        let model = IslandLiveStore(); model.receiveLegacy(event())
        model.receiveLocalContent(try content(["type": "tool", "id": "current", "name": "exec_command", "text": "{\"cmd\":\"current work\"}"]))
        let currentOperation = model.tasks[0].operation
        model.receiveLegacy(.init(event: .permissionRequest, sessionHash: hash("chat"), turnHash: hash("one"),
            sessionKind: .user, source: .hook, toolCallHash: hash("current"), occurredAt: Date()))
        let requests = model.tasks[0].requests.count
        model.receiveLocalContent(try content(["type": "tool", "id": "historic", "name": "exec_command", "text": "{\"cmd\":\"old work\"}", "presentationRecovery": true]))
        model.receiveLocalContent(try content(["type": "output", "id": "current", "text": "old result", "presentationRecovery": true]))
        XCTAssertEqual(model.tasks[0].activeItems.count, 1)
        XCTAssertEqual(model.tasks[0].activeItems["current"], currentOperation)
        XCTAssertEqual(model.tasks[0].activityStatus, .working)
        XCTAssertEqual(model.tasks[0].requests.count, requests)
        XCTAssertFalse(model.tasks[0].resolvedCallHashes.contains(hash("current")))
        XCTAssertEqual(model.tasks[0].entries.first(where: { $0.publicItem?.sourceID == "historic" })?.publicItem?.status, "completed")
    }
}
