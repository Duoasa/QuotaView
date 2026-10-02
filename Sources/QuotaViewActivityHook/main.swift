import CryptoKit
import Darwin
import Foundation
import OSLog
#if SWIFT_PACKAGE
import QuotaViewActivityHookSupport
#endif

private let diagnosticLogger = Logger(
    subsystem: "com.quotaview.menubar",
    category: "CodexActivityHook"
)

private enum HookEvent: String, Codable {
    case sessionStart = "SessionStart"
    case sessionEnd = "SessionEnd"
    case userPromptSubmit = "UserPromptSubmit"
    case preToolUse = "PreToolUse"
    case permissionRequest = "PermissionRequest"
    case postToolUse = "PostToolUse"
    case preCompact = "PreCompact"
    case postCompact = "PostCompact"
    case subagentStart = "SubagentStart"
    case subagentStop = "SubagentStop"
    case interrupt = "Interrupt"
    case stop = "Stop"
}

private enum ToolCategory: String, Codable {
    case shell
    case fileEdit
    case mcp
    case subagent
    case goal
    case localTool
}

private enum ActivitySource: String, Codable {
    case hook
}

private enum PlanSource: String, Codable {
    case legacyTool
}

private enum SessionStartSource: String, Codable {
    case startup
    case resume
    case clear
    case compact
}

private struct SanitizedPlanProgress: Codable {
    let completedSteps: Int
    let inProgressSteps: Int
    let pendingSteps: Int
}

private struct SanitizedActivity: Codable {
    let schemaVersion: Int
    let event: HookEvent
    let sessionHash: String
    let turnHash: String?
    let toolCallHash: String?
    let toolName: String?
    let workspaceName: String?
    let toolCategory: ToolCategory?
    let sessionStartSource: SessionStartSource?
    let planProgress: SanitizedPlanProgress?
    let source: ActivitySource
    let planSource: PlanSource?
    let occurredAt: Date
}

private struct BridgeEnvelope: Codable {
    let authenticationToken: String
    let installationIdentifier: String
    let eventID: String
    let activity: SanitizedActivity
}

private struct DeliveryAcknowledgement: Codable {
    let eventID: String?
    let accepted: Bool
}

private struct RouteConfiguration: Decodable {
    let version: Int
    let socketPath: String
    let queuePath: String
    let authenticationToken: String
    let installationIdentifier: String

    static func read(from path: String) -> RouteConfiguration? {
        let descriptor = Darwin.open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        defer { Darwin.close(descriptor) }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              metadata.st_uid == getuid(),
              metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_mode & (S_IRWXG | S_IRWXO) == 0,
              metadata.st_size > 0, metadata.st_size <= 16_384 else { return nil }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        guard let data = try? handle.read(upToCount: 16_385), data.count <= 16_384,
              let route = try? JSONDecoder().decode(RouteConfiguration.self, from: data),
              route.version == 1,
              route.socketPath.hasPrefix("/"), route.queuePath.hasPrefix("/"),
              !route.authenticationToken.isEmpty, !route.installationIdentifier.isEmpty else { return nil }
        return route
    }
}

private struct Arguments {
    let socketPath: String
    let queuePath: String
    let authenticationToken: String
    let installationIdentifier: String

    init?(_ arguments: [String]) {
        if arguments.first == "--configuration" {
            guard arguments.count == 2,
                  let route = RouteConfiguration.read(from: arguments[1]) else { return nil }
            self.socketPath = route.socketPath
            self.queuePath = route.queuePath
            self.authenticationToken = route.authenticationToken
            self.installationIdentifier = route.installationIdentifier
            return
        }
        func value(for name: String) -> String? {
            guard let index = arguments.firstIndex(of: name),
                  arguments.indices.contains(index + 1) else { return nil }
            let value = arguments[index + 1]
            return value.isEmpty ? nil : value
        }
        // Existing approved definitions can continue delivering during migration.
        guard let socketPath = value(for: "--socket"),
              let authenticationToken = value(for: "--token"),
              let installationIdentifier = value(for: "--installation-id") else { return nil }
        self.socketPath = socketPath
        self.queuePath = value(for: "--queue") ?? defaultQueuePath()
        self.authenticationToken = authenticationToken
        self.installationIdentifier = installationIdentifier
    }
}

private func hashIdentifier(_ identifier: String) -> String {
    let digest = SHA256.hash(data: Data(identifier.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
}

private func sanitizedWorkspaceName(_ path: String?) -> String? {
    guard let path, !path.isEmpty else { return nil }
    let name = URL(fileURLWithPath: path)
        .standardizedFileURL
        .lastPathComponent
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return name.isEmpty ? nil : String(name.prefix(80))
}

private func toolCategory(_ canonicalName: String?) -> ToolCategory? {
    guard let canonicalName, !canonicalName.isEmpty else {
        return nil
    }
    if canonicalName == "Bash" || canonicalName == "exec_command" {
        return .shell
    }
    if ["apply_patch", "Edit", "Write"].contains(canonicalName) {
        return .fileEdit
    }
    if canonicalName == "Agent"
        || canonicalName == "spawn_agent"
        || canonicalName.contains("subagent")
    {
        return .subagent
    }
    if canonicalName.hasPrefix("mcp__") {
        return .mcp
    }
    if ["create_goal", "get_goal", "update_goal"].contains(
        canonicalName
    ) || canonicalName.hasSuffix("__create_goal")
        || canonicalName.hasSuffix("__get_goal")
        || canonicalName.hasSuffix("__update_goal")
    {
        return .goal
    }
    return .localTool
}

private func sanitizedPlanProgress(
    event: HookEvent,
    toolName: String?,
    toolInput: Any?
) -> SanitizedPlanProgress? {
    guard event == .preToolUse,
          let parsed = CodexActivityPlanInputParser.parse(
              toolName: toolName,
              toolInput: toolInput
          )
    else { return nil }
    return SanitizedPlanProgress(
        completedSteps: parsed.completedSteps,
        inProgressSteps: parsed.inProgressSteps,
        pendingSteps: parsed.pendingSteps
    )
}

private func sanitize(_ data: Data) -> SanitizedActivity? {
    guard data.count <= 2_097_152,
          let object = try? JSONSerialization.jsonObject(with: data),
          let input = object as? [String: Any],
          let eventName = input["hook_event_name"] as? String,
          let event = HookEvent(rawValue: eventName),
          let sessionID = input["session_id"] as? String,
          !sessionID.isEmpty
    else {
        return nil
    }

    let turnID = input["turn_id"] as? String
    let toolName = input["tool_name"] as? String
    let planProgress = sanitizedPlanProgress(
        event: event,
        toolName: toolName,
        toolInput: input["tool_input"]
    )
    return SanitizedActivity(
        schemaVersion: 3,
        event: event,
        sessionHash: hashIdentifier(sessionID),
        turnHash: turnID.map(hashIdentifier),
        toolCallHash: ["tool_use_id", "tool_call_id", "call_id", "item_id"]
            .compactMap { input[$0] as? String }.first(where: { !$0.isEmpty })
            .map(hashIdentifier),
        toolName: toolName.flatMap { name in
            let canonicalName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return canonicalName.isEmpty ? nil : String(canonicalName.prefix(256))
        },
        workspaceName: sanitizedWorkspaceName(input["cwd"] as? String),
        toolCategory: toolCategory(toolName),
        sessionStartSource: (input["source"] as? String)
            .flatMap(SessionStartSource.init(rawValue:)),
        planProgress: planProgress,
        source: .hook,
        planSource: planProgress == nil ? nil : .legacyTool,
        occurredAt: Date()
    )
}

private func readBoundedStandardInput(
    maximumBytes: Int
) -> Data? {
    var data = Data()
    while data.count <= maximumBytes {
        let remaining = maximumBytes + 1 - data.count
        let chunk: Data?
        do {
            chunk = try FileHandle.standardInput.read(
                upToCount: min(65_536, remaining)
            )
        } catch {
            return nil
        }
        guard let chunk, !chunk.isEmpty else {
            return data
        }
        data.append(chunk)
        if data.count > maximumBytes {
            return nil
        }
    }
    return nil
}

private enum SocketDeliveryResult {
    case delivered
    case failed(String)
}

private func send(
    _ data: Data,
    eventID: String,
    to socketPath: String
) -> SocketDeliveryResult {
    let pathBytes = Array(socketPath.utf8CString)
    var address = sockaddr_un()
    guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
        return .failed("socket_path_too_long")
    }

    let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else {
        return .failed("socket_creation_failed")
    }
    defer { Darwin.close(descriptor) }
    guard fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0 else {
        return .failed("socket_nonblocking_setup_failed")
    }
    let deadline = Date().addingTimeInterval(0.75)
    func ready(for events: Int16) -> Bool {
        var descriptorState = pollfd(fd: descriptor, events: events, revents: 0)
        while Date() < deadline {
            let remaining = max(1, Int32(ceil(deadline.timeIntervalSinceNow * 1_000)))
            let result = Darwin.poll(&descriptorState, 1, remaining)
            if result > 0 { return descriptorState.revents & events != 0 }
            if result == 0 || errno != EINTR { return false }
        }
        return false
    }

    var noSigPipe: Int32 = 1
    setsockopt(
        descriptor,
        SOL_SOCKET,
        SO_NOSIGPIPE,
        &noSigPipe,
        socklen_t(MemoryLayout<Int32>.size)
    )

    address.sun_family = sa_family_t(AF_UNIX)
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    withUnsafeMutableBytes(of: &address.sun_path) { destination in
        destination.initializeMemory(as: UInt8.self, repeating: 0)
        pathBytes.withUnsafeBytes { source in
            destination.copyBytes(from: source)
        }
    }

    let didConnect = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(
            to: sockaddr.self,
            capacity: 1
        ) { socketAddress in
            Darwin.connect(
                descriptor,
                socketAddress,
                socklen_t(MemoryLayout<sockaddr_un>.size)
            )
        }
    }
    if didConnect != 0 {
        guard errno == EINPROGRESS, ready(for: Int16(POLLOUT)) else {
            return .failed("socket_connection_failed")
        }
        var connectionError: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &connectionError, &length) == 0,
              connectionError == 0 else { return .failed("socket_connection_failed") }
    }

    let didWrite = data.withUnsafeBytes { rawBuffer in
        guard var pointer = rawBuffer.baseAddress else {
            return data.isEmpty
        }
        var remaining = rawBuffer.count
        while remaining > 0 {
            guard Date() < deadline else { return false }
            let sent = Darwin.send(descriptor, pointer, remaining, 0)
            if sent <= 0 {
                if errno == EINTR { continue }
                if (errno == EAGAIN || errno == EWOULDBLOCK), ready(for: Int16(POLLOUT)) { continue }
                return false
            }
            pointer = pointer.advanced(by: sent)
            remaining -= sent
        }
        return true
    }
    guard didWrite else { return .failed("socket_write_failed") }

    var acknowledgementData = Data()
    var acknowledgementBuffer = [UInt8](repeating: 0, count: 1_024)
    while acknowledgementData.count <= 4_096 {
        guard ready(for: Int16(POLLIN)) else { break }
        let count = Darwin.recv(
            descriptor,
            &acknowledgementBuffer,
            acknowledgementBuffer.count,
            0
        )
        if count <= 0 {
            if count < 0, errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK { continue }
            break
        }
        acknowledgementData.append(
            acknowledgementBuffer,
            count: count
        )
        if let acknowledgement = try? JSONDecoder().decode(
            DeliveryAcknowledgement.self,
            from: acknowledgementData
        ) {
            guard acknowledgement.accepted,
                  acknowledgement.eventID == eventID
            else {
                return .failed("socket_event_rejected")
            }
            return .delivered
        }
    }
    return .failed("socket_acknowledgement_missing")
}

private func defaultQueuePath() -> String {
    "/tmp/com.quotaview.codex-activity-\(getuid())"
}

private func writeFallback(
    _ data: Data,
    eventID: String,
    to queuePath: String
) -> Bool {
    guard !data.isEmpty, data.count <= 65_536 else {
        return false
    }

    var directoryMetadata = stat()
    guard lstat(queuePath, &directoryMetadata) == 0,
          directoryMetadata.st_uid == getuid(),
          directoryMetadata.st_mode & S_IFMT == S_IFDIR,
          directoryMetadata.st_mode & (S_IRWXG | S_IRWXO) == 0
    else {
        return false
    }

    let fileManager = FileManager.default
    guard let existingFiles = try? fileManager.contentsOfDirectory(
        atPath: queuePath
    ) else {
        return false
    }
    let queuedCount = existingFiles.lazy.filter {
        $0.hasPrefix("event-") && $0.hasSuffix(".json")
    }.prefix(128).count
    guard queuedCount < 128 else { return false }

    let temporaryPath = "\(queuePath)/.event-\(eventID).tmp"
    let finalPath = "\(queuePath)/event-\(eventID).json"
    let descriptor = Darwin.open(
        temporaryPath,
        O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
        S_IRUSR | S_IWUSR
    )
    guard descriptor >= 0 else { return false }

    var didClose = false
    var didRename = false
    defer {
        if !didClose {
            Darwin.close(descriptor)
        }
        if !didRename {
            unlink(temporaryPath)
        }
    }

    let didWrite = data.withUnsafeBytes { rawBuffer in
        guard var pointer = rawBuffer.baseAddress else { return false }
        var remaining = rawBuffer.count
        while remaining > 0 {
            let written = Darwin.write(descriptor, pointer, remaining)
            guard written > 0 else { return false }
            pointer = pointer.advanced(by: written)
            remaining -= written
        }
        return true
    }
    guard didWrite else { return false }

    guard Darwin.close(descriptor) == 0 else { return false }
    didClose = true
    guard rename(temporaryPath, finalPath) == 0 else { return false }
    didRename = true
    return true
}

private func appendDiagnostic(
    code: String,
    event: HookEvent,
    outcome: String,
    queuePath: String
) {
    diagnosticLogger.info(
        "activity \(event.rawValue, privacy: .public) delivery \(code, privacy: .public); outcome \(outcome, privacy: .public)"
    )

    var directoryMetadata = stat()
    guard lstat(queuePath, &directoryMetadata) == 0,
          directoryMetadata.st_uid == getuid(),
          directoryMetadata.st_mode & S_IFMT == S_IFDIR,
          directoryMetadata.st_mode & (S_IRWXG | S_IRWXO) == 0
    else {
        return
    }

    let path = "\(queuePath)/diagnostics.log"
    let descriptor = Darwin.open(
        path,
        O_WRONLY | O_CREAT | O_APPEND | O_NOFOLLOW | O_CLOEXEC,
        S_IRUSR | S_IWUSR
    )
    guard descriptor >= 0 else { return }
    defer { Darwin.close(descriptor) }

    guard Darwin.lockf(descriptor, F_LOCK, 0) == 0 else { return }
    defer { Darwin.lockf(descriptor, F_ULOCK, 0) }

    var metadata = stat()
    guard fstat(descriptor, &metadata) == 0,
          metadata.st_uid == getuid(),
          metadata.st_mode & S_IFMT == S_IFREG,
          metadata.st_mode & (S_IRWXG | S_IRWXO) == 0
    else {
        return
    }

    if metadata.st_size >= 65_536 {
        guard ftruncate(descriptor, 0) == 0 else { return }
    }

    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "\(timestamp) event=\(event.rawValue) code=\(code) outcome=\(outcome)\n"
    _ = line.withCString { pointer in
        Darwin.write(descriptor, pointer, strlen(pointer))
    }
}

guard let arguments = Arguments(Array(CommandLine.arguments.dropFirst())) else {
    exit(0)
}

guard let input = readBoundedStandardInput(maximumBytes: 2_097_152)
else {
    exit(0)
}
let eventID = UUID().uuidString.lowercased()
guard let activity = sanitize(input),
      let payload = try? JSONEncoder().encode(
          BridgeEnvelope(
              authenticationToken: arguments.authenticationToken,
              installationIdentifier:
                  arguments.installationIdentifier,
              eventID: eventID,
              activity: activity
          )
      )
else {
    exit(0)
}

switch send(payload, eventID: eventID, to: arguments.socketPath) {
case .delivered:
    appendDiagnostic(
        code: "socket_acknowledged",
        event: activity.event,
        outcome: "accepted",
        queuePath: arguments.queuePath
    )
case .failed(let code):
    let queuePath = arguments.queuePath
    let fallbackSucceeded = writeFallback(
        payload,
        eventID: eventID,
        to: queuePath
    )
    appendDiagnostic(
        code: code,
        event: activity.event,
        outcome: fallbackSucceeded ? "queued" : "failed",
        queuePath: queuePath
    )
}
