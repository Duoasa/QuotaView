import Darwin
import Foundation
import XCTest
import QuotaViewCore
import QuotaViewActivityHookSupport
@testable import QuotaView

final class DevinIntegrationSmokeTests: XCTestCase {
    private func directory() throws -> URL {
        let root = URL(fileURLWithPath: "/private/tmp/qv-devin-" + UUID().uuidString.prefix(8))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func installer(_ provider: IslandAgentProvider, _ root: URL, helper: URL = URL(fileURLWithPath: "/usr/bin/true")) -> NativeAgentInstaller {
        NativeAgentInstaller(provider: provider, socketURL: root.appendingPathComponent(provider.rawValue + ".sock"), authenticationToken: "fixture",
            homeOverride: root, supportOverride: root.appendingPathComponent(provider.rawValue), helperOverride: helper)
    }
    func testDocumentedEventsFilterPrivatePayloadAndKeepPromptIdentity() throws {
        for provider in ["devinDesktop", "devinCLI"] {
            for (event, expected) in [("UserPromptSubmit", "UserPromptSubmit"), ("PreToolUse", "PreToolUse"), ("PostToolUse", "PostToolUseFailure"),
                                      ("PermissionRequest", "PermissionRequest"), ("Stop", "Stop"), ("PostCompaction", "PostCompact"), ("SessionEnd", "SessionEnd")] {
                let payload: [String: Any] = ["session_id": "shared", "prompt_id": "turn", "tool_name": "exec", "prompt": "PRIVATE",
                    "tool_input": ["command": "PRIVATE"], "tool_response": ["success": false, "output": "PRIVATE"], "summary": "PRIVATE", "cwd": "PRIVATE"]
                let normalized = try XCTUnwrap(NativeAgentHookNormalizer.normalize(payload, provider: provider, event: event))
                XCTAssertEqual(normalized["hook_event_name"] as? String, expected)
                XCTAssertEqual(normalized["turn_id"] as? String, "turn")
                XCTAssertFalse(String(decoding: try JSONSerialization.data(withJSONObject: normalized), as: UTF8.self).contains("PRIVATE"))
                XCTAssertNil(NativeAgentHookNormalizer.neutralOutput(provider: provider, event: event))
            }
            XCTAssertNil(NativeAgentHookNormalizer.normalize(["session_id": "shared"], provider: provider, event: "SubagentStop"))
        }
    }
    func testSourceSelectionAndInheritedClaudeHook() {
        XCTAssertEqual(DevinHookSource.provider(ancestorPaths: ["/bin/sh", "/usr/local/bin/devin", "/bin/zsh", "/Applications/Terminal.app/Contents/MacOS/Terminal"], complete: true), "devinCLI")
        XCTAssertEqual(DevinHookSource.provider(ancestorPaths: ["/bin/sh", "/Applications/Devin.app/Contents/Resources/app/bin/devin", "/Applications/Devin.app/Contents/Frameworks/Devin Helper.app/Contents/MacOS/Devin Helper"], complete: true), "devinDesktop")
        XCTAssertEqual(DevinHookSource.provider(ancestorPaths: ["/bin/sh", "/usr/local/bin/devin", "/bin/zsh", "/Applications/Devin.app/Contents/MacOS/Devin"], complete: true), "devinCLI")
        XCTAssertNil(DevinHookSource.provider(ancestorPaths: ["/bin/sh"], complete: false))
        XCTAssertTrue(DevinHookSource.isInheritedClaudeHook(["session_id": "s"], environment: ["DEVIN_PROJECT_DIR": "/fixture"]))
        XCTAssertFalse(DevinHookSource.isInheritedClaudeHook(["transcript_path": "/fixture/claude"], environment: ["DEVIN_PROJECT_DIR": "/fixture"]))
        XCTAssertFalse(DevinHookSource.isInheritedClaudeHook([:], environment: [:]))
    }
    func testSharedJSONCPreservesCommentsForeignHooksAndIndependentDisable() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("config.json")
        let foreign = #"{"matcher":"exec", /* foreign hook */ "hooks":[{"type":"command","command":"echo https://example.test/a//b"}]}"#
        let original = "{\n// user settings\n\"version\": 42, \"theme\": \"深色\",\n\"hooks\": {\"PreToolUse\": [" + foreign + "]} /* keep me */\n}"
        try Data(original.utf8).write(to: file)
        let desktop = installer(.devinDesktop, root), cli = installer(.devinCLI, root)
        _ = try desktop.configure(enabled: true); _ = try cli.configure(enabled: true)
        let both = try Data(contentsOf: file)
        _ = try desktop.configure(enabled: true); _ = try cli.configure(enabled: true)
        XCTAssertEqual(try Data(contentsOf: file), both)
        _ = try desktop.configure(enabled: false)
        var text = try String(contentsOf: file, encoding: .utf8)
        XCTAssertFalse(text.contains(desktop.route.path)); XCTAssertTrue(text.contains(cli.route.path))
        _ = try cli.configure(enabled: false)
        text = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(text.contains(foreign)); XCTAssertTrue(text.contains("// user settings")); XCTAssertTrue(text.contains("/* keep me */"))
        XCTAssertTrue(text.contains("\"version\": 42")); XCTAssertTrue(text.contains("深色")); XCTAssertFalse(text.contains("--agent-hook"))
        let disabled = try Data(contentsOf: file)
        _ = try desktop.configure(enabled: false); XCTAssertEqual(try Data(contentsOf: file), disabled)
    }
    func testDisableRemovesOnlyOwnedChildrenInsideMixedHookArrays() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("config.json"), item = installer(.devinCLI, root)
        _ = try item.configure(enabled: true)
        let config = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        let hooks = try XCTUnwrap(config["hooks"] as? [String: [[String: Any]]])
        let child = try XCTUnwrap((hooks["Stop"]?.first?["hooks"] as? [[String: Any]])?.first)
        let own = String(decoding: try JSONSerialization.data(withJSONObject: child, options: .withoutEscapingSlashes), as: UTF8.self)
        let foreign = #"{"type":"command", /* keep child */ "command":"echo foreign"}"#
        for items in [[own, foreign], [foreign, own], [foreign, own, foreign]] {
            let original = "{\"hooks\":{\"Stop\":[{\"hooks\":[" + items.joined(separator: ", /* between */ ") + "]}]}}"
            try Data(original.utf8).write(to: file)
            _ = try item.configure(enabled: false)
            let result = try String(contentsOf: file, encoding: .utf8)
            XCTAssertEqual(result.components(separatedBy: foreign).count, original.components(separatedBy: foreign).count)
            XCTAssertTrue(result.contains("/* between */")); XCTAssertFalse(result.contains(item.route.path))
            _ = try item.configure(enabled: true) // The preserved JSONC remains installable.
        }
    }
    func testMalformedAndDuplicateJSONCKeysAreNotOverwritten() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("config.json"), item = installer(.devinCLI, root)
        for value in ["{/* incomplete", "{\"hooks\":42}", "{\"hooks\":{},\"hooks\":{}}", "{\"hooks\":{\"Stop\":[{\"hooks\":false}]}}"] {
            let bytes = Data(value.utf8); try bytes.write(to: file)
            XCTAssertThrowsError(try item.configure(enabled: true)); XCTAssertEqual(try Data(contentsOf: file), bytes)
            XCTAssertFalse(FileManager.default.fileExists(atPath: item.route.path))
        }
    }
    func testConcurrentInstallationRetainsBothSurfaces() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let desktop = installer(.devinDesktop, root), cli = installer(.devinCLI, root)
        async let first = Task.detached { try desktop.configure(enabled: true) }.value
        async let second = Task.detached { try cli.configure(enabled: true) }.value
        _ = try await (first, second)
        let text = try String(contentsOf: root.appendingPathComponent("config.json"), encoding: .utf8)
        XCTAssertTrue(text.contains(desktop.route.path)); XCTAssertTrue(text.contains(cli.route.path))
    }
    private static func send(_ payload: [String: Any], socket path: String) throws {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(fd, 0); guard fd >= 0 else { return }
        defer { Darwin.close(fd) }
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { target in
            target.copyBytes(from: Array(path.utf8CString).map { UInt8(bitPattern: $0) })
        }
        let connected = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        XCTAssertEqual(connected, 0); guard connected == 0 else { return }
        let eventID = UUID().uuidString
        var line = try JSONSerialization.data(withJSONObject: ["authenticationToken": "fixture", "eventID": eventID, "kind": "hook", "awaitDecision": false, "payload": payload])
        line.append(10)
        let count = line.withUnsafeBytes { Darwin.send(fd, $0.baseAddress, $0.count, 0) }
        XCTAssertEqual(count, line.count)
        var buffer = [UInt8](repeating: 0, count: 4096)
        let received = Darwin.recv(fd, &buffer, buffer.count, 0)
        XCTAssertGreaterThan(received, 0); guard received > 0 else { return }
        let ack = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(buffer.prefix(received))) as? [String: Any])
        XCTAssertEqual(ack["eventID"] as? String, eventID); XCTAssertEqual(ack["accepted"] as? Bool, true)
    }
    @MainActor
    private func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<200 { if condition() { return }; try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertTrue(condition())
    }
    @MainActor
    func testCLIHookAndDesktopIPCStaySeparateAndDisableIndependently() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let helper = URL(fileURLWithPath: ProcessInfo.processInfo.environment["QV_NATIVE_HELPER"] ?? FileManager.default.currentDirectoryPath + "/.build/debug/QuotaViewActivityHook")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: helper.path))
        let suite = "QuotaView.DevinSmoke." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults), island = IslandSession(); defer { island.stop() }
        XCTAssertFalse(preferences.devinDesktopEnabled); XCTAssertFalse(preferences.devinCLIEnabled)
        preferences.devinDesktopEnabled = true; preferences.devinCLIEnabled = true
        let desktop = NativeAgentRuntime(provider: .devinDesktop, preferences: preferences, island: island, defaults: defaults, installer: installer(.devinDesktop, root, helper: helper))
        let cli = NativeAgentRuntime(provider: .devinCLI, preferences: preferences, island: island, defaults: defaults, installer: installer(.devinCLI, root, helper: helper))
        defer { desktop.stop(); cli.stop() }
        desktop.start(); cli.start(); try await waitFor { desktop.status == .waiting && cli.status == .waiting }
        let config = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("config.json"))) as? [String: Any])
        let hooks = try XCTUnwrap(config["hooks"] as? [String: [[String: Any]]])
        func fire(_ event: String, desktop: Bool, turn: String = "turn") async throws {
            let payload: [String: Any] = ["hook_event_name": event, "session_id": "same-session", "prompt_id": turn, "tool_name": "exec", "tool_response": ["success": true]]
            if desktop {
                let normalized = try XCTUnwrap(NativeAgentHookNormalizer.normalize(payload, provider: "devinDesktop", event: event))
                let socket = root.appendingPathComponent("devinDesktop.sock").path
                try await Task.detached { try Self.send(normalized, socket: socket) }.value
                return
            }
            // Run both installed commands from the CLI. Only CLI may forward.
            for entry in try XCTUnwrap(hooks[event]) {
                let command = try XCTUnwrap((entry["hooks"] as? [[String: Any]])?.first?["command"] as? String)
                let process = Process(), input = Pipe(), output = Pipe()
                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                process.arguments = ["-c", command + "; :"]
                process.standardInput = input; process.standardOutput = output; process.standardError = output
                input.fileHandleForWriting.write(try JSONSerialization.data(withJSONObject: payload)); try input.fileHandleForWriting.close()
                let status: Int32 = try await withCheckedThrowingContinuation { continuation in
                    process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
                    do { try process.run() } catch { continuation.resume(throwing: error) }
                }
                XCTAssertEqual(status, 0); XCTAssertTrue(output.fileHandleForReading.readDataToEndOfFile().isEmpty)
            }
        }
        for provider in [IslandAgentProvider.devinDesktop, .devinCLI] {
            let isDesktop = provider == .devinDesktop, key = CodexActivityPrivacy.hashIdentifier(provider.rawValue + ":same-session")
            try await fire("UserPromptSubmit", desktop: isDesktop)
            try await waitFor { island.model.tasks.contains { $0.key == key && !$0.terminal } }
            XCTAssertEqual(island.model.provider(for: key), provider)
            try await fire("PermissionRequest", desktop: isDesktop)
            try await waitFor { island.model.tasks.contains { $0.key == key && $0.status == .waiting } }
            try await fire("PostToolUse", desktop: isDesktop)
            try await waitFor { island.model.tasks.contains { $0.key == key && $0.status != .waiting } }
            try await fire("Stop", desktop: isDesktop)
            try await waitFor { island.model.tasks.contains { $0.key == key && $0.status == .completed } }
            try await fire("UserPromptSubmit", desktop: isDesktop, turn: "next")
            try await fire("Stop", desktop: isDesktop) // Previous turn cannot finish the next one.
            XCTAssertTrue(island.model.tasks.contains { $0.key == key && !$0.terminal })
        }
        XCTAssertEqual(island.model.tasks.count, 2)
        preferences.devinDesktopEnabled = false
        try await waitFor { desktop.status == .disabled }
        XCTAssertEqual(island.model.tasks.count, 1); XCTAssertEqual(cli.status, .connected)
        XCTAssertEqual(island.model.provider(for: try XCTUnwrap(island.model.tasks.first).key), .devinCLI)
    }
}
