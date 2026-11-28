import Foundation
import QuotaViewCore
#if SWIFT_PACKAGE
import QuotaViewActivityHookSupport
#endif

/// Common hook session, turn and observation ingress. Interactive requests are
/// consumed by their source adapter before reaching this observation path.
@MainActor
final class GenericHookAgentAdapter {
    private let context: NativeAgentHookContext
    private let devin: DevinAgentAdapter?
    private let antigravity: AntigravityAgentAdapter?
    private let openCode: OpenCodeInteractionAdapter?
    private let dsh: DSHInteractionAdapter?
    private var rateLogTask: Task<Void, Never>?

    init(context: NativeAgentHookContext, devin: DevinAgentAdapter?, antigravity: AntigravityAgentAdapter?, openCode: OpenCodeInteractionAdapter?, dsh: DSHInteractionAdapter?) {
        self.context = context
        self.devin = devin
        self.antigravity = antigravity
        self.openCode = openCode
        self.dsh = dsh
    }

    func stop() {
        rateLogTask?.cancel()
        rateLogTask = nil
    }

    private func removeSession(_ key: String) {
        context.sessions.removeValue(forKey: key)
        devin?.removeSession(key)
        antigravity?.removeSession(key)
    }

    func receive(_ message: ClaudeCodeBridgeMessage, homes: [URL], connected: () -> Void) {
        defer { antigravity?.refreshApprovalMonitor() }
        // Observation-only ingress never holds an interactive connection.
        if message.awaitsDecision { context.bridge.resolve(eventID: message.eventID, decision: nil) }
        guard context.running, context.enabled, context.listening,
              let payload = (try? JSONSerialization.jsonObject(with: message.payload)) as? [String: Any],
              let sourceSession = payload["session_id"] as? String, !sourceSession.isEmpty, sourceSession.utf8.count <= 256,
              let eventName = payload["hook_event_name"] as? String else { return }
        // Older helpers may still report ask_permission before the client evaluates it.
        let name = context.provider == .antigravity && eventName == "PermissionRequest" ? "PreToolUse" : eventName
        let accepted = ["SessionStart", "SessionEnd", "UserPromptSubmit", "TurnStarted", "PreToolUse", "PostToolUse", "PostToolUseFailure",
                        "PermissionRequest", "PermissionResult", "PreCompact", "PostCompact", "Stop", "StopFailure", "Interrupt", "Usage", "Metadata", "ModelRequest"]
        guard accepted.contains(name) else { return }
        var sourcePrefix = context.provider.rawValue + ":"
        if let dsh {
            guard let prefix = dsh.sourcePrefix(namespace: payload["source_namespace"] as? String) else { return }
            sourcePrefix = prefix
        }
        connected()
        // Kimi identifies its primary agent as "main". Separate any explicitly
        // identified child so its Stop cannot complete the parent's task.
        let child = context.provider == .kimiCode ? (payload["agent_id"] as? String).flatMap { $0.isEmpty || $0 == "main" ? nil : $0 } : nil
        let rawSession = child.map { sourceSession + ":agent:" + $0 } ?? sourceSession
        let threadID = sourcePrefix + (context.provider == .antigravity ? rawSession.lowercased() : rawSession)
        let key = CodexActivityPrivacy.hashIdentifier(threadID)
        if context.sessions[key] == nil, context.sessions.count >= 512 {
            guard let oldest = context.sessions.filter({ !$0.value.active }).min(by: { $0.value.updated < $1.value.updated })?.key else { return }
            if let id = context.sessions[oldest]?.terminalBinding { ClaudeTerminalNavigation.bind(nil, to: id) }
            removeSession(oldest)
        }
        var session = context.sessions[key] ?? NativeAgentHookContext.Session()
        if context.provider == .dsh, let epoch = payload["source_epoch"] as? String, let old = session.epoch, old != epoch {
            dsh?.releaseRequests(in: key)
        }
        let nativeTurn = payload["turn_id"] as? String
        // Ignore stale observations before they can change current metadata.
        if context.provider.isDevin, !["SessionStart", "SessionEnd", "UserPromptSubmit", "TurnStarted"].contains(name),
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
        if context.provider != .antigravity, let parent = child == nil ? payload["parent_session_id"] as? String : sourceSession,
           let identity = CodexActivitySubagentIdentity(threadID: sourcePrefix + rawSession,
               parentThreadID: sourcePrefix + parent, title: session.title) {
            session.parent = parent
            context.island.model.setProvider(context.provider, for: key)
            context.island.model.receiveSubagentIdentity(identity)
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
            session.rateLedger = .init(); session.rateRequestStart = nil; session.rateRequestID = nil
            session.rateLogPosition = nil; session.rateLogPath = nil
            session.turnStartedAt = (payload["rate_event_ms"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date(); session.rateCompletedAt = nil
        }
        if [IslandAgentProvider.kimiCode, .copilotCLI].contains(context.provider),
           let path = payload["rate_log_path"] as? String, path.hasPrefix("/"), path.utf8.count <= 4096 {
            if session.rateLogPath != path { session.rateLogPosition = nil }
            session.rateLogPath = path
            if session.rateLogPosition == nil { session.rateLogPosition = 0 }
            if startedTurn { session.rateLogPosition = AgentRateObservation.integer(payload["rate_log_position"]) ?? 0 }
        }
        antigravity?.prepareSession(key, source: sourceSession, name: name, payload: payload, startedTurn: startedTurn, session: &session)
        if name == "ModelRequest", context.provider == .geminiCLI, session.active {
            session.rateRequestStart = (payload["rate_event_ms"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
            session.rateRequestID = UUID().uuidString
        }
        devin?.prepareSession(key, sourceSession: sourceSession, name: name, payload: payload, startedTurn: startedTurn)
        if [.kimiCode, .geminiCLI, .copilotCLI, .devinCLI].contains(context.provider), session.parent == nil {
            // Only the local helper supplies this descriptor. Each surface gets
            // a private binding even when two providers use the same session ID.
            if !context.preferences.codexIslandPrivacy, name != "SessionEnd",
               let field = payload["terminal_host"] as? [String: Any],
               let data = try? JSONSerialization.data(withJSONObject: field), data.count <= 2048,
               let terminal = try? JSONDecoder().decode(ClaudeConversationHost.Terminal.self, from: data),
               terminal.agentProvider == context.provider.rawValue, terminal.valid {
                let id = session.terminalBinding ?? UUID()
                ClaudeTerminalNavigation.bind(terminal, to: id)
                session.terminalBinding = id
                session.conversation = .agentTerminal(context.provider, id)
            } else if let id = session.terminalBinding {
                ClaudeTerminalNavigation.bind(nil, to: id)
                session.terminalBinding = nil
                session.conversation = nil
            }
        }
        if !context.preferences.codexIslandPrivacy, session.parent == nil {
            if let conversation = devin?.desktopConversation(key, source: sourceSession) {
                session.conversation = conversation
            } else if context.provider == .cursor, let id = UUID(uuidString: sourceSession) {
                session.conversation = .cursor(id)
            } else if let antigravity, let id = UUID(uuidString: sourceSession) {
                session.conversation = antigravity.conversation(key, id: id)
            } else if context.provider == .dsh {
                session.conversation = payload["official_desktop_navigation"] as? Bool == true && IslandConversationTarget.isSessionID(sourceSession)
                    ? .dsh(sourceSession) : nil
            }
        }
        context.island.model.setProvider(context.provider, for: key)
        context.sessions[key] = session
        devin?.sessionDidChange(key, turn: session.turn, name: name, payload: payload)
        openCode?.sessionDidChange(key, ended: ["Stop", "StopFailure", "Interrupt", "SessionEnd"].contains(name))
        if context.provider == .dsh, session.title == nil || startedTurn || name == "Stop" {
            refreshDSHTitle(key: key, sourceID: sourceSession, namespace: payload["source_namespace"] as? String, homes: homes)
        }
        if context.provider == .dsh && (startedTurn || ["SessionEnd", "Stop", "StopFailure", "Interrupt"].contains(name)) {
            dsh?.releaseRequests(in: key)
        }
        if context.provider == .antigravity, let turn = session.turn, session.active,
           ["TurnStarted", "Usage", "Stop", "Interrupt", "StopFailure"].contains(name) {
            antigravity?.refreshDetail(key: key, source: sourceSession, turn: turn, session: session, event: name)
        }
        if context.provider == .antigravity, name == "TurnStarted", !startedTurn { context.publishMetadata(key); return }
        if name == "SessionStart" || name == "Metadata" || name == "ModelRequest" { context.publishMetadata(key); return }
        if name == "SessionEnd" {
            if let turn = session.turn { context.island.model.withdrawHookExecution(session: key, turn: turn) }
            if session.parent != nil { context.island.model.withdrawSubagentObservation(for: key) }
            removeSession(key)
            return
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
                context.sessions[key]?.pendingPermission = call
                context.sessions[key]?.pendingPermissionTool = tool
            } else if name == "PermissionResult" || (context.provider.isDevin && ["PostToolUse", "PostToolUseFailure"].contains(name)
                && session.pendingPermissionTool == tool && (call == nil || call == session.pendingPermission)) {
                call = call ?? session.pendingPermission
                context.sessions[key]?.pendingPermission = nil
                context.sessions[key]?.pendingPermissionTool = nil
            }
            let activity = CodexActivityEvent(event: event, sessionHash: key, turnHash: turn,
                toolCategory: category(tool), source: .hook, turnCompletionStatus: completion,
                toolCallHash: call, toolName: tool)
            if session.parent != nil { context.island.model.receiveSubagentActivity(activity) }
            else {
                context.island.model.receiveLegacy(activity)
                context.island.model.setConversation(session.conversation, for: key, provider: context.provider)
            }
            context.publishMetadata(key)
            if name == "PreToolUse", let tool, (!context.provider.usesExternalHooks || call != nil),
               let data = try? JSONSerialization.data(withJSONObject: ["type": "tool", "id": call ?? UUID().uuidString, "name": tool, "text": ""]) {
                let content = CodexLocalPublicContent(publicSessionHash: key, turnHash: turn, data: data, occurredAt: Date())
                context.island.model.receiveLocalContent(content)
            }
            if ["PostToolUse", "PostToolUseFailure"].contains(name), let call,
               let data = try? JSONSerialization.data(withJSONObject: ["type": "output", "id": call, "text": ""]) {
                context.island.model.receiveLocalContent(.init(publicSessionHash: key, turnHash: turn, data: data, occurredAt: Date()))
            }
            if completion != nil {
                if context.provider == .dsh, completion == .completed, session.parent == nil,
                   let answer = payload["final_response"] as? [String: Any],
                   let text = answer["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   text.utf8.count <= 65_536, let id = answer["id"] as? String, !id.isEmpty, id.utf8.count <= 128,
                   let data = try? JSONSerialization.data(withJSONObject: ["type": "message", "id": "dsh-final:" + id,
                       "channel": "final", "text": text, "sourceTruncated": answer["truncated"] as? Bool ?? false]) {
                    context.island.model.receiveLocalContent(.init(publicSessionHash: key, turnHash: turn, data: data, occurredAt: Date()))
                }
                context.sessions[key]?.active = false
                context.sessions[key]?.rateCompletedAt = Date()
                devin?.completed(key)
            }
        }
        antigravity?.observeUsage(key: key, sourceSession: sourceSession, turn: turn, session: session, name: name, payload: payload)
        // DSH's epoch/sequence above deduplicates usage before aggregation.
        if name == "Usage", context.provider == .dsh, session.active, session.parent == nil,
           payload["source_sequence"] is Int, let count = payload["tokens"] as? Int64, (0...1_000_000_000).contains(count) {
            session.tokens = min(session.tokens + count, 1_000_000_000_000)
            context.sessions[key] = session
            context.island.model.receiveToken(.init(sessionHash: key, turnHash: turn, cumulativeTotalTokens: session.tokens,
                                            lastReportedTotalTokens: count, directTurnTotalTokens: session.tokens))
        }
        if name == "Usage", session.parent == nil, let output = AgentRateObservation.integer(payload["output_tokens"]) {
            let start = (payload["rate_start_ms"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
                ?? (context.provider == .geminiCLI ? session.rateRequestStart : nil)
            let end = ((payload["rate_end_ms"] ?? payload["rate_event_ms"]) as? Double)
                .map { Date(timeIntervalSince1970: $0 / 1000) }
            let id = context.provider == .geminiCLI ? session.rateRequestID : payload["usage_id"] as? String
            if let start, let end, let id,
               let rate = AgentRateObservation(id: id, output: output, durationMS: end.timeIntervalSince(start) * 1000, end: end) {
                context.receiveRates([rate], key: key, turn: turn)
            }
        }
        devin?.refreshMetadata()
        if context.provider == .kimiCode || context.provider == .copilotCLI { refreshRateLogs() }
    }

    private struct RateLogRead: Sendable {
        let key: String; let turn: String; let path: String; let position: Int64; let since: Date
    }
    private func refreshRateLogs() {
        guard rateLogTask == nil else { return }
        let current = context.revision, source = context.provider.rawValue
        rateLogTask = Task { [weak self] in
            defer { if self?.context.revision == current { self?.rateLogTask = nil } }
            while !Task.isCancelled {
                guard let self, context.running, context.enabled, context.revision == current else { return }
                let requests = context.sessions.compactMap { key, s -> RateLogRead? in
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
                guard !Task.isCancelled, context.revision == current, context.enabled else { return }
                for (request, rates) in result {
                    guard let session = context.sessions[request.key], session.turn == request.turn,
                          session.rateLogPath == request.path, session.rateLogPosition == request.position else { continue }
                    context.receiveRates(rates, key: request.key, turn: request.turn)
                }
                do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
            }
        }
    }
    private func refreshDSHTitle(key: String, sourceID: String, namespace: String?, homes: [URL]) {
        guard let session = context.sessions[key], let turn = session.turn else { return }
        let current = context.revision
        dsh?.readTitle(for: key, sourceID: sourceID, namespace: namespace, homes: homes) { [weak self] title in
            guard let self, context.enabled, context.revision == current, context.sessions[key]?.turn == turn,
                  context.sessions[key]?.epoch == session.epoch, context.sessions[key]?.title == session.title else { return }
            context.sessions[key]?.title = title
            context.publishMetadata(key)
        }
    }

    private func category(_ name: String?) -> CodexActivityToolCategory {
        let name = name?.lowercased() ?? ""
        if (name == "exec" || name.contains("bash")) || name.contains("shell") || name.contains("terminal") { return .shell }
        if name.contains("edit") || name.contains("write") || name.contains("patch") { return .fileEdit }
        if name.contains("agent") { return .subagent }
        return .localTool
    }
}
