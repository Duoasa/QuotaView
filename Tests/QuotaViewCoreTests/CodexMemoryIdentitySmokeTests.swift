import Foundation
import SQLite3
import XCTest
@testable import QuotaViewCore

final class CodexMemoryIdentitySmokeTests: XCTestCase {
    func testExactOfficialMemoryMarkersAndEncodingVariants() {
        for source: Any in [["internal": "memory_consolidation"], ["subagent": "memory_consolidation"],
                            ["subAgent": "memory_consolidation"], "{\"internal\":\"memory_consolidation\"}",
                            "{\"subAgent\":\"memory_consolidation\"}"] {
            XCTAssertEqual(CodexActivitySessionKind.classify(source: source), .memoryConsolidation)
            XCTAssertEqual(CodexActivitySessionKind.classify(source: source, threadSource: "user"), .memoryConsolidation)
        }
        XCTAssertEqual(CodexActivitySessionKind.classify(source: "unknown", threadSource: "memory_consolidation"), .memoryConsolidation)
        XCTAssertEqual(CodexActivitySessionKind.classify(source: "vscode", threadSource: "memory_consolidation"), .memoryConsolidation)
    }

    func testNamesPathsAndGenericSubagentKindsDoNotProveMemoryIdentity() {
        for source: Any in ["memories", "memory", "unknown", "/tmp/memories", ["custom": "memory_consolidation"]] {
            XCTAssertEqual(CodexActivitySessionKind.classify(source: source), .unknown)
        }
        for source: Any in [["internal": "guardian"], ["subAgent": "compact"], ["subagent": ["other": "memory_consolidation"]]] {
            XCTAssertEqual(CodexActivitySessionKind.classify(source: source), .internalTask)
        }
        XCTAssertEqual(CodexActivitySessionKind.classify(source: ["internal": "memory_consolidation", "subagent": "review"]), .internalTask)
        XCTAssertEqual(CodexActivitySessionKind.classify(source: ["internal": "memory_consolidation"], threadSource: "guardian_review"), .internalTask)
        XCTAssertTrue(CodexActivitySessionKind.memoryConsolidation.supportsActivityPresentation)
        XCTAssertFalse(CodexActivitySessionKind.internalTask.supportsActivityPresentation)
    }

    func testSparseMetadataCannotOverwriteVerifiedMemory() {
        XCTAssertEqual(CodexActivitySessionKind.resolving(.user, .memoryConsolidation), .memoryConsolidation)
        XCTAssertEqual(CodexActivitySessionKind.resolving(.memoryConsolidation, .unknown, .user), .memoryConsolidation)
    }

    func testMemoryRegistryTracksLifecycleWithoutUserSelectionOrRequestCapabilities() throws {
        var registry = CodexActivityTaskRegistry()
        let began = try XCTUnwrap(registry.admit(event(.userPromptSubmit), kind: .memoryConsolidation, selectedSession: nil))
        XCTAssertTrue(began.startsTurn)
        XCTAssertFalse(began.selectsTask)
        XCTAssertEqual(registry.backgroundIdentity(for: "memory"), began.identity)
        XCTAssertNil(registry.currentIdentity(for: "memory"))
        XCTAssertFalse(registry.permitsPublicAttachment(session: "memory", turn: "turn", source: .localRollout, occurredAt: Date()))
        XCTAssertNil(registry.admit(event(.stop, turn: "other"), kind: .memoryConsolidation, selectedSession: nil))
        XCTAssertNil(registry.admit(event(.stop, source: .hook), kind: .memoryConsolidation, selectedSession: nil))
        XCTAssertNotNil(registry.admit(event(.stop), kind: .memoryConsolidation, selectedSession: nil))
        XCTAssertNil(registry.admit(event(.preToolUse), kind: .memoryConsolidation, selectedSession: nil))
    }

    func testLateMemoryIdentityPreservesTurnAndTerminalEvidence() throws {
        var registry = CodexActivityTaskRegistry()
        let original = try XCTUnwrap(registry.admit(event(.userPromptSubmit), kind: .unknown, selectedSession: nil)).identity
        XCTAssertEqual(registry.reclassify(session: "memory", kind: .memoryConsolidation), original)
        XCTAssertEqual(registry.backgroundIdentity(for: "memory"), original)
        XCTAssertNil(registry.currentIdentity(for: "memory"))
        XCTAssertEqual(registry.reclassify(session: "memory", kind: .user), original)
        XCTAssertNotNil(registry.admit(event(.stop), kind: .memoryConsolidation, selectedSession: nil))
        _ = registry.reclassify(session: "memory", kind: .memoryConsolidation)
        XCTAssertNil(registry.admit(event(.userPromptSubmit), kind: .memoryConsolidation, selectedSession: nil))
        registry.remove(session: "memory")
        XCTAssertNil(registry.backgroundIdentity(for: "memory"))
    }

    func testHookInheritsValidatedNativeIdentityButCannotAssertItsOwnKind() async throws {
        let root = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let classifier = CodexActivitySessionClassifier(codexHome: root)
        let known = await classifier.kind(for: event(.preToolUse, kind: .memoryConsolidation, source: .appServer))
        XCTAssertEqual(known, .memoryConsolidation)
        let inherited = await classifier.kind(for: event(.postToolUse, source: .hook))
        XCTAssertEqual(inherited, .memoryConsolidation)
        let isolated = CodexActivitySessionClassifier(codexHome: root)
        let asserted = await isolated.kind(for: event(.preToolUse, kind: .memoryConsolidation, source: .hook))
        XCTAssertEqual(asserted, .unknown)
    }

    func testHookVerifiedSQLiteMemoryOverridesCachedUserFallback() async throws {
        let root = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try sql(root, "CREATE TABLE threads(id TEXT,source TEXT,thread_source TEXT,updated_at_ms INTEGER); INSERT INTO threads VALUES('memory','vscode','user',1);")
        let classifier = CodexActivitySessionClassifier(codexHome: root)
        let session = CodexActivityPrivacy.hashIdentifier("memory")
        let hook = CodexActivityEvent(event: .preToolUse, sessionHash: session, source: .hook)
        let initial = await classifier.kind(for: hook)
        XCTAssertEqual(initial, .user)
        let native = CodexActivityEvent(event: .preToolUse, sessionHash: session, sessionKind: .memoryConsolidation, source: .appServer)
        let refined = await classifier.kind(for: native)
        XCTAssertEqual(refined, .memoryConsolidation)
        let inherited = await classifier.kind(for: hook)
        XCTAssertEqual(inherited, .memoryConsolidation)
    }

    func testDiscoveryRetainsMemoryAndLetsSpecificRolloutIdentityOverrideDatabaseFallback() throws {
        let root = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("sessions/memory.jsonl")
        try rollout(id: "memory", source: ["internal": "memory_consolidation"]).write(to: file)
        try sql(root, "CREATE TABLE threads(id TEXT,rollout_path TEXT,cwd TEXT,archived INTEGER,updated_at_ms INTEGER,source TEXT,thread_source TEXT); INSERT INTO threads VALUES('memory','\(file.path)','/tmp/project',0,1,'vscode','user');")
        let discovery = CodexLocalRolloutDiscovery(codexHomeURL: root, maximumCandidateCount: 24, fileManager: .default)
        let candidate = try XCTUnwrap(discovery.recentCandidates().first)
        XCTAssertEqual(candidate.sessionKind, .memoryConsolidation)
        XCTAssertEqual(candidate.metadataKind, .memoryConsolidation)
        XCTAssertEqual(candidate.sessionHash, CodexActivityPrivacy.hashIdentifier("memory"))
    }

    func testDiscoveryReadsBothThreadSourceNamesWithoutGuessingMemoriesWorkspace() throws {
        let root = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        for key in ["thread_source", "threadSource"] {
            let file = root.appendingPathComponent("sessions/\(key).jsonl")
            let metadata: [String: Any] = ["type": "session_meta", "payload": ["id": key, "source": "unknown", key: "memory_consolidation", "cwd": "/tmp/project"]]
            try line(metadata).write(to: file)
            XCTAssertEqual(CodexLocalRolloutDiscovery.readSessionMetadata(from: file)?.kind, .memoryConsolidation)
        }
        let user = root.appendingPathComponent("sessions/user.jsonl")
        try line(["type": "session_meta", "payload": ["id": "user", "source": "vscode", "cwd": "/tmp/memories"]]).write(to: user)
        XCTAssertEqual(CodexLocalRolloutDiscovery.readSessionMetadata(from: user)?.kind, .user)
    }

    func testDecoderRetainsMemoryOnStartWorkAndCompletion() throws {
        let session = CodexActivityPrivacy.hashIdentifier("memory")
        var decoder = CodexLocalRolloutLineDecoder(sessionHash: session, sessionKind: .memoryConsolidation)
        for payload: [String: Any] in [["type": "task_started", "turn_id": "one"], ["type": "task_complete", "turn_id": "one"]] {
            let record = try XCTUnwrap(decoder.decode(line: line(["type": "event_msg", "payload": payload])))
            guard case .activity(let event) = record.update else { return XCTFail("expected activity") }
            XCTAssertEqual(event.sessionKind, .memoryConsolidation)
        }
        XCTAssertNil(decoder.activeTurnHash)
    }

    func testLocalClientPublishesLateMetadataWithoutAppendOrSyntheticTurnStart() async throws {
        let root = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("sessions/memory.jsonl")
        try rollout(id: "memory", source: "vscode").write(to: file)
        try sql(root, "CREATE TABLE threads(id TEXT,rollout_path TEXT,cwd TEXT,archived INTEGER,updated_at_ms INTEGER,source TEXT,thread_source TEXT); INSERT INTO threads VALUES('memory','\(file.path)','/tmp/project',0,1,'vscode','user');")
        let sink = MemoryIdentityRecordSink()
        let start = expectation(description: "original turn")
        let changed = expectation(description: "metadata arrives without append")
        let client = CodexLocalRolloutActivityClient(configuration: .init(isEnabled: true, codexHomeURL: root))
        await client.start(handler: { record, _ in
            await sink.append(record)
            switch record.update {
            case .activity: start.fulfill()
            case .sessionMetadata: changed.fulfill()
            default: break
            }
        }, connectionStateHandler: { _ in })
        await fulfillment(of: [start], timeout: 3)
        try sql(root, "UPDATE threads SET thread_source='memory_consolidation',updated_at_ms=2 WHERE id='memory';")
        await client.recheck()
        await client.pollOnceForTesting()
        await fulfillment(of: [changed], timeout: 3)
        await client.pollOnceForTesting()
        await client.stop()
        let records = await sink.records
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.last?.update, .sessionMetadata)
        XCTAssertEqual(records.last?.threadIdentity?.sessionKind, .memoryConsolidation)
        XCTAssertEqual(records.last?.requiresLiveConfirmation, false)
    }

    func testLatePreciseMemoryCanRefineGenericInternalAndExplicitInternalCanRetractIt() throws {
        var registry = CodexActivityTaskRegistry()
        let identity = try XCTUnwrap(registry.admit(event(.userPromptSubmit), kind: .unknown, selectedSession: nil)).identity
        _ = registry.reclassify(session: "memory", kind: .internalTask)
        XCTAssertEqual(registry.reclassify(session: "memory", kind: .memoryConsolidation), identity)
        XCTAssertEqual(registry.backgroundIdentity(for: "memory"), identity)
        _ = registry.reclassify(session: "memory", kind: .internalTask)
        XCTAssertNil(registry.backgroundIdentity(for: "memory"))
        XCTAssertNil(registry.currentIdentity(for: "memory"))
    }

    func testDecoderUsesMatchingMetadataWithoutChangingLifecycle() throws {
        let session = CodexActivityPrivacy.hashIdentifier("memory")
        var decoder = CodexLocalRolloutLineDecoder(sessionHash: session)
        XCTAssertNil(decoder.decode(line: try line(["type": "session_meta", "payload": ["id": "other", "source": ["internal": "memory_consolidation"]]])))
        XCTAssertEqual(decoder.sessionKind, .unknown)
        XCTAssertNil(decoder.decode(line: try line(["type": "session_meta", "payload": ["id": "memory", "source": ["internal": "memory_consolidation"]]])))
        XCTAssertEqual(decoder.sessionKind, .memoryConsolidation)
        XCTAssertNil(decoder.activeTurnHash)
    }

    func testIdentityUpdateCannotReleaseRecoveredUserContext() {
        var recovery = CodexLocalActivityRecovery()
        let incoming = CodexLocalRolloutDecodedRecord(eventID: nil, update: .activity(event(.userPromptSubmit, kind: .user)), requiresLiveConfirmation: true)
        XCTAssertNil(recovery.project(incoming))
        let metadata = CodexLocalRolloutDecodedRecord(eventID: nil, update: .sessionMetadata,
            threadIdentity: .init(threadID: "memory", sessionHash: "memory", sessionKind: .memoryConsolidation))
        XCTAssertNil(recovery.project(metadata))
        recovery.forget(session: "memory")
        XCTAssertTrue(recovery.confirm(.init(sessionHash: "memory", turnHash: "turn")).isEmpty)
    }

    private func event(_ type: CodexActivityHookEvent, turn: String? = "turn", kind: CodexActivitySessionKind? = nil,
                       source: CodexActivityEventSource = .localRollout) -> CodexActivityEvent {
        .init(event: type, sessionHash: "memory", turnHash: turn, sessionKind: kind, source: source)
    }
    private func fixtureDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        return root
    }
    private func sql(_ root: URL, _ statement: String) throws {
        var db: OpaquePointer?
        guard sqlite3_open(root.appendingPathComponent("state_5.sqlite").path, &db) == SQLITE_OK else { throw NSError(domain: "MemoryFixture", code: 1) }
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, statement, nil, nil, nil) == SQLITE_OK else { throw NSError(domain: "MemoryFixture", code: 2) }
    }
    private func line(_ object: [String: Any]) throws -> Data {
        var bytes = try JSONSerialization.data(withJSONObject: object); bytes.append(10); return bytes
    }
    private func rollout(id: String, source: Any) throws -> Data {
        var bytes = try line(["type": "session_meta", "payload": ["id": id, "source": source]])
        bytes.append(try line(["type": "event_msg", "payload": ["type": "task_started", "turn_id": "one"]]))
        return bytes
    }
}

private actor MemoryIdentityRecordSink {
    var records: [CodexLocalRolloutDecodedRecord] = []
    func append(_ record: CodexLocalRolloutDecodedRecord) { records.append(record) }
}
