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

    func receiveLocalPublicContent(_ content: CodexLocalPublicContent, generation expected: UInt64? = nil) {
        let run = expected ?? nativeGeneration
        guard nativeGeneration == run else { return }
        if taskRegistry.permitsPublicAttachment(session: content.sessionHash, turn: content.turnHash,
            source: .localRollout, occurredAt: content.occurredAt, permitsTerminal: true) {
            localPublicContentDidReceive?(content)
        } else if !taskRegistry.isPriorTurn(session: content.sessionHash, turn: content.turnHash) {
            // Disk details never create a task. Retain bounded context until the
            // matching identified lifecycle receives positive current evidence.
            pendingLocalPublicContent.append(content)
            while pendingLocalPublicContent.count > 200
                || pendingLocalPublicContent.reduce(0, { $0 + $1.data.count }) > 2_097_152 {
                pendingLocalPublicContent.removeFirst()
            }
        }
    }

    private func flushLocalPublicContent(for session: String) {
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
        let kind = metadata.map { CodexActivitySessionKind.classify(source: $0["source"], threadSource: $0["threadSource"] as? String) }
            ?? sessionKinds[session] ?? .user // Shared already verified this connection's thread metadata.
        guard kind != .internalTask else { return }

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
        } else if let known = sessionKinds[session], known != .unknown {
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
        guard kind == .user else { return false }
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
    }

    /// Unfollow cancels a receipt even before its first capability reaches the
    /// Island. An in-flight source classifier cannot reattach a detached scope.
    func cancelDesktopAttachment(conversationID: String) {
        desktopReceiptReservations.removeValue(forKey: CodexActivityPrivacy.hashIdentifier(conversationID))
    }

    /// Resource revocation cancels in-flight attachment; it is not settlement.
    func invalidateDesktopProjection(conversationID: String?, epoch: UInt64) {
        guard desktopPublicEpoch == epoch else { return }
        if let conversationID {
            desktopReceiptReservations.removeValue(forKey: CodexActivityPrivacy.hashIdentifier(conversationID))
        } else { desktopReceiptReservations.removeAll() }
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
        sessionClassifier = CodexActivitySessionClassifier(codexHome: root)
        hookSessionClassifier = CodexActivitySessionClassifier(codexHome: root)
        startNativeActivityNotifications()
        return true
    }

    func receiveLocalRecord(_ record: CodexLocalRolloutDecodedRecord, replay: Bool,
                            generation expected: UInt64? = nil) async {
        let run = expected ?? nativeGeneration
        guard nativeGeneration == run else { return }
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

    private static func localRecordSession(_ record: CodexLocalRolloutDecodedRecord) -> String? {
        switch record.update {
        case .activity(let event): return event.sessionHash
        case .tokenUsage(let usage): return usage.sessionHash
        case .tokenUsageReplay(let usages): return usages.first?.sessionHash
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
                           selectionEvidenceAt: Date? = nil, admissionAllowed: (() -> Bool)? = nil,
                           confirmedCurrentTurn: Bool = false) async {
        let run = expected ?? nativeGeneration
        let classifier = delivery.activity.source == .hook ? hookSessionClassifier : sessionClassifier
        let kind: CodexActivitySessionKind
        if let sessionKindResolver { kind = await sessionKindResolver(delivery.activity) }
        else { kind = await classifier.kind(for: delivery.activity) }
        guard run == nativeGeneration, admissionAllowed?() ?? true else { return }
        let before = snapshot
        receive(CodexActivityDelivery(eventID: delivery.eventID, source: delivery.source,
                                      activity: delivery.activity.classified(as: kind)),
                selectionEvidenceAt: selectionEvidenceAt, confirmedCurrentTurn: confirmedCurrentTurn)
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

    func receive(_ delivery: CodexActivityDelivery, selectionEvidenceAt: Date? = nil, confirmedCurrentTurn: Bool = false) {
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
                                                selectionEvidenceAt: selectionEvidenceAt,
                                                confirmedCurrentTurn: confirmedCurrentTurn) else { return }
        admittedActivityDidReceive?(event)
        flushLocalPublicContent(for: event.sessionHash)
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

        let pendingWait = nextLifecycle == .active
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
        localDesktopFollows.removeAll(); localDesktopFollowOrder.removeAll()
        pendingLocalPublicContent.removeAll(); nativeWaitEvidence.removeAll(); confirmedNativeTurns.removeAll()
        pendingNativePublicMessages.removeAll()
        nativePublicEpoch = nil; closedNativePublicEpoch = nil
        desktopPublicEpoch = nil; closedDesktopPublicEpoch = nil
        desktopAdmissions.removeAll(); desktopReceiptReservations.removeAll(); desktopWaitEvidence.removeAll()
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
