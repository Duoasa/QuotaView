import Foundation
import XCTest
@testable import QuotaViewCore

final class CodexDesktopRequestProjectionTests: XCTestCase {
    func testExactIntegerAndStringRequestIdentityAndPublicQuestionStructure() throws {
        let data = Data(#"""
        {"id":"thread","source":"appServer","title":"Real title","requests":[
          {"id":9223372036854775807,"method":"item/tool/requestUserInput","params":{"threadId":"thread","turnId":"turn","itemId":"call","questions":[{"id":"question-original","header":"Choice","question":"Continue?","isOther":true,"isSecret":false,"options":[{"label":"Yes","description":"Continue work"},{"label":"No","description":"Stop"}],"privateReasoning":"DO_NOT_FORWARD"}],"privateReasoning":"DO_NOT_FORWARD"}},
          {"id":"9223372036854775807","method":"item/commandExecution/requestApproval","params":{"threadId":"thread","turnId":"turn","command":"swift build","availableDecisions":["accept","decline"]}}
        ],"turns":[{"turnId":"turn","status":"inProgress","turnStartedAtMs":1720000000123,"items":[{"id":"private","type":"reasoning","summary":"DO_NOT_FORWARD"}]}]}
        """#.utf8)
        let projection = try project(data)
        XCTAssertEqual(projection.currentTurnID, "turn")
        XCTAssertEqual(projection.status, "inProgress")
        XCTAssertEqual(projection.title, "Real title")
        XCTAssertEqual(projection.sourceKind, .user)
        XCTAssertEqual(projection.startedAt?.timeIntervalSince1970 ?? 0, 1720000000.123, accuracy: 0.001)
        XCTAssertEqual(projection.requests.map(\.requestID), [.integer(Int64.max), .string(String(Int64.max))])
        XCTAssertEqual(projection.authoritativePendingIdentities.count, 2)
        let question = projection.requests[0]
        XCTAssertEqual(question.userInputMode, .synchronous)
        let envelope = String(decoding: question.envelopeData, as: UTF8.self)
        XCTAssertTrue(envelope.contains("9223372036854775807"))
        XCTAssertTrue(envelope.contains("question-original"))
        XCTAssertTrue(envelope.contains("Continue work"))
        XCTAssertFalse(envelope.contains("DO_NOT_FORWARD"))
        let params = try JSONSerialization.jsonObject(with: question.paramsData) as! [String: Any]
        let questions = params["questions"] as! [[String: Any]]
        XCTAssertEqual(questions[0]["header"] as? String, "Choice")
        XCTAssertEqual(questions[0]["isOther"] as? Bool, true)
    }

    func testCurrentTurnDropsStaleRequestsAndTerminalClearsPending() throws {
        let requests: [[String: Any]] = [rpc(id: "old", turn: "old"), rpc(id: "new", turn: "new")]
        var state = base(requests: requests, turns: [turn("old", status: "inProgress"), turn("new")])
        var projection = try project(state)
        XCTAssertEqual(projection.requests.map(\.requestID), [.string("new")])
        XCTAssertEqual(projection.authoritativePendingIdentities.count, 1)
        XCTAssertTrue(projection.pendingRequestsAreAuthoritative)
        state["turns"] = [turn("old"), turn("new", status: "completed")]
        projection = try project(state)
        XCTAssertEqual(projection.currentTurnID, "new")
        XCTAssertEqual(projection.status, "completed")
        XCTAssertTrue(projection.requests.isEmpty)
        XCTAssertTrue(projection.authoritativePendingIdentities.isEmpty)
        XCTAssertTrue(projection.pendingRequestsAreAuthoritative)
    }

    func testCanonicalLatestTurnAndLiveOverlayKeepPublicFileContext() throws {
        var state = base(requests: [rpc(id: "file", method: "item/fileChange/requestApproval", params: ["itemId": "patch"])], turns: [])
        state["turnHistory"] = ["kind": "canonical", "history": ["islands": [["newerBoundary": ["status": "exhausted"], "entries": [["value": "old-key"], ["value": "current-key"]]]], "entitiesByKey": [
            "old-key": turn("old", status: "completed"),
            "current-key": turn("turn", items: [["id": "patch", "type": "fileChange", "status": "inProgress", "changes": [["path": "src/a.swift", "kind": "update", "diff": "+ public change", "privateReasoning": "PRIVATE"]]]])]]]
        state["turns"] = [turn("turn", items: [["id": "reasoning", "type": "reasoning", "summary": "PRIVATE"]])]
        let projection = try project(state)
        XCTAssertEqual(projection.currentTurnID, "turn")
        let context = String(decoding: try XCTUnwrap(projection.requests.first?.contextItemData), as: UTF8.self)
        XCTAssertTrue(context.contains("src/a.swift")); XCTAssertTrue(context.contains("+ public change"))
        XCTAssertFalse(context.contains("PRIVATE")); XCTAssertFalse(context.contains("reasoning"))
    }

    func testCanonicalNewerBoundaryIncompleteCannotClearRequests() throws {
        var state = base(requests: [], turns: [turn("historical", status: "completed")])
        state["turnHistory"] = ["kind": "canonical", "history": ["islands": [["newerBoundary": ["status": "notLoaded"], "entries": [["value": "historical-key"]]]], "entitiesByKey": ["historical-key": turn("historical", status: "completed")]]]
        let projection = try project(state)
        XCTAssertNil(projection.currentTurnID)
        XCTAssertFalse(projection.pendingRequestsAreAuthoritative)
        XCTAssertEqual(projection.status, "unknown")
    }

    func testCanonicalLiveSuffixStartsNewTurnWithoutRevivingOldRequests() throws {
        var state = base(requests: [rpc(id: "old", turn: "old"), rpc(id: "new", turn: "new")], turns: [turn("old", status: "completed"), turn("new")])
        state["turnHistory"] = ["kind": "canonical", "history": ["islands": [["newerBoundary": ["status": "exhausted"], "entries": [["value": "old-key"]]]], "entitiesByKey": ["old-key": turn("old", status: "completed")]]]
        let projection = try project(state)
        XCTAssertEqual(projection.currentTurnID, "new")
        XCTAssertEqual(projection.requests.map(\.requestID), [.string("new")])
    }

    func testInternalTaskClassificationDoesNotInventUserSession() throws {
        var state = base(requests: [], turns: [turn("turn")])
        state["source"] = ["subagent": ["thread_spawn": ["parent_thread_id": "parent"]]]
        let child = try project(state)
        XCTAssertEqual(child.sourceKind, .subagent)
        XCTAssertNotEqual(child.sourceKind, .user)
        XCTAssertTrue(child.requests.isEmpty)
        state["source"] = "unknown"; state["threadSource"] = NSNull()
        XCTAssertEqual(try project(state).sourceKind, .unknown)
    }

    func testMalformedRequestIdentityAndCrossConversationFailClosed() throws {
        for id: Any in [NSNull(), true, 1.5] {
            XCTAssertThrowsError(try project(base(requests: [rpc(id: id)], turns: [turn("turn")])))
        }
        XCTAssertThrowsError(try project(base(requests: [rpc(id: "cross", params: ["threadId": "other-thread"])], turns: [turn("turn")])))
        let duplicate = rpc(id: "duplicate")
        XCTAssertThrowsError(try project(base(requests: [duplicate, duplicate], turns: [turn("turn")])))
        XCTAssertThrowsError(try project(base(requests: [duplicate, rpc(id: "duplicate", method: "item/fileChange/requestApproval")], turns: [turn("turn")])))
    }

    func testMissingRequestCollectionCannotBecomeAuthoritativeEmptySnapshot() throws {
        var state = base(requests: [], turns: [turn("turn")]); state.removeValue(forKey: "requests")
        XCTAssertThrowsError(try project(state))
        state["requests"] = []; state["id"] = "other"
        XCTAssertThrowsError(try project(state))
    }

    func testUnknownRequestRemainsInAuthoritativeIdentityWithoutInventedActions() throws {
        let projection = try project(base(requests: [rpc(id: "unsupported", method: "future/request")], turns: [turn("turn")]))
        XCTAssertTrue(projection.requests.isEmpty)
        XCTAssertEqual(projection.authoritativePendingIdentities.count, 1)
    }

    func testAsyncQuestionUsesNativeMessageIdentityAndNeverPretendsToBeRPC() throws {
        let message: [String: Any] = ["id": "message/1", "type": "agentMessage", "text": "PRIVATE_TEXT", "questions": [
            ["title": "Which target?", "options": ["Production", "Staging"]], ["title": "Why?", "options": []]]]
        let projection = try project(base(requests: [], turns: [turn("turn", items: [message])]))
        XCTAssertTrue(projection.requests.isEmpty)
        XCTAssertEqual(projection.asyncQuestions.count, 2)
        let question = projection.asyncQuestions[0]
        XCTAssertEqual(question.questionItemID, #"["request_user_input_async","message/1",0]"#)
        XCTAssertEqual(question.userInputMode, .asynchronous)
        XCTAssertEqual(question.sourceItemID, "message/1")
        XCTAssertEqual(question.options, ["Production", "Staging"])
        let envelope = String(decoding: try question.asyncRequestEnvelopeData(conversationID: "thread"), as: UTF8.self)
        XCTAssertTrue(envelope.contains("desktop/tool/requestUserInputAsync"))
        XCTAssertTrue(envelope.contains("Which target?"))
        XCTAssertFalse(envelope.contains("PRIVATE_TEXT"))
        XCTAssertEqual(projection.authoritativeAsyncQuestionIDs.count, 2)
        XCTAssertTrue(projection.authoritativePendingIdentities.isEmpty)
    }

    func testAcceptedNativeQuestionReplyResolvesOnlyMatchingQuestion() throws {
        let id = #"["request_user_input_async","message",0]"#
        let message: [String: Any] = ["id": "message", "type": "agentMessage", "questions": [["title": "Target?", "options": ["Staging"]], ["title": "Other?", "options": []]]]
        let accepted = reply(id: id, question: "Target?", answer: "Staging", status: "accepted")
        var items = [message, accepted]
        var projection = try project(base(requests: [], turns: [turn("turn", items: items)]))
        XCTAssertEqual(projection.asyncQuestions[0].resolvedAnswer, "Staging")
        XCTAssertNil(projection.asyncQuestions[1].resolvedAnswer)
        XCTAssertEqual(projection.authoritativeAsyncQuestionIDs.count, 1)
        items[1] = reply(id: id, question: "Target?", answer: "Staging", status: "pending")
        projection = try project(base(requests: [], turns: [turn("turn", items: items)]))
        XCTAssertEqual(projection.authoritativeAsyncQuestionIDs.count, 2)
        items[1] = reply(id: id, question: "Wrong question", answer: "Staging", status: "accepted")
        projection = try project(base(requests: [], turns: [turn("turn", items: items)]))
        XCTAssertEqual(projection.authoritativeAsyncQuestionIDs.count, 2)
    }

    func testAcceptedUserMessageAndTerminalQuestionDoNotLeaveWaitingState() throws {
        let id = #"["request_user_input_async","message",0]"#
        let message: [String: Any] = ["id": "message", "type": "agentMessage", "questions": [["title": "Target?", "options": ["Staging"]]]]
        var userReply = reply(id: id, question: "Target?", answer: "Staging", status: "accepted")
        userReply["type"] = "userMessage"; userReply["content"] = userReply.removeValue(forKey: "input")
        var projection = try project(base(requests: [], turns: [turn("turn", items: [message, userReply])]))
        XCTAssertEqual(projection.asyncQuestions.first?.resolvedAnswer, "Staging")
        XCTAssertTrue(projection.authoritativeAsyncQuestionIDs.isEmpty)
        projection = try project(base(requests: [], turns: [turn("turn", status: "completed", items: [message])]))
        XCTAssertTrue(projection.authoritativeAsyncQuestionIDs.isEmpty)
    }

    func testNativePluralNetworkProposalsPreserveStructureWithoutInventedDecisions() throws {
        let native: [String: Any] = ["id": "network", "method": "item/commandExecution/requestApproval", "params": [
            "threadId": "thread", "turnId": "turn", "command": "curl https://example.com",
            "proposedNetworkPolicyAmendments": [["action": "allow", "host": "example.com"], ["action": "deny", "host": "private.example.com"]]]]
        let projection = try project(base(requests: [native], turns: [turn("turn")]))
        let request = try XCTUnwrap(projection.requests.first)
        let params = try JSONSerialization.jsonObject(with: request.paramsData) as! [String: Any]
        let proposals = try XCTUnwrap(params["proposedNetworkPolicyAmendments"] as? [[String: String]])
        XCTAssertEqual(proposals, [["action": "allow", "host": "example.com"], ["action": "deny", "host": "private.example.com"]])
        XCTAssertNil(params["availableDecisions"])
        let envelope = try JSONSerialization.jsonObject(with: request.envelopeData) as! [String: Any]
        let envelopeParams = envelope["params"] as! [String: Any]
        XCTAssertEqual(envelopeParams["proposedNetworkPolicyAmendments"] as? [[String: String]], proposals)
    }

    func testNullableMCPTurnUsesOwnerCurrentTurnOnlyInPresentation() throws {
        let original = Data(#"{"id":"thread","source":"appServer","requests":[{"id":9223372036854775807,"method":"mcpServer/elicitation/request","params":{"threadId":"thread","turnId":null,"serverName":"connector","mode":"form","message":"Choose a setting","requestedSchema":{"type":"object","properties":{"setting":{"type":"string"}}}}}],"turns":[{"turnId":"current","status":"inProgress","items":[]}]}"#.utf8)
        let projection = try project(original)
        let request = try XCTUnwrap(projection.requests.first)
        XCTAssertEqual(request.requestID, .integer(Int64.max))
        XCTAssertEqual(request.turnID, "current")
        XCTAssertEqual(projection.authoritativePendingIdentities, [.init(turnID: "current", requestID: .integer(Int64.max), method: "mcpServer/elicitation/request")])
        let params = try JSONSerialization.jsonObject(with: request.paramsData) as! [String: Any]
        XCTAssertEqual(params["turnId"] as? String, "current")
        XCTAssertEqual(params["serverName"] as? String, "connector")
        let envelope = try JSONSerialization.jsonObject(with: request.envelopeData) as! [String: Any]
        XCTAssertEqual((envelope["params"] as? [String: Any])?["turnId"] as? String, "current")
        XCTAssertTrue(String(decoding: original, as: UTF8.self).contains(#""turnId":null"#))
        XCTAssertEqual(String(decoding: request.envelopeData, as: UTF8.self).components(separatedBy: "9223372036854775807").count, 2)
    }

    func testCompletedRPCRemovesAuthoritativePendingIdentityEvenBeforeArrayRemoval() throws {
        var completed = rpc(id: "answered", method: "mcpServer/elicitation/request", params: ["serverName": "connector", "mode": "form", "message": "Already answered"])
        completed["completed"] = true
        var pending = rpc(id: "pending"); pending["completed"] = false
        let projection = try project(base(requests: [completed, pending], turns: [turn("turn")]))
        XCTAssertTrue(projection.pendingRequestsAreAuthoritative)
        XCTAssertEqual(projection.requests.map(\.requestID), [.string("pending")])
        XCTAssertEqual(projection.authoritativePendingIdentities, [.init(turnID: "turn", requestID: .string("pending"), method: "item/commandExecution/requestApproval")])
        let cleared = try project(base(requests: [completed], turns: [turn("turn")]))
        XCTAssertTrue(cleared.requests.isEmpty)
        XCTAssertTrue(cleared.authoritativePendingIdentities.isEmpty)
    }

    func testRuntimeFlagsAreExplicitContinuationEvidenceRatherThanInProgressOrEmptyRequests() throws {
        var state = base(requests: [], turns: [turn("turn")])
        XCTAssertEqual(try project(state).threadWaitStatus, .unavailable)
        XCTAssertFalse(try project(state).provesNoPendingConfirmation)
        let unsupportedRuntimeStates: [[String: Any]] = [
            ["type": "active"], ["type": "active", "activeFlags": ["futureWaitingFlag"]],
            ["type": "active", "activeFlags": "invalid"], ["type": "idle"]]
        for runtime in unsupportedRuntimeStates {
            state["threadRuntimeStatus"] = runtime
            XCTAssertEqual(try project(state).threadWaitStatus, .unavailable)
            XCTAssertFalse(try project(state).provesNoPendingConfirmation)
        }
        state["threadRuntimeStatus"] = ["type": "active", "activeFlags": ["waitingOnApproval"]]
        XCTAssertEqual(try project(state).threadWaitStatus, .waiting(.approval))
        XCTAssertFalse(try project(state).provesNoPendingConfirmation)
        state["threadRuntimeStatus"] = ["type": "active", "activeFlags": []]
        XCTAssertEqual(try project(state).threadWaitStatus, .running)
        XCTAssertTrue(try project(state).provesNoPendingConfirmation)
        state["requests"] = [rpc(id: "future", method: "future/approval/request")]
        XCTAssertFalse(try project(state).provesNoPendingConfirmation,
            "An unrepresented pending RPC is not an empty confirmation set")
    }

    func testAutomaticServiceRPCsNeedNoThreadParamsAndDoNotBlockConfirmationContinuation() throws {
        let services: [[String: Any]] = [
            ["id": "time", "method": "currentTime/read", "params": [:]],
            ["id": "token", "method": "account/chatgptAuthTokens/refresh", "params": ["reason": "fixture"]],
            ["id": "attestation", "method": "attestation/generate", "params": ["challenge": "fixture"]]]
        var state = base(requests: services, turns: [turn("turn")])
        state["threadRuntimeStatus"] = ["type": "active", "activeFlags": []]
        let full = try project(state)
        XCTAssertTrue(full.requests.isEmpty)
        XCTAssertTrue(full.authoritativePendingIdentities.isEmpty)
        XCTAssertTrue(full.provesNoPendingConfirmation)
        state["requests"] = services + [rpc(id: "future", method: "future/approval/request")]
        XCTAssertFalse(try project(state).provesNoPendingConfirmation,
            "A known automatic RPC exclusion cannot suppress unknown user interactions")
        state["requests"] = [["method": "currentTime/read", "params": [:]]]
        XCTAssertThrowsError(try project(state), "Even an automatic RPC retains envelope identity validation")
    }

    func testNativeLiveSuffixWithoutCanonicalAnchorOrStartTimeOwnsCurrentQuestion() throws {
        var old = turn("old", status: "completed"); old.removeValue(forKey: "turnStartedAtMs")
        var fresh = turn("fresh", items: [["id": "message", "type": "agentMessage", "questions": [["title": "Fixture question", "options": ["A", "B"]]]]])
        fresh.removeValue(forKey: "turnStartedAtMs")
        var state = base(requests: [rpc(id: "old", turn: "old"), rpc(id: "fresh", turn: "fresh")], turns: [fresh])
        state["turnHistory"] = ["kind": "canonical", "history": ["islands": [["newerBoundary": ["status": "exhausted"], "entries": [["value": "old-key"]]]], "entitiesByKey": ["old-key": old]]]
        let projection = try project(state)
        XCTAssertEqual(projection.currentTurnID, "fresh")
        XCTAssertEqual(projection.status, "inProgress")
        XCTAssertTrue(projection.pendingRequestsAreAuthoritative)
        XCTAssertEqual(projection.requests.map(\.requestID), [.string("fresh")])
        XCTAssertEqual(projection.authoritativeAsyncQuestionIDs.count, 1)
    }

    func testNativeSameTurnLiveStatusRestoresActiveQuestionWithoutPaginationOverlay() throws {
        var state = base(requests: [rpc(id: "pending")], turns: [turn("turn", items: [[
            "id": "message", "type": "agentMessage", "questions": [["title": "Fixture question", "options": ["A"]]]]])])
        state["turnHistory"] = ["kind": "canonical", "history": ["islands": [["newerBoundary": ["status": "exhausted"], "entries": [["value": "key"]]]], "entitiesByKey": ["key": turn("turn", status: "completed")]]]
        let projection = try project(state)
        XCTAssertEqual(projection.status, "inProgress")
        XCTAssertEqual(projection.requests.count, 1)
        XCTAssertEqual(projection.authoritativeAsyncQuestionIDs.count, 1)
        XCTAssertTrue(projection.pendingRequestsAreAuthoritative)
    }

    func testNativePaginationOverlayKeepsExistingTerminalState() throws {
        var canonical = turn("turn", status: "completed")
        canonical["itemsPagination"] = ["hasLoadedOldest": false]
        var state = base(requests: [rpc(id: "pending")], turns: [turn("turn")])
        state["turnHistory"] = ["kind": "canonical", "history": ["islands": [["newerBoundary": ["status": "exhausted"], "entries": [["value": "key"]]]], "entitiesByKey": ["key": canonical]]]
        let projection = try project(state)
        XCTAssertEqual(projection.status, "completed")
        XCTAssertTrue(projection.authoritativePendingIdentities.isEmpty)
    }

    func testNativeLivePrefixBeforeCanonicalAnchorIsNotAppendedAsCurrentTurn() throws {
        var prefix = turn("prefix"); prefix.removeValue(forKey: "turnStartedAtMs")
        var state = base(requests: [], turns: [prefix, turn("old", status: "completed")])
        state["turnHistory"] = ["kind": "canonical", "history": ["islands": [["newerBoundary": ["status": "exhausted"], "entries": [["value": "old-key"], ["value": "current-key"]]]], "entitiesByKey": ["old-key": turn("old", status: "completed"), "current-key": turn("current")]]]
        XCTAssertEqual(try project(state).currentTurnID, "current")
    }

    func testMissingCanonicalTailCannotPromoteOlderTurnToSettlementOrCompletionProof() throws {
        for oldStatus in ["completed", "inProgress"] {
            var state = base(requests: [rpc(id: "old-pending", turn: "old")], turns: [])
            state["threadRuntimeStatus"] = ["type": "active", "activeFlags": []]
            state["turnHistory"] = ["kind": "canonical", "history": ["islands": [[
                "newerBoundary": ["status": "exhausted"], "entries": [["value": "old-key"], ["value": "missing-current-key"]]]],
                "entitiesByKey": ["old-key": turn("old", status: oldStatus)]]]
            let projection = try project(state)
            XCTAssertNil(projection.currentTurnID)
            XCTAssertEqual(projection.status, "unknown",
                "An older completed turn cannot tell Runtime to stop following the current task")
            XCTAssertFalse(projection.pendingRequestsAreAuthoritative)
            XCTAssertFalse(projection.provesNoPendingConfirmation,
                "An unresolved current reference cannot erase the previously observed waiting request")
        }
    }

    private func project(_ data: Data) throws -> CodexDesktopInteractionProjection {
        try CodexDesktopRequestProjector.project(conversationID: "thread", conversationStateData: data)
    }
    private func project(_ state: [String: Any]) throws -> CodexDesktopInteractionProjection {
        try project(JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]))
    }
    private func base(requests: [[String: Any]], turns: [[String: Any]]) -> [String: Any] {
        ["id": "thread", "source": "appServer", "title": "Task", "requests": requests, "turns": turns]
    }
    private func turn(_ id: String, status: String = "inProgress", items: [[String: Any]] = []) -> [String: Any] {
        ["turnId": id, "status": status, "turnStartedAtMs": 1720000000000, "items": items]
    }
    private func rpc(id: Any, turn: String = "turn", method: String = "item/commandExecution/requestApproval", params: [String: Any] = [:]) -> [String: Any] {
        ["id": id, "method": method, "params": ["threadId": "thread", "turnId": turn, "command": "swift build", "availableDecisions": ["accept", "decline"]].merging(params) { _, value in value }]
    }
    private func reply(id: String, question: String, answer: String, status: String) -> [String: Any] {
        let answers = [["questionItemId": id, "question": question, "answer": answer]]
        let text = CodexDesktopRequestProjector.asyncReplyOpeningTag + "\n" + String(decoding: try! JSONSerialization.data(withJSONObject: answers), as: UTF8.self) + "\n" + CodexDesktopRequestProjector.asyncReplyClosingTag
        return ["id": "answer", "type": "steeringUserMessage", "status": status, "input": [["type": "text", "text": text]]]
    }
}
