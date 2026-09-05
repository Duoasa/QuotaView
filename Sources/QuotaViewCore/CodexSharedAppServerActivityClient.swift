import CryptoKit
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
        "item/started",
        "item/completed",
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
    private var frameDecoder = CodexAppServerWebSocketMessageDecoder()
    private var activityNotificationHandler:
        (@Sendable (CodexActivityEvent) async -> Void)?
    private var tokenUsageNotificationHandler:
        (@Sendable (CodexActivityTokenUsageUpdate) async -> Void)?
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

        let opened: OpenedSocket
        do {
            opened = try await openSocket()
        } catch {
            guard configuration.launchServerIfNeeded else { throw error }
            try launchServerIfNeeded()
            opened = try await waitForServerSocket()
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

        let stream = Self.dataStream(from: handle)
        let client = self
        readTask = Task.detached(priority: .utility) {
            do {
                if !opened.remainingData.isEmpty {
                    try await client.consumeSocketData(
                        opened.remainingData,
                        generation: generation
                    )
                }
                for await chunk in stream {
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
                    "optOutNotificationMethods": Self
                        .contentNotificationOptOutMethods
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
           let thread = result["thread"] as? [String: Any] {
            rememberThread(thread, hash: hash)
        } else { threadKinds[hash] = .unknown }
        subscribedThreadHashes.insert(hash)
    }

    private func rememberThread(_ thread: [String: Any], hash: String) {
        if threadKinds.count >= 1024, threadKinds[hash] == nil { return }
        threadKinds[hash] = CodexActivitySessionKind.classify(
            source: thread["source"],
            threadSource: (thread["threadSource"] ?? thread["thread_source"]) as? String
        )
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
        guard let socketHandle else {
            throw ClientError.connectionClosed
        }
        let frame = CodexAppServerWebSocketFrameEncoder.clientFrame(
            opcode: opcode,
            payload: payload
        )
        do {
            try socketHandle.write(contentsOf: frame)
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

        if let id = message["id"] as? Int {
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

        if message["method"] as? String == "thread/started",
           let params = message["params"] as? [String: Any],
           let thread = params["thread"] as? [String: Any], let id = thread["id"] as? String {
            rememberThread(thread, hash: CodexActivityPrivacy.hashIdentifier(id))
        }

        if let event = CodexAppServerActivityNotificationDecoder.decode(
            data: data
        ), let kind = threadKinds[event.sessionHash], kind != .internalTask,
           let activityNotificationHandler {
            await activityNotificationHandler(event.classified(as: kind))
        }
        if let tokenUsage = CodexAppServerActivityNotificationDecoder
            .decodeTokenUsage(data: data),
           let kind = threadKinds[tokenUsage.sessionHash], kind != .internalTask,
           let tokenUsageNotificationHandler
        {
            await tokenUsageNotificationHandler(tokenUsage)
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
        readTask?.cancel()
        readTask = nil
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

    private func waitForServerSocket() async throws -> OpenedSocket {
        let deadline = Date().addingTimeInterval(
            configuration.startupTimeoutSeconds
        )
        var lastError: Error = ClientError.connectionClosed

        while Date() < deadline, !Task.isCancelled {
            do {
                return try await openSocket()
            } catch {
                lastError = error
                try await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        throw lastError
    }

    private func openSocket() async throws -> OpenedSocket {
        let path = configuration.socketURL.path
        let maximum = configuration.maximumMessageBytes
        return try await Task.detached(priority: .utility) {
            try Self.openSocket(
                path: path,
                maximumMessageBytes: maximum
            )
        }.value
    }

    private struct OpenedSocket: @unchecked Sendable {
        let fileDescriptor: Int32
        let remainingData: Data
    }

    private nonisolated static func openSocket(
        path: String,
        maximumMessageBytes: Int
    ) throws -> OpenedSocket {
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw ClientError.connectionFailed(
                String(cString: strerror(errno))
            )
        }

        var shouldClose = true
        defer {
            if shouldClose {
                Darwin.close(descriptor)
            }
        }

        var noSignal: Int32 = 1
        setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &noSignal,
            socklen_t(MemoryLayout<Int32>.size)
        )

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
        let connectionResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(
                to: sockaddr.self,
                capacity: 1
            ) {
                Darwin.connect(descriptor, $0, addressLength)
            }
        }
        guard connectionResult == 0 else {
            throw ClientError.connectionFailed(
                String(cString: strerror(errno))
            )
        }

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
        try writeAll(
            Data(request.utf8),
            to: descriptor
        )

        var response = Data()
        let separator = Data([0x0D, 0x0A, 0x0D, 0x0A])
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while response.range(of: separator) == nil {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            guard count > 0 else {
                throw ClientError.connectionClosed
            }
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
        shouldClose = false
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

    private nonisolated static func writeAll(
        _ data: Data,
        to descriptor: Int32
    ) throws {
        try data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            var offset = 0
            while offset < data.count {
                let count = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    data.count - offset
                )
                guard count > 0 else {
                    throw ClientError.connectionClosed
                }
                offset += count
            }
        }
    }

    private nonisolated static func dataStream(
        from handle: FileHandle
    ) -> AsyncStream<Data> {
        AsyncStream { continuation in
            handle.readabilityHandler = { readableHandle in
                let data = readableHandle.availableData
                if data.isEmpty {
                    readableHandle.readabilityHandler = nil
                    continuation.finish()
                } else {
                    continuation.yield(data)
                }
            }
            continuation.onTermination = { _ in
                handle.readabilityHandler = nil
            }
        }
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
        guard buffer.count <= maximumMessageBytes + 14 else {
            throw CodexSharedAppServerActivityClient.ClientError
                .messageTooLarge
        }
        return events
    }

    private mutating func nextFrame() throws -> Frame? {
        guard buffer.count >= 2 else { return nil }
        let bytes = [UInt8](buffer)
        let first = bytes[0]
        let second = bytes[1]
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
            guard bytes.count >= 4 else { return nil }
            payloadLength = UInt64(bytes[2]) << 8 | UInt64(bytes[3])
            index = 4
        } else if payloadLength == 127 {
            guard bytes.count >= 10 else { return nil }
            payloadLength = 0
            for byte in bytes[2..<10] {
                payloadLength = payloadLength << 8 | UInt64(byte)
            }
            index = 10
        }

        guard payloadLength <= UInt64(maximumMessageBytes),
              payloadLength <= UInt64(Int.max)
        else {
            throw CodexSharedAppServerActivityClient.ClientError
                .messageTooLarge
        }
        let totalLength = index + Int(payloadLength)
        guard bytes.count >= totalLength else { return nil }
        let payload = Data(bytes[index..<totalLength])
        buffer.removeFirst(totalLength)
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
