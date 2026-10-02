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

    private func settled(_ runtime: CodexActivityRuntime) async throws {
        let deadline = Date().addingTimeInterval(15)
        while runtime.hookOperation != .idle, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(runtime.hookOperation, .idle)
    }
}
