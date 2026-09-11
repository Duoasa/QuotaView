import Darwin
import Foundation
import QuotaViewCore


typealias CodexActivityDeliveryHandler = (
    CodexActivityDelivery,
    @escaping @Sendable (Bool) -> Void
) -> Void

private struct CodexActivityDeliveryAcknowledgement: Codable {
    let eventID: String?
    let accepted: Bool
}

final class CodexActivityUnixBridge: @unchecked Sendable {
    enum BridgeError: LocalizedError {
        case socketCreationFailed
        case socketPathTooLong
        case bindFailed
        case listenFailed

        var errorDescription: String? {
            switch self {
            case .socketCreationFailed:
                "无法创建 Codex 灵动岛监听端口。"
            case .socketPathTooLong:
                "Codex 灵动岛监听路径过长。"
            case .bindFailed:
                "无法绑定 Codex 灵动岛监听端口。"
            case .listenFailed:
                "无法启动 Codex 灵动岛监听。"
            }
        }
    }

    private let socketURL: URL
    private let authenticationToken: String
    private let installationIdentifier: String
    private let queue = DispatchQueue(
        label: "com.duoasa.QuotaView.codex-activity-bridge",
        qos: .utility
    )
    private var source: DispatchSourceRead?
    private var descriptor: Int32 = -1
    private var handler: CodexActivityDeliveryHandler?

    init(
        socketURL: URL,
        authenticationToken: String,
        installationIdentifier: String
    ) {
        self.socketURL = socketURL
        self.authenticationToken = authenticationToken
        self.installationIdentifier = installationIdentifier
    }

    func start(
        handler: @escaping CodexActivityDeliveryHandler
    ) throws {
        stop()
        self.handler = handler

        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: socketURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        unlink(socketURL.path)

        let pathBytes = Array(socketURL.path.utf8CString)
        var address = sockaddr_un()
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path)
        else {
            throw BridgeError.socketPathTooLong
        }

        let listener = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0 else {
            throw BridgeError.socketCreationFailed
        }
        descriptor = listener

        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            destination.initializeMemory(as: UInt8.self, repeating: 0)
            pathBytes.withUnsafeBytes { source in
                destination.copyBytes(from: source)
            }
        }

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(
                to: sockaddr.self,
                capacity: 1
            ) { socketAddress in
                Darwin.bind(
                    listener,
                    socketAddress,
                    socklen_t(MemoryLayout<sockaddr_un>.size)
                )
            }
        }
        guard bindResult == 0 else {
            Darwin.close(listener)
            descriptor = -1
            throw BridgeError.bindFailed
        }

        chmod(socketURL.path, S_IRUSR | S_IWUSR)
        guard Darwin.listen(listener, 16) == 0 else {
            Darwin.close(listener)
            descriptor = -1
            unlink(socketURL.path)
            throw BridgeError.listenFailed
        }

        let flags = fcntl(listener, F_GETFL)
        _ = fcntl(listener, F_SETFL, flags | O_NONBLOCK)

        let source = DispatchSource.makeReadSource(
            fileDescriptor: listener,
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.acceptAvailableConnections()
        }
        self.source = source
        source.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
        if descriptor >= 0 {
            Darwin.close(descriptor)
            descriptor = -1
        }
        unlink(socketURL.path)
        handler = nil
    }

    private func acceptAvailableConnections() {
        guard descriptor >= 0 else { return }
        while true {
            let connection = Darwin.accept(descriptor, nil, nil)
            guard connection >= 0 else { return }
            var noSigPipe: Int32 = 1
            setsockopt(
                connection,
                SOL_SOCKET,
                SO_NOSIGPIPE,
                &noSigPipe,
                socklen_t(MemoryLayout<Int32>.size)
            )
            read(connection: connection)
        }
    }

    private func read(connection: Int32) {
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(
            connection,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &timeout,
            socklen_t(MemoryLayout<timeval>.size)
        )
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8_192)

        while data.count <= 65_536 {
            let count = Darwin.recv(
                connection,
                &buffer,
                buffer.count,
                0
            )
            guard count > 0 else { break }
            data.append(buffer, count: count)

            if let envelope = try? JSONDecoder().decode(
                CodexActivityBridgeEnvelope.self,
                from: data
            ) {
                guard authenticationTokensMatch(
                    envelope.authenticationToken,
                    authenticationToken
                ),
                authenticationTokensMatch(
                    envelope.installationIdentifier,
                    installationIdentifier
                )
                else {
                    Darwin.close(connection)
                    return
                }
                guard let handler else {
                    sendAcknowledgement(
                        eventID: envelope.eventID,
                        accepted: false,
                        connection: connection
                    )
                    return
                }
                let delivery = CodexActivityDelivery(
                    eventID: envelope.eventID,
                    source: .liveSocket,
                    activity: envelope.activity
                )
                handler(delivery) { [weak self] accepted in
                    guard let self else {
                        Darwin.close(connection)
                        return
                    }
                    self.sendAcknowledgement(
                        eventID: envelope.eventID,
                        accepted: accepted,
                        connection: connection
                    )
                }
                return
            }
        }
        Darwin.close(connection)
    }

    private func sendAcknowledgement(
        eventID: String?,
        accepted: Bool,
        connection: Int32
    ) {
        defer { Darwin.close(connection) }
        guard let payload = try? JSONEncoder().encode(
            CodexActivityDeliveryAcknowledgement(
                eventID: eventID,
                accepted: accepted
            )
        ) else {
            return
        }
        _ = payload.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return false
            }
            var pointer = baseAddress
            var remaining = buffer.count
            while remaining > 0 {
                let written = Darwin.send(
                    connection,
                    pointer,
                    remaining,
                    0
                )
                guard written > 0 else { return false }
                pointer = pointer.advanced(by: written)
                remaining -= written
            }
            return true
        }
    }
}

final class CodexActivityFileBridge: @unchecked Sendable {
    enum BridgeError: LocalizedError {
        case queueCreationFailed
        case unsafeQueueDirectory
        case queueWatchFailed

        var errorDescription: String? {
            switch self {
            case .queueCreationFailed:
                "无法创建 Codex 灵动岛事件队列。"
            case .unsafeQueueDirectory:
                "Codex 灵动岛事件队列的权限不安全。"
            case .queueWatchFailed:
                "无法监听 Codex 灵动岛事件队列。"
            }
        }
    }

    private static let maximumPayloadBytes = 65_536
    private static let maximumQueuedFiles = 128
    private static let staleEventAge: TimeInterval = 300

    private let queueURL: URL
    private let authenticationToken: String
    private let installationIdentifier: String
    private let queue = DispatchQueue(
        label: "com.duoasa.QuotaView.codex-activity-file-bridge",
        qos: .utility
    )
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: Int32 = -1
    private var handler: CodexActivityDeliveryHandler?
    private var startupReplayFileNames: Set<String> = []
    private var inFlightFileNames: Set<String> = []

    init(
        queueURL: URL,
        authenticationToken: String,
        installationIdentifier: String
    ) {
        self.queueURL = queueURL
        self.authenticationToken = authenticationToken
        self.installationIdentifier = installationIdentifier
    }

    func start(
        handler: @escaping CodexActivityDeliveryHandler
    ) throws {
        stop()
        try prepareQueueDirectory()
        self.handler = handler
        startupReplayFileNames = Set(
            eventURLsInQueue().map(\.lastPathComponent)
        )

        let directoryDescriptor = Darwin.open(
            queueURL.path,
            O_EVTONLY | O_CLOEXEC
        )
        guard directoryDescriptor >= 0 else {
            self.handler = nil
            throw BridgeError.queueWatchFailed
        }
        descriptor = directoryDescriptor

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: directoryDescriptor,
            eventMask: [.write, .extend],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.drainAvailableEvents()
        }
        self.source = source
        source.resume()
        queue.async { [weak self] in
            self?.drainAvailableEvents()
        }
    }

    func stop() {
        source?.cancel()
        source = nil
        if descriptor >= 0 {
            Darwin.close(descriptor)
            descriptor = -1
        }
        handler = nil
        startupReplayFileNames.removeAll()
        inFlightFileNames.removeAll()
    }

    private func prepareQueueDirectory() throws {
        let path = queueURL.path
        var metadata = stat()
        if lstat(path, &metadata) == 0 {
            guard metadata.st_uid == getuid(),
                  metadata.st_mode & S_IFMT == S_IFDIR
            else {
                throw BridgeError.unsafeQueueDirectory
            }
        } else {
            guard mkdir(path, S_IRWXU) == 0 else {
                throw BridgeError.queueCreationFailed
            }
        }

        guard chmod(path, S_IRWXU) == 0,
              lstat(path, &metadata) == 0,
              metadata.st_uid == getuid(),
              metadata.st_mode & S_IFMT == S_IFDIR,
              metadata.st_mode & (S_IRWXG | S_IRWXO) == 0
        else {
            throw BridgeError.unsafeQueueDirectory
        }
    }

    private func drainAvailableEvents() {
        let eventURLs = eventURLsInQueue()
        var deliveries: [(
            url: URL,
            delivery: CodexActivityDelivery
        )] = []
        for url in eventURLs.prefix(Self.maximumQueuedFiles) {
            let fileName = url.lastPathComponent
            guard !inFlightFileNames.contains(fileName) else { continue }
            guard let data = readPayload(at: url),
                  let envelope = try? JSONDecoder().decode(
                      CodexActivityBridgeEnvelope.self,
                      from: data
                  ),
                  authenticationTokensMatch(
                      envelope.authenticationToken,
                      authenticationToken
                  ),
                  authenticationTokensMatch(
                      envelope.installationIdentifier,
                      installationIdentifier
                  ),
                  abs(envelope.activity.occurredAt.timeIntervalSinceNow)
                    <= Self.staleEventAge
            else {
                unlink(url.path)
                startupReplayFileNames.remove(fileName)
                continue
            }
            let source: CodexActivityDeliverySource =
                startupReplayFileNames.contains(fileName)
                ? .startupReplay
                : .liveQueue
            deliveries.append((
                url: url,
                delivery: CodexActivityDelivery(
                    eventID: envelope.eventID,
                    source: source,
                    activity: envelope.activity
                )
            ))
        }

        deliveries.sort {
            $0.delivery.activity.occurredAt
                < $1.delivery.activity.occurredAt
        }
        for item in deliveries {
            let fileName = item.url.lastPathComponent
            guard let handler else { return }
            inFlightFileNames.insert(fileName)
            handler(item.delivery) { [weak self] accepted in
                guard let self else { return }
                self.queue.async {
                    self.inFlightFileNames.remove(fileName)
                    guard accepted else { return }
                    unlink(item.url.path)
                    self.startupReplayFileNames.remove(fileName)
                    self.drainAvailableEvents()
                }
            }
        }
    }

    private func eventURLsInQueue() -> [URL] {
        let fileManager = FileManager.default
        guard let urls = try? fileManager.contentsOfDirectory(
            at: queueURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return urls
            .filter {
                $0.pathExtension == "json"
                    && $0.lastPathComponent.hasPrefix("event-")
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func readPayload(at url: URL) -> Data? {
        let fileDescriptor = Darwin.open(
            url.path,
            O_RDONLY | O_NOFOLLOW | O_CLOEXEC
        )
        guard fileDescriptor >= 0 else { return nil }
        defer { Darwin.close(fileDescriptor) }

        var metadata = stat()
        guard fstat(fileDescriptor, &metadata) == 0,
              metadata.st_uid == getuid(),
              metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_size > 0,
              metadata.st_size <= Self.maximumPayloadBytes
        else {
            return nil
        }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8_192)
        while data.count <= Self.maximumPayloadBytes {
            let count = Darwin.read(
                fileDescriptor,
                &buffer,
                min(
                    buffer.count,
                    Self.maximumPayloadBytes + 1 - data.count
                )
            )
            guard count >= 0 else { return nil }
            guard count > 0 else { return data }
            data.append(buffer, count: count)
        }
        return nil
    }
}

private func authenticationTokensMatch(
    _ received: String,
    _ expected: String
) -> Bool {
    let receivedBytes = Array(received.utf8)
    let expectedBytes = Array(expected.utf8)
    guard receivedBytes.count == expectedBytes.count else {
        return false
    }
    var difference: UInt8 = 0
    for index in receivedBytes.indices {
        difference |= receivedBytes[index] ^ expectedBytes[index]
    }
    return difference == 0
}

enum CodexActivityDiagnostics {
    private static let maximumLogBytes: off_t = 65_536

    static var logURL: URL {
        URL(
            fileURLWithPath:
                "/tmp/com.quotaview.codex-activity-\(getuid())",
            isDirectory: true
        )
        .appendingPathComponent("diagnostics.log")
    }

    static func record(
        delivery: CodexActivityDelivery,
        outcome: String
    ) {
        let path = logURL.path
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

        if metadata.st_size >= maximumLogBytes {
            guard ftruncate(descriptor, 0) == 0 else { return }
        }

        let activity = delivery.activity
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let session = String(activity.sessionHash.prefix(12))
        let turn = activity.turnHash.map { String($0.prefix(12)) } ?? "none"
        let eventID = delivery.eventID.map {
            String($0.prefix(12))
        } ?? "legacy"
        let activitySource = activity.source?.rawValue ?? "unknown"
        let planSource = activity.planSource?.rawValue ?? "none"
        let line = "\(timestamp) event=\(activity.event.rawValue) source=\(delivery.source.rawValue) activity_source=\(activitySource) plan_source=\(planSource) outcome=\(outcome) session=\(session) turn=\(turn) id=\(eventID)\n"
        _ = line.withCString { pointer in
            Darwin.write(descriptor, pointer, strlen(pointer))
        }
    }
}
