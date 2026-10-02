import Darwin
import Foundation
import XCTest
@testable import QuotaViewCore

final class CodexDesktopSocketSmokeTests: XCTestCase {
    func testStockClientDrainsOversizedBurstThenSubmitsHealthyNativeQuestion() async throws {
        var question = CodexDesktopIPCClientTests.request(id: "question")
        question["method"] = "item/tool/requestUserInput"
        question["params"] = ["threadId": "conversation", "turnId": "turn", "questions": [
            ["id": "answer", "header": "Fixture", "question": "Fixture question", "isOther": true,
             "options": [["label": "A", "description": "Fixture choice"]]]]]
        let state = CodexDesktopIPCClientTests.data(CodexDesktopIPCClientTests.state(requests: [question]))
        let big = CodexDesktopIPCClientTests.data(["type": "broadcast", "method": "thread-stream-state-changed",
            "sourceClientId": "unix-fixture-owner", "targetClientIds": ["unix-fixture-client"], "version": 11,
            "params": ["conversationId": "oversized", "hostId": "local", "change": ["type": "snapshot", "revision": 1,
                "conversationState": ["body": String(repeating: "x", count: 9_437_184 + 65_536)]]]])
        let peer = try CodexDesktopUnixPeerFixture(state: state, firstSnapshotPayload: big)
        defer { peer.stop() }
        let client = CodexDesktopIPCClient(configuration: .init(socketURL: peer.socketURL, requestTimeoutSeconds: 1))
        let recorder = CodexDesktopIPCSnapshotRecorder()
        await client.start(snapshotHandler: { await recorder.record($0) }, stateHandler: { await recorder.recordState($0) },
            invalidationHandler: { await recorder.recordInvalidation($0) })
        do {
            try await recorder.waitForConnection()
            try await client.follow(conversationID: "oversized")
            let invalidation = try await recorder.waitForInvalidation(after: 0)
            XCTAssertEqual(invalidation.conversationID, "oversized")
            let connected = await recorder.isConnected
            XCTAssertTrue(connected, "Burst must backpressure instead of overflowing the chunk queue")
            try await client.follow(conversationID: "conversation")
            let snapshot = try await recorder.wait(after: 0)
            let handle = try XCTUnwrap(snapshot.requests.first)
            XCTAssertEqual(handle.method, "item/tool/requestUserInput")
            _ = try await client.submit(handle: handle, result: CodexDesktopIPCClientTests.data(["answers": ["answer": ["answers": ["A"]]]]))
            XCTAssertEqual(peer.submissions.count, 1)
            XCTAssertEqual(peer.requestMethods.filter { $0 == "initialize" }.count, 1)
            await client.stop()
        } catch { await client.stop(); throw error }
    }

    func testStockClientConsumesShortNativeFramesWhileUnixPeerRemainsOpen() async throws {
        let state = CodexDesktopIPCClientTests.data(CodexDesktopIPCClientTests.state(requests: [], items: [[
            "id": "message", "type": "agentMessage", "questions": [["title": "Fixture question", "options": ["A", "B"]]]]]))
        let peer = try CodexDesktopUnixPeerFixture(state: state)
        defer { peer.stop() }
        let client = CodexDesktopIPCClient(configuration: .init(socketURL: peer.socketURL, requestTimeoutSeconds: 1))
        let recorder = CodexDesktopIPCSnapshotRecorder()
        await client.start(snapshotHandler: { await recorder.record($0) }, stateHandler: { await recorder.recordState($0) })
        do {
            try await recorder.waitForConnection()
            try await client.follow(conversationID: "conversation")
            let snapshot = try await recorder.wait(after: 0)
            XCTAssertTrue(snapshot.supportsUntrustedAppInput)
            XCTAssertEqual(snapshot.requests.count, 1)
            XCTAssertEqual(snapshot.requests.first?.kind, .asynchronousQuestion)
            XCTAssertTrue(peer.wasPeerOpenWhenSnapshotSent,
                "A short response must be processed without waiting for peer EOF or 64KB")
            XCTAssertEqual(peer.requestMethods, ["initialize", "thread-owner-discovery"])
            XCTAssertTrue(peer.submissions.isEmpty)
            await client.stop()
        } catch {
            await client.stop()
            throw error
        }
    }
}

/// Exercises the production Darwin AF_UNIX transport, with no connector or
/// AsyncStream injection. All payloads are isolated fixture data; its short
/// replies are sent on a connection that remains open for the next request.
final class CodexDesktopUnixPeerFixture: @unchecked Sendable {
    let socketURL: URL
    private let directory: URL
    private let listener: Int32
    private let state: [String: Any]
    private var firstSnapshotPayload: Data?
    private let lock = NSLock()
    private var peer: Int32? = nil
    private var stopped = false
    private var methods: [String] = []
    private var sentSnapshotWhileOpen = false
    private var submitted: [[String: Any]] = []
    private var worker: Task<Void, Never>?

    var requestMethods: [String] { lock.withLock { methods } }
    var wasPeerOpenWhenSnapshotSent: Bool { lock.withLock { sentSnapshotWhileOpen } }
    var submissions: [[String: Any]] { lock.withLock { submitted } }

    init(state: Data, firstSnapshotPayload: Data? = nil) throws {
        self.firstSnapshotPayload = firstSnapshotPayload
        self.state = try XCTUnwrap(JSONSerialization.jsonObject(with: state) as? [String: Any])
        directory = URL(fileURLWithPath: "/private/tmp/qv-unix-" + String(UUID().uuidString.prefix(12)), isDirectory: true)
        socketURL = directory.appendingPathComponent("i.sock")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw CodexDesktopIPCError.unavailable }
        listener = fd
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes = Array(socketURL.path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            Darwin.close(fd); throw CodexDesktopIPCError.unavailable
        }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, Darwin.listen(fd, 1) == 0 else {
            Darwin.close(fd); throw CodexDesktopIPCError.unavailable
        }
        guard Darwin.chmod(socketURL.path, 0o600) == 0 else {
            Darwin.close(fd); throw CodexDesktopIPCError.unavailable
        }
        worker = Task.detached(priority: .utility) { [self] in serve() }
    }

    func stop() {
        let closeListener: Bool = lock.withLock {
            guard !stopped else { return false }
            stopped = true
            // Wake a pending recv; the worker owns closing its accepted fd.
            // Holding the lock prevents racing with its final fd release.
            if let peer { Darwin.shutdown(peer, SHUT_RDWR) }
            return true
        }
        if closeListener {
            Darwin.shutdown(listener, SHUT_RDWR)
            Darwin.close(listener)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func serve() {
        var accepted: Int32
        repeat { accepted = Darwin.accept(listener, nil, nil) } while accepted < 0 && errno == EINTR
        guard accepted >= 0 else { return }
        let admitted = lock.withLock { () -> Bool in
            guard !stopped else { return false }
            peer = accepted; return true
        }
        guard admitted else { Darwin.close(accepted); return }
        defer {
            lock.withLock { peer = nil; Darwin.close(accepted) }
        }
        var noSignal: Int32 = 1
        setsockopt(accepted, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        do {
            while !lock.withLock({ stopped }) {
                let header = try readExact(accepted, count: 4)
                let size = header.enumerated().reduce(UInt32(0)) { $0 | (UInt32($1.element) << UInt32($1.offset * 8)) }
                guard size > 0, size <= 1_048_576 else { throw CodexDesktopIPCError.invalidMessage }
                let message = try XCTUnwrap(JSONSerialization.jsonObject(with: readExact(accepted, count: Int(size))) as? [String: Any])
                let method = message["method"] as? String ?? ""
                if message["type"] as? String == "request", let id = message["requestId"] as? String {
                    lock.withLock { methods.append(method) }
                    switch method {
                    case "initialize":
                        try respond(accepted, id: id, method: method, owner: "unix-fixture-client", result: ["clientId": "unix-fixture-client"])
                    case "thread-owner-discovery":
                        try respond(accepted, id: id, method: method, owner: "unix-fixture-owner", result: ["supportsUntrustedAppInput": true])
                    case "thread-follower-submit-user-input":
                        lock.withLock { submitted.append(message) }
                        try respond(accepted, id: id, method: method, owner: "unix-fixture-owner", result: ["ok": true])
                    default: throw CodexDesktopIPCError.invalidMessage
                    }
                } else if method == "thread-stream-following-changed",
                          let params = message["params"] as? [String: Any], params["following"] as? Bool == true {
                    lock.withLock { sentSnapshotWhileOpen = !stopped }
                    if let firstSnapshotPayload {
                        self.firstSnapshotPayload = nil
                        try sendPayload(accepted, firstSnapshotPayload)
                        continue
                    }
                    try send(accepted, ["type": "broadcast", "method": "thread-stream-state-changed",
                        "sourceClientId": "unix-fixture-owner", "version": 11,
                        "params": ["conversationId": params["conversationId"] ?? "conversation", "hostId": "local",
                            "change": ["type": "snapshot", "revision": 1, "conversationState": state]]])
                }
            }
        } catch { /* EOF/fixture teardown ends this one native peer. */ }
    }

    private func readExact(_ fd: Int32, count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count), offset = 0
        while offset < count {
            let received = bytes.withUnsafeMutableBytes {
                Darwin.recv(fd, $0.baseAddress?.advanced(by: offset), count - offset, 0)
            }
            if received < 0, errno == EINTR { continue }
            guard received > 0 else { throw CodexDesktopIPCError.unavailable }
            offset += received
        }
        return Data(bytes)
    }
    private func respond(_ fd: Int32, id: String, method: String, owner: String, result: [String: Any]) throws {
        try send(fd, ["type": "response", "requestId": id, "resultType": "success", "method": method,
            "handledByClientId": owner, "result": result])
    }
    private func send(_ fd: Int32, _ object: [String: Any]) throws {
        let payload = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try sendPayload(fd, payload)
    }
    private func sendPayload(_ fd: Int32, _ payload: Data) throws {
        let frame = try CodexDesktopIPCFrameDecoder.frame(payload, maximumFrameBytes: max(1_048_576, payload.count))
        var offset = 0
        while offset < frame.count {
            let sent = frame.withUnsafeBytes {
                Darwin.send(fd, $0.baseAddress?.advanced(by: offset), frame.count - offset, 0)
            }
            if sent < 0, errno == EINTR { continue }
            guard sent > 0 else { throw CodexDesktopIPCError.unavailable }
            offset += sent
        }
    }
}
