import Darwin
import Foundation

private enum ProbeError: Error, CustomStringConvertible {
    case invalidArguments(String)
    case invalidRuntime(String)
    case launch(String)
    case encoding(String)
    case timeout(String)
    case rpc(String)
    case shutdown(String)

    var description: String {
        switch self {
        case let .invalidArguments(message),
             let .invalidRuntime(message),
             let .launch(message),
             let .encoding(message),
             let .timeout(message),
             let .rpc(message),
             let .shutdown(message):
            return message
        }
    }
}

private final class JSONLineCollector: @unchecked Sendable {
    private let lock = NSLock()
    private let signal = DispatchSemaphore(value: 0)
    private var buffer = Data()
    private var messages: [[String: Any]] = []

    func append(_ data: Data) {
        guard !data.isEmpty else { return }

        lock.lock()
        buffer.append(data)

        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[..<newline]
            buffer.removeSubrange(...newline)

            guard !line.isEmpty,
                  let value = try? JSONSerialization.jsonObject(with: Data(line)),
                  let message = value as? [String: Any] else {
                continue
            }

            messages.append(message)
            signal.signal()
        }
        lock.unlock()
    }

    func waitForResponse(id: Int, timeout: TimeInterval) throws -> [String: Any] {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if let response = removeFirst(where: { message in
                (message["id"] as? NSNumber)?.intValue == id
            }) {
                return response
            }

            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { break }
            _ = signal.wait(timeout: .now() + min(remaining, 0.25))
        }

        throw ProbeError.timeout("Timed out waiting for RPC response id \(id).")
    }

    func waitForNotification(
        method: String,
        loginID: String?,
        timeout: TimeInterval
    ) throws -> [String: Any] {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if let notification = removeFirst(where: { message in
                guard message["method"] as? String == method else { return false }
                guard let loginID else { return true }
                let params = message["params"] as? [String: Any]
                return params?["loginId"] as? String == loginID
            }) {
                return notification
            }

            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { break }
            _ = signal.wait(timeout: .now() + min(remaining, 0.25))
        }

        throw ProbeError.timeout("Timed out waiting for \(method).")
    }

    private func removeFirst(
        where predicate: ([String: Any]) -> Bool
    ) -> [String: Any]? {
        lock.lock()
        defer { lock.unlock() }

        guard let index = messages.firstIndex(where: predicate) else {
            return nil
        }
        return messages.remove(at: index)
    }
}

private struct ProbeOptions {
    let runtimeURL: URL
    let runtimeHomeURL: URL
    let startDeviceCodeLogin: Bool
    let readRateLimits: Bool
    let logout: Bool

    static func parse(_ arguments: [String]) throws -> ProbeOptions {
        guard arguments.count >= 2 else {
            throw ProbeError.invalidArguments(
                "Usage: RuntimeProbe <runtime> <runtime-home|:temporary|:application-support> "
                    + "[--device-code|--read-rate-limits|--logout]"
            )
        }

        let runtimeURL = URL(fileURLWithPath: arguments[0]).standardizedFileURL
        let runtimeHomeURL: URL
        switch arguments[1] {
        case ":temporary":
            runtimeHomeURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("QuotaViewRuntimeSpike", isDirectory: true)
        case ":application-support":
            guard let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first else {
                throw ProbeError.invalidArguments(
                    "Unable to resolve the application support directory."
                )
            }
            runtimeHomeURL = applicationSupport
                .appendingPathComponent("QuotaView", isDirectory: true)
                .appendingPathComponent("CodexRuntimeSpike", isDirectory: true)
        default:
            runtimeHomeURL = URL(
                fileURLWithPath: arguments[1]
            ).standardizedFileURL
        }
        let flags = Set(arguments.dropFirst(2))
        let knownFlags: Set<String> = [
            "--device-code",
            "--read-rate-limits",
            "--logout"
        ]
        let unknownFlags = flags.subtracting(knownFlags)

        guard unknownFlags.isEmpty else {
            throw ProbeError.invalidArguments(
                "Unknown flags: \(unknownFlags.sorted().joined(separator: ", "))"
            )
        }
        guard !(flags.contains("--device-code") && flags.contains("--logout")) else {
            throw ProbeError.invalidArguments(
                "--device-code and --logout cannot be used together."
            )
        }

        return ProbeOptions(
            runtimeURL: runtimeURL,
            runtimeHomeURL: runtimeHomeURL,
            startDeviceCodeLogin: flags.contains("--device-code"),
            readRateLimits: flags.contains("--read-rate-limits"),
            logout: flags.contains("--logout")
        )
    }
}

private final class RuntimeProbe {
    private let options: ProbeOptions
    private let process = Process()
    private let inputPipe = Pipe()
    private let outputPipe = Pipe()
    private let errorPipe = Pipe()
    private let collector = JSONLineCollector()
    private let exitSignal = DispatchSemaphore(value: 0)
    private var stderrBuffer = Data()
    private let stderrLock = NSLock()

    init(options: ProbeOptions) {
        self.options = options
    }

    func run() throws {
        try validateRuntime()
        try prepareRuntimeHome()
        try launch()

        defer {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
        }

        do {
            try send([
                "method": "initialize",
                "id": 1,
                "params": [
                    "clientInfo": [
                        "name": "quotaview_appstore_spike",
                        "title": "QuotaView App Store Runtime Spike",
                        "version": "1.0.0"
                    ]
                ]
            ])

            // Rosetta's first translation of the large Runtime can take more than
            // 20 seconds on a cold cache. Keep this bounded but architecture-safe.
            let initialize = try collector.waitForResponse(id: 1, timeout: 60)
            try requireSuccess(initialize, method: "initialize")
            print("initialize=ok")

            try send(["method": "initialized", "params": [:]])
            try send([
                "method": "account/read",
                "id": 2,
                "params": ["refreshToken": false]
            ])

            let accountRead = try collector.waitForResponse(id: 2, timeout: 30)
            let accountResult = try requireSuccess(accountRead, method: "account/read")
            printSanitizedAccount(accountResult)

            if options.startDeviceCodeLogin {
                try runDeviceCodeLogin()
            } else if options.logout {
                try runLogout()
            } else if options.readRateLimits {
                try runRateLimits(requestID: 4)
            }
        } catch {
            let probeError = error
            do {
                try shutdown()
            } catch {
                throw ProbeError.shutdown(
                    "Probe failed: \(probeError); Runtime cleanup failed: \(error)"
                )
            }
            throw probeError
        }

        try shutdown()
    }

    private func validateRuntime() throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: options.runtimeURL.path,
            isDirectory: &isDirectory
        ), !isDirectory.boolValue else {
            throw ProbeError.invalidRuntime(
                "Runtime does not exist: \(options.runtimeURL.path)"
            )
        }

        guard FileManager.default.isExecutableFile(atPath: options.runtimeURL.path) else {
            throw ProbeError.invalidRuntime(
                "Runtime is not executable: \(options.runtimeURL.path)"
            )
        }
    }

    private func prepareRuntimeHome() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: options.runtimeHomeURL,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: options.runtimeHomeURL.appendingPathComponent("tmp", isDirectory: true),
            withIntermediateDirectories: true
        )

        let config = """
        check_for_update_on_startup = false
        cli_auth_credentials_store = "keyring"

        [history]
        persistence = "none"

        [shell_environment_policy]
        inherit = "none"
        """
        try Data(config.utf8).write(
            to: options.runtimeHomeURL.appendingPathComponent("config.toml"),
            options: .atomic
        )
    }

    private func launch() throws {
        outputPipe.fileHandleForReading.readabilityHandler = { [collector] handle in
            collector.append(handle.availableData)
        }
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.appendStderr(handle.availableData)
        }

        process.executableURL = options.runtimeURL
        process.arguments = ["--listen", "stdio://", "--strict-config"]
        process.currentDirectoryURL = options.runtimeHomeURL
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.environment = sanitizedEnvironment()
        process.terminationHandler = { [exitSignal] _ in
            exitSignal.signal()
        }

        do {
            try process.run()
        } catch {
            throw ProbeError.launch("Runtime launch failed: \(error.localizedDescription)")
        }

        print("runtime_pid=\(process.processIdentifier)")
    }

    private func sanitizedEnvironment() -> [String: String] {
        let temporaryDirectory = options.runtimeHomeURL
            .appendingPathComponent("tmp", isDirectory: true)
            .path
        return [
            "CODEX_HOME": options.runtimeHomeURL.path,
            "HOME": options.runtimeHomeURL.path,
            "TMPDIR": temporaryDirectory,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "LANG": "en_US.UTF-8",
            "LC_CTYPE": "UTF-8"
        ]
    }

    private func send(_ message: [String: Any]) throws {
        guard JSONSerialization.isValidJSONObject(message) else {
            throw ProbeError.encoding("RPC request is not valid JSON.")
        }

        var data = try JSONSerialization.data(withJSONObject: message)
        data.append(0x0A)
        do {
            try inputPipe.fileHandleForWriting.write(contentsOf: data)
        } catch {
            throw ProbeError.rpc("Failed to write RPC request: \(error.localizedDescription)")
        }
    }

    @discardableResult
    private func requireSuccess(
        _ response: [String: Any],
        method: String
    ) throws -> [String: Any] {
        if let error = response["error"] as? [String: Any] {
            let code = (error["code"] as? NSNumber)?.stringValue ?? "unknown"
            let message = error["message"] as? String ?? "unknown error"
            throw ProbeError.rpc("\(method) failed (\(code)): \(message)")
        }

        guard let result = response["result"] as? [String: Any] else {
            throw ProbeError.rpc("\(method) returned no result object.")
        }
        return result
    }

    private func printSanitizedAccount(_ result: [String: Any]) {
        let account = result["account"] as? [String: Any]
        let accountType = account?["type"] as? String ?? "signedOut"
        let planType = account?["planType"] as? String ?? "-"
        let requiresOpenAIAuth = result["requiresOpenaiAuth"] as? Bool

        print("account_type=\(accountType)")
        print("plan_type=\(planType)")
        print("requires_openai_auth=\(requiresOpenAIAuth.map(String.init) ?? "unknown")")
    }

    private func runDeviceCodeLogin() throws {
        try send([
            "method": "account/login/start",
            "id": 3,
            "params": ["type": "chatgptDeviceCode"]
        ])

        let response = try collector.waitForResponse(id: 3, timeout: 30)
        let result = try requireSuccess(response, method: "account/login/start")
        guard let loginID = result["loginId"] as? String,
              let verificationURL = result["verificationUrl"] as? String,
              let userCode = result["userCode"] as? String else {
            throw ProbeError.rpc("Device Code response is incomplete.")
        }

        print("device_verification_url=\(verificationURL)")
        print("device_user_code=\(userCode)")
        print("device_login_status=waiting")
        fflush(stdout)

        let notification = try collector.waitForNotification(
            method: "account/login/completed",
            loginID: loginID,
            timeout: 600
        )
        let params = notification["params"] as? [String: Any]
        guard params?["success"] as? Bool == true else {
            let error = params?["error"] as? String ?? "login failed"
            throw ProbeError.rpc("Device Code login failed: \(error)")
        }

        print("device_login_status=connected")
        let accountUpdated = try collector.waitForNotification(
            method: "account/updated",
            loginID: nil,
            timeout: 30
        )
        let updatedParams = accountUpdated["params"] as? [String: Any]
        guard updatedParams?["authMode"] as? String == "chatgpt" else {
            throw ProbeError.rpc(
                "Device Code completed, but account/updated did not confirm ChatGPT auth."
            )
        }
        print("device_auth_state=ready")
        try runRateLimits(requestID: 4)
    }

    private func runRateLimits(requestID: Int) throws {
        try send([
            "method": "account/rateLimits/read",
            "id": requestID,
            "params": [:]
        ])
        let limits = try collector.waitForResponse(id: requestID, timeout: 30)
        let limitsResult = try requireSuccess(
            limits,
            method: "account/rateLimits/read"
        )
        printSanitizedRateLimits(limitsResult)
    }

    private func runLogout() throws {
        try send(["method": "account/logout", "id": 5])
        let response = try collector.waitForResponse(id: 5, timeout: 30)
        try requireSuccess(response, method: "account/logout")
        print("logout=ok")

        try send([
            "method": "account/read",
            "id": 6,
            "params": ["refreshToken": false]
        ])
        let accountRead = try collector.waitForResponse(id: 6, timeout: 30)
        let accountResult = try requireSuccess(accountRead, method: "account/read")
        printSanitizedAccount(accountResult)
    }

    private func printSanitizedRateLimits(_ result: [String: Any]) {
        let limits = result["rateLimits"] as? [String: Any]
        let primary = limits?["primary"] as? [String: Any]
        let secondary = limits?["secondary"] as? [String: Any]
        print("rate_limits_present=\(limits != nil)")
        print("primary_present=\(primary != nil)")
        print("secondary_present=\(secondary != nil)")
        print("primary_used_percent=\(numericString(primary?["usedPercent"]))")
        print("primary_resets_at=\(numericString(primary?["resetsAt"]))")
        print("secondary_used_percent=\(numericString(secondary?["usedPercent"]))")
        print("secondary_resets_at=\(numericString(secondary?["resetsAt"]))")
        print("reset_credit_fields_ignored=true")
    }

    private func numericString(_ value: Any?) -> String {
        (value as? NSNumber)?.stringValue ?? "-"
    }

    private func appendStderr(_ data: Data) {
        guard !data.isEmpty else { return }
        stderrLock.lock()
        defer { stderrLock.unlock() }
        let remaining = max(0, 8_192 - stderrBuffer.count)
        if remaining > 0 {
            stderrBuffer.append(data.prefix(remaining))
        }
    }

    private func shutdown() throws {
        let pid = process.processIdentifier
        try? inputPipe.fileHandleForWriting.close()

        if exitSignal.wait(timeout: .now() + 5) == .timedOut {
            process.terminate()
            if exitSignal.wait(timeout: .now() + 3) == .timedOut {
                Darwin.kill(pid, SIGKILL)
                guard exitSignal.wait(timeout: .now() + 3) == .success else {
                    throw ProbeError.shutdown("Runtime did not exit after SIGKILL.")
                }
            }
        }

        errno = 0
        let isGone = Darwin.kill(pid, 0) == -1 && errno == ESRCH
        print("runtime_termination_status=\(process.terminationStatus)")
        print("orphan_process=\(!isGone)")

        if !isGone {
            throw ProbeError.shutdown("Runtime process still exists after shutdown.")
        }
    }
}

@main
private struct RuntimeProbeMain {
    static func main() {
        do {
            let options = try ProbeOptions.parse(Array(CommandLine.arguments.dropFirst()))
            let probe = RuntimeProbe(options: options)
            try probe.run()
        } catch {
            FileHandle.standardError.write(
                Data("runtime_spike_error=\(error)\n".utf8)
            )
            Darwin.exit(EXIT_FAILURE)
        }
    }
}
