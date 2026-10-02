import Combine
import Foundation
import SwiftUI
import XCTest
@testable import QuotaView
@testable import QuotaViewCore

@MainActor
final class FocusedQuestionInteractionEntrySmokeTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_790_888_000)
    private func question(_ id: String = "input", other: Bool = true) -> [String: Any] {
        ["id": id, "method": "item/tool/requestUserInput", "params": [
            "threadId": "conversation", "turnId": "turn", "itemId": "item-" + id,
            "questions": [["id": "q", "question": "Choose?", "isOther": other,
                "options": [["label": "A"], ["label": "B"]]]]]]
    }
    private func apply(_ model: IslandLiveStore, _ snapshot: CodexDesktopConversationSnapshot) throws {
        model.receiveDesktopProjection(try CodexDesktopRequestProjector.project(
            conversationID: snapshot.conversationID, conversationStateData: snapshot.conversationState),
            snapshot: snapshot)
    }
    private func update(_ board: IslandBoardState, _ model: IslandLiveStore) {
        board.update(model.display(english: false, remaining: nil, enabled: true, privacy: false, at: date),
            reduceMotion: true, now: date)
    }
    private func model(_ snapshot: CodexDesktopConversationSnapshot, client: CodexDesktopIPCClient) throws -> IslandLiveStore {
        let model = IslandLiveStore()
        model.receiveLegacy(.init(event: .userPromptSubmit,
            sessionHash: CodexActivityPrivacy.hashIdentifier("conversation"),
            turnHash: CodexActivityPrivacy.hashIdentifier("turn"), sessionKind: .user,
            source: .appServer, occurredAt: date))
        model.setDesktopConnection(connected: true, epoch: snapshot.connectionEpoch)
        model.responseCapability = { wire in
            guard snapshot.supportsUntrustedAppInput, let handle = wire.desktopHandle else { return false }
            return handle.ownerClientID == snapshot.ownerClientID && handle.connectionEpoch == snapshot.connectionEpoch
        }
        model.respond = { wire, result in
            _ = try await client.submit(handle: try XCTUnwrap(wire.desktopHandle), result: result.data)
        }
        try apply(model, snapshot)
        return model
    }
    private func attach(_ board: IslandBoardState, to model: IslandLiveStore) {
        model.onChange = { [weak board, weak model] in
            guard let board, let model else { return }
            board.update(model.display(english: false, remaining: nil, enabled: true, privacy: false, at: self.date),
                reduceMotion: true, now: self.date)
        }
        update(board, model)
    }
    // Construct the production View with the real Board-owned binding, then use
    // the very same entry that its option, TextField, Confirm and Skip call.
    private func view(_ board: IslandBoardState, request: IslandConfirmation? = nil) throws -> IslandApprovalView {
        let approval = try XCTUnwrap(board.approval)
        let request = request ?? approval.request
        return IslandApprovalView(task: approval.task, metadata: nil, request: request,
            metrics: board.approvalMetrics(request: request), english: false,
            visible: true, playbackEnabled: false, reduceMotion: true, scrollLink: IslandTaskScrollLink(),
            draft: board.approvalDraftBinding(for: request.id),
            onDecision: { requestID, decision in board.onConfirmation?(approval.task.id, requestID, decision) })
    }
    private func wait(_ predicate: () -> Bool) async throws {
        for _ in 0..<200 { if predicate() { return }; try await Task.sleep(nanoseconds: 5_000_000) }
        throw CodexDesktopIPCError.unavailable
    }

    func testRealUnixShortFrameToProductionViewPublishesBoardDraftThenConfirmsOnce() async throws {
        let state = CodexDesktopIPCClientTests.data(CodexDesktopIPCClientTests.state(requests: [question()]))
        XCTAssertLessThan(state.count, 8_192)
        let fixture = try CodexDesktopUnixPeerFixture(state: state)
        defer { fixture.stop() }
        let client = CodexDesktopIPCClient(configuration: .init(socketURL: fixture.socketURL, requestTimeoutSeconds: 1))
        let recorder = CodexDesktopIPCSnapshotRecorder()
        await client.start(snapshotHandler: { await recorder.record($0) }, stateHandler: { await recorder.recordState($0) })
        try await client.follow(conversationID: "conversation")
        let snapshot = try await recorder.wait(after: 0)
        XCTAssertTrue(fixture.wasPeerOpenWhenSnapshotSent, "A live socket must deliver short frames before EOF")
        let model = try model(snapshot, client: client), board = IslandBoardState()
        var decisions: [(Int, UUID, IslandConfirmationDecision)] = []
        board.onConfirmation = { taskID, requestID, decision in
            decisions.append((taskID, requestID, decision))
            model.submit(taskID, requestID: requestID, decision: decision)
        }
        attach(board, to: model)
        let pending = try XCTUnwrap(board.approval), id = pending.request.id
        let entry = try view(board).questionInteraction
        var publications = 0
        let subscription = board.objectWillChange.sink { publications += 1 }
        XCTAssertTrue(entry.canEdit); XCTAssertTrue(entry.canSkip); XCTAssertFalse(entry.canConfirm)
        XCTAssertTrue(entry.choose("A", questionID: "q"))
        XCTAssertTrue(entry.isSelected("A", questionID: "q"))
        XCTAssertEqual(board.approvalDraftBinding(for: id).wrappedValue.selections["q"], ["A"])
        XCTAssertTrue(try view(board).questionInteraction.isSelected("A", questionID: "q"))
        XCTAssertTrue(entry.canConfirm)
        XCTAssertTrue(entry.chooseCustom(questionID: "q"))
        XCTAssertTrue(entry.isCustomSelected(questionID: "q")); XCTAssertFalse(entry.canConfirm)
        let typed = "自己的回答\nwith exact whitespace  "
        entry.answerBinding(questionID: "q").wrappedValue = typed
        XCTAssertEqual(board.approvalDraftBinding(for: id).wrappedValue.values["q"], typed)
        XCTAssertTrue(entry.isCustomSelected(questionID: "q")); XCTAssertTrue(entry.isAnswered(questionID: "q"))
        XCTAssertTrue(entry.canConfirm)
        XCTAssertTrue(entry.choose("B", questionID: "q")); XCTAssertFalse(entry.isCustomSelected(questionID: "q"))
        XCTAssertTrue(entry.chooseCustom(questionID: "q"))
        XCTAssertEqual(entry.answerBinding(questionID: "q").wrappedValue, typed)
        XCTAssertGreaterThanOrEqual(publications, 5, "Published Board writes drive selection/text feedback")
        XCTAssertTrue(decisions.isEmpty); XCTAssertTrue(fixture.submissions.isEmpty)
        try apply(model, snapshot); update(board, model)
        XCTAssertEqual(board.approval?.request.id, id)
        XCTAssertTrue(try view(board).questionInteraction.isCustomSelected(questionID: "q"))
        board.collapse(); update(board, model)
        XCTAssertEqual(board.approvalDraftBinding(for: id).wrappedValue.values["q"], typed)
        board.select(pending.task.id)
        XCTAssertTrue(try view(board).questionInteraction.confirm())
        XCTAssertFalse(try view(board).questionInteraction.confirm(), "Submitting phase disables another View send")
        XCTAssertEqual(decisions.count, 1)
        XCTAssertEqual(decisions.first?.0, pending.task.id); XCTAssertEqual(decisions.first?.1, id)
        try await wait { model.tasks[0].requests.first?.value.phase == .sent }
        XCTAssertFalse(try view(board).questionInteraction.confirm())
        XCTAssertEqual(decisions.count, 1); XCTAssertEqual(fixture.submissions.count, 1)
        let params = try XCTUnwrap(fixture.submissions.first?["params"] as? [String: Any])
        let response = try XCTUnwrap(params["response"] as? [String: Any])
        let answers = try XCTUnwrap(response["answers"] as? [String: [String: [String]]])
        XCTAssertEqual(answers["q"]?["answers"], [typed])
        withExtendedLifetime(subscription) {}
        await client.stop()
    }

    func testReadonlyAndInactiveViewCallbacksPreserveExistingBoardDraft() async throws {
        let fixture = CodexDesktopIPCFixture(state: CodexDesktopIPCClientTests.state(requests: [question()]))
        let (client, _, snapshot) = try await fixture.connectedClient()
        let model = try model(snapshot, client: client), board = IslandBoardState()
        var decisions = 0
        board.onConfirmation = { _, _, _ in decisions += 1 }
        attach(board, to: model)
        let original = try XCTUnwrap(board.approval?.request), entry = try view(board).questionInteraction
        XCTAssertTrue(entry.edit("保留自填内容", questionID: "q"))
        XCTAssertTrue(entry.choose("A", questionID: "q"))
        let saved = board.approvalDraftBinding(for: original.id).wrappedValue
        var readonly = original; readonly.canRespond = false
        var unsupported = original
        var raw = question(), params = raw["params"] as! [String: Any]
        var questions = params["questions"] as! [[String: Any]]
        questions[0]["multiSelect"] = true; params["questions"] = questions; raw["params"] = params
        unsupported.protocolRequest = try IslandCodexApprovalRequest(data: CodexDesktopIPCClientTests.data(raw))
        var local = original
        local.protocolRequest = try IslandCodexApprovalRequest(localQuestions: questions,
            callID: "local", sessionHash: "conversation", turnHash: "turn")
        var absent = original; absent.protocolRequest = nil
        let phases: [IslandConfirmation.Phase] = [.submitting(.skipQuestion), .sent, .resultUnknown, .resolved]
        let stopped = phases.map { phase -> IslandConfirmation in var value = original; value.phase = phase; return value }
        for request in [readonly, unsupported, local, absent] + stopped {
            let blocked = try view(board, request: request).questionInteraction
            XCTAssertFalse(blocked.canEdit); XCTAssertFalse(blocked.canConfirm); XCTAssertFalse(blocked.canSkip)
            XCTAssertFalse(blocked.choose("B", questionID: "q"))
            XCTAssertFalse(blocked.chooseCustom(questionID: "q"))
            XCTAssertFalse(blocked.edit("must not replace", questionID: "q"))
            blocked.answerBinding(questionID: "q").wrappedValue = "must not replace through TextField"
            XCTAssertFalse(blocked.confirm()); XCTAssertFalse(blocked.skip())
            XCTAssertEqual(board.approvalDraftBinding(for: original.id).wrappedValue, saved)
        }
        XCTAssertTrue(try view(board, request: readonly).questionInteraction.isSelected("A", questionID: "q"))
        XCTAssertEqual(try view(board, request: readonly).questionInteraction.answerBinding(questionID: "q").wrappedValue,
            "保留自填内容")
        model.setDesktopConnection(connected: false, epoch: nil)
        update(board, model)
        XCTAssertFalse(try view(board).questionInteraction.canEdit)
        XCTAssertFalse(try view(board).questionInteraction.edit("disconnected", questionID: "q"))
        XCTAssertEqual(board.approvalDraftBinding(for: original.id).wrappedValue, saved)
        XCTAssertEqual(decisions, 0); XCTAssertTrue(fixture.submissions.isEmpty)
        await client.stop()
    }

    func testOwnerWithoutInputCapabilityKeepsViewReadonlyAndPreservesItsBoardDraft() async throws {
        let fixture = CodexDesktopIPCFixture(state: CodexDesktopIPCClientTests.state(requests: [question()]), supportsInput: false)
        let (client, _, snapshot) = try await fixture.connectedClient()
        XCTAssertFalse(snapshot.supportsUntrustedAppInput)
        let model = try model(snapshot, client: client), board = IslandBoardState()
        var decisions = 0
        board.onConfirmation = { _, _, _ in decisions += 1 }
        attach(board, to: model)
        let request = try XCTUnwrap(board.approval?.request)
        XCTAssertNotNil(request.protocolRequest?.desktopHandle)
        XCTAssertFalse(request.canRespond, "A native identity alone cannot grant the owner's input capability")
        var saved = IslandApprovalDraft(); saved.values["q"] = "existing readonly draft"
        board.approvalDraftBinding(for: request.id).wrappedValue = saved
        let entry = try view(board).questionInteraction
        XCTAssertFalse(entry.canEdit); XCTAssertFalse(entry.canConfirm); XCTAssertFalse(entry.canSkip)
        XCTAssertTrue(entry.isCustomSelected(questionID: "q"))
        XCTAssertFalse(entry.choose("A", questionID: "q")); XCTAssertFalse(entry.chooseCustom(questionID: "q"))
        entry.answerBinding(questionID: "q").wrappedValue = "must not change"
        XCTAssertFalse(entry.confirm()); XCTAssertFalse(entry.skip())
        XCTAssertEqual(board.approvalDraftBinding(for: request.id).wrappedValue, saved)
        XCTAssertEqual(decisions, 0); XCTAssertTrue(fixture.submissions.isEmpty)
        await client.stop()
    }

    func testViewEntryDraftsStayIsolatedAcrossOriginalRequestUUIDsAndRefresh() async throws {
        let fixture = CodexDesktopIPCFixture(state: CodexDesktopIPCClientTests.state(requests: [question("one"), question("two")]))
        let (client, _, snapshot) = try await fixture.connectedClient()
        let model = try model(snapshot, client: client), board = IslandBoardState()
        attach(board, to: model)
        let first = try XCTUnwrap(model.tasks[0].requests.first?.value)
        let second = try XCTUnwrap(model.tasks[0].requests.dropFirst().first?.value)
        let firstEntry = try view(board, request: first).questionInteraction
        let secondEntry = try view(board, request: second).questionInteraction
        XCTAssertTrue(firstEntry.choose("A", questionID: "q"))
        XCTAssertTrue(secondEntry.edit("second draft", questionID: "q"))
        let firstDraft = board.approvalDraftBinding(for: first.id).wrappedValue
        let secondDraft = board.approvalDraftBinding(for: second.id).wrappedValue
        XCTAssertNotEqual(first.id, second.id); XCTAssertNotEqual(firstDraft, secondDraft)
        XCTAssertTrue(firstEntry.isSelected("A", questionID: "q"))
        XCTAssertTrue(secondEntry.isCustomSelected(questionID: "q"))
        try apply(model, snapshot); update(board, model)
        XCTAssertEqual(model.tasks[0].requests.map { $0.value.id }, [first.id, second.id])
        XCTAssertEqual(board.approvalDraftBinding(for: first.id).wrappedValue, firstDraft)
        XCTAssertEqual(board.approvalDraftBinding(for: second.id).wrappedValue, secondDraft)
        XCTAssertFalse(firstEntry.choose("invented", questionID: "q"))
        XCTAssertFalse(firstEntry.choose("A", questionID: "unknown"))
        XCTAssertFalse(firstEntry.chooseCustom(questionID: "unknown"))
        XCTAssertFalse(firstEntry.edit("wrong question", questionID: "unknown"))
        XCTAssertEqual(board.approvalDraftBinding(for: first.id).wrappedValue, firstDraft)
        XCTAssertTrue(fixture.submissions.isEmpty)
        await client.stop()
    }

    func testViewConfirmationRejectsIncompleteAndInvalidDraftWhileRestrictedCustomIsDisabled() async throws {
        let fixture = CodexDesktopIPCFixture(state: CodexDesktopIPCClientTests.state(requests: [question(other: false)]))
        let (client, _, snapshot) = try await fixture.connectedClient()
        let model = try model(snapshot, client: client), board = IslandBoardState()
        var decisions = 0
        board.onConfirmation = { _, _, _ in decisions += 1 }
        attach(board, to: model)
        let request = try XCTUnwrap(board.approval?.request), entry = try view(board).questionInteraction
        XCTAssertFalse(entry.confirm()); XCTAssertFalse(entry.chooseCustom(questionID: "q"))
        XCTAssertFalse(entry.edit("custom unavailable", questionID: "q"))
        entry.answerBinding(questionID: "q").wrappedValue = "unavailable through input binding"
        XCTAssertTrue(board.approvalDraftBinding(for: request.id).wrappedValue.values.isEmpty)
        var invalid = IslandApprovalDraft(); invalid.selections["q"] = ["A", "invented"]
        board.approvalDraftBinding(for: request.id).wrappedValue = invalid
        XCTAssertFalse(entry.canConfirm); XCTAssertFalse(entry.confirm()); XCTAssertEqual(decisions, 0)
        XCTAssertTrue(fixture.submissions.isEmpty)
        XCTAssertTrue(entry.choose("B", questionID: "q")); XCTAssertTrue(entry.canConfirm)
        XCTAssertTrue(entry.confirm()); XCTAssertEqual(decisions, 1)
        await client.stop()
    }

    func testNativeSkipUsesTheSameViewEntryAndEmptyAnswersWithoutDraftMutation() async throws {
        let fixture = CodexDesktopIPCFixture(state: CodexDesktopIPCClientTests.state(requests: [question()]))
        let (client, _, snapshot) = try await fixture.connectedClient()
        let model = try model(snapshot, client: client), board = IslandBoardState()
        var decisions: [IslandConfirmationDecision] = []
        board.onConfirmation = { taskID, requestID, decision in
            decisions.append(decision); model.submit(taskID, requestID: requestID, decision: decision)
        }
        attach(board, to: model)
        let id = try XCTUnwrap(board.approval?.request.id), entry = try view(board).questionInteraction
        XCTAssertTrue(entry.edit("draft not sent by Skip", questionID: "q"))
        let saved = board.approvalDraftBinding(for: id).wrappedValue
        XCTAssertTrue(entry.skip()); XCTAssertEqual(decisions, [.skipQuestion])
        XCTAssertFalse(try view(board).questionInteraction.skip())
        try await wait { model.tasks[0].requests.first?.value.phase == .sent }
        XCTAssertEqual(board.approvalDraftBinding(for: id).wrappedValue, saved)
        XCTAssertEqual(fixture.submissions.count, 1)
        let params = try XCTUnwrap(fixture.submissions.first?["params"] as? [String: Any])
        let response = try XCTUnwrap(params["response"] as? [String: Any])
        XCTAssertEqual((response["answers"] as? [String: Any])?.count, 0)
        await client.stop()
    }

    func testAsyncSkipUsesTheSameViewEntryWithoutNativeAnswerOrSettlement() async throws {
        let blocker = CodexDesktopIPCClientTests.request(id: "approval")
        let asyncItem: [String: Any] = ["type": "agentMessage", "id": "async", "questions": [["title": "Choose?", "options": ["A", "B"]]]]
        let fixture = CodexDesktopIPCFixture(state: CodexDesktopIPCClientTests.state(requests: [blocker], items: [asyncItem]))
        let (client, _, snapshot) = try await fixture.connectedClient()
        let model = try model(snapshot, client: client), board = IslandBoardState()
        var decisions: [IslandConfirmationDecision] = []
        board.onConfirmation = { taskID, requestID, decision in
            decisions.append(decision); model.submit(taskID, requestID: requestID, decision: decision)
        }
        attach(board, to: model)
        let pending = try XCTUnwrap(model.tasks[0].requests.first { $0.mode == .asynchronous })
        let entry = try view(board, request: pending.value).questionInteraction
        let questionID = try XCTUnwrap(pending.value.protocolRequest?.questions.first?.id)
        XCTAssertTrue(entry.edit("not an answer yet", questionID: questionID))
        XCTAssertTrue(entry.canSkip); XCTAssertTrue(entry.skip())
        XCTAssertEqual(decisions, [.skipQuestion]); XCTAssertTrue(fixture.submissions.isEmpty)
        XCTAssertEqual(model.tasks[0].requests.count, 1)
        XCTAssertTrue(model.tasks[0].requestLifecycle.hasBlockingRequest)
        XCTAssertTrue(model.tasks[0].requestLifecycle.resolvedCallHashes.isEmpty)
        try apply(model, snapshot); update(board, model)
        XCTAssertEqual(model.tasks[0].requests.count, 1, "Skipped async prompt does not reopen on the same snapshot")
        XCTAssertTrue(fixture.submissions.isEmpty)
        await client.stop()
    }
}
