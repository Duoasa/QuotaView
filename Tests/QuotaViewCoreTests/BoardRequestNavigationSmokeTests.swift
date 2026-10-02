import Foundation
import XCTest
@testable import QuotaView
@testable import QuotaViewCore

final class BoardRequestNavigationSmokeTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_790_888_000)
    private func json(_ method: String, _ params: [String: Any], id: Int? = nil) -> Data {
        var message: [String: Any] = ["method": method, "params": params]
        if let id { message["id"] = id }
        return try! JSONSerialization.data(withJSONObject: message)
    }
    @MainActor
    private func start(_ model: IslandLiveStore, _ thread: String) {
        model.receive(json("turn/started", ["threadId": thread, "turnId": "turn", "turn": ["id": "turn"]]), at: date)
    }
    @MainActor
    private func question(_ model: IslandLiveStore, _ thread: String, id: Int) {
        model.receive(json("item/tool/requestUserInput", ["threadId": thread, "turnId": "turn", "itemId": "call-\(id)",
            "questions": [["id": "scope", "header": "范围", "question": "这次修改哪个应用？", "isOther": true,
                "options": [["label": "DSH", "description": "仅修改 DSH"], ["label": "两个应用", "description": "分别修改"]]]]], id: id), at: date)
    }
    @MainActor
    private func update(_ board: IslandBoardState, _ model: IslandLiveStore, automatic: Bool = true) {
        var display = model.display(english: false, remaining: nil, enabled: true, privacy: false)
        display.automaticPopupEnabled = automatic
        board.update(display, reduceMotion: true, now: date)
    }

    @MainActor
    func testNewRequestOpensItsDetailFromOrdinaryContentAndRefreshDoesNotReopenIt() throws {
        let model = IslandLiveStore(); let board = IslandBoardState()
        start(model, "ordinary"); start(model, "request"); update(board, model)
        let ordinary = model.tasks[0].id, requested = model.tasks[1].id
        board.select(ordinary)
        var selected: [Int] = []
        board.onSelect = { selected.append($0); model.select($0) }
        question(model, "request", id: 1); update(board, model)
        XCTAssertEqual(board.detailID, requested)
        XCTAssertEqual(board.approval?.task.id, requested)
        XCTAssertEqual(selected, [requested])
        XCTAssertFalse(board.compact)
        let wire = try XCTUnwrap(board.approval?.request.protocolRequest)
        XCTAssertEqual(wire.questions[0].id, "scope")
        XCTAssertEqual(wire.questions[0].title, "这次修改哪个应用？")
        board.dismissDetail(); update(board, model); update(board, model)
        XCTAssertNil(board.detailID, "The same pending request must not reopen on polling")
        XCTAssertEqual(selected, [requested])
    }

    @MainActor
    func testParallelRequestsKeepCurrentDraftAndQueueSwitchUntilExternalResolution() throws {
        let model = IslandLiveStore(); let board = IslandBoardState()
        start(model, "A"); start(model, "B"); update(board, model)
        question(model, "A", id: 1); update(board, model)
        let task = try XCTUnwrap(board.approval?.task.id)
        let first = try XCTUnwrap(board.approval?.request.id)
        var draft = IslandApprovalDraft(); draft.values["scope"] = "保留正在填写的内容"
        board.approvalDraftBinding(for: first).wrappedValue = draft
        question(model, "B", id: 2); question(model, "A", id: 3); update(board, model)
        XCTAssertEqual(board.approval?.request.id, first)
        XCTAssertEqual(board.approval?.request.queueCount, 2)
        XCTAssertEqual(board.approvalDraftBinding(for: first).wrappedValue, draft)
        model.receive(json("serverRequest/resolved", ["threadId": "B", "turnId": "turn", "requestId": 2])); update(board, model)
        XCTAssertEqual(board.approval?.request.id, first, "B resolving cannot close A's detail")
        model.nextRequest(task); update(board, model)
        XCTAssertNotEqual(board.approval?.request.id, first)
        XCTAssertEqual(board.approval?.request.queueIndex, 2)
        XCTAssertEqual(board.approvalDraftBinding(for: first).wrappedValue, draft)
        model.receive(json("serverRequest/resolved", ["threadId": "A", "turnId": "turn", "requestId": 3])); update(board, model)
        XCTAssertEqual(board.approval?.request.id, first)
        XCTAssertEqual(board.approvalDraftBinding(for: first).wrappedValue, draft)
        model.receive(json("serverRequest/resolved", ["threadId": "A", "turnId": "turn", "requestId": 1])); update(board, model)
        XCTAssertNil(board.approval); XCTAssertNil(board.detailID)
        XCTAssertTrue(board.approvalDraftBinding(for: first).wrappedValue.values.isEmpty)
    }

    @MainActor
    func testDisabledPopupUsageResetAndPinnedPagesKeepTheirNavigation() {
        let model = IslandLiveStore(); let manual = IslandBoardState()
        start(model, "manual"); update(manual, model, automatic: false)
        question(model, "manual", id: 1); update(manual, model, automatic: false)
        XCTAssertTrue(manual.compact); XCTAssertNil(manual.detailID)

        let usage = IslandBoardState(); update(usage, model); usage.dismissDetail(); usage.openUsage()
        start(model, "usage"); question(model, "usage", id: 2); update(usage, model)
        XCTAssertTrue(usage.showsUsage); XCTAssertNil(usage.approval)
        usage.openReset()
        start(model, "reset"); question(model, "reset", id: 3); update(usage, model)
        XCTAssertTrue(usage.showsReset); XCTAssertTrue(usage.showsUsage); XCTAssertNil(usage.approval)

        let pinned = IslandBoardState(); pinned.pin(); update(pinned, model)
        XCTAssertEqual(pinned.presentation, .pinned); XCTAssertNil(pinned.detailID)
        start(model, "pinned"); question(model, "pinned", id: 4); update(pinned, model)
        XCTAssertEqual(pinned.presentation, .pinned); XCTAssertNil(pinned.detailID)
    }

    @MainActor
    func testUnknownWaitDoesNotInventDetailButItsTypedRequestOpensOnce() {
        let model = IslandLiveStore(); let board = IslandBoardState()
        start(model, "details"); update(board, model)
        model.receiveLegacy(.init(event: .permissionRequest,
            sessionHash: CodexActivityPrivacy.hashIdentifier("details"), turnHash: CodexActivityPrivacy.hashIdentifier("turn"),
            sessionKind: .user, source: .hook, toolCallHash: CodexActivityPrivacy.hashIdentifier("call-1"), occurredAt: date))
        update(board, model)
        XCTAssertNil(board.detailID, "Missing details must not invent a confirmation form")
        question(model, "details", id: 1); update(board, model)
        XCTAssertEqual(board.approval?.request.protocolRequest?.kind, .questions)
        board.dismissDetail(); update(board, model)
        XCTAssertNil(board.detailID)
    }
}
