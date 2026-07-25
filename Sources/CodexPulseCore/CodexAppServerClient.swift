import Foundation

public actor CodexAppServerClient {
    public enum ClientError: LocalizedError {
        case executableNotFound
        case launchFailed(String)
        case connectionClosed
        case invalidMessage
        case requestTimedOut(String)
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
    private let requestTimeoutNanoseconds: UInt64
    private var process: Process?
    private var inputHandle: FileHandle?
    private var outputTask: Task<Void, Never>?
    private var errorTask: Task<Void, Never>?
    private var pending: [Int: PendingRequest] = [:]
    private var nextRequestID = 1
    private var initialized = false
    private var lastStandardError = ""

    public init(
        executablePath: String? = CodexExecutableLocator.locate(),
        requestTimeoutSeconds: TimeInterval = 45
    ) {
        self.executablePath = executablePath
        self.requestTimeoutNanoseconds = UInt64(max(requestTimeoutSeconds, 1) * 1_000_000_000)
    }

    public func fetchSnapshot(now: Date = Date()) async throws -> CodexSnapshot {
        try await connectIfNeeded()

        async let rateLimits: AccountRateLimitsResponse = request(
            method: "account/rateLimits/read"
        )
        async let usage: AccountUsageResponse = request(
            method: "account/usage/read"
        )

        return try await CodexSnapshot.make(
            rateLimits: rateLimits,
            usage: usage,
            now: now
        )
    }

    public func stop() {
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

        let outputHandle = standardOutput.fileHandleForReading
        let outputStream = Self.dataStream(from: outputHandle)
        let outputClient = self
        outputTask = Task.detached(priority: .utility) {
            await Self.readLines(from: outputStream) { line in
                await outputClient.handleOutputLine(line)
            }
            await outputClient.handleConnectionClosed()
        }

        let errorHandle = standardError.fileHandleForReading
        let errorStream = Self.dataStream(from: errorHandle)
        let errorClient = self
        errorTask = Task.detached(priority: .utility) {
            await Self.readLines(from: errorStream) { line in
                await errorClient.recordStandardError(line)
            }
        }

        process.terminationHandler = { [weak self] _ in
            Task {
                await self?.handleConnectionClosed()
            }
        }

        do {
            let _: EmptyResult = try await request(
                method: "initialize",
                params: [
                    "clientInfo": [
                        "name": "codex_pulse",
                        "title": "Codex Pulse",
                        "version": "0.1.0"
                    ]
                ],
                includeNullParams: false
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
        includeNullParams: Bool = true
    ) async throws -> Response {
        let resultData = try await requestData(
            method: method,
            params: params,
            includeNullParams: includeNullParams
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
        includeNullParams: Bool
    ) async throws -> Data {
        guard process?.isRunning == true, inputHandle != nil else {
            throw ClientError.connectionClosed
        }

        let id = nextRequestID
        nextRequestID += 1

        return try await withCheckedThrowingContinuation { continuation in
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

            let timeout = requestTimeoutNanoseconds
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: timeout)
                await self?.expireRequest(id: id)
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

    private func recordStandardError(_ line: String) {
        guard !line.isEmpty else { return }
        lastStandardError = line
    }

    private func handleConnectionClosed() {
        guard process != nil else { return }
        initialized = false
        failAllPending(with: ClientError.connectionClosed)
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

    private nonisolated static func readLines(
        from stream: AsyncStream<Data>,
        onLine: @escaping @Sendable (String) async -> Void
    ) async {
        var buffer = Data()

        for await chunk in stream {
            buffer.append(chunk)

            while let newlineIndex = buffer.firstIndex(of: 0x0A) {
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

        if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8) {
            await onLine(line)
        }
    }
}
