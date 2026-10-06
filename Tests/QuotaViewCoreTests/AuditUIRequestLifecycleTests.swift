import Foundation
import XCTest
@testable import QuotaView

final class AuditUIRequestLifecycleTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_790_888_000)
    private func data(_ method: String, _ params: [String: Any], id: Int? = nil) -> Data {
        var value: [String: Any] = ["method": method, "params": params]
        if let id { value["id"] = id }
        return try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }
    @MainActor private func model() -> IslandLiveStore {
        let model = IslandLiveStore()
        model.receive(data("turn/started", ["threadId": "thread", "turnId": "turn", "turn": ["id": "turn"]]), at: date)
        return model
    }
    @MainActor private func update(_ board: IslandBoardState, _ model: IslandLiveStore) {
        board.update(model.display(english: false, remaining: nil, enabled: true, privacy: false), reduceMotion: true, now: date)
    }
    private func permissions(_ paths: [String], id: Int = 42) -> Data {
        data("item/permissions/requestApproval", ["threadId": "thread", "turnId": "turn",
            "permissions": ["fileSystem": ["read": paths]]], id: id)
    }
    @MainActor func testPermissionRevisionClearsDraftAndRequiresNewSelectionForActualPayload() throws {
        let model = model(), board = IslandBoardState()
        model.receive(permissions(["/A", "/B"]), at: date); update(board, model)
        let old = try XCTUnwrap(board.approval?.request)
        let oldWire = try XCTUnwrap(old.protocolRequest)
        var draft = IslandApprovalDraft(); draft.selections["permissions"] = [oldWire.permissions[0].id]
        board.approvalDraftBinding(for: old.id).wrappedValue = draft
        XCTAssertEqual(draft.result(for: oldWire)?["permissions"]["fileSystem"]["read"], .array([.string("/A")]))
        model.receive(permissions(["/B", "/A"]), at: date); update(board, model)
        let revised = try XCTUnwrap(board.approval?.request)
        XCTAssertNotEqual(revised.id, old.id)
        let newDraft = board.approvalDraftBinding(for: revised.id).wrappedValue
        XCTAssertTrue(newDraft.selections.isEmpty)
        XCTAssertNil(newDraft.result(for: try XCTUnwrap(revised.protocolRequest)))
        XCTAssertTrue(board.approvalDraftBinding(for: old.id).wrappedValue.selections.isEmpty)
    }
    @MainActor func testIdenticalReplayKeepsDraftAndQueuePosition() throws {
        let model = model(), board = IslandBoardState()
        model.receive(permissions(["/A", "/B"]), at: date); update(board, model)
        let original = try XCTUnwrap(board.approval?.request)
        var draft = IslandApprovalDraft(); draft.sessionScope = true
        board.approvalDraftBinding(for: original.id).wrappedValue = draft
        model.receive(permissions(["/A", "/B"]), at: date); update(board, model)
        XCTAssertEqual(board.approval?.request.id, original.id)
        XCTAssertEqual(board.approvalDraftBinding(for: original.id).wrappedValue, draft)
    }
    @MainActor func testResolvingPrecedingRequestPreservesMiddleRequestAndDraft() throws {
        let model = model(), board = IslandBoardState()
        for id in 1...3 { model.receive(permissions(["/\(id)"], id: id), at: date) }
        let task = try XCTUnwrap(model.tasks.first?.id)
        model.nextRequest(task); update(board, model)
        let selected = try XCTUnwrap(board.approval?.request.id)
        var draft = IslandApprovalDraft(); draft.sessionScope = true
        board.approvalDraftBinding(for: selected).wrappedValue = draft
        model.receive(data("serverRequest/resolved", ["threadId": "thread", "turnId": "turn", "requestId": 1]), at: date)
        update(board, model)
        XCTAssertEqual(board.approval?.request.id, selected)
        XCTAssertEqual(board.approval?.request.queueIndex, 1)
        XCTAssertEqual(board.approvalDraftBinding(for: selected).wrappedValue, draft)
    }
    @MainActor func testQuestionContentAndSecretRevisionNeverMigratesAnswer() throws {
        let model = model(), board = IslandBoardState()
        for secret in [false, true] {
            model.receive(data("item/tool/requestUserInput", ["threadId": "thread", "turnId": "turn",
                "questions": [["id": "same", "question": "Value", "isSecret": secret, "isOther": true]]], id: 42), at: date)
            update(board, model)
            let request = try XCTUnwrap(board.approval?.request)
            if secret { XCTAssertTrue(board.approvalDraftBinding(for: request.id).wrappedValue.values.isEmpty) }
            else {
                var draft = IslandApprovalDraft(); draft.values["same"] = "private answer"
                board.approvalDraftBinding(for: request.id).wrappedValue = draft
            }
        }
    }
    func testPermissionIDsFollowSemanticValueRatherThanPosition() throws {
        let a = try IslandCodexApprovalRequest(data: permissions(["/A", "/B"]))
        let b = try IslandCodexApprovalRequest(data: permissions(["/B", "/A"]))
        XCTAssertEqual(a.permissions[0].id, b.permissions[1].id)
        XCTAssertNotEqual(a.permissions[0].id, b.permissions[0].id)
    }
    func testExternalPatternsFallBackWithoutEvaluatingRegex() {
        for pattern in ["^[a-z]+$", "^(a+)+$", "(a|aa)+$", "[", String(repeating: "a", count: 20_000)] {
            let field = IslandApprovalField(id: "value", schema: .object(["type": .string("string"), "pattern": .string(pattern)]), required: true)
            XCTAssertFalse(field.supported)
        }
        XCTAssertTrue(IslandApprovalField(id: "value", schema: .object(["type": .string("string")]), required: true).supported)
    }
}
