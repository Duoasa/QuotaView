import Foundation
import XCTest
@testable import QuotaViewCore

final class NativeHookConfigurationTests: XCTestCase {
    private let command = "'/private/tmp/QuotaViewActivityHook' --configuration '/private/tmp/quotaview-route.json'"
    private let events: Set<String> = ["SessionStart", "Stop"]

    func testNativeAuthorizationChangesOnlyExactOwnedDefinitions() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let client = fixture.client()
        defer { Task { await client.stop() } }
        let before = try await client.inspectOwnedHooks(
            sourceURL: fixture.source, command: command,
            expectedEvents: events, cwds: [fixture.root]
        )
        XCTAssertTrue(before.isComplete)
        XCTAssertTrue(before.isEnabled)
        XCTAssertFalse(before.isTrusted)
        XCTAssertEqual(before.untrustedCount, 2)
        let after = try await client.authorizeOwnedHooks(
            sourceURL: fixture.source, command: command,
            expectedEvents: events, cwds: [fixture.root]
        )
        await client.stop()
        XCTAssertTrue(after.isTrusted)
        XCTAssertEqual(after.trustedHashes.count, 2)
        let writes = try fixture.writes()
        XCTAssertEqual(writes.count, 1)
        let params = try XCTUnwrap(writes.first?["params"] as? [String: Any])
        XCTAssertEqual(params["reloadUserConfig"] as? Bool, true)
        // Codex chooses the user config from this client's isolated CODEX_HOME.
        // Passing a canonicalized filePath can fail its strict path comparison.
        XCTAssertNil(params["filePath"])
        let edits = try XCTUnwrap(params["edits"] as? [[String: Any]])
        XCTAssertEqual(edits.count, 2)
        for edit in edits {
            let keyPath = try XCTUnwrap(edit["keyPath"] as? String)
            XCTAssertTrue(keyPath.hasPrefix("hooks.state.\"\(fixture.source.path)"))
            XCTAssertTrue(keyPath.hasSuffix(".trusted_hash"))
            XCTAssertFalse(keyPath.contains("foreign"))
            XCTAssertFalse(keyPath.contains("\\/"))
            XCTAssertEqual(edit["mergeStrategy"] as? String, "replace")
            XCTAssertEqual(edit["value"] as? String, "sha256:" + String(repeating: "a", count: 64))
        }
        XCTAssertTrue(edits.contains { ($0["keyPath"] as? String)?.contains("\\\"quoted\\\"") == true })
    }

    func testIncompleteDisabledAndInvalidSourceNeverWriteTrust() async throws {
        for mode in ["missing", "disabled", "sourceError", "unknownTrust"] {
            let fixture = try makeFixture(mode: mode)
            defer { fixture.remove() }
            let client = fixture.client()
            defer { Task { await client.stop() } }
            do {
                _ = try await client.authorizeOwnedHooks(
                    sourceURL: fixture.source, command: command,
                    expectedEvents: events, cwds: [fixture.root]
                )
                XCTFail("Should reject \(mode)")
            } catch {
                let expected: CodexHookConfigurationError = mode == "disabled"
                    ? .disabled : .incomplete
                XCTAssertEqual(error as? CodexHookConfigurationError, expected)
            }
            await client.stop()
            XCTAssertTrue(try fixture.writes().isEmpty)
        }
    }

    func testDefinitionChangeDuringWriteIsNeverReportedAuthorized() async throws {
        let fixture = try makeFixture(mode: "race")
        defer { fixture.remove() }
        let client = fixture.client()
        defer { Task { await client.stop() } }
        do {
            _ = try await client.authorizeOwnedHooks(
                sourceURL: fixture.source, command: command,
                expectedEvents: events, cwds: [fixture.root]
            )
            XCTFail("Changed definition must not report authorized")
        } catch {
            XCTAssertEqual(error as? CodexHookConfigurationError, .authorizationNotConfirmed)
        }
        await client.stop()
    }

    func testTrustedDefinitionsAreReadOnlyAndRepeatedCwdsDeduplicate() async throws {
        let fixture = try makeFixture(mode: "trusted")
        defer { fixture.remove() }
        let client = fixture.client()
        defer { Task { await client.stop() } }
        let result = try await client.authorizeOwnedHooks(
            sourceURL: fixture.source, command: command,
            expectedEvents: events, cwds: [fixture.root, fixture.root]
        )
        await client.stop()
        XCTAssertTrue(result.isComplete)
        XCTAssertTrue(result.isTrusted)
        XCTAssertTrue(try fixture.writes().isEmpty)
    }

    /// Explicit opt-in executes discovery/configuration RPC only. No thread,
    /// account or Hook execution request exists in this fixture.
    func testCurrentCodexNativeTrustWithIsolatedHome() async throws {
        guard let executable = ProcessInfo.processInfo.environment["QUOTAVIEW_NATIVE_HOOK_TEST_EXECUTABLE"] else {
            throw XCTSkip("Set QUOTAVIEW_NATIVE_HOOK_TEST_EXECUTABLE for an isolated native API smoke")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .standardizedFileURL.resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("hooks.json")
        let hook: [String: Any] = ["hooks": ["SessionStart": [["hooks": [["type": "command", "command": "/bin/true", "timeout": 2]]]]]]
        try JSONSerialization.data(withJSONObject: hook).write(to: source)
        let client = CodexAppServerClient(
            executablePath: executable,
            environment: ["PATH": "/usr/bin:/bin", "HOME": root.path, "CODEX_HOME": root.path],
            startupTimeoutSeconds: 5, requestTimeoutSeconds: 5
        )
        defer { Task { await client.stop() } }
        let before = try await client.inspectOwnedHooks(
            sourceURL: source, command: "/bin/true", expectedEvents: ["SessionStart"], cwds: [root]
        )
        XCTAssertTrue(before.isComplete)
        XCTAssertFalse(before.isTrusted)
        let after = try await client.authorizeOwnedHooks(
            sourceURL: source, command: "/bin/true", expectedEvents: ["SessionStart"], cwds: [root]
        )
        await client.stop()
        XCTAssertTrue(after.isTrusted)
        let config = try String(contentsOf: root.appendingPathComponent("config.toml"), encoding: .utf8)
        XCTAssertTrue(config.contains("trusted_hash"))
        XCTAssertTrue(config.contains(before.hooks[0].currentHash))
    }

    func testCurrentCodexUserHookSymlinkWithIsolatedHome() async throws {
        guard let executable = ProcessInfo.processInfo.environment["QUOTAVIEW_NATIVE_HOOK_TEST_EXECUTABLE"] else {
            throw XCTSkip("Set QUOTAVIEW_NATIVE_HOOK_TEST_EXECUTABLE for an isolated native API smoke")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .standardizedFileURL.resolvingSymlinksInPath()
        let home = root.appendingPathComponent("codex-home")
        let dotfiles = root.appendingPathComponent("dotfiles")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dotfiles, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = home.appendingPathComponent("hooks.json")
        let target = dotfiles.appendingPathComponent("hooks.json")
        let unrelated = dotfiles.appendingPathComponent("other-hooks.json")
        let hook: [String: Any] = ["hooks": ["SessionStart": [["hooks": [["type": "command", "command": "/bin/true", "timeout": 2]]]]]]
        let definition = try JSONSerialization.data(withJSONObject: hook)
        try definition.write(to: target)
        try definition.write(to: unrelated)
        try FileManager.default.createSymbolicLink(at: source, withDestinationURL: target)
        let client = CodexAppServerClient(
            executablePath: executable,
            environment: ["PATH": "/usr/bin:/bin", "HOME": root.path, "CODEX_HOME": home.path],
            startupTimeoutSeconds: 5, requestTimeoutSeconds: 5
        )
        defer { Task { await client.stop() } }
        do {
            _ = try await client.authorizeOwnedHooks(
                sourceURL: unrelated, command: "/bin/true", expectedEvents: ["SessionStart"], cwds: [home]
            )
            XCTFail("Another source in the same dotfiles directory is not this client's user Hook")
        } catch {
            XCTAssertEqual(error as? CodexHookConfigurationError, .incomplete)
        }
        // The installer uses the canonical target path after resolving symlinks.
        let after = try await client.authorizeOwnedHooks(
            sourceURL: target, command: "/bin/true", expectedEvents: ["SessionStart"], cwds: [home]
        )
        await client.stop()
        XCTAssertTrue(after.isTrusted)
        XCTAssertEqual(try Data(contentsOf: unrelated), definition)
        XCTAssertEqual(try Data(contentsOf: target), definition)
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent("config.toml").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dotfiles.appendingPathComponent("config.toml").path))
    }

    private struct Fixture {
        let root: URL
        let source: URL
        let executable: URL
        let log: URL
        func remove() { try? FileManager.default.removeItem(at: root) }
        func client() -> CodexAppServerClient {
            CodexAppServerClient(
                executablePath: executable.path,
                environment: ["PATH": "/usr/bin:/bin", "HOME": root.path, "CODEX_HOME": root.path],
                startupTimeoutSeconds: 3, requestTimeoutSeconds: 3
            )
        }
        func writes() throws -> [[String: Any]] {
            let lines = try String(contentsOf: log, encoding: .utf8).split(separator: "\n")
            return try lines.compactMap { line in
                let value = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
                return value?["method"] as? String == "config/batchWrite" ? value : nil
            }
        }
    }

    private func makeFixture(mode: String = "ordinary") throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .standardizedFileURL.resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("hooks.json")
        let executable = root.appendingPathComponent("fake-codex")
        let log = root.appendingPathComponent("requests.jsonl")
        let parameters = ["source": source.path, "command": command, "mode": mode, "log": log.path]
        try JSONSerialization.data(withJSONObject: parameters).write(to: root.appendingPathComponent("fixture.json"))
        let script = #"""
        #!/usr/bin/python3
        import json, pathlib, sys
        cfg = json.loads(pathlib.Path(__file__).with_name('fixture.json').read_text())
        hash_value = 'sha256:' + 'a' * 64
        written = False
        def hook(event, suffix, **overrides):
            item = dict(key=cfg['source']+':'+suffix, eventName=event,
                handlerType='command', command=cfg['command'], sourcePath=cfg['source'],
                source='user', pluginId=None, enabled=True, isManaged=False,
                currentHash=hash_value, trustStatus='untrusted')
            item.update(overrides)
            return item
        for line in sys.stdin:
            request = json.loads(line)
            with open(cfg['log'], 'a') as log:
                log.write(json.dumps(request)+'\n')
            if 'id' not in request: continue
            method = request['method']
            if method == 'initialize': result = {}
            elif method == 'hooks/list':
                owned = [hook('sessionStart', 'session_start:"quoted":0'), hook('stop', 'stop:0')]
                mode = cfg['mode']
                if mode == 'missing': owned.pop()
                if mode == 'disabled': owned[0]['enabled'] = False
                if mode == 'unknownTrust': owned[0]['trustStatus'] = 'future-policy'
                if written or mode == 'trusted':
                    for h in owned: h['trustStatus'] = 'trusted'
                if written and mode == 'race':
                    owned[0]['currentHash'] = 'sha256:' + 'b' * 64
                other = [hook('stop', 'foreign-command', command=cfg['command']+' foreign'),
                    hook('stop', 'foreign-source', sourcePath=cfg['source']+'.foreign'),
                    hook('stop', 'foreign-project', source='project'),
                    hook('stop', 'foreign-managed', isManaged=True),
                    hook('stop', 'foreign-plugin', pluginId='foreign-plugin')]
                errors = [dict(path=cfg['source']+'.foreign', message='Other source warning')]
                if mode == 'sourceError': errors.append(dict(path=cfg['source'],message='Broken owned source'))
                entry = dict(cwd=str(pathlib.Path(__file__).parent), hooks=owned+other, errors=errors, warnings=[])
                result = dict(data=[entry] * max(1, len(request['params']['cwds'])))
            elif method == 'config/batchWrite':
                written = True
                result = dict(status='ok')
            else:
                print(json.dumps(dict(id=request['id'],error=dict(code=-32601,message='Unexpected request'))),flush=True)
                continue
            print(json.dumps(dict(id=request['id'],result=result)),flush=True)
        """#
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        return Fixture(root: root, source: source, executable: executable, log: log)
    }
}
