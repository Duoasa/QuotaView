import Foundation
import QuotaViewCore
import SQLite3
#if SWIFT_PACKAGE
import QuotaViewActivityHookSupport
#endif

/// Local display projections. The hook only supplies a conversation identifier and client hint.
enum AntigravityHistory {
    static let clients = ["antigravity", "antigravity-cli", "antigravity-ide"]

    static func logs(root: URL, session: String, client: String?) -> URL? {
        guard UUID(uuidString: session) != nil else { return nil }
        let matches = clients.filter { client == nil || client == $0 }.map {
            root.appendingPathComponent($0 + "/brain/" + session + "/.system_generated/logs", isDirectory: true)
        }.filter { safe($0) && FileManager.default.fileExists(atPath: $0.path) }
        return matches.count == 1 ? matches[0] : nil
    }

    static func safe(_ url: URL) -> Bool {
        url.standardizedFileURL.path == url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    static func title(database: URL, session: String) -> String? {
        guard safe(database), FileManager.default.fileExists(atPath: database.path) else { return nil }
        func read(_ path: String) -> String? {
            var db: OpaquePointer?
            defer { sqlite3_close(db) }
            guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else { return nil }
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            let sql = "SELECT substr(coalesce(nullif(trim(title), ''), preview), 1, 256) FROM conversation_summaries WHERE conversation_id = ?"
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
            return session.withCString { id in
                guard sqlite3_bind_text(statement, 1, id, -1, nil) == SQLITE_OK,
                      sqlite3_step(statement) == SQLITE_ROW, let raw = sqlite3_column_text(statement, 0) else { return nil }
                let value = String(cString: raw).split(whereSeparator: \.isWhitespace).joined(separator: " ")
                return value.isEmpty ? nil : value
            }
        }
        if let value = read(database.path) { return value }
        // A checkpointed WAL database can lack sidecars. Read it without creating any.
        guard !FileManager.default.fileExists(atPath: database.path + "-wal") else { return nil }
        return read(database.absoluteString + "?immutable=1")
    }

    struct Reply {
        let index: Int
        let text: String
        let truncated: Bool
        let hasTools: Bool
        let date: Date
    }

    static func replies(logs: URL, firstStep: Int?, start: Date, end: Date) -> [Reply] {
        let file = logs.appendingPathComponent("transcript_full.jsonl")
        guard safe(file), let size = ClaudeCodeTranscriptTail.fileSize(file.path) else { return [] }
        var reader = ClaudeCodeTranscriptTail(path: file.path, offset: size > 4_194_304 ? size - 4_194_304 : 0)
        let clock = ISO8601DateFormatter()
        var result: [Int: Reply] = [:]
        for line in reader.readLines() {
            guard let row = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  row["type"] as? String == "PLANNER_RESPONSE", row["status"] as? String == "DONE",
                  let index = row["step_index"] as? Int, firstStep.map({ index >= $0 }) ?? true,
                  let stamp = row["created_at"] as? String, let date = clock.date(from: stamp),
                  date.timeIntervalSince1970 >= floor(start.timeIntervalSince1970) - (firstStep == nil ? 0 : 1), date <= end,
                  let raw = row["content"] as? String, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let prefix = String(raw.prefix(65_536))
            result[index] = Reply(index: index, text: prefix, truncated: raw.count > 65_536,
                hasTools: !(row["tool_calls"] as? [Any] ?? []).isEmpty, date: date)
        }
        return result.values.sorted { $0.index < $1.index }
    }

    static func tokens(_ row: [String: Any]) -> Int64? {
        func count(_ key: String) -> Int64? {
            guard let n = AgentRateObservation.integer(row[key]), (0...1_000_000_000).contains(n) else { return nil }
            return n
        }
        guard let input = count("input_tokens"), let output = count("output_tokens"),
              let cached = (row["cache_read_tokens"] == nil ? 0 : count("cache_read_tokens")) else { return nil }
        return input + cached + output
    }
}

struct AntigravityUsage: Equatable, Sendable {
    var account: AntigravityAccount?
    var days: [DailyTokenActivity] = []
    var updatedAt: Date?
    var total: Int64? { days.isEmpty ? nil : days.reduce(0) { $0 + $1.tokens } }
}

/// Cache unchanged transcripts. Chunk mirrors and repeated writes share a conversation/step identity.
actor AntigravityUsageScanner {
    private struct Sample {
        let day: Date
        let tokens: Int64
        let timestamp: Date
    }
    private struct Cached {
        let modified: Date
        let size: UInt64
        let samples: [Int: Sample]
    }
    private var cache: [URL: Cached] = [:]

    func scan(root: URL) -> AntigravityUsage {
        var seen = Set<URL>(), days: [Date: Int64] = [:]
        var latest: Date?
        let fm = FileManager.default
        let clock = ISO8601DateFormatter()
        var conversations: [String: [Int: Sample]] = [:]
        for client in AntigravityHistory.clients {
            let brain = root.appendingPathComponent(client + "/brain")
            for folder in (try? fm.contentsOfDirectory(at: brain, includingPropertiesForKeys: nil)) ?? [] {
                guard !Task.isCancelled, let uuid = UUID(uuidString: folder.lastPathComponent) else { continue }
                let logs = folder.appendingPathComponent(".system_generated/logs")
                let chunks = logs.appendingPathComponent("chunks/transcript_full")
                let history = ((try? fm.contentsOfDirectory(at: chunks, includingPropertiesForKeys: nil)) ?? [])
                    .filter { $0.pathExtension == "jsonl" }.sorted { $0.path < $1.path }
                for file in history + [logs.appendingPathComponent("transcript_full.jsonl")] {
                    guard !Task.isCancelled, AntigravityHistory.safe(file), let size = ClaudeCodeTranscriptTail.fileSize(file.path),
                          let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { continue }
                    seen.insert(file)
                    if cache[file]?.modified != modified || cache[file]?.size != size {
                        var reader = ClaudeCodeTranscriptTail(path: file.path)
                        var samples: [Int: Sample] = [:]
                        while reader.offset < size && !Task.isCancelled {
                            let before = reader.offset
                            for line in reader.readLines(maximumBytes: 1_048_576) {
                                guard let row = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                                      row["type"] as? String == "PLANNER_RESPONSE",
                                      let index = row["step_index"] as? Int, let count = AntigravityHistory.tokens(row),
                                      let stamp = row["created_at"] as? String, let date = clock.date(from: stamp) else { continue }
                                samples[index] = Sample(day: ClaudeCodeUsageScanner.localDay(date), tokens: count, timestamp: date)
                            }
                            if reader.offset == before { break }
                        }
                        if !Task.isCancelled { cache[file] = Cached(modified: modified, size: size, samples: samples) }
                    }
                    if let samples = cache[file]?.samples {
                        conversations[uuid.uuidString, default: [:]].merge(samples) { _, latest in latest }
                    }
                }
            }
        }
        cache = cache.filter { seen.contains($0.key) }
        for steps in conversations.values {
            for sample in steps.values {
                days[sample.day, default: 0] += sample.tokens
                latest = max(latest ?? sample.timestamp, sample.timestamp)
            }
        }
        return .init(days: days.keys.sorted().map { .init(date: $0, tokens: days[$0]!, modelPriced: true) }, updatedAt: latest)
    }
}

/// Read only the account label and quota windows from the installed provider's public JSON output.
struct AntigravityAccount: Equatable, Sendable {
    struct Window: Equatable, Sendable {
        let title: String
        let remaining: Int
        let resetsAt: Date?
    }
    var displayPlan: String? {
        guard let plan else { return nil }
        var words = plan.split(whereSeparator: \.isWhitespace)[...]
        if words.first?.lowercased() == "antigravity" { words = words.dropFirst() }
        if words.last?.lowercased() == "quota" { words = words.dropLast() }
        return words.isEmpty ? plan : words.joined(separator: " ")
    }

    let plan: String?
    let windows: [Window]
    let updatedAt: Date

    static func read() -> Self? {
        let helper = "/Applications/CodexBar.app/Contents/Helpers/CodexBarCLI"
        guard FileManager.default.isExecutableFile(atPath: helper),
              let data = BoundedStatusLineCommand.run(command: helper + " usage --provider antigravity --json --no-color",
                                                     input: Data(), timeoutSeconds: 10) else { return nil }
        return decode(data)
    }

    static func decode(_ data: Data) -> Self? {
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              rows.count == 1, rows[0]["provider"] as? String == "antigravity",
              let usage = rows[0]["usage"] as? [String: Any] else { return nil }
        let clock = ISO8601DateFormatter()
        func date(_ key: Any?) -> Date? {
            guard let raw = key as? String else { return nil }
            return clock.date(from: raw) ?? (try? Date(raw, strategy: .iso8601.time(includingFractionalSeconds: true)))
        }
        func window(_ value: Any?, title: String) -> Window? {
            guard let row = value as? [String: Any], let used = row["usedPercent"] as? Double,
                  used.isFinite, (0...100).contains(used) else { return nil }
            return .init(title: title, remaining: Int((100 - used).rounded()), resetsAt: date(row["resetsAt"]))
        }
        let extra = usage["extraRateWindows"] as? [[String: Any]] ?? []
        var windows = extra.compactMap { row -> Window? in
            guard let title = row["title"] as? String, !title.isEmpty else { return nil }
            return window(row["window"], title: title)
        }
        if windows.isEmpty {
            windows = ["primary", "secondary", "tertiary"].compactMap { window(usage[$0], title: "Antigravity") }
        }
        func groupOrder(_ window: Window) -> Int {
            let title = window.title.lowercased()
            if title.hasPrefix("gemini") { return 0 }
            if title.hasPrefix("claude") || title.hasPrefix("gpt") { return 1 }
            return 2
        }
        windows.sort { groupOrder($0) < groupOrder($1) }
        let plan = (usage["loginMethod"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard plan?.isEmpty == false || !windows.isEmpty, let stamp = date(usage["updatedAt"]) else { return nil }
        return .init(plan: plan?.isEmpty == false ? plan : nil, windows: windows, updatedAt: stamp)
    }
}
