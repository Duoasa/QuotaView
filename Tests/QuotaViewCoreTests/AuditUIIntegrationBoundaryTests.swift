import Foundation
import XCTest
@testable import QuotaView
@testable import QuotaViewCore

@MainActor final class AuditUIIntegrationBoundaryTests: XCTestCase {
    private func data(_ method: String, _ params: [String: Any], id: Any? = nil) throws -> Data {
        var m: [String: Any] = ["method": method, "params": params]
        if let id { m["id"] = id }
        return try JSONSerialization.data(withJSONObject: m, options: [.sortedKeys])
    }
    private func model() throws -> IslandLiveStore {
        let model = IslandLiveStore()
        model.receive(try data("turn/started", ["threadId": "thread", "turnId": "turn", "turn": ["id": "turn"]]))
        return model
    }
    func testTypedRPCIdentityNeverAliasesAdjacentLargeIntegersOrStrings() throws {
        let model = try model()
        let ids: [Any] = [Int64(9_007_199_254_740_992), Int64(9_007_199_254_740_993), Int64.max, "9007199254740993"]
        for id in ids {
            model.receive(try data("item/commandExecution/requestApproval",
                ["threadId": "thread", "turnId": "turn", "command": "fixture", "availableDecisions": ["accept", "decline"]], id: id))
        }
        XCTAssertEqual(model.tasks[0].requests.count, 4)
        XCTAssertEqual(model.tasks[0].requests.compactMap { $0.value.protocolRequest?.rpcIdentity },
            [.integer(9_007_199_254_740_992), .integer(9_007_199_254_740_993), .integer(Int64.max), .string("9007199254740993")])
        for (offset, id) in ids.enumerated() {
            model.receive(try data("serverRequest/resolved", ["threadId": "thread", "turnId": "turn", "requestId": id]))
            XCTAssertEqual(model.tasks[0].requests.count, 3 - offset)
        }
    }
    func testMissingAndFutureFlagsDoNotClearKnownWaitButExplicitEmptyDoes() throws {
        let model = try model()
        func status(_ flags: Any?) throws {
            var status: [String: Any] = ["type": "active"]
            if let flags { status["activeFlags"] = flags }
            model.receive(try data("thread/status/changed", ["threadId": "thread", "turnId": "turn", "status": status]))
        }
        try status(["waitingOnApproval"])
        XCTAssertEqual(model.tasks[0].status, .waiting)
        for flags: Any? in [nil, NSNull(), "wrong", ["futureFlag"], ["waitingOnApproval", "futureFlag"]] {
            try status(flags)
            XCTAssertEqual(model.tasks[0].status, .waiting)
        }
        try status([String]())
        XCTAssertNotEqual(model.tasks[0].status, .waiting)
    }
    func testPartialQuestionPagePreservesPresentationAndExactAcceptedReplySettles() throws {
        var lifecycle = IslandLiveStore.RequestLifecycle()
        let wire = try IslandCodexApprovalRequest(data: data("desktop/tool/requestUserInputAsync",
            ["threadId": "thread", "turnId": "turn", "questions": [["id": "q", "question": "Choose", "isOther": true]]], id: "question"))
        let pending = IslandLiveStore.Pending(key: "question",
            value: .init(question: .init("Choose"), impact: .init(""), protocolRequest: wire, canRespond: false),
            desktopIdentity: .asynchronousQuestion("question"), desktopOwner: "owner", desktopEpoch: 1, mode: .asynchronous)
        lifecycle.observe(pending)
        let id = try XCTUnwrap(lifecycle.visibleRequests.first?.value.id)
        _ = lifecycle.resolveDesktopRequests(owner: "owner", epoch: 1, pending: [], asyncQuestions: [],
            asyncQuestionsAreAuthoritative: false)
        XCTAssertEqual(lifecycle.visibleRequests.first?.value.id, id)
        lifecycle.resolveDesktopAnswers(owner: "other", epoch: 1, answered: ["question"])
        XCTAssertEqual(lifecycle.visibleRequests.first?.value.id, id)
        lifecycle.resolveDesktopAnswers(owner: "owner", epoch: 1, answered: ["question"])
        XCTAssertTrue(lifecycle.visibleRequests.isEmpty)
        lifecycle.observe(pending)
        _ = lifecycle.resolveDesktopRequests(owner: "owner", epoch: 1, pending: [], asyncQuestions: [],
            asyncQuestionsAreAuthoritative: true)
        XCTAssertTrue(lifecycle.visibleRequests.isEmpty)
    }
    func testSparseFallbacksAreBilingualAndServiceContentIsUnchanged() throws {
        let sparse = try IslandCodexApprovalRequest(data: data("item/fileChange/requestApproval", ["threadId": "thread"], id: 1))
        XCTAssertEqual(sparse.titleText.value(false), "Codex 请求你的处理")
        XCTAssertEqual(sparse.titleText.value(true), "Codex requests your input")
        XCTAssertTrue(sparse.detailText.value(false).contains("文件差异"))
        XCTAssertTrue(sparse.detailText.value(true).contains("file diff"))
        let service = "service supplied 原文"
        let real = try IslandCodexApprovalRequest(data: data("item/fileChange/requestApproval",
            ["threadId": "thread", "reason": service, "grantRoot": "/fixture"], id: 2))
        XCTAssertEqual(real.titleText.value(false), service)
        XCTAssertEqual(real.titleText.value(true), service)
        XCTAssertEqual(real.detailText.value(false), "/fixture")
        XCTAssertEqual(real.detailText.value(true), "/fixture")
    }
}
