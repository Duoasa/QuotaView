import Foundation
import SQLite3

/// Classification describes the execution unit, not its current activity.
public enum CodexActivitySessionKind: String, Codable, Sendable {
    case user, memoryConsolidation, subagent, internalTask, unknown

    /// Background memory remains observable without granting user conversation capabilities.
    public var supportsActivityPresentation: Bool { self == .user || self == .memoryConsolidation || self == .subagent }

    /// Explicit background/internal identity takes precedence over sparse host fallbacks.
    /// Exact memory identity can refine a previously generic internal classification.
    public static func resolving(_ kinds: Self...) -> Self {
        if kinds.contains(.memoryConsolidation) { return .memoryConsolidation }
        if kinds.contains(.internalTask) { return .internalTask }
        if kinds.contains(.subagent) { return .subagent }
        if kinds.contains(.user) { return .user }
        return .unknown
    }

    public static func classify(source: Any?, threadSource: String? = nil) -> Self {
        let sourceKind: Self
        if let object = source as? [String: Any] {
            let tags = ["internal", "subagent", "subAgent"].filter { object.keys.contains($0) }
            if tags.count == 1, let tag = tags.first {
                if object[tag] as? String == "memory_consolidation" { sourceKind = .memoryConsolidation }
                else if tag != "internal", CodexActivitySubagentIdentity.threadSpawn(source: object) != nil { sourceKind = .subagent }
                else { sourceKind = .internalTask }
            } else {
                sourceKind = tags.isEmpty ? .unknown : .internalTask
            }
        } else if let text = source as? String {
            if let data = text.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data), object is [String: Any] {
                sourceKind = classify(source: object)
            } else if text.lowercased().contains("subagent") {
                sourceKind = .internalTask
            } else if ["cli", "exec", "vscode", "appServer", "app-server"].contains(text) {
                sourceKind = .user
            } else { sourceKind = .unknown }
        } else { sourceKind = .unknown }
        let threadKind: Self
        switch threadSource {
        case "memory_consolidation": threadKind = .memoryConsolidation
        case "user", "agent_created_thread": threadKind = .user
        case "subagent":
            // This persisted generic tag is refined only by the exact native
            // subtype. Alone it grants neither user nor child presentation.
            threadKind = sourceKind == .subagent || sourceKind == .memoryConsolidation ? .unknown : .internalTask
        case .some(let text) where !text.isEmpty: threadKind = .internalTask
        default: threadKind = .unknown
        }
        if threadKind == .internalTask || sourceKind == .internalTask { return .internalTask }
        return resolving(threadKind, sourceKind)
    }

    public static func classify(metadata: [String: Any]) -> Self {
        let kind = classify(source: metadata["source"],
                            threadSource: metadata["threadSource"] as? String ?? metadata["thread_source"] as? String)
        guard kind != .memoryConsolidation else { return kind }
        let child = CodexActivitySubagentIdentity.decode(metadata)
        if kind == .internalTask {
            let threadSource = metadata["threadSource"] as? String ?? metadata["thread_source"] as? String
            return threadSource == "subagent" && child != nil ? .subagent : .internalTask
        }
        if kind == .subagent, child == nil { return .internalTask }
        return child == nil ? kind : .subagent
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
        var compactionItemHash: String?
        var compactionStartedAt: Date?
        var compactionEndedAt: Date?
    }
    private var tasks: [String: TaskState] = [:]
    private var order: [String] = []
    private var generation: UInt64 = 0
    public init() {}

    public func currentIdentity(for session: String) -> CodexActivityTaskIdentity? {
        guard let task = tasks[session], task.kind == .user, task.hasTurn else { return nil }
        return task.identity
    }

    public func backgroundIdentity(for session: String) -> CodexActivityTaskIdentity? {
        guard let task = tasks[session], task.kind == .memoryConsolidation, task.hasTurn else { return nil }
        return task.identity
    }

    public func subagentIdentity(for session: String) -> CodexActivityTaskIdentity? {
        guard let task = tasks[session], task.kind == .subagent, task.hasTurn else { return nil }
        return task.identity
    }

    /// Bounded admission identities, newest first, for targeted metadata reads.
    /// Includes terminal executions so late identity can correct a retained card.
    public var executionIdentities: [CodexActivityTaskIdentity] {
        order.reversed().compactMap { executionIdentity(for: $0) }
    }

    /// Metadata can identify an admitted unknown execution without granting it
    /// the verified-user attachment rights of currentIdentity.
    public func executionIdentity(for session: String) -> CodexActivityTaskIdentity? {
        guard let task = tasks[session], task.kind != .internalTask, task.hasTurn else { return nil }
        return task.identity
    }

    /// Late metadata changes presentation only, preserving turn, clock and terminal evidence.
    @discardableResult
    public mutating func reclassify(session: String, kind: CodexActivitySessionKind) -> CodexActivityTaskIdentity? {
        guard var task = tasks[session] else { return nil }
        if kind == .internalTask { task.kind = .internalTask }
        else if kind == .subagent, task.kind != .memoryConsolidation { task.kind = .subagent }
        else { task.kind = .resolving(task.kind, kind) }
        tasks[session] = task
        return task.identity
    }

    /// A native turn trigger labels this execution only; a later execution must
    /// not inherit the old turn's background presentation.
    public mutating func reclassifyExecution(session: String, kind: CodexActivitySessionKind) {
        guard var task = tasks[session] else { return }
        task.kind = kind
        tasks[session] = task
    }

    public mutating func remove(session: String) {
        tasks.removeValue(forKey: session)
        order.removeAll { $0 == session }
    }

    /// Public data cannot establish or change a task. Lifecycle admission owns
    /// the identity; trace and request projections can only attach to it.
    public func permitsPublicAttachment(session: String, turn: String?, source: CodexActivityEventSource,
                                        occurredAt: Date, timeSensitive: Bool = false,
                                        permitsTerminal: Bool = false) -> Bool {
        guard let task = tasks[session], task.kind == .user, task.hasTurn,
              permitsTerminal || !task.terminal else { return false }
        if let turn, task.identity.turnHash != turn { return false }
        if turn == nil, task.identity.turnHash == nil { return false }
        let authority = source == .localRollout ? 3 : source == .appServer ? 2 : 1
        if timeSensitive, let latest = task.lastEventAt[authority], occurredAt < latest { return false }
        return true
    }

    /// Child progress is read-only and must attach to its admitted exact turn.
    /// This never grants the user request capabilities of permitsPublicAttachment.
    public func permitsSubagentAttachment(session: String, turn: String?, source: CodexActivityEventSource,
                                         occurredAt: Date, timeSensitive: Bool = false,
                                         permitsTerminal: Bool = false) -> Bool {
        guard let task = tasks[session], task.kind == .subagent, task.hasTurn,
              permitsTerminal || !task.terminal, let turn, task.identity.turnHash == turn else { return false }
        let authority = source == .localRollout ? 3 : source == .appServer ? 2 : 1
        if timeSensitive, let latest = task.lastEventAt[authority], occurredAt < latest { return false }
        return true
    }

    public func isPriorTurn(session: String, turn: String) -> Bool {
        tasks[session]?.previousTurns.contains(turn) == true
    }

    public mutating func admit(_ event: CodexActivityEvent, kind: CodexActivitySessionKind,
                               selectedSession: String?, selectedOccurredAt: Date? = nil,
                               selectionEvidenceAt: Date? = nil, confirmedCurrentTurn: Bool = false) -> Admission? {
        guard kind != .internalTask else { return nil }
        let session = event.sessionHash
        let authority = event.source == .localRollout ? 3 : event.source == .appServer ? 2 : 1
        let isStart = event.event == .userPromptSubmit
        let isTerminal = [.stop, .interrupt, .sessionEnd].contains(event.event)
        let positive = isStart || [.preToolUse, .permissionRequest, .preCompact, .subagentStart].contains(event.event)
        var existing = tasks[session]
        // A withdrawn child needs new positive observation; output/settlement
        // alone cannot recreate a running child after the bounded slot expires.
        if kind == .subagent, existing == nil, !positive { return nil }
        // An end-only event cannot establish a currently active turn.
        if event.event == .postCompact, existing?.hasTurn != true { return nil }
        if let old = existing {
            if let latest = old.lastEventAt[authority], event.occurredAt < latest,
               !(confirmedCurrentTurn && isStart && event.turnHash != old.identity.turnHash) { return nil }
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
                    && (authority >= old.authority || confirmedCurrentTurn)
                guard newLegacyPrompt || newIdentifiedTurn else { return nil }
            } else if let incoming = event.turnHash, let current = old.identity.turnHash, incoming != current {
                // Receipt time cannot prove a new turn across transports.
                // Only the native service's explicit current-turn snapshot can
                // supersede stronger durable context without a local new start.
                guard isStart, authority >= old.authority || confirmedCurrentTurn else { return nil }
            } else if isStart, event.turnHash == nil, old.identity.turnHash != nil {
                return nil
            }
        } else if isTerminal {
            return nil
        }
        // Unknown legacy streams may update their own state but cannot select
        // over a verified user task. Arrival ordering is never terminal authority.
        let selectedKind = selectedSession.flatMap { tasks[$0]?.kind }
        // A recovered context keeps its original timestamp; fresh confirmation supplies
        // selection evidence separately, without fabricating another start event.
        let isRecentEnough = selectedOccurredAt.map { (selectionEvidenceAt ?? event.occurredAt) >= $0 } ?? true
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
        // Native lifecycle and durable rollout can report the same compaction.
        // In particular, an end-only rollout must not be followed by a delayed
        // native start that leaves the island stuck in compaction.
        if event.event == .preCompact {
            if let latest = task.lastEventAt.values.max(), event.occurredAt < latest { return nil }
            if let endedAt = task.compactionEndedAt, event.occurredAt <= endedAt { return nil }
            if let item = event.compactionItemHash, item == task.compactionItemHash { return nil }
            task.compactionItemHash = event.compactionItemHash
            task.compactionStartedAt = event.occurredAt
            task.compactionEndedAt = nil
        } else if event.event == .postCompact {
            if let startedAt = task.compactionStartedAt, event.occurredAt < startedAt { return nil }
            if task.compactionStartedAt != nil, task.compactionEndedAt == nil,
               let current = task.compactionItemHash, let incoming = event.compactionItemHash,
               current != incoming { return nil }
            if let endedAt = task.compactionEndedAt,
               event.occurredAt <= endedAt || (event.compactionItemHash != nil
                    && event.compactionItemHash == task.compactionItemHash) { return nil }
            task.compactionItemHash = event.compactionItemHash
            task.compactionEndedAt = event.occurredAt
        } else if [.preToolUse, .postToolUse, .permissionRequest, .subagentStart].contains(event.event),
                  let startedAt = task.compactionStartedAt, task.compactionEndedAt == nil,
                  event.occurredAt >= startedAt {
            // A real continuation can recover from a missing PostCompact.
            task.compactionEndedAt = event.occurredAt
        }
        // Bind native identity to a legacy leading event without losing turn state.
        if task.identity.turnHash == nil, let turn = event.turnHash {
            task.identity = .init(sessionHash: session, turnHash: turn, generation: task.identity.generation)
        }
        task.kind = .resolving(task.kind, kind)
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
                         selectsTask: task.kind != .memoryConsolidation && task.kind != .subagent
                            && (session == selectedSession || (canSelect && (positive || selectedSession == nil))),
                         evictedSessions: evicted)
    }
}

/// Metadata I/O is serialized off the main actor. Unknown results expire quickly
/// because hooks may arrive before the host commits a new thread to SQLite.
public actor CodexActivitySessionClassifier {
    private var cache: [String: (CodexActivitySessionKind, Date)] = [:]
    private var executionIdentities: [CodexLocalExecutionMetadata.Identity] = []
    private var executionCheckedAtByExecution: [CodexLocalExecutionMetadata.Execution: TimeInterval] = [:]
    private let codexHome: URL?
    private let executionMetadataService: CodexLocalExecutionMetadata.Service
    public init(codexHome: URL? = nil, executionMetadataService: CodexLocalExecutionMetadata.Service? = nil) {
        self.codexHome = codexHome
        let root = codexHome ?? ProcessInfo.processInfo.environment["CODEX_HOME"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        } ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        self.executionMetadataService = executionMetadataService ?? .init(codexHome: root)
    }
    public func kind(for event: CodexActivityEvent) async -> CodexActivitySessionKind {
        (await classification(for: event)).kind
    }

    public func classification(for event: CodexActivityEvent) async -> CodexActivitySessionClassification {
        let now = Date()
        if event.source != .hook, let kind = event.sessionKind, kind != .unknown {
            return await classification(remember(kind, for: event.sessionHash, at: now), event: event, at: now)
        }
        // Hook cannot assert its own execution kind. It may inherit validated
        // native/rollout metadata for the same hashed thread or read SQLite.
        if let (kind, date) = cache[event.sessionHash],
           now.timeIntervalSince(date) < (kind == .unknown || kind == .user ? 1 : 60) {
            return await classification(kind, event: event, at: now)
        }
        let kind = CodexActivitySessionKind.localKind(sessionHash: event.sessionHash, codexHome: codexHome)
        return await classification(remember(kind, for: event.sessionHash, at: now), event: event, at: now)
    }

    private func classification(_ kind: CodexActivitySessionKind, event: CodexActivityEvent,
                                at now: Date) async -> CodexActivitySessionClassification {
        // Origin and execution trigger are independent. An exact native start
        // can label this turn even when sparse thread metadata says user.
        guard kind == .unknown || kind == .user || kind == .subagent,
              let turn = event.turnHash else { return .init(kind: kind) }
        let execution = CodexLocalExecutionMetadata.Execution(sessionHash: event.sessionHash, turnHash: turn)
        let uptime = ProcessInfo.processInfo.systemUptime
        if uptime - (executionCheckedAtByExecution[execution] ?? -.infinity) >= 1 {
            let result = await executionMetadataService.read(preferred: [execution], now: now)
            executionIdentities.removeAll { result.resolvedSessions.contains($0.sessionHash) }
            executionIdentities.append(contentsOf: result.identities)
            if executionIdentities.count > 128 { executionIdentities.removeFirst(executionIdentities.count - 128) }
            executionCheckedAtByExecution[execution] = uptime
            while executionCheckedAtByExecution.count > 128,
                  let oldest = executionCheckedAtByExecution.min(by: { $0.value < $1.value })?.key {
                executionCheckedAtByExecution.removeValue(forKey: oldest)
            }
        }
        // A stronger identity can arrive while the service is awaited.
        if let current = cache[event.sessionHash]?.0,
           current == .internalTask || current == .memoryConsolidation {
            return .init(kind: current)
        }
        guard executionIdentities.contains(where: {
            $0.sessionHash == event.sessionHash && $0.turnHash == turn
        }) else { return .init(kind: cache[event.sessionHash]?.0 ?? kind) }
        return .init(kind: .memoryConsolidation, executionTurnHash: turn)
    }

    private func remember(_ incoming: CodexActivitySessionKind, for session: String, at date: Date) -> CodexActivitySessionKind {
        let previous = cache[session]?.0 ?? .unknown
        let kind: CodexActivitySessionKind
        if incoming == .internalTask { kind = .internalTask }
        else if incoming == .subagent, previous != .memoryConsolidation { kind = .subagent }
        else { kind = .resolving(previous, incoming) }
        if cache.count >= 128, cache[session] == nil,
           let oldest = cache.min(by: { $0.value.1 < $1.value.1 })?.key {
            cache.removeValue(forKey: oldest)
        }
        cache[session] = (kind, date)
        return kind
    }
}

public struct CodexActivitySessionClassification: Sendable {
    public let kind: CodexActivitySessionKind
    public let executionTurnHash: String?
    public init(kind: CodexActivitySessionKind, executionTurnHash: String? = nil) {
        self.kind = kind; self.executionTurnHash = executionTurnHash
    }
}
