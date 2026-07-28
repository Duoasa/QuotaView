import Foundation

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

    private let executablePath: String?
    private let startupTimeoutNanoseconds: UInt64
    private let requestTimeoutNanoseconds: UInt64
    private let maximumLineBytes: Int
    private var process: Process?
    private var inputHandle: FileHandle?
    private var outputTask: Task<Void, Never>?
    private var errorTask: Task<Void, Never>?
    private var pending: [Int: PendingRequest] = [:]
    private var nextRequestID = 1
    private var connectionGeneration: UInt64 = 0
    private var initialized = false
    private var lastStandardError = ""

    public init(
        executablePath: String? = CodexExecutableLocator.locate(),
        startupTimeoutSeconds: TimeInterval = 45,
        requestTimeoutSeconds: TimeInterval = 15,
        maximumLineBytes: Int = 1_048_576
    ) {
        self.executablePath = executablePath
        self.startupTimeoutNanoseconds = UInt64(
            max(startupTimeoutSeconds, 1) * 1_000_000_000
        )
        self.requestTimeoutNanoseconds = UInt64(
            max(requestTimeoutSeconds, 1) * 1_000_000_000
        )
        self.maximumLineBytes = max(maximumLineBytes, 1_024)
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

    public func stop() {
        connectionGeneration &+= 1
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
        process.standardInput = standardInput
        process.standardOutput = standardOutput
        process.standardError = standardError

        do {
            try process.run()
        } catch {
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
                        "version": "0.2.0"
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

    private func handleOutputLine(_ line: String) {
        guard
            let data = line.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            let message = object as? [String: Any],
            let id = message["id"] as? Int,
            let request = pending.removeValue(forKey: id)
        else {
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
