import Darwin
import Foundation

/// One acknowledged, fixed-size read at a time. Kernel pipe/socket buffers
/// provide backpressure; control messages are never discarded to make room.
final class CodexBoundedInputReader: @unchecked Sendable {
    static let maximumChunkBytes = 65_536
    let chunks: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation
    private let handle: FileHandle
    private let isSocket: Bool
    private let lock = NSLock()
    private let readPermit = DispatchSemaphore(value: 1)
    private var closed = false
    private var queuedBytes = 0
    private var highWaterBytes = 0
    private var receivedBytes = 0

    struct Metrics: Equatable {
        let queuedBytes: Int
        let highWaterBytes: Int
        let receivedBytes: Int
    }
    var metrics: Metrics {
        lock.lock(); defer { lock.unlock() }
        return .init(queuedBytes: queuedBytes, highWaterBytes: highWaterBytes, receivedBytes: receivedBytes)
    }

    init(handle: FileHandle, isSocket: Bool = false) {
        self.handle = handle; self.isSocket = isSocket
        let pair = AsyncStream<Data>.makeStream(bufferingPolicy: .bufferingOldest(1))
        chunks = pair.stream; continuation = pair.continuation
        let flags = fcntl(handle.fileDescriptor, F_GETFL)
        guard flags >= 0, fcntl(handle.fileDescriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
            closed = true; try? handle.close(); continuation.finish(); return
        }
        handle.readabilityHandler = { [weak self] _ in
            guard let self else { return }
            self.readPermit.wait()
            switch self.readAvailable() {
            case .data(let data):
                switch self.continuation.yield(data) {
                case .enqueued: break
                // A violated producer contract closes the channel, never drops
                // one message and continues with a deceptively healthy stream.
                case .dropped, .terminated: self.close()
                @unknown default: self.close()
                }
            case .retry: self.readPermit.signal()
            case .closed: self.close()
            }
        }
        continuation.onTermination = { [weak self] _ in self?.close() }
    }
    func acknowledgeRead() {
        lock.lock(); queuedBytes = 0; lock.unlock()
        readPermit.signal()
    }
    private enum ReadResult { case data(Data), retry, closed }
    private func readAvailable() -> ReadResult {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return .closed }
        var bytes = [UInt8](repeating: 0, count: Self.maximumChunkBytes)
        while true {
            let count = bytes.withUnsafeMutableBytes { Darwin.read(handle.fileDescriptor, $0.baseAddress, $0.count) }
            if count > 0 {
                queuedBytes = count; highWaterBytes = max(highWaterBytes, count); receivedBytes += count
                return .data(Data(bytes.prefix(count)))
            }
            if count == 0 { return .closed }
            if errno == EINTR { continue }
            if errno == EAGAIN || errno == EWOULDBLOCK { return .retry }
            return .closed
        }
    }
    func writeSocket(_ data: Data, deadline: UInt64) throws {
        lock.lock(); defer { lock.unlock() }
        guard isSocket, !closed else { throw CodexSharedAppServerActivityClient.ClientError.connectionClosed }
        try CodexSocketOpening.write(data, to: handle.fileDescriptor, deadline: deadline)
    }
    func close() {
        lock.lock()
        guard !closed else { lock.unlock(); return }
        closed = true; queuedBytes = 0
        if isSocket { _ = Darwin.shutdown(handle.fileDescriptor, SHUT_RDWR) }
        lock.unlock()
        readPermit.signal()
        handle.readabilityHandler = nil
        try? handle.close()
        continuation.finish()
    }
    deinit { close() }
}
