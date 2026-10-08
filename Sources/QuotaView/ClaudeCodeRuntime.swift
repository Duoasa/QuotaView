import AppKit
import Combine
import Foundation
import QuotaViewCore

/// Claude Code usage for the island usage page, from local sources only:
/// status-line windows, Claude Code's cached usage, its profile and transcripts.
struct IslandClaudeUsage: Equatable {
    enum QuotaState: Equatable {
        /// No local source can supply windows until the status line is enabled.
        case off
        /// A source is enabled but has not reported current windows yet.
        case waiting
        case available
    }
    var presentation: CurrentCodexPresentation
    var fiveHour: CodexQuotaWindowPresentation?
    var sevenDay: CodexQuotaWindowPresentation?
    var quotaState: QuotaState
    var planName: String?
    var extraUsageEnabled: Bool?
    var extraUsagePercent: Int?
}

@MainActor
final class ClaudeCodeRuntime: ObservableObject {
    enum ConnectionStatus: Equatable {
        case disabled, configuring, awaitingEvent, connected
        case failed(String)
    }

    @Published private(set) var status: ConnectionStatus = .disabled
    @Published private(set) var installerState = ClaudeCodeInstaller.State()
    @Published private(set) var rateLimits: ClaudeCodeRateLimits?
    @Published private(set) var usage: ClaudeCodeUsageSummary?
    @Published private(set) var profile: ClaudeCodeAccountProfile?
    @Published private(set) var lastEventAt: Date?
    var configurationDirectory: URL { installer.configurationDirectory }

    private struct Session {
        let id: String
        let key: String
        var cwd: String?
        var transcriptPath: String?
        var tail: ClaudeCodeTranscriptTail?
        var turnID: String?
        var turnKey: String?
        var turnActive = false
        var backfilling = false
        var usageKeys: Set<String> = []
        var turnTokens: Int64 = 0
        var lastAssistant: (id: String, text: String)?
        var model: String?
        var effort: String?
        var hasTitle = false
        /// A title found before the island admitted this session's card.
        var pendingTitle: (text: String, explicit: Bool)?
        var agentTurns: [String: String] = [:]
        var updatedAt = Date()
    }

    private struct Approval {
        let eventID: String
        let sessionKey: String
        let toolUseID: String
        let rpcID: IslandApprovalJSON
        var awaitsDecision: Bool
        let toolInput: [String: Any]
        let suggestions: [Any]
    }

    private let preferences: AppPreferences
    private let island: IslandSession
    private let installer: ClaudeCodeInstaller
    private let bridge: ClaudeCodeBridge
    private let scanner: ClaudeCodeUsageScanner
    private var sessions: [String: Session] = [:]
    private var approvals: [String: Approval] = [:]
    private var tailTimer: Timer?
    private var usageTimer: Timer?
    private var usageTask: Task<Void, Never>?
    private var configurationTask: Task<Void, Never>?
    private var configurationRevision = UUID()
    private var preferenceCancellable: AnyCancellable?
    private var appliedConfiguration: (enabled: Bool, configuration: ClaudeCodeInstaller.Configuration)?
    private var bridgeRunning = false
    private var isRunning = false
    private var connectedThisRun = false

    init(preferences: AppPreferences, island: IslandSession,
         defaults: UserDefaults = .standard,
         installer: ClaudeCodeInstaller? = nil) {
        self.preferences = preferences
        self.island = island
        let tokenKey = "claudeCode.bridge.authenticationToken"
        let token: String
        if let existing = defaults.string(forKey: tokenKey), !existing.isEmpty { token = existing }
        else { token = UUID().uuidString.lowercased(); defaults.set(token, forKey: tokenKey) }
        let installer = installer ?? ClaudeCodeInstaller(socketURL: Self.defaultSocketURL(), authenticationToken: token)
        self.installer = installer
        bridge = ClaudeCodeBridge(socketURL: installer.socketURL, authenticationToken: installer.authenticationToken)
        scanner = ClaudeCodeUsageScanner(projectsURL: installer.projectsURL)
        island.model.claudeResponseCapability = { [weak self] wire in
            guard let self, bridgeRunning, preferences.claudeCodeEnabled,
                  preferences.claudeCodeInteractiveApprovals,
                  let id = ClaudeCodeApproval.eventID(of: wire) else { return false }
            return approvals[id]?.awaitsDecision == true
        }
        island.model.claudeRespond = { [weak self] wire, result in
            guard let self else { throw CancellationError() }
            try self.respond(wire, result: result)
        }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        preferenceCancellable = preferences.objectWillChange.receive(on: RunLoop.main).sink { [weak self] _ in
            DispatchQueue.main.async { self?.reconcile() }
        }
        reconcile()
    }

    func stop() {
        isRunning = false
        preferenceCancellable = nil
        configurationRevision = UUID()
        appliedConfiguration = nil
        configurationTask?.cancel()
        stopBridge()
        status = .disabled
    }

    // MARK: Configuration

    private var desiredConfiguration: ClaudeCodeInstaller.Configuration {
        .init(interactiveApprovals: preferences.claudeCodeInteractiveApprovals, statusLine: preferences.claudeCodeStatusLineEnabled)
    }

    private func reconcile(force: Bool = false) {
        guard isRunning else { return }
        let enabled = preferences.claudeCodeEnabled
        let configuration = desiredConfiguration
        if !configuration.interactiveApprovals { returnApprovalsToTerminal() }
        if !force, let applied = appliedConfiguration, applied.enabled == enabled, applied.configuration == configuration { return }
        let wasEnabled = appliedConfiguration?.enabled ?? false
        appliedConfiguration = (enabled, configuration)
        let revision = UUID()
        configurationRevision = revision
        let installer = installer
        if enabled {
            startBridge()
            guard bridgeRunning else { appliedConfiguration = nil; return }
        } else {
            stopBridge()
        }
        status = .configuring
        let previous = configurationTask
        configurationTask = Task { [weak self] in
            await previous?.value
            // Finish an in-flight file transaction before the next one, but do
            // not start queued work after stop or publish an obsolete result.
            guard let self, !Task.isCancelled, isRunning, configurationRevision == revision else { return }
            let result: Result<ClaudeCodeInstaller.State, Error> = await Task.detached(priority: .utility) {
                do {
                    if enabled { try installer.install(configuration) }
                    else {
                        let state = installer.state()
                        if wasEnabled || force || state.hasOwnedHooks || state.statusLineInstalled {
                            try installer.uninstall()
                        }
                    }
                    return .success(installer.state())
                } catch { return .failure(error) }
            }.value
            guard !Task.isCancelled, isRunning, configurationRevision == revision else { return }
            switch result {
            case .success(let state):
                installerState = state
                if enabled {
                    status = connectedThisRun ? .connected : (state.hooksInstalled ? .awaitingEvent : .failed(AppCopy(language: preferences.resolvedLanguage).text(
                        "Claude Code Hook 未完整写入，请重试。", "Claude Code hooks were not fully written; try again.")))
                } else { status = .disabled }
            case .failure(let error):
                installerState = installer.state()
                status = .failed(error.localizedDescription)
            }
            if enabled { refreshUsage(); loadRateLimitSnapshot() }
        }
        if !enabled { installerState = installer.state() }
    }

    func retry() { reconcile(force: true) }

    func revealSettingsFile() {
        NSWorkspace.shared.activateFileViewerSelecting([installer.settingsURL])
    }

    private func startBridge() {
        guard !bridgeRunning else { return }
        do {
            // The main queue preserves Hook order; unstructured Tasks need not.
            try bridge.start(onMessage: { [weak self] message in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.receive(message) } }
            }, onDisconnect: { [weak self] eventID in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.helperDisconnected(eventID) } }
            })
            bridgeRunning = true
            usageTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshUsage() }
            }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func stopBridge() {
        bridge.stop()
        bridgeRunning = false
        usageTask?.cancel(); usageTask = nil
        tailTimer?.invalidate(); tailTimer = nil
        usageTimer?.invalidate(); usageTimer = nil
        for approval in approvals.values {
            island.model.resolveClaudeRequest(sessionKey: approval.sessionKey, rpcID: approval.rpcID)
        }
        approvals.removeAll()
        sessions.removeAll()
        connectedThisRun = false
        rateLimits = nil; usage = nil; profile = nil
        island.claudeUsage = nil
    }

    // MARK: Ingress

    private func receive(_ message: ClaudeCodeBridgeMessage) {
        guard isRunning, bridgeRunning, preferences.claudeCodeEnabled,
              let payload = (try? JSONSerialization.jsonObject(with: message.payload)) as? [String: Any] else {
            if message.awaitsDecision { bridge.resolve(eventID: message.eventID, decision: nil) }
            return
        }
        lastEventAt = Date()
        if !connectedThisRun { connectedThisRun = true; status = .connected }
        if message.kind == "statusLine" {
            if let limits = ClaudeCodeRateLimits.decode(snapshot: message.payload) { rateLimits = limits; publishUsage() }
            return
        }
        guard let event = payload["hook_event_name"] as? String,
              let sessionID = payload["session_id"] as? String, !sessionID.isEmpty, sessionID.utf8.count <= 256 else {
            if message.awaitsDecision { bridge.resolve(eventID: message.eventID, decision: nil) }
            return
        }
        var session = sessions[sessionID] ?? Session(id: sessionID, key: Self.sessionKey(sessionID))
        session.updatedAt = Date()
        if let cwd = payload["cwd"] as? String, !cwd.isEmpty { session.cwd = cwd }
        if let effort = payload["effort"] as? String, !effort.isEmpty { session.effort = effort }
        if let model = payload["model"] as? String, !model.isEmpty, session.model == nil { session.model = model }
        if let path = payload["transcript_path"] as? String, path.hasPrefix("/"), session.transcriptPath != path {
            session.transcriptPath = path
            session.tail = nil
        }
        island.model.setProvider(.claudeCode, for: session.key)
        let agentID = payload["agent_id"] as? String
        sessions[sessionID] = session
        if let agentID, !agentID.isEmpty, event != "PermissionRequest" {
            receiveAgentEvent(event, agentID: agentID, payload: payload, sessionID: sessionID)
            return
        }
        drainTranscript(sessionID)
        switch event {
        case "UserPromptSubmit":
            beginTurn(sessionID, byPrompt: true)
            emit(.userPromptSubmit, sessionID, payload)
            publishMetadata(sessionID)
        case "PreToolUse":
            ensureTurn(sessionID)
            emit(.preToolUse, sessionID, payload)
        case "PostToolUse", "PostToolUseFailure":
            emit(.postToolUse, sessionID, payload)
            if let id = payload["tool_use_id"] as? String { retireApprovals(sessionID: sessionID, toolUseID: id) }
        case "PermissionRequest":
            ensureTurn(sessionID)
            admitApproval(message, payload: payload, sessionID: sessionID)
            return
        case "PreCompact":
            ensureTurn(sessionID)
            emit(.preCompact, sessionID, payload)
        case "PostCompact":
            emit(.postCompact, sessionID, payload)
        case "Stop":
            finishTurn(sessionID, payload: payload, status: .completed)
        case "StopFailure":
            finishTurn(sessionID, payload: payload, status: .failed)
        case "SubagentStart", "SubagentStop":
            // Subagent hooks without agent_id carry no child identity.
            break
        case "SessionEnd":
            if sessions[sessionID]?.turnKey != nil { emit(.sessionEnd, sessionID, payload) }
            retireApprovals(sessionID: sessionID, toolUseID: nil)
            sessions.removeValue(forKey: sessionID)
        default:
            break // SessionStart and Notification only refresh session metadata.
        }
        if message.awaitsDecision { bridge.resolve(eventID: message.eventID, decision: nil) }
        scheduleTailTimer()
    }

    private func receiveAgentEvent(_ event: String, agentID: String, payload: [String: Any], sessionID: String) {
        guard var session = sessions[sessionID],
              let identity = CodexActivitySubagentIdentity(threadID: "claude-code-agent:" + agentID,
                  parentThreadID: "claude-code:" + sessionID, nickname: payload["agent_type"] as? String) else { return }
        island.model.setProvider(.claudeCode, for: identity.sessionHash)
        island.model.receiveSubagentIdentity(identity)
        let turn = session.agentTurns[agentID] ?? CodexActivityPrivacy.hashIdentifier("claude-agent-turn:" + agentID)
        session.agentTurns[agentID] = turn
        sessions[sessionID] = session
        let hookEvent: CodexActivityHookEvent?
        var completion: CodexActivityTurnCompletionStatus?
        switch event {
        case "SubagentStart": hookEvent = .userPromptSubmit
        case "PreToolUse": hookEvent = .preToolUse
        case "PostToolUse", "PostToolUseFailure": hookEvent = .postToolUse
        case "PreCompact": hookEvent = .preCompact
        case "PostCompact": hookEvent = .postCompact
        case "SubagentStop", "Stop": hookEvent = .stop; completion = .completed
        case "StopFailure": hookEvent = .stop; completion = .failed
        default: hookEvent = nil
        }
        guard let hookEvent else { return }
        let tool = payload["tool_name"] as? String
        island.model.receiveSubagentActivity(CodexActivityEvent(event: hookEvent, sessionHash: identity.sessionHash,
            turnHash: turn, toolCategory: Self.category(tool), source: .hook, turnCompletionStatus: completion, toolName: tool))
        if event == "PreToolUse", let tool {
            let input = (payload["tool_input"] as? [String: Any]).flatMap(Self.json) ?? ""
            sendContent(["type": "tool", "id": payload["tool_use_id"] as? String ?? UUID().uuidString, "name": tool, "text": Self.toolText(input)],
                        session: identity.sessionHash, turn: turn)
        }
        if hookEvent == .stop { sessions[sessionID]?.agentTurns.removeValue(forKey: agentID) }
    }

    // MARK: Turns

    private func ensureTurn(_ sessionID: String) {
        if sessions[sessionID]?.turnActive != true { beginTurn(sessionID, byPrompt: false) }
    }

    private func beginTurn(_ sessionID: String, byPrompt: Bool) {
        guard var session = sessions[sessionID] else { return }
        let turnID = UUID().uuidString.lowercased()
        session.turnID = turnID
        session.turnKey = CodexActivityPrivacy.hashIdentifier("claude-turn:" + sessionID + ":" + turnID)
        session.turnActive = true
        session.usageKeys.removeAll(); session.turnTokens = 0; session.lastAssistant = nil
        if let path = session.transcriptPath, session.tail == nil {
            let size = ClaudeCodeTranscriptTail.fileSize(path) ?? 0
            // A mid-turn admission backfills from the latest real prompt.
            session.backfilling = !byPrompt
            session.tail = .init(path: path, offset: byPrompt ? size : (size > 1_048_576 ? size - 1_048_576 : 0))
        } else { session.backfilling = false }
        sessions[sessionID] = session
        if let path = session.transcriptPath, !session.hasTitle { discoverTitle(path, sessionID: sessionID) }
        if !byPrompt { emit(.userPromptSubmit, sessionID, [:]); publishMetadata(sessionID) }
    }

    private func finishTurn(_ sessionID: String, payload: [String: Any], status: CodexActivityTurnCompletionStatus) {
        guard sessions[sessionID]?.turnActive == true else { return }
        drainTranscript(sessionID)
        guard var session = sessions[sessionID], session.turnActive else { return }
        if status == .completed, let last = session.lastAssistant {
            sendContent(["type": "message", "id": last.id, "text": last.text, "channel": "final"], sessionID: sessionID)
        } else if status == .failed, let error = payload["error"] as? String ?? payload["message"] as? String, !error.isEmpty {
            sendContent(["type": "message", "id": "stop-failure:" + (session.turnID ?? ""), "text": error, "channel": "final"],
                        sessionID: sessionID)
        }
        emit(.stop, sessionID, payload, completion: status)
        session.turnActive = false
        sessions[sessionID] = session
        retireApprovals(sessionID: sessionID, toolUseID: nil)
        scheduleUsageRefresh()
    }

    private func emit(_ event: CodexActivityHookEvent, _ sessionID: String, _ payload: [String: Any],
                      completion: CodexActivityTurnCompletionStatus? = nil) {
        guard let session = sessions[sessionID] else { return }
        let tool = payload["tool_name"] as? String
        let call = (payload["tool_use_id"] as? String).map { CodexActivityPrivacy.hashIdentifier("claude-tool:" + $0) }
        island.model.receiveLegacy(CodexActivityEvent(event: event, sessionHash: session.key, turnHash: session.turnKey,
            workspaceName: CodexActivityPrivacy.workspaceName(from: session.cwd), toolCategory: Self.category(tool),
            source: .hook, turnCompletionStatus: completion, toolCallHash: call, toolName: tool))
        if let pending = session.pendingTitle { setTitle(pending.text, explicit: pending.explicit, sessionID: sessionID) }
    }

    private func setTitle(_ title: String, explicit: Bool, sessionID: String) {
        guard var session = sessions[sessionID] else { return }
        session.hasTitle = true
        if island.model.tasks.contains(where: { $0.key == session.key }) {
            island.model.setTitle(title, for: session.key, source: explicit ? .explicitName : .threadTitle)
            session.pendingTitle = nil
        } else if explicit || session.pendingTitle?.explicit != true {
            session.pendingTitle = (title, explicit)
        }
        sessions[sessionID] = session
    }

    // MARK: Transcript

    private func scheduleTailTimer() {
        let active = sessions.values.contains { $0.turnActive && $0.tail != nil }
        if active, tailTimer == nil {
            tailTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.pollTranscripts() }
            }
            tailTimer?.tolerance = 0.25
        } else if !active { tailTimer?.invalidate(); tailTimer = nil }
    }

    private func pollTranscripts() {
        for (id, session) in sessions where session.turnActive && session.tail != nil { drainTranscript(id) }
        // Idle sessions are forgotten after a day without hooks.
        sessions = sessions.filter { $0.value.turnActive || $0.value.updatedAt.timeIntervalSinceNow > -86_400 }
        scheduleTailTimer()
    }

    private func drainTranscript(_ sessionID: String) {
        guard var session = sessions[sessionID], var tail = session.tail else { return }
        let lines = tail.readLines(maximumBytes: 2_097_152)
        session.tail = tail
        sessions[sessionID] = session
        guard !lines.isEmpty else { return }
        var records = lines.flatMap { ClaudeCodeTranscriptDecoder.records($0) }
        if session.backfilling {
            // A mid-turn admission shows only the current turn: records after
            // the latest real prompt. Titles anywhere in the backlog still apply.
            sessions[sessionID]?.backfilling = false
            if let prompt = records.lastIndex(where: { if case .userPrompt = $0 { return true }; return false }) {
                let titles = records[..<prompt].filter { if case .customTitle = $0 { return true }; return false }
                records = titles + records[prompt...]
            }
        }
        for record in records { apply(record, sessionID: sessionID) }
    }

    private func apply(_ record: ClaudeCodeTranscriptRecord, sessionID: String) {
        guard var session = sessions[sessionID] else { return }
        switch record {
        case .customTitle(let title):
            sessions[sessionID] = session
            setTitle(title, explicit: true, sessionID: sessionID)
            return
        case .summary:
            break
        case .userPrompt(let prompt):
            guard !session.hasTitle else { break }
            sessions[sessionID] = session
            setTitle(Self.promptTitle(prompt), explicit: false, sessionID: sessionID)
            return
        case .interrupted:
            guard session.turnActive else { return }
            sessions[sessionID] = session
            emit(.interrupt, sessionID, [:])
            sessions[sessionID]?.turnActive = false
            retireApprovals(sessionID: sessionID, toolUseID: nil)
            return
        case .assistantText(let id, let text):
            session.lastAssistant = (id, text)
            sessions[sessionID] = session
            sendContent(["type": "message", "id": id, "text": text, "channel": "commentary"], sessionID: sessionID)
            return
        case .toolUse(let id, let name, let input):
            sessions[sessionID] = session
            sendContent(["type": "tool", "id": id, "name": name, "text": Self.toolText(input)], sessionID: sessionID)
            return
        case .toolResult(let id, let text, _):
            sessions[sessionID] = session
            sendContent(["type": "output", "id": id, "text": text], sessionID: sessionID)
            retireApprovals(sessionID: sessionID, toolUseID: id)
            return
        case .usage(let key, let model, let usage, _):
            if !session.usageKeys.contains(key), session.usageKeys.count < 100_000 {
                session.usageKeys.insert(key)
                session.turnTokens += usage.total
                if let turn = session.turnKey, session.turnActive {
                    island.model.receiveToken(.init(sessionHash: session.key, turnHash: turn,
                        cumulativeTotalTokens: session.turnTokens, lastReportedTotalTokens: session.turnTokens))
                }
            }
            if session.model != model {
                session.model = model
                sessions[sessionID] = session
                publishMetadata(sessionID)
                return
            }
        }
        sessions[sessionID] = session
    }

    private func discoverTitle(_ path: String, sessionID: String) {
        var custom: String?, prompt: String?
        for line in ClaudeCodeTranscriptTail.headLines(path) {
            for record in ClaudeCodeTranscriptDecoder.records(line) {
                if case .customTitle(let title) = record { custom = title }
                if case .userPrompt(let text) = record, prompt == nil { prompt = text }
            }
        }
        if let custom { setTitle(custom, explicit: true, sessionID: sessionID) }
        else if let prompt { setTitle(Self.promptTitle(prompt), explicit: false, sessionID: sessionID) }
    }

    private func publishMetadata(_ sessionID: String) {
        guard let session = sessions[sessionID] else { return }
        sendContent(["type": "metadata", "model": session.model.map(ClaudeCodePricing.displayName(for:)) ?? "",
                     "effort": session.effort ?? ""], sessionID: sessionID)
    }

    private func sendContent(_ object: [String: Any], sessionID: String) {
        guard let session = sessions[sessionID], let turn = session.turnKey else { return }
        sendContent(object, session: session.key, turn: turn)
    }

    private func sendContent(_ object: [String: Any], session: String, turn: String) {
        guard JSONSerialization.isValidJSONObject(object), let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        island.model.receiveLocalContent(CodexLocalPublicContent(publicSessionHash: session, turnHash: turn, data: data, occurredAt: Date()))
    }

    // MARK: Approvals

    private func admitApproval(_ message: ClaudeCodeBridgeMessage, payload: [String: Any], sessionID: String) {
        guard let session = sessions[sessionID], let turn = session.turnKey,
              let toolName = payload["tool_name"] as? String, !toolName.isEmpty else {
            if message.awaitsDecision { bridge.resolve(eventID: message.eventID, decision: nil) }
            return
        }
        let rawInput = payload["tool_input"] as? [String: Any]
        // A truncated input cannot be echoed back safely in updatedInput.
        let complete = rawInput != nil && rawInput?["_quotaViewTruncated"] == nil
        let input = rawInput ?? [:]
        let suggestions = payload["permission_suggestions"] as? [Any] ?? []
        let toolUseID = payload["tool_use_id"] as? String ?? message.eventID
        guard let wire = try? ClaudeCodeApproval.request(eventID: message.eventID, sessionKey: session.key, turnKey: turn,
                  toolName: toolName, toolInput: input, toolUseID: toolUseID, cwd: session.cwd,
                  hasSuggestions: !suggestions.isEmpty) else {
            if message.awaitsDecision { bridge.resolve(eventID: message.eventID, decision: nil) }
            return
        }
        // Never hold Claude Code's Hook for a request the island cannot answer.
        let interactive = preferences.claudeCodeInteractiveApprovals && message.awaitsDecision
            && complete && (wire.kind != .questions || wire.supportedQuestions)
        if message.awaitsDecision && !interactive { bridge.resolve(eventID: message.eventID, decision: nil) }
        approvals[message.eventID] = Approval(eventID: message.eventID, sessionKey: session.key, toolUseID: toolUseID,
            rpcID: wire.rpcID, awaitsDecision: interactive, toolInput: input, suggestions: suggestions)
        island.model.observeClaudeRequest(wire, sessionKey: session.key, turnKey: turn,
            callHash: CodexActivityPrivacy.hashIdentifier("claude-tool:" + toolUseID), interactive: interactive)
        scheduleTailTimer()
    }

    private func respond(_ wire: IslandCodexApprovalRequest, result: IslandApprovalJSON) throws {
        guard bridgeRunning, preferences.claudeCodeEnabled, preferences.claudeCodeInteractiveApprovals,
              let eventID = ClaudeCodeApproval.eventID(of: wire),
              let approval = approvals[eventID], approval.awaitsDecision,
              let decision = ClaudeCodeApproval.decision(for: wire, result: result,
                  toolInput: approval.toolInput, suggestions: approval.suggestions) else {
            throw CocoaError(.userCancelled)
        }
        approvals.removeValue(forKey: eventID)
        bridge.resolve(eventID: eventID, decision: decision)
        island.model.resolveClaudeRequest(sessionKey: approval.sessionKey, rpcID: approval.rpcID)
    }

    private func returnApprovalsToTerminal() {
        for (eventID, var approval) in approvals where approval.awaitsDecision {
            approval.awaitsDecision = false
            approvals[eventID] = approval
            bridge.resolve(eventID: eventID, decision: nil)
            island.model.returnClaudeRequestToTerminal(sessionKey: approval.sessionKey, rpcID: approval.rpcID)
        }
    }

    private func helperDisconnected(_ eventID: String) {
        guard let approval = approvals.removeValue(forKey: eventID) else { return }
        island.model.resolveClaudeRequest(sessionKey: approval.sessionKey, rpcID: approval.rpcID)
    }

    private func retireApprovals(sessionID: String, toolUseID: String?) {
        let key = Self.sessionKey(sessionID)
        for approval in approvals.values where approval.sessionKey == key && (toolUseID == nil || approval.toolUseID == toolUseID) {
            approvals.removeValue(forKey: approval.eventID)
            if approval.awaitsDecision { bridge.resolve(eventID: approval.eventID, decision: nil) }
            island.model.resolveClaudeRequest(sessionKey: approval.sessionKey, rpcID: approval.rpcID)
        }
    }

    // MARK: Usage

    private var usageRefreshScheduled = false
    private func scheduleUsageRefresh() {
        guard !usageRefreshScheduled else { return }
        usageRefreshScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.usageRefreshScheduled = false
            self?.refreshUsage()
        }
    }

    func refreshUsage() {
        guard bridgeRunning, usageTask == nil else { return }
        let scanner = scanner
        let profileURL = installer.globalConfigURL
        usageTask = Task { [weak self] in
            let summary = await scanner.scan()
            guard !Task.isCancelled else { return }
            let profile = await Task.detached(priority: .utility) { ClaudeCodeAccountProfile.read(from: profileURL) }.value
            guard let self, !Task.isCancelled else { return }
            usageTask = nil
            guard bridgeRunning else { return }
            usage = summary
            self.profile = profile
            publishUsage()
        }
    }

    private func loadRateLimitSnapshot() {
        guard let data = try? Data(contentsOf: installer.statusLineSnapshotURL),
              let limits = ClaudeCodeRateLimits.decode(snapshot: data) else { return }
        if rateLimits.map({ $0.capturedAt < limits.capturedAt }) ?? true { rateLimits = limits; publishUsage() }
    }

    var usagePresentation: IslandClaudeUsage? {
        let statusLine = preferences.claudeCodeStatusLineEnabled
        return Self.presentation(rateLimits: statusLine ? rateLimits : nil, usage: usage, profile: profile, statusLineEnabled: statusLine)
    }

    private func publishUsage() { island.claudeUsage = usagePresentation }

    nonisolated static func presentation(rateLimits: ClaudeCodeRateLimits?, usage: ClaudeCodeUsageSummary?,
                                         profile: ClaudeCodeAccountProfile? = nil, statusLineEnabled: Bool = true,
                                         now: Date = Date()) -> IslandClaudeUsage? {
        guard rateLimits != nil || usage != nil || profile != nil else { return nil }
        // The newest local report wins; a window past its reset time is no longer current.
        let limits = [rateLimits, profile?.cachedRateLimits].compactMap { $0 }.max { $0.capturedAt < $1.capturedAt }
        func window(_ value: ClaudeCodeRateLimits.Window?, minutes: Int, id: String) -> CodexQuotaWindowPresentation? {
            guard let value, value.resetsAt.map({ $0 > now }) ?? true else { return nil }
            let remaining = value.remainingPercent
            return .init(id: EntityID(rawValue: "claude-code." + id), usedPercent: 100 - remaining, remainingPercent: remaining,
                         windowDurationMinutes: minutes, resetsAt: value.resetsAt)
        }
        let fiveHour = window(limits?.fiveHour, minutes: 300, id: "five-hour")
        let sevenDay = window(limits?.sevenDay, minutes: 10_080, id: "seven-day")
        let windows = [fiveHour, sevenDay].compactMap { $0 }
        let primary = windows.first
        let lowest = windows.map(\.remainingPercent).min()
        let availability: CurrentCodexPresentation.Availability = lowest.map { $0 <= 0 ? .exhausted : ($0 <= 10 ? .limited : .ready) } ?? .ready
        let days = usage?.days ?? []
        let activity = days.map { DailyTokenActivity(date: $0.date, tokens: $0.tokens, modelPriced: true, estimatedCost: $0.estimatedCost) }
        let latest = days.last
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        // The footer time describes the quota when one is shown, else the token scan.
        let updated = windows.isEmpty ? (usage?.updatedAt ?? now) : (limits?.capturedAt ?? now)
        return .init(presentation: .init(availability: availability, planType: "Claude Code",
                usedPercent: primary?.usedPercent ?? 0, remainingPercent: primary?.remainingPercent ?? 0,
                windowDurationMinutes: primary?.windowDurationMinutes, resetsAt: primary?.resetsAt,
                quotaWindows: windows, sparkQuota: nil, creditBalance: nil, hasCredits: false, unlimitedCredits: false,
                availableResetCredits: nil, lifetimeTokens: usage?.lifetimeTokens, recentDailyTokens: latest?.tokens,
                recentDailyDate: latest.map { formatter.string(from: $0.date) }, tokenActivity: activity, lastUpdatedAt: updated),
            fiveHour: fiveHour, sevenDay: sevenDay,
            quotaState: !windows.isEmpty ? .available : (statusLineEnabled || limits != nil ? .waiting : .off),
            planName: profile?.planName, extraUsageEnabled: profile?.extraUsageEnabled,
            extraUsagePercent: profile?.extraUsagePercent.map { Int(min(100, max(0, $0)).rounded()) })
    }

    // MARK: Helpers

    nonisolated static func sessionKey(_ sessionID: String) -> String { CodexActivityPrivacy.hashIdentifier("claude-code:" + sessionID) }

    nonisolated static func category(_ tool: String?) -> CodexActivityToolCategory? {
        guard let tool else { return nil }
        switch tool {
        case "Bash", "BashOutput", "KillShell": return .shell
        case "Edit", "MultiEdit", "Write", "NotebookEdit": return .fileEdit
        case "Task", "Agent": return .subagent
        default: return tool.hasPrefix("mcp__") ? .mcp : .localTool
        }
    }

    /// The most identifying argument of common tools; other inputs stay as JSON.
    nonisolated static func toolText(_ input: String) -> String {
        guard let object = input.data(using: .utf8).flatMap({ try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) else {
            return input
        }
        for key in ["command", "file_path", "notebook_path", "url", "pattern", "query", "description", "path"] {
            if let value = object[key] as? String, !value.isEmpty { return value }
        }
        return input
    }

    private static func promptTitle(_ prompt: String) -> String {
        let line = prompt.split(whereSeparator: \.isNewline).first.map(String.init) ?? prompt
        return line.count > 80 ? String(line.prefix(79)) + "…" : line
    }

    private static func json(_ object: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return nil }
        return String(decoding: data.prefix(16_384), as: UTF8.self)
    }

    private static func defaultSocketURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(ClaudeCodeChannel.supportDirectory, isDirectory: true)
            .appendingPathComponent("claude-code.sock")
    }
}
