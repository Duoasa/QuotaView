import Foundation
import XCTest
@testable import QuotaViewCore

final class AuditTransportProjectionTests: XCTestCase {
    func testPartialItemsKeepSynchronousAuthoritySeparate() throws {
        let complete = try state(items: [question])
        var partial = complete
        partial["turns"] = [["turnId": "turn", "status": "inProgress", "items": [],
                              "itemsPagination": ["hasLoadedOldest": false]]]
        let full = try project(complete), page = try project(partial)
        XCTAssertTrue(full.asyncQuestionsAreAuthoritative)
        XCTAssertTrue(page.pendingRequestsAreAuthoritative)
        XCTAssertFalse(page.asyncQuestionsAreAuthoritative)
        XCTAssertEqual(page.requests.count, 1)
        partial["turns"] = [["turnId": "turn", "status": "completed", "items": [],
                              "itemsPagination": ["hasLoadedOldest": false]]]
        XCTAssertTrue(try project(partial).asyncQuestionsAreAuthoritative)
    }

    func testSharedWaitFlagsAndExactRPCIdentity() throws {
        for raw in [#"{"type":"active"}"#, #"{"type":"active","activeFlags":42}"#,
                    #"{"type":"active","activeFlags":["futureWaitingFlag"]}"#,
                    #"{"type":"active","activeFlags":[true]}"#] {
            XCTAssertEqual(CodexSharedMessageIdentity.waitStatus(statusData: Data(raw.utf8)), .unavailable)
        }
        XCTAssertEqual(CodexSharedMessageIdentity.waitStatus(statusData: Data(#"{"type":"active","activeFlags":[]}"#.utf8)), .running)
        XCTAssertEqual(CodexSharedMessageIdentity.waitStatus(statusData: Data(#"{"type":"active","activeFlags":["waitingOnUserInput"]}"#.utf8)), .waiting(.userInput))
        let ids: [CodexDesktopIPCRequestID] = [.integer(9_007_199_254_740_992), .integer(9_007_199_254_740_993),
                                              .integer(Int64.max), .string("9007199254740993")]
        var decoded = Set<CodexDesktopIPCRequestID>()
        for id in ids {
            let data = try JSONEncoder().encode(["id": id])
            let value = try XCTUnwrap(CodexSharedMessageIdentity.rpcID(messageData: data))
            XCTAssertEqual(value, id); decoded.insert(value)
            let resolved = try JSONEncoder().encode(["requestId": id])
            XCTAssertEqual(CodexSharedMessageIdentity.rpcID(messageData: resolved, field: "requestId"), id)
            XCTAssertEqual(try JSONEncoder().encode(value), try JSONEncoder().encode(id))
        }
        XCTAssertEqual(decoded.count, 4)
    }

    func testIncrementalProjectionMatchesFullOracleWithoutHistoryRescan() throws {
        for count in [100, 1_000, 10_000] {
            var entities: [String: DesktopIPCJSON] = [:]
            var entries: [DesktopIPCJSON] = []
            for i in 0..<count {
                let key = "k\(i)"
                entries.append(.object(["value": .string(key)]))
                entities[key] = .object(["turnId": .string("t\(i)"), "status": .string("completed"), "items": .array([])])
            }
            let tail = "k\(count - 1)", turn = "t\(count - 1)"
            let item: DesktopIPCJSON = .object(["id": .string("a"), "type": .string("agentMessage"), "text": .string("start")])
            entities[tail] = .object(["turnId": .string(turn), "status": .string("inProgress"), "items": .array([item])])
            var tree: DesktopIPCJSON = .object(["id": .string("conversation"), "source": .string("appServer"), "title": .string("A"),
                "requests": .array([]), "turns": .array([]), "turnHistory": .object(["kind": .string("canonical"),
                    "history": .object(["entitiesByKey": .object(entities), "islands": .array([.object([
                        "entries": .array(entries), "newerBoundary": .object(["status": .string("exhausted")])])])])])])
            var cache = CodexDesktopProjectionCache()
            _ = try cache.project(conversationID: "conversation", state: tree, patches: nil)
            let scanned = cache.indexVisitedEntries, built = cache.projectionBuildCount
            let batches: [[DesktopIPCJSON]] = [
                [patch([.string("title")], .string("B"))],
                [patch([.string("turnHistory"), .string("history"), .string("entitiesByKey"), .string(tail), .string("items"), .integer(0), .string("text")], .string("updated"))],
                [patch([.string("requests")], .array([.object(["id": .integer(7), "method": .string("item/tool/requestUserInput"),
                    "params": .object(["threadId": .string("conversation"), "turnId": .string(turn), "questions": .array([])])])]))],
                [patch([.string("requests")], .array([]))],
                [.object(["op": .string("add"), "path": .array([.string("turnHistory"), .string("history"), .string("entitiesByKey"), .string(tail), .string("itemsPagination")]), "value": .object(["hasLoadedOldest": .bool(false)])])],
                [patch([.string("turnHistory"), .string("history"), .string("entitiesByKey"), .string(tail), .string("status")], .string("completed"))]
            ]
            for (index, batch) in batches.enumerated() {
                var byteCount = tree.budgetByteCount
                tree = try DesktopIPCJSON.applying(batch, to: tree, byteCount: &byteCount)
                let incremental = try cache.project(conversationID: "conversation", state: tree, patches: batch)
                let full = try CodexDesktopRequestProjector.project(conversationID: "conversation", state: tree)
                try assertEqual(incremental, full)
                XCTAssertEqual(cache.indexVisitedEntries, scanned)
                if index < 2 { XCTAssertEqual(cache.projectionBuildCount, built) }
            }
            print("AUDIT013 history=\(count) initialIndexVisits=\(scanned) after6Patches=\(cache.indexVisitedEntries) projectionBuilds=\(cache.projectionBuildCount)")
            var small = CodexDesktopProjectionCache()
            let smallTree: DesktopIPCJSON = .object(["id": .string("small"), "source": .string("appServer"),
                "title": .string("small"), "requests": .array([]), "turns": .array([.object([
                    "turnId": .string("small-turn"), "status": .string("inProgress"), "items": .array([])])])])
            _ = try small.project(conversationID: "small", state: smallTree, patches: nil)
            var smallTimes: [Double] = []
            let metadataPatch = [patch([.string("title")], .string("B"))]
            for _ in 0..<100 {
                _ = try cache.project(conversationID: "conversation", state: tree, patches: metadataPatch)
                let start = DispatchTime.now().uptimeNanoseconds
                _ = try small.project(conversationID: "small", state: smallTree, patches: metadataPatch)
                smallTimes.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000)
            }
            smallTimes.sort()
            print("AUDIT013 alternatingLargeHistory=\(count) healthyP95us=\(smallTimes[94]) healthyP99us=\(smallTimes[98])")
            let replacement = patch([.string("turnHistory"), .string("history"), .string("entitiesByKey"), .string(tail), .string("turnId")], .string("new-id"))
            var size = tree.budgetByteCount
            tree = try DesktopIPCJSON.applying([replacement], to: tree, byteCount: &size)
            try assertEqual(cache.project(conversationID: "conversation", state: tree, patches: [replacement]),
                            CodexDesktopRequestProjector.project(conversationID: "conversation", state: tree))
            XCTAssertGreaterThan(cache.indexVisitedEntries, scanned)
        }
    }

    private var question: [String: Any] { ["id": "a", "type": "agentMessage", "questions": [["title": "Choose", "options": ["Yes"]]]] }
    private func state(items: [[String: Any]]) throws -> [String: Any] {
        ["id": "conversation", "source": "appServer", "requests": [["id": 1, "method": "item/tool/requestUserInput",
            "params": ["threadId": "conversation", "turnId": "turn", "questions": []]]],
         "turns": [["turnId": "turn", "status": "inProgress", "items": items]]]
    }
    private func project(_ object: [String: Any]) throws -> CodexDesktopInteractionProjection {
        try CodexDesktopRequestProjector.project(conversationID: "conversation", conversationStateData: JSONSerialization.data(withJSONObject: object))
    }
    private func patch(_ path: [DesktopIPCJSON], _ value: DesktopIPCJSON) -> DesktopIPCJSON {
        .object(["op": .string("replace"), "path": .array(path), "value": value])
    }
    private func assertEqual(_ a: CodexDesktopInteractionProjection, _ b: CodexDesktopInteractionProjection) throws {
        XCTAssertEqual(a.currentTurnID,b.currentTurnID); XCTAssertEqual(a.status,b.status); XCTAssertEqual(a.title,b.title)
        XCTAssertEqual(a.sourceKind,b.sourceKind); XCTAssertEqual(a.startedAt,b.startedAt)
        XCTAssertEqual(a.authoritativePendingIdentities,b.authoritativePendingIdentities)
        XCTAssertEqual(a.pendingRequestsAreAuthoritative,b.pendingRequestsAreAuthoritative)
        XCTAssertEqual(a.asyncQuestionsAreAuthoritative,b.asyncQuestionsAreAuthoritative)
        XCTAssertEqual(a.asyncQuestions,b.asyncQuestions); XCTAssertEqual(a.authoritativeAsyncQuestionIDs,b.authoritativeAsyncQuestionIDs)
        XCTAssertEqual(a.threadWaitStatus,b.threadWaitStatus)
        XCTAssertEqual(a.requests.map(\.envelopeData),b.requests.map(\.envelopeData))
        XCTAssertEqual(a.requests.map(\.contextItemData),b.requests.map(\.contextItemData))
    }
}
