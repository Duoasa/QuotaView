import Foundation
import SQLite3

/// Some Codex background turns are intentionally neither persisted as threads
/// nor exposed by a Desktop owner. Their native start metadata is still logged.
/// This adapter reads only identity/start metadata; it never projects log text.
public enum CodexLocalExecutionMetadata {
    public struct Identity: Hashable, Sendable {
        public let threadID: String
        public let sessionHash: String
        public let turnHash: String
        public init(threadID: String, sessionHash: String, turnHash: String) {
            self.threadID = threadID; self.sessionHash = sessionHash; self.turnHash = turnHash
        }
    }
    public struct Execution: Hashable, Sendable {
        public let sessionHash: String
        public let turnHash: String?
        public init(sessionHash: String, turnHash: String?) {
            self.sessionHash = sessionHash; self.turnHash = turnHash
        }
    }
    public struct ReadResult: Sendable {
        public enum Status: Equatable, Sendable { case complete, partial, failed }
        public let identities: [Identity]
        /// These threads had their latest start checked. An absent identity
        /// means no memory proof, including an unsupported/oversized new start.
        public let resolvedSessions: Set<String>
        public let failedSessions: Set<String>
        public let status: Status
        public init(identities: [Identity], resolvedSessions: Set<String>, failedSessions: Set<String>, status: Status) {
            self.identities = identities; self.resolvedSessions = resolvedSessions
            self.failedSessions = failedSessions; self.status = status
        }
    }
    /// One service belongs to one configured directory/generation. Mapping is
    /// metadata only; it never establishes a turn or remembers a session kind.
    public actor Service {
        private let codexHome: URL
        private var threadIDs: [String: String] = [:]
        private var order: [String] = []
        private var cursor: DiscoveryCursor?
        private var preferredPivot: String?
        public init(codexHome: URL) { self.codexHome = codexHome.standardizedFileURL }
        public func read(preferred: [Execution] = [], now: Date = Date()) -> ReadResult {
            CodexLocalExecutionMetadata.readMetadata(codexHome: codexHome, preferred: preferred, now: now,
                threadIDs: &threadIDs, order: &order, cursor: &cursor, preferredPivot: &preferredPivot)
        }
    }
    static let maximumRecordBytes = 65_536
    static let maximumReadBytes = 2_097_152
    static let maximumRecords = 128

    private struct DiscoveryCursor {
        let timestamp: Int64
        let nanoseconds: Int64
        let rowID: Int64
    }
    private final class Budget {
        let deadline: UnsafeMutablePointer<TimeInterval>
        let end: TimeInterval
        var bytes = 0
        var records = 0
        var limit = CodexLocalExecutionMetadata.maximumReadBytes
        init() {
            end = ProcessInfo.processInfo.systemUptime + 0.05
            deadline = .allocate(capacity: 1)
            deadline.initialize(to: end)
        }
        deinit { deadline.deinitialize(count: 1); deadline.deallocate() }
        var available: Bool { ProcessInfo.processInfo.systemUptime < deadline.pointee }
        func charge(_ count: Int) -> Bool {
            guard count >= 0, bytes + count <= limit, available else { return false }
            bytes += count
            return true
        }
    }

    /// Compatibility for one-shot callers. Live transports share Service so
    /// discovery can advance and preferred executions are never globally ranked.
    static func memoryIdentities(codexHome: URL, now: Date = Date()) -> [Identity] {
        var threadIDs: [String: String] = [:], order: [String] = []
        var cursor: DiscoveryCursor?, preferredPivot: String?
        return readMetadata(codexHome: codexHome, preferred: [], now: now,
            threadIDs: &threadIDs, order: &order, cursor: &cursor, preferredPivot: &preferredPivot).identities
    }

    private static func readMetadata(codexHome: URL, preferred: [Execution], now: Date,
                                     threadIDs: inout [String: String], order: inout [String],
                                     cursor: inout DiscoveryCursor?, preferredPivot: inout String?) -> ReadResult {
        var wanted = Set<String>()
        let executions = preferred.prefix(maximumRecords).filter { wanted.insert($0.sessionHash).inserted }
        let pivot = preferredPivot.flatMap { hash in executions.firstIndex { $0.sessionHash == hash } }
        let prioritized = pivot.map { Array(executions[($0 + 1)...]) + Array(executions[...$0]) } ?? executions
        var database: OpaquePointer?
        guard sqlite3_open_v2(codexHome.appendingPathComponent("logs_2.sqlite").path,
            &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK, let database else {
            if let database { sqlite3_close(database) }
            return .init(identities: [], resolvedSessions: [], failedSessions: wanted, status: .failed)
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 20)
        let budget = Budget()
        sqlite3_progress_handler(database, 1000, { raw in
            guard let raw else { return 1 }
            return ProcessInfo.processInfo.systemUptime >= raw.assumingMemoryBound(to: TimeInterval.self).pointee ? 1 : 0
        }, budget.deadline)
        defer { sqlite3_progress_handler(database, 0, nil, nil) }
        let lower = Int64(now.timeIntervalSince1970 - 86_400), upper = Int64(now.timeIntervalSince1970 + 2)
        var identities: [Identity] = [], resolved = Set<String>(), failed = Set<String>()
        func read(_ hash: String, preferredTarget: Bool = false) {
            guard !resolved.contains(hash), !failed.contains(hash), let thread = threadIDs[hash] else { return }
            guard budget.available, budget.records < maximumRecords else { return }
            if preferredTarget { preferredPivot = hash }
            switch latestStart(database: database, threadID: thread, lower: lower, upper: upper, budget: budget) {
            case .resolved(let identity):
                resolved.insert(hash)
                if let identity { identities.append(identity) }
            case .failed: failed.insert(hash)
            }
        }
        // Known current executions run before discovery or unrelated requests.
        // Leave half the existing time budget for discovery/new mappings. A
        // fixed provider order cannot starve its later targets on every poll.
        if prioritized.count > 1 {
            budget.deadline.pointee = min(budget.end, ProcessInfo.processInfo.systemUptime + 0.025)
            budget.limit = maximumReadBytes - maximumRecords * (1024 + 24)
        }
        for execution in prioritized { read(execution.sessionHash, preferredTarget: true) }
        budget.deadline.pointee = budget.end; budget.limit = maximumReadBytes

        func remember(_ thread: String) {
            let hash = CodexActivityPrivacy.hashIdentifier(thread)
            if threadIDs[hash] == nil, threadIDs.count >= maximumRecords {
                guard let oldest = order.first(where: { !wanted.contains($0) }) else { return }
                threadIDs.removeValue(forKey: oldest); order.removeAll { $0 == oldest }
            }
            threadIDs[hash] = thread
            order.removeAll { $0 == hash }; order.append(hash)
        }
        // A small head pass notices new threads; the rest walks older metadata
        // with a keyset cursor. Only IDs/clocks are read, not message payloads.
        let headCount = cursor == nil ? maximumRecords : 16
        let head = discover(database: database, lower: lower, upper: upper, cursor: nil, limit: headCount, budget: budget)
        for row in head.rows { remember(row.thread) }
        var discoveryComplete = head.complete
        if let previous = cursor {
            let page = discover(database: database, lower: lower, upper: upper, cursor: previous,
                limit: maximumRecords - headCount, budget: budget)
            for row in page.rows { remember(row.thread) }
            if let last = page.lastCursor { cursor = last }
            if page.complete, page.scannedCount < maximumRecords - headCount { cursor = nil }
            discoveryComplete = discoveryComplete && page.complete && cursor == nil
        } else {
            if let last = head.lastCursor, !head.complete || head.scannedCount == headCount { cursor = last }
            discoveryComplete = discoveryComplete && cursor == nil
        }
        // Newly discovered preferred hashes also precede every other thread.
        for execution in prioritized { read(execution.sessionHash, preferredTarget: true) }
        for hash in order.reversed() { read(hash) }
        failed.formUnion(wanted.union(threadIDs.keys).subtracting(resolved))
        let complete = failed.isEmpty && discoveryComplete
        return .init(identities: identities, resolvedSessions: resolved, failedSessions: failed,
                     status: complete ? .complete : resolved.isEmpty ? .failed : .partial)
    }

    private enum ThreadRead { case resolved(Identity?), failed }
    private static func latestStart(database: OpaquePointer, threadID: String, lower: Int64, upper: Int64,
                                    budget: Budget) -> ThreadRead {
        guard budget.available, budget.records < maximumRecords else { return .failed }
        budget.records += 1
        let sql = """
        SELECT
          CASE WHEN length(CAST(feedback_log_body AS BLOB)) <= 65536 THEN feedback_log_body ELSE NULL END,
          length(CAST(feedback_log_body AS BLOB)) FROM logs
        WHERE thread_id = ? AND ts >= ? AND ts <= ? AND target = 'codex_core::session::handlers'
          AND module_path = 'codex_core::session::handlers'
          AND file = 'core/src/session/handlers.rs'
          AND CAST(substr(CAST(feedback_log_body AS BLOB), 1, 2048) AS TEXT)
            LIKE 'session_loop{thread_id=%}: Submission sub=Submission { id:%op: TurnInput %'
        ORDER BY ts DESC, ts_nanos DESC, id DESC LIMIT 1
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return .failed }
        defer { sqlite3_finalize(statement) }
        bind(threadID, to: statement, at: 1)
        sqlite3_bind_int64(statement, 2, lower); sqlite3_bind_int64(statement, 3, upper)
        let outcome = sqlite3_step(statement)
        if outcome == SQLITE_DONE { return .resolved(nil) }
        guard outcome == SQLITE_ROW else { return .failed }
        let count = Int(sqlite3_column_int64(statement, 1))
        // An oversized newest start invalidates this thread's old proof only.
        // NULL bodies do not consume another thread's transfer budget.
        guard count > 0, count <= maximumRecordBytes else { return .resolved(nil) }
        guard budget.charge(count), let bytes = sqlite3_column_blob(statement, 0) else { return .failed }
        guard let turn = memoryTurnID(threadID: threadID, bytes: Array(UnsafeBufferPointer(
            start: bytes.assumingMemoryBound(to: UInt8.self), count: count))) else { return .resolved(nil) }
        return .resolved(.init(threadID: threadID, sessionHash: CodexActivityPrivacy.hashIdentifier(threadID),
                              turnHash: CodexActivityPrivacy.hashIdentifier(turn)))
    }

    private struct DiscoveryRow { let thread: String; let cursor: DiscoveryCursor }
    private struct DiscoveryResult {
        var rows: [DiscoveryRow] = []
        var complete = false
        var scannedCount = 0
        var lastCursor: DiscoveryCursor?
    }
    private static func discover(database: OpaquePointer, lower: Int64, upper: Int64,
                                 cursor: DiscoveryCursor?, limit: Int, budget: Budget) -> DiscoveryResult {
        guard budget.available, limit > 0 else { return .init() }
        let older = cursor == nil ? "" : " AND (ts < ? OR (ts = ? AND (ts_nanos < ? OR (ts_nanos = ? AND id < ?))))"
        let sql = """
        SELECT thread_id, ts, ts_nanos, id FROM logs
        WHERE ts >= ? AND ts <= ? AND target = 'codex_core::session::handlers'
          AND module_path = 'codex_core::session::handlers'
          AND file = 'core/src/session/handlers.rs' AND thread_id IS NOT NULL
        \(older)
        ORDER BY ts DESC, ts_nanos DESC, id DESC LIMIT ?
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return .init() }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, lower); sqlite3_bind_int64(statement, 2, upper)
        var index: Int32 = 3
        if let cursor {
            for value in [cursor.timestamp, cursor.timestamp, cursor.nanoseconds, cursor.nanoseconds, cursor.rowID] {
                sqlite3_bind_int64(statement, index, value); index += 1
            }
        }
        sqlite3_bind_int(statement, index, Int32(limit))
        var result = DiscoveryResult()
        while budget.available {
            let outcome = sqlite3_step(statement)
            if outcome == SQLITE_DONE { result.complete = true; return result }
            guard outcome == SQLITE_ROW else { return result }
            let location = DiscoveryCursor(timestamp: sqlite3_column_int64(statement, 1),
                nanoseconds: sqlite3_column_int64(statement, 2), rowID: sqlite3_column_int64(statement, 3))
            result.scannedCount += 1; result.lastCursor = location
            guard let bytes = sqlite3_column_text(statement, 0) else { continue }
            let count = Int(sqlite3_column_bytes(statement, 0))
            guard count > 0, count <= 1024 else { continue }
            guard budget.charge(count + 24) else { return result }
            let thread = String(cString: bytes)
            result.rows.append(.init(thread: thread, cursor: location))
        }
        return result
    }

    private static func bind(_ text: String, to statement: OpaquePointer, at index: Int32) {
        sqlite3_bind_text(statement, index, text, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }

    /// Parse the Rust Debug envelope by structure. Quoted prompt/tool content is
    /// opaque, so it cannot forge a start field or an execution identity.
    static func memoryTurnID(threadID: String, bytes: [UInt8]) -> String? {
        guard bytes.count <= maximumRecordBytes, threadID.utf8.count <= 1024 else { return nil }
        let prefix = Array("session_loop{thread_id=\(threadID)}: Submission sub=Submission { id: ".utf8)
        guard bytes.starts(with: prefix) else { return nil }
        var cursor = prefix.count
        guard let turn = quoted(bytes, cursor: &cursor), !turn.isEmpty, turn.utf8.count <= 1024 else { return nil }
        let opening = Array(", op: TurnInput { request: TurnInputRequest {".utf8)
        guard bytes[cursor...].starts(with: opening) else { return nil }
        cursor += opening.count
        var depth = 3, matches = 0
        let marker = Array("start: TurnStartOptions { turn_trigger: Some(\"memory_consolidation\"),".utf8)
        while cursor < bytes.count {
            if bytes[cursor] == 34 {
                guard skipQuoted(bytes, cursor: &cursor) else { return nil }
                continue
            }
            if depth == 3, bytes[cursor...].starts(with: marker),
               cursor == 0 || bytes[cursor - 1] == 32 || bytes[cursor - 1] == 44 {
                matches += 1
            }
            if bytes[cursor] == 123 { depth += 1 }
            else if bytes[cursor] == 125 { depth -= 1; if depth < 0 { return nil } }
            cursor += 1
        }
        return depth == 0 && matches == 1 ? turn : nil
    }

    private static func quoted(_ bytes: [UInt8], cursor: inout Int) -> String? {
        let start = cursor
        guard skipQuoted(bytes, cursor: &cursor), cursor > start + 1 else { return nil }
        let value = bytes[(start + 1)..<(cursor - 1)]
        // IDs never need escaped Rust Debug strings; reject ambiguous encodings.
        guard !value.contains(92) else { return nil }
        return String(bytes: value, encoding: .utf8)
    }

    private static func skipQuoted(_ bytes: [UInt8], cursor: inout Int) -> Bool {
        guard cursor < bytes.count, bytes[cursor] == 34 else { return false }
        cursor += 1
        while cursor < bytes.count {
            if bytes[cursor] == 92 { cursor += 2 }
            else if bytes[cursor] == 34 { cursor += 1; return true }
            else { cursor += 1 }
        }
        return false
    }
}
