import Foundation
import QuotaViewCore

/// Holds a request only while its originating OpenCode client, session and turn can answer it.
@MainActor
final class OpenCodeInteractionAdapter: NativeHookInteractionAdapter {
    struct Turn: Equatable {
        let id: String
        let nativeID: String
        let epoch: String
    }

    private struct Request {
        let wire: IslandCodexApprovalRequest
        let eventID: String
        let turn: Turn
        enum Phase {
            case waiting
            case submitted(receiptTimeout: Task<Void, Never>)
        }
        var phase = Phase.waiting
    }

    private let model: IslandLiveStore
    private let bridge: ClaudeCodeBridge
    private let currentTurn: (String) -> Turn?
    private var requests: [String: Request] = [:]

    init(model: IslandLiveStore, bridge: ClaudeCodeBridge, currentTurn: @escaping (String) -> Turn?) {
        self.model = model
        self.bridge = bridge
        self.currentTurn = currentTurn
        model.openCodeResponseCapability = { [weak self] wire in
            self?.waitingRequest(for: wire) != nil
        }
        model.openCodeRespond = { [weak self] wire, result in
            guard let self else { throw CancellationError() }
            try respond(to: wire, with: result)
        }
    }

    private func waitingRequest(for wire: IslandCodexApprovalRequest) -> Request? {
        guard let request = requests[wire.rpcID.text], case .waiting = request.phase,
              request.wire.raw == wire.raw, currentTurn(wire.threadID) == request.turn else { return nil }
        return request
    }

    private func respond(to wire: IslandCodexApprovalRequest, with result: IslandApprovalJSON) throws {
        guard let request = waitingRequest(for: wire), wire.permits(result) else { throw CancellationError() }
        let decision: [String: Any]
        if wire.kind == .questions {
            decision = ["answers": wire.questions.map { result["answers"][$0.id]["answers"].array.map(\.text) }]
        } else {
            switch result["decision"].text {
            case "accept": decision = ["reply": "once"]
            case "decline": decision = ["reply": "reject"]
            default: throw CocoaError(.coderInvalidValue)
            }
        }

        let timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            self?.model.markOpenCodeDeliveryUnknown(wire)
        }
        requests[wire.rpcID.text]?.phase = .submitted(receiptTimeout: timeout)
        bridge.resolve(eventID: request.eventID, decision: decision)
    }

    /// Returns true for OpenCode interaction messages. Ordinary hook events continue through the runtime.
    func handle(_ message: ClaudeCodeBridgeMessage) -> Bool {
        guard let payload = (try? JSONSerialization.jsonObject(with: message.payload)) as? [String: Any],
              let name = payload["hook_event_name"] as? String else { return false }
        switch name {
        case "OpenCodeInteraction":
            if message.awaitsDecision && !admit(message, payload: payload) {
                bridge.resolve(eventID: message.eventID, decision: nil)
            }
        case "OpenCodeReleased", "OpenCodeDeliveryFailed":
            if let eventID = payload["interaction_id"] as? String,
               let request = requests["openCode:" + eventID],
               let source = payload["session_id"] as? String,
               request.wire.threadID == CodexActivityPrivacy.hashIdentifier("openCode:" + source),
               request.turn.epoch == payload["source_epoch"] as? String,
               request.turn.nativeID == payload["turn_id"] as? String {
                if name == "OpenCodeReleased" {
                    close(request)
                } else if case .submitted = request.phase {
                    model.markOpenCodeDeliveryUnknown(request.wire)
                }
            }
            if message.awaitsDecision { bridge.resolve(eventID: message.eventID, decision: nil) }
        default: return false
        }
        return true
    }

    private func admit(_ message: ClaudeCodeBridgeMessage, payload: [String: Any]) -> Bool {
        let eventID = message.eventID
        let rpcID = "openCode:" + eventID
        guard message.payload.count <= 65_536, requests.count < 32, requests[rpcID] == nil,
              UUID(uuidString: eventID) != nil, eventID == payload["interaction_id"] as? String,
              let source = payload["session_id"] as? String, let nativeID = payload["native_id"] as? String,
              !nativeID.isEmpty, nativeID.utf8.count <= 128 else { return false }
        let key = CodexActivityPrivacy.hashIdentifier("openCode:" + source)
        guard let turn = currentTurn(key), turn.nativeID == payload["turn_id"] as? String,
              turn.epoch == payload["source_epoch"] as? String,
              !requests.values.contains(where: { $0.wire.threadID == key && $0.wire.params["itemId"].text == nativeID })
        else { return false }

        var params: [String: Any] = ["openCode": true, "threadId": key, "turnId": turn.id, "itemId": nativeID]
        let method: String
        switch payload["interaction_type"] as? String {
        case "question":
            guard let questions = payload["questions"] as? [[String: Any]] else { return false }
            params["questions"] = questions
            method = "item/tool/requestUserInput"
        case "permission":
            guard let command = payload["command"] as? String, !command.isEmpty else { return false }
            params["command"] = command
            params["availableDecisions"] = ["accept", "decline"]
            method = "item/commandExecution/requestApproval"
        default: return false
        }
        guard let data = try? JSONSerialization.data(withJSONObject: ["id": rpcID, "method": method, "params": params]),
              let wire = try? IslandCodexApprovalRequest(data: data), wire.kind != .questions || wire.supportedQuestions
        else { return false }

        requests[rpcID] = Request(wire: wire, eventID: eventID, turn: turn)
        guard model.observeNativeToolRequest(wire, sessionKey: key, turnKey: turn.id,
            callHash: CodexActivityPrivacy.hashIdentifier("openCode:" + source + ":" + nativeID)) else {
            requests.removeValue(forKey: rpcID)
            return false
        }
        bridge.admit(eventID: eventID)
        return true
    }

    func sessionDidChange(_ key: String, ended: Bool) {
        let turn = currentTurn(key)
        for request in requests.values where request.wire.threadID == key && (ended || request.turn != turn) {
            close(request)
        }
    }

    func disconnected(eventID: String) {
        if let request = requests["openCode:" + eventID] { close(request) }
    }

    func closeAll() {
        for request in requests.values { close(request) }
    }

    private func close(_ request: Request) {
        requests.removeValue(forKey: request.wire.rpcID.text)
        switch request.phase {
        case .waiting: bridge.resolve(eventID: request.eventID, decision: nil)
        case .submitted(let timeout): timeout.cancel()
        }
        model.resolveLocalHookRequest(sessionKey: request.wire.threadID, rpcID: request.wire.rpcID)
    }
}
