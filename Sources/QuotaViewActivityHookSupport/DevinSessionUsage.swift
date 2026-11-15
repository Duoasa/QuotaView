import Foundation
import CoreFoundation
import SQLite3

/// Local metadata only. The hook captures a position before generation starts;
/// the app reads subsequent usage off the main thread, including delayed commits.
public enum DevinSessionUsage {
    public struct Store: Sendable, Equatable {
        public let directory: URL
        public let files: Bool

        public init?(directory: String, files: Bool) {
            guard directory.hasPrefix("/"), directory.utf8.count <= 4096,
                  !directory.contains("\0") else { return nil }
            self.directory = URL(fileURLWithPath: directory).standardizedFileURL
            self.files = files
        }

        public static func current(session: String, environment: [String: String] = ProcessInfo.processInfo.environment,
                                   home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Store? {
            guard validSession(session) else { return nil }
            let base: URL
            if let custom = environment["DEVIN_SESSIONS_DIR"], custom.hasPrefix("/") {
                base = URL(fileURLWithPath: custom)
            } else if let data = environment["XDG_DATA_HOME"], data.hasPrefix("/") {
                base = URL(fileURLWithPath: data).appendingPathComponent("devin")
            } else { base = home.appendingPathComponent(".local/share/devin") }
            let directory = base.appendingPathComponent("cli")
            let files = environment["DEVIN_SESSION_STORE"] == "files"
                || (environment["DEVIN_SESSION_STORE"] != "sqlite"
                    && FileManager.default.fileExists(atPath: directory.appendingPathComponent("sessions/\(session)/meta.json").path))
            return Store(directory: directory.path, files: files)
        }
    }

    public struct Snapshot: Sendable {
        public let model: String?
        /// SQLite node id or JSONL byte offset, according to Store.files.
        public let position: Int64?
        /// Input + output reported by completed model requests after the position.
        /// Cache/context counters are not added again; missing usage stays unknown.
        public let tokens: Int64?
        public var rates: [AgentRateObservation] = []
    }

    private static func validSession(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 128
            && value.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }
    }

    private static func model(_ value: Any?) -> String? {
        guard let value = value as? String, !value.isEmpty, value.utf8.count <= 128,
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return value
    }

    public static func read(session: String, store: Store, after position: Int64? = nil) -> Snapshot? {
        guard validSession(session), position == nil || position! >= -1 else { return nil }
        return store.files ? readFiles(session: session, store: store, after: position)
            : readDatabase(session: session, store: store, after: position)
    }

    private final class Budget {
        let deadline = ProcessInfo.processInfo.systemUptime + 0.08
        var expired: Bool { ProcessInfo.processInfo.systemUptime >= deadline }
    }

    private static func readDatabase(session: String, store: Store, after position: Int64?) -> Snapshot? {
        let path = store.directory.appendingPathComponent("sessions.db").path
        // Unavailable is not an empty history. No database is created here.
        guard isRegularFile(URL(fileURLWithPath: path)) else { return nil }
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }; return nil
        }
        defer { sqlite3_close(db) }
        sqlite3_limit(db, SQLITE_LIMIT_LENGTH, 1_048_576)
        sqlite3_busy_timeout(db, 20)
        let budget = Budget()
        sqlite3_progress_handler(db, 500, { context in
            guard let context else { return 1 }
            return Unmanaged<Budget>.fromOpaque(context).takeUnretainedValue().expired ? 1 : 0
        }, Unmanaged.passUnretained(budget).toOpaque())
        defer { sqlite3_progress_handler(db, 0, nil, nil) }
        guard sqlite3_exec(db, "BEGIN", nil, nil, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_exec(db, "ROLLBACK", nil, nil, nil) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        func prepare(_ sql: String) -> OpaquePointer? {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return nil }
            sqlite3_bind_text(statement, 1, session, -1, transient)
            return statement
        }
        guard let header = prepare("SELECT model, (SELECT COALESCE(MAX(node_id), -1) FROM message_nodes WHERE session_id = ?1) FROM sessions WHERE id = ?1") else { return nil }
        defer { sqlite3_finalize(header) }
        let status = sqlite3_step(header)
        if status == SQLITE_DONE { return Snapshot(model: nil, position: -1, tokens: nil) }
        guard status == SQLITE_ROW else { return nil }
        let selectedModel = model(text(header, 0))
        let latest = sqlite3_column_int64(header, 1)
        let metadata = Snapshot(model: selectedModel, position: latest, tokens: nil)
        guard let position, latest > position else { return metadata }
        // Project only these metadata fields; prompt, response and tool content
        // are never returned from SQLite or put into the event envelope.
        guard let query = prepare("""
            SELECT node_id, json_extract(chat_message, '$.metadata.request_id'),
                   json_extract(chat_message, '$.message_id'),
                   json_extract(chat_message, '$.metadata.metrics.input_tokens'),
                   json_extract(chat_message, '$.metadata.metrics.output_tokens'),
                   json_type(chat_message, '$.metadata.metrics.input_tokens'),
                   json_type(chat_message, '$.metadata.metrics.output_tokens'),
                   json_extract(chat_message, '$.metadata.metrics.total_time_ms')
            FROM message_nodes WHERE session_id = ?1 AND node_id > ?2
              AND json_extract(chat_message, '$.role') = 'assistant'
            ORDER BY node_id LIMIT 8193
            """) else { return metadata }
        defer { sqlite3_finalize(query) }
        sqlite3_bind_int64(query, 2, position)
        var requests: [String: Int64] = [:]
        var rates: [String: AgentRateObservation] = [:]
        var rows = 0
        while true {
            let result = sqlite3_step(query)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW, rows < 8192, !budget.expired else { return metadata }
            rows += 1
            guard text(query, 5) == "integer", text(query, 6) == "integer",
                  sqlite3_column_type(query, 3) == SQLITE_INTEGER, sqlite3_column_type(query, 4) == SQLITE_INTEGER,
                  let count = total(sqlite3_column_int64(query, 3), sqlite3_column_int64(query, 4)) else { continue }
            let id = text(query, 1) ?? text(query, 2) ?? "node:\(sqlite3_column_int64(query, 0))"
            requests[id] = max(requests[id] ?? 0, count)
            if sqlite3_column_type(query, 7) == SQLITE_INTEGER,
               let rate = AgentRateObservation(id: id, output: sqlite3_column_int64(query, 4),
                   durationMS: Double(sqlite3_column_int64(query, 7)), end: Date()),
               rate.output > (rates[id]?.output ?? 0) { rates[id] = rate }
        }
        return Snapshot(model: selectedModel, position: latest, tokens: sum(requests), rates: Array(rates.values))
    }

    private static func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) == SQLITE_TEXT,
              sqlite3_column_bytes(statement, column) <= 256, let bytes = sqlite3_column_text(statement, column) else { return nil }
        let value = String(cString: bytes)
        return value.isEmpty ? nil : value
    }

    private static func total(_ input: Int64, _ output: Int64) -> Int64? {
        guard (0...1_000_000_000_000).contains(input), (0...1_000_000_000_000).contains(output) else { return nil }
        return input + output
    }

    private static func integer(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue >= 0, number.doubleValue <= 1_000_000_000_000,
              number.doubleValue == Double(number.int64Value) else { return nil }
        return number.int64Value
    }

    private static func sum(_ requests: [String: Int64]) -> Int64? {
        guard !requests.isEmpty else { return nil }
        let total = requests.values.reduce(Int64(0), +) // bounded: <= 8192 * 2e12
        return total <= 1_000_000_000_000 ? total : nil
    }

    private static func readFiles(session: String, store: Store, after position: Int64?) -> Snapshot? {
        let directory = store.directory.appendingPathComponent("sessions/\(session)")
        let meta = directory.appendingPathComponent("meta.json")
        let log = directory.appendingPathComponent("log.jsonl")
        guard isRegularFile(meta), isRegularFile(log) else { return nil }
        guard let handle = try? FileHandle(forReadingFrom: meta) else { return nil }
        defer { try? handle.close() }
        guard let bytes = try? handle.read(upToCount: 65_537), bytes.count <= 65_536,
              let object = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any],
              object["id"] as? String == session, object["v"] as? Int == 1 else { return nil }
        let selectedModel = model(object["model"])
        guard let file = try? FileHandle(forReadingFrom: log) else { return Snapshot(model: selectedModel, position: nil, tokens: nil) }
        defer { try? file.close() }
        guard let end = try? file.seekToEnd(), end <= UInt64(Int64.max) else { return nil }
        let metadata = Snapshot(model: selectedModel, position: Int64(end), tokens: nil)
        guard let position, position >= 0, UInt64(position) <= end, end - UInt64(position) <= 16_777_216 else { return metadata }
        do { try file.seek(toOffset: UInt64(position)) } catch { return metadata }
        guard let data = try? file.read(upToCount: Int(end - UInt64(position))) else { return metadata }
        var requests: [String: Int64] = [:]
        var rates: [String: AgentRateObservation] = [:]
        let budget = Budget()
        var rows = 0
        // Ignore the unfinished final line while Devin is appending it. Re-read
        // from the original turn boundary next time; duplicates remain idempotent.
        guard let lastNewline = data.lastIndex(of: 10) else { return metadata }
        for line in data.prefix(through: lastNewline).split(separator: 10) {
            guard rows < 8192, line.count <= 1_048_576, !budget.expired else { return metadata }
            rows += 1
            guard let item = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any] else { return metadata }
            guard item["kind"] as? String == "node", let node = item["node"] as? [String: Any],
                  let message = node["message"] as? [String: Any], message["role"] as? String == "assistant",
                  let info = message["metadata"] as? [String: Any], let metrics = info["metrics"] as? [String: Any],
                  let input = integer(metrics["input_tokens"]), let output = integer(metrics["output_tokens"]),
                  let count = total(input, output), let nodeID = integer(node["id"]) else { continue }
            let id = (info["request_id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? (message["message_id"] as? String) ?? "node:\(nodeID)"
            guard id.utf8.count <= 256 else { continue }
            requests[id] = max(requests[id] ?? 0, count)
            if let ms = integer(metrics["total_time_ms"]),
               let rate = AgentRateObservation(id: id, output: output, durationMS: Double(ms), end: Date()),
               rate.output > (rates[id]?.output ?? 0) { rates[id] = rate }
        }
        return Snapshot(model: selectedModel, position: Int64(end), tokens: sum(requests), rates: Array(rates.values))
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeRegular
    }
}

/// Privacy-bounded output accounting shared by local file and hook adapters.
public struct AgentRateObservation: Sendable {
    public let id: String
    public let output: Int64
    public let start: Date
    public let end: Date
    public init?(id: String, output: Int64, durationMS: Double, end: Date) {
        guard !id.isEmpty, id.utf8.count <= 512, (1...1_000_000_000).contains(output),
              durationMS.isFinite, durationMS > 0, durationMS <= 86_400_000,
              end.timeIntervalSince1970.isFinite else { return nil }
        self.id = id; self.output = output; self.end = end
        start = end.addingTimeInterval(-durationMS / 1000)
    }
    public static func integer(_ value: Any?) -> Int64? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
              n.doubleValue.isFinite, n.doubleValue >= 0, n.doubleValue <= 9_007_199_254_740_991,
              n.doubleValue == Double(n.int64Value) else { return nil }
        return n.int64Value
    }
}

/// Bounded turn-local reads. Only official Kimi request/usage and Copilot usage
/// records are admitted; session aggregates and incomplete JSONL tails are ignored.
public enum AgentRateLog {
    public static func locate(provider: String, session: String, agent: String = "main",
                              environment: [String: String] = ProcessInfo.processInfo.environment,
                              home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        func safe(_ s: String) -> Bool {
            !s.isEmpty && s.utf8.count <= 256 && s != "." && s != ".."
                && !s.contains("/") && !s.contains("\0")
        }
        guard safe(session), safe(agent) else { return nil }
        let key = provider == "kimiCode" ? "KIMI_CODE_HOME" : "COPILOT_HOME"
        let standard = provider == "kimiCode" ? ".kimi-code" : ".copilot"
        let base = environment[key].flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil }
            ?? home.appendingPathComponent(standard)
        if provider == "copilotCLI" { return base.appendingPathComponent("session-state/\(session)/events.jsonl") }
        guard provider == "kimiCode",
              let workspaces = try? FileManager.default.contentsOfDirectory(at: base.appendingPathComponent("sessions"),
                  includingPropertiesForKeys: nil), workspaces.count <= 512 else { return nil }
        let matches = workspaces.map { $0.appendingPathComponent("\(session)/agents/\(agent)/wire.jsonl") }
            .filter { FileManager.default.fileExists(atPath: $0.deletingLastPathComponent().path) }
        return matches.count == 1 ? matches[0] : nil
    }
    public static func position(_ url: URL) -> Int64? {
        if !FileManager.default.fileExists(atPath: url.path) { return 0 }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              attrs[.type] as? FileAttributeType == .typeRegular else { return nil }
        return (attrs[.size] as? NSNumber)?.int64Value
    }
    public static func read(url: URL, provider: String, after: Int64, since: Date) -> [AgentRateObservation] {
        guard after >= 0, let end = position(url), end >= after, end - after <= 16_777_216,
              let file = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? file.close() }
        do { try file.seek(toOffset: UInt64(after)) } catch { return [] }
        guard let data = try? file.read(upToCount: Int(end - after)),
              let newline = data.lastIndex(of: 10) else { return [] }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.08
        var rates: [AgentRateObservation] = [], request: Double?, rows = 0
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for line in data.prefix(through: newline).split(separator: 10) {
            rows += 1
            guard rows <= 8192, line.count <= 1_048_576, ProcessInfo.processInfo.systemUptime < deadline else { return [] }
            guard let obj = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any] else { continue }
            let type = obj["type"] as? String
            if provider == "kimiCode" {
                if type == "llm.request" { request = AgentRateObservation.integer(obj["time"]).map(Double.init); continue }
                guard type == "usage.record", obj["usageScope"] as? String == "turn" else { continue }
                let start = request; request = nil
                guard let start, let end = AgentRateObservation.integer(obj["time"]),
                      let usage = obj["usage"] as? [String: Any], let output = AgentRateObservation.integer(usage["output"]),
                      let rate = AgentRateObservation(id: "kimi:\(after):\(rows)", output: output,
                          durationMS: Double(end) - start, end: Date(timeIntervalSince1970: Double(end)/1000)),
                      rate.start >= since.addingTimeInterval(-1) else { continue }
                rates.append(rate)
            } else if provider == "copilotCLI", type == "session.usage_record",
                      let data = obj["data"] as? [String: Any], let usage = data["usage"] as? [String: Any],
                      let output = AgentRateObservation.integer(usage["outputTokens"]),
                      let duration = usage["duration"] as? Double, let raw = obj["timestamp"] as? String,
                      let end = iso.date(from: raw) ?? ISO8601DateFormatter().date(from: raw),
                      let id = obj["id"] as? String,
                      let rate = AgentRateObservation(id: id, output: output, durationMS: duration, end: end),
                      rate.start >= since.addingTimeInterval(-1) { rates.append(rate) }
        }
        return rates
    }
}
