import AppKit
import Foundation
import XCTest
@testable import QuotaView
@testable import QuotaViewCore

final class CodexSubagentTransportSmokeTests: XCTestCase {
    private func client() -> CodexSharedAppServerActivityClient {
        .init(configuration: .init(isEnabled: false,
            socketURL: URL(fileURLWithPath: "/tmp/unused-child-smoke.sock"), executablePath: nil))
    }
    private func send(_ client: CodexSharedAppServerActivityClient, _ method: String,
                      _ params: [String: Any], id: Int? = nil) async throws {
        var envelope: [String: Any] = ["method": method, "params": params]
        if let id { envelope["id"] = id }
        try await client.handleJSONMessage(JSONSerialization.data(withJSONObject: envelope))
    }
    private func thread(_ id: String, parent: String = "parent", title: String = "Audit") -> [String: Any] {
        ["id": id, "name": title, "model": "6.1 Sol", "reasoningEffort": "Ultra",
         "source": ["subAgent": ["thread_spawn": ["parent_thread_id": parent, "depth": 1,
             "agent_nickname": "Nickname", "agent_role": "worker"]]], "threadSource": "subagent",
         "status": ["type": "active"], "privateReasoning": "PRIVATE-THREAD"]
    }

    @MainActor
    func testThreeSharedChildrenReachStoreAndParentCardWithoutUserOwnership() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let shared = client()
        let store = CodexActivityStore(titleClient: .init(executablePath: nil), sessionDirectory: root,
            sessionKindResolver: { $0.sessionKind ?? .unknown })
        store.setMultitaskEnabled(true)
        let model = IslandLiveStore()
        var userEvents: [CodexActivityEvent] = []
        var userMessages = 0
        store.admittedActivityDidReceive = { userEvents.append($0); model.receiveLegacy($0) }
        store.publicMessageDidReceive = { userMessages += 1; model.receive($0) }
        store.activitySessionKindDidResolve = { model.setSessionKind($1, for: $0) }
        store.activityExecutionKindDidResolve = { model.receiveExecutionSessionKind($1, session: $0) }
        store.subagentIdentityDidReceive = { model.receiveSubagentIdentity($0) }
        store.subagentActivityDidReceive = { model.receiveSubagentActivity($0) }
        store.subagentPublicMessageDidReceive = { model.receiveSubagentPublicMessage($0) }
        await shared.start(handler: { _ in }, connectionStateHandler: { _ in })
        await shared.setScopedPublicMessageHandler { data, epoch in
            await store.receiveScopedPublicMessage(data, connectionEpoch: epoch)
        }
        try await send(shared, "thread/started", ["thread": ["id": "parent", "source": "vscode", "name": "Parent"]])
        try await send(shared, "turn/started", ["threadId": "parent", "turn": ["id": "parent-turn"]])
        let parentMessageCount = userMessages
        let titles = ["Memory identity review", "Approval copy audit", "Memory v2 diagnosis"]
        for (index, title) in titles.enumerated() {
            let id = "child-\(index)"
            try await send(shared, "thread/started", ["thread": thread(id, title: title)])
            try await send(shared, "thread/snapshot", ["thread": thread(id, title: title),
                "currentTurn": ["id": "turn-\(index)", "status": "inProgress", "startedAtMs": Date().timeIntervalSince1970 * 1000]])
            try await send(shared, "item/started", ["threadId": id, "turnId": "turn-\(index)",
                "item": ["id": "message-\(index)", "type": "agentMessage", "text": "公开进展 \(index)",
                    "privateReasoning": "PRIVATE-ITEM"]])
            try await send(shared, "item/tool/requestUserInput", ["threadId": id, "turnId": "turn-\(index)",
                "itemId": "question", "questions": [["id": "q", "question": "PRIVATE-QUESTION"]]], id: index + 1)
        }
        let display = model.display(english: false, remaining: nil, enabled: true, privacy: false)
        let children = display.sessionMetadata[model.tasks.first?.id ?? 0]?.subagents ?? []
        XCTAssertEqual(model.tasks.count, 1)
        XCTAssertEqual(store.multitask.entries.count, 1)
        XCTAssertEqual(children.map(\.title).sorted(), titles.sorted())
        XCTAssertEqual(Set(children.map(\.model)), ["6.1 Sol · Ultra"])
        XCTAssertEqual(Set(children.map(\.detail)), Set((0..<3).map { "公开进展 \($0)" }))
        XCTAssertEqual(userEvents.count, 1)
        XCTAssertEqual(userMessages, parentMessageCount)
        XCTAssertTrue(display.activeRequestIDs.isEmpty)
        try await send(shared, "turn/completed", ["threadId": "child-0", "turn": ["id": "turn-0", "status": "completed"]])
        let after = model.display(english: false, remaining: nil, enabled: true, privacy: false)
        XCTAssertEqual(after.sessionMetadata[model.tasks.first?.id ?? 0]?.subagents.count, 2)
        await shared.stop(); await store.stop()
    }

    func testVerifiedChildRefinesWarmGenericInternalAndExplicitGuardianRetracts() async throws {
        let capture = ChildTransportCapture(); let shared = client()
        await shared.start(handler: { await capture.event($0) }, connectionStateHandler: { _ in })
        await shared.setScopedPublicMessageHandler { data, _ in await capture.message(data) }
        try await send(shared, "thread/started", ["thread": ["id": "child", "threadSource": "subagent", "source": "unknown"]])
        try await send(shared, "turn/started", ["threadId": "child", "turn": ["id": "turn"]])
        try await send(shared, "thread/started", ["thread": thread("child", title: "Own title")])
        try await send(shared, "turn/started", ["threadId": "child", "turn": ["id": "turn"]])
        try await send(shared, "thread/started", ["thread": ["id": "child", "source": "unknown"]])
        try await send(shared, "thread/started", ["thread": ["id": "child", "source": ["internal": "guardian"]]])
        try await send(shared, "turn/started", ["threadId": "child", "turn": ["id": "second"]])
        let result = await capture.snapshot()
        XCTAssertTrue(result.events.isEmpty, "Scoped child lifecycle is admitted by Store exactly once")
        let envelopes = try result.messages.map { try XCTUnwrap(JSONSerialization.jsonObject(with: $0) as? [String: Any]) }
        XCTAssertEqual(envelopes.map { $0["method"] as? String }, ["thread/started", "thread/started", "turn/started", "thread/started", "thread/started"])
        let metadata = try XCTUnwrap((envelopes[3]["params"] as? [String: Any])?["thread"] as? [String: Any])
        let inherited = try XCTUnwrap(CodexActivitySubagentIdentity.decode(metadata))
        XCTAssertEqual(inherited.parentThreadID, "parent")
        XCTAssertEqual(inherited.title, "Own title")
        XCTAssertFalse(result.messages.contains { String(decoding: $0, as: UTF8.self).contains("PRIVATE-") })
        await shared.stop()
    }

    func testChildProjectionRejectsRequestsPrivateItemsTokensAndConflictingParent() async throws {
        let capture = ChildTransportCapture(); let shared = client()
        await shared.start(handler: { await capture.event($0) }, tokenUsageHandler: { _ in await capture.token() }, connectionStateHandler: { _ in })
        await shared.setScopedPublicMessageHandler { data, _ in await capture.message(data) }
        try await send(shared, "thread/started", ["thread": thread("child")])
        try await send(shared, "item/tool/requestUserInput", ["threadId": "child", "turnId": "turn", "questions": [["question": "PRIVATE-QUESTION"]]], id: 1)
        for type in ["reasoning", "agent_message", "userMessage"] {
            try await send(shared, "item/started", ["threadId": "child", "turnId": "turn", "item": ["type": type, "text": "PRIVATE-ITEM"]])
        }
        try await send(shared, "thread/tokenUsage/updated", ["threadId": "child", "turnId": "turn",
            "tokenUsage": ["total": ["totalTokens": 100], "last": ["totalTokens": 100]]])
        try await send(shared, "thread/started", ["thread": thread("child", parent: "other")])
        try await send(shared, "turn/started", ["threadId": "child", "turn": ["id": "turn"]])
        let result = await capture.snapshot()
        XCTAssertTrue(result.events.isEmpty)
        XCTAssertEqual(result.tokens, 0)
        XCTAssertEqual(result.messages.count, 1)
        XCTAssertFalse(String(decoding: result.messages[0], as: UTF8.self).contains("PRIVATE-"))
        await shared.stop()
    }

    func testDirectParentMetadataIsNormalizedButMemoryStillOverridesChild() async throws {
        let capture = ChildTransportCapture(); let shared = client()
        await shared.start(handler: { await capture.event($0) }, connectionStateHandler: { _ in })
        await shared.setScopedPublicMessageHandler { data, _ in await capture.message(data) }
        try await send(shared, "thread/started", ["thread": ["id": "direct", "source": "unknown",
            "parent_thread_id": "parent", "agent_nickname": "Name", "agent_role": "worker", "title": "Direct title"]])
        try await send(shared, "turn/started", ["threadId": "direct", "turn": ["id": "turn"]])
        try await send(shared, "thread/started", ["thread": ["id": "memory", "source": ["subAgent": "memory_consolidation"],
            "parentThreadId": "parent", "name": "Memory"]])
        try await send(shared, "turn/started", ["threadId": "memory", "turn": ["id": "memory-turn"]])
        let result = await capture.snapshot()
        XCTAssertEqual(result.events.map(\.sessionKind), [.memoryConsolidation])
        let first = try XCTUnwrap(JSONSerialization.jsonObject(with: result.messages[0]) as? [String: Any])
        let metadata = try XCTUnwrap((first["params"] as? [String: Any])?["thread"] as? [String: Any])
        XCTAssertNil(metadata["parent_thread_id"])
        XCTAssertEqual(CodexActivitySubagentIdentity.decode(metadata)?.parentThreadID, "parent")
        XCTAssertEqual(CodexActivitySubagentIdentity.decode(metadata)?.title, "Direct title")
        await shared.stop()
    }
}

private actor ChildTransportCapture {
    private var events: [CodexActivityEvent] = []
    private var messages: [Data] = []
    private var tokens = 0
    func event(_ event: CodexActivityEvent) { events.append(event) }
    func message(_ data: Data) { messages.append(data) }
    func token() { tokens += 1 }
    func snapshot() -> (events: [CodexActivityEvent], messages: [Data], tokens: Int) { (events, messages, tokens) }
}
