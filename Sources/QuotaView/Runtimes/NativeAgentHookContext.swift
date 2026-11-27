import Foundation
import QuotaViewCore
#if SWIFT_PACKAGE
import QuotaViewActivityHookSupport
#endif

/// A source that owns interactive requests on its hook connection.
@MainActor
protocol NativeHookInteractionAdapter: AnyObject {
    func handle(_ message: ClaudeCodeBridgeMessage) -> Bool
    func disconnected(eventID: String)
}

/// Shared ingress generation and the live hook turns observed by the island.
/// Source-specific requests, readers and polling tasks belong to their adapters.
@MainActor
final class NativeAgentHookContext {
    let provider: IslandAgentProvider
    let preferences: AppPreferences
    let island: IslandSession
    let installer: NativeAgentInstaller
    let bridge: ClaudeCodeBridge
    var revision = UUID()
    var running = false
    var listening = false

    init(provider: IslandAgentProvider, preferences: AppPreferences, island: IslandSession, installer: NativeAgentInstaller, bridge: ClaudeCodeBridge) {
        self.provider = provider
        self.preferences = preferences
        self.island = island
        self.installer = installer
        self.bridge = bridge
    }

    struct Session {
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
        var rateRequestStart: Date?
        var rateRequestID: String?
        var rateLogPath: String?
        var rateLogPosition: Int64?
        var turnStartedAt = Date()
        var rateCompletedAt: Date?
        var tokens: Int64 = 0
        var sequence: Int = -1
        var epoch: String?
        var updated = Date()
    }
    var sessions: [String: Session] = [:]

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

    func receiveRates(_ rates: [AgentRateObservation], key: String, turn: String) {
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

    func publishMetadata(_ key: String) {
        guard let session = sessions[key], let turn = session.turn else { return }
        island.model.setTitle(session.title ?? provider.displayName + " " + preferences.copy.text("任务", "task"), for: key, source: .threadTitle)
        guard let model = session.model,
              let data = try? JSONSerialization.data(withJSONObject: ["type": "metadata", "model": model, "effort": ""]) else { return }
        let content = CodexLocalPublicContent(publicSessionHash: key, turnHash: turn, data: data, occurredAt: Date())
        island.model.receiveLocalContent(content)
    }
}
