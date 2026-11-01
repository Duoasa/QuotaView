import Darwin
import Foundation
import XCTest
@testable import QuotaView
@testable import QuotaViewCore
import QuotaViewActivityHookSupport

final class GrokBugFixSmokeTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = URL(fileURLWithPath: "/private/tmp/qv-fix-" + String(UUID().uuidString.prefix(8)))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let helper = root.appendingPathComponent("helper")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: helper)
        chmod(helper.path, 0o700)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }
    private func installer() -> NativeAgentInstaller {
        .init(provider: .kimiCode, socketURL: root.appendingPathComponent("events.sock"), authenticationToken: "fixture",
              homeOverride: root, supportOverride: root.appendingPathComponent("O'Brien 支持"), helperOverride: root.appendingPathComponent("helper"))
    }
    func testKimiEscapesAndPreservesArrayHooksOnRepeatedInstall() throws {
        let installer = installer(), config = root.appendingPathComponent("config.toml")
        let original = "model = 'fixture'\n[[hooks]]\nevent = 'Stop'\ncommand = 'foreign'\n"
        try Data(original.utf8).write(to: config)
        _ = try installer.configure(enabled: true)
        let installed = try String(contentsOf: config, encoding: .utf8)
        XCTAssertFalse(installed.contains(#"\/"#))
        XCTAssertTrue(installed.contains(installer.tomlString(installer.quote(installer.helper.path) + " --agent-hook --configuration " + installer.quote(installer.route.path))))
        XCTAssertEqual(installer.tomlString("/a\n\u{1}\u{7f}\"\\中"), #""/a\u000A\u0001\u007F\"\\中""#)
        _ = try installer.configure(enabled: true)
        XCTAssertEqual(try String(contentsOf: config, encoding: .utf8), installed)
        _ = try installer.configure(enabled: false)
        XCTAssertEqual(try String(contentsOf: config, encoding: .utf8), original)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: installer.route.path)[.posixPermissions] as? Int, 0o600)
    }
    func testKimiRejectsConflictingTablesWithoutChangingUserConfig() throws {
        let installer = installer(), config = root.appendingPathComponent("config.toml")
        for original in ["hooks = {}\n", "[hooks]\nx = 1\n", "[hooks.Stop]\nx = 1\n", "[ 'hooks' . Stop ]\nx = 1\n",
                         "hooks.Stop = {}\n", #"["\u0068ooks"]"# + "\nx = 1\n"] {
            try Data(original.utf8).write(to: config)
            XCTAssertThrowsError(try installer.configure(enabled: true), original)
            XCTAssertEqual(try String(contentsOf: config, encoding: .utf8), original)
        }
    }
    func testNativeInstallerLockHasAnAbsoluteDeadline() throws {
        let installer = installer()
        try FileManager.default.createDirectory(at: installer.support, withIntermediateDirectories: true)
        let fd = Darwin.open(installer.support.appendingPathComponent("install.lock").path, O_CREAT | O_RDWR, 0o600)
        XCTAssertGreaterThanOrEqual(fd, 0); defer { Darwin.close(fd) }
        XCTAssertEqual(flock(fd, LOCK_EX | LOCK_NB), 0)
        let start = ProcessInfo.processInfo.systemUptime
        XCTAssertThrowsError(try installer.configure(enabled: true))
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 3)
    }
    func testUsageRejectsOverflowInRecordAndAcrossRecords() async throws {
        XCTAssertNil(ClaudeCodeTokenUsage(usage: ["input_tokens": Int64.max, "output_tokens": 1]))
        XCTAssertNil(ClaudeCodeTokenUsage(usage: ["cache_creation": ["ephemeral_5m_input_tokens": -1]]))
        XCTAssertNil(ClaudeCodeTokenUsage(input: Int64.max) + ClaudeCodeTokenUsage(output: 1))
        XCTAssertNil(ClaudeCodeTokenUsage(input: -1).total)
        func record(_ id: String, _ usage: [String: Any]) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["type": "assistant", "timestamp": "2026-11-01T00:00:00Z",
                "message": ["id": id, "model": "claude-sonnet-5", "usage": usage]]) + Data([10])
        }
        try (record("a", ["input_tokens": Int64.max]) + record("b", ["output_tokens": 1])
            + record("c", ["input_tokens": Int64.max, "output_tokens": 1])).write(to: root.appendingPathComponent("usage.jsonl"))
        let scanner = ClaudeCodeUsageScanner(projectsURL: root)
        for _ in 0..<2 {
            let summary = await scanner.scan()
            XCTAssertFalse(summary.complete)
            XCTAssertEqual(summary.lifetimeTokens, Int64.max)
            XCTAssertNil(summary.days.first?.estimatedCost)
        }
    }
    func testClaudeInstallRoundTripsApostrophePathsAndRejectsUnsupportedStatusLine() throws {
        let installer = ClaudeCodeInstaller(socketURL: root.appendingPathComponent("events.sock"), authenticationToken: "fixture",
            configurationDirectory: root, supportDirectory: root.appendingPathComponent("O'Brien"), helperURL: root.appendingPathComponent("helper"), environment: [:])
        XCTAssertTrue(installer.owns(installer.hookCommand)); XCTAssertTrue(installer.ownsStatusLine(installer.statusLineCommand))
        XCTAssertFalse(installer.owns(installer.hookCommand + "\nrm x"))
        XCTAssertFalse(installer.owns(installer.hookCommand.replacingOccurrences(of: "--configuration", with: "$(echo --configuration)")))
        let original = Data(#"{"statusLine":"user-command"}"#.utf8)
        try original.write(to: installer.settingsURL)
        XCTAssertThrowsError(try installer.install(.init(interactiveApprovals: false, statusLine: true)))
        XCTAssertEqual(try Data(contentsOf: installer.settingsURL), original)
        try Data("{}".utf8).write(to: installer.settingsURL)
        for _ in 0..<2 { try installer.install(.init(interactiveApprovals: false, statusLine: true)) }
        XCTAssertTrue(installer.state().hooksInstalled)
        try installer.uninstall()
        XCTAssertFalse(installer.state().hasOwnedHooks)
    }
    func testApprovalIncludesAllGenericParametersAndRejectsAmbiguousOrOversizedInputs() throws {
        func request(_ input: [String: Any], tool: String = "WebFetch") throws -> IslandCodexApprovalRequest {
            try ClaudeCodeApproval.request(eventID: "fixture", sessionKey: "session", turnKey: "turn", toolName: tool,
                toolInput: input, toolUseID: "item", cwd: nil, hasSuggestions: false)
        }
        let wire = try request(["url": "https://example.test", "prompt": "extra instruction", "headers": ["X-Fixture": "value"]])
        XCTAssertTrue(wire.detail.contains("extra instruction")); XCTAssertTrue(wire.detail.contains("X-Fixture"))
        XCTAssertThrowsError(try request(["url": String(repeating: "x", count: 65_537)]))
        XCTAssertThrowsError(try request(["questions": [["question": "same"], ["question": "same"]]], tool: "AskUserQuestion"))
    }
    func testStatusLineDeadlineCoversClosedOutputAndDescendants() throws {
        XCTAssertEqual(BoundedStatusLineCommand.run(command: "cat", input: Data("fixture".utf8), timeoutSeconds: 1), Data("fixture".utf8))
        let start = ProcessInfo.processInfo.systemUptime
        XCTAssertNil(BoundedStatusLineCommand.run(command: "exec 1>&-; sleep 10", input: Data(), timeoutSeconds: 0.15))
        XCTAssertNil(BoundedStatusLineCommand.run(command: "sleep 10 & wait", input: Data(), timeoutSeconds: 0.15))
        XCTAssertNil(BoundedStatusLineCommand.run(command: "yes x", input: Data(), timeoutSeconds: 1, maximumOutputBytes: 1024))
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 1)
    }
    func testHookFirstPacketDeadlineCannotBeExtendedByDrippingBytes() throws {
        let socket = root.appendingPathComponent("bridge.sock")
        let bridge = ClaudeCodeBridge(socketURL: socket, authenticationToken: "fixture")
        try bridge.start(onMessage: { _ in XCTFail("Incomplete input cannot authenticate") }, onDisconnect: { _ in })
        defer { bridge.stop() }
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        defer { Darwin.close(fd) }
        var noSignal: Int32 = 1, timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: Array(socket.path.utf8) + [0]) }
        let connected = withUnsafePointer(to: &address) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        XCTAssertEqual(connected, 0)
        let group = DispatchGroup(), start = ProcessInfo.processInfo.systemUptime
        group.enter()
        DispatchQueue.global().async {
            defer { group.leave() }
            var byte: UInt8 = 32
            for _ in 0..<15 {
                if Darwin.send(fd, &byte, 1, 0) != 1 { break }
                usleep(100_000)
            }
        }
        var byte: UInt8 = 0
        XCTAssertLessThanOrEqual(Darwin.recv(fd, &byte, 1, 0), 0)
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 1.7)
        XCTAssertEqual(group.wait(timeout: .now() + 2), .success)
    }

    private func listener() throws -> (Int32, URL) {
        let path = root.appendingPathComponent("s.sock")
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes = Array(path.path.utf8) + [0]
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        let status = withUnsafePointer(to: &address) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard status == 0, Darwin.listen(fd, 8) == 0 else { Darwin.close(fd); throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        return (fd, path)
    }
    func testSharedHandshakeTimeoutAndCancellationCloseUnresponsiveConnections() async throws {
        let (fd, path) = try listener(); defer { Darwin.close(fd) }
        let started = ProcessInfo.processInfo.systemUptime
        XCTAssertThrowsError(try CodexSharedAppServerActivityClient.openSocket(path: path.path, maximumMessageBytes: 1024, deadline: started + 0.15))
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - started, 0.6)
        let task = Task.detached {
            try CodexSharedAppServerActivityClient.openSocket(path: path.path, maximumMessageBytes: 1024, deadline: ProcessInfo.processInfo.systemUptime + 5)
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        let cancelled = ProcessInfo.processInfo.systemUptime; task.cancel()
        do { let opened = try await task.value; Darwin.close(opened.fileDescriptor); XCTFail("cancelled handshake returned a socket") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - cancelled, 0.5)
    }
    func testSharedSocketRejectsWritableParent() throws {
        let (fd, path) = try listener(); defer { Darwin.close(fd) }
        chmod(root.path, 0o777)
        XCTAssertThrowsError(try CodexSharedAppServerActivityClient.openSocket(path: path.path, maximumMessageBytes: 1024, deadline: ProcessInfo.processInfo.systemUptime + 1))
    }
    func testStderrDiscardContinuesAfterAnOversizedSplitLine() async throws {
        actor Lines { var lines: [String] = []; func add(_ line: String) { lines.append(line) } }
        let lines = Lines()
        let stream = AsyncStream<Data> { c in
            c.yield(Data("ok\n".utf8)); c.yield(Data(repeating: 120, count: 20)); c.yield(Data(repeating: 120, count: 20))
            c.yield(Data("\nrecovered\nlast".utf8)); c.finish()
        }
        try await CodexAppServerClient.readLines(from: stream, maximumLineBytes: 16, discardOversizedLines: true) { await lines.add($0) }
        let result = await lines.lines; XCTAssertEqual(result, ["ok", "recovered", "last"])
    }
    @MainActor
    func testItemContextsAreBoundedClearedAndCannotApproveMissingDiff() throws {
        let store = IslandLiveStore()
        func receive(_ method: String, _ params: [String: Any], id: String? = nil) throws {
            var message: [String: Any] = ["method": method, "params": params]
            if let id { message["id"] = id }
            store.receive(try JSONSerialization.data(withJSONObject: message))
        }
        try receive("turn/started", ["threadId": "context-test", "turnId": "one"])
        for i in 0..<220 {
            try receive("item/started", ["threadId": "context-test", "turnId": "one", "item": ["id": "i-\(i)", "type": "fileChange", "changes": [["path": "fixture", "diff": String(repeating: "a", count: 12_000)]]]])
        }
        XCTAssertLessThanOrEqual(store.retainedItemContextCount, 200)
        XCTAssertLessThanOrEqual(store.retainedItemContextBytes, 2_097_152)
        try receive("turn/started", ["threadId": "context-test", "turnId": "two"])
        XCTAssertEqual(store.retainedItemContextCount, 0)
        try receive("item/started", ["threadId": "context-test", "turnId": "two", "item": ["id": "huge", "type": "fileChange", "changes": [["path": "fixture", "diff": String(repeating: "a", count: 33_000)]]]])
        try receive("item/fileChange/requestApproval", ["threadId": "context-test", "turnId": "two", "itemId": "huge", "availableDecisions": ["accept", "decline"]], id: "approval")
        let display = store.display(english: true, remaining: nil, enabled: true, privacy: false)
        let task = try XCTUnwrap(display.state.tasks.first)
        let confirmation = try XCTUnwrap(display.taskDetails[task.id]?.confirmation)
        XCTAssertTrue(confirmation.protocolRequest?.observationOnly == true)
        XCTAssertFalse(confirmation.canRespond)
        try receive("thread/closed", ["threadId": "context-test"])
        XCTAssertEqual(store.retainedItemContextCount, 0)
    }
}
