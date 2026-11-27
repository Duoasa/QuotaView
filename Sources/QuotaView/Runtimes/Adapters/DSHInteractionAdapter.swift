import Foundation
import QuotaViewCore

/// Owns DSH requests and title reads for one runtime. The runtime supplies the live turn.
@MainActor
final class DSHInteractionAdapter: NativeHookInteractionAdapter {
    struct Turn {
        let id: String
        let nativeID: String?
        let epoch: String?
        let isChild: Bool
    }

    private struct Request {
        let session: String
        let turn: String
        let epoch: String
        let auditID: String
        let wire: IslandCodexApprovalRequest
        var rpcID: IslandApprovalJSON { wire.rpcID }
        var awaitsDecision = true
    }

    private let model: IslandLiveStore
    private let bridge: ClaudeCodeBridge
    private let defaultNamespace: String
    private let isInteractive: () -> Bool
    private let currentTurn: (String) -> Turn?
    private var requests: [String: Request] = [:]
    private var titleTasks: [String: Task<Void, Never>] = [:]
    private var titleReadAt: [String: Date] = [:]

    init(model: IslandLiveStore, bridge: ClaudeCodeBridge, home: URL,
         isInteractive: @escaping () -> Bool, currentTurn: @escaping (String) -> Turn?) {
        self.model = model
        self.bridge = bridge
        self.defaultNamespace = Self.namespace(for: home)
        self.isInteractive = isInteractive
        self.currentTurn = currentTurn
        model.dshResponseCapability = { [weak self] wire in self?.canRespond(to: wire) == true }
        model.dshRespond = { [weak self] wire, result in
            guard let self else { throw CancellationError() }
            try respond(wire, result: result)
        }
    }

    private static func namespace(for home: URL) -> String {
        CodexActivityPrivacy.hashIdentifier(home.resolvingSymlinksInPath().standardizedFileURL.path)
    }

    func sourcePrefix(namespace: String?) -> String? {
        let namespace = namespace ?? defaultNamespace
        guard namespace.utf8.count == 64, namespace.allSatisfy({ "0123456789abcdef".contains($0) }) else { return nil }
        return "dsh:" + namespace + ":"
    }

    private func canRespond(to wire: IslandCodexApprovalRequest) -> Bool {
        guard isInteractive(), let id = DSHApproval.eventID(of: wire),
              let request = requests[id], request.awaitsDecision, request.wire == wire,
              let turn = currentTurn(request.session) else { return false }
        return turn.id == request.turn && turn.epoch == request.epoch
    }

    func handle(_ message: ClaudeCodeBridgeMessage) -> Bool {
        guard let payload = (try? JSONSerialization.jsonObject(with: message.payload)) as? [String: Any],
              let name = payload["hook_event_name"] as? String,
              name.hasPrefix("DSHApproval") || name.hasPrefix("DSHQuestion") else { return false }
        if !receive(message, payload: payload, name: name), message.awaitsDecision {
            bridge.resolve(eventID: message.eventID, decision: nil)
        }
        return true
    }

    private func receive(_ message: ClaudeCodeBridgeMessage, payload: [String: Any], name: String) -> Bool {
        guard let source = payload["session_id"] as? String, !source.isEmpty, source.utf8.count <= 256,
              let namespace = payload["source_namespace"] as? String, let sourcePrefix = sourcePrefix(namespace: namespace),
              let epoch = payload["source_epoch"] as? String, !epoch.isEmpty, epoch.utf8.count <= 128,
              let nativeTurn = payload["turn_id"] as? String,
              let id = payload["request_id"] as? String, !id.isEmpty, id.utf8.count <= 128,
              let auditID = payload["approval_id"] as? String, !auditID.isEmpty, auditID.utf8.count <= 128 else { return false }
        let prefix = sourcePrefix + source
        let key = CodexActivityPrivacy.hashIdentifier(prefix)
        guard let session = currentTurn(key), !session.isChild,
              session.epoch == epoch, session.nativeID == nativeTurn else { return false }
        let turn = session.id
        if name == "DSHApprovalRequest" || name == "DSHQuestionRequest" {
            guard message.awaitsDecision, message.eventID == id, isInteractive(),
                  requests[id] == nil, requests.count < 32,
                  !requests.values.contains(where: { $0.session == key && $0.auditID == auditID }),
                  let call = payload["tool_use_id"] as? String, !call.isEmpty, call.utf8.count <= 256,
                  let wire = try? DSHApproval.request(eventID: id, sessionKey: key, turnKey: turn, payload: payload) else { return false }
            requests[id] = .init(session: key, turn: turn, epoch: epoch, auditID: auditID, wire: wire)
            guard model.observeNativeToolRequest(wire, sessionKey: key, turnKey: turn,
                    callHash: CodexActivityPrivacy.hashIdentifier(prefix + ":" + call)) else {
                requests.removeValue(forKey: id); return false
            }
            bridge.admit(eventID: id)
            return true
        }
        guard let request = requests[id], request.session == key, request.turn == turn,
              request.epoch == epoch, request.auditID == auditID else { return false }
        if name == "DSHQuestionClosed", request.wire.kind == .questions {
            release(id)
        } else if name == "DSHApprovalSettled", let outcome = payload["outcome"] as? String,
           ["allowed-once", "rejected", "cancelled", "unavailable"].contains(outcome) {
            requests.removeValue(forKey: id)
            bridge.resolve(eventID: id, decision: nil)
            model.resolveLocalHookRequest(sessionKey: key, rpcID: request.rpcID)
        } else if name == "DSHApprovalReleased" { release(id) }
        return true
    }

    private func respond(_ wire: IslandCodexApprovalRequest, result: IslandApprovalJSON) throws {
        guard canRespond(to: wire), wire.permits(result),
              let id = DSHApproval.eventID(of: wire), requests[id]?.rpcID == wire.rpcID else { throw CocoaError(.userCancelled) }
        if wire.kind == .questions, let question = wire.questions.first,
           let answer = result["answers"][question.id]["answers"].array.first?.text {
            guard answer.utf8.count <= 4096 else { throw CocoaError(.fileReadTooLarge) }
            requests[id]?.awaitsDecision = false
            bridge.resolve(eventID: id, decision: ["answer": answer])
            return
        }
        switch result["decision"].text {
        case "accept", "decline":
            requests[id]?.awaitsDecision = false
            bridge.resolve(eventID: id, decision: ["outcome": result["decision"].text == "accept" ? "allowed-once" : "rejected"])
            // Keep the pending presentation until the actual DSH audit event.
        case "dshDelegate": release(id)
        default: throw CocoaError(.coderInvalidValue)
        }
    }

    func disconnected(eventID: String) { release(eventID) }

    private func release(_ id: String) {
        guard let request = requests.removeValue(forKey: id) else { return }
        bridge.resolve(eventID: id, decision: nil)
        if request.wire.kind == .questions {
            model.resolveLocalHookRequest(sessionKey: request.session, rpcID: request.rpcID)
        } else {
            model.returnDSHRequest(sessionKey: request.session, rpcID: request.rpcID)
        }
    }

    func releaseRequests(in session: String) {
        for (id, request) in requests where request.session == session { release(id) }
    }

    func releaseAll() {
        for id in Array(requests.keys) { release(id) }
    }

    func stop() {
        for task in titleTasks.values { task.cancel() }
        titleTasks.removeAll()
        titleReadAt.removeAll()
        releaseAll()
    }

    func readTitle(for key: String, sourceID: String, namespace: String?, homes: [URL],
                   completion: @escaping (String) -> Void) {
        let now = Date()
        guard titleTasks[key] == nil, titleTasks.count < 32,
              now.timeIntervalSince(titleReadAt[key] ?? .distantPast) >= 5,
              let home = homes.first(where: { Self.namespace(for: $0) == namespace }) else { return }
        titleReadAt[key] = now
        if titleReadAt.count > 512, let oldest = titleReadAt.min(by: { $0.value < $1.value })?.key {
            titleReadAt.removeValue(forKey: oldest)
        }
        titleTasks[key] = Task { [weak self] in
            let title = await Task.detached(priority: .utility) { Self.cachedTitle(home: home, sessionID: sourceID) }.value
            guard let self, !Task.isCancelled else { return }
            titleTasks.removeValue(forKey: key)
            if let title { completion(title) }
        }
    }

    /// Read only the public title projection, never derive a title from prompts.
    nonisolated static func cachedTitle(home: URL, sessionID: String) -> String? {
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
}
