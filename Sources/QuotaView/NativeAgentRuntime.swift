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
    private var applied: Bool?
    private var devinMetadataTask: Task<Void, Never>?
    private var dshTitleTasks: [String: Task<Void, Never>] = [:]
    private var dshTitleReadAt: [String: Date] = [:]
    private struct Session {
        var turn: String?
        var nativeTurn: String?
        var active = false
        var model: String?
        var title: String?
        var parent: String?
        var pendingPermission: String?
        var pendingPermissionTool: String?
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
    private struct DSHRequest {
        let session: String; let turn: String; let epoch: String; let auditID: String
        let rpcID: IslandApprovalJSON
        var awaitsDecision = true
    }
    private var dshRequests: [String: DSHRequest] = [:]

    init(provider: IslandAgentProvider, preferences: AppPreferences, island: IslandSession, defaults: UserDefaults, installer suppliedInstaller: NativeAgentInstaller? = nil) {
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
        if provider == .dsh {
            island.model.dshResponseCapability = { [weak self] wire in
                guard let self, running, listening, enabled, preferences.dshInteractiveApprovals,
                      let id = DSHApproval.eventID(of: wire), let request = dshRequests[id], request.awaitsDecision,
                      let session = sessions[request.session] else { return false }
                return session.active && session.turn == request.turn && session.epoch == request.epoch
            }
            island.model.dshRespond = { [weak self] wire, result in
                guard let self else { throw CancellationError() }
                try respondDSH(wire, result: result)
            }
        }
    }
    var enabled: Bool {
        switch provider {
        case .dsh: preferences.dshEnabled
        case .kimiCode: preferences.kimiCodeEnabled
        case .cursor: preferences.cursorEnabled
        case .geminiCLI: preferences.geminiCLIEnabled
        case .openCode: preferences.openCodeEnabled
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
        if provider == .dsh && (!enabled || !preferences.dshInteractiveApprovals) {
            for id in Array(dshRequests.keys) { releaseDSH(id) }
        }
        guard running, force || applied != enabled else { return }
        let enabled = enabled
        let wasConfigured = applied != nil || FileManager.default.fileExists(atPath: installer.route.path)
        applied = enabled; revision = UUID()
        let current = revision
        stopListening()
        failure = nil; configuredHomes = []
        guard enabled || wasConfigured else { status = .disabled; return }
        status = .configuring
        let previous = configurationTask
        let installer = installer
        let additionalHomes = additionalHomes
        configurationTask = Task { [weak self] in
            await previous?.value
            let result = await Task.detached(priority: .utility) { () -> Result<[URL], NativeAgentInstaller.Failure> in
                do { return .success(try installer.configure(enabled: enabled, additionalHomes: additionalHomes)) }
                catch let error as NativeAgentInstaller.Failure { return .failure(error) }
                catch { return .failure(.invalidConfiguration) }
            }.value
            guard let self, running, revision == current else { return }
            switch result {
            case .success(let homes): configuredHomes = homes
            case .failure(let error): failure = error; status = .failed; return
            }
            guard enabled else { status = .disabled; return }
            do {
                try bridge.start(onMessage: { [weak self] message in
                    Task { @MainActor in
                        guard let self, self.revision == current else { return }
                        self.receive(message)
                    }
                }, onDisconnect: { [weak self] id in
                    Task { @MainActor in
                        guard let self, self.revision == current else { return }
                        self.releaseDSH(id)
                    }
                })
                listening = true; status = .waiting
            } catch { self.failure = .listenerUnavailable; status = .failed }
        }
    }
    private func stopListening() {
        for task in dshTitleTasks.values { task.cancel() }
        dshTitleTasks.removeAll(); dshTitleReadAt.removeAll()
        for id in Array(dshRequests.keys) { releaseDSH(id) }
        devinMetadataTask?.cancel(); devinMetadataTask = nil
        if listening { bridge.stop() }; listening = false
        for (key, value) in sessions {
            if let turn = value.turn { island.model.withdrawHookExecution(session: key, turn: turn) }
            if value.parent != nil { island.model.withdrawSubagentObservation(for: key) }
        }
        sessions.removeAll()
    }
    private func receive(_ message: ClaudeCodeBridgeMessage) {
        if provider == .dsh,
           let payload = (try? JSONSerialization.jsonObject(with: message.payload)) as? [String: Any],
           let name = payload["hook_event_name"] as? String, name.hasPrefix("DSHApproval") {
            if !receiveDSH(message, payload: payload, name: name), message.awaitsDecision { bridge.resolve(eventID: message.eventID, decision: nil) }
            return
        }
        // Observation-only ingress never holds an interactive connection.
        if message.awaitsDecision { bridge.resolve(eventID: message.eventID, decision: nil) }
        guard running, enabled, listening,
              let payload = (try? JSONSerialization.jsonObject(with: message.payload)) as? [String: Any],
              let sourceSession = payload["session_id"] as? String, !sourceSession.isEmpty, sourceSession.utf8.count <= 256,
              let name = payload["hook_event_name"] as? String else { return }
        let accepted = ["SessionStart", "SessionEnd", "UserPromptSubmit", "TurnStarted", "PreToolUse", "PostToolUse", "PostToolUseFailure",
                        "PermissionRequest", "PermissionResult", "PreCompact", "PostCompact", "Stop", "StopFailure", "Interrupt", "Usage", "Metadata"]
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
        island.model.setProvider(provider, for: key)
        sessions[key] = session
        if provider == .dsh, session.title == nil || startedTurn || name == "Stop" {
            refreshDSHTitle(key: key, sourceID: sourceSession, namespace: payload["source_namespace"] as? String)
        }
        if provider == .dsh && (startedTurn || ["SessionEnd", "Stop", "StopFailure", "Interrupt"].contains(name)) {
            for id in dshRequests.filter({ $0.value.session == key }).map(\.key) { releaseDSH(id) }
        }
        if name == "SessionStart" || name == "Metadata" { publishMetadata(key); return }
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
            else { island.model.receiveLegacy(activity) }
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
                if provider.isDevin { sessions[key]?.devinCompletedAt = Date() }
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
        if provider.isDevin { refreshDevinMetadata() }
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
        if name == "DSHApprovalRequest" {
            guard message.awaitsDecision, message.eventID == id, preferences.dshInteractiveApprovals,
                  dshRequests[id] == nil, dshRequests.count < 32,
                  !dshRequests.values.contains(where: { $0.session == key && $0.auditID == auditID }),
                  let call = payload["tool_use_id"] as? String, !call.isEmpty, call.utf8.count <= 256,
                  let wire = try? DSHApproval.request(eventID: id, sessionKey: key, turnKey: turn, payload: payload) else { return false }
            dshRequests[id] = .init(session: key, turn: turn, epoch: epoch, auditID: auditID, rpcID: wire.rpcID)
            guard island.model.observeDSHRequest(wire, sessionKey: key, turnKey: turn,
                    callHash: CodexActivityPrivacy.hashIdentifier(prefix + ":" + call)) else {
                dshRequests.removeValue(forKey: id); return false
            }
            bridge.admit(eventID: id)
            return true
        }
        guard let request = dshRequests[id], request.session == key, request.turn == turn,
              request.epoch == epoch, request.auditID == auditID else { return false }
        if name == "DSHApprovalSettled", let outcome = payload["outcome"] as? String,
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
        island.model.returnDSHRequest(sessionKey: request.session, rpcID: request.rpcID)
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
