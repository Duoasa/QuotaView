import Foundation
import XCTest
import QuotaViewActivityHookSupport
@testable import QuotaViewCore

final class AuditLifecyclePrivacyRuleTests: XCTestCase {
    func testPureHelperAndCoreRulesShareGoalPrecedenceHashesAndPathBounds() {
        let corpus: [(String?, String?)] = [(nil,nil), ("",nil), ("Bash","shell"), ("exec_command","shell"),
            ("apply_patch","fileEdit"), ("Agent","subagent"), ("spawn_agent","subagent"),
            ("subagent_future","subagent"), ("mcp__functions__update_goal","goal"),
            ("mcp__functions__create_goal","goal"), ("mcp__functions__get_goal","goal"),
            ("update_goal","goal"), ("mcp__unknown","mcp"), ("functions.request_user_input_async","localTool")]
        for (name, expected) in corpus {
            XCTAssertEqual(CodexActivityPrivacyRules.toolCategoryRawValue(for: name), expected)
            XCTAssertEqual(CodexActivityPrivacy.toolCategory(for: name)?.rawValue, expected)
        }
        XCTAssertEqual(CodexActivityPrivacyRules.hashIdentifier("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        for identifier in ["", "abc", "中文/fixture"] {
            XCTAssertEqual(CodexActivityPrivacyRules.hashIdentifier(identifier), CodexActivityPrivacy.hashIdentifier(identifier))
        }
        for path: String? in [nil, "", "/fixture/a/../target", "/" + String(repeating: "文", count: 90)] {
            XCTAssertEqual(CodexActivityPrivacyRules.workspaceName(from: path), CodexActivityPrivacy.workspaceName(from: path))
            XCTAssertLessThanOrEqual(CodexActivityPrivacyRules.workspaceName(from: path)?.count ?? 0, 80)
        }
    }

    func testUnknownHelperSocketWithoutExplicitQueueCannotUseStableFallback() {
        let support = "/fixture/Application Support"
        XCTAssertEqual(CodexActivityPrivacyRules.legacyQueuePath(socketPath: support + "/QuotaView/codex-activity.sock", applicationSupportPath: support, userID: 501), "/tmp/com.quotaview.codex-activity-501")
        XCTAssertEqual(CodexActivityPrivacyRules.legacyQueuePath(socketPath: support + "/QuotaView-073-Development/codex-activity.sock", applicationSupportPath: support, userID: 501), "/tmp/com.quotaview.development073.codex-activity-501")
        for socket in ["", "relative", "/fixture/custom.sock", support + "/QuotaView-Isolated-0123456789ab/codex-activity.sock", support + "/QuotaView/../QuotaView/codex-activity.sock"] {
            XCTAssertNil(CodexActivityPrivacyRules.legacyQueuePath(socketPath: socket, applicationSupportPath: support, userID: 501))
        }
        XCTAssertNil(CodexActivityPrivacyRules.legacyQueuePath(socketPath: "/fixture/custom.sock", applicationSupportPath: nil, userID: 501))
    }

    func testActualHelperWireDecodesAllEventsWithoutSendingPrivateBodies() throws {
        guard let executable = ProcessInfo.processInfo.environment["QV_AUDIT_B_HOOK"] else {
            throw XCTSkip("Set QV_AUDIT_B_HOOK to the isolated helper build to verify its real JSON wire")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        for event in CodexActivityHookEvent.allCases {
            let queue = root.appendingPathComponent(event.rawValue)
            try FileManager.default.createDirectory(at: queue, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let input: [String: Any] = ["hook_event_name": event.rawValue, "session_id": "private-session",
                "turn_id": "private-turn", "cwd": "/private/fixture/" + String(repeating: "x", count: 100),
                "tool_name": "mcp__functions__update_goal", "tool_input": ["prompt": "PRIVATE-BODY-NEVER-SEND"]]
            let process = Process(), pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = ["--socket", root.appendingPathComponent("absent.sock").path,
                "--queue", queue.path, "--token", "fixture-token", "--installation-id", "fixture-install"]
            process.standardInput = pipe
            try process.run()
            try pipe.fileHandleForWriting.write(contentsOf: JSONSerialization.data(withJSONObject: input))
            try pipe.fileHandleForWriting.close(); process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0)
            let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: queue, includingPropertiesForKeys: nil).first { $0.pathExtension == "json" })
            let data = try Data(contentsOf: file)
            XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("PRIVATE-BODY-NEVER-SEND"))
            let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let activity = try XCTUnwrap(envelope["activity"] as? [String: Any])
            let bytes = try JSONSerialization.data(withJSONObject: activity)
            let decoded = try JSONDecoder().decode(CodexActivityEvent.self, from: bytes)
            XCTAssertEqual(decoded.event, event)
            XCTAssertEqual(decoded.toolCategory, .goal)
            XCTAssertEqual(decoded.sessionHash, CodexActivityPrivacy.hashIdentifier("private-session"))
            XCTAssertEqual(decoded.turnHash, CodexActivityPrivacy.hashIdentifier("private-turn"))
            XCTAssertEqual(decoded.workspaceName?.count, 80)
            for schema in 1...3 {
                var legacy = activity; legacy["schemaVersion"] = schema
                legacy.removeValue(forKey: "turnHash"); legacy["futureField"] = "ignored"
                let compatible = try JSONDecoder().decode(CodexActivityEvent.self, from: JSONSerialization.data(withJSONObject: legacy))
                XCTAssertNotNil(CodexActivityReducer.snapshot(for: compatible))
            }
            var unknown = activity; unknown["event"] = "FutureEvent"
            XCTAssertThrowsError(try JSONDecoder().decode(CodexActivityEvent.self, from: JSONSerialization.data(withJSONObject: unknown)))
            var missing = activity; missing.removeValue(forKey: "sessionHash")
            XCTAssertThrowsError(try JSONDecoder().decode(CodexActivityEvent.self, from: JSONSerialization.data(withJSONObject: missing)))
        }
    }
}
