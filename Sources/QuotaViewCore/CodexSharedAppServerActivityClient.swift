import CryptoKit
import CoreFoundation
import Darwin
import Foundation

public enum CodexSharedAppServerConnectionState: String, Sendable {
    case disabled
    case discovering
    case connected
}

public actor CodexSharedAppServerActivityClient {
    public nonisolated static let contentNotificationOptOutMethods = [
        "turn/diff/updated",
        // Item lifecycle carries contextCompaction. The decoder projects only
        // compaction metadata and immediately discards every other item.
        "item/agentMessage/delta",
        "item/plan/delta",
        "item/reasoning/summaryTextDelta",
        "item/reasoning/summaryPartAdded",
        "item/reasoning/textDelta",
        "item/commandExecution/outputDelta",
        "item/fileChange/outputDelta",
        "command/exec/outputDelta",
        "hook/started",
        "hook/completed"
    ]

    public enum ClientError: LocalizedError, Equatable {
        case executableNotFound
        case launchFailed(String)
        case socketPathTooLong
        case connectionFailed(String)
        case invalidHandshake
        case connectionClosed
        case invalidMessage
        case requestTimedOut(String)
        case messageTooLarge
        case server(code: Int?, message: String)

        public var errorDescription: String? {
            switch self {
            case .executableNotFound:
                "找不到 Codex，无法启动共享 App Server。"
            case .launchFailed(let message):
                "无法启动共享 Codex App Server：\(message)"
            case .socketPathTooLong:
                "Codex App Server socket 路径过长。"
            case .connectionFailed(let message):
                "无法连接共享 Codex App Server：\(message)"
            case .invalidHandshake:
                "共享 Codex App Server WebSocket 握手无效。"
            case .connectionClosed:
                "共享 Codex App Server 已断开连接。"
            case .invalidMessage:
                "共享 Codex App Server 返回了无法识别的数据。"
            case .requestTimedOut(let method):
                "共享 Codex App Server 的 \(method) 请求超时。"
            case .messageTooLarge:
                "共享 Codex App Server 返回的数据超过安全大小限制。"
            case .server(_, let message):
                "共享 Codex App Server 返回错误：\(message)"
            }
        }
    }

    public struct Configuration: Sendable, Equatable {
        public let isEnabled: Bool
        public let socketURL: URL
        public let executablePath: String?
        public let launchServerIfNeeded: Bool
        public let startupTimeoutSeconds: TimeInterval
        public let requestTimeoutSeconds: TimeInterval
        public let subscriptionPollSeconds: TimeInterval
        public let maximumMessageBytes: Int
        public let clientVersion: String

        public init(
            isEnabled: Bool,
            socketURL: URL,
            executablePath: String?,
            launchServerIfNeeded: Bool = false,
            startupTimeoutSeconds: TimeInterval = 8,
            requestTimeoutSeconds: TimeInterval = 5,
            subscriptionPollSeconds: TimeInterval = 0.5,
            maximumMessageBytes: Int =
                CodexAppServerActivityNotificationDecoder.maximumMessageBytes,
            clientVersion: String = Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "0.4.5"
        ) {
            self.isEnabled = isEnabled
            self.socketURL = socketURL
            self.executablePath = executablePath
            self.launchServerIfNeeded = launchServerIfNeeded
            self.startupTimeoutSeconds = max(startupTimeoutSeconds, 1)
            self.requestTimeoutSeconds = max(requestTimeoutSeconds, 1)
            self.subscriptionPollSeconds = max(
                subscriptionPollSeconds,
                0.2
            )
            self.maximumMessageBytes = max(maximumMessageBytes, 1_024)
            self.clientVersion = clientVersion
        }

        public static func live(
            environment: [String: String] =
                ProcessInfo.processInfo.environment,
            fileManager: FileManager = .default
        ) -> Configuration {
            Configuration(
                isEnabled: !Self.isAutomaticDiscoveryDisabled(
                    environment: environment
                ),
                socketURL: Self.defaultSocketURL(
                    environment: environment,
                    fileManager: fileManager
                ),
                executablePath: CodexExecutableLocator.locate(
                    environment: environment,
                    fileManager: fileManager
                ),
                launchServerIfNeeded: Self.isSharedDaemonEnabled(
                    environment: environment
                )
            )
        }

        public static func isSharedDaemonEnabled(
            environment: [String: String]
        ) -> Bool {
            environment["CODEX_APP_SERVER_USE_LOCAL_DAEMON"] == "1"
        }

        public static func isAutomaticDiscoveryDisabled(
            environment: [String: String]
        ) -> Bool {
            environment["QUOTAVIEW_CODEX_SOCKET_DISABLED"] == "1"
        }

        public static func defaultSocketURL(
            environment: [String: String],
            fileManager: FileManager = .default
        ) -> URL {
            let codexHome: URL
            if let override = environment["CODEX_HOME"],
               !override.isEmpty {
                codexHome = URL(fileURLWithPath: override)
            } else {
                codexHome = fileManager.homeDirectoryForCurrentUser
                    .appendingPathComponent(".codex", isDirectory: true)
            }
            return codexHome
                .appendingPathComponent(
                    "app-server-control",
                    isDirectory: true
                )
                .appendingPathComponent("app-server-control.sock")
        }
    }

    private struct PendingRequest {
        let method: String
        let continuation: CheckedContinuation<Data, Error>
    }

    private struct EmptyResult: Decodable {}

    private struct LoadedThreadListResponse: Decodable {
        let data: [String]
        let nextCursor: String?
    }

    private let configuration: Configuration
    private let requestTimeoutNanoseconds: UInt64
    private let subscriptionPollNanoseconds: UInt64
    private var serverProcess: Process?
    private var openingSocket: CodexSocketOpening?
    private var openingSocketCloseObserver: (@Sendable (Int32) -> Void)?
    // Internal diagnostic injection: only the owned opening fd's close result,
    // with no application call site or process-wide resource assumption.
    func setOpeningSocketCloseObserver(_ observer: (@Sendable (Int32) -> Void)?) {
        openingSocketCloseObserver = observer
    }
    private var socketReader: CodexBoundedInputReader?
    private var socketHandle: FileHandle?
    private var readTask: Task<Void, Never>?
    private var maintenanceTask: Task<Void, Never>?
    private var pending: [Int: PendingRequest] = [:]
    private var nextRequestID = 1
    private var connectionGeneration: UInt64 = 0
    private var initialized = false
    private var isStarted = false
    private var runGeneration: UInt64 = 0
    private var subscribedThreadHashes: Set<String> = []
    private var threadKinds: [String: CodexActivitySessionKind] = [:]
    private var threadSubagents: [String: CodexActivitySubagentIdentity] = [:]
    private var frameDecoder = CodexAppServerWebSocketMessageDecoder()
    private var activityNotificationHandler:
        (@Sendable (CodexActivityEvent) async -> Void)?
    private var tokenUsageNotificationHandler:
        (@Sendable (CodexActivityTokenUsageUpdate) async -> Void)?
    private var publicMessageHandler: (@Sendable (Data) async -> Void)?
    public func setPublicMessageHandler(_ handler: (@Sendable (Data) async -> Void)?) { publicMessageHandler = handler }
    private var scopedPublicMessageHandler: (@Sendable (Data, UInt64) async -> Void)?
    public func setScopedPublicMessageHandler(_ handler: (@Sendable (Data, UInt64) async -> Void)?) {
        scopedPublicMessageHandler = handler
    }
    private struct ObservedServerRequest: Equatable {
        let threadID: String
        let turnID: String?
        let itemID: String?
    }
    private var ambiguousServerRequests: Set<String> = []
    private var observedServerRequests: [String: ObservedServerRequest] = [:]
    private var observedServerRequestOrder: [String] = []
    private var snapshotRefreshTasks: [String: Task<Void, Never>] = [:]
    private var hasPublicMessageHandler: Bool { publicMessageHandler != nil || scopedPublicMessageHandler != nil }

    private var connectionStateHandler:
        (@Sendable (CodexSharedAppServerConnectionState) async -> Void)?
    private var connectionState:
        CodexSharedAppServerConnectionState = .disabled

    public init(configuration: Configuration = .live()) {
        self.configuration = configuration
        requestTimeoutNanoseconds = UInt64(
            configuration.requestTimeoutSeconds * 1_000_000_000
        )
        subscriptionPollNanoseconds = UInt64(
            configuration.subscriptionPollSeconds * 1_000_000_000
        )
    }

    public func start(
        handler: @escaping @Sendable (CodexActivityEvent) async -> Void,
        tokenUsageHandler: (@Sendable (
            CodexActivityTokenUsageUpdate
        ) async -> Void)? = nil,
        connectionStateHandler: @escaping @Sendable (
            CodexSharedAppServerConnectionState
        ) async -> Void
    ) async {
        activityNotificationHandler = handler
        tokenUsageNotificationHandler = tokenUsageHandler
        self.connectionStateHandler = connectionStateHandler
        guard configuration.isEnabled else {
            await publishConnectionState(.disabled)
            return
        }
        guard !isStarted else {
            await connectionStateHandler(connectionState)
            return
        }
        isStarted = true
        runGeneration &+= 1
        let run = runGeneration
        await publishConnectionState(.discovering)
        guard isStarted, run == runGeneration else { return }
        let client = self
        maintenanceTask = Task(priority: .utility) {
            await client.runMaintenanceLoop(generation: run)
        }
    }

    public func stop() async {
        isStarted = false
        runGeneration &+= 1
        maintenanceTask?.cancel()
        maintenanceTask = nil
        activityNotificationHandler = nil
        publicMessageHandler = nil
        scopedPublicMessageHandler = nil
        tokenUsageNotificationHandler = nil
        closeConnection(error: ClientError.connectionClosed)

        // The App Server is shared with Codex Desktop. Never terminate a
        // process that may still be serving another connected client.
        serverProcess = nil
        let stoppedHandler = connectionStateHandler
        connectionStateHandler = nil
        connectionState = .disabled
        await stoppedHandler?(.disabled)
    }

    private func runMaintenanceLoop(generation run: UInt64) async {
        var retryDelayNanoseconds: UInt64 = 1_000_000_000
        let maximumRetryDelayNanoseconds: UInt64 = 8_000_000_000

        while isStarted, run == runGeneration, !Task.isCancelled {
            do {
                if !initialized {
                    try await connectAndInitialize(generation: run)
                    guard isStarted, run == runGeneration, !Task.isCancelled else { return }
                    retryDelayNanoseconds = 1_000_000_000
                }
                try await refreshThreadSubscriptions()
                try await Task.sleep(
                    nanoseconds: subscriptionPollNanoseconds
                )
            } catch is CancellationError {
                return
            } catch {
                guard isStarted, run == runGeneration, !Task.isCancelled else { return }
                closeConnection(error: error)
                await publishConnectionState(.discovering)
                try? await Task.sleep(
                    nanoseconds: retryDelayNanoseconds
                )
                retryDelayNanoseconds = min(
                    retryDelayNanoseconds * 2,
                    maximumRetryDelayNanoseconds
                )
            }
        }
    }

    private func connectAndInitialize(generation run: UInt64) async throws {
        closeConnection(error: ClientError.connectionClosed)

        let deadline = CodexSocketOpening.deadline(after: configuration.startupTimeoutSeconds)
        let opened: OpenedSocket
        do {
            opened = try await openSocket(deadline: deadline)
        } catch {
            guard isStarted, run == runGeneration, !Task.isCancelled else { throw CancellationError() }
            guard configuration.launchServerIfNeeded else { throw error }
            try launchServerIfNeeded()
            opened = try await waitForServerSocket(deadline: deadline)
        }

        guard isStarted, run == runGeneration, !Task.isCancelled else {
            Darwin.close(opened.fileDescriptor)
            throw CancellationError()
        }
        connectionGeneration &+= 1
        let generation = connectionGeneration
        let handle = FileHandle(
            fileDescriptor: opened.fileDescriptor,
            closeOnDealloc: true
        )
        socketHandle = handle
        frameDecoder = CodexAppServerWebSocketMessageDecoder(
            maximumMessageBytes: configuration.maximumMessageBytes
        )

        let socketReader = CodexBoundedInputReader(handle: handle, isSocket: true)
        self.socketReader = socketReader
        let client = self
        readTask = Task.detached(priority: .utility) {
            do {
                if !opened.remainingData.isEmpty {
                    try await client.consumeSocketData(
                        opened.remainingData,
                        generation: generation
                    )
                }
                for await chunk in socketReader.chunks {
                    defer { socketReader.acknowledgeRead() }
                    try Task.checkCancellation()
                    try await client.consumeSocketData(
                        chunk,
                        generation: generation
                    )
                }
                await client.connectionDidClose(generation: generation)
            } catch {
                await client.connectionDidFail(
                    error,
                    generation: generation
                )
            }
        }

        let _: EmptyResult = try await request(
            method: "initialize",
            params: [
                "clientInfo": [
                    "name": "quotaview",
                    "title": "QuotaView",
                    "version": configuration.clientVersion
                ],
                "capabilities": [
                    "optOutNotificationMethods": !hasPublicMessageHandler ? Self.contentNotificationOptOutMethods : Self.contentNotificationOptOutMethods.filter { $0.contains("reasoning") || $0.contains("hook/") }
                ]
            ]
        )
        guard isStarted, run == runGeneration, generation == connectionGeneration, !Task.isCancelled else {
            throw CancellationError()
        }
        try sendNotification(method: "initialized", params: [:])
        initialized = true
        subscribedThreadHashes.removeAll(keepingCapacity: true)
        threadKinds.removeAll(keepingCapacity: true)
        threadSubagents.removeAll(keepingCapacity: true)
        await publishConnectionState(.connected)
    }

    private func refreshThreadSubscriptions() async throws {
        let generation = connectionGeneration
        var cursor: String?
        var pageCount = 0

        repeat {
            var params: [String: Any] = ["limit": 100]
            if let cursor {
                params["cursor"] = cursor
            }
            let response: LoadedThreadListResponse = try await request(
                method: "thread/loaded/list",
                params: params
            )
            for threadID in response.data.prefix(100) {
                guard generation == connectionGeneration, !Task.isCancelled else { throw CancellationError() }
                do {
                    try await subscribeIfNeeded(threadID: threadID)
                } catch let error as ClientError {
                    guard case .server = error else { throw error }
                    // A just-created or externally removed thread can appear
                    // in the loaded list before its rollout is readable. One
                    // bad entry must not disconnect subscriptions for every
                    // other active thread; the next poll can retry it.
                    continue
                }
            }
            cursor = response.nextCursor
            pageCount += 1
        } while cursor != nil && pageCount < 10
    }

    private func subscribeIfNeeded(threadID: String) async throws {
        guard !threadID.isEmpty else { return }
        let hash = CodexActivityPrivacy.hashIdentifier(threadID)
        guard !subscribedThreadHashes.contains(hash), subscribedThreadHashes.count < 1024 else { return }

        let generation = connectionGeneration
        let data = try await requestData(
            method: "thread/resume",
            params: [
                "threadId": threadID,
                "excludeTurns": true
            ]
        )
        guard generation == connectionGeneration else { return }
        if let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let thread = result["thread"] as? [String: Any], thread["id"] as? String == threadID {
            rememberThread(thread, hash: hash)
            if Self.observesMetadata(threadKinds[hash]), hasPublicMessageHandler {
                await publishThreadSnapshot(thread, threadID: threadID, generation: generation)
            }
        } else if threadKinds[hash] == nil { threadKinds[hash] = .unknown }
        subscribedThreadHashes.insert(hash)
    }

    private func publishThreadSnapshot(_ thread: [String: Any], threadID: String, generation: UInt64) async {
        var params: [String: Any] = ["thread": projectedThreadMetadata(thread)]
        if Self.observesLifecycle(threadKinds[CodexActivityPrivacy.hashIdentifier(threadID)]),
           (thread["status"] as? [String: Any])?["type"] as? String == "active",
           let current = try? await currentTurn(threadID: threadID), generation == connectionGeneration {
            params["currentTurn"] = current
        }
        guard generation == connectionGeneration else { return }
        if let envelope = try? JSONSerialization.data(withJSONObject: ["method": "thread/snapshot", "params": params]) {
            await publishPublicMessage(envelope, generation: generation)
        }
    }

    private func scheduleCurrentThreadSnapshot(threadID: String) {
        let hash = CodexActivityPrivacy.hashIdentifier(threadID)
        guard isStarted, hasPublicMessageHandler, Self.observesMetadata(threadKinds[hash]),
              snapshotRefreshTasks[hash] == nil, snapshotRefreshTasks.count < 8 else { return }
        let generation = connectionGeneration
        snapshotRefreshTasks[hash] = Task { [weak self] in
            guard let self else { return }
            await self.refreshCurrentThreadSnapshot(threadID: threadID, generation: generation)
        }
    }

    private func refreshCurrentThreadSnapshot(threadID: String, generation: UInt64) async {
        defer { if generation == connectionGeneration { snapshotRefreshTasks.removeValue(forKey: CodexActivityPrivacy.hashIdentifier(threadID)) } }
        guard generation == connectionGeneration, !Task.isCancelled,
              let data = try? await requestData(method: "thread/read", params: ["threadId": threadID, "includeTurns": false]),
              generation == connectionGeneration, !Task.isCancelled,
              let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let thread = result["thread"] as? [String: Any], thread["id"] as? String == threadID else { return }
        rememberThread(thread, hash: CodexActivityPrivacy.hashIdentifier(threadID))
        guard Self.observesMetadata(threadKinds[CodexActivityPrivacy.hashIdentifier(threadID)]) else { return }
        await publishThreadSnapshot(thread, threadID: threadID, generation: generation)
    }

    private func currentTurn(threadID: String) async throws -> [String: Any]? {
        let data = try await requestData(method: "thread/turns/list", params: [
            "threadId": threadID, "limit": 1, "sortDirection": "desc", "itemsView": "notLoaded"
        ])
        guard let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let turns = response["data"] as? [[String: Any]], turns.count == 1,
              let turn = turns.first, turn["status"] as? String == "inProgress",
              let id = turn["id"] as? String, !id.isEmpty else { return nil }
        var clean: [String: Any] = ["id": id, "status": "inProgress"]
        if let value = turn["startedAt"] as? NSNumber, value.doubleValue.isFinite, value.doubleValue >= 0 {
            clean["startedAtMs"] = value.doubleValue * 1_000
        } else if let value = turn["startedAtMs"] as? NSNumber, value.doubleValue.isFinite, value.doubleValue >= 0 {
            clean["startedAtMs"] = value
        }
        return clean
    }

    private static func publicThreadMetadata(_ thread: [String: Any]) -> [String: Any] {
        var clean: [String: Any] = [:]
        for key in ["id", "name", "title", "model", "reasoningEffort", "effort", "source", "threadSource", "status",
                    "parentThreadId", "agentNickname", "agentRole"] {
            if let value = thread[key] { clean[key] = value }
        }
        // Raw Core/SQLite metadata uses snake case; consumers use the API name.
        if let value = thread["threadSource"] as? String ?? thread["thread_source"] as? String { clean["threadSource"] = value }
        for (api, core) in [("parentThreadId", "parent_thread_id"), ("agentNickname", "agent_nickname"), ("agentRole", "agent_role")] {
            if let value = thread[api] as? String ?? thread[core] as? String { clean[api] = value }
        }
        return clean
    }

    private func projectedThreadMetadata(_ thread: [String: Any]) -> [String: Any] {
        var clean = Self.publicThreadMetadata(thread)
        if let id = thread["id"] as? String {
            let hash = CodexActivityPrivacy.hashIdentifier(id)
            if threadKinds[hash] == .subagent, let prior = threadSubagents[hash],
               CodexActivitySubagentIdentity.decode(thread) == nil {
                // Sparse resume/read replies inherit only the parent verified
                // for this thread on this connection, never a title guess.
                clean["parentThreadId"] = prior.parentThreadID
                if clean["agentNickname"] == nil { clean["agentNickname"] = prior.nickname }
                if clean["agentRole"] == nil { clean["agentRole"] = prior.role }
                if clean["name"] == nil, clean["title"] == nil { clean["title"] = prior.title }
            }
        }
        return clean
    }

    private static func observesLifecycle(_ kind: CodexActivitySessionKind?) -> Bool {
        kind == .user || kind == .memoryConsolidation || kind == .subagent
    }

    private static func observesMetadata(_ kind: CodexActivitySessionKind?) -> Bool {
        observesLifecycle(kind) || kind == .internalTask
    }

    private func publishPublicMessage(_ data: Data, generation: UInt64) async {
        guard generation == connectionGeneration else { return }
        if let scopedPublicMessageHandler { await scopedPublicMessageHandler(data, generation) }
        guard generation == connectionGeneration else { return }
        if let publicMessageHandler { await publicMessageHandler(data) }
    }

    private static func rpcKey(_ raw: Any?) -> String? {
        guard let raw else { return nil }
        if let text = raw as? String { return "s:" + text }
        guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite,
              let data = try? JSONSerialization.data(withJSONObject: number, options: [.fragmentsAllowed]) else { return nil }
        return "n:" + String(decoding: data, as: UTF8.self)
    }

    private func publicProjection(_ message: [String: Any]) -> [String: Any]? {
        guard let method = message["method"] as? String, !method.contains("reasoning"), !method.contains("hook/"),
              var params = message["params"] as? [String: Any],
              (params["item"] as? [String: Any])?["type"] as? String != "reasoning" else { return nil }
        if method == "serverRequest/resolved" {
            guard let key = Self.rpcKey(params["requestId"]), !ambiguousServerRequests.contains(key),
                  let observed = observedServerRequests[key] else { return nil }
            if let thread = params["threadId"] as? String, thread != observed.threadID { return nil }
            if let turn = params["turnId"] as? String, let expected = observed.turnID, turn != expected { return nil }
            params["threadId"] = observed.threadID
            if params["turnId"] == nil, let turn = observed.turnID { params["turnId"] = turn }
            observedServerRequests.removeValue(forKey: key)
            observedServerRequestOrder.removeAll { $0 == key }
        }
        guard let threadID = params["threadId"] as? String ?? (params["thread"] as? [String: Any])?["id"] as? String,
              let kind = threadKinds[CodexActivityPrivacy.hashIdentifier(threadID)],
              Self.observesMetadata(kind) else { return nil }
        if let thread = params["thread"] as? [String: Any],
           let incoming = CodexActivitySubagentIdentity.decode(thread),
           let prior = threadSubagents[CodexActivityPrivacy.hashIdentifier(threadID)],
           incoming.parentSessionHash != prior.parentSessionHash { return nil }
        if let thread = params["thread"] as? [String: Any] { params["thread"] = projectedThreadMetadata(thread) }
        // Background/internal identity reaches Store even when it retracts a
        // previously displayed task. Its content and RPCs never acquire ownership.
        if kind == .memoryConsolidation || kind == .internalTask {
            guard message["id"] == nil, ["thread/started", "thread/snapshot"].contains(method),
                  let thread = params["thread"] as? [String: Any] else { return nil }
            var metadata: [String: Any] = ["thread": Self.publicThreadMetadata(thread)]
            if kind == .memoryConsolidation, let current = params["currentTurn"] as? [String: Any] {
                metadata["currentTurn"] = current.filter { ["id", "status", "startedAtMs"].contains($0.key) }
            }
            return ["method": method, "params": metadata]
        }
        if kind == .subagent {
            guard threadSubagents[CodexActivityPrivacy.hashIdentifier(threadID)] != nil else { return nil }
            if params["thread"] == nil {
                // Each child envelope carries this connection's verified parent
                // scope, so Store origin-LRU loss cannot turn a sparse event into
                // the generic user fallback or detach its child relationship.
                params["thread"] = projectedThreadMetadata(["id": threadID])
            }
            return Self.subagentPublicProjection(message, method: method, params: params)
        }
        if let rpc = Self.rpcKey(message["id"]), ["item/commandExecution/requestApproval", "item/fileChange/requestApproval",
            "item/permissions/requestApproval", "item/tool/requestUserInput", "mcpServer/elicitation/request"].contains(method) {
            let request = ObservedServerRequest(threadID: threadID, turnID: params["turnId"] as? String,
                itemID: params["itemId"] as? String)
            if let previous = observedServerRequests[rpc], previous != request { ambiguousServerRequests.insert(rpc) }
            else { observedServerRequests[rpc] = request }
            observedServerRequestOrder.removeAll { $0 == rpc }; observedServerRequestOrder.append(rpc)
            while observedServerRequestOrder.count > 256 {
                let oldest = observedServerRequestOrder.removeFirst()
                observedServerRequests.removeValue(forKey: oldest); ambiguousServerRequests.remove(oldest)
            }
        }
        if let thread = params["thread"] as? [String: Any] { params["thread"] = Self.publicThreadMetadata(thread) }
        var clean = message; clean["params"] = params
        return clean
    }

    /// Child transport is an observation lane. Its public progress and exact
    /// lifecycle never enter the ordinary user RPC/request ownership map.
    private static func subagentPublicProjection(_ message: [String: Any], method: String,
                                                params: [String: Any]) -> [String: Any]? {
        let allowed = ["thread/started", "thread/snapshot", "thread/status/changed", "turn/started", "turn/completed",
            "item/started", "item/completed", "item/agentMessage/delta", "item/commandExecution/outputDelta"]
        guard message["id"] == nil, allowed.contains(method) else { return nil }
        var clean = params.filter { ["threadId", "turnId", "itemId", "status", "emittedAtMs"].contains($0.key) }
        if let thread = params["thread"] as? [String: Any] { clean["thread"] = publicThreadMetadata(thread) }
        for key in ["turn", "currentTurn"] {
            if let turn = params[key] as? [String: Any] {
                clean[key] = turn.filter { ["id", "status", "startedAtMs", "completedAtMs"].contains($0.key) }
            }
        }
        if ["item/started", "item/completed"].contains(method) {
            guard let item = params["item"] as? [String: Any], let type = item["type"] as? String,
                  ["agentMessage", "commandExecution", "fileChange", "mcpToolCall", "dynamicToolCall", "webSearch",
                   "collabToolCall", "contextCompaction"].contains(type) else { return nil }
            clean["item"] = item.filter { ["id", "type", "text", "phase", "command", "status", "tool", "name",
                "server", "query", "changes", "arguments", "agentStatus", "receiverThreadIds", "senderThreadId"].contains($0.key) }
        } else if ["item/agentMessage/delta", "item/commandExecution/outputDelta"].contains(method),
                  let delta = params["delta"] as? String {
            clean["delta"] = delta
        }
        var envelope: [String: Any] = ["method": method, "params": clean]
        if let emitted = message["emittedAtMs"] { envelope["emittedAtMs"] = emitted }
        return envelope
    }

    private func rememberThread(_ thread: [String: Any], hash: String) {
        if threadKinds.count >= 1024, threadKinds[hash] == nil { return }
        let incoming = CodexActivitySessionKind.classify(metadata: thread)
        let previous = threadKinds[hash] ?? .unknown
        if incoming == .subagent, let child = CodexActivitySubagentIdentity.decode(thread) {
            // A later source subtype may refine generic internal, but an
            // existing verified parent must never be silently reassigned.
            if let prior = threadSubagents[hash], prior.parentSessionHash != child.parentSessionHash {
                threadKinds[hash] = .internalTask
                return
            }
            threadSubagents[hash] = child
            threadKinds[hash] = previous == .memoryConsolidation ? previous : .subagent
        } else {
            threadKinds[hash] = incoming == .internalTask ? .internalTask : .resolving(previous, incoming)
        }
    }

    private func request<Response: Decodable>(
        method: String,
        params: [String: Any]
    ) async throws -> Response {
        let data = try await requestData(method: method, params: params)
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw ClientError.invalidMessage
        }
    }

    private func requestData(
        method: String,
        params: [String: Any]
    ) async throws -> Data {
        guard socketHandle != nil else {
            throw ClientError.connectionClosed
        }

        let id = nextRequestID
        nextRequestID += 1

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[id] = PendingRequest(
                    method: method,
                    continuation: continuation
                )
                do {
                    try writeJSONMessage([
                        "method": method,
                        "id": id,
                        "params": params
                    ])
                } catch {
                    pending.removeValue(forKey: id)
                    continuation.resume(throwing: error)
                    return
                }

                Task { [weak self] in
                    try? await Task.sleep(
                        nanoseconds: self?.requestTimeoutNanoseconds
                            ?? 5_000_000_000
                    )
                    await self?.expireRequest(id: id)
                }
            }
        } onCancel: { [weak self] in
            Task {
                await self?.cancelRequest(id: id)
            }
        }
    }

    private func sendNotification(
        method: String,
        params: [String: Any]
    ) throws {
        try writeJSONMessage([
            "method": method,
            "params": params
        ])
    }

    private func writeJSONMessage(_ message: [String: Any]) throws {
        let payload = try JSONSerialization.data(withJSONObject: message)
        guard payload.count <= configuration.maximumMessageBytes else {
            throw ClientError.messageTooLarge
        }
        try writeFrame(opcode: .text, payload: payload)
    }

    private func writeFrame(
        opcode: CodexAppServerWebSocketOpcode,
        payload: Data
    ) throws {
        guard let socketReader else {
            throw ClientError.connectionClosed
        }
        let frame = CodexAppServerWebSocketFrameEncoder.clientFrame(
            opcode: opcode,
            payload: payload
        )
        do {
            try socketReader.writeSocket(frame,
                deadline: CodexSocketOpening.deadline(after: configuration.requestTimeoutSeconds))
        } catch {
            throw ClientError.connectionClosed
        }
    }

    private func consumeSocketData(
        _ data: Data,
        generation: UInt64
    ) async throws {
        guard generation == connectionGeneration else { return }
        let events = try frameDecoder.append(data)
        for event in events {
            guard generation == connectionGeneration else { return }
            switch event {
            case .text(let payload):
                try await handleJSONMessage(payload)
            case .ping(let payload):
                try writeFrame(opcode: .pong, payload: payload)
            case .close:
                throw ClientError.connectionClosed
            }
        }
    }

    func handleJSONMessage(_ data: Data) async throws {
        guard data.count <= configuration.maximumMessageBytes,
              let object = try? JSONSerialization.jsonObject(with: data),
              let message = object as? [String: Any]
        else {
            throw ClientError.invalidMessage
        }

        if message["method"] == nil, let id = message["id"] as? Int {
            guard let request = pending.removeValue(forKey: id) else {
                return
            }
            if let error = message["error"] as? [String: Any] {
                request.continuation.resume(
                    throwing: ClientError.server(
                        code: error["code"] as? Int,
                        message: error["message"] as? String
                            ?? "未知错误"
                    )
                )
                return
            }
            guard let result = message["result"] else {
                request.continuation.resume(
                    throwing: ClientError.invalidMessage
                )
                return
            }
            do {
                let resultData = try JSONSerialization.data(
                    withJSONObject: result,
                    options: [.fragmentsAllowed]
                )
                request.continuation.resume(returning: resultData)
            } catch {
                request.continuation.resume(
                    throwing: ClientError.invalidMessage
                )
            }
            return
        }

        if ["thread/started", "thread/snapshot"].contains(message["method"] as? String ?? ""),
           let params = message["params"] as? [String: Any],
           let thread = params["thread"] as? [String: Any], let id = thread["id"] as? String {
            rememberThread(thread, hash: CodexActivityPrivacy.hashIdentifier(id))
        }

        let generation = connectionGeneration
        if let method = message["method"] as? String,
           (method == "turn/started" || message["id"] != nil),
           let params = message["params"] as? [String: Any], let threadID = params["threadId"] as? String {
            scheduleCurrentThreadSnapshot(threadID: threadID)
        }
        if let event = CodexAppServerActivityNotificationDecoder.decode(data: data),
           let kind = threadKinds[event.sessionHash], kind != .internalTask,
           (scopedPublicMessageHandler == nil || kind == .memoryConsolidation),
           let activityNotificationHandler {
            await activityNotificationHandler(event.classified(as: kind))
        }
        if scopedPublicMessageHandler == nil, let tokenUsage = CodexAppServerActivityNotificationDecoder
            .decodeTokenUsage(data: data),
           let kind = threadKinds[tokenUsage.sessionHash], kind == .user,
           let tokenUsageNotificationHandler
        {
            await tokenUsageNotificationHandler(tokenUsage)
        }

        guard generation == connectionGeneration else { return }
        // Lifecycle admission completes before public projections can mutate UI.
        if hasPublicMessageHandler, let clean = publicProjection(message),
           let publicData = try? JSONSerialization.data(withJSONObject: clean, options: [.sortedKeys]) {
            await publishPublicMessage(publicData, generation: generation)
        }

        guard message["method"] as? String == "thread/started",
              let params = message["params"] as? [String: Any],
              let thread = params["thread"] as? [String: Any],
              let threadID = thread["id"] as? String,
              !threadID.isEmpty
        else {
            return
        }

        guard isStarted, threadKinds[CodexActivityPrivacy.hashIdentifier(threadID)] != .internalTask else { return }
        let client = self
        Task(priority: .utility) {
            try? await client.subscribeIfNeeded(threadID: threadID)
        }
    }

    private func expireRequest(id: Int) {
        guard let request = pending.removeValue(forKey: id) else { return }
        request.continuation.resume(
            throwing: ClientError.requestTimedOut(request.method)
        )
    }

    private func cancelRequest(id: Int) {
        guard let request = pending.removeValue(forKey: id) else { return }
        request.continuation.resume(throwing: CancellationError())
    }

    private func connectionDidClose(generation: UInt64) async {
        guard generation == connectionGeneration else { return }
        closeConnection(error: ClientError.connectionClosed)
        if isStarted {
            await publishConnectionState(.discovering)
        }
    }

    private func connectionDidFail(
        _ error: Error,
        generation: UInt64
    ) async {
        guard generation == connectionGeneration else { return }
        closeConnection(error: error)
        if isStarted {
            await publishConnectionState(.discovering)
        }
    }

    private func publishConnectionState(
        _ state: CodexSharedAppServerConnectionState
    ) async {
        guard connectionState != state else { return }
        connectionState = state
        if let connectionStateHandler {
            await connectionStateHandler(state)
        }
    }

    private func closeConnection(error: Error) {
        connectionGeneration &+= 1
        initialized = false
        subscribedThreadHashes.removeAll(keepingCapacity: true)
        threadKinds.removeAll(keepingCapacity: true)
        threadSubagents.removeAll(keepingCapacity: true)
        observedServerRequests.removeAll(); observedServerRequestOrder.removeAll(); ambiguousServerRequests.removeAll()
        snapshotRefreshTasks.values.forEach { $0.cancel() }; snapshotRefreshTasks.removeAll()
        openingSocket?.cancel(); openingSocket = nil
        readTask?.cancel()
        readTask = nil
        socketReader?.close(); socketReader = nil
        socketHandle?.closeFile()
        socketHandle = nil
        frameDecoder = CodexAppServerWebSocketMessageDecoder(
            maximumMessageBytes: configuration.maximumMessageBytes
        )

        let requests = pending.values
        pending.removeAll()
        for request in requests {
            request.continuation.resume(throwing: error)
        }
    }

    private func launchServerIfNeeded() throws {
        if serverProcess?.isRunning == true { return }
        guard let executablePath = configuration.executablePath else {
            throw ClientError.executableNotFound
        }

        let parentURL = configuration.socketURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: parentURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw ClientError.launchFailed(error.localizedDescription)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = [
            "-c",
            "tools.update_plan.enabled=true",
            "app-server",
            "--listen",
            "unix://\(configuration.socketURL.path)"
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw ClientError.launchFailed(error.localizedDescription)
        }
        serverProcess = process
    }

    private func waitForServerSocket(deadline: UInt64) async throws -> OpenedSocket {
        var lastError: Error = ClientError.connectionClosed

        while DispatchTime.now().uptimeNanoseconds < deadline, !Task.isCancelled {
            do {
                return try await openSocket(deadline: deadline)
            } catch {
                lastError = error
                try await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        throw lastError
    }

    private func openSocket(deadline: UInt64) async throws -> OpenedSocket {
        let path = configuration.socketURL.path
        let maximum = configuration.maximumMessageBytes
        let owner = try CodexSocketOpening(deadline: deadline, didClose: openingSocketCloseObserver)
        openingSocket = owner
        defer { if openingSocket === owner { openingSocket = nil } }
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .utility) {
                try Self.openSocket(path: path, maximumMessageBytes: maximum, owner: owner)
            }.value
        } onCancel: { owner.cancel() }
    }

    private struct OpenedSocket: @unchecked Sendable {
        let fileDescriptor: Int32
        let remainingData: Data
    }

    private nonisolated static func openSocket(
        path: String,
        maximumMessageBytes: Int,
        owner: CodexSocketOpening
    ) throws -> OpenedSocket {
        try CodexSocketOpening.verifyPath(path)
        let originalIdentity = try CodexSocketOpening.pathIdentity(path)
        let descriptor = owner.descriptor
        var transferred = false
        defer { if !transferred { owner.finish() } }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let maximumPathBytes = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < maximumPathBytes else {
            throw ClientError.socketPathTooLong
        }
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(
                to: CChar.self,
                capacity: maximumPathBytes
            ) { pathPointer in
                _ = path.withCString {
                    strlcpy(pathPointer, $0, maximumPathBytes)
                }
            }
        }

        let addressLength = socklen_t(
            MemoryLayout<sa_family_t>.size + path.utf8.count + 1
        )
        let connectionResult = try owner.perform { descriptor in
            withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(
                to: sockaddr.self,
                capacity: 1
            ) {
                Darwin.connect(descriptor, $0, addressLength)
            }
        }
        }
        if connectionResult != 0 {
            guard errno == EINPROGRESS || errno == EAGAIN || errno == EINTR else {
                throw ClientError.connectionFailed(String(cString: strerror(errno)))
            }
            try owner.wait(for: Int16(POLLOUT))
            var socketError: Int32 = 0, size = socklen_t(MemoryLayout<Int32>.size)
            try owner.perform { descriptor in
                guard getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &socketError, &size) == 0, socketError == 0 else {
                    throw ClientError.connectionFailed(String(cString: strerror(socketError == 0 ? errno : socketError)))
                }
            }
        }
        try owner.perform { descriptor in
            var peerUID: uid_t = 0, peerGID: gid_t = 0
            guard getpeereid(descriptor, &peerUID, &peerGID) == 0, peerUID == getuid() else { throw ClientError.invalidHandshake }
        }
        try CodexSocketOpening.verifyPath(path)
        guard try CodexSocketOpening.pathIdentity(path) == originalIdentity else { throw ClientError.invalidHandshake }

        let keyData = Data(UUID().uuidString.utf8.prefix(16))
        let key = keyData.base64EncodedString()
        let request = """
        GET / HTTP/1.1\r
        Host: localhost\r
        Upgrade: websocket\r
        Connection: Upgrade\r
        Sec-WebSocket-Key: \(key)\r
        Sec-WebSocket-Version: 13\r
        \r

        """
        try owner.write(Data(request.utf8))

        var response = Data()
        let separator = Data([0x0D, 0x0A, 0x0D, 0x0A])
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while response.range(of: separator) == nil {
            let count = try owner.perform { Darwin.read($0, &buffer, buffer.count) }
            if count < 0, errno == EINTR { continue }
            if count < 0, errno == EAGAIN || errno == EWOULDBLOCK {
                try owner.wait(for: Int16(POLLIN)); continue
            }
            guard count > 0 else { throw ClientError.connectionClosed }
            response.append(buffer, count: count)
            guard response.count <= 16_384 else {
                throw ClientError.invalidHandshake
            }
        }

        guard let headerRange = response.range(of: separator) else {
            throw ClientError.invalidHandshake
        }
        let headerData = response[..<headerRange.upperBound]
        guard let header = String(data: headerData, encoding: .utf8) else {
            throw ClientError.invalidHandshake
        }
        let lines = header.components(separatedBy: "\r\n")
        guard lines.first?.contains(" 101 ") == true else {
            throw ClientError.invalidHandshake
        }

        let expectedAccept = websocketAccept(for: key)
        let accept = lines.dropFirst().compactMap { line -> String? in
            guard let colon = line.firstIndex(of: ":") else { return nil }
            let name = line[..<colon]
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            guard name == "sec-websocket-accept" else { return nil }
            return line[line.index(after: colon)...]
                .trimmingCharacters(in: .whitespaces)
        }.first
        guard accept == expectedAccept else {
            throw ClientError.invalidHandshake
        }

        let remaining = Data(response[headerRange.upperBound...])
        guard remaining.count <= maximumMessageBytes else {
            throw ClientError.messageTooLarge
        }
        // Recheck source after the entire upgrade, including path replacement.
        try CodexSocketOpening.verifyPath(path)
        guard try CodexSocketOpening.pathIdentity(path) == originalIdentity else { throw ClientError.invalidHandshake }
        try owner.transfer()
        transferred = true
        return OpenedSocket(
            fileDescriptor: descriptor,
            remainingData: remaining
        )
    }

    private nonisolated static func websocketAccept(
        for key: String
    ) -> String {
        let source = Data(
            (key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").utf8
        )
        return Data(Insecure.SHA1.hash(data: source)).base64EncodedString()
    }


}

enum CodexAppServerWebSocketOpcode: UInt8 {
    case continuation = 0x0
    case text = 0x1
    case close = 0x8
    case ping = 0x9
    case pong = 0xA
}

enum CodexAppServerWebSocketEvent: Equatable {
    case text(Data)
    case ping(Data)
    case close
}

enum CodexAppServerWebSocketFrameEncoder {
    static func clientFrame(
        opcode: CodexAppServerWebSocketOpcode,
        payload: Data,
        maskingKey: UInt32 = arc4random()
    ) -> Data {
        var frame = Data([0x80 | opcode.rawValue])
        let length = payload.count
        if length <= 125 {
            frame.append(0x80 | UInt8(length))
        } else if length <= Int(UInt16.max) {
            frame.append(0x80 | 126)
            frame.append(UInt8((length >> 8) & 0xFF))
            frame.append(UInt8(length & 0xFF))
        } else {
            frame.append(0x80 | 127)
            let value = UInt64(length)
            for shift in stride(from: 56, through: 0, by: -8) {
                frame.append(UInt8((value >> UInt64(shift)) & 0xFF))
            }
        }

        let mask = [
            UInt8((maskingKey >> 24) & 0xFF),
            UInt8((maskingKey >> 16) & 0xFF),
            UInt8((maskingKey >> 8) & 0xFF),
            UInt8(maskingKey & 0xFF)
        ]
        frame.append(contentsOf: mask)
        frame.append(
            contentsOf: payload.enumerated().map {
                $0.element ^ mask[$0.offset % 4]
            }
        )
        return frame
    }
}

struct CodexAppServerWebSocketMessageDecoder {
    private(set) var buffer = Data()
    private var readOffset = 0
    private var expectedFrameLength: Int?
    private(set) var copiedPayloadBytes = 0
    private(set) var compactedBytes = 0
    private var fragmentedText = Data()
    private var isReadingFragmentedText = false
    private let maximumMessageBytes: Int

    init(maximumMessageBytes: Int = 1_048_576) {
        self.maximumMessageBytes = max(maximumMessageBytes, 1_024)
    }

    mutating func append(
        _ data: Data
    ) throws -> [CodexAppServerWebSocketEvent] {
        buffer.append(data)

        var events: [CodexAppServerWebSocketEvent] = []
        while let frame = try nextFrame() {
            switch frame.opcode {
            case .text:
                guard !isReadingFragmentedText else {
                    throw CodexSharedAppServerActivityClient.ClientError
                        .invalidMessage
                }
                if frame.isFinal {
                    events.append(.text(frame.payload))
                } else {
                    fragmentedText = frame.payload
                    isReadingFragmentedText = true
                }
            case .continuation:
                guard isReadingFragmentedText else {
                    throw CodexSharedAppServerActivityClient.ClientError
                        .invalidMessage
                }
                fragmentedText.append(frame.payload)
                guard fragmentedText.count <= maximumMessageBytes else {
                    throw CodexSharedAppServerActivityClient.ClientError
                        .messageTooLarge
                }
                if frame.isFinal {
                    events.append(.text(fragmentedText))
                    fragmentedText.removeAll(keepingCapacity: true)
                    isReadingFragmentedText = false
                }
            case .ping:
                guard frame.isFinal, frame.payload.count <= 125 else {
                    throw CodexSharedAppServerActivityClient.ClientError
                        .invalidMessage
                }
                events.append(.ping(frame.payload))
            case .pong:
                guard frame.isFinal, frame.payload.count <= 125 else {
                    throw CodexSharedAppServerActivityClient.ClientError
                        .invalidMessage
                }
            case .close:
                guard frame.isFinal, frame.payload.count <= 125 else {
                    throw CodexSharedAppServerActivityClient.ClientError
                        .invalidMessage
                }
                events.append(.close)
            }
        }
        guard buffer.count - readOffset <= maximumMessageBytes + 14 else {
            throw CodexSharedAppServerActivityClient.ClientError
                .messageTooLarge
        }
        return events
    }

    private mutating func nextFrame() throws -> Frame? {
        let available = buffer.count - readOffset
        if let expectedFrameLength, available < expectedFrameLength { return nil }
        guard available >= 2 else { return nil }
        // Only the header is inspected until this exact frame is complete.
        func byte(_ offset: Int) -> UInt8 { buffer[buffer.startIndex + readOffset + offset] }
        let first = byte(0)
        let second = byte(1)
        let isFinal = first & 0x80 != 0
        guard first & 0x70 == 0,
              second & 0x80 == 0,
              let opcode = CodexAppServerWebSocketOpcode(
                  rawValue: first & 0x0F
              )
        else {
            throw CodexSharedAppServerActivityClient.ClientError
                .invalidMessage
        }

        var index = 2
        var payloadLength = UInt64(second & 0x7F)
        if payloadLength == 126 {
            guard available >= 4 else { return nil }
            payloadLength = UInt64(byte(2)) << 8 | UInt64(byte(3))
            index = 4
        } else if payloadLength == 127 {
            guard available >= 10 else { return nil }
            payloadLength = 0
            for offset in 2..<10 { payloadLength = payloadLength << 8 | UInt64(byte(offset)) }
            index = 10
        }

        guard payloadLength <= UInt64(maximumMessageBytes),
              payloadLength <= UInt64(Int.max)
        else {
            throw CodexSharedAppServerActivityClient.ClientError
                .messageTooLarge
        }
        let totalLength = index + Int(payloadLength)
        expectedFrameLength = totalLength
        guard available >= totalLength else { return nil }
        let start = buffer.startIndex + readOffset
        let payload = Data(buffer[(start + index)..<(start + totalLength)])
        copiedPayloadBytes += payload.count
        readOffset += totalLength
        expectedFrameLength = nil
        if readOffset == buffer.count {
            buffer.removeAll(keepingCapacity: true); readOffset = 0
        } else if readOffset >= 65_536 && readOffset >= buffer.count / 2 {
            let remaining = Data(buffer[(buffer.startIndex + readOffset)...])
            compactedBytes += remaining.count
            buffer = remaining; readOffset = 0
        }
        return Frame(
            isFinal: isFinal,
            opcode: opcode,
            payload: payload
        )
    }

    private struct Frame {
        let isFinal: Bool
        let opcode: CodexAppServerWebSocketOpcode
        let payload: Data
    }
}
