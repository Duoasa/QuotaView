import AppKit
import Combine
import Darwin
import Foundation
import QuotaViewCore

enum CodexActivityConnectionStatus: Equatable {
    case notInstalled
    case installedNeedsRestart
    case awaitingTrust
    case awaitingFirstEvent
    case connected
    case abnormal(String)
}

enum CodexHooksFeatureStatus: Equatable {
    case checking
    case enabled
    case disabled
    case unavailable
}

enum CodexActivityBridgeStatus: Equatable {
    case stopped
    case listening
    case failed(String)
}

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
    var nativeConnectionStateDidChange:
        ((CodexSharedAppServerConnectionState) -> Void)?

    private let titleClient: CodexAppServerClient
    private let sharedActivityClient: CodexSharedAppServerActivityClient
    private let localRolloutActivityClient:
        CodexLocalRolloutActivityClient
    private(set) var nativeConnectionState:
        CodexSharedAppServerConnectionState = .disabled
    private var sharedConnectionState:
        CodexSharedAppServerConnectionState = .disabled
    private var localRolloutConnectionState:
        CodexSharedAppServerConnectionState = .disabled
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
    private let sessionClassifier = CodexActivitySessionClassifier()
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
            CodexActivityStore.confirmationReminderDelay
    ) {
        self.titleClient = titleClient
        self.sharedActivityClient = sharedActivityClient
        self.localRolloutActivityClient = localRolloutActivityClient
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
                    guard let self else { return }
                    switch record.update {
                    case .activity(let event):
                        let delivery = CodexActivityDelivery(
                            eventID: record.eventID,
                            source: isStartupReplay
                                ? .startupReplay
                                : .localRollout,
                            activity: event
                        )
                        await self.receiveClassified(delivery, generation: run)
                        CodexActivityDiagnostics.record(
                            delivery: delivery,
                            outcome: isStartupReplay
                                ? "local_rollout_replay"
                                : "local_rollout_received"
                        )
                    case .tokenUsage(let update):
                        await self.receiveNativeToken(update, generation: run)
                    case .tokenUsageReplay(let updates):
                        await self.receiveNativeTokenReplay(updates, generation: run)
                    }
                },
                connectionStateHandler: { [weak self] state in
                    await self?.setNativeConnectionState(state, local: true, generation: run)
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
                    await self?.setNativeConnectionState(state, local: false, generation: run)
                }
            )
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

    private func setNativeConnectionState(_ state: CodexSharedAppServerConnectionState,
                                          local: Bool, generation run: UInt64) {
        guard run == nativeGeneration else { return }
        if local { setLocalRolloutConnectionState(state) }
        else { setSharedConnectionState(state) }
    }

    private func setSharedConnectionState(
        _ state: CodexSharedAppServerConnectionState
    ) {
        sharedConnectionState = state
        publishAggregateConnectionState()
    }

    private func setLocalRolloutConnectionState(
        _ state: CodexSharedAppServerConnectionState
    ) {
        localRolloutConnectionState = state
        publishAggregateConnectionState()
    }

    private func publishAggregateConnectionState() {
        let state: CodexSharedAppServerConnectionState
        if localRolloutConnectionState == .connected
            || sharedConnectionState == .connected
        {
            state = .connected
        } else if localRolloutConnectionState == .discovering
                    || sharedConnectionState == .discovering
        {
            state = .discovering
        } else {
            state = .disabled
        }
        guard nativeConnectionState != state else { return }
        nativeConnectionState = state
        nativeConnectionStateDidChange?(state)
    }

    func receiveClassified(_ delivery: CodexActivityDelivery, generation expected: UInt64? = nil) async {
        let run = expected ?? nativeGeneration
        let kind = await sessionClassifier.kind(for: delivery.activity)
        guard run == nativeGeneration else { return }
        let before = snapshot
        receive(CodexActivityDelivery(eventID: delivery.eventID, source: delivery.source,
                                      activity: delivery.activity.classified(as: kind)))
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

    func receive(_ delivery: CodexActivityDelivery) {
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
                                                selectedOccurredAt: snapshot?.occurredAt) else { return }
        _ = registerEventID(delivery.eventID)
        for session in admission.evictedSessions { discardSession(session) }
        if resolvedKind != .unknown { sessionKinds[event.sessionHash] = resolvedKind }
        if admission.startsTurn {
            planProgressBySession.removeValue(forKey: event.sessionHash)
            goalStatusBySession.removeValue(forKey: event.sessionHash)
            terminalTurnsBySession.removeValue(forKey: event.sessionHash)
        }
        // A repeated transport start is an acknowledgement, not new activity.
        if admission.duplicateStart { return }
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

        let approximateProgress = approximateProgress(
            for: event,
            activeGoalStatus: knownGoalStatus
        )
        guard let nextSnapshot = CodexActivityReducer.snapshot(
            for: event,
            approximateProgressFraction: approximateProgress,
            activeGoalStatus: knownGoalStatus
        ) else {
            return
        }

        // Background state may settle, but only the selected task owns UI timers.
        guard admission.selectsTask else { return }
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

    func stop() async {
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
        localRolloutConnectionState = .disabled
        sharedConnectionState = .disabled
        publishAggregateConnectionState()
        await titleClient.setActivityNotificationHandler(nil)
        guard run == nativeGeneration else { return }
        await titleClient.stop()
        guard run == nativeGeneration else { return }
        await localRolloutActivityClient.stop()
        guard run == nativeGeneration else { return }
        await sharedActivityClient.stop()
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

@MainActor
final class CodexActivityRuntime: ObservableObject {
    @Published private(set) var connectionStatus:
        CodexActivityConnectionStatus = .notInstalled
    @Published private(set) var bridgeStatus:
        CodexActivityBridgeStatus = .stopped
    @Published private(set) var hooksFeatureStatus:
        CodexHooksFeatureStatus = .checking
    @Published private(set) var nativeConnectionState:
        CodexSharedAppServerConnectionState = .disabled
    @Published private(set) var codexVersion: String?
    @Published private(set) var isConfiguring = false
    @Published private(set) var isOpeningSecurityReview = false

    let store: CodexActivityStore

    private let preferences: AppPreferences
    private let defaults: UserDefaults
    private let bridge: CodexActivityUnixBridge
    private let fileBridge: CodexActivityFileBridge
    private let installer: CodexActivityHookInstaller
    private let environmentInspector: CodexActivityEnvironmentInspector
    private let securityReviewLauncher: CodexSecurityReviewLauncher
    private var island: CodexActivityIslandPanelController?
    private var preferenceCancellable: AnyCancellable?
    private var timingPreferenceCancellable: AnyCancellable?
    private var accessibilityCancellable: AnyCancellable?
    private var screenTrackingCancellable: AnyCancellable?
    private var quotaStatusCancellable: AnyCancellable?
    private var currentQuotaPresentation: CurrentCodexPresentation?
    private var workspaceCancellables: Set<AnyCancellable> = []
    private var setupTask: Task<Void, Never>?
    private var securityReviewObservationTask: Task<Void, Never>?
    private var setupIslandRequested = false
    private var isRunning = false

    private enum DefaultsKey {
        static let setupEnabled = "codexActivity.setup.enabled"
        static let observedInstallation =
            "codexActivity.setup.observedInstallation"
        static let connectedInstallation =
            "codexActivity.setup.connectedInstallation"
        static let restartProcessIdentifier =
            "codexActivity.setup.restartProcessIdentifier"
        static let reviewConfirmedInstallation =
            "codexActivity.setup.reviewConfirmedInstallation"
    }

    init(
        preferences: AppPreferences,
        quotaStatusStore: CodexStatusStore? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.preferences = preferences
        self.defaults = defaults
        store = CodexActivityStore(
            compactDelay:
                TimeInterval(preferences.codexActivityCompactDelay),
            hiddenDelayAfterCompact: TimeInterval(
                preferences.codexActivityHiddenDelayAfterCompact
            )
        )

        let tokenKey = "codexActivity.bridge.authenticationToken"
        let token: String
        if let existing = defaults.string(forKey: tokenKey),
           !existing.isEmpty
        {
            token = existing
        } else {
            token = UUID().uuidString.lowercased()
            defaults.set(token, forKey: tokenKey)
        }

        let socketURL = Self.defaultSocketURL()
        let queueURL = Self.defaultQueueURL()
        let installer = CodexActivityHookInstaller(
            socketURL: socketURL,
            authenticationToken: token
        )
        self.installer = installer
        bridge = CodexActivityUnixBridge(
            socketURL: socketURL,
            authenticationToken: token,
            installationIdentifier: installer.installationIdentifier
        )
        fileBridge = CodexActivityFileBridge(
            queueURL: queueURL,
            authenticationToken: token,
            installationIdentifier: installer.installationIdentifier
        )
        environmentInspector = CodexActivityEnvironmentInspector()
        securityReviewLauncher = CodexSecurityReviewLauncher(
            codexExecutablePath: environmentInspector.executablePath
        )

        store.stateDidChange = { [weak self] in
            self?.render()
        }
        store.nativeConnectionStateDidChange = { [weak self] state in
            self?.handleNativeConnectionState(state)
        }
        if let quotaStatusStore {
            currentQuotaPresentation = quotaStatusStore.hasCurrentCodexStatus
                ? quotaStatusStore.snapshot
                : nil
            quotaStatusCancellable = Publishers.CombineLatest(
                quotaStatusStore.$snapshot,
                quotaStatusStore.$errorMessage
            )
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot, errorMessage in
                self?.currentQuotaPresentation = errorMessage == nil
                    ? snapshot
                    : nil
                self?.render()
            }
        }
        preferenceCancellable = preferences.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.render()
                }
            }
        timingPreferenceCancellable = Publishers.CombineLatest(
            preferences.$codexActivityCompactDelay,
            preferences.$codexActivityHiddenDelayAfterCompact
        )
        .dropFirst()
        .receive(on: RunLoop.main)
        .sink { [weak self] compactDelay, hiddenDelay in
            self?.store.updateInactivityDelays(
                compactDelay: TimeInterval(compactDelay),
                hiddenDelayAfterCompact: TimeInterval(hiddenDelay)
            )
        }
        accessibilityCancellable = NotificationCenter.default.publisher(
            for: NSWorkspace
                .accessibilityDisplayOptionsDidChangeNotification
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            Task { @MainActor in
                self?.render()
            }
        }

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.publisher(
            for: NSWorkspace.didLaunchApplicationNotification
        )
        .merge(with: workspaceCenter.publisher(
            for: NSWorkspace.didTerminateApplicationNotification
        ))
        .receive(on: RunLoop.main)
        .sink { [weak self] notification in
            guard let application = notification.userInfo?[
                NSWorkspace.applicationUserInfoKey
            ] as? NSRunningApplication,
            application.bundleIdentifier == "com.openai.codex"
            else {
                return
            }
            Task { @MainActor in
                self?.refreshConnectionStatus()
            }
        }
        .store(in: &workspaceCancellables)

        NotificationCenter.default.publisher(
            for: NSApplication.didChangeScreenParametersNotification
        )
        .merge(with: workspaceCenter.publisher(
            for: NSWorkspace.didActivateApplicationNotification
        ))
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            Task { @MainActor in
                self?.render()
            }
        }
        .store(in: &workspaceCancellables)
    }

    func start() {
        isRunning = true
        store.startNativeActivityNotifications()
        let handler: CodexActivityDeliveryHandler = {
            [weak self] delivery, completion in
            Task { @MainActor in
                guard let self else {
                    completion(false)
                    return
                }
                completion(await self.receive(delivery))
            }
        }
        var isListening = false
        var failures: [String] = []

        do {
            try fileBridge.start(handler: handler)
            isListening = true
        } catch {
            failures.append(error.localizedDescription)
        }

        do {
            try bridge.start(handler: handler)
            isListening = true
        } catch {
            failures.append(error.localizedDescription)
        }

        bridgeStatus = isListening
            ? .listening
            : .failed(failures.joined(separator: " "))
        reconcileOnLaunch()
    }

    func enableCodexActivity() {
        setupIslandRequested = true
        render()
        configure(previouslyEnabledOnly: false)
    }

    func openCodexSecurityReview() {
        guard !isConfiguring, !isOpeningSecurityReview else { return }
        securityReviewObservationTask?.cancel()
        isOpeningSecurityReview = true
        setupIslandRequested = true
        render()

        let launcher = securityReviewLauncher
        let baselineProcessIdentifier =
            Self.runningCodexProcessIdentifier().map(Int.init) ?? 0
        Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                Result { try launcher.prepareLauncher() }
            }.value
            guard let self, !Task.isCancelled else { return }

            switch result {
            case .success(let launcherURL):
                guard NSWorkspace.shared.open(launcherURL) else {
                    isOpeningSecurityReview = false
                    connectionStatus = .abnormal(
                        CodexSecurityReviewLauncher.LaunchError
                            .couldNotOpenTerminal.localizedDescription
                    )
                    render()
                    return
                }

                defaults.set(
                    baselineProcessIdentifier,
                    forKey: DefaultsKey.restartProcessIdentifier
                )
                defaults.removeObject(
                    forKey: DefaultsKey.observedInstallation
                )
                defaults.removeObject(
                    forKey: DefaultsKey.connectedInstallation
                )
                defaults.removeObject(
                    forKey: DefaultsKey.reviewConfirmedInstallation
                )
                connectionStatus = .awaitingTrust
                isOpeningSecurityReview = false
                observeSecurityReviewCompletion()
                render()
            case .failure(let error):
                isOpeningSecurityReview = false
                connectionStatus = .abnormal(
                    error.localizedDescription
                )
                render()
            }
        }
    }

    func disableCodexActivity() {
        guard !isConfiguring else { return }
        isConfiguring = true
        setupTask?.cancel()
        securityReviewObservationTask?.cancel()
        let installer = installer
        setupTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                Result { try installer.uninstall() }
            }.value
            guard let self, !Task.isCancelled else { return }
            isConfiguring = false
            switch result {
            case .success:
                defaults.set(false, forKey: DefaultsKey.setupEnabled)
                defaults.removeObject(
                    forKey: DefaultsKey.observedInstallation
                )
                defaults.removeObject(
                    forKey: DefaultsKey.connectedInstallation
                )
                defaults.removeObject(
                    forKey: DefaultsKey.restartProcessIdentifier
                )
                defaults.removeObject(
                    forKey: DefaultsKey.reviewConfirmedInstallation
                )
                setupIslandRequested = false
                connectionStatus = .notInstalled
                store.hide()
                island?.hide()
            case .failure(let error):
                connectionStatus = .abnormal(
                    error.localizedDescription
                )
                render()
            }
        }
    }

    func restartCodex() {
        guard !isConfiguring, !isOpeningSecurityReview else { return }
        let workspace = NSWorkspace.shared
        let runningApplication = NSRunningApplication
            .runningApplications(
                withBundleIdentifier: "com.openai.codex"
            )
            .first
        guard let applicationURL = runningApplication?.bundleURL
            ?? workspace.urlForApplication(
                withBundleIdentifier: "com.openai.codex"
            )
        else {
            connectionStatus = .abnormal(
                localizedSetupMessage(
                    chinese: "找不到可以重新启动的 Codex 应用。",
                    english:
                        "QuotaView could not find the Codex application."
                )
            )
            render()
            return
        }

        isConfiguring = true
        setupIslandRequested = true
        render()

        Task { [weak self] in
            guard let self else { return }
            if let runningApplication,
               !runningApplication.isTerminated
            {
                guard runningApplication.terminate() else {
                    self.finishCodexRestart(
                        errorMessage: self.localizedSetupMessage(
                            chinese: "Codex 拒绝了重新启动请求。",
                            english:
                                "Codex declined the restart request."
                        )
                    )
                    return
                }
                for _ in 0..<40 where !runningApplication.isTerminated {
                    try? await Task.sleep(
                        nanoseconds: 250_000_000
                    )
                }
                guard runningApplication.isTerminated else {
                    self.finishCodexRestart(
                        errorMessage: self.localizedSetupMessage(
                            chinese:
                                "Codex 尚未退出，请保存当前任务后重试。",
                            english:
                                "Codex is still running. Save the current task and try again."
                        )
                    )
                    return
                }
            }

            workspace.openApplication(
                at: applicationURL,
                configuration: NSWorkspace.OpenConfiguration()
            ) { [weak self] _, error in
                Task { @MainActor in
                    self?.finishCodexRestart(
                        errorMessage: error?.localizedDescription
                    )
                }
            }
        }
    }

    func refreshConnectionStatus() {
        guard !isConfiguring else { return }
        inspectEnvironmentAndInstallation()
    }

    var isNativeActivityConnected: Bool {
        nativeConnectionState == .connected
    }

    func stop() async {
        isRunning = false
        setupTask?.cancel()
        securityReviewObservationTask?.cancel()
        bridge.stop()
        fileBridge.stop()
        bridgeStatus = .stopped
        await store.stop()
        island?.hide()
    }

    var diagnosticLogPath: String {
        CodexActivityDiagnostics.logURL.path
    }

    private func handleNativeConnectionState(
        _ state: CodexSharedAppServerConnectionState
    ) {
        let wasConnected = isNativeActivityConnected
        nativeConnectionState = state

        if state == .connected {
            connectionStatus = .connected
            setupIslandRequested = false
            render()
        } else if wasConnected, isRunning {
            inspectEnvironmentAndInstallation()
        }
    }

    private func reconcileOnLaunch() {
        let installer = installer
        let optedIn = defaults.bool(forKey: DefaultsKey.setupEnabled)
        Task { [weak self] in
            let shouldReconcile = await Task.detached(priority: .utility) {
                let hasExistingHandler =
                    (try? installer.hasQuotaViewHandlers()) ?? false
                return optedIn || hasExistingHandler
            }.value
            guard let self, !Task.isCancelled else { return }
            if shouldReconcile {
                configure(previouslyEnabledOnly: true)
            } else {
                inspectEnvironmentAndInstallation()
            }
        }
    }

    private func configure(previouslyEnabledOnly: Bool) {
        guard !isConfiguring else { return }
        isConfiguring = true
        hooksFeatureStatus = .checking
        setupTask?.cancel()

        let inspector = environmentInspector
        let installer = installer
        setupTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                Result {
                    if previouslyEnabledOnly {
                        let hasExistingHandler =
                            try installer.hasQuotaViewHandlers()
                        guard hasExistingHandler else {
                            return CodexActivitySetupResult.notInstalled
                        }
                    }

                    let environment =
                        try inspector.inspectAndEnableHooksIfNeeded()
                    let installation = try installer.install()
                    return CodexActivitySetupResult.installed(
                        environment: environment,
                        hookDefinitionChanged:
                            installation.hookDefinitionChanged
                    )
                }
            }.value

            guard let self, !Task.isCancelled else { return }
            isConfiguring = false
            switch result {
            case .success(.notInstalled):
                defaults.set(false, forKey: DefaultsKey.setupEnabled)
                setupIslandRequested = false
                connectionStatus = .notInstalled
                render()
                inspectEnvironmentAndInstallation()
            case .success(.installed(
                let environment,
                let hookDefinitionChanged
            )):
                codexVersion = environment.version
                hooksFeatureStatus = .enabled
                defaults.set(true, forKey: DefaultsKey.setupEnabled)

                if hookDefinitionChanged
                    || environment.didEnableHooks
                {
                    defaults.removeObject(
                        forKey: DefaultsKey.observedInstallation
                    )
                    defaults.removeObject(
                        forKey: DefaultsKey.connectedInstallation
                    )
                    defaults.removeObject(
                        forKey: DefaultsKey.restartProcessIdentifier
                    )
                    defaults.removeObject(
                        forKey: DefaultsKey.reviewConfirmedInstallation
                    )
                }
                updateConnectionStatusFromInstalledState()
                if !previouslyEnabledOnly,
                   connectionStatus != .connected
                {
                    openCodexSecurityReview()
                }
            case .failure(let error):
                hooksFeatureStatus = .unavailable
                connectionStatus = .abnormal(
                    error.localizedDescription
                )
                render()
            }
        }
    }

    private func inspectEnvironmentAndInstallation() {
        setupTask?.cancel()
        hooksFeatureStatus = .checking
        let inspector = environmentInspector
        let installer = installer
        setupTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                Result {
                    let environment = try inspector.inspect()
                    let installed = try installer.isInstalled()
                    return (environment, installed)
                }
            }.value
            guard let self, !Task.isCancelled else { return }
            switch result {
            case .success(let (environment, installed)):
                codexVersion = environment.version
                hooksFeatureStatus = environment.hooksEnabled
                    ? .enabled
                    : .disabled
                if isNativeActivityConnected {
                    connectionStatus = .connected
                    setupIslandRequested = false
                    render()
                } else if installed {
                    defaults.set(true, forKey: DefaultsKey.setupEnabled)
                    updateConnectionStatusFromInstalledState()
                } else {
                    connectionStatus = .notInstalled
                    setupIslandRequested = false
                    render()
                }
            case .failure(let error):
                hooksFeatureStatus = .unavailable
                if isNativeActivityConnected {
                    connectionStatus = .connected
                } else if defaults.bool(forKey: DefaultsKey.setupEnabled) {
                    connectionStatus = .abnormal(
                        error.localizedDescription
                    )
                } else {
                    connectionStatus = .notInstalled
                }
                render()
            }
        }
    }

    private func receive(_ delivery: CodexActivityDelivery) async -> Bool {
        let activity = delivery.activity
        if defaults.bool(forKey: DefaultsKey.setupEnabled) {
            guard canAcceptActivityAfterRequiredRestart() else {
                render()
                CodexActivityDiagnostics.record(
                    delivery: delivery,
                    outcome: "rejected_restart_required"
                )
                return false
            }

            let installationID = installer.installationIdentifier
            var evidence = CodexActivityConnectionEvidence(
                observedInstallationID: defaults.string(
                    forKey: DefaultsKey.observedInstallation
                ),
                connectedInstallationID: defaults.string(
                    forKey: DefaultsKey.connectedInstallation
                )
            )
            evidence.record(
                event: activity.event,
                installationID: installationID
            )
            defaults.set(
                evidence.observedInstallationID,
                forKey: DefaultsKey.observedInstallation
            )
            if let connectedInstallationID =
                evidence.connectedInstallationID
            {
                defaults.set(
                    connectedInstallationID,
                    forKey: DefaultsKey.connectedInstallation
                )
            }
            updateConnectionStatusFromInstalledState()
            if connectionStatus == .connected {
                setupIslandRequested = false
            }
        }
        let snapshotBeforeDelivery = store.snapshot
        let presentationBeforeDelivery = store.presentation
        let lifecycleBeforeDelivery = store.lifecycle
        await store.receiveClassified(delivery)
        let didApplyDelivery = store.snapshot != snapshotBeforeDelivery
            || store.presentation != presentationBeforeDelivery
            || store.lifecycle != lifecycleBeforeDelivery
        CodexActivityDiagnostics.record(
            delivery: delivery,
            outcome: didApplyDelivery
                ? "accepted_applied"
                : "accepted_ignored"
        )
        return true
    }

    private func canAcceptActivityAfterRequiredRestart() -> Bool {
        guard let baselineProcessIdentifier = defaults.object(
            forKey: DefaultsKey.restartProcessIdentifier
        ) as? Int
        else {
            return true
        }

        guard let currentProcessIdentifier =
            Self.runningCodexProcessIdentifier(),
            CodexActivityRestartRequirement(
                baselineProcessIdentifier: baselineProcessIdentifier
            ).isSatisfied(
                currentProcessIdentifier: currentProcessIdentifier
            )
        else {
            return false
        }

        defaults.removeObject(
            forKey: DefaultsKey.restartProcessIdentifier
        )
        return true
    }

    private func updateConnectionStatusFromInstalledState() {
        if isNativeActivityConnected {
            connectionStatus = .connected
            setupIslandRequested = false
            render()
            return
        }

        if case .failed(let message) = bridgeStatus {
            connectionStatus = .abnormal(message)
            render()
            return
        }

        let installationID = installer.installationIdentifier
        let reviewConfirmed = defaults.string(
            forKey: DefaultsKey.reviewConfirmedInstallation
        ) == installationID

        if let restartProcessIdentifier = defaults.object(
            forKey: DefaultsKey.restartProcessIdentifier
        ) as? Int {
            if restartProcessIdentifier == 0, reviewConfirmed {
                defaults.removeObject(
                    forKey: DefaultsKey.restartProcessIdentifier
                )
            } else {
                let currentProcessIdentifier =
                    Self.runningCodexProcessIdentifier()
                let requirement = CodexActivityRestartRequirement(
                    baselineProcessIdentifier: restartProcessIdentifier
                )
                if !requirement.isSatisfied(
                    currentProcessIdentifier: currentProcessIdentifier
                ) {
                    connectionStatus =
                        CodexActivitySetupStatusResolver.resolve(
                            evidenceStatus: .awaitingTrust,
                            reviewConfirmed: reviewConfirmed,
                            requiresRestart: true
                        )
                    render()
                    return
                }
                defaults.removeObject(
                    forKey: DefaultsKey.restartProcessIdentifier
                )
            }
        }

        let evidence = CodexActivityConnectionEvidence(
            observedInstallationID: defaults.string(
                forKey: DefaultsKey.observedInstallation
            ),
            connectedInstallationID: defaults.string(
                forKey: DefaultsKey.connectedInstallation
            )
        )
        let evidenceStatus = evidence.status(for: installationID)
        connectionStatus = CodexActivitySetupStatusResolver.resolve(
            evidenceStatus: evidenceStatus,
            reviewConfirmed: reviewConfirmed,
            requiresRestart: false
        )
        if connectionStatus == .connected {
            setupIslandRequested = false
        }
        render()
    }

    private func observeSecurityReviewCompletion() {
        securityReviewObservationTask?.cancel()
        let completionURL = securityReviewLauncher.reviewCompletionURL
        let installationID = installer.installationIdentifier
        securityReviewObservationTask = Task { [weak self] in
            for _ in 0..<1_200 {
                guard let self, !Task.isCancelled else { return }
                if FileManager.default.fileExists(
                    atPath: completionURL.path
                ) {
                    let result = try? String(
                        contentsOf: completionURL,
                        encoding: .utf8
                    ).trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    try? FileManager.default.removeItem(
                        at: completionURL
                    )
                    if result == "confirmed" {
                        self.defaults.set(
                            installationID,
                            forKey:
                                DefaultsKey.reviewConfirmedInstallation
                        )
                        self.updateConnectionStatusFromInstalledState()
                    } else {
                        self.connectionStatus = .abnormal(
                            self.localizedSetupMessage(
                                chinese:
                                    "Codex 安全确认未完成，请重试。",
                                english:
                                    "The Codex security review did not complete. Try again."
                            )
                        )
                        self.render()
                    }
                    return
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    private func finishCodexRestart(errorMessage: String?) {
        isConfiguring = false
        if let errorMessage {
            connectionStatus = .abnormal(errorMessage)
            render()
        } else {
            updateConnectionStatusFromInstalledState()
        }
    }

    private func localizedSetupMessage(
        chinese: String,
        english: String
    ) -> String {
        switch preferences.resolvedLanguage {
        case .simplifiedChinese: chinese
        case .english: english
        }
    }

    private static func runningCodexProcessIdentifier() -> pid_t? {
        NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.openai.codex"
        )
        .first(where: { !$0.isTerminated })?
        .processIdentifier
    }

    private func render() {
        defer { reconcileScreenTracking() }

        guard preferences.codexActivityIslandEnabled else {
            island?.hide()
            return
        }

        if shouldRenderDisconnectedIsland {
            renderDisconnectedIsland()
            return
        }

        guard let snapshot = store.snapshot,
              store.presentation != .hidden
        else {
            island?.hide()
            return
        }

        let title = store.resolvedThreadTitle
            ?? snapshot.workspaceName.map { "Codex · \($0)" }
            ?? "Codex"
        let copy = CodexActivityCopy(
            language: preferences.resolvedLanguage
        )
        let currentTurnTokenUsage = store.currentTurnTokenUsage
        let tokenUsageTitle = currentTurnTokenUsage.map {
            copy.tokenUsageTitle(totalTokens: $0)
        }
        let showsCompletionReceipt =
            CodexActivityTurnTokenUsagePresentationContract
            .showsCompletionReceipt(
                visualState: snapshot.state,
                operationKey: snapshot.operationKey,
                totalTokens: currentTurnTokenUsage
            )
        let completionQuotaRemainingPercent = showsCompletionReceipt
            ? currentQuotaPresentation?.remainingPercent
            : nil
        let baseAccessibilityLabel = copy.accessibilityLabel(
            windowTitle: title,
            statusTitle: copy.statusTitle(for: snapshot.state),
            operation: copy.operation(for: snapshot.operationKey),
            approximateProgressFraction:
                snapshot.approximateProgressFraction,
            tokenUsageTitle: tokenUsageTitle
        )
        let renderState = CodexActivityRenderState(
            taskIdentity: snapshot.taskIdentity,
            visualState: snapshot.state,
            approximateProgressFraction:
                snapshot.approximateProgressFraction,
            windowTitle: title,
            statusTitle: copy.statusTitle(for: snapshot.state),
            operation: copy.operation(
                for: snapshot.operationKey
            ),
            tokenUsageTitle: tokenUsageTitle,
            completionReceiptStatus: showsCompletionReceipt
                ? copy.statusTitle(for: snapshot.state)
                : nil,
            completionReceiptDetail: showsCompletionReceipt
                ? currentTurnTokenUsage.map {
                    copy.completionTokenUsageDetail(totalTokens: $0)
                }
                : nil,
            completionQuotaRemainingPercent:
                completionQuotaRemainingPercent,
            isConfirmationReminderActive:
                store.isConfirmationReminderActive,
            accessibilityLabel: showsCompletionReceipt
                ? baseAccessibilityLabel
                    + copy.completionQuotaAccessibilitySuffix(
                        remainingPercent:
                            completionQuotaRemainingPercent
                    )
                : baseAccessibilityLabel
        )
        let presentation: CodexActivityIslandPresentation =
            store.presentation == .compact ? .compact : .expanded
        let codexProcessIdentifier =
            Self.runningCodexProcessIdentifier()

        if island == nil {
            island = CodexActivityIslandPanelController(
                initialState: renderState,
                progressEffect:
                    preferences.codexActivityProgressEffect,
                screenPlacement:
                    preferences.codexActivityScreenPlacement,
                codexProcessIdentifier: codexProcessIdentifier
            )
        }
        island?.update(
            renderState: renderState,
            presentationMode: presentation,
            presentationAccessibilityValue:
                copy.presentationAccessibilityValue(presentation),
            reduceMotion:
                NSWorkspace.shared
                .accessibilityDisplayShouldReduceMotion,
            progressEffect: preferences.codexActivityProgressEffect,
            screenPlacement: preferences.codexActivityScreenPlacement,
            codexProcessIdentifier: codexProcessIdentifier,
            playbackEnabled: store.shouldPlayVisualEffects
        )
    }

    private func reconcileScreenTracking() {
        let shouldTrack = preferences.codexActivityIslandEnabled
            && preferences.codexActivityScreenPlacement == .codexScreen
            && island?.isVisible == true

        guard shouldTrack else {
            screenTrackingCancellable?.cancel()
            screenTrackingCancellable = nil
            return
        }
        guard screenTrackingCancellable == nil else { return }

        screenTrackingCancellable = Timer.publish(
            every: 1,
            on: .main,
            in: .common
        )
        .autoconnect()
        .sink { [weak self] _ in
            Task { @MainActor in
                guard let self,
                      let island = self.island,
                      island.isVisible
                else {
                    return
                }
                island.reposition(
                    screenPlacement: .codexScreen,
                    codexProcessIdentifier:
                        Self.runningCodexProcessIdentifier()
                )
            }
        }
    }

    private var shouldRenderDisconnectedIsland: Bool {
        guard connectionStatus != .connected else { return false }
        return setupIslandRequested
            || defaults.bool(forKey: DefaultsKey.setupEnabled)
    }

    private func renderDisconnectedIsland() {
        let copy = CodexActivityCopy(
            language: preferences.resolvedLanguage
        )
        let statusTitle = copy.statusTitle(
            for: .disconnectedCodex
        )
        let operation = copy.disconnectedOperation(
            for: connectionStatus,
            isConfiguring: isConfiguring || isOpeningSecurityReview
        )
        let renderState = CodexActivityRenderState(
            visualState: .disconnectedCodex,
            approximateProgressFraction: nil,
            windowTitle: "QuotaView",
            statusTitle: statusTitle,
            operation: operation,
            accessibilityLabel: copy.accessibilityLabel(
                windowTitle: "QuotaView",
                statusTitle: statusTitle,
                operation: operation,
                approximateProgressFraction: nil
            )
        )
        let codexProcessIdentifier =
            Self.runningCodexProcessIdentifier()

        if island == nil {
            island = CodexActivityIslandPanelController(
                initialState: renderState,
                progressEffect:
                    preferences.codexActivityProgressEffect,
                screenPlacement:
                    preferences.codexActivityScreenPlacement,
                codexProcessIdentifier: codexProcessIdentifier
            )
        }
        island?.update(
            renderState: renderState,
            presentationMode: .expanded,
            presentationAccessibilityValue:
                copy.presentationAccessibilityValue(.expanded),
            reduceMotion:
                NSWorkspace.shared
                .accessibilityDisplayShouldReduceMotion,
            progressEffect: preferences.codexActivityProgressEffect,
            screenPlacement: preferences.codexActivityScreenPlacement,
            codexProcessIdentifier: codexProcessIdentifier,
            playbackEnabled: false
        )
    }

    private static func defaultSocketURL() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("QuotaView", isDirectory: true)
            .appendingPathComponent("codex-activity.sock")
    }

    private static func defaultQueueURL() -> URL {
        URL(
            fileURLWithPath:
                "/tmp/com.quotaview.codex-activity-\(getuid())",
            isDirectory: true
        )
    }
}

enum CodexActivityTurnTokenUsagePresentationContract {
    static func showsCompletionReceipt(
        visualState: CodexActivityVisualState,
        operationKey: CodexActivityOperationKey,
        totalTokens: Int64?
    ) -> Bool {
        visualState == .completed
            && operationKey == .turnCompleted
            && totalTokens != nil
    }
}

enum CodexActivityTokenUsageFormatter {
    static func string(for totalTokens: Int64) -> String {
        let tokens = max(totalTokens, 0)
        if tokens >= 1_000_000 {
            return compact(
                Double(tokens) / 1_000_000,
                suffix: "M"
            )
        }
        if tokens >= 1_000 {
            return compact(Double(tokens) / 1_000, suffix: "K")
        }
        return String(tokens)
    }

    private static func compact(
        _ value: Double,
        suffix: String
    ) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded.rounded() == rounded {
            return "\(Int64(rounded))\(suffix)"
        }
        return String(
            format: "%.1f%@",
            locale: Locale(identifier: "en_US_POSIX"),
            rounded,
            suffix
        )
    }
}

struct CodexActivityCopy {
    let language: AppPreferences.Language

    func tokenUsageTitle(totalTokens: Int64) -> String {
        let count = CodexActivityTokenUsageFormatter.string(
            for: totalTokens
        )
        return switch language {
        case .simplifiedChinese: "本次 \(count) tokens"
        case .english: "This turn \(count) tokens"
        }
    }

    func completionTokenUsageDetail(totalTokens: Int64) -> String {
        let count = CodexActivityTokenUsageFormatter.string(
            for: totalTokens
        )
        return switch language {
        case .simplifiedChinese: "本次消耗 \(count) tokens"
        case .english: "\(count) tokens this turn"
        }
    }

    func completionQuotaAccessibilitySuffix(
        remainingPercent: Int?
    ) -> String {
        switch (language, remainingPercent) {
        case (.simplifiedChinese, .some(let remainingPercent)):
            "，当前额度剩余 \(min(max(remainingPercent, 0), 100))%"
        case (.simplifiedChinese, .none):
            "，当前额度剩余不可用"
        case (.english, .some(let remainingPercent)):
            ", current quota remaining: "
                + "\(min(max(remainingPercent, 0), 100)) percent"
        case (.english, .none):
            ", current quota remaining unavailable"
        }
    }

    func statusTitle(for state: CodexActivityVisualState) -> String {
        switch (language, state) {
        case (.simplifiedChinese, .disconnectedCodex):
            "未连接 Codex"
        case (.simplifiedChinese, .standby): "空闲"
        case (.simplifiedChinese, .thinking): "思考中"
        case (.simplifiedChinese, .working): "工作中"
        case (.simplifiedChinese, .compactingContext):
            "正在压缩上下文"
        case (.simplifiedChinese, .awaitingConfirmation): "待确认"
        case (.simplifiedChinese, .completed): "已完成"
        case (.simplifiedChinese, .error): "失败"
        case (.simplifiedChinese, .unavailable): "未载入"
        case (.english, .disconnectedCodex): "Codex Not Connected"
        case (.english, .standby): "Idle"
        case (.english, .thinking): "Thinking"
        case (.english, .working): "Working"
        case (.english, .compactingContext): "Compacting Context"
        case (.english, .awaitingConfirmation): "Awaiting Confirmation"
        case (.english, .completed): "Completed"
        case (.english, .error): "Failed"
        case (.english, .unavailable): "Not Loaded"
        }
    }

    func disconnectedOperation(
        for status: CodexActivityConnectionStatus,
        isConfiguring: Bool
    ) -> String {
        if isConfiguring {
            return switch language {
            case .simplifiedChinese:
                "正在准备 Codex 灵动岛连接"
            case .english:
                "Preparing the Codex island connection"
            }
        }

        return switch (language, status) {
        case (.simplifiedChinese, .notInstalled):
            "在 QuotaView 设置中连接 Codex 灵动岛"
        case (.simplifiedChinese, .installedNeedsRestart):
            "完成安全确认后重新启动 Codex"
        case (.simplifiedChinese, .awaitingTrust):
            "请在打开的 Codex 窗口完成安全确认"
        case (.simplifiedChinese, .awaitingFirstEvent):
            "向 Codex 发送一条新消息以完成连接"
        case (.simplifiedChinese, .connected):
            "Codex 灵动岛连接已激活"
        case (.simplifiedChinese, .abnormal):
            "连接遇到问题，请返回 QuotaView 设置"
        case (.english, .notInstalled):
            "Connect the Codex island in QuotaView Settings"
        case (.english, .installedNeedsRestart):
            "Restart Codex after completing the security review"
        case (.english, .awaitingTrust):
            "Complete the security review in the opened Codex window"
        case (.english, .awaitingFirstEvent):
            "Send a new Codex message to finish connecting"
        case (.english, .connected):
            "Codex activity is active"
        case (.english, .abnormal):
            "Connection needs attention in QuotaView Settings"
        }
    }

    func operation(for key: CodexActivityOperationKey) -> String {
        switch (language, key) {
        case (.simplifiedChinese, .connectingSession):
            "正在连接 Codex 会话"
        case (.simplifiedChinese, .sessionEnded):
            "Codex 会话已结束"
        case (.simplifiedChinese, .analyzingRequest):
            "正在分析新的任务"
        case (.simplifiedChinese, .executingShell):
            "正在执行终端操作"
        case (.simplifiedChinese, .editingFiles):
            "正在修改项目文件"
        case (.simplifiedChinese, .callingExternalTool):
            "正在调用外部工具"
        case (.simplifiedChinese, .coordinatingSubagent):
            "正在协调子任务"
        case (.simplifiedChinese, .usingLocalTool):
            "正在执行本地工具"
        case (.simplifiedChinese, .executingPlan):
            "正在执行多步骤计划"
        case (.simplifiedChinese, .managingGoal):
            "正在更新长期目标"
        case (.simplifiedChinese, .followingGoal):
            "正在跟进长期目标"
        case (.simplifiedChinese, .goalPaused):
            "长期目标已暂停"
        case (.simplifiedChinese, .goalBlocked):
            "长期目标需要处理"
        case (.simplifiedChinese, .goalLimited):
            "长期目标暂受用量限制"
        case (.simplifiedChinese, .goalCompleted):
            "长期目标已完成"
        case (.simplifiedChinese, .usingTool):
            "正在执行工具操作"
        case (.simplifiedChinese, .awaitingApproval):
            "有一项操作需要你的批准"
        case (.simplifiedChinese, .awaitingUserInput):
            "任务正在等待你的输入"
        case (.simplifiedChinese, .reviewingToolResult):
            "正在检查工具执行结果"
        case (.simplifiedChinese, .compactingContext):
            "正在整理较早消息以释放上下文空间"
        case (.simplifiedChinese, .continuingAfterCompaction):
            "上下文整理完成，正在继续任务"
        case (.simplifiedChinese, .subagentStarted):
            "子任务已启动"
        case (.simplifiedChinese, .subagentStopped):
            "正在汇总子任务结果"
        case (.simplifiedChinese, .turnCompleted):
            "当前任务已完成"
        case (.simplifiedChinese, .turnInterrupted):
            "当前任务已中断"
        case (.simplifiedChinese, .turnFailed):
            "当前任务执行失败"
        case (.simplifiedChinese, .bridgeUnavailable):
            "Codex 灵动岛连接不可用"
        case (.simplifiedChinese, .malformedEvent):
            "收到无法识别的 Codex 状态事件"
        case (.english, .connectingSession):
            "Connecting to the Codex session"
        case (.english, .sessionEnded):
            "The Codex session ended"
        case (.english, .analyzingRequest):
            "Analyzing the new task"
        case (.english, .executingShell):
            "Running a terminal operation"
        case (.english, .editingFiles):
            "Editing project files"
        case (.english, .callingExternalTool):
            "Calling an external tool"
        case (.english, .coordinatingSubagent):
            "Coordinating a subtask"
        case (.english, .usingLocalTool):
            "Running a local tool"
        case (.english, .executingPlan):
            "Executing a multi-step plan"
        case (.english, .managingGoal):
            "Updating the long-running goal"
        case (.english, .followingGoal):
            "Following the long-running goal"
        case (.english, .goalPaused):
            "The long-running goal is paused"
        case (.english, .goalBlocked):
            "The long-running goal needs attention"
        case (.english, .goalLimited):
            "The long-running goal is usage-limited"
        case (.english, .goalCompleted):
            "The long-running goal is complete"
        case (.english, .usingTool):
            "Running a tool"
        case (.english, .awaitingApproval):
            "An operation needs your approval"
        case (.english, .awaitingUserInput):
            "The task is waiting for your input"
        case (.english, .reviewingToolResult):
            "Reviewing the tool result"
        case (.english, .compactingContext):
            "Condensing earlier messages to free context"
        case (.english, .continuingAfterCompaction):
            "Context compacted; continuing the task"
        case (.english, .subagentStarted):
            "A subtask started"
        case (.english, .subagentStopped):
            "Summarizing subtask results"
        case (.english, .turnCompleted):
            "The current task is complete"
        case (.english, .turnInterrupted):
            "The current task was interrupted"
        case (.english, .turnFailed):
            "The current task failed"
        case (.english, .bridgeUnavailable):
            "The Codex island connection is unavailable"
        case (.english, .malformedEvent):
            "Received an unrecognized Codex status event"
        }
    }

    func accessibilityLabel(
        windowTitle: String,
        statusTitle: String,
        operation: String,
        approximateProgressFraction: Double?,
        tokenUsageTitle: String? = nil
    ) -> String {
        let progressText = approximateProgressFraction.map {
            String(Int((min(max($0, 0), 1) * 100).rounded()))
        }
        switch language {
        case .simplifiedChinese:
            if let progressText {
                return "\(windowTitle)，状态：\(statusTitle)，"
                    + "近似进度：\(progressText)%，当前操作：\(operation)"
                    + tokenUsageAccessibilitySuffix(tokenUsageTitle)
            }
            return "\(windowTitle)，状态：\(statusTitle)，"
                + "当前操作：\(operation)"
                + tokenUsageAccessibilitySuffix(tokenUsageTitle)
        case .english:
            if let progressText {
                return "\(windowTitle), status: \(statusTitle), "
                    + "approximate progress: \(progressText)%, "
                    + "current operation: \(operation)"
                    + tokenUsageAccessibilitySuffix(tokenUsageTitle)
            }
            return "\(windowTitle), status: \(statusTitle), "
                + "current operation: \(operation)"
                + tokenUsageAccessibilitySuffix(tokenUsageTitle)
        }
    }

    private func tokenUsageAccessibilitySuffix(
        _ tokenUsageTitle: String?
    ) -> String {
        guard let tokenUsageTitle else { return "" }
        return switch language {
        case .simplifiedChinese: "，\(tokenUsageTitle)"
        case .english: ", \(tokenUsageTitle)"
        }
    }

    func presentationAccessibilityValue(
        _ presentation: CodexActivityIslandPresentation
    ) -> String {
        switch (language, presentation) {
        case (.simplifiedChinese, .expanded): "展开"
        case (.simplifiedChinese, .compact): "紧凑"
        case (.english, .expanded): "Expanded"
        case (.english, .compact): "Compact"
        }
    }
}

typealias CodexActivityDeliveryHandler = (
    CodexActivityDelivery,
    @escaping @Sendable (Bool) -> Void
) -> Void

private struct CodexActivityDeliveryAcknowledgement: Codable {
    let eventID: String?
    let accepted: Bool
}

final class CodexActivityUnixBridge: @unchecked Sendable {
    enum BridgeError: LocalizedError {
        case socketCreationFailed
        case socketPathTooLong
        case bindFailed
        case listenFailed

        var errorDescription: String? {
            switch self {
            case .socketCreationFailed:
                "无法创建 Codex 灵动岛监听端口。"
            case .socketPathTooLong:
                "Codex 灵动岛监听路径过长。"
            case .bindFailed:
                "无法绑定 Codex 灵动岛监听端口。"
            case .listenFailed:
                "无法启动 Codex 灵动岛监听。"
            }
        }
    }

    private let socketURL: URL
    private let authenticationToken: String
    private let installationIdentifier: String
    private let queue = DispatchQueue(
        label: "com.duoasa.QuotaView.codex-activity-bridge",
        qos: .utility
    )
    private var source: DispatchSourceRead?
    private var descriptor: Int32 = -1
    private var handler: CodexActivityDeliveryHandler?

    init(
        socketURL: URL,
        authenticationToken: String,
        installationIdentifier: String
    ) {
        self.socketURL = socketURL
        self.authenticationToken = authenticationToken
        self.installationIdentifier = installationIdentifier
    }

    func start(
        handler: @escaping CodexActivityDeliveryHandler
    ) throws {
        stop()
        self.handler = handler

        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: socketURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        unlink(socketURL.path)

        let pathBytes = Array(socketURL.path.utf8CString)
        var address = sockaddr_un()
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path)
        else {
            throw BridgeError.socketPathTooLong
        }

        let listener = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0 else {
            throw BridgeError.socketCreationFailed
        }
        descriptor = listener

        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            destination.initializeMemory(as: UInt8.self, repeating: 0)
            pathBytes.withUnsafeBytes { source in
                destination.copyBytes(from: source)
            }
        }

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(
                to: sockaddr.self,
                capacity: 1
            ) { socketAddress in
                Darwin.bind(
                    listener,
                    socketAddress,
                    socklen_t(MemoryLayout<sockaddr_un>.size)
                )
            }
        }
        guard bindResult == 0 else {
            Darwin.close(listener)
            descriptor = -1
            throw BridgeError.bindFailed
        }

        chmod(socketURL.path, S_IRUSR | S_IWUSR)
        guard Darwin.listen(listener, 16) == 0 else {
            Darwin.close(listener)
            descriptor = -1
            unlink(socketURL.path)
            throw BridgeError.listenFailed
        }

        let flags = fcntl(listener, F_GETFL)
        _ = fcntl(listener, F_SETFL, flags | O_NONBLOCK)

        let source = DispatchSource.makeReadSource(
            fileDescriptor: listener,
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.acceptAvailableConnections()
        }
        self.source = source
        source.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
        if descriptor >= 0 {
            Darwin.close(descriptor)
            descriptor = -1
        }
        unlink(socketURL.path)
        handler = nil
    }

    private func acceptAvailableConnections() {
        guard descriptor >= 0 else { return }
        while true {
            let connection = Darwin.accept(descriptor, nil, nil)
            guard connection >= 0 else { return }
            var noSigPipe: Int32 = 1
            setsockopt(
                connection,
                SOL_SOCKET,
                SO_NOSIGPIPE,
                &noSigPipe,
                socklen_t(MemoryLayout<Int32>.size)
            )
            read(connection: connection)
        }
    }

    private func read(connection: Int32) {
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(
            connection,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &timeout,
            socklen_t(MemoryLayout<timeval>.size)
        )
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8_192)

        while data.count <= 65_536 {
            let count = Darwin.recv(
                connection,
                &buffer,
                buffer.count,
                0
            )
            guard count > 0 else { break }
            data.append(buffer, count: count)

            if let envelope = try? JSONDecoder().decode(
                CodexActivityBridgeEnvelope.self,
                from: data
            ) {
                guard authenticationTokensMatch(
                    envelope.authenticationToken,
                    authenticationToken
                ),
                authenticationTokensMatch(
                    envelope.installationIdentifier,
                    installationIdentifier
                )
                else {
                    Darwin.close(connection)
                    return
                }
                guard let handler else {
                    sendAcknowledgement(
                        eventID: envelope.eventID,
                        accepted: false,
                        connection: connection
                    )
                    return
                }
                let delivery = CodexActivityDelivery(
                    eventID: envelope.eventID,
                    source: .liveSocket,
                    activity: envelope.activity
                )
                handler(delivery) { [weak self] accepted in
                    guard let self else {
                        Darwin.close(connection)
                        return
                    }
                    self.sendAcknowledgement(
                        eventID: envelope.eventID,
                        accepted: accepted,
                        connection: connection
                    )
                }
                return
            }
        }
        Darwin.close(connection)
    }

    private func sendAcknowledgement(
        eventID: String?,
        accepted: Bool,
        connection: Int32
    ) {
        defer { Darwin.close(connection) }
        guard let payload = try? JSONEncoder().encode(
            CodexActivityDeliveryAcknowledgement(
                eventID: eventID,
                accepted: accepted
            )
        ) else {
            return
        }
        _ = payload.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return false
            }
            var pointer = baseAddress
            var remaining = buffer.count
            while remaining > 0 {
                let written = Darwin.send(
                    connection,
                    pointer,
                    remaining,
                    0
                )
                guard written > 0 else { return false }
                pointer = pointer.advanced(by: written)
                remaining -= written
            }
            return true
        }
    }
}

final class CodexActivityFileBridge: @unchecked Sendable {
    enum BridgeError: LocalizedError {
        case queueCreationFailed
        case unsafeQueueDirectory
        case queueWatchFailed

        var errorDescription: String? {
            switch self {
            case .queueCreationFailed:
                "无法创建 Codex 灵动岛事件队列。"
            case .unsafeQueueDirectory:
                "Codex 灵动岛事件队列的权限不安全。"
            case .queueWatchFailed:
                "无法监听 Codex 灵动岛事件队列。"
            }
        }
    }

    private static let maximumPayloadBytes = 65_536
    private static let maximumQueuedFiles = 128
    private static let staleEventAge: TimeInterval = 300

    private let queueURL: URL
    private let authenticationToken: String
    private let installationIdentifier: String
    private let queue = DispatchQueue(
        label: "com.duoasa.QuotaView.codex-activity-file-bridge",
        qos: .utility
    )
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: Int32 = -1
    private var handler: CodexActivityDeliveryHandler?
    private var startupReplayFileNames: Set<String> = []
    private var inFlightFileNames: Set<String> = []

    init(
        queueURL: URL,
        authenticationToken: String,
        installationIdentifier: String
    ) {
        self.queueURL = queueURL
        self.authenticationToken = authenticationToken
        self.installationIdentifier = installationIdentifier
    }

    func start(
        handler: @escaping CodexActivityDeliveryHandler
    ) throws {
        stop()
        try prepareQueueDirectory()
        self.handler = handler
        startupReplayFileNames = Set(
            eventURLsInQueue().map(\.lastPathComponent)
        )

        let directoryDescriptor = Darwin.open(
            queueURL.path,
            O_EVTONLY | O_CLOEXEC
        )
        guard directoryDescriptor >= 0 else {
            self.handler = nil
            throw BridgeError.queueWatchFailed
        }
        descriptor = directoryDescriptor

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: directoryDescriptor,
            eventMask: [.write, .extend],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.drainAvailableEvents()
        }
        self.source = source
        source.resume()
        queue.async { [weak self] in
            self?.drainAvailableEvents()
        }
    }

    func stop() {
        source?.cancel()
        source = nil
        if descriptor >= 0 {
            Darwin.close(descriptor)
            descriptor = -1
        }
        handler = nil
        startupReplayFileNames.removeAll()
        inFlightFileNames.removeAll()
    }

    private func prepareQueueDirectory() throws {
        let path = queueURL.path
        var metadata = stat()
        if lstat(path, &metadata) == 0 {
            guard metadata.st_uid == getuid(),
                  metadata.st_mode & S_IFMT == S_IFDIR
            else {
                throw BridgeError.unsafeQueueDirectory
            }
        } else {
            guard mkdir(path, S_IRWXU) == 0 else {
                throw BridgeError.queueCreationFailed
            }
        }

        guard chmod(path, S_IRWXU) == 0,
              lstat(path, &metadata) == 0,
              metadata.st_uid == getuid(),
              metadata.st_mode & S_IFMT == S_IFDIR,
              metadata.st_mode & (S_IRWXG | S_IRWXO) == 0
        else {
            throw BridgeError.unsafeQueueDirectory
        }
    }

    private func drainAvailableEvents() {
        let eventURLs = eventURLsInQueue()
        var deliveries: [(
            url: URL,
            delivery: CodexActivityDelivery
        )] = []
        for url in eventURLs.prefix(Self.maximumQueuedFiles) {
            let fileName = url.lastPathComponent
            guard !inFlightFileNames.contains(fileName) else { continue }
            guard let data = readPayload(at: url),
                  let envelope = try? JSONDecoder().decode(
                      CodexActivityBridgeEnvelope.self,
                      from: data
                  ),
                  authenticationTokensMatch(
                      envelope.authenticationToken,
                      authenticationToken
                  ),
                  authenticationTokensMatch(
                      envelope.installationIdentifier,
                      installationIdentifier
                  ),
                  abs(envelope.activity.occurredAt.timeIntervalSinceNow)
                    <= Self.staleEventAge
            else {
                unlink(url.path)
                startupReplayFileNames.remove(fileName)
                continue
            }
            let source: CodexActivityDeliverySource =
                startupReplayFileNames.contains(fileName)
                ? .startupReplay
                : .liveQueue
            deliveries.append((
                url: url,
                delivery: CodexActivityDelivery(
                    eventID: envelope.eventID,
                    source: source,
                    activity: envelope.activity
                )
            ))
        }

        deliveries.sort {
            $0.delivery.activity.occurredAt
                < $1.delivery.activity.occurredAt
        }
        for item in deliveries {
            let fileName = item.url.lastPathComponent
            guard let handler else { return }
            inFlightFileNames.insert(fileName)
            handler(item.delivery) { [weak self] accepted in
                guard let self else { return }
                self.queue.async {
                    self.inFlightFileNames.remove(fileName)
                    guard accepted else { return }
                    unlink(item.url.path)
                    self.startupReplayFileNames.remove(fileName)
                    self.drainAvailableEvents()
                }
            }
        }
    }

    private func eventURLsInQueue() -> [URL] {
        let fileManager = FileManager.default
        guard let urls = try? fileManager.contentsOfDirectory(
            at: queueURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return urls
            .filter {
                $0.pathExtension == "json"
                    && $0.lastPathComponent.hasPrefix("event-")
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func readPayload(at url: URL) -> Data? {
        let fileDescriptor = Darwin.open(
            url.path,
            O_RDONLY | O_NOFOLLOW | O_CLOEXEC
        )
        guard fileDescriptor >= 0 else { return nil }
        defer { Darwin.close(fileDescriptor) }

        var metadata = stat()
        guard fstat(fileDescriptor, &metadata) == 0,
              metadata.st_uid == getuid(),
              metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_size > 0,
              metadata.st_size <= Self.maximumPayloadBytes
        else {
            return nil
        }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8_192)
        while data.count <= Self.maximumPayloadBytes {
            let count = Darwin.read(
                fileDescriptor,
                &buffer,
                min(
                    buffer.count,
                    Self.maximumPayloadBytes + 1 - data.count
                )
            )
            guard count >= 0 else { return nil }
            guard count > 0 else { return data }
            data.append(buffer, count: count)
        }
        return nil
    }
}

private func authenticationTokensMatch(
    _ received: String,
    _ expected: String
) -> Bool {
    let receivedBytes = Array(received.utf8)
    let expectedBytes = Array(expected.utf8)
    guard receivedBytes.count == expectedBytes.count else {
        return false
    }
    var difference: UInt8 = 0
    for index in receivedBytes.indices {
        difference |= receivedBytes[index] ^ expectedBytes[index]
    }
    return difference == 0
}

private enum CodexActivitySetupResult {
    case notInstalled
    case installed(
        environment: CodexActivityEnvironmentInspection,
        hookDefinitionChanged: Bool
    )
}

struct CodexActivityConnectionEvidence: Equatable {
    var observedInstallationID: String?
    var connectedInstallationID: String?

    mutating func record(
        event: CodexActivityHookEvent,
        installationID: String
    ) {
        observedInstallationID = installationID
        if event == .userPromptSubmit {
            connectedInstallationID = installationID
        }
    }

    func status(
        for installationID: String
    ) -> CodexActivityConnectionStatus {
        if connectedInstallationID == installationID {
            return .connected
        }
        if observedInstallationID == installationID {
            return .awaitingFirstEvent
        }
        return .awaitingTrust
    }
}

struct CodexActivityRestartRequirement: Equatable {
    let baselineProcessIdentifier: Int

    func isSatisfied(
        currentProcessIdentifier: pid_t?
    ) -> Bool {
        guard let currentProcessIdentifier else { return false }
        return Int(currentProcessIdentifier)
            != baselineProcessIdentifier
    }
}

struct CodexActivitySetupStatusResolver {
    static func resolve(
        evidenceStatus: CodexActivityConnectionStatus,
        reviewConfirmed: Bool,
        requiresRestart: Bool
    ) -> CodexActivityConnectionStatus {
        if requiresRestart {
            return reviewConfirmed
                ? .installedNeedsRestart
                : .awaitingTrust
        }
        if evidenceStatus == .awaitingTrust, reviewConfirmed {
            return .awaitingFirstEvent
        }
        return evidenceStatus
    }
}

struct CodexActivityEnvironmentInspection: Sendable {
    let version: String
    let hooksEnabled: Bool
    let didEnableHooks: Bool
}

struct CodexActivityEnvironmentInspector: Sendable {
    enum InspectionError: LocalizedError {
        case codexUnavailable
        case commandFailed(String)
        case commandTimedOut
        case hooksFeatureUnavailable

        var errorDescription: String? {
            switch self {
            case .codexUnavailable:
                "找不到支持 Hooks 的 Codex 安装。"
            case .commandFailed(let message):
                "检测 Codex 环境失败：\(message)"
            case .commandTimedOut:
                "检测 Codex 环境超时。"
            case .hooksFeatureUnavailable:
                "当前 Codex 版本未提供 Hooks 功能。"
            }
        }
    }

    private struct CommandResult {
        let standardOutput: String
        let standardError: String
    }

    let executablePath: String?
    let timeout: TimeInterval

    init(
        executablePath: String? = CodexExecutableLocator.locate(),
        timeout: TimeInterval = 8
    ) {
        self.executablePath = executablePath
        self.timeout = max(timeout, 1)
    }

    func inspect() throws -> CodexActivityEnvironmentInspection {
        guard let executablePath else {
            throw InspectionError.codexUnavailable
        }
        let versionResult = try run(
            executablePath: executablePath,
            arguments: ["--version"]
        )
        let version = versionResult.standardOutput
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !version.isEmpty else {
            throw InspectionError.commandFailed(
                versionResult.standardError
            )
        }

        let featureResult = try run(
            executablePath: executablePath,
            arguments: ["features", "list"]
        )
        guard let hooksEnabled = Self.hooksEnabled(
            in: featureResult.standardOutput
        ) else {
            throw InspectionError.hooksFeatureUnavailable
        }
        return CodexActivityEnvironmentInspection(
            version: version,
            hooksEnabled: hooksEnabled,
            didEnableHooks: false
        )
    }

    func inspectAndEnableHooksIfNeeded()
        throws -> CodexActivityEnvironmentInspection
    {
        let current = try inspect()
        guard !current.hooksEnabled else { return current }
        guard let executablePath else {
            throw InspectionError.codexUnavailable
        }

        _ = try run(
            executablePath: executablePath,
            arguments: ["features", "enable", "hooks"]
        )
        let updated = try inspect()
        guard updated.hooksEnabled else {
            throw InspectionError.hooksFeatureUnavailable
        }
        return CodexActivityEnvironmentInspection(
            version: updated.version,
            hooksEnabled: true,
            didEnableHooks: true
        )
    }

    private func run(
        executablePath: String,
        arguments: [String]
    ) throws -> CommandResult {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = standardOutput
        process.standardError = standardError

        do {
            try process.run()
        } catch {
            throw InspectionError.commandFailed(
                error.localizedDescription
            )
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        guard !process.isRunning else {
            process.terminate()
            process.waitUntilExit()
            throw InspectionError.commandTimedOut
        }

        let outputData = standardOutput.fileHandleForReading
            .readDataToEndOfFile()
        let errorData = standardError.fileHandleForReading
            .readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let error = String(data: errorData, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            let message = error
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw InspectionError.commandFailed(
                message.isEmpty ? "exit \(process.terminationStatus)" : message
            )
        }
        return CommandResult(
            standardOutput: output,
            standardError: error
        )
    }

    private static func hooksEnabled(in output: String) -> Bool? {
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.first == "hooks" else { continue }
            if fields.last == "true" { return true }
            if fields.last == "false" { return false }
        }
        return nil
    }
}

struct CodexSecurityReviewLauncher: Sendable {
    enum LaunchError: LocalizedError {
        case codexUnavailable
        case expectUnavailable
        case couldNotPrepareLauncher
        case couldNotOpenTerminal

        var errorDescription: String? {
            switch self {
            case .codexUnavailable:
                "找不到可用于安全确认的 Codex CLI。"
            case .expectUnavailable:
                "当前系统缺少打开 Codex 安全确认所需的终端组件。"
            case .couldNotPrepareLauncher:
                "无法准备 Codex 安全确认窗口。"
            case .couldNotOpenTerminal:
                "无法打开 Codex 安全确认窗口。"
            }
        }
    }

    let codexExecutablePath: String?
    let launcherDirectoryURL: URL
    let reviewCompletionURL: URL

    init(
        codexExecutablePath: String?,
        launcherDirectoryURL: URL? = nil,
        reviewCompletionURL: URL? = nil
    ) {
        self.codexExecutablePath = codexExecutablePath
        let resolvedLauncherDirectoryURL: URL
        if let launcherDirectoryURL {
            resolvedLauncherDirectoryURL = launcherDirectoryURL
        } else {
            resolvedLauncherDirectoryURL = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
                .appendingPathComponent("QuotaView", isDirectory: true)
                .appendingPathComponent("Launchers", isDirectory: true)
        }
        self.launcherDirectoryURL = resolvedLauncherDirectoryURL
        self.reviewCompletionURL = reviewCompletionURL
            ?? resolvedLauncherDirectoryURL.appendingPathComponent(
                "QuotaViewHookReviewComplete"
            )
    }

    func prepareLauncher() throws -> URL {
        guard let codexExecutablePath,
              FileManager.default.isExecutableFile(
                atPath: codexExecutablePath
              )
        else {
            throw LaunchError.codexUnavailable
        }
        guard FileManager.default.isExecutableFile(
            atPath: "/usr/bin/expect"
        ) else {
            throw LaunchError.expectUnavailable
        }

        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(
                at: launcherDirectoryURL,
                withIntermediateDirectories: true
            )
            chmod(launcherDirectoryURL.path, S_IRWXU)

            let expectURL = launcherDirectoryURL
                .appendingPathComponent("QuotaViewHookReview.exp")
            let launcherURL = launcherDirectoryURL
                .appendingPathComponent("Open Codex Security Review.command")
            if fileManager.fileExists(
                atPath: reviewCompletionURL.path
            ) {
                try fileManager.removeItem(at: reviewCompletionURL)
            }
            let expectScript = """
            #!/usr/bin/expect -f
            set timeout 180
            set codex_path [lindex $argv 0]
            set completion_path [lindex $argv 1]
            proc write_result {path value} {
                set result_file [open $path w]
                puts $result_file $value
                close $result_file
                file attributes $path -permissions 0600
            }
            spawn -noecho $codex_path
            expect {
                -re {›} {
                }
                timeout {
                    write_result $completion_path "failed:prompt-timeout"
                    puts stderr "Timed out waiting for the Codex prompt."
                    exit 124
                }
                eof {
                    catch wait result
                    exit [lindex $result 3]
                }
            }

            set setup_deadline [expr {[clock milliseconds] + 240000}]
            set review_ready 0
            for {set attempt 0} {$attempt < 6 && !$review_ready} {incr attempt} {
                set quiet_deadline [expr {[clock milliseconds] + 3000}]
                while {[clock milliseconds] < $setup_deadline} {
                    set timeout 1
                    expect {
                        -re {.+} {
                            set quiet_deadline [expr {[clock milliseconds] + 3000}]
                        }
                        timeout {
                        }
                        eof {
                            catch wait result
                            exit [lindex $result 3]
                        }
                    }
                    if {[clock milliseconds] >= $quiet_deadline} {
                        break
                    }
                }

                send -- "/hooks\\r"
                set timeout 15
                expect {
                    -re {Press t to trust all} {
                        set review_ready 1
                    }
                    -re {Press enter to view hooks} {
                        write_result $completion_path "confirmed"
                        close
                        catch wait
                        exit 0
                    }
                    timeout {
                    }
                    eof {
                        catch wait result
                        exit [lindex $result 3]
                    }
                }
            }
            if {!$review_ready} {
                write_result $completion_path "failed:review-timeout"
                puts stderr "Timed out opening the Codex hook review."
                exit 125
            }

            interact {
                -re {[tT]} {
                    send -- $interact_out(0,string)
                    set timeout 30
                    expect {
                        -re {Press enter to view hooks} {
                            write_result $completion_path "confirmed"
                            close
                            catch wait
                            exit 0
                        }
                        timeout {
                            write_result $completion_path "failed:trust-not-confirmed"
                            puts stderr "Codex did not confirm hook trust."
                            exit 126
                        }
                        eof {
                            catch wait result
                            exit [lindex $result 3]
                        }
                    }
                }
            }
            """
            let launcherScript = """
            #!/bin/zsh
            exec /usr/bin/expect \
            \(Self.shellQuote(expectURL.path)) \
            \(Self.shellQuote(codexExecutablePath)) \
            \(Self.shellQuote(reviewCompletionURL.path))
            """

            try Data(expectScript.utf8).write(
                to: expectURL,
                options: .atomic
            )
            try Data(launcherScript.utf8).write(
                to: launcherURL,
                options: .atomic
            )
            chmod(expectURL.path, S_IRUSR | S_IWUSR | S_IXUSR)
            chmod(launcherURL.path, S_IRUSR | S_IWUSR | S_IXUSR)
            return launcherURL
        } catch {
            throw LaunchError.couldNotPrepareLauncher
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(
            of: "'",
            with: "'\\''"
        ) + "'"
    }
}

enum CodexActivityDiagnostics {
    private static let maximumLogBytes: off_t = 65_536

    static var logURL: URL {
        URL(
            fileURLWithPath:
                "/tmp/com.quotaview.codex-activity-\(getuid())",
            isDirectory: true
        )
        .appendingPathComponent("diagnostics.log")
    }

    static func record(
        delivery: CodexActivityDelivery,
        outcome: String
    ) {
        let path = logURL.path
        let descriptor = Darwin.open(
            path,
            O_WRONLY | O_CREAT | O_APPEND | O_NOFOLLOW | O_CLOEXEC,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else { return }
        defer { Darwin.close(descriptor) }

        guard Darwin.lockf(descriptor, F_LOCK, 0) == 0 else { return }
        defer { Darwin.lockf(descriptor, F_ULOCK, 0) }

        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              metadata.st_uid == getuid(),
              metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_mode & (S_IRWXG | S_IRWXO) == 0
        else {
            return
        }

        if metadata.st_size >= maximumLogBytes {
            guard ftruncate(descriptor, 0) == 0 else { return }
        }

        let activity = delivery.activity
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let session = String(activity.sessionHash.prefix(12))
        let turn = activity.turnHash.map { String($0.prefix(12)) } ?? "none"
        let eventID = delivery.eventID.map {
            String($0.prefix(12))
        } ?? "legacy"
        let activitySource = activity.source?.rawValue ?? "unknown"
        let planSource = activity.planSource?.rawValue ?? "none"
        let line = "\(timestamp) event=\(activity.event.rawValue) source=\(delivery.source.rawValue) activity_source=\(activitySource) plan_source=\(planSource) outcome=\(outcome) session=\(session) turn=\(turn) id=\(eventID)\n"
        _ = line.withCString { pointer in
            Darwin.write(descriptor, pointer, strlen(pointer))
        }
    }
}

struct CodexActivityHookInstaller: Sendable {
    enum InstallationError: LocalizedError {
        case helperUnavailable
        case invalidHooksFile
        case helperInstallationFailed

        var errorDescription: String? {
            switch self {
            case .helperUnavailable:
                "当前 QuotaView 构建中缺少活动 Hook 辅助程序。"
            case .invalidHooksFile:
                "现有 Codex hooks.json 不是有效的 JSON 对象。"
            case .helperInstallationFailed:
                "无法将 Codex 灵动岛 Helper 安装到固定路径。"
            }
        }
    }

    struct InstallationResult: Sendable {
        let hookDefinitionChanged: Bool
    }

    private static let commandMarker = "QuotaViewActivityHook"
    private static let eventNames = CodexActivityHookEvent.allCases
        .map(\.rawValue)

    let socketURL: URL
    let authenticationToken: String
    let hooksURL: URL
    let bundledHelperURL: URL
    let installedHelperURL: URL

    init(
        socketURL: URL,
        authenticationToken: String,
        hooksURL: URL? = nil,
        helperURL: URL? = nil,
        installedHelperURL: URL? = nil
    ) {
        self.socketURL = socketURL
        self.authenticationToken = authenticationToken
        self.hooksURL = hooksURL
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex", isDirectory: true)
                .appendingPathComponent("hooks.json")
        self.bundledHelperURL = helperURL
            ?? Bundle.main.bundleURL
                .appendingPathComponent("Contents/Helpers")
                .appendingPathComponent(Self.commandMarker)
        if let installedHelperURL {
            self.installedHelperURL = installedHelperURL
        } else if hooksURL != nil || helperURL != nil {
            self.installedHelperURL = self.bundledHelperURL
        } else {
            self.installedHelperURL = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
                .appendingPathComponent("QuotaView", isDirectory: true)
                .appendingPathComponent("Helpers", isDirectory: true)
                .appendingPathComponent(Self.commandMarker)
        }
    }

    var installationIdentifier: String {
        CodexActivityPrivacy.hashIdentifier(baseHookCommand())
    }

    func isInstalled() throws -> Bool {
        guard FileManager.default.fileExists(atPath: hooksURL.path) else {
            return false
        }
        let root = try readRoot()
        let hooks = try readHooks(from: root)
        let expectedCommand = hookCommand()
        return Self.eventNames.allSatisfy { eventName in
            guard let groups = hooks[eventName] as? [[String: Any]]
            else {
                return false
            }
            return groups.contains { group in
                handlers(in: group).contains {
                    command(in: $0) == expectedCommand
                }
            }
        }
    }

    func hasQuotaViewHandlers() throws -> Bool {
        guard FileManager.default.fileExists(atPath: hooksURL.path) else {
            return false
        }
        let hooks = try readHooks(from: readRoot())
        return hooks.values.contains { value in
            guard let groups = value as? [[String: Any]] else {
                return false
            }
            return groups.contains { group in
                handlers(in: group).contains {
                    command(in: $0).contains(Self.commandMarker)
                }
            }
        }
    }

    func install() throws -> InstallationResult {
        guard FileManager.default.isExecutableFile(
            atPath: bundledHelperURL.path
        )
        else {
            throw InstallationError.helperUnavailable
        }

        let hookDefinitionChanged = try !isInstalled()
        try installHelper()

        var root = try readRoot(allowMissing: true)
        var hooks = try readHooks(from: root)
        hooks = removingQuotaViewHandlers(from: hooks)

        let command = hookCommand()

        for eventName in Self.eventNames {
            var groups = hooks[eventName] as? [[String: Any]] ?? []
            let timeout = eventName == HookEventName.sessionEnd ? 1 : 2
            groups.append([
                "hooks": [[
                    "type": "command",
                    "command": command,
                    "timeout": timeout
                ]]
            ])
            hooks[eventName] = groups
        }

        root["hooks"] = hooks
        try writeRoot(root)
        return InstallationResult(
            hookDefinitionChanged: hookDefinitionChanged
        )
    }

    func uninstall() throws {
        if FileManager.default.fileExists(atPath: hooksURL.path) {
            var root = try readRoot()
            let hooks = try readHooks(from: root)
            root["hooks"] = removingQuotaViewHandlers(from: hooks)
            try writeRoot(root)
        }
        if installedHelperURL != bundledHelperURL,
           FileManager.default.fileExists(atPath: installedHelperURL.path)
        {
            try FileManager.default.removeItem(at: installedHelperURL)
        }
    }

    private func readRoot(
        allowMissing: Bool = false
    ) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: hooksURL.path) else {
            if allowMissing {
                return [
                    "description":
                        "User-level Codex hooks, including QuotaView activity."
                ]
            }
            return [:]
        }

        let data = try Data(contentsOf: hooksURL)
        guard let object = try JSONSerialization.jsonObject(with: data)
            as? [String: Any]
        else {
            throw InstallationError.invalidHooksFile
        }
        return object
    }

    private func readHooks(
        from root: [String: Any]
    ) throws -> [String: Any] {
        guard let value = root["hooks"] else {
            return [:]
        }
        guard let hooks = value as? [String: Any] else {
            throw InstallationError.invalidHooksFile
        }

        for value in hooks.values {
            guard let groups = value as? [[String: Any]] else {
                throw InstallationError.invalidHooksFile
            }
            for group in groups {
                guard group["hooks"] as? [[String: Any]] != nil else {
                    throw InstallationError.invalidHooksFile
                }
            }
        }
        return hooks
    }

    private func writeRoot(_ root: [String: Any]) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: hooksURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if fileManager.fileExists(atPath: hooksURL.path) {
            let backupURL = hooksURL.appendingPathExtension(
                "quotaview-backup"
            )
            if !fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.copyItem(at: hooksURL, to: backupURL)
            }
        }

        let data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: hooksURL, options: .atomic)
        chmod(hooksURL.path, S_IRUSR | S_IWUSR)
    }

    private func installHelper() throws {
        if bundledHelperURL == installedHelperURL {
            guard FileManager.default.isExecutableFile(
                atPath: installedHelperURL.path
            ) else {
                throw InstallationError.helperInstallationFailed
            }
            return
        }

        let fileManager = FileManager.default
        let directoryURL = installedHelperURL
            .deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        chmod(directoryURL.path, S_IRWXU)

        let temporaryURL = directoryURL.appendingPathComponent(
            ".\(Self.commandMarker)-\(UUID().uuidString)",
            isDirectory: false
        )
        do {
            try fileManager.copyItem(
                at: bundledHelperURL,
                to: temporaryURL
            )
            chmod(temporaryURL.path, S_IRWXU)
            if fileManager.fileExists(atPath: installedHelperURL.path) {
                _ = try fileManager.replaceItemAt(
                    installedHelperURL,
                    withItemAt: temporaryURL
                )
            } else {
                try fileManager.moveItem(
                    at: temporaryURL,
                    to: installedHelperURL
                )
            }
            chmod(installedHelperURL.path, S_IRWXU)
            guard fileManager.isExecutableFile(
                atPath: installedHelperURL.path
            ) else {
                throw InstallationError.helperInstallationFailed
            }
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            if error is InstallationError {
                throw error
            }
            throw InstallationError.helperInstallationFailed
        }
    }

    private func removingQuotaViewHandlers(
        from hooks: [String: Any]
    ) -> [String: Any] {
        var result = hooks
        for (eventName, value) in hooks {
            guard let groups = value as? [[String: Any]] else {
                continue
            }

            let cleanedGroups = groups.compactMap { group -> [String: Any]? in
                let remaining = handlers(in: group).filter {
                    !command(in: $0).contains(Self.commandMarker)
                }
                guard !remaining.isEmpty else { return nil }
                var updated = group
                updated["hooks"] = remaining
                return updated
            }
            result[eventName] = cleanedGroups
        }
        return result
    }

    private func handlers(
        in group: [String: Any]
    ) -> [[String: Any]] {
        group["hooks"] as? [[String: Any]] ?? []
    }

    private func command(in handler: [String: Any]) -> String {
        handler["command"] as? String ?? ""
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func hookCommand() -> String {
        [
            baseHookCommand(),
            "--installation-id",
            shellQuote(installationIdentifier)
        ].joined(separator: " ")
    }

    private func baseHookCommand() -> String {
        [
            shellQuote(installedHelperURL.path),
            "--socket",
            shellQuote(socketURL.path),
            "--token",
            shellQuote(authenticationToken)
        ].joined(separator: " ")
    }

    private enum HookEventName {
        static let sessionEnd = "SessionEnd"
    }
}
