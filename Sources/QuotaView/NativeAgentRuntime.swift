import AppKit
import Combine
import Foundation
import QuotaViewCore

/// Independent local ingress for DSH and Kimi Code. No polling, account credentials, or transcript reads.
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
    private struct Session {
        var turn: String?
        var nativeTurn: String?
        var active = false
        var model: String?
        var title: String?
        var parent: String?
        var pendingPermission: String?
        var tokens: Int64 = 0
        var sequence: Int = -1
        var epoch: String?
        var updated = Date()
    }
    private var sessions: [String: Session] = [:]

    init(provider: IslandAgentProvider, preferences: AppPreferences, island: IslandSession, defaults: UserDefaults) {
        self.provider = provider; self.preferences = preferences; self.island = island; self.defaults = defaults
        additionalHomes = (provider == .dsh ? defaults.stringArray(forKey: "integrations.dsh.additionalHomes") ?? [] : []).prefix(32)
            .filter { $0.hasPrefix("/") }.map { URL(fileURLWithPath: $0) }
        let key = "integrations." + provider.rawValue + ".token"
        let token = defaults.string(forKey: key) ?? UUID().uuidString
        defaults.set(token, forKey: key)
        let channel = String(CodexActivityPrivacy.hashIdentifier(ClaudeCodeChannel.identifier).prefix(12))
        let socket = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("qv-\(channel)-\(provider.rawValue)/events.sock")
        installer = NativeAgentInstaller(provider: provider, socketURL: socket, authenticationToken: token)
        defaultDSHNamespace = CodexActivityPrivacy.hashIdentifier(installer.home.resolvingSymlinksInPath().standardizedFileURL.path)
        bridge = ClaudeCodeBridge(socketURL: socket, authenticationToken: token)
    }
    var enabled: Bool { provider == .dsh ? preferences.dshEnabled : preferences.kimiCodeEnabled }
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
                }, onDisconnect: { _ in })
                listening = true; status = .waiting
            } catch { self.failure = .listenerUnavailable; status = .failed }
        }
    }
    private func stopListening() {
        if listening { bridge.stop() }; listening = false
        for (key, value) in sessions {
            if let turn = value.turn { island.model.withdrawHookExecution(session: key, turn: turn) }
            if value.parent != nil { island.model.withdrawSubagentObservation(for: key) }
        }
        sessions.removeAll()
    }
    private func receive(_ message: ClaudeCodeBridgeMessage) {
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
        let nativeTurn = payload["turn_id"] as? String
        if name == "UserPromptSubmit" || name == "TurnStarted" {
            if !session.active || (nativeTurn != nil && session.nativeTurn != nil && nativeTurn != session.nativeTurn) {
                session.turn = CodexActivityPrivacy.hashIdentifier(sourcePrefix + rawSession + ":" + (nativeTurn ?? UUID().uuidString))
                session.nativeTurn = nativeTurn; session.active = true; session.tokens = 0; session.pendingPermission = nil
            }
            if let nativeTurn { session.nativeTurn = nativeTurn }
        } else if !session.active && ["PreToolUse", "PermissionRequest"].contains(name) {
            // A late tool event for a finished native turn cannot create another card.
            if let nativeTurn, nativeTurn == session.nativeTurn { return }
            session.turn = CodexActivityPrivacy.hashIdentifier(sourcePrefix + rawSession + ":" + (nativeTurn ?? UUID().uuidString))
            session.nativeTurn = nativeTurn; session.active = true; session.tokens = 0; session.pendingPermission = nil
        }
        island.model.setProvider(provider, for: key)
        sessions[key] = session
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
            } else if name == "PermissionResult" {
                call = call ?? session.pendingPermission
                sessions[key]?.pendingPermission = nil
            }
            let activity = CodexActivityEvent(event: event, sessionHash: key, turnHash: turn,
                toolCategory: category(tool), source: .hook, turnCompletionStatus: completion,
                toolCallHash: call, toolName: tool)
            if session.parent != nil { island.model.receiveSubagentActivity(activity) }
            else { island.model.receiveLegacy(activity) }
            publishMetadata(key)
            if name == "PreToolUse", let tool,
               let data = try? JSONSerialization.data(withJSONObject: ["type": "tool", "id": call ?? UUID().uuidString, "name": tool, "text": ""]) {
                let content = CodexLocalPublicContent(publicSessionHash: key, turnHash: turn, data: data, occurredAt: Date())
                island.model.receiveLocalContent(content)
            }
            if ["PostToolUse", "PostToolUseFailure"].contains(name), let call,
               let data = try? JSONSerialization.data(withJSONObject: ["type": "output", "id": call, "text": ""]) {
                island.model.receiveLocalContent(.init(publicSessionHash: key, turnHash: turn, data: data, occurredAt: Date()))
            }
            if completion != nil { sessions[key]?.active = false }
        }
        // DSH's epoch/sequence above deduplicates usage before aggregation.
        if name == "Usage", provider == .dsh, session.active, session.parent == nil,
           payload["source_sequence"] is Int, let count = payload["tokens"] as? Int64, (0...1_000_000_000).contains(count) {
            session.tokens = min(session.tokens + count, 1_000_000_000_000)
            sessions[key] = session
            island.model.receiveToken(.init(sessionHash: key, turnHash: turn, cumulativeTotalTokens: session.tokens,
                                            lastReportedTotalTokens: count, directTurnTotalTokens: session.tokens))
        }
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
        if name.contains("bash") || name.contains("shell") || name.contains("terminal") { return .shell }
        if name.contains("edit") || name.contains("write") || name.contains("patch") { return .fileEdit }
        if name.contains("agent") { return .subagent }
        return .localTool
    }
}
