import Foundation
import QuotaViewCore
#if SWIFT_PACKAGE
import QuotaViewActivityHookSupport
#endif

/// Each Devin surface has its own decision channel and local usage cursor.
@MainActor
final class DevinAgentAdapter: NativeHookInteractionAdapter {
    private let context: NativeAgentHookContext
    private var metadataTask: Task<Void, Never>?
    private struct Metadata {
        var store: DevinSessionUsage.Store?
        var sourceSession: String?
        var startPosition: Int64?
        var completedAt: Date?
        var hasUsage = false
    }
    private var metadata: [String: Metadata] = [:]
    private struct Permission {
        let wire: IslandCodexApprovalRequest
        let call: String?
        var dispatched = false
    }
    private var permissions: [String: Permission] = [:]
    var interactive: Bool {
        context.provider.isDevin && (context.provider == .devinCLI ? context.preferences.devinCLIApprovals : context.preferences.devinDesktopApprovals)
            && context.preferences.codexActivityIslandEnabled && !context.preferences.codexIslandPrivacy
    }

    init(context hookContext: NativeAgentHookContext) {
        self.context = hookContext
        context.island.model.devinCapabilities[context.provider] = { [weak self] wire in
            guard let self, context.running, context.listening, context.enabled, interactive, wire.devinProvider == context.provider,
                  let held = permissions[wire.rpcID.text], !held.dispatched, held.wire == wire,
                  let session = context.sessions[wire.threadID] else { return false }
            return session.active && session.turn == wire.turnID
        }
        context.island.model.devinResponders[context.provider] = { [weak self] wire, result in
            guard let self, context.island.model.devinCapabilities[context.provider]?(wire) == true, wire.permits(result),
                  ["accept", "decline"].contains(result["decision"].text) else { throw CancellationError() }
            permissions[wire.rpcID.text]?.dispatched = true
            context.bridge.resolve(eventID: String(wire.rpcID.text.dropFirst(context.provider.rawValue.count + 1)),
                decision: ["decision": result["decision"].text == "accept" ? "approve" : "block"])
        }
    }

    func handle(_ message: ClaudeCodeBridgeMessage) -> Bool {
        if !message.awaitsDecision,
           let payload = (try? JSONSerialization.jsonObject(with: message.payload)) as? [String: String],
           payload["hook_event_name"] == "DevinDecisionReturned", let event = payload["request_id"] {
            let id = context.provider.rawValue + ":" + event
            if let held = permissions[id], held.dispatched { closePermission(id) }
            return true
        }
        if message.awaitsDecision {
            if let payload = (try? JSONSerialization.jsonObject(with: message.payload)) as? [String: Any],
               admitPermission(message, payload: payload) { return true }
            context.bridge.resolve(eventID: message.eventID, decision: nil)
            return true
        }
        return false
    }

    func disconnected(eventID: String) {
        closePermission(context.provider.rawValue + ":" + eventID)
    }

    func closeAll() {
        for id in Array(permissions.keys) { closePermission(id) }
    }

    func stop() {
        closeAll()
        metadataTask?.cancel()
        metadataTask = nil
        metadata.removeAll()
    }

    func removeSession(_ key: String) {
        metadata.removeValue(forKey: key)
    }

    func prepareSession(_ key: String, sourceSession: String, name: String, payload: [String: Any], startedTurn: Bool) {
        var state = metadata[key] ?? Metadata()
        if startedTurn {
            state.startPosition = name == "UserPromptSubmit" ? payload["devin_start_position"] as? Int64 : nil
            state.completedAt = nil
            state.hasUsage = false
        }
        if let directory = payload["devin_storage_directory"] as? String,
           let files = payload["devin_storage_files"] as? Bool,
           let store = DevinSessionUsage.Store(directory: directory, files: files) {
            // A changed store cannot reuse a position from the old one.
            if state.store != nil && state.store != store && !startedTurn { state.startPosition = nil }
            state.store = store; state.sourceSession = sourceSession
        }
        metadata[key] = state
    }

    func desktopConversation(_ key: String, source: String) -> IslandConversationTarget? {
        guard context.provider == .devinDesktop, metadata[key]?.store != nil, IslandConversationTarget.isSessionID(source) else { return nil }
        return .devin(source)
    }

    func sessionDidChange(_ key: String, turn: String?, name: String, payload: [String: Any]) {
        for (id, held) in permissions where held.wire.threadID == key {
            let post = ["PostToolUse", "PostToolUseFailure"].contains(name)
            let call = (payload["tool_use_id"] ?? payload["tool_call_id"]) as? String
            if held.wire.turnID != turn || ["Stop", "SessionEnd", "StopFailure", "Interrupt"].contains(name)
                || (post && held.call != nil && held.call == call && payload["tool_name"] as? String == "exec") { closePermission(id) }
        }
    }

    func completed(_ key: String) {
        metadata[key]?.completedAt = Date()
    }

    private func closePermission(_ id: String) {
        guard let held = permissions.removeValue(forKey: id) else { return }
        if !held.dispatched {
            context.bridge.resolve(eventID: String(id.dropFirst(context.provider.rawValue.count + 1)), decision: nil)
        }
        context.island.model.resolveLocalHookRequest(sessionKey: held.wire.threadID, rpcID: held.wire.rpcID)
    }

    private func admitPermission(_ message: ClaudeCodeBridgeMessage, payload: [String: Any]) -> Bool {
        guard context.running, context.enabled, context.listening, interactive, message.awaitsDecision,
              UUID(uuidString: message.eventID) != nil, permissions.count < 32,
              payload["hook_event_name"] as? String == "PermissionRequest", payload["tool_name"] as? String == "exec",
              let rawSession = payload["session_id"] as? String, let nativeTurn = payload["turn_id"] as? String,
              !nativeTurn.isEmpty, let input = payload["tool_input"] as? [String: Any],
              let command = input["command"] as? String, !command.isEmpty,
              let cwd = payload["cwd"] as? String, !cwd.isEmpty, cwd.utf8.count <= 4096,
              let data = try? JSONSerialization.data(withJSONObject: input, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              data.count <= 48_000 else { return false }
        let key = CodexActivityPrivacy.hashIdentifier(context.provider.rawValue + ":" + rawSession)
        let id = context.provider.rawValue + ":" + message.eventID
        guard let session = context.sessions[key], session.active, session.nativeTurn == nativeTurn, session.parent == nil,
              let turn = session.turn, !permissions.values.contains(where: { $0.wire.threadID == key }) else { return false }
        let call = (payload["tool_use_id"] ?? payload["tool_call_id"]) as? String
        let params: [String: Any] = ["devinProvider": context.provider.rawValue, "threadId": key, "turnId": turn, "itemId": call ?? id,
            "toolName": "exec", "command": String(decoding: data, as: UTF8.self), "cwd": cwd,
            "availableDecisions": ["accept", "decline"]]
        guard let raw = try? JSONSerialization.data(withJSONObject: ["method": "item/commandExecution/requestApproval",
            "id": id, "params": params]), let wire = try? IslandCodexApprovalRequest(data: raw) else { return false }
        permissions[id] = .init(wire: wire, call: call)
        let callHash = CodexActivityPrivacy.hashIdentifier(context.provider.rawValue + ":" + rawSession + ":" + (call ?? id))
        guard context.island.model.observeNativeToolRequest(wire, sessionKey: key, turnKey: turn, callHash: callHash) else {
            permissions.removeValue(forKey: id)
            return false
        }
        return true
    }

    private struct DevinRead: Sendable {
        let key: String
        let sourceSession: String
        let turn: String
        let store: DevinSessionUsage.Store
        let start: Int64?
    }

    func refreshMetadata() {
        guard metadataTask == nil else { return }
        let currentRevision = context.revision
        metadataTask = Task { [weak self] in
            defer { if self?.context.revision == currentRevision { self?.metadataTask = nil } }
            while !Task.isCancelled {
                guard let self, context.running, context.enabled, context.revision == currentRevision else { return }
                let requests = context.sessions.compactMap { key, value -> DevinRead? in
                    guard let state = self.metadata[key], value.active || (state.completedAt.map { Date().timeIntervalSince($0) < 10 } ?? false),
                          let turn = value.turn, let store = state.store, let source = state.sourceSession else { return nil }
                    return DevinRead(key: key, sourceSession: source, turn: turn, store: store, start: state.startPosition)
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
                guard !Task.isCancelled, context.running, context.enabled, context.revision == currentRevision else { return }
                for (request, snapshot) in snapshots {
                    guard let snapshot, var session = context.sessions[request.key], session.turn == request.turn,
                          let state = metadata[request.key], state.store == request.store, state.startPosition == request.start else { continue }
                    if let model = snapshot.model, model != session.model {
                        session.model = model
                        context.sessions[request.key] = session
                        context.publishMetadata(request.key)
                    }
                    if request.start != nil {
                        context.receiveRates(snapshot.rates, key: request.key, turn: request.turn)
                    }
                    if let tokens = snapshot.tokens, request.start != nil, tokens >= session.tokens,
                       !state.hasUsage || tokens != session.tokens {
                        context.sessions[request.key]?.tokens = tokens
                        metadata[request.key]?.hasUsage = true
                        context.island.model.receiveToken(.init(sessionHash: request.key, turnHash: request.turn,
                            cumulativeTotalTokens: tokens, lastReportedTotalTokens: tokens, directTurnTotalTokens: tokens))
                    }
                }
                do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
            }
        }
    }
}
