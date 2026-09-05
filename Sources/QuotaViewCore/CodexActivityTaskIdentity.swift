import Foundation
import SQLite3

/// Classification describes the execution unit, not its current activity.
public enum CodexActivitySessionKind: String, Codable, Sendable {
    case user, internalTask, unknown

    public static func classify(source: Any?, threadSource: String? = nil) -> Self {
        if let threadSource, !threadSource.isEmpty, threadSource != "user" {
            return .internalTask
        }
        if let object = source as? [String: Any] {
            return object["subagent"] != nil ? .internalTask : .unknown
        }
        if let text = source as? String {
            if let data = text.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) {
                let kind = classify(source: object)
                if kind != .unknown { return kind }
            }
            if text.lowercased().contains("subagent") { return .internalTask }
            if ["cli", "exec", "vscode", "appServer", "app-server"].contains(text) {
                return .user
            }
        }
        return threadSource == "user" ? .user : .unknown
    }

    /// Legacy hooks contain only a hash. Read local metadata without retaining IDs,
    /// prompts or paths. Callers cache conclusive results; missing metadata is not trust.
    public static func localKind(sessionHash: String, codexHome: URL? = nil) -> Self {
        let home = codexHome ?? ProcessInfo.processInfo.environment["CODEX_HOME"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        } ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        var db: OpaquePointer?
        guard sqlite3_open_v2(home.appendingPathComponent("state_5.sqlite").path,
                             &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              let db else {
            if let db { sqlite3_close(db) }
            return .unknown
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 20)
        var statement: OpaquePointer?
        let sql = "SELECT id, source, thread_source FROM threads ORDER BY updated_at_ms DESC LIMIT 1024"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { return .unknown }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = sqlite3_column_text(statement, 0),
                  CodexActivityPrivacy.hashIdentifier(String(cString: id)) == sessionHash else { continue }
            let source = sqlite3_column_text(statement, 1).map { String(cString: $0) }
            let threadSource = sqlite3_column_text(statement, 2).map { String(cString: $0) }
            return classify(source: source, threadSource: threadSource)
        }
        return .unknown
    }
}

public struct CodexActivityTaskIdentity: Equatable, Hashable, Sendable {
    public let sessionHash: String
    public let turnHash: String?
    /// Distinguishes legacy turns for which the host provides no turn ID.
    public let generation: UInt64

    public init(sessionHash: String, turnHash: String?, generation: UInt64 = 0) {
        self.sessionHash = sessionHash
        self.turnHash = turnHash
        self.generation = generation
    }
}

/// All transports pass through this registry before mutating domain or UI state.
/// Only positive activity may select a task; terminal events have no selection rights.
public struct CodexActivityTaskRegistry {
    public struct Admission {
        public let identity: CodexActivityTaskIdentity
        public let startsTurn: Bool
        public let duplicateStart: Bool
        public let selectsTask: Bool
        public let evictedSessions: [String]
    }
    private struct TaskState {
        var identity: CodexActivityTaskIdentity
        var kind: CodexActivitySessionKind
        var authority: Int
        var terminal = false
        var hasTurn = true
        var lastEventAt: [Int: Date] = [:]
        var previousTurns: [String] = []
    }
    private var tasks: [String: TaskState] = [:]
    private var order: [String] = []
    private var generation: UInt64 = 0
    public init() {}

    public mutating func admit(_ event: CodexActivityEvent, kind: CodexActivitySessionKind,
                               selectedSession: String?, selectedOccurredAt: Date? = nil) -> Admission? {
        guard kind != .internalTask else { return nil }
        let session = event.sessionHash
        let authority = event.source == .localRollout ? 3 : event.source == .appServer ? 2 : 1
        let isStart = event.event == .userPromptSubmit
        let isTerminal = [.stop, .interrupt, .sessionEnd].contains(event.event)
        let positive = isStart || [.preToolUse, .permissionRequest, .preCompact, .subagentStart].contains(event.event)
        var existing = tasks[session]
        if let old = existing {
            if let latest = old.lastEventAt[authority], event.occurredAt < latest { return nil }
            if event.event == .sessionStart, event.sessionStartSource != .compact { return nil }
            if let turn = event.turnHash, old.previousTurns.contains(turn) { return nil }
            if isTerminal {
                guard (!old.terminal || event.event == .sessionEnd),
                      event.event == .sessionEnd || old.identity.turnHash == event.turnHash,
                      event.event == .sessionEnd || authority >= old.authority
                else { return nil }
            } else if old.terminal {
                // Only explicit new-turn evidence can leave terminal state.
                let newLegacyPrompt = isStart && authority == 1
                    && old.identity.turnHash == nil && event.turnHash == nil
                let newIdentifiedTurn = positive && event.turnHash != nil
                    && event.turnHash != old.identity.turnHash
                guard newLegacyPrompt || newIdentifiedTurn else { return nil }
            } else if let incoming = event.turnHash, let current = old.identity.turnHash, incoming != current {
                guard isStart, authority >= old.authority else { return nil }
            } else if isStart, event.turnHash == nil, old.identity.turnHash != nil {
                return nil
            }
        } else if isTerminal {
            return nil
        }
        // Unknown legacy streams may update their own state but cannot select
        // over a verified user task. Arrival ordering is never terminal authority.
        let selectedKind = selectedSession.flatMap { tasks[$0]?.kind }
        let isRecentEnough = selectedOccurredAt.map { event.occurredAt >= $0 } ?? true
        let canSelect = (kind != .unknown || selectedKind != .user) && isRecentEnough
        let duplicate = isStart && event.turnHash != nil && (existing.map {
            $0.hasTurn && !$0.terminal && $0.identity.turnHash == event.turnHash
        } ?? false)
        let startsTurn = existing == nil || (isStart && !duplicate)
            || (existing?.terminal == true && positive)
        if startsTurn {
            generation &+= 1
            var previous = existing?.previousTurns ?? []
            if let old = existing?.identity.turnHash, old != event.turnHash { previous.append(old) }
            existing = TaskState(identity: .init(sessionHash: session, turnHash: event.turnHash,
                                                generation: generation),
                                 kind: kind, authority: authority,
                                 hasTurn: event.event != .sessionStart || event.sessionStartSource == .compact,
                                 previousTurns: Array(previous.suffix(16)))
        }
        guard var task = existing else { return nil }
        // Bind native identity to a legacy leading event without losing turn state.
        if task.identity.turnHash == nil, let turn = event.turnHash {
            task.identity = .init(sessionHash: session, turnHash: turn, generation: task.identity.generation)
        }
        if kind != .unknown { task.kind = kind }
        if positive && event.turnHash != nil { task.authority = max(task.authority, authority) }
        if isTerminal { task.terminal = true }
        task.lastEventAt[authority] = event.occurredAt
        tasks[session] = task
        order.removeAll { $0 == session }
        order.append(session)
        var evicted: [String] = []
        while tasks.count > 128, let oldest = order.first(where: { $0 != selectedSession && $0 != session }) {
            tasks.removeValue(forKey: oldest)
            order.removeAll { $0 == oldest }
            evicted.append(oldest)
        }
        return Admission(identity: task.identity, startsTurn: startsTurn,
                         duplicateStart: duplicate,
                         selectsTask: session == selectedSession || (canSelect && (positive || selectedSession == nil)),
                         evictedSessions: evicted)
    }
}

/// Metadata I/O is serialized off the main actor. Unknown results expire quickly
/// because hooks may arrive before the host commits a new thread to SQLite.
public actor CodexActivitySessionClassifier {
    private var cache: [String: (CodexActivitySessionKind, Date)] = [:]
    private let codexHome: URL?
    public init(codexHome: URL? = nil) { self.codexHome = codexHome }
    public func kind(for event: CodexActivityEvent) -> CodexActivitySessionKind {
        if event.source != .hook, let kind = event.sessionKind, kind != .unknown { return kind }
        if let (kind, date) = cache[event.sessionHash], Date().timeIntervalSince(date) < (kind == .unknown ? 1 : 60) {
            return kind
        }
        let kind = CodexActivitySessionKind.localKind(sessionHash: event.sessionHash, codexHome: codexHome)
        if cache.count >= 128, let oldest = cache.min(by: { $0.value.1 < $1.value.1 })?.key {
            cache.removeValue(forKey: oldest)
        }
        cache[event.sessionHash] = (kind, Date())
        return kind
    }
}
