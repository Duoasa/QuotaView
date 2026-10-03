import Foundation
import SQLite3
import XCTest
@testable import QuotaViewCore

final class CodexClassifierExecutionCoverageSmokeTests: XCTestCase {
    func testImmediateNextTurnReadsNewMemoryProofDespiteSessionCache() async throws {
        for cachedUser in [false, true] {
            let root = try directory()
            defer { try? FileManager.default.removeItem(at: root) }
            try insert(root, turn: "A", trigger: "user")
            let classifier = CodexActivitySessionClassifier(codexHome: root)
            let first = await classifier.classification(for: event(turn: "A", user: cachedUser))
            XCTAssertEqual(first.kind, cachedUser ? .user : .unknown)
            // No sleep: this is deliberately inside the same one-second TTL.
            try insert(root, turn: "B", trigger: "memory_consolidation")
            let second = await classifier.classification(for: event(turn: "B"))
            XCTAssertEqual(second.kind, .memoryConsolidation)
            XCTAssertEqual(second.executionTurnHash, CodexActivityPrivacy.hashIdentifier("B"))
        }
    }

    func testImmediateNonmemoryTurnRevokesPreviousExactProof() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        try insert(root, turn: "A", trigger: "memory_consolidation")
        let classifier = CodexActivitySessionClassifier(codexHome: root)
        let first = await classifier.classification(for: event(turn: "A"))
        XCTAssertEqual(first.kind, .memoryConsolidation)
        try insert(root, turn: "B", trigger: "user")
        let second = await classifier.classification(for: event(turn: "B"))
        XCTAssertEqual(second.kind, .unknown)
        XCTAssertNil(second.executionTurnHash)
        let old = await classifier.classification(for: event(turn: "A"))
        XCTAssertEqual(old.kind, .unknown)
        XCTAssertNil(old.executionTurnHash)
    }

    func testChildOriginUsesExactExecutionOverlayAndReturnsToChildOnNextTurn() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        try insert(root, turn: "A", trigger: "memory_consolidation")
        let classifier = CodexActivitySessionClassifier(codexHome: root)
        func child(_ turn: String) -> CodexActivityEvent {
            .init(event: .userPromptSubmit, sessionHash: CodexActivityPrivacy.hashIdentifier("thread"),
                  turnHash: CodexActivityPrivacy.hashIdentifier(turn), sessionKind: .subagent, source: .appServer)
        }
        let first = await classifier.classification(for: child("A"))
        XCTAssertEqual(first.kind, .memoryConsolidation)
        XCTAssertEqual(first.executionTurnHash, CodexActivityPrivacy.hashIdentifier("A"))
        // Origin stays child; only this execution is a memory consolidation.
        try insert(root, turn: "B", trigger: "user")
        let second = await classifier.classification(for: child("B"))
        XCTAssertEqual(second.kind, .subagent)
        XCTAssertNil(second.executionTurnHash)
        let hook = await classifier.classification(for: event(turn: "B"))
        XCTAssertEqual(hook.kind, .subagent)
        XCTAssertNil(hook.executionTurnHash)
    }

    private func event(turn: String, user: Bool = false) -> CodexActivityEvent {
        .init(event: .preToolUse, sessionHash: CodexActivityPrivacy.hashIdentifier("thread"),
              turnHash: CodexActivityPrivacy.hashIdentifier(turn), sessionKind: user ? .user : nil,
              source: user ? .appServer : .hook)
    }
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try sql(root, "CREATE TABLE logs(id INTEGER PRIMARY KEY,ts INTEGER,ts_nanos INTEGER,target TEXT,module_path TEXT,file TEXT,thread_id TEXT,feedback_log_body TEXT); CREATE INDEX logs_time ON logs(ts DESC,ts_nanos DESC,id DESC);")
        return root
    }
    private func insert(_ root: URL, turn: String, trigger: String) throws {
        let body = "session_loop{thread_id=thread}: Submission sub=Submission { id: \"\(turn)\", op: TurnInput { request: TurnInputRequest { input: UserInput { content: [] }, start: TurnStartOptions { turn_trigger: Some(\"\(trigger)\"), final_output_json_schema: None }, additional_context: {} }, mode: StartIfIdle } }"
        let quoted = "'" + body.replacingOccurrences(of: "'", with: "''") + "'"
        try sql(root, "INSERT INTO logs(ts,ts_nanos,target,module_path,file,thread_id,feedback_log_body) VALUES(\(Int(Date().timeIntervalSince1970)),0,'codex_core::session::handlers','codex_core::session::handlers','core/src/session/handlers.rs','thread',\(quoted));")
    }
    private func sql(_ root: URL, _ query: String) throws {
        var database: OpaquePointer?
        guard sqlite3_open(root.appendingPathComponent("logs_2.sqlite").path, &database) == SQLITE_OK else { throw NSError(domain: "CoverageSmoke", code: 1) }
        defer { sqlite3_close(database) }
        guard sqlite3_exec(database, query, nil, nil, nil) == SQLITE_OK else { throw NSError(domain: "CoverageSmoke", code: 2) }
    }
}
