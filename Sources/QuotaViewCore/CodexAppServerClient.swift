import Foundation

/// Codex's own discovery result. Hook commands and trust hashes stay local.
public struct CodexHookMetadata: Decodable, Equatable, Sendable {
    public let key: String
    public let eventName: String
    public let handlerType: String
    public let command: String?
    public let sourcePath: String
    public let source: String
    public let pluginId: String?
    public let enabled: Bool
    public let isManaged: Bool
    public let currentHash: String
    public let trustStatus: String
}

public struct CodexOwnedHookState: Equatable, Sendable {
    public let hooks: [CodexHookMetadata]
    public let expectedEvents: Set<String>
    public let issues: [String]

    public var isComplete: Bool {
        !expectedEvents.isEmpty && issues.isEmpty
            && hooks.count == expectedEvents.count
            && Set(hooks.map(\.eventName)) == expectedEvents
    }

    public var isEnabled: Bool {
        !hooks.isEmpty && hooks.allSatisfy(\.enabled)
    }

    public var isTrusted: Bool {
        isComplete && isEnabled
            && hooks.allSatisfy { $0.trustStatus == "trusted" }
    }

    public var untrustedCount: Int {
        hooks.filter { $0.trustStatus != "trusted" }.count
    }

    public var trustedHashes: [String: String] {
        Dictionary(hooks.filter { $0.trustStatus == "trusted" }.map {
            ($0.key, $0.currentHash)
        }, uniquingKeysWith: { first, _ in first })
    }
}

public enum CodexHookConfigurationError: LocalizedError, Equatable, Sendable {
    case incomplete
    case disabled
    case authorizationNotConfirmed

    public var errorDescription: String? {
        switch self {
        case .incomplete:
            "QuotaView Hook 配置不完整，未修改 Codex 的授权。"
        case .disabled:
            "QuotaView Hook 已被禁用，未修改 Codex 的授权。"
        case .authorizationNotConfirmed:
            "Codex 未确认当前 Hook 定义的授权，请重试。"
        }
    }
}

public actor CodexAppServerClient {
    public enum ClientError: LocalizedError, Equatable {
        case executableNotFound
        case launchFailed(String)
        case connectionClosed
        case invalidMessage
        case requestTimedOut(String)
        case messageTooLarge
        case cancelled
        case server(code: Int?, message: String)

        public var errorDescription: String? {
            switch self {
            case .executableNotFound:
                "找不到 Codex。请安装 ChatGPT/Codex，或通过 CODEX_EXECUTABLE 指定路径。"
            case .launchFailed(let message):
                "无法启动 Codex App Server：\(message)"
            case .connectionClosed:
                "Codex App Server 已断开连接。"
            case .invalidMessage:
                "Codex 返回了无法识别的数据。"
            case .requestTimedOut(let method):
                "读取 \(method) 超时。"
            case .messageTooLarge:
                "Codex 返回的数据超过安全大小限制。"
            case .cancelled:
                "Codex 状态读取已取消。"
            case .server(_, let message):
                "Codex 返回错误：\(message)"
            }
        }
    }

    private struct PendingRequest {
        let method: String
        let continuation: CheckedContinuation<Data, Error>
    }

    private let proxyConfiguration: ProxyConfiguration
    private let inheritedEnvironment: [String: String]
    private let executablePath: String?
    private let startupTimeoutNanoseconds: UInt64
    private let requestTimeoutNanoseconds: UInt64
    private let maximumLineBytes: Int
    private let clientVersion: String
    private var socksBridge: SOCKS5HTTPBridge?
    private var process: Process?
    private var inputHandle: FileHandle?
    private var outputTask: Task<Void, Never>?
    private var errorTask: Task<Void, Never>?
    private var pending: [Int: PendingRequest] = [:]
    private var nextRequestID = 1
    private var connectionGeneration: UInt64 = 0
    private var initialized = false
    private var lastStandardError = ""
    private var activityNotificationHandler:
        (@Sendable (CodexActivityEvent) async -> Void)?

    private nonisolated static let allThreadSourceKinds = [
        "cli",
        "vscode",
        "exec",
        "appServer",
        "subAgent",
        "subAgentReview",
        "subAgentCompact",
        "subAgentThreadSpawn",
        "subAgentOther",
        "unknown"
    ]

    public init(
        executablePath: String? = CodexExecutableLocator.locate(),
        proxyConfiguration: ProxyConfiguration = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        startupTimeoutSeconds: TimeInterval = 45,
        requestTimeoutSeconds: TimeInterval = 15,
        maximumLineBytes: Int = 1_048_576,
        clientVersion: String = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0.4.0"
    ) {
        self.proxyConfiguration = proxyConfiguration
        self.inheritedEnvironment = environment
        self.executablePath = executablePath
        self.startupTimeoutNanoseconds = UInt64(
            max(startupTimeoutSeconds, 1) * 1_000_000_000
        )
        self.requestTimeoutNanoseconds = UInt64(
            max(requestTimeoutSeconds, 1) * 1_000_000_000
        )
        self.maximumLineBytes = max(maximumLineBytes, 1_024)
        self.clientVersion = clientVersion
    }

    public func fetchPayload(
        now: Date = Date(),
        includeUsage: Bool = true
    ) async throws -> CodexProviderPayload {
        try await connectIfNeeded()

        guard includeUsage else {
            let rateLimits: AccountRateLimitsResponse
            do {
                rateLimits = try await request(
                    method: "account/rateLimits/read"
                )
            } catch {
                stop()
                throw error
            }
            return CodexProviderPayload(
                rateLimits: rateLimits,
                usage: nil,
                capturedAt: now,
                optionalIssues: []
            )
        }

        async let rateLimits: AccountRateLimitsResponse = request(
            method: "account/rateLimits/read"
        )
        async let optionalUsage: AccountUsageResponse? = try? await request(
            method: "account/usage/read"
        )

        let resolvedRateLimits: AccountRateLimitsResponse
        do {
            resolvedRateLimits = try await rateLimits
        } catch {
            stop()
            throw error
        }
        let resolvedUsage = await optionalUsage
        let optionalIssues: [SanitizedErrorSummary] = resolvedUsage == nil
            ? [SanitizedErrorSummary("account/usage/read unavailable")]
            : []

        return CodexProviderPayload(
            rateLimits: resolvedRateLimits,
            usage: resolvedUsage,
            capturedAt: now,
            optionalIssues: optionalIssues
        )
    }

    public func fetchThreadDisplayName(
        matchingSessionHash sessionHash: String
    ) async throws -> String? {
        try await connectIfNeeded()

        let response: ThreadListResponse
        do {
            response = try await requestThreadList(
                includeAllSourceKinds: true
            )
        } catch let error as ClientError {
            guard case .server = error else {
                stop()
                throw error
            }
            do {
                response = try await requestThreadList(
                    includeAllSourceKinds: false
                )
            } catch {
                stop()
                throw error
            }
        } catch {
            stop()
            throw error
        }

        return response.data.first {
            $0.matches(sessionHash: sessionHash)
        }?.privacySafeDisplayName
    }

    /// Discovery and authorization deliberately use the same native metadata.
    /// Matching a product name inside a command is never sufficient ownership.
    public func inspectOwnedHooks(
        sourceURL: URL,
        command: String,
        expectedEvents: Set<String>,
        cwds: [URL] = []
    ) async throws -> CodexOwnedHookState {
        try await connectIfNeeded()
        let response: HooksListResponse = try await request(
            method: "hooks/list",
            params: ["cwds": cwds.map { $0.standardizedFileURL.path }],
            includeNullParams: false
        )
        let canonicalSource = sourceURL.standardizedFileURL
            .resolvingSymlinksInPath().path
        let normalizedEvents = Set(expectedEvents.map(Self.nativeHookEventName))
        var owned: [String: CodexHookMetadata] = [:]
        var issues: [String] = []
        for entry in response.data {
            for error in entry.errors {
                if error.path.map({ Self.canonicalPath($0) == canonicalSource }) ?? true {
                    issues.append(error.message)
                }
            }
            for hook in entry.hooks where hook.handlerType == "command"
                && hook.command == command && hook.source == "user"
                && !hook.isManaged && hook.pluginId == nil
                && Self.canonicalPath(hook.sourcePath) == canonicalSource {
                if let prior = owned[hook.key], prior != hook {
                    issues.append("Conflicting native Hook definitions")
                }
                owned[hook.key] = hook
                if hook.key.isEmpty || hook.key.utf8.count > 4_096
                    || !Self.isNativeHookHash(hook.currentHash) {
                    issues.append("Invalid native Hook identity")
                }
                if !["trusted", "untrusted", "modified"].contains(hook.trustStatus) {
                    issues.append("Unsupported native Hook trust state")
                }
            }
        }
        if command.isEmpty || command.utf8.count > 16_384 {
            issues.append("Invalid owned Hook command")
        }
        return CodexOwnedHookState(
            hooks: owned.values.sorted { $0.key < $1.key },
            expectedEvents: normalizedEvents,
            issues: issues
        )
    }

    /// Called only after the user authorizes QuotaView's installed observers.
    /// Writes only the discovered hashes for this exact command and source.
    public func authorizeOwnedHooks(
        sourceURL: URL,
        command: String,
        expectedEvents: Set<String>,
        cwds: [URL] = []
    ) async throws -> CodexOwnedHookState {
        let configuredHome = inheritedEnvironment["CODEX_HOME"].flatMap {
            $0.isEmpty ? nil : URL(fileURLWithPath: $0)
        } ?? URL(fileURLWithPath: inheritedEnvironment["HOME"]
            ?? FileManager.default.homeDirectoryForCurrentUser.path)
            .appendingPathComponent(".codex", isDirectory: true)
        // A user hooks.json may legitimately be a symlink into a dotfiles
        // directory. Match the client's actual user source, not its parent.
        guard sourceURL.standardizedFileURL.resolvingSymlinksInPath().path
            == configuredHome.appendingPathComponent("hooks.json")
                .standardizedFileURL.resolvingSymlinksInPath().path else {
            throw CodexHookConfigurationError.incomplete
        }
        let before = try await inspectOwnedHooks(
            sourceURL: sourceURL, command: command,
            expectedEvents: expectedEvents, cwds: cwds
        )
        try Task.checkCancellation()
        guard before.isComplete else { throw CodexHookConfigurationError.incomplete }
        guard before.isEnabled else { throw CodexHookConfigurationError.disabled }
        if before.isTrusted { return before }

        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        let edits: [[String: Any]] = try before.hooks.filter {
            $0.trustStatus != "trusted"
        }.map { hook in
            let quotedKey = String(decoding: try encoder.encode(hook.key), as: UTF8.self)
            return [
                "keyPath": "hooks.state.\(quotedKey).trusted_hash",
                "value": hook.currentHash,
                "mergeStrategy": "replace"
            ]
        }
        try Task.checkCancellation()
        let _: EmptyResult = try await request(
            method: "config/batchWrite",
            params: [
                "edits": edits,
                "reloadUserConfig": true
            ],
            includeNullParams: false
        )
        let after = try await inspectOwnedHooks(
            sourceURL: sourceURL, command: command,
            expectedEvents: expectedEvents, cwds: cwds
        )
        // If definitions changed during the request, the old hashes cannot
        // authorize them and the UI must continue to show pending authorization.
        let originalHashes = Dictionary(uniqueKeysWithValues: before.hooks.map {
            ($0.key, $0.currentHash)
        })
        guard after.isTrusted, after.trustedHashes == originalHashes else {
            throw CodexHookConfigurationError.authorizationNotConfirmed
        }
        return after
    }

    private struct HooksListResponse: Decodable {
        struct Entry: Decodable {
            struct Issue: Decodable {
                let message: String
                let path: String?
            }
            let hooks: [CodexHookMetadata]
            let errors: [Issue]
        }
        let data: [Entry]
    }

    private nonisolated static func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    private nonisolated static func nativeHookEventName(_ name: String) -> String {
        guard let first = name.first else { return name }
        return first.lowercased() + name.dropFirst()
    }

    private nonisolated static func isNativeHookHash(_ value: String) -> Bool {
        guard value.hasPrefix("sha256:"), value.utf8.count == 71 else { return false }
        return value.dropFirst(7).allSatisfy { "0123456789abcdef".contains($0) }
    }

    public func setActivityNotificationHandler(
        _ handler: (@Sendable (CodexActivityEvent) async -> Void)?
    ) {
        activityNotificationHandler = handler
    }

    public func stop() {
        connectionGeneration &+= 1
        socksBridge?.stop()
        socksBridge = nil
        outputTask?.cancel()
        errorTask?.cancel()
        outputTask = nil
        errorTask = nil

        inputHandle?.closeFile()
        inputHandle = nil

        if process?.isRunning == true {
            process?.terminate()
        }
        process = nil
        initialized = false
        failAllPending(with: ClientError.connectionClosed)
    }

    private func connectIfNeeded() async throws {
        if initialized, process?.isRunning == true {
            return
        }

        stop()

        guard let executablePath else {
            throw ClientError.executableNotFound
        }

        let process = Process()
        let standardInput = Pipe()
        let standardOutput = Pipe()
        let standardError = Pipe()

        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["app-server"]
        var effectiveProxy = proxyConfiguration
        if proxyConfiguration.isEnabled, proxyConfiguration.scheme == .socks5 {
            let generation = connectionGeneration
            let bridge = SOCKS5HTTPBridge()
            socksBridge = bridge
            do {
                let port = try await bridge.start(configuration: proxyConfiguration)
                try Task.checkCancellation()
                guard generation == connectionGeneration else { throw ClientError.cancelled }
                effectiveProxy = ProxyConfiguration(isEnabled: true, port: String(port))
            } catch {
                bridge.stop()
                if generation == connectionGeneration { socksBridge = nil }
                throw error
            }
        }
        process.environment = try effectiveProxy.applying(to: inheritedEnvironment)
        process.standardInput = standardInput
        process.standardOutput = standardOutput
        process.standardError = standardError

        do {
            try process.run()
        } catch {
            socksBridge?.stop()
            socksBridge = nil
            throw ClientError.launchFailed(error.localizedDescription)
        }

        self.process = process
        self.inputHandle = standardInput.fileHandleForWriting
        self.lastStandardError = ""
        let connectionGeneration = self.connectionGeneration

        let outputHandle = standardOutput.fileHandleForReading
        let outputStream = Self.dataStream(from: outputHandle)
        let outputClient = self
        let maximumLineBytes = self.maximumLineBytes
        outputTask = Task.detached(priority: .utility) {
            do {
                try await Self.readLines(
                    from: outputStream,
                    maximumLineBytes: maximumLineBytes
                ) { line in
                    await outputClient.handleOutputLine(line)
                }
                await outputClient.handleConnectionClosed(
                    generation: connectionGeneration
                )
            } catch {
                await outputClient.handleOversizedOutput(
                    generation: connectionGeneration
                )
            }
        }

        let errorHandle = standardError.fileHandleForReading
        let errorStream = Self.dataStream(from: errorHandle)
        let errorClient = self
        errorTask = Task.detached(priority: .utility) {
            try? await Self.readLines(
                from: errorStream,
                maximumLineBytes: maximumLineBytes
            ) { line in
                await errorClient.recordStandardError(line)
            }
        }

        process.terminationHandler = { [weak self] _ in
            Task {
                await self?.handleConnectionClosed(
                    generation: connectionGeneration
                )
            }
        }

        do {
            let _: EmptyResult = try await request(
                method: "initialize",
                params: [
                    "clientInfo": [
                        "name": "quotaview",
                        "title": "QuotaView",
                        "version": clientVersion
                    ]
                ],
                includeNullParams: false,
                timeoutNanoseconds: startupTimeoutNanoseconds
            )
            try sendNotification(method: "initialized", params: [:])
            initialized = true
        } catch {
            let detail = lastStandardError.isEmpty
                ? error.localizedDescription
                : lastStandardError
            stop()
            throw ClientError.launchFailed(detail)
        }
    }

    private struct EmptyResult: Decodable {}

    private struct ThreadListResponse: Decodable {
        let data: [CodexThreadMetadata]
    }

    private func requestThreadList(
        includeAllSourceKinds: Bool
    ) async throws -> ThreadListResponse {
        var params: [String: Any] = [
            "limit": 100,
            "useStateDbOnly": true
        ]
        if includeAllSourceKinds {
            params["sourceKinds"] = Self.allThreadSourceKinds
        }
        return try await request(
            method: "thread/list",
            params: params,
            includeNullParams: false
        )
    }

    private func request<Response: Decodable>(
        method: String,
        params: [String: Any]? = nil,
        includeNullParams: Bool = true,
        timeoutNanoseconds: UInt64? = nil
    ) async throws -> Response {
        let resultData = try await requestData(
            method: method,
            params: params,
            includeNullParams: includeNullParams,
            timeoutNanoseconds: timeoutNanoseconds
        )

        do {
            return try JSONDecoder().decode(Response.self, from: resultData)
        } catch {
            throw ClientError.invalidMessage
        }
    }

    private func requestData(
        method: String,
        params: [String: Any]?,
        includeNullParams: Bool,
        timeoutNanoseconds: UInt64?
    ) async throws -> Data {
        guard process?.isRunning == true, inputHandle != nil else {
            throw ClientError.connectionClosed
        }

        let id = nextRequestID
        nextRequestID += 1
        let timeout = timeoutNanoseconds ?? requestTimeoutNanoseconds

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[id] = PendingRequest(
                    method: method,
                    continuation: continuation
                )

                do {
                    var message: [String: Any] = [
                        "method": method,
                        "id": id
                    ]

                    if let params {
                        message["params"] = params
                    } else if includeNullParams {
                        message["params"] = NSNull()
                    }

                    try writeMessage(message)
                } catch {
                    pending.removeValue(forKey: id)
                    continuation.resume(throwing: error)
                    return
                }

                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: timeout)
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
        try writeMessage([
            "method": method,
            "params": params
        ])
    }

    private func writeMessage(_ message: [String: Any]) throws {
        guard let inputHandle else {
            throw ClientError.connectionClosed
        }

        var data = try JSONSerialization.data(withJSONObject: message)
        data.append(0x0A)

        do {
            try inputHandle.write(contentsOf: data)
        } catch {
            throw ClientError.connectionClosed
        }
    }

    private func handleOutputLine(_ line: String) async {
        guard
            let data = line.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            let message = object as? [String: Any]
        else {
            return
        }

        guard let id = message["id"] as? Int else {
            guard let event = CodexAppServerActivityNotificationDecoder
                    .decode(data: data),
                  let activityNotificationHandler
            else {
                return
            }
            await activityNotificationHandler(event)
            return
        }

        guard let request = pending.removeValue(forKey: id) else {
            return
        }

        if let error = message["error"] as? [String: Any] {
            request.continuation.resume(
                throwing: ClientError.server(
                    code: error["code"] as? Int,
                    message: error["message"] as? String ?? "未知错误"
                )
            )
            return
        }

        guard let result = message["result"] else {
            request.continuation.resume(throwing: ClientError.invalidMessage)
            return
        }

        do {
            let resultData = try JSONSerialization.data(withJSONObject: result)
            request.continuation.resume(returning: resultData)
        } catch {
            request.continuation.resume(throwing: ClientError.invalidMessage)
        }
    }

    private func expireRequest(id: Int) {
        guard let request = pending.removeValue(forKey: id) else {
            return
        }
        request.continuation.resume(
            throwing: ClientError.requestTimedOut(request.method)
        )
    }

    private func cancelRequest(id: Int) {
        guard let request = pending.removeValue(forKey: id) else {
            return
        }
        request.continuation.resume(
            throwing: ClientError.cancelled
        )
    }

    private func recordStandardError(_ line: String) {
        guard !line.isEmpty else { return }
        lastStandardError = String(line.prefix(4_096))
    }

    private func handleConnectionClosed(
        generation: UInt64
    ) {
        guard generation == connectionGeneration,
              process != nil
        else {
            return
        }
        initialized = false
        failAllPending(with: ClientError.connectionClosed)
    }

    private func handleOversizedOutput(
        generation: UInt64
    ) {
        guard generation == connectionGeneration,
              process != nil
        else {
            return
        }
        failAllPending(with: ClientError.messageTooLarge)
        stop()
    }

    private func failAllPending(with error: Error) {
        let requests = pending.values
        pending.removeAll()
        for request in requests {
            request.continuation.resume(throwing: error)
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

    private enum LineReadError: Error {
        case lineTooLarge
    }

    private nonisolated static func readLines(
        from stream: AsyncStream<Data>,
        maximumLineBytes: Int,
        onLine: @escaping @Sendable (String) async -> Void
    ) async throws {
        var buffer = Data()

        for await chunk in stream {
            buffer.append(chunk)

            if buffer.count > maximumLineBytes,
               !buffer.prefix(maximumLineBytes).contains(0x0A) {
                throw LineReadError.lineTooLarge
            }

            while let newlineIndex = buffer.firstIndex(of: 0x0A) {
                guard newlineIndex <= maximumLineBytes else {
                    throw LineReadError.lineTooLarge
                }

                var lineData = Data(buffer[..<newlineIndex])
                buffer.removeSubrange(...newlineIndex)

                if lineData.last == 0x0D {
                    lineData.removeLast()
                }

                if let line = String(data: lineData, encoding: .utf8) {
                    await onLine(line)
                }
            }
        }

        guard buffer.count <= maximumLineBytes else {
            throw LineReadError.lineTooLarge
        }

        if !buffer.isEmpty,
           let line = String(data: buffer, encoding: .utf8) {
            await onLine(line)
        }
    }
}
