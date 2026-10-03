import Combine
import Foundation
import QuotaViewCore


@MainActor
final class CodexActivityStore: ObservableObject {
    nonisolated static let compactDelay: TimeInterval = 20
    nonisolated static let hiddenDelayAfterCompact: TimeInterval = 100
    nonisolated static let settledEventReplayAgeThreshold: TimeInterval = 20
    nonisolated static let confirmationReminderDelay: TimeInterval = 10

    @Published private(set) var snapshot: CodexActivitySnapshot?
    /// Background execution is observable without becoming a user conversation.
    @Published private(set) var backgroundMemorySnapshots: [CodexActivitySnapshot] = []
    private struct ObservedActivity {
        let snapshot: CodexActivitySnapshot
        let lifecycle: CodexActivityTurnLifecycle
        var source: CodexActivityEventSource
        var isDesktopObservation = false
        var snapshotBeforeSourceLoss: CodexActivitySnapshot?
    }
    private var observedActivityBySession: [String: ObservedActivity] = [:]
    private var memoryActivityBySession: [String: ObservedActivity] = [:]
    private var executionMemoryTurns: [String: String] = [:]
    private struct ExecutionMemoryKey: Hashable {
        let session: String
        let turn: String
    }
    private struct PendingExecutionMemory {
        let generation: UInt64
        let receivedAt: TimeInterval
    }
    // Discovery can precede the lifecycle which admits its exact execution.
    // This is evidence only; it neither creates a task nor grants capabilities.
    private var pendingExecutionMemory: [ExecutionMemoryKey: PendingExecutionMemory] = [:]
    private var pendingExecutionMemoryOrder: [ExecutionMemoryKey] = []
    private static let maximumPendingExecutionMemory = 128
    private static let pendingExecutionMemoryLifetime: TimeInterval = 86_400
    var activityExecutionKindDidResolve: ((String, CodexActivitySessionKind) -> Void)?
    var subagentIdentityDidReceive: ((CodexActivitySubagentIdentity) -> Void)?
    var subagentActivityDidReceive: ((CodexActivityEvent) -> Void)?
    var subagentPublicContentDidReceive: ((CodexLocalPublicContent) -> Void)?
    var subagentPublicMessageDidReceive: ((Data) -> Void)?
    var subagentSourceUnavailable: ((CodexActivityEventSource?) -> Void)?
    /// Capacity/root withdrawal revokes one execution without inventing completion.
    var subagentObservationDidWithdraw: ((String) -> Void)?
    private var subagentIdentities: [String: CodexActivitySubagentIdentity] = [:]
    private var lastAdmittedActivityBySession: [String: CodexActivityEvent] = [:]
    private var admittedTurnStartBySession: [String: CodexActivityEvent] = [:]
    private var subagentUnavailableSessions: Set<String> = []
    @Published private(set) var presentation:
        CodexActivityPresentation = .hidden
    @Published private(set) var resolvedThreadTitle: String?
    @Published private(set) var lifecycle:
        CodexActivityTurnLifecycle = .idle
    @Published private(set) var isConfirmationReminderActive = false
    private(set) var multitask = CodexActivityMultitaskState()
    // Shared admitted snapshots permit enabling midway through existing work.
    // No extra observer, timer, or title request runs while multitask is disabled.
    private var admittedSnapshots: [String: CodexActivityMultitaskState.Entry] = [:]
    private var multitaskTask: Task<Void, Never>?
    private var multitaskDeadline: TimeInterval?
    private var multitaskGeneration: UInt64 = 0
    private var multitaskTitleTasks: [String: Task<Void, Never>] = [:]

    func tokenUsage(for session: String) -> Int64? {
        guard let turn = activeTurnHashBySession[session],
              let usage = turnTokenUsageBySession[session], usage.turnHash == turn,
              let count = usage.consumedTokens, count > 0 else { return nil }
        return count
    }

    // Sum the current turns in this displayed group, never formatted labels or
    // account totals. Missing data remains unknown rather than a partial total.
    var multitaskTotalTokenUsage: Int64? {
        guard !multitask.entries.isEmpty else { return nil }
        var total: Int64 = 0
        for entry in multitask.entries {
            guard let count = tokenUsage(for: entry.snapshot.sessionHash) else { return nil }
            let sum = total.addingReportingOverflow(count)
            guard !sum.overflow else { return nil }
            total = sum.partialValue
        }
        return total
    }

    func title(for session: String) -> String? { titleCache[session] }
    func titleSource(for session: String) -> IslandTaskTitleSource { titleCacheSources[session] ?? .fallback }

    func setMultitaskEnabled(_ enabled: Bool) {
        guard multitask.enabled != enabled else { return }
        multitaskGeneration &+= 1
        multitaskTask?.cancel(); multitaskTask = nil; multitaskDeadline = nil
        multitaskTitleTasks.values.forEach { $0.cancel() }; multitaskTitleTasks.removeAll()
        multitask.setEnabled(enabled)
        guard enabled else { return }
        let now = ProcessInfo.processInfo.systemUptime
        multitask.updateDelays(compact: Double(compactDelayNanoseconds) / 1e9,
                               hidden: Double(hiddenDelayNanoseconds) / 1e9, now: now)
        let seeds = admittedSnapshots.values.filter { $0.lifecycle == .active }
            .sorted { $0.snapshot.occurredAt < $1.snapshot.occurredAt }
        for entry in seeds {
            multitask.receive(entry.snapshot, lifecycle: entry.lifecycle,
                              compactionSource: entry.compactionSource, now: now, permitsNewEntry: true)
        }
        if let session = snapshot?.sessionHash,
           let entry = multitask.entries.first(where: { $0.snapshot.sessionHash == session }) {
            multitask.select(entry.id)
        }
        resolveMultitaskTitles()
    }

    func selectMultitaskTask(_ id: Int) {
        guard multitask.enabled else { return }
        multitask.select(id)
        notifyChange()
    }

    var currentTurnTokenUsage: Int64? {
        guard let snapshot,
              let activeTurnHash = activeTurnHashBySession[
                  snapshot.sessionHash
              ],
              let usage = turnTokenUsageBySession[snapshot.sessionHash],
              usage.turnHash == activeTurnHash,
              let consumedTokens = usage.consumedTokens,
              consumedTokens > 0
        else {
            return nil
        }
        return consumedTokens
    }

    var localPublicContentDidReceive: ((CodexLocalPublicContent) -> Void)?
    var threadMetadataDidReceive: ((CodexActivityTaskIdentity, CodexLocalRolloutThreadMetadata) -> Void)?
    /// Local-only tasks can request read-only Desktop owner discovery without
    /// waiting for a Shared App Server envelope carrying the raw thread ID.
    var localThreadActivityDidReceive: ((CodexLocalRolloutThreadIdentity, Bool) -> Void)?
    private var localDesktopFollows: [String: (identity: CodexLocalRolloutThreadIdentity, turn: String)] = [:]
    private var localDesktopFollowOrder: [String] = []
    var localDesktopFollowIdentities: [CodexLocalRolloutThreadIdentity] {
        localDesktopFollowOrder.compactMap { localDesktopFollows[$0]?.identity }
    }
    var publicMessageDidReceive: ((Data) -> Void)?
    var desktopProjectionDidReceive: ((CodexDesktopInteractionProjection, CodexDesktopConversationSnapshot) -> Void)?
    var admittedActivityDidReceive: ((CodexActivityEvent) -> Void)?
    /// Classification is published before any user activity/content callback.
    var activitySessionKindDidResolve: ((String, CodexActivitySessionKind) -> Void)?
    var cumulativeTokensDidReceive: ((CodexActivityTokenUsageUpdate) -> Void)?
    var stateDidChange: (() -> Void)?
    var automaticConnectionDidChange: ((CodexAutomaticActivityConnection) -> Void)?
    private(set) var automaticConnection = CodexAutomaticActivityConnection()
    var nativeConnectionState: CodexSharedAppServerConnectionState { automaticConnection.nativeState }
    var localHealth: CodexLocalActivityHealth { automaticConnection.localHealth }
    private var nativeIsRunning = false

    private var titleClient: CodexAppServerClient
    private var sharedActivityClient: CodexSharedAppServerActivityClient
    private var localRolloutActivityClient: CodexLocalRolloutActivityClient
    private var compactDelayNanoseconds: UInt64
    private var hiddenDelayNanoseconds: UInt64
    private var settledEventReplayAgeThresholdNanoseconds: UInt64
    private var confirmationReminderDelayNanoseconds: UInt64
    private var inactivityTask: Task<Void, Never>?
    private var confirmationReminderTask: Task<Void, Never>?
    private var confirmationReminderContext:
        ConfirmationReminderContext?
    private var titleTask: Task<Void, Never>?
    private var titleTaskSessionHash: String?
    private var titleCache: [String: String] = [:]
    private var titleCacheSources: [String: IslandTaskTitleSource] = [:]
    private var threadMetadataBySession: [String: CodexLocalRolloutThreadMetadata] = [:]
    private var threadMetadataOrder: [String] = []
    private var titleAttemptedAt: [String: Date] = [:]
    private var latestEventAtBySession: [String: Date] = [:]
    private var terminalTurnsBySession: [String: TerminalTurn] = [:]
    private var acceptedEventIDs: Set<String> = []
    private var acceptedEventIDOrder: [String] = []
    private var planProgressBySession: [String: StoredPlanProgress] = [:]
    private var goalStatusBySession: [String: CodexActivityGoalStatus] = [:]
    private var cumulativeTokensBySession: [String: Int64] = [:]
    private var latestLegacyTokenAtBySession: [String: Date] = [:]
    private var activeTurnHashBySession: [String: String] = [:]
    private var turnTokenUsageBySession: [String: StoredTurnTokenUsage] = [:]
    private var sessionClassifier = CodexActivitySessionClassifier()
    private var hookSessionClassifier = CodexActivitySessionClassifier()
    private var executionMetadataRoot: URL
    private var executionMetadataService: CodexLocalExecutionMetadata.Service
    private var localRecovery = CodexLocalActivityRecovery()
    private var pendingLocalPublicContent: [CodexLocalPublicContent] = []
    private struct BufferedNativePublicMessage {
        let data: Data
        let epoch: UInt64
        let session: String
        let turn: String
        let receivedAt: Date
    }
    private var pendingNativePublicMessages: [BufferedNativePublicMessage] = []
    private var nativePublicEpoch: UInt64?
    private var closedNativePublicEpoch: UInt64?
    private var desktopPublicEpoch: UInt64?
    private var closedDesktopPublicEpoch: UInt64?
    private struct DesktopAdmission {
        let owner: String
        let epoch: UInt64
        let revision: Int64
        let turnHash: String
    }
    private var desktopAdmissions: [String: DesktopAdmission] = [:]
    private var desktopMemoryAdmissions: [String: DesktopAdmission] = [:]
    private var desktopReceiptReservations: [String: (id: UUID, admission: DesktopAdmission)] = [:]
    private var desktopWaitEvidence: [String: NativeWaitEvidence] = [:]
    private struct NativeWaitEvidence {
        let identity: CodexActivityTaskIdentity
        let epoch: UInt64
        let reason: CodexActivityWaitReason
    }
    private var nativeWaitEvidence: [String: NativeWaitEvidence] = [:]
    private var confirmedNativeTurns: [String: CodexActivityTaskIdentity] = [:]
    private var selectedActivityAt: Date?
    private var selectedCompactionSource: CodexActivityEventSource?
    private let sessionKindResolver: (@Sendable (CodexActivityEvent) async -> CodexActivitySessionKind)?
    private var nativeGeneration: UInt64 = 0
    private var nativeStartTask: Task<Void, Never>?
    private var taskRegistry = CodexActivityTaskRegistry()
    private var sessionKinds: [String: CodexActivitySessionKind] = [:]
    private var sessionKindOrder: [String] = []
    private static let maximumRememberedSessionKinds = 1024
    private var revision: UInt64 = 0

    private struct StoredPlanProgress {
        let turnHash: String?
        let fraction: Double
        let source: CodexActivityPlanSource
    }

    private struct TerminalTurn {
        let turnHash: String?
    }

    private struct StoredTurnTokenUsage {
        let turnHash: String
        let baselineTotalTokens: Int64?
        let consumedTokens: Int64?
        var segmentOffset: Int64 = 0
        var directTotalTokens: Int64? = nil
    }

    private struct ConfirmationReminderContext: Equatable {
        let sessionHash: String
        let turnHash: String?
    }

    init(
        titleClient: CodexAppServerClient = CodexAppServerClient(),
        sharedActivityClient: CodexSharedAppServerActivityClient =
            CodexSharedAppServerActivityClient(),
        localRolloutActivityClient: CodexLocalRolloutActivityClient =
            CodexLocalRolloutActivityClient(),
        compactDelay: TimeInterval = CodexActivityStore.compactDelay,
        hiddenDelayAfterCompact: TimeInterval =
            CodexActivityStore.hiddenDelayAfterCompact,
        settledEventReplayAgeThreshold: TimeInterval =
            CodexActivityStore.settledEventReplayAgeThreshold,
        confirmationReminderDelay: TimeInterval =
            CodexActivityStore.confirmationReminderDelay,
        sessionDirectory: URL? = nil,
        sessionKindResolver: (@Sendable (CodexActivityEvent) async -> CodexActivitySessionKind)? = nil
    ) {
        self.sessionKindResolver = sessionKindResolver
        self.titleClient = titleClient
        self.sharedActivityClient = sharedActivityClient
        self.localRolloutActivityClient = localRolloutActivityClient
        let metadataRoot = (sessionDirectory ?? ProcessInfo.processInfo.environment["CODEX_HOME"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        } ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")).standardizedFileURL
        let service = CodexLocalExecutionMetadata.Service(codexHome: metadataRoot)
        executionMetadataRoot = metadataRoot
        executionMetadataService = service
        sessionClassifier = CodexActivitySessionClassifier(codexHome: metadataRoot, executionMetadataService: service)
        hookSessionClassifier = CodexActivitySessionClassifier(codexHome: metadataRoot, executionMetadataService: service)
        compactDelayNanoseconds = UInt64(
            max(compactDelay, 0) * 1_000_000_000
        )
        hiddenDelayNanoseconds = UInt64(
            max(hiddenDelayAfterCompact, 0) * 1_000_000_000
        )
        settledEventReplayAgeThresholdNanoseconds = Self.nanoseconds(
            for: settledEventReplayAgeThreshold
        )
        confirmationReminderDelayNanoseconds = Self.nanoseconds(
            for: confirmationReminderDelay
        )
    }

    var shouldPlayVisualEffects: Bool {
        guard presentation != .hidden else { return false }
        return lifecycle == .active || lifecycle == .completed
    }

    func startNativeActivityNotifications() {
        guard !nativeIsRunning else { return }
        nativeIsRunning = true
        updateAutomaticConnection(.init(localHealth: .checking))
        nativeStartTask?.cancel()
        nativeGeneration &+= 1
        let run = nativeGeneration
        let service = CodexLocalExecutionMetadata.Service(codexHome: executionMetadataRoot)
        executionMetadataService = service
        sessionClassifier = .init(codexHome: executionMetadataRoot, executionMetadataService: service)
        hookSessionClassifier = .init(codexHome: executionMetadataRoot, executionMetadataService: service)
        let sharedActivityClient = sharedActivityClient
        let localRolloutActivityClient = localRolloutActivityClient
        nativeStartTask = Task { [weak self] in
            guard let self, self.nativeGeneration == run, !Task.isCancelled else { return }
            await localRolloutActivityClient.setExecutionMetadataService(service, preferredExecutions: { [weak self] in
                await self?.executionMetadataPreferences(generation: run) ?? []
            })
            guard self.nativeGeneration == run, !Task.isCancelled else { return }
            await localRolloutActivityClient.setActiveExecutionProvider { [weak self] in
                await self?.activeExecutionMetadataPreferences(generation: run) ?? []
            }
            guard self.nativeGeneration == run, !Task.isCancelled else { return }
            await localRolloutActivityClient.setExecutionMetadataReadHandler { [weak self] summary in
                await self?.recordExecutionMetadataRead(summary, generation: run)
            }
            guard self.nativeGeneration == run, !Task.isCancelled else { return }
            await self.titleClient.setActivityNotificationHandler { [weak self] event in
                await self?.receiveClassified(.init(source: .liveSocket, activity: event), generation: run)
            }
            guard self.nativeGeneration == run, !Task.isCancelled else { return }
            await localRolloutActivityClient.setPublicContentHandler { [weak self] content in
                guard let self else { return }; await self.receiveLocalPublicContent(content, generation: run)
            }
            await localRolloutActivityClient.start(
                handler: { [weak self] record, isStartupReplay in
                    await self?.receiveLocalRecord(record, replay: isStartupReplay, generation: run)
                },
                connectionStateHandler: { _ in },
                healthHandler: { [weak self] health in
                    await self?.setLocalHealth(health, generation: run)
                }
            )
            guard self.nativeGeneration == run, !Task.isCancelled else { return }
            await sharedActivityClient.setScopedPublicMessageHandler { [weak self] data, epoch in
                guard let self else { return }
                await self.receiveScopedPublicMessage(data, connectionEpoch: epoch, generation: run)
            }
            await sharedActivityClient.start(
                handler: { [weak self] event in
                    let delivery = CodexActivityDelivery(
                        source: .liveSocket,
                        activity: event
                    )
                    await self?.receiveClassified(delivery, generation: run)
                    CodexActivityDiagnostics.record(
                        delivery: delivery,
                        outcome: "native_received"
                    )
                },
                tokenUsageHandler: { [weak self] update in
                    await self?.receiveNativeToken(update, generation: run)
                },
                connectionStateHandler: { [weak self] state in
                    await self?.setSharedConnectionState(state, generation: run)
                }
            )
            guard self.nativeGeneration == run, !Task.isCancelled else { return }
        }
    }

    private func executionMetadataPreferences(generation expected: UInt64) -> [CodexLocalExecutionMetadata.Execution] {
        guard nativeGeneration == expected else { return [] }
        return taskRegistry.executionIdentities.filter { observedActivityBySession[$0.sessionHash] != nil }.map {
            .init(sessionHash: $0.sessionHash, turnHash: $0.turnHash)
        }
    }

    private func activeExecutionMetadataPreferences(generation expected: UInt64) -> [CodexLocalExecutionMetadata.Execution] {
        guard nativeGeneration == expected else { return [] }
        return taskRegistry.executionIdentities.compactMap { identity in
            guard let turn = identity.turnHash,
                  let observed = observedActivityBySession[identity.sessionHash], observed.lifecycle == .active,
                  observed.snapshot.state != .unavailable,
                  observed.snapshot.operationKey != .sessionEnded,
                  executionMemoryTurns[identity.sessionHash] == nil else { return nil }
            let user = taskRegistry.permitsPublicAttachment(session: identity.sessionHash, turn: turn,
                source: .localRollout, occurredAt: Date())
            let child = taskRegistry.permitsSubagentAttachment(session: identity.sessionHash, turn: turn,
                source: .localRollout, occurredAt: Date())
            return user || child ? .init(sessionHash: identity.sessionHash, turnHash: turn) : nil
        }
    }

    private func recordExecutionMetadataRead(_ summary: CodexLocalRolloutActivityClient.MetadataReadSummary,
                                            generation expected: UInt64) {
        guard nativeGeneration == expected else { return }
        CodexActivityDiagnostics.recordMetadata(outcome: "execution_metadata_coverage", sessionHash: "none",
            turnHash: nil, generation: expected,
            details: "status=\(summary.status) preferred=\(summary.preferredCount) memory=\(summary.memoryCount) resolved=\(summary.resolvedCount) failed=\(summary.failedCount)")
    }

    func receiveLocalPublicContent(_ content: CodexLocalPublicContent, generation expected: UInt64? = nil) {
        let run = expected ?? nativeGeneration
        guard nativeGeneration == run else { return }
        if let payload = try? JSONSerialization.jsonObject(with: content.data) as? [String: Any],
           payload["presentationRecovery"] as? Bool == true {
            guard ["metadata", "message", "tool", "output"].contains(payload["type"] as? String ?? ""),
                  activeExecutionMetadataPreferences(generation: run).contains(where: {
                      $0.sessionHash == content.sessionHash && $0.turnHash == content.turnHash
                  }) else { return }
            if sessionKinds[content.sessionHash] == .subagent { subagentPublicContentDidReceive?(content) }
            else { localPublicContentDidReceive?(content) }
            return
        }
        if sessionKinds[content.sessionHash] == .subagent {
            guard executionMemoryTurns[content.sessionHash] == nil, isSubagentProgressContent(content.data) else { return }
            if permitsSubagentContent(session: content.sessionHash, turn: content.turnHash) {
                subagentPublicContentDidReceive?(content)
            } else if !taskRegistry.isPriorTurn(session: content.sessionHash, turn: content.turnHash) {
                bufferLocalPublicContent(content)
            }
            return
        }
        guard !isBackgroundOrInternal(content.sessionHash) else { return }
        if taskRegistry.permitsPublicAttachment(session: content.sessionHash, turn: content.turnHash,
            source: .localRollout, occurredAt: content.occurredAt, permitsTerminal: true) {
            localPublicContentDidReceive?(content)
        } else if !taskRegistry.isPriorTurn(session: content.sessionHash, turn: content.turnHash) {
            // Disk details never create a task. Retain bounded context until the
            // matching identified lifecycle receives positive current evidence.
            bufferLocalPublicContent(content)
        }
    }

    private func bufferLocalPublicContent(_ content: CodexLocalPublicContent) {
        pendingLocalPublicContent.append(content)
        while pendingLocalPublicContent.count > 200
            || pendingLocalPublicContent.reduce(0, { $0 + $1.data.count }) > 2_097_152 {
            pendingLocalPublicContent.removeFirst()
        }
    }

    private func permitsSubagentContent(session: String, turn: String, source: CodexActivityEventSource = .localRollout,
            occurredAt: Date = Date(), timeSensitive: Bool = false) -> Bool {
        sessionKinds[session] == .subagent && subagentIdentities[session] != nil && executionMemoryTurns[session] == nil
            && taskRegistry.permitsSubagentAttachment(session: session, turn: turn, source: source,
                occurredAt: occurredAt, timeSensitive: timeSensitive, permitsTerminal: true)
    }

    private func isSubagentProgressContent(_ data: Data) -> Bool {
        guard data.count <= 1_048_576,
              let content = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = content["type"] as? String else { return false }
        return ["metadata", "message", "tool", "output"].contains(type)
    }

    private func flushLocalPublicContent(for session: String) {
        if sessionKinds[session] == .subagent {
            guard executionMemoryTurns[session] == nil else {
                pendingLocalPublicContent.removeAll { $0.sessionHash == session }; return
            }
            let buffered = pendingLocalPublicContent.filter { $0.sessionHash == session }
            pendingLocalPublicContent.removeAll { $0.sessionHash == session }
            for content in buffered {
                guard isSubagentProgressContent(content.data) else { continue }
                if permitsSubagentContent(session: session, turn: content.turnHash) {
                    subagentPublicContentDidReceive?(content)
                } else if !taskRegistry.isPriorTurn(session: session, turn: content.turnHash) {
                    bufferLocalPublicContent(content)
                }
            }
            return
        }
        guard !isBackgroundOrInternal(session) else {
            pendingLocalPublicContent.removeAll { $0.sessionHash == session }
            return
        }
        let buffered = pendingLocalPublicContent.filter { $0.sessionHash == session }
        pendingLocalPublicContent.removeAll { $0.sessionHash == session }
        for content in buffered {
            if taskRegistry.permitsPublicAttachment(session: session, turn: content.turnHash,
                source: .localRollout, occurredAt: content.occurredAt, permitsTerminal: true) {
                localPublicContentDidReceive?(content)
            } else if !taskRegistry.isPriorTurn(session: session, turn: content.turnHash) {
                pendingLocalPublicContent.append(content)
            }
        }
    }

    /// The shared connection passes one scoped envelope through this ingress.
    /// Domain admission precedes every Island lifecycle/content projection.
    func receiveScopedPublicMessage(_ data: Data, connectionEpoch epoch: UInt64,
                                    generation expected: UInt64? = nil, at now: Date = Date()) async {
        let run = expected ?? nativeGeneration
        guard run == nativeGeneration, data.count <= CodexAppServerActivityNotificationDecoder.maximumMessageBytes,
              closedNativePublicEpoch.map({ epoch > $0 }) ?? true,
              nativePublicEpoch.map({ epoch >= $0 }) ?? true,
              var envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = envelope["method"] as? String, !method.contains("reasoning"), !method.contains("hook/"),
              var params = envelope["params"] as? [String: Any],
              let threadID = params["threadId"] as? String ?? (params["thread"] as? [String: Any])?["id"] as? String,
              !threadID.isEmpty else { return }
        if nativePublicEpoch != epoch {
            nativePublicEpoch = epoch; nativeWaitEvidence.removeAll(); confirmedNativeTurns.removeAll()
            pendingNativePublicMessages.removeAll()
        }
        let session = CodexActivityPrivacy.hashIdentifier(threadID)
        let turn = params["turn"] as? [String: Any]
        var turnID = params["turnId"] as? String ?? turn?["id"] as? String
        let date = Self.publicEventDate(envelope["emittedAtMs"] ?? params["emittedAtMs"], fallback: now)
        let metadata = params["thread"] as? [String: Any]
        let status = params["status"] as? [String: Any] ?? metadata?["status"] as? [String: Any]
        let metadataKind = metadata.map { CodexActivitySessionKind.classify(metadata: $0) } ?? .unknown
        if let metadata, let child = CodexActivitySubagentIdentity.decode(metadata, expectedThreadID: threadID) {
            receiveSubagentIdentity(child)
        }
        // This ingress is fed by Shared's thread-scoped, verified projection.
        // Sparse RPC/settlement envelopes inherit that user scope; explicit or
        // previously known memory/internal metadata still overrides the fallback.
        let incomingKind = metadata == nil ? CodexActivitySessionKind.user : metadataKind
        let kind = resolveSessionKind(incomingKind, session: session)
        if kind == .internalTask { return }
        if kind == .memoryConsolidation {
            await receiveMemoryPublicLifecycle(data, method: method, params: params,
                status: status, session: session, epoch: epoch, generation: run, at: now)
            return
        }
        if kind == .subagent {
            await receiveSubagentPublicMessage(data, envelope: envelope, method: method, params: params,
                status: status, session: session, epoch: epoch, generation: run, at: now)
            return
        }

        if method == "thread/snapshot", let current = params["currentTurn"] as? [String: Any],
           status?["type"] as? String == "active", current["status"] as? String == "inProgress",
           let id = current["id"] as? String, !id.isEmpty {
            turnID = id
            let hash = CodexActivityPrivacy.hashIdentifier(id)
            if taskRegistry.currentIdentity(for: session)?.turnHash != hash {
                let start = CodexActivityEvent(event: .userPromptSubmit, sessionHash: session, turnHash: hash,
                    sessionKind: kind, source: .appServer,
                    occurredAt: Self.publicEventDate(current["startedAtMs"], fallback: date))
                await receiveClassified(.init(source: .liveSocket, activity: start), generation: run,
                                        selectionEvidenceAt: date, confirmedCurrentTurn: true)
            }
        } else if let event = CodexAppServerActivityNotificationDecoder.decode(data: data, now: now) {
            await receiveClassified(.init(source: .liveSocket, activity: event.classified(as: kind)), generation: run)
        } else if let id = turnID, !id.isEmpty,
                  ((envelope["id"] != nil && ["item/commandExecution/requestApproval", "item/fileChange/requestApproval",
                    "item/permissions/requestApproval", "item/tool/requestUserInput", "mcpServer/elicitation/request"].contains(method))
                    || (method == "item/started" && ["commandExecution", "fileChange", "mcpToolCall", "dynamicToolCall",
                        "webSearch", "collabToolCall"].contains((params["item"] as? [String: Any])?["type"] as? String ?? ""))) {
            // A positively identified leading request/item can establish its own
            // turn, but output, deltas and terminal records have no such right.
            let blocking = envelope["id"] != nil && method != "item/tool/requestUserInput"
            let event = CodexActivityEvent(event: blocking ? .permissionRequest : .preToolUse,
                sessionHash: session, turnHash: CodexActivityPrivacy.hashIdentifier(id),
                sessionKind: kind, source: .appServer,
                waitReason: blocking ? .approval : nil,
                toolCallHash: (params["itemId"] as? String).map(CodexActivityPrivacy.hashIdentifier), occurredAt: date)
            await receiveClassified(.init(source: .liveSocket, activity: event), generation: run)
        }
        guard run == nativeGeneration, nativePublicEpoch == epoch,
              closedNativePublicEpoch.map({ epoch > $0 }) ?? true else { return }
        let turnHash = turnID.map(CodexActivityPrivacy.hashIdentifier)
        let isMetadata = ["thread/started", "thread/snapshot"].contains(method)
        let terminal = method == "turn/completed" || method == "serverRequest/resolved" || method == "thread/archived" || method == "thread/closed"
        let stateTransition = ["turn/started", "turn/completed", "thread/status/changed"].contains(method)
            || ((params["item"] as? [String: Any])?["type"] as? String == "contextCompaction")
        guard taskRegistry.permitsPublicAttachment(session: session, turn: turnHash,
            source: .appServer, occurredAt: date, timeSensitive: stateTransition, permitsTerminal: terminal || isMetadata),
              let identity = taskRegistry.currentIdentity(for: session) else {
            if let turnHash, !taskRegistry.isPriorTurn(session: session, turn: turnHash),
               (envelope["id"] != nil || ["item/started", "item/completed", "item/agentMessage/delta", "item/commandExecution/outputDelta", "serverRequest/resolved"].contains(method)) {
                pendingNativePublicMessages.append(.init(data: data, epoch: epoch, session: session,
                    turn: turnHash, receivedAt: now))
                while pendingNativePublicMessages.count > 200
                    || pendingNativePublicMessages.reduce(0, { $0 + $1.data.count }) > 2_097_152 {
                    pendingNativePublicMessages.removeFirst()
                }
            }
            return
        }

        // Attach thread-scoped state to the admitted current turn; never infer an
        // identified current turn from disk history or a bare active snapshot.
        if params["turnId"] == nil, let turnID { params["turnId"] = turnID }
        if method == "turn/started" || (method == "thread/snapshot" && turnID != nil
            && (params["currentTurn"] as? [String: Any])?["status"] as? String == "inProgress") {
            confirmedNativeTurns[session] = identity
            for record in localRecovery.confirm(identity) {
                guard run == nativeGeneration, nativePublicEpoch == epoch else { return }
                await applyLocalRecord(record, replay: true, generation: run, selectionEvidenceAt: date)
            }
            guard run == nativeGeneration, nativePublicEpoch == epoch,
                  taskRegistry.currentIdentity(for: session)?.turnHash == identity.turnHash else { return }
            flushLocalPublicContent(for: session)
        }
        if let status, status["type"] as? String == "active", let flags = status["activeFlags"] as? [String] {
            let reason: CodexActivityWaitReason? = flags.contains("waitingOnUserInput") ? .userInput
                : flags.contains("waitingOnApproval") ? .approval : nil
            if let reason {
                if admittedSnapshots[session]?.snapshot.state != .awaitingConfirmation {
                    let waiting = CodexActivityEvent(event: .permissionRequest, sessionHash: session,
                        turnHash: identity.turnHash, sessionKind: .user, source: .appServer,
                        waitReason: reason, occurredAt: date)
                    await receiveClassified(.init(source: .liveSocket, activity: waiting), generation: run)
                    guard run == nativeGeneration, nativePublicEpoch == epoch else { return }
                }
                nativeWaitEvidence[session] = .init(identity: identity, epoch: epoch, reason: reason)
            } else if let prior = nativeWaitEvidence.removeValue(forKey: session), prior.epoch == epoch,
                    prior.identity == identity {
                let continued = CodexActivityEvent(event: .postToolUse, sessionHash: session,
                    turnHash: identity.turnHash, sessionKind: .user, source: .appServer,
                    waitReason: prior.reason, occurredAt: date)
                await receiveClassified(.init(source: .liveSocket, activity: continued), generation: run)
                guard run == nativeGeneration, nativePublicEpoch == epoch else { return }
            }
        }
        envelope["params"] = params
        envelope["_quotaViewConnectionEpoch"] = epoch
        if let forwarded = try? JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys]) {
            publicMessageDidReceive?(forwarded)
        }
        if let update = CodexAppServerActivityNotificationDecoder.decodeTokenUsage(data: data, now: now) {
            receiveNativeToken(update, generation: run)
        }
        if method == "thread/snapshot", turnID != nil {
            let waiting = pendingNativePublicMessages.filter { $0.epoch == epoch && $0.session == session && $0.turn == identity.turnHash }
            pendingNativePublicMessages.removeAll { $0.epoch != epoch || $0.session == session }
            for message in waiting {
                guard run == nativeGeneration, nativePublicEpoch == epoch else { return }
                await receiveScopedPublicMessage(message.data, connectionEpoch: epoch, generation: run, at: message.receivedAt)
            }
        }
    }

    /// Desktop IPC has its own owner/connection scope. Its snapshot proves the
    /// current turn; it never borrows the observer App Server's RPC ownership.
    @discardableResult
    func receiveDesktopProjection(_ projection: CodexDesktopInteractionProjection,
                                  snapshot desktop: CodexDesktopConversationSnapshot,
                                  at now: Date = Date()) async -> Bool {
        let run = nativeGeneration
        let epoch = desktop.connectionEpoch
        guard desktop.conversationState.count <= CodexDesktopRequestProjector.maximumStateBytes,
              !desktop.conversationID.isEmpty, !desktop.ownerClientID.isEmpty,
              closedDesktopPublicEpoch.map({ epoch > $0 }) ?? true,
              desktopPublicEpoch.map({ epoch >= $0 }) ?? true,
              let turnID = projection.currentTurnID, !turnID.isEmpty else { return false }
        let session = CodexActivityPrivacy.hashIdentifier(desktop.conversationID)
        let kind: CodexActivitySessionKind
        if projection.sourceKind != .unknown {
            kind = projection.sourceKind
        } else if let known = sessionKinds[session], known != .unknown,
                  known != .user || taskRegistry.currentIdentity(for: session) != nil {
            // Classification cached from paused local metadata is not a live
            // Desktop attachment. Only admitted user lifecycle can supply this
            // fallback; local discovery below must still hold its follow lease.
            kind = known
        } else if let local = localDesktopFollows[session]?.identity,
                  local.threadID == desktop.conversationID, local.sessionHash == session,
                  local.sessionKind == .user {
            // Discovery verified this directory's session metadata before
            // requesting a follow. A paused rollout need not already be an
            // admitted task; only the owner supplies current-turn authority.
            // stop/directory reset and LRU withdrawal revoke this identity.
            kind = .user
        } else {
            kind = .unknown
        }
        let resolvedKind = resolveSessionKind(kind, session: session)
        if resolvedKind == .memoryConsolidation {
            return await receiveDesktopMemoryProjection(projection, snapshot: desktop, session: session, generation: run, at: now)
        }
        guard kind == .user, resolvedKind == .user else { return false }
        let turnHash = CodexActivityPrivacy.hashIdentifier(turnID)
        if let prior = desktopReceiptReservations[session]?.admission, prior.epoch == epoch,
           prior.owner == desktop.ownerClientID, desktop.revision <= prior.revision { return false }
        if desktopPublicEpoch != epoch {
            desktopPublicEpoch = epoch
            desktopAdmissions.removeAll(); desktopReceiptReservations.removeAll(); desktopWaitEvidence.removeAll()
        }
        let active = projection.status == "inProgress"
        guard active || ["completed", "interrupted", "failed"].contains(projection.status) else { return false }
        let receiptID = UUID()
        desktopReceiptReservations[session] = (receiptID, .init(owner: desktop.ownerClientID, epoch: epoch,
                                                               revision: desktop.revision, turnHash: turnHash))
        let isCurrentReceipt: () -> Bool = { [weak self] in
            guard let self else { return false }
            return nativeGeneration == run && desktopPublicEpoch == epoch
                && (closedDesktopPublicEpoch.map { epoch > $0 } ?? true)
                && desktopReceiptReservations[session]?.id == receiptID
        }
        if active, taskRegistry.currentIdentity(for: session)?.turnHash != turnHash {
            let start = CodexActivityEvent(event: .userPromptSubmit, sessionHash: session, turnHash: turnHash,
                workspaceName: projection.title, sessionKind: kind, source: .appServer,
                occurredAt: projection.startedAt ?? now)
            await receiveClassified(.init(source: .liveSocket, activity: start), generation: run,
                                    selectionEvidenceAt: now, admissionAllowed: isCurrentReceipt, confirmedCurrentTurn: true)
        }
        guard isCurrentReceipt(),
              closedDesktopPublicEpoch.map({ epoch > $0 }) ?? true,
              taskRegistry.permitsPublicAttachment(session: session, turn: turnHash,
                source: .appServer, occurredAt: now, permitsTerminal: !active),
              let identity = taskRegistry.currentIdentity(for: session), identity.turnHash == turnHash else { return false }
        desktopAdmissions[session] = .init(owner: desktop.ownerClientID, epoch: epoch,
                                          revision: desktop.revision, turnHash: turnHash)
        if active {
            // A positively identified Desktop current turn can release buffered
            // local public content through the same Registry boundary.
            confirmedNativeTurns[session] = identity
            for record in localRecovery.confirm(identity) {
                guard isCurrentReceipt() else { return false }
                await applyLocalRecord(record, replay: true, generation: run, selectionEvidenceAt: now)
            }
            guard isCurrentReceipt(), taskRegistry.currentIdentity(for: session) == identity else { return false }
            flushLocalPublicContent(for: session)
            let blockers = projection.requests.filter { $0.turnID == turnID && $0.userInputMode != .asynchronous }
            let waitReason: CodexActivityWaitReason?
            if case .waiting(let reason) = projection.threadWaitStatus {
                waitReason = reason
            } else if let blocker = blockers.first {
                waitReason = blocker.method == "item/tool/requestUserInput" ? .userInput : .approval
            } else { waitReason = nil }
            if let waitReason {
                let question = waitReason == .userInput
                let waiting = CodexActivityEvent(event: .permissionRequest, sessionHash: session,
                    turnHash: turnHash, sessionKind: kind, source: .appServer,
                    waitReason: waitReason, toolName: question ? "request_user_input" : nil, occurredAt: now)
                await receiveClassified(.init(source: .liveSocket, activity: waiting), generation: run, admissionAllowed: isCurrentReceipt)
                guard isCurrentReceipt() else { return false }
                desktopWaitEvidence[session] = .init(identity: identity, epoch: epoch, reason: waitReason)
            }
        } else {
            let event: CodexActivityHookEvent = projection.status == "interrupted" ? .interrupt : .stop
            await receiveClassified(.init(source: .liveSocket, activity: .init(event: event,
                sessionHash: session, turnHash: turnHash, sessionKind: kind,
                source: .appServer, turnCompletionStatus: projection.status == "failed" ? .failed
                    : projection.status == "interrupted" ? .interrupted : .completed,
                occurredAt: now)), generation: run, admissionAllowed: isCurrentReceipt)
            guard isCurrentReceipt() else { return false }
            desktopWaitEvidence.removeValue(forKey: session)
        }
        guard isCurrentReceipt(),
              closedDesktopPublicEpoch.map({ epoch > $0 }) ?? true,
              taskRegistry.currentIdentity(for: session) == identity else { return false }
        desktopProjectionDidReceive?(projection, desktop)
        return true
    }

    func setDesktopConnection(connected: Bool) {
        guard !connected else { return }
        if let epoch = desktopPublicEpoch { closedDesktopPublicEpoch = max(closedDesktopPublicEpoch ?? epoch, epoch) }
        desktopAdmissions.removeAll(); desktopReceiptReservations.removeAll(); desktopWaitEvidence.removeAll()
        desktopMemoryAdmissions.removeAll()
        markMemorySourceUnavailable(.appServer, onlyDesktop: true)
    }

    /// Unfollow cancels a receipt even before its first capability reaches the
    /// Island. An in-flight source classifier cannot reattach a detached scope.
    func cancelDesktopAttachment(conversationID: String) {
        let session = CodexActivityPrivacy.hashIdentifier(conversationID)
        desktopReceiptReservations.removeValue(forKey: session)
        desktopMemoryAdmissions.removeValue(forKey: session)
        markMemorySourceUnavailable(.appServer, onlyDesktop: true, sessions: [session])
    }

    /// Resource revocation cancels in-flight attachment; it is not settlement.
    func invalidateDesktopProjection(conversationID: String?, epoch: UInt64) {
        guard desktopPublicEpoch == epoch else { return }
        if let conversationID {
            let session = CodexActivityPrivacy.hashIdentifier(conversationID)
            desktopReceiptReservations.removeValue(forKey: session)
            desktopMemoryAdmissions.removeValue(forKey: session)
            markMemorySourceUnavailable(.appServer, onlyDesktop: true, sessions: [session])
        } else {
            desktopReceiptReservations.removeAll(); desktopMemoryAdmissions.removeAll()
            markMemorySourceUnavailable(.appServer, onlyDesktop: true)
        }
    }

    /// Only the owner stream's exact removal can settle Desktop wait evidence.
    func receiveDesktopRequestSettlement(sessionHash: String, turnHash: String,
                                         epoch: UInt64, stillWaiting: Bool, at now: Date = Date()) {
        guard !stillWaiting, desktopPublicEpoch == epoch,
              closedDesktopPublicEpoch.map({ epoch > $0 }) ?? true,
              let identity = taskRegistry.currentIdentity(for: sessionHash), identity.turnHash == turnHash,
              let admitted = desktopAdmissions[sessionHash], admitted.epoch == epoch,
              admitted.turnHash == turnHash,
              let entry = admittedSnapshots[sessionHash], entry.snapshot.taskIdentity == identity,
              entry.snapshot.state == .awaitingConfirmation else { return }
        if desktopWaitEvidence[sessionHash]?.identity == identity { desktopWaitEvidence.removeValue(forKey: sessionHash) }
        // Island has settled every bound request/source identity on this turn;
        // remove the duplicate observer wait only after that exact proof.
        if nativeWaitEvidence[sessionHash]?.identity == identity { nativeWaitEvidence.removeValue(forKey: sessionHash) }
        receive(.init(event: .postToolUse, sessionHash: sessionHash, turnHash: turnHash,
            sessionKind: .user, source: .appServer, occurredAt: now))
    }

    /// Request matching and remaining blockers belong to the request lifecycle.
    /// The ingress boundary only verifies its current task and connection scope.
    /// This stays synchronous so an earlier resolution cannot overtake a new
    /// blocking request within the same turn while waiting on another actor.
    func receiveRequestSettlement(_ settlement: CodexActivityRequestSettlement,
                                  at now: Date = Date()) {
        guard !settlement.stillWaiting,
              nativePublicEpoch == settlement.connectionEpoch,
              closedNativePublicEpoch.map({ settlement.connectionEpoch > $0 }) ?? true,
              let identity = taskRegistry.currentIdentity(for: settlement.sessionHash),
              identity.turnHash == settlement.turnHash,
              let entry = admittedSnapshots[settlement.sessionHash],
              entry.snapshot.taskIdentity == identity,
              entry.snapshot.state == .awaitingConfirmation else { return }
        if let wait = nativeWaitEvidence[settlement.sessionHash],
           wait.identity == identity, wait.epoch == settlement.connectionEpoch {
            nativeWaitEvidence.removeValue(forKey: settlement.sessionHash)
        }
        receive(.init(event: .postToolUse, sessionHash: identity.sessionHash,
            turnHash: identity.turnHash, sessionKind: .user, source: .appServer,
            occurredAt: now))
    }

    private static func publicEventDate(_ value: Any?, fallback: Date) -> Date {
        guard let number = value as? NSNumber, number.doubleValue.isFinite, number.doubleValue >= 0 else { return fallback }
        return Date(timeIntervalSince1970: number.doubleValue / 1_000)
    }
    private func setLocalHealth(_ health: CodexLocalActivityHealth, generation run: UInt64) {
        guard nativeGeneration == run else { return }
        if health.hasReadError || health == .disabled { compactionSourceUnavailable(.localRollout) }
        var next = automaticConnection
        next.localHealth = health
        updateAutomaticConnection(next)
    }

    func recheckLocalDiscovery() async { await localRolloutActivityClient.recheck() }

    @discardableResult
    func changeDataDirectory(_ root: URL) async -> Bool {
        let run = await stop()
        guard nativeGeneration == run, !Task.isCancelled else { return false }
        let environment = CodexActivityDirectoryEnvironment.make(root: root)
        titleClient = CodexAppServerClient(environment: environment)
        sharedActivityClient = CodexSharedAppServerActivityClient(configuration: .live(environment: environment))
        guard await localRolloutActivityClient.setDataDirectory(root),
              nativeGeneration == run, !Task.isCancelled else { return false }
        executionMetadataRoot = root.standardizedFileURL
        startNativeActivityNotifications()
        return true
    }

    func receiveLocalRecord(_ record: CodexLocalRolloutDecodedRecord, replay: Bool,
                            generation expected: UInt64? = nil) async {
        let run = expected ?? nativeGeneration
        guard nativeGeneration == run else {
            if let identity = record.threadIdentity, identity.executionTurnHash != nil {
                CodexActivityDiagnostics.recordMetadata(outcome: "execution_metadata_generation_rejected",
                    sessionHash: identity.sessionHash, turnHash: identity.executionTurnHash, generation: run)
            }
            return
        }
        if let identity = verifiedLocalRecordIdentity(record) {
            if let child = identity.subagentIdentity, identity.sessionKind == .subagent,
               child.threadID == identity.threadID, child.sessionHash == identity.sessionHash {
                receiveSubagentIdentity(child)
            }
            if let turn = identity.executionTurnHash, identity.sessionKind == .memoryConsolidation {
                // Retain an early identity until its matching lifecycle is
                // admitted. Metadata alone must not change the current turn.
                rememberExecutionMemory(session: identity.sessionHash, turn: turn, generation: run)
                let admitted = taskRegistry.executionIdentity(for: identity.sessionHash)
                if admitted?.turnHash == turn, identity.sessionKind == .memoryConsolidation,
                   sessionKinds[identity.sessionHash] != .internalTask {
                    _ = resolveExecutionMemory(session: identity.sessionHash, turn: turn)
                    removePendingExecutionMemory(session: identity.sessionHash, turn: turn)
                }
            } else { _ = resolveSessionKind(identity.sessionKind, session: identity.sessionHash) }
            if let metadata = identity.threadMetadata,
               identity.sessionKind != .internalTask, identity.sessionKind != .memoryConsolidation {
                rememberThreadMetadata(metadata, session: identity.sessionHash)
            }
        }
        if case .sessionMetadata = record.update {
            if let identity = verifiedLocalRecordIdentity(record) { publishThreadMetadata(for: identity.sessionHash) }
            return
        }
        // A bounded tail may contain a current turn_context after its start has
        // fallen outside the read window. Release only its token replay against
        // the same already admitted live execution; historical activity and
        // questions retain the existing stronger recovery gate.
        if record.requiresLiveConfirmation, case .tokenUsageReplay(let updates) = record.update,
           let local = verifiedLocalRecordIdentity(record), let first = updates.first,
           updates.allSatisfy({ $0.sessionHash == local.sessionHash && $0.turnHash == first.turnHash }),
           activeExecutionMetadataPreferences(generation: run).contains(where: {
               $0.sessionHash == local.sessionHash && $0.turnHash == first.turnHash
           }) {
            await applyLocalRecord(record, replay: true, generation: run)
            publishThreadMetadata(for: local.sessionHash)
            // This is only read-only owner discovery. Request response ability
            // still requires the independent Desktop owner/turn/epoch checks.
            publishLocalDesktopFollow(record, active: true, generation: run)
            return
        }
        let terminal: Bool
        if case .activity(let event) = record.update { terminal = [.stop, .interrupt, .sessionEnd].contains(event.event) }
        else { terminal = false }
        if !terminal { publishLocalDesktopFollow(record, active: true, generation: run) }
        guard let projection = localRecovery.project(record) else {
            if let session = Self.localRecordSession(record), let identity = confirmedNativeTurns[session],
               taskRegistry.currentIdentity(for: session)?.turnHash == identity.turnHash {
                for recovered in localRecovery.confirm(identity) {
                    await applyLocalRecord(recovered, replay: true, generation: run, selectionEvidenceAt: Date())
                }
                flushLocalPublicContent(for: session)
            }
            return
        }
        for context in projection.context {
            guard nativeGeneration == run else { return }
            await applyLocalRecord(context, replay: true, generation: run,
                                   selectionEvidenceAt: projection.confirmationTime)
        }
        guard nativeGeneration == run else { return }
        await applyLocalRecord(projection.record, replay: replay, generation: run)
        if terminal { publishLocalDesktopFollow(record, active: false, generation: run) }
        // A native snapshot may precede discovery of the paused rollout. Its
        // identified current turn also confirms context arriving in that order.
        if let session = Self.localRecordSession(record), let identity = confirmedNativeTurns[session],
           taskRegistry.currentIdentity(for: session)?.turnHash == identity.turnHash {
            for recovered in localRecovery.confirm(identity) {
                await applyLocalRecord(recovered, replay: true, generation: run, selectionEvidenceAt: Date())
            }
            flushLocalPublicContent(for: session)
        }
    }

    private func publishLocalDesktopFollow(_ record: CodexLocalRolloutDecodedRecord, active: Bool, generation run: UInt64) {
        guard nativeGeneration == run, let identity = record.threadIdentity,
              identity.sessionKind == .user, !identity.threadID.isEmpty, identity.threadID.utf8.count <= 1024,
              !isBackgroundOrInternal(identity.sessionHash),
              identity.sessionHash == CodexActivityPrivacy.hashIdentifier(identity.threadID) else { return }
        let session: String; let turn: String?
        switch record.update {
        case .activity(let event):
            guard event.source == .localRollout, event.sessionKind != .internalTask else { return }
            session = event.sessionHash; turn = event.turnHash
        case .tokenUsage(let usage): session = usage.sessionHash; turn = usage.turnHash
        case .tokenUsageReplay(let updates):
            guard let first = updates.first, updates.allSatisfy({ $0.sessionHash == first.sessionHash && $0.turnHash == first.turnHash }) else { return }
            session = first.sessionHash; turn = first.turnHash
        case .sessionMetadata: return
        }
        guard session == identity.sessionHash, let turn,
              !taskRegistry.isPriorTurn(session: session, turn: turn) else { return }
        if active {
            guard terminalTurnsBySession[session]?.turnHash != turn else { return }
            localDesktopFollows[session] = (identity, turn)
            localDesktopFollowOrder.removeAll { $0 == session }; localDesktopFollowOrder.append(session)
            while localDesktopFollowOrder.count > 100 {
                let evicted = localDesktopFollowOrder.removeFirst()
                if let previous = localDesktopFollows.removeValue(forKey: evicted) {
                    // Withdrawing a bounded read-only observation is independent
                    // of answering or completing the user's underlying task.
                    localThreadActivityDidReceive?(previous.identity, false)
                }
            }
        } else {
            // Only an admitted terminal for the current turn can withdraw this
            // intent; an older completion cannot detach a newer conversation.
            guard taskRegistry.currentIdentity(for: session)?.turnHash == turn,
                  terminalTurnsBySession[session]?.turnHash == turn else { return }
            localDesktopFollows.removeValue(forKey: session)
            localDesktopFollowOrder.removeAll { $0 == session }
        }
        localThreadActivityDidReceive?(identity, active)
    }

    private func verifiedLocalRecordIdentity(_ record: CodexLocalRolloutDecodedRecord) -> CodexLocalRolloutThreadIdentity? {
        guard let identity = record.threadIdentity, !identity.threadID.isEmpty,
              identity.threadID.utf8.count <= 1024,
              identity.sessionHash == CodexActivityPrivacy.hashIdentifier(identity.threadID) else { return nil }
        switch record.update {
        case .activity(let event): guard event.sessionHash == identity.sessionHash else { return nil }
        case .tokenUsage(let usage): guard usage.sessionHash == identity.sessionHash else { return nil }
        case .tokenUsageReplay(let updates):
            guard !updates.isEmpty, updates.allSatisfy({ $0.sessionHash == identity.sessionHash }) else { return nil }
        case .sessionMetadata: break
        }
        return identity
    }

    private static func localRecordSession(_ record: CodexLocalRolloutDecodedRecord) -> String? {
        switch record.update {
        case .activity(let event): return event.sessionHash
        case .tokenUsage(let usage): return usage.sessionHash
        case .tokenUsageReplay(let usages): return usages.first?.sessionHash
        case .sessionMetadata: return record.threadIdentity?.sessionHash
        }
    }

    private func applyLocalRecord(_ record: CodexLocalRolloutDecodedRecord, replay: Bool,
                                  generation run: UInt64, selectionEvidenceAt: Date? = nil) async {
        switch record.update {
        case .activity(let event):
            let delivery = CodexActivityDelivery(eventID: record.eventID,
                source: replay ? .startupReplay : .localRollout, activity: event)
            await receiveClassified(delivery, generation: run, selectionEvidenceAt: selectionEvidenceAt)
        case .tokenUsage(let update): receiveNativeToken(update, generation: run)
        case .tokenUsageReplay(let updates): receiveNativeTokenReplay(updates, generation: run)
        case .sessionMetadata: break
        }
    }

    private func receiveNativeTokenReplay(_ updates: [CodexActivityTokenUsageUpdate], generation run: UInt64) {
        guard run == nativeGeneration else { return }
        receiveTokenReplay(updates)
    }

    func receiveTokenReplay(_ updates: [CodexActivityTokenUsageUpdate]) {
        let before = currentTurnTokenUsage
        for update in updates { receive(update, publish: false) }
        if multitask.enabled || (currentTurnTokenUsage != before && presentation != .hidden) { notifyChange() }
    }

    private func receiveNativeToken(_ update: CodexActivityTokenUsageUpdate, generation run: UInt64) {
        guard run == nativeGeneration else { return }
        receive(update)
    }

    private func setSharedConnectionState(_ state: CodexSharedAppServerConnectionState, generation run: UInt64) {
        guard nativeGeneration == run else { return }
        if state != .connected {
            compactionSourceUnavailable(.appServer)
            if let epoch = nativePublicEpoch { closedNativePublicEpoch = max(closedNativePublicEpoch ?? epoch, epoch) }
            nativeWaitEvidence.removeAll(); confirmedNativeTurns.removeAll(); pendingNativePublicMessages.removeAll()
        }
        var next = automaticConnection
        next.sharedState = state
        updateAutomaticConnection(next)
    }

    func compactionSourceUnavailable(_ source: CodexActivityEventSource) {
        for (session, event) in lastAdmittedActivityBySession where (event.source ?? .hook) == source {
            subagentUnavailableSessions.insert(session)
        }
        subagentSourceUnavailable?(source)
        markMemorySourceUnavailable(source)
        for (session, entry) in admittedSnapshots where entry.compactionSource == source && entry.snapshot.state == .compactingContext {
            let old = entry.snapshot
            let unavailable = CodexActivitySnapshot(sessionHash: session, taskIdentity: old.taskIdentity,
                state: .unavailable, workspaceName: old.workspaceName, operationKey: .bridgeUnavailable,
                toolCategory: old.toolCategory, approximateProgressFraction: old.approximateProgressFraction,
                occurredAt: old.occurredAt)
            admittedSnapshots[session] = .init(id: 0, snapshot: unavailable, lifecycle: .unconfirmed, compactionSource: nil)
            multitask.receive(unavailable, lifecycle: .unconfirmed, compactionSource: nil,
                              now: ProcessInfo.processInfo.systemUptime, permitsNewEntry: false)
        }
        if multitask.enabled { notifyChange() }
        guard selectedCompactionSource == source, let current = snapshot,
              current.state == .compactingContext else { return }
        // Losing the start source is not evidence that compaction finished.
        // Preserve identity and counters until a real continuation or end arrives.
        snapshot = CodexActivitySnapshot(
            sessionHash: current.sessionHash, taskIdentity: current.taskIdentity,
            state: .unavailable, workspaceName: current.workspaceName,
            operationKey: .bridgeUnavailable, toolCategory: current.toolCategory,
            approximateProgressFraction: current.approximateProgressFraction,
            occurredAt: current.occurredAt
        )
        lifecycle = .unconfirmed
        notifyChange()
    }

    private func updateAutomaticConnection(_ value: CodexAutomaticActivityConnection) {
        guard automaticConnection != value else { return }
        automaticConnection = value
        automaticConnectionDidChange?(value)
    }

    private func isBackgroundOrInternal(_ session: String) -> Bool {
        let kind = sessionKinds[session]
        return kind == .memoryConsolidation || kind == .subagent || kind == .internalTask || executionMemoryTurns[session] != nil
    }

    private func receiveSubagentIdentity(_ identity: CodexActivitySubagentIdentity) {
        if let previous = subagentIdentities[identity.sessionHash],
           previous.parentSessionHash != identity.parentSessionHash {
            CodexActivityDiagnostics.recordMetadata(outcome: "subagent_parent_relation_rejected",
                sessionHash: identity.sessionHash, turnHash: nil, generation: nativeGeneration)
            return
        }
        subagentIdentities[identity.sessionHash] = identity
        let resolved = resolveSessionKind(.subagent, session: identity.sessionHash, verifiedChild: true)
        guard resolved == .subagent else { subagentIdentities.removeValue(forKey: identity.sessionHash); return }
        subagentIdentities = subagentIdentities.filter { sessionKinds[$0.key] == .subagent }
        guard executionMemoryTurns[identity.sessionHash] == nil else { return }
        subagentIdentityDidReceive?(identity)
        // A relation can arrive after its current lifecycle; replay this admitted
        // read-only state through the child channel without creating a new turn.
        if !subagentUnavailableSessions.contains(identity.sessionHash),
           let event = lastAdmittedActivityBySession[identity.sessionHash],
           let current = taskRegistry.executionIdentity(for: identity.sessionHash),
           event.turnHash == nil || event.turnHash == current.turnHash {
            if let start = admittedTurnStartBySession[identity.sessionHash], start.turnHash == current.turnHash, start != event {
                subagentActivityDidReceive?(start.classified(as: .subagent))
            }
            subagentActivityDidReceive?(event.classified(as: .subagent))
        }
    }

    private func rememberExecutionMemory(session: String, turn: String, generation: UInt64) {
        guard generation == nativeGeneration, sessionKinds[session] != .internalTask,
              !taskRegistry.isPriorTurn(session: session, turn: turn) else {
            CodexActivityDiagnostics.recordMetadata(outcome: "execution_metadata_scope_rejected",
                sessionHash: session, turnHash: turn, generation: generation)
            return
        }
        prunePendingExecutionMemory()
        let key = ExecutionMemoryKey(session: session, turn: turn)
        pendingExecutionMemory[key] = .init(generation: generation, receivedAt: ProcessInfo.processInfo.systemUptime)
        pendingExecutionMemoryOrder.removeAll { $0 == key }
        pendingExecutionMemoryOrder.append(key)
        CodexActivityDiagnostics.recordMetadata(outcome: "execution_metadata_pending",
            sessionHash: session, turnHash: turn, generation: generation)
        while pendingExecutionMemoryOrder.count > Self.maximumPendingExecutionMemory {
            pendingExecutionMemory.removeValue(forKey: pendingExecutionMemoryOrder.removeFirst())
        }
    }

    private func prunePendingExecutionMemory() {
        let now = ProcessInfo.processInfo.systemUptime
        pendingExecutionMemory = pendingExecutionMemory.filter { key, evidence in
            evidence.generation == nativeGeneration
                && now - evidence.receivedAt <= Self.pendingExecutionMemoryLifetime
                && !taskRegistry.isPriorTurn(session: key.session, turn: key.turn)
        }
        pendingExecutionMemoryOrder.removeAll { pendingExecutionMemory[$0] == nil }
    }

    private func removePendingExecutionMemory(session: String, turn: String? = nil) {
        pendingExecutionMemory = pendingExecutionMemory.filter { key, _ in
            key.session != session || (turn != nil && key.turn != turn)
        }
        pendingExecutionMemoryOrder.removeAll { pendingExecutionMemory[$0] == nil }
    }

    /// Late authoritative metadata changes presentation, never execution state.
    @discardableResult
    private func resolveSessionKind(_ incoming: CodexActivitySessionKind,
                                    session: String, verifiedChild: Bool = false) -> CodexActivitySessionKind {
        let known = sessionKinds[session] ?? .unknown
        let resolved = verifiedChild && incoming == .subagent && known != .memoryConsolidation ? .subagent
            : incoming == .internalTask ? .internalTask : CodexActivitySessionKind.resolving(known, incoming)
        guard resolved != .unknown else { return resolved }
        rememberSessionKind(resolved, session: session)
        if executionMemoryTurns[session] != nil, resolved != .internalTask {
            // Origin metadata may change while the current execution remains a
            // proved memory turn. Preserve that execution and its background row.
            taskRegistry.reclassifyExecution(session: session, kind: .memoryConsolidation)
        } else if verifiedChild, resolved == .subagent { taskRegistry.reclassifyExecution(session: session, kind: resolved) }
        else { _ = taskRegistry.reclassify(session: session, kind: resolved) }
        guard known != resolved else { return resolved }
        // The Island withdraws a generic record before any subsequent callback.
        activitySessionKindDidResolve?(session, resolved)
        if resolved == .internalTask { subagentIdentities.removeValue(forKey: session) }
        if resolved == .subagent, executionMemoryTurns[session] != nil { return resolved }
        guard resolved == .memoryConsolidation || resolved == .subagent || resolved == .internalTask else { return resolved }
        withdrawUserPresentation(session: session, resolved: resolved)
        return resolved
    }

    @discardableResult
    private func resolveExecutionMemory(session: String, turn: String) -> CodexActivitySessionKind {
        guard executionMemoryTurns[session] != turn else { return .memoryConsolidation }
        executionMemoryTurns[session] = turn
        CodexActivityDiagnostics.recordMetadata(outcome: "execution_metadata_applied",
            sessionHash: session, turnHash: turn, generation: nativeGeneration)
        taskRegistry.reclassifyExecution(session: session, kind: .memoryConsolidation)
        activityExecutionKindDidResolve?(session, .memoryConsolidation)
        withdrawUserPresentation(session: session, resolved: .memoryConsolidation)
        return .memoryConsolidation
    }

    private func withdrawUserPresentation(session: String, resolved: CodexActivitySessionKind) {
        admittedSnapshots.removeValue(forKey: session)
        multitask.remove(session, now: ProcessInfo.processInfo.systemUptime)
        multitaskTitleTasks.removeValue(forKey: session)?.cancel()
        titleCache.removeValue(forKey: session); titleCacheSources.removeValue(forKey: session)
        titleAttemptedAt.removeValue(forKey: session)
        nativeWaitEvidence.removeValue(forKey: session); desktopWaitEvidence.removeValue(forKey: session)
        confirmedNativeTurns.removeValue(forKey: session)
        desktopAdmissions.removeValue(forKey: session); desktopReceiptReservations.removeValue(forKey: session)
        pendingNativePublicMessages.removeAll { $0.session == session }
        pendingLocalPublicContent.removeAll { $0.sessionHash == session }
        localRecovery.forget(session: session)
        if let oldFollow = localDesktopFollows.removeValue(forKey: session) {
            localDesktopFollowOrder.removeAll { $0 == session }
            localThreadActivityDidReceive?(oldFollow.identity, false)
        }
        if snapshot?.sessionHash == session {
            revision &+= 1
            inactivityTask?.cancel(); titleTask?.cancel()
            titleTask = nil; titleTaskSessionHash = nil
            snapshot = nil; lifecycle = .idle; presentation = .hidden
            resolvedThreadTitle = nil; selectedActivityAt = nil; selectedCompactionSource = nil
            resetConfirmationReminder()
        }
        if resolved == .memoryConsolidation,
           let observed = observedActivityBySession[session], observed.snapshot.operationKey != .sessionEnded {
            memoryActivityBySession[session] = observed
        } else {
            memoryActivityBySession.removeValue(forKey: session)
        }
        publishMemorySnapshots()
        notifyChange()
    }

    /// Metadata-only threads need no lifecycle slot. Keep bounded identities,
    /// protecting all admitted observations until Registry explicitly evicts them.
    private func rememberSessionKind(_ kind: CodexActivitySessionKind, session: String) {
        sessionKinds[session] = kind
        sessionKindOrder.removeAll { $0 == session }; sessionKindOrder.append(session)
        while sessionKinds.count > Self.maximumRememberedSessionKinds,
              let oldest = sessionKindOrder.first(where: { $0 != session && observedActivityBySession[$0] == nil }) {
            forgetSessionOrigin(oldest)
        }
    }

    private func boundDesktopMemoryAdmissions(keeping session: String) {
        while desktopMemoryAdmissions.count > 128,
              let oldest = desktopMemoryAdmissions.keys.filter({ $0 != session }).min(by: {
                  let firstUnadmitted = taskRegistry.backgroundIdentity(for: $0) == nil
                  let secondUnadmitted = taskRegistry.backgroundIdentity(for: $1) == nil
                  if firstUnadmitted != secondUnadmitted { return firstUnadmitted }
                  return $0 < $1
              }) {
            desktopMemoryAdmissions.removeValue(forKey: oldest)
        }
    }

    private func publishMemorySnapshots() {
        backgroundMemorySnapshots = memoryActivityBySession.values.map(\.snapshot).sorted {
            if $0.occurredAt == $1.occurredAt { return $0.sessionHash < $1.sessionHash }
            return $0.occurredAt > $1.occurredAt
        }
    }

    /// A lost source is uncertainty, not a completed turn. A genuine later
    /// lifecycle event can resume or settle the same identity.
    private func markMemorySourceUnavailable(_ source: CodexActivityEventSource, onlyDesktop: Bool = false,
                                             sessions: Set<String>? = nil) {
        var changed = false
        for (session, entry) in memoryActivityBySession where entry.source == source && entry.lifecycle == .active
            && entry.isDesktopObservation == onlyDesktop && (sessions?.contains(session) ?? true) {
            let old = entry.snapshot
            let unavailable = CodexActivitySnapshot(sessionHash: session, taskIdentity: old.taskIdentity,
                state: .unavailable, workspaceName: old.workspaceName, operationKey: .bridgeUnavailable,
                toolCategory: old.toolCategory, approximateProgressFraction: old.approximateProgressFraction,
                occurredAt: old.occurredAt)
            var uncertain = ObservedActivity(snapshot: unavailable, lifecycle: .unconfirmed, source: source)
            uncertain.isDesktopObservation = onlyDesktop
            uncertain.snapshotBeforeSourceLoss = old
            memoryActivityBySession[session] = uncertain
            observedActivityBySession[session] = uncertain
            changed = true
        }
        if changed { publishMemorySnapshots(); notifyChange() }
    }

    private func restoreMemoryObservation(session: String, turnHash: String, desktop: Bool) {
        guard taskRegistry.backgroundIdentity(for: session)?.turnHash == turnHash,
              let uncertain = memoryActivityBySession[session], uncertain.lifecycle == .unconfirmed,
              let confirmed = uncertain.snapshotBeforeSourceLoss else { return }
        var restored = ObservedActivity(snapshot: confirmed, lifecycle: .active, source: .appServer)
        restored.isDesktopObservation = desktop
        memoryActivityBySession[session] = restored; observedActivityBySession[session] = restored
        publishMemorySnapshots(); notifyChange()
    }

    private func noteMemoryNativeObservation(session: String, turnHash: String, desktop: Bool) {
        guard taskRegistry.backgroundIdentity(for: session)?.turnHash == turnHash,
              var observed = memoryActivityBySession[session], observed.lifecycle == .active else { return }
        observed.source = .appServer
        observed.isDesktopObservation = desktop
        memoryActivityBySession[session] = observed; observedActivityBySession[session] = observed
    }

    private func clearMemoryWait(session: String, turnHash: String, at now: Date) {
        guard taskRegistry.backgroundIdentity(for: session)?.turnHash == turnHash,
              let previous = memoryActivityBySession[session], previous.lifecycle == .active,
              previous.snapshot.state == .awaitingConfirmation else { return }
        let old = previous.snapshot
        let running = CodexActivitySnapshot(sessionHash: session, taskIdentity: old.taskIdentity,
            state: .thinking, workspaceName: old.workspaceName, operationKey: .analyzingRequest,
            toolCategory: old.toolCategory, approximateProgressFraction: old.approximateProgressFraction,
            occurredAt: max(old.occurredAt, now))
        var observed = ObservedActivity(snapshot: running, lifecycle: .active, source: previous.source)
        observed.isDesktopObservation = previous.isDesktopObservation
        memoryActivityBySession[session] = observed; observedActivityBySession[session] = observed
        publishMemorySnapshots(); notifyChange()
    }

    /// Desktop current-turn observation can update background lifecycle while
    /// remaining separate from every user request admission and owner callback.
    private func receiveDesktopMemoryProjection(_ projection: CodexDesktopInteractionProjection,
        snapshot desktop: CodexDesktopConversationSnapshot, session: String, generation run: UInt64, at now: Date) async -> Bool {
        guard let turnID = projection.currentTurnID,
              ["inProgress", "completed", "interrupted", "failed"].contains(projection.status) else { return false }
        let epoch = desktop.connectionEpoch, turnHash = CodexActivityPrivacy.hashIdentifier(turnID)
        let active = projection.status == "inProgress"
        // A terminal snapshot cannot establish another task or consume receipt capacity.
        if !active, taskRegistry.backgroundIdentity(for: session)?.turnHash != turnHash { return false }
        if let prior = desktopMemoryAdmissions[session], prior.epoch == epoch,
           prior.owner == desktop.ownerClientID, desktop.revision <= prior.revision { return false }
        if desktopPublicEpoch != epoch {
            desktopPublicEpoch = epoch
            desktopAdmissions.removeAll(); desktopReceiptReservations.removeAll(); desktopWaitEvidence.removeAll()
            desktopMemoryAdmissions.removeAll()
        }
        let receipt = DesktopAdmission(owner: desktop.ownerClientID, epoch: epoch,
                                       revision: desktop.revision, turnHash: turnHash)
        desktopMemoryAdmissions[session] = receipt
        boundDesktopMemoryAdmissions(keeping: session)
        var accepted = false
        defer {
            if !accepted, desktopMemoryAdmissions[session]?.revision == receipt.revision,
               desktopMemoryAdmissions[session]?.owner == receipt.owner,
               desktopMemoryAdmissions[session]?.epoch == receipt.epoch {
                desktopMemoryAdmissions.removeValue(forKey: session)
            }
        }
        let valid: () -> Bool = { [weak self] in
            guard let self else { return false }
            return nativeGeneration == run && desktopPublicEpoch == epoch
                && (closedDesktopPublicEpoch.map { epoch > $0 } ?? true)
                && desktopMemoryAdmissions[session]?.revision == desktop.revision
                && desktopMemoryAdmissions[session]?.owner == desktop.ownerClientID
        }
        if active, taskRegistry.backgroundIdentity(for: session)?.turnHash != turnHash {
            let start = CodexActivityEvent(event: .userPromptSubmit, sessionHash: session, turnHash: turnHash,
                sessionKind: .memoryConsolidation, source: .appServer, occurredAt: projection.startedAt ?? now)
            await receiveClassified(.init(source: .liveSocket, activity: start), generation: run,
                admissionAllowed: valid, confirmedCurrentTurn: true)
        } else if !active {
            let completion: CodexActivityTurnCompletionStatus = projection.status == "failed" ? .failed
                : projection.status == "interrupted" ? .interrupted : .completed
            let event = CodexActivityEvent(event: completion == .interrupted ? .interrupt : .stop,
                sessionHash: session, turnHash: turnHash, sessionKind: .memoryConsolidation, source: .appServer,
                turnCompletionStatus: completion, occurredAt: now)
            await receiveClassified(.init(source: .liveSocket, activity: event), generation: run, admissionAllowed: valid)
        }
        guard valid(), taskRegistry.backgroundIdentity(for: session)?.turnHash == turnHash else { return false }
        if active { restoreMemoryObservation(session: session, turnHash: turnHash, desktop: true) }
        guard var observed = memoryActivityBySession[session] else { return false }
        observed.source = .appServer
        observed.isDesktopObservation = true
        memoryActivityBySession[session] = observed; observedActivityBySession[session] = observed
        if active, projection.threadWaitStatus == .running {
            clearMemoryWait(session: session, turnHash: turnHash, at: now)
        }
        accepted = true
        return true // Accepted observation; no user request/owner callback was issued.
    }

    private func receiveSubagentPublicMessage(_ data: Data, envelope: [String: Any], method: String,
            params: [String: Any], status: [String: Any]?, session: String,
            epoch: UInt64, generation run: UInt64, at now: Date) async {
        let allowed = ["thread/started", "thread/snapshot", "thread/status/changed", "turn/started", "turn/completed",
            "item/started", "item/completed", "item/agentMessage/delta", "item/commandExecution/outputDelta"]
        guard envelope["id"] == nil, allowed.contains(method), subagentIdentities[session] != nil else { return }
        if let item = params["item"] as? [String: Any],
           ["reasoning", "userMessage"].contains(item["type"] as? String ?? "") { return }
        let current = params["currentTurn"] as? [String: Any]
        let turn = params["turn"] as? [String: Any]
        let turnID = params["turnId"] as? String ?? turn?["id"] as? String ?? current?["id"] as? String
        guard let turnID, !turnID.isEmpty else { return }
        let hash = CodexActivityPrivacy.hashIdentifier(turnID)
        if method == "thread/snapshot", status?["type"] as? String == "active",
           current?["status"] as? String == "inProgress", taskRegistry.executionIdentity(for: session)?.turnHash != hash {
            let start = CodexActivityEvent(event: .userPromptSubmit, sessionHash: session, turnHash: hash,
                sessionKind: .subagent, source: .appServer,
                occurredAt: Self.publicEventDate(current?["startedAtMs"], fallback: now))
            await receiveClassified(.init(source: .liveSocket, activity: start), generation: run,
                                    selectionEvidenceAt: now, confirmedCurrentTurn: true)
        } else if method == "thread/snapshot", let raw = current?["status"] as? String,
                  let completion = CodexActivityTurnCompletionStatus(rawValue: raw) {
            let ended = CodexActivityEvent(event: completion == .interrupted ? .interrupt : .stop,
                sessionHash: session, turnHash: hash, sessionKind: .subagent, source: .appServer,
                turnCompletionStatus: completion,
                occurredAt: Self.publicEventDate(current?["completedAtMs"], fallback: now))
            await receiveClassified(.init(source: .liveSocket, activity: ended), generation: run)
        } else if let event = CodexAppServerActivityNotificationDecoder.decode(data: data, now: now) {
            await receiveClassified(.init(source: .liveSocket, activity: event.classified(as: .subagent)), generation: run)
        }
        guard run == nativeGeneration, nativePublicEpoch == epoch,
              closedNativePublicEpoch.map({ epoch > $0 }) ?? true,
              permitsSubagentContent(session: session, turn: hash, source: .appServer,
                occurredAt: now, timeSensitive: ["turn/started", "turn/completed", "thread/status/changed"].contains(method)) else { return }
        var forwarded = envelope
        forwarded["_quotaViewConnectionEpoch"] = epoch
        if let bytes = try? JSONSerialization.data(withJSONObject: forwarded, options: [.sortedKeys]) {
            subagentPublicMessageDidReceive?(bytes)
        }
    }

    private func receiveMemoryPublicLifecycle(_ data: Data, method: String, params: [String: Any],
        status: [String: Any]?, session: String, epoch: UInt64, generation run: UInt64, at now: Date) async {
        guard run == nativeGeneration, nativePublicEpoch == epoch,
              closedNativePublicEpoch.map({ epoch > $0 }) ?? true else { return }
        if method == "thread/snapshot", let current = params["currentTurn"] as? [String: Any],
           let id = current["id"] as? String, !id.isEmpty {
            let turnHash = CodexActivityPrivacy.hashIdentifier(id)
            if current["status"] as? String == "inProgress", status?["type"] as? String == "active" {
                if taskRegistry.backgroundIdentity(for: session)?.turnHash != turnHash {
                    let start = CodexActivityEvent(event: .userPromptSubmit, sessionHash: session,
                        turnHash: turnHash, sessionKind: .memoryConsolidation, source: .appServer,
                        occurredAt: Self.publicEventDate(current["startedAtMs"], fallback: now))
                    await receiveClassified(.init(source: .liveSocket, activity: start), generation: run,
                        confirmedCurrentTurn: true)
                }
                guard run == nativeGeneration, nativePublicEpoch == epoch,
                      closedNativePublicEpoch.map({ epoch > $0 }) ?? true else { return }
                restoreMemoryObservation(session: session, turnHash: turnHash, desktop: false)
                noteMemoryNativeObservation(session: session, turnHash: turnHash, desktop: false)
                if let flags = status?["activeFlags"] as? [String], flags.isEmpty {
                    clearMemoryWait(session: session, turnHash: turnHash, at: now)
                }
            } else if let raw = current["status"] as? String,
                      let completion = CodexActivityTurnCompletionStatus(rawValue: raw) {
                let ended = CodexActivityEvent(event: completion == .interrupted ? .interrupt : .stop,
                    sessionHash: session, turnHash: turnHash, sessionKind: .memoryConsolidation,
                    source: .appServer, turnCompletionStatus: completion,
                    occurredAt: Self.publicEventDate(current["completedAtMs"], fallback: now))
                await receiveClassified(.init(source: .liveSocket, activity: ended), generation: run)
            }
        } else if let event = CodexAppServerActivityNotificationDecoder.decode(data: data, now: now) {
            await receiveClassified(.init(source: .liveSocket,
                activity: event.classified(as: .memoryConsolidation)), generation: run)
        }
        // Metadata or background lifecycle never grants question/RPC ownership.
    }

    func receiveClassified(_ delivery: CodexActivityDelivery, generation expected: UInt64? = nil,
                           selectionEvidenceAt: Date? = nil, admissionAllowed: (() -> Bool)? = nil,
                           confirmedCurrentTurn: Bool = false) async {
        let run = expected ?? nativeGeneration
        let classifier = delivery.activity.source == .hook ? hookSessionClassifier : sessionClassifier
        let classification: CodexActivitySessionClassification
        if let sessionKindResolver { classification = .init(kind: await sessionKindResolver(delivery.activity)) }
        else { classification = await classifier.classification(for: delivery.activity) }
        guard run == nativeGeneration, admissionAllowed?() ?? true else { return }
        let before = snapshot
        receive(CodexActivityDelivery(eventID: delivery.eventID, source: delivery.source,
                                      activity: delivery.activity.classified(as: classification.kind)),
                selectionEvidenceAt: selectionEvidenceAt, confirmedCurrentTurn: confirmedCurrentTurn,
                executionMemoryTurnHash: classification.executionTurnHash)
        CodexActivityDiagnostics.record(delivery: delivery,
            outcome: before != snapshot ? "task_applied" : "task_ignored")
    }

    func receive(_ event: CodexActivityEvent) {
        receive(
            CodexActivityDelivery(
                source: .liveSocket,
                activity: event
            )
        )
    }

    func receive(_ delivery: CodexActivityDelivery, selectionEvidenceAt: Date? = nil, confirmedCurrentTurn: Bool = false,
                 executionMemoryTurnHash: String? = nil) {
        let event = delivery.activity
        var knownGoalStatus = event.goalStatus
            ?? goalStatusBySession[event.sessionHash]
        guard CodexActivityReducer.snapshot(
            for: event,
            activeGoalStatus: knownGoalStatus
        ) != nil
        else {
            return
        }

        let baseKind = resolveSessionKind(executionMemoryTurnHash == nil ? event.sessionKind ?? .unknown : .unknown,
                                          session: event.sessionHash)
        prunePendingExecutionMemory()
        let pendingTurn = event.turnHash.flatMap { turn in
            pendingExecutionMemory[.init(session: event.sessionHash, turn: turn)] != nil ? turn : nil
        }
        var resolvedKind = baseKind
        var executionMemoryToAdmit: String?
        var revokesExecutionMemory = false
        if baseKind != .memoryConsolidation && baseKind != .internalTask {
            if let turn = executionMemoryTurnHash ?? pendingTurn, turn == event.turnHash,
               !taskRegistry.isPriorTurn(session: event.sessionHash, turn: turn) {
                resolvedKind = .memoryConsolidation
                executionMemoryToAdmit = turn
            } else if let turn = executionMemoryTurns[event.sessionHash] {
                // Sparse tool/session events inherit the already admitted
                // execution; a missing turn ID cannot revoke its background kind.
                if event.turnHash == turn || (event.turnHash == nil
                    && taskRegistry.executionIdentity(for: event.sessionHash)?.turnHash == turn) {
                    resolvedKind = .memoryConsolidation
                }
                else if let nextTurn = event.turnHash,
                        [.userPromptSubmit, .preToolUse, .permissionRequest].contains(event.event),
                        !taskRegistry.isPriorTurn(session: event.sessionHash, turn: nextTurn) {
                    revokesExecutionMemory = true
                }
            }
        }
        if let id = delivery.eventID, acceptedEventIDs.contains(id) { return }
        // Execution classification and admission commit together. Rejected old
        // clocks/turns cannot remove the current card before Registry rejects them.
        var admittingRegistry = taskRegistry
        if executionMemoryToAdmit != nil || revokesExecutionMemory {
            admittingRegistry.reclassifyExecution(session: event.sessionHash, kind: resolvedKind)
        }
        guard let admission = admittingRegistry.admit(event, kind: resolvedKind,
                                                selectedSession: snapshot?.sessionHash,
                                                selectedOccurredAt: selectedActivityAt ?? snapshot?.occurredAt,
                                                selectionEvidenceAt: selectionEvidenceAt,
                                                confirmedCurrentTurn: confirmedCurrentTurn) else { return }
        taskRegistry = admittingRegistry
        lastAdmittedActivityBySession[event.sessionHash] = event
        if admission.startsTurn { admittedTurnStartBySession[event.sessionHash] = event }
        subagentUnavailableSessions.remove(event.sessionHash)
        if let turn = executionMemoryToAdmit {
            _ = resolveExecutionMemory(session: event.sessionHash, turn: turn)
            removePendingExecutionMemory(session: event.sessionHash, turn: turn)
        }
        else if revokesExecutionMemory {
            executionMemoryTurns.removeValue(forKey: event.sessionHash)
            memoryActivityBySession.removeValue(forKey: event.sessionHash)
            activityExecutionKindDidResolve?(event.sessionHash, .user)
            publishMemorySnapshots()
        }
        if resolvedKind == .subagent {
            if let child = subagentIdentities[event.sessionHash] {
                subagentIdentityDidReceive?(child)
                subagentActivityDidReceive?(event)
            }
            flushLocalPublicContent(for: event.sessionHash)
        } else if resolvedKind != .memoryConsolidation {
            admittedActivityDidReceive?(event)
            flushLocalPublicContent(for: event.sessionHash)
        }
        publishThreadMetadata(for: event.sessionHash)
        _ = registerEventID(delivery.eventID)
        for session in admission.evictedSessions { discardSession(session, preservingChildOrigin: true) }
        if resolvedKind != .unknown, executionMemoryTurns[event.sessionHash] == nil {
            sessionKinds[event.sessionHash] = resolvedKind
        }
        if admission.startsTurn {
            // Only accepted new-turn evidence retires identities known to be
            // previous turns. A rejected clock or a future early identity stays inert.
            prunePendingExecutionMemory()
            planProgressBySession.removeValue(forKey: event.sessionHash)
            goalStatusBySession.removeValue(forKey: event.sessionHash)
            terminalTurnsBySession.removeValue(forKey: event.sessionHash)
        }
        // Transport duplicates cannot wake a task. Explicit fresh confirmation of
        // recovered context may reselect an existing turn without resetting its usage.
        let confirmsRecoveredTask = selectionEvidenceAt != nil && admission.selectsTask
            && snapshot?.sessionHash != event.sessionHash
        if admission.duplicateStart && !confirmsRecoveredTask { return }
        latestEventAtBySession[event.sessionHash] = event.occurredAt
        if let goalStatus = event.goalStatus {
            goalStatusBySession[event.sessionHash] = goalStatus
        }
        if admission.startsTurn { knownGoalStatus = event.goalStatus }
        synchronizeTokenTurn(for: event)
        var nextLifecycle = resolvedKind == .memoryConsolidation
            ? (memoryActivityBySession[event.sessionHash]?.lifecycle ?? .idle)
            : resolvedKind == .subagent ? (observedActivityBySession[event.sessionHash]?.lifecycle ?? .idle) : lifecycle

        switch event.event {
        case .userPromptSubmit:
            terminalTurnsBySession.removeValue(forKey: event.sessionHash)
            nextLifecycle = .active
        case .sessionStart:
            if event.sessionStartSource != .compact {
                terminalTurnsBySession.removeValue(
                    forKey: event.sessionHash
                )
                nextLifecycle = .idle
            } else {
                nextLifecycle = .active
            }
        case .sessionEnd:
            terminalTurnsBySession[event.sessionHash] = TerminalTurn(
                turnHash: event.turnHash
            )
            nextLifecycle = .idle
            goalStatusBySession.removeValue(forKey: event.sessionHash)
        case .interrupt:
            terminalTurnsBySession[event.sessionHash] = TerminalTurn(
                turnHash: event.turnHash
            )
            nextLifecycle = .idle
        case .stop:
            terminalTurnsBySession[event.sessionHash] = TerminalTurn(
                turnHash: event.turnHash
            )
            nextLifecycle = event.turnCompletionStatus == .failed
                || event.turnCompletionStatus == .interrupted
                || (knownGoalStatus != nil && knownGoalStatus != .complete)
                ? .idle
                : .completed
        case .preToolUse, .permissionRequest, .preCompact,
             .subagentStart:
            // Some Codex hosts do not emit UserPromptSubmit before the first
            // activity of a new turn. A leading activity is still conclusive
            // evidence of a new turn after the terminal guard has rejected
            // any same-turn late event.
            terminalTurnsBySession.removeValue(forKey: event.sessionHash)
            nextLifecycle = .active
        case .postToolUse:
            nextLifecycle = event.goalStatus != nil
                && event.goalStatus != .active
                && event.goalStatus != .complete
                ? .idle : .active
        case .postCompact, .subagentStop:
            nextLifecycle = .active
        }

        let approximateProgress = admission.duplicateStart
            ? planProgressBySession[event.sessionHash]?.fraction
            : approximateProgress(for: event, activeGoalStatus: knownGoalStatus)
        guard let nextSnapshot = CodexActivityReducer.snapshot(
            for: event,
            approximateProgressFraction: approximateProgress,
            activeGoalStatus: knownGoalStatus
        ) else {
            return
        }

        let pendingWait = resolvedKind != .memoryConsolidation && resolvedKind != .subagent && nextLifecycle == .active
            ? (desktopWaitEvidence[event.sessionHash].flatMap { $0.identity == admission.identity ? $0.reason : nil }
                ?? nativeWaitEvidence[event.sessionHash].flatMap { $0.identity == admission.identity ? $0.reason : nil })
            : nil
        let identifiedSnapshot = CodexActivitySnapshot(
            sessionHash: nextSnapshot.sessionHash, taskIdentity: admission.identity,
            state: pendingWait == nil ? nextSnapshot.state : .awaitingConfirmation, workspaceName: nextSnapshot.workspaceName,
            operationKey: pendingWait == nil ? nextSnapshot.operationKey
                : pendingWait == .userInput ? .awaitingUserInput : .awaitingApproval,
            toolCategory: nextSnapshot.toolCategory,
            approximateProgressFraction: nextSnapshot.approximateProgressFraction,
            occurredAt: nextSnapshot.occurredAt
        )
        var observed = ObservedActivity(snapshot: identifiedSnapshot, lifecycle: nextLifecycle,
            source: event.source ?? .hook)
        if resolvedKind == .memoryConsolidation,
           let previous = memoryActivityBySession[event.sessionHash],
           previous.snapshot.taskIdentity == admission.identity, previous.lifecycle == .active,
           observed.source == .hook, previous.source != .hook {
            // Hook tool detail supplements an identified native/rollout observer;
            // it does not replace the source whose disconnect revokes live proof.
            observed.source = previous.source
            observed.isDesktopObservation = previous.isDesktopObservation
        }
        observedActivityBySession[event.sessionHash] = observed
        if resolvedKind == .subagent { notifyChange(); return }
        if resolvedKind == .memoryConsolidation {
            if event.event == .sessionEnd {
                memoryActivityBySession.removeValue(forKey: event.sessionHash)
            } else {
                memoryActivityBySession[event.sessionHash] = observed
            }
            publishMemorySnapshots()
            notifyChange()
            return
        }
        let source: CodexActivityEventSource? = identifiedSnapshot.state == .compactingContext ? event.source : nil
        let eligible = !isStaleSettledContinuationEvent(delivery) || selectionEvidenceAt != nil
        if resolvedKind == .user {
            let admittedLifecycle: CodexActivityTurnLifecycle = eligible ? nextLifecycle : .unconfirmed
            admittedSnapshots[event.sessionHash] = .init(id: 0, snapshot: identifiedSnapshot,
                lifecycle: admittedLifecycle, compactionSource: source)
            multitask.receive(identifiedSnapshot, lifecycle: admittedLifecycle, compactionSource: source,
                              now: ProcessInfo.processInfo.systemUptime, permitsNewEntry: eligible)
        }
        // Single-island selection and timers retain their existing behavior.
        guard admission.selectsTask else {
            if multitask.enabled { notifyChange() }
            return
        }
        selectedActivityAt = max(selectedActivityAt ?? .distantPast, selectionEvidenceAt ?? event.occurredAt)
        selectedCompactionSource = source
        lifecycle = nextLifecycle
        revision &+= 1
        let eventRevision = revision
        inactivityTask?.cancel()

        if CodexActivityReducer.shouldHideImmediately(after: event) {
            if snapshot?.sessionHash == event.sessionHash {
                snapshot = identifiedSnapshot
                presentation = .hidden
                resolvedThreadTitle = nil
                resetConfirmationReminder()
                notifyChange()
            }
            titleCache.removeValue(forKey: event.sessionHash)
            titleCacheSources.removeValue(forKey: event.sessionHash)
            titleAttemptedAt.removeValue(forKey: event.sessionHash)
            planProgressBySession.removeValue(
                forKey: event.sessionHash
            )
            goalStatusBySession.removeValue(forKey: event.sessionHash)
            if titleTaskSessionHash == event.sessionHash {
                titleTask?.cancel()
                titleTask = nil
                titleTaskSessionHash = nil
            }
            return
        }

        if snapshot?.sessionHash != event.sessionHash {
            titleTask?.cancel()
            titleTask = nil
            titleTaskSessionHash = nil
        }
        snapshot = identifiedSnapshot
        resolvedThreadTitle = titleCache[event.sessionHash]
        if isStaleSettledContinuationEvent(delivery) {
            lifecycle = .unconfirmed
            presentation = .hidden
            resetConfirmationReminder()
            notifyChange()
            return
        }
        updateConfirmationReminder(
            for: identifiedSnapshot,
            turnHash: event.turnHash
                ?? activeTurnHashBySession[event.sessionHash],
            occurredAt: event.occurredAt
        )
        presentation = .expanded
        notifyChange()

        resolveTitleIfNeeded(
            for: event.sessionHash,
            revision: eventRevision
        )

        if identifiedSnapshot.state != .awaitingConfirmation && CodexActivityReducer.shouldStartInactivityCycle(after: event) {
            scheduleInactivityCycle(revision: eventRevision)
        }
    }

    func receive(_ update: CodexActivityTokenUsageUpdate, publish: Bool = true) {
        guard update.cumulativeTotalTokens >= 0, update.lastReportedTotalTokens >= 0,
              update.cumulativeTotalTokens >= update.lastReportedTotalTokens else { return }
        guard !isBackgroundOrInternal(update.sessionHash) else { return }
        cumulativeTokensDidReceive?(update)
        // Token records never start a new turn or revive a terminal one.
        guard activeTurnHashBySession[update.sessionHash] == update.turnHash,
              terminalTurnsBySession[update.sessionHash] == nil,
              update.cumulativeTotalTokens >= 0,
              update.lastReportedTotalTokens >= 0,
              update.cumulativeTotalTokens >= update.lastReportedTotalTokens
        else { return }

        let existing = turnTokenUsageBySession[update.sessionHash]
        let resolved: StoredTurnTokenUsage
        if let direct = update.directTurnTotalTokens {
            guard direct >= update.lastReportedTotalTokens,
                  direct <= update.cumulativeTotalTokens
            else { return }
            // Do not mix response-ledger totals with legacy context totals.
            // The first authoritative value can correct a fallback estimate.
            let total = max(existing?.directTotalTokens ?? 0, direct)
            resolved = StoredTurnTokenUsage(
                turnHash: update.turnHash,
                baselineTotalTokens: existing?.baselineTotalTokens,
                consumedTokens: total > 0 ? total : nil,
                segmentOffset: existing?.segmentOffset ?? 0,
                directTotalTokens: total
            )
        } else {
            if let latest = latestLegacyTokenAtBySession[update.sessionHash],
               update.occurredAt < latest { return }
            let previousCumulative = cumulativeTokensBySession[update.sessionHash]
            // Keep the legacy baseline fresh for subsequent old-format turns,
            // but never let a legacy rebroadcast overwrite direct turn usage.
            if existing?.directTotalTokens != nil {
                latestLegacyTokenAtBySession[update.sessionHash] = update.occurredAt
                cumulativeTokensBySession[update.sessionHash] = update.cumulativeTotalTokens
                return
            }

            var baseline = existing?.baselineTotalTokens
                ?? previousCumulative
                ?? max(0, update.cumulativeTotalTokens - update.lastReportedTotalTokens)
            var offset = existing?.segmentOffset ?? 0
            if update.cumulativeTotalTokens < baseline
                || previousCumulative.map({ update.cumulativeTotalTokens < $0 }) == true {
                // A restart/context reset begins a new cumulative segment.
                // Count its first reported response once, then use deltas again.
                offset = existing?.consumedTokens ?? 0
                baseline = update.cumulativeTotalTokens - update.lastReportedTotalTokens
            }
            let (measured, overflow) = offset.addingReportingOverflow(
                update.cumulativeTotalTokens - baseline
            )
            guard !overflow else { return }
            latestLegacyTokenAtBySession[update.sessionHash] = update.occurredAt
            cumulativeTokensBySession[update.sessionHash] = update.cumulativeTotalTokens
            let total = max(existing?.consumedTokens ?? 0, measured)
            resolved = StoredTurnTokenUsage(
                turnHash: update.turnHash,
                baselineTotalTokens: baseline,
                consumedTokens: total > 0 ? total : nil,
                segmentOffset: offset
            )
        }
        turnTokenUsageBySession[update.sessionHash] = resolved
        guard publish, existing?.consumedTokens != resolved.consumedTokens,
              multitask.enabled || (snapshot?.sessionHash == update.sessionHash && presentation != .hidden)
        else { return }
        notifyChange()
    }

    func hide() {
        revision &+= 1
        inactivityTask?.cancel()
        titleTask?.cancel()
        resetConfirmationReminder()
        titleTask = nil
        titleTaskSessionHash = nil
        presentation = .hidden
        notifyChange()
    }

    @discardableResult
    func stop() async -> UInt64 {
        setMultitaskEnabled(false)
        admittedSnapshots.removeAll()
        pendingExecutionMemory.removeAll(); pendingExecutionMemoryOrder.removeAll()
        for session in Array(executionMemoryTurns.keys) { revokeExecutionMemory(session) }
        observedActivityBySession.removeAll(); memoryActivityBySession.removeAll()
        for session in subagentIdentities.keys { subagentObservationDidWithdraw?(session) }
        subagentIdentities.removeAll()
        lastAdmittedActivityBySession.removeAll()
        admittedTurnStartBySession.removeAll()
        subagentUnavailableSessions.removeAll()
        subagentSourceUnavailable?(nil)
        backgroundMemorySnapshots = []
        nativeIsRunning = false
        nativeGeneration &+= 1
        let run = nativeGeneration
        nativeStartTask?.cancel()
        nativeStartTask = nil
        hide()
        lifecycle = .idle
        taskRegistry = CodexActivityTaskRegistry()
        for session in Set(latestEventAtBySession.keys).union(sessionKinds.keys) { discardSession(session) }
        acceptedEventIDs.removeAll()
        acceptedEventIDOrder.removeAll()
        snapshot = nil
        localRecovery = CodexLocalActivityRecovery()
        localDesktopFollows.removeAll(); localDesktopFollowOrder.removeAll()
        pendingLocalPublicContent.removeAll(); nativeWaitEvidence.removeAll(); confirmedNativeTurns.removeAll()
        threadMetadataBySession.removeAll(); threadMetadataOrder.removeAll(); titleCacheSources.removeAll()
        pendingNativePublicMessages.removeAll()
        nativePublicEpoch = nil; closedNativePublicEpoch = nil
        desktopPublicEpoch = nil; closedDesktopPublicEpoch = nil
        desktopAdmissions.removeAll(); desktopReceiptReservations.removeAll(); desktopWaitEvidence.removeAll()
        desktopMemoryAdmissions.removeAll()
        selectedActivityAt = nil
        selectedCompactionSource = nil
        updateAutomaticConnection(.init())
        await titleClient.setActivityNotificationHandler(nil)
        guard run == nativeGeneration else { return run }
        await titleClient.stop()
        guard run == nativeGeneration else { return run }
        await localRolloutActivityClient.stop()
        guard run == nativeGeneration else { return run }
        await sharedActivityClient.stop()
        return run
    }

    func updateInactivityDelays(
        compactDelay: TimeInterval,
        hiddenDelayAfterCompact: TimeInterval
    ) {
        let compactNanoseconds = Self.nanoseconds(for: compactDelay)
        let hiddenNanoseconds = Self.nanoseconds(
            for: hiddenDelayAfterCompact
        )
        guard compactDelayNanoseconds != compactNanoseconds
                || hiddenDelayNanoseconds != hiddenNanoseconds
        else {
            return
        }

        compactDelayNanoseconds = compactNanoseconds
        hiddenDelayNanoseconds = hiddenNanoseconds
        multitask.updateDelays(compact: compactDelay, hidden: hiddenDelayAfterCompact,
                               now: ProcessInfo.processInfo.systemUptime)
        scheduleMultitaskTransition()
        guard snapshot?.state == .completed
                || snapshot?.state == .standby
        else {
            return
        }

        revision &+= 1
        let timingRevision = revision
        inactivityTask?.cancel()
        switch presentation {
        case .expanded:
            scheduleInactivityCycle(revision: timingRevision)
        case .compact:
            scheduleHideAfterCompact(revision: timingRevision)
        case .hidden:
            break
        }
    }

    private func synchronizeTokenTurn(for event: CodexActivityEvent) {
        switch event.event {
        case .sessionEnd:
            activeTurnHashBySession.removeValue(
                forKey: event.sessionHash
            )
            turnTokenUsageBySession.removeValue(
                forKey: event.sessionHash
            )
            cumulativeTokensBySession.removeValue(
                forKey: event.sessionHash
            )
            latestLegacyTokenAtBySession.removeValue(forKey: event.sessionHash)
        case .userPromptSubmit:
            guard let turnHash = event.turnHash else {
                activeTurnHashBySession.removeValue(
                    forKey: event.sessionHash
                )
                turnTokenUsageBySession.removeValue(
                    forKey: event.sessionHash
                )
                return
            }
            beginTokenUsageTurn(
                sessionHash: event.sessionHash,
                turnHash: turnHash
            )
        case .preToolUse, .permissionRequest, .postToolUse,
             .preCompact, .postCompact, .subagentStart,
             .subagentStop, .interrupt, .stop:
            guard let turnHash = event.turnHash else { return }
            beginTokenUsageTurn(
                sessionHash: event.sessionHash,
                turnHash: turnHash
            )
        case .sessionStart:
            break
        }
    }

    private func beginTokenUsageTurn(
        sessionHash: String,
        turnHash: String
    ) {
        guard activeTurnHashBySession[sessionHash] != turnHash else {
            return
        }
        activeTurnHashBySession[sessionHash] = turnHash
        turnTokenUsageBySession[sessionHash] = StoredTurnTokenUsage(
            turnHash: turnHash,
            baselineTotalTokens: cumulativeTokensBySession[sessionHash],
            consumedTokens: nil
        )
    }

    private func rememberTitle(_ value: String?, session: String, source: IslandTaskTitleSource) {
        guard let value else { return }
        let title = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.utf8.count <= 512,
              source.rawValue >= titleSource(for: session).rawValue else { return }
        titleCache[session] = title; titleCacheSources[session] = source
    }

    private func rememberThreadMetadata(_ value: CodexLocalRolloutThreadMetadata, session: String) {
        let previous = threadMetadataBySession[session]
        let preservesName = previous?.titleIsExplicitName == true && !value.titleIsExplicitName
        let title = preservesName ? previous?.title : value.title ?? previous?.title
        let total = [value.cumulativeTotalTokens, previous?.cumulativeTotalTokens].compactMap { $0 }.max()
        threadMetadataBySession[session] = .init(title: title,
            titleIsExplicitName: preservesName || (value.title != nil ? value.titleIsExplicitName : previous?.titleIsExplicitName == true),
            model: value.model ?? previous?.model, reasoningEffort: value.reasoningEffort ?? previous?.reasoningEffort,
            cumulativeTotalTokens: total)
        threadMetadataOrder.removeAll { $0 == session }; threadMetadataOrder.append(session)
        while threadMetadataOrder.count > 128 {
            threadMetadataBySession.removeValue(forKey: threadMetadataOrder.removeFirst())
        }
    }

    private func publishThreadMetadata(for session: String) {
        guard executionMemoryTurns[session] == nil, let value = threadMetadataBySession[session],
              let identity = taskRegistry.currentIdentity(for: session) ?? taskRegistry.subagentIdentity(for: session),
              identity.turnHash != nil else { return }
        if taskRegistry.currentIdentity(for: session) != nil {
            rememberTitle(value.title, session: session, source: value.titleIsExplicitName ? .explicitName : .threadTitle)
            if snapshot?.sessionHash == session { resolvedThreadTitle = titleCache[session] }
        }
        threadMetadataDidReceive?(identity, value)
    }

    private func resolveTitleIfNeeded(
        for sessionHash: String,
        revision: UInt64
    ) {
        guard titleSource(for: sessionHash) == .fallback,
              titleTaskSessionHash != sessionHash
        else {
            return
        }
        if let attemptedAt = titleAttemptedAt[sessionHash],
           Date().timeIntervalSince(attemptedAt) < 10
        {
            return
        }

        titleAttemptedAt[sessionHash] = Date()
        titleTaskSessionHash = sessionHash
        titleTask = Task { [weak self, titleClient] in
            let title = try? await titleClient.fetchThreadDisplayName(
                matchingSessionHash: sessionHash
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                self.titleTask = nil
                self.titleTaskSessionHash = nil
                guard self.snapshot?.sessionHash == sessionHash else {
                    return
                }
                // The legacy lookup may return cwd rather than an explicit
                // name. It remains a replaceable fallback, never higher evidence.
                self.rememberTitle(title, session: sessionHash, source: .fallback)
                self.resolvedThreadTitle = self.titleCache[sessionHash]
                if self.revision >= revision {
                    self.notifyChange()
                }
            }
        }
    }

    private func approximateProgress(
        for event: CodexActivityEvent,
        activeGoalStatus: CodexActivityGoalStatus?
    ) -> Double? {
        switch event.event {
        case .userPromptSubmit:
            planProgressBySession.removeValue(
                forKey: event.sessionHash
            )
            return nil
        case .sessionStart:
            if event.sessionStartSource != .compact {
                planProgressBySession.removeValue(
                    forKey: event.sessionHash
                )
            }
        case .sessionEnd:
            planProgressBySession.removeValue(
                forKey: event.sessionHash
            )
            return nil
        case .interrupt:
            planProgressBySession.removeValue(
                forKey: event.sessionHash
            )
            return nil
        case .stop:
            planProgressBySession.removeValue(
                forKey: event.sessionHash
            )
            guard event.turnCompletionStatus != .failed,
                  event.turnCompletionStatus != .interrupted,
                  activeGoalStatus == nil || activeGoalStatus == .complete
            else {
                return nil
            }
            return 1
        default:
            break
        }

        if let planProgress = event.planProgress {
            let source = event.planSource ?? .legacyTool
            if planProgress.totalSteps == 0, source == .appServer {
                if let stored = planProgressBySession[
                    event.sessionHash
                ], Self.sameTurn(stored.turnHash, event.turnHash),
                   Self.planSourcePriority(stored.source)
                    > Self.planSourcePriority(source)
                {
                    return stored.fraction
                }
                planProgressBySession.removeValue(
                    forKey: event.sessionHash
                )
                return nil
            }
            guard let fraction = planProgress.approximateFraction else {
                return nil
            }

            if let stored = planProgressBySession[event.sessionHash],
               Self.sameTurn(stored.turnHash, event.turnHash) {
                if Self.planSourcePriority(stored.source)
                    > Self.planSourcePriority(source)
                {
                    return stored.fraction
                }
                let resolvedFraction = max(stored.fraction, fraction)
                planProgressBySession[event.sessionHash] =
                    StoredPlanProgress(
                        turnHash: event.turnHash ?? stored.turnHash,
                        fraction: resolvedFraction,
                        source: source
                    )
                return resolvedFraction
            }

            planProgressBySession[event.sessionHash] =
                StoredPlanProgress(
                    turnHash: event.turnHash,
                    fraction: fraction,
                    source: source
                )
            return fraction
        }

        guard let stored = planProgressBySession[event.sessionHash]
        else {
            return nil
        }
        if let storedTurnHash = stored.turnHash,
           let eventTurnHash = event.turnHash,
           storedTurnHash != eventTurnHash
        {
            planProgressBySession.removeValue(
                forKey: event.sessionHash
            )
            return nil
        }
        return stored.fraction
    }

    private nonisolated static func sameTurn(
        _ lhs: String?,
        _ rhs: String?
    ) -> Bool {
        guard let lhs, let rhs else { return true }
        return lhs == rhs
    }

    private nonisolated static func planSourcePriority(
        _ source: CodexActivityPlanSource
    ) -> Int {
        switch source {
        case .localRollout: 3
        case .appServer: 2
        case .legacyTool: 1
        }
    }

    private func scheduleInactivityCycle(revision: UInt64) {
        inactivityTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(
                    nanoseconds: compactDelayNanoseconds
                )
                guard !Task.isCancelled, self.revision == revision else {
                    return
                }
                presentation = .compact
                notifyChange()
                await sleepUntilHidden(revision: revision)
            } catch {
                return
            }
        }
    }

    private func updateConfirmationReminder(
        for snapshot: CodexActivitySnapshot,
        turnHash: String?,
        occurredAt: Date
    ) {
        guard snapshot.state == .awaitingConfirmation else {
            resetConfirmationReminder()
            return
        }

        let context = ConfirmationReminderContext(
            sessionHash: snapshot.sessionHash,
            turnHash: turnHash
        )
        guard confirmationReminderContext != context else { return }

        confirmationReminderTask?.cancel()
        confirmationReminderContext = context
        isConfirmationReminderActive = false

        let elapsed = max(0, Date().timeIntervalSince(occurredAt))
        let configuredDelay = TimeInterval(
            confirmationReminderDelayNanoseconds
        ) / 1_000_000_000
        let remainingDelay = max(0, configuredDelay - elapsed)
        guard remainingDelay > 0 else {
            isConfirmationReminderActive = true
            return
        }

        confirmationReminderTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(
                    nanoseconds: Self.nanoseconds(for: remainingDelay)
                )
                guard !Task.isCancelled,
                      self.confirmationReminderContext == context,
                      self.snapshot?.state == .awaitingConfirmation
                else {
                    return
                }
                self.isConfirmationReminderActive = true
                self.notifyChange()
            } catch {
                return
            }
        }
    }

    private func resetConfirmationReminder() {
        confirmationReminderTask?.cancel()
        confirmationReminderTask = nil
        confirmationReminderContext = nil
        isConfirmationReminderActive = false
    }

    private func scheduleHideAfterCompact(revision: UInt64) {
        inactivityTask = Task { [weak self] in
            guard let self else { return }
            await sleepUntilHidden(revision: revision)
        }
    }

    private func isStaleSettledContinuationEvent(
        _ delivery: CodexActivityDelivery
    ) -> Bool {
        guard delivery.source == .startupReplay else { return false }
        let event = delivery.activity
        guard CodexActivityReducer
            .isSettledContinuationEvent(after: event)
        else {
            return false
        }
        let elapsed = max(0, Date().timeIntervalSince(event.occurredAt))
        let replayAgeThreshold = TimeInterval(
            settledEventReplayAgeThresholdNanoseconds
        ) / 1_000_000_000
        return elapsed >= replayAgeThreshold
    }

    private func discardSession(_ session: String, preservingChildOrigin: Bool = false) {
        let retainsChildOrigin = preservingChildOrigin && sessionKinds[session] == .subagent
            && subagentIdentities[session] != nil
        if subagentIdentities[session] != nil { subagentObservationDidWithdraw?(session) }
        removePendingExecutionMemory(session: session)
        if !retainsChildOrigin { subagentIdentities.removeValue(forKey: session) }
        lastAdmittedActivityBySession.removeValue(forKey: session)
        admittedTurnStartBySession.removeValue(forKey: session)
        subagentUnavailableSessions.remove(session)
        revokeExecutionMemory(session)
        admittedSnapshots.removeValue(forKey: session)
        observedActivityBySession.removeValue(forKey: session)
        memoryActivityBySession.removeValue(forKey: session)
        desktopMemoryAdmissions.removeValue(forKey: session)
        publishMemorySnapshots()
        multitask.remove(session, now: ProcessInfo.processInfo.systemUptime)
        multitaskTitleTasks.removeValue(forKey: session)?.cancel()
        latestEventAtBySession.removeValue(forKey: session)
        terminalTurnsBySession.removeValue(forKey: session)
        planProgressBySession.removeValue(forKey: session)
        goalStatusBySession.removeValue(forKey: session)
        cumulativeTokensBySession.removeValue(forKey: session)
        latestLegacyTokenAtBySession.removeValue(forKey: session)
        activeTurnHashBySession.removeValue(forKey: session)
        turnTokenUsageBySession.removeValue(forKey: session)
        titleCache.removeValue(forKey: session)
        titleCacheSources.removeValue(forKey: session)
        threadMetadataBySession.removeValue(forKey: session); threadMetadataOrder.removeAll { $0 == session }
        titleAttemptedAt.removeValue(forKey: session)
        if !retainsChildOrigin { forgetSessionOrigin(session) }
    }

    /// Origin proof outlives a bounded execution slot, with its own bounded LRU.
    /// Pruning that proof also clears the relationship; a later transport must
    /// supply verified native metadata before the child may reattach.
    private func forgetSessionOrigin(_ session: String) {
        if subagentIdentities.removeValue(forKey: session) != nil {
            subagentObservationDidWithdraw?(session)
        }
        sessionKinds.removeValue(forKey: session)
        sessionKindOrder.removeAll { $0 == session }
    }

    private func revokeExecutionMemory(_ session: String) {
        if executionMemoryTurns.removeValue(forKey: session) != nil {
            activityExecutionKindDidResolve?(session, .unknown)
        }
    }

    private func registerEventID(_ eventID: String?) -> Bool {
        guard let eventID, !eventID.isEmpty else { return true }
        guard acceptedEventIDs.insert(eventID).inserted else {
            return false
        }
        acceptedEventIDOrder.append(eventID)
        if acceptedEventIDOrder.count > 512 {
            let overflow = acceptedEventIDOrder.count - 512
            let removed = acceptedEventIDOrder.prefix(overflow)
            acceptedEventIDs.subtract(removed)
            acceptedEventIDOrder.removeFirst(overflow)
        }
        return true
    }

    private func sleepUntilHidden(revision: UInt64) async {
        do {
            try await Task.sleep(
                nanoseconds: hiddenDelayNanoseconds
            )
            guard !Task.isCancelled, self.revision == revision else {
                return
            }
            presentation = .hidden
            notifyChange()
        } catch {
            return
        }
    }

    private nonisolated static func nanoseconds(
        for delay: TimeInterval
    ) -> UInt64 {
        UInt64(max(delay, 0) * 1_000_000_000)
    }

    private func notifyChange() {
        scheduleMultitaskTransition()
        resolveMultitaskTitles()
        stateDidChange?()
    }

    private func scheduleMultitaskTransition() {
        let deadline = multitask.enabled ? multitask.nextDeadline : nil
        guard deadline != multitaskDeadline else { return }
        multitaskTask?.cancel(); multitaskTask = nil; multitaskDeadline = deadline
        guard let deadline else { return }
        let generation = multitaskGeneration
        multitaskTask = Task { [weak self] in
            let remaining = max(0, deadline - ProcessInfo.processInfo.systemUptime)
            do { try await Task.sleep(nanoseconds: Self.nanoseconds(for: remaining)) } catch { return }
            guard let self, !Task.isCancelled, self.multitask.enabled,
                  self.multitaskGeneration == generation, self.multitask.nextDeadline == deadline else { return }
            self.multitask.advance(now: ProcessInfo.processInfo.systemUptime)
            self.notifyChange()
        }
    }

    private func resolveMultitaskTitles() {
        guard multitask.enabled else { return }
        let generation = multitaskGeneration
        for entry in multitask.entries where multitaskTitleTasks.count < 2 {
            let session = entry.snapshot.sessionHash
            guard titleSource(for: session) == .fallback, multitaskTitleTasks[session] == nil,
                  titleAttemptedAt[session].map({ Date().timeIntervalSince($0) >= 10 }) ?? true else { continue }
            titleAttemptedAt[session] = Date()
            multitaskTitleTasks[session] = Task { [weak self, titleClient] in
                let title = try? await titleClient.fetchThreadDisplayName(matchingSessionHash: session)
                guard let self, !Task.isCancelled, self.multitask.enabled,
                      self.multitaskGeneration == generation else { return }
                self.multitaskTitleTasks.removeValue(forKey: session)
                self.rememberTitle(title, session: session, source: .fallback)
                if self.snapshot?.sessionHash == session { self.resolvedThreadTitle = self.titleCache[session] }
                self.notifyChange()
            }
        }
    }
}
