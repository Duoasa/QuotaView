import Darwin
import Foundation
import XCTest
@testable import QuotaView
@testable import QuotaViewCore

@MainActor
final class NativeHookRuntimeSmokeTests: XCTestCase {
    func testAutomaticSetupNativeConsentDeliveryAndPersistentOptOut() async throws {
        guard let executable = ProcessInfo.processInfo.environment["QUOTAVIEW_NATIVE_HOOK_TEST_EXECUTABLE"] else {
            throw XCTSkip("An explicitly selected Codex CLI is required for this isolated smoke")
        }
        let root = URL(fileURLWithPath: "/private/tmp/qv-native-" + String(UUID().uuidString.prefix(8)))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let helper = root.appendingPathComponent("QuotaViewActivityHook")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        let installer = CodexActivityHookInstaller(socketURL: root.appendingPathComponent("test.sock"),
            authenticationToken: "isolated-token", queueURL: root.appendingPathComponent("queue"),
            hooksURL: root.appendingPathComponent("hooks.json"), helperURL: helper,
            installedHelperURL: helper, configurationURL: root.appendingPathComponent("route.json"))
        let domain = "QuotaViewNativeRuntime-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(123, forKey: "codexActivity.setup.restartProcessIdentifier")
        let store = CodexActivityStore(titleClient: CodexAppServerClient(executablePath: nil),
            sharedActivityClient: CodexSharedAppServerActivityClient(configuration: .init(isEnabled: false,
                socketURL: root.appendingPathComponent("unused.sock"), executablePath: nil)),
            localRolloutActivityClient: CodexLocalRolloutActivityClient(configuration: .init(isEnabled: false,
                codexHomeURL: root)), sessionDirectory: root, sessionKindResolver: { _ in .user })
        let runtime = CodexActivityRuntime(preferences: AppPreferences(defaults: defaults), defaults: defaults,
            hookInstaller: installer, hookEnvironmentInspector: .init(executablePath: executable,
                dataDirectoryURL: root), defaultDataDirectory: root, activityStore: store)
        // Exercise setup without showing any application UI or starting actual task observers.
        runtime.refreshConnectionStatus()
        try await settled(runtime)
        XCTAssertEqual(runtime.hookConnectionStatus, .awaitingTrust)
        XCTAssertTrue(try installer.isInstalled())
        XCTAssertFalse(try String(contentsOf: installer.hooksURL, encoding: .utf8).contains("isolated-token"))
        let definitions = try Data(contentsOf: installer.hooksURL)
        runtime.openCodexSecurityReview()
        try await settled(runtime)
        XCTAssertEqual(runtime.hookConnectionStatus, .awaitingFirstEvent)
        XCTAssertNil(defaults.object(forKey: "codexActivity.setup.restartProcessIdentifier"))
        XCTAssertEqual(try Data(contentsOf: installer.hooksURL), definitions)
        let received = await runtime.receiveCompatibilityActivity(.init(source: .liveSocket,
            activity: .init(event: .postToolUse, sessionHash: "fixture-session", turnHash: "fixture-turn", source: .hook)))
        XCTAssertTrue(received)
        XCTAssertEqual(runtime.hookConnectionStatus, .connected)
        runtime.refreshConnectionStatus()
        try await settled(runtime)
        XCTAssertEqual(runtime.hookConnectionStatus, .connected)
        runtime.disableCompatibilityHook()
        try await settled(runtime)
        XCTAssertEqual(runtime.hookConnectionStatus, .notInstalled)
        runtime.refreshConnectionStatus()
        try await settled(runtime)
        XCTAssertFalse(try installer.hasQuotaViewHandlers(), "Explicit opt-out cannot be reinstalled by maintenance")
        XCTAssertEqual(runtime.hookConnectionStatus, .notInstalled)
        await runtime.stop()
    }

    func testRevokedNativeTrustCannotBeRestoredByQueuedOrLiveDelivery() async throws {
        let fixture = try makeTrustFixture(); defer { fixture.remove() }
        let (runtime, store) = fixture.runtime()
        runtime.refreshConnectionStatus(); try await settled(runtime)
        XCTAssertEqual(runtime.hookConnectionStatus, .awaitingTrust)
        runtime.openCodexSecurityReview(); try await settled(runtime)
        XCTAssertEqual(runtime.hookConnectionStatus, .awaitingFirstEvent)
        _ = await runtime.receiveCompatibilityActivity(.init(source: .liveSocket,
            activity: .init(event: .postToolUse, sessionHash: "first", turnHash: "turn", source: .hook)))
        XCTAssertEqual(runtime.hookConnectionStatus, .connected)

        try fixture.setTrust(false)
        runtime.refreshConnectionStatus(); try await settled(runtime)
        XCTAssertEqual(runtime.hookConnectionStatus, .awaitingTrust)
        let current = store.snapshot
        XCTAssertEqual(current?.sessionHash, "first")
        let queued = CodexActivityEvent(event: .userPromptSubmit, sessionHash: "historical-task",
            turnHash: "historical-turn", source: .hook, occurredAt: Date().addingTimeInterval(-120))
        _ = await runtime.receiveCompatibilityActivity(.init(eventID: "queued-before-revocation", source: .startupReplay, activity: queued))
        XCTAssertEqual(runtime.hookConnectionStatus, .awaitingTrust,
            "A previously authenticated payload does not reinstate revoked native authorization")
        XCTAssertEqual(store.snapshot, current,
            "Historical receipt neither clears the current task nor bypasses normal old-activity admission")
        _ = await runtime.receiveCompatibilityActivity(.init(source: .liveQueue,
            activity: .init(event: .postToolUse, sessionHash: "historical-task", turnHash: "historical-turn", source: .hook)))
        XCTAssertEqual(runtime.hookConnectionStatus, .awaitingTrust,
            "Fresh receipt is also independent of configuration trust")
        await runtime.stop()
    }

    func testNewRuntimeRequiresFreshDeliveryDespitePersistedHistoryAndReplay() async throws {
        let fixture = try makeTrustFixture(); defer { fixture.remove() }
        try fixture.setTrust(true)
        fixture.defaults.set(fixture.installer.installationIdentifier, forKey: "codexActivity.setup.connectedInstallation")
        fixture.defaults.set(fixture.installer.installationIdentifier, forKey: "codexActivity.setup.observedInstallation")
        let (runtime, _) = fixture.runtime()
        runtime.refreshConnectionStatus(); try await settled(runtime)
        XCTAssertEqual(runtime.hookConnectionStatus, .awaitingFirstEvent)
        for source in [CodexActivityDeliverySource.startupReplay, .liveQueue] {
            _ = await runtime.receiveCompatibilityActivity(.init(source: source,
                activity: .init(event: .postToolUse, sessionHash: "historical", turnHash: "old", source: .hook,
                    occurredAt: Date().addingTimeInterval(-120))))
            XCTAssertEqual(runtime.hookConnectionStatus, .awaitingFirstEvent,
                "Persisted/replayed receipt cannot prove delivery for this runtime run")
        }
        _ = await runtime.receiveCompatibilityActivity(.init(source: .liveQueue,
            activity: .init(event: .postToolUse, sessionHash: "live", turnHash: "new", source: .hook)))
        XCTAssertEqual(runtime.hookConnectionStatus, .connected)
        await runtime.stop()
        let (nextRuntime, _) = fixture.runtime()
        nextRuntime.refreshConnectionStatus(); try await settled(nextRuntime)
        XCTAssertEqual(nextRuntime.hookConnectionStatus, .awaitingFirstEvent,
            "Restart resets current delivery health while preserving history")
        XCTAssertEqual(fixture.defaults.string(forKey: "codexActivity.setup.connectedInstallation"),
            fixture.installer.installationIdentifier)
        await nextRuntime.stop()
    }

    func testFailedRemovalKeepsExplicitOptOutAcrossRefreshAndNewRuntime() async throws {
        let fixture = try makeTrustFixture(); defer { fixture.remove() }
        let (runtime, store) = fixture.runtime()
        runtime.refreshConnectionStatus(); try await settled(runtime)
        runtime.openCodexSecurityReview(); try await settled(runtime)
        _ = await runtime.receiveCompatibilityActivity(.init(source: .liveSocket,
            activity: .init(event: .postToolUse, sessionHash: "live", turnHash: "turn", source: .hook)))
        XCTAssertEqual(runtime.hookConnectionStatus, .connected)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixture.installer.hooksURL)) as? [String: Any])
        var hooks = try XCTUnwrap(object["hooks"] as? [String: Any])
        var groups = try XCTUnwrap(hooks["Stop"] as? [[String: Any]])
        groups.append(["hooks": [["type": "command", "command": "/bin/echo foreign-observer", "timeout": 2]]])
        hooks["Stop"] = groups; object["hooks"] = hooks
        let original = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try original.write(to: fixture.installer.hooksURL, options: .atomic)
        // A held own-writer lock forces a bounded cleanup failure without
        // changing permissions or touching any real Codex/user configuration.
        let lock = Darwin.open(fixture.root.appendingPathComponent(".quotaview-hooks.lock").path, O_RDWR | O_NOFOLLOW)
        XCTAssertGreaterThanOrEqual(lock, 0)
        defer { Darwin.close(lock) }
        XCTAssertEqual(flock(lock, LOCK_EX | LOCK_NB), 0)
        var locked = true
        defer { if locked { _ = flock(lock, LOCK_UN) } }
        runtime.disableCompatibilityHook()
        XCTAssertEqual(fixture.defaults.object(forKey: "codexActivity.setup.automaticHook") as? Bool, false,
            "User intent is durable before filesystem cleanup settles")
        XCTAssertNil(fixture.defaults.object(forKey: "codexActivity.setup.nativeConsentVersion"))
        try await settled(runtime)
        if case .abnormal = runtime.hookConnectionStatus {}
        else { XCTFail("Residual cleanup failure remains visible") }
        let before = store.snapshot
        _ = await runtime.receiveCompatibilityActivity(.init(source: .liveSocket,
            activity: .init(event: .userPromptSubmit, sessionHash: "cached-disabled", turnHash: "old", source: .hook)))
        XCTAssertEqual(store.snapshot, before, "Cached own handlers cannot reactivate an opted-out channel")
        if case .abnormal = runtime.hookConnectionStatus {}
        else { XCTFail("Delivery cannot erase the removal failure") }
        XCTAssertEqual(try Data(contentsOf: fixture.installer.hooksURL), original)
        _ = flock(lock, LOCK_UN); locked = false
        runtime.refreshConnectionStatus(); try await settled(runtime)
        XCTAssertEqual(fixture.defaults.object(forKey: "codexActivity.setup.automaticHook") as? Bool, false)
        XCTAssertEqual(try Data(contentsOf: fixture.installer.hooksURL), original,
            "Rechecking failure residue must not reinstall or repair opted-out Hooks")
        if case .abnormal = runtime.hookConnectionStatus {}
        else { XCTFail("Read-only residue inspection preserves the opt-out") }
        await runtime.stop()
        let (nextRuntime, nextStore) = fixture.runtime()
        nextRuntime.refreshConnectionStatus(); try await settled(nextRuntime)
        XCTAssertEqual(fixture.defaults.object(forKey: "codexActivity.setup.automaticHook") as? Bool, false)
        _ = await nextRuntime.receiveCompatibilityActivity(.init(source: .liveQueue,
            activity: .init(event: .userPromptSubmit, sessionHash: "cached-after-restart", turnHash: "old", source: .hook)))
        XCTAssertNil(nextStore.snapshot)
        XCTAssertEqual(try Data(contentsOf: fixture.installer.hooksURL), original)
        nextRuntime.disableCompatibilityHook(); try await settled(nextRuntime)
        XCTAssertEqual(nextRuntime.hookConnectionStatus, .notInstalled)
        let remaining = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixture.installer.hooksURL)) as? [String: Any])
        let remainingHooks = try XCTUnwrap(remaining["hooks"] as? [String: Any])
        let commands = remainingHooks.values.flatMap { ($0 as? [[String: Any]] ?? []) }
            .flatMap { ($0["hooks"] as? [[String: Any]] ?? []) }.compactMap { $0["command"] as? String }
        XCTAssertEqual(commands, ["/bin/echo foreign-observer"], "Retry removes only this installation's own definitions")
        await nextRuntime.stop()
    }

    private struct TrustFixture {
        let root: URL
        let executable: URL
        let state: URL
        let domain: String
        let defaults: UserDefaults
        let installer: CodexActivityHookInstaller
        func setTrust(_ trusted: Bool) throws {
            try Data((trusted ? "trusted" : "untrusted").utf8).write(to: state, options: .atomic)
        }
        func remove() {
            defaults.removePersistentDomain(forName: domain)
            try? FileManager.default.removeItem(at: root)
        }
        @MainActor func runtime() -> (CodexActivityRuntime, CodexActivityStore) {
            let store = CodexActivityStore(titleClient: CodexAppServerClient(executablePath: nil),
                sharedActivityClient: CodexSharedAppServerActivityClient(configuration: .init(isEnabled: false,
                    socketURL: root.appendingPathComponent("unused.sock"), executablePath: nil)),
                localRolloutActivityClient: CodexLocalRolloutActivityClient(configuration: .init(isEnabled: false,
                    codexHomeURL: root)), sessionDirectory: root, sessionKindResolver: { _ in .user })
            return (.init(preferences: AppPreferences(defaults: defaults), defaults: defaults,
                hookInstaller: installer, hookEnvironmentInspector: .init(executablePath: executable.path,
                    dataDirectoryURL: root), defaultDataDirectory: root, activityStore: store), store)
        }
    }

    private func makeTrustFixture() throws -> TrustFixture {
        let root = URL(fileURLWithPath: "/private/tmp/qv-trust-" + String(UUID().uuidString.prefix(8)))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let executable = root.appendingPathComponent("codex"), state = root.appendingPathComponent("trust-state")
        let helper = root.appendingPathComponent("QuotaViewActivityHook")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        let script = #"""
        #!/usr/bin/python3
        import json, pathlib, sys
        root = pathlib.Path(__file__).parent
        if '--version' in sys.argv:
            print('codex-cli isolated-trust-fixture'); sys.exit(0)
        if 'features' in sys.argv:
            print('hooks stable true'); sys.exit(0)
        for line in sys.stdin:
            request = json.loads(line)
            if 'id' not in request: continue
            method = request['method']
            if method == 'initialize': result = {}
            elif method == 'hooks/list':
                source = root / 'hooks.json'
                definitions = json.loads(source.read_text()).get('hooks', {})
                hooks = []
                for event, groups in definitions.items():
                    for index, group in enumerate(groups):
                        for subindex, handler in enumerate(group['hooks']):
                            hooks.append(dict(key=str(source)+':'+event+':'+str(index)+':'+str(subindex),
                                eventName=event[:1].lower()+event[1:], handlerType='command', command=handler['command'],
                                sourcePath=str(source), source='user', pluginId=None, enabled=True, isManaged=False,
                                currentHash='sha256:'+'a'*64, trustStatus=(root/'trust-state').read_text()))
                result = dict(data=[dict(cwd=str(root), hooks=hooks, errors=[])])
            elif method == 'config/batchWrite':
                (root/'trust-state').write_text('trusted')
                result = {}
            else:
                print(json.dumps(dict(id=request['id'], error=dict(code=-32601,message='Unexpected isolated request'))),flush=True)
                continue
            print(json.dumps(dict(id=request['id'],result=result)),flush=True)
        """#
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let installer = CodexActivityHookInstaller(socketURL: root.appendingPathComponent("test.sock"),
            authenticationToken: "isolated-token", queueURL: root.appendingPathComponent("queue"),
            hooksURL: root.appendingPathComponent("hooks.json"), helperURL: helper,
            installedHelperURL: helper, configurationURL: root.appendingPathComponent("route.json"))
        let domain = "QuotaViewTrustFixture-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        let fixture = TrustFixture(root: root, executable: executable, state: state, domain: domain,
            defaults: defaults, installer: installer)
        try fixture.setTrust(false)
        return fixture
    }

    private func settled(_ runtime: CodexActivityRuntime) async throws {
        let deadline = Date().addingTimeInterval(15)
        while runtime.hookOperation != .idle, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(runtime.hookOperation, .idle)
    }
}
