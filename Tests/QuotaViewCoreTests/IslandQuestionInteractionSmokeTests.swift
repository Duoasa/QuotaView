import Foundation
import XCTest
@testable import QuotaView
@testable import QuotaViewCore

final class IslandQuestionInteractionSmokeTests: XCTestCase {
    private func synchronous(multiple: Bool = false) -> [String: Any] {
        ["id": "input", "method": "item/tool/requestUserInput", "params": [
            "threadId": "conversation", "turnId": "turn", "itemId": "question-item",
            "questions": [["id": "q", "question": "Choose?", "isOther": true,
                "multiSelect": multiple, "options": [["label": "A"], ["label": "B"]]]]]]
    }
    private func asyncQuestion(_ id: String) -> [String: Any] {
        ["type": "agentMessage", "id": id, "questions": [["title": "Choose?", "options": ["A", "B"]]]]
    }
    @MainActor private func model(_ snapshot: CodexDesktopConversationSnapshot, client: CodexDesktopIPCClient) throws -> IslandLiveStore {
        let model = IslandLiveStore()
        model.receiveLegacy(.init(event: .userPromptSubmit,
            sessionHash: CodexActivityPrivacy.hashIdentifier("conversation"),
            turnHash: CodexActivityPrivacy.hashIdentifier("turn"), sessionKind: .user, source: .appServer))
        model.setDesktopConnection(connected: true, epoch: snapshot.connectionEpoch)
        model.responseCapability = { $0.desktopHandle != nil }
        model.respond = { wire, result in
            _ = try await client.submit(handle: try XCTUnwrap(wire.desktopHandle), result: result.data)
        }
        try apply(model, snapshot)
        return model
    }
    @MainActor private func apply(_ model: IslandLiveStore, _ snapshot: CodexDesktopConversationSnapshot) throws {
        model.receiveDesktopProjection(try CodexDesktopRequestProjector.project(
            conversationID: snapshot.conversationID, conversationStateData: snapshot.conversationState), snapshot: snapshot)
    }
    @MainActor private func wait(_ predicate: () -> Bool) async throws {
        for _ in 0..<200 { if predicate() { return }; try await Task.sleep(nanoseconds: 5_000_000) }
        throw CodexDesktopIPCError.unavailable
    }

    @MainActor func testChoiceAndCustomDraftNeverDispatchUntilExplicitConfirmation() async throws {
        let fixture = CodexDesktopIPCFixture(state: CodexDesktopIPCClientTests.state(requests: [synchronous()]))
        let (client, _, snapshot) = try await fixture.connectedClient()
        let model = try model(snapshot, client: client)
        let pending = try XCTUnwrap(model.tasks[0].requests.first)
        let wire = try XCTUnwrap(pending.value.protocolRequest)
        let q = try XCTUnwrap(wire.questions.first)
        XCTAssertTrue(pending.value.canRespond)
        var draft = IslandApprovalDraft()
        XCTAssertNil(draft.result(for: wire))
        draft.selectAnswer("A", for: q)
        XCTAssertEqual(draft.answer(for: q), "A")
        draft.selectAnswer("B", for: q)
        XCTAssertEqual(draft.answer(for: q), "B")
        draft.selectCustomAnswer(for: q)
        XCTAssertTrue(draft.usesCustomAnswer(for: q))
        XCTAssertNil(draft.result(for: wire), "Selecting custom input without text is not a valid answer")
        let typed = "自己的回答\nwith exact whitespace  "
        draft.setAnswer(typed, for: q)
        draft.selectAnswer("A", for: q)
        XCTAssertFalse(draft.usesCustomAnswer(for: q))
        XCTAssertEqual(draft.answer(for: q), "A")
        draft.selectCustomAnswer(for: q)
        XCTAssertEqual(draft.answer(for: q), typed, "Changing choices keeps the user's typed draft")
        try apply(model, snapshot)
        XCTAssertEqual(model.tasks[0].requests[0].value.id, pending.value.id)
        XCTAssertEqual(model.tasks[0].requests[0].value.phase, .ready)
        XCTAssertTrue(fixture.submissions.isEmpty)
        let result = try XCTUnwrap(draft.result(for: wire))
        XCTAssertTrue(wire.permits(result))
        model.submit(model.tasks[0].id, requestID: pending.value.id, decision: .reply(result))
        try await wait { model.tasks[0].requests.first?.value.phase == .sent }
        model.submit(model.tasks[0].id, requestID: pending.value.id, decision: .reply(result))
        XCTAssertEqual(fixture.submissions.count, 1)
        let params = try XCTUnwrap(fixture.submissions.first?["params"] as? [String: Any])
        let response = try XCTUnwrap(params["response"] as? [String: Any])
        let answers = try XCTUnwrap(response["answers"] as? [String: [String: [String]]])
        XCTAssertEqual(answers["q"]?["answers"], [typed])
        XCTAssertEqual(model.tasks[0].requests.count, 1, "ACK is not authoritative settlement")
        await client.stop()
    }

    @MainActor func testSynchronousSkipDispatchesEmptyAnswersAndWaitsForOwnerRemoval() async throws {
        let fixture = CodexDesktopIPCFixture(state: CodexDesktopIPCClientTests.state(requests: [synchronous()]))
        let (client, recorder, snapshot) = try await fixture.connectedClient()
        let model = try model(snapshot, client: client)
        let pending = try XCTUnwrap(model.tasks[0].requests.first)
        model.submit(model.tasks[0].id, requestID: pending.value.id, decision: .skipQuestion)
        try await wait { model.tasks[0].requests.first?.value.phase == .sent }
        XCTAssertEqual(fixture.submissions.count, 1)
        let params = try XCTUnwrap(fixture.submissions.first?["params"] as? [String: Any])
        let response = try XCTUnwrap(params["response"] as? [String: Any])
        XCTAssertEqual((response["answers"] as? [String: Any])?.count, 0)
        XCTAssertEqual(model.tasks[0].requests.count, 1)
        let count = await recorder.count
        fixture.setState(CodexDesktopIPCClientTests.state(requests: []), revision: 8)
        try apply(model, await recorder.wait(after: count))
        XCTAssertTrue(model.tasks[0].requests.isEmpty)
        await client.stop()
    }

    @MainActor func testAsyncSkipIsPresentationOnlyAndRefreshDoesNotResurrectIt() async throws {
        let blocker = CodexDesktopIPCClientTests.request(id: "approval")
        let first = asyncQuestion("first")
        let fixture = CodexDesktopIPCFixture(state: CodexDesktopIPCClientTests.state(requests: [blocker], items: [first]))
        let (client, recorder, snapshot) = try await fixture.connectedClient()
        let model = try model(snapshot, client: client)
        let pending = try XCTUnwrap(model.tasks[0].requests.first { $0.mode == .asynchronous })
        let wire = try XCTUnwrap(pending.value.protocolRequest)
        let question = try XCTUnwrap(wire.questions.first)
        XCTAssertTrue(question.allowsCustomAnswer)
        XCTAssertNil(wire.questionSkipResult)
        XCTAssertFalse(wire.permits(.object(["answers": .object([:])])))
        model.submit(model.tasks[0].id, requestID: pending.value.id, decision: .skipQuestion)
        XCTAssertTrue(fixture.submissions.isEmpty, "Async Skip never fabricates a user reply")
        XCTAssertEqual(model.tasks[0].requests.count, 1)
        XCTAssertTrue(model.tasks[0].requestLifecycle.hasBlockingRequest)
        XCTAssertTrue(model.tasks[0].requestLifecycle.resolvedCallHashes.isEmpty)
        XCTAssertTrue(model.tasks[0].requestLifecycle.resolvedRequestKeys.isEmpty)
        XCTAssertTrue(model.tasks[0].requestLifecycle.skippedAsyncQuestionIDs.isEmpty,
            "Local retirement does not create a request lifecycle settlement")
        try apply(model, snapshot)
        XCTAssertEqual(model.tasks[0].requests.count, 1)
        let count = await recorder.count
        fixture.setState(CodexDesktopIPCClientTests.state(requests: [blocker], items: [first]), revision: 8)
        try apply(model, await recorder.wait(after: count))
        XCTAssertEqual(model.tasks[0].requests.count, 1, "A new authoritative revision cannot restore the retired async question")
        let refreshedCount = await recorder.count
        fixture.setState(CodexDesktopIPCClientTests.state(requests: [blocker], items: [first, asyncQuestion("second")]), revision: 9)
        try apply(model, await recorder.wait(after: refreshedCount))
        XCTAssertEqual(model.tasks[0].requests.count, 2)
        let next = try XCTUnwrap(model.tasks[0].requests.first { $0.mode == .asynchronous })
        XCTAssertNotEqual(next.value.id, pending.value.id)
        XCTAssertTrue(next.value.canRespond)
        XCTAssertTrue(fixture.submissions.isEmpty)
        await client.stop()
    }

    @MainActor func testUnsupportedQuestionSchemaUsesNativeHandoffDespiteOwnerCapability() async throws {
        let fixture = CodexDesktopIPCFixture(state: CodexDesktopIPCClientTests.state(requests: [synchronous(multiple: true)]))
        let (client, _, snapshot) = try await fixture.connectedClient()
        let model = try model(snapshot, client: client)
        let pending = try XCTUnwrap(model.tasks[0].requests.first)
        let wire = try XCTUnwrap(pending.value.protocolRequest)
        XCTAssertNotNil(wire.desktopHandle)
        XCTAssertFalse(wire.supportedQuestions)
        XCTAssertFalse(pending.value.canRespond)
        var draft = IslandApprovalDraft(); draft.selections["q"] = ["A"]
        XCTAssertNil(draft.result(for: wire))
        model.submit(model.tasks[0].id, requestID: pending.value.id, decision: .skipQuestion)
        XCTAssertTrue(fixture.submissions.isEmpty)
        XCTAssertEqual(model.tasks[0].requests.count, 1)
        await client.stop()
    }

    func testIncompleteQuestionSetAndUnsupportedAnswersCannotBecomeAConfirmation() throws {
        let wire = try IslandApprovalFixtures.request("questions")
        var draft = IslandApprovalDraft()
        draft.selectAnswer("Current module", for: wire.questions[0])
        XCTAssertNil(draft.result(for: wire), "Every required question must have a valid answer")
        draft.setAnswer("Keep existing data", for: wire.questions[1])
        XCTAssertNotNil(draft.result(for: wire))
        draft.selections[wire.questions[0].id] = ["Current module", "invented choice"]
        XCTAssertNil(draft.result(for: wire), "Unknown selections cannot be silently dropped")
        var raw = synchronous()
        var params = raw["params"] as! [String: Any]
        var questions = params["questions"] as! [[String: Any]]
        questions[0]["isOther"] = false
        params["questions"] = questions; raw["params"] = params
        let restricted = try IslandCodexApprovalRequest(data: CodexDesktopIPCClientTests.data(raw))
        draft = IslandApprovalDraft()
        draft.setAnswer("not a listed choice", for: restricted.questions[0])
        XCTAssertFalse(restricted.questions[0].allowsCustomAnswer)
        XCTAssertNil(draft.result(for: restricted))
    }
}
