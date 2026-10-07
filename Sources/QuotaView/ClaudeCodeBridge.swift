import Darwin
import Foundation

struct ClaudeCodeBridgeMessage: Sendable {
    let eventID: String
    let kind: String
    let awaitsDecision: Bool
    /// The helper's bounded payload object, re-encoded for crossing actors.
    let payload: Data
}

/// Private Unix socket for the Claude Code helper. One newline-terminated JSON
/// request per connection. A PermissionRequest connection stays open until
/// QuotaView answers or the helper exits (Claude Code resolved it itself).
final class ClaudeCodeBridge: @unchecked Sendable {
    enum BridgeError: LocalizedError {
        case socketPathTooLong, bindFailed, listenFailed
        var errorDescription: String? {
            switch self {
            case .socketPathTooLong: "Claude Code 监听路径过长。"
            case .bindFailed: "无法绑定 Claude Code 监听端口。"
            case .listenFailed: "无法启动 Claude Code 监听。"
            }
        }
    }

    typealias MessageHandler = @Sendable (ClaudeCodeBridgeMessage) -> Void
    typealias DisconnectHandler = @Sendable (String) -> Void

    static let maximumRequestBytes = 1_572_864
    static let maximumPendingConnections = 64

    let socketURL: URL
    private let authenticationToken: String
    private let queue = DispatchQueue(label: "com.duoasa.QuotaView.claude-code-bridge", qos: .userInitiated)
    private var listener: Int32 = -1
    private var lockDescriptor: Int32 = -1
    private var socketIdentity: (device: dev_t, inode: ino_t)?
    private var acceptSource: DispatchSourceRead?
    private var onMessage: MessageHandler?
    private var onDisconnect: DisconnectHandler?
    private struct PendingConnection { let descriptor: Int32; let source: DispatchSourceRead }
    private var pending: [String: PendingConnection] = [:]

    init(socketURL: URL, authenticationToken: String) {
        self.socketURL = socketURL
        self.authenticationToken = authenticationToken
    }

    deinit { stop() }

    func start(onMessage: @escaping MessageHandler, onDisconnect: @escaping DisconnectHandler) throws {
        try queue.sync {
            stopOnQueue()
            self.onMessage = onMessage
            self.onDisconnect = onDisconnect
            try listenOnQueue()
        }
    }

    func stop() {
        queue.sync { stopOnQueue() }
    }

    /// Sends a decision line and closes the connection. `nil` closes without a
    /// decision, which leaves Claude Code's own terminal dialog in charge.
    func resolve(eventID: String, decision: [String: Any]?) {
        let line: Data?
        if let decision, JSONSerialization.isValidJSONObject(["eventID": eventID, "decision": decision]) {
            line = try? JSONSerialization.data(withJSONObject: ["eventID": eventID, "decision": decision])
        } else { line = nil }
        queue.async { [weak self] in
            guard let self, let connection = pending.removeValue(forKey: eventID) else { return }
            connection.source.cancel()
            if var line { line.append(0x0A); Self.write(line, to: connection.descriptor) }
            Darwin.close(connection.descriptor)
        }
    }

    private func listenOnQueue() throws {
        let directory = socketURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        chmod(directory.path, S_IRWXU)
        let lock = Darwin.open(socketURL.path + ".lock", O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard lock >= 0 else { throw BridgeError.bindFailed }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { Darwin.close(lock); throw BridgeError.bindFailed }
        lockDescriptor = lock
        unlink(socketURL.path)

        let pathBytes = Array(socketURL.path.utf8CString)
        var address = sockaddr_un()
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            releaseLock(); throw BridgeError.socketPathTooLong
        }
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { releaseLock(); throw BridgeError.bindFailed }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            destination.initializeMemory(as: UInt8.self, repeating: 0)
            pathBytes.withUnsafeBytes { destination.copyBytes(from: $0) }
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else { Darwin.close(descriptor); releaseLock(); throw BridgeError.bindFailed }
        chmod(socketURL.path, S_IRUSR | S_IWUSR)
        var metadata = stat()
        if lstat(socketURL.path, &metadata) == 0 { socketIdentity = (metadata.st_dev, metadata.st_ino) }
        guard Darwin.listen(descriptor, 32) == 0 else {
            Darwin.close(descriptor); removeOwnedSocket(); releaseLock(); throw BridgeError.listenFailed
        }
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
        listener = descriptor
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptConnections() }
        acceptSource = source
        source.resume()
    }

    private func stopOnQueue() {
        acceptSource?.cancel(); acceptSource = nil
        if listener >= 0 { Darwin.close(listener); listener = -1; removeOwnedSocket() }
        for connection in pending.values { connection.source.cancel(); Darwin.close(connection.descriptor) }
        let abandoned = Array(pending.keys)
        pending.removeAll()
        if let onDisconnect { abandoned.forEach(onDisconnect) }
        releaseLock()
        onMessage = nil; onDisconnect = nil
    }

    private func removeOwnedSocket() {
        var current = stat()
        if let socketIdentity, lstat(socketURL.path, &current) == 0,
           current.st_dev == socketIdentity.device, current.st_ino == socketIdentity.inode { unlink(socketURL.path) }
        socketIdentity = nil
    }

    private func releaseLock() {
        if lockDescriptor >= 0 { _ = flock(lockDescriptor, LOCK_UN); Darwin.close(lockDescriptor); lockDescriptor = -1 }
    }

    private func acceptConnections() {
        while listener >= 0 {
            let connection = Darwin.accept(listener, nil, nil)
            guard connection >= 0 else { return }
            var noSigPipe: Int32 = 1
            setsockopt(connection, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
            var timeout = timeval(tv_sec: 1, tv_usec: 0)
            setsockopt(connection, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            setsockopt(connection, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            handle(connection)
        }
    }

    private func handle(_ connection: Int32) {
        guard let line = Self.readLine(connection),
              let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              let token = object["authenticationToken"] as? String, Self.constantTimeEqual(token, authenticationToken),
              let eventID = object["eventID"] as? String, !eventID.isEmpty, eventID.utf8.count <= 128,
              let kind = object["kind"] as? String, ["hook", "statusLine"].contains(kind),
              let payload = object["payload"] as? [String: Any],
              let payloadData = try? JSONSerialization.data(withJSONObject: payload),
              let onMessage else {
            Darwin.close(connection); return
        }
        let wantsDecision = kind == "hook" && object["awaitDecision"] as? Bool == true
        let holds = wantsDecision && pending.count < Self.maximumPendingConnections && pending[eventID] == nil
        var acknowledgement: [String: Any] = ["eventID": eventID, "accepted": true]
        if holds { acknowledgement["pending"] = true }
        guard var ack = try? JSONSerialization.data(withJSONObject: acknowledgement) else { Darwin.close(connection); return }
        ack.append(0x0A)
        guard Self.write(ack, to: connection) else { Darwin.close(connection); return }
        if holds {
            // Any readable event on an idle request connection is EOF or an error:
            // the helper was terminated, so Claude Code settled the prompt itself.
            let source = DispatchSource.makeReadSource(fileDescriptor: connection, queue: queue)
            source.setEventHandler { [weak self] in
                guard let self, let current = pending[eventID], current.descriptor == connection else { return }
                var byte: UInt8 = 0
                let count = Darwin.recv(connection, &byte, 1, MSG_PEEK | MSG_DONTWAIT)
                if count < 0, errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR { return }
                if count > 0 { _ = Darwin.recv(connection, &byte, 1, MSG_DONTWAIT); return }
                pending.removeValue(forKey: eventID)
                current.source.cancel()
                Darwin.close(connection)
                onDisconnect?(eventID)
            }
            pending[eventID] = .init(descriptor: connection, source: source)
            source.resume()
        } else {
            Darwin.close(connection)
        }
        onMessage(.init(eventID: eventID, kind: kind, awaitsDecision: holds, payload: payloadData))
    }

    private static func readLine(_ connection: Int32) -> Data? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while data.count <= maximumRequestBytes {
            let count = Darwin.recv(connection, &buffer, buffer.count, 0)
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { return nil }
            if let newline = buffer[0..<count].firstIndex(of: 0x0A) {
                data.append(contentsOf: buffer[0..<newline])
                return data
            }
            data.append(contentsOf: buffer[0..<count])
        }
        return nil
    }

    @discardableResult
    private static func write(_ data: Data, to connection: Int32) -> Bool {
        data.withUnsafeBytes { buffer -> Bool in
            guard var pointer = buffer.baseAddress else { return false }
            var remaining = buffer.count
            while remaining > 0 {
                let written = Darwin.send(connection, pointer, remaining, 0)
                if written < 0, errno == EINTR { continue }
                guard written > 0 else { return false }
                pointer = pointer.advanced(by: written); remaining -= written
            }
            return true
        }
    }

    private static func constantTimeEqual(_ received: String, _ expected: String) -> Bool {
        let left = Array(received.utf8), right = Array(expected.utf8)
        guard left.count == right.count else { return false }
        return zip(left, right).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
