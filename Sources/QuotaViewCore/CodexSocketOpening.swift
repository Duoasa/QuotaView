import Darwin
import Foundation

/// Owns even an unfinished upgrade. Cancel shuts down immediately; only the
/// worker closes/releases the fd, preventing reuse during its next poll/read.
final class CodexSocketOpening: @unchecked Sendable {
    let descriptor: Int32
    private let deadline: UInt64
    private let lock = NSLock()
    private var cancelled = false
    private var released = false
    private let didClose: (@Sendable (Int32) -> Void)?
    init(deadline: UInt64, didClose: (@Sendable (Int32) -> Void)? = nil) throws {
        self.deadline = deadline
        self.didClose = didClose
        descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw CodexSharedAppServerActivityClient.ClientError.connectionClosed }
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
            Darwin.close(descriptor); throw CodexSharedAppServerActivityClient.ClientError.connectionClosed
        }
        var noSignal: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
    }
    static func deadline(after seconds: TimeInterval) -> UInt64 {
        DispatchTime.now().uptimeNanoseconds &+ UInt64(max(0, seconds) * 1_000_000_000)
    }
    func perform<T>(_ body: (Int32) throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled, !released else { throw CancellationError() }
        guard DispatchTime.now().uptimeNanoseconds < deadline else {
            throw CodexSharedAppServerActivityClient.ClientError.requestTimedOut("socket/upgrade")
        }
        return try body(descriptor)
    }
    func wait(for events: Int16) throws {
        while true {
            // Poll is bounded to a small slice, outside the fd lock. cancel
            // retains fd ownership and shutdown wakes this exact descriptor.
            try perform { _ in () }
            if try Self.poll(descriptor, events: events, deadline: deadline) { return }
        }
    }
    private static func poll(_ fd: Int32, events: Int16, deadline: UInt64) throws -> Bool {
        let now = DispatchTime.now().uptimeNanoseconds
        guard now < deadline else { throw CodexSharedAppServerActivityClient.ClientError.requestTimedOut("socket/upgrade") }
        let milliseconds = Int32(min(50, max(1, (deadline - now + 999_999) / 1_000_000)))
        var value = pollfd(fd: fd, events: events, revents: 0)
        let result = Darwin.poll(&value, 1, milliseconds)
        if result < 0, errno == EINTR { return false }
        guard result >= 0, value.revents & Int16(POLLNVAL) == 0 else {
            throw CodexSharedAppServerActivityClient.ClientError.connectionClosed
        }
        return result > 0
    }
    func write(_ data: Data) throws {
        var offset = 0
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            while offset < bytes.count {
                let count = try perform { Darwin.write($0, base.advanced(by: offset), bytes.count - offset) }
                if count < 0, errno == EINTR { continue }
                if count < 0, errno == EAGAIN || errno == EWOULDBLOCK { try wait(for: Int16(POLLOUT)); continue }
                guard count > 0 else { throw CodexSharedAppServerActivityClient.ClientError.connectionClosed }
                offset += count
            }
        }
    }
    static func write(_ data: Data, to fd: Int32, deadline: UInt64) throws {
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                guard DispatchTime.now().uptimeNanoseconds < deadline else {
                    throw CodexSharedAppServerActivityClient.ClientError.requestTimedOut("socket/write")
                }
                let count = Darwin.write(fd, base.advanced(by: offset), bytes.count - offset)
                if count < 0, errno == EINTR { continue }
                if count < 0, errno == EAGAIN || errno == EWOULDBLOCK {
                    _ = try poll(fd, events: Int16(POLLOUT), deadline: deadline); continue
                }
                guard count > 0 else { throw CodexSharedAppServerActivityClient.ClientError.connectionClosed }
                offset += count
            }
        }
    }
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        guard !released, !cancelled else { return }
        cancelled = true; _ = Darwin.shutdown(descriptor, SHUT_RDWR)
    }
    func transfer() throws {
        try perform { _ in released = true }
    }
    func finish() {
        lock.lock()
        guard !released else { lock.unlock(); return }
        released = true
        let result = Darwin.close(descriptor)
        lock.unlock()
        // Report this owner's actual close after releasing the fd lock. A
        // transferred descriptor is closed by its connected reader instead.
        didClose?(result)
    }
    deinit { finish() }

    struct PathIdentity: Equatable { let device: dev_t; let inode: ino_t }
    static func pathIdentity(_ path: String) throws -> PathIdentity {
        var value = stat()
        guard lstat(path, &value) == 0 else { throw CodexSharedAppServerActivityClient.ClientError.connectionClosed }
        return .init(device: value.st_dev, inode: value.st_ino)
    }
    static func verifyPath(_ path: String, expectedUID: uid_t = getuid()) throws {
        var socket = stat()
        guard lstat(path, &socket) == 0, socket.st_mode & S_IFMT == S_IFSOCK,
              socket.st_uid == expectedUID else { throw CodexSharedAppServerActivityClient.ClientError.invalidHandshake }
        var directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        var isParent = true
        while true {
            var value = stat()
            guard lstat(directory.path, &value) == 0, value.st_mode & S_IFMT == S_IFDIR,
                  value.st_uid == expectedUID || (!isParent && value.st_uid == 0),
                  value.st_mode & 0o022 == 0 || (!isParent && value.st_uid == 0 && value.st_mode & S_ISVTX != 0)
            else { throw CodexSharedAppServerActivityClient.ClientError.invalidHandshake }
            if directory.path == "/" { break }
            isParent = false; directory.deleteLastPathComponent()
        }
    }
}
