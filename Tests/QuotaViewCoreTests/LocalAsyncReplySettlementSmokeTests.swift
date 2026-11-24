import Foundation
import XCTest
@testable import QuotaView
@testable import QuotaViewCore

/// Hash-only accepted rollout replies settle exactly observed async questions.
/// Fixtures never connect to the user's Codex or dispatch an answer.
@MainActor
final class LocalAsyncReplySettlementSmokeTests: XCTestCase {
    private let session = CodexActivityPrivacy.hashIdentifier("conversation")
    private func makeModel(turn: String = "turn", defaults: UserDefaults? = nil) -> IslandLiveStore {
        let model = IslandLiveStore(archiveDefaults: defaults)
        model.receiveLegacy(.init(event: .userPromptSubmit, sessionHash: session,
            turnHash: CodexActivityPrivacy.hashIdentifier(turn), sessionKind: .user, source: .appServer))
        return model
    }
    private func localQuestion(source: String = "call-fixture", titles: [String], turn: String = "turn", asynchronous: Bool = true) throws -> CodexLocalPublicContent {
        let questions: [[String: Any]] = titles.enumerated().map { index, title in
            ["id": "q\(index)", "title": title, "question": title,
             "options": asynchronous ? ["A", "B"] as Any : [["label": "A"], ["label": "B"]] as Any]
        }
        let arguments = String(decoding: try CodexDesktopIPCClientTests.data(["questions": questions]), as: UTF8.self)
        let line = try CodexDesktopIPCClientTests.data(["type": "response_item", "payload": [
            "type": "function_call", "name": asynchronous ? "functions.request_user_input_async" : "functions.request_user_input",
            "call_id": source, "arguments": arguments]])
        return try XCTUnwrap(CodexLocalPublicContent.decode(line, sessionHash: session,
            activeTurnHash: CodexActivityPrivacy.hashIdentifier(turn)))
    }
    private func acceptedReply(source: String = "call-fixture", questions: [(Int, String)], turn: String = "turn") throws -> CodexLocalPublicContent {
        let values: [[String: String]] = try questions.map { index, title in
            let id = String(decoding: try JSONSerialization.data(withJSONObject: ["request_user_input_async", source, index],
                options: [.withoutEscapingSlashes]), as: UTF8.self)
            return ["questionItemId": id, "question": title, "answer": "private accepted fixture answer"]
        }
        let text = CodexDesktopRequestProjector.asyncReplyOpeningTag + "\n"
            + String(decoding: try CodexDesktopIPCClientTests.data(values), as: UTF8.self)
            + "\n" + CodexDesktopRequestProjector.asyncReplyClosingTag
        let line = try CodexDesktopIPCClientTests.data(["type": "response_item", "payload": [
            "type": "message", "role": "user", "content": [["type": "input_text", "text": text]]]])
        return try XCTUnwrap(CodexLocalPublicContent.decode(line, sessionHash: session,
            activeTurnHash: CodexActivityPrivacy.hashIdentifier(turn)))
    }
    private func nativeItem(source: String = "call-fixture", titles: [String]) -> [String: Any] {
        ["type": "agentMessage", "id": source, "questions": titles.map { ["title": $0, "options": ["A", "B"]] }]
    }
    private func apply(_ snapshot: CodexDesktopConversationSnapshot, to model: IslandLiveStore) throws {
        let projection = try CodexDesktopRequestProjector.project(conversationID: snapshot.conversationID,
            conversationStateData: snapshot.conversationState)
        model.receiveDesktopProjection(projection, snapshot: snapshot)
    }
    private func enableDesktop(_ snapshot: CodexDesktopConversationSnapshot, in model: IslandLiveStore) {
        model.setDesktopConnection(connected: true, epoch: snapshot.connectionEpoch)
        model.responseCapability = { $0.desktopHandle != nil }
        model.respond = { _, _ in XCTFail("Settlement observation must not submit an answer") }
    }

    func testFreshReadOnlyQuestionUpgradesThenStaysSettledAcrossRestart() async throws {
        let suite = "QuotaViewTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let local = try localQuestion(titles: ["Choose?"])
        let model = makeModel(defaults: defaults)
        model.receiveLocalContent(local)
        XCTAssertEqual(model.tasks[0].requests.map(\.value.canRespond), [false])
        let fixture = CodexDesktopIPCFixture(state: CodexDesktopIPCClientTests.state(requests: [],
            items: [nativeItem(titles: ["Choose?"])]))
        let (client, _, snapshot) = try await fixture.connectedClient()
        enableDesktop(snapshot, in: model)
        try apply(snapshot, to: model)
        XCTAssertEqual(model.tasks[0].requests.map(\.value.canRespond), [true])
        model.invalidateDesktopResponses(conversationID: snapshot.conversationID, epoch: snapshot.connectionEpoch)
        model.receiveLocalContent(try acceptedReply(questions: [(0, "Choose?")]))
        let restarted = makeModel(defaults: defaults)
        restarted.receiveLocalContent(local)
        enableDesktop(snapshot, in: restarted)
        try apply(snapshot, to: restarted)
        XCTAssertTrue(restarted.tasks[0].requests.isEmpty)
        restarted.setDesktopConnection(connected: false, epoch: nil)
        let other = try localQuestion(source: "new-call", titles: ["Choose?"])
        restarted.receiveLocalContent(other)
        XCTAssertTrue(restarted.tasks[0].requests.isEmpty, "Historical rollout data cannot overrule the last owner snapshot")
        let fresh = CodexLocalPublicContent(publicSessionHash: other.sessionHash, turnHash: other.turnHash,
                                            data: other.data, occurredAt: Date().addingTimeInterval(1))
        restarted.receiveLocalContent(fresh)
        XCTAssertEqual(restarted.tasks[0].requests.count, 1)
        XCTAssertTrue(fixture.submissions.isEmpty)
        await client.stop()
    }

    func testReadonlyNativeReplySettlesExactQuestionWithoutSendingOrPublishingAnswer() async throws {
        let fixture = CodexDesktopIPCFixture(state: CodexDesktopIPCClientTests.state(requests: [],
            items: [nativeItem(titles: ["First?"])]))
        let (client, _, snapshot) = try await fixture.connectedClient()
        let model = makeModel(); enableDesktop(snapshot, in: model); try apply(snapshot, to: model)
        let request = try XCTUnwrap(model.tasks[0].requestLifecycle.requests.first)
        XCTAssertTrue(request.value.canRespond)
        model.invalidateDesktopResponses(conversationID: snapshot.conversationID, epoch: snapshot.connectionEpoch)
        XCTAssertEqual(model.tasks[0].requestLifecycle.requests.first?.value.id, request.value.id)
        XCTAssertFalse(model.tasks[0].requestLifecycle.requests[0].value.canRespond)
        model.receiveLocalContent(try acceptedReply(questions: [(0, "First?")]))
        XCTAssertTrue(model.tasks[0].requestLifecycle.requests.isEmpty)
        XCTAssertTrue(model.tasks[0].entries.isEmpty, "Private native answer is settlement evidence only")
        XCTAssertTrue(fixture.submissions.isEmpty)
        try apply(snapshot, to: model)
        XCTAssertTrue(model.tasks[0].requestLifecycle.requests.isEmpty, "An unchanged native snapshot cannot resurrect the exact accepted question")
        await client.stop()
    }

    func testParallelNativeQuestionsAndSynchronousRPCSettleIndependently() async throws {
        let sync = CodexDesktopIPCClientTests.request(id: "sync", method: "item/tool/requestUserInput")
        let fixture = CodexDesktopIPCFixture(state: CodexDesktopIPCClientTests.state(requests: [sync],
            items: [nativeItem(titles: ["First?", "Second?"])]))
        let (client, _, snapshot) = try await fixture.connectedClient()
        let model = makeModel(); enableDesktop(snapshot, in: model); try apply(snapshot, to: model)
        XCTAssertEqual(model.tasks[0].requestLifecycle.requests.count, 3)
        let syncID = try XCTUnwrap(model.tasks[0].requestLifecycle.requests.first { $0.mode == .synchronous }?.value.id)
        model.invalidateDesktopResponses(conversationID: snapshot.conversationID, epoch: snapshot.connectionEpoch)
        model.receiveLocalContent(try acceptedReply(questions: [(0, "First?")]))
        XCTAssertEqual(model.tasks[0].requestLifecycle.requests.count, 2)
        XCTAssertEqual(model.tasks[0].requestLifecycle.requests.filter { $0.mode == .asynchronous }.first?.value.protocolRequest?.questions.first?.title, "Second?")
        XCTAssertEqual(model.tasks[0].requestLifecycle.requests.first { $0.mode == .synchronous }?.value.id, syncID)
        XCTAssertEqual(model.tasks[0].status, .waiting)
        model.receiveLocalContent(try acceptedReply(questions: [(1, "Second?")]))
        XCTAssertEqual(model.tasks[0].requestLifecycle.requests.count, 1)
        XCTAssertEqual(model.tasks[0].requestLifecycle.requests[0].value.id, syncID)
        XCTAssertTrue(fixture.submissions.isEmpty)
        await client.stop()
    }

    func testLocalMultiQuestionRequestRemainsUntilEveryExactQuestionIsAnswered() throws {
        let model = makeModel(), request = try localQuestion(titles: ["First?", "Second?"])
        model.receiveLocalContent(request)
        let uuid = try XCTUnwrap(model.tasks[0].requestLifecycle.requests.first?.value.id)
        model.receiveLocalContent(try acceptedReply(questions: [(0, "First?")]))
        XCTAssertEqual(model.tasks[0].requestLifecycle.requests.count, 1)
        XCTAssertEqual(model.tasks[0].requestLifecycle.requests[0].value.id, uuid)
        model.receiveLocalContent(request)
        model.receiveLocalContent(try acceptedReply(questions: [(0, "First?")]))
        XCTAssertEqual(model.tasks[0].requestLifecycle.requests.count, 1)
        model.receiveLocalContent(try acceptedReply(questions: [(1, "Second?")]))
        XCTAssertTrue(model.tasks[0].requestLifecycle.requests.isEmpty)
        model.receiveLocalContent(request)
        XCTAssertTrue(model.tasks[0].requestLifecycle.requests.isEmpty)
    }

    func testWrongSourceIndexOrQuestionTextCannotClearKnownLocalQuestion() throws {
        let model = makeModel(); model.receiveLocalContent(try localQuestion(titles: ["First?"]))
        let uuid = try XCTUnwrap(model.tasks[0].requestLifecycle.requests.first?.value.id)
        let mismatches = [try acceptedReply(source: "other-call", questions: [(0, "First?")]),
                          try acceptedReply(questions: [(1, "First?")]),
                          try acceptedReply(questions: [(0, "Different text")])]
        for reply in mismatches {
            model.receiveLocalContent(reply)
            XCTAssertEqual(model.tasks[0].requestLifecycle.requests.first?.value.id, uuid)
        }
        model.receiveLocalContent(try acceptedReply(questions: [(0, "First?")]))
        XCTAssertTrue(model.tasks[0].requestLifecycle.requests.isEmpty)
    }

    func testReplyBeforeObservedQuestionDoesNotCreateFutureSettlementTombstone() throws {
        let model = makeModel(), reply = try acceptedReply(questions: [(0, "First?")])
        model.receiveLocalContent(reply)
        model.receiveLocalContent(try localQuestion(titles: ["First?"]))
        XCTAssertEqual(model.tasks[0].requestLifecycle.requests.count, 1)
        model.receiveLocalContent(reply)
        XCTAssertTrue(model.tasks[0].requestLifecycle.requests.isEmpty)
        XCTAssertTrue(model.tasks[0].entries.isEmpty)
    }

    func testAnsweredQuestionStaysHiddenAfterRelaunchAndNativeReplay() async throws {
        let suite = "QuotaViewTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let request = try localQuestion(titles: ["Restart?"])
        let first = makeModel(defaults: defaults)
        first.receiveLocalContent(request)
        first.receiveLocalContent(try acceptedReply(questions: [(0, "Restart?")]))
        let second = makeModel(defaults: defaults)
        second.receiveLocalContent(request)
        XCTAssertTrue(second.tasks[0].requests.isEmpty)
        let fixture = CodexDesktopIPCFixture(state: CodexDesktopIPCClientTests.state(requests: [],
            items: [nativeItem(titles: ["Restart?", "Another question?"])]))
        let (client, _, snapshot) = try await fixture.connectedClient()
        enableDesktop(snapshot, in: second)
        try apply(snapshot, to: second)
        XCTAssertEqual(second.tasks[0].requests.map { $0.value.question.chinese }, ["Another question?"])
        XCTAssertTrue(fixture.submissions.isEmpty)
        await client.stop()
    }

    func testReadonlyAsyncQuestionStillExpiresAfterDraftInteraction() throws {
        let model = makeModel()
        model.receiveLocalContent(try localQuestion(titles: ["Restart?"]))
        let task = try XCTUnwrap(model.tasks.first)
        let request = try XCTUnwrap(task.requests.first?.value)
        XCTAssertFalse(request.canRespond)
        let now = Date()
        _ = model.display(english: true, remaining: nil, enabled: true, privacy: false, at: now)
        model.claimConfirmation(taskID: task.id, requestID: request.id)
        _ = model.display(english: true, remaining: nil, enabled: true, privacy: false, at: now.addingTimeInterval(31))
        XCTAssertTrue(model.tasks[0].requests.isEmpty)
    }

    func testStartupReplayShowsOnlyQuestionsStillAwaitingAnAnswer() throws {
        var replay = CodexLocalPublicReplayBuffer()
        let first = try localQuestion(titles: ["Restart?", "Proceed?"])
        let other = try localQuestion(source: "another-call", titles: ["Restart?"])
        replay.append(first, isAssistantMessage: false)
        replay.append(other, isAssistantMessage: false)
        replay.append(try acceptedReply(questions: [(0, "Restart?")]), isAssistantMessage: false, isAcceptedReply: true)
        XCTAssertEqual(replay.contentsForDelivery.first?.data, first.data)
        replay.append(try acceptedReply(questions: [(1, "Proceed?")]), isAssistantMessage: false, isAcceptedReply: true)
        let delivered = replay.contentsForDelivery.map(\.data)
        XCTAssertFalse(delivered.contains(first.data))
        let model = makeModel()
        for content in replay.contentsForDelivery { model.receiveLocalContent(content) }
        model.receiveLocalContent(first)
        XCTAssertEqual(model.tasks[0].requests.count, 1)
        XCTAssertEqual(model.tasks[0].requests.first?.value.protocolRequest?.localObservation?.callID, "another-call")
    }

    func testHistoricalTurnReplyAndReplayedRequestCannotAffectCurrentTurn() throws {
        let model = makeModel(), oldRequest = try localQuestion(titles: ["First?"])
        let oldReply = try acceptedReply(questions: [(0, "First?")])
        model.receiveLocalContent(oldRequest); model.receiveLocalContent(oldReply)
        model.receiveLegacy(.init(event: .userPromptSubmit, sessionHash: session,
            turnHash: CodexActivityPrivacy.hashIdentifier("next-turn"), sessionKind: .user, source: .appServer))
        model.receiveLocalContent(try localQuestion(titles: ["First?"], turn: "next-turn"))
        let uuid = try XCTUnwrap(model.tasks[0].requestLifecycle.requests.first?.value.id)
        model.receiveLocalContent(oldReply); model.receiveLocalContent(oldRequest)
        XCTAssertEqual(model.tasks[0].requestLifecycle.requests.count, 1)
        XCTAssertEqual(model.tasks[0].requestLifecycle.requests[0].value.id, uuid)
        model.receiveLocalContent(try acceptedReply(questions: [(0, "First?")], turn: "next-turn"))
        XCTAssertTrue(model.tasks[0].requestLifecycle.requests.isEmpty)
    }

    func testAsyncReplyCannotResolveSynchronousLocalQuestionOrAnonymousWait() throws {
        let model = makeModel()
        model.receiveLocalContent(try localQuestion(source: "sync-call", titles: ["Sync?"], asynchronous: false))
        model.receiveLocalContent(try localQuestion(titles: ["First?"]))
        model.receiveLegacy(.init(event: .permissionRequest, sessionHash: session,
            turnHash: CodexActivityPrivacy.hashIdentifier("turn"), sessionKind: .user, source: .hook))
        XCTAssertTrue(model.tasks[0].requestLifecycle.waitingOnSource)
        model.receiveLocalContent(try acceptedReply(source: "sync-call", questions: [(0, "Sync?")]))
        XCTAssertEqual(model.tasks[0].requestLifecycle.requests.count, 2)
        model.receiveLocalContent(try acceptedReply(questions: [(0, "First?")]))
        XCTAssertEqual(model.tasks[0].requestLifecycle.requests.count, 1)
        XCTAssertEqual(model.tasks[0].requestLifecycle.requests[0].mode, .synchronous)
        XCTAssertTrue(model.tasks[0].requestLifecycle.waitingOnSource)
        XCTAssertEqual(model.tasks[0].status, .waiting)
    }

    func testRetiredProofCapacityNeverRejectsNewAnswersOrEvictsActiveMultiQuestionProofs() throws {
        let model = makeModel()
        let activeTitles = (0..<32).map { "Active question \($0)?" }
        model.receiveLocalContent(try localQuestion(source: "active-call", titles: activeTitles))
        model.receiveLocalContent(try acceptedReply(source: "active-call",
            questions: Array(activeTitles.enumerated()).dropLast().map { ($0.offset, $0.element) }))
        let activeID = try XCTUnwrap(model.tasks[0].requestLifecycle.requests.first?.value.id)
        for group in 0..<9 {
            let source = "retired-\(group)", titles = (0..<32).map { "Group \(group) question \($0)?" }
            model.receiveLocalContent(try localQuestion(source: source, titles: titles))
            XCTAssertEqual(model.tasks[0].requestLifecycle.requests.count, 2)
            model.receiveLocalContent(try acceptedReply(source: source, questions: Array(titles.enumerated()).map { ($0.offset, $0.element) }))
            XCTAssertEqual(model.tasks[0].requestLifecycle.requests.count, 1,
                           "New observed answers must still settle after more than 256 retired proofs")
            XCTAssertEqual(model.tasks[0].requestLifecycle.requests.first?.value.id, activeID)
        }
        model.receiveLocalContent(try acceptedReply(source: "active-call", questions: [(31, activeTitles[31])]))
        XCTAssertTrue(model.tasks[0].requestLifecycle.requests.isEmpty,
                      "Older partial proofs of a still-observed multi-question request are protected")
    }
}
