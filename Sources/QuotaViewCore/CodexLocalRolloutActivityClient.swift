import Foundation
import Darwin
#if canImport(QuotaViewActivityHookSupport)
import QuotaViewActivityHookSupport
#endif

public enum CodexLocalRolloutDecodedUpdate: Equatable, Sendable {
    case activity(CodexActivityEvent)
    case tokenUsage(CodexActivityTokenUsageUpdate)
    case tokenUsageReplay([CodexActivityTokenUsageUpdate])
    /// A verified identity update, without inventing another lifecycle event.
    case sessionMetadata
}

/// Bounded display fields read from the verified thread row. These are not
/// evidence of an active turn and never convey a request/response capability.
public struct CodexLocalRolloutThreadMetadata: Equatable, Sendable {
    public let title: String?
    public let titleIsExplicitName: Bool
    public let model: String?
    public let reasoningEffort: String?
    public let cumulativeTotalTokens: Int64?
    public init(title: String? = nil, titleIsExplicitName: Bool = false,
                model: String? = nil, reasoningEffort: String? = nil,
                cumulativeTotalTokens: Int64? = nil) {
        func bounded(_ value: String?, _ limit: Int) -> String? {
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && trimmed.utf8.count <= limit ? trimmed : nil
        }
        self.title = bounded(title, 512)
        self.titleIsExplicitName = self.title != nil && titleIsExplicitName
        self.model = bounded(model, 256)
        self.reasoningEffort = bounded(reasoningEffort, 64)
        self.cumulativeTotalTokens = cumulativeTotalTokens.flatMap { $0 >= 0 ? $0 : nil }
    }
    var isEmpty: Bool { title == nil && model == nil && reasoningEffort == nil && cumulativeTotalTokens == nil }
}

/// Transient read-only discovery identity from validated session metadata.
/// It is never an RPC capability, never persisted, and contains no user content.
public struct CodexLocalRolloutThreadIdentity: Equatable, Sendable {
    public let threadID: String
    public let sessionHash: String
    public let sessionKind: CodexActivitySessionKind
    public let executionTurnHash: String?
    public let subagentIdentity: CodexActivitySubagentIdentity?
    public let threadMetadata: CodexLocalRolloutThreadMetadata?
    public init(threadID: String, sessionHash: String, sessionKind: CodexActivitySessionKind,
                executionTurnHash: String? = nil, subagentIdentity: CodexActivitySubagentIdentity? = nil,
                threadMetadata: CodexLocalRolloutThreadMetadata? = nil) {
        self.threadID = threadID; self.sessionHash = sessionHash; self.sessionKind = sessionKind
        self.executionTurnHash = executionTurnHash
        self.subagentIdentity = subagentIdentity
        self.threadMetadata = threadMetadata
    }
}

public struct CodexLocalRolloutDecodedRecord: Equatable, Sendable {
    public let eventID: String?
    public let update: CodexLocalRolloutDecodedUpdate
    /// Context recovered from disk is not proof that a task is currently running.
    public let requiresLiveConfirmation: Bool
    public let threadIdentity: CodexLocalRolloutThreadIdentity?

    public init(
        eventID: String?,
        update: CodexLocalRolloutDecodedUpdate,
        requiresLiveConfirmation: Bool = false,
        threadIdentity: CodexLocalRolloutThreadIdentity? = nil
    ) {
        self.eventID = eventID
        self.update = update
        self.requiresLiveConfirmation = requiresLiveConfirmation
        self.threadIdentity = threadIdentity
    }
}

public struct CodexLocalRolloutLineDecoder: Sendable {
    public static let maximumLineBytes = 1_048_576

    private let sessionHash: String
    private let workspaceName: String?
    private(set) var sessionKind: CodexActivitySessionKind
    private(set) var activeTurnHash: String?
    private var metadataRecoveryTurnHash: String?
    private(set) var isMetadataRecoveredTurn = false
    private var pendingQuestionCalls: [String] = []
    private var pendingAsyncQuestionCalls: [String] = []
    var asynchronousQuestionCallIDs: Set<String> { Set(pendingAsyncQuestionCalls) }

    public init(sessionHash: String, workspaceName: String? = nil, sessionKind: CodexActivitySessionKind = .unknown,
                metadataRecoveryTurnHash: String? = nil) {
        self.sessionHash = sessionHash
        self.workspaceName = workspaceName
        self.sessionKind = sessionKind
        self.metadataRecoveryTurnHash = metadataRecoveryTurnHash
    }

    mutating func restrictMetadataRecovery(to turnHash: String?) {
        metadataRecoveryTurnHash = turnHash
        if isMetadataRecoveredTurn, activeTurnHash != turnHash {
            activeTurnHash = nil
            isMetadataRecoveredTurn = false
            pendingQuestionCalls.removeAll(); pendingAsyncQuestionCalls.removeAll()
        }
    }

    mutating func refineSessionKind(_ kind: CodexActivitySessionKind) {
        if kind == .internalTask { sessionKind = .internalTask }
        else if kind == .subagent, sessionKind != .memoryConsolidation { sessionKind = .subagent }
        else { sessionKind = .resolving(sessionKind, kind) }
    }

    public mutating func decode(
        line: Data,
        now: Date = Date()
    ) -> CodexLocalRolloutDecodedRecord? {
        guard let envelope = CodexLocalRolloutEnvelope(line) else { return nil }
        return decode(envelope, now: now)
    }

    mutating func decode(_ decoded: CodexLocalRolloutEnvelope, now: Date = Date()) -> CodexLocalRolloutDecodedRecord? {
        let envelope = decoded.object, payload = decoded.payload, recordType = decoded.type

        if recordType == "session_meta" {
            guard Self.hashedIdentifier(payload["id"]) == sessionHash else { return nil }
            let kind = CodexActivitySessionKind.classify(metadata: payload)
            refineSessionKind(kind)
            return nil // Discovery owns metadata publication; no synthetic lifecycle event.
        }

        if recordType == "turn_context" {
            // Only an independently admitted live execution may bind a missing
            // start. Context alone must never manufacture a lifecycle event.
            if let thread = payload["thread_id"], Self.hashedIdentifier(thread) != sessionHash { return nil }
            let contextTurn = Self.hashedIdentifier(payload["turn_id"])
            if isMetadataRecoveredTurn, contextTurn != activeTurnHash {
                activeTurnHash = nil
                isMetadataRecoveredTurn = false
                pendingQuestionCalls.removeAll(); pendingAsyncQuestionCalls.removeAll()
            }
            if let contextTurn, contextTurn == metadataRecoveryTurnHash, contextTurn != activeTurnHash {
                activeTurnHash = contextTurn
                isMetadataRecoveredTurn = true
            }
            return nil
        }

        let occurredAt = decoded.timestamp ?? now
        let eventID = Self.eventID(
            sessionHash: sessionHash,
            ordinal: envelope["ordinal"],
            recordType: recordType,
            payloadType: payload["type"] as? String
        )

        if recordType == "token_usage_record" {
            guard let turnHash = activeTurnHash,
                  Self.hashedIdentifier(payload["turn_id"]) == turnHash,
                  Self.hashedIdentifier(payload["thread_id"]) == sessionHash,
                  let turn = payload["turn_token_usage"] as? [String: Any],
                  let thread = payload["thread_token_usage"] as? [String: Any],
                  let usage = payload["usage"] as? [String: Any],
                  let direct = CodexActivityNumeric.nonnegativeInteger(turn["total_tokens"]),
                  let cumulative = CodexActivityNumeric.nonnegativeInteger(thread["total_tokens"]),
                  let last = CodexActivityNumeric.nonnegativeInteger(usage["total_tokens"]),
                  cumulative >= direct, direct >= last
            else { return nil }
            return CodexLocalRolloutDecodedRecord(
                eventID: eventID,
                update: .tokenUsage(CodexActivityTokenUsageUpdate(
                    sessionHash: sessionHash,
                    turnHash: turnHash,
                    cumulativeTotalTokens: cumulative,
                    lastReportedTotalTokens: last,
                    directTurnTotalTokens: direct,
                    occurredAt: occurredAt
                ))
            )
        }

        if recordType == "event_msg" {
            return decodeEventMessage(
                payload,
                eventID: eventID,
                occurredAt: occurredAt
            )
        }

        guard recordType == "response_item" else { return nil }
        return decodeToolCall(
            payload,
            eventID: eventID,
            occurredAt: occurredAt
        )
    }

    private mutating func decodeEventMessage(
        _ payload: [String: Any],
        eventID: String?,
        occurredAt: Date
    ) -> CodexLocalRolloutDecodedRecord? {
        guard let type = payload["type"] as? String else { return nil }

        switch type {
        case "item_started", "item_completed":
            guard let turnHash = activeTurnHash,
                  Self.hashedIdentifier(payload["turn_id"]) == turnHash,
                  Self.hashedIdentifier(payload["thread_id"]) == sessionHash,
                  let item = payload["item"] as? [String: Any],
                  item["type"] as? String == "ContextCompaction"
            else { return nil }
            return CodexLocalRolloutDecodedRecord(
                eventID: eventID,
                update: .activity(CodexActivityEvent(
                    event: type == "item_started" ? .preCompact : .postCompact,
                    sessionHash: sessionHash,
                    turnHash: turnHash,
                    workspaceName: workspaceName,
                    sessionKind: sessionKind,
                    source: .localRollout,
                    compactionItemHash: Self.hashedIdentifier(item["id"]),
                    occurredAt: occurredAt
                ))
            )

        case "task_started":
            guard let turnHash = Self.hashedIdentifier(
                payload["turn_id"]
            ) else {
                return nil
            }
            activeTurnHash = turnHash
            isMetadataRecoveredTurn = false
            pendingQuestionCalls.removeAll(); pendingAsyncQuestionCalls.removeAll()
            return CodexLocalRolloutDecodedRecord(
                eventID: eventID,
                update: .activity(
                    CodexActivityEvent(
                        event: .userPromptSubmit,
                        sessionHash: sessionHash,
                        turnHash: turnHash,
                        workspaceName: workspaceName,
                        sessionKind: sessionKind,
                        source: .localRollout,
                        occurredAt: occurredAt
                    )
                )
            )

        case "token_count":
            guard let turnHash = activeTurnHash,
                  let info = payload["info"] as? [String: Any],
                  let total = info["total_token_usage"]
                    as? [String: Any],
                  let last = info["last_token_usage"]
                    as? [String: Any],
                  let cumulative = CodexActivityNumeric.nonnegativeInteger(
                    total["total_tokens"]
                  ),
                  let lastReported = CodexActivityNumeric.nonnegativeInteger(
                    last["total_tokens"]
                  ),
                  cumulative >= lastReported
            else {
                return nil
            }
            return CodexLocalRolloutDecodedRecord(
                eventID: eventID,
                update: .tokenUsage(
                    CodexActivityTokenUsageUpdate(
                        sessionHash: sessionHash,
                        turnHash: turnHash,
                        cumulativeTotalTokens: cumulative,
                        lastReportedTotalTokens: lastReported,
                        occurredAt: occurredAt
                    )
                )
            )

        case "task_complete":
            guard let turnHash = Self.hashedIdentifier(
                payload["turn_id"]
            ), turnHash == activeTurnHash else {
                return nil
            }
            activeTurnHash = nil
            pendingQuestionCalls.removeAll(); pendingAsyncQuestionCalls.removeAll()
            return CodexLocalRolloutDecodedRecord(
                eventID: eventID,
                update: .activity(
                    CodexActivityEvent(
                        event: .stop,
                        sessionHash: sessionHash,
                        turnHash: turnHash,
                        workspaceName: workspaceName,
                        sessionKind: sessionKind,
                        source: .localRollout,
                        turnCompletionStatus: .completed,
                        occurredAt: occurredAt
                    )
                )
            )

        case "turn_aborted":
            guard let turnHash = activeTurnHash else { return nil }
            if let reportedTurn = Self.hashedIdentifier(payload["turn_id"]),
               reportedTurn != turnHash { return nil }
            activeTurnHash = nil
            pendingQuestionCalls.removeAll(); pendingAsyncQuestionCalls.removeAll()
            return CodexLocalRolloutDecodedRecord(
                eventID: eventID,
                update: .activity(
                    CodexActivityEvent(
                        event: .interrupt,
                        sessionHash: sessionHash,
                        turnHash: turnHash,
                        workspaceName: workspaceName,
                        sessionKind: sessionKind,
                        source: .localRollout,
                        turnCompletionStatus: .interrupted,
                        occurredAt: occurredAt
                    )
                )
            )

        default:
            return nil
        }
    }

    private mutating func decodeToolCall(
        _ payload: [String: Any],
        eventID: String?,
        occurredAt: Date
    ) -> CodexLocalRolloutDecodedRecord? {
        guard let turnHash = activeTurnHash, let itemType = payload["type"] as? String else { return nil }
        if ["function_call_output", "custom_tool_call_output"].contains(itemType),
           let callID = payload["call_id"] as? String,
           let index = pendingQuestionCalls.firstIndex(of: callID) {
            pendingQuestionCalls.remove(at: index)
            return .init(eventID: eventID, update: .activity(.init(
                event: .postToolUse, sessionHash: sessionHash, turnHash: turnHash,
                workspaceName: workspaceName, toolCategory: .localTool,
                sessionKind: sessionKind, source: .localRollout, waitReason: .userInput,
                toolCallHash: Self.hashedIdentifier(callID), toolName: "request_user_input", occurredAt: occurredAt)))
        }
        guard itemType == "function_call" || itemType == "custom_tool_call",
              let name = payload["name"] as? String,
              !name.isEmpty
        else {
            return nil
        }

        let inputMode = CodexUserInputMode.forToolName(name)
        let asksQuestion = inputMode != nil
        let asynchronousQuestion = inputMode == .asynchronous
        let callHash = Self.hashedIdentifier(payload["call_id"])
        if asksQuestion, let callID = payload["call_id"] as? String, !callID.isEmpty, callID.utf8.count <= 1024 {
            if asynchronousQuestion {
                pendingAsyncQuestionCalls.removeAll { $0 == callID }; pendingAsyncQuestionCalls.append(callID)
                if pendingAsyncQuestionCalls.count > 128 { pendingAsyncQuestionCalls.removeFirst() }
            } else {
                pendingQuestionCalls.removeAll { $0 == callID }; pendingQuestionCalls.append(callID)
                if pendingQuestionCalls.count > 128 { pendingQuestionCalls.removeFirst() }
            }
        }
        let planProgress = CodexLocalRolloutPlanParser.parse(
            toolName: name,
            arguments: payload["arguments"],
            input: payload["input"]
        )
        return CodexLocalRolloutDecodedRecord(
            eventID: eventID,
            update: .activity(
                CodexActivityEvent(
                    // Async launches present a question while the turn continues.
                    // Only the synchronous tool call itself proves a blocking wait.
                    event: asksQuestion && !asynchronousQuestion ? .permissionRequest : .preToolUse,
                    sessionHash: sessionHash,
                    turnHash: turnHash,
                    workspaceName: workspaceName,
                    toolCategory: CodexActivityPrivacy.toolCategory(
                        for: name
                    ),
                    planProgress: planProgress,
                    sessionKind: sessionKind,
                    source: .localRollout,
                    planSource: planProgress == nil
                        ? nil
                        : .localRollout,
                    waitReason: asksQuestion ? .userInput : nil,
                    toolCallHash: callHash,
                    toolName: String(name.prefix(256)),
                    occurredAt: occurredAt
                )
            )
        )
    }

    private static func hashedIdentifier(_ value: Any?) -> String? {
        guard let value = value as? String, !value.isEmpty else {
            return nil
        }
        return CodexActivityPrivacy.hashIdentifier(value)
    }

    private static func eventID(
        sessionHash: String,
        ordinal: Any?,
        recordType: String,
        payloadType: String?
    ) -> String? {
        guard let ordinal = CodexActivityNumeric.nonnegativeInteger(ordinal) else {
            return nil
        }
        return "rollout:\(sessionHash):\(ordinal):\(recordType):\(payloadType ?? "-")"
    }

}

public enum CodexLocalActivityHealth: Sendable, Equatable {
    case disabled, checking, waitingForRecords, ready, receiving, unreadable, unsupported

    public var hasReadError: Bool { self == .unreadable || self == .unsupported }
}

public actor CodexLocalRolloutActivityClient {
    public struct Configuration: Sendable, Equatable {
        public let isEnabled: Bool
        public let codexHomeURL: URL
        public let pollIntervalSeconds: TimeInterval
        public let candidateRefreshSeconds: TimeInterval
        public let maximumCandidateCount: Int
        public let startupTailBytes: Int

        public init(
            isEnabled: Bool,
            codexHomeURL: URL,
            pollIntervalSeconds: TimeInterval = 0.25,
            candidateRefreshSeconds: TimeInterval = 1,
            maximumCandidateCount: Int = 24,
            startupTailBytes: Int = 16 * 1_048_576
        ) {
            self.isEnabled = isEnabled
            self.codexHomeURL = codexHomeURL.standardizedFileURL
            self.pollIntervalSeconds = max(pollIntervalSeconds, 0.1)
            self.candidateRefreshSeconds = max(
                candidateRefreshSeconds,
                pollIntervalSeconds
            )
            self.maximumCandidateCount = min(128, max(1, maximumCandidateCount))
            self.startupTailBytes = max(
                CodexLocalRolloutLineDecoder.maximumLineBytes,
                min(startupTailBytes, 16 * 1_048_576)
            )
        }

        public static func live(
            environment: [String: String] =
                ProcessInfo.processInfo.environment,
            fileManager: FileManager = .default
        ) -> Configuration {
            let home: URL
            if let configured = environment["CODEX_HOME"],
               !configured.isEmpty
            {
                home = URL(fileURLWithPath: configured)
            } else {
                home = fileManager.homeDirectoryForCurrentUser
                    .appendingPathComponent(".codex", isDirectory: true)
            }
            return Configuration(
                isEnabled:
                    environment["QUOTAVIEW_DISABLE_LOCAL_ROLLOUT"] != "1",
                codexHomeURL: home
            )
        }
    }

    /// Coverage diagnostics contain counts only, never thread IDs or log text.
    public struct MetadataReadSummary: Equatable, Sendable {
        public let status: CodexLocalExecutionMetadata.ReadResult.Status
        public let preferredCount: Int
        public let memoryCount: Int
        public let resolvedCount: Int
        public let failedCount: Int
    }

    private var metadataReadHandler: (@Sendable (MetadataReadSummary) async -> Void)?
    private var lastMetadataReadSummary: MetadataReadSummary?
    public func setExecutionMetadataReadHandler(_ handler: (@Sendable (MetadataReadSummary) async -> Void)?) {
        metadataReadHandler = handler
        lastMetadataReadSummary = nil
    }

    public typealias UpdateHandler = @Sendable (
        CodexLocalRolloutDecodedRecord,
        Bool
    ) async -> Void
    public typealias ConnectionStateHandler = @Sendable (
        CodexSharedAppServerConnectionState
    ) async -> Void
    public typealias HealthHandler = @Sendable (CodexLocalActivityHealth) async -> Void

    private typealias Candidate = CodexLocalRolloutDiscovery.Candidate

    private struct FileIdentity: Equatable, Sendable {
        let device: UInt64
        let inode: UInt64

        init?(attributes: [FileAttributeKey: Any]) {
            guard let device = attributes[.systemNumber] as? NSNumber,
                  let inode = attributes[.systemFileNumber] as? NSNumber else { return nil }
            self.device = device.uint64Value
            self.inode = inode.uint64Value
        }

        init?(handle: FileHandle) {
            var info = stat()
            guard fstat(handle.fileDescriptor, &info) == 0 else { return nil }
            device = UInt64(info.st_dev)
            inode = UInt64(info.st_ino)
        }
    }

    private struct TailState: Sendable {
        let fileIdentity: FileIdentity
        let sessionHash: String
        var offset: UInt64
        var pending = Data()
        var discardingOversizedLine = false
        var decoder: CodexLocalRolloutLineDecoder
        var subagentIdentity: CodexActivitySubagentIdentity?
        var threadMetadata: CodexLocalRolloutThreadMetadata?
        var recoveryAttemptedTurnHash: String?
    }

    private var configuration: Configuration
    private let fileManager: FileManager
    private var publicContentHandler: (@Sendable (CodexLocalPublicContent) async -> Void)?
    public func setPublicContentHandler(_ handler: (@Sendable (CodexLocalPublicContent) async -> Void)?) { publicContentHandler = handler }
    private var updateHandler: UpdateHandler?
    private var connectionStateHandler: ConnectionStateHandler?
    private var healthHandler: HealthHandler?
    private var health: CodexLocalActivityHealth = .disabled
    private var startedAt = Date.distantFuture
    private var receivedActivity = false
    private var readFailed = false
    struct ParsingWorkSummary {
        var processedLines = 0
        var yieldedSlices = 0
        var maximumSliceSeconds: Double = 0
    }
    private(set) var parsingWorkSummary = ParsingWorkSummary()
    private var parsingSliceObserver: (@Sendable () async -> Void)?
    func setParsingSliceObserverForTesting(_ observer: (@Sendable () async -> Void)?) { parsingSliceObserver = observer }
    private var unsupportedMetadata = false
    private var discovery: CodexLocalRolloutDiscovery
    private var maintenanceTask: Task<Void, Never>?
    private var tailStates: [URL: TailState] = [:]
    private var candidates: [Candidate] = []
    private var lastCandidateRefresh = Date.distantPast
    private var executionMetadata: Set<CodexLocalExecutionMetadata.Identity> = []
    private var executionMetadataService: CodexLocalExecutionMetadata.Service
    private var preferredExecutions: (@Sendable () async -> [CodexLocalExecutionMetadata.Execution])?
    private var activeExecutionProvider: (@Sendable () async -> [CodexLocalExecutionMetadata.Execution])?
    private var activeExecutionTurns: [String: String] = [:]

    /// The owner supplies only currently admitted user/subagent executions in
    /// this root/generation. Historical or unknown turns must not be returned.
    public func setActiveExecutionProvider(_ provider: (@Sendable () async -> [CodexLocalExecutionMetadata.Execution])?) {
        activeExecutionProvider = provider
        activeExecutionTurns.removeAll()
    }

    public func setExecutionMetadataService(_ service: CodexLocalExecutionMetadata.Service,
        preferredExecutions: (@Sendable () async -> [CodexLocalExecutionMetadata.Execution])? = nil) {
        executionMetadataService = service
        self.preferredExecutions = preferredExecutions
        executionMetadata.removeAll()
        lastCandidateRefresh = .distantPast
    }
    private var isStarted = false
    private var generation: UInt64 = 0
    private var pollingGeneration: UInt64?
    private var connectionState:
        CodexSharedAppServerConnectionState = .disabled

    public init(
        configuration: Configuration = .live(),
        fileManager: FileManager = .default
    ) {
        self.configuration = configuration
        self.fileManager = fileManager
        executionMetadataService = .init(codexHome: configuration.codexHomeURL)
        discovery = CodexLocalRolloutDiscovery(codexHomeURL: configuration.codexHomeURL,
            maximumCandidateCount: configuration.maximumCandidateCount, fileManager: fileManager)
    }

    public func start(
        handler: @escaping UpdateHandler,
        connectionStateHandler: @escaping ConnectionStateHandler,
        healthHandler: HealthHandler? = nil
    ) async {
        updateHandler = handler
        self.connectionStateHandler = connectionStateHandler
        self.healthHandler = healthHandler
        guard configuration.isEnabled else {
            await publishHealth(.disabled, force: true)
            await publishConnectionState(.disabled)
            return
        }
        guard !isStarted else {
            let run = generation
            await connectionStateHandler(connectionState)
            guard isStarted, generation == run else { return }
            await publishHealth(health, force: true)
            return
        }
        isStarted = true
        parsingWorkSummary = .init()
        startedAt = Date()
        generation &+= 1
        let run = generation
        await publishConnectionState(.discovering)
        guard isStarted, generation == run else { return }
        await publishHealth(.checking)
        guard isStarted, generation == run else { return }
        let client = self
        maintenanceTask = Task(priority: .utility) {
            await client.runMaintenanceLoop(generation: run)
        }
    }

    public func stop() async {
        isStarted = false
        generation &+= 1
        lastCandidateRefresh = .distantPast
        maintenanceTask?.cancel()
        maintenanceTask = nil
        let callback = healthHandler
        updateHandler = nil
        publicContentHandler = nil
        connectionStateHandler = nil
        healthHandler = nil
        receivedActivity = false
        discovery.reset()
        executionMetadata.removeAll()
        activeExecutionProvider = nil
        activeExecutionTurns.removeAll()
        metadataReadHandler = nil
        parsingSliceObserver = nil
        lastMetadataReadSummary = nil
        tailStates.removeAll()
        candidates.removeAll()
        health = .disabled
        connectionState = .disabled
        // Finish all mutation before the callback can reenter and start another run.
        await callback?(.disabled)
    }

    func pollOnceForTesting() async {
        await pollOnce(now: Date())
    }

    /// Recheck preserves live cursors and task state; it never touches Codex configuration.
    public func recheck() async {
        guard isStarted, configuration.isEnabled else {
            await publishHealth(.disabled, force: true)
            return
        }
        lastCandidateRefresh = .distantPast
        discovery.recheck()
        let run = generation
        await publishHealth(.checking)
        guard isStarted, generation == run, !Task.isCancelled else { return }
        await pollOnce(now: Date())
    }

    @discardableResult
    public func setDataDirectory(_ url: URL) -> Bool {
        guard !isStarted else { return false }
        configuration = .init(isEnabled: configuration.isEnabled, codexHomeURL: url,
                              pollIntervalSeconds: configuration.pollIntervalSeconds,
                              candidateRefreshSeconds: configuration.candidateRefreshSeconds,
                              maximumCandidateCount: configuration.maximumCandidateCount,
                              startupTailBytes: configuration.startupTailBytes)
        executionMetadataService = .init(codexHome: url)
        executionMetadata.removeAll()
        activeExecutionTurns.removeAll()
        discovery = CodexLocalRolloutDiscovery(codexHomeURL: url,
            maximumCandidateCount: configuration.maximumCandidateCount, fileManager: fileManager)
        return true
    }

    private func runMaintenanceLoop(generation run: UInt64) async {
        while isStarted, generation == run, !Task.isCancelled {
            await pollOnce(now: Date())
            do {
                try await Task.sleep(
                    nanoseconds: UInt64(
                        configuration.pollIntervalSeconds
                            * 1_000_000_000
                    )
                )
            } catch {
                return
            }
        }
    }

    private func pollOnce(now: Date) async {
        let run = generation
        guard isStarted, pollingGeneration != run else { return }
        pollingGeneration = run
        defer { if pollingGeneration == run { pollingGeneration = nil } }
        if now.timeIntervalSince(lastCandidateRefresh)
            >= configuration.candidateRefreshSeconds
        {
            candidates = discovery.recentCandidates()
            readFailed = discovery.readFailed
            unsupportedMetadata = discovery.unsupportedMetadata
            lastCandidateRefresh = now
            let preferred = await preferredExecutions?() ?? []
            guard isStarted, generation == run, !Task.isCancelled else { return }
            let result = await executionMetadataService.read(preferred: preferred, now: now)
            guard isStarted, generation == run, !Task.isCancelled else { return }
            let summary = MetadataReadSummary(status: result.status, preferredCount: preferred.count,
                memoryCount: result.identities.count, resolvedCount: result.resolvedSessions.count,
                failedCount: result.failedSessions.count)
            if summary != lastMetadataReadSummary {
                lastMetadataReadSummary = summary
                await metadataReadHandler?(summary)
                guard isStarted, generation == run, !Task.isCancelled else { return }
            }
            let identities = Set(result.identities)
            let changed = identities.subtracting(executionMetadata)
            executionMetadata = executionMetadata.filter { !result.resolvedSessions.contains($0.sessionHash) }
            executionMetadata.formUnion(identities)
            if executionMetadata.count > 128 {
                let wanted = Set(preferred.map(\.sessionHash))
                executionMetadata = Set(executionMetadata.sorted {
                    wanted.contains($0.sessionHash) && !wanted.contains($1.sessionHash)
                }.prefix(128))
            }
            for identity in changed {
                guard isStarted, generation == run, !Task.isCancelled else { return }
                await updateHandler?(.init(eventID: nil, update: .sessionMetadata,
                    threadIdentity: .init(threadID: identity.threadID, sessionHash: identity.sessionHash,
                        sessionKind: .memoryConsolidation, executionTurnHash: identity.turnHash)), false)
            }
            let reclassified = discovery.excludedIdentities.compactMap { file, identity in
                tailStates[file]?.sessionHash == identity.sessionHash ? identity : nil
            }
            let retained = Set(candidates.map(\.fileURL))
            tailStates = tailStates.filter { retained.contains($0.key) }
            for identity in reclassified {
                guard isStarted, generation == run, !Task.isCancelled else { return }
                await updateHandler?(.init(eventID: nil, update: .sessionMetadata, threadIdentity: identity), false)
            }
        }

        let active = await activeExecutionProvider?() ?? []
        guard isStarted, generation == run, !Task.isCancelled else { return }
        activeExecutionTurns = Dictionary(active.prefix(128).compactMap { identity in
            identity.turnHash.map { (identity.sessionHash, $0) }
        }, uniquingKeysWith: { first, _ in first })
        for candidate in candidates {
            guard isStarted, generation == run, !Task.isCancelled else { return }
            await consume(candidate: candidate, generation: run)
        }
        guard isStarted, generation == run else { return }
        let next: CodexLocalActivityHealth = readFailed ? .unreadable
            : !tailStates.isEmpty ? (receivedActivity ? .receiving : .ready)
            : unsupportedMetadata ? .unsupported : .waitingForRecords
        await publishHealth(next)
        guard isStarted, generation == run else { return }
        await publishConnectionState(next == .ready || next == .receiving ? .connected : .discovering)
    }

    private func consume(candidate: Candidate, generation run: UInt64) async {
        let root = configuration.codexHomeURL.appendingPathComponent("sessions")
        guard CodexLocalRolloutDiscovery.isAllowedRollout(candidate.fileURL, sessionsURL: root) else {
            tailStates.removeValue(forKey: candidate.fileURL)
            return
        }
        if tailStates[candidate.fileURL] == nil {
            await bootstrap(candidate: candidate, generation: run)
            return
        }

        guard var state = tailStates[candidate.fileURL],
              let attributes = try? fileManager.attributesOfItem(
                atPath: candidate.fileURL.path
              ),
              let size = (attributes[.size] as? NSNumber)?.uint64Value
        else {
            readFailed = true
            return
        }

        if size < state.offset || FileIdentity(attributes: attributes) != state.fileIdentity
            || state.sessionHash != candidate.sessionHash {
            tailStates.removeValue(forKey: candidate.fileURL)
            await bootstrap(candidate: candidate, generation: run)
            return
        }
        guard let metadata = discovery.sessionMetadata(from: candidate.fileURL),
              metadata.threadID == candidate.threadID, metadata.sessionHash == candidate.sessionHash,
              metadata.kind == candidate.metadataKind else {
            tailStates.removeValue(forKey: candidate.fileURL); lastCandidateRefresh = .distantPast
            return
        }
        let recoveryTurn = [CodexActivitySessionKind.user, .subagent].contains(candidate.sessionKind)
            ? activeExecutionTurns[candidate.sessionHash] : nil
        if state.decoder.isMetadataRecoveredTurn, recoveryTurn == nil { state.recoveryAttemptedTurnHash = nil }
        state.decoder.restrictMetadataRecovery(to: recoveryTurn)
        if let recoveryTurn, state.decoder.activeTurnHash != recoveryTurn,
           state.recoveryAttemptedTurnHash != recoveryTurn {
            await bootstrap(candidate: candidate, generation: run)
            return
        }
        let previousKind = state.decoder.sessionKind
        let previousChild = state.subagentIdentity
        let previousMetadata = state.threadMetadata
        state.decoder.refineSessionKind(candidate.sessionKind)
        state.subagentIdentity = metadata.subagentIdentity?.withTitle(candidate.title)
        state.threadMetadata = candidate.threadMetadata
        if state.decoder.sessionKind != previousKind || state.subagentIdentity != previousChild
            || state.threadMetadata != previousMetadata {
            // Classification can arrive after the last rollout append. Publish
            // metadata alone and retain the original decoder/turn/cursor.
            tailStates[candidate.fileURL] = state
            await updateHandler?(.init(eventID: nil, update: .sessionMetadata,
                threadIdentity: .init(threadID: candidate.threadID, sessionHash: candidate.sessionHash,
                                      sessionKind: state.decoder.sessionKind,
                                      subagentIdentity: state.subagentIdentity,
                                      threadMetadata: state.threadMetadata)), false)
            guard isStarted, generation == run, !Task.isCancelled,
                  tailStates[candidate.fileURL]?.offset == state.offset else { return }
        }
        if state.subagentIdentity != previousChild {
            await publishSubagentTitle(state.subagentIdentity, turnHash: state.decoder.activeTurnHash, generation: run)
            guard isStarted, generation == run, !Task.isCancelled else { return }
        }
        tailStates[candidate.fileURL] = state
        guard size > state.offset else { return }
        guard let handle = try? FileHandle(forReadingFrom: candidate.fileURL)
        else {
            readFailed = true
            return
        }
        defer { try? handle.close() }
        guard FileIdentity(handle: handle) == state.fileIdentity else {
            tailStates.removeValue(forKey: candidate.fileURL)
            await bootstrap(candidate: candidate, generation: run)
            return
        }
        do {
            try handle.seek(toOffset: state.offset)
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            state.offset = try handle.offset()
            state.pending.append(data)
            var records: [(CodexLocalRolloutDecodedRecord?, CodexLocalPublicContent?)] = []
            let complete = await consumeCompleteLines(from: &state.pending, discarding: &state.discardingOversizedLine, generation: run) { line in
                guard let envelope = CodexLocalRolloutEnvelope(line) else { return }
                let record = state.decoder.decode(envelope)
                let content = publicContentHandler == nil ? nil : CodexLocalPublicContent.decode(envelope, sessionHash: state.sessionHash, activeTurnHash: state.decoder.activeTurnHash, asynchronousQuestionCallIDs: state.decoder.asynchronousQuestionCallIDs)
                if record != nil || content != nil { records.append((record, content)) }
            }
            guard complete, isStarted, generation == run, !Task.isCancelled else { return }
            // Commit the cursor before any reentrant callback can stop/restart us.
            tailStates[candidate.fileURL] = state
            for (record, content) in records {
                guard isStarted, generation == run, !Task.isCancelled else { return }
                if let record {
                    receivedActivity = true
                    await updateHandler?(.init(eventID: record.eventID, update: record.update,
                        requiresLiveConfirmation: record.requiresLiveConfirmation,
                        threadIdentity: .init(threadID: candidate.threadID, sessionHash: candidate.sessionHash, sessionKind: candidate.sessionKind,
                                              subagentIdentity: state.subagentIdentity,
                                              threadMetadata: state.threadMetadata)), false)
                }
                guard isStarted, generation == run else { return }
                if let content { await publicContentHandler?(content) }
            }
        } catch {
            readFailed = true
            return
        }
    }

    private func bootstrap(candidate: Candidate, generation run: UInt64) async {
        guard let handle = try? FileHandle(forReadingFrom: candidate.fileURL)
        else {
            readFailed = true
            return
        }
        defer { try? handle.close() }

        do {
            guard let fileIdentity = FileIdentity(handle: handle),
                  let metadata = discovery.sessionMetadata(from: candidate.fileURL),
                  metadata.sessionHash == candidate.sessionHash, metadata.threadID == candidate.threadID,
                  metadata.kind == candidate.metadataKind else {
                lastCandidateRefresh = .distantPast
                return
            }
            let size = try handle.seekToEnd()
            let start = size > UInt64(configuration.startupTailBytes)
                ? size - UInt64(configuration.startupTailBytes)
                : 0
            try handle.seek(toOffset: start)
            var data = try handle.read(upToCount: Int(size - start)) ?? Data()
            let actualOffset = try handle.offset()
            var discarding = false
            if start > 0 {
                if let newline = data.firstIndex(of: 0x0A) {
                    data.removeSubrange(data.startIndex...newline)
                } else { data.removeAll(); discarding = true }
            }

            let recoveryTurn = [CodexActivitySessionKind.user, .subagent].contains(candidate.sessionKind)
                ? activeExecutionTurns[candidate.sessionHash] : nil
            var decoder = CodexLocalRolloutLineDecoder(
                sessionHash: candidate.sessionHash,
                workspaceName: candidate.workspaceName,
                sessionKind: candidate.sessionKind,
                metadataRecoveryTurnHash: recoveryTurn
            )
            var recoveryTokens: [CodexActivityTokenUsageUpdate] = []
            var replay = BootstrapReplay()
            var freshStart = false
            var publicReplay = CodexLocalPublicReplayBuffer()
            var latestPublicMetadata: CodexLocalPublicContent?
            var pending = data
            let complete = await consumeCompleteLines(from: &pending, discarding: &discarding, generation: run) { line in
                guard let envelope = CodexLocalRolloutEnvelope(line) else { return }
                let decoded = decoder.decode(envelope)
                publicReplay.selectTurn(decoder.activeTurnHash)
                if let content = publicContentHandler == nil ? nil : CodexLocalPublicContent.decode(envelope, sessionHash: candidate.sessionHash, activeTurnHash: decoder.activeTurnHash, asynchronousQuestionCallIDs: decoder.asynchronousQuestionCallIDs) {
                    if content.projectionKind == "metadata" {
                        // Model/effort must survive a busy turn's 200-output
                        // replay cap without retaining additional user content.
                        latestPublicMetadata = content
                    } else {
                        publicReplay.append(content, isAssistantMessage: content.projectionKind == "message")
                    }
                }
                guard let record = decoded else { return }
                if case .tokenUsage(let usage) = record.update, decoder.isMetadataRecoveredTurn {
                    recoveryTokens.append(usage)
                    if recoveryTokens.count > 256 { recoveryTokens.removeFirst() }
                }
                if case .activity(let event) = record.update, event.event == .userPromptSubmit {
                    // Do not use the decoder's missing-timestamp fallback as live evidence.
                    let timestamp = envelope.timestamp
                    let now = Date()
                    freshStart = timestamp.map { $0 >= startedAt && $0 >= now.addingTimeInterval(-5)
                        && $0 <= now.addingTimeInterval(2) } ?? false
                }
                replay.record(record)
            }
            guard complete, isStarted, generation == run, !Task.isCancelled else { return }
            let child = metadata.subagentIdentity?.withTitle(candidate.title)
            tailStates[candidate.fileURL] = TailState(
                fileIdentity: fileIdentity, sessionHash: candidate.sessionHash,
                offset: actualOffset, pending: pending,
                discardingOversizedLine: discarding, decoder: decoder, subagentIdentity: child,
                threadMetadata: candidate.threadMetadata, recoveryAttemptedTurnHash: recoveryTurn
            )
            if child != nil || candidate.threadMetadata != nil {
                await updateHandler?(.init(eventID: nil, update: .sessionMetadata,
                    threadIdentity: .init(threadID: candidate.threadID, sessionHash: candidate.sessionHash,
                        sessionKind: candidate.sessionKind, subagentIdentity: child,
                        threadMetadata: candidate.threadMetadata)), true)
                guard isStarted, generation == run, !Task.isCancelled else { return }
            }
            if replay.isActive, !decoder.isMetadataRecoveredTurn {
                if freshStart { receivedActivity = true }
                for record in replay.records {
                    guard isStarted, generation == run, !Task.isCancelled else { return }
                    await updateHandler?(.init(eventID: record.eventID, update: record.update,
                                              requiresLiveConfirmation: !freshStart,
                                              threadIdentity: .init(threadID: candidate.threadID, sessionHash: candidate.sessionHash, sessionKind: candidate.sessionKind,
                                                                    subagentIdentity: child,
                                                                    threadMetadata: candidate.threadMetadata)), true)
                }
                await publishSubagentTitle(child, turnHash: decoder.activeTurnHash, generation: run)
                guard isStarted, generation == run, !Task.isCancelled else { return }
                if let content = latestPublicMetadata, content.turnHash == decoder.activeTurnHash {
                    await publicContentHandler?(content)
                }
                for content in publicReplay.contents {
                    guard isStarted, generation == run else { return }
                    await publicContentHandler?(content)
                }
            } else if decoder.isMetadataRecoveredTurn, let turn = decoder.activeTurnHash, turn == recoveryTurn {
                // Repair presentation for an already-live execution. Neither
                // lifecycle events nor old questions gain authority from disk.
                let currentTokens = recoveryTokens.filter { $0.turnHash == turn }
                if !currentTokens.isEmpty {
                    await updateHandler?(.init(eventID: nil, update: .tokenUsageReplay(currentTokens),
                        requiresLiveConfirmation: true,
                        threadIdentity: .init(threadID: candidate.threadID, sessionHash: candidate.sessionHash,
                            sessionKind: candidate.sessionKind, threadMetadata: candidate.threadMetadata)), true)
                }
                guard isStarted, generation == run, !Task.isCancelled else { return }
                if let content = latestPublicMetadata, content.turnHash == turn {
                    await publicContentHandler?(content)
                }
                let currentContent = publicReplay.contents.filter { $0.turnHash == turn }
                let observedToolIDs = Set(currentContent.compactMap { content -> String? in
                    guard content.projectionKind == "tool" else { return nil }
                    return content.projectionCallID
                })
                for content in currentContent {
                    guard isStarted, generation == run, !Task.isCancelled else { return }
                    guard let type = content.projectionKind else { continue }
                    let ordinaryTool = type == "tool"
                        && content.projectionCallID.map(observedToolIDs.contains) == true
                    let ordinaryOutput = type == "output"
                        && content.projectionCallID.map(observedToolIDs.contains) == true
                    guard type == "message" || ordinaryTool || ordinaryOutput else { continue }
                    // Consumers restore public text only. An observed old tool
                    // is not evidence that it is still running or awaiting input.
                    guard var fields = (try? JSONSerialization.jsonObject(with: content.data)) as? [String: Any] else { continue }
                    fields["presentationRecovery"] = true
                    guard let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]) else { continue }
                    await publicContentHandler?(.init(sessionHash: content.sessionHash, turnHash: content.turnHash,
                        data: data, occurredAt: content.occurredAt))
                }
            }
        } catch {
            readFailed = true
            return
        }
    }

    private func publishSubagentTitle(_ child: CodexActivitySubagentIdentity?, turnHash: String?, generation run: UInt64) async {
        guard isStarted, generation == run, let child, let turnHash, let title = child.title,
              let data = try? JSONSerialization.data(withJSONObject: ["type": "metadata", "title": title]) else { return }
        await publicContentHandler?(.init(sessionHash: child.sessionHash, turnHash: turnHash, data: data, occurredAt: Date()))
    }

    private func consumeCompleteLines(
        from data: inout Data,
        discarding: inout Bool,
        generation run: UInt64,
        body: (Data) -> Void
    ) async -> Bool {
        var cursor = data.startIndex
        var sliceBytes = 0, sliceLines = 0
        var sliceStarted = ContinuousClock.now
        defer { data.removeSubrange(data.startIndex..<cursor) }
        func recordSlice() {
            let duration = sliceStarted.duration(to: .now).components
            let seconds = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
            parsingWorkSummary.maximumSliceSeconds = max(parsingWorkSummary.maximumSliceSeconds, seconds)
        }
        // Scan without repeatedly shifting a multi-MiB tail after every line.
        while let range = data.range(of: Data([10]), in: cursor..<data.endIndex) {
            let newline = range.lowerBound
            let count = newline - cursor
            parsingWorkSummary.processedLines += 1
            if !discarding, count <= CodexLocalRolloutLineDecoder.maximumLineBytes {
                body(Data(data[cursor..<newline]))
            }
            cursor = range.upperBound
            discarding = false
            sliceBytes += count + 1; sliceLines += 1
            if sliceBytes >= 262_144 || sliceLines >= 128
                || sliceStarted.duration(to: .now) >= .milliseconds(5) {
                recordSlice()
                parsingWorkSummary.yieldedSlices += 1
                await Task.yield()
                await parsingSliceObserver?()
                guard isStarted, generation == run, !Task.isCancelled else { return false }
                sliceBytes = 0; sliceLines = 0; sliceStarted = .now
            }
        }
        if sliceLines > 0 { recordSlice() }
        if data.endIndex - cursor > CodexLocalRolloutLineDecoder.maximumLineBytes {
            cursor = data.endIndex
            discarding = true
        }
        return true
    }

    private func publishHealth(_ value: CodexLocalActivityHealth, force: Bool = false) async {
        guard force || health != value else { return }
        health = value
        await healthHandler?(value)
    }

    private func publishConnectionState(
        _ state: CodexSharedAppServerConnectionState
    ) async {
        guard connectionState != state else { return }
        connectionState = state
        await connectionStateHandler?(state)
    }
}

/// One recent assistant progress record shares the existing content budget with
/// tools/outputs. Keeping this slot prevents a busy tool stream from erasing the
/// public progress summary, without retaining a second unbounded text buffer.
struct CodexLocalPublicReplayBuffer {
    static let maximumCount = 200
    static let maximumBytes = 2_097_152
    private(set) var contents: [CodexLocalPublicContent] = []
    private(set) var byteCount = 0
    private var currentTurn: String?
    private var protectedMessageIndex: Int?

    mutating func selectTurn(_ turn: String?) {
        if currentTurn != turn { protectedMessageIndex = nil }
        currentTurn = turn
    }

    mutating func append(_ content: CodexLocalPublicContent, isAssistantMessage: Bool) {
        selectTurn(content.turnHash)
        contents.append(content)
        byteCount += content.data.count
        if isAssistantMessage { protectedMessageIndex = contents.count - 1 }
        while contents.count > Self.maximumCount || byteCount > Self.maximumBytes {
            // Prefer the oldest ordinary record; a sole oversized message is
            // still removed, so the same hard byte/count bounds always apply.
            let removedIndex = protectedMessageIndex == 0 && contents.count > 1 ? 1 : 0
            byteCount -= contents.remove(at: removedIndex).data.count
            if let protected = protectedMessageIndex {
                protectedMessageIndex = protected == removedIndex ? nil
                    : protected > removedIndex ? protected - 1 : protected
            }
        }
    }
}

private struct BootstrapReplay {
    private var start: CodexLocalRolloutDecodedRecord?
    private var plan: CodexLocalRolloutDecodedRecord?
    private var compaction: CodexLocalRolloutDecodedRecord?
    private var legacyTokens: [CodexActivityTokenUsageUpdate] = []
    private var directTokens: CodexLocalRolloutDecodedRecord?
    private(set) var isActive = false

    mutating func record(_ record: CodexLocalRolloutDecodedRecord) {
        switch record.update {
        case .tokenUsageReplay, .sessionMetadata:
            break // Neither metadata nor a recovery batch invents a lifecycle start.
        case .activity(let event):
            switch event.event {
            case .userPromptSubmit:
                self = BootstrapReplay()
                start = record
                isActive = true
            case .stop, .interrupt, .sessionEnd:
                self = BootstrapReplay()
            case .preCompact, .postCompact:
                if isActive { compaction = record }
            case .preToolUse:
                if isActive {
                    compaction = nil
                    if event.planProgress != nil { plan = record }
                }
            default:
                break
            }
        case .tokenUsage(let update):
            if isActive {
                if let total = update.directTurnTotalTokens {
                    if case .tokenUsage(let previous) = directTokens?.update,
                       let previousTotal = previous.directTurnTotalTokens,
                       previousTotal > total { break }
                    directTokens = record
                } else {
                    legacyTokens.append(update)
                }
            }
        }
    }

    var records: [CodexLocalRolloutDecodedRecord] {
        // Usage and activity are independent streams. Preserve direct usage
        // even when the final record is a legacy rebroadcast without ordinal.
        var result = [start, plan, compaction].compactMap { $0 }
        var usage = legacyTokens
        if case .tokenUsage(let direct) = directTokens?.update { usage.append(direct) }
        // Preserve every numeric segment, but publish only the recovered total.
        if !usage.isEmpty {
            result.append(.init(eventID: nil, update: .tokenUsageReplay(usage)))
        }
        return result
    }
}

private enum CodexLocalRolloutPlanParser {
    static func parse(toolName: String, arguments: Any?, input: Any?) -> CodexActivityPlanProgress? {
        guard let counts = CodexActivityPlanInputParser.parseRollout(
            toolName: toolName, arguments: arguments, input: input) else { return nil }
        return .init(completedSteps: counts.completedSteps,
                     inProgressSteps: counts.inProgressSteps, pendingSteps: counts.pendingSteps)
    }
}
