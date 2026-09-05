import Foundation
import XCTest
import SQLite3
@testable import QuotaView
@testable import QuotaViewCore

final class CodexActivityOwnershipTests: XCTestCase {
    @MainActor
    private func store() -> CodexActivityStore {
        CodexActivityStore(titleClient: CodexAppServerClient(executablePath: nil))
    }

    @MainActor
    func testForeignTerminalCannotOwnCurrentTask() async {
        let s = store()
        s.receive(CodexActivityEvent(event: .userPromptSubmit, sessionHash: "user", turnHash: "active", source: .localRollout))
        s.receive(CodexActivityEvent(event: .stop, sessionHash: "background", turnHash: "other", source: .localRollout, turnCompletionStatus: .completed))
        XCTAssertEqual(s.snapshot?.sessionHash, "user")
        XCTAssertEqual(s.lifecycle, .active)
        await s.stop()
    }

    @MainActor
    func testLateOldTurnCannotCompleteNewTurn() async {
        let s = store()
        s.receive(CodexActivityEvent(event: .userPromptSubmit, sessionHash: "user", turnHash: "old", source: .localRollout))
        s.receive(CodexActivityEvent(event: .userPromptSubmit, sessionHash: "user", turnHash: "new", source: .localRollout))
        s.receive(CodexActivityEvent(event: .stop, sessionHash: "user", turnHash: "old", source: .hook))
        XCTAssertEqual(s.lifecycle, .active)
        XCTAssertNotEqual(s.snapshot?.state, .completed)
        await s.stop()
    }

    @MainActor
    func testOldSessionEndCannotDisableCurrentPlayback() async {
        let s = store()
        s.receive(CodexActivityEvent(event: .userPromptSubmit, sessionHash: "user", turnHash: "active", source: .localRollout))
        s.receive(CodexActivityEvent(event: .sessionEnd, sessionHash: "background", source: .hook))
        XCTAssertEqual(s.lifecycle, .active)
        XCTAssertTrue(s.shouldPlayVisualEffects)
        await s.stop()
    }

    @MainActor
    func testDuplicatedStartCannotEraseSameTurnPlan() async {
        let s = store()
        s.receive(CodexActivityEvent(event: .userPromptSubmit, sessionHash: "user", turnHash: "active", source: .localRollout))
        s.receive(CodexActivityEvent(event: .preToolUse, sessionHash: "user", turnHash: "active", planProgress: .init(completedSteps: 2, inProgressSteps: 1, pendingSteps: 1), source: .localRollout, planSource: .localRollout))
        s.receive(CodexActivityEvent(event: .userPromptSubmit, sessionHash: "user", turnHash: "active", source: .hook))
        XCTAssertEqual(s.snapshot?.approximateProgressFraction, 0.525)
        await s.stop()
    }

    @MainActor
    func testUnscopedWaitingCannotReviveCompletedTurn() async {
        let s = store()
        s.receive(CodexActivityEvent(event: .userPromptSubmit, sessionHash: "user", turnHash: "active", source: .localRollout))
        s.receive(CodexActivityEvent(event: .stop, sessionHash: "user", turnHash: "active", source: .localRollout, turnCompletionStatus: .completed))
        s.receive(CodexActivityEvent(event: .permissionRequest, sessionHash: "user", source: .appServer, waitReason: .approval))
        XCTAssertEqual(s.lifecycle, .completed)
        XCTAssertEqual(s.snapshot?.state, .completed)
        await s.stop()
    }

    @MainActor
    func testGoalCompletionDoesNotCompleteRunningTurn() async {
        let s = store()
        s.receive(CodexActivityEvent(event: .userPromptSubmit, sessionHash: "user", turnHash: "active", source: .localRollout))
        s.receive(CodexActivityEvent(event: .postToolUse, sessionHash: "user", toolCategory: .goal, source: .appServer, goalStatus: .complete))
        XCTAssertNotEqual(s.snapshot?.state, .completed)
        XCTAssertEqual(s.lifecycle, .active)
        await s.stop()
    }

    func testDatabaseDiscoveryExcludesGuardian() async throws {
        try await verifyDiscovery(useDatabase: true)
    }

    func testDirectoryDiscoveryExcludesGuardian() async throws {
        try await verifyDiscovery(useDatabase: false)
    }

    private func verifyDiscovery(useDatabase: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let dir = root.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for (i, id) in ["user", "guardian"].enumerated() {
            let source: Any = id == "user" ? "vscode" : ["subagent": ["other": "guardian"]]
            let objects: [[String: Any]] = [
                ["type": "session_meta", "payload": ["id": id, "source": source]],
                ["type": "event_msg", "payload": ["type": "task_started", "turn_id": id]]
            ]
            var data = Data()
            for object in objects {
                data.append(try JSONSerialization.data(withJSONObject: object)); data.append(10)
            }
            let path = dir.appendingPathComponent("\(id).jsonl")
            try data.write(to: path)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: Double(i + 1))], ofItemAtPath: path.path)
        }
        if useDatabase {
            var db: OpaquePointer?
            XCTAssertEqual(sqlite3_open(root.appendingPathComponent("state_5.sqlite").path, &db), SQLITE_OK)
            defer { sqlite3_close(db) }
            let sql = """
            CREATE TABLE threads (id TEXT, rollout_path TEXT, cwd TEXT, archived INTEGER, updated_at_ms INTEGER, source TEXT, thread_source TEXT);
            INSERT INTO threads VALUES ('user','\(dir.path)/user.jsonl','/tmp',0,1,'vscode','user');
            INSERT INTO threads VALUES ('guardian','\(dir.path)/guardian.jsonl','/tmp',0,2,'{"subagent":{"other":"guardian"}}','guardian_review');
            """
            XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        }
        let sink = AuditRecordSink()
        let received = expectation(description: "Candidate replay")
        let client = CodexLocalRolloutActivityClient(configuration: .init(isEnabled: true, codexHomeURL: root, maximumCandidateCount: 1))
        await client.start(handler: { record, _ in
            await sink.append(record)
            received.fulfill()
        }, connectionStateHandler: { _ in })
        await fulfillment(of: [received], timeout: 2)
        await client.stop()
        let records = await sink.records
        let sessions = records.compactMap { record -> String? in
            guard case .activity(let event) = record.update else { return nil }
            return event.sessionHash
        }
        XCTAssertEqual(sessions, [CodexActivityPrivacy.hashIdentifier("user")])
    }

    @MainActor
    func testLegacyRestartPreservesIntermediateCounterReset() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let dir = root.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var records: [[String: Any]] = [
            ["type": "session_meta", "payload": ["id": "user", "source": "vscode"]],
            ["type": "event_msg", "payload": ["type": "task_started", "turn_id": "active"]]
        ]
        for (total, last) in [(100,100), (400,300), (100,100), (150,50)] {
            records.append(["type": "event_msg", "payload": ["type": "token_count", "info": ["total_token_usage": ["total_tokens": total], "last_token_usage": ["total_tokens": last]]]])
        }
        var data = Data()
        for object in records { data.append(try JSONSerialization.data(withJSONObject: object)); data.append(10) }
        try data.write(to: dir.appendingPathComponent("user.jsonl"))
        let s = store()
        let received = expectation(description: "Startup and all legacy counter segments")
        received.expectedFulfillmentCount = 2
        let client = CodexLocalRolloutActivityClient(configuration: .init(isEnabled: true, codexHomeURL: root))
        await client.start(handler: { record, _ in
            switch record.update {
            case .activity(let event): await s.receive(event)
            case .tokenUsage(let usage): await s.receive(usage)
            case .tokenUsageReplay(let updates): await s.receiveTokenReplay(updates)
            }
            received.fulfill()
        }, connectionStateHandler: { _ in })
        await fulfillment(of: [received], timeout: 2)
        await client.stop()
        XCTAssertEqual(s.currentTurnTokenUsage, 550)
        await s.stop()
    }
}

private actor AuditRecordSink {
    var records: [CodexLocalRolloutDecodedRecord] = []
    func append(_ record: CodexLocalRolloutDecodedRecord) { records.append(record) }
}
