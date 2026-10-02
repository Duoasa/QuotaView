import Foundation
import XCTest
@testable import QuotaView
@testable import QuotaViewCore

final class HookBridgeReadinessTests: XCTestCase {
    private final class Probe: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        private var callback: (@Sendable (Bool) -> Void)?
        func received(_ completion: @escaping @Sendable (Bool) -> Void) -> Int {
            lock.lock(); defer { lock.unlock() }
            count += 1; callback = completion; return count
        }
        var receivedCount: Int { lock.lock(); defer { lock.unlock() }; return count }
        func complete(_ accepted: Bool) {
            lock.lock(); let completion = callback; callback = nil; lock.unlock()
            completion?(accepted)
        }
    }

    func testConfigurationReadyReplaysBufferedStartupWithoutNewFile() throws {
        let root = try queueRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let event = try writeEvent(root, id: "startup", installation: "selected")
        let bridge = makeBridge(root); defer { bridge.stop() }
        let probe = Probe(), received = expectation(description: "Ready explicitly drains startup queue")
        try bridge.start(handler: { delivery, completion in
            XCTAssertEqual(delivery.source, .startupReplay)
            XCTAssertEqual(delivery.eventID, "startup")
            _ = probe.received(completion); completion(true); received.fulfill()
        }, deliveryReady: false)
        // Drain barriers are explicit readiness changes; this does not rely on
        // a timer waking the bridge or on any further queue write.
        bridge.setDeliveryReady(false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: event.path))
        XCTAssertEqual(probe.receivedCount, 0)
        bridge.setDeliveryReady(true)
        wait(for: [received], timeout: 1)
        try waitForRemoval(event)
    }

    func testReadinessHandoffRetriesAnUnacceptedEventWithoutFilesystemChange() throws {
        let root = try queueRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let event = try writeEvent(root, id: "retry", installation: "selected")
        let bridge = makeBridge(root); defer { bridge.stop() }
        let probe = Probe()
        let first = expectation(description: "Consumer still preparing retains event")
        let second = expectation(description: "Settled consumer retries retained event")
        try bridge.start { _, completion in
            if probe.received(completion) == 1 { completion(false); first.fulfill() }
            else { completion(true); second.fulfill() }
        }
        wait(for: [first], timeout: 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: event.path))
        bridge.setDeliveryReady(true)
        wait(for: [second], timeout: 1)
        XCTAssertEqual(probe.receivedCount, 2)
        try waitForRemoval(event)
    }

    func testLateAcknowledgementFromStoppedRunCannotRemoveNewRunReplay() throws {
        let root = try queueRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let event = try writeEvent(root, id: "late", installation: "selected")
        let bridge = makeBridge(root); defer { bridge.stop() }
        let probe = Probe(), received = expectation(description: "Old run holds acknowledgement")
        try bridge.start { _, completion in _ = probe.received(completion); received.fulfill() }
        wait(for: [received], timeout: 1)
        bridge.stop()
        let replay = expectation(description: "New run owns replay")
        try bridge.start(handler: { delivery, completion in
            XCTAssertEqual(delivery.eventID, "late")
            XCTAssertEqual(delivery.source, .startupReplay)
            completion(true); replay.fulfill()
        }, deliveryReady: false)
        probe.complete(true)
        // stop/start and readiness commands share the receiver's serial queue.
        // A completion carrying the old generation is ignored there.
        bridge.setDeliveryReady(false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: event.path))
        bridge.setDeliveryReady(true)
        wait(for: [replay], timeout: 1)
        try waitForRemoval(event)
    }

    func testNewDirectoryInstallationNeverReceivesPreviousDirectoryQueue() throws {
        let root = try queueRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let stale = try writeEvent(root, id: "old-root", installation: "previous-directory")
        let current = try writeEvent(root, id: "new-root", installation: "selected")
        let bridge = makeBridge(root); defer { bridge.stop() }
        let received = expectation(description: "Only selected installation is admitted")
        received.assertForOverFulfill = true
        try bridge.start(handler: { delivery, completion in
            XCTAssertEqual(delivery.eventID, "new-root")
            completion(true); received.fulfill()
        }, deliveryReady: false)
        bridge.setDeliveryReady(true)
        wait(for: [received], timeout: 1)
        try waitForRemoval(current)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
    }

    private func queueRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("qv-ready-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        return root
    }
    private func makeBridge(_ queue: URL) -> CodexActivityFileBridge {
        CodexActivityFileBridge(queueURL: queue, authenticationToken: "isolated-token", installationIdentifier: "selected")
    }
    private func writeEvent(_ queue: URL, id: String, installation: String) throws -> URL {
        let url = queue.appendingPathComponent("event-\(id).json")
        let envelope = CodexActivityBridgeEnvelope(authenticationToken: "isolated-token",
            installationIdentifier: installation, eventID: id,
            activity: .init(event: .permissionRequest, sessionHash: "isolated-session", turnHash: "isolated-turn", source: .hook))
        try JSONEncoder().encode(envelope).write(to: url, options: .atomic)
        return url
    }
    private func waitForRemoval(_ url: URL) throws {
        let deadline = Date().addingTimeInterval(1)
        while FileManager.default.fileExists(atPath: url.path), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.005)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}
