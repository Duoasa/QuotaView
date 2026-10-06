import AppKit
import Foundation
import QuotaViewCore

/// A workspace label is useful while disconnected, but cannot replace a real
/// thread title or the user-visible name obtained from Codex.
enum IslandTaskTitleSource: Int {
    case fallback, threadTitle, explicitName
}

/// Identity, ordering and request lifecycle are independent of presentation/focus.
/// Shared Desktop connections are observers until response ownership is established.
@MainActor
final class IslandLiveStore {
    enum DesktopRequestIdentity: Hashable {
        case server(CodexDesktopPendingRequestIdentity)
        case asynchronousQuestion(String)
    }
    struct Pending: Equatable {
        let key: String
        var value: IslandConfirmation
        var callHash: String? = nil
        var rpcEpoch: UInt64? = nil
        var desktopIdentity: DesktopRequestIdentity? = nil
        var desktopOwner: String? = nil
        var desktopEpoch: UInt64? = nil
        var mode: CodexUserInputMode? = nil
        var isGeneric = false
        var blocksExecution: Bool {
            if isGeneric { return mode != .asynchronous }
            return value.protocolRequest?.kind != .questions || mode == .synchronous
        }
    }

    struct TaskRecord {
        let id: Int
        let key: String
        var threadID: String?
        var turnKey: String?
        var title = ""
        var titleSource: IslandTaskTitleSource = .fallback
        var model = ""
        var effort = ""
        var modelTurnKey: String?
        var effortTurnKey: String?
        var activityStatus: IslandTaskStatus = .thinking
        var requestLifecycle = RequestLifecycle()
        var observerReminderDismissed = false
        var observedPermissionNotices: Set<String> = []
        var status: IslandTaskStatus {
            if terminal { return activityStatus }
            if observerReminderDismissed && requestLifecycle.canHideObserverReminder { return activityStatus }
            return requestLifecycle.waitingOnSource || requestLifecycle.hasBlockingRequest ? .waiting : activityStatus
        }
        var requests: [Pending] {
            observerReminderDismissed && requestLifecycle.canHideObserverReminder ? [] : requestLifecycle.visibleRequests
        }
        var requestIndex: Int { get { requestLifecycle.requestIndex } set { requestLifecycle.requestIndex = newValue } }
        var waitingOnSource: Bool { requestLifecycle.waitingOnSource }
        var sourceWaitReason: CodexActivityWaitReason? { requestLifecycle.waitReason }
        var genericWaitCallHash: String? { requestLifecycle.requests.first(where: \.isGeneric)?.callHash }
        var resolvedCallHashes: [String] { requestLifecycle.resolvedCallHashes }
        var resolvedRequestKeys: [String] { requestLifecycle.resolvedRequestKeys }
        var asynchronousQuestionCallHashes: Set<String> { requestLifecycle.asynchronousCallHashes }
        var operation = ""
        var publicProgress = ""
        var tokens: Int64?
        var startedAt: Date?
        var endedAt: Date?
        var updatedAt = Date.distantPast
        var progress: Double?
        var progressResolver = CodexActivityStateSmokeProgressResolver()
        var progressUpdatedAt: Date?
        var displayedProgress: Double = 0.01
        var nativeContentAvailable = false
        var nativeState = false
        var entries: [IslandTraceEntry] = []
        var removedEntryCount = 0
        var retainedEntryBytes = 0
        var activeItems: [String: String] = [:]
        var executionEnded = false
        var terminal: Bool { executionEnded || [.completed, .failed, .cancelled].contains(activityStatus) }
    }
    // QuotaView-only display suppression. This never archives a Codex thread,
    // stops a turn, or resolves a request. Persist only existing one-way hashes.
    private static let archivedTurnsKey = "island.archivedTurns"
    private static let unknownTurn = "unknown-turn"
    private let archiveDefaults: UserDefaults?
    private var archivedTurns: [String: String]
    private static let retiredAsyncKey = "island.retiredAsyncPresentations.v1"
    private struct AsyncPresentation {
        var expiresAt: Date?
        var claimed = false
        var handoffAt: Date?
    }
    private var asyncPresentations: [String: AsyncPresentation] = [:]
    // Only hashed thread/turn/question identity and retirement time are saved.
    // This is presentation suppression, never a response or settlement ledger.
    private var retiredAsyncPresentations: [String: Double]
    init(archiveDefaults: UserDefaults? = nil) {
        self.archiveDefaults = archiveDefaults
        archivedTurns = archiveDefaults?.dictionary(forKey: Self.archivedTurnsKey) as? [String: String] ?? [:]
        let saved = archiveDefaults?.dictionary(forKey: Self.retiredAsyncKey) as? [String: Double] ?? [:]
        retiredAsyncPresentations = Dictionary(uniqueKeysWithValues: saved.filter {
            $0.key.utf8.count == 64 && $0.key.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
                && $0.value.isFinite && $0.value > 0
        }.sorted { $0.value > $1.value }.prefix(4096).map { ($0.key, $0.value) })
    }
    private func isArchived(_ task: TaskRecord) -> Bool {
        guard let turn = archivedTurns[task.key] else { return false }
        // A reconnect snapshot may precede the identified turn; keep it hidden
        // until a different, positively identified turn starts.
        return task.turnKey == nil || turn == Self.unknownTurn || task.turnKey == turn
    }
    private func saveArchives() { archiveDefaults?.set(archivedTurns, forKey: Self.archivedTurnsKey) }
    func archiveFromIsland(_ id: Int) {
        let visible = tasks.filter { !isArchived($0) }
        guard let position = visible.firstIndex(where: { $0.id == id }) else { return }
        let task = visible[position]
        archivedTurns[task.key] = task.turnKey ?? Self.unknownTurn
        saveArchives()
        if selectedID == id {
            let remaining = visible.filter { $0.id != id }
            selectedID = remaining.isEmpty ? 0 : remaining[min(position, remaining.count - 1)].id
        }
        if preservedID == id { preservedID = nil }
        onChange?()
    }
    private(set) var tasks: [TaskRecord] = []
    private(set) var selectedID = 0
    private(set) var connection = CodexSharedAppServerConnectionState.discovering
    private(set) var connectionEpoch = 0
    var preservedID: Int?
    private var nextID = 1
    private var nativeConnectionEpoch: UInt64?
    private var desktopConnected = false
    private var desktopConnectionEpoch: UInt64?
    private struct DesktopScope { let owner: String; let epoch: UInt64; let revision: Int64 }
    private var desktopScopes: [String: DesktopScope] = [:]
    private var priorTurnKeys: [String: Set<String>] = [:]
    private var metadata: [String: [String: Any]] = [:]
    private var sessionKinds: [String: CodexActivitySessionKind] = [:]
    private var sessionKindOrder: [String] = []
    struct SubagentRecord {
        var identity: CodexActivitySubagentIdentity
        var title = ""
        var model = ""
        var effort = ""
        var turn: String?
        var status: IslandTaskStatus = .unknown
        var startedAt: Date?
        var updatedAt = Date.distantPast
        var source: CodexActivityEventSource?
        var progress = ""
        var publicMessageID: String?
        var publicMessageText = ""
        var priorTurns = Set<String>()
        var terminal: Bool { [.completed, .failed, .cancelled].contains(status) }
    }
    private(set) var subagents: [String: SubagentRecord] = [:]
    private var subagentOrder: [String] = []

    func receiveSubagentIdentity(_ identity: CodexActivitySubagentIdentity) {
        guard presentationKind(for: identity.sessionHash) != .memoryConsolidation else { return }
        if let previous = subagents[identity.sessionHash], previous.identity.parentSessionHash != identity.parentSessionHash { return }
        // Store supplies a validated native parent relation. Legacy generic
        // internal classification may be refined, but never a memory execution.
        sessionKinds[identity.sessionHash] = .subagent
        withdrawNonUserSession(identity.sessionHash, kind: .subagent)
        if subagents[identity.sessionHash] == nil {
            subagents[identity.sessionHash] = .init(identity: identity)
            subagentOrder.append(identity.sessionHash)
        } else { subagents[identity.sessionHash]?.identity = identity }
        if let title = identity.title, !title.isEmpty { subagents[identity.sessionHash]?.title = title }
        while subagentOrder.count > 128 { subagents.removeValue(forKey: subagentOrder.removeFirst()) }
        onChange?()
    }

    func receiveSubagentActivity(_ event: CodexActivityEvent) {
        guard var child = subagents[event.sessionHash],
              presentationKind(for: event.sessionHash) == .subagent else { return }
        // Store/Registry has already admitted this event and its source clock.
        // A confirmed new-turn snapshot can carry an earlier real startedAt;
        // a second global timestamp comparison would veto that valid admission.
        let positive = [.userPromptSubmit, .preToolUse, .permissionRequest, .preCompact].contains(event.event)
        if let turn = event.turnHash {
            guard !child.priorTurns.contains(turn) else { return }
            if child.turn != turn {
                guard positive else { return }
                if let old = child.turn { child.priorTurns.insert(old) }
                while child.priorTurns.count > 32 { child.priorTurns.remove(child.priorTurns.sorted().first!) }
                child.turn = turn; child.startedAt = event.occurredAt; child.progress = ""
                child.publicMessageID = nil; child.publicMessageText = ""
            } else if child.terminal { return }
        } else if child.turn == nil || child.terminal { return }
        child.updatedAt = max(child.updatedAt, event.occurredAt); child.source = event.source
        switch event.event {
        case .userPromptSubmit, .postToolUse, .postCompact: child.status = .thinking
        case .preToolUse: child.status = .working
        case .permissionRequest: child.status = .waiting
        case .preCompact: child.status = .compacting
        case .stop, .sessionEnd:
            child.status = event.turnCompletionStatus == .failed ? .failed : event.turnCompletionStatus == .interrupted ? .cancelled : .completed
        case .interrupt: child.status = .cancelled
        case .sessionStart, .subagentStart, .subagentStop: return
        }
        subagents[event.sessionHash] = child; onChange?()
    }

    /// Capacity withdrawal clears the execution while retaining harmless display
    /// metadata. Only a later admitted positive event may show this child again.
    func withdrawSubagentObservation(for session: String) {
        guard var child = subagents[session] else { return }
        if child.terminal, let turn = child.turn { child.priorTurns.insert(turn) }
        while child.priorTurns.count > 32 { child.priorTurns.remove(child.priorTurns.sorted().first!) }
        child.turn = nil; child.startedAt = nil; child.status = .unknown; child.source = nil
        child.progress = ""; child.publicMessageID = nil; child.publicMessageText = ""
        subagents[session] = child
        onChange?()
    }

    func receiveSubagentSourceUnavailable(_ source: CodexActivityEventSource?) {
        for key in subagents.keys where !subagents[key]!.terminal
            && (source == nil || subagents[key]!.source == source) {
            subagents[key]?.status = .unknown
        }
        onChange?()
    }

    private func receiveSubagentContent(_ content: CodexLocalPublicContent, payload: [String: Any]) {
        guard var child = subagents[content.sessionHash], child.turn == content.turnHash,
              presentationKind(for: content.sessionHash) == .subagent else { return }
        if payload["presentationRecovery"] as? Bool == true && child.terminal { return }
        switch payload["type"] as? String {
        case "metadata":
            if let title = payload["title"] as? String, !title.isEmpty { child.title = title }
            if let model = nonempty(payload["model"]) { child.model = model }
            if let effort = nonempty(payload["effort"]) { child.effort = effort }
        case "message": child.progress = messageSummary(payload["text"] as? String ?? "")
        case "tool":
            if !child.terminal && payload["presentationRecovery"] as? Bool != true {
                child.progress = toolSummary(payload["name"] as? String ?? "", arguments: payload["text"] as? String ?? "")
            }
        default: return
        }
        subagents[content.sessionHash] = child; onPublicChange?()
    }

    func receiveSubagentPublicMessage(_ data: Data) {
        guard data.count <= 1_048_576, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = object["method"] as? String, let payload = object["params"] as? [String: Any] else { return }
        let metadata = payload["thread"] as? [String: Any]
        let current = payload["currentTurn"] as? [String: Any] ?? payload["turn"] as? [String: Any]
        guard let threadID = payload["threadId"] as? String ?? metadata?["id"] as? String,
              let turn = payload["turnId"] as? String ?? current?["id"] as? String else { return }
        let key = CodexActivityPrivacy.hashIdentifier(threadID)
        guard var child = subagents[key], presentationKind(for: key) == .subagent,
              CodexActivityPrivacy.hashIdentifier(turn) == child.turn else { return }
        if method == "thread/snapshot" || method == "thread/started", let metadata {
            if let title = metadata["name"] as? String ?? metadata["title"] as? String, !title.isEmpty { child.title = title }
            if let model = metadata["model"] as? String ?? current?["model"] as? String, !model.isEmpty { child.model = model }
            if let effort = metadata["reasoningEffort"] as? String ?? metadata["effort"] as? String ?? current?["reasoningEffort"] as? String,
               !effort.isEmpty { child.effort = effort }
        } else if method == "item/agentMessage/delta", let itemID = payload["itemId"] as? String,
                  itemID == child.publicMessageID, let delta = payload["delta"] as? String, !child.terminal {
            child.publicMessageText = String((child.publicMessageText + delta).prefix(2048))
            child.progress = messageSummary(child.publicMessageText)
        } else if method == "item/started" || method == "item/completed", let item = payload["item"] as? [String: Any],
           let type = item["type"] as? String,
           ["agentMessage", "commandExecution", "fileChange", "mcpToolCall", "dynamicToolCall", "webSearch", "collabToolCall"].contains(type) {
            if type == "agentMessage" {
                child.publicMessageID = item["id"] as? String
                child.publicMessageText = String((item["text"] as? String ?? "").prefix(2048))
                child.progress = messageSummary(child.publicMessageText)
            }
            else if method == "item/started" { child.progress = summary(toolName(type, item: item)); if !child.terminal { child.status = .working } }
        } else { return }
        subagents[key] = child; onPublicChange?()
    }

    private var messageSummaryCache: [String: String] = [:]
    private func messageSummary(_ value: String) -> String {
        // Summaries show prose, not Markdown markers or link destinations.
        // Bound parsing and cache the prefix: later streaming deltas do not
        // repeatedly parse the entire answer or even this unchanged prefix.
        let prefix = String(value.prefix(1024))
        if let cached = messageSummaryCache[prefix] { return cached }
        let parsed = try? AttributedString(markdown: prefix,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        let result = summary(parsed.map { String($0.characters) } ?? prefix)
        if messageSummaryCache.count >= 64 { messageSummaryCache.removeAll(keepingCapacity: true) }
        messageSummaryCache[prefix] = result
        return result
    }
    private func summary(_ value: String) -> String {
        // Streaming deltas used to split and join the entire accumulated answer
        // on the main actor, only to discard everything beyond 240 characters.
        var result = ""
        var count = 0
        var space = false
        for character in value {
            if character.isWhitespace { space = !result.isEmpty; continue }
            if space { result.append(" "); count += 1; space = false }
            if count == 240 { break }
            result.append(character); count += 1
            if count == 240 { break }
        }
        return result
    }
    private func toolSummary(_ name: String, arguments: String) -> String {
        let name = name.split(separator: ".").last.map(String.init) ?? name
        let object = arguments.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        if ["spawn_agent", "followup_task", "send_message"].contains(name), let target = object?["task_name"] as? String ?? object?["target"] as? String {
            let label = target.split(separator: "/").last.map(String.init)?.replacingOccurrences(of: "_", with: " ") ?? target
            return "Codex · " + summary(label)
        }
        return summary(name)
    }

    private func childPresentations(parent: String, english: Bool, at now: Date) -> [IslandSubagentPresentation] {
        subagents.values.filter { $0.identity.parentSessionHash == parent && $0.startedAt != nil && !$0.terminal
            && presentationKind(for: $0.identity.sessionHash) == .subagent }
            .sorted { ($0.startedAt ?? .distantPast, $0.identity.sessionHash) < ($1.startedAt ?? .distantPast, $1.identity.sessionHash) }
            .map { child in
                let copy = AppCopy(language: english ? .english : .simplifiedChinese)
                let title = child.title.isEmpty ? (child.identity.nickname ?? child.identity.role ?? copy.islandSubagentTitle) : child.title
                let status: String
                switch child.status {
                case .unknown: status = copy.islandSubagentStatusUnavailable
                case .cancelled: status = copy.islandSubagentInterrupted
                default: status = CodexActivityCopy(language: english ? .english : .simplifiedChinese).statusTitle(for: child.status.visualState)
                }
                let metadata = IslandSessionMetadata(modelName: child.model, reasoningEffort: child.effort,
                    elapsedSeconds: child.status == .unknown ? nil : child.startedAt.map { max(0, Int(now.timeIntervalSince($0))) })
                return .init(id: child.identity.sessionHash, title: title, status: status, visualState: child.status.visualState,
                             model: metadata.modelTitle, duration: metadata.durationTitle, detail: child.progress,
                             avatar: child.identity.avatar)
            }
    }

    /// Native request.start labels one execution, not the lifetime of a thread.
    /// Keep its revocable presentation separate from persistent source metadata.
    private var executionMemorySessions: Set<String> = []
    private var executionKindOrder: [String] = []
    private func presentationKind(for key: String) -> CodexActivitySessionKind {
        let persistent = sessionKinds[key] ?? .unknown
        if persistent == .memoryConsolidation || persistent == .internalTask { return persistent }
        return executionMemorySessions.contains(key) ? .memoryConsolidation : persistent
    }
    func receiveExecutionSessionKind(_ kind: CodexActivitySessionKind, session key: String) {
        if kind == .memoryConsolidation {
            if var child = subagents[key] {
                if let turn = child.turn { child.priorTurns.insert(turn) }
                child.startedAt = nil; child.status = .unknown; child.progress = ""
                subagents[key] = child
            }
            executionMemorySessions.insert(key)
            executionKindOrder.removeAll { $0 == key }; executionKindOrder.append(key)
            while executionKindOrder.count > 256 {
                executionMemorySessions.remove(executionKindOrder.removeFirst())
            }
        } else {
            executionMemorySessions.remove(key)
            executionKindOrder.removeAll { $0 == key }
        }
        withdrawNonUserSession(key, kind: presentationKind(for: key))
        onChange?()
    }
    /// Classification changes presentation without completing or answering a task.
    func setSessionKind(_ kind: CodexActivitySessionKind, for key: String) {
        guard kind != .unknown else { return }
        let resolved = kind == .internalTask ? kind
            : CodexActivitySessionKind.resolving(sessionKinds[key] ?? .unknown, kind)
        sessionKinds[key] = resolved
        sessionKindOrder.removeAll { $0 == key }; sessionKindOrder.append(key)
        while sessionKindOrder.count > 256 { sessionKinds.removeValue(forKey: sessionKindOrder.removeFirst()) }
        withdrawNonUserSession(key, kind: presentationKind(for: key))
    }
    private func withdrawNonUserSession(_ key: String, kind: CodexActivitySessionKind) {
        guard kind == .memoryConsolidation || kind == .internalTask || kind == .subagent else { return }
        let removed = tasks.filter { $0.key == key }.map(\.id)
        removeTaskRecords { $0.key == key }
        metadata.removeValue(forKey: key); desktopScopes.removeValue(forKey: key)
        pendingLocalContent.removeAll { $0.sessionHash == key }
        clearContexts(for: key)
        if removed.contains(selectedID) { selectedID = tasks.first?.id ?? 0 }
        if let id = preservedID, removed.contains(id) { preservedID = nil }
        if !removed.isEmpty { onChange?() }
    }
    var onChange: (() -> Void)?
    var onPublicChange: (() -> Void)?
    var nativeRequestSettlementDidReceive: ((CodexActivityRequestSettlement) -> Void)?
    var desktopRequestSettlementDidReceive: ((String, String, UInt64, Bool) -> Void)?
    private var pendingLocalContent: [CodexLocalPublicContent] = []
    var responseCapability: ((IslandCodexApprovalRequest) -> Bool)?
    var respond: ((IslandCodexApprovalRequest, IslandApprovalJSON) async throws -> Void)?

    func reset() { messageSummaryCache.removeAll(); asyncPresentations.removeAll(); subagents.removeAll(); subagentOrder.removeAll(); tasks.removeAll(); metadata.removeAll(); sessionKinds.removeAll(); sessionKindOrder.removeAll(); executionMemorySessions.removeAll(); executionKindOrder.removeAll(); priorTurnKeys.removeAll(); itemContexts.removeAll(); contextBytes.removeAll(); contextKeys.removeAll(); totalEntryBytes = 0; totalContextBytes = 0; pendingLocalContent.removeAll(); selectedID = 0; nativeConnectionEpoch = nil; desktopConnected = false; desktopConnectionEpoch = nil; desktopScopes.removeAll(); connectionEpoch += 1; onChange?() }
    func select(_ id: Int) { if tasks.contains(where: { $0.id == id }) { selectedID = id; onChange?() } }
    func setConnection(_ state: CodexSharedAppServerConnectionState) {
        guard state != connection else { return }
        if state != .connected {
            connectionEpoch += 1
            for i in tasks.indices { tasks[i].requestLifecycle.invalidateResponses() }
        }
        connection = state; onChange?()
    }
    func setDesktopConnection(connected: Bool, epoch: UInt64?) {
        let changedEpoch = epoch != nil && desktopConnectionEpoch != epoch
        if !connected || changedEpoch {
            for i in tasks.indices { tasks[i].requestLifecycle.invalidateDesktopResponses() }
        }
        desktopConnected = connected
        if !connected { desktopConnectionEpoch = nil; desktopScopes.removeAll() }
        else if let epoch { desktopConnectionEpoch = epoch }
        onChange?()
    }
    /// Resource admission failure revokes the affected transport capability;
    /// it supplies no evidence that the owner answered its pending request.
    func invalidateDesktopResponses(conversationID: String?, epoch: UInt64) {
        guard desktopConnectionEpoch == epoch else { return }
        let key = conversationID.map(CodexActivityPrivacy.hashIdentifier)
        for i in tasks.indices where key == nil || tasks[i].key == key {
            tasks[i].requestLifecycle.invalidateDesktopResponses(epoch: epoch)
        }
        onChange?()
    }
    /// Store has already admitted the conversation and identified current turn.
    /// Only actor-minted handles, correlated below, can make a form interactive.
    func receiveDesktopProjection(_ projection: CodexDesktopInteractionProjection,
                                  snapshot: CodexDesktopConversationSnapshot) {
        guard desktopConnected, projection.sourceKind != .internalTask, projection.sourceKind != .memoryConsolidation, projection.sourceKind != .subagent,
              let turn = projection.currentTurnID, !turn.isEmpty else { return }
        if let epoch = desktopConnectionEpoch, epoch != snapshot.connectionEpoch { return }
        desktopConnectionEpoch = snapshot.connectionEpoch
        let observedAt = Date()
        let key = CodexActivityPrivacy.hashIdentifier(snapshot.conversationID)
        guard let i = tasks.firstIndex(where: { $0.key == key }), tasks[i].turnKey == CodexActivityPrivacy.hashIdentifier(turn) else { return }
        if let prior = desktopScopes[key], prior.epoch == snapshot.connectionEpoch {
            guard prior.owner != snapshot.ownerClientID || snapshot.revision > prior.revision else { return }
            if prior.owner != snapshot.ownerClientID { tasks[i].requestLifecycle.invalidateDesktopResponses() }
        }
        desktopScopes[key] = .init(owner: snapshot.ownerClientID, epoch: snapshot.connectionEpoch, revision: snapshot.revision)
        tasks[i].threadID = snapshot.conversationID
        applyTitle(projection.title, source: .explicitName, at: i)
        guard !tasks[i].terminal, projection.status == "inProgress" else { onChange?(); return }
        func handle(_ id: CodexDesktopIPCRequestID, method: String, turn: String) -> CodexDesktopIPCRequestHandle? {
            snapshot.requests.first { $0.requestID == id && $0.method == method && $0.turnID == turn
                && $0.ownerClientID == snapshot.ownerClientID && $0.connectionEpoch == snapshot.connectionEpoch
                && $0.conversationID == snapshot.conversationID }
        }
        func pending(_ wire: IslandCodexApprovalRequest, identity: DesktopRequestIdentity,
                     call: String?, mode: CodexUserInputMode?) -> Pending {
            let identityKey: String
            switch identity {
            case .server(let identity): identityKey = Data(identity.turnID.utf8).base64EncodedString() + ":" + identity.method
                + ":" + ((try? JSONEncoder().encode(identity.requestID)) ?? Data()).base64EncodedString()
            case .asynchronousQuestion(let id): identityKey = "async:" + Data(id.utf8).base64EncodedString()
            }
            let availableControls: Bool
            switch wire.kind {
            case .command, .terminalInput, .network, .fileChange: availableControls = !wire.actions.isEmpty
            case .questions: availableControls = wire.supportedQuestions
            default: availableControls = true
            }
            let canRespond = availableControls && snapshot.supportsUntrustedAppInput && wire.desktopHandle != nil
                && respond != nil && responseCapability?(wire) == true && wire.kind != .nativeOnly
                && wire.kind != .mcpURL && (wire.kind != .mcpForm || wire.supportedForm)
            let title = wire.titleText
            return .init(key: "desktop:" + CodexActivityPrivacy.hashIdentifier(snapshot.ownerClientID) + ":\(snapshot.connectionEpoch):" + identityKey,
                value: .init(question: title, impact: canRespond ? .init("处理后同步至 Codex。", "Send this response to Codex.")
                    : .init("请在 Codex 处理。", "Handle this request in Codex."), protocolRequest: wire, canRespond: canRespond),
                callHash: call, desktopIdentity: identity, desktopOwner: snapshot.ownerClientID,
                desktopEpoch: snapshot.connectionEpoch, mode: mode)
        }
        let wasWaiting = tasks[i].requestLifecycle.waitingOnSource || tasks[i].requestLifecycle.hasBlockingRequest
        if projection.pendingRequestsAreAuthoritative {
            tasks[i].requestLifecycle.observeDesktopRuntimeWait(projection, owner: snapshot.ownerClientID,
                epoch: snapshot.connectionEpoch, at: observedAt)
        }
        if projection.asyncQuestionsAreAuthoritative { tasks[i].requestLifecycle.admitAuthoritativeDesktopQuestions() }
        tasks[i].requestLifecycle.resolveDesktopAnswers(owner: snapshot.ownerClientID, epoch: snapshot.connectionEpoch,
            answered: Set(projection.asyncQuestions.filter { $0.resolvedAnswer != nil }.map(\.questionItemID)))
        for request in projection.requests where request.turnID == turn {
            guard var wire = try? IslandCodexApprovalRequest(data: request.envelopeData) else { continue }
            wire = wire.attachingDesktopHandle(handle(request.requestID, method: request.method, turn: turn))
            if let context = request.contextItemData { wire.contextItem = try? JSONDecoder().decode(IslandApprovalJSON.self, from: context) }
            let item = wire.params["itemId"].text
            tasks[i].requestLifecycle.observe(pending(wire, identity: .server(request.identity),
                call: item.isEmpty ? nil : CodexActivityPrivacy.hashIdentifier(item), mode: request.userInputMode))
        }
        for question in projection.asyncQuestions where question.turnID == turn && question.resolvedAnswer == nil {
            guard var wire = try? IslandCodexApprovalRequest(desktopAsyncQuestion: question, conversationID: snapshot.conversationID) else { continue }
            wire = wire.attachingDesktopHandle(handle(.string(question.questionItemID), method: wire.method, turn: turn))
            let request = pending(wire, identity: .asynchronousQuestion(question.questionItemID),
                call: CodexActivityPrivacy.hashIdentifier(question.questionItemID), mode: .asynchronous)
            if !isRetiredAsync(request, task: tasks[i]) { tasks[i].requestLifecycle.observe(request) }
        }
        if projection.pendingRequestsAreAuthoritative {
            let settled = tasks[i].requestLifecycle.resolveDesktopRequests(owner: snapshot.ownerClientID, epoch: snapshot.connectionEpoch,
                pending: projection.authoritativePendingIdentities, asyncQuestions: projection.authoritativeAsyncQuestionIDs,
                asyncQuestionsAreAuthoritative: projection.asyncQuestionsAreAuthoritative, at: observedAt)
            tasks[i].requestLifecycle.reconcileDesktopContinuation(projection, owner: snapshot.ownerClientID,
                epoch: snapshot.connectionEpoch, at: observedAt)
            let stillWaiting = tasks[i].requestLifecycle.waitingOnSource || tasks[i].requestLifecycle.hasBlockingRequest
            if settled || projection.provesNoPendingConfirmation || wasWaiting != stillWaiting {
                desktopRequestSettlementDidReceive?(key, CodexActivityPrivacy.hashIdentifier(turn), snapshot.connectionEpoch,
                    stillWaiting)
            }
        }
        onChange?()
    }
    private func index(_ key: String, admit: Bool) -> Int? {
        guard presentationKind(for: key) != .memoryConsolidation, presentationKind(for: key) != .internalTask, presentationKind(for: key) != .subagent else { return nil }
        if let i = tasks.firstIndex(where: { $0.key == key }) { return i }
        guard admit else { return nil }
        // New conversations append to the list. Completed cards remain until
        // the user archives them; starting another task is not a dismissal.
        tasks.append(.init(id: nextID, key: key)); nextID += 1
        if !tasks.contains(where: { $0.id == selectedID }) { selectedID = tasks.last!.id }
        return tasks.count - 1
    }
    func receiveAdmittedActivity(_ projection: CodexIslandActivityProjection) {
        if let event = projection.event { receiveLegacy(event, projection: projection); return }
        guard let i = tasks.firstIndex(where: { $0.key == projection.snapshot.sessionHash }),
              !tasks[i].terminal, projection.snapshot.taskIdentity?.turnHash == tasks[i].turnKey else { return }
        // Source loss is uncertainty, not success or an execution tombstone.
        // A conclusive continuation for this same turn may restore live proof.
        if projection.snapshot.state == .unavailable {
            tasks[i].activityStatus = .unknown; tasks[i].endedAt = Date(); onChange?()
        }
    }
    func receiveLegacy(_ event: CodexActivityEvent, projection: CodexIslandActivityProjection? = nil) {
        guard event.sessionKind != .unknown else { return }
        if let kind = event.sessionKind { setSessionKind(kind, for: event.sessionHash) }
        guard presentationKind(for: event.sessionHash) != .memoryConsolidation,
              presentationKind(for: event.sessionHash) != .internalTask, presentationKind(for: event.sessionHash) != .subagent else { return }
        let active = [.userPromptSubmit, .preToolUse, .permissionRequest, .preCompact].contains(event.event)
        guard let i = index(event.sessionHash, admit: active) else { return }
        let key = event.turnHash
        if let key, priorTurnKeys[event.sessionHash]?.contains(key) == true { return }
        if tasks[i].terminal && (key == nil || tasks[i].turnKey == key) { return }
        if let key, tasks[i].turnKey != key, active {
            startTurn(i, key: key, at: event.occurredAt)
        }
        if let key, tasks[i].turnKey != nil, tasks[i].turnKey != key { return }
        if tasks[i].terminal && !active { return }
        if let call = event.toolCallHash, event.event == .permissionRequest,
           tasks[i].resolvedCallHashes.contains(call)
                || tasks[i].requestLifecycle.retiredObserverCallHashes.contains(call) { return }
        if [.preToolUse, .permissionRequest].contains(event.event) {
            tasks[i].requestLifecycle.observeMode(event.userInputMode, callHash: event.toolCallHash)
        }
        tasks[i].updatedAt = max(tasks[i].updatedAt, event.occurredAt)
        if projection?.lifecycle == .active { tasks[i].endedAt = nil }
        if tasks[i].title.isEmpty { applyTitle(event.workspaceName, source: .fallback, at: i) }
        switch event.event {
        case .userPromptSubmit: tasks[i].activityStatus = .thinking; tasks[i].operation = ""
        case .preToolUse:
            tasks[i].requestLifecycle.observeToolStart(callHash: event.toolCallHash, toolName: event.toolName,
                at: event.occurredAt, source: event.source)
            tasks[i].requestLifecycle.continueCall(event.toolCallHash, at: event.occurredAt, source: event.source)
            tasks[i].activityStatus = .working; tasks[i].operation = ""
        case .postToolUse:
            if let call = event.toolCallHash {
                tasks[i].requestLifecycle.resolveCall(call, proofMode: event.userInputMode,
                    at: event.occurredAt, source: event.source)
            }
            if event.userInputMode != .asynchronous && event.toolCallHash.flatMap({ tasks[i].requestLifecycle.mode(for: $0) }) != .asynchronous {
                tasks[i].activityStatus = tasks[i].activeItems.isEmpty ? .thinking : .working
            }
        case .permissionRequest:
            let notice = CodexActivityPrivacy.hashIdentifier([
                event.source?.rawValue ?? "unknown", event.toolCallHash ?? "", event.toolName ?? "",
                event.effectiveWaitReason?.rawValue ?? "", String(event.occurredAt.timeIntervalSince1970)
            ].joined(separator: ":"))
            if !tasks[i].observedPermissionNotices.contains(notice), tasks[i].observedPermissionNotices.count < 256 {
                tasks[i].observedPermissionNotices.insert(notice)
                tasks[i].observerReminderDismissed = false
            }
            if event.source == .appServer, event.toolCallHash == nil, event.userInputMode != .asynchronous {
                tasks[i].requestLifecycle.setSourceWait(event.effectiveWaitReason, waiting: true,
                    epoch: nativeConnectionEpoch ?? UInt64(connectionEpoch), at: event.occurredAt)
            } else {
                tasks[i].requestLifecycle.observeWait(callHash: event.toolCallHash, mode: event.userInputMode,
                    reason: event.effectiveWaitReason, toolName: event.toolName, at: event.occurredAt, source: event.source)
            }
            if event.userInputMode == .asynchronous { tasks[i].activityStatus = .working }
        case .preCompact: tasks[i].activityStatus = .compacting
        case .postCompact:
            if tasks[i].activityStatus == .compacting || projection?.lifecycle == .active {
                tasks[i].activityStatus = .thinking
            }
        case .stop:
            switch event.turnCompletionStatus {
            case .failed: tasks[i].activityStatus = .failed
            case .interrupted: tasks[i].activityStatus = .cancelled
            default: tasks[i].activityStatus = .completed; tasks[i].progress = 1
            }
            tasks[i].endedAt = event.occurredAt; tasks[i].requestLifecycle.finishTurn(); tasks[i].activeItems.removeAll()
        case .interrupt:
            tasks[i].activityStatus = .cancelled; tasks[i].endedAt = event.occurredAt
            tasks[i].requestLifecycle.finishTurn(); tasks[i].activeItems.removeAll()
        case .sessionEnd:
            tasks[i].activityStatus = .cancelled; tasks[i].executionEnded = true
            tasks[i].endedAt = event.occurredAt; tasks[i].requestLifecycle.finishTurn(); tasks[i].activeItems.removeAll()
        default: break
        }
        if event.event == .stop, let projection {
            switch projection.snapshot.state {
            case .completed: tasks[i].activityStatus = .completed
            case .error: tasks[i].activityStatus = .failed
            case .unavailable: tasks[i].activityStatus = .unknown
            default: tasks[i].activityStatus = .cancelled
            }
            tasks[i].executionEnded = true
            tasks[i].progress = projection.snapshot.approximateProgressFraction
        } else if let projection { tasks[i].progress = projection.snapshot.approximateProgressFraction }
        else if !tasks[i].terminal, let progress = event.planProgress?.approximateFraction { tasks[i].progress = progress }
        let pending = pendingLocalContent.filter { $0.sessionHash == event.sessionHash && $0.turnHash == tasks[i].turnKey }
        pendingLocalContent.removeAll { $0.sessionHash == event.sessionHash }
        for content in pending { receiveLocalContent(content) }
        onChange?()
    }
    func withdrawHookExecution(session: String, turn: String) {
        let removed = Set(tasks.filter { $0.key == session && $0.turnKey == turn }.map(\.id))
        guard !removed.isEmpty else { return }
        removeTaskRecords { removed.contains($0.id) }
        if removed.contains(selectedID) { selectedID = tasks.first?.id ?? 0 }
        if let preservedID, removed.contains(preservedID) { self.preservedID = nil }
        onChange?()
    }
    func receiveToken(_ update: CodexActivityTokenUsageUpdate) {
        guard let i = tasks.firstIndex(where: { $0.key == update.sessionHash }),
              tasks[i].turnKey == nil || tasks[i].turnKey == update.turnHash,
              update.cumulativeTotalTokens >= 0,
              tasks[i].turnKey != nil || update.occurredAt >= (tasks[i].startedAt ?? .distantPast) else { return }
        // The first Hook observation can be much later than the actual turn
        // start. Its exact turn ID admits older same-turn cumulative display,
        // while monotonic totals prevent replay from moving the count backwards.
        tasks[i].tokens = max(tasks[i].tokens ?? 0, update.cumulativeTotalTokens); onChange?()
    }
    func receiveLocalContent(_ content: CodexLocalPublicContent) {
        if subagents[content.sessionHash] != nil {
            guard let payload = try? JSONSerialization.jsonObject(with: content.data) as? [String: Any] else { return }
            receiveSubagentContent(content, payload: payload); return
        }
        guard presentationKind(for: content.sessionHash) != .memoryConsolidation,
              presentationKind(for: content.sessionHash) != .internalTask, presentationKind(for: content.sessionHash) != .subagent else { return }
        guard let p = try? JSONSerialization.jsonObject(with: content.data) as? [String: Any] else { return }
        guard let i = tasks.firstIndex(where: { $0.key == content.sessionHash }) else {
            pendingLocalContent.append(content)
            while pendingLocalContent.count > 200 || pendingLocalContent.reduce(0, { $0 + $1.data.count }) > 2_097_152 { pendingLocalContent.removeFirst() }
            return
        }
        guard tasks[i].turnKey == content.turnHash else { return }
        let type = p["type"] as? String
        let presentationRecovery = p["presentationRecovery"] as? Bool == true
        if presentationRecovery {
            guard !tasks[i].terminal, ["metadata", "message", "tool", "output"].contains(type ?? "") else { return }
        }
        if type == "questionReply", let raw = p["replies"] as? [[String: String]], (1...32).contains(raw.count) {
            let proofs = raw.compactMap { item -> (String, String)? in
                guard let identity = item["questionItemHash"], let question = item["questionHash"],
                      identity.count == CodexActivityPrivacy.hashIdentifier("").count,
                      question.count == CodexActivityPrivacy.hashIdentifier("").count else { return nil }
                return (identity, question)
            }
            guard proofs.count == raw.count else { return }
            if tasks[i].requestLifecycle.receiveAcceptedAsyncReplies(proofs) { onChange?() }
            return
        }
        if type == "questionRequest", let id = p["id"] as? String,
           let questions = p["questions"] as? [[String: Any]] {
            let mode = (p["userInputMode"] as? String).flatMap(CodexUserInputMode.init(rawValue:))
                ?? (p["asynchronous"] as? Bool == true ? .asynchronous : .synchronous)
            receiveLocalQuestions(questions, callID: id, content: content, mode: mode, at: i)
            return
        }
        if !presentationRecovery, type == "output", let id = p["id"] as? String {
            let mode = (p["userInputMode"] as? String).flatMap(CodexUserInputMode.init(rawValue:))
                ?? (p["asynchronous"] as? Bool == true ? .asynchronous : nil)
            if tasks[i].requestLifecycle.resolveCall(CodexActivityPrivacy.hashIdentifier(id), proofMode: mode) { onChange?() }
        }
        if type == "metadata" {
            applyTitle(p["title"] as? String, source: p["titleIsExplicitName"] as? Bool == true ? .explicitName : .threadTitle, at: i)
            if let model = nonempty(p["model"]) { tasks[i].model = model; tasks[i].modelTurnKey = content.turnHash }
            if let effort = nonempty(p["effort"]) { tasks[i].effort = effort; tasks[i].effortTurnKey = content.turnHash }
        } else {
            // The rollout may supply the final channel after the native stream
            // has stopped. Accept this public answer without reviving execution.
            let isFinal = type == "message" && p["channel"] as? String == "final"
            guard (!(tasks[i].nativeContentAvailable && connection == .connected) || isFinal), let id = p["id"] as? String else {
                if type == "output" { onChange?() }
                return
            }
            if type == "output" {
                if let j = tasks[i].entries.firstIndex(where: { $0.publicItem?.sourceID == id }) {
                    let output = Self.retainText(p["text"] as? String ?? "")
                    let oldBytes = entryBytes(tasks[i].entries[j])
                    tasks[i].entries[j].publicItem?.output = output.text
                    tasks[i].entries[j].publicItem?.sourceTruncated = output.truncated
                    tasks[i].entries[j].publicItem?.status = "completed"
                    accountEntryChange(at: i, old: oldBytes, new: entryBytes(tasks[i].entries[j]))
                    trim(i)
                }
                if !presentationRecovery {
                    tasks[i].activeItems.removeValue(forKey: id)
                    if tasks[i].activeItems.isEmpty && tasks[i].activityStatus == .working { tasks[i].activityStatus = .thinking; tasks[i].operation = "" }
                }
            } else {
                let message = type == "message"
                let name = p["name"] as? String ?? ""
                let body = p["text"] as? String ?? ""
                let text = message ? body : name + "\n" + body
                let channel = message ? p["channel"] as? String : nil
                let retained = Self.retainText(text)
                upsert(.init(text: .init(retained.text), kind: channel == "final" ? .result : .progress,
                    publicItem: .init(category: message ? .message : .command,
                    sourceID: id, turnID: content.turnHash, status: message || presentationRecovery ? "completed" : "inProgress", sourceTruncated: retained.truncated, messagePhase: channel)), at: i)
                if message { tasks[i].publicProgress = messageSummary(body); if tasks[i].status == .thinking { tasks[i].operation = tasks[i].publicProgress } }
                else if !message && !presentationRecovery && !tasks[i].terminal {
                    let args = body.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                    let detail = args?["cmd"] as? String ?? args?["code"] as? String ?? args?["command"] as? String ?? body
                    let label = name.split(separator: ".").last.map(String.init) ?? name
                    let description = label + " · " + String(detail.replacingOccurrences(of: "\n", with: " ").prefix(240))
                    tasks[i].activeItems[id] = description; tasks[i].activityStatus = .working; tasks[i].operation = description
                }
            }
        }
        onPublicChange?()
    }
    func setTitle(_ title: String?, for key: String, source: IslandTaskTitleSource = .explicitName) {
        guard let i = tasks.firstIndex(where: { $0.key == key }) else { return }
        if applyTitle(title, source: source, at: i) { onChange?() }
    }

    /// Thread-row metadata enriches an existing admitted execution. It cannot
    /// create a card, change its turn/status, or mint confirmation controls.
    func receiveThreadMetadata(_ value: CodexLocalRolloutThreadMetadata, identity: CodexActivityTaskIdentity) {
        guard let turn = identity.turnHash else { return }
        if var child = subagents[identity.sessionHash], child.turn == turn,
           presentationKind(for: identity.sessionHash) == .subagent {
            if let title = value.title, child.title.isEmpty { child.title = title }
            if let model = value.model, child.model.isEmpty { child.model = model }
            if let effort = value.reasoningEffort, child.effort.isEmpty { child.effort = effort }
            subagents[identity.sessionHash] = child; onChange?(); return
        }
        guard let i = tasks.firstIndex(where: { $0.key == identity.sessionHash }), tasks[i].turnKey == turn,
              ![.memoryConsolidation, .internalTask, .subagent].contains(presentationKind(for: identity.sessionHash)) else { return }
        applyTitle(value.title, source: value.titleIsExplicitName ? .explicitName : .threadTitle, at: i)
        // The thread row may lag a just-started turn. Exact-turn metadata is
        // stronger, so database fields only fill missing execution labels.
        if let model = value.model, tasks[i].model.isEmpty { tasks[i].model = model }
        if let effort = value.reasoningEffort, tasks[i].effort.isEmpty { tasks[i].effort = effort }
        if let total = value.cumulativeTotalTokens { tasks[i].tokens = max(tasks[i].tokens ?? 0, total) }
        onChange?()
    }

    @discardableResult
    private func applyTitle(_ title: String?, source: IslandTaskTitleSource, at i: Int) -> Bool {
        guard let title = nonempty(title), source.rawValue >= tasks[i].titleSource.rawValue else { return false }
        let changed = tasks[i].title != title || tasks[i].titleSource != source
        tasks[i].title = title; tasks[i].titleSource = source
        return changed
    }

    private func nonempty(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    private func startTurn(_ i: Int, key: String?, at date: Date) {
        if let key, priorTurnKeys[tasks[i].key]?.contains(key) == true { return }
        if let key, let archived = archivedTurns[tasks[i].key], archived != key {
            if archived == Self.unknownTurn && tasks[i].turnKey == nil && tasks[i].nativeState {
                // The existing native snapshot has just acquired its turn ID.
                archivedTurns[tasks[i].key] = key
            } else { archivedTurns.removeValue(forKey: tasks[i].key) }
            saveArchives()
        }
        if tasks[i].turnKey == key && !tasks[i].terminal {
            if tasks[i].startedAt == nil { tasks[i].startedAt = date }
            return
        }
        if tasks[i].turnKey == nil && tasks[i].nativeState {
            tasks[i].turnKey = key; tasks[i].startedAt = date
            return
        }
        if let old = tasks[i].turnKey { priorTurnKeys[tasks[i].key, default: []].insert(old) }
        tasks[i].turnKey = key; tasks[i].startedAt = date; tasks[i].endedAt = nil
        tasks[i].activityStatus = .thinking; tasks[i].executionEnded = false; tasks[i].requestLifecycle = RequestLifecycle(); tasks[i].progress = nil; tasks[i].operation = ""
        tasks[i].observerReminderDismissed = false
        tasks[i].observedPermissionNotices.removeAll()
        tasks[i].progressResolver.reset(); tasks[i].progressUpdatedAt = date; tasks[i].displayedProgress = 0.01
        tasks[i].activeItems.removeAll(); tasks[i].nativeContentAvailable = false; tasks[i].publicProgress = ""
        clearEntries(at: i); clearContexts(for: tasks[i].key); tasks[i].removedEntryCount = 0; tasks[i].updatedAt = date
    }
    private func receiveLocalQuestions(_ questions: [[String: Any]], callID: String, content: CodexLocalPublicContent, mode: CodexUserInputMode, at i: Int) {
        guard !tasks[i].terminal, !callID.isEmpty,
              let wire = try? IslandCodexApprovalRequest(localQuestions: questions, callID: callID,
                  sessionHash: content.sessionHash, turnHash: content.turnHash, asynchronous: mode == .asynchronous), !wire.questions.isEmpty else { return }
        let call = CodexActivityPrivacy.hashIdentifier(callID)
        tasks[i].requestLifecycle.observeMode(mode, callHash: call)
        if tasks[i].requests.contains(where: { ($0.rpcEpoch != nil || $0.desktopIdentity != nil) && $0.callHash == call }) { onChange?(); return }
        let pending = Pending(key: "local:\(content.turnHash):\(callID)", value: .init(
            question: .init(wire.questions[0].title), impact: .init("请在 Codex 回答。", "Answer in Codex."),
            protocolRequest: wire, canRespond: false), callHash: call, mode: mode)
        if !isRetiredAsync(pending, task: tasks[i]) { tasks[i].requestLifecycle.observe(pending) }
        onChange?()
    }
    @discardableResult
    private func resolveRequest(_ i: Int, id: CodexDesktopIPCRequestID, epoch: UInt64) -> Bool {
        guard tasks[i].requestLifecycle.resolveRPC(id, epoch: epoch) else { return false }
        if let turn = tasks[i].turnKey {
            nativeRequestSettlementDidReceive?(.init(sessionHash: tasks[i].key,
                turnHash: turn, connectionEpoch: epoch,
                stillWaiting: tasks[i].requestLifecycle.waitingOnSource || tasks[i].requestLifecycle.hasBlockingRequest))
        }
        return true
    }
    func nextRequest(_ id: Int) {
        guard let i = tasks.firstIndex(where: { $0.id == id }), !tasks[i].requests.isEmpty else { return }
        tasks[i].requestIndex = (tasks[i].requestIndex + 1) % tasks[i].requests.count; onChange?()
    }
    private(set) var publicEnvelopeDecodeCount = 0
    func receive(_ data: Data, at now: Date = Date()) {
        publicEnvelopeDecodeCount += 1
        guard data.count <= 1_048_576, let m = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        receive(envelope: m, byteCount: data.count, rawData: data, at: now)
    }
    func receive(envelope m: [String: Any], byteCount: Int, rawData: Data? = nil,
                 usesAdmittedProgress: Bool = false, at now: Date = Date()) {
        guard (0...1_048_576).contains(byteCount), let method = m["method"] as? String, !method.contains("reasoning"),
              let p = m["params"] as? [String: Any] else { return }
        let scope = (m["_quotaViewConnectionEpoch"] as? NSNumber)?.uint64Value ?? UInt64(connectionEpoch)
        if m["_quotaViewConnectionEpoch"] != nil {
            if let latest = nativeConnectionEpoch, scope < latest { return }
            if nativeConnectionEpoch != scope {
                nativeConnectionEpoch = scope
                for i in tasks.indices { tasks[i].requestLifecycle.invalidateResponses(except: scope) }
            }
        }
        if method == "thread/started" || method == "thread/snapshot" {
            guard let thread = p["thread"] as? [String: Any], let tid = thread["id"] as? String else { return }
            let key = CodexActivityPrivacy.hashIdentifier(tid)
            let kind = CodexActivitySessionKind.classify(source: thread["source"],
                threadSource: thread["threadSource"] as? String ?? thread["thread_source"] as? String)
            setSessionKind(kind, for: key)
            guard presentationKind(for: key) != .internalTask, presentationKind(for: key) != .memoryConsolidation, presentationKind(for: key) != .subagent else { return }
            metadata[key] = thread
            let status = thread["status"] as? [String: Any]
            let active = status?["type"] as? String == "active"
            guard let i = index(key, admit: active) else { return }
            applyMetadata(thread, at: i); tasks[i].threadID = tid
            if active { tasks[i].nativeState = true; applyFlags(status, at: i, epoch: scope) }
            onChange?(); return
        }
        if method == "serverRequest/resolved", p["threadId"] == nil,
           let encoded = try? JSONSerialization.data(withJSONObject: p),
           let id = CodexSharedMessageIdentity.rpcID(messageData: encoded, field: "requestId") {
            let matches = tasks.indices.filter { i in
                tasks[i].requests.contains { $0.rpcEpoch == scope && $0.value.protocolRequest?.rpcIdentity == id }
            }
            // Some protocol versions omit threadId. Resolve only an unambiguous
            // pending request, never an unrelated session with a reused ID.
            if matches.count == 1 { resolveRequest(matches[0], id: id, epoch: scope); onChange?() }
            return
        }
        guard let tid = p["threadId"] as? String else { return }
        let key = CodexActivityPrivacy.hashIdentifier(tid)
        let turn = p["turn"] as? [String: Any]
        let turnID = p["turnId"] as? String ?? turn?["id"] as? String
        let turnKey = turnID.map(CodexActivityPrivacy.hashIdentifier)
        let serverRequest = m["id"] != nil
        let activeStatus = (p["status"] as? [String: Any])?["type"] as? String == "active"
        let admit = method == "turn/started" || serverRequest || activeStatus
        guard let i = index(key, admit: admit) else { return }
        if let turnKey, priorTurnKeys[key]?.contains(turnKey) == true { return }
        if let turnKey, tasks[i].turnKey != nil, tasks[i].turnKey != turnKey, method != "turn/started" { return }
        tasks[i].threadID = tid
        if let meta = metadata[key] { applyMetadata(meta, at: i) }
        if serverRequest {
            guard let data = rawData ?? (try? JSONSerialization.data(withJSONObject: m, options: [.sortedKeys])),
                  var wire = try? IslandCodexApprovalRequest(data: data) else { return }
            if wire.kind == .nativeOnly && !["mcpServer/elicitation/request"].contains(method) { return }
            if let itemID = p["itemId"] as? String, let entry = tasks[i].entries.last(where: { $0.publicItem?.sourceID == itemID }) {
                if let context = itemContexts[key + ":" + itemID] { wire.contextItem = context }
                _ = entry
            }
            if tasks[i].turnKey == nil { tasks[i].turnKey = turnKey }
            let requestKey = RequestLifecycle.rpcKey(wire.rpcIdentity, epoch: scope)
            guard !tasks[i].resolvedRequestKeys.contains(requestKey) else { return }
            let itemID = wire.params["itemId"].text
            guard !tasks[i].terminal else { return }
            let question = wire.titleText
            let canRespond = !wire.observationOnly && respond != nil && responseCapability?(wire) == true && wire.kind != .nativeOnly && wire.kind != .mcpURL && (wire.kind != .mcpForm || wire.supportedForm) && (wire.kind != .questions || wire.supportedQuestions)
            tasks[i].requestLifecycle.observe(.init(key: requestKey, value: .init(question: question,
                impact: canRespond ? .init("确认后继续任务。", "Approve to resume the task.")
                    : .init("此连接仅支持查看，请在 Codex 处理。", "This connection is read-only; handle the request in Codex."), protocolRequest: wire, canRespond: canRespond),
                callHash: itemID.isEmpty ? nil : CodexActivityPrivacy.hashIdentifier(itemID), rpcEpoch: scope,
                mode: method == "item/tool/requestUserInput" ? .synchronous : nil))
            onChange?(); return
        }
        switch method {
        case "turn/started":
            guard !(tasks[i].terminal && tasks[i].turnKey == turnKey) else { return }
            startTurn(i, key: turnKey, at: eventDate(p["startedAtMs"] ?? turn?["startedAtMs"], fallback: now))
            tasks[i].nativeState = true
            if let model = nonempty(p["model"]) { tasks[i].model = model; tasks[i].modelTurnKey = tasks[i].turnKey }
            if let effort = nonempty(p["reasoningEffort"]) { tasks[i].effort = effort; tasks[i].effortTurnKey = tasks[i].turnKey }
        case "turn/completed":
            guard !tasks[i].terminal else { return }
            let status = turn?["status"] as? String
            guard ["completed", "interrupted", "failed"].contains(status) else { return }
            tasks[i].activityStatus = status == "completed" ? .completed : status == "interrupted" ? .cancelled : .failed
            tasks[i].progress = status == "completed" ? 1 : tasks[i].progress
            tasks[i].endedAt = eventDate(turn?["completedAtMs"], fallback: now)
            tasks[i].requestLifecycle.finishTurn(); tasks[i].activeItems.removeAll()
            for item in turn?["items"] as? [[String: Any]] ?? [] where item["type"] as? String == "agentMessage" {
                appendItem(item, turnID: turnID ?? "", at: i)
            }
            if let error = turn?["error"] as? [String: Any], let message = error["message"] as? String {
                upsert(.init(text: .init(message), kind: .failure), at: i)
            }
        case "thread/status/changed": applyFlags(p["status"] as? [String: Any], at: i, epoch: scope)
        case "thread/tokenUsage/updated":
            if !usesAdmittedProgress,
               let data = rawData ?? (try? JSONSerialization.data(withJSONObject: m)),
               let usage = CodexAppServerActivityNotificationDecoder.decodeTokenUsage(data: data, now: now) { receiveToken(usage) }
        case "turn/plan/updated":
            if !usesAdmittedProgress, !tasks[i].terminal,
               let data = rawData ?? (try? JSONSerialization.data(withJSONObject: m)),
               let event = CodexAppServerActivityNotificationDecoder.decode(data: data, now: now) {
                tasks[i].progress = event.planProgress?.approximateFraction
            }
        case "serverRequest/resolved":
            if let encoded = try? JSONSerialization.data(withJSONObject: p),
               let id = CodexSharedMessageIdentity.rpcID(messageData: encoded, field: "requestId") {
                resolveRequest(i, id: id, epoch: scope)
            }
        case "item/started", "item/completed":
            guard let item = p["item"] as? [String: Any], let type = item["type"] as? String,
                  type != "reasoning", let itemID = item["id"] as? String else { break }
            if tasks[i].terminal {
                // Some streams deliver the final item after the terminal event.
                // Require its current turn and update content only, never state.
                if tasks[i].status == .completed, turnKey != nil, turnKey == tasks[i].turnKey,
                   method == "item/completed", type == "agentMessage" {
                    appendItem(item, turnID: turnID ?? "", at: i)
                    onPublicChange?()
                }
                return
            }
            // Retain only fields consumed by approval detail. Completed output
            // already has a bounded display entry and is not approval context.
            let needed = item.filter { ["type", "changes", "arguments", "server", "tool"].contains($0.key) }
            if let context = try? IslandApprovalJSON(any: needed) { setContext(context, key: key + ":" + itemID, task: key) }
            if type == "contextCompaction" {
                tasks[i].activityStatus = method == "item/started" ? .compacting : .thinking
                trim(i)
                break
            }
            let mode = CodexUserInputMode.forToolName(item["tool"] as? String ?? item["name"] as? String ?? item["toolName"] as? String)
            if method == "item/started" { tasks[i].requestLifecycle.observeMode(mode, callHash: CodexActivityPrivacy.hashIdentifier(itemID)) }
            if method == "item/started" && type != "agentMessage" {
                tasks[i].requestLifecycle.continueCall(CodexActivityPrivacy.hashIdentifier(itemID))
                let description = operationDescription(type, item: item)
                tasks[i].activeItems[itemID] = description
                tasks[i].activityStatus = .working
                tasks[i].operation = description
            }
            if method == "item/completed" {
                tasks[i].requestLifecycle.resolveCall(CodexActivityPrivacy.hashIdentifier(itemID), proofMode: mode, epoch: scope)
                tasks[i].activeItems.removeValue(forKey: itemID)
                if tasks[i].activeItems.isEmpty {
                    tasks[i].activityStatus = .thinking
                    tasks[i].operation = String((tasks[i].entries.last(where: { $0.publicItem?.category == .message })?.text.chinese ?? "").prefix(240))
                }
                else { tasks[i].activityStatus = .working; tasks[i].operation = tasks[i].activeItems.sorted { $0.key < $1.key }.last!.value }
            }
            if !appendItem(item, turnID: turnID ?? "", at: i) { trim(i) }
        case "item/agentMessage/delta", "item/commandExecution/outputDelta":
            guard !tasks[i].terminal, let itemID = p["itemId"] as? String, let delta = p["delta"] as? String else { break }
            appendDelta(delta, itemID: itemID, message: method.contains("agentMessage"), at: i)
            onPublicChange?(); return
        case "thread/archived", "thread/closed":
            removeTaskRecords { $0.key == key }; onChange?(); return
        default: return
        }
        tasks[i].updatedAt = now; onChange?()
    }
    private var itemContexts: [String: IslandApprovalJSON] = [:]
    private func applyMetadata(_ data: [String: Any], at i: Int) {
        if let name = nonempty(data["name"]) { applyTitle(name, source: .explicitName, at: i) }
        else { applyTitle(nonempty(data["title"]), source: .threadTitle, at: i) }
        if let model = nonempty(data["model"]), tasks[i].modelTurnKey == nil || tasks[i].modelTurnKey != tasks[i].turnKey { tasks[i].model = model }
        if let effort = nonempty(data["reasoningEffort"]) ?? nonempty(data["effort"]),
           tasks[i].effortTurnKey == nil || tasks[i].effortTurnKey != tasks[i].turnKey { tasks[i].effort = effort }
    }
    private func applyFlags(_ status: [String: Any]?, at i: Int, epoch: UInt64) {
        guard !tasks[i].terminal, let status, status["type"] as? String == "active" else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: status) else { return }
        let reason: CodexActivityWaitReason?
        switch CodexSharedMessageIdentity.waitStatus(statusData: data) {
        case .unavailable: return
        case .running: reason = nil
        case .waiting(let wait): reason = wait
        }
        tasks[i].requestLifecycle.setSourceWait(reason, waiting: reason != nil, epoch: epoch)
        // Thread continuation says execution resumed. It never says which
        // independent async question was answered, so request identities survive.
        if tasks[i].activityStatus != .compacting {
            tasks[i].activityStatus = tasks[i].activeItems.isEmpty ? .thinking : .working
        }
    }
    private func toolName(_ type: String, item: [String: Any]) -> String {
        switch type { case "commandExecution": return "exec"; case "fileChange": return "apply_patch"
        case "webSearch": return "web"; default: return item["tool"] as? String ?? type }
    }
    private func operationDescription(_ type: String, item: [String: Any]) -> String {
        let name = toolName(type, item: item)
        let detail: String
        if type == "commandExecution" { detail = item["command"] as? String ?? "" }
        else if type == "fileChange" { detail = (item["changes"] as? [[String: Any]] ?? []).compactMap { $0["path"] as? String }.joined(separator: ", ") }
        else { detail = "" }
        return name + " · " + String(detail.replacingOccurrences(of: "\n", with: " ").prefix(240))
    }
    @discardableResult
    private func appendItem(_ item: [String: Any], turnID: String, at i: Int) -> Bool {
        guard let type = item["type"] as? String, let itemID = item["id"] as? String else { return false }
        let category: CodexPublicTraceItem.Category
        let text: String; var output: String?; var truncated = false
        switch type {
        case "agentMessage": category = .message; text = item["text"] as? String ?? ""
        case "commandExecution": category = .command; text = item["command"] as? String ?? ""; output = item["aggregatedOutput"] as? String
        case "fileChange":
            category = .fileChange
            text = (item["changes"] as? [[String: Any]] ?? []).map { ($0["path"] as? String ?? "") + "\n" + ($0["diff"] as? String ?? "") }.joined(separator: "\n\n")
        case "mcpToolCall", "dynamicToolCall", "webSearch", "collabToolCall":
            category = .command
            let args = item["arguments"].flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys, .fragmentsAllowed]) }.flatMap { String(data: $0, encoding: .utf8) }
            text = toolName(type, item: item) + (args.map { "\n" + $0 } ?? "")
            output = (item["error"] as? [String: Any])?["message"] as? String
        default: return false
        }
        guard !text.isEmpty else { return false }
        beginNativeContent(i)
        let retained = Self.retainText(text)
        let retainedOutput = output.map(Self.retainText)
        truncated = retained.truncated || retainedOutput?.truncated == true
        let status = item["status"] as? String
        let exit = item["exitCode"] as? Int
        let failed = status == "failed" || exit.map { $0 != 0 } == true
        let phase = category == .message ? (item["phase"] as? String ?? item["channel"] as? String) : nil
        upsert(.init(text: .init(retained.text), kind: failed ? .failure : (["final", "final_answer"].contains(phase ?? "") ? .result : .progress),
            publicItem: .init(category: category, sourceID: itemID, turnID: turnID, status: status,
                output: retainedOutput?.text, sourceTruncated: truncated, exitCode: exit, messagePhase: phase)), at: i)
        if category == .message {
            tasks[i].publicProgress = messageSummary(text)
            if tasks[i].status == .thinking { tasks[i].operation = tasks[i].publicProgress }
        }
        return true
    }
    private func beginNativeContent(_ i: Int) {
        if !tasks[i].nativeContentAvailable { clearEntries(at: i); tasks[i].nativeContentAvailable = true }
    }
    /// The retained unit is a Character. The flag records actual loss, not a
    /// different UTF-8 threshold that can disagree for ASCII or combined text.
    static func retainText(_ text: String) -> (text: String, truncated: Bool) {
        guard text.utf8.count > 65_536,
              let end = text.index(text.startIndex, offsetBy: 65_536, limitedBy: text.endIndex), end != text.endIndex else { return (text, false) }
        return (String(text[..<end]), true)
    }
    private func appendDelta(_ delta: String, itemID: String, message: Bool, at i: Int) {
        beginNativeContent(i)
        if let j = tasks[i].entries.firstIndex(where: { $0.publicItem?.sourceID == itemID }) {
            let oldBytes = entryBytes(tasks[i].entries[j])
            let retained = Self.retainText((message ? tasks[i].entries[j].text.chinese : tasks[i].entries[j].publicItem?.output ?? "") + delta)
            if message { tasks[i].entries[j].text = .init(retained.text) }
            else { tasks[i].entries[j].publicItem?.output = retained.text }
            let wasTruncated = tasks[i].entries[j].publicItem?.sourceTruncated == true
            tasks[i].entries[j].publicItem?.sourceTruncated = wasTruncated || retained.truncated
            accountEntryChange(at: i, old: oldBytes, new: entryBytes(tasks[i].entries[j]))
            trim(i)
        } else if message {
            let retained = Self.retainText(delta)
            upsert(.init(text: .init(retained.text), publicItem: .init(category: .message, sourceID: itemID,
                turnID: tasks[i].turnKey ?? "", sourceTruncated: retained.truncated)), at: i)
        }
        if message, let text = tasks[i].entries.last(where: { $0.publicItem?.sourceID == itemID })?.text.chinese {
            tasks[i].publicProgress = messageSummary(text)
            if tasks[i].status == .thinking { tasks[i].operation = tasks[i].publicProgress }
        }
    }
    private func upsert(_ entry: IslandTraceEntry, at i: Int) {
        var entry = entry
        var oldBytes = 0
        if let source = entry.publicItem?.sourceID, let j = tasks[i].entries.firstIndex(where: { $0.publicItem?.sourceID == source }) {
            oldBytes = entryBytes(tasks[i].entries[j]); entry.id = tasks[i].entries[j].id; tasks[i].entries[j] = entry
        } else { tasks[i].entries.append(entry) }
        accountEntryChange(at: i, old: oldBytes, new: entryBytes(entry))
        trim(i)
    }
    private var totalEntryBytes = 0
    private var totalContextBytes = 0
    private var contextBytes: [String: Int] = [:]
    private var contextKeys: [String: Set<String>] = [:]
    private(set) var contentAccountingOperations = 0
    var retainedContentBytes: Int { totalEntryBytes + totalContextBytes }
    // Slow oracle for isolated accounting tests; never used on ingress.
    var contentAccountingOracle: Int {
        tasks.reduce(0) { $0 + $1.entries.reduce(0) { $0 + entryBytes($1) } }
            + itemContexts.values.reduce(0) { $0 + $1.data.count }
    }
    private func entryBytes(_ entry: IslandTraceEntry) -> Int { entry.text.chinese.utf8.count + (entry.publicItem?.output?.utf8.count ?? 0) }
    private func accountEntryChange(at i: Int, old: Int, new: Int) {
        contentAccountingOperations += 1
        tasks[i].retainedEntryBytes += new - old; totalEntryBytes += new - old
    }
    private func clearEntries(at i: Int) {
        totalEntryBytes -= tasks[i].retainedEntryBytes; tasks[i].retainedEntryBytes = 0; tasks[i].entries.removeAll()
    }
    private func setContext(_ value: IslandApprovalJSON, key: String, task: String) {
        let bytes = value.data.count
        totalContextBytes += bytes - (contextBytes[key] ?? 0)
        itemContexts[key] = value; contextBytes[key] = bytes; contextKeys[task, default: []].insert(key)
        contentAccountingOperations += 1
    }
    private func removeContext(_ key: String, task: String) {
        totalContextBytes -= contextBytes.removeValue(forKey: key) ?? 0
        itemContexts.removeValue(forKey: key); contextKeys[task]?.remove(key)
        if contextKeys[task]?.isEmpty == true { contextKeys.removeValue(forKey: task) }
    }
    private func clearContexts(for task: String) {
        for key in contextKeys.removeValue(forKey: task) ?? [] {
            totalContextBytes -= contextBytes.removeValue(forKey: key) ?? 0; itemContexts.removeValue(forKey: key)
        }
    }
    private func removeTaskRecords(where shouldRemove: (TaskRecord) -> Bool) {
        for task in tasks where shouldRemove(task) { totalEntryBytes -= task.retainedEntryBytes; clearContexts(for: task.key) }
        tasks.removeAll(where: shouldRemove)
    }
    private func trim(_ i: Int) {
        func discardOldest(_ index: Int) {
            let entry = tasks[index].entries.removeFirst(); tasks[index].removedEntryCount += 1
            accountEntryChange(at: index, old: entryBytes(entry), new: 0)
            if let id = entry.publicItem?.sourceID { removeContext(tasks[index].key + ":" + id, task: tasks[index].key) }
        }
        while tasks[i].entries.count > 200 { discardOldest(i) }
        while retainedContentBytes > 2_097_152,
              let old = tasks.indices.filter({ !tasks[$0].entries.isEmpty }).min(by: { tasks[$0].updatedAt < tasks[$1].updatedAt }) {
            discardOldest(old)
        }
        // Context-only items have no display row to evict. Approval requests
        // already own their required context copy and are never removed here.
        while retainedContentBytes > 2_097_152, let key = itemContexts.keys.sorted().first {
            guard let task = contextKeys.first(where: { $0.value.contains(key) })?.key else { break }
            removeContext(key, task: task)
        }
    }
    private func eventDate(_ value: Any?, fallback: Date) -> Date {
        guard let n = value as? NSNumber, n.doubleValue > 0 else { return fallback }
        return Date(timeIntervalSince1970: n.doubleValue / 1000)
    }
    private func asyncPresentationKey(_ pending: Pending, task: TaskRecord) -> String? {
        guard pending.mode == .asynchronous, let turn = task.turnKey,
              let wire = pending.value.protocolRequest, wire.kind == .questions else { return nil }
        let identity: String
        if case .asynchronousQuestion(let id)? = pending.desktopIdentity { identity = "native:" + id }
        else if let local = wire.localObservation, local.mode == .asynchronous { identity = "local:" + local.callID }
        else { return nil }
        return CodexActivityPrivacy.hashIdentifier(task.key + ":" + turn + ":" + identity)
    }
    private func isRetiredAsync(_ pending: Pending, task: TaskRecord) -> Bool {
        asyncPresentationKey(pending, task: task).map { retiredAsyncPresentations[$0] != nil } ?? false
    }
    private func retireAsyncPresentation(taskIndex i: Int, requestID: UUID, at now: Date) -> Bool {
        guard let pending = tasks[i].requestLifecycle.requests.first(where: { $0.value.id == requestID }),
              let key = asyncPresentationKey(pending, task: tasks[i]) else { return false }
        if case .submitting = pending.value.phase { return false }
        retiredAsyncPresentations[key] = now.timeIntervalSince1970
        if retiredAsyncPresentations.count > 4096 {
            for old in retiredAsyncPresentations.sorted(by: { $0.value < $1.value })
                .prefix(retiredAsyncPresentations.count - 4096) { retiredAsyncPresentations.removeValue(forKey: old.key) }
        }
        archiveDefaults?.set(retiredAsyncPresentations, forKey: Self.retiredAsyncKey)
        asyncPresentations.removeValue(forKey: key)
        tasks[i].requestLifecycle.requests.removeAll { $0.value.id == requestID }
        tasks[i].requestIndex = min(tasks[i].requestIndex, max(0, tasks[i].requests.count - 1))
        // Do not emit an accepted reply, serverRequest/resolved, or wait settlement.
        return true
    }
    func claimConfirmation(taskID: Int, requestID: UUID) {
        guard let task = tasks.first(where: { $0.id == taskID }),
              let pending = task.requestLifecycle.requests.first(where: { $0.value.id == requestID }),
              let key = asyncPresentationKey(pending, task: task) else { return }
        var presentation = asyncPresentations[key] ?? .init()
        presentation.claimed = true; presentation.expiresAt = nil
        asyncPresentations[key] = presentation
    }
    func dismissConfirmation(taskID: Int, requestID: UUID) {
        guard let i = tasks.firstIndex(where: { $0.id == taskID }),
              let pending = tasks[i].requests.first(where: { $0.value.id == requestID }) else { return }
        if retireAsyncPresentation(taskIndex: i, requestID: requestID, at: Date()) { onChange?(); return }
        if pending.isGeneric, tasks[i].requestLifecycle.canHideObserverReminder {
            tasks[i].observerReminderDismissed = true
            onChange?()
        }
    }
    private func advanceConfirmationPresentation(at now: Date, visible: Bool) {
        var activeKeys: Set<String> = []
        for i in tasks.indices {
            let pendingRequests = tasks[i].requestLifecycle.requests
            for pending in pendingRequests {
                guard let key = asyncPresentationKey(pending, task: tasks[i]) else { continue }
                activeKeys.insert(key)
                if retiredAsyncPresentations[key] != nil {
                    tasks[i].requestLifecycle.requests.removeAll { $0.value.id == pending.value.id }
                    continue
                }
                var presentation = asyncPresentations[key] ?? .init()
                switch pending.value.phase {
                case .submitting:
                    presentation.claimed = true; presentation.expiresAt = nil
                case .sent, .resultUnknown:
                    // Submission is not settlement. Retire the local panel while
                    // Codex remains the place to inspect an uncertain result.
                    if presentation.handoffAt == nil { presentation.handoffAt = now.addingTimeInterval(3) }
                case .ready, .failed:
                    if visible && !isArchived(tasks[i]) && !presentation.claimed && presentation.expiresAt == nil {
                        presentation.expiresAt = now.addingTimeInterval(30)
                    }
                case .resolved: presentation.handoffAt = now
                }
                asyncPresentations[key] = presentation
                if let deadline = presentation.handoffAt ?? presentation.expiresAt, now >= deadline {
                    _ = retireAsyncPresentation(taskIndex: i, requestID: pending.value.id, at: now)
                }
            }
            tasks[i].requestIndex = min(tasks[i].requestIndex, max(0, tasks[i].requests.count - 1))
        }
        asyncPresentations = asyncPresentations.filter { activeKeys.contains($0.key) }
    }
    func submit(_ id: Int, requestID: UUID, decision: IslandConfirmationDecision) {
        if decision == .skipQuestion, let task = tasks.first(where: { $0.id == id }),
           let pending = task.requests.first(where: { $0.value.id == requestID }), pending.mode == .asynchronous {
            dismissConfirmation(taskID: id, requestID: requestID); return
        }
        guard let i = tasks.firstIndex(where: { $0.id == id }),
              let j = tasks[i].requestLifecycle.requests.firstIndex(where: { $0.value.id == requestID }),
              tasks[i].requestLifecycle.requests[j].value.canRespond, tasks[i].requestLifecycle.requests[j].value.phase.canSubmit,
              let wire = tasks[i].requestLifecycle.requests[j].value.protocolRequest,
              !wire.observationOnly, responseCapability?(wire) == true else { return }
        let turn = tasks[i].turnKey
        let epoch = connectionEpoch
        let handle = wire.desktopHandle
        if let handle {
            guard desktopConnected, desktopConnectionEpoch == handle.connectionEpoch,
                  turn == CodexActivityPrivacy.hashIdentifier(handle.turnID),
                  desktopScopes[tasks[i].key]?.owner == handle.ownerClientID else { return }
        }
        if decision == .skipQuestion {
            guard wire.kind == .questions, wire.supportedQuestions else { return }
            if let skip = wire.questionSkipResult {
                submit(id, requestID: requestID, decision: .reply(skip))
            } else if wire.userInputMode == .asynchronous, handle?.kind == .asynchronousQuestion,
                      tasks[i].requestLifecycle.skipAsyncQuestion(requestID) {
                // No RPC, answer tombstone, or source-wait settlement is emitted.
                onChange?()
            }
            return
        }
        guard case .reply(let result) = decision, wire.permits(result), let respond else { return }
        claimConfirmation(taskID: id, requestID: requestID)
        tasks[i].requestLifecycle.requests[j].value.phase = .submitting(decision); onChange?()
        Task { [weak self] in
            guard let self else { return }
            @MainActor func currentRequest() -> (Int, Int)? {
                guard let i = tasks.firstIndex(where: { $0.id == id && $0.turnKey == turn }),
                      let j = tasks[i].requestLifecycle.requests.firstIndex(where: { $0.value.id == requestID }),
                      tasks[i].requestLifecycle.requests[j].value.canRespond,
                      tasks[i].requestLifecycle.requests[j].value.phase == .submitting(decision) else { return nil }
                if let handle {
                    guard desktopConnected, desktopConnectionEpoch == handle.connectionEpoch,
                          tasks[i].requestLifecycle.requests[j].value.protocolRequest?.desktopHandle == handle,
                          desktopScopes[tasks[i].key]?.owner == handle.ownerClientID else { return nil }
                } else if epoch != connectionEpoch { return nil }
                return (i, j)
            }
            guard let (i, j) = currentRequest() else { return }
            guard responseCapability?(wire) == true else {
                tasks[i].requestLifecycle.requests[j].value.phase = .resultUnknown
                tasks[i].requestLifecycle.requests[j].value.canRespond = false; onChange?(); return
            }
            do {
                try await respond(wire, result)
                guard let (i, j) = currentRequest() else { return }
                tasks[i].requestLifecycle.requests[j].value.phase = .sent; onChange?()
            } catch {
                guard let (i, j) = currentRequest() else { return }
                tasks[i].requestLifecycle.requests[j].value.phase = .resultUnknown
                tasks[i].requestLifecycle.requests[j].value.canRespond = false; onChange?()
            }
        }
    }
    private func advanceProgress(at now: Date) {
        for i in tasks.indices {
            if tasks[i].status == .completed { tasks[i].displayedProgress = 1; continue }
            guard !tasks[i].terminal else { continue }
            let previous = tasks[i].progressUpdatedAt ?? tasks[i].startedAt ?? now
            guard now >= previous else { continue }
            // Resolve using the existing single-island algorithm, owned by the
            // task rather than a disposable selected-row renderer. Bound catch-up.
            var remaining = min(60, now.timeIntervalSince(previous))
            repeat {
                let step = min(0.25, remaining)
                if let value = tasks[i].progressResolver.resolve(state: tasks[i].status.visualState,
                    plannedFraction: tasks[i].progress, elapsed: Float(step), reduceMotion: false) {
                    tasks[i].displayedProgress = max(tasks[i].displayedProgress, min(value, 0.95))
                }
                remaining -= step
            } while remaining > 0.000001
            tasks[i].progressUpdatedAt = now
        }
    }
    func display(english: Bool, remaining: Int?, enabled: Bool, privacy: Bool, at now: Date = Date()) -> CodexMultitaskDisplay {
        advanceConfirmationPresentation(at: now, visible: enabled && !privacy)
        advanceProgress(at: now)
        var details: [Int: IslandTaskDetailData] = [:]; var metas: [Int: IslandSessionMetadata] = [:]
        let copy = CodexActivityCopy(language: english ? .english : .simplifiedChinese)
        let visibleTasks = tasks.filter { !isArchived($0) }
        let items = visibleTasks.map { task -> CodexMultitaskRenderTask in
            let settlement = task.terminal ? nil : task.requestLifecycle.desktopSettlementDisplay(at: now)
            let synchronizing = settlement == .synchronizing
            let presentationStatus = settlement == nil ? task.status : task.activityStatus
            let visual: CodexActivityVisualState = synchronizing ? .working : presentationStatus.visualState
            let duration = task.startedAt.map { max(0, Int((task.endedAt ?? now).timeIntervalSince($0))) }
            let children = privacy ? [] : childPresentations(parent: task.key, english: english, at: now)
            let runningChildren = children.filter { [.thinking, .working, .compactingContext].contains($0.visualState) }
            metas[task.id] = .init(modelName: task.model.isEmpty ? (english ? "Unknown model" : "模型未知") : task.model, reasoningEffort: task.effort, elapsedSeconds: duration, subagents: children)
            var request = task.requests.isEmpty ? nil : task.requests[min(task.requestIndex, task.requests.count - 1)].value
            if settlement != nil { request = nil }
            if let pending = task.requests.first(where: { $0.value.id == request?.id }) {
                request?.canDismissLocally = asyncPresentationKey(pending, task: task) != nil
                    || (pending.isGeneric && task.requestLifecycle.canHideObserverReminder)
            }
            request?.queueIndex = task.requestIndex + 1; request?.queueCount = task.requests.count
            details[task.id] = .init(entries: privacy ? [] : task.entries, confirmation: privacy ? nil : request, status: presentationStatus, removedEntryCount: task.removedEntryCount)
            let title = privacy ? (english ? "Codex task" : "Codex 任务") : (task.title.isEmpty ? (english ? "Untitled task" : "未命名任务") : task.title)
            let status: String
            if synchronizing { status = english ? "Syncing" : "同步中" }
            else if task.status == .cancelled { status = english ? "Interrupted" : "已中断" }
            else if task.status == .queued { status = english ? "Queued" : "排队中" }
            else if presentationStatus == .waiting && task.sourceWaitReason == .userInput { status = english ? "Awaiting answer" : "等待回答" }
            else { status = copy.statusTitle(for: visual) }
            let operation: String
            if task.operation == "exec" || task.operation.hasPrefix("exec · ") {
                operation = (english ? "Executing" : "执行中") + task.operation.dropFirst(4)
            } else if !task.operation.isEmpty { operation = task.operation }
            else if !runningChildren.isEmpty && !task.terminal {
                operation = summary(runningChildren.map(\.title).joined(separator: english ? ", " : "、")) + (english ? " are working" : " 正在工作")
            } else { operation = task.publicProgress }
            let render = CodexActivityRenderState(taskIdentity: .init(sessionHash: task.key, turnHash: task.turnKey),
                visualState: visual, approximateProgressFraction: task.displayedProgress,
                windowTitle: title, statusTitle: status, operation: privacy || task.status == .compacting ? "" : (synchronizing
                    ? (english ? "Request handled" : "请求已处理") : presentationStatus == .waiting
                    ? status + " · " + (request?.question.value(english) ?? "") : operation),
                tokenUsageTitle: task.tokens.map { CodexActivityTokenUsageFormatter.string(for: $0) + " tokens" },
                accessibilityLabel: "\(title), \(status)")
            return .init(id: task.id, renderState: render, playbackEnabled: !task.terminal || task.status == .completed, hasPendingRequest: settlement == nil && !task.requests.isEmpty)
        }
        let connectionCopy = AppCopy(language: english ? .english : .simplifiedChinese)
        return .init(state: .init(tasks: items, selectedID: selectedID, allCompleted: !visibleTasks.isEmpty && visibleTasks.allSatisfy(\.terminal), compact: true, receiptStartedAt: nil),
            english: english, effect: .dropField, visible: enabled, playbackEnabled: true, totalTokens: nil, remainingPercent: remaining,
            sessionMetadata: metas, taskDetails: details, connectionTitle: connection == .connected || desktopConnected
                ? (visibleTasks.isEmpty ? connectionCopy.text("就绪", "Ready") : connectionCopy.text("已连接", "Connected"))
                : (visibleTasks.isEmpty ? connectionCopy.text("等待 Codex 任务", "Waiting for Codex") : connectionCopy.text("本地活动数据", "Local activity")),
            privacyMode: privacy, activeRequestIDs: privacy ? [] : Set(visibleTasks.flatMap {
                $0.requestLifecycle.desktopSettlementDisplay(at: now) != nil ? [] : $0.requests.map { $0.value.id }
            }))
    }
}
