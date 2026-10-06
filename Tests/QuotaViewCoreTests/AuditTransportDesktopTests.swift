import Foundation
import XCTest
@testable import QuotaViewCore

final class AuditTransportDesktopTests: XCTestCase {
    func testForeignCandidateFailurePreservesQuietOwnerHandleAndSingleSend() async throws {
        let fixture = AuditTransportDesktopFixture(state: state())
        let recorder = AuditTransportSnapshots()
        let client = fixture.client()
        await client.start(snapshotHandler: { await recorder.record($0) }, stateHandler: { _ in })
        try await client.follow(conversationID: "conversation")
        let initial = await recorder.next()
        let handle = try XCTUnwrap(initial.requests.first)
        fixture.setAutomaticSnapshots(false)
        fixture.emitForeign(source: "foreign-owner")
        fixture.emitProbe(id: "after-foreign")
        await fixture.waitForProbeResponse("after-foreign")
        let submitted = try await client.submit(handle: handle, result: Data(#"{"decision":"accept"}"#.utf8))
        XCTAssertEqual(submitted,.acceptedForDispatch)
        do { _ = try await client.submit(handle: handle,result: Data(#"{"decision":"accept"}"#.utf8)); XCTFail("duplicate sent") }
        catch { XCTAssertEqual(error as? CodexDesktopIPCError,.alreadySubmitted) }
        XCTAssertEqual(fixture.submissionCount,1)
        await client.stop()
    }

    func testForeignWrongAcknowledgementAndStatusBroadcastCannotRevokeHealthyOwner() async throws {
        let fixture = AuditTransportDesktopFixture(state: state()), recorder = AuditTransportSnapshots()
        let client = fixture.client()
        await client.start(snapshotHandler: { await recorder.record($0) }, stateHandler: { _ in })
        try await client.follow(conversationID: "conversation")
        let initial = await recorder.next(), handle = try XCTUnwrap(initial.requests.first)
        fixture.setAutomaticSnapshots(false)
        fixture.useWrongOwnerAcknowledgement()
        fixture.emitForeignStatus(source: "foreign-owner")
        fixture.emitProbe(id: "after-status")
        await fixture.waitForProbeResponse("after-status")
        fixture.emitForeign(source: "foreign-owner")
        fixture.emitProbe(id: "after-wrong-ack")
        await fixture.waitForProbeResponse("after-wrong-ack")
        _ = try await client.submit(handle: handle, result: Data(#"{"decision":"accept"}"#.utf8))
        XCTAssertEqual(fixture.submissionCount, 1)
        await client.stop()
    }

    func testDiscoveredOwnerWithoutSnapshotSchedulesRecoveryUntilAuthorityArrives() async throws {
        let fixture = AuditTransportDesktopFixture(state: state())
        fixture.skipFirstSnapshot()
        let client = fixture.client(), received = expectation(description: "recovery obtains owner state")
        await client.start(snapshotHandler: { _ in received.fulfill() }, stateHandler: { _ in })
        try await client.follow(conversationID: "conversation")
        await fulfillment(of: [received], timeout: 2)
        XCTAssertGreaterThanOrEqual(fixture.followCount, 2)
        await client.stop()
    }

    func testProvenOwnerReplacementRevokesOldHandleAndAdmitsNewOne() async throws {
        let fixture = AuditTransportDesktopFixture(state: state()), recorder = AuditTransportSnapshots()
        let client = fixture.client()
        await client.start(snapshotHandler: { await recorder.record($0) }, stateHandler: { _ in })
        try await client.follow(conversationID: "conversation")
        let initial = await recorder.next(), old = try XCTUnwrap(initial.requests.first)
        fixture.changeProvenOwner("new-owner")
        fixture.emitForeign(source: "new-owner")
        let replaced = await recorder.next(), new = try XCTUnwrap(replaced.requests.first)
        XCTAssertEqual(new.ownerClientID,"new-owner")
        do { _ = try await client.submit(handle: old,result: Data(#"{"decision":"accept"}"#.utf8)); XCTFail("old capability survived owner replacement") }
        catch { XCTAssertEqual(error as? CodexDesktopIPCError,.staleRequest) }
        _ = try await client.submit(handle: new,result: Data(#"{"decision":"accept"}"#.utf8))
        XCTAssertEqual(fixture.submissionCount,1)
        await client.stop()
    }

    func testPartialPageRetainsAsyncHandleAndAlreadySentIdentityAcrossFullRecovery() async throws {
        let question: [String: Any] = ["id": "message", "type": "agentMessage", "questions": [["title": "Choose", "options": ["Yes"]]]]
        let fixture = AuditTransportDesktopFixture(state: state(requests: [],items: [question]))
        let recorder = AuditTransportSnapshots(), client = fixture.client()
        await client.start(snapshotHandler: { await recorder.record($0) }, stateHandler: { _ in })
        try await client.follow(conversationID: "conversation")
        let first = await recorder.next(), handle = try XCTUnwrap(first.requests.first)
        let response = try JSONSerialization.data(withJSONObject: ["answers": [handle.requestID.stringForAudit: ["answers": ["Yes"]]]])
        _ = try await client.submit(handle: handle,result: response)
        _ = await recorder.next() // submission's mandatory fresh snapshot
        fixture.setState(state(requests: [],items: [],partial: true),revision: 8)
        let partial = await recorder.next()
        XCTAssertTrue(partial.interactionProjection?.pendingRequestsAreAuthoritative == true)
        XCTAssertFalse(partial.interactionProjection?.asyncQuestionsAreAuthoritative == true)
        XCTAssertEqual(partial.requests.first,handle)
        do { _ = try await client.submit(handle: handle,result: response); XCTFail("partial page re-enabled send") }
        catch { XCTAssertEqual(error as? CodexDesktopIPCError,.alreadySubmitted) }
        fixture.setState(state(requests: [],items: [question]),revision: 9)
        let full = await recorder.next()
        XCTAssertEqual(full.requests.first,handle)
        do { _ = try await client.submit(handle: handle,result: response); XCTFail("full recovery re-enabled send") }
        catch { XCTAssertEqual(error as? CodexDesktopIPCError,.alreadySubmitted) }
        fixture.setState(state(requests: [],items: []),revision: 10)
        let removed = await recorder.next()
        XCTAssertTrue(removed.requests.isEmpty)
        XCTAssertEqual(fixture.submissionCount,1)
        await client.stop()
    }

    func testExactAcceptedReplyOnPartialPageSettlesOnlyObservedMatchingQuestion() async throws {
        let question: [String: Any] = ["id": "message", "type": "agentMessage", "questions": [["title": "Choose", "options": ["Yes"]]]]
        let fixture = AuditTransportDesktopFixture(state: state(requests: [],items: [question])), recorder = AuditTransportSnapshots()
        let client = fixture.client()
        await client.start(snapshotHandler: { await recorder.record($0) },stateHandler: { _ in })
        try await client.follow(conversationID: "conversation")
        let first = await recorder.next(), handle = try XCTUnwrap(first.requests.first)
        let replyJSON = try JSONSerialization.data(withJSONObject: [["questionItemId": handle.requestID.stringForAudit,"question": "Choose","answer": "Yes"]])
        let text = CodexDesktopRequestProjector.asyncReplyOpeningTag + String(decoding: replyJSON,as: UTF8.self) + CodexDesktopRequestProjector.asyncReplyClosingTag
        let reply: [String: Any] = ["type": "steeringUserMessage","status": "accepted","input": [["type": "text","text": text]]]
        fixture.setState(state(requests: [],items: [question,reply],partial: true),revision: 8)
        let answered = await recorder.next()
        XCTAssertTrue(answered.requests.isEmpty)
        XCTAssertEqual(answered.interactionProjection?.asyncQuestions.first?.resolvedAnswer,"Yes")
        await client.stop()
    }

    func testPartialAcceptedReplyWithoutQuestionSettlesPriorIdentityAndCannotRevive() async throws {
        let question: [String: Any] = ["id": "message", "type": "agentMessage", "questions": [["title": "Choose", "options": ["Yes"]]]]
        let fixture = AuditTransportDesktopFixture(state: state(requests: [], items: [question])), recorder = AuditTransportSnapshots()
        let client = fixture.client()
        await client.start(snapshotHandler: { await recorder.record($0) }, stateHandler: { _ in })
        try await client.follow(conversationID: "conversation")
        let first = await recorder.next(), handle = try XCTUnwrap(first.requests.first)
        let replyJSON = try JSONSerialization.data(withJSONObject: [["questionItemId": handle.requestID.stringForAudit, "question": "Choose", "answer": "Yes"]])
        let text = CodexDesktopRequestProjector.asyncReplyOpeningTag + String(decoding: replyJSON, as: UTF8.self) + CodexDesktopRequestProjector.asyncReplyClosingTag
        let reply: [String: Any] = ["type": "steeringUserMessage", "status": "accepted", "input": [["type": "text", "text": text]]]
        fixture.setState(state(requests: [], items: [reply], partial: true), revision: 8)
        let answered = await recorder.next()
        XCTAssertTrue(answered.requests.isEmpty)
        XCTAssertEqual(answered.interactionProjection?.asyncQuestions.first?.resolvedAnswer, "Yes")
        fixture.setState(state(requests: [], items: [question], partial: true), revision: 9)
        let replayedPage = await recorder.next()
        XCTAssertTrue(replayedPage.requests.isEmpty)
        XCTAssertEqual(replayedPage.interactionProjection?.asyncQuestions.first?.resolvedAnswer, "Yes")
        await client.stop()
    }

    func testPartialKnowledgeCountAndBytesInvalidateOnlyThatConversation() async throws {
        for byteBudget in [false, true] {
            let count = byteBudget ? 1 : 128
            let title = byteBudget ? String(repeating: "a", count: 1_000) : "Choose"
            let firstItems: [[String: Any]] = (0..<count).map { ["id": "a-\($0)", "type": "agentMessage", "questions": [["title": title, "options": ["Yes"]]]] }
            let nextItems: [[String: Any]] = (0..<(byteBudget ? 1 : 129)).map { ["id": "b-\($0)", "type": "agentMessage", "questions": [["title": title, "options": ["Yes"]]]] }
            let fixture = AuditTransportDesktopFixture(state: state(requests: [], items: firstItems)), recorder = AuditTransportSnapshots()
            let client = fixture.client(maximumConversationBytes: byteBudget ? 2_048 : 8 * 1_048_576)
            let invalidated = expectation(description: byteBudget ? "retained byte budget" : "retained count budget")
            await client.start(snapshotHandler: { await recorder.record($0) }, stateHandler: { _ in }, invalidationHandler: { value in
                XCTAssertEqual(value.conversationID, "conversation")
                XCTAssertEqual(value.reason, .resourceLimit)
                invalidated.fulfill()
            })
            try await client.follow(conversationID: "conversation")
            let first = await recorder.next(), handle = try XCTUnwrap(first.requests.first)
            fixture.setState(state(requests: [], items: nextItems, partial: true), revision: 8)
            await fulfillment(of: [invalidated], timeout: 2)
            let response = try JSONSerialization.data(withJSONObject: ["answers": [handle.requestID.stringForAudit: ["answers": ["Yes"]]]])
            do { _ = try await client.submit(handle: handle, result: response); XCTFail("resource-invalidated capability was usable") }
            catch { XCTAssertEqual(error as? CodexDesktopIPCError, .staleRequest) }
            XCTAssertEqual(fixture.submissionCount, 0)
            await client.stop()
        }
    }

    private func state(requests: [[String: Any]]? = nil, items: [[String: Any]] = [],partial: Bool = false) -> [String: Any] {
        let pending = requests ?? [["id": 42,"method": "item/commandExecution/requestApproval",
            "params": ["threadId": "conversation","turnId": "turn","itemId": "item","command": "fixture command"]]]
        var turn: [String: Any] = ["turnId": "turn","status": "inProgress","items": items]
        if partial { turn["itemsPagination"] = ["hasLoadedOldest": false] }
        return ["id": "conversation","source": "appServer","requests": pending,"turns": [turn]]
    }
}

private extension CodexDesktopIPCRequestID {
    var stringForAudit: String { if case .string(let value) = self { return value }; return "" }
}
private actor AuditTransportSnapshots {
    private var queued: [CodexDesktopConversationSnapshot] = []
    private var waiter: CheckedContinuation<CodexDesktopConversationSnapshot,Never>?
    func record(_ snapshot: CodexDesktopConversationSnapshot) {
        if let waiter { self.waiter=nil; waiter.resume(returning:snapshot) } else { queued.append(snapshot) }
    }
    func next() async -> CodexDesktopConversationSnapshot {
        if !queued.isEmpty { return queued.removeFirst() }
        return await withCheckedContinuation { waiter=$0 }
    }
}
private final class AuditTransportDesktopFixture: @unchecked Sendable {
    private let lock=NSLock()
    private var state: [String: Any]
    private var revision=7
    private var owner="fixture-owner"
    private var automaticSnapshots=true
    private var skippedSnapshots=0
    private var follows=0
    private var submitted=0
    private var wrongOwnerAcknowledgement=false
    private var incoming: AsyncStream<Data>.Continuation?
    private var probeWaiters: [String: CheckedContinuation<Void,Never>] = [:]
    private var finishedProbes: Set<String> = []
    init(state: [String: Any]) { self.state=state }
    var submissionCount: Int { lock.withLock { submitted } }
    var followCount: Int { lock.withLock { follows } }
    func skipFirstSnapshot() { lock.withLock { skippedSnapshots=1 } }
    func client(maximumConversationBytes: Int = 8 * 1_048_576) -> CodexDesktopIPCClient {
        .init(configuration: .init(socketURL: URL(fileURLWithPath: "/fixture/ipc.sock"),requestTimeoutSeconds: 1,
            maximumConversationStateBytes: maximumConversationBytes),connector: { [self] _ in
            let pair=AsyncStream<Data>.makeStream()
            lock.withLock { incoming=pair.continuation }
            return .init(chunks: pair.stream,write: { [self] in try receive($0) },close: { pair.continuation.finish() })
        })
    }
    func useWrongOwnerAcknowledgement() { lock.withLock { wrongOwnerAcknowledgement=true } }
    func emitForeignStatus(source: String) { lock.withLock { emit(["type":"broadcast",
        "method":"thread-stream-following-status-requested","version":1,"sourceClientId":source,
        "params":["conversationId":"conversation","hostId":"local"]]) } }
    func setAutomaticSnapshots(_ value: Bool) { lock.withLock { automaticSnapshots=value } }
    func changeProvenOwner(_ value: String) { lock.withLock { owner=value } }
    func setState(_ value: [String: Any],revision: Int) { lock.withLock { state=value; self.revision=revision; snapshot() } }
    func emitForeign(source: String) { lock.withLock { emit(["type":"broadcast","method":"thread-stream-state-changed","version":11,
        "sourceClientId":source,"params":["conversationId":"conversation","hostId":"local","change":["type":"snapshot","revision":revision,"conversationState":state]]]) } }
    func emitProbe(id: String) { lock.withLock { emit(["type":"request","requestId":id,"method":"audit-probe"]) } }
    func waitForProbeResponse(_ id: String) async {
        await withCheckedContinuation { continuation in
            lock.withLock { if finishedProbes.contains(id) { continuation.resume() } else { probeWaiters[id]=continuation } }
        }
    }
    private func receive(_ data: Data) throws {
        var decoder=CodexDesktopIPCFrameDecoder(maximumFrameBytes: 9_437_184)
        for payload in try decoder.append(data) {
            let message=try XCTUnwrap(JSONSerialization.jsonObject(with:payload) as? [String: Any])
            lock.withLock {
                if message["type"] as? String == "response",let id=message["requestId"] as? String {
                    finishedProbes.insert(id); probeWaiters.removeValue(forKey:id)?.resume(); return
                }
                guard let method=message["method"] as? String else { return }
                if message["type"] as? String == "request",let id=message["requestId"] as? String {
                    if method == "initialize" { response(id,method,owner:"fixture-client",result:["clientId":"fixture-client"]) }
                    else if method == "thread-owner-discovery" {
                        if let candidate=message["targetClientId"] as? String,candidate != owner {
                            if wrongOwnerAcknowledgement { response(id,method,owner:owner,result:["supportsUntrustedAppInput":true]) }
                            else { emit(["type":"response","requestId":id,"resultType":"error","error":"no-client-found"]) }
                        } else { response(id,method,owner:owner,result:["supportsUntrustedAppInput":true]) }
                    } else if method.hasPrefix("thread-follower-") {
                        submitted += 1
                        response(id,method,owner:owner,result:method == "thread-follower-steer-turn" ? ["result":["turnId":"turn"]] : ["ok":true])
                    }
                } else if method == "thread-stream-following-changed" {
                    follows += 1
                    if skippedSnapshots > 0 { skippedSnapshots -= 1 }
                    else if automaticSnapshots { snapshot() }
                }
            }
        }
    }
    private func response(_ id: String,_ method: String,owner: String,result: [String: Any]) {
        emit(["type":"response","requestId":id,"method":method,"resultType":"success","handledByClientId":owner,"result":result])
    }
    private func snapshot() { emit(["type":"broadcast","method":"thread-stream-state-changed","sourceClientId":owner,"version":11,
        "params":["conversationId":"conversation","hostId":"local","change":["type":"snapshot","revision":revision,"conversationState":state]]]) }
    private func emit(_ message: [String: Any]) {
        incoming?.yield(try! CodexDesktopIPCFrameDecoder.frame(JSONSerialization.data(withJSONObject:message),maximumFrameBytes:9_437_184))
    }
}
