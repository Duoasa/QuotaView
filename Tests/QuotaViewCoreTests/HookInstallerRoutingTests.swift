import CryptoKit
import Darwin
import Foundation
import XCTest
@testable import QuotaView
@testable import QuotaViewCore

final class HookInstallerRoutingTests: XCTestCase {
    func testAutomaticRepairKeepsDefinitionAndOtherChannelsStable() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundled = try makeHelper(at: root.appendingPathComponent("Bundle/QuotaViewActivityHook"))
        let hooks = root.appendingPathComponent("Codex/hooks.json")
        let stable = makeInstaller(root: root, hooks: hooks, bundled: bundled, channel: "stable")
        let development = makeInstaller(root: root, hooks: hooks, bundled: bundled, channel: "development")
        XCTAssertTrue(try stable.install().hookDefinitionChanged)
        XCTAssertTrue(try development.install().hookDefinitionChanged)
        let installed = try Data(contentsOf: hooks)
        let route = try Data(contentsOf: development.configurationURL)
        let repaired = try development.install()
        XCTAssertFalse(repaired.hookDefinitionChanged)
        XCTAssertFalse(repaired.helperRepaired)
        XCTAssertFalse(repaired.routeRepaired)
        XCTAssertEqual(try Data(contentsOf: hooks), installed)
        XCTAssertEqual(try Data(contentsOf: development.configurationURL), route)
        XCTAssertTrue(try stable.isInstalled())
        XCTAssertTrue(try development.isInstalled())

        // Binary and route refresh must not change the definition Codex trusted.
        try Data("#!/bin/sh\n# updated build\nexit 0\n".utf8).write(to: bundled)
        let changedRoute = CodexActivityHookInstaller(socketURL: development.socketURL,
            authenticationToken: "rotated-token", queueURL: root.appendingPathComponent("new-queue"),
            hooksURL: hooks, helperURL: bundled, installedHelperURL: development.installedHelperURL,
            configurationURL: development.configurationURL, channelIdentifier: "development")
        let refresh = try changedRoute.install()
        XCTAssertFalse(refresh.hookDefinitionChanged)
        XCTAssertTrue(refresh.helperRepaired)
        XCTAssertTrue(refresh.routeRepaired)
        XCTAssertEqual(changedRoute.installationIdentifier, development.installationIdentifier)
        XCTAssertEqual(try Data(contentsOf: hooks), installed)
        XCTAssertFalse(String(decoding: installed, as: UTF8.self).contains("rotated-token"))
        let configuration = try readObject(changedRoute.configurationURL)
        XCTAssertEqual(configuration["queuePath"] as? String, root.appendingPathComponent("new-queue").path)
        XCTAssertEqual(configuration["authenticationToken"] as? String, "rotated-token")
        XCTAssertEqual(try permissions(changedRoute.configurationURL), 0o600)

        try changedRoute.uninstall()
        XCTAssertTrue(try stable.isInstalled())
        XCTAssertFalse(try changedRoute.hasQuotaViewHandlers())
        XCTAssertTrue(FileManager.default.fileExists(atPath: stable.configurationURL.path))
    }

    func testMissingHelperIsRepairedWithoutRewritingHooks() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundled = try makeHelper(at: root.appendingPathComponent("Bundle/QuotaViewActivityHook"))
        let installer = makeInstaller(root: root, hooks: root.appendingPathComponent("hooks.json"),
                                      bundled: bundled, channel: "development")
        _ = try installer.install()
        let hooks = try Data(contentsOf: installer.hooksURL)
        try FileManager.default.removeItem(at: installer.installedHelperURL)
        XCTAssertFalse(try installer.isInstalled())
        let repaired = try installer.install()
        XCTAssertTrue(repaired.helperRepaired)
        XCTAssertFalse(repaired.hookDefinitionChanged)
        XCTAssertEqual(try Data(contentsOf: installer.hooksURL), hooks)
        XCTAssertTrue(try installer.isInstalled())
    }

    func testLegacyMigrationOwnsOnlyExactSocketAndToken() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundled = try makeHelper(at: root.appendingPathComponent("Bundle/QuotaViewActivityHook"))
        let installer = makeInstaller(root: root, hooks: root.appendingPathComponent("hooks.json"),
                                      bundled: bundled, channel: "development")
        let legacy = "'/old/QuotaViewActivityHook' --socket '\(installer.socketURL.path)' --token 'development-token' --installation-id 'legacy-id'"
        let other = "'/old/QuotaViewActivityHook' --socket '/stable.sock' --token 'stable-token' --installation-id 'stable-id'"
        let untouched = "echo QuotaViewActivityHook"
        try writeObject(["description": "Keep this", "future-setting": ["enabled": true],
            "hooks": ["PostToolUse": [["matcher": "Bash", "extra": "keep", "hooks": [
                ["type": "command", "command": legacy], ["type": "command", "command": other],
                ["type": "command", "command": untouched]]]], "Stop": [["hooks": []]]]], to: installer.hooksURL)
        let before = try Data(contentsOf: installer.hooksURL)
        _ = try installer.install()
        let object = try readObject(installer.hooksURL)
        XCTAssertEqual(object["description"] as? String, "Keep this")
        XCTAssertNotNil(object["future-setting"])
        let installedCommands = commands(in: object)
        XCTAssertFalse(installedCommands.contains(legacy))
        XCTAssertTrue(installedCommands.contains(other))
        XCTAssertTrue(installedCommands.contains(untouched))
        XCTAssertEqual(try Data(contentsOf: installer.hooksURL.appendingPathExtension("quotaview-backup")), before)
        try installer.uninstall()
        let remaining = commands(in: try readObject(installer.hooksURL))
        XCTAssertTrue(remaining.contains(other))
        XCTAssertTrue(remaining.contains(untouched))
        XCTAssertFalse(remaining.contains(installer.hookCommand))
    }

    func testInvalidExistingHooksDoNotPartiallyInstall() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundled = try makeHelper(at: root.appendingPathComponent("Bundle/QuotaViewActivityHook"))
        let installer = makeInstaller(root: root, hooks: root.appendingPathComponent("hooks.json"),
                                      bundled: bundled, channel: "development")
        let original = Data(#"{"hooks":{"Stop":"not-an-array"},"other":"preserve"}"#.utf8)
        try original.write(to: installer.hooksURL)
        XCTAssertThrowsError(try installer.install())
        XCTAssertEqual(try Data(contentsOf: installer.hooksURL), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: installer.installedHelperURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: installer.configurationURL.path))
    }

    func testInspectorTargetsSelectedRootAndHonorsExplicitDisable() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let selected = root.appendingPathComponent("selected-home")
        try FileManager.default.createDirectory(at: selected, withIntermediateDirectories: true)
        try Data("[features]\nhooks = false # deliberate opt-out\n".utf8)
            .write(to: selected.appendingPathComponent("config.toml"))
        let executable = try makeHelper(at: root.appendingPathComponent("codex"), script: """
        #!/bin/sh
        if [ "$1" = "--version" ]; then echo "codex-cli fixture"; exit 0; fi
        if [ "$1" = "features" ] && [ "$2" = "list" ]; then
          printf '%s' "$CODEX_HOME" > '\(root.appendingPathComponent("selected-root.txt").path)'
          echo 'hooks stable false'; exit 0
        fi
        if [ "$1" = "features" ] && [ "$2" = "enable" ]; then
          touch '\(root.appendingPathComponent("unexpected-enable").path)'; exit 0
        fi
        exit 1
        """)
        let inspector = CodexActivityEnvironmentInspector(executablePath: executable.path, timeout: 2,
            dataDirectoryURL: selected, environment: ["PATH": "/usr/bin:/bin", "CODEX_HOME": "/ignored"])
        XCTAssertFalse(try inspector.inspect().hooksEnabled)
        XCTAssertThrowsError(try inspector.inspectAndEnableHooksIfNeeded(preference: .disabled)) { error in
            XCTAssertTrue(error is CodexActivityEnvironmentInspector.InspectionError)
        }
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("selected-root.txt"), encoding: .utf8),
                       selected.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("unexpected-enable").path))
    }

    func testInspectorEnablesLegacyFeatureByItsReportedName() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let marker = root.appendingPathComponent("enabled")
        let executable = try makeHelper(at: root.appendingPathComponent("codex"), script: """
        #!/bin/sh
        if [ "$1" = "--version" ]; then echo "codex-cli legacy-fixture"; exit 0; fi
        if [ "$1" = "features" ] && [ "$2" = "list" ]; then
          if [ -f '\(marker.path)' ]; then echo 'codex_hooks experimental true';
          else echo 'codex_hooks experimental false'; fi
          exit 0
        fi
        if [ "$1" = "features" ] && [ "$2" = "enable" ] && [ "$3" = "codex_hooks" ]; then
          touch '\(marker.path)'; exit 0
        fi
        exit 1
        """)
        let result = try CodexActivityEnvironmentInspector(executablePath: executable.path, timeout: 2,
            dataDirectoryURL: root, environment: ["PATH": "/usr/bin:/bin"]).inspectAndEnableHooksIfNeeded(preference: .absent)
        XCTAssertTrue(result.hooksEnabled)
        XCTAssertTrue(result.didEnableHooks)
        XCTAssertEqual(result.hooksFeatureName, "codex_hooks")
    }

    func testHelperFallbackUsesProtectedConfiguredQueueAndToolCorrelation() throws {
        let helper = try actualBuiltHelper()
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let queue = root.appendingPathComponent("development-queue")
        try FileManager.default.createDirectory(at: queue, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let installer = CodexActivityHookInstaller(socketURL: root.appendingPathComponent("absent.sock"),
            authenticationToken: "isolated-token", queueURL: queue, hooksURL: root.appendingPathComponent("hooks.json"),
            helperURL: helper, installedHelperURL: root.appendingPathComponent("Helper/QuotaViewActivityHook"),
            channelIdentifier: "development")
        _ = try installer.install()
        let input: [String: Any] = ["hook_event_name": "PermissionRequest", "session_id": "fixture-session",
            "turn_id": "fixture-turn", "tool_use_id": "fixture-tool-call", "tool_name": "exec_command",
            "tool_input": ["cmd": "PRIVATE INPUT MUST NOT LEAVE THE HELPER"]]
        let output = try runHelper(helper, configuration: installer.configurationURL, input: input)
        XCTAssertTrue(output.isEmpty, "An observer must not alter Codex's Hook response")
        let events = try FileManager.default.contentsOfDirectory(at: queue, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("event-") && $0.pathExtension == "json" }
        let envelope = try readObject(try XCTUnwrap(events.first))
        XCTAssertEqual(envelope["authenticationToken"] as? String, "isolated-token")
        XCTAssertEqual(envelope["installationIdentifier"] as? String, installer.installationIdentifier)
        let activity = try XCTUnwrap(envelope["activity"] as? [String: Any])
        let digest = SHA256.hash(data: Data("fixture-tool-call".utf8)).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(activity["toolCallHash"] as? String, digest)
        XCTAssertFalse(String(decoding: try Data(contentsOf: events[0]), as: UTF8.self).contains("PRIVATE INPUT"))
    }

    func testHelperRejectsReadableOrSymlinkedRouteConfiguration() throws {
        let helper = try actualBuiltHelper()
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let queue = root.appendingPathComponent("queue")
        try FileManager.default.createDirectory(at: queue, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let route = root.appendingPathComponent("route.json")
        try writeObject(["version": 1, "socketPath": root.appendingPathComponent("absent.sock").path,
            "queuePath": queue.path, "authenticationToken": "isolated", "installationIdentifier": "fixture"], to: route)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: route.path)
        let input: [String: Any] = ["hook_event_name": "Stop", "session_id": "fixture-session"]
        XCTAssertTrue(try runHelper(helper, configuration: route, input: input).isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: queue.path), [])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: route.path)
        let link = root.appendingPathComponent("route-link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: route)
        XCTAssertTrue(try runHelper(helper, configuration: link, input: input).isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: queue.path), [])
    }

    func testConcurrentForeignEditRejectsStaleHooksWrite() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundled = try makeHelper(at: root.appendingPathComponent("Bundle/QuotaViewActivityHook"))
        let installer = makeInstaller(root: root, hooks: root.appendingPathComponent("hooks.json"),
                                      bundled: bundled, channel: "development")
        try writeObject(["hooks": [:]], to: installer.hooksURL)
        let sourceRevision = try Data(contentsOf: installer.hooksURL)
        try writeObject(["description": "Another application just added this", "hooks": ["Stop": [["hooks": [
            ["type": "command", "command": "/another-app/observer"]]]]]], to: installer.hooksURL)
        let foreignRevision = try Data(contentsOf: installer.hooksURL)
        XCTAssertThrowsError(try installer.writeRoot(["hooks": [:]], expectedRevision: sourceRevision)) { error in
            guard case CodexActivityHookInstaller.InstallationError.hooksFileChanged = error else {
                return XCTFail("A changed source must fail with a configuration conflict")
            }
        }
        XCTAssertEqual(try Data(contentsOf: installer.hooksURL), foreignRevision)
        XCTAssertFalse(FileManager.default.fileExists(atPath:
            installer.hooksURL.appendingPathExtension("quotaview-backup").path))
        _ = try installer.install()
        XCTAssertTrue(commands(in: try readObject(installer.hooksURL)).contains("/another-app/observer"))
    }

    func testInspectorTerminatesIgnoredSIGTERMWithinBound() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = try makeHelper(at: root.appendingPathComponent("codex"), script: """
        #!/bin/sh
        trap '' TERM
        exec /bin/sleep 10
        """)
        let inspector = CodexActivityEnvironmentInspector(executablePath: executable.path, timeout: 1,
            dataDirectoryURL: root, environment: ["PATH": "/usr/bin:/bin"])
        let started = Date()
        XCTAssertThrowsError(try inspector.inspect()) { error in
            guard case CodexActivityEnvironmentInspector.InspectionError.commandTimedOut = error else {
                return XCTFail("A hung executable must report a bounded timeout")
            }
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
    }

    func testInspectorDoesNotWaitForInheritedDescendantPipe() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let childPID = root.appendingPathComponent("child-pid")
        defer {
            if let text = try? String(contentsOf: childPID, encoding: .utf8),
               let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                _ = kill(pid, SIGTERM)
            }
        }
        let executable = try makeHelper(at: root.appendingPathComponent("codex"), script: """
        #!/bin/sh
        if [ "$1" = "--version" ]; then
          /bin/sleep 10 &
          echo "$!" > '\(childPID.path)'
          echo 'codex-cli inherited-pipe-fixture'
          exit 0
        fi
        echo 'hooks stable true'
        """)
        let started = Date()
        let result = try CodexActivityEnvironmentInspector(executablePath: executable.path, timeout: 1,
            dataDirectoryURL: root, environment: ["PATH": "/usr/bin:/bin"]).inspect()
        XCTAssertTrue(result.hooksEnabled)
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
    }

    func testInspectorRejectsUnboundedOutputWithoutPipeDeadlock() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = try makeHelper(at: root.appendingPathComponent("codex"), script: """
        #!/bin/sh
        exec /usr/bin/yes oversized-output
        """)
        let started = Date()
        XCTAssertThrowsError(try CodexActivityEnvironmentInspector(executablePath: executable.path, timeout: 2,
            dataDirectoryURL: root, environment: ["PATH": "/usr/bin:/bin"]).inspect()) { error in
            XCTAssertTrue(error.localizedDescription.contains("64 KiB"))
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
    }

    func testInstallerLockContentionIsBoundedAndPreservesFile() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundled = try makeHelper(at: root.appendingPathComponent("Bundle/QuotaViewActivityHook"))
        let installer = makeInstaller(root: root, hooks: root.appendingPathComponent("hooks.json"),
                                      bundled: bundled, channel: "development")
        try writeObject(["hooks": [:]], to: installer.hooksURL)
        let revision = try Data(contentsOf: installer.hooksURL)
        let descriptor = open(root.appendingPathComponent(".quotaview-hooks.lock").path,
                              O_RDWR | O_CREAT | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { _ = flock(descriptor, LOCK_UN); close(descriptor) }
        XCTAssertEqual(flock(descriptor, LOCK_EX | LOCK_NB), 0)
        let started = Date()
        XCTAssertThrowsError(try installer.install())
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
        XCTAssertEqual(try Data(contentsOf: installer.hooksURL), revision)
        XCTAssertFalse(FileManager.default.fileExists(atPath: installer.configurationURL.path))
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("QuotaViewHookRouting-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeHelper(at url: URL, script: String = "#!/bin/sh\nexit 0\n") throws -> URL {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(script.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    private func makeInstaller(root: URL, hooks: URL, bundled: URL, channel: String) -> CodexActivityHookInstaller {
        CodexActivityHookInstaller(socketURL: root.appendingPathComponent("\(channel).sock"),
            authenticationToken: "\(channel)-token", queueURL: root.appendingPathComponent("\(channel)-queue"),
            hooksURL: hooks, helperURL: bundled,
            installedHelperURL: root.appendingPathComponent("\(channel)/QuotaViewActivityHook"),
            channelIdentifier: channel)
    }

    private func writeObject(_ object: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: url)
    }

    private func readObject(_ url: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func commands(in root: [String: Any]) -> [String] {
        (root["hooks"] as? [String: Any] ?? [:]).values.flatMap { value in
            (value as? [[String: Any]] ?? []).flatMap { group in
                (group["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String }
            }
        }
    }

    private func permissions(_ url: URL) throws -> Int {
        (try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue ?? 0
    }

    private func actualBuiltHelper() throws -> URL {
        let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let url = packageRoot.appendingPathComponent(".build/debug/QuotaViewActivityHook")
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw XCTSkip("The isolated helper integration fixture requires the built SwiftPM helper.")
        }
        return url
    }

    private func runHelper(_ helper: URL, configuration: URL, input: [String: Any]) throws -> Data {
        let process = Process(), stdin = Pipe(), stdout = Pipe()
        process.executableURL = helper
        process.arguments = ["--configuration", configuration.path]
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = Pipe()
        try process.run()
        try stdin.fileHandleForWriting.write(contentsOf: JSONSerialization.data(withJSONObject: input))
        try stdin.fileHandleForWriting.close()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return stdout.fileHandleForReading.readDataToEndOfFile()
    }
}
