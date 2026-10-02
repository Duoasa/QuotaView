import Foundation
import XCTest
@testable import QuotaView
@testable import QuotaViewCore

final class DesktopRequestLifecycleSmokeTests: XCTestCase {
    private func request(_ id: Any = 42, method: String = "item/commandExecution/requestApproval", item: String? = "item") -> [String: Any] {
        var request = CodexDesktopIPCClientTests.request(id: id, method: method)
        var params = request["params"] as! [String: Any]
        params["availableDecisions"] = ["accept", "decline"]
        if let item { params["itemId"] = item } else { params.removeValue(forKey: "itemId") }
        request["params"] = params; return request
    }
    private func projection(_ snapshot: CodexDesktopConversationSnapshot) throws -> CodexDesktopInteractionProjection {
        try CodexDesktopRequestProjector.project(conversationID: snapshot.conversationID, conversationStateData: snapshot.conversationState)
    }
    @MainActor
    private func model(_ snapshot: CodexDesktopConversationSnapshot, client: CodexDesktopIPCClient) -> IslandLiveStore {
        let model = IslandLiveStore()
        model.receiveLegacy(.init(event: .userPromptSubmit,
            sessionHash: CodexActivityPrivacy.hashIdentifier(snapshot.conversationID),
            turnHash: CodexActivityPrivacy.hashIdentifier("turn"), sessionKind: .user, source: .appServer))
        model.setDesktopConnection(connected: true, epoch: snapshot.connectionEpoch)
        model.responseCapability = { $0.desktopHandle != nil }
        model.respond = { wire, result in
            _ = try await client.submit(handle: try XCTUnwrap(wire.desktopHandle), result: result.data)
        }
        return model
    }
    @MainActor
    private func apply(_ model: IslandLiveStore, _ snapshot: CodexDesktopConversationSnapshot) throws {
        model.receiveDesktopProjection(try projection(snapshot), snapshot: snapshot)
    }
    @MainActor
    private func wait(_ predicate: () -> Bool) async throws {
        for _ in 0..<200 { if predicate() { return }; try await Task.sleep(nanoseconds: 5_000_000) }
        throw CodexDesktopIPCError.unavailable
    }

    @MainActor
    func testNativeCommandWithoutAvailableDecisionsExposesSchemaActionsAndDispatches() async throws {
        let raw: [String: Any] = ["id": 42, "method": "item/commandExecution/requestApproval",
            "params": ["threadId": "conversation", "turnId": "turn", "itemId": "command", "kind": "command",
                       "command": "swift build", "cwd": "/fixture/project", "reason": "Build the current project"]]
        XCTAssertTrue(try IslandCodexApprovalRequest(data: CodexDesktopIPCClientTests.data(raw)).actions.isEmpty,
                      "The compatibility default never grants an observer response capability")
        let fixture = CodexDesktopIPCFixture(state: CodexDesktopIPCClientTests.state(requests: [raw]))
        let (client, _, snapshot) = try await fixture.connectedClient()
        let model = model(snapshot, client: client); try apply(model, snapshot)
        let pending = try XCTUnwrap(model.tasks[0].requests.first)
        let wire = try XCTUnwrap(pending.value.protocolRequest)
        XCTAssertTrue(pending.value.canRespond)
        XCTAssertEqual(wire.actions.map { $0.result["decision"].text }, ["accept", "acceptForSession", "decline", "cancel"])
        XCTAssertFalse(wire.actions.contains { $0.result["decision"].object != nil })
        model.submit(model.tasks[0].id, requestID: pending.value.id,
                     decision: .reply(.object(["decision": .string("acceptForSession")])))
        try await wait { model.tasks[0].requests[0].value.phase == .sent }
        let submitted = try XCTUnwrap(fixture.submissions.first?["params"] as? [String: Any])
        XCTAssertEqual(submitted["decision"] as? String, "acceptForSession")
        await client.stop()
    }

    @MainActor
    func testNativeFileChangeWithoutAvailableDecisionsExposesSchemaActionsAndDispatches() async throws {
        let raw: [String: Any] = ["id": "file-approval", "method": "item/fileChange/requestApproval",
            "params": ["threadId": "conversation", "turnId": "turn", "itemId": "file", "reason": "Apply the requested changes",
                       "grantRoot": "/fixture/project"]]
        let fixture = CodexDesktopIPCFixture(state: CodexDesktopIPCClientTests.state(requests: [raw]))
        let (client, _, snapshot) = try await fixture.connectedClient()
        let model = model(snapshot, client: client); try apply(model, snapshot)
        let pending = try XCTUnwrap(model.tasks[0].requests.first)
        let wire = try XCTUnwrap(pending.value.protocolRequest)
        XCTAssertTrue(pending.value.canRespond)
        XCTAssertEqual(wire.actions.map { $0.result["decision"].text }, ["accept", "acceptForSession", "decline", "cancel"])
        XCTAssertFalse(wire.actions.contains { $0.result["decision"].object != nil })
        model.submit(model.tasks[0].id, requestID: pending.value.id,
                     decision: .reply(.object(["decision": .string("decline")])))
        try await wait { model.tasks[0].requests[0].value.phase == .sent }
        let submitted = try XCTUnwrap(fixture.submissions.first?["params"] as? [String: Any])
        XCTAssertEqual(submitted["decision"] as? String, "decline")
        await client.stop()
    }

    @MainActor
    func testNativeProposedAmendmentsRemainExactAndExplicitFutureDecisionsConstrainActions() async throws {
        var raw: [String: Any] = ["id": 42, "method": "item/commandExecution/requestApproval", "params": [
            "threadId": "conversation", "turnId": "turn", "itemId": "command", "command": "swift build",
            "proposedExecpolicyAmendment": ["swift", "build"],
            "proposedNetworkPolicyAmendments": [["action": "allow", "host": "example.com"], ["action": "deny", "host": "blocked.example"]]]]
        let fixture = CodexDesktopIPCFixture(state: CodexDesktopIPCClientTests.state(requests: [raw]))
        let (client, recorder, snapshot) = try await fixture.connectedClient()
        let model = model(snapshot, client: client); try apply(model, snapshot)
        var wire = try XCTUnwrap(model.tasks[0].requests.first?.value.protocolRequest)
        let exec: IslandApprovalJSON = .object(["decision": .object(["acceptWithExecpolicyAmendment": .object([
            "execpolicy_amendment": .array([.string("swift"), .string("build")])])])])
        let network: IslandApprovalJSON = .object(["decision": .object(["applyNetworkPolicyAmendment": .object([
            "network_policy_amendment": .object(["action": .string("deny"), "host": .string("blocked.example")])])])])
        XCTAssertEqual(wire.actions.count, 7)
        XCTAssertTrue(wire.actions.contains { $0.result == exec })
        XCTAssertTrue(wire.actions.contains { $0.result == network && !$0.affirmative })
        var params = raw["params"] as! [String: Any]
        params["availableDecisions"] = ["decline", "futureUnsupportedDecision"]
        raw["params"] = params
        var count = await recorder.count
        fixture.setState(CodexDesktopIPCClientTests.state(requests: [raw]), revision: 8)
        try apply(model, await recorder.wait(after: count))
        wire = try XCTUnwrap(model.tasks[0].requests.first?.value.protocolRequest)
        XCTAssertEqual(wire.actions.map { $0.result["decision"].text }, ["decline"])
        XCTAssertFalse(wire.permits(exec))
        XCTAssertFalse(wire.permits(.object(["decision": .string("accept")])))
        params["availableDecisions"] = [String]()
        raw["params"] = params
        count = await recorder.count
        fixture.setState(CodexDesktopIPCClientTests.state(requests: [raw]), revision: 9)
        try apply(model, await recorder.wait(after: count))
        XCTAssertTrue(model.tasks[0].requests[0].value.protocolRequest?.actions.isEmpty == true)
        XCTAssertFalse(model.tasks[0].requests[0].value.canRespond)
        await client.stop()
    }

    @MainActor
    func testDesktopCapabilityUpgradesObserverAndAckDoesNotResolveOrSubmitTwice() async throws {
        let raw = request()
        let fixture = CodexDesktopIPCFixture(state: CodexDesktopIPCClientTests.state(requests: [raw]))
        let (client, recorder, snapshot) = try await fixture.connectedClient()
        let model = model(snapshot, client: client)
        model.receive(CodexDesktopIPCClientTests.data(raw))
        let original = try XCTUnwrap(model.tasks[0].requests.first?.value.id)
        XCTAssertFalse(model.tasks[0].requests[0].value.canRespond)
        try apply(model, snapshot)
        XCTAssertEqual(model.tasks[0].requests.count, 1)
        XCTAssertEqual(model.tasks[0].requests[0].value.id, original)
        XCTAssertTrue(model.tasks[0].requests[0].value.canRespond)
        XCTAssertNil(model.tasks[0].requests[0].rpcEpoch, "Desktop does not reuse Shared RPC epoch ownership")
        model.setConnection(.discovering)
        XCTAssertTrue(model.tasks[0].requests[0].value.canRespond, "Shared observer reconnect cannot revoke Desktop ownership")
        let decision = IslandConfirmationDecision.reply(.object(["decision": .string("accept")]))
        model.submit(model.tasks[0].id, requestID: original, decision: decision)
        model.submit(model.tasks[0].id, requestID: original, decision: decision)
        try await wait { model.tasks[0].requests[0].value.phase == .sent }
        XCTAssertEqual(fixture.submissions.count, 1)
        XCTAssertEqual(model.tasks[0].requests.count, 1, "Dispatch acknowledgement is not owner settlement")
        let count = await recorder.count
        fixture.setState(CodexDesktopIPCClientTests.state(requests: []), revision: 8)
        try apply(model, await recorder.wait(after: count))
        XCTAssertTrue(model.tasks[0].requests.isEmpty)
        await client.stop()
    }

    @MainActor
    func testOwnerSettlementKeepsParallelRPCAndIndependentAsyncQuestion() async throws {
        let a = request(1, item: "a"), b = request(2, method: "item/tool/requestUserInput", item: "b")
        let async: [String: Any] = ["type": "agentMessage", "id": "async", "questions": [["title": "Async?", "options": ["Later"]]]]
        let fixture = CodexDesktopIPCFixture(state: CodexDesktopIPCClientTests.state(requests: [a, b], items: [async]))
        let (client, recorder, snapshot) = try await fixture.connectedClient()
        let model = model(snapshot, client: client); try apply(model, snapshot)
        var remaining: [Bool] = []
        model.desktopRequestSettlementDidReceive = { _, _, _, waiting in remaining.append(waiting) }
        XCTAssertEqual(model.tasks[0].requests.count, 3)
        XCTAssertEqual(model.tasks[0].status, .waiting)
        var count = await recorder.count
        fixture.setState(CodexDesktopIPCClientTests.state(requests: [b], items: [async]), revision: 8)
        try apply(model, await recorder.wait(after: count))
        XCTAssertEqual(model.tasks[0].requests.count, 2)
        XCTAssertEqual(model.tasks[0].status, .waiting)
        count = await recorder.count
        fixture.setState(CodexDesktopIPCClientTests.state(requests: [], items: [async]), revision: 9)
        try apply(model, await recorder.wait(after: count))
        XCTAssertEqual(model.tasks[0].requests.count, 1)
        XCTAssertEqual(model.tasks[0].requests[0].mode, .asynchronous)
        XCTAssertNotEqual(model.tasks[0].status, .waiting)
        XCTAssertEqual(remaining, [true, false])
        model.receiveLegacy(.init(event: .permissionRequest,
            sessionHash: CodexActivityPrivacy.hashIdentifier("conversation"), turnHash: CodexActivityPrivacy.hashIdentifier("turn"),
            sessionKind: .user, source: .hook, toolCallHash: CodexActivityPrivacy.hashIdentifier("b")))
        XCTAssertEqual(model.tasks[0].requests.count, 1, "A late Hook cannot resurrect the answered synchronous question")
        await client.stop()
    }

    @MainActor
    func testEarlySharedWaitAndNoItemRPCBindToDesktopIdentityThenSettle() async throws {
        let raw = request(item: nil)
        let fixture = CodexDesktopIPCFixture(state: CodexDesktopIPCClientTests.state(requests: [raw]))
        let (client, recorder, snapshot) = try await fixture.connectedClient()
        var models: [IslandLiveStore] = []
        for sharedRPC in [false, true] {
            let model = model(snapshot, client: client)
            model.receiveLegacy(.init(event: .permissionRequest,
                sessionHash: CodexActivityPrivacy.hashIdentifier("conversation"), turnHash: CodexActivityPrivacy.hashIdentifier("turn"),
                sessionKind: .user, source: .appServer, waitReason: .approval))
            model.receive(CodexDesktopIPCClientTests.data(["method": "thread/status/changed", "_quotaViewConnectionEpoch": 9,
                "params": ["threadId": "conversation", "turnId": "turn", "status": ["type": "active", "activeFlags": ["waitingOnApproval"]]]]))
            if sharedRPC {
                var envelope = raw; envelope["_quotaViewConnectionEpoch"] = 9
                model.receive(CodexDesktopIPCClientTests.data(envelope))
            }
            let original = model.tasks[0].requests.first?.value.id
            try apply(model, snapshot)
            if sharedRPC { XCTAssertEqual(model.tasks[0].requests[0].value.id, original) }
            XCTAssertTrue(model.tasks[0].waitingOnSource)
            models.append(model)
        }
        let count = await recorder.count
        fixture.setState(CodexDesktopIPCClientTests.state(requests: []), revision: 8)
        let settled = try await recorder.wait(after: count)
        for model in models {
            try apply(model, settled)
            XCTAssertTrue(model.tasks[0].requests.isEmpty)
            XCTAssertFalse(model.tasks[0].waitingOnSource, "No duplicate/old RPC wait alias remains")
            XCTAssertNotEqual(model.tasks[0].status, .waiting)
        }
        await client.stop()
    }

    @MainActor
    func testLargeIntegerAndStringRequestIDsStayDistinctAndReplyPreservesExactID() async throws {
        let first: Int64 = 9_007_199_254_740_992, second: Int64 = 9_007_199_254_740_993
        let a = request(first, item: nil), b = request(second, item: nil), c = request(String(first), item: nil)
        let fixture = CodexDesktopIPCFixture(state: CodexDesktopIPCClientTests.state(requests: [a, b, c]))
        let (client, recorder, snapshot) = try await fixture.connectedClient()
        let model = model(snapshot, client: client); try apply(model, snapshot)
        XCTAssertEqual(model.tasks[0].requests.count, 3)
        XCTAssertEqual(Set(model.tasks[0].requests.map(\.key)).count, 3)
        let chosen = try XCTUnwrap(model.tasks[0].requests.first { $0.value.protocolRequest?.desktopHandle?.requestID == .integer(second) })
        model.submit(model.tasks[0].id, requestID: chosen.value.id, decision: .reply(.object(["decision": .string("accept")])))
        try await wait { model.tasks[0].requests.contains { $0.value.id == chosen.value.id && $0.value.phase == .sent } }
        let sent = try XCTUnwrap(fixture.submissions.first?["params"] as? [String: Any])
        XCTAssertEqual((sent["requestId"] as? NSNumber)?.int64Value, second)
        let count = await recorder.count
        fixture.setState(CodexDesktopIPCClientTests.state(requests: [b, c]), revision: 8)
        try apply(model, await recorder.wait(after: count))
        XCTAssertEqual(model.tasks[0].requests.count, 2)
        XCTAssertTrue(model.tasks[0].requests.contains { $0.value.protocolRequest?.desktopHandle?.requestID == .integer(second) })
        XCTAssertTrue(model.tasks[0].requests.contains { $0.value.protocolRequest?.desktopHandle?.requestID == .string(String(first)) })
        await client.stop()
    }

    @MainActor
    func testParallelRPCsSharingItemKeepIndependentIdentityAndCapability() async throws {
        let a = request(1, item: "shared-item"), b = request(2, item: "shared-item")
        let fixture = CodexDesktopIPCFixture(state: CodexDesktopIPCClientTests.state(requests: [a, b]))
        let (client, recorder, snapshot) = try await fixture.connectedClient()
        let model = model(snapshot, client: client); try apply(model, snapshot)
        XCTAssertEqual(model.tasks[0].requests.count, 2)
        let original = try XCTUnwrap(model.tasks[0].requests.first { $0.value.protocolRequest?.desktopHandle?.requestID == .integer(2) }?.value.id)
        var count = await recorder.count
        fixture.setState(CodexDesktopIPCClientTests.state(requests: [b]), revision: 8)
        try apply(model, await recorder.wait(after: count))
        XCTAssertEqual(model.tasks[0].requests.count, 1)
        XCTAssertEqual(model.tasks[0].requests[0].value.id, original)
        XCTAssertFalse(model.tasks[0].requestLifecycle.resolvedCallHashes.contains(CodexActivityPrivacy.hashIdentifier("shared-item")))
        model.setDesktopConnection(connected: false, epoch: nil)
        await client.stop()
        count = await recorder.count
        await client.start(snapshotHandler: { await recorder.record($0) }, stateHandler: { await recorder.recordState($0) })
        try await client.follow(conversationID: "conversation")
        let fresh = try await recorder.wait(after: count)
        model.setDesktopConnection(connected: true, epoch: fresh.connectionEpoch); try apply(model, fresh)
        XCTAssertEqual(model.tasks[0].requests[0].value.id, original)
        XCTAssertTrue(model.tasks[0].requests[0].value.canRespond)
        await client.stop()
    }

    @MainActor
    func testRawJSONAndLocalQuestionsCannotAcquireDesktopCapability() async throws {
        let fixture = CodexDesktopIPCFixture(state: CodexDesktopIPCClientTests.state(requests: [request()]))
        let (client, _, snapshot) = try await fixture.connectedClient()
        let handle = try XCTUnwrap(snapshot.requests.first)
        let parsed = try IslandCodexApprovalRequest(data: handle.rawRequest)
        XCTAssertNil(parsed.desktopHandle)
        var wrong = request("42")
        wrong["desktopHandle"] = ["ownerClientID": "fixture-owner", "nonce": "pretend"]
        XCTAssertNil(try IslandCodexApprovalRequest(data: CodexDesktopIPCClientTests.data(wrong)).attachingDesktopHandle(handle).desktopHandle)
        let local = try IslandCodexApprovalRequest(localQuestions: [["id": "q", "question": "Local?"]], callID: "item", sessionHash: "conversation", turnHash: "turn")
        XCTAssertNil(local.attachingDesktopHandle(handle).desktopHandle)
        await client.stop()
    }

    @MainActor
    func testAuthoritativeDesktopAsyncSetSupersedesOnlySameTurnReadonlyAsyncObservations() async throws {
        let native: [String: Any] = ["type": "agentMessage", "id": "native-message", "questions": [
            ["title": "Native first?", "options": ["A", "B"]], ["title": "Native second?", "options": ["Later"]]]]
        let fixture = CodexDesktopIPCFixture(state: CodexDesktopIPCClientTests.state(requests: [], items: [native]))
        let (client, recorder, snapshot) = try await fixture.connectedClient()
        let model = model(snapshot, client: client)
        func local(_ call: String, session: String = "conversation", async: Bool = true) throws -> CodexLocalPublicContent {
            let questions: [[String: Any]] = async ? [["title": "Rollout source?", "options": ["A", "B"]]]
                : [["id": "sync", "question": "Independent synchronous?", "options": [["label": "Yes"]]]]
            let args = String(decoding: CodexDesktopIPCClientTests.data(["questions": questions]), as: UTF8.self)
            let line = CodexDesktopIPCClientTests.data(["type": "response_item", "payload": ["type": "function_call",
                "name": async ? "functions.request_user_input_async" : "functions.request_user_input", "call_id": call, "arguments": args]])
            return try XCTUnwrap(CodexLocalPublicContent.decode(line, sessionHash: CodexActivityPrivacy.hashIdentifier(session),
                                                               activeTurnHash: CodexActivityPrivacy.hashIdentifier("turn")))
        }
        let leading = try local("rollout-launch-id")
        model.receiveLocalContent(leading)
        model.receiveLocalContent(try local("independent-sync", async: false))
        model.receiveLegacy(.init(event: .userPromptSubmit, sessionHash: CodexActivityPrivacy.hashIdentifier("other"),
            turnHash: CodexActivityPrivacy.hashIdentifier("turn"), sessionKind: .user, source: .appServer))
        model.receiveLocalContent(try local("other-async", session: "other"))
        let full = try projection(snapshot)
        let partial = CodexDesktopInteractionProjection(currentTurnID: full.currentTurnID, status: full.status, title: full.title,
            sourceKind: full.sourceKind, startedAt: full.startedAt, requests: full.requests,
            authoritativePendingIdentities: full.authoritativePendingIdentities, pendingRequestsAreAuthoritative: false,
            asyncQuestions: full.asyncQuestions, authoritativeAsyncQuestionIDs: full.authoritativeAsyncQuestionIDs)
        model.receiveDesktopProjection(partial, snapshot: snapshot)
        XCTAssertTrue(model.tasks[0].requests.contains { $0.value.protocolRequest?.localObservation?.asynchronous == true },
                      "A partial owner projection cannot discard another source")
        try apply(model, snapshot)
        XCTAssertEqual(model.tasks[0].requests.count, 3, "Two real native questions plus the independent local synchronous request")
        XCTAssertFalse(model.tasks[0].requests.contains { $0.value.protocolRequest?.localObservation?.asynchronous == true })
        XCTAssertEqual(model.tasks[1].requests.count, 1, "Authority is scoped to one task and turn")
        let first = try XCTUnwrap(full.asyncQuestions.first)
        let answer = String(decoding: CodexDesktopIPCClientTests.data([["questionItemId": first.questionItemID,
            "question": first.question, "answer": "A"]]), as: UTF8.self)
        let reply: [String: Any] = ["type": "steeringUserMessage", "id": "external-reply", "status": "accepted", "input": [[
            "type": "text", "text": CodexDesktopRequestProjector.asyncReplyOpeningTag + answer + CodexDesktopRequestProjector.asyncReplyClosingTag]]]
        let count = await recorder.count
        fixture.setState(CodexDesktopIPCClientTests.state(requests: [], items: [native, reply]), revision: 8)
        try apply(model, await recorder.wait(after: count))
        XCTAssertEqual(model.tasks[0].requests.count, 2, "Only the exact answered native question disappears")
        model.receiveLocalContent(leading)
        XCTAssertEqual(model.tasks[0].requests.count, 2, "Late rollout replay cannot resurrect the superseded async presentation")
        XCTAssertFalse(model.tasks[0].requestLifecycle.resolvedCallHashes.contains(CodexActivityPrivacy.hashIdentifier("rollout-launch-id")),
                       "Source replacement does not invent an answered-call tombstone")
        await client.stop()
    }

    @MainActor
    func testNativeAsyncQuestionReplyStaysNonblockingUntilExactOwnerReply() async throws {
        let async: [String: Any] = ["type": "agentMessage", "id": "async/source", "questions": [["title": "Which?", "options": ["A", "B"]]]]
        let fixture = CodexDesktopIPCFixture(state: CodexDesktopIPCClientTests.state(requests: [], items: [async]))
        let (client, recorder, snapshot) = try await fixture.connectedClient()
        let model = model(snapshot, client: client); try apply(model, snapshot)
        let pending = try XCTUnwrap(model.tasks[0].requests.first)
        let wire = try XCTUnwrap(pending.value.protocolRequest)
        XCTAssertEqual(wire.desktopHandle?.kind, .asynchronousQuestion)
        XCTAssertEqual(wire.userInputMode, .asynchronous)
        XCTAssertNotEqual(model.tasks[0].status, .waiting)
        let questionID = try XCTUnwrap(wire.questions.first?.id)
        var draft = IslandApprovalDraft(); draft.selections[questionID] = ["A"]
        model.submit(model.tasks[0].id, requestID: pending.value.id, decision: .reply(try XCTUnwrap(draft.result(for: wire))))
        try await wait { model.tasks[0].requests[0].value.phase == .sent }
        XCTAssertEqual(model.tasks[0].requests.count, 1)
        XCTAssertNotEqual(model.tasks[0].status, .waiting)
        let command = try XCTUnwrap(fixture.submissions.first)
        XCTAssertEqual(command["method"] as? String, "thread-follower-steer-turn")
        let params = try XCTUnwrap(command["params"] as? [String: Any])
        XCTAssertNil(params["requestId"], "Async question identity is not a pending RPC")
        let input = try XCTUnwrap(params["input"] as? [[String: Any]])
        let reply: [String: Any] = ["type": "steeringUserMessage", "id": "reply", "status": "accepted", "input": input]
        let count = await recorder.count
        fixture.setState(CodexDesktopIPCClientTests.state(requests: [], items: [async, reply]), revision: 8)
        try apply(model, await recorder.wait(after: count))
        XCTAssertTrue(model.tasks[0].requests.isEmpty)
        await client.stop()
    }

    @MainActor
    func testScopedResourceInvalidationPreservesWaitAndOtherConversationCapability() async throws {
        let fixtureA = CodexDesktopIPCFixture(state: CodexDesktopIPCClientTests.state(requests: [request()]))
        var rawB = request(99, item: "other-item")
        var paramsB = rawB["params"] as! [String: Any]; paramsB["threadId"] = "other"; rawB["params"] = paramsB
        var stateB = CodexDesktopIPCClientTests.state(requests: [rawB]); stateB["id"] = "other"
        let fixtureB = CodexDesktopIPCFixture(state: stateB)
        let (clientA, _, snapshotA) = try await fixtureA.connectedClient()
        let (clientB, _, snapshotB) = try await fixtureB.connectedClient()
        XCTAssertEqual(snapshotA.connectionEpoch, snapshotB.connectionEpoch)
        let model = model(snapshotA, client: clientA); try apply(model, snapshotA)
        model.receiveLegacy(.init(event: .userPromptSubmit, sessionHash: CodexActivityPrivacy.hashIdentifier("other"),
            turnHash: CodexActivityPrivacy.hashIdentifier("turn"), sessionKind: .user, source: .appServer))
        try apply(model, snapshotB)
        let a = try XCTUnwrap(model.tasks.first { $0.key == CodexActivityPrivacy.hashIdentifier("conversation") })
        let b = try XCTUnwrap(model.tasks.first { $0.key == CodexActivityPrivacy.hashIdentifier("other") })
        let requestA = try XCTUnwrap(a.requests.first?.value.id), requestB = try XCTUnwrap(b.requests.first?.value.id)
        let gate = DesktopLifecycleSubmissionGate()
        model.respond = { wire, result in
            _ = try await clientA.submit(handle: try XCTUnwrap(wire.desktopHandle), result: result.data)
            try await gate.hold()
        }
        model.submit(a.id, requestID: requestA, decision: .reply(.object(["decision": .string("accept")])))
        try await gate.waitUntilEntered()
        model.invalidateDesktopResponses(conversationID: "conversation", epoch: snapshotA.connectionEpoch + 1)
        XCTAssertTrue(model.tasks.first { $0.id == a.id }!.requests[0].value.canRespond, "An invalidation from another connection is ignored")
        model.invalidateDesktopResponses(conversationID: "conversation", epoch: snapshotA.connectionEpoch)
        var currentA = try XCTUnwrap(model.tasks.first { $0.id == a.id })
        let currentB = try XCTUnwrap(model.tasks.first { $0.id == b.id })
        XCTAssertEqual(currentA.requests.first?.value.id, requestA)
        XCTAssertEqual(currentA.status, .waiting)
        XCTAssertFalse(currentA.requests[0].value.canRespond)
        XCTAssertEqual(currentA.requests[0].value.phase, .resultUnknown)
        XCTAssertEqual(currentB.requests.first?.value.id, requestB)
        XCTAssertTrue(currentB.requests[0].value.canRespond)
        XCTAssertEqual(currentB.status, .waiting)
        XCTAssertTrue(currentA.requestLifecycle.resolvedCallHashes.isEmpty, "Resource loss is not an answered-call tombstone")
        await gate.release(fail: false)
        try await Task.sleep(nanoseconds: 10_000_000)
        currentA = try XCTUnwrap(model.tasks.first { $0.id == a.id })
        XCTAssertEqual(currentA.requests[0].value.phase, .resultUnknown, "A late dispatch ACK cannot undo capability revocation")
        await clientA.stop(); await clientB.stop()
    }

    @MainActor
    func testOldConnectionAwaitAndCatchCannotOverwriteRefreshedRequest() async throws {
        for fail in [false, true] {
            let fixture = CodexDesktopIPCFixture(state: CodexDesktopIPCClientTests.state(requests: [request()]))
            let (client, recorder, snapshot) = try await fixture.connectedClient()
            let model = model(snapshot, client: client); try apply(model, snapshot)
            let original = try XCTUnwrap(model.tasks[0].requests.first?.value.id)
            let gate = DesktopLifecycleSubmissionGate()
            model.respond = { wire, result in
                _ = try await client.submit(handle: try XCTUnwrap(wire.desktopHandle), result: result.data)
                try await gate.hold()
            }
            model.submit(model.tasks[0].id, requestID: original, decision: .reply(.object(["decision": .string("accept")])))
            try await gate.waitUntilEntered()
            model.setDesktopConnection(connected: false, epoch: nil)
            await client.stop()
            let count = await recorder.count
            await client.start(snapshotHandler: { await recorder.record($0) }, stateHandler: { await recorder.recordState($0) })
            try await client.follow(conversationID: "conversation")
            let fresh = try await recorder.wait(after: count)
            XCTAssertNotEqual(fresh.connectionEpoch, snapshot.connectionEpoch)
            model.setDesktopConnection(connected: true, epoch: fresh.connectionEpoch); try apply(model, fresh)
            XCTAssertEqual(model.tasks[0].requests[0].value.id, original)
            XCTAssertTrue(model.tasks[0].requests[0].value.canRespond)
            XCTAssertEqual(model.tasks[0].requests[0].value.phase, .resultUnknown)
            await gate.release(fail: fail)
            try await Task.sleep(nanoseconds: 10_000_000)
            XCTAssertEqual(model.tasks[0].requests[0].value.phase, .resultUnknown)
            XCTAssertTrue(model.tasks[0].requests[0].value.canRespond, "A stale catch cannot disable the fresh handle")
            await client.stop()
        }
    }
}

private actor DesktopLifecycleSubmissionGate {
    private var entered = false
    private var continuation: CheckedContinuation<Void, Error>?
    func hold() async throws { entered = true; try await withCheckedThrowingContinuation { continuation = $0 } }
    func waitUntilEntered() async throws {
        for _ in 0..<200 { if entered { return }; try await Task.sleep(nanoseconds: 5_000_000) }
        throw CodexDesktopIPCError.unavailable
    }
    func release(fail: Bool) {
        if fail { continuation?.resume(throwing: CodexDesktopIPCError.outcomeUnknown) }
        else { continuation?.resume() }
        continuation = nil
    }
}
