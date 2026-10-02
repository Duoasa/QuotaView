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
    var publicMessageDidReceive: ((Data) -> Void)?
    var admittedActivityDidReceive: ((CodexActivityEvent) -> Void)?
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
    private var localRecovery = CodexLocalActivityRecovery()
    private var selectedActivityAt: Date?
    private var selectedCompactionSource: CodexActivityEventSource?
    private let sessionKindResolver: (@Sendable (CodexActivityEvent) async -> CodexActivitySessionKind)?
    private var nativeGeneration: UInt64 = 0
    private var nativeStartTask: Task<Void, Never>?
    private var taskRegistry = CodexActivityTaskRegistry()
    private var sessionKinds: [String: CodexActivitySessionKind] = [:]
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
        sessionClassifier = CodexActivitySessionClassifier(codexHome: sessionDirectory)
        hookSessionClassifier = CodexActivitySessionClassifier(codexHome: sessionDirectory)
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
        let sharedActivityClient = sharedActivityClient
        let localRolloutActivityClient = localRolloutActivityClient
        nativeStartTask = Task { [weak self] in
            guard let self, self.nativeGeneration == run, !Task.isCancelled else { return }
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
            await sharedActivityClient.setPublicMessageHandler { [weak self] data in
                await self?.receivePublicMessage(data, generation: run)
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

    private func receiveLocalPublicContent(_ content: CodexLocalPublicContent, generation run: UInt64) {
        guard nativeGeneration == run else { return }; localPublicContentDidReceive?(content)
    }
    private func receivePublicMessage(_ data: Data, generation run: UInt64) {
        guard nativeGeneration == run else { return }; publicMessageDidReceive?(data)
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
        sessionClassifier = CodexActivitySessionClassifier(codexHome: root)
        hookSessionClassifier = CodexActivitySessionClassifier(codexHome: root)
        startNativeActivityNotifications()
        return true
    }

    private func receiveLocalRecord(_ record: CodexLocalRolloutDecodedRecord, replay: Bool,
                                    generation run: UInt64) async {
        guard nativeGeneration == run else { return }
        guard let projection = localRecovery.project(record) else { return }
        for context in projection.context {
            guard nativeGeneration == run else { return }
            await applyLocalRecord(context, replay: true, generation: run,
                                   selectionEvidenceAt: projection.confirmationTime)
        }
        guard nativeGeneration == run else { return }
        await applyLocalRecord(projection.record, replay: replay, generation: run)
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
        if state != .connected { compactionSourceUnavailable(.appServer) }
        var next = automaticConnection
        next.sharedState = state
        updateAutomaticConnection(next)
    }

    func compactionSourceUnavailable(_ source: CodexActivityEventSource) {
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

    func receiveClassified(_ delivery: CodexActivityDelivery, generation expected: UInt64? = nil,
                           selectionEvidenceAt: Date? = nil, admissionAllowed: (() -> Bool)? = nil) async {
        let run = expected ?? nativeGeneration
        let classifier = delivery.activity.source == .hook ? hookSessionClassifier : sessionClassifier
        let kind: CodexActivitySessionKind
        if let sessionKindResolver { kind = await sessionKindResolver(delivery.activity) }
        else { kind = await classifier.kind(for: delivery.activity) }
        guard run == nativeGeneration, admissionAllowed?() ?? true else { return }
        let before = snapshot
        receive(CodexActivityDelivery(eventID: delivery.eventID, source: delivery.source,
                                      activity: delivery.activity.classified(as: kind)),
                selectionEvidenceAt: selectionEvidenceAt)
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

    func receive(_ delivery: CodexActivityDelivery, selectionEvidenceAt: Date? = nil) {
        let event = delivery.activity
        if let id = delivery.eventID, acceptedEventIDs.contains(id) { return }
        var knownGoalStatus = event.goalStatus
            ?? goalStatusBySession[event.sessionHash]
        guard CodexActivityReducer.snapshot(
            for: event,
            activeGoalStatus: knownGoalStatus
        ) != nil
        else {
            return
        }

        let kind = sessionKinds[event.sessionHash] ?? .unknown
        let resolvedKind = kind == .internalTask ? kind : event.sessionKind ?? kind
        guard let admission = taskRegistry.admit(event, kind: resolvedKind,
                                                selectedSession: snapshot?.sessionHash,
                                                selectedOccurredAt: selectedActivityAt ?? snapshot?.occurredAt,
                                                selectionEvidenceAt: selectionEvidenceAt) else { return }
        admittedActivityDidReceive?(event)
        _ = registerEventID(delivery.eventID)
        for session in admission.evictedSessions { discardSession(session) }
        if resolvedKind != .unknown { sessionKinds[event.sessionHash] = resolvedKind }
        if admission.startsTurn {
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
        var nextLifecycle = lifecycle

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

        let identifiedSnapshot = CodexActivitySnapshot(
            sessionHash: nextSnapshot.sessionHash, taskIdentity: admission.identity,
            state: nextSnapshot.state, workspaceName: nextSnapshot.workspaceName,
            operationKey: nextSnapshot.operationKey, toolCategory: nextSnapshot.toolCategory,
            approximateProgressFraction: nextSnapshot.approximateProgressFraction,
            occurredAt: nextSnapshot.occurredAt
        )
        let source: CodexActivityEventSource? = nextSnapshot.state == .compactingContext ? event.source : nil
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

        if CodexActivityReducer.shouldStartInactivityCycle(after: event) {
            scheduleInactivityCycle(revision: eventRevision)
        }
    }

    func receive(_ update: CodexActivityTokenUsageUpdate, publish: Bool = true) {
        guard update.cumulativeTotalTokens >= 0, update.lastReportedTotalTokens >= 0,
              update.cumulativeTotalTokens >= update.lastReportedTotalTokens else { return }
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
        nativeIsRunning = false
        nativeGeneration &+= 1
        let run = nativeGeneration
        nativeStartTask?.cancel()
        nativeStartTask = nil
        hide()
        lifecycle = .idle
        taskRegistry = CodexActivityTaskRegistry()
        for session in Array(latestEventAtBySession.keys) { discardSession(session) }
        acceptedEventIDs.removeAll()
        acceptedEventIDOrder.removeAll()
        snapshot = nil
        localRecovery = CodexLocalActivityRecovery()
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

    private func resolveTitleIfNeeded(
        for sessionHash: String,
        revision: UInt64
    ) {
        guard titleCache[sessionHash] == nil,
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
                if let title {
                    self.titleCache[sessionHash] = title
                }
                self.resolvedThreadTitle = title
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

    private func discardSession(_ session: String) {
        admittedSnapshots.removeValue(forKey: session)
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
        titleAttemptedAt.removeValue(forKey: session)
        sessionKinds.removeValue(forKey: session)
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
            guard titleCache[session] == nil, multitaskTitleTasks[session] == nil,
                  titleAttemptedAt[session].map({ Date().timeIntervalSince($0) >= 10 }) ?? true else { continue }
            titleAttemptedAt[session] = Date()
            multitaskTitleTasks[session] = Task { [weak self, titleClient] in
                let title = try? await titleClient.fetchThreadDisplayName(matchingSessionHash: session)
                guard let self, !Task.isCancelled, self.multitask.enabled,
                      self.multitaskGeneration == generation else { return }
                self.multitaskTitleTasks.removeValue(forKey: session)
                if let title { self.titleCache[session] = title }
                if self.snapshot?.sessionHash == session { self.resolvedThreadTitle = title }
                self.notifyChange()
            }
        }
    }
}
