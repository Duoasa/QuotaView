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
    public let conversationID: String
    public let hostID: String
    public let ownerClientID: String
    public let connectionEpoch: UInt64
    public let revision: Int64
    /// Bounded, transient in-memory desktop state. Never persisted or logged.
    public let conversationState: Data
    public let supportsUntrustedAppInput: Bool
    public let requests: [CodexDesktopIPCRequestHandle]
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
        public init(isEnabled: Bool = true, socketURL: URL,
                    requestTimeoutSeconds: TimeInterval = 5,
                    maximumFrameBytes: Int = 9_437_184,
                    maximumRetainedStateBytes: Int = 33_554_432) {
            self.isEnabled = isEnabled; self.socketURL = socketURL
            self.requestTimeoutSeconds = max(0.05, requestTimeoutSeconds)
            self.maximumFrameBytes = max(1024, min(maximumFrameBytes, 9_437_184))
            self.maximumRetainedStateBytes = max(self.maximumFrameBytes, min(maximumRetainedStateBytes, 33_554_432))
        }
        public static func live(environment: [String: String] = ProcessInfo.processInfo.environment) -> Self {
            let root = environment["CODEX_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
            return .init(socketURL: root.appendingPathComponent("ipc/ipc.sock"))
        }
    }
    private struct FollowKey: Hashable { let conversationID: String; let hostID: String }
    private struct Owner { let clientID: String; let supportsInput: Bool }
    private struct Ledger {
        var owner: Owner
        var revision: Int64
        var state: DesktopIPCJSON
        var encoded: Data
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
    private var decoder: CodexDesktopIPCFrameDecoder
    private var pending: [String: Pending] = [:]
    private var follows: Set<FollowKey> = []
    private var followingInFlight: Set<FollowKey> = []
    private var followRecoveries: [FollowKey: FollowRecovery] = [:]
    private var owners: [FollowKey: Owner] = [:]
    private var ledger: [FollowKey: Ledger] = [:]
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
        owners.removeValue(forKey: key); removeLedger(key)
        if initialized {
            try? broadcast(method: "thread-stream-following-changed", version: 1,
                           params: ["conversationId": .string(conversationID), "hostId": .string(hostID), "following": .bool(false)])
        }
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
                do { try await self?.consume(chunk, epoch: run) }
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
        guard initialized, follows.contains(key), !resourceBlockedFollows.contains(key), !followingInFlight.contains(key) else { return }
        if candidateOwner == nil, owners[key] != nil { return }
        followingInFlight.insert(key); let run = epoch
        defer { if run == epoch { followingInFlight.remove(key) } }
        let response = try await requestEnvelope(method: "thread-owner-discovery", version: 1,
                                                 targetOwner: candidateOwner,
                                                 params: ["conversationId": .string(key.conversationID), "hostId": .string(key.hostID)])
        let message = try DesktopIPCJSON.decode(response, limit: configuration.maximumFrameBytes)
        guard run == epoch, initialized, follows.contains(key), !resourceBlockedFollows.contains(key), !Task.isCancelled,
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
        for data in try decoder.append(chunk) {
            guard run == epoch, started else { return }
            try await handle(data, epoch: run)
        }
    }
    private func handle(_ data: Data, epoch run: UInt64) async throws {
        let message = try DesktopIPCJSON.decode(data, limit: configuration.maximumFrameBytes)
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
        guard message["version"]?.integer == 11 else {
            incompatible = true; await closeConnection(); return
        }
        guard let source = message["sourceClientId"]?.string, let owner = owners[key] else { return }
        guard source == owner.clientID else {
            removeLedger(key)
            scheduleFollowRecovery(key, candidateOwner: source); return
        }
        guard let change = params["change"], let revision = change["revision"]?.integer, revision >= 0 else {
            throw CodexDesktopIPCError.invalidMessage
        }
        let state: DesktopIPCJSON
        switch change["type"]?.string {
        case "snapshot":
            guard let candidate = change["conversationState"], candidate["id"]?.string == conversation else { throw CodexDesktopIPCError.invalidMessage }
            if let previous = ledger[key], revision < previous.revision { return }
            state = candidate
        case "patches":
            guard let entry = ledger[key], change["baseRevision"]?.integer == entry.revision,
                  revision > entry.revision, let patches = change["patches"]?.array else {
                removeLedger(key)
                try broadcast(method: "thread-stream-following-changed", version: 1,
                              params: ["conversationId": .string(conversation), "hostId": .string(host), "following": .bool(true)], targets: [source]); return
            }
            guard patches.count <= 1024 else { await invalidateResourceLimit(key, epoch: run); return }
            do { state = try DesktopIPCJSON.applying(patches, to: entry.state) }
            catch { removeLedger(key); throw CodexDesktopIPCError.invalidMessage }
            guard state["id"]?.string == conversation else { throw CodexDesktopIPCError.invalidMessage }
        default: throw CodexDesktopIPCError.invalidMessage
        }
        let encoded = try state.encode()
        let retained = ledger.filter { $0.key != key }.reduce(encoded.count) { $0 + $1.value.encoded.count }
        guard encoded.count <= CodexDesktopRequestProjector.maximumStateBytes,
              retained <= configuration.maximumRetainedStateBytes else {
            await invalidateResourceLimit(key, epoch: run); return
        }
        guard let requests = state["requests"]?.array else { throw CodexDesktopIPCError.invalidMessage }
        guard requests.count <= CodexDesktopRequestProjector.maximumPendingRequests else {
            await invalidateResourceLimit(key, epoch: run); return
        }
        let projection: CodexDesktopInteractionProjection
        do { projection = try CodexDesktopRequestProjector.project(conversationID: conversation, conversationStateData: encoded) }
        catch CodexDesktopRequestProjectionError.oversizedState {
            await invalidateResourceLimit(key, epoch: run); return
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
        ledger[key] = .init(owner: owner, revision: revision, state: state, encoded: encoded, handles: handles)
        if change["type"]?.string == "snapshot", let waiters = snapshotWaiters.removeValue(forKey: key) {
            for waiter in waiters.values { waiter.timer.cancel(); waiter.continuation.resume() }
        }
        await snapshotHandler?(.init(conversationID: conversation, hostID: host, ownerClientID: source,
                                     connectionEpoch: run, revision: revision, conversationState: encoded,
                                     supportsUntrustedAppInput: owner.supportsInput && host == "local" && projection.pendingRequestsAreAuthoritative, requests: handles))
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
    private func invalidateResourceLimit(_ key: FollowKey, epoch run: UInt64) async {
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
            connectionEpoch: run, reason: .resourceLimit))
    }
    private func suspendForResourceLimit(epoch run: UInt64) async {
        guard run == epoch else { return }
        // A frame header has no trustworthy conversation scope. Stop automatic
        // observation until an explicit start; never classify size as a version
        // mismatch or repeatedly reconnect into the same oversized snapshot.
        resourceSuspended = true
        await invalidationHandler?(.init(conversationID: nil, hostID: nil,
            connectionEpoch: run, reason: .resourceLimit))
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

struct CodexDesktopIPCTransport: Sendable {
    let chunks: AsyncStream<Data>
    let write: @Sendable (Data) throws -> Void
    let close: @Sendable () -> Void
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
            return .init(chunks: socket.chunks, write: { try socket.write($0) }, close: { socket.close() })
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
    private var closed = false
    init(fd: Int32) {
        let pair = AsyncStream<Data>.makeStream(bufferingPolicy: .bufferingOldest(128))
        chunks = pair.stream; continuation = pair.continuation
        handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        handle.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            do {
                let data = try handle.read(upToCount: 65_536) ?? Data()
                guard !data.isEmpty else { self.close(); return }
                switch self.continuation.yield(data) {
                case .enqueued: break
                case .dropped, .terminated: self.close()
                @unknown default: self.close()
                }
            } catch { self.close() }
        }
    }
    func write(_ data: Data) throws {
        writeLock.lock(); defer { writeLock.unlock() }
        guard !closed else { throw CodexDesktopIPCError.unavailable }
        try handle.write(contentsOf: data)
    }
    func close() {
        writeLock.lock(); defer { writeLock.unlock() }
        guard !closed else { return }; closed = true
        handle.readabilityHandler = nil; try? handle.close(); continuation.finish()
    }
}

/// Bounded JSON tree, used only for atomic desktop Immer patch reconstruction.
fileprivate indirect enum DesktopIPCJSON: Equatable, Codable {
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
    static func decode(_ data: Data, limit: Int) throws -> Self {
        guard data.count <= limit else { throw CodexDesktopIPCError.resourceLimit }
        let value = try JSONDecoder().decode(Self.self, from: data)
        var nodes = 0
        func bounded(_ value: Self, depth: Int) -> Bool {
            nodes += 1; guard depth <= 64, nodes <= 100_000 else { return false }
            switch value {
            case .object(let object): return object.values.allSatisfy { bounded($0, depth: depth + 1) }
            case .array(let array): return array.allSatisfy { bounded($0, depth: depth + 1) }
            default: return true
            }
        }
        guard bounded(value, depth: 0) else { throw CodexDesktopIPCError.resourceLimit }
        return value
    }
    static func applying(_ patches: [Self], to state: Self) throws -> Self {
        var candidate = state
        for patch in patches {
            guard let operation = patch["op"]?.string, ["add", "remove", "replace"].contains(operation),
                  let path = patch["path"]?.array, !path.isEmpty, path.count <= 64,
                  operation == "remove" || patch["value"] != nil else { throw CodexDesktopIPCError.invalidMessage }
            candidate = try candidate.patch(path[...], operation: operation, value: patch["value"])
        }
        return candidate
    }
    private func patch(_ path: ArraySlice<Self>, operation: String, value: Self?) throws -> Self {
        guard let component = path.first else { throw CodexDesktopIPCError.invalidMessage }
        let tail = path.dropFirst()
        switch self {
        case .object(var object):
            guard let key = component.string else { throw CodexDesktopIPCError.invalidMessage }
            if tail.isEmpty {
                if operation == "remove" { guard object.removeValue(forKey: key) != nil else { throw CodexDesktopIPCError.invalidMessage } }
                else { guard operation == "add" || object[key] != nil else { throw CodexDesktopIPCError.invalidMessage }; object[key] = value! }
            } else { guard let child = object[key] else { throw CodexDesktopIPCError.invalidMessage }; object[key] = try child.patch(tail, operation: operation, value: value) }
            return .object(object)
        case .array(var array):
            guard let raw = component.integer, raw >= 0, raw <= Int64(array.count) else { throw CodexDesktopIPCError.invalidMessage }
            let index = Int(raw)
            if tail.isEmpty {
                if operation == "add" { array.insert(value!, at: index) }
                else { guard index < array.count else { throw CodexDesktopIPCError.invalidMessage }; if operation == "remove" { array.remove(at: index) } else { array[index] = value! } }
            } else { guard index < array.count else { throw CodexDesktopIPCError.invalidMessage }; array[index] = try array[index].patch(tail, operation: operation, value: value) }
            return .array(array)
        default: throw CodexDesktopIPCError.invalidMessage
        }
    }
}
