import CryptoKit
import Darwin
import Foundation
import OSLog

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
    case stop = "Stop"
}

private enum ToolCategory: String, Codable {
    case shell
    case fileEdit
    case mcp
    case subagent
    case localTool
}

private enum SessionStartSource: String, Codable {
    case startup
    case resume
    case clear
    case compact
}

private struct SanitizedActivity: Codable {
    let schemaVersion: Int
    let event: HookEvent
    let sessionHash: String
    let turnHash: String?
    let workspaceName: String?
    let toolCategory: ToolCategory?
    let sessionStartSource: SessionStartSource?
    let occurredAt: Date
}

private struct BridgeEnvelope: Codable {
    let authenticationToken: String
    let installationIdentifier: String
    let activity: SanitizedActivity
}

private struct Arguments {
    let socketPath: String
    let authenticationToken: String
    let installationIdentifier: String

    init?(_ arguments: [String]) {
        guard let socketIndex = arguments.firstIndex(of: "--socket"),
              arguments.indices.contains(socketIndex + 1),
              let tokenIndex = arguments.firstIndex(of: "--token"),
              arguments.indices.contains(tokenIndex + 1),
              let installationIndex = arguments.firstIndex(
                of: "--installation-id"
              ),
              arguments.indices.contains(installationIndex + 1)
        else {
            return nil
        }

        let socketPath = arguments[socketIndex + 1]
        let authenticationToken = arguments[tokenIndex + 1]
        let installationIdentifier =
            arguments[installationIndex + 1]
        guard !socketPath.isEmpty,
              !authenticationToken.isEmpty,
              !installationIdentifier.isEmpty
        else {
            return nil
        }
        self.socketPath = socketPath
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
    return .localTool
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
    return SanitizedActivity(
        schemaVersion: 1,
        event: event,
        sessionHash: hashIdentifier(sessionID),
        turnHash: turnID.map(hashIdentifier),
        workspaceName: sanitizedWorkspaceName(input["cwd"] as? String),
        toolCategory: toolCategory(input["tool_name"] as? String),
        sessionStartSource: (input["source"] as? String)
            .flatMap(SessionStartSource.init(rawValue:)),
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
    guard didConnect == 0 else {
        return .failed("socket_connection_failed")
    }

    let didWrite = data.withUnsafeBytes { rawBuffer in
        guard var pointer = rawBuffer.baseAddress else {
            return data.isEmpty
        }
        var remaining = rawBuffer.count
        while remaining > 0 {
            let sent = Darwin.send(descriptor, pointer, remaining, 0)
            guard sent > 0 else { return false }
            pointer = pointer.advanced(by: sent)
            remaining -= sent
        }
        return true
    }
    return didWrite ? .delivered : .failed("socket_write_failed")
}

private func defaultQueuePath() -> String {
    "/tmp/com.quotaview.codex-activity-\(getuid())"
}

private func writeFallback(
    _ data: Data,
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

    let identifier = UUID().uuidString.lowercased()
    let temporaryPath = "\(queuePath)/.event-\(identifier).tmp"
    let finalPath = "\(queuePath)/event-\(identifier).json"
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
    fallbackSucceeded: Bool,
    queuePath: String
) {
    let outcome = fallbackSucceeded ? "queued" : "failed"
    diagnosticLogger.error(
        "activity delivery \(code, privacy: .public); fallback \(outcome, privacy: .public)"
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

    var metadata = stat()
    guard fstat(descriptor, &metadata) == 0,
          metadata.st_uid == getuid(),
          metadata.st_mode & S_IFMT == S_IFREG,
          metadata.st_mode & (S_IRWXG | S_IRWXO) == 0,
          metadata.st_size <= 65_536
    else {
        return
    }

    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "\(timestamp) code=\(code) fallback=\(outcome)\n"
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
guard let activity = sanitize(input),
      let payload = try? JSONEncoder().encode(
          BridgeEnvelope(
              authenticationToken: arguments.authenticationToken,
              installationIdentifier:
                  arguments.installationIdentifier,
              activity: activity
          )
      )
else {
    exit(0)
}

switch send(payload, to: arguments.socketPath) {
case .delivered:
    break
case .failed(let code):
    let queuePath = defaultQueuePath()
    let fallbackSucceeded = writeFallback(payload, to: queuePath)
    appendDiagnostic(
        code: code,
        fallbackSucceeded: fallbackSucceeded,
        queuePath: queuePath
    )
}
