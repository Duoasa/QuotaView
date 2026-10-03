import Foundation
import XCTest
@testable import QuotaViewCore

final class MemoryTransportSmokeTests: XCTestCase {
    func testScopedSharedLaneKeepsMemoryLifecycleAndMetadataWithoutContentOrActions() async throws {
        let capture = MemoryTransportCapture()
        let client = CodexSharedAppServerActivityClient(configuration: .init(isEnabled: false,
            socketURL: URL(fileURLWithPath: "/tmp/unused-memory-smoke.sock"), executablePath: nil))
        await client.start(handler: { await capture.append($0) },
            tokenUsageHandler: { await capture.append($0) }, connectionStateHandler: { _ in })
        await client.setScopedPublicMessageHandler { data, _ in await capture.append(data) }
        try await send(client, "thread/started", ["thread": ["id": "memory", "source": "unknown",
            "threadSource": NSNull(), "thread_source": "memory_consolidation", "status": ["type": "active"],
            "privateReasoning": "PRIVATE-MEMORY"]])
        try await send(client, "turn/started", ["threadId": "memory", "turn": ["id": "memory-turn"]])
        try await send(client, "item/tool/requestUserInput", ["threadId": "memory", "turnId": "memory-turn",
            "itemId": "question", "questions": [["id": "question", "question": "PRIVATE-MEMORY"]]], id: 1)
        try await send(client, "item/started", ["threadId": "memory", "turnId": "memory-turn",
            "item": ["type": "agentMessage", "text": "PRIVATE-MEMORY"]])
        try await send(client, "thread/tokenUsage/updated", ["threadId": "memory", "turnId": "memory-turn",
            "tokenUsage": ["total": ["totalTokens": 100], "last": ["totalTokens": 100]]])
        try await send(client, "turn/completed", ["threadId": "memory", "turn": ["id": "memory-turn", "status": "completed"]])
        let result = await capture.snapshot()
        XCTAssertEqual(result.events.map(\.event), [.userPromptSubmit, .stop])
        XCTAssertTrue(result.events.allSatisfy { $0.sessionKind == .memoryConsolidation
            && $0.sessionHash == CodexActivityPrivacy.hashIdentifier("memory") })
        XCTAssertEqual(result.events.last?.turnCompletionStatus, .completed)
        XCTAssertEqual(result.tokenCount, 0)
        XCTAssertEqual(result.messages.count, 1)
        let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: result.messages[0]) as? [String: Any])
        let thread = try XCTUnwrap((envelope["params"] as? [String: Any])?["thread"] as? [String: Any])
        XCTAssertEqual(thread["threadSource"] as? String, "memory_consolidation")
        XCTAssertNil(thread["thread_source"])
        XCTAssertFalse(String(decoding: result.messages[0], as: UTF8.self).contains("PRIVATE-MEMORY"))
        await client.stop()
    }

    func testSharedMemoryIdentitySurvivesSparseMetadataAndDoesNotTransferToOtherThread() async throws {
        let capture = MemoryTransportCapture()
        let client = CodexSharedAppServerActivityClient(configuration: .init(isEnabled: false,
            socketURL: URL(fileURLWithPath: "/tmp/unused-memory-smoke.sock"), executablePath: nil))
        await client.start(handler: { await capture.append($0) }, connectionStateHandler: { _ in })
        try await send(client, "thread/started", ["thread": ["id": "memory", "source": ["subAgent": "memory_consolidation"]]])
        try await send(client, "thread/started", ["thread": ["id": "memory", "source": "unknown"]])
        try await send(client, "thread/started", ["thread": ["id": "user", "source": "vscode", "title": "memories"]])
        for thread in ["memory", "user"] {
            try await send(client, "turn/started", ["threadId": thread, "turn": ["id": "turn"]])
        }
        let result = await capture.snapshot()
        XCTAssertEqual(result.events.count, 2)
        XCTAssertEqual(result.events[0].sessionKind, .memoryConsolidation)
        XCTAssertEqual(result.events[1].sessionKind, .user)
        XCTAssertNotEqual(result.events[0].sessionHash, result.events[1].sessionHash)
        await client.stop()
    }

    func testSharedExactMemoryRefinesInternalAndExplicitInternalRetractsMemory() async throws {
        let capture = MemoryTransportCapture()
        let client = CodexSharedAppServerActivityClient(configuration: .init(isEnabled: false,
            socketURL: URL(fileURLWithPath: "/tmp/unused-memory-smoke.sock"), executablePath: nil))
        await client.start(handler: { await capture.append($0) }, connectionStateHandler: { _ in })
        await client.setScopedPublicMessageHandler { data, _ in await capture.append(data) }
        for source: Any in [["subAgent": ["other": "internal"]], ["subAgent": "memory_consolidation"], ["internal": "guardian"]] {
            try await send(client, "thread/started", ["thread": ["id": "same-thread", "source": source]])
            try await send(client, "turn/started", ["threadId": "same-thread", "turn": ["id": "turn"]])
        }
        let result = await capture.snapshot()
        XCTAssertEqual(result.events.count, 1, "Explicit non-memory internal metadata retracts the memory lifecycle lane")
        XCTAssertEqual(result.events.first?.sessionKind, .memoryConsolidation)
        XCTAssertEqual(result.messages.count, 3, "Identity-only metadata reaches Store for refinement and retraction")
        let envelopes = try result.messages.map { try JSONSerialization.jsonObject(with: $0) as! [String: Any] }
        let threads = envelopes.map { ($0["params"] as! [String: Any])["thread"] as! [String: Any] }
        XCTAssertEqual(threads.map { CodexActivitySessionKind.classify(source: $0["source"]) },
            [.internalTask, .memoryConsolidation, .internalTask])
        await client.stop()
    }

    func testDesktopMemoryProjectionIsReadOnlyWithMissingOrMalformedRequestCollection() throws {
        for source: Any in [["internal": "memory_consolidation"], ["subagent": "memory_consolidation"], ["subAgent": "memory_consolidation"]] {
            var state = desktopState(source: source)
            state["requests"] = "not-an-action-collection"
            let projection = try project(state)
            XCTAssertEqual(projection.sourceKind, .memoryConsolidation)
            XCTAssertEqual(projection.currentTurnID, "turn")
            XCTAssertEqual(projection.status, "inProgress")
            XCTAssertTrue(projection.requests.isEmpty)
            XCTAssertTrue(projection.asyncQuestions.isEmpty)
            XCTAssertTrue(projection.authoritativePendingIdentities.isEmpty)
            XCTAssertTrue(projection.authoritativeAsyncQuestionIDs.isEmpty)
            XCTAssertFalse(projection.pendingRequestsAreAuthoritative)
            XCTAssertFalse(projection.provesNoPendingConfirmation)
            state.removeValue(forKey: "requests")
            XCTAssertEqual(try project(state).sourceKind, .memoryConsolidation)
        }
    }

    func testDesktopSnakeSourceKeepsMemoryKindAndUserNamedMemoriesRetainsQuestionCapability() throws {
        var memory = desktopState(source: "unknown")
        memory["threadSource"] = NSNull(); memory["thread_source"] = "memory_consolidation"
        XCTAssertEqual(try project(memory).sourceKind, .memoryConsolidation)
        var user = desktopState(source: "vscode")
        user["title"] = "memories"
        let projection = try project(user)
        XCTAssertEqual(projection.sourceKind, .user)
        XCTAssertEqual(projection.requests.count, 1)
        XCTAssertEqual(projection.asyncQuestions.count, 1)
        XCTAssertTrue(projection.pendingRequestsAreAuthoritative)
    }

    private func send(_ client: CodexSharedAppServerActivityClient, _ method: String,
                      _ params: [String: Any], id: Int? = nil) async throws {
        var envelope: [String: Any] = ["method": method, "params": params]
        if let id { envelope["id"] = id }
        try await client.handleJSONMessage(JSONSerialization.data(withJSONObject: envelope))
    }

    private func desktopState(source: Any) -> [String: Any] {
        ["id": "thread", "source": source, "requests": [["id": "rpc", "method": "item/tool/requestUserInput",
            "params": ["threadId": "thread", "turnId": "turn", "itemId": "call", "questions": [["id": "choice",
                "question": "Target?", "options": [["label": "Staging"]]]]]]],
         "turns": [["turnId": "turn", "status": "inProgress", "items": [["id": "message", "type": "agentMessage",
            "questions": [["title": "Target?", "options": ["Staging"]]]]]]]]
    }

    private func project(_ state: [String: Any]) throws -> CodexDesktopInteractionProjection {
        try CodexDesktopRequestProjector.project(conversationID: "thread",
            conversationStateData: JSONSerialization.data(withJSONObject: state))
    }
}

private actor MemoryTransportCapture {
    private var events: [CodexActivityEvent] = []
    private var messages: [Data] = []
    private var tokenCount = 0
    func append(_ event: CodexActivityEvent) { events.append(event) }
    func append(_ data: Data) { messages.append(data) }
    func append(_ token: CodexActivityTokenUsageUpdate) { tokenCount += 1 }
    func snapshot() -> (events: [CodexActivityEvent], messages: [Data], tokenCount: Int) {
        (events, messages, tokenCount)
    }
}
