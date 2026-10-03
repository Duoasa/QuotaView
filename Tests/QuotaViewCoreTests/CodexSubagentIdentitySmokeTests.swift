import Foundation
import SQLite3
import XCTest
@testable import QuotaViewCore

final class CodexSubagentIdentitySmokeTests: XCTestCase {
    func testAvatarMatchesCodexRendererFixturesIncludingUTF16SurrogatePair() {
        // Fixed expectations from the current native renderer, not a second
        // implementation of the production hash.
        let fixtures: [(String, Int)] = [
            ("child", 16),
            ("child-0", 5),
            ("00000000-0000-0000-0000-000000000001", 17),
            ("01a0f6d1-1dd7-7c61-af79-c0fad5756d37", 15),
            ("𠮷-agent", 11)
        ]
        for (threadID, expectedIndex) in fixtures {
            let avatar = CodexActivitySubagentAvatar(threadID: threadID)
            XCTAssertEqual(avatar.paletteIndex, expectedIndex, threadID)
            XCTAssertEqual(avatar.assetName, "CodexSubagentAvatar-\(expectedIndex)")
        }
    }

    func testAvatarUsesNativeThreadIDAndSurvivesDisplayMetadataUpdates() throws {
        let original = try XCTUnwrap(CodexActivitySubagentIdentity(
            threadID: "child", parentThreadID: "parent", nickname: "Atlas", role: "reviewer", title: "First title"))
        let updated = try XCTUnwrap(CodexActivitySubagentIdentity(
            threadID: "child", parentThreadID: "other-parent", nickname: "Butterfly", role: "builder", title: "memories"))
        XCTAssertEqual(original.avatar.paletteIndex, 16)
        XCTAssertEqual(updated.avatar, original.avatar)
        XCTAssertEqual(original.withTitle("New title").avatar, original.avatar)
        let decoded = CodexActivitySubagentIdentity.decode([
            "id": "child", "parentThreadId": "parent", "agentNickname": "Changed nickname", "title": "Changed title"])
        XCTAssertEqual(decoded?.avatar, original.avatar)
    }

    func testNullAPISourceFallsBackToCoreAliasBeforeChildAdmission() {
        let metadata: [String: Any] = ["id": "child", "threadSource": NSNull(),
            "thread_source": "memory_consolidation", "parentThreadId": "parent", "source": "unknown"]
        XCTAssertEqual(CodexActivitySessionKind.classify(metadata: metadata), .memoryConsolidation)
        XCTAssertNil(CodexActivitySubagentIdentity.decode(metadata))
        var child = metadata
        child["thread_source"] = "subagent"
        XCTAssertEqual(CodexActivitySessionKind.classify(metadata: child), .subagent)
        XCTAssertEqual(CodexActivitySubagentIdentity.decode(child)?.parentThreadID, "parent")
    }

    func testNativeThreadSpawnVariantsRetainExactParent() throws {
        for key in ["subagent", "subAgent"] {
            let metadata: [String: Any] = ["id": "child", "thread_source": "subagent", "source": [key: ["thread_spawn": [
                "parent_thread_id": "parent", "depth": 1, "agent_nickname": "Atlas", "agent_role": "reviewer"]]]]
            let child = try XCTUnwrap(CodexActivitySubagentIdentity.decode(metadata))
            XCTAssertEqual(child.parentSessionHash, CodexActivityPrivacy.hashIdentifier("parent"))
            XCTAssertEqual(child.depth, 1)
            XCTAssertEqual(child.nickname, "Atlas")
            XCTAssertEqual(child.role, "reviewer")
            XCTAssertEqual(CodexActivitySessionKind.classify(metadata: metadata), .subagent)
        }
    }

    func testParentFieldIsIndependentOfOriginAndTitle() throws {
        let metadata: [String: Any] = ["id": "child", "source": "appServer", "threadSource": "agent_created_thread",
                                      "parentThreadId": "parent", "name": "memories", "agentNickname": "A"]
        XCTAssertEqual(try XCTUnwrap(CodexActivitySubagentIdentity.decode(metadata)).parentThreadID, "parent")
        XCTAssertEqual(CodexActivitySessionKind.classify(metadata: metadata), .subagent)
        XCTAssertEqual(CodexActivitySessionKind.classify(metadata: ["id": "child", "parentThreadId": "parent", "thread_source": "subagent", "source": "appServer"]), .subagent)
        XCTAssertNil(CodexActivitySubagentIdentity.decode(["id": "child", "name": "subagent", "cwd": "/tmp/memories"]))
    }

    func testMemoryAndInternalWorkersNeverBecomeOrdinaryChildren() {
        for marker in ["memory_consolidation", "review", "compact"] {
            let metadata: [String: Any] = ["id": "child", "parentThreadId": "parent", "source": ["subAgent": marker]]
            XCTAssertNil(CodexActivitySubagentIdentity.decode(metadata))
            XCTAssertNotEqual(CodexActivitySessionKind.classify(metadata: metadata), .subagent)
        }
        XCTAssertNil(CodexActivitySubagentIdentity.decode(["id": "child", "parentThreadId": "parent", "source": ["internal": "guardian"]]))
        XCTAssertEqual(CodexActivitySessionKind.classify(source: ["subagent": "memory_consolidation"], threadSource: "subagent"), .memoryConsolidation)
        XCTAssertEqual(CodexActivitySessionKind.classify(source: "unknown", threadSource: "subagent"), .internalTask)
        XCTAssertEqual(CodexActivitySessionKind.resolving(.subagent, .memoryConsolidation), .memoryConsolidation)
        XCTAssertEqual(CodexActivitySessionKind.resolving(.subagent, .internalTask), .internalTask)
    }

    func testConflictingSelfAndMalformedRelationshipsAreRejected() {
        for spawn: [String: Any] in [["parent_thread_id": "parent", "depth": true],
                                    ["parent_thread_id": "child", "depth": 1],
                                    ["parent_thread_id": "different", "depth": 1]] {
            let metadata: [String: Any] = ["id": "child", "parentThreadId": "parent", "source": ["subagent": ["thread_spawn": spawn]]]
            XCTAssertNil(CodexActivitySubagentIdentity.decode(metadata))
            XCTAssertEqual(CodexActivitySessionKind.classify(metadata: metadata), .internalTask)
        }
        XCTAssertNil(CodexActivitySubagentIdentity.decode(["id": "child", "parentThreadId": "child"]))
        XCTAssertNil(CodexActivitySubagentIdentity.decode(["id": "wrong", "parentThreadId": "parent"], expectedThreadID: "child"))
    }

    func testChildRegistryPreservesLifecycleWithoutSelectingOrGrantingUserRights() throws {
        var registry = CodexActivityTaskRegistry()
        let start = CodexActivityEvent(event: .userPromptSubmit, sessionHash: "child", turnHash: "turn", sessionKind: .subagent, source: .localRollout)
        let admission = try XCTUnwrap(registry.admit(start, kind: .subagent, selectedSession: nil))
        XCTAssertTrue(admission.startsTurn)
        XCTAssertFalse(admission.selectsTask)
        XCTAssertNil(registry.currentIdentity(for: "child"))
        XCTAssertEqual(registry.executionIdentity(for: "child"), admission.identity)
        XCTAssertEqual(registry.subagentIdentity(for: "child"), admission.identity)
        XCTAssertEqual(registry.executionIdentities, [admission.identity])
        XCTAssertTrue(registry.permitsSubagentAttachment(session: "child", turn: "turn", source: .localRollout, occurredAt: Date()))
        XCTAssertFalse(registry.permitsSubagentAttachment(session: "child", turn: "old", source: .localRollout, occurredAt: Date()))
        XCTAssertFalse(registry.permitsPublicAttachment(session: "child", turn: "turn", source: .localRollout, occurredAt: Date()))
        XCTAssertNil(registry.admit(.init(event: .stop, sessionHash: "child", turnHash: "old", source: .localRollout), kind: .subagent, selectedSession: nil))
        XCTAssertNotNil(registry.admit(.init(event: .stop, sessionHash: "child", turnHash: "turn", source: .localRollout), kind: .subagent, selectedSession: nil))
    }

    func testDiscoveryRetainsThreeNativeChildrenAndSeparatesMemory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 1...3 {
            let payload: [String: Any] = ["id": "child-\(index)", "source": ["subagent": ["thread_spawn": [
                "parent_thread_id": "parent", "depth": 1, "agent_nickname": "Agent \(index)"]]]]
            let file = root.appendingPathComponent("sessions/child-\(index).jsonl")
            var data = try JSONSerialization.data(withJSONObject: ["type": "session_meta", "payload": payload])
            data.append(10)
            try data.write(to: file)
            XCTAssertEqual(CodexLocalRolloutDiscovery.readSessionMetadata(from: file)?.subagentIdentity?.parentThreadID, "parent")
        }
        let memory = root.appendingPathComponent("sessions/memory.jsonl")
        var data = try JSONSerialization.data(withJSONObject: ["type": "session_meta", "payload": ["id": "memory", "source": ["internal": "memory_consolidation"]]])
        data.append(10); try data.write(to: memory)
        let discovery = CodexLocalRolloutDiscovery(codexHomeURL: root, maximumCandidateCount: 24, fileManager: .default)
        let candidates = discovery.recentCandidates()
        XCTAssertEqual(candidates.filter { $0.sessionKind == .subagent }.count, 3)
        XCTAssertEqual(candidates.filter { $0.sessionKind == .memoryConsolidation }.count, 1)
    }
    func testLocalBootstrapPublishesChildIdentityAndTitleBeforeReadOnlyLifecycle() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("sessions/child.jsonl")
        let metadata: [String: Any] = ["id": "child", "thread_source": "subagent", "source": ["subagent": ["thread_spawn": ["parent_thread_id": "parent", "depth": 1]]]]
        var data = Data()
        for line: [String: Any] in [["type": "session_meta", "payload": metadata],
                                  ["type": "event_msg", "payload": ["type": "task_started", "turn_id": "turn"]]] {
            data.append(try JSONSerialization.data(withJSONObject: line)); data.append(10)
        }
        try data.write(to: file)
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(root.appendingPathComponent("state_5.sqlite").path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        let query = "CREATE TABLE threads(id TEXT,rollout_path TEXT,cwd TEXT,source TEXT,thread_source TEXT,title TEXT,archived INTEGER,updated_at_ms INTEGER); INSERT INTO threads VALUES('child','\(file.path)','','unknown','user','Memory identity review',0,1);"
        XCTAssertEqual(sqlite3_exec(database, query, nil, nil, nil), SQLITE_OK)
        let recorder = SubagentLocalRecorder()
        let client = CodexLocalRolloutActivityClient(configuration: .init(isEnabled: true, codexHomeURL: root, pollIntervalSeconds: 10))
        await client.setPublicContentHandler { content in await recorder.append(content) }
        await client.start(handler: { record, _ in await recorder.append(record) }, connectionStateHandler: { _ in })
        await client.pollOnceForTesting()
        await client.stop()
        let records = await recorder.records
        let contents = await recorder.contents
        let identityIndex = try XCTUnwrap(records.firstIndex { record in
            if case .sessionMetadata = record.update { return record.threadIdentity?.subagentIdentity?.title == "Memory identity review" }
            return false
        })
        let startIndex = try XCTUnwrap(records.firstIndex { record in
            if case .activity(let event) = record.update { return event.event == .userPromptSubmit && event.sessionKind == .subagent }
            return false
        })
        XCTAssertLessThan(identityIndex, startIndex)
        XCTAssertEqual(records[startIndex].threadIdentity?.subagentIdentity?.parentThreadID, "parent")
        let title = try XCTUnwrap(contents.first { content in
            let payload = (try? JSONSerialization.jsonObject(with: content.data)) as? [String: Any]
            return payload?["title"] as? String == "Memory identity review"
        })
        XCTAssertEqual(title.turnHash, CodexActivityPrivacy.hashIdentifier("turn"))
    }

}


private actor SubagentLocalRecorder {
    var records: [CodexLocalRolloutDecodedRecord] = []
    var contents: [CodexLocalPublicContent] = []
    func append(_ record: CodexLocalRolloutDecodedRecord) { records.append(record) }
    func append(_ content: CodexLocalPublicContent) { contents.append(content) }
}
