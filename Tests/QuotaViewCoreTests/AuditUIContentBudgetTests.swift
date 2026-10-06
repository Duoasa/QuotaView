import Foundation
import XCTest
@testable import QuotaView

final class AuditUIContentBudgetTests: XCTestCase {
    private func data(_ method: String, _ params: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: ["method": method, "params": params])
    }
    @MainActor private func start(_ model: IslandLiveStore, turn: String) {
        model.receive(data("turn/started", ["threadId": "thread", "turnId": turn, "turn": ["id": turn]]))
    }
    @MainActor private func item(_ model: IslandLiveStore, text: String, type: String = "agentMessage", id: String = "item", turn: String = "turn") {
        var item: [String: Any] = ["id": id, "type": type, "status": "completed", "phase": "final"]
        if type == "commandExecution" { item["command"] = "fixture"; item["aggregatedOutput"] = text }
        else { item["text"] = text }
        model.receive(data("item/completed", ["threadId": "thread", "turnId": turn, "item": item]))
    }
    @MainActor func testActualTruncationMatchesSavedCharacterBoundary() throws {
        for body in [String(repeating: "a", count: 65_536), String(repeating: "a", count: 65_537),
                     String(repeating: "a", count: 100_000), String(repeating: "a", count: 131_072),
                     String(repeating: "字", count: 65_536), String(repeating: "e\u{301}", count: 65_537)] {
            for type in ["agentMessage", "commandExecution"] {
                let model = IslandLiveStore(); start(model, turn: "turn"); item(model, text: body, type: type)
                let entry = try XCTUnwrap(model.tasks.first?.entries.first)
                let saved = type == "agentMessage" ? entry.text.chinese : entry.publicItem?.output ?? ""
                XCTAssertEqual(saved, String(body.prefix(65_536)))
                XCTAssertEqual(entry.publicItem?.sourceTruncated, body.count > 65_536)
            }
        }
    }
    @MainActor func testOldTurnContextsAreReleasedRatherThanAccumulatingRawOutputs() throws {
        let model = IslandLiveStore()
        for turn in 0..<3 {
            let id = "turn-\(turn)"; start(model, turn: id)
            for itemID in 0..<20 {
                item(model, text: String(repeating: "x", count: 524_288), type: "commandExecution", id: "\(turn)-\(itemID)", turn: id)
            }
            let contexts = try XCTUnwrap(Mirror(reflecting: model).children.first { $0.label == "itemContexts" }?.value as? [String: IslandApprovalJSON])
            XCTAssertLessThanOrEqual(contexts.count, 20)
            XCTAssertFalse(contexts.values.contains { $0["aggregatedOutput"] != .null })
        }
        model.receive(data("thread/closed", ["threadId": "thread"]))
        let contexts = try XCTUnwrap(Mirror(reflecting: model).children.first { $0.label == "itemContexts" }?.value as? [String: IslandApprovalJSON])
        XCTAssertTrue(contexts.isEmpty)
    }
    @MainActor func testPendingFileDiffOwnsOriginalContextThroughContentEviction() throws {
        let model = IslandLiveStore(); start(model, turn: "turn")
        let diff = String(repeating: "original diff\n", count: 30_000)
        model.receive(data("item/completed", ["threadId": "thread", "turnId": "turn", "item": [
            "id": "file", "type": "fileChange", "status": "completed", "changes": [["path": "/fixture", "diff": diff]]]]))
        var request = try JSONSerialization.jsonObject(with: data("item/fileChange/requestApproval", [
            "threadId": "thread", "turnId": "turn", "itemId": "file", "availableDecisions": ["accept", "decline"]])) as! [String: Any]
        request["id"] = 42
        model.receive(try JSONSerialization.data(withJSONObject: request))
        let id = try XCTUnwrap(model.tasks.first?.requests.first?.value.id)
        for number in 0..<40 {
            item(model, text: String(repeating: "字", count: 65_536), type: "commandExecution", id: "output-\(number)")
        }
        let pending = try XCTUnwrap(model.tasks.first?.requests.first)
        XCTAssertEqual(pending.value.id, id)
        XCTAssertEqual(pending.value.protocolRequest?.contextItem?["changes"].array.first?["diff"].text, diff)
        XCTAssertEqual(model.retainedContentBytes, model.contentAccountingOracle)
        XCTAssertLessThanOrEqual(model.retainedContentBytes, 2_097_152)
    }
    @MainActor func testUnknownContextOnlyItemsStillObeyContentBudget() {
        let model = IslandLiveStore(); start(model, turn: "turn")
        for number in 0..<4 {
            model.receive(data("item/started", ["threadId": "thread", "turnId": "turn", "item": [
                "id": "future-\(number)", "type": "futurePublicTool", "arguments": ["value": String(repeating: "x", count: 750_000)]]]))
            XCTAssertLessThanOrEqual(model.retainedContentBytes, 2_097_152)
            XCTAssertEqual(model.retainedContentBytes, model.contentAccountingOracle)
        }
    }
}
