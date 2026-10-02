import Foundation
import XCTest
@testable import QuotaView
@testable import QuotaViewCore

final class PendingConfirmationRecoveryTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_790_888_000)
    private func hash(_ id: String) -> String { CodexActivityPrivacy.hashIdentifier(id) }
    private func json(_ method: String, _ params: [String: Any], id: Any? = nil) -> Data {
        var value: [String: Any] = ["method": method, "params": params]
        if let id { value["id"] = id }
        return try! JSONSerialization.data(withJSONObject: value)
    }
    private func line(_ type: String, _ payload: [String: Any], at: Date) -> Data {
        let format = ISO8601DateFormatter(); format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return try! JSONSerialization.data(withJSONObject: ["type": type, "payload": payload, "timestamp": format.string(from: at)])
    }
    private var questions: [[String: Any]] {
        [["id": "scope", "header": "本次范围", "question": "这次只修改 DSH 吗？", "options": [
            ["label": "只修改 DSH", "description": "保留 DeepViewer 当前内容"],
            ["label": "同时修改两个应用", "description": "分别处理数据目录"]
        ], "isOther": true]]
    }
    private func questionLine(call: String = "call-1", at: Date) -> Data {
        let args = String(decoding: try! JSONSerialization.data(withJSONObject: ["questions": questions, "ignored": "private context"]), as: UTF8.self)
        return line("response_item", ["type": "function_call", "name": "functions.request_user_input", "call_id": call, "arguments": args], at: at)
    }
    private func outputLine(call: String = "call-1", at: Date) -> Data {
        line("response_item", ["type": "function_call_output", "call_id": call, "output": "{\"answers\":{\"scope\":{\"answers\":[\"只修改 DSH\"]}}}"], at: at)
    }
    private func content(_ data: Data, session: String = "dsh", turn: String = "turn") throws -> CodexLocalPublicContent {
        try XCTUnwrap(CodexLocalPublicContent.decode(data, sessionHash: hash(session), activeTurnHash: hash(turn)))
    }
    @MainActor
    private func start(_ model: IslandLiveStore, session: String = "dsh", turn: String = "turn") {
        model.receiveLegacy(.init(event: .userPromptSubmit, sessionHash: hash(session), turnHash: hash(turn),
            workspaceName: session, sessionKind: .user, source: .localRollout, occurredAt: date))
    }
    @MainActor
    private func nativeQuestion(_ model: IslandLiveStore, session: String = "dsh", turn: String = "turn", call: String = "call-1", rpc: Any = 7, at: Date) {
        model.receive(json("item/tool/requestUserInput", ["threadId": session, "turnId": turn,
            "itemId": call, "questions": questions], id: rpc), at: at)
    }

    @MainActor
    func testQuestionToolPreservesTypeContentAndNeverInventsResponseOwnership() async throws {
        var decoder = CodexLocalRolloutLineDecoder(sessionHash: hash("dsh"), sessionKind: .user)
        _ = decoder.decode(line: line("event_msg", ["type": "task_started", "turn_id": "turn"], at: date))
        let question = questionLine(at: date.addingTimeInterval(1))
        guard case .activity(let event) = try XCTUnwrap(decoder.decode(line: question)).update else { return XCTFail("Expected a question event") }
        XCTAssertEqual(event.event, .permissionRequest)
        XCTAssertEqual(event.waitReason, .userInput)
        XCTAssertEqual(event.toolCallHash, hash("call-1"))
        let publicContent = try content(question)
        let clean = try XCTUnwrap(JSONSerialization.jsonObject(with: publicContent.data) as? [String: Any])
        XCTAssertEqual(clean["type"] as? String, "questionRequest")
        XCTAssertNil(clean["ignored"])
        let model = IslandLiveStore(); start(model)
        model.receiveLegacy(event)
        XCTAssertNil(model.tasks[0].requests[0].value.protocolRequest)
        var changes = 0; model.onChange = { changes += 1 }
        var responses = 0
        model.responseCapability = { _ in true }
        model.respond = { _, _ in responses += 1 }
        model.receiveLocalContent(publicContent)
        XCTAssertEqual(changes, 1, "Question details publish immediately")
        let request = try XCTUnwrap(model.tasks[0].requests.first?.value)
        let wire = try XCTUnwrap(request.protocolRequest)
        XCTAssertEqual(wire.kind, .questions)
        XCTAssertTrue(wire.observationOnly)
        XCTAssertTrue(try IslandCodexApprovalRequest(data: wire.raw).observationOnly,
            "Serialization cannot turn a local observation into a response capability")
        XCTAssertFalse(request.canRespond)
        XCTAssertEqual(wire.questions[0].id, "scope")
        XCTAssertEqual(wire.questions[0].header, "本次范围")
        XCTAssertEqual(wire.questions[0].title, "这次只修改 DSH 吗？")
        XCTAssertEqual(wire.questions[0].options[0]["label"].text, "只修改 DSH")
        XCTAssertEqual(wire.questions[0].options[0]["description"].text, "保留 DeepViewer 当前内容")
        XCTAssertFalse(wire.permits(.object(["answers": .object(["scope": .object(["answers": .array([.string("只修改 DSH")])])])])),
            "A public observation never permits sending a fabricated RPC result")
        model.submit(model.tasks[0].id, requestID: request.id,
            decision: .reply(.object(["answers": .object(["scope": .object(["answers": .array([.string("只修改 DSH")])])])])) )
        await Task.yield()
        XCTAssertEqual(responses, 0, "A rollout tool call is not an RPC request owner")
        let display = model.display(english: false, remaining: nil, enabled: true, privacy: false)
        XCTAssertEqual(display.state.tasks[0].renderState.statusTitle, "等待回答")
        guard case .activity(let resolved) = try XCTUnwrap(decoder.decode(line: outputLine(at: date.addingTimeInterval(2)))).update else { return XCTFail("Expected matching result") }
        XCTAssertEqual(resolved.event, .postToolUse)
        XCTAssertEqual(resolved.toolCallHash, event.toolCallHash)
    }

    @MainActor
    func testCallResultResolvesOnlyMatchingSessionTurnAndCall() throws {
        let model = IslandLiveStore(); start(model); start(model, session: "other")
        model.receiveLocalContent(try content(questionLine(at: date.addingTimeInterval(1))))
        model.receiveLocalContent(try content(questionLine(at: date.addingTimeInterval(1)), session: "other"))
        model.receiveLocalContent(try content(outputLine(call: "another-call", at: date.addingTimeInterval(2))))
        XCTAssertEqual(model.tasks.map { $0.requests.count }, [1, 1])
        model.receiveLocalContent(try content(outputLine(at: date.addingTimeInterval(2)), turn: "older-turn"))
        XCTAssertEqual(model.tasks.map { $0.requests.count }, [1, 1])
        var changes = 0; model.onChange = { changes += 1 }
        model.receiveLocalContent(try content(outputLine(at: date.addingTimeInterval(2))))
        XCTAssertEqual(model.tasks.map { $0.requests.count }, [0, 1])
        XCTAssertEqual(model.tasks[0].status, .thinking)
        XCTAssertGreaterThan(changes, 0, "Matching answers immediately remove the attention state")
        XCTAssertEqual(model.tasks[1].title, "other")
    }

    @MainActor
    func testLateGenericOrDetailedRequestCannotResurrectAnsweredCall() throws {
        let model = IslandLiveStore(); start(model)
        model.receiveLocalContent(try content(questionLine(at: date.addingTimeInterval(1))))
        model.receiveLocalContent(try content(outputLine(at: date.addingTimeInterval(2))))
        model.receiveLegacy(.init(event: .permissionRequest, sessionHash: hash("dsh"), turnHash: hash("turn"),
            sessionKind: .user, source: .hook, waitReason: .userInput, toolCallHash: hash("call-1"), occurredAt: date.addingTimeInterval(3)))
        model.receiveLegacy(.init(event: .permissionRequest, sessionHash: hash("dsh"), turnHash: hash("turn"),
            sessionKind: .user, source: .hook, occurredAt: date.addingTimeInterval(1.5)))
        nativeQuestion(model, at: date.addingTimeInterval(3))
        model.receiveLocalContent(try content(questionLine(at: date.addingTimeInterval(1))))
        XCTAssertTrue(model.tasks[0].requests.isEmpty)
        XCTAssertEqual(model.tasks[0].status, .thinking)
        model.receiveLocalContent(try content(questionLine(call: "new-call", at: date.addingTimeInterval(4))))
        XCTAssertEqual(model.tasks[0].requests.count, 1, "A genuinely new request remains available")
    }

    @MainActor
    func testGenericWaitClearsOnRealContinuationAndNeverInventsApprovalContent() {
        let model = IslandLiveStore(); start(model)
        model.receiveLegacy(.init(event: .permissionRequest, sessionHash: hash("dsh"), turnHash: hash("turn"),
            sessionKind: .user, source: .hook, occurredAt: date.addingTimeInterval(1)))
        XCTAssertEqual(model.tasks[0].requests[0].value.question.chinese, "请求详情暂不可用")
        XCTAssertNil(model.tasks[0].requests[0].value.protocolRequest)
        XCTAssertFalse(model.tasks[0].requests[0].value.canRespond)
        model.receiveLegacy(.init(event: .preToolUse, sessionHash: hash("dsh"), turnHash: hash("turn"),
            sessionKind: .user, source: .localRollout, occurredAt: date.addingTimeInterval(2)))
        XCTAssertTrue(model.tasks[0].requests.isEmpty)
        XCTAssertEqual(model.tasks[0].status, .working)
        model.receiveLegacy(.init(event: .permissionRequest, sessionHash: hash("dsh"), turnHash: hash("turn"),
            sessionKind: .user, source: .hook, occurredAt: date.addingTimeInterval(1.5)))
        XCTAssertTrue(model.tasks[0].requests.isEmpty, "A generic wait before real continuation cannot return late")
        model.receiveLegacy(.init(event: .permissionRequest, sessionHash: hash("dsh"), turnHash: hash("turn"),
            sessionKind: .user, source: .hook, occurredAt: date.addingTimeInterval(3)))
        XCTAssertEqual(model.tasks[0].requests.count, 1)
        model.receiveLegacy(.init(event: .postToolUse, sessionHash: hash("dsh"), turnHash: hash("turn"),
            sessionKind: .user, source: .hook, occurredAt: date.addingTimeInterval(4)))
        XCTAssertTrue(model.tasks[0].requests.isEmpty)
        XCTAssertNotEqual(model.tasks[0].status, .waiting)
    }

    @MainActor
    func testNativeRequestReplacesLocalDetailAndOutputResolvesWithNativeTrace() throws {
        let model = IslandLiveStore(); start(model)
        model.setConnection(.connected)
        model.receiveLocalContent(try content(questionLine(at: date.addingTimeInterval(1))))
        nativeQuestion(model, at: date.addingTimeInterval(1.1))
        XCTAssertEqual(model.tasks[0].requests.count, 1)
        XCTAssertEqual(model.tasks[0].requests[0].value.protocolRequest?.observationOnly, false)
        model.receive(json("item/agentMessage/delta", ["threadId": "dsh", "turnId": "turn", "itemId": "message", "delta": "Current response"]), at: date.addingTimeInterval(1.2))
        XCTAssertTrue(model.tasks[0].nativeContentAvailable)
        model.receiveLocalContent(try content(outputLine(at: date.addingTimeInterval(2))))
        XCTAssertTrue(model.tasks[0].requests.isEmpty)
        XCTAssertFalse(model.display(english: false, remaining: nil, enabled: true, privacy: false).state.tasks[0].hasPendingRequest)
    }

    @MainActor
    func testNativeResolutionWithoutThreadOnlyClearsUnambiguousMatchingRPC() {
        let model = IslandLiveStore(); start(model); start(model, session: "other")
        nativeQuestion(model, at: date.addingTimeInterval(1))
        nativeQuestion(model, session: "other", rpc: "7", at: date.addingTimeInterval(1))
        model.receive(json("serverRequest/resolved", ["requestId": 7]), at: date.addingTimeInterval(2))
        XCTAssertEqual(model.tasks.map { $0.requests.count }, [0, 1], "Numeric and string IDs must remain distinct")
        nativeQuestion(model, at: date.addingTimeInterval(3))
        XCTAssertTrue(model.tasks[0].requests.isEmpty, "A resolved RPC cannot be replayed")
        nativeQuestion(model, call: "call-2", rpc: 8, at: date.addingTimeInterval(4))
        nativeQuestion(model, session: "other", call: "call-2", rpc: 8, at: date.addingTimeInterval(4))
        model.receive(json("serverRequest/resolved", ["requestId": 8]), at: date.addingTimeInterval(5))
        XCTAssertEqual(model.tasks.map { $0.requests.count }, [1, 2], "Ambiguous requests require their thread scope")
        model.receive(json("serverRequest/resolved", ["threadId": "other", "turnId": "turn", "requestId": 8]), at: date.addingTimeInterval(6))
        XCTAssertEqual(model.tasks.map { $0.requests.count }, [1, 1])
    }

    @MainActor
    func testPriorTurnAndCompletedReplayCannotInstallQuestionOnCurrentTask() throws {
        let model = IslandLiveStore(); start(model)
        let oldQuestion = try content(questionLine(at: date.addingTimeInterval(1)))
        model.receiveLegacy(.init(event: .stop, sessionHash: hash("dsh"), turnHash: hash("turn"),
            sessionKind: .user, source: .localRollout, turnCompletionStatus: .completed, occurredAt: date.addingTimeInterval(2)))
        model.receiveLocalContent(oldQuestion)
        XCTAssertTrue(model.tasks[0].requests.isEmpty)
        start(model, turn: "next")
        model.receiveLocalContent(oldQuestion)
        model.receiveLocalContent(try content(outputLine(at: date.addingTimeInterval(2))))
        XCTAssertTrue(model.tasks[0].requests.isEmpty)
        XCTAssertEqual(model.tasks[0].turnKey, hash("next"))
        let empty = IslandLiveStore()
        empty.receiveLocalContent(try content(outputLine(at: date.addingTimeInterval(2))))
        empty.receiveLocalContent(oldQuestion)
        XCTAssertTrue(empty.tasks.isEmpty, "Historical public data alone cannot admit a task")
        start(empty)
        XCTAssertTrue(empty.tasks[0].requests.isEmpty, "Answer-before-request replay must remain resolved")
    }

    @MainActor
    func testCompletedOperationClearsItsApprovalWithoutClearingOtherRequest() {
        let model = IslandLiveStore(); start(model)
        for (id, item) in [(1, "first-command"), (2, "second-command")] {
            model.receive(json("item/commandExecution/requestApproval", ["threadId": "dsh", "turnId": "turn",
                "itemId": item, "command": "swift test", "availableDecisions": ["accept", "decline"]], id: id),
                at: date.addingTimeInterval(1))
        }
        model.receiveLegacy(.init(event: .postToolUse, sessionHash: hash("dsh"), turnHash: hash("turn"),
            sessionKind: .user, source: .hook, toolCallHash: hash("first-command"), occurredAt: date.addingTimeInterval(2)))
        XCTAssertEqual(model.tasks[0].requests.count, 1)
        XCTAssertEqual(model.tasks[0].requests[0].value.protocolRequest?.params["itemId"].text, "second-command")
        XCTAssertEqual(model.tasks[0].status, .waiting)
    }

    @MainActor
    func testAsyncQuestionChoicesAndFreeTextPreserveLatestPublicSchema() throws {
        let payload: [String: Any] = ["type": "function_call", "name": "functions.request_user_input_async", "call_id": "async-call",
            "arguments": String(decoding: try JSONSerialization.data(withJSONObject: ["questions": [
                ["title": "用哪种方式连接？", "options": ["自动连接", "仅手动配置"]],
                ["title": "还有什么要求？"]
            ]]), as: UTF8.self)]
        let data = line("response_item", payload, at: date.addingTimeInterval(1))
        var decoder = CodexLocalRolloutLineDecoder(sessionHash: hash("dsh"), sessionKind: .user)
        _ = decoder.decode(line: line("event_msg", ["type": "task_started", "turn_id": "turn"], at: date))
        guard case .activity(let event) = try XCTUnwrap(decoder.decode(line: data)).update else { return XCTFail("Expected an async question") }
        XCTAssertEqual(event.waitReason, .userInput)
        let model = IslandLiveStore(); start(model); model.receiveLegacy(event)
        model.receiveLocalContent(try content(data))
        let wire = try XCTUnwrap(model.tasks[0].requests[0].value.protocolRequest)
        XCTAssertEqual(wire.kind, .questions)
        XCTAssertTrue(wire.observationOnly)
        XCTAssertEqual(wire.questions.map(\.title), ["用哪种方式连接？", "还有什么要求？"])
        XCTAssertEqual(wire.questions.map(\.id), ["question-1", "question-2"])
        XCTAssertEqual(wire.questions[0].options.map { $0["label"].text }, ["自动连接", "仅手动配置"])
        XCTAssertTrue(wire.questions[1].options.isEmpty)
        XCTAssertFalse(model.tasks[0].requests[0].value.canRespond)
        let ack = line("response_item", ["type": "function_call_output", "call_id": "async-call", "output": "{\"success\":true}"], at: date.addingTimeInterval(2))
        XCTAssertNil(decoder.decode(line: ack), "Async launch success cannot produce a answered lifecycle event")
        let ackContent = try XCTUnwrap(CodexLocalPublicContent.decode(ack, sessionHash: hash("dsh"), activeTurnHash: hash("turn"),
            asynchronousQuestionCallIDs: decoder.asynchronousQuestionCallIDs))
        model.receiveLocalContent(ackContent)
        XCTAssertEqual(model.tasks[0].requests.count, 1, "Starting an async question is not answering it")
        model.receiveLegacy(.init(event: .postToolUse, sessionHash: hash("dsh"), turnHash: hash("turn"),
            sessionKind: .user, source: .hook, toolCallHash: hash("async-call"), occurredAt: date.addingTimeInterval(2.1)))
        XCTAssertEqual(model.tasks[0].requests.count, 1)
        XCTAssertEqual(wire.localObservation?.asynchronous, true)
        let reordered = IslandLiveStore(); start(reordered)
        reordered.receiveLocalContent(ackContent); reordered.receiveLocalContent(try content(data))
        XCTAssertEqual(reordered.tasks[0].requests.count, 1, "An ack preceding replay cannot suppress its async question")
        start(model, turn: "next")
        XCTAssertTrue(model.tasks[0].requests.isEmpty, "A new turn supersedes the prior async question")
    }

    @MainActor
    func testUnrelatedRPCResolutionDoesNotClearGenericWaitForDifferentCall() {
        let model = IslandLiveStore(); start(model)
        model.receiveLegacy(.init(event: .permissionRequest, sessionHash: hash("dsh"), turnHash: hash("turn"),
            sessionKind: .user, source: .hook, toolCallHash: hash("real-pending"), occurredAt: date.addingTimeInterval(1)))
        model.receive(json("serverRequest/resolved", ["threadId": "dsh", "turnId": "turn", "requestId": 999]),
            at: date.addingTimeInterval(2))
        XCTAssertEqual(model.tasks[0].requests.count, 1)
        XCTAssertEqual(model.tasks[0].genericWaitCallHash, hash("real-pending"))
        XCTAssertEqual(model.tasks[0].status, .waiting)
    }

    @MainActor
    func testOnlyKnownNativeUserWaitContinuationResolvesLocalAsyncQuestions() throws {
        let model = IslandLiveStore(); start(model)
        let args = String(decoding: try JSONSerialization.data(withJSONObject: ["questions": [["title": "请选择范围", "options": ["仅 DSH", "全部"]]]]), as: UTF8.self)
        let question = try content(line("response_item", ["type": "function_call", "name": "functions.request_user_input_async",
            "call_id": "async-proof", "arguments": args], at: date.addingTimeInterval(1)))
        model.receiveLocalContent(question)
        model.receive(json("thread/status/changed", ["threadId": "dsh", "status": ["type": "active", "activeFlags": []]]),
            at: date.addingTimeInterval(2))
        XCTAssertEqual(model.tasks[0].requests.count, 1, "An initial nonwaiting snapshot cannot infer an answer")
        model.receive(json("item/commandExecution/requestApproval", ["threadId": "dsh", "turnId": "turn", "itemId": "unrelated-command",
            "command": "swift test", "availableDecisions": ["accept", "decline"]], id: 42), at: date.addingTimeInterval(3))
        model.receive(json("thread/status/changed", ["threadId": "dsh", "status": ["type": "active", "activeFlags": ["waitingOnUserInput"]]]),
            at: date.addingTimeInterval(4))
        XCTAssertEqual(model.tasks[0].requests.count, 2)
        model.receive(json("thread/status/changed", ["threadId": "dsh", "status": ["type": "active", "activeFlags": []]]),
            at: date.addingTimeInterval(5))
        XCTAssertEqual(model.tasks[0].requests.count, 1)
        XCTAssertEqual(model.tasks[0].requests[0].value.protocolRequest?.kind, .command)
        XCTAssertEqual(model.tasks[0].status, .waiting, "Unrelated approvals remain pending")
        XCTAssertTrue(model.tasks[0].asynchronousQuestionCallHashes.isEmpty)
        model.receiveLocalContent(question)
        XCTAssertEqual(model.tasks[0].requests.count, 1, "A answered question cannot return in a delayed public replay")
    }

    @MainActor
    func testHookAsyncAckBeforePublicQuestionCannotCreateResolutionTombstone() throws {
        let args = String(decoding: try JSONSerialization.data(withJSONObject: ["questions": [["title": "选择范围", "options": ["仅 DSH", "全部"]]]]), as: UTF8.self)
        let question = try content(line("response_item", ["type": "function_call", "name": "functions.request_user_input_async",
            "call_id": "async-early", "arguments": args], at: date.addingTimeInterval(1)))
        for name in ["functions.request_user_input_async", nil] as [String?] {
            let model = IslandLiveStore(); start(model)
            model.receiveLegacy(.init(event: .postToolUse, sessionHash: hash("dsh"), turnHash: hash("turn"),
                sessionKind: .user, source: .hook, toolCallHash: hash("async-early"), toolName: name, occurredAt: date.addingTimeInterval(2)))
            XCTAssertFalse(model.tasks[0].resolvedCallHashes.contains(hash("async-early")))
            model.receiveLocalContent(question)
            XCTAssertEqual(model.tasks[0].requests.count, 1, "A Hook launcher ack cannot suppress a later public async question")
            XCTAssertEqual(model.tasks[0].requests[0].value.protocolRequest?.localObservation?.asynchronous, true)
        }
    }

    @MainActor
    func testNativeAsyncOrUnknownDynamicAckBeforePublicQuestionDoesNotResolveIt() throws {
        let args = String(decoding: try JSONSerialization.data(withJSONObject: ["questions": [["title": "选择范围"]]]), as: UTF8.self)
        let question = try content(line("response_item", ["type": "function_call", "name": "functions.request_user_input_async",
            "call_id": "native-early", "arguments": args], at: date.addingTimeInterval(1)))
        for (type, name) in [("mcpToolCall", "functions.request_user_input_async"), ("dynamicToolCall", "opaque_tool")] {
            let model = IslandLiveStore(); start(model)
            model.receive(json("item/completed", ["threadId": "dsh", "turnId": "turn", "item": ["id": "native-early", "type": type,
                "tool": name, "status": "completed"]]), at: date.addingTimeInterval(2))
            XCTAssertFalse(model.tasks[0].resolvedCallHashes.contains(hash("native-early")))
            model.receiveLocalContent(question)
            XCTAssertEqual(model.tasks[0].requests.count, 1, "A native launcher item completion is not a human answer")
        }
    }

    func testCorrelationRemainsCompatibleWithOlderEventsAndClassification() throws {
        let event = CodexActivityEvent(event: .permissionRequest, sessionHash: hash("dsh"), turnHash: hash("turn"),
            waitReason: .userInput, toolCallHash: hash("call-1"), toolName: "request_user_input", occurredAt: date)
        XCTAssertEqual(event.classified(as: .user).toolCallHash, event.toolCallHash)
        XCTAssertEqual(event.classified(as: .user).toolName, event.toolName)
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(event)) as? [String: Any])
        old.removeValue(forKey: "toolCallHash"); old.removeValue(forKey: "toolName")
        let decoded = try JSONDecoder().decode(CodexActivityEvent.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertNil(decoded.toolCallHash); XCTAssertNil(decoded.toolName)
        XCTAssertEqual(decoded.waitReason, .userInput)
    }
}
