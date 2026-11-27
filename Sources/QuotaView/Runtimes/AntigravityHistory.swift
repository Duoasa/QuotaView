import AppKit
import OSLog
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

    struct Focus: Equatable, Sendable {
        let step: Int
        let call: Int
        let title: String
    }

    struct ProgressBatch: Sendable {
        var focuses: [Focus] = []
        var plan: CodexActivityPlanProgress?
        var planChanged = false
    }

    // Follow complete records in this turn and keep the cursor between polls.
    struct ProgressReader: Sendable {
        private var tail: ClaudeCodeTranscriptTail?
        private var lastPlanPosition = (-1, -1)

        mutating func read(root: URL, session: String, client: String?, first: Int?, start: Date) -> ProgressBatch {
            var result = ProgressBatch()
            guard let logs = AntigravityHistory.logs(root: root, session: session, client: client) else { return result }
            let file = logs.appendingPathComponent("transcript_full.jsonl")
            guard AntigravityHistory.safe(file) else { return result }
            if tail?.path != file.path {
                guard let size = ClaudeCodeTranscriptTail.fileSize(file.path) else { return result }
                tail = .init(path: file.path, offset: size > 4_194_304 ? size - 4_194_304 : 0)
            }
            let lines = tail?.readLines() ?? []
            guard !lines.isEmpty else { return result }
            let clock = ISO8601DateFormatter()
            for line in lines {
                guard let row = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      row["type"] as? String == "PLANNER_RESPONSE", row["status"] as? String == "DONE",
                      let step = row["step_index"] as? Int, step >= (first ?? 0),
                      let stamp = row["created_at"] as? String, let date = clock.date(from: stamp),
                      date.timeIntervalSince1970 >= floor(start.timeIntervalSince1970) - (first == nil ? 0 : 1),
                      date <= Date(), let calls = row["tool_calls"] as? [[String: Any]] else { continue }
                for (index, call) in calls.enumerated() {
                    if call["name"] as? String == "update_steps", (step, index) >= lastPlanPosition,
                       let args = call["args"] as? [String: Any], let steps = args["steps"] as? [[String: Any]],
                       steps.count <= CodexActivityPlanProgress.maximumStepCount {
                        let statuses = steps.compactMap { $0["status"] as? String }
                        guard statuses.count == steps.count else { continue }
                        let plan = CodexActivityPlanProgress(statuses: statuses, completedStatus: "done")
                        guard steps.isEmpty || plan != nil else { continue }
                        result.plan = plan
                        result.planChanged = true
                        lastPlanPosition = (step, index)
                        continue
                    }
                    guard call["name"] as? String == "update_focus" else { continue }
                    guard let args = call["args"] as? [String: Any], let raw = args["focus"] as? String else { continue }
                    let title = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
                    if !title.isEmpty { result.focuses.append(.init(step: step, call: index, title: String(title.prefix(256)))) }
                }
            }
            result.focuses.sort { ($0.step, $0.call) < ($1.step, $1.call) }
            return result
        }
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
    var didCheckAccount = false
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

enum AntigravityCLI {
    static func executable(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                           path: String = ProcessInfo.processInfo.environment["PATH"] ?? "",
                           systemBins: [String] = ["/opt/homebrew/bin", "/usr/local/bin"],
                           systemApplications: URL = URL(fileURLWithPath: "/Applications")) -> URL? {
        let directories = [home.appendingPathComponent(".local/bin").path] + systemBins
            + path.split(separator: ":").filter { $0.hasPrefix("/") }.map(String.init)
        let bundled = [systemApplications, home.appendingPathComponent("Applications")]
            .map { $0.appendingPathComponent("Gemini.app/Contents/Helpers/agy") }
        let candidates = directories.map { URL(fileURLWithPath: $0).appendingPathComponent("agy") } + bundled
        return candidates.first { url in
            FileManager.default.isExecutableFile(atPath: url.path)
                && (try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
    }

    static func install() -> Bool {
        if executable() != nil { return true }
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        } catch { return false }
        defer { try? manager.removeItem(at: directory) }
        let script = directory.appendingPathComponent("install.sh").path
        guard BoundedStatusLineCommand.execute("/usr/bin/curl", arguments: [
            "--disable", "--fail", "--silent", "--show-error", "--location", "--proto", "=https",
            "--proto-redir", "=https", "--output", script, "https://antigravity.google/cli/install.sh"
        ], timeoutSeconds: 45) != nil else { return false }
        let target = manager.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin")
        return BoundedStatusLineCommand.execute("/bin/bash", arguments: [script, "--dir", target.path],
                                                timeoutSeconds: 600, maximumOutputBytes: 1_048_576) != nil
            && executable() != nil
    }

    static func read() -> AntigravityAccount? {
        guard let executable = executable() else { return nil }
        return read(executable: executable)
    }

    static func read(executable: URL) -> AntigravityAccount? {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        } catch { return nil }
        defer { try? manager.removeItem(at: directory) }
        // agy uses either BROWSER or PATH to launch its OAuth UI. These overrides
        // belong only to the passive probe and its descendants.
        for name in ["open", "xdg-open"] {
            do { try manager.createSymbolicLink(atPath: directory.appendingPathComponent(name).path,
                                                withDestinationPath: "/usr/bin/false") } catch { return nil }
        }
        let environment = ["BROWSER": directory.appendingPathComponent("open").path,
                           "PATH": directory.path + ":" + (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"),
                           "AGY_CLI_DISABLE_AUTO_UPDATE": "true"]
        guard let version = BoundedStatusLineCommand.execute(executable.path, arguments: ["--version"],
                timeoutSeconds: 3, environmentOverrides: environment, directory: directory),
              let number = String(decoding: version, as: UTF8.self).range(of: #"\b[0-9]+\.[0-9]+\.[0-9]+\b"#, options: .regularExpression),
              String(decoding: version, as: UTF8.self)[number].compare("1.1.11", options: .numeric) != .orderedAscending,
              let data = BoundedStatusLineCommand.execute(executable.path, arguments: ["-p", "/usage", "--output-format", "json"],
                timeoutSeconds: 30, environmentOverrides: environment, directory: directory) else { return nil }
        return decode(data)
    }

    static func decode(_ data: Data) -> AntigravityAccount? {
        guard let report = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              report["status"] as? String == "SUCCESS", let command = report["command"] as? [String: Any],
              command["name"] as? String == "usage", let summary = command["data"] as? [String: Any],
              let groups = summary["groups"] as? [[String: Any]] else { return nil }
        var windows: [AntigravityAccount.Window] = []
        let clock = ISO8601DateFormatter()
        for group in groups {
            guard let name = group["name"] as? String, !name.isEmpty,
                  let buckets = group["buckets"] as? [[String: Any]] else { continue }
            let family = switch name {
            case "Gemini Models": "Gemini"
            case "Claude and GPT models": "Claude/GPT"
            default: name
            }
            for bucket in buckets {
                guard bucket["disabled"] as? Bool != true, let fraction = bucket["remaining_fraction"] as? NSNumber,
                      CFGetTypeID(fraction) != CFBooleanGetTypeID(), (0...1).contains(fraction.doubleValue),
                      let period = bucket["window"] as? String, !period.isEmpty else { continue }
                let reset = (bucket["reset_time"] as? String).flatMap {
                    clock.date(from: $0) ?? (try? Date($0, strategy: .iso8601.time(includingFractionalSeconds: true)))
                }
                let title = family + " " + (period == "5h" ? "5-hour" : period)
                windows.append(.init(title: title, remaining: Int((fraction.doubleValue * 100).rounded()), resetsAt: reset))
            }
        }
        guard !windows.isEmpty else { return nil }
        return .init(plan: summary["plan"] as? String, windows: windows, updatedAt: Date())
    }
}

/// Measured quota windows and subscription metadata for the active account.
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

    static func read(manual: Bool = false, cli: () -> Self? = AntigravityCLI.read,
                     desktop: (Bool) -> Self? = AntigravityDesktopQuota.read) -> Self? {
        if let account = cli() {
            Logger(subsystem: "com.quotaview", category: "AntigravityQuota").info("Read agy quota windows: \(account.windows.count, privacy: .public)")
            return account
        }

        if let desktop = desktop(manual) {
            Logger(subsystem: "com.quotaview", category: "AntigravityQuota").info("Read desktop quota windows: \(desktop.windows.count, privacy: .public)")
            return desktop
        }
        return nil
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
            guard let row = value as? [String: Any], row["usageKnown"] as? Bool != false,
                  let used = row["usedPercent"] as? Double,
                  used.isFinite, (0...100).contains(used) else { return nil }
            return .init(title: title, remaining: Int((100 - used).rounded()), resetsAt: date(row["resetsAt"]))
        }
        guard let stamp = date(usage["updatedAt"]) else { return nil }
        let plan = (usage["loginMethod"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = rows[0]["source"] as? String
        if source?.lowercased() == "offline" || plan?.lowercased() == "offline" {
            return .init(plan: nil, windows: [], updatedAt: stamp)
        }
        let extra = usage["extraRateWindows"] as? [[String: Any]] ?? []
        var windows = extra.compactMap { row -> Window? in
            guard row["usageKnown"] as? Bool != false, row["id"] as? String != "antigravity-offline-conversations",
                  let title = row["title"] as? String, !title.isEmpty else { return nil }
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
        guard plan?.isEmpty == false || !windows.isEmpty || !extra.isEmpty else { return nil }
        return .init(plan: plan?.isEmpty == false ? plan : nil, windows: windows, updatedAt: stamp)
    }
}

/// Read the model settings in the official desktop app using macOS Accessibility.
enum AntigravityDesktopQuota {
    struct PageItem {
        let heading: Bool
        let text: String
    }

    static func parse(_ items: [PageItem], at now: Date) -> AntigravityAccount? {
        var family: String?
        var cadence: String?
        var reset: Date?
        var plan: String?
        var nextIsPlan = false
        var windows: [AntigravityAccount.Window] = []
        for item in items {
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if item.heading {
                switch text.lowercased() {
                case "gemini models", "gemini 模型": family = "Gemini"
                case "claude and gpt models", "claude 和 gpt 模型": family = "Claude/GPT"
                default: family = text.range(of: #"^Gemini [0-9]"#, options: .regularExpression) == nil ? nil : text
                }
                cadence = nil; nextIsPlan = false
                continue
            }
            if nextIsPlan {
                if !text.isEmpty, text.count <= 64 { plan = text }
                nextIsPlan = false
            }
            if ["Your Plan:", "你的套餐：", "您的套餐："].contains(text) { nextIsPlan = true; continue }
            guard let family else { continue }
            if family.hasPrefix("Gemini "), text == family + " Weekly Limit" {
                cadence = "weekly"; reset = nil
                continue
            }
            switch text.lowercased() {
            case "weekly limit remaining", "每周剩余额度": cadence = "weekly"; reset = nil
            case "five hour limit remaining", "5 小时剩余额度": cadence = "5-hour"; reset = nil
            default:
                guard let period = cadence else { continue }
                if text.hasPrefix("You have used "), let range = text.range(of: "fully refresh in ") {
                    let duration = String(text[range.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: "."))
                    let units = ["day": 86400, "hour": 3600, "minute": 60, "second": 1]
                    var seconds = 0
                    for part in duration.components(separatedBy: ",") {
                        let words = part.split(separator: " ")
                        guard words.count == 2, let n = Int(words[0]), (0...366).contains(n),
                              let unit = units[String(words[1].hasSuffix("s") ? words[1].dropLast() : words[1])] else { seconds = 0; break }
                        seconds += n * unit
                    }
                    if seconds > 0 { reset = now.addingTimeInterval(Double(seconds)) }
                } else {
                    if text.hasSuffix("%"), let value = Int(text.dropLast()), (0...100).contains(value) {
                        let title = family + " " + period
                        guard !windows.contains(where: { $0.title == title }) else { return nil }
                        windows.append(.init(title: title, remaining: value, resetsAt: reset))
                    }
                    cadence = nil
                }
            }
        }
        guard !windows.isEmpty else { return nil }
        return .init(plan: plan, windows: windows, updatedAt: now)
    }

    private static func value(_ node: AXUIElement, _ key: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(node, key as CFString, &result) == .success else { return nil }
        return result
    }

    private static func children(_ node: AXUIElement) -> [AXUIElement] {
        value(node, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    private static func label(_ node: AXUIElement) -> String {
        for key in [kAXTitleAttribute, kAXDescriptionAttribute] {
            if let s = value(node, key) as? String, !s.isEmpty { return s }
        }
        return ""
    }

    /// Search control names only. Skip conversation messages, editor content and text fields.
    private static func find(_ root: AXUIElement, role: String, names: [String]) -> AXUIElement? {
        var stack = [root]
        let deadline = ProcessInfo.processInfo.systemUptime + 1
        for _ in 0..<1600 {
            guard let node = stack.popLast(), ProcessInfo.processInfo.systemUptime < deadline else { break }
            let kind = value(node, kAXRoleAttribute) as? String
            if kind == role, names.contains(label(node)) { return node }
            if ["AXStaticText", "AXTextArea", "AXTextField", "AXLink", "AXButton", "AXImage"].contains(kind ?? "") { continue }
            stack.append(contentsOf: children(node).reversed())
        }
        return nil
    }

    private static func settings(_ window: AXUIElement) -> AXUIElement? {
        find(window, role: "AXGroup", names: ["Settings", "设置"])
    }
    private static func button(_ root: AXUIElement, _ names: [String]) -> AXUIElement? {
        find(root, role: kAXButtonRole, names: names)
    }
    private static func press(_ button: AXUIElement) -> Bool {
        AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
    }
    private static func page(_ settings: AXUIElement) -> AXUIElement? {
        guard let heading = find(settings, role: "AXHeading", names: [
            "Models & Usage Refresh quota and credits data", "Models & Usage", "模型与用量", "模型与用量 刷新额度和点数数据"
        ]), let parent = value(heading, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { return nil }
        return (parent as! AXUIElement)
    }
    private static func readPage(_ page: AXUIElement) -> AntigravityAccount? {
        var items: [PageItem] = []
        var stack = Array(children(page).reversed())
        let deadline = ProcessInfo.processInfo.systemUptime + 1
        for _ in 0..<500 {
            guard let node = stack.popLast() else { return parse(items, at: Date()) }
            guard ProcessInfo.processInfo.systemUptime < deadline else { return nil }
            switch value(node, kAXRoleAttribute) as? String {
            case "AXHeading": items.append(.init(heading: true, text: label(node)))
            case "AXStaticText":
                if let s = value(node, kAXValueAttribute) as? String { items.append(.init(heading: false, text: s)) }
            case "AXGroup": stack.append(contentsOf: children(node).reversed())
            default: break
            }
        }
        return nil
    }

    private static func refreshedAccount(in sheet: AXUIElement, page models: AXUIElement) -> AntigravityAccount? {
        let labels = ["Refresh quota and credits data", "刷新额度和点数数据"]
        guard let refresh = button(models, labels) else { return nil }
        if (value(refresh, kAXEnabledAttribute) as? Bool) == true, !press(refresh) { return nil }
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        repeat {
            Thread.sleep(forTimeInterval: 0.15)
            guard !Task.isCancelled, let current = page(sheet) else { return nil }
            if let control = button(current, labels), (value(control, kAXEnabledAttribute) as? Bool) == true,
               let result = readPage(current) { return result }
        } while ProcessInfo.processInfo.systemUptime < deadline
        return nil
    }

    static func read(manual: Bool = false) -> AntigravityAccount? {
        guard AXIsProcessTrusted() else { return nil }
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.antigravity")
        guard apps.count == 1, let app = apps.first else { return nil }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.15)
        AXUIElementSetAttributeValue(root, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        let windows = value(root, kAXWindowsAttribute) as? [AXUIElement] ?? []
        for window in windows {
            if let sheet = settings(window), let models = page(sheet), let account = refreshedAccount(in: sheet, page: models) { return account }
        }
        // When the user is working in the desktop app, never switch its page on a timer.
        guard manual || !app.isActive else { return nil }
        for window in windows {
            let minimized = (value(window, kAXMinimizedAttribute) as? Bool) == true
            var open = button(window, ["Settings", "设置"])
            // Some desktop versions retain their accessible controls while
            // minimized. Only an explicit refresh may restore a dormant window.
            let restoreWindow = minimized && manual && open == nil
            if restoreWindow {
                guard AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse) == .success else { continue }
                Thread.sleep(forTimeInterval: 0.35)
                open = button(window, ["Settings", "设置"])
            }
            defer {
                if restoreWindow { AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue) }
            }
            if let sheet = settings(window) {
                if let models = page(sheet) { return refreshedAccount(in: sheet, page: models) }
                continue
            }
            guard let open, press(open) else { continue }
            var ownedSheet: AXUIElement?
            defer {
                if let ownedSheet, let current = settings(window), CFEqual(ownedSheet, current),
                   let close = button(current, ["Close", "关闭"]) { _ = press(close) }
            }
            var selected = false
            let deadline = ProcessInfo.processInfo.systemUptime + 4
            repeat {
                guard !Task.isCancelled else { return nil }
                if let sheet = settings(window) {
                    ownedSheet = sheet
                    if let models = page(sheet) {
                        return refreshedAccount(in: sheet, page: models)
                    } else if !selected, let models = button(sheet, ["Models", "模型"]) {
                        selected = press(models)
                    }
                }
                Thread.sleep(forTimeInterval: 0.12)
            } while ProcessInfo.processInfo.systemUptime < deadline
            return nil
        }
        return nil
    }
}
