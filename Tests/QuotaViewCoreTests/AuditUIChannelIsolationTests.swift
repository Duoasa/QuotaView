import Darwin
import Foundation
import XCTest
@testable import QuotaView
@testable import QuotaViewCore

final class AuditUIChannelIsolationTests: XCTestCase {
    private func root() throws -> URL {
        let url = URL(fileURLWithPath: "/private/tmp/qv-aud18-" + UUID().uuidString.prefix(12))
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    func testStableDevelopmentNilAndThirdIdentityUseIndependentWritableChannels() throws {
        let ids = ["com.quotaview", "com.quotaview.development073", nil, "com.fixture.other-development"]
            .map { CodexActivityChannelIdentity(bundleIdentifier: $0) }
        XCTAssertEqual(Set(ids.map(\.identifier)).count, 4)
        XCTAssertEqual(Set(ids.map(\.supportDirectory)).count, 4)
        XCTAssertEqual(ids.map(\.permitsAutomaticHook), [true, true, false, false])
        XCTAssertEqual(CodexActivityDiagnostics.logURL.deletingLastPathComponent().lastPathComponent,
            "\(CodexActivityChannelIdentity.current.identifier).codex-activity-\(getuid())",
            "Diagnostics are writable channel data and must use the same isolated identity")
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let bridges = ids.enumerated().map { offset, _ in
            CodexActivityUnixBridge(socketURL: root.appendingPathComponent("\(offset).sock"),
                authenticationToken: "isolated-\(offset)", installationIdentifier: "fixture")
        }
        defer { bridges.forEach { $0.stop() } }
        for bridge in bridges { try bridge.start { _, reply in reply(false) } }
        for offset in ids.indices { XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("\(offset).sock").path)) }
    }
    func testSecondInstanceCannotStealSocketAndFirstStopPreservesReplacementInode() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("owner.sock")
        let a = CodexActivityUnixBridge(socketURL: url, authenticationToken: "a", installationIdentifier: "fixture")
        let b = CodexActivityUnixBridge(socketURL: url, authenticationToken: "b", installationIdentifier: "fixture")
        defer { a.stop(); b.stop() }
        try a.start { _, reply in reply(false) }
        var before = stat(); XCTAssertEqual(lstat(url.path, &before), 0)
        XCTAssertThrowsError(try b.start { _, reply in reply(false) })
        b.stop()
        var current = stat(); XCTAssertEqual(lstat(url.path, &current), 0)
        XCTAssertEqual(current.st_ino, before.st_ino)
        XCTAssertEqual(unlink(url.path), 0)
        let foreign = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(foreign, 0); defer { Darwin.close(foreign) }
        var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes = Array(url.path.utf8CString)
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            destination.initializeMemory(as: UInt8.self, repeating: 0)
            bytes.withUnsafeBytes { destination.copyBytes(from: $0) }
        }
        let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.bind(foreign, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        } }
        XCTAssertEqual(bound, 0)
        var replacement = stat(); XCTAssertEqual(lstat(url.path, &replacement), 0)
        a.stop()
        var retained = stat(); XCTAssertEqual(lstat(url.path, &retained), 0)
        XCTAssertEqual(retained.st_ino, replacement.st_ino)
    }
    func testDifferentTokenQueuedEventsAreNotDrainedByAnotherInstance() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        func write(_ id: String, token: String) throws -> URL {
            let url = root.appendingPathComponent("event-\(id).json")
            let envelope = CodexActivityBridgeEnvelope(authenticationToken: token, installationIdentifier: "fixture",
                eventID: id, activity: .init(event: .preToolUse, sessionHash: "fixture", occurredAt: Date()))
            try JSONEncoder().encode(envelope).write(to: url)
            return url
        }
        let foreign = try write("foreign", token: "b")
        _ = try write("own", token: "a")
        let bridge = CodexActivityFileBridge(queueURL: root, authenticationToken: "a", installationIdentifier: "fixture")
        defer { bridge.stop() }
        let delivered = expectation(description: "Own delivery is queue barrier")
        try bridge.start { value, reply in
            XCTAssertEqual(value.eventID, "own")
            XCTAssertTrue(FileManager.default.fileExists(atPath: foreign.path))
            reply(true); delivered.fulfill()
        }
        wait(for: [delivered], timeout: 2)
        bridge.stop()
        XCTAssertTrue(FileManager.default.fileExists(atPath: foreign.path))
    }
}
