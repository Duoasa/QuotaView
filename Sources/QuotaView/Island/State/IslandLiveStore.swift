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
    typealias RequestLifecycle = IslandRequestLifecycle<IslandConfirmation>
    typealias Pending = RequestLifecycle.Pending
    typealias DesktopRequestIdentity = RequestLifecycle.DesktopRequestIdentity

    struct TaskRecord {
        let id: Int
        let key: String
        var threadID: String?
        var desktopThreadID: UUID?
        var nativeConversation: IslandConversationTarget?
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
        var antigravityFocus: AntigravityHistory.Focus?
        var tokens: Int64?
        var outputRate: CodexOutputRateSample?
        var averageOutputRate: CodexOutputRateSample?
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
        var activeItems: [String: String] = [:]
        var terminal: Bool { [.completed, .failed, .cancelled].contains(activityStatus) }
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
    var usesLegacyDesktopAnswers: Bool { desktopConnected }
    private var desktopConnectionEpoch: UInt64?
    private struct DesktopScope { let owner: String; let epoch: UInt64; let streamGeneration: UInt64; let revision: Int64 }
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

    func receiveSubagentIdentity(_ identity: CodexActivitySubagentIdentity, migratingTurn: String? = nil) {
        guard presentationKind(for: identity.sessionHash) != .memoryConsolidation else { return }
        if let previous = subagents[identity.sessionHash], previous.identity.parentSessionHash != identity.parentSessionHash { return }
        // Store supplies a validated native parent relation. Legacy generic
        // internal classification may be refined, but never a memory execution.
        sessionKinds[identity.sessionHash] = .subagent
        // Antigravity may publish its parent after the hook has already created a task.
        let observed = migratingTurn.flatMap { turn in tasks.first { $0.key == identity.sessionHash && $0.turnKey == turn } }
        withdrawNonUserSession(identity.sessionHash, kind: .subagent)
        if subagents[identity.sessionHash] == nil {
            var child = SubagentRecord(identity: identity)
            if let observed {
                child.turn = observed.turnKey
                child.status = observed.activityStatus
                child.startedAt = observed.startedAt
                child.updatedAt = observed.updatedAt
                child.source = .hook
                child.model = observed.model
                child.progress = observed.antigravityFocus?.title ?? observed.publicProgress
            }
            subagents[identity.sessionHash] = child
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

    private func childPresentations(parent: String, english: Bool, language: AppPreferences.Language, at now: Date) -> [IslandSubagentPresentation] {
        subagents.values.filter { $0.identity.parentSessionHash == parent && $0.startedAt != nil && !$0.terminal
            && presentationKind(for: $0.identity.sessionHash) == .subagent }
            .sorted { ($0.startedAt ?? .distantPast, $0.identity.sessionHash) < ($1.startedAt ?? .distantPast, $1.identity.sessionHash) }
            .map { child in
                let copy = AppCopy(language: language)
                let title = child.title.isEmpty ? (child.identity.nickname ?? child.identity.role ?? copy.islandSubagentTitle) : child.title
                let status: String
                switch child.status {
                case .unknown: status = copy.islandSubagentStatusUnavailable
                case .cancelled: status = copy.islandSubagentInterrupted
                default: status = CodexActivityCopy(language: language).statusTitle(for: child.status.visualState)
                }
                let metadata = IslandSessionMetadata(modelName: child.model, reasoningEffort: child.effort,
                    elapsedSeconds: child.status == .unknown ? nil : child.startedAt.map { max(0, Int(now.timeIntervalSince($0))) })
                return .init(id: child.identity.sessionHash, title: title, status: status, visualState: child.status.visualState,
                             model: metadata.modelTitle, duration: metadata.durationTitle, detail: child.progress,
                             avatar: provider(for: parent) == .codex ? child.identity.avatar : nil, provider: provider(for: parent))
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
        tasks.removeAll { $0.key == key }
        metadata.removeValue(forKey: key); desktopScopes.removeValue(forKey: key)
        pendingLocalContent.removeAll { $0.sessionHash == key }
        itemContexts = itemContexts.filter { !$0.key.hasPrefix(key + ":") }
        itemContextOrder.removeAll { itemContexts[$0] == nil }
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
    var claudeResponseCapability: ((IslandCodexApprovalRequest) -> Bool)?
    var claudeRespond: ((IslandCodexApprovalRequest, IslandApprovalJSON) async throws -> Void)?
    var antigravityResponseCapability: ((IslandCodexApprovalRequest) -> Bool)?
    var antigravityRespond: ((IslandCodexApprovalRequest, IslandApprovalJSON) async throws -> Void)?
    var devinCapabilities: [IslandAgentProvider: (IslandCodexApprovalRequest) -> Bool] = [:]
    var devinResponders: [IslandAgentProvider: (IslandCodexApprovalRequest, IslandApprovalJSON) async throws -> Void] = [:]
    var openCodeResponseCapability: ((IslandCodexApprovalRequest) -> Bool)?
    var openCodeRespond: ((IslandCodexApprovalRequest, IslandApprovalJSON) async throws -> Void)?
    var dshResponseCapability: ((IslandCodexApprovalRequest) -> Bool)?
    var dshRespond: ((IslandCodexApprovalRequest, IslandApprovalJSON) async throws -> Void)?
    private var providers: [String: IslandAgentProvider] = [:]
    private var disabledProviders = Set<IslandAgentProvider>()
    func setProviderEnabled(_ provider: IslandAgentProvider, enabled: Bool) {
        if enabled { disabledProviders.remove(provider); return }
        guard disabledProviders.insert(provider).inserted else { return }
        let removed = Set(tasks.filter { self.provider(for: $0.key) == provider }.map(\.id))
        tasks.removeAll { removed.contains($0.id) }
        if removed.contains(selectedID) { selectedID = tasks.first?.id ?? 0 }
        if let preservedID, removed.contains(preservedID) { self.preservedID = nil }
        onChange?()
    }

    func setProvider(_ provider: IslandAgentProvider, for key: String) {
        guard providers[key] != provider else { return }
        providers[key] = provider
        if providers.count > 512, let stale = providers.keys.first(where: { key in !tasks.contains { $0.key == key } }) {
            providers.removeValue(forKey: stale)
        }
    }
    func setConversation(_ target: IslandConversationTarget?, for key: String, provider: IslandAgentProvider) {
        guard self.provider(for: key) == provider, let i = tasks.firstIndex(where: { $0.key == key }),
              tasks[i].nativeConversation != target else { return }
        tasks[i].nativeConversation = target
        onChange?()
    }
    func provider(for key: String) -> IslandAgentProvider { providers[key] ?? .codex }

    /// Claude Code permission prompts have no Codex transport. The Hook keeps
    /// its connection open; closing it, a tool result or the turn end retires it.
    func observeClaudeRequest(_ wire: IslandCodexApprovalRequest, sessionKey: String, turnKey: String,
                              callHash: String?, interactive: Bool) {
        guard wire.isClaudeCode, let i = tasks.firstIndex(where: { $0.key == sessionKey }),
              tasks[i].turnKey == turnKey, !tasks[i].terminal else { return }
        let canRespond = interactive && claudeRespond != nil && claudeResponseCapability?(wire) == true
            && (wire.kind != .questions || wire.supportedQuestions)
        let title = [wire.questions.first?.title ?? "", wire.params["message"].text, wire.params["reason"].text]
            .first { !$0.isEmpty }
        let question = title.map { IslandDetailText($0) }
            ?? .init("Claude Code 请求你的处理", "Claude Code requests your input")
        tasks[i].requestLifecycle.observe(.init(key: "claude:" + wire.key, value: .init(question: question,
            impact: canRespond ? .init("处理后同步至 Claude Code。", "Send this response to Claude Code.")
                : .init("请在运行 Claude Code 的终端处理。", "Handle this request in the Claude Code terminal."),
            protocolRequest: wire, canRespond: canRespond), callHash: callHash, rpcEpoch: 0,
            mode: wire.kind == .questions ? .synchronous : nil))
        tasks[i].observerReminderDismissed = false
        onChange?()
    }
    func markOpenCodeDeliveryUnknown(_ wire: IslandCodexApprovalRequest) {
        guard wire.isOpenCode, let i = tasks.firstIndex(where: { $0.key == wire.threadID && $0.turnKey == wire.turnID }),
              let j = tasks[i].requestLifecycle.requests.firstIndex(where: { $0.value.protocolRequest?.rpcID == wire.rpcID })
        else { return }
        tasks[i].requestLifecycle.requests[j].value.phase = .resultUnknown
        tasks[i].requestLifecycle.requests[j].value.canRespond = false
        onChange?()
    }

    func resolveLocalHookRequest(sessionKey: String, rpcID: IslandApprovalJSON) {
        guard let i = tasks.firstIndex(where: { $0.key == sessionKey }),
              tasks[i].requestLifecycle.resolveRPC(rpcID, epoch: 0) else { return }
        onChange?()
    }

    func observeCodexPermissionHook(_ wire: IslandCodexApprovalRequest, callHash: String?) -> Bool {
        guard wire.isCodexPermissionHook, !desktopConnected, capability(for: wire),
              let i = tasks.firstIndex(where: { $0.key == wire.threadID && $0.turnKey == wire.turnID && !$0.terminal }),
              !isArchived(tasks[i]), provider(for: wire.threadID) == .codex else { return false }
        let question = IslandDetailText("允许执行这条命令？", "Allow this command?")
        tasks[i].requestLifecycle.observe(.init(key: wire.rpcID.text, value: .init(question: question,
            impact: .init("处理后同步至 Codex。", "Send this response to Codex."), protocolRequest: wire, canRespond: true),
            callHash: callHash, rpcEpoch: 0))
        guard tasks[i].requests.contains(where: { $0.value.protocolRequest?.rpcID == wire.rpcID }) else { return false }
        tasks[i].observerReminderDismissed = false
        onChange?()
        return true
    }

    @discardableResult
    func observeNativeToolRequest(_ wire: IslandCodexApprovalRequest, sessionKey: String, turnKey: String, callHash: String) -> Bool {
        let agent = wire.devinProvider ?? (wire.isOpenCode ? IslandAgentProvider.openCode : wire.isDSH ? .dsh : .antigravity)
        guard wire.isDSH || wire.isAntigravity || wire.isOpenCode || wire.devinProvider != nil, provider(for: sessionKey) == agent, capability(for: wire),
              let i = tasks.firstIndex(where: { $0.key == sessionKey && $0.turnKey == turnKey && !$0.terminal }) else { return false }
        tasks[i].requestLifecycle.observe(.init(key: (agent.rawValue + ":") + wire.key, value: .init(
            question: wire.kind == .questions ? .init(wire.questions.first?.title ?? "") : wire.isOpenCode || wire.devinProvider != nil ? wire.kind.title : wire.isDSH ? .init("DSH 请求审批", "DSH requests approval") : .init("Antigravity 请求审批", "Antigravity requests approval"),
            impact: wire.devinProvider != nil ? .init(agent.displayName) : wire.isOpenCode ? .init("处理后同步至 OpenCode。", "Send this response to OpenCode.") : wire.isDSH ? .init("处理后同步至 DSH。", "Send this response to DSH.") : .init("处理后同步至 Antigravity。", "Send this response to Antigravity."), protocolRequest: wire, canRespond: true),
            callHash: callHash, rpcEpoch: 0))
        let admitted = tasks[i].requests.contains { $0.value.protocolRequest?.rpcID == wire.rpcID }
        if admitted { tasks[i].observerReminderDismissed = false; onChange?() }
        return admitted
    }

    /// Relinquish the local capability and erase arguments. The original source
    /// is still waiting; only its actual decision/tool event settles that wait.
    func returnDSHRequest(sessionKey: String, rpcID: IslandApprovalJSON) {
        guard let i = tasks.firstIndex(where: { $0.key == sessionKey }),
              let j = tasks[i].requestLifecycle.requests.firstIndex(where: { $0.value.protocolRequest?.isDSH == true && $0.value.protocolRequest?.rpcID == rpcID }) else { return }
        tasks[i].requestLifecycle.requests[j].value.protocolRequest = nil
        tasks[i].requestLifecycle.requests[j].value.canRespond = false
        tasks[i].requestLifecycle.requests[j].value.phase = .ready
        tasks[i].requestLifecycle.requests[j].value.impact = .init("请在 DSH 中处理。", "Handle this request in DSH.")
        tasks[i].requestLifecycle.requests[j].rpcEpoch = nil
        tasks[i].requestLifecycle.requests[j].isGeneric = true
        onChange?()
    }

    /// Returning the helper to Claude Code revokes local answers, but the
    /// underlying permission still waits in the terminal until a real event settles it.
    func returnClaudeRequestToTerminal(sessionKey: String, rpcID: IslandApprovalJSON) {
        guard let i = tasks.firstIndex(where: { $0.key == sessionKey }),
              let request = tasks[i].requestLifecycle.requests.firstIndex(where: {
                  $0.value.protocolRequest?.isClaudeCode == true && $0.value.protocolRequest?.rpcID == rpcID
              }) else { return }
        tasks[i].requestLifecycle.requests[request].value.canRespond = false
        tasks[i].requestLifecycle.requests[request].value.impact = .init(
            "请在运行 Claude Code 的终端处理。", "Handle this request in the Claude Code terminal.")
        onChange?()
    }

    func reset() { messageSummaryCache.removeAll(); asyncPresentations.removeAll(); subagents.removeAll(); subagentOrder.removeAll(); tasks.removeAll(); providers.removeAll(); metadata.removeAll(); sessionKinds.removeAll(); sessionKindOrder.removeAll(); executionMemorySessions.removeAll(); executionKindOrder.removeAll(); priorTurnKeys.removeAll(); itemContexts.removeAll(); itemContextOrder.removeAll(); pendingLocalContent.removeAll(); selectedID = 0; nativeConnectionEpoch = nil; desktopConnected = false; desktopConnectionEpoch = nil; desktopScopes.removeAll(); connectionEpoch += 1; onChange?() }
    func select(_ id: Int) { if tasks.contains(where: { $0.id == id }) { selectedID = id; onChange?() } }
    func setConnection(_ state: CodexSharedAppServerConnectionState) {
        guard state != connection else { return }
        if state != .connected {
            connectionEpoch += 1
            for i in tasks.indices { tasks[i].requestLifecycle.invalidateResponses() }
        }
        connection = state; onChange?()
    }
    /// Upgrade the existing local question in place. Keep request UUID, drafts,
    /// receipts and visibility; never synthesize another question from a poll.
    func updateSharedQuestionCapabilities(threadID: String? = nil, handles: [CodexSharedQuestionHandle]) {
        let session = threadID.map(CodexActivityPrivacy.hashIdentifier)
        var changed = false
        for i in tasks.indices where session == nil || tasks[i].key == session {
            for j in tasks[i].requestLifecycle.requests.indices {
                guard let wire = tasks[i].requestLifecycle.requests[j].value.protocolRequest,
                      wire.localObservation?.asynchronous == true, wire.desktopHandle == nil else { continue }
                if threadID != nil, !tasks[i].requestLifecycle.requests[j].value.phase.canSubmit {
                    continue // An in-flight/unknown action cannot be replaced by a polling refresh.
                }
                let matching = handles.first {
                    wire.localObservation?.callID == $0.sourceItemID
                        && tasks[i].key == CodexActivityPrivacy.hashIdentifier($0.threadID)
                        && tasks[i].turnKey == CodexActivityPrivacy.hashIdentifier($0.turnID)
                }
                let updated = wire.attachingSharedQuestionHandle(tasks[i].terminal || desktopConnected ? nil : matching)
                let canRespond = (updated.sharedQuestionHandle != nil || updated.nativeQuestionCard != nil) && respond != nil && capability(for: updated)
                if updated != wire || canRespond != tasks[i].requestLifecycle.requests[j].value.canRespond {
                    tasks[i].requestLifecycle.requests[j].value.protocolRequest = updated
                    tasks[i].requestLifecycle.requests[j].value.canRespond = canRespond
                    if !canRespond && !tasks[i].requestLifecycle.requests[j].value.phase.canSubmit {
                        tasks[i].requestLifecycle.requests[j].value.phase = .resultUnknown
                    }
                    changed = true
                }
            }
        }
        if changed { onChange?() }
    }

    func nativeQuestionTargets(_ identities: [CodexLocalRolloutThreadIdentity]) -> [CodexDesktopQuestionInput.Target] {
        tasks.flatMap { task -> [CodexDesktopQuestionInput.Target] in
            guard !task.terminal, let turn = task.turnKey,
                  let identity = identities.first(where: { $0.sessionHash == task.key && $0.sessionKind == .user }),
                  let thread = UUID(uuidString: identity.threadID) else { return [] }
            return task.requests.compactMap { pending in
                guard pending.value.phase.canSubmit, let wire = pending.value.protocolRequest,
                      wire.desktopHandle == nil, wire.sharedQuestionHandle == nil, !wire.contextUnavailable,
                      let local = wire.localObservation, local.asynchronous, local.turnHash == turn,
                      wire.questions.count == 1, wire.supportedQuestions, let q = wire.questions.first, !q.secret
                else { return nil }
                return .init(thread: thread, turnHash: turn, callID: local.callID,
                             question: q.title, options: q.options.map { $0["label"].text })
            }
        }
    }

    func isSubmittingNativeQuestion(_ card: CodexDesktopQuestionInput.Card) -> Bool {
        guard let task = tasks.first(where: { $0.key == CodexActivityPrivacy.hashIdentifier(card.target.thread.uuidString.lowercased()) }),
              !task.terminal, task.turnKey == card.target.turnHash else { return false }
        let matches = task.requests.filter { pending in
            guard let wire = pending.value.protocolRequest, wire.localObservation?.asynchronous == true else { return false }
            return wire.questions.contains { $0.title == card.target.question && $0.options.map { $0["label"].text } == card.target.options }
        }
        guard matches.count == 1, let request = matches.first, case .submitting = request.value.phase else { return false }
        return request.value.canRespond && request.value.protocolRequest?.nativeQuestionCard == card
    }

    func updateNativeQuestionCards(_ cards: [CodexDesktopQuestionInput.Card]) {
        var changed = false
        for i in tasks.indices {
            for j in tasks[i].requestLifecycle.requests.indices {
                let pending = tasks[i].requestLifecycle.requests[j].value
                guard pending.phase.canSubmit, var wire = pending.protocolRequest,
                      let local = wire.localObservation, local.asynchronous else { continue }
                let card = cards.first { card in
                    let t = card.target
                    return t.turnHash == local.turnHash && t.callID == local.callID &&
                        CodexActivityPrivacy.hashIdentifier(t.thread.uuidString.lowercased()) == local.sessionHash &&
                        wire.questions.count == 1 && wire.questions[0].title == t.question &&
                        wire.questions[0].options.map { $0["label"].text } == t.options
                }
                let previous = wire.nativeQuestionCard
                wire.nativeQuestionCard = desktopConnected || tasks[i].terminal || wire.sharedQuestionHandle != nil ? nil : card
                let enabled = (wire.nativeQuestionCard != nil || wire.sharedQuestionHandle != nil) && respond != nil && capability(for: wire)
                if wire.nativeQuestionCard != previous || enabled != pending.canRespond {
                    tasks[i].requestLifecycle.requests[j].value.protocolRequest = wire
                    tasks[i].requestLifecycle.requests[j].value.canRespond = enabled
                    changed = true
                }
            }
        }
        if changed { onChange?() }
    }

    func setDesktopConnection(connected: Bool, epoch: UInt64?) {
        let changedEpoch = epoch != nil && desktopConnectionEpoch != epoch
        if !connected || changedEpoch {
            for i in tasks.indices { tasks[i].requestLifecycle.desktopDisconnected() }
        }
        desktopConnected = connected
        if connected { updateSharedQuestionCapabilities(handles: []) }
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
            guard snapshot.streamGeneration >= prior.streamGeneration else { return }
            guard snapshot.streamGeneration > prior.streamGeneration || prior.owner != snapshot.ownerClientID || snapshot.revision > prior.revision else { return }
            if snapshot.streamGeneration != prior.streamGeneration || prior.owner != snapshot.ownerClientID { tasks[i].requestLifecycle.invalidateDesktopResponses() }
        }
        desktopScopes[key] = .init(owner: snapshot.ownerClientID, epoch: snapshot.connectionEpoch, streamGeneration: snapshot.streamGeneration, revision: snapshot.revision)
        tasks[i].threadID = snapshot.conversationID
        if snapshot.hostID == "local" { tasks[i].desktopThreadID = UUID(uuidString: snapshot.conversationID) }
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
            let title = wire.questions.first?.title ?? (wire.params["message"].text.isEmpty
                ? (wire.params["reason"].text.isEmpty ? "Codex 请求你的处理" : wire.params["reason"].text) : wire.params["message"].text)
            return .init(key: "desktop:" + CodexActivityPrivacy.hashIdentifier(snapshot.ownerClientID) + ":\(snapshot.connectionEpoch):" + identityKey,
                value: .init(question: .init(title), impact: canRespond ? .init("处理后同步至 Codex。", "Send this response to Codex.")
                    : .init("请在 Codex 处理。", "Handle this request in Codex."), protocolRequest: wire, canRespond: canRespond),
                callHash: call, desktopIdentity: identity, desktopOwner: snapshot.ownerClientID,
                desktopEpoch: snapshot.connectionEpoch, mode: mode)
        }
        let wasWaiting = tasks[i].requestLifecycle.waitingOnSource || tasks[i].requestLifecycle.hasBlockingRequest
        if projection.pendingRequestsAreAuthoritative {
            tasks[i].requestLifecycle.admitAuthoritativeDesktopQuestions(at: observedAt)
            tasks[i].requestLifecycle.observeDesktopRuntimeWait(projection, owner: snapshot.ownerClientID,
                epoch: snapshot.connectionEpoch, at: observedAt)
        }
        for request in projection.requests where request.turnID == turn {
            guard var wire = try? IslandCodexApprovalRequest(data: request.envelopeData) else { continue }
            wire = wire.attachingDesktopHandle(handle(request.requestID, method: request.method, turn: turn))
            if let context = request.contextItemData { wire.contextItem = try? JSONDecoder().decode(IslandApprovalJSON.self, from: context) }
            let item = wire.params["itemId"].text
            tasks[i].requestLifecycle.observe(pending(wire, identity: .server(request.identity),
                call: item.isEmpty ? nil : CodexActivityPrivacy.hashIdentifier(item), mode: request.userInputMode))
        }
        let answered = projection.asyncQuestions.filter { $0.turnID == turn && $0.resolvedAnswer != nil }
        rememberAnsweredPresentations(answered.map {
            (CodexActivityPrivacy.hashIdentifier($0.questionItemID), CodexActivityPrivacy.hashIdentifier($0.question))
        }, task: tasks[i], at: observedAt)
        for question in projection.asyncQuestions where question.turnID == turn && question.resolvedAnswer == nil {
            guard var wire = try? IslandCodexApprovalRequest(desktopAsyncQuestion: question, conversationID: snapshot.conversationID) else { continue }
            wire = wire.attachingDesktopHandle(handle(.string(question.questionItemID), method: wire.method, turn: turn))
            let request = pending(wire, identity: .asynchronousQuestion(question.questionItemID),
                call: CodexActivityPrivacy.hashIdentifier(question.questionItemID), mode: .asynchronous)
            if !isRetiredAsync(request, task: tasks[i]) { tasks[i].requestLifecycle.observe(request) }
        }
        if projection.pendingRequestsAreAuthoritative {
            let settled = tasks[i].requestLifecycle.resolveDesktopRequests(owner: snapshot.ownerClientID, epoch: snapshot.connectionEpoch,
                pending: projection.authoritativePendingIdentities, asyncQuestions: projection.authoritativeAsyncQuestionIDs, at: observedAt)
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
        guard !disabledProviders.contains(provider(for: key)) else { return nil }
        guard presentationKind(for: key) != .memoryConsolidation, presentationKind(for: key) != .internalTask, presentationKind(for: key) != .subagent else { return nil }
        if let i = tasks.firstIndex(where: { $0.key == key }) { return i }
        guard admit else { return nil }
        // New conversations append to the list. Completed cards remain until
        // the user archives them; starting another task is not a dismissal.
        tasks.append(.init(id: nextID, key: key)); nextID += 1
        if !tasks.contains(where: { $0.id == selectedID }) { selectedID = tasks.last!.id }
        return tasks.count - 1
    }
    func receiveLegacy(_ event: CodexActivityEvent) {
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
        case .postCompact: if tasks[i].activityStatus == .compacting { tasks[i].activityStatus = .thinking }
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
        default: break
        }
        if !tasks[i].terminal, let progress = event.planProgress?.approximateFraction { tasks[i].progress = progress }
        let pending = pendingLocalContent.filter { $0.sessionHash == event.sessionHash && $0.turnHash == tasks[i].turnKey }
        pendingLocalContent.removeAll { $0.sessionHash == event.sessionHash }
        for content in pending { receiveLocalContent(content) }
        onChange?()
    }
    func withdrawHookExecution(session: String, turn: String) {
        let removed = Set(tasks.filter { $0.key == session && $0.turnKey == turn }.map(\.id))
        guard !removed.isEmpty else { return }
        tasks.removeAll { removed.contains($0.id) }
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
        if let rate = update.outputRate,
           rate.occurredAt > (tasks[i].outputRate?.occurredAt ?? .distantPast) {
            tasks[i].outputRate = rate
            tasks[i].averageOutputRate = update.averageOutputRate
        }
        tasks[i].tokens = max(tasks[i].tokens ?? 0, update.cumulativeTotalTokens); onChange?()
    }
    func receiveOutputRate(session: String, turn: String, latest: CodexOutputRateSample?, average: CodexOutputRateSample?) {
        guard let latest, let i = tasks.firstIndex(where: { $0.key == session && $0.turnKey == turn }),
              latest.occurredAt >= (tasks[i].outputRate?.occurredAt ?? .distantPast) else { return }
        guard tasks[i].outputRate != latest || tasks[i].averageOutputRate != average else { return }
        tasks[i].outputRate = latest; tasks[i].averageOutputRate = average; onChange?()
    }
    func receiveObservedPlan(_ plan: CodexActivityPlanProgress?, key: String, turn: String) {
        guard let i = tasks.firstIndex(where: { $0.key == key }), tasks[i].turnKey == turn,
              !tasks[i].terminal, tasks[i].progress != plan?.approximateFraction else { return }
        tasks[i].progress = plan?.approximateFraction
        onChange?()
    }

    func receiveAntigravityFocus(_ focuses: [AntigravityHistory.Focus], key: String, turn: String) {
        guard provider(for: key) == .antigravity, let i = tasks.firstIndex(where: { $0.key == key }),
              tasks[i].turnKey == turn, !tasks[i].terminal else { return }
        let previous = tasks[i].antigravityFocus
        for focus in focuses {
            if let latest = tasks[i].antigravityFocus,
               (focus.step, focus.call) < (latest.step, latest.call) || focus == latest { continue }
            tasks[i].antigravityFocus = focus
            upsert(.init(text: .init(focus.title), kind: .progress,
                         publicItem: .init(category: .message, sourceID: "antigravity-focus-\(focus.step)-\(focus.call)",
                                           turnID: turn, status: "completed", messagePhase: "commentary", isStepTitle: true)), at: i)
        }
        if previous != tasks[i].antigravityFocus { onPublicChange?() }
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
            let matched = tasks[i].requestLifecycle.receiveAcceptedAsyncReplies(proofs)
            let confirmed = p["verifiedReplay"] as? Bool == true ? proofs : matched
            if !confirmed.isEmpty {
                rememberAnsweredPresentations(confirmed, task: tasks[i], at: Date())
                onChange?()
            }
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
            if tasks[i].requestLifecycle.resolveCall(CodexActivityPrivacy.hashIdentifier(id), proofMode: mode, at: Date()) { onChange?() }
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
                    let output = p["text"] as? String ?? ""
                    tasks[i].entries[j].publicItem?.output = String(output.prefix(65536))
                    tasks[i].entries[j].publicItem?.sourceTruncated = output.count > 65536
                    tasks[i].entries[j].publicItem?.status = "completed"
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
                upsert(.init(text: .init(String(text.prefix(65536))), kind: channel == "final" ? .result : .progress,
                    publicItem: .init(category: message ? .message : .command,
                    sourceID: id, turnID: content.turnHash, status: message || presentationRecovery ? "completed" : "inProgress", sourceTruncated: text.count > 65536 || p["sourceTruncated"] as? Bool == true, messagePhase: channel)), at: i)
                if message { tasks[i].publicProgress = messageSummary(body); if tasks[i].status == .thinking { tasks[i].operation = tasks[i].publicProgress } }
                else if !message && !presentationRecovery && !tasks[i].terminal {
                    let args = body.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                    let detail = args?["cmd"] as? String ?? args?["code"] as? String ?? args?["command"] as? String ?? body
                    let label = name.split(separator: ".").last.map(String.init) ?? name
                    let description = detail.isEmpty ? label : label + " · " + String(detail.replacingOccurrences(of: "\n", with: " ").prefix(240))
                    tasks[i].activeItems[id] = description; tasks[i].activityStatus = .working; tasks[i].operation = description
                }
            }
        }
        trim(i); onPublicChange?()
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
        if let id = value.desktopThreadID, CodexActivityPrivacy.hashIdentifier(id.uuidString.lowercased()) == identity.sessionHash {
            tasks[i].desktopThreadID = id
        }
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
        clearItemContexts(for: tasks[i].key)
        if let old = tasks[i].turnKey { priorTurnKeys[tasks[i].key, default: []].insert(old) }
        tasks[i].turnKey = key; tasks[i].startedAt = date; tasks[i].endedAt = nil
        tasks[i].outputRate = nil
        tasks[i].averageOutputRate = nil
        // Devin reports usage after the prompt's saved position, so its next
        // turn starts unknown. Other providers may report session-wide totals.
        if provider(for: tasks[i].key).isDevin { tasks[i].tokens = nil }
        tasks[i].activityStatus = .thinking; tasks[i].requestLifecycle = RequestLifecycle(); tasks[i].progress = nil; tasks[i].operation = ""
        tasks[i].observerReminderDismissed = false
        tasks[i].observedPermissionNotices.removeAll()
        tasks[i].progressResolver.reset(); tasks[i].progressUpdatedAt = date; tasks[i].displayedProgress = 0.01
        tasks[i].activeItems.removeAll(); tasks[i].nativeContentAvailable = false; tasks[i].publicProgress = ""
        tasks[i].antigravityFocus = nil
        tasks[i].entries.removeAll(); tasks[i].removedEntryCount = 0; tasks[i].updatedAt = date
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
        if mode == .asynchronous, !tasks[i].requestLifecycle.acceptsLocalAsyncQuestion(pending, occurredAt: content.occurredAt) { return }
        if !isRetiredAsync(pending, task: tasks[i]) { tasks[i].requestLifecycle.observe(pending) }
        onChange?()
    }
    @discardableResult
    private func resolveRequest(_ i: Int, id: IslandApprovalJSON, epoch: UInt64) -> Bool {
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
    func receive(_ data: Data, at now: Date = Date()) {
        guard data.count <= 1_048_576, let m = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = m["method"] as? String, !method.contains("reasoning"),
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
            let status = thread["status"] as? [String: Any]
            let active = status?["type"] as? String == "active"
            guard let i = index(key, admit: active) else { return }
            // Retain only bounded display metadata after admission, never turns
            // or complete history carried by thread/snapshot.
            metadata[key] = thread.filter { ["name", "title", "model", "reasoningEffort", "effort"].contains($0.key) }
                .mapValues { String(($0 as? String ?? "").prefix(4_096)) }
            applyMetadata(metadata[key] ?? [:], at: i); tasks[i].threadID = tid
            if active { tasks[i].nativeState = true; applyFlags(status, at: i, epoch: scope, observedAt: now) }
            onChange?(); return
        }
        if method == "serverRequest/resolved", p["threadId"] == nil,
           let raw = p["requestId"], let id = try? IslandApprovalJSON(any: raw) {
            let matches = tasks.indices.filter { i in
                tasks[i].requests.contains { $0.rpcEpoch == scope && $0.value.protocolRequest?.rpcID == id }
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
            guard var wire = try? IslandCodexApprovalRequest(data: data) else { return }
            if wire.kind == .nativeOnly && !["mcpServer/elicitation/request"].contains(method) { return }
            if let itemID = p["itemId"] as? String, let entry = tasks[i].entries.last(where: { $0.publicItem?.sourceID == itemID }) {
                if let context = itemContexts[key + ":" + itemID] {
                    if context.value == .null { wire.contextUnavailable = true } else { wire.contextItem = context.value }
                } else if wire.kind == .fileChange || entry.publicItem?.category == .command { wire.contextUnavailable = true }
            }
            if wire.kind == .fileChange, wire.contextItem == nil { wire.contextUnavailable = true }
            if tasks[i].turnKey == nil { tasks[i].turnKey = turnKey }
            let requestKey = RequestLifecycle.rpcKey(wire.rpcID, epoch: scope)
            guard !tasks[i].resolvedRequestKeys.contains(requestKey) else { return }
            let itemID = wire.params["itemId"].text
            guard !tasks[i].terminal else { return }
            let question = !wire.questions.isEmpty ? wire.questions[0].title : wire.params["message"].text.isEmpty ? (wire.params["reason"].text.isEmpty ? "Codex 请求你的处理" : wire.params["reason"].text) : wire.params["message"].text
            let canRespond = !wire.observationOnly && respond != nil && responseCapability?(wire) == true && wire.kind != .nativeOnly && wire.kind != .mcpURL && (wire.kind != .mcpForm || wire.supportedForm) && (wire.kind != .questions || wire.supportedQuestions)
            tasks[i].requestLifecycle.observe(.init(key: requestKey, value: .init(question: .init(question),
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
        case "thread/status/changed": applyFlags(p["status"] as? [String: Any], at: i, epoch: scope, observedAt: now)
        case "thread/tokenUsage/updated":
            if let usage = CodexAppServerActivityNotificationDecoder.decodeTokenUsage(data: data, now: now) { receiveToken(usage) }
        case "turn/plan/updated":
            if !tasks[i].terminal, let event = CodexAppServerActivityNotificationDecoder.decode(data: data, now: now) {
                tasks[i].progress = event.planProgress?.approximateFraction
            }
        case "serverRequest/resolved":
            if let raw = p["requestId"], let id = try? IslandApprovalJSON(any: raw) {
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
            if type == "contextCompaction" { tasks[i].activityStatus = method == "item/started" ? .compacting : .thinking; break }
            let mode = CodexUserInputMode.forToolName(item["tool"] as? String ?? item["name"] as? String ?? item["toolName"] as? String)
            if method == "item/started" { tasks[i].requestLifecycle.observeMode(mode, callHash: CodexActivityPrivacy.hashIdentifier(itemID)) }
            if method == "item/started" && type != "agentMessage" {
                tasks[i].requestLifecycle.continueCall(CodexActivityPrivacy.hashIdentifier(itemID), at: now)
                let description = operationDescription(type, item: item)
                tasks[i].activeItems[itemID] = description
                tasks[i].activityStatus = .working
                tasks[i].operation = description
            }
            if method == "item/completed" {
                tasks[i].requestLifecycle.resolveCall(CodexActivityPrivacy.hashIdentifier(itemID), proofMode: mode, epoch: scope, at: now)
                tasks[i].activeItems.removeValue(forKey: itemID)
                if tasks[i].activeItems.isEmpty {
                    tasks[i].activityStatus = .thinking
                    tasks[i].operation = String((tasks[i].entries.last(where: { $0.publicItem?.category == .message })?.text.chinese ?? "").prefix(240))
                }
                else { tasks[i].activityStatus = .working; tasks[i].operation = tasks[i].activeItems.sorted { $0.key < $1.key }.last!.value }
            }
            appendItem(item, turnID: turnID ?? "", at: i)
            if tasks[i].entries.contains(where: { $0.publicItem?.sourceID == itemID }),
               ["commandExecution", "fileChange", "mcpToolCall", "dynamicToolCall"].contains(type) {
                // Output is trace content, not approval input. Bound retained
                // context separately; an omitted context never grants approval.
                let context = item.filter { ["type", "id", "command", "cwd", "changes", "arguments", "server", "tool"].contains($0.key) }
                let data = try? JSONSerialization.data(withJSONObject: context)
                let contextKey = key + ":" + itemID
                itemContexts.removeValue(forKey: contextKey)
                let value = data.map { $0.count <= 32_768 } == true ? (try? IslandApprovalJSON(any: context)) : nil
                let size = value != nil ? (data?.count ?? 0) : 0
                while itemContexts.count >= 200 || retainedItemContextBytes + size > 2_097_152 {
                    guard let oldest = itemContextOrder.first else { break }
                    itemContextOrder.removeFirst(); itemContexts.removeValue(forKey: oldest)
                }
                itemContextOrder.removeAll { $0 == contextKey }; itemContextOrder.append(contextKey)
                itemContexts[contextKey] = .init(value: value ?? .null, byteCount: size)
            }
        case "item/agentMessage/delta", "item/commandExecution/outputDelta":
            guard !tasks[i].terminal, let itemID = p["itemId"] as? String, let delta = p["delta"] as? String else { break }
            appendDelta(delta, itemID: itemID, message: method.contains("agentMessage"), at: i)
            onPublicChange?(); return
        case "thread/archived", "thread/closed":
            tasks.removeAll { $0.key == key }
            metadata.removeValue(forKey: key); priorTurnKeys.removeValue(forKey: key); desktopScopes.removeValue(forKey: key)
            pendingLocalContent.removeAll { $0.sessionHash == key }; clearItemContexts(for: key)
            onChange?(); return
        default: return
        }
        tasks[i].updatedAt = now; onChange?()
    }
    private struct ItemContext { let value: IslandApprovalJSON; let byteCount: Int }
    private var itemContexts: [String: ItemContext] = [:]
    private var itemContextOrder: [String] = []
    var retainedItemContextBytes: Int { itemContexts.values.reduce(0) { $0 + $1.byteCount } }
    var retainedItemContextCount: Int { itemContexts.count }
    private func clearItemContexts(for key: String) {
        itemContexts = itemContexts.filter { !$0.key.hasPrefix(key + ":") }
        itemContextOrder.removeAll { itemContexts[$0] == nil }
    }
    private func applyMetadata(_ data: [String: Any], at i: Int) {
        if let name = nonempty(data["name"]) { applyTitle(name, source: .explicitName, at: i) }
        else { applyTitle(nonempty(data["title"]), source: .threadTitle, at: i) }
        if let model = nonempty(data["model"]), tasks[i].modelTurnKey == nil || tasks[i].modelTurnKey != tasks[i].turnKey { tasks[i].model = model }
        if let effort = nonempty(data["reasoningEffort"]) ?? nonempty(data["effort"]),
           tasks[i].effortTurnKey == nil || tasks[i].effortTurnKey != tasks[i].turnKey { tasks[i].effort = effort }
    }
    private func applyFlags(_ status: [String: Any]?, at i: Int, epoch: UInt64, observedAt: Date) {
        guard !tasks[i].terminal, let status, status["type"] as? String == "active" else { return }
        let flags = status["activeFlags"] as? [String] ?? []
        let reason: CodexActivityWaitReason? = flags.contains("waitingOnUserInput") ? .userInput
            : flags.contains("waitingOnApproval") ? .approval : nil
        tasks[i].requestLifecycle.setSourceWait(reason, waiting: reason != nil, epoch: epoch, at: observedAt)
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
    private func appendItem(_ item: [String: Any], turnID: String, at i: Int) {
        guard let type = item["type"] as? String, let itemID = item["id"] as? String else { return }
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
        default: return
        }
        guard !text.isEmpty else { return }
        beginNativeContent(i)
        if text.utf8.count > 131072 || (output?.utf8.count ?? 0) > 131072 { truncated = true }
        let status = item["status"] as? String
        let exit = item["exitCode"] as? Int
        let failed = status == "failed" || exit.map { $0 != 0 } == true
        let phase = category == .message ? (item["phase"] as? String ?? item["channel"] as? String) : nil
        upsert(.init(text: .init(String(text.prefix(65536))), kind: failed ? .failure : (["final", "final_answer"].contains(phase ?? "") ? .result : .progress),
            publicItem: .init(category: category, sourceID: itemID, turnID: turnID, status: status,
                output: output.map { String($0.prefix(65536)) }, sourceTruncated: truncated, exitCode: exit, messagePhase: phase)), at: i)
        if category == .message {
            tasks[i].publicProgress = messageSummary(text)
            if tasks[i].status == .thinking { tasks[i].operation = tasks[i].publicProgress }
        }
    }
    private func beginNativeContent(_ i: Int) {
        if !tasks[i].nativeContentAvailable { clearItemContexts(for: tasks[i].key); tasks[i].entries.removeAll(); tasks[i].nativeContentAvailable = true }
    }
    private func appendDelta(_ delta: String, itemID: String, message: Bool, at i: Int) {
        beginNativeContent(i)
        if let j = tasks[i].entries.firstIndex(where: { $0.publicItem?.sourceID == itemID }) {
            if message { tasks[i].entries[j].text.chinese += delta; tasks[i].entries[j].text.english = tasks[i].entries[j].text.chinese }
            else { let output = (tasks[i].entries[j].publicItem?.output ?? "") + delta; tasks[i].entries[j].publicItem?.output = output }
            let body = tasks[i].entries[j].text.chinese
            let output = tasks[i].entries[j].publicItem?.output ?? ""
            // UTF-8 size is cheap for native Swift strings and bounds character
            // count. Avoid walking every accumulated grapheme for short deltas.
            if (body.utf8.count > 65536 && body.count > 65536) || (output.utf8.count > 65536 && output.count > 65536) {
                tasks[i].entries[j].text = .init(String(tasks[i].entries[j].text.chinese.prefix(65536)))
                let output = tasks[i].entries[j].publicItem?.output.map { String($0.prefix(65536)) }
                tasks[i].entries[j].publicItem?.output = output
                tasks[i].entries[j].publicItem?.sourceTruncated = true
            }
        } else if message {
            upsert(.init(text: .init(delta), publicItem: .init(category: .message, sourceID: itemID, turnID: tasks[i].turnKey ?? "")), at: i)
        }
        if message, let text = tasks[i].entries.last(where: { $0.publicItem?.sourceID == itemID })?.text.chinese {
            tasks[i].publicProgress = messageSummary(text)
            if tasks[i].status == .thinking { tasks[i].operation = tasks[i].publicProgress }
        }
        trim(i)
    }
    private func upsert(_ entry: IslandTraceEntry, at i: Int) {
        var entry = entry
        if let source = entry.publicItem?.sourceID, let j = tasks[i].entries.firstIndex(where: { $0.publicItem?.sourceID == source }) {
            entry.id = tasks[i].entries[j].id; tasks[i].entries[j] = entry
        } else { tasks[i].entries.append(entry) }
        trim(i)
    }
    private func trim(_ i: Int) {
        func discardOldest(_ index: Int) {
            let entry = tasks[index].entries.removeFirst(); tasks[index].removedEntryCount += 1
            if let id = entry.publicItem?.sourceID { itemContexts.removeValue(forKey: tasks[index].key + ":" + id); itemContextOrder.removeAll { itemContexts[$0] == nil } }
        }
        while tasks[i].entries.count > 200 { discardOldest(i) }
        var bytes = tasks.reduce(0) { $0 + $1.entries.reduce(0) { $0 + $1.text.chinese.utf8.count + ($1.publicItem?.output?.utf8.count ?? 0) } }
        while bytes > 2_097_152,
              let old = tasks.indices.filter({ !tasks[$0].entries.isEmpty }).min(by: { tasks[$0].updatedAt < tasks[$1].updatedAt }) {
            let entry = tasks[old].entries[0]
            bytes -= entry.text.chinese.utf8.count + (entry.publicItem?.output?.utf8.count ?? 0)
            discardOldest(old)
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
    private func answeredPresentationKey(_ proof: (String, String), task: TaskRecord) -> String {
        CodexActivityPrivacy.hashIdentifier([task.key, task.turnKey ?? "", "answered", proof.0, proof.1].joined(separator: ":"))
    }
    private func rememberAnsweredPresentations(_ proofs: [(String, String)], task: TaskRecord, at now: Date) {
        recordRetiredPresentations(proofs.map { answeredPresentationKey($0, task: task) }, at: now)
    }
    private func isRetiredAsync(_ pending: Pending, task: TaskRecord) -> Bool {
        if let key = asyncPresentationKey(pending, task: task), retiredAsyncPresentations[key] != nil { return true }
        let proofs = RequestLifecycle.asyncQuestionProofs(pending)
        return !proofs.isEmpty && proofs.allSatisfy { retiredAsyncPresentations[answeredPresentationKey($0, task: task)] != nil }
    }
    private func retireAsyncPresentation(taskIndex i: Int, requestID: UUID, at now: Date) -> Bool {
        guard let pending = tasks[i].requestLifecycle.requests.first(where: { $0.value.id == requestID }),
              let key = asyncPresentationKey(pending, task: tasks[i]) else { return false }
        if case .submitting = pending.value.phase { return false }
        recordRetiredPresentations([key], at: now)
        asyncPresentations.removeValue(forKey: key)
        tasks[i].requestLifecycle.requests.removeAll { $0.value.id == requestID }
        tasks[i].requestIndex = min(tasks[i].requestIndex, max(0, tasks[i].requests.count - 1))
        // Do not emit an accepted reply, serverRequest/resolved, or wait settlement.
        return true
    }
    private func recordRetiredPresentations(_ keys: [String], at now: Date) {
        let newKeys = keys.filter { retiredAsyncPresentations[$0] == nil }
        guard !newKeys.isEmpty else { return }
        for key in newKeys { retiredAsyncPresentations[key] = now.timeIntervalSince1970 }
        if retiredAsyncPresentations.count > 4096 {
            for old in retiredAsyncPresentations.sorted(by: { $0.value < $1.value })
                .prefix(retiredAsyncPresentations.count - 4096) { retiredAsyncPresentations.removeValue(forKey: old.key) }
        }
        archiveDefaults?.set(retiredAsyncPresentations, forKey: Self.retiredAsyncKey)
    }
    func claimConfirmation(taskID: Int, requestID: UUID) {
        guard let task = tasks.first(where: { $0.id == taskID }),
              let pending = task.requestLifecycle.requests.first(where: { $0.value.id == requestID }), pending.value.canRespond,
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
                if isRetiredAsync(pending, task: tasks[i]) {
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
                    if !pending.value.canRespond { presentation.claimed = false }
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
              !wire.observationOnly, capability(for: wire) else { return }
        let turn = tasks[i].turnKey
        let epoch = connectionEpoch
        let handle = wire.desktopHandle
        let sharedHandle = wire.sharedQuestionHandle
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
        let handler = if let provider = wire.devinProvider {
            devinResponders[provider]
        } else {
            wire.isOpenCode ? openCodeRespond : wire.isAntigravity ? antigravityRespond : wire.isDSH ? dshRespond : wire.isClaudeCode ? claudeRespond : self.respond
        }
        guard case .reply(let result) = decision, wire.permits(result), let respond = handler else { return }
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
                } else if let card = wire.nativeQuestionCard, sharedHandle == nil {
                    guard tasks[i].requestLifecycle.requests[j].value.protocolRequest?.nativeQuestionCard == card else { return nil }
                } else if !wire.isLocalHook, epoch != connectionEpoch { return nil }
                if let sharedHandle, tasks[i].requestLifecycle.requests[j].value.protocolRequest?.sharedQuestionHandle != sharedHandle { return nil }
                return (i, j)
            }
            guard let (i, j) = currentRequest() else { return }
            guard capability(for: wire) else {
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
    private func capability(for wire: IslandCodexApprovalRequest) -> Bool {
        if let provider = wire.devinProvider { return devinCapabilities[provider]?(wire) == true }
        return (wire.isOpenCode ? openCodeResponseCapability : wire.isAntigravity ? antigravityResponseCapability : wire.isDSH ? dshResponseCapability : wire.isClaudeCode ? claudeResponseCapability : responseCapability)?(wire) == true
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
    func display(english: Bool, remaining: Int?, enabled: Bool, privacy: Bool, at now: Date = Date(), language selectedLanguage: AppPreferences.Language? = nil, cardOptions: IslandTaskCardOptions = .init()) -> CodexMultitaskDisplay {
        let language = selectedLanguage ?? (english ? .english : .simplifiedChinese)
        let appCopy = AppCopy(language: language)
        advanceConfirmationPresentation(at: now, visible: enabled && !privacy)
        advanceProgress(at: now)
        var details: [Int: IslandTaskDetailData] = [:]; var metas: [Int: IslandSessionMetadata] = [:]
        let copy = CodexActivityCopy(language: language)
        let visibleTasks = tasks.filter { !isArchived($0) }
        let items = visibleTasks.map { task -> CodexMultitaskRenderTask in
            let settlement = task.terminal ? nil : task.requestLifecycle.desktopSettlementDisplay(at: now)
            let synchronizing = settlement == .synchronizing
            let presentationStatus = settlement == nil ? task.status : task.activityStatus
            let visual: CodexActivityVisualState = synchronizing ? .working : presentationStatus.visualState
            let duration = task.startedAt.map { max(0, Int((task.endedAt ?? now).timeIntervalSince($0))) }
            let children = privacy ? [] : childPresentations(parent: task.key, english: english, language: language, at: now)
            let runningChildren = children.filter { [.thinking, .working, .compactingContext].contains($0.visualState) }
            metas[task.id] = cardOptions.applying(to: .init(modelName: task.model.isEmpty ? (appCopy.text("模型未知", "Unknown model")) : task.model, reasoningEffort: task.effort, elapsedSeconds: duration, subagents: children))
            let provider = self.provider(for: task.key)
            let pending = task.requests.isEmpty ? nil : task.requests[min(task.requestIndex, task.requests.count - 1)]
            var request = settlement == nil ? pending?.value : nil
            if let pending, request != nil {
                request?.canDismissLocally = asyncPresentationKey(pending, task: task) != nil
                    || (pending.isGeneric && task.requestLifecycle.canHideObserverReminder)
                if provider == .codex, pending.isGeneric, !desktopConnected {
                    request?.impact = .init("QuotaView 尚未连接到 Codex 桌面端的审批通道。请在原对话中处理。",
                        "QuotaView is disconnected from Codex desktop approvals. Respond in the original conversation.")
                }
            }
            request?.queueIndex = task.requestIndex + 1; request?.queueCount = task.requests.count
            request?.provider = provider
            // DSH task observation remains read-only, but an admitted live
            // approval carries its own revocable response capability.
            if provider.isObserverOnly && request?.protocolRequest?.devinProvider != provider && !(provider == .openCode && request?.protocolRequest?.isOpenCode == true) && !(provider == .dsh && request?.protocolRequest?.isDSH == true)
                && !(provider == .antigravity && request?.protocolRequest?.isAntigravity == true) {
                request?.canRespond = false
                request?.impact = .init("请在 \(provider.displayName) 中确认。", "Confirm this request in \(provider.displayName).")
            }
            details[task.id] = .init(entries: privacy ? [] : task.entries, confirmation: privacy ? nil : request, status: presentationStatus, removedEntryCount: task.removedEntryCount, provider: provider,
                desktopThreadID: enabled && !privacy ? task.desktopThreadID : nil,
                nativeConversation: enabled && !privacy ? task.nativeConversation : nil)
            let title = privacy ? provider.displayName + (appCopy.text(" 任务", " task")) : (task.title.isEmpty ? (appCopy.text("未命名任务", "Untitled task")) : task.title)
            let status: String
            if synchronizing { status = appCopy.text("同步中", "Syncing") }
            else if task.status == .cancelled { status = appCopy.text("已中断", "Interrupted") }
            else if task.status == .queued { status = appCopy.text("排队中", "Queued") }
            else if presentationStatus == .waiting && task.sourceWaitReason == .userInput { status = appCopy.text("等待回答", "Awaiting answer") }
            else { status = copy.statusTitle(for: visual) }
            let operation: String
            if [.thinking, .working].contains(task.status), let focus = task.antigravityFocus {
                operation = focus.title
            } else if task.operation == "exec" || task.operation.hasPrefix("exec · ") {
                operation = (appCopy.text("执行中", "Executing")) + task.operation.dropFirst(4)
            } else if !task.operation.isEmpty { operation = task.operation }
            else if !runningChildren.isEmpty && !task.terminal {
                operation = summary(runningChildren.map(\.title).joined(separator: appCopy.text("、", ", "))) + (appCopy.text(" 正在工作", " are working"))
            } else { operation = task.publicProgress }
            let render = CodexActivityRenderState(taskIdentity: .init(sessionHash: task.key, turnHash: task.turnKey),
                visualState: visual, approximateProgressFraction: task.displayedProgress,
                windowTitle: title, statusTitle: status, operation: privacy || task.status == .compacting ? "" : (synchronizing
                    ? (appCopy.text("请求已处理", "Request handled")) : presentationStatus == .waiting
                    ? status + " · " + (request?.question.value(language) ?? "") : operation),
                tokenUsageTitle: cardOptions.tokens ? task.tokens.map { CodexActivityTokenUsageFormatter.string(for: $0) + " tok" } : nil,
                accessibilityLabel: "\(title), \(status)")
            return .init(id: task.id, renderState: render, playbackEnabled: !task.terminal || task.status == .completed, hasPendingRequest: settlement == nil && !task.requests.isEmpty, provider: provider,
                         outputRate: cardOptions.outputRate ? (task.status == .completed ? task.averageOutputRate :
                            (!task.terminal ? task.outputRate : nil)) : nil, cardOptions: cardOptions)
        }
        let connectionCopy = AppCopy(language: language)
        return .init(state: .init(tasks: items, selectedID: selectedID, allCompleted: !visibleTasks.isEmpty && visibleTasks.allSatisfy(\.terminal), compact: true, receiptStartedAt: nil),
            english: english, effect: .dropField, visible: enabled, playbackEnabled: true, totalTokens: nil, remainingPercent: remaining,
            sessionMetadata: metas, taskDetails: details, connectionTitle: connection == .connected || desktopConnected
                ? (visibleTasks.isEmpty ? connectionCopy.text("就绪", "Ready") : connectionCopy.text("已连接", "Connected"))
                : (visibleTasks.isEmpty ? connectionCopy.text("等待 Codex 任务", "Waiting for Codex") : connectionCopy.text("本地活动数据", "Local activity")),
            privacyMode: privacy, activeRequestIDs: privacy ? [] : Set(visibleTasks.flatMap {
                $0.requestLifecycle.desktopSettlementDisplay(at: now) != nil ? [] : $0.requests.map { $0.value.id }
            }), language: language)
    }
}

extension IslandCodexApprovalRequest: RequestLifecycleWire {
    var isQuestion: Bool { kind == .questions }
    var hasLocalObservation: Bool { localObservation != nil }
    var localAsyncCallID: String? {
        guard let localObservation, localObservation.mode == .asynchronous else { return nil }
        return localObservation.callID
    }
    var survivesRPCDisconnect: Bool { isLocalHook || nativeQuestionCard != nil }
    var questionTitles: [String] { questions.map(\.title) }
}

extension IslandConfirmation: RequestLifecyclePayload {
    static func observerWait(_ wait: RequestObserverWait) -> Self {
        let impact: IslandDetailText
        switch wait {
        case .source:
            impact = .init("正在同步请求详情。如有 macOS 权限弹窗，请在系统弹窗中处理。",
                "Syncing request details. If macOS shows a permission dialog, respond in that system dialog.")
        case .call:
            impact = .init("请在 Codex 查看并处理。", "Review and handle this request in Codex.")
        }
        return .init(question: .init("请求详情暂不可用", "Request details unavailable"), impact: impact)
    }

    mutating func inheritSubmission(from prior: Self) {
        id = prior.id
        phase = prior.phase
    }

    mutating func invalidateResponse() {
        canRespond = false
        if !phase.canSubmit { phase = .resultUnknown }
    }
}
