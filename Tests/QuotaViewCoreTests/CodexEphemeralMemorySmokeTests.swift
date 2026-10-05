import Foundation
import SQLite3
import XCTest
@testable import QuotaViewCore
@testable import QuotaView

final class CodexEphemeralMemorySmokeTests: XCTestCase {
    private let now = Date()
    private func record(thread: String = "memory", turn: String = "turn", trigger: String = "memory_consolidation",
                        prompt: String = "fixture") -> String {
        let quoted = String(decoding: try! JSONEncoder().encode(prompt), as: UTF8.self)
        return "session_loop{thread_id=\(thread)}: Submission sub=Submission { id: \"\(turn)\", op: TurnInput { request: TurnInputRequest { input: UserInput { content: [Text { text: \(quoted), text_elements: [] }] }, start: TurnStartOptions { turn_trigger: Some(\"\(trigger)\"), final_output_json_schema: None }, additional_context: {} }, mode: StartIfIdle } }"
    }
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try sql(root, "CREATE TABLE logs(id INTEGER PRIMARY KEY, ts INTEGER, ts_nanos INTEGER, target TEXT, module_path TEXT, file TEXT, thread_id TEXT, feedback_log_body TEXT); CREATE INDEX idx_logs_ts ON logs(ts DESC,ts_nanos DESC,id DESC);")
        return root
    }
    private func sql(_ root: URL, _ sql: String) throws {
        var database: OpaquePointer?
        guard sqlite3_open(root.appendingPathComponent("logs_2.sqlite").path, &database) == SQLITE_OK else { throw NSError(domain: "EphemeralMemory", code: 1) }
        defer { sqlite3_close(database) }
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw NSError(domain: "EphemeralMemory", code: 2) }
    }
    private func insert(_ root: URL, thread: String = "memory", turn: String = "turn", trigger: String = "memory_consolidation",
                        timestamp: Date? = nil, target: String = "codex_core::session::handlers", body: String? = nil) throws {
        func q(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "''") + "'" }
        let text = body ?? record(thread: thread, turn: turn, trigger: trigger)
        try sql(root, "INSERT INTO logs(ts,ts_nanos,target,module_path,file,thread_id,feedback_log_body) VALUES(\(Int((timestamp ?? now).timeIntervalSince1970)),0,\(q(target)),'codex_core::session::handlers','core/src/session/handlers.rs',\(q(thread)),\(q(text)));" )
    }
    private func hook(_ type: CodexActivityHookEvent = .preToolUse, turn: String? = "turn",
                      occurredAt: Date = Date(), session: String = "memory") -> CodexActivityEvent {
        .init(event: type, sessionHash: CodexActivityPrivacy.hashIdentifier(session),
              turnHash: turn.map(CodexActivityPrivacy.hashIdentifier), workspaceName: "memories_v2",
              sessionKind: .user, source: .hook, occurredAt: occurredAt)
    }

    func testExactStartMetadataClassifiesEphemeralHookWithoutAThreadOrRollout() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        try insert(root)
        let classifier = CodexActivitySessionClassifier(codexHome: root)
        let classified = await classifier.classification(for: hook())
        XCTAssertEqual(classified.kind, .memoryConsolidation)
        XCTAssertEqual(classified.executionTurnHash, hook().turnHash)
        let next = await classifier.classification(for: hook(turn: "next"))
        XCTAssertEqual(next.kind, .unknown)
        XCTAssertNil(next.executionTurnHash)
        let unbound = await classifier.classification(for: hook(turn: nil))
        XCTAssertEqual(unbound.kind, .unknown)
    }

    func testHookHostAliasBindsOnlyTheExactNativeMemoryTurn() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        try insert(root)
        let classifier = CodexActivitySessionClassifier(codexHome: root)
        let incoming = hook(session: "host")
        let proof = await classifier.classification(for: incoming)
        XCTAssertEqual(proof.kind, .memoryConsolidation)
        XCTAssertEqual(proof.executionSessionHash, hook().sessionHash)
        XCTAssertEqual(proof.executionTurnHash, incoming.turnHash)
        let next = await classifier.classification(for: hook(turn: "different", session: "host"))
        XCTAssertEqual(next.kind, .unknown, "The host alias must not acquire a permanent memory origin")
        let native = await classifier.classification(for: incoming.classified(as: .user))
        XCTAssertEqual(native.kind, .memoryConsolidation)
        let nonHook = CodexActivityEvent(event: .preToolUse, sessionHash: incoming.sessionHash,
            turnHash: incoming.turnHash, sessionKind: .user, source: .appServer)
        let rejected = await classifier.classification(for: nonHook)
        XCTAssertEqual(rejected.kind, .user)
        XCTAssertNil(rejected.executionSessionHash)
    }

    func testAmbiguousNativeMemoryTurnCannotRewriteAHookHost() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        try insert(root); try insert(root, thread: "other-memory")
        let classifier = CodexActivitySessionClassifier(codexHome: root)
        let result = await classifier.classification(for: hook(session: "host"))
        XCTAssertEqual(result.kind, .unknown)
        XCTAssertNil(result.executionSessionHash)
    }

    @MainActor
    func testLateMemoryIdentityPreservesSessionEndCleanup() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = CodexActivityStore(titleClient: .init(executablePath: nil), sessionDirectory: root)
        for (offset, event) in [CodexActivityHookEvent.userPromptSubmit, .stop, .sessionEnd].enumerated() {
            await store.receiveClassified(.init(source: .liveSocket,
                activity: hook(event, occurredAt: now.addingTimeInterval(Double(offset)), session: "host")))
        }
        try insert(root)
        await store.receiveLocalRecord(.init(eventID: nil, update: .sessionMetadata,
            threadIdentity: .init(threadID: "memory", sessionHash: hook().sessionHash,
                sessionKind: .memoryConsolidation, executionTurnHash: hook().turnHash)), replay: false)
        XCTAssertTrue(store.backgroundMemorySnapshots.isEmpty)
        await store.stop()
    }

    @MainActor
    func testTerminalBeforeStartCannotReviveMemoryAsThinking() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        try insert(root)
        let store = CodexActivityStore(titleClient: .init(executablePath: nil), sessionDirectory: root)
        await store.receiveClassified(.init(eventID: "stop", source: .liveSocket,
            activity: hook(.stop, occurredAt: now.addingTimeInterval(2), session: "host")))
        await store.receiveClassified(.init(eventID: "late-start", source: .liveSocket,
            activity: hook(.userPromptSubmit, occurredAt: now.addingTimeInterval(1), session: "host")))
        XCTAssertEqual(store.backgroundMemorySnapshots.first?.state, .completed)
        await store.stop()
    }

    @MainActor
    func testSparseUnknownHookStillUpdatesAVerifiedUserExecution() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = CodexActivityStore(titleClient: .init(executablePath: nil), sessionDirectory: root)
        let model = IslandLiveStore()
        store.admittedActivityDidReceive = { model.receiveLegacy($0) }
        store.receive(hook(.userPromptSubmit, occurredAt: now, session: "host"))
        await store.receiveClassified(.init(source: .liveSocket,
            activity: hook(.preToolUse, occurredAt: now.addingTimeInterval(1), session: "host")))
        XCTAssertEqual(model.tasks.count, 1)
        XCTAssertEqual(model.tasks.first?.status, .working)
        XCTAssertEqual(store.snapshot?.state, .working)
        await store.stop()
    }

    @MainActor
    func testDuplicateHookIDCannotRecreateAnEvictedCanonicalMemoryTurn() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        try insert(root)
        let store = CodexActivityStore(titleClient: .init(executablePath: nil), sessionDirectory: root)
        let start = hook(.userPromptSubmit, session: "host")
        await store.receiveClassified(.init(eventID: "start", source: .liveSocket, activity: start))
        await store.receiveClassified(.init(eventID: "stop", source: .liveSocket,
            activity: hook(.stop, occurredAt: start.occurredAt.addingTimeInterval(1), session: "host")))
        for number in 0..<129 {
            store.receive(.init(event: .userPromptSubmit, sessionHash: "user-\(number)",
                turnHash: "turn-\(number)", sessionKind: .user, source: .appServer,
                occurredAt: start.occurredAt.addingTimeInterval(2 + Double(number))))
        }
        XCTAssertTrue(store.backgroundMemorySnapshots.isEmpty)
        await store.receiveClassified(.init(eventID: "start", source: .liveSocket, activity: start))
        XCTAssertTrue(store.backgroundMemorySnapshots.isEmpty)
        await store.stop()
    }

    @MainActor
    func testMetadataAndNonPositiveHookCannotRecreateAnEvictedBoundMemoryExecution() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        try insert(root)
        let store = CodexActivityStore(titleClient: .init(executablePath: nil), sessionDirectory: root)
        let start = hook(.userPromptSubmit, occurredAt: now, session: "host")
        await store.receiveClassified(.init(eventID: "start", source: .liveSocket, activity: start))
        await store.receiveClassified(.init(eventID: "stop", source: .liveSocket,
            activity: hook(.stop, occurredAt: now.addingTimeInterval(1), session: "host")))
        XCTAssertEqual(store.backgroundMemorySnapshots.first?.state, .completed)
        for number in 0..<129 {
            store.receive(.init(event: .userPromptSubmit, sessionHash: "user-\(number)",
                turnHash: "turn-\(number)", sessionKind: .user, source: .appServer,
                occurredAt: now.addingTimeInterval(2 + Double(number))))
        }
        XCTAssertTrue(store.backgroundMemorySnapshots.isEmpty)
        await store.receiveLocalRecord(.init(eventID: nil, update: .sessionMetadata,
            threadIdentity: .init(threadID: "memory", sessionHash: hook().sessionHash,
                sessionKind: .memoryConsolidation, executionTurnHash: hook().turnHash)), replay: false)
        XCTAssertTrue(store.backgroundMemorySnapshots.isEmpty, "Metadata cannot replay an already bound start")
        await store.receiveClassified(.init(eventID: "late-tool-output", source: .liveSocket,
            activity: hook(.postToolUse, occurredAt: now.addingTimeInterval(1), session: "host")))
        XCTAssertTrue(store.backgroundMemorySnapshots.isEmpty, "A tool result cannot replay an evicted start")
        await store.receiveClassified(.init(eventID: "late-start-copy", source: .liveSocket, activity: start))
        XCTAssertTrue(store.backgroundMemorySnapshots.isEmpty, "A new delivery ID cannot restore an ended turn")
        await store.stop()
    }

    @MainActor
    func testEvictedActiveMemoryRequiresNewPositiveHookWithoutReplayingItsOldStart() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        try insert(root)
        let store = CodexActivityStore(titleClient: .init(executablePath: nil), sessionDirectory: root)
        await store.receiveClassified(.init(eventID: "start", source: .liveSocket,
            activity: hook(.userPromptSubmit, occurredAt: now, session: "host")))
        for number in 0..<129 {
            store.receive(.init(event: .userPromptSubmit, sessionHash: "user-\(number)",
                turnHash: "turn-\(number)", sessionKind: .user, source: .appServer,
                occurredAt: now.addingTimeInterval(2 + Double(number))))
        }
        let parent = store.snapshot
        XCTAssertTrue(store.backgroundMemorySnapshots.isEmpty)
        await store.receiveLocalRecord(.init(eventID: nil, update: .sessionMetadata,
            threadIdentity: .init(threadID: "memory", sessionHash: hook().sessionHash,
                sessionKind: .memoryConsolidation, executionTurnHash: hook().turnHash)), replay: false)
        XCTAssertTrue(store.backgroundMemorySnapshots.isEmpty)
        let freshClock = now.addingTimeInterval(200)
        await store.receiveClassified(.init(eventID: "fresh-positive", source: .liveSocket,
            activity: hook(.preToolUse, occurredAt: freshClock, session: "host")))
        XCTAssertEqual(store.backgroundMemorySnapshots.first?.state, .working)
        XCTAssertEqual(store.backgroundMemorySnapshots.first?.occurredAt, freshClock)
        XCTAssertEqual(store.snapshot, parent)
        await store.stop()
    }

    @MainActor
    func testRejectedWeakHookStopCannotPreventAnEvictedActiveMemoryFromRecovering() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        try insert(root)
        let store = CodexActivityStore(titleClient: .init(executablePath: nil), sessionDirectory: root)
        store.receive(.init(event: .userPromptSubmit, sessionHash: hook().sessionHash,
            turnHash: hook().turnHash, sessionKind: .memoryConsolidation, source: .localRollout, occurredAt: now))
        await store.receiveClassified(.init(eventID: "bind", source: .liveSocket,
            activity: hook(.preToolUse, occurredAt: now.addingTimeInterval(1), session: "host")))
        await store.receiveClassified(.init(eventID: "weak-stop", source: .liveSocket,
            activity: hook(.stop, occurredAt: now.addingTimeInterval(2), session: "host")))
        XCTAssertEqual(store.backgroundMemorySnapshots.first?.state, .working)
        for number in 0..<129 {
            store.receive(.init(event: .userPromptSubmit, sessionHash: "user-\(number)",
                turnHash: "turn-\(number)", sessionKind: .user, source: .appServer,
                occurredAt: now.addingTimeInterval(3 + Double(number))))
        }
        let parent = store.snapshot
        XCTAssertTrue(store.backgroundMemorySnapshots.isEmpty)
        let freshClock = now.addingTimeInterval(200)
        await store.receiveClassified(.init(eventID: "fresh", source: .liveSocket,
            activity: hook(.preToolUse, occurredAt: freshClock, session: "host")))
        XCTAssertEqual(store.backgroundMemorySnapshots.first?.state, .working)
        XCTAssertEqual(store.backgroundMemorySnapshots.first?.occurredAt, freshClock)
        XCTAssertEqual(store.snapshot, parent)
        await store.stop()
    }

    @MainActor
    func testSharedHostMemoryTurnsUseTheirOwnThreadsAndPreserveParent() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        try insert(root); try insert(root, thread: "other-memory", turn: "other-turn")
        let store = CodexActivityStore(titleClient: .init(executablePath: nil), sessionDirectory: root)
        let model = IslandLiveStore()
        store.admittedActivityDidReceive = { model.receiveLegacy($0) }
        store.hookExecutionDidRebind = { model.withdrawHookExecution(session: $0, turn: $1) }
        let parent = CodexActivityEvent(event: .userPromptSubmit, sessionHash: hook(session: "host").sessionHash,
            turnHash: CodexActivityPrivacy.hashIdentifier("parent-turn"), workspaceName: "Normal task",
            sessionKind: .user, source: .appServer, occurredAt: now)
        store.receive(parent)
        let parentSnapshot = store.snapshot
        await store.receiveClassified(.init(source: .liveSocket, activity: hook(.userPromptSubmit, session: "host")))
        await store.receiveClassified(.init(source: .liveSocket,
            activity: hook(.preToolUse, turn: "other-turn", session: "host")))
        XCTAssertEqual(store.snapshot, parentSnapshot)
        XCTAssertEqual(model.tasks.count, 1)
        XCTAssertEqual(model.tasks.first?.turnKey, parent.turnHash)
        XCTAssertEqual(Set(store.backgroundMemorySnapshots.map(\.sessionHash)),
            [hook().sessionHash, CodexActivityPrivacy.hashIdentifier("other-memory")])
        await store.stop()
    }

    @MainActor
    func testLateIdentityMovesRealCompletedHookObservationAndWithdrawsOnlyItsTurn() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = CodexActivityStore(titleClient: .init(executablePath: nil), sessionDirectory: root)
        let model = IslandLiveStore()
        store.admittedActivityDidReceive = { model.receiveLegacy($0) }
        store.hookExecutionDidRebind = { model.withdrawHookExecution(session: $0, turn: $1) }
        let start = hook(.userPromptSubmit, occurredAt: now, session: "host")
        let stop = hook(.stop, occurredAt: now.addingTimeInterval(1), session: "host")
        // Simulate the retained pre-fix card independently of the new ingress.
        model.receiveLegacy(start)
        await store.receiveClassified(.init(eventID: "start", source: .liveSocket, activity: start))
        await store.receiveClassified(.init(eventID: "stop", source: .liveSocket, activity: stop))
        XCTAssertNil(store.snapshot)
        try insert(root)
        let identity = CodexLocalRolloutThreadIdentity(threadID: "memory", sessionHash: hook().sessionHash,
            sessionKind: .memoryConsolidation, executionTurnHash: start.turnHash)
        await store.receiveLocalRecord(.init(eventID: nil, update: .sessionMetadata, threadIdentity: identity), replay: false)
        XCTAssertTrue(model.tasks.isEmpty)
        XCTAssertEqual(store.backgroundMemorySnapshots.count, 1)
        XCTAssertEqual(store.backgroundMemorySnapshots.first?.state, .completed)
        XCTAssertEqual(store.backgroundMemorySnapshots.first?.occurredAt, stop.occurredAt)
        await store.receiveClassified(.init(eventID: "start", source: .liveSocket, activity: start))
        XCTAssertEqual(store.backgroundMemorySnapshots.first?.state, .completed, "External duplicate cannot revive a migrated terminal turn")
        await store.stop()
    }

    @MainActor
    func testLateMemoryIdentityCannotWithdrawANewerParentTurn() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = CodexActivityStore(titleClient: .init(executablePath: nil), sessionDirectory: root)
        let model = IslandLiveStore()
        store.admittedActivityDidReceive = { model.receiveLegacy($0) }
        store.hookExecutionDidRebind = { model.withdrawHookExecution(session: $0, turn: $1) }
        await store.receiveClassified(.init(source: .liveSocket, activity: hook(.userPromptSubmit, session: "host")))
        let parent = CodexActivityEvent(event: .userPromptSubmit, sessionHash: hook(session: "host").sessionHash,
            turnHash: CodexActivityPrivacy.hashIdentifier("parent-turn"), sessionKind: .user,
            source: .appServer, occurredAt: now.addingTimeInterval(2))
        store.receive(parent)
        let before = store.snapshot
        try insert(root)
        await store.receiveLocalRecord(.init(eventID: nil, update: .sessionMetadata,
            threadIdentity: .init(threadID: "memory", sessionHash: hook().sessionHash,
                sessionKind: .memoryConsolidation, executionTurnHash: hook().turnHash)), replay: false)
        XCTAssertEqual(store.snapshot, before)
        XCTAssertEqual(model.tasks.count, 1)
        XCTAssertEqual(model.tasks.first?.turnKey, parent.turnHash)
        XCTAssertEqual(store.backgroundMemorySnapshots.count, 1)
        await store.stop()
    }

    @MainActor
    func testUnknownHookHasNoUserProjectionAndTerminalOnlyProofCreatesNoMemoryExecution() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = CodexActivityStore(titleClient: .init(executablePath: nil), sessionDirectory: root)
        let model = IslandLiveStore()
        store.admittedActivityDidReceive = { model.receiveLegacy($0) }
        await store.receiveClassified(.init(source: .liveSocket, activity: hook(.preToolUse, turn: "unknown", session: "host")))
        XCTAssertTrue(model.tasks.isEmpty)
        XCTAssertNil(store.snapshot)
        await store.receiveClassified(.init(source: .liveSocket, activity: hook(.stop, session: "host")))
        try insert(root)
        await store.receiveLocalRecord(.init(eventID: nil, update: .sessionMetadata,
            threadIdentity: .init(threadID: "memory", sessionHash: hook().sessionHash,
                sessionKind: .memoryConsolidation, executionTurnHash: hook().turnHash)), replay: false)
        XCTAssertTrue(store.backgroundMemorySnapshots.isEmpty)
        await store.stop()
    }

    func testQuotedPromptCannotForgeMemoryTrigger() {
        let fake = "start: TurnStartOptions { turn_trigger: Some(\"memory_consolidation\"),"
        XCTAssertNil(CodexLocalExecutionMetadata.memoryTurnID(threadID: "memory",
            bytes: Array(record(trigger: "user", prompt: fake).utf8)))
        XCTAssertEqual(CodexLocalExecutionMetadata.memoryTurnID(threadID: "memory",
            bytes: Array(record(prompt: "\\\" } } " + fake).utf8)), "turn")
    }

    func testWrongThreadMalformedEnvelopeAndNestedFieldCannotProveMemory() {
        XCTAssertNil(CodexLocalExecutionMetadata.memoryTurnID(threadID: "other", bytes: Array(record().utf8)))
        XCTAssertNil(CodexLocalExecutionMetadata.memoryTurnID(threadID: "memory", bytes: Array(record().dropLast().utf8)))
        let nested = record(trigger: "user").replacingOccurrences(of: "additional_context: {}",
            with: "additional_context: { start: TurnStartOptions { turn_trigger: Some(\"memory_consolidation\"), } }")
        XCTAssertNil(CodexLocalExecutionMetadata.memoryTurnID(threadID: "memory", bytes: Array(nested.utf8)))
    }

    func testLatestNonMemoryStartCannotReuseOlderMemoryIdentity() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        try insert(root)
        try insert(root, turn: "next", trigger: "user")
        XCTAssertTrue(CodexLocalExecutionMetadata.memoryIdentities(codexHome: root, now: now).isEmpty)
    }

    func testLatestOversizedStartCannotReuseOlderMemoryIdentity() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        try insert(root)
        try insert(root, turn: "next", body: record(turn: "next", prompt: String(repeating: "a", count: 70_000)))
        XCTAssertTrue(CodexLocalExecutionMetadata.memoryIdentities(codexHome: root, now: now).isEmpty)
    }

    func testReadBudgetPreservesProvedThreadsAndReportsPartialCoverage() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        for number in 0..<34 {
            let thread = "thread-\(number)"
            try insert(root, thread: thread, body: record(thread: thread, prompt: String(repeating: "a", count: 64_000)))
        }
        let result = await CodexLocalExecutionMetadata.Service(codexHome: root).read(now: now)
        XCTAssertEqual(result.status, .partial)
        XCTAssertFalse(result.identities.isEmpty)
        XCTAssertLessThan(result.identities.count, 34)
        XCTAssertEqual(Set(result.identities.map(\.sessionHash)), result.resolvedSessions)
        XCTAssertFalse(result.failedSessions.isEmpty)
    }

    func testUnrelatedOversizedStartCannotEraseSmallMemoryProof() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        try insert(root)
        try insert(root, thread: "ordinary", trigger: "user",
            body: record(thread: "ordinary", trigger: "user", prompt: String(repeating: "a", count: 2_100_000)))
        let result = await CodexLocalExecutionMetadata.Service(codexHome: root).read(preferred: [
            .init(sessionHash: hook().sessionHash, turnHash: hook().turnHash)
        ], now: now)
        XCTAssertTrue(result.identities.contains { $0.sessionHash == hook().sessionHash })
        XCTAssertTrue(result.resolvedSessions.contains(hook().sessionHash))
    }

    func testDiscoveryCursorReachesThreadBeyondFirst128GlobalStarts() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        try insert(root)
        for number in 0..<140 { try insert(root, thread: "ordinary-\(number)", trigger: "user") }
        let service = CodexLocalExecutionMetadata.Service(codexHome: root)
        let preferred = [CodexLocalExecutionMetadata.Execution(sessionHash: hook().sessionHash, turnHash: hook().turnHash)]
        let first = await service.read(preferred: preferred, now: now)
        XCTAssertFalse(first.identities.contains { $0.sessionHash == hook().sessionHash })
        let second = await service.read(preferred: preferred, now: now)
        XCTAssertTrue(second.identities.contains { $0.sessionHash == hook().sessionHash && $0.turnHash == hook().turnHash })
    }

    func testMappedPreferredThreadIsReadBeforeNewGlobalStartFlood() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        try insert(root)
        let service = CodexLocalExecutionMetadata.Service(codexHome: root)
        let preferred = [CodexLocalExecutionMetadata.Execution(sessionHash: hook().sessionHash, turnHash: hook().turnHash)]
        let initial = await service.read(preferred: preferred, now: now)
        XCTAssertEqual(initial.identities.first?.turnHash, hook().turnHash)
        for number in 0..<140 { try insert(root, thread: "ordinary", turn: "user-\(number)", trigger: "user") }
        let result = await service.read(preferred: preferred, now: now)
        XCTAssertTrue(result.identities.contains { $0.sessionHash == hook().sessionHash && $0.turnHash == hook().turnHash })
    }

    func testUnsupportedLatestStartInvalidatesOnlyItsOwnThread() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        try insert(root)
        try insert(root, thread: "other-memory")
        let service = CodexLocalExecutionMetadata.Service(codexHome: root)
        _ = await service.read(now: now)
        try insert(root, turn: "next", body: String(record(turn: "next").dropLast()))
        let result = await service.read(now: now)
        XCTAssertTrue(result.resolvedSessions.contains(hook().sessionHash))
        XCTAssertFalse(result.identities.contains { $0.sessionHash == hook().sessionHash })
        XCTAssertTrue(result.identities.contains { $0.sessionHash == CodexActivityPrivacy.hashIdentifier("other-memory") })
    }

    func testSuccessfulEmptyReadIsDistinctFromDatabaseFailure() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let empty = await CodexLocalExecutionMetadata.Service(codexHome: root).read(now: now)
        XCTAssertEqual(empty.status, .complete)
        XCTAssertTrue(empty.identities.isEmpty)
        let absent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let failed = await CodexLocalExecutionMetadata.Service(codexHome: absent).read(preferred: [
            .init(sessionHash: hook().sessionHash, turnHash: hook().turnHash)
        ], now: now)
        XCTAssertEqual(failed.status, .failed)
        XCTAssertTrue(failed.resolvedSessions.isEmpty)
        XCTAssertEqual(failed.failedSessions, [hook().sessionHash])
    }

    func testWrongEmitterAndOutOfWindowRecordsDoNotClassify() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        try insert(root, target: "tool_output")
        try insert(root, thread: "old", timestamp: now.addingTimeInterval(-86_410))
        try insert(root, thread: "future", timestamp: now.addingTimeInterval(10))
        XCTAssertTrue(CodexLocalExecutionMetadata.memoryIdentities(codexHome: root, now: now).isEmpty)
    }

    @MainActor
    func testHookOnlyMemoryStaysInFooterAndNewTurnReturnsToUserList() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        try insert(root)
        let store = CodexActivityStore(titleClient: .init(executablePath: nil), sessionDirectory: root)
        store.setMultitaskEnabled(true)
        var kinds: [CodexActivitySessionKind] = []
        store.activityExecutionKindDidResolve = { _, kind in kinds.append(kind) }
        await store.receiveClassified(.init(source: .liveSocket, activity: hook(.userPromptSubmit)))
        XCTAssertEqual(store.backgroundMemorySnapshots.count, 1)
        XCTAssertTrue(store.multitask.entries.isEmpty)
        XCTAssertNil(store.snapshot)
        await store.receiveClassified(.init(source: .liveSocket, activity: hook(.preToolUse)))
        XCTAssertEqual(store.backgroundMemorySnapshots.count, 1)
        await store.receiveLocalRecord(.init(eventID: nil, update: .sessionMetadata,
            threadIdentity: .init(threadID: "memory", sessionHash: hook().sessionHash, sessionKind: .user)), replay: false)
        await store.receiveClassified(.init(source: .liveSocket, activity: hook(.userPromptSubmit, turn: "next")))
        XCTAssertTrue(store.backgroundMemorySnapshots.isEmpty)
        XCTAssertEqual(store.snapshot?.taskIdentity?.turnHash, hook(turn: "next").turnHash)
        XCTAssertEqual(kinds, [.memoryConsolidation, .user])
        await store.stop()
    }

    @MainActor
    func testLateMetadataMigratesMatchingTurnAndRejectsOldTurnWithoutNewHook() async throws {
        let store = CodexActivityStore(titleClient: .init(executablePath: nil))
        store.setMultitaskEnabled(true)
        store.receive(hook(.userPromptSubmit))
        XCTAssertEqual(store.snapshot?.taskIdentity?.turnHash, hook().turnHash)
        let identity = CodexLocalRolloutThreadIdentity(threadID: "memory", sessionHash: hook().sessionHash,
            sessionKind: .memoryConsolidation, executionTurnHash: hook().turnHash)
        await store.receiveLocalRecord(.init(eventID: nil, update: .sessionMetadata, threadIdentity: identity), replay: false)
        XCTAssertTrue(store.multitask.entries.isEmpty)
        XCTAssertEqual(store.backgroundMemorySnapshots.count, 1)
        store.receive(hook(.userPromptSubmit, turn: "next"))
        await store.receiveLocalRecord(.init(eventID: nil, update: .sessionMetadata, threadIdentity: identity), replay: false)
        XCTAssertEqual(store.snapshot?.taskIdentity?.turnHash, hook(turn: "next").turnHash)
        XCTAssertTrue(store.backgroundMemorySnapshots.isEmpty)
        await store.stop()
    }

    @MainActor
    func testRejectedOlderClockCannotMoveCurrentUserExecutionIntoFooter() async {
        let store = CodexActivityStore(titleClient: .init(executablePath: nil))
        var kinds: [CodexActivitySessionKind] = []
        store.activityExecutionKindDidResolve = { _, kind in kinds.append(kind) }
        store.receive(hook(.userPromptSubmit, turn: "current", occurredAt: now))
        store.receive(.init(eventID: "late-memory", source: .liveSocket,
            activity: hook(.userPromptSubmit, occurredAt: now.addingTimeInterval(-5))),
            executionMemoryTurnHash: hook().turnHash)
        XCTAssertTrue(kinds.isEmpty)
        XCTAssertTrue(store.backgroundMemorySnapshots.isEmpty)
        XCTAssertEqual(store.snapshot?.taskIdentity?.turnHash, hook(turn: "current").turnHash)
        await store.stop()
    }

    @MainActor
    func testRejectedOlderClockAndDuplicateIDCannotRevokeCurrentMemoryExecution() async {
        let store = CodexActivityStore(titleClient: .init(executablePath: nil))
        var kinds: [CodexActivitySessionKind] = []
        store.activityExecutionKindDidResolve = { _, kind in kinds.append(kind) }
        store.receive(.init(eventID: "memory-start", source: .liveSocket,
            activity: hook(.userPromptSubmit, occurredAt: now)), executionMemoryTurnHash: hook().turnHash)
        store.receive(.init(eventID: "late-user", source: .liveSocket,
            activity: hook(.userPromptSubmit, turn: "old-user", occurredAt: now.addingTimeInterval(-5))))
        store.receive(.init(eventID: "memory-start", source: .liveSocket,
            activity: hook(.userPromptSubmit, turn: "new-user", occurredAt: now.addingTimeInterval(1))))
        XCTAssertEqual(kinds, [.memoryConsolidation])
        XCTAssertEqual(store.backgroundMemorySnapshots.first?.taskIdentity?.turnHash, hook().turnHash)
        XCTAssertNil(store.snapshot)
        await store.stop()
    }

    @MainActor
    func testEvictionAndStopRevokeExecutionOverlayBeforeSameSessionReentry() async {
        let store = CodexActivityStore(titleClient: .init(executablePath: nil))
        var kinds: [CodexActivitySessionKind] = []
        store.activityExecutionKindDidResolve = { session, kind in
            if session == self.hook().sessionHash { kinds.append(kind) }
        }
        store.receive(.init(source: .liveSocket, activity: hook(.userPromptSubmit)), executionMemoryTurnHash: hook().turnHash)
        for number in 0..<129 {
            store.receive(CodexActivityEvent(event: .userPromptSubmit, sessionHash: "session-\(number)",
                turnHash: "turn-\(number)", source: .hook, occurredAt: now.addingTimeInterval(Double(number + 1))))
        }
        XCTAssertEqual(kinds, [.memoryConsolidation, .unknown])
        store.receive(hook(.userPromptSubmit, turn: "reentry", occurredAt: now.addingTimeInterval(131)))
        XCTAssertEqual(store.snapshot?.taskIdentity?.turnHash, hook(turn: "reentry").turnHash)
        store.receive(.init(source: .liveSocket, activity: hook(.userPromptSubmit, turn: "second-memory",
            occurredAt: now.addingTimeInterval(132))), executionMemoryTurnHash: hook(turn: "second-memory").turnHash)
        await store.stop()
        XCTAssertEqual(kinds, [.memoryConsolidation, .unknown, .memoryConsolidation, .unknown])
    }

    func testExistingLocalRefreshDeliversLateIdentityExactlyOnceAndNoLifecycle() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let client = CodexLocalRolloutActivityClient(configuration: .init(isEnabled: true, codexHomeURL: root))
        let sink = EphemeralIdentitySink()
        await client.start(handler: { record, _ in await sink.append(record) }, connectionStateHandler: { _ in })
        await client.pollOnceForTesting()
        try insert(root)
        await client.recheck()
        await client.recheck()
        await client.stop()
        let records = await sink.records
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.update, .sessionMetadata)
        XCTAssertEqual(records.first?.threadIdentity?.executionTurnHash, hook().turnHash)
        let second = try directory(); defer { try? FileManager.default.removeItem(at: second) }
        let changedDirectory = await client.setDataDirectory(second)
        XCTAssertTrue(changedDirectory)
    }
}

private actor EphemeralIdentitySink {
    var records: [CodexLocalRolloutDecodedRecord] = []
    func append(_ record: CodexLocalRolloutDecodedRecord) { records.append(record) }
}
