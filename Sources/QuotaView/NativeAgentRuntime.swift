import AppKit
import Combine
import Foundation
import QuotaViewCore
#if SWIFT_PACKAGE
import QuotaViewActivityHookSupport
#endif

/// Independent local ingress for observation-only agents. Devin supplements hook
/// events with bounded local model/usage reads; no account credentials are used.
@MainActor
final class NativeAgentRuntime: ObservableObject {
    enum Status: Equatable { case disabled, configuring, waiting, connected, failed }
    @Published private(set) var status: Status = .disabled
    @Published private(set) var failure: NativeAgentInstaller.Failure?
    @Published private(set) var configuredHomes: [URL] = []
    @Published private(set) var additionalHomes: [URL]
    @Published private(set) var directorySelectionFailed = false
    enum AGYInstallation { case missing, installing, installed, failed }
    @Published private(set) var agyInstallation: AGYInstallation = .missing

    func checkAGYInstallation() {
        guard provider == .antigravity, agyInstallation != .installing else { return }
        if AntigravityCLI.executable() != nil {
            agyInstallation = .installed
        } else if agyInstallation != .failed {
            agyInstallation = .missing
        }
    }

    func installAGY() {
        checkAGYInstallation()
        guard provider == .antigravity, agyInstallation == .missing || agyInstallation == .failed else { return }
        agyInstallation = .installing
        Task {
            let installed = await Task.detached(priority: .utility) { AntigravityCLI.install() }.value
            agyInstallation = installed ? .installed : .failed
            if installed { await refreshAntigravityAccount() }
        }
    }

    let provider: IslandAgentProvider
    let installer: NativeAgentInstaller
    private let preferences: AppPreferences
    private let defaults: UserDefaults
    private let defaultDSHNamespace: String
    private let island: IslandSession
    private let bridge: ClaudeCodeBridge
    private var observation: AnyCancellable?
    private var configurationTask: Task<Void, Never>?
    private var revision = UUID()
    private var running = false
    private var listening = false
    private var approvalRouteEnabled: Bool?
    private var applied: Bool?
    private var devinMetadataTask: Task<Void, Never>?
    private let readsInstalledAccount: Bool
    private var antigravityAccountTimer: Task<Void, Never>?
    private var antigravityAccountRead: Task<AntigravityAccount?, Never>?
    private let antigravityScanner = AntigravityUsageScanner()
    private var antigravityDetailTasks: [String: Task<Void, Never>] = [:]
    private var antigravityScan: Task<Void, Never>?
    private var antigravityScanDirty = false
    private var rateLogTask: Task<Void, Never>?
    private var dshTitleTasks: [String: Task<Void, Never>] = [:]
    private var dshTitleReadAt: [String: Date] = [:]
    private struct Session {
        var turn: String?
        var terminalBinding: UUID?
        var nativeTurn: String?
        var conversation: IslandConversationTarget?
        var active = false
        var model: String?
        var title: String?
        var parent: String?
        var pendingPermission: String?
        var pendingPermissionTool: String?
        var rateLedger = AgentOutputRateLedger()
        var antigravityTurnStep: Int?
        var antigravityClient: String?
        var antigravityFirstStep: Int?
        var antigravityCountedSteps: Set<Int> = []
        var rateRequestStart: Date?
        var rateRequestID: String?
        var rateLogPath: String?
        var rateLogPosition: Int64?
        var turnStartedAt = Date()
        var rateCompletedAt: Date?
        var tokens: Int64 = 0
        var sequence: Int = -1
        var epoch: String?
        var devinStore: DevinSessionUsage.Store?
        var devinSourceSession: String?
        var devinStartPosition: Int64?
        var devinCompletedAt: Date?
        var devinHasUsage = false
        var updated = Date()
    }
    private var sessions: [String: Session] = [:]
    private struct DevinPermission {
        let wire: IslandCodexApprovalRequest
        let call: String?
        var dispatched = false
    }
    private var devinPermissions: [String: DevinPermission] = [:]
    var devinInteractive: Bool {
        provider.isDevin && (provider == .devinCLI ? preferences.devinCLIApprovals : preferences.devinDesktopApprovals)
            && preferences.codexActivityIslandEnabled && !preferences.codexIslandPrivacy
    }
    private var dshInteractive: Bool {
        preferences.dshInteractiveApprovals && preferences.codexActivityIslandEnabled && !preferences.codexIslandPrivacy
    }
    private struct DSHRequest {
        let session: String; let turn: String; let epoch: String; let auditID: String
        let wire: IslandCodexApprovalRequest
        var rpcID: IslandApprovalJSON { wire.rpcID }
        var awaitsDecision = true
    }
    private struct AntigravityRequest {
        let key: String
        let turn: String
        let card: AntigravityDesktopApproval.Card
        let rpcID: IslandApprovalJSON
    }
    private var antigravityRequests: [String: AntigravityRequest] = [:]
    private var antigravityApprovalPoll: Task<Void, Never>?
    private var handledAntigravityCards: [UUID: AntigravityDesktopApproval.Card] = [:]
    private let readApprovalCards: (Set<UUID>) async -> [UUID: AntigravityDesktopApproval.Card]
    typealias AnswerNativeQuestion = @MainActor (AntigravityDesktopApproval.Card, String, () -> Bool) async -> Bool
    private let answerNativeQuestion: AnswerNativeQuestion
    private let pressApprovalButton: (AntigravityDesktopApproval.Card, Bool) -> Bool
    private var openCode: OpenCodeInteractionAdapter?
    private var openCodeInteractive: Bool {
        provider == .openCode && preferences.openCodeInteractionsEnabled &&
            preferences.codexActivityIslandEnabled && !preferences.codexIslandPrivacy
    }
    private var dshRequests: [String: DSHRequest] = [:]

    init(provider: IslandAgentProvider, preferences: AppPreferences, island: IslandSession, defaults: UserDefaults, installer suppliedInstaller: NativeAgentInstaller? = nil,
         readApprovalCards: ((Set<UUID>) async -> [UUID: AntigravityDesktopApproval.Card])? = nil,
         pressApprovalButton: @escaping (AntigravityDesktopApproval.Card, Bool) -> Bool = AntigravityDesktopApproval.press,
         answerNativeQuestion: @escaping AnswerNativeQuestion = AntigravityDesktopApproval.answer) {
        self.answerNativeQuestion = answerNativeQuestion
        self.readApprovalCards = readApprovalCards ?? { ids in
            guard suppliedInstaller == nil else { return [:] }
            return await Task.detached(priority: .utility) { AntigravityDesktopApproval.scan(ids) }.value
        }
        self.pressApprovalButton = pressApprovalButton
        readsInstalledAccount = suppliedInstaller == nil
        self.provider = provider; self.preferences = preferences; self.island = island; self.defaults = defaults
        additionalHomes = (provider == .dsh ? defaults.stringArray(forKey: "integrations.dsh.additionalHomes") ?? [] : []).prefix(32)
            .filter { $0.hasPrefix("/") }.map { URL(fileURLWithPath: $0) }
        let key = "integrations." + provider.rawValue + ".token"
        let token = defaults.string(forKey: key) ?? UUID().uuidString
        defaults.set(token, forKey: key)
        let channel = String(CodexActivityPrivacy.hashIdentifier(ClaudeCodeChannel.identifier).prefix(12))
        let socket = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("qv-\(channel)-\(provider.rawValue)/events.sock")
        installer = suppliedInstaller ?? NativeAgentInstaller(provider: provider, socketURL: socket, authenticationToken: token)
        defaultDSHNamespace = CodexActivityPrivacy.hashIdentifier(installer.home.resolvingSymlinksInPath().standardizedFileURL.path)
        bridge = ClaudeCodeBridge(socketURL: installer.socketURL, authenticationToken: installer.authenticationToken)
        if provider.isDevin {
            island.model.devinCapabilities[provider] = { [weak self] wire in
                guard let self, running, listening, enabled, devinInteractive, wire.devinProvider == provider,
                      let held = devinPermissions[wire.rpcID.text], !held.dispatched, held.wire == wire,
                      let session = sessions[wire.threadID] else { return false }
                return session.active && session.turn == wire.turnID
            }
            island.model.devinResponders[provider] = { [weak self] wire, result in
                guard let self, island.model.devinCapabilities[provider]?(wire) == true, wire.permits(result),
                      ["accept", "decline"].contains(result["decision"].text) else { throw CancellationError() }
                devinPermissions[wire.rpcID.text]?.dispatched = true
                bridge.resolve(eventID: String(wire.rpcID.text.dropFirst(provider.rawValue.count + 1)),
                    decision: ["decision": result["decision"].text == "accept" ? "approve" : "block"])
            }
        }
        if provider == .openCode {
            openCode = OpenCodeInteractionAdapter(model: island.model, bridge: bridge) { [weak self] key in
                guard let self, running, listening, enabled, openCodeInteractive,
                      let session = sessions[key], session.active, session.parent == nil,
                      let turn = session.turn, let nativeTurn = session.nativeTurn, let epoch = session.epoch
                else { return nil }
                return .init(id: turn, nativeID: nativeTurn, epoch: epoch)
            }
        }
        if provider == .antigravity {
            island.model.antigravityResponseCapability = { [weak self] wire in
                guard let self, wire.isAntigravity, enabled, listening, antigravityApprovalsEnabled,
                      let live = antigravityRequests[String(wire.rpcID.text.dropFirst("antigravity:".count))] else { return false }
                return handledAntigravityCards[live.card.conversation] != live.card && live.key == wire.threadID && live.turn == wire.turnID && sessions[live.key]?.active == true
                    && sessions[live.key]?.turn == live.turn
            }
            island.model.antigravityRespond = { [weak self] wire, result in
                guard let self, island.model.antigravityResponseCapability?(wire) == true, wire.permits(result) else { throw CocoaError(.userCancelled) }
                let id = String(wire.rpcID.text.dropFirst("antigravity:".count))
                guard let request = antigravityRequests[id] else { throw CancellationError() }
                let session = request.card.conversation
                let current = await self.readApprovalCards([session])
                guard island.model.antigravityResponseCapability?(wire) == true,
                      current[session] == request.card else {
                    removeAntigravityRequest(id)
                    throw CancellationError()
                }
                if request.card.question != nil {
                    guard let answer = result["answers"]["answer"]["answers"].array.first?.text,
                          await answerNativeQuestion(request.card, answer, {
                              self.island.model.antigravityResponseCapability?(wire) == true
                          }) else { throw CocoaError(.userCancelled) }
                    handledAntigravityCards[session] = request.card
                    // AXPress confirms dispatch. The next native scan retires
                    // the card when the original question actually disappears.
                    return
                }
                let allow: Bool
                switch result["decision"].text {
                case "accept": allow = true
                case "decline": allow = false
                default: throw CocoaError(.coderInvalidValue)
                }
                guard self.pressApprovalButton(request.card, allow) else { throw CocoaError(.userCancelled) }
                handledAntigravityCards[session] = request.card
                removeAntigravityRequest(id)
            }
        }
        if provider == .dsh {
            island.model.dshResponseCapability = { [weak self] wire in
                guard let self, running, listening, enabled, dshInteractive,
                      let id = DSHApproval.eventID(of: wire), let request = dshRequests[id], request.awaitsDecision, request.wire == wire,
                      let session = sessions[request.session] else { return false }
                return session.active && session.turn == request.turn && session.epoch == request.epoch
            }
            island.model.dshRespond = { [weak self] wire, result in
                guard let self else { throw CancellationError() }
                try respondDSH(wire, result: result)
            }
        }
    }
    private var antigravityApprovalsEnabled: Bool {
        preferences.antigravityInteractiveApprovals && preferences.codexActivityIslandEnabled && !preferences.codexIslandPrivacy
    }
    var enabled: Bool {
        switch provider {
        case .dsh: preferences.dshEnabled
        case .kimiCode: preferences.kimiCodeEnabled
        case .cursor: preferences.cursorEnabled
        case .geminiCLI: preferences.geminiCLIEnabled
        case .openCode: preferences.openCodeEnabled
        case .antigravity: preferences.antigravityEnabled
        case .copilotCLI: preferences.copilotCLIEnabled
        case .devinDesktop: preferences.devinDesktopEnabled
        case .devinCLI: preferences.devinCLIEnabled
        case .codex, .claudeCode: false
        }
    }
    func start() {
        guard !running else { return }; running = true
        observation = preferences.objectWillChange.receive(on: RunLoop.main).sink { [weak self] _ in
            Task { @MainActor in self?.reconcile() }
        }
        reconcile()
    }
    func stop() {
        running = false; observation = nil; revision = UUID(); applied = nil
        stopListening(); status = .disabled
    }
    func retry() { reconcile(force: true) }
    func revealConfiguration() { NSWorkspace.shared.open(installer.home) }
    func addConfigurationDirectory() {
        guard provider == .dsh, additionalHomes.count < 32 else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.message = preferences.copy.text("选择兼容客户端的 DSH 数据目录或 profiles 目录。", "Choose the compatible client's DSH data directory or profiles directory.")
        guard panel.runModal() == .OK, let selected = panel.url else { return }
        Task { [weak self] in
            let home = await Task.detached(priority: .utility) { NativeAgentInstaller.dshHome(for: selected) }.value
            guard let self else { return }
            directorySelectionFailed = home == nil
            guard let home else { return }
            if !additionalHomes.contains(home) && !configuredHomes.contains(home) {
                additionalHomes.append(home)
                defaults.set(additionalHomes.map(\.path), forKey: "integrations.dsh.additionalHomes")
            }
            if enabled { retry() }
        }
    }
    func removeConfigurationDirectory(_ home: URL) {
        guard provider == .dsh else { return }
        additionalHomes.removeAll { $0 == home }
        defaults.set(additionalHomes.map(\.path), forKey: "integrations.dsh.additionalHomes")
        // Reconcile even while disabled to clean any previously installed block.
        retry()
    }
    private func reconcile(force: Bool = false) {
        if provider == .antigravity { refreshAntigravityApprovalMonitor() }
        if provider == .dsh && (!enabled || !dshInteractive) {
            for id in Array(dshRequests.keys) { releaseDSH(id) }
        }
        if !openCodeInteractive {
            openCode?.closeAll()
        }
        if !devinInteractive { for id in Array(devinPermissions.keys) { closeDevin(id) } }
        if preferences.codexIslandPrivacy {
            for (key, session) in sessions where session.terminalBinding != nil {
                if let id = session.terminalBinding { ClaudeTerminalNavigation.bind(nil, to: id) }
                sessions[key]?.terminalBinding = nil
                sessions[key]?.conversation = nil
                publishMetadata(key)
            }
        }
        let interactive = openCodeInteractive || devinInteractive || (provider == .dsh && dshInteractive)
        if running, enabled, listening, provider == .openCode || provider.isDevin || provider == .dsh, approvalRouteEnabled != interactive {
            do {
                try installer.writeRoute(interactiveApprovals: interactive)
                approvalRouteEnabled = interactive
            } catch { failure = .invalidConfiguration; status = .failed }
        }
        guard running, force || applied != enabled else { return }
        let enabled = enabled
        let wasConfigured = applied != nil || FileManager.default.fileExists(atPath: installer.route.path)
        applied = enabled; revision = UUID()
        let current = revision
        stopListening()
        if provider == .antigravity, enabled {
            island.antigravityUsage = .init()
            if readsInstalledAccount {
                antigravityAccountTimer = Task { [weak self] in
                    while !Task.isCancelled {
                        await self?.refreshAntigravityAccount()
                        try? await Task.sleep(nanoseconds: 300_000_000_000)
                    }
                }
            }
            Task { await refreshAntigravityUsage() }
        }
        failure = nil; configuredHomes = []
        guard enabled || wasConfigured else { status = .disabled; return }
        status = .configuring
        let previous = configurationTask
        let installer = installer
        let additionalHomes = additionalHomes
        let approvals = interactive
        configurationTask = Task { [weak self] in
            await previous?.value
            let result = await Task.detached(priority: .utility) { () -> Result<[URL], NativeAgentInstaller.Failure> in
                do { return .success(try installer.configure(enabled: enabled, additionalHomes: additionalHomes, interactiveApprovals: approvals)) }
                catch let error as NativeAgentInstaller.Failure { return .failure(error) }
                catch { return .failure(.invalidConfiguration) }
            }.value
            guard let self, running, revision == current else { return }
            switch result {
            case .success(let homes): configuredHomes = homes
            case .failure(let error): failure = error; status = .failed; return
            }
            guard enabled else {
                status = .disabled
                await installer.configureConversationEditor(enabled: false)
                return
            }
            do {
                try bridge.start(onMessage: { [weak self] message in
                    Task { @MainActor in
                        guard let self, self.revision == current else { return }
                        self.receive(message)
                    }
                }, onDisconnect: { [weak self] id in
                    Task { @MainActor in
                        guard let self, self.revision == current else { return }
                        if self.provider.isDevin { self.closeDevin(self.provider.rawValue + ":" + id) }
                        self.releaseDSH(id)
                        self.openCode?.disconnected(eventID: id)
                    }
                })
                listening = true; status = .waiting
                if provider == .openCode || provider.isDevin || provider == .dsh {
                    approvalRouteEnabled = approvals
                    reconcile()
                }
            } catch { self.failure = .listenerUnavailable; status = .failed; return }
            await installer.configureConversationEditor(enabled: true)
        }
    }
    private func stopListening() {
        for id in Array(devinPermissions.keys) { closeDevin(id) }
        openCode?.closeAll()
        if provider == .antigravity {
            antigravityApprovalPoll?.cancel()
            antigravityApprovalPoll = nil
            handledAntigravityCards.removeAll()
            for id in Array(antigravityRequests.keys) { removeAntigravityRequest(id) }
            for task in antigravityDetailTasks.values { task.cancel() }
            antigravityDetailTasks.removeAll()
            antigravityScan?.cancel(); antigravityScan = nil; antigravityScanDirty = false
            antigravityAccountTimer?.cancel(); antigravityAccountTimer = nil
            antigravityAccountRead?.cancel(); antigravityAccountRead = nil
            island.antigravityUsage = nil
        }
        for task in dshTitleTasks.values { task.cancel() }
        dshTitleTasks.removeAll(); dshTitleReadAt.removeAll()
        for id in Array(dshRequests.keys) { releaseDSH(id) }
        devinMetadataTask?.cancel(); devinMetadataTask = nil
        rateLogTask?.cancel(); rateLogTask = nil
        if listening { bridge.stop() }; listening = false
        for (key, value) in sessions {
            if let id = value.terminalBinding { ClaudeTerminalNavigation.bind(nil, to: id) }
            if let turn = value.turn { island.model.withdrawHookExecution(session: key, turn: turn) }
            if value.parent != nil { island.model.withdrawSubagentObservation(for: key) }
        }
        sessions.removeAll()
    }
    private func closeDevin(_ id: String) {
        guard let held = devinPermissions.removeValue(forKey: id) else { return }
        if !held.dispatched {
            bridge.resolve(eventID: String(id.dropFirst(provider.rawValue.count + 1)), decision: nil)
        }
        island.model.resolveLocalHookRequest(sessionKey: held.wire.threadID, rpcID: held.wire.rpcID)
    }

    private func admitDevin(_ message: ClaudeCodeBridgeMessage, payload: [String: Any]) -> Bool {
        guard running, enabled, listening, devinInteractive, message.awaitsDecision,
              UUID(uuidString: message.eventID) != nil, devinPermissions.count < 32,
              payload["hook_event_name"] as? String == "PermissionRequest", payload["tool_name"] as? String == "exec",
              let rawSession = payload["session_id"] as? String, let nativeTurn = payload["turn_id"] as? String,
              !nativeTurn.isEmpty, let input = payload["tool_input"] as? [String: Any],
              let command = input["command"] as? String, !command.isEmpty,
              let cwd = payload["cwd"] as? String, !cwd.isEmpty, cwd.utf8.count <= 4096,
              let data = try? JSONSerialization.data(withJSONObject: input, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              data.count <= 48_000 else { return false }
        let key = CodexActivityPrivacy.hashIdentifier(provider.rawValue + ":" + rawSession)
        let id = provider.rawValue + ":" + message.eventID
        guard let session = sessions[key], session.active, session.nativeTurn == nativeTurn, session.parent == nil,
              let turn = session.turn, !devinPermissions.values.contains(where: { $0.wire.threadID == key }) else { return false }
        let call = (payload["tool_use_id"] ?? payload["tool_call_id"]) as? String
        let params: [String: Any] = ["devinProvider": provider.rawValue, "threadId": key, "turnId": turn, "itemId": call ?? id,
            "toolName": "exec", "command": String(decoding: data, as: UTF8.self), "cwd": cwd,
            "availableDecisions": ["accept", "decline"]]
        guard let raw = try? JSONSerialization.data(withJSONObject: ["method": "item/commandExecution/requestApproval",
            "id": id, "params": params]), let wire = try? IslandCodexApprovalRequest(data: raw) else { return false }
        devinPermissions[id] = .init(wire: wire, call: call)
        let callHash = CodexActivityPrivacy.hashIdentifier(provider.rawValue + ":" + rawSession + ":" + (call ?? id))
        guard island.model.observeNativeToolRequest(wire, sessionKey: key, turnKey: turn, callHash: callHash) else {
            devinPermissions.removeValue(forKey: id)
            return false
        }
        return true
    }

    private func receive(_ message: ClaudeCodeBridgeMessage) {
        if provider.isDevin, !message.awaitsDecision,
           let payload = (try? JSONSerialization.jsonObject(with: message.payload)) as? [String: String],
           payload["hook_event_name"] == "DevinDecisionReturned", let event = payload["request_id"] {
            let id = provider.rawValue + ":" + event
            if let held = devinPermissions[id], held.dispatched { closeDevin(id) }
            return
        }
        if provider.isDevin, message.awaitsDecision {
            if let payload = (try? JSONSerialization.jsonObject(with: message.payload)) as? [String: Any],
               admitDevin(message, payload: payload) { return }
            bridge.resolve(eventID: message.eventID, decision: nil)
            return
        }
        if openCode?.handle(message) == true { return }
        if provider == .dsh,
           let payload = (try? JSONSerialization.jsonObject(with: message.payload)) as? [String: Any],
           let name = payload["hook_event_name"] as? String, name.hasPrefix("DSHApproval") || name.hasPrefix("DSHQuestion") {
            if !receiveDSH(message, payload: payload, name: name), message.awaitsDecision { bridge.resolve(eventID: message.eventID, decision: nil) }
            return
        }
        defer { if provider == .antigravity { refreshAntigravityApprovalMonitor() } }
        // Observation-only ingress never holds an interactive connection.
        if message.awaitsDecision { bridge.resolve(eventID: message.eventID, decision: nil) }
        guard running, enabled, listening,
              let payload = (try? JSONSerialization.jsonObject(with: message.payload)) as? [String: Any],
              let sourceSession = payload["session_id"] as? String, !sourceSession.isEmpty, sourceSession.utf8.count <= 256,
              let eventName = payload["hook_event_name"] as? String else { return }
        // Older helpers may still report ask_permission before the client evaluates it.
        let name = provider == .antigravity && eventName == "PermissionRequest" ? "PreToolUse" : eventName
        let accepted = ["SessionStart", "SessionEnd", "UserPromptSubmit", "TurnStarted", "PreToolUse", "PostToolUse", "PostToolUseFailure",
                        "PermissionRequest", "PermissionResult", "PreCompact", "PostCompact", "Stop", "StopFailure", "Interrupt", "Usage", "Metadata", "ModelRequest"]
        guard accepted.contains(name) else { return }
        var sourcePrefix = provider.rawValue + ":"
        if provider == .dsh {
            // One provider in the UI; separate data roots must never complete,
            // rename or charge tokens to each other's copied session IDs.
            let namespace = payload["source_namespace"] as? String
                ?? defaultDSHNamespace
            guard namespace.utf8.count == 64, namespace.allSatisfy({ "0123456789abcdef".contains($0) }) else { return }
            sourcePrefix += namespace + ":"
        }
        if status != .connected { status = .connected }
        // Kimi identifies its primary agent as "main". Separate any explicitly
        // identified child so its Stop cannot complete the parent's task.
        let child = provider == .kimiCode ? (payload["agent_id"] as? String).flatMap { $0.isEmpty || $0 == "main" ? nil : $0 } : nil
        let rawSession = child.map { sourceSession + ":agent:" + $0 } ?? sourceSession
        let key = CodexActivityPrivacy.hashIdentifier(sourcePrefix + rawSession)
        if sessions[key] == nil, sessions.count >= 512 {
            guard let oldest = sessions.filter({ !$0.value.active }).min(by: { $0.value.updated < $1.value.updated })?.key else { return }
            if let id = sessions[oldest]?.terminalBinding { ClaudeTerminalNavigation.bind(nil, to: id) }
            sessions.removeValue(forKey: oldest)
        }
        var session = sessions[key] ?? Session()
        if provider == .dsh, let epoch = payload["source_epoch"] as? String, let old = session.epoch, old != epoch {
            for id in dshRequests.filter({ $0.value.session == key }).map(\.key) { releaseDSH(id) }
        }
        let nativeTurn = payload["turn_id"] as? String
        // Ignore stale observations before they can change current metadata.
        if provider.isDevin, !["SessionStart", "SessionEnd", "UserPromptSubmit", "TurnStarted"].contains(name),
           let nativeTurn, let expected = session.nativeTurn, nativeTurn != expected { return }
        if let epoch = payload["source_epoch"] as? String, let sequence = payload["source_sequence"] as? Int {
            if session.epoch == epoch && sequence <= session.sequence { return }
            session.epoch = epoch; session.sequence = sequence
        }
        session.updated = Date()
        if let model = payload["model"] as? String { session.model = String(model.prefix(128)) }
        if let title = payload["session_title"] as? String, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            session.title = String(title.components(separatedBy: .newlines).joined(separator: " ").prefix(256))
        }
        // DSH declares origin=subagent. Ordinary forks are never grouped as children.
        if let parent = child == nil ? payload["parent_session_id"] as? String : sourceSession,
           let identity = CodexActivitySubagentIdentity(threadID: sourcePrefix + rawSession,
               parentThreadID: sourcePrefix + parent, title: session.title) {
            session.parent = parent
            island.model.setProvider(provider, for: key)
            island.model.receiveSubagentIdentity(identity)
        }
        var startedTurn = false
        if name == "UserPromptSubmit" || name == "TurnStarted" {
            if !session.active || (nativeTurn != nil && session.nativeTurn != nil && nativeTurn != session.nativeTurn) {
                session.turn = CodexActivityPrivacy.hashIdentifier(sourcePrefix + rawSession + ":" + (nativeTurn ?? UUID().uuidString))
                session.nativeTurn = nativeTurn; session.active = true; session.tokens = 0; session.pendingPermission = nil; session.pendingPermissionTool = nil
                startedTurn = true
            }
            if let nativeTurn { session.nativeTurn = nativeTurn }
        } else if !session.active && ["PreToolUse", "PermissionRequest"].contains(name) {
            // A late tool event for a finished native turn cannot create another card.
            if let nativeTurn, nativeTurn == session.nativeTurn { return }
            session.turn = CodexActivityPrivacy.hashIdentifier(sourcePrefix + rawSession + ":" + (nativeTurn ?? UUID().uuidString))
            session.nativeTurn = nativeTurn; session.active = true; session.tokens = 0; session.pendingPermission = nil; session.pendingPermissionTool = nil
            startedTurn = true
        }
        if startedTurn {
            session.antigravityCountedSteps.removeAll()
            session.antigravityTurnStep = payload["first_step"] as? Int
            session.rateLedger = .init(); session.rateRequestStart = nil; session.rateRequestID = nil
            session.rateLogPosition = nil; session.rateLogPath = nil
            session.turnStartedAt = (payload["rate_event_ms"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date(); session.rateCompletedAt = nil
        }
        if [IslandAgentProvider.kimiCode, .copilotCLI].contains(provider),
           let path = payload["rate_log_path"] as? String, path.hasPrefix("/"), path.utf8.count <= 4096 {
            if session.rateLogPath != path { session.rateLogPosition = nil }
            session.rateLogPath = path
            if session.rateLogPosition == nil { session.rateLogPosition = 0 }
            if startedTurn { session.rateLogPosition = AgentRateObservation.integer(payload["rate_log_position"]) ?? 0 }
        }
        if provider == .antigravity, let client = payload["log_client"] as? String,
           AntigravityHistory.clients.contains(client) { session.antigravityClient = client }
        if provider == .antigravity, name == "TurnStarted", let ms = payload["rate_event_ms"] as? Double {
            session.antigravityFirstStep = payload["first_step"] as? Int
            session.rateRequestStart = Date(timeIntervalSince1970: ms / 1000)
            session.rateRequestID = UUID().uuidString
        }
        if name == "ModelRequest", provider == .geminiCLI, session.active {
            session.rateRequestStart = (payload["rate_event_ms"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
            session.rateRequestID = UUID().uuidString
        }
        if provider.isDevin {
            if startedTurn {
                session.devinStartPosition = name == "UserPromptSubmit" ? payload["devin_start_position"] as? Int64 : nil
                session.devinCompletedAt = nil
                session.devinHasUsage = false
            }
            if let directory = payload["devin_storage_directory"] as? String,
               let files = payload["devin_storage_files"] as? Bool,
               let store = DevinSessionUsage.Store(directory: directory, files: files) {
                // A changed store cannot reuse a position from the old one.
                if session.devinStore != nil && session.devinStore != store && !startedTurn { session.devinStartPosition = nil }
                session.devinStore = store; session.devinSourceSession = sourceSession
            }
        }
        if [.kimiCode, .geminiCLI, .copilotCLI, .devinCLI].contains(provider), session.parent == nil {
            // Only the local helper supplies this descriptor. Each surface gets
            // a private binding even when two providers use the same session ID.
            if !preferences.codexIslandPrivacy, name != "SessionEnd",
               let field = payload["terminal_host"] as? [String: Any],
               let data = try? JSONSerialization.data(withJSONObject: field), data.count <= 2048,
               let terminal = try? JSONDecoder().decode(ClaudeConversationHost.Terminal.self, from: data),
               terminal.agentProvider == provider.rawValue, terminal.valid {
                let id = session.terminalBinding ?? UUID()
                ClaudeTerminalNavigation.bind(terminal, to: id)
                session.terminalBinding = id
                session.conversation = .agentTerminal(provider, id)
            } else if let id = session.terminalBinding {
                ClaudeTerminalNavigation.bind(nil, to: id)
                session.terminalBinding = nil
                session.conversation = nil
            }
        }
        if !preferences.codexIslandPrivacy, session.parent == nil {
            if provider == .devinDesktop, session.devinStore != nil, IslandConversationTarget.isSessionID(sourceSession) {
                session.conversation = .devin(sourceSession)
            } else if provider == .cursor, let id = UUID(uuidString: sourceSession) {
                session.conversation = .cursor(id)
            } else if provider == .antigravity, let id = UUID(uuidString: sourceSession) {
                switch session.antigravityClient {
                case "antigravity": session.conversation = .antigravity(id)
                case nil: session.conversation = .antigravityHook(id)
                default: session.conversation = nil
                }
            } else if provider == .dsh {
                session.conversation = payload["official_desktop_navigation"] as? Bool == true && IslandConversationTarget.isSessionID(sourceSession)
                    ? .dsh(sourceSession) : nil
            }
        }
        island.model.setProvider(provider, for: key)
        sessions[key] = session
        if provider.isDevin {
            for (id, held) in devinPermissions where held.wire.threadID == key {
                let post = ["PostToolUse", "PostToolUseFailure"].contains(name)
                let call = (payload["tool_use_id"] ?? payload["tool_call_id"]) as? String
                if held.wire.turnID != session.turn || ["Stop", "SessionEnd", "StopFailure", "Interrupt"].contains(name)
                    || (post && held.call != nil && held.call == call && payload["tool_name"] as? String == "exec") { closeDevin(id) }
            }
        }
        openCode?.sessionDidChange(key, ended: ["Stop", "StopFailure", "Interrupt", "SessionEnd"].contains(name))
        if provider == .dsh, session.title == nil || startedTurn || name == "Stop" {
            refreshDSHTitle(key: key, sourceID: sourceSession, namespace: payload["source_namespace"] as? String)
        }
        if provider == .dsh && (startedTurn || ["SessionEnd", "Stop", "StopFailure", "Interrupt"].contains(name)) {
            for id in dshRequests.filter({ $0.value.session == key }).map(\.key) { releaseDSH(id) }
        }
        if provider == .antigravity, let turn = session.turn, session.active,
           ["TurnStarted", "Usage", "Stop", "Interrupt", "StopFailure"].contains(name) {
            refreshAntigravityDetail(key: key, source: sourceSession, turn: turn, session: session, event: name)
        }
        if provider == .antigravity, name == "TurnStarted", !startedTurn { publishMetadata(key); return }
        if name == "SessionStart" || name == "Metadata" || name == "ModelRequest" { publishMetadata(key); return }
        if name == "SessionEnd" {
            if let turn = session.turn { island.model.withdrawHookExecution(session: key, turn: turn) }
            if session.parent != nil { island.model.withdrawSubagentObservation(for: key) }
            sessions.removeValue(forKey: key); return
        }
        guard let turn = session.turn else { return }
        if let nativeTurn, let expected = session.nativeTurn, nativeTurn != expected { return }
        let event: CodexActivityHookEvent?
        var completion: CodexActivityTurnCompletionStatus?
        switch name {
        case "UserPromptSubmit", "TurnStarted": event = .userPromptSubmit
        case "PreToolUse": event = .preToolUse
        case "PostToolUse", "PostToolUseFailure", "PermissionResult": event = .postToolUse
        case "PermissionRequest": event = .permissionRequest
        case "PreCompact": event = .preCompact
        case "PostCompact": event = .postCompact
        case "Stop": event = .stop; completion = .completed
        case "StopFailure": event = .stop; completion = .failed
        case "Interrupt": event = .interrupt; completion = .interrupted
        default: event = nil
        }
        if let event, session.active {
            let tool = (payload["tool_name"] as? String).map { String($0.prefix(128)) }
            var call = ((payload["tool_use_id"] ?? payload["tool_call_id"]) as? String).map { CodexActivityPrivacy.hashIdentifier(sourcePrefix + rawSession + ":" + $0) }
            if name == "PermissionRequest" {
                call = call ?? CodexActivityPrivacy.hashIdentifier(turn + ":permission:" + (tool ?? ""))
                sessions[key]?.pendingPermission = call
                sessions[key]?.pendingPermissionTool = tool
            } else if name == "PermissionResult" || (provider.isDevin && ["PostToolUse", "PostToolUseFailure"].contains(name)
                && session.pendingPermissionTool == tool && (call == nil || call == session.pendingPermission)) {
                call = call ?? session.pendingPermission
                sessions[key]?.pendingPermission = nil
                sessions[key]?.pendingPermissionTool = nil
            }
            let activity = CodexActivityEvent(event: event, sessionHash: key, turnHash: turn,
                toolCategory: category(tool), source: .hook, turnCompletionStatus: completion,
                toolCallHash: call, toolName: tool)
            if session.parent != nil { island.model.receiveSubagentActivity(activity) }
            else {
                island.model.receiveLegacy(activity)
                island.model.setConversation(session.conversation, for: key, provider: provider)
            }
            publishMetadata(key)
            if name == "PreToolUse", let tool, (!provider.usesExternalHooks || call != nil),
               let data = try? JSONSerialization.data(withJSONObject: ["type": "tool", "id": call ?? UUID().uuidString, "name": tool, "text": ""]) {
                let content = CodexLocalPublicContent(publicSessionHash: key, turnHash: turn, data: data, occurredAt: Date())
                island.model.receiveLocalContent(content)
            }
            if ["PostToolUse", "PostToolUseFailure"].contains(name), let call,
               let data = try? JSONSerialization.data(withJSONObject: ["type": "output", "id": call, "text": ""]) {
                island.model.receiveLocalContent(.init(publicSessionHash: key, turnHash: turn, data: data, occurredAt: Date()))
            }
            if completion != nil {
                if provider == .dsh, completion == .completed, session.parent == nil,
                   let answer = payload["final_response"] as? [String: Any],
                   let text = answer["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   text.utf8.count <= 65_536, let id = answer["id"] as? String, !id.isEmpty, id.utf8.count <= 128,
                   let data = try? JSONSerialization.data(withJSONObject: ["type": "message", "id": "dsh-final:" + id,
                       "channel": "final", "text": text, "sourceTruncated": answer["truncated"] as? Bool ?? false]) {
                    island.model.receiveLocalContent(.init(publicSessionHash: key, turnHash: turn, data: data, occurredAt: Date()))
                }
                sessions[key]?.active = false
                sessions[key]?.rateCompletedAt = Date()
                if provider.isDevin { sessions[key]?.devinCompletedAt = Date() }
            }
        }
        if provider == .antigravity, ["Usage", "Stop"].contains(name), let id = session.rateRequestID,
           let start = session.rateRequestStart, let endMS = payload["rate_event_ms"] as? Double,
           UUID(uuidString: sourceSession) != nil {
            sessions[key]?.rateRequestStart = nil
            let root = installer.home.deletingLastPathComponent()
            let hint = session.antigravityClient
            let step = session.antigravityFirstStep
            let end = Date(timeIntervalSince1970: endMS / 1000)
            let version = revision
            Task { [weak self] in
                for _ in 0..<40 {
                    guard let self, running, enabled, revision == version, sessions[key]?.turn == turn else { return }
                    if let usage = await Task.detached(priority: .utility, operation: {
                        guard let logs = AntigravityHistory.logs(root: root, session: sourceSession, client: hint) else { return nil as (step: Int, output: Int64, total: Int64?)? }
                        return Self.antigravityUsage(logs.appendingPathComponent("transcript_full.jsonl"), step: step, start: start, end: end)
                    }).value {
                        guard revision == version, enabled, sessions[key]?.turn == turn,
                              sessions[key]?.antigravityCountedSteps.insert(usage.step).inserted == true else { return }
                        if let rate = AgentRateObservation(id: id, output: usage.output, durationMS: end.timeIntervalSince(start) * 1000, end: end) {
                            receiveRates([rate], key: key, turn: turn)
                        }
                        if let total = usage.total {
                            sessions[key]?.tokens += total
                            let sum = sessions[key]?.tokens ?? total
                            island.model.receiveToken(.init(sessionHash: key, turnHash: turn, cumulativeTotalTokens: sum, lastReportedTotalTokens: total, directTurnTotalTokens: sum))
                        }
                        await refreshAntigravityUsage()
                        return
                    }
                    try? await Task.sleep(nanoseconds: 250_000_000)
                }
            }
        }
        // DSH's epoch/sequence above deduplicates usage before aggregation.
        if name == "Usage", provider == .dsh, session.active, session.parent == nil,
           payload["source_sequence"] is Int, let count = payload["tokens"] as? Int64, (0...1_000_000_000).contains(count) {
            session.tokens = min(session.tokens + count, 1_000_000_000_000)
            sessions[key] = session
            island.model.receiveToken(.init(sessionHash: key, turnHash: turn, cumulativeTotalTokens: session.tokens,
                                            lastReportedTotalTokens: count, directTurnTotalTokens: session.tokens))
        }
        if name == "Usage", session.parent == nil, let output = AgentRateObservation.integer(payload["output_tokens"]) {
            let start = (payload["rate_start_ms"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
                ?? (provider == .geminiCLI ? session.rateRequestStart : nil)
            let end = ((payload["rate_end_ms"] ?? payload["rate_event_ms"]) as? Double)
                .map { Date(timeIntervalSince1970: $0 / 1000) }
            let id = provider == .geminiCLI ? session.rateRequestID : payload["usage_id"] as? String
            if let start, let end, let id,
               let rate = AgentRateObservation(id: id, output: output, durationMS: end.timeIntervalSince(start) * 1000, end: end) {
                receiveRates([rate], key: key, turn: turn)
            }
        }
        if provider.isDevin { refreshDevinMetadata() }
        if provider == .kimiCode || provider == .copilotCLI { refreshRateLogs() }
    }

    private struct AntigravityTurn: Equatable {
        let key: String
        let turn: String
    }

    private var antigravityApprovalTurns: [UUID: AntigravityTurn] {
        guard running, enabled, listening, antigravityApprovalsEnabled else { return [:] }
        var targets: [UUID: AntigravityTurn] = [:]
        for (key, session) in sessions where session.active && session.parent == nil {
            guard let turn = session.turn else { continue }
            switch session.conversation {
            case .antigravity(let id), .antigravityHook(let id): targets[id] = .init(key: key, turn: turn)
            default: break
            }
        }
        return targets
    }

    private func refreshAntigravityApprovalMonitor() {
        let turns = antigravityApprovalTurns
        for (id, request) in antigravityRequests where turns[request.card.conversation]?.turn != request.turn {
            removeAntigravityRequest(id)
        }
        handledAntigravityCards = handledAntigravityCards.filter { turns[$0.key] != nil }
        guard !turns.isEmpty else {
            antigravityApprovalPoll?.cancel()
            antigravityApprovalPoll = nil
            return
        }
        guard antigravityApprovalPoll == nil else { return }
        antigravityApprovalPoll = Task { [weak self] in
            while !Task.isCancelled {
                guard let turns = self?.antigravityApprovalTurns, !turns.isEmpty else { return }
                let cards = await self?.readApprovalCards(Set(turns.keys)) ?? [:]
                guard !Task.isCancelled else { return }
                self?.updateAntigravityCards(cards, scannedTurns: turns)
                do { try await Task.sleep(for: .seconds(1.5)) } catch { return }
            }
        }
    }

    private func updateAntigravityCards(_ cards: [UUID: AntigravityDesktopApproval.Card], scannedTurns: [UUID: AntigravityTurn]) {
        let turns = antigravityApprovalTurns
        for (id, request) in antigravityRequests where cards[request.card.conversation] != request.card {
            removeAntigravityRequest(id)
        }
        for (conversation, card) in cards {
            guard conversation == card.conversation, let scope = turns[conversation], scope == scannedTurns[conversation],
                  handledAntigravityCards[conversation] != card,
                  !antigravityRequests.values.contains(where: { $0.card == card }) else { continue }
            let key = scope.key, turn = scope.turn
            let id = UUID().uuidString
            var params: [String: Any] = ["antigravity": true, "threadId": key, "turnId": turn, "itemId": id]
            let method: String
            if let question = card.question {
                method = "item/tool/requestUserInput"
                params["questions"] = [["id": "answer", "question": card.content, "isOther": true,
                    "options": question.options.map { ["label": $0.label] }]]
            } else if let nativeScope = card.scope {
                method = "item/commandExecution/requestApproval"
                params["command"] = card.content
                params["nativeScope"] = nativeScope.rawValue
                params["availableDecisions"] = ["accept", "decline"]
            } else { continue }
            guard let data = try? JSONSerialization.data(withJSONObject: ["id": "antigravity:" + id,
                "method": method, "params": params]),
                  let wire = try? IslandCodexApprovalRequest(data: data) else { continue }
            antigravityRequests[id] = .init(key: key, turn: turn, card: card, rpcID: wire.rpcID)
            if !island.model.observeNativeToolRequest(wire, sessionKey: key, turnKey: turn, callHash: id) {
                removeAntigravityRequest(id)
            }
        }
    }

    private func removeAntigravityRequest(_ id: String) {
        guard let request = antigravityRequests.removeValue(forKey: id) else { return }
        island.model.resolveLocalHookRequest(sessionKey: request.key, rpcID: request.rpcID)
    }

    private func receiveDSH(_ message: ClaudeCodeBridgeMessage, payload: [String: Any], name: String) -> Bool {
        guard running, enabled, listening,
              let source = payload["session_id"] as? String, !source.isEmpty, source.utf8.count <= 256,
              let namespace = payload["source_namespace"] as? String, namespace.count == 64,
              namespace.allSatisfy({ "0123456789abcdef".contains($0) }),
              let epoch = payload["source_epoch"] as? String, !epoch.isEmpty, epoch.utf8.count <= 128,
              let nativeTurn = payload["turn_id"] as? String,
              let id = payload["request_id"] as? String, !id.isEmpty, id.utf8.count <= 128,
              let auditID = payload["approval_id"] as? String, !auditID.isEmpty, auditID.utf8.count <= 128 else { return false }
        let prefix = "dsh:" + namespace + ":" + source
        let key = CodexActivityPrivacy.hashIdentifier(prefix)
        guard let session = sessions[key], session.active, session.parent == nil,
              session.epoch == epoch, session.nativeTurn == nativeTurn, let turn = session.turn else { return false }
        if name == "DSHApprovalRequest" || name == "DSHQuestionRequest" {
            guard message.awaitsDecision, message.eventID == id, dshInteractive,
                  dshRequests[id] == nil, dshRequests.count < 32,
                  !dshRequests.values.contains(where: { $0.session == key && $0.auditID == auditID }),
                  let call = payload["tool_use_id"] as? String, !call.isEmpty, call.utf8.count <= 256,
                  let wire = try? DSHApproval.request(eventID: id, sessionKey: key, turnKey: turn, payload: payload) else { return false }
            dshRequests[id] = .init(session: key, turn: turn, epoch: epoch, auditID: auditID, wire: wire)
            guard island.model.observeNativeToolRequest(wire, sessionKey: key, turnKey: turn,
                    callHash: CodexActivityPrivacy.hashIdentifier(prefix + ":" + call)) else {
                dshRequests.removeValue(forKey: id); return false
            }
            bridge.admit(eventID: id)
            return true
        }
        guard let request = dshRequests[id], request.session == key, request.turn == turn,
              request.epoch == epoch, request.auditID == auditID else { return false }
        if name == "DSHQuestionClosed", request.wire.kind == .questions {
            releaseDSH(id)
        } else if name == "DSHApprovalSettled", let outcome = payload["outcome"] as? String,
           ["allowed-once", "rejected", "cancelled", "unavailable"].contains(outcome) {
            dshRequests.removeValue(forKey: id)
            bridge.resolve(eventID: id, decision: nil)
            island.model.resolveLocalHookRequest(sessionKey: key, rpcID: request.rpcID)
        } else if name == "DSHApprovalReleased" { releaseDSH(id) }
        return true
    }

    private func respondDSH(_ wire: IslandCodexApprovalRequest, result: IslandApprovalJSON) throws {
        guard island.model.dshResponseCapability?(wire) == true, wire.permits(result),
              let id = DSHApproval.eventID(of: wire), dshRequests[id]?.rpcID == wire.rpcID else { throw CocoaError(.userCancelled) }
        if wire.kind == .questions, let question = wire.questions.first,
           let answer = result["answers"][question.id]["answers"].array.first?.text {
            guard answer.utf8.count <= 4096 else { throw CocoaError(.fileReadTooLarge) }
            dshRequests[id]?.awaitsDecision = false
            bridge.resolve(eventID: id, decision: ["answer": answer])
            return
        }
        switch result["decision"].text {
        case "accept", "decline":
            dshRequests[id]?.awaitsDecision = false
            bridge.resolve(eventID: id, decision: ["outcome": result["decision"].text == "accept" ? "allowed-once" : "rejected"])
            // Keep the pending presentation until the actual DSH audit event.
        case "dshDelegate": releaseDSH(id)
        default: throw CocoaError(.coderInvalidValue)
        }
    }

    private func releaseDSH(_ id: String) {
        guard let request = dshRequests.removeValue(forKey: id) else { return }
        bridge.resolve(eventID: id, decision: nil)
        if request.wire.kind == .questions {
            island.model.resolveLocalHookRequest(sessionKey: request.session, rpcID: request.rpcID)
        } else {
            island.model.returnDSHRequest(sessionKey: request.session, rpcID: request.rpcID)
        }
    }

    private struct DevinRead: Sendable {
        let key: String
        let sourceSession: String
        let turn: String
        let store: DevinSessionUsage.Store
        let start: Int64?
    }

    private func refreshDevinMetadata() {
        guard devinMetadataTask == nil else { return }
        let currentRevision = revision
        devinMetadataTask = Task { [weak self] in
            defer { if self?.revision == currentRevision { self?.devinMetadataTask = nil } }
            while !Task.isCancelled {
                guard let self, running, enabled, revision == currentRevision else { return }
                let requests = sessions.compactMap { key, value -> DevinRead? in
                    guard value.active || (value.devinCompletedAt.map { Date().timeIntervalSince($0) < 10 } ?? false),
                          let turn = value.turn, let store = value.devinStore, let source = value.devinSourceSession else { return nil }
                    return DevinRead(key: key, sourceSession: source, turn: turn, store: store, start: value.devinStartPosition)
                }
                guard !requests.isEmpty else { return }
                let reader = Task.detached(priority: .utility) {
                    var values: [(DevinRead, DevinSessionUsage.Snapshot?)] = []
                    for request in requests {
                        guard !Task.isCancelled else { break }
                        values.append((request, DevinSessionUsage.read(session: request.sourceSession, store: request.store, after: request.start)))
                    }
                    return values
                }
                let snapshots = await withTaskCancellationHandler(operation: { await reader.value }, onCancel: { reader.cancel() })
                guard !Task.isCancelled, running, enabled, revision == currentRevision else { return }
                for (request, snapshot) in snapshots {
                    guard let snapshot, var session = sessions[request.key], session.turn == request.turn,
                          session.devinStore == request.store, session.devinStartPosition == request.start else { continue }
                    if let model = snapshot.model, model != session.model {
                        session.model = model
                        sessions[request.key] = session
                        publishMetadata(request.key)
                    }
                    if request.start != nil {
                        receiveRates(snapshot.rates, key: request.key, turn: request.turn)
                    }
                    if let tokens = snapshot.tokens, request.start != nil, tokens >= session.tokens,
                       !session.devinHasUsage || tokens != session.tokens {
                        sessions[request.key]?.tokens = tokens
                        sessions[request.key]?.devinHasUsage = true
                        island.model.receiveToken(.init(sessionHash: request.key, turnHash: request.turn,
                            cumulativeTotalTokens: tokens, lastReportedTotalTokens: tokens, directTurnTotalTokens: tokens))
                    }
                }
                do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
            }
        }
    }
    private func receiveRates(_ rates: [AgentRateObservation], key: String, turn: String) {
        guard var session = sessions[key], session.turn == turn, session.parent == nil else { return }
        var changed = false
        for rate in rates {
            if session.rateLedger.record(id: rate.id, output: rate.output, start: rate.start, end: rate.end) { changed = true }
        }
        guard changed else { return }
        sessions[key] = session
        island.model.receiveOutputRate(session: key, turn: turn,
            latest: session.rateLedger.latest, average: session.rateLedger.average)
    }
    func refreshAntigravityAccount(manual: Bool = false) async {
        guard provider == .antigravity, readsInstalledAccount, running, enabled else { return }
        if let read = antigravityAccountRead { _ = await read.value; return }
        let version = revision
        let read = Task.detached(priority: .utility) { AntigravityAccount.read(manual: manual) }
        antigravityAccountRead = read
        let account = await read.value
        guard revision == version, enabled else { return }
        antigravityAccountRead = nil
        if var usage = island.antigravityUsage {
            if !usage.didCheckAccount || (usage.account?.windows.isEmpty == false) != (account?.windows.isEmpty == false) {
                objectWillChange.send()
            }
            usage.account = account
            usage.didCheckAccount = true
            island.antigravityUsage = usage
        }
    }

    func refreshAntigravityUsage() async {
        guard provider == .antigravity, running, enabled else { return }
        if let antigravityScan {
            antigravityScanDirty = true
            await antigravityScan.value
            return
        }
        let version = revision, root = installer.home.deletingLastPathComponent()
        let task = Task {
            repeat {
                antigravityScanDirty = false
                var usage = await antigravityScanner.scan(root: root)
                guard !Task.isCancelled, revision == version, enabled else { return }
                usage.account = island.antigravityUsage?.account
                usage.didCheckAccount = island.antigravityUsage?.didCheckAccount ?? false
                island.antigravityUsage = usage
            } while antigravityScanDirty
            antigravityScan = nil
        }
        antigravityScan = task
        await task.value
    }

    private func refreshAntigravityDetail(key: String, source: String, turn: String, session: Session, event: String) {
        antigravityDetailTasks[key]?.cancel()
        let version = revision, root = installer.home.deletingLastPathComponent()
        let client = session.antigravityClient, first = session.antigravityTurnStep, start = session.turnStartedAt
        let end = Date(), finished = event == "Stop"
        antigravityDetailTasks[key] = Task { [weak self] in
            var receivedFinal = false
            for attempt in 0..<(finished ? 17 : 3) {
                if attempt > 0 {
                    try? await Task.sleep(nanoseconds: attempt < 10 ? 400_000_000 : 8_000_000_000)
                }
                guard !Task.isCancelled else { return }
                let needsReplies = !receivedFinal
                let (title, replies) = await Task.detached(priority: .utility) {
                    guard let logs = AntigravityHistory.logs(root: root, session: source, client: client) else {
                        return (nil as String?, [AntigravityHistory.Reply]())
                    }
                    let database = logs.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                        .deletingLastPathComponent().appendingPathComponent("conversation_summaries.db")
                    return (AntigravityHistory.title(database: database, session: source),
                            needsReplies ? AntigravityHistory.replies(logs: logs, firstStep: first, start: start, end: end) : [])
                }.value
                guard let self, !Task.isCancelled, revision == version, enabled, sessions[key]?.turn == turn else { return }
                if let title, sessions[key]?.title != title { sessions[key]?.title = title; publishMetadata(key) }
                let finalIndex = replies.last.flatMap { last in
                    finished && !last.hasTools && last.index >= (session.antigravityFirstStep ?? 0) ? last.index : nil
                }
                for reply in replies {
                    let final = reply.index == finalIndex
                    let row: [String: Any] = ["type": "message", "id": "antigravity-step-" + String(reply.index),
                        "channel": final ? "final" : "commentary", "text": reply.text, "sourceTruncated": reply.truncated]
                    if let data = try? JSONSerialization.data(withJSONObject: row) {
                        island.model.receiveLocalContent(.init(publicSessionHash: key, turnHash: turn, data: data, occurredAt: reply.date))
                    }
                }
                receivedFinal = receivedFinal || finalIndex != nil
                if title != nil && (event == "TurnStarted" || receivedFinal || (!finished && !replies.isEmpty)) { break }
            }
            self?.antigravityDetailTasks[key] = nil
        }
    }

    private struct RateLogRead: Sendable {
        let key: String; let turn: String; let path: String; let position: Int64; let since: Date
    }
    nonisolated static func antigravityUsage(_ file: URL, step: Int?, start: Date, end: Date) -> (step: Int, output: Int64, total: Int64?)? {
        guard file.resolvingSymlinksInPath().standardizedFileURL == file.standardizedFileURL,
              let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let length = try? handle.seekToEnd() else { return nil }
        let size = min(length, 2_097_152)
        guard (try? handle.seek(toOffset: length - size)) != nil, let data = try? handle.read(upToCount: Int(size)) else { return nil }
        // created_at has one-second resolution in desktop logs. Intermediate
        // system and tool steps can precede the actual planner response.
        let clock = ISO8601DateFormatter()
        var matches: [(step: Int, output: Int64, total: Int64?)] = []
        for line in data.split(separator: 10) {
            guard let row = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  row["type"] as? String == "PLANNER_RESPONSE", let index = row["step_index"] as? Int,
                  let timestamp = row["created_at"] as? String, let date = clock.date(from: timestamp),
                  date.timeIntervalSince1970 >= floor(start.timeIntervalSince1970) - 1, date <= end,
                  let output = AgentRateObservation.integer(row["output_tokens"]), (0...1_000_000_000).contains(output) else { continue }
            matches.append((index, output, AntigravityHistory.tokens(row)))
        }
        let candidates = matches.filter { candidate in step.map { candidate.step >= $0 } ?? true }
        guard let selected = candidates.first, candidates.count == 1 || selected.step == step else { return nil }
        return selected
    }
    private func refreshRateLogs() {
        guard rateLogTask == nil else { return }
        let current = revision, source = provider.rawValue
        rateLogTask = Task { [weak self] in
            defer { if self?.revision == current { self?.rateLogTask = nil } }
            while !Task.isCancelled {
                guard let self, running, enabled, revision == current else { return }
                let requests = sessions.compactMap { key, s -> RateLogRead? in
                    guard s.active || (s.rateCompletedAt.map { Date().timeIntervalSince($0) < 10 } ?? false),
                          s.parent == nil, let turn = s.turn, let path = s.rateLogPath,
                          let position = s.rateLogPosition else { return nil }
                    return .init(key: key, turn: turn, path: path, position: position, since: s.turnStartedAt)
                }
                guard !requests.isEmpty else { return }
                let reader = Task.detached(priority: .utility) {
                    var result: [(RateLogRead, [AgentRateObservation])] = []
                    for request in requests {
                        guard !Task.isCancelled else { break }
                        result.append((request, AgentRateLog.read(url: URL(fileURLWithPath: request.path),
                            provider: source, after: request.position, since: request.since)))
                    }
                    return result
                }
                let result = await withTaskCancellationHandler(operation: { await reader.value }, onCancel: { reader.cancel() })
                guard !Task.isCancelled, revision == current, enabled else { return }
                for (request, rates) in result {
                    guard let session = sessions[request.key], session.turn == request.turn,
                          session.rateLogPath == request.path, session.rateLogPosition == request.position else { continue }
                    receiveRates(rates, key: request.key, turn: request.turn)
                }
                do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
            }
        }
    }
    private func refreshDSHTitle(key: String, sourceID: String, namespace: String?) {
        guard dshTitleTasks[key] == nil, dshTitleTasks.count < 32,
              Date().timeIntervalSince(dshTitleReadAt[key] ?? .distantPast) >= 5,
              let home = configuredHomes.first(where: { CodexActivityPrivacy.hashIdentifier($0.resolvingSymlinksInPath().standardizedFileURL.path) == namespace }),
              let session = sessions[key], let turn = session.turn else { return }
        let current = revision, epoch = session.epoch
        dshTitleReadAt[key] = Date()
        if dshTitleReadAt.count > 512, let oldest = dshTitleReadAt.min(by: { $0.value < $1.value })?.key { dshTitleReadAt.removeValue(forKey: oldest) }
        dshTitleTasks[key] = Task { [weak self] in
            let title = await Task.detached(priority: .utility) { Self.dshCachedTitle(home: home, sessionID: sourceID) }.value
            guard let self, !Task.isCancelled, revision == current else { return }
            dshTitleTasks.removeValue(forKey: key)
            guard enabled, sessions[key]?.turn == turn, sessions[key]?.epoch == epoch,
                  sessions[key]?.title == session.title, let title else { return }
            sessions[key]?.title = title
            publishMetadata(key)
        }
    }

    /// Read only the public title projection, never derive a title from prompts.
    nonisolated static func dshCachedTitle(home: URL, sessionID: String) -> String? {
        guard !sessionID.isEmpty, sessionID.utf8.count <= 256,
              sessionID.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { return nil }
        let directory = home.appendingPathComponent("storages/session_projcache/sessions").standardizedFileURL
        let file = directory.appendingPathComponent(sessionID + ".json")
        guard file.resolvingSymlinksInPath().path == file.path,
              let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? Int, size <= 2_097_152,
              let data = try? Data(contentsOf: file), data.count <= 2_097_152 else { return nil }
        struct Projection: Decodable {
            struct Record: Decodable {
                struct Rows: Decodable {
                    struct Title: Decodable { let ver: Int; let val: String }
                    let title: Title
                }
                let rows: Rows
            }
            let version: Int; let record: Record
        }
        guard let projection = try? JSONDecoder().decode(Projection.self, from: data), projection.version == 7,
              projection.record.rows.title.ver == 1 else { return nil }
        let title = projection.record.rows.title.val.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : String(title.components(separatedBy: .newlines).joined(separator: " ").prefix(256))
    }

    private func publishMetadata(_ key: String) {
        guard let session = sessions[key], let turn = session.turn else { return }
        island.model.setTitle(session.title ?? provider.displayName + " " + preferences.copy.text("任务", "task"), for: key, source: .threadTitle)
        guard let model = session.model,
              let data = try? JSONSerialization.data(withJSONObject: ["type": "metadata", "model": model, "effort": ""]) else { return }
        let content = CodexLocalPublicContent(publicSessionHash: key, turnHash: turn, data: data, occurredAt: Date())
        island.model.receiveLocalContent(content)
    }
    private func category(_ name: String?) -> CodexActivityToolCategory {
        let name = name?.lowercased() ?? ""
        if (name == "exec" || name.contains("bash")) || name.contains("shell") || name.contains("terminal") { return .shell }
        if name.contains("edit") || name.contains("write") || name.contains("patch") { return .fileEdit }
        if name.contains("agent") { return .subagent }
        return .localTool
    }
}
