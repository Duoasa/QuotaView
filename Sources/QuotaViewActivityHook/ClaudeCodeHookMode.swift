import Darwin
import Foundation

/// Claude Code entry points of the shared activity helper.
///
/// `--claude-code --configuration <route.json>` is installed as a Claude Code
/// command hook. It forwards a bounded copy of the hook input to QuotaView over
/// the private Unix socket. For PermissionRequest it can wait for a decision
/// made in the island; any failure prints nothing so Claude Code keeps its own
/// terminal dialog.
///
/// `--claude-statusline --configuration <route.json>` is installed as the
/// Claude Code status line. It records the official `rate_limits` snapshot for
/// QuotaView and then prints the user's original status line (or a compact one).
enum ClaudeCodeHookMode {
    static func handles(_ arguments: [String]) -> Bool {
        guard let mode = arguments.first,
              mode == "--claude-code" || mode == "--claude-statusline" || mode == "--agent-hook" else { return false }
        guard arguments.count == 3, arguments[1] == "--configuration",
              let route = ClaudeCodeRoute.read(from: arguments[2]) else {
            // A broken route must never block Claude Code.
            return true
        }
        if mode == "--agent-hook" {
            NativeAgentHookForwarder.run(route: route)
        } else if mode == "--claude-code" {
            ClaudeCodeHookForwarder(route: route).run()
        } else {
            ClaudeCodeStatusLineForwarder(route: route).run()
        }
        return true
    }
}

struct ClaudeCodeRoute: Decodable {
    let version: Int
    let socketPath: String
    let authenticationToken: String
    let interactiveApprovals: Bool?
    let decisionTimeoutSeconds: Double?
    let statusLineSnapshotPath: String?
    let statusLineForwardCommand: String?

    static func read(from path: String) -> ClaudeCodeRoute? {
        let descriptor = Darwin.open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        defer { Darwin.close(descriptor) }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              metadata.st_uid == getuid(),
              metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_mode & (S_IRWXG | S_IRWXO) == 0,
              metadata.st_size > 0, metadata.st_size <= 65_536 else { return nil }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        guard let data = try? handle.read(upToCount: 65_537), data.count <= 65_536,
              let route = try? JSONDecoder().decode(ClaudeCodeRoute.self, from: data),
              route.version == 1, route.socketPath.hasPrefix("/"),
              !route.authenticationToken.isEmpty else { return nil }
        return route
    }
}

enum ClaudeCodeHookIO {
    static func readStandardInput(maximumBytes: Int) -> Data? {
        var data = Data()
        while data.count <= maximumBytes {
            let chunk: Data?
            do { chunk = try FileHandle.standardInput.read(upToCount: 65_536) } catch { return nil }
            guard let chunk, !chunk.isEmpty else { return data }
            data.append(chunk)
        }
        return nil
    }

    static func writeStandardOutput(_ data: Data) {
        FileHandle.standardOutput.write(data)
    }

    /// Bounded JSON value: oversized values become a truncated string.
    static func bounded(_ value: Any?, maximumBytes: Int) -> Any? {
        guard let value, !(value is NSNull) else { return nil }
        if let text = value as? String {
            return text.utf8.count <= maximumBytes ? text : String(decoding: Array(text.utf8.prefix(maximumBytes)), as: UTF8.self)
        }
        guard JSONSerialization.isValidJSONObject(["v": value]),
              let data = try? JSONSerialization.data(withJSONObject: ["v": value], options: [.fragmentsAllowed]) else { return nil }
        if data.count <= maximumBytes { return value }
        let text = String(decoding: data.prefix(maximumBytes), as: UTF8.self)
        return ["_quotaViewTruncated": true, "preview": text]
    }
}

/// Small blocking Unix-socket client with explicit deadlines.
final class ClaudeCodeSocketClient {
    private var descriptor: Int32 = -1
    private var pending = Data()

    deinit { close() }

    func connect(path: String, timeout: TimeInterval) -> Bool {
        let pathBytes = Array(path.utf8CString)
        var address = sockaddr_un()
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { return false }
        let socketDescriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketDescriptor >= 0 else { return false }
        descriptor = socketDescriptor
        var noSigPipe: Int32 = 1
        setsockopt(socketDescriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        let flags = fcntl(socketDescriptor, F_GETFL)
        guard fcntl(socketDescriptor, F_SETFL, flags | O_NONBLOCK) == 0 else { close(); return false }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            destination.initializeMemory(as: UInt8.self, repeating: 0)
            pathBytes.withUnsafeBytes { source in destination.copyBytes(from: source) }
        }
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(socketDescriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if result != 0 {
            guard errno == EINPROGRESS, wait(for: Int16(POLLOUT), until: Date().addingTimeInterval(timeout)) else {
                close(); return false
            }
            var connectionError: Int32 = 0
            var length = socklen_t(MemoryLayout<Int32>.size)
            guard getsockopt(socketDescriptor, SOL_SOCKET, SO_ERROR, &connectionError, &length) == 0,
                  connectionError == 0 else { close(); return false }
        }
        return true
    }

    func send(_ data: Data, timeout: TimeInterval) -> Bool {
        guard descriptor >= 0 else { return false }
        let deadline = Date().addingTimeInterval(timeout)
        return data.withUnsafeBytes { buffer -> Bool in
            guard var pointer = buffer.baseAddress else { return data.isEmpty }
            var remaining = buffer.count
            while remaining > 0 {
                let sent = Darwin.send(descriptor, pointer, remaining, 0)
                if sent > 0 {
                    pointer = pointer.advanced(by: sent); remaining -= sent; continue
                }
                if sent < 0, errno == EINTR { continue }
                if sent < 0, errno == EAGAIN || errno == EWOULDBLOCK,
                   wait(for: Int16(POLLOUT), until: deadline) { continue }
                return false
            }
            return true
        }
    }

    /// Reads one newline-terminated JSON object, or nil at EOF/deadline.
    func readLine(until deadline: Date, maximumBytes: Int = 1_048_576) -> [String: Any]? {
        guard descriptor >= 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: 8_192)
        while true {
            if let newline = pending.firstIndex(of: 0x0A) {
                let line = pending[pending.startIndex..<newline]
                pending.removeSubrange(pending.startIndex...newline)
                if line.isEmpty { continue }
                return (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any]
            }
            guard pending.count <= maximumBytes, wait(for: Int16(POLLIN), until: deadline) else { return nil }
            let count = Darwin.recv(descriptor, &buffer, buffer.count, 0)
            if count > 0 { pending.append(buffer, count: count); continue }
            if count < 0, errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK { continue }
            // EOF: the final object may lack a trailing newline.
            if !pending.isEmpty, let object = try? JSONSerialization.jsonObject(with: pending) as? [String: Any] {
                pending.removeAll(); return object
            }
            return nil
        }
    }

    func close() {
        if descriptor >= 0 { Darwin.close(descriptor); descriptor = -1 }
    }

    private func wait(for events: Int16, until deadline: Date) -> Bool {
        var state = pollfd(fd: descriptor, events: events, revents: 0)
        while true {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { return false }
            let milliseconds = Int32(min(Double(Int32.max), max(1, ceil(remaining * 1_000))))
            let result = Darwin.poll(&state, 1, milliseconds)
            if result > 0 { return state.revents & (events | Int16(POLLHUP) | Int16(POLLERR)) != 0 }
            if result == 0 { return false }
            if errno != EINTR { return false }
        }
    }
}

struct ClaudeCodeHookForwarder {
    let route: ClaudeCodeRoute

    private static let scalarKeys = [
        "hook_event_name", "session_id", "prompt_id", "transcript_path", "cwd", "permission_mode",
        "tool_name", "tool_use_id", "notification_type", "message", "title", "agent_id", "agent_type",
        "agent_transcript_path", "source", "model", "session_title", "stop_reason", "reason", "error",
        "stop_hook_active", "is_interrupt", "requires_permission", "auto_approved", "trigger"
    ]

    func run() {
        signal(SIGPIPE, SIG_IGN)
        guard let input = ClaudeCodeHookIO.readStandardInput(maximumBytes: 8_388_608),
              let object = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any],
              let event = object["hook_event_name"] as? String, !event.isEmpty,
              let session = object["session_id"] as? String, !session.isEmpty else { return }
        var payload: [String: Any] = [:]
        for key in Self.scalarKeys {
            if let value = ClaudeCodeHookIO.bounded(object[key], maximumBytes: 16_384) { payload[key] = value }
        }
        if let value = ClaudeCodeHookIO.bounded(object["tool_input"], maximumBytes: 262_144) { payload["tool_input"] = value }
        if let value = ClaudeCodeHookIO.bounded(object["permission_suggestions"], maximumBytes: 65_536) {
            payload["permission_suggestions"] = value
        }
        if let value = ClaudeCodeHookIO.bounded(object["last_assistant_message"], maximumBytes: 131_072) {
            payload["last_assistant_message"] = value
        }
        if let effort = object["effort"] as? [String: Any], let level = effort["level"] as? String {
            payload["effort"] = String(level.prefix(64))
        } else if let effort = object["effort"] as? String {
            payload["effort"] = String(effort.prefix(64))
        }
        payload["hook_process_id"] = Int(getppid())

        let awaitsDecision = event == "PermissionRequest" && route.interactiveApprovals != false
        let eventID = UUID().uuidString.lowercased()
        let envelope: [String: Any] = [
            "authenticationToken": route.authenticationToken,
            "eventID": eventID,
            "kind": "hook",
            "awaitDecision": awaitsDecision,
            "payload": payload
        ]
        guard JSONSerialization.isValidJSONObject(envelope),
              var data = try? JSONSerialization.data(withJSONObject: envelope) else { return }
        data.append(0x0A)
        let client = ClaudeCodeSocketClient()
        guard client.connect(path: route.socketPath, timeout: 0.5),
              client.send(data, timeout: 1) else { return }
        guard let acknowledgement = client.readLine(until: Date().addingTimeInterval(awaitsDecision ? 2 : 0.75)),
              acknowledgement["eventID"] as? String == eventID,
              acknowledgement["accepted"] as? Bool == true else { return }
        guard awaitsDecision, acknowledgement["pending"] as? Bool == true else { return }

        let timeout = min(max(route.decisionTimeoutSeconds ?? 3_540, 5), 86_400)
        guard let reply = client.readLine(until: Date().addingTimeInterval(timeout)),
              reply["eventID"] as? String == eventID,
              let decision = reply["decision"] as? [String: Any],
              let behavior = decision["behavior"] as? String else { return }
        var output: [String: Any] = [:]
        switch behavior {
        case "allow":
            output["behavior"] = "allow"
            if let updatedInput = decision["updatedInput"] as? [String: Any] { output["updatedInput"] = updatedInput }
            if let permissions = decision["updatedPermissions"] as? [Any], !permissions.isEmpty {
                output["updatedPermissions"] = permissions
            }
        case "deny":
            output["behavior"] = "deny"
            if let message = decision["message"] as? String, !message.isEmpty { output["message"] = message }
            if decision["interrupt"] as? Bool == true { output["interrupt"] = true }
        default:
            // "passthrough": let Claude Code's own dialog decide.
            return
        }
        let hookOutput: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": output
            ]
        ]
        guard JSONSerialization.isValidJSONObject(hookOutput),
              let encoded = try? JSONSerialization.data(withJSONObject: hookOutput) else { return }
        ClaudeCodeHookIO.writeStandardOutput(encoded)
    }
}

struct ClaudeCodeStatusLineForwarder {
    let route: ClaudeCodeRoute

    func run() {
        signal(SIGPIPE, SIG_IGN)
        let input = ClaudeCodeHookIO.readStandardInput(maximumBytes: 2_097_152) ?? Data()
        let object = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any] ?? [:]
        if !object.isEmpty { record(object) }
        if let command = route.statusLineForwardCommand?.trimmingCharacters(in: .whitespacesAndNewlines),
           !command.isEmpty, let output = forward(command: command, input: input) {
            ClaudeCodeHookIO.writeStandardOutput(output)
            return
        }
        ClaudeCodeHookIO.writeStandardOutput(Data(compactLine(object).utf8))
    }

    private func record(_ object: [String: Any]) {
        var snapshot: [String: Any] = ["capturedAt": Date().timeIntervalSince1970]
        for key in ["session_id", "version", "rate_limits", "cost", "model", "context_window", "exceeds_200k_tokens"] {
            if let value = ClaudeCodeHookIO.bounded(object[key], maximumBytes: 16_384) { snapshot[key] = value }
        }
        if let workspace = object["workspace"] as? [String: Any], let directory = workspace["current_dir"] as? String {
            snapshot["cwd"] = String(directory.prefix(4_096))
        } else if let directory = object["cwd"] as? String {
            snapshot["cwd"] = String(directory.prefix(4_096))
        }
        guard JSONSerialization.isValidJSONObject(snapshot),
              let data = try? JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys]) else { return }
        if let path = route.statusLineSnapshotPath, path.hasPrefix("/") {
            writePrivate(data, to: path)
        }
        // Best effort live notification; the file remains the durable source.
        let envelope: [String: Any] = [
            "authenticationToken": route.authenticationToken,
            "eventID": UUID().uuidString.lowercased(),
            "kind": "statusLine",
            "awaitDecision": false,
            "payload": snapshot
        ]
        guard JSONSerialization.isValidJSONObject(envelope),
              var message = try? JSONSerialization.data(withJSONObject: envelope) else { return }
        message.append(0x0A)
        let client = ClaudeCodeSocketClient()
        if client.connect(path: route.socketPath, timeout: 0.15) {
            _ = client.send(message, timeout: 0.25)
            _ = client.readLine(until: Date().addingTimeInterval(0.25))
        }
    }

    private func writePrivate(_ data: Data, to path: String) {
        let directory = (path as NSString).deletingLastPathComponent
        var metadata = stat()
        guard lstat(directory, &metadata) == 0, metadata.st_uid == getuid(),
              metadata.st_mode & S_IFMT == S_IFDIR else { return }
        let temporary = directory + "/.claude-statusline-\(getpid()).tmp"
        let descriptor = Darwin.open(temporary, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return }
        let written = data.withUnsafeBytes { buffer -> Bool in
            guard var pointer = buffer.baseAddress else { return false }
            var remaining = buffer.count
            while remaining > 0 {
                let count = Darwin.write(descriptor, pointer, remaining)
                guard count > 0 else { return false }
                pointer = pointer.advanced(by: count); remaining -= count
            }
            return true
        }
        Darwin.close(descriptor)
        if !written || rename(temporary, path) != 0 { unlink(temporary) }
    }

    private func forward(command: String, input: Data) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        let stdinPipe = Pipe(), stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let writer = stdinPipe.fileHandleForWriting
        DispatchQueue.global(qos: .userInitiated).async {
            try? writer.write(contentsOf: input)
            try? writer.close()
        }
        var output = Data()
        let reader = stdoutPipe.fileHandleForReading
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            output = reader.readDataToEndOfFile()
            group.leave()
        }
        if group.wait(timeout: .now() + 5) == .timedOut {
            process.terminate()
            return nil
        }
        process.waitUntilExit()
        return output
    }

    private func compactLine(_ object: [String: Any]) -> String {
        var parts: [String] = []
        if let model = object["model"] as? [String: Any], let name = model["display_name"] as? String, !name.isEmpty {
            parts.append(name)
        }
        if let workspace = object["workspace"] as? [String: Any], let directory = workspace["current_dir"] as? String {
            let name = (directory as NSString).lastPathComponent
            if !name.isEmpty { parts.append(name) }
        }
        if let context = object["context_window"] as? [String: Any],
           let used = context["used_percentage"] as? NSNumber {
            parts.append("ctx \(Int(used.doubleValue.rounded()))%")
        }
        if let limits = object["rate_limits"] as? [String: Any] {
            if let window = limits["five_hour"] as? [String: Any], let used = window["used_percentage"] as? NSNumber {
                parts.append("5h \(Int(used.doubleValue.rounded()))%")
            }
            if let window = limits["seven_day"] as? [String: Any], let used = window["used_percentage"] as? NSNumber {
                parts.append("7d \(Int(used.doubleValue.rounded()))%")
            }
        }
        return parts.joined(separator: " · ")
    }
}

/// Kimi's hooks are observation-only here: never print a permission decision.
enum NativeAgentHookForwarder {
    static func run(route: ClaudeCodeRoute) {
        guard let data = ClaudeCodeHookIO.readStandardInput(maximumBytes: 1_048_576),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let event = object["hook_event_name"] as? String,
              let session = object["session_id"] as? String, !session.isEmpty, session.utf8.count <= 256 else { return }
        var payload: [String: Any] = ["hook_event_name": event, "session_id": session]
        for key in ["turn_id", "prompt_id", "tool_name", "tool_use_id", "tool_call_id", "model", "session_title", "agent_id", "source", "reason"] {
            if let value = object[key] as? String { payload[key] = String(value.prefix(256)) }
        }
        let eventID = UUID().uuidString
        let envelope: [String: Any] = ["authenticationToken": route.authenticationToken, "eventID": eventID,
            "kind": "hook", "awaitDecision": false, "payload": payload]
        guard var line = try? JSONSerialization.data(withJSONObject: envelope) else { return }
        line.append(0x0A)
        let client = ClaudeCodeSocketClient()
        guard client.connect(path: route.socketPath, timeout: 0.25), client.send(line, timeout: 0.25) else { return }
        _ = client.readLine(until: Date().addingTimeInterval(0.25))
    }
}
