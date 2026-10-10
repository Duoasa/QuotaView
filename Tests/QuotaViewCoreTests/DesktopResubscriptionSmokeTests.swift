import Foundation
@testable import QuotaView
@testable import QuotaViewCore
import XCTest

final class DesktopResubscriptionSmokeTests: XCTestCase {
    func data(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
    func state(turn: String, status: String = "inProgress", async: Bool) -> [String: Any] {
        let question: [String: Any] = ["type": "agentMessage", "id": "native-\(turn)", "questions": [["title": "Choose?", "options": ["A", "B"]]]]
        let command: [String: Any] = ["id": "approval-\(turn)", "method": "item/commandExecution/requestApproval", "params": ["threadId": "conversation", "turnId": turn, "itemId": "command-\(turn)", "command": "fixture command"]]
        return ["id": "conversation", "title": "Fixture", "source": "appServer", "cwd": "/fixture/project", "requests": status == "inProgress" && !async ? [command] : [], "turns": [["turnId": turn, "status": status, "items": async ? [question] : []]]]
    }
    @MainActor func apply(_ model: IslandLiveStore, _ snapshot: CodexDesktopConversationSnapshot) throws {
        model.receiveDesktopProjection(try CodexDesktopRequestProjector.project(conversationID: snapshot.conversationID, conversationStateData: snapshot.conversationState), snapshot: snapshot)
    }
    @MainActor func localQuestion(_ model: IslandLiveStore, turn: String) throws {
        let args = String(decoding: try data(["questions": [["title": "Choose?", "options": ["A", "B"]]]]), as: UTF8.self)
        let line = try data(["type": "response_item", "payload": ["type": "function_call", "name": "request_user_input_async", "call_id": "local-\(turn)", "arguments": args]])
        let content = CodexLocalPublicContent.decode(line, sessionHash: CodexActivityPrivacy.hashIdentifier("conversation"), activeTurnHash: CodexActivityPrivacy.hashIdentifier(turn))!
        model.receiveLocalContent(content)
    }
    @MainActor func check(async: Bool) async throws {
        let fixture = CodexDesktopIPCFixture(state: state(turn: "turn", async: async))
        let (client, recorder, first) = try await fixture.connectedClient()
        let model = IslandLiveStore()
        func event(_ kind: CodexActivityHookEvent, _ turn: String) {
            model.receiveLegacy(.init(event: kind, sessionHash: CodexActivityPrivacy.hashIdentifier("conversation"), turnHash: CodexActivityPrivacy.hashIdentifier(turn), sessionKind: .user, source: .appServer))
        }
        model.setDesktopConnection(connected: true, epoch: first.connectionEpoch)
        model.responseCapability = { $0.desktopHandle != nil }
        model.respond = { _, _ in fatalError("This audit never submits") }
        event(.userPromptSubmit, "turn")
        try apply(model, first)
        let baseline = model.tasks[0].requests.filter { $0.value.canRespond }.count
        var count = await recorder.count
        fixture.setState(state(turn: "turn", status: "completed", async: async), revision: 100)
        let completed = try await recorder.wait(after: count)
        event(.stop, "turn")
        try apply(model, completed)
        model.invalidateDesktopResponses(conversationID: "conversation", epoch: first.connectionEpoch)
        await client.unfollow(conversationID: "conversation")
        fixture.setState(state(turn: "turn2", async: async), revision: 1, emit: false)
        count = await recorder.count
        try await client.follow(conversationID: "conversation")
        let resumed = try await recorder.wait(after: count)
        event(.userPromptSubmit, "turn2")
        if async { try localQuestion(model, turn: "turn2") } else { event(.permissionRequest, "turn2") }
        try apply(model, resumed)
        XCTAssertEqual(baseline, 1)
        XCTAssertGreaterThan(resumed.streamGeneration, completed.streamGeneration)
        XCTAssertEqual(resumed.connectionEpoch, first.connectionEpoch)
        XCTAssertEqual(model.tasks[0].requests.filter { $0.value.canRespond }.count, 1)
        let oldCurrent = await client.isCurrent(completed)
        let newCurrent = await client.isCurrent(resumed)
        XCTAssertFalse(oldCurrent)
        XCTAssertTrue(newCurrent)
        do {
            _ = try await client.submit(handle: XCTUnwrap(first.requests.first), result: data(["decision": "accept"]))
            XCTFail("An old subscription handle must never submit")
        } catch { }
        // A queued older-generation snapshot must not settle the new request,
        // even when its native revision is numerically higher.
        var staleState = state(turn: "turn2", async: async)
        staleState["requests"] = []
        staleState["turns"] = [["turnId": "turn2", "status": "inProgress", "items": []]]
        let stale = CodexDesktopConversationSnapshot(conversationID: resumed.conversationID,
            hostID: resumed.hostID, ownerClientID: resumed.ownerClientID,
            connectionEpoch: resumed.connectionEpoch, revision: 999,
            streamGeneration: completed.streamGeneration, conversationState: try data(staleState),
            supportsUntrustedAppInput: true, requests: [])
        try apply(model, stale)
        XCTAssertEqual(model.tasks[0].requests.filter { $0.value.canRespond }.count, 1)
        let pending = try XCTUnwrap(model.tasks[0].requests.first?.value.protocolRequest)
        if async { XCTAssertEqual(pending.questions.first?.options.count, 2) }
        else { XCTAssertEqual(pending.actions.count, 4) }
        let staleRevision = CodexDesktopConversationSnapshot(conversationID: resumed.conversationID,
            hostID: resumed.hostID, ownerClientID: resumed.ownerClientID,
            connectionEpoch: resumed.connectionEpoch, revision: 0,
            streamGeneration: resumed.streamGeneration, conversationState: try data(staleState),
            supportsUntrustedAppInput: true, requests: [])
        try apply(model, staleRevision)
        try apply(model, resumed) // Duplicate snapshots must not reset the request.
        XCTAssertEqual(model.tasks[0].requests.filter { $0.value.canRespond }.count, 1)
        count = await recorder.count
        fixture.setState(state(turn: "turn2", async: async), revision: 101)
        try apply(model, await recorder.wait(after: count))
        let recovered = model.tasks[0].requests.filter { $0.value.canRespond }.count
        XCTAssertEqual(recovered, 1)
        XCTAssertTrue(fixture.submissions.isEmpty)
        await client.stop()
    }
    @MainActor func testAsyncQuestionAfterRevisionReset() async throws { try await check(async: true) }
    @MainActor func testCommandApprovalAfterRevisionReset() async throws { try await check(async: false) }
}
