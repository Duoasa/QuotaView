import Foundation
import CoreFoundation
#if canImport(Darwin)
import Darwin
#endif

/// Desktop coordination IDs preserve the JSON-RPC string/integer distinction.
public enum CodexDesktopIPCRequestID: Codable, Hashable, Sendable {
    case string(String)
    case integer(Int64)

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let text = try? value.decode(String.self) { self = .string(text) }
        else { self = .integer(try value.decode(Int64.self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .string(let text): try value.encode(text)
        case .integer(let number): try value.encode(number)
        }
    }
    fileprivate var json: DesktopIPCJSON {
        switch self {
        case .string(let text): return .string(text)
        case .integer(let number): return .integer(number)
        }
    }
    fileprivate init?(_ value: DesktopIPCJSON?) {
        switch value {
        case .string(let text) where !text.isEmpty: self = .string(text)
        case .integer(let number): self = .integer(number)
        default: return nil
        }
    }
}

public enum CodexDesktopIPCRequestKind: Equatable, Sendable {
    case serverRequest
    case asynchronousQuestion
}

/// Minted only from the current owner's authoritative pending-request stream.
public struct CodexDesktopIPCRequestHandle: Equatable, Sendable {
    public let kind: CodexDesktopIPCRequestKind
    public let connectionEpoch: UInt64
    public let ownerClientID: String
    public let conversationID: String
    public let turnID: String
    public let requestID: CodexDesktopIPCRequestID
    public let method: String
    public let revision: Int64
    public let rawRequest: Data
    fileprivate let nonce: UUID
}

public struct CodexDesktopConversationSnapshot: Sendable {
    /// Locally minted ledger lifetime; revisions are comparable only within it.
    public let streamGeneration: UInt64
    public let conversationID: String
    public let hostID: String
    public let ownerClientID: String
    public let connectionEpoch: UInt64
    public let revision: Int64
    private let stateData: Data?
    private let decodedState: DesktopIPCJSON?
    /// Compatibility access for data-based callers. Production consumes the
    /// projection and byte budget, so streaming never materializes this copy.
    /// The decoded tree contains only valid JSON values; failure stays closed.
    public var conversationState: Data { stateData ?? (try? decodedState?.encode()) ?? Data() }
    /// Conservative serialized size, maintained from changed subtrees.
    public let conversationStateByteCount: Int
    public let supportsUntrustedAppInput: Bool
    public let requests: [CodexDesktopIPCRequestHandle]
    /// Computed once on the transport actor; avoids decoding history again on MainActor.
    public var interactionProjection: CodexDesktopInteractionProjection? = nil

    init(conversationID: String, hostID: String, ownerClientID: String, connectionEpoch: UInt64,
         revision: Int64, streamGeneration: UInt64 = 0, conversationState: Data, supportsUntrustedAppInput: Bool,
         requests: [CodexDesktopIPCRequestHandle], interactionProjection: CodexDesktopInteractionProjection? = nil) {
        self.conversationID = conversationID; self.hostID = hostID; self.ownerClientID = ownerClientID
        self.connectionEpoch = connectionEpoch; self.revision = revision; self.streamGeneration = streamGeneration
        stateData = conversationState; decodedState = nil; conversationStateByteCount = conversationState.count
        self.supportsUntrustedAppInput = supportsUntrustedAppInput; self.requests = requests
        self.interactionProjection = interactionProjection
    }

    fileprivate init(conversationID: String, hostID: String, ownerClientID: String, connectionEpoch: UInt64,
                     revision: Int64, streamGeneration: UInt64, state: DesktopIPCJSON, byteCount: Int, supportsUntrustedAppInput: Bool,
                     requests: [CodexDesktopIPCRequestHandle], interactionProjection: CodexDesktopInteractionProjection) {
        self.conversationID = conversationID; self.hostID = hostID; self.ownerClientID = ownerClientID
        self.connectionEpoch = connectionEpoch; self.revision = revision; self.streamGeneration = streamGeneration
        stateData = nil; decodedState = state; conversationStateByteCount = byteCount
        self.supportsUntrustedAppInput = supportsUntrustedAppInput; self.requests = requests
        self.interactionProjection = interactionProjection
    }
}

public enum CodexDesktopIPCConnectionState: Equatable, Sendable {
    case connecting
    case connected
    case disconnected
}

/// Invalidates response capability without answering or removing a request.
/// A nil conversation scope means the connection could not safely identify the
/// oversized frame's owner; all capabilities on this epoch become read-only.
public struct CodexDesktopIPCInvalidation: Equatable, Sendable {
    public enum Reason: Equatable, Sendable { case resourceLimit }
    public let conversationID: String?
    public let hostID: String?
    public let connectionEpoch: UInt64
    public let reason: Reason
    /// Fixed metadata only; never includes a request or conversation payload.
    public var diagnosticCode: String = "conversation_budget"
}

public enum CodexDesktopIPCSubmissionResult: Equatable, Sendable {
    /// An IPC acknowledgement; settlement must come from a newer state stream.
    case acceptedForDispatch
}

public enum CodexDesktopIPCError: Error, Equatable, LocalizedError {
    case unavailable, peerMismatch, unsupportedProtocol, invalidMessage, resourceLimit
    case staleRequest, alreadySubmitted, invalidResponse, outcomeUnknown
    case rejected(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable: return "Codex 桌面连接暂不可用。"
        case .peerMismatch: return "Codex 桌面连接的归属校验失败。"
        case .unsupportedProtocol: return "当前 Codex 桌面协议尚不兼容。"
        case .invalidMessage: return "Codex 桌面返回了无法识别的数据。"
        case .resourceLimit: return "此会话的数据超出灵动岛处理范围，请在 Codex 处理。"
        case .staleRequest: return "此请求已更新，请使用当前的确认内容。"
        case .alreadySubmitted: return "此请求已提交，正在等待 Codex 同步。"
        case .invalidResponse: return "确认内容与当前请求不匹配。"
        case .outcomeUnknown: return "已发送，但尚未确认结果；请在 Codex 查看当前状态。"
        case .rejected: return "Codex 暂未接受此请求。"
        }
    }
}

/// Version-specific desktop follower adapter, separate from app-server JSON-RPC.
/// It observes existing owners and never claims thread ownership or starts turns.
public actor CodexDesktopIPCClient {
    public struct Configuration: Sendable {
        public let isEnabled: Bool
        public let socketURL: URL
        public let requestTimeoutSeconds: TimeInterval
        public let maximumFrameBytes: Int
        public let maximumRetainedStateBytes: Int
        public let maximumConversationStateBytes: Int
        public let maximumJSONNodes: Int
        public let frameDrainTimeoutSeconds: TimeInterval
        public init(isEnabled: Bool = true, socketURL: URL,
                    requestTimeoutSeconds: TimeInterval = 5,
                    maximumFrameBytes: Int = 9_437_184,
                    maximumRetainedStateBytes: Int = 33_554_432,
                    frameDrainTimeoutSeconds: TimeInterval = 5,
                    maximumConversationStateBytes: Int = CodexDesktopRequestProjector.maximumStateBytes,
                    maximumJSONNodes: Int = 100_000) {
            self.isEnabled = isEnabled; self.socketURL = socketURL
            self.requestTimeoutSeconds = max(0.05, requestTimeoutSeconds)
            self.maximumFrameBytes = max(1024, min(maximumFrameBytes, 72 * 1_048_576))
            self.maximumRetainedStateBytes = max(self.maximumFrameBytes, min(maximumRetainedStateBytes, 128 * 1_048_576))
            self.maximumConversationStateBytes = max(1024, min(maximumConversationStateBytes,
                CodexDesktopRequestProjector.maximumDesktopStateBytes))
            self.maximumJSONNodes = max(1024, min(maximumJSONNodes, 1_000_000))
            self.frameDrainTimeoutSeconds = max(0.05, min(frameDrainTimeoutSeconds, 30))
        }
        public static func live(environment: [String: String] = ProcessInfo.processInfo.environment) -> Self {
            let root = environment["CODEX_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
            return live(socketURL: root.appendingPathComponent("ipc/ipc.sock"))
        }
        public static func live(socketURL: URL) -> Self {
            .init(socketURL: socketURL,
                maximumFrameBytes: 72 * 1_048_576, maximumRetainedStateBytes: 128 * 1_048_576,
                maximumConversationStateBytes: CodexDesktopRequestProjector.maximumDesktopStateBytes,
                maximumJSONNodes: 1_000_000)
        }
    }
    private struct FollowKey: Hashable { let conversationID: String; let hostID: String }
    private struct Owner { let clientID: String; let supportsInput: Bool }
    private struct Ledger {
        let streamGeneration: UInt64
        var owner: Owner
        var revision: Int64
        var state: DesktopIPCJSON
        var stateByteCount: Int
        var handles: [CodexDesktopIPCRequestHandle]
    }
    private struct AttemptIdentity: Hashable {
        let connectionEpoch: UInt64
        let ownerClientID: String
        let conversationID: String
        let turnID: String
        let requestID: CodexDesktopIPCRequestID
        let method: String
        init(_ handle: CodexDesktopIPCRequestHandle) {
            connectionEpoch = handle.connectionEpoch; ownerClientID = handle.ownerClientID
            conversationID = handle.conversationID; turnID = handle.turnID
            requestID = handle.requestID; method = handle.method
        }
    }
    private struct SnapshotWaiter {
        let continuation: CheckedContinuation<Void, Error>
        let timer: Task<Void, Never>
    }
    private struct FollowRecovery {
        let id: UUID
        let task: Task<Void, Never>
    }
    private struct Pending {
        let method: String
        let owner: String?
        let continuation: CheckedContinuation<Data, Error>
        let timer: Task<Void, Never>
        let submission: Bool
    }
    typealias Connector = @Sendable (URL) async throws -> CodexDesktopIPCTransport
    private let configuration: Configuration
    private let connector: Connector
    private var transport: CodexDesktopIPCTransport?
    private var reader: Task<Void, Never>?
    private var maintenance: Task<Void, Never>?
    private var reconnectWaiter: CheckedContinuation<Void, Never>?
    private var started = false
    private var initialized = false
    private var incompatible = false
    private var resourceSuspended = false
    private var resourceBlockedFollows: Set<FollowKey> = []
    private var epoch: UInt64 = 0
    private var clientID = ""
    private var decoder: DesktopIPCInboundDecoder
    private var frameDeadline: Task<Void, Never>?
    private var deadlineFrame: UInt64?
    private var pending: [String: Pending] = [:]
    private var follows: Set<FollowKey> = []
    private var followingInFlight: [FollowKey: UUID] = [:]
    private var followRecoveries: [FollowKey: FollowRecovery] = [:]
    private var owners: [FollowKey: Owner] = [:]
    private var ledger: [FollowKey: Ledger] = [:]
    private var nextStreamGeneration: UInt64 = 0
    private var attempted: Set<AttemptIdentity> = []
    private var snapshotWaiters: [FollowKey: [UUID: SnapshotWaiter]] = [:]
    private var snapshotHandler: (@Sendable (CodexDesktopConversationSnapshot) async -> Void)?
    private var stateHandler: (@Sendable (CodexDesktopIPCConnectionState) async -> Void)?
    private var invalidationHandler: (@Sendable (CodexDesktopIPCInvalidation) async -> Void)?

    public init(configuration: Configuration = .live()) {
        self.configuration = configuration
        connector = { try await CodexDesktopIPCTransport.open($0) }
        decoder = .init(maximumFrameBytes: configuration.maximumFrameBytes)
    }
    init(configuration: Configuration, connector: @escaping Connector) {
        self.configuration = configuration; self.connector = connector
        decoder = .init(maximumFrameBytes: configuration.maximumFrameBytes)
    }
    public func start(
        snapshotHandler: @escaping @Sendable (CodexDesktopConversationSnapshot) async -> Void,
        stateHandler: @escaping @Sendable (CodexDesktopIPCConnectionState) async -> Void,
        invalidationHandler: (@Sendable (CodexDesktopIPCInvalidation) async -> Void)? = nil
    ) async {
        self.snapshotHandler = snapshotHandler; self.stateHandler = stateHandler
        self.invalidationHandler = invalidationHandler
        guard configuration.isEnabled else { await stateHandler(.disconnected); return }
        if started {
            let blocked = resourceBlockedFollows
            resourceBlockedFollows.removeAll()
            if resourceSuspended {
                resourceSuspended = false
                maintenance?.cancel()
                maintenance = Task { [weak self] in await self?.maintainConnection() }
                return
            }
            for key in blocked { scheduleFollowRecovery(key) }
            await stateHandler(initialized ? .connected : .connecting)
            return
        }
        started = true; incompatible = false; resourceSuspended = false
        resourceBlockedFollows.removeAll()
        maintenance = Task { [weak self] in await self?.maintainConnection() }
    }
    public func stop() async {
        started = false; incompatible = false; resourceSuspended = false
        follows.removeAll(); resourceBlockedFollows.removeAll()
        maintenance?.cancel(); maintenance = nil
        await closeConnection()
        snapshotHandler = nil; stateHandler = nil; invalidationHandler = nil
    }
    /// A disconnected follow remains an intent and is restored on reconnection.
    public func follow(conversationID: String, hostID: String = "local") async throws {
        guard !conversationID.isEmpty, !hostID.isEmpty, follows.count < 128 || follows.contains(.init(conversationID: conversationID, hostID: hostID)) else {
            throw CodexDesktopIPCError.invalidMessage
        }
        let key = FollowKey(conversationID: conversationID, hostID: hostID)
        follows.insert(key)
        guard initialized else { return }
        do { try await establishFollow(key) }
        catch { scheduleFollowRecovery(key); throw error }
    }
    public func unfollow(conversationID: String, hostID: String = "local") async {
        let key = FollowKey(conversationID: conversationID, hostID: hostID)
        follows.remove(key); resourceBlockedFollows.remove(key); followRecoveries.removeValue(forKey: key)?.task.cancel()
        followingInFlight.removeValue(forKey: key)
        owners.removeValue(forKey: key); removeLedger(key)
        if initialized {
            try? broadcast(method: "thread-stream-following-changed", version: 1,
                           params: ["conversationId": .string(conversationID), "hostId": .string(hostID), "following": .bool(false)])
        }
    }
    /// Recheck callbacks queued across an unfollow/reconnect before UI admission.
    public func isCurrent(_ snapshot: CodexDesktopConversationSnapshot) -> Bool {
        let key = FollowKey(conversationID: snapshot.conversationID, hostID: snapshot.hostID)
        guard initialized, follows.contains(key), snapshot.connectionEpoch == epoch,
              let current = ledger[key] else { return false }
        return current.streamGeneration == snapshot.streamGeneration
            && current.owner.clientID == snapshot.ownerClientID
            && current.revision == snapshot.revision
    }
    public func submit(handle: CodexDesktopIPCRequestHandle, result: Data) async throws -> CodexDesktopIPCSubmissionResult {
        let key = FollowKey(conversationID: handle.conversationID, hostID: "local")
        try validate(handle, key: key)
        let response = try DesktopIPCJSON.decode(result, limit: 1_048_576)
        if handle.kind == .asynchronousQuestion {
            // Native desktop uses follower steering for these questions. It has
            // no cross-IPC expected-turn CAS; refresh and revalidate immediately
            // before this one user action, then await the native reply in stream.
            guard Self.validResponse(response, method: "item/tool/requestUserInput") else { throw CodexDesktopIPCError.invalidResponse }
            try await refreshSnapshot(key)
            try validate(handle, key: key)
            guard let entry = ledger[key], let question = try DesktopIPCJSON.decode(handle.rawRequest, limit: 1_048_576)["params"]?["questions"]?.array?.first,
                  let questionID = question["id"]?.string, handle.requestID == .string(questionID),
                  let title = question["question"]?.string,
                  let answers = response["answers"]?.object, answers.count == 1,
                  let selected = answers[questionID]?["answers"]?.array, selected.count == 1,
                  let answer = selected.first?.string, !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  answer.utf8.count <= 65_536 else { throw CodexDesktopIPCError.invalidResponse }
            let reply = DesktopIPCJSON.array([.object(["questionItemId": .string(questionID), "question": .string(title), "answer": .string(answer)])])
            let text = CodexDesktopRequestProjector.asyncReplyOpeningTag + "\n" + String(decoding: try reply.encode(), as: UTF8.self) + "\n" + CodexDesktopRequestProjector.asyncReplyClosingTag
            let messageID = UUID().uuidString
            let context: DesktopIPCJSON = .object(["prompt": .string(title + "\n" + answer), "turnTrigger": .string("send_user_message_async_question"),
                "addedFiles": .array([]), "fileAttachments": .array([]), "imageAttachments": .array([]), "commentAttachments": .array([]),
                "ideContext": .null, "workspaceRoots": entry.state["cwd"]?.string.map { .array([.string($0)]) } ?? .array([])])
            let restore: DesktopIPCJSON = .object(["id": .string(messageID), "cwd": entry.state["cwd"] ?? .null, "context": context])
            attempted.insert(AttemptIdentity(handle))
            let data = try await request(method: "thread-follower-steer-turn", version: 1, targetOwner: handle.ownerClientID,
                params: ["conversationId": .string(handle.conversationID), "clientUserMessageId": .string(messageID),
                    "input": .array([.object(["type": .string("text"), "text": .string(text), "text_elements": .array([])])]),
                    "restoreMessage": restore, "attachments": .array([])], submission: true)
            let acknowledgement = try DesktopIPCJSON.decode(data, limit: configuration.maximumFrameBytes)
            guard acknowledgement["result"]?["turnId"]?.string == handle.turnID else { throw CodexDesktopIPCError.outcomeUnknown }
            return .acceptedForDispatch
        }
        let verb: String
        let valueKey: String
        switch handle.method {
        case "item/commandExecution/requestApproval": verb = "thread-follower-command-approval-decision"; valueKey = "decision"
        case "item/fileChange/requestApproval": verb = "thread-follower-file-approval-decision"; valueKey = "decision"
        case "item/permissions/requestApproval": verb = "thread-follower-permissions-request-approval-response"; valueKey = "response"
        case "item/tool/requestUserInput": verb = "thread-follower-submit-user-input"; valueKey = "response"
        case "mcpServer/elicitation/request": verb = "thread-follower-submit-mcp-server-elicitation-response"; valueKey = "response"
        default: throw CodexDesktopIPCError.invalidResponse
        }
        guard Self.validResponse(response, method: handle.method) else { throw CodexDesktopIPCError.invalidResponse }
        let submittedValue = valueKey == "decision" ? response["decision"]! : response
        attempted.insert(AttemptIdentity(handle))
        let data = try await request(method: verb, version: 1, targetOwner: handle.ownerClientID,
            params: ["conversationId": .string(handle.conversationID), "requestId": handle.requestID.json, valueKey: submittedValue], submission: true)
        let acknowledgement = try DesktopIPCJSON.decode(data, limit: configuration.maximumFrameBytes)
        guard acknowledgement["ok"]?.bool == true else { throw CodexDesktopIPCError.outcomeUnknown }
        return .acceptedForDispatch
    }
    private func validate(_ handle: CodexDesktopIPCRequestHandle, key: FollowKey) throws {
        guard initialized, transport != nil else { throw CodexDesktopIPCError.unavailable }
        guard handle.connectionEpoch == epoch, follows.contains(key), let entry = ledger[key],
              entry.owner.clientID == handle.ownerClientID, entry.owner.supportsInput, entry.revision >= handle.revision,
              entry.handles.contains(where: { $0.nonce == handle.nonce && $0.rawRequest == handle.rawRequest }),
              !handle.turnID.isEmpty else { throw CodexDesktopIPCError.staleRequest }
        guard !attempted.contains(AttemptIdentity(handle)) else { throw CodexDesktopIPCError.alreadySubmitted }
    }
    private func refreshSnapshot(_ key: FollowKey) async throws {
        guard let owner = owners[key] else { throw CodexDesktopIPCError.staleRequest }
        let id = UUID(), run = epoch
        try await withCheckedThrowingContinuation { continuation in
            let timer = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64((self?.configuration.requestTimeoutSeconds ?? 5) * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await self?.expireSnapshot(key: key, id: id, epoch: run)
            }
            snapshotWaiters[key, default: [:]][id] = .init(continuation: continuation, timer: timer)
            do {
                try broadcast(method: "thread-stream-following-changed", version: 1,
                    params: ["conversationId": .string(key.conversationID), "hostId": .string(key.hostID), "following": .bool(true)], targets: [owner.clientID])
            } catch {
                let waiter = snapshotWaiters[key]?.removeValue(forKey: id); waiter?.timer.cancel(); waiter?.continuation.resume(throwing: error)
            }
        }
    }
    private func expireSnapshot(key: FollowKey, id: UUID, epoch run: UInt64) {
        guard run == epoch, let waiter = snapshotWaiters[key]?.removeValue(forKey: id) else { return }
        waiter.continuation.resume(throwing: CodexDesktopIPCError.unavailable)
    }
    private func maintainConnection() async {
        var backoff: UInt64 = 250_000_000
        while started, !Task.isCancelled {
            if incompatible || resourceSuspended { return }
            if !initialized {
                do {
                    try await connect()
                    backoff = 250_000_000
                    let run = epoch
                    for key in follows {
                        guard initialized, run == epoch, !Task.isCancelled else { break }
                        do { try await establishFollow(key) }
                        catch { scheduleFollowRecovery(key) }
                    }
                } catch {
                    guard started, !resourceSuspended, !Task.isCancelled else { return }
                    await closeConnection()
                    guard started, !resourceSuspended, !Task.isCancelled else { return }
                    try? await Task.sleep(nanoseconds: backoff)
                    backoff = min(backoff * 2, 5_000_000_000)
                }
            } else {
                await withCheckedContinuation { continuation in reconnectWaiter = continuation }
            }
        }
    }
    private func connect() async throws {
        epoch &+= 1; let run = epoch
        await stateHandler?(.connecting)
        guard started, run == epoch, !Task.isCancelled else { throw CodexDesktopIPCError.unavailable }
        let opened = try await connector(configuration.socketURL)
        guard started, run == epoch, !Task.isCancelled else { opened.close(); throw CodexDesktopIPCError.unavailable }
        transport = opened; decoder = .init(maximumFrameBytes: configuration.maximumFrameBytes)
        reader = Task { [weak self] in
            for await chunk in opened.chunks {
                guard !Task.isCancelled else { break }
                do {
                    defer { opened.acknowledgeRead() }
                    try await self?.consume(chunk, epoch: run)
                }
                catch let error as CodexDesktopIPCError where error == .resourceLimit {
                    await self?.suspendForResourceLimit(epoch: run); break
                } catch { await self?.protocolFailed(epoch: run); break }
            }
            await self?.connectionEnded(epoch: run)
        }
        let data = try await request(method: "initialize", version: 0, params: ["clientType": .string("quotaview")])
        let result = try DesktopIPCJSON.decode(data, limit: configuration.maximumFrameBytes)
        guard let id = result["clientId"]?.string, !id.isEmpty, started, run == epoch else { throw CodexDesktopIPCError.invalidMessage }
        clientID = id; initialized = true
        await stateHandler?(.connected)
    }
    private func establishFollow(_ key: FollowKey, candidateOwner: String? = nil) async throws {
        guard initialized, follows.contains(key), !resourceBlockedFollows.contains(key), followingInFlight[key] == nil else { return }
        if candidateOwner == nil, owners[key] != nil { return }
        let attempt = UUID(); followingInFlight[key] = attempt; let run = epoch
        defer { if followingInFlight[key] == attempt { followingInFlight.removeValue(forKey: key) } }
        let response = try await requestEnvelope(method: "thread-owner-discovery", version: 1,
                                                 targetOwner: candidateOwner,
                                                 params: ["conversationId": .string(key.conversationID), "hostId": .string(key.hostID)])
        let message = try DesktopIPCJSON.decode(response, limit: configuration.maximumFrameBytes)
        guard run == epoch, followingInFlight[key] == attempt, initialized, follows.contains(key), !resourceBlockedFollows.contains(key), !Task.isCancelled,
              let ownerID = message["handledByClientId"]?.string, !ownerID.isEmpty,
              candidateOwner == nil || ownerID == candidateOwner else { throw CodexDesktopIPCError.peerMismatch }
        let owner = Owner(clientID: ownerID, supportsInput: message["result"]?["supportsUntrustedAppInput"]?.bool == true)
        if owners[key]?.clientID != ownerID { removeLedger(key) }
        owners[key] = owner
        try broadcast(method: "thread-stream-following-changed", version: 1,
                      params: ["conversationId": .string(key.conversationID), "hostId": .string(key.hostID), "following": .bool(true)],
                      targets: [ownerID])
    }
    /// Readiness recovery belongs to each unresolved follow, not to event polling
    /// or submission retries. A native status request accelerates formal discovery;
    /// otherwise only owner-less intents back off while this connection is live.
    private func scheduleFollowRecovery(_ key: FollowKey, candidateOwner: String? = nil) {
        guard started, initialized, follows.contains(key), !resourceBlockedFollows.contains(key) else { return }
        if let previous = followRecoveries[key] {
            guard candidateOwner != nil else { return }
            previous.task.cancel()
        }
        let id = UUID(), run = epoch
        let task = Task { [weak self] in
            guard let self else { return }
            await recoverFollow(key, id: id, run: run, candidateOwner: candidateOwner)
        }
        followRecoveries[key] = .init(id: id, task: task)
    }
    private func recoverFollow(_ key: FollowKey, id: UUID, run: UInt64, candidateOwner: String?) async {
        defer { if followRecoveries[key]?.id == id { followRecoveries.removeValue(forKey: key) } }
        var candidate = candidateOwner
        var backoff: UInt64 = 250_000_000
        var waitBeforeDiscovery = candidate == nil
        while started, initialized, run == epoch, follows.contains(key),
              followRecoveries[key]?.id == id, !Task.isCancelled {
            if candidate == nil, owners[key] != nil { return }
            if waitBeforeDiscovery {
                do { try await Task.sleep(nanoseconds: backoff) } catch { return }
                guard started, initialized, run == epoch, follows.contains(key),
                      followRecoveries[key]?.id == id, !Task.isCancelled else { return }
            }
            do { try await establishFollow(key, candidateOwner: candidate) } catch { }
            guard started, initialized, run == epoch, follows.contains(key),
                  followRecoveries[key]?.id == id, !Task.isCancelled else { return }
            if owners[key] != nil { return }
            candidate = nil; waitBeforeDiscovery = true
            backoff = min(backoff * 2, 5_000_000_000)
        }
    }
    private func request(method: String, version: Int64, targetOwner: String? = nil,
                         params: [String: DesktopIPCJSON], submission: Bool = false) async throws -> Data {
        let envelope = try await requestEnvelope(method: method, version: version, targetOwner: targetOwner, params: params, submission: submission)
        guard let result = try DesktopIPCJSON.decode(envelope, limit: configuration.maximumFrameBytes)["result"] else { throw CodexDesktopIPCError.invalidMessage }
        return try result.encode()
    }
    private func requestEnvelope(method: String, version: Int64, targetOwner: String? = nil,
                                 params: [String: DesktopIPCJSON], submission: Bool = false) async throws -> Data {
        guard transport != nil else { throw CodexDesktopIPCError.unavailable }
        let id = UUID().uuidString, run = epoch
        var message: [String: DesktopIPCJSON] = ["type": .string("request"), "requestId": .string(id),
            "sourceClientId": .string(clientID), "version": .integer(version), "method": .string(method), "params": .object(params)]
        if let targetOwner { message["targetClientId"] = .string(targetOwner) }
        return try await withCheckedThrowingContinuation { continuation in
            let timer = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64((self?.configuration.requestTimeoutSeconds ?? 5) * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await self?.expire(id: id, epoch: run)
            }
            pending[id] = .init(method: method, owner: targetOwner, continuation: continuation, timer: timer, submission: submission)
            do { try write(.object(message)) }
            catch {
                let request = pending.removeValue(forKey: id); request?.timer.cancel()
                request?.continuation.resume(throwing: submission ? CodexDesktopIPCError.outcomeUnknown : error)
            }
        }
    }
    private func broadcast(method: String, version: Int64, params: [String: DesktopIPCJSON], targets: [String]? = nil) throws {
        var message: [String: DesktopIPCJSON] = ["type": .string("broadcast"), "method": .string(method),
            "sourceClientId": .string(clientID), "version": .integer(version), "params": .object(params)]
        if let targets { message["targetClientIds"] = .array(targets.map(DesktopIPCJSON.string)) }
        try write(.object(message))
    }
    private func write(_ message: DesktopIPCJSON) throws {
        guard let transport else { throw CodexDesktopIPCError.unavailable }
        try transport.write(CodexDesktopIPCFrameDecoder.frame(try message.encode(), maximumFrameBytes: configuration.maximumFrameBytes))
    }
    private func consume(_ chunk: Data, epoch run: UInt64) async throws {
        guard run == epoch, started else { return }
        // The socket is backpressured while we decode and deliver this chunk.
        // Our own processing time is not a stalled peer. Restart the idle
        // deadline on actual read progress, not only at the first frame byte.
        frameDeadline?.cancel(); frameDeadline = nil; deadlineFrame = nil
        let events = try decoder.append(chunk)
        for event in events {
            guard run == epoch, started else { return }
            switch event {
            case .message(let data):
                do { try await handle(data, epoch: run) }
                catch CodexDesktopIPCError.resourceLimit {
                    try await handleResourceEnvelope(DesktopIPCEnvelopeReducer.reduce(data), epoch: run,
                        diagnosticCode: "json_structure")
                }
            case .oversized(let reduced):
                try await handleResourceEnvelope(reduced, epoch: run)
            }
        }
        guard run == epoch, started else { return }
        updateFrameDeadline(epoch: run)
    }
    private func updateFrameDeadline(epoch run: UInt64) {
        guard decoder.pendingFrame != deadlineFrame else { return }
        frameDeadline?.cancel(); frameDeadline = nil
        deadlineFrame = decoder.pendingFrame
        guard let frame = deadlineFrame else { return }
        let seconds = configuration.frameDrainTimeoutSeconds
        frameDeadline = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) } catch { return }
            await self?.expireFrame(frame, epoch: run)
        }
    }
    private func expireFrame(_ frame: UInt64, epoch run: UInt64) async {
        guard !Task.isCancelled, run == epoch, deadlineFrame == frame, decoder.pendingFrame == frame else { return }
        await suspendForResourceLimit(epoch: run, diagnosticCode: "frame_stalled")
    }
    /// The whole declared frame has been consumed. Only a unique envelope from
    /// an already discovered owner can quarantine one follow; body contents are
    /// never materialized. Audience/foreign/unfollowed traffic is simply ignored.
    private func handleResourceEnvelope(_ reduced: Data?, epoch run: UInt64, diagnosticCode: String = "frame_bytes") async throws {
        guard let reduced else { throw CodexDesktopIPCError.resourceLimit }
        let message = try DesktopIPCJSON.decode(reduced, limit: DesktopIPCEnvelopeReducer.maximumMetadataBytes)
        guard initialized, message["type"]?.string == "broadcast",
              message["method"]?.string == "thread-stream-state-changed",
              let source = message["sourceClientId"]?.string, !source.isEmpty,
              let params = message["params"], let conversation = params["conversationId"]?.string, !conversation.isEmpty,
              let host = params["hostId"]?.string, !host.isEmpty else { throw CodexDesktopIPCError.resourceLimit }
        if let audience = message["targetClientIds"] {
            guard let targets = audience.array, targets.allSatisfy({ $0.string != nil }) else { throw CodexDesktopIPCError.resourceLimit }
            guard targets.contains(.string(clientID)) else { return }
        }
        let key = FollowKey(conversationID: conversation, hostID: host)
        guard follows.contains(key), !resourceBlockedFollows.contains(key) else { return }
        guard let owner = owners[key] else { throw CodexDesktopIPCError.resourceLimit }
        guard source == owner.clientID else { return }
        guard message["version"]?.integer == 11 else {
            incompatible = true; await closeConnection(); return
        }
        await invalidateResourceLimit(key, epoch: run, diagnosticCode: diagnosticCode)
    }
    private func handle(_ data: Data, epoch run: UInt64) async throws {
        let message = try DesktopIPCJSON.decode(data, limit: configuration.maximumFrameBytes,
            maximumNodes: configuration.maximumJSONNodes)
        switch message["type"]?.string {
        case "response":
            guard let id = message["requestId"]?.string, let request = pending.removeValue(forKey: id) else { return }
            request.timer.cancel()
            guard message["resultType"]?.string == "success" else {
                request.continuation.resume(throwing: request.submission ? CodexDesktopIPCError.outcomeUnknown : CodexDesktopIPCError.rejected(message["error"]?.string ?? "error")); return
            }
            guard message["method"]?.string == request.method,
                  request.owner == nil || message["handledByClientId"]?.string == request.owner else {
                request.continuation.resume(throwing: request.submission ? CodexDesktopIPCError.outcomeUnknown : CodexDesktopIPCError.peerMismatch); return
            }
            request.continuation.resume(returning: data)
        case "client-discovery-request":
            guard let id = message["requestId"]?.string else { throw CodexDesktopIPCError.invalidMessage }
            try write(.object(["type": .string("client-discovery-response"), "requestId": .string(id), "response": .object(["canHandle": .bool(false)])]))
        case "request":
            guard let id = message["requestId"]?.string else { throw CodexDesktopIPCError.invalidMessage }
            try write(.object(["type": .string("response"), "requestId": .string(id), "resultType": .string("error"), "error": .string("no-handler-for-request")]))
        case "broadcast":
            if let targets = message["targetClientIds"]?.array, !targets.contains(.string(clientID)) { return }
            try await handleBroadcast(message, epoch: run)
        default: throw CodexDesktopIPCError.invalidMessage
        }
    }
    private func handleBroadcast(_ message: DesktopIPCJSON, epoch run: UInt64) async throws {
        guard initialized, let method = message["method"]?.string else { return }
        if method == "client-status-changed", message["version"]?.integer == 0,
           message["params"]?["status"]?.string == "disconnected",
           let peer = message["params"]?["clientId"]?.string, owners.values.contains(where: { $0.clientID == peer }) {
            await closeConnection(); return
        }
        if method == "ipc-connection-reset", message["version"]?.integer == 1 { await closeConnection(); return }
        guard let params = message["params"], let conversation = params["conversationId"]?.string,
              let host = params["hostId"]?.string else { return }
        let key = FollowKey(conversationID: conversation, hostID: host)
        guard follows.contains(key), !resourceBlockedFollows.contains(key) else { return }
        if method == "thread-stream-following-status-requested", message["version"]?.integer == 1,
           let source = message["sourceClientId"]?.string {
            // Discovery must run outside the reader: its response arrives on
            // this same stream. Never treat a status broadcast as owner proof.
            scheduleFollowRecovery(key, candidateOwner: source); return
        }
        guard method == "thread-stream-state-changed" else { return }
        guard let source = message["sourceClientId"]?.string, let owner = owners[key] else { return }
        guard source == owner.clientID else {
            removeLedger(key)
            scheduleFollowRecovery(key, candidateOwner: source); return
        }
        guard message["version"]?.integer == 11 else {
            incompatible = true; await closeConnection(); return
        }
        guard let change = params["change"], let revision = change["revision"]?.integer, revision >= 0 else {
            throw CodexDesktopIPCError.invalidMessage
        }
        let state: DesktopIPCJSON
        var stateByteCount: Int
        switch change["type"]?.string {
        case "snapshot":
            guard let candidate = change["conversationState"], candidate["id"]?.string == conversation else { throw CodexDesktopIPCError.invalidMessage }
            if let previous = ledger[key], revision < previous.revision { return }
            state = candidate
            stateByteCount = candidate.budgetByteCount
        case "patches":
            guard let entry = ledger[key], change["baseRevision"]?.integer == entry.revision,
                  revision > entry.revision, let patches = change["patches"]?.array else {
                removeLedger(key)
                try broadcast(method: "thread-stream-following-changed", version: 1,
                              params: ["conversationId": .string(conversation), "hostId": .string(host), "following": .bool(true)], targets: [source]); return
            }
            guard patches.count <= 1024 else { await invalidateResourceLimit(key, epoch: run, diagnosticCode: "patch_count"); return }
            stateByteCount = entry.stateByteCount
            do { state = try DesktopIPCJSON.applying(patches, to: entry.state, byteCount: &stateByteCount) }
            catch { removeLedger(key); throw CodexDesktopIPCError.invalidMessage }
            guard state["id"]?.string == conversation else { throw CodexDesktopIPCError.invalidMessage }
        default: throw CodexDesktopIPCError.invalidMessage
        }
        let retained = ledger.filter { $0.key != key }.reduce(stateByteCount) { $0 + $1.value.stateByteCount }
        guard stateByteCount <= configuration.maximumConversationStateBytes else {
            await invalidateResourceLimit(key, epoch: run, diagnosticCode: "state_bytes"); return
        }
        guard retained <= configuration.maximumRetainedStateBytes else {
            await invalidateResourceLimit(key, epoch: run, diagnosticCode: "retained_bytes"); return
        }
        guard let requests = state["requests"]?.array else { throw CodexDesktopIPCError.invalidMessage }
        guard requests.count <= CodexDesktopRequestProjector.maximumPendingRequests else {
            await invalidateResourceLimit(key, epoch: run, diagnosticCode: "request_count"); return
        }
        let projection: CodexDesktopInteractionProjection
        do { projection = try CodexDesktopRequestProjector.project(conversationID: conversation, state: state) }
        catch CodexDesktopRequestProjectionError.oversizedState {
            await invalidateResourceLimit(key, epoch: run, diagnosticCode: "projection_budget"); return
        }
        let old = ledger[key]?.handles ?? []
        var handles: [CodexDesktopIPCRequestHandle] = []
        var seen: Set<CodexDesktopIPCRequestID> = []
        for request in requests {
            guard let id = CodexDesktopIPCRequestID(request["id"]), seen.insert(id).inserted else { throw CodexDesktopIPCError.invalidMessage }
            guard projection.pendingRequestsAreAuthoritative,
                  let method = request["method"]?.string, Self.submittableMethods.contains(method),
                  request["completed"]?.bool != true, request["params"]?["threadId"]?.string == conversation,
                  let projected = projection.requests.first(where: { $0.requestID == id && $0.method == method }) else { continue }
            let raw = try request.encode(), turn = projected.turnID
            let oldHandle = old.first { $0.kind == .serverRequest && $0.requestID == id && $0.method == method && $0.turnID == turn && $0.rawRequest == raw }
            handles.append(.init(kind: .serverRequest, connectionEpoch: run, ownerClientID: source, conversationID: conversation,
                turnID: turn, requestID: id, method: method, revision: oldHandle?.revision ?? revision,
                rawRequest: raw, nonce: oldHandle?.nonce ?? UUID()))
        }
        for question in projection.asyncQuestions where projection.pendingRequestsAreAuthoritative && projection.authoritativeAsyncQuestionIDs.contains(question.questionItemID) {
            let raw = try question.asyncRequestEnvelopeData(conversationID: conversation), id = CodexDesktopIPCRequestID.string(question.questionItemID)
            let oldHandle = old.first { $0.kind == .asynchronousQuestion && $0.requestID == id && $0.turnID == question.turnID && $0.rawRequest == raw }
            handles.append(.init(kind: .asynchronousQuestion, connectionEpoch: run, ownerClientID: source, conversationID: conversation,
                turnID: question.turnID, requestID: id, method: "desktop/tool/requestUserInputAsync", revision: oldHandle?.revision ?? revision,
                rawRequest: raw, nonce: oldHandle?.nonce ?? UUID()))
        }
        if projection.pendingRequestsAreAuthoritative {
            let live = Set(handles.map(AttemptIdentity.init))
            attempted = attempted.filter { $0.conversationID != conversation || $0.ownerClientID != source || live.contains($0) }
        }
        let streamGeneration: UInt64
        if let existing = ledger[key] { streamGeneration = existing.streamGeneration }
        else { nextStreamGeneration += 1; streamGeneration = nextStreamGeneration }
        ledger[key] = .init(streamGeneration: streamGeneration, owner: owner, revision: revision, state: state, stateByteCount: stateByteCount, handles: handles)
        if change["type"]?.string == "snapshot", let waiters = snapshotWaiters.removeValue(forKey: key) {
            for waiter in waiters.values { waiter.timer.cancel(); waiter.continuation.resume() }
        }
        await snapshotHandler?(.init(conversationID: conversation, hostID: host, ownerClientID: source,
                                     connectionEpoch: run, revision: revision, streamGeneration: streamGeneration, state: state, byteCount: stateByteCount,
                                     supportsUntrustedAppInput: owner.supportsInput && host == "local" && projection.pendingRequestsAreAuthoritative,
                                     requests: handles, interactionProjection: projection))
    }
    private static let submittableMethods: Set<String> = ["item/commandExecution/requestApproval", "item/fileChange/requestApproval",
        "item/permissions/requestApproval", "item/tool/requestUserInput", "mcpServer/elicitation/request"]
    private static func validResponse(_ response: DesktopIPCJSON, method: String) -> Bool {
        guard let object = response.object else { return false }
        switch method {
        case "item/commandExecution/requestApproval", "item/fileChange/requestApproval":
            guard object.count == 1, let decision = object["decision"] else { return false }
            if let choice = decision.string { return ["accept", "acceptForSession", "decline", "cancel"].contains(choice) }
            guard method == "item/commandExecution/requestApproval", let options = decision.object, options.count == 1 else { return false }
            return options["acceptWithExecpolicyAmendment"]?.object != nil || options["applyNetworkPolicyAmendment"]?.object != nil
        case "item/tool/requestUserInput":
            guard Set(object.keys) == ["answers"], let answers = object["answers"]?.object, answers.count <= 64 else { return false }
            return answers.values.allSatisfy { value in
                guard let entry = value.object, Set(entry.keys) == ["answers"], let values = entry["answers"]?.array else { return false }
                return values.allSatisfy { $0.string != nil }
            }
        case "item/permissions/requestApproval":
            return Set(object.keys).isSubset(of: ["permissions", "scope"]) && object["permissions"]?.object != nil
                && (object["scope"] == nil || ["turn", "session"].contains(object["scope"]?.string ?? ""))
        case "mcpServer/elicitation/request":
            return Set(object.keys).isSubset(of: ["action", "content", "_meta"]) && ["accept", "decline", "cancel"].contains(object["action"]?.string ?? "")
        default: return false
        }
    }
    private func removeLedger(_ key: FollowKey) {
        // A stream gap is not settlement. Keep submission identities until an
        // authoritative snapshot proves removal, even when new handles are minted.
        ledger.removeValue(forKey: key)
    }
    private func expire(id: String, epoch run: UInt64) {
        guard run == epoch, let request = pending.removeValue(forKey: id) else { return }
        request.continuation.resume(throwing: request.submission ? CodexDesktopIPCError.outcomeUnknown : CodexDesktopIPCError.unavailable)
    }
    private func invalidateResourceLimit(_ key: FollowKey, epoch run: UInt64, diagnosticCode: String = "conversation_budget") async {
        guard run == epoch, !resourceBlockedFollows.contains(key) else { return }
        resourceBlockedFollows.insert(key)
        followRecoveries.removeValue(forKey: key)?.task.cancel()
        let owner = owners.removeValue(forKey: key)
        removeLedger(key)
        if let waiters = snapshotWaiters.removeValue(forKey: key) {
            for waiter in waiters.values { waiter.timer.cancel(); waiter.continuation.resume(throwing: CodexDesktopIPCError.resourceLimit) }
        }
        if let owner {
            try? broadcast(method: "thread-stream-following-changed", version: 1,
                params: ["conversationId": .string(key.conversationID), "hostId": .string(key.hostID), "following": .bool(false)], targets: [owner.clientID])
        }
        await invalidationHandler?(.init(conversationID: key.conversationID, hostID: key.hostID,
            connectionEpoch: run, reason: .resourceLimit, diagnosticCode: diagnosticCode))
    }
    private func suspendForResourceLimit(epoch run: UInt64, diagnosticCode: String = "frame_unroutable") async {
        guard run == epoch else { return }
        // Incomplete/unroutable drain has no trustworthy conversation scope.
        // Stop automatic observation until explicit start; never reconnect in
        // a loop into the same resource pressure or call it a version mismatch.
        resourceSuspended = true
        await invalidationHandler?(.init(conversationID: nil, hostID: nil,
            connectionEpoch: run, reason: .resourceLimit, diagnosticCode: diagnosticCode))
        guard run == epoch else { return }
        await closeConnection()
    }
    private func protocolFailed(epoch run: UInt64) async {
        guard run == epoch else { return }
        incompatible = true; await closeConnection()
    }
    private func connectionEnded(epoch run: UInt64) async {
        guard run == epoch else { return }
        await closeConnection()
    }
    private func closeConnection() async {
        epoch &+= 1; initialized = false; clientID = ""
        frameDeadline?.cancel(); frameDeadline = nil; deadlineFrame = nil
        reader?.cancel(); reader = nil; transport?.close(); transport = nil
        followRecoveries.values.forEach { $0.task.cancel() }; followRecoveries.removeAll()
        owners.removeAll(); ledger.removeAll(); attempted.removeAll(); followingInFlight.removeAll()
        let waiting = snapshotWaiters.values.flatMap { $0.values }; snapshotWaiters.removeAll()
        for waiter in waiting { waiter.timer.cancel(); waiter.continuation.resume(throwing: CodexDesktopIPCError.unavailable) }
        let requests = pending.values; pending.removeAll()
        for request in requests { request.timer.cancel(); request.continuation.resume(throwing: request.submission ? CodexDesktopIPCError.outcomeUnknown : CodexDesktopIPCError.unavailable) }
        reconnectWaiter?.resume(); reconnectWaiter = nil
        await stateHandler?(.disconnected)
    }
}

/// The private IPC uses a little-endian UInt32 byte count, not WebSockets/JSONL.
struct CodexDesktopIPCFrameDecoder {
    let maximumFrameBytes: Int
    private var buffer = Data()
    init(maximumFrameBytes: Int) { self.maximumFrameBytes = maximumFrameBytes }
    mutating func append(_ data: Data) throws -> [Data] {
        guard data.count <= maximumFrameBytes + 4, buffer.count + data.count <= maximumFrameBytes * 2 + 8 else { throw CodexDesktopIPCError.resourceLimit }
        buffer.append(data); var messages: [Data] = []
        while buffer.count >= 4 {
            let bytes = Array(buffer.prefix(4))
            let length = Int(UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24)
            guard length > 0 else { throw CodexDesktopIPCError.invalidMessage }
            guard length <= maximumFrameBytes else { throw CodexDesktopIPCError.resourceLimit }
            guard buffer.count >= length + 4 else { break }
            messages.append(Data(buffer.dropFirst(4).prefix(length))); buffer.removeFirst(length + 4)
        }
        return messages
    }
    static func frame(_ data: Data, maximumFrameBytes: Int) throws -> Data {
        guard !data.isEmpty, data.count <= maximumFrameBytes else { throw CodexDesktopIPCError.invalidMessage }
        let size = UInt32(data.count)
        return Data([UInt8(truncatingIfNeeded: size), UInt8(truncatingIfNeeded: size >> 8), UInt8(truncatingIfNeeded: size >> 16), UInt8(truncatingIfNeeded: size >> 24)]) + data
    }
}

/// Framing and drain use the native 256MiB wire bound, independently from the
/// configured materialization limit. Oversized frames are routed and discarded.
private struct DesktopIPCInboundDecoder {
    enum Event { case message(Data), oversized(Data?) }
    static let maximumWireBytes = 256 * 1_048_576
    let maximumFrameBytes: Int
    private var header: [UInt8] = []
    private var remaining = 0
    private var payload = Data()
    private var reducer: DesktopIPCEnvelopeReducer?
    private var generation: UInt64 = 0
    private(set) var pendingFrame: UInt64?
    init(maximumFrameBytes: Int) { self.maximumFrameBytes = maximumFrameBytes }

    mutating func append(_ chunk: Data) throws -> [Event] {
        guard chunk.count <= Self.maximumWireBytes + 4 else { throw CodexDesktopIPCError.resourceLimit }
        var result: [Event] = [], offset = chunk.startIndex
        while offset < chunk.endIndex {
            if remaining == 0 {
                if header.isEmpty { generation &+= 1; pendingFrame = generation }
                while header.count < 4, offset < chunk.endIndex { header.append(chunk[offset]); offset += 1 }
                guard header.count == 4 else { break }
                let count = Int(UInt32(header[0]) | UInt32(header[1]) << 8 | UInt32(header[2]) << 16 | UInt32(header[3]) << 24)
                header.removeAll(keepingCapacity: true)
                guard count > 0 else { throw CodexDesktopIPCError.invalidMessage }
                guard count <= Self.maximumWireBytes else { throw CodexDesktopIPCError.resourceLimit }
                remaining = count
                if count > maximumFrameBytes { reducer = .init() }
            }
            let count = min(remaining, chunk.endIndex - offset)
            let bytes = chunk[offset..<(offset + count)]
            if reducer != nil { reducer!.append(bytes) }
            else { payload.append(contentsOf: bytes) }
            offset += count; remaining -= count
            if remaining == 0 {
                if let reducer { result.append(.oversized(reducer.finish())) }
                else { result.append(.message(payload)) }
                payload = Data(); reducer = nil; pendingFrame = nil
            }
        }
        return result
    }
}

/// Incremental JSON grammar, with no retained body strings/keys. Only the
/// params.change value is replaced by null; all other envelope fields survive
/// in order. Routing is decoded only after the entire frame, including trailing
/// version, has arrived. Duplicate decoded envelope keys fail closed.
private struct DesktopIPCEnvelopeReducer {
    static let maximumMetadataBytes = 65_536
    private enum Phase: Equatable { case keyOrEnd, key, colon, value, commaOrEnd, arrayValueOrEnd, arrayValue, arrayCommaOrEnd }
    private struct Container {
        let object: Bool
        let retained: Bool
        let root: Bool
        let params: Bool
        var phase: Phase
        var key: String?
        var keys: Set<String> = []
    }
    private enum Token { case none, string(key: Bool, retained: Bool), scalar(retained: Bool) }
    private var stack: [Container] = []
    private var token: Token = .none
    private var tokenBytes = Data()
    private var escape = 0 // 0 ordinary, -1 after backslash, 1...4 unicode hex
    private var output = Data()
    private var rootComplete = false
    private var reducedChange = false
    private var failed = false

    static func reduce(_ data: Data) -> Data? {
        var reducer = Self()
        // Existing bounded payloads still use the same streaming grammar.
        for offset in stride(from: 0, to: data.count, by: 65_536) {
            reducer.append(data[offset..<min(data.count, offset + 65_536)])
        }
        return reducer.finish()
    }
    mutating func append<S: Sequence>(_ bytes: S) where S.Element == UInt8 {
        for byte in bytes {
            guard !failed else { return }
            consume(byte)
        }
    }
    func finish() -> Data? {
        var candidate = self
        if case .scalar = candidate.token { candidate.endScalar() }
        guard !candidate.failed, candidate.rootComplete, candidate.stack.isEmpty,
              case .none = candidate.token, candidate.reducedChange,
              (try? DesktopIPCJSON.decode(candidate.output, limit: Self.maximumMetadataBytes)) != nil else { return nil }
        return candidate.output
    }
    private mutating func emit(_ byte: UInt8, retained: Bool) {
        guard retained else { return }
        guard output.count < Self.maximumMetadataBytes else { failed = true; return }
        output.append(byte)
    }
    private mutating func consume(_ byte: UInt8) {
        switch token {
        case .string(let key, let retained):
            emit(byte, retained: retained)
            if key { tokenBytes.append(byte) }
            if escape > 0 {
                guard Self.hex(byte) else { failed = true; return }
                escape -= 1; return
            }
            if escape == -1 {
                if byte == 117 { escape = 4 }
                else if [34, 47, 92, 98, 102, 110, 114, 116].contains(byte) { escape = 0 }
                else { failed = true }
                return
            }
            if byte == 92 { escape = -1; return }
            if byte == 34 {
                token = .none
                if key {
                    guard let name = try? JSONDecoder().decode(String.self, from: tokenBytes), !stack.isEmpty else { failed = true; return }
                    let index = stack.count - 1
                    guard stack[index].keys.insert(name).inserted else { failed = true; return }
                    stack[index].key = name; stack[index].phase = .colon
                    tokenBytes = Data()
                } else { completeValue() }
            } else if byte < 32 { failed = true }
        case .scalar(let retained):
            if Self.whitespace(byte) || byte == 44 || byte == 93 || byte == 125 {
                endScalar()
                if !failed { consume(byte) }
            } else {
                guard tokenBytes.count < 128 else { failed = true; return }
                tokenBytes.append(byte); emit(byte, retained: retained)
            }
        case .none:
            let retained = stack.last?.retained ?? true
            if Self.whitespace(byte) { emit(byte, retained: retained); return }
            if stack.isEmpty {
                guard !rootComplete else { failed = true; return }
                startValue(byte, retained: true); return
            }
            let index = stack.count - 1
            switch stack[index].phase {
            case .keyOrEnd, .key:
                if byte == 125, stack[index].phase == .keyOrEnd { endContainer(byte, object: true); return }
                guard byte == 34 else { failed = true; return }
                // Discarded body keys are parsed as strings, but never retained
                // or entered into a per-object set.
                let keepKey = retained
                token = .string(key: keepKey, retained: retained)
                tokenBytes = keepKey ? Data([34]) : Data()
                escape = 0; emit(byte, retained: retained)
                if !keepKey { stack[index].phase = .colon }
            case .colon:
                guard byte == 58 else { failed = true; return }
                emit(byte, retained: retained); stack[index].phase = .value
            case .value, .arrayValue, .arrayValueOrEnd:
                if byte == 93, stack[index].phase == .arrayValueOrEnd { endContainer(byte, object: false); return }
                let drop = retained && stack[index].params && stack[index].key == "change"
                if drop {
                    guard !reducedChange else { failed = true; return }
                    reducedChange = true
                    for byte in "null".utf8 { emit(byte, retained: true) }
                }
                startValue(byte, retained: retained && !drop)
            case .commaOrEnd:
                if byte == 125 { endContainer(byte, object: true) }
                else if byte == 44 { emit(byte, retained: retained); stack[index].phase = .key; stack[index].key = nil }
                else { failed = true }
            case .arrayCommaOrEnd:
                if byte == 93 { endContainer(byte, object: false) }
                else if byte == 44 { emit(byte, retained: retained); stack[index].phase = .arrayValue }
                else { failed = true }
            }
        }
    }
    private mutating func startValue(_ byte: UInt8, retained: Bool) {
        if byte == 123 || byte == 91 {
            guard stack.count < 256 else { failed = true; return }
            let isRoot = stack.isEmpty
            let isParams = byte == 123 && stack.last?.root == true && stack.last?.key == "params"
            emit(byte, retained: retained)
            stack.append(.init(object: byte == 123, retained: retained, root: isRoot, params: isParams,
                phase: byte == 123 ? .keyOrEnd : .arrayValueOrEnd))
        } else if byte == 34 {
            token = .string(key: false, retained: retained); tokenBytes = Data(); escape = 0
            emit(byte, retained: retained)
        } else if byte == 45 || (48...57).contains(byte) || [102, 110, 116].contains(byte) {
            token = .scalar(retained: retained); tokenBytes = Data([byte]); emit(byte, retained: retained)
        } else { failed = true }
    }
    private mutating func endScalar() {
        guard (try? DesktopIPCJSON.decode(tokenBytes, limit: 128)) != nil else { failed = true; return }
        token = .none; tokenBytes = Data(); completeValue()
    }
    private mutating func endContainer(_ byte: UInt8, object: Bool) {
        guard let container = stack.last, container.object == object else { failed = true; return }
        emit(byte, retained: container.retained); stack.removeLast(); completeValue()
    }
    private mutating func completeValue() {
        guard !stack.isEmpty else { rootComplete = true; return }
        let index = stack.count - 1
        if stack[index].object {
            // A discarded key ends in .colon, not in value-complete state.
            if stack[index].phase == .colon { return }
            guard stack[index].phase == .value else { failed = true; return }
            stack[index].phase = .commaOrEnd
        } else {
            guard [.arrayValue, .arrayValueOrEnd].contains(stack[index].phase) else { failed = true; return }
            stack[index].phase = .arrayCommaOrEnd
        }
    }
    private static func whitespace(_ byte: UInt8) -> Bool { byte == 9 || byte == 10 || byte == 13 || byte == 32 }
    private static func hex(_ byte: UInt8) -> Bool { (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte) }
}

struct CodexDesktopIPCTransport: Sendable {
    let chunks: AsyncStream<Data>
    let write: @Sendable (Data) throws -> Void
    let close: @Sendable () -> Void
    var acknowledgeRead: @Sendable () -> Void = {}
    static func open(_ url: URL) async throws -> Self {
        try await Task.detached(priority: .utility) {
            try verifyPeer(url)
            let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { throw CodexDesktopIPCError.unavailable }
            var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
            address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
            let bytes = Array(url.path.utf8) + [0]
            guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { Darwin.close(fd); throw CodexDesktopIPCError.unavailable }
            withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
            let connected = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
            }
            guard connected == 0 else { Darwin.close(fd); throw CodexDesktopIPCError.unavailable }
            // Verify the connected process's UID as well as the filesystem entry.
            var peerUID: uid_t = 0, peerGID: gid_t = 0
            guard getpeereid(fd, &peerUID, &peerGID) == 0, peerUID == getuid() else { Darwin.close(fd); throw CodexDesktopIPCError.peerMismatch }
            do { try verifyPeer(url) } catch { Darwin.close(fd); throw error }
            var noSignal: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
            let socket = DesktopIPCSocket(fd: fd)
            return .init(chunks: socket.chunks, write: { try socket.write($0) }, close: { socket.close() },
                         acknowledgeRead: { socket.acknowledgeRead() })
        }.value
    }
    static func verifyPeer(_ url: URL, expectedUID: uid_t = getuid()) throws {
        var directory = stat(), socket = stat()
        guard lstat(url.deletingLastPathComponent().path, &directory) == 0, lstat(url.path, &socket) == 0,
              directory.st_mode & S_IFMT == S_IFDIR, socket.st_mode & S_IFMT == S_IFSOCK,
              directory.st_uid == expectedUID, socket.st_uid == expectedUID,
              directory.st_mode & 0o022 == 0 else { throw CodexDesktopIPCError.peerMismatch }
    }
}

private final class DesktopIPCSocket: @unchecked Sendable {
    let chunks: AsyncStream<Data>
    private let handle: FileHandle
    private let continuation: AsyncStream<Data>.Continuation
    private let writeLock = NSLock()
    private let readPermit = DispatchSemaphore(value: 1)
    private var closed = false
    init(fd: Int32) {
        let pair = AsyncStream<Data>.makeStream(bufferingPolicy: .bufferingOldest(1))
        chunks = pair.stream; continuation = pair.continuation
        handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        handle.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            // One in-flight chunk supplies backpressure during large-frame drain.
            // Never wait while holding the fd lock; close wakes this permit.
            self.readPermit.wait()
            // FileHandle.read(upToCount:) can wait to fill its requested
            // length on a socket. Native initialize replies are short frames
            // on a connection that stays open; consume only available bytes.
            switch self.readAvailable() {
            case .data(let data):
                switch self.continuation.yield(data) {
                case .enqueued: break
                case .dropped, .terminated: self.close()
                @unknown default: self.close()
                }
            case .retry: self.readPermit.signal()
            case .closed: self.close()
            }
        }
    }
    func acknowledgeRead() { readPermit.signal() }
    private enum ReadResult { case data(Data), retry, closed }
    private func readAvailable() -> ReadResult {
        // Nonblocking recv makes it safe to share this lock with close: no
        // callback can read a descriptor after close/reuse, and shutdown never
        // waits for a reader that is trying to fill an entire buffer.
        writeLock.lock(); defer { writeLock.unlock() }
        guard !closed else { return .closed }
        var bytes = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = bytes.withUnsafeMutableBytes {
                Darwin.recv(handle.fileDescriptor, $0.baseAddress, $0.count, MSG_DONTWAIT)
            }
            if count > 0 { return .data(Data(bytes.prefix(count))) }
            if count == 0 { return .closed }
            if errno == EINTR { continue }
            if errno == EAGAIN || errno == EWOULDBLOCK { return .retry }
            return .closed
        }
    }
    func write(_ data: Data) throws {
        writeLock.lock(); defer { writeLock.unlock() }
        guard !closed else { throw CodexDesktopIPCError.unavailable }
        try handle.write(contentsOf: data)
    }
    func close() {
        writeLock.lock()
        guard !closed else { writeLock.unlock(); return }
        closed = true; writeLock.unlock()
        // Wake a waiting callback before removing its handler. Closed readers
        // cannot touch the fd, so teardown needs neither its lock nor permit.
        readPermit.signal()
        handle.readabilityHandler = nil; try? handle.close(); continuation.finish()
    }
}

/// Bounded JSON tree, used only for atomic desktop Immer patch reconstruction.
indirect enum DesktopIPCJSON: Equatable, Codable, Sendable {
    case object([String: Self]), array([Self]), string(String), integer(Int64), number(Double), bool(Bool), null
    var object: [String: Self]? { if case .object(let value) = self { return value }; return nil }
    var array: [Self]? { if case .array(let value) = self { return value }; return nil }
    var string: String? { if case .string(let value) = self { return value }; return nil }
    var integer: Int64? { if case .integer(let value) = self { return value }; return nil }
    var bool: Bool? { if case .bool(let value) = self { return value }; return nil }
    subscript(_ key: String) -> Self? { object?[key] }
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let bool = try? value.decode(Bool.self) { self = .bool(bool) }
        else if let integer = try? value.decode(Int64.self) { self = .integer(integer) }
        else if let number = try? value.decode(Double.self), number.isFinite { self = .number(number) }
        else if let string = try? value.decode(String.self) { self = .string(string) }
        else if let array = try? value.decode([Self].self) { self = .array(array) }
        else { self = .object(try value.decode([String: Self].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .object(let object): try value.encode(object)
        case .array(let array): try value.encode(array)
        case .string(let string): try value.encode(string)
        case .integer(let integer): try value.encode(integer)
        case .number(let number): try value.encode(number)
        case .bool(let bool): try value.encode(bool)
        case .null: try value.encodeNil()
        }
    }
    func encode() throws -> Data { let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return try encoder.encode(self) }
    /// Upper bound for the compact JSON encoding. Count once for snapshots;
    /// patches subtract/replace only their affected leaves, including commas
    /// and keys. No complete-history encoding or scan is needed per patch.
    var budgetByteCount: Int {
        switch self {
        case .object(let values):
            return 2 + max(0, values.count - 1) + values.reduce(0) {
                $0 + Self.stringBudget($1.key) + 1 + $1.value.budgetByteCount
            }
        case .array(let values): return 2 + max(0, values.count - 1) + values.reduce(0) { $0 + $1.budgetByteCount }
        case .string(let value): return Self.stringBudget(value)
        case .integer(let value): return String(value).utf8.count
        case .number: return 32 // Includes exponent/sign for every finite Double.
        case .bool(let value): return value ? 4 : 5
        case .null: return 4
        }
    }
    private static func stringBudget(_ value: String) -> Int {
        var count = 2
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 8, 9, 10, 12, 13, 34, 47, 92: count += 2
            case 0...31, 0x2028, 0x2029: count += 6
            case 0...0x7f: count += 1
            case 0...0x7ff: count += 2
            case 0...0xffff: count += 3
            default: count += 4
            }
        }
        return count
    }
    static func decode(_ data: Data, limit: Int, maximumNodes: Int = 100_000) throws -> Self {
        guard data.count <= limit else { throw CodexDesktopIPCError.resourceLimit }
        let value = try JSONDecoder().decode(Self.self, from: data)
        var nodes = 0
        func bounded(_ value: Self, depth: Int) -> Bool {
            nodes += 1; guard depth <= 64, nodes <= maximumNodes else { return false }
            switch value {
            case .object(let object): return object.values.allSatisfy { bounded($0, depth: depth + 1) }
            case .array(let array): return array.allSatisfy { bounded($0, depth: depth + 1) }
            default: return true
            }
        }
        guard bounded(value, depth: 0) else { throw CodexDesktopIPCError.resourceLimit }
        return value
    }
    static func applying(_ patches: [Self], to state: Self, byteCount: inout Int) throws -> Self {
        var candidate = state
        for patch in patches {
            guard let operation = patch["op"]?.string, ["add", "remove", "replace"].contains(operation),
                  let path = patch["path"]?.array, !path.isEmpty, path.count <= 64,
                  operation == "remove" || patch["value"] != nil else { throw CodexDesktopIPCError.invalidMessage }
            candidate = try candidate.patch(path[...], operation: operation, value: patch["value"], byteCount: &byteCount)
        }
        return candidate
    }
    private func patch(_ path: ArraySlice<Self>, operation: String, value: Self?, byteCount: inout Int) throws -> Self {
        guard let component = path.first else { throw CodexDesktopIPCError.invalidMessage }
        let tail = path.dropFirst()
        switch self {
        case .object(var object):
            guard let key = component.string else { throw CodexDesktopIPCError.invalidMessage }
            if tail.isEmpty {
                if operation == "remove" {
                    guard let removed = object.removeValue(forKey: key) else { throw CodexDesktopIPCError.invalidMessage }
                    byteCount -= Self.stringBudget(key) + 1 + removed.budgetByteCount + (object.isEmpty ? 0 : 1)
                } else {
                    guard operation == "add" || object[key] != nil else { throw CodexDesktopIPCError.invalidMessage }
                    if let previous = object[key] { byteCount += value!.budgetByteCount - previous.budgetByteCount }
                    else { byteCount += Self.stringBudget(key) + 1 + value!.budgetByteCount + (object.isEmpty ? 0 : 1) }
                    object[key] = value!
                }
            } else {
                guard let child = object[key] else { throw CodexDesktopIPCError.invalidMessage }
                object[key] = try child.patch(tail, operation: operation, value: value, byteCount: &byteCount)
            }
            return .object(object)
        case .array(var array):
            guard let raw = component.integer, raw >= 0, raw <= Int64(array.count) else { throw CodexDesktopIPCError.invalidMessage }
            let index = Int(raw)
            if tail.isEmpty {
                if operation == "add" {
                    byteCount += value!.budgetByteCount + (array.isEmpty ? 0 : 1)
                    array.insert(value!, at: index)
                } else {
                    guard index < array.count else { throw CodexDesktopIPCError.invalidMessage }
                    if operation == "remove" {
                        byteCount -= array[index].budgetByteCount + (array.count > 1 ? 1 : 0)
                        array.remove(at: index)
                    } else {
                        byteCount += value!.budgetByteCount - array[index].budgetByteCount
                        array[index] = value!
                    }
                }
            } else {
                guard index < array.count else { throw CodexDesktopIPCError.invalidMessage }
                array[index] = try array[index].patch(tail, operation: operation, value: value, byteCount: &byteCount)
            }
            return .array(array)
        default: throw CodexDesktopIPCError.invalidMessage
        }
    }
}
