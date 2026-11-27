import Darwin
import Foundation
import XCTest
import os
@testable import QuotaView
@testable import QuotaViewCore

final class CodexActivityBridgeLifecycleTests: XCTestCase {
    private let token = "isolated-token"
    private let installation = "isolated-installation"

    func testStoppingReplacedUnixListenerPreservesNewEndpointAndAcknowledgements() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let socket = root.appendingPathComponent("events.sock")
        let old = CodexActivityUnixBridge(socketURL: socket, authenticationToken: token, installationIdentifier: installation)
        let current = CodexActivityUnixBridge(socketURL: socket, authenticationToken: token, installationIdentifier: installation)
        defer { old.stop(); current.stop() }

        try old.start { delivery, ack in
            XCTAssertEqual(delivery.source, .liveSocket)
            XCTAssertEqual(delivery.eventID, "old")
            ack(true)
        }
        try assertAccepted("old", at: socket)
        let oldFD = try XCTUnwrap(try listenerDescriptors(at: socket).first)
        try current.start { delivery, ack in
            XCTAssertEqual(delivery.source, .liveSocket)
            XCTAssertEqual(delivery.eventID, "current")
            ack(true)
        }
        old.stop()
        try assertAccepted("current", at: socket)
        try eventually { try !self.listenerDescriptors(at: socket).contains(oldFD) }
        current.stop()
        XCTAssertFalse(FileManager.default.fileExists(atPath: socket.path))
        try eventually { try self.listenerDescriptors(at: socket).isEmpty }
    }

    func testFileWatcherClosesQueueDescriptorAndReplaysAfterOldAcknowledgement() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("event-held.json")
        try envelope("held").write(to: file, options: .atomic)
        let bridge = CodexActivityFileBridge(queueURL: root, authenticationToken: token, installationIdentifier: installation)
        defer { bridge.stop() }

        var directory = stat()
        XCTAssertEqual(lstat(root.path, &directory), 0)
        let ackSlot = OSAllocatedUnfairLock<(@Sendable (Bool) -> Void)?>(initialState: nil)
        let buffered = expectation(description: "First run has the queued event")
        try bridge.start { delivery, ack in
            XCTAssertEqual(delivery.eventID, "held")
            ackSlot.withLock { $0 = ack }
            buffered.fulfill()
        }
        wait(for: [buffered], timeout: 3)
        let oldAck = try XCTUnwrap(ackSlot.withLock { $0 })
        XCTAssertFalse(try openDescriptors(for: directory).isEmpty)
        bridge.stop()
        try eventually { try self.openDescriptors(for: directory).isEmpty }

        let replay = expectation(description: "Current run accepts the replay")
        try bridge.start(handler: { delivery, ack in
            XCTAssertEqual(delivery.eventID, "held")
            XCTAssertEqual(delivery.source, .startupReplay)
            ack(true)
            replay.fulfill()
        }, deliveryReady: false)
        XCTAssertFalse(try openDescriptors(for: directory).isEmpty)
        oldAck(true)
        bridge.setDeliveryReady(true)
        wait(for: [replay], timeout: 3)
        try eventually { !FileManager.default.fileExists(atPath: file.path) }
        bridge.stop()
        try eventually { try self.openDescriptors(for: directory).isEmpty }
    }

    func testUnixListenerCanStopWithAnAcceptedDeliveryAwaitingAcknowledgement() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let socket = root.appendingPathComponent("pending.sock")
        let bridge = CodexActivityUnixBridge(socketURL: socket, authenticationToken: token, installationIdentifier: installation)
        defer { bridge.stop() }

        let accepted = expectation(description: "Receiver has the event and retains its reply")
        let answered = expectation(description: "Original client receives the held acknowledgement")
        let ackSlot = OSAllocatedUnfairLock<(@Sendable (Bool) -> Void)?>(initialState: nil)
        try bridge.start { delivery, ack in
            XCTAssertEqual(delivery.eventID, "pending")
            ackSlot.withLock { $0 = ack }
            bridge.stop()
            // Cancellation cannot release the source's fd before this handler returns.
            XCTAssertEqual(try? self.listenerDescriptors(at: socket).count, 1)
            accepted.fulfill()
        }
        let fds = try listenerDescriptors(at: socket)
        XCTAssertEqual(fds.count, 1)
        DispatchQueue.global().async {
            defer { answered.fulfill() }
            do { try self.assertAccepted("pending", at: socket) }
            catch { XCTFail("Waiting client failed: \(error)") }
        }
        wait(for: [accepted], timeout: 3)
        let ack = try XCTUnwrap(ackSlot.withLock { $0 })
        bridge.stop()
        XCTAssertFalse(FileManager.default.fileExists(atPath: socket.path))
        try eventually { try self.listenerDescriptors(at: socket).isEmpty }
        ack(true)
        wait(for: [answered], timeout: 3)
    }

    func testFileDeliveryCanRestartWithoutAdmittingTheRestOfItsOldBatch() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let events = try ["one", "two"].map { id in
            let url = root.appendingPathComponent("event-\(id).json")
            try envelope(id).write(to: url, options: .atomic)
            return url
        }
        let bridge = CodexActivityFileBridge(queueURL: root, authenticationToken: token, installationIdentifier: installation)
        defer { bridge.stop() }
        let restarted = expectation(description: "Current callback synchronously restarted the bridge")
        let replayed = expectation(description: "Both retained files replay after readiness")
        replayed.expectedFulfillmentCount = events.count
        let ids = OSAllocatedUnfairLock(initialState: Set<String>())
        try bridge.start { _, oldAck in
            bridge.stop()
            do {
                try bridge.start(handler: { delivery, ack in
                    XCTAssertEqual(delivery.source, .startupReplay)
                    ids.withLock { _ = $0.insert(delivery.eventID ?? "") }
                    ack(true)
                    replayed.fulfill()
                }, deliveryReady: false)
            } catch {
                XCTFail("Could not restart queue on its delivery callback: \(error)")
            }
            oldAck(true)
            restarted.fulfill()
        }
        wait(for: [restarted], timeout: 3)
        bridge.setDeliveryReady(true)
        wait(for: [replayed], timeout: 3)
        XCTAssertEqual(ids.withLock { $0 }, ["one", "two"])
        try eventually { events.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) } }
    }

    private func makeRoot() throws -> URL {
        let root = URL(fileURLWithPath: "/tmp/qv-bridge-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        return root
    }

    private func envelope(_ id: String) throws -> Data {
        try JSONEncoder().encode(CodexActivityBridgeEnvelope(authenticationToken: token,
            installationIdentifier: installation, eventID: id, activity: .init(event: .stop, sessionHash: "fixture-session")))
    }

    private func assertAccepted(_ eventID: String, at url: URL) throws {
        struct Ack: Decodable { let eventID: String; let accepted: Bool }
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw failure() }
        let client = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        defer { Darwin.close(fd) }
        var timeout = timeval(tv_sec: 8, tv_usec: 0)
        var noSigPipe: Int32 = 1
        guard setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout))) == 0,
              setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout.size(ofValue: noSigPipe))) == 0
        else { throw failure() }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let path = Array(url.path.utf8CString)
        guard path.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw POSIXError(.ENAMETOOLONG) }
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            path.withUnsafeBytes { destination.copyBytes(from: $0) }
        }
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { throw failure() }
        try client.write(contentsOf: envelope(eventID))
        let response = try XCTUnwrap(try client.readToEnd())
        let ack = try JSONDecoder().decode(Ack.self, from: response)
        XCTAssertEqual(ack.eventID, eventID)
        XCTAssertTrue(ack.accepted)
    }

    private func failure() -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }

    private func listenerDescriptors(at socket: URL) throws -> [Int32] {
        try FileManager.default.contentsOfDirectory(atPath: "/dev/fd").compactMap(Int32.init).filter { fd in
            var peer = sockaddr()
            var length = socklen_t(MemoryLayout<sockaddr>.size)
            guard getpeername(fd, &peer, &length) == -1, errno == ENOTCONN else { return false }
            var address = sockaddr_un()
            length = socklen_t(MemoryLayout<sockaddr_un>.size)
            let result = withUnsafeMutablePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
            }
            guard result == 0, address.sun_family == sa_family_t(AF_UNIX) else { return false }
            let path = withUnsafeBytes(of: address.sun_path) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            return path == socket.path
        }
    }

    private func openDescriptors(for directory: stat) throws -> [Int32] {
        try FileManager.default.contentsOfDirectory(atPath: "/dev/fd").compactMap(Int32.init).filter { fd in
            var metadata = stat()
            return fstat(fd, &metadata) == 0 && metadata.st_dev == directory.st_dev && metadata.st_ino == directory.st_ino
        }
    }

    private func eventually(file: StaticString = #filePath, line: UInt = #line, _ condition: () throws -> Bool) throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        while try !condition() {
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                XCTFail("Bridge cleanup did not complete", file: file, line: line)
                return
            }
            Thread.sleep(forTimeInterval: 0.005)
        }
    }
}
