import Foundation
import SQLite3
import XCTest
import QuotaViewActivityHookSupport

/// Schema reproduced from the official 3000.11.234 CLI's freshly created DB
/// and its own SQLite -> files migration, without signing in or making requests.
final class DevinUsageFixture {
    let root: URL
    let directory: URL
    let store: DevinSessionUsage.Store
    let db: OpaquePointer
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("qv-devin-usage-" + UUID().uuidString)
        directory = root.appendingPathComponent("cli")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = try XCTUnwrap(DevinSessionUsage.Store(directory: directory.path, files: false))
        var pointer: OpaquePointer?
        XCTAssertEqual(sqlite3_open(directory.appendingPathComponent("sessions.db").path, &pointer), SQLITE_OK)
        db = try XCTUnwrap(pointer)
        // Integration tests write while the real observer holds short read
        // transactions. A zero-timeout fixture writer can fail spuriously on CI.
        XCTAssertEqual(sqlite3_busy_timeout(db, 1_000), SQLITE_OK)
        try execute("CREATE TABLE sessions(id TEXT PRIMARY KEY, model TEXT NOT NULL)")
        try execute("CREATE TABLE message_nodes(session_id TEXT NOT NULL, node_id INTEGER NOT NULL, chat_message TEXT NOT NULL, UNIQUE(session_id,node_id))")
        try execute("INSERT INTO sessions VALUES('shared','swe-2-max')")
    }
    deinit { sqlite3_close(db); try? FileManager.default.removeItem(at: root) }
    func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "DevinFixture", code: Int(sqlite3_errcode(db)))
        }
    }
    func message(_ id: Int, request: String? = nil, input: Any = 100, output: Any = 10, session: String = "shared") throws {
        let object: [String: Any] = ["role": "assistant", "content": "PRIVATE_RESPONSE", "message_id": "message-\(id)",
            "metadata": ["request_id": request ?? "request-\(id)", "metrics": ["input_tokens": input, "output_tokens": output,
                "cache_read_tokens": 80, "context_input_tokens": 9999]]]
        let data = try JSONSerialization.data(withJSONObject: object)
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, "INSERT INTO message_nodes VALUES(?1,?2,?3)", -1, &statement, nil), SQLITE_OK)
        let s = try XCTUnwrap(statement); defer { sqlite3_finalize(s) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(s, 1, session, -1, transient); sqlite3_bind_int(s, 2, Int32(id))
        sqlite3_bind_text(s, 3, String(decoding: data, as: UTF8.self), -1, transient)
        let result = sqlite3_step(s)
        guard result == SQLITE_DONE else {
            throw NSError(domain: "DevinFixture", code: Int(result))
        }
    }
}

final class DevinSessionUsageTests: XCTestCase {
    func testDatabaseUsesSessionModelAndOnlyNewRequestsWithoutDoubleCounting() throws {
        let fixture = try DevinUsageFixture()
        try fixture.message(1, input: 99999)
        let baseline = try XCTUnwrap(DevinSessionUsage.read(session: "shared", store: fixture.store))
        XCTAssertEqual(baseline.model, "swe-2-max"); XCTAssertEqual(baseline.position, 1); XCTAssertNil(baseline.tokens)
        try fixture.message(2, request: "same"); try fixture.message(3, request: "same")
        try fixture.message(4, input: 20, output: 10)
        try fixture.message(5, input: 999999, session: "other")
        for _ in 0..<2 {
            let snapshot = try XCTUnwrap(DevinSessionUsage.read(session: "shared", store: fixture.store, after: baseline.position))
            XCTAssertEqual(snapshot.tokens, 140); XCTAssertEqual(snapshot.position, 4)
        }
        try fixture.execute("UPDATE sessions SET model='another-model' WHERE id='shared'")
        XCTAssertEqual(DevinSessionUsage.read(session: "shared", store: fixture.store)?.model, "another-model")
        XCTAssertNil(DevinSessionUsage.read(session: "shared", store: fixture.store, after: 4)?.tokens)
        XCTAssertEqual(DevinSessionUsage.read(session: "new-session", store: fixture.store)?.position, -1)
    }

    func testMissingCorruptAndInvalidCountsNeverBecomeFabricatedZero() throws {
        let fixture = try DevinUsageFixture()
        try fixture.message(1, input: -1); try fixture.message(2, input: true)
        try fixture.message(3, input: 1.5); try fixture.message(4, input: "200")
        try fixture.message(5, input: NSNumber(value: Int64.max))
        XCTAssertNil(DevinSessionUsage.read(session: "shared", store: fixture.store, after: -1)?.tokens)
        try fixture.message(6, input: 0, output: 0)
        XCTAssertEqual(DevinSessionUsage.read(session: "shared", store: fixture.store, after: -1)?.tokens, 0)
        try fixture.execute("UPDATE message_nodes SET chat_message='invalid-json' WHERE node_id=1")
        let invalid = DevinSessionUsage.read(session: "shared", store: fixture.store, after: -1)
        XCTAssertEqual(invalid?.model, "swe-2-max"); XCTAssertNil(invalid?.tokens)
        XCTAssertNil(DevinSessionUsage.read(session: "../../private", store: fixture.store))
        XCTAssertNil(DevinSessionUsage.read(session: "shared", store: fixture.store, after: -2))
        let missing = try XCTUnwrap(DevinSessionUsage.Store(directory: fixture.root.appendingPathComponent("missing").path, files: false))
        XCTAssertNil(DevinSessionUsage.read(session: "shared", store: missing))
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.directory.path))
    }

    func testDatabaseIsReadOnlyAndLockWaitIsBounded() throws {
        let fixture = try DevinUsageFixture()
        let before = try Data(contentsOf: fixture.directory.appendingPathComponent("sessions.db"))
        _ = DevinSessionUsage.read(session: "shared", store: fixture.store)
        XCTAssertEqual(before, try Data(contentsOf: fixture.directory.appendingPathComponent("sessions.db")))
        try fixture.execute("BEGIN EXCLUSIVE")
        let started = ProcessInfo.processInfo.systemUptime
        XCTAssertNil(DevinSessionUsage.read(session: "shared", store: fixture.store))
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - started, 0.5)
        try fixture.execute("ROLLBACK")
    }

    func testLiveWALUsageIsVisibleWithoutChangingDatabaseOrJournal() throws {
        let fixture = try DevinUsageFixture()
        try fixture.execute("PRAGMA journal_mode=WAL")
        try fixture.message(1, input: 9999)
        let start = try XCTUnwrap(DevinSessionUsage.read(session: "shared", store: fixture.store)?.position)
        try fixture.message(2, input: 70, output: 30)
        let database = fixture.directory.appendingPathComponent("sessions.db")
        let journal = fixture.directory.appendingPathComponent("sessions.db-wal")
        let before = try Data(contentsOf: database), walBefore = try Data(contentsOf: journal)
        XCTAssertEqual(DevinSessionUsage.read(session: "shared", store: fixture.store, after: start)?.tokens, 100)
        XCTAssertEqual(before, try Data(contentsOf: database)); XCTAssertEqual(walBefore, try Data(contentsOf: journal))
    }

    func testFileStoreByteBoundaryPartialAppendAndDeduplication() throws {
        let fixture = try DevinUsageFixture()
        let store = try XCTUnwrap(DevinSessionUsage.Store(directory: fixture.directory.path, files: true))
        let directory = fixture.directory.appendingPathComponent("sessions/shared")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"v":1,"id":"shared","model":"swe-2-max","excerpts":["PRIVATE"]}"#.utf8).write(to: directory.appendingPathComponent("meta.json"))
        let log = directory.appendingPathComponent("log.jsonl")
        let history = #"{"kind":"node","node":{"id":1,"message":{"role":"assistant","content":"PRIVATE","metadata":{"request_id":"history","metrics":{"input_tokens":99999,"output_tokens":1}}}}}"# + "\n"
        try Data(history.utf8).write(to: log)
        let baseline = try XCTUnwrap(DevinSessionUsage.read(session: "shared", store: store))
        XCTAssertEqual(baseline.position, Int64(history.utf8.count)); XCTAssertNil(baseline.tokens)
        let current = #"{"kind":"node","node":{"id":2,"message":{"role":"assistant","content":"PRIVATE","metadata":{"request_id":"new","metrics":{"input_tokens":100,"output_tokens":20}}}}}"#
        try Data((history + current + "\n" + current).utf8).write(to: log)
        XCTAssertEqual(DevinSessionUsage.read(session: "shared", store: store, after: baseline.position)?.tokens, 120)
        try Data((history + current + "\n" + current + "\n").utf8).write(to: log)
        XCTAssertEqual(DevinSessionUsage.read(session: "shared", store: store, after: baseline.position)?.tokens, 120)
        try Data(history.utf8.prefix(10)).write(to: log)
        XCTAssertNil(DevinSessionUsage.read(session: "shared", store: store, after: baseline.position)?.tokens)
    }

    func testStoreDiscoveryUsesClientEnvironmentAndRejectsSessionPaths() throws {
        let home = URL(fileURLWithPath: "/fixture/home")
        XCTAssertEqual(DevinSessionUsage.Store.current(session: "abc", environment: [:], home: home)?.directory.path,
                       "/fixture/home/.local/share/devin/cli")
        XCTAssertEqual(DevinSessionUsage.Store.current(session: "abc", environment: ["XDG_DATA_HOME": "/fixture/data"], home: home)?.directory.path,
                       "/fixture/data/devin/cli")
        let override = DevinSessionUsage.Store.current(session: "abc", environment: ["DEVIN_SESSIONS_DIR": "/fixture/sessions", "DEVIN_SESSION_STORE": "files"], home: home)
        XCTAssertEqual(override?.directory.path, "/fixture/sessions/cli"); XCTAssertEqual(override?.files, true)
        XCTAssertNil(DevinSessionUsage.Store.current(session: "../bad", environment: [:], home: home))
    }
}
