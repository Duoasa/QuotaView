import Foundation
import XCTest
import QuotaViewActivityHookSupport
@testable import QuotaViewCore

final class AuditRolloutPlanCompatibilityTests: XCTestCase {
    private func rollout(_ source: String, name: String = "functions.exec", direct: Bool = false) throws -> CodexActivityPlanProgress? {
        var decoder = CodexLocalRolloutLineDecoder(sessionHash: "fixture", sessionKind: .user)
        func line(_ type: String, _ payload: [String: Any]) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["type": type, "payload": payload])
        }
        _ = decoder.decode(line: try line("event_msg", ["type": "task_started", "turn_id": "one"]))
        let payload = ["type": direct ? "function_call" : "custom_tool_call", "name": name,
                       "call_id": "fixture", direct ? "arguments" : "input": source]
        guard let record = decoder.decode(line: try line("response_item", payload)),
              case .activity(let activity) = record.update else { return nil }
        return activity.planProgress
    }

    func testSharedCorpusThroughHookParserAndActualRolloutLineDecoder() throws {
        let pending = "{plan:[{step:'private text',status:'pending'}]}"
        let completed = "{plan:[{status:'completed'}]}"
        let corpus: [(String, [Int]?)] = [
            ("tools.update_plan({explanation: `Example plan: [{status: 'completed'}]`, plan: [{step: 'real task', status: 'pending'}]})", [0,0,1]),
            ("tools.update_plan({metadata:{plan:[{status:'completed'}]},plan:[{status:'pending'}]})", [0,0,1]),
            ("tools.update_plan({metadata:{plan:[{status:'completed'}]}})", nil),
            ("tools.update_plan({plan:[{status:'pending',status:'completed'}]})", nil),
            ("tools.update_plan({plan:[{status:'pending'}],plan:[{status:'completed'}]})", nil),
            ("// tools.update_plan(\(completed))\n tools.update_plan(\(pending))", [0,0,1]),
            ("'tools.update_plan(\(completed))'; tools.update_plan(\(pending))", [0,0,1]),
            ("tools /*comment*/ . update_plan (\(pending)); tools.update_plan(\(completed))", [1,0,0]),
            ("tools.update_plan({plan:[{status:'future'}]})", nil),
            ("tools.update_plan({plan:[]})", nil),
            ("tools.update_plan({plan:[{status:'inProgress'}]})", [0,1,0]),
            ("tools.update_plan({plan:[{status:'pending'}]}", nil),
            ("tools.update_plan({plan:[" + Array(repeating: "{status:'pending'}", count: 100).joined(separator: ",") + "]})", [0,0,100]),
            ("tools.update_plan({plan:[" + Array(repeating: "{status:'pending'}", count: 101).joined(separator: ",") + "]})", nil),
            (String(repeating: " ", count: 1_048_577) + "tools.update_plan(\(pending))", nil)
        ]
        for (source, expected) in corpus {
            let hook = CodexActivityPlanInputParser.parse(toolName: "functions.exec", toolInput: source)
            let local = try rollout(source)
            XCTAssertEqual(hook.map { [$0.completedSteps, $0.inProgressSteps, $0.pendingSteps] }, expected)
            XCTAssertEqual(local.map { [$0.completedSteps, $0.inProgressSteps, $0.pendingSteps] }, expected)
        }
    }

    func testDirectJSONAdaptersKeepOnlyCounts() throws {
        let object: [String: Any] = ["plan": [["step": "do not publish this", "status": "pending"]]]
        let source = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        let hook = CodexActivityPlanInputParser.parse(toolName: "update_plan", toolInput: object)
        let local = try rollout(source, name: "update_plan", direct: true)
        XCTAssertEqual(hook?.pendingSteps, 1)
        XCTAssertEqual(local?.pendingSteps, 1)
        XCTAssertEqual(local?.completedSteps, 0)
    }
}
