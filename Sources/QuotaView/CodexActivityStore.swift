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
    private let hookSessionClassifier = CodexActivitySessionClassifier(codexHome: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex"))
    private var localRecovery = CodexLocalActivityRecovery()
    private var selectedActivityAt: Date?
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

    private func setLocalHealth(_ health: CodexLocalActivityHealth, generation run: UInt64) {
        guard nativeGeneration == run else { return }
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
        if currentTurnTokenUsage != before, presentation != .hidden { notifyChange() }
    }

    private func receiveNativeToken(_ update: CodexActivityTokenUsageUpdate, generation run: UInt64) {
        guard run == nativeGeneration else { return }
        receive(update)
    }

    private func setSharedConnectionState(_ state: CodexSharedAppServerConnectionState, generation run: UInt64) {
        guard nativeGeneration == run else { return }
        var next = automaticConnection
        next.sharedState = state
        updateAutomaticConnection(next)
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

        // Background state may settle, but only the selected task owns UI timers.
        guard admission.selectsTask else { return }
        selectedActivityAt = max(selectedActivityAt ?? .distantPast, selectionEvidenceAt ?? event.occurredAt)
        lifecycle = nextLifecycle
        let identifiedSnapshot = CodexActivitySnapshot(
            sessionHash: nextSnapshot.sessionHash, taskIdentity: admission.identity,
            state: nextSnapshot.state, workspaceName: nextSnapshot.workspaceName,
            operationKey: nextSnapshot.operationKey, toolCategory: nextSnapshot.toolCategory,
            approximateProgressFraction: nextSnapshot.approximateProgressFraction,
            occurredAt: nextSnapshot.occurredAt
        )
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
              snapshot?.sessionHash == update.sessionHash,
              presentation != .hidden
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
        stateDidChange?()
    }
}
