import Foundation
import Darwin
import XCTest
@testable import QuotaViewCore
@testable import QuotaView

final class ProxySettingsTests: XCTestCase {
    func testValidationRejectsCredentialsPathsAndInvalidPorts() throws {
        for host in ["", "http://127.0.0.1", "host/path", "host?token=x", "host#x", "a b", "-host", "host."] {
            XCTAssertThrowsError(try ProxyConfiguration(host: host).validated(), host)
        }
        XCTAssertThrowsError(try ProxyConfiguration(host: "user:secret@host").validated()) {
            XCTAssertEqual($0 as? ProxyConfiguration.ValidationError, .authenticationUnsupported)
        }
        for port in ["0", "65536", "-1", "1.2", "", "１２", "80/", "9999999999999999999999"] {
            XCTAssertThrowsError(try ProxyConfiguration(port: port).validated(), port)
        }
        let ipv6 = try ProxyConfiguration(isEnabled: true, scheme: .socks5,
                                         host: " [::1] ", port: "07890").validated()
        XCTAssertEqual(ipv6.host, "::1")
        XCTAssertEqual(try ipv6.applying(to: [:])["HTTPS_PROXY"], "socks5h://[::1]:7890")
    }

    func testProxyEnvironmentIsScopedAndDisabledPreservesOriginalBehavior() throws {
        let base = ["HTTPS_PROXY": "http://old:80", "http_proxy": "http://old:81",
                    "ALL_PROXY": "socks5://old:82", "NO_PROXY": "*", "no_proxy": "*",
                    "PATH": "/usr/bin", "SENTINEL": "preserved"]
        XCTAssertEqual(try ProxyConfiguration.default.applying(to: base), base)
        let config = ProxyConfiguration(isEnabled: true)
        let active = try config.applying(to: base)
        for key in ["HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy"] {
            XCTAssertEqual(active[key], "http://127.0.0.1:7890")
        }
        XCTAssertEqual(active["no_proxy"], "localhost,127.0.0.1,::1")
        XCTAssertEqual(active["NO_PROXY"], active["no_proxy"])
        XCTAssertEqual(active["SENTINEL"], base["SENTINEL"])
        XCTAssertEqual(base["NO_PROXY"], "*")
    }

    @MainActor
    func testPreferencesPersistAtomicallyAndRestoreDefaults() throws {
        let name = "QuotaViewProxyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = AppPreferences(defaults: defaults)
        XCTAssertEqual(preferences.proxyConfiguration, .default)
        let value = ProxyConfiguration(isEnabled: true, scheme: .socks5, host: "proxy.example", port: "1080")
        try preferences.saveProxyConfiguration(value)
        XCTAssertEqual(AppPreferences(defaults: defaults).proxyConfiguration, value)
        XCTAssertThrowsError(try preferences.saveProxyConfiguration(.init(isEnabled: true, host: "user:pw@host")))
        XCTAssertEqual(AppPreferences(defaults: defaults).proxyConfiguration, value)
        preferences.restoreProxyDefaults()
        XCTAssertEqual(AppPreferences(defaults: defaults).proxyConfiguration, .default)
    }

    func testHTTPAndSOCKS5CarryActualNetworkRequestsAndRecover() async throws {
        let fixture = try await ProxyFixture.start()
        defer { fixture.stop() }
        for scheme in ProxyConfiguration.Scheme.allCases {
            let client = fixture.client(scheme: scheme)
            let result = try await client.fetchPayload(includeUsage: false)
            XCTAssertEqual(result.rateLimits.rateLimits.primary?.usedPercent, 23)
            await client.stop()
        }
        let events = try fixture.events()
        XCTAssertTrue(events.contains("\"scheme\": \"http\""))
        XCTAssertTrue(events.contains("\"scheme\": \"socks5\""))
        XCTAssertTrue(events.contains("quota.fixture.invalid"))
        // Disabled mode retains the pre-existing environment-provided proxy.
        let restored = fixture.client(configuration: .default,
            environment: ["http_proxy": "http://127.0.0.1:\(fixture.port)"])
        let restoredPayload = try await restored.fetchPayload(includeUsage: false)
        XCTAssertEqual(restoredPayload.rateLimits.rateLimits.primary?.usedPercent, 23)
        await restored.stop()
    }

    func testProxyRefusalTimeoutAndDisconnectDoNotBecomeSuccess() async throws {
        let fixture = try await ProxyFixture.start()
        defer { fixture.stop() }
        for scheme in ProxyConfiguration.Scheme.allCases {
            for mode in ["drop", "auth", "forbidden", "hang"] {
                try fixture.mode(mode)
                let client = fixture.client(scheme: scheme, timeout: mode == "hang" ? 1 : 5)
                do {
                    _ = try await client.fetchPayload(includeUsage: false)
                    XCTFail("\(mode) unexpectedly succeeded")
                } catch {
                    if mode == "hang" {
                        XCTAssertEqual(ProxyConnectionFailure.classify(error), .timedOut)
                    }
                }
                await client.stop()
            }
        }
        try fixture.mode("success")
        let recovered = fixture.client()
        let payload = try await recovered.fetchPayload(includeUsage: false)
        XCTAssertEqual(payload.rateLimits.rateLimits.primary?.usedPercent, 23)
        await recovered.stop()
        let unavailable = fixture.client(configuration: .init(isEnabled: true, port: "1"))
        do { _ = try await unavailable.fetchPayload(includeUsage: false); XCTFail("Closed proxy port succeeded") }
        catch { XCTAssertEqual(ProxyConnectionFailure.classify(error), .connectionFailed) }
        await unavailable.stop()
    }

    @MainActor
    func testConnectionTestValidatesQuotaAndCancellationDiscardsLateResults() async throws {
        let fixture = try await ProxyFixture.start()
        defer { fixture.stop() }
        let store = makeStore(fixture: fixture)
        let config = fixture.configuration(scheme: .socks5)
        store.testProxyConnection(config)
        try await waitUntil { store.proxyTestState != .testing }
        XCTAssertEqual(store.proxyTestState, .success)
        XCTAssertNil(store.snapshot, "Testing must not publish account data")
        try fixture.mode("bad")
        store.testProxyConnection(config)
        try await waitUntil { store.proxyTestState != .testing }
        XCTAssertEqual(store.proxyTestState, .failed(.invalidResponse))
        try fixture.mode("hang")
        store.testProxyConnection(config)
        try await Task.sleep(for: .milliseconds(100))
        store.cancelProxyTest()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(store.proxyTestState, .idle)
        try fixture.mode("success")
        store.testProxyConnection(config)
        try await waitUntil { store.proxyTestState != .testing }
        XCTAssertEqual(store.proxyTestState, .success)
        await store.stop()
    }

    @MainActor
    func testSavingProxyReplacesBusinessClientAndRejectsOldRequest() async throws {
        let fixture = try await ProxyFixture.start()
        defer { fixture.stop() }
        let name = "QuotaViewProxyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = AppPreferences(defaults: defaults)
        // Default behavior uses an inherited proxy, so this also proves restoration.
        let store = makeStore(fixture: fixture, preferences: preferences, defaults: defaults)
        try fixture.mode("hang")
        let old = Task { await store.refresh() }
        try await Task.sleep(for: .milliseconds(100))
        try fixture.mode("success")
        try preferences.saveProxyConfiguration(fixture.configuration(scheme: .socks5))
        try await waitUntil { store.hasCurrentCodexStatus && !store.isRefreshing }
        await old.value
        XCTAssertEqual(store.snapshot?.remainingPercent, 77)
        XCTAssertNil(store.errorMessage)
        XCTAssertTrue(try fixture.events().contains("\"scheme\": \"socks5\""))
        try preferences.saveProxyConfiguration(.init(isEnabled: true, port: "1"))
        try await waitUntil { store.errorMessage != nil && !store.isRefreshing }
        XCTAssertFalse(store.hasCurrentCodexStatus)
        preferences.restoreProxyDefaults()
        try await waitUntil { store.hasCurrentCodexStatus && !store.isRefreshing }
        XCTAssertEqual(store.snapshot?.remainingPercent, 77)
        XCTAssertFalse(preferences.proxyConfiguration.isEnabled)
        await store.stop()
    }

    func testSOCKSBridgeRejectsOversizedHeadersAndClosesItsListener() async throws {
        let bridge = SOCKS5HTTPBridge()
        let port = try await bridge.start(configuration: .init(isEnabled: true, scheme: .socks5))
        defer { bridge.stop() }
        func connectLoopback() -> Int32 {
            let fd = socket(AF_INET, SOCK_STREAM, 0)
            guard fd >= 0 else { return -1 }
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = port.bigEndian
            address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if result != 0 { close(fd); return -1 }
            var timeout = timeval(tv_sec: 1, tv_usec: 0)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            var noSignal: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
            return fd
        }
        let fd = connectLoopback()
        XCTAssertGreaterThanOrEqual(fd, 0)
        guard fd >= 0 else { return }
        defer { close(fd) }
        let oversized = [UInt8](repeating: 65, count: 70_000)
        _ = oversized.withUnsafeBytes { Darwin.send(fd, $0.baseAddress, $0.count, 0) }
        var byte: UInt8 = 0
        let count = recv(fd, &byte, 1, 0)
        XCTAssertTrue(count == 0 || (count < 0 && errno == ECONNRESET), "Oversized request was not closed")
        bridge.stop()
        try await Task.sleep(for: .milliseconds(100))
        let afterStop = connectLoopback()
        XCTAssertEqual(afterStop, -1, "Listener must close when its query client stops")
        if afterStop >= 0 { close(afterStop) }
    }

    func testInstalledCodexThroughHTTPAndSOCKS5WithIsolatedFixtureAccount() async throws {
        guard ProcessInfo.processInfo.environment["QUOTAVIEW_RUN_CODEX_PROXY_TESTS"] == "1" else {
            throw XCTSkip("Opt in with QUOTAVIEW_RUN_CODEX_PROXY_TESTS=1; requires locally installed Codex")
        }
        let executable = try XCTUnwrap(CodexExecutableLocator.locate())
        let fixture = try await ProxyFixture.start(tls: true)
        defer { fixture.stop() }
        let codexHome = fixture.root.appendingPathComponent("codex-home")
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        try "chatgpt_base_url = \"https://quota.fixture.invalid\"\n[analytics]\nenabled = false\n".write(
            to: codexHome.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let claims: [String: Any] = ["https://api.openai.com/auth": [
            "chatgpt_account_id": "fixture-account", "chatgpt_plan_type": "plus"], "exp": 4102444800]
        func base64URL(_ data: Data) -> String {
            data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        let jwt = base64URL(Data("{\"alg\":\"none\"}".utf8)) + "."
            + base64URL(try JSONSerialization.data(withJSONObject: claims)) + ".fixture"
        let auth: [String: Any] = ["auth_mode": "chatgpt", "tokens": ["id_token": jwt,
            "access_token": jwt, "refresh_token": "fixture-only", "account_id": "fixture-account"],
            "last_refresh": ISO8601DateFormatter().string(from: Date())]
        try JSONSerialization.data(withJSONObject: auth).write(to: codexHome.appendingPathComponent("auth.json"))
        for scheme in ProxyConfiguration.Scheme.allCases {
            let isolatedHome = fixture.root.appendingPathComponent("codex-" + scheme.rawValue)
            try FileManager.default.copyItem(at: codexHome, to: isolatedHome)
            let client = CodexAppServerClient(executablePath: executable,
                proxyConfiguration: fixture.configuration(scheme: scheme),
                environment: ["PATH": "/usr/bin:/bin", "HOME": fixture.root.path,
                              "CODEX_HOME": isolatedHome.path,
                              "CODEX_CA_CERTIFICATE": fixture.root.appendingPathComponent("cert.pem").path],
                startupTimeoutSeconds: 10, requestTimeoutSeconds: 8)
            do {
                let payload = try await client.fetchPayload(includeUsage: false)
                XCTAssertEqual(payload.rateLimits.rateLimits.primary?.usedPercent, 23)
                _ = try CodexProviderAdapter.makeResult(payload: payload)
            } catch {
                await client.stop()
                XCTFail("Installed Codex \(scheme) failed: \(error); fixture events: \((try? fixture.events()) ?? "none")")
                continue
            }
            await client.stop()
        }
        let events = try fixture.events()
        XCTAssertTrue(events.contains("\"scheme\": \"http\""))
        XCTAssertTrue(events.contains("\"scheme\": \"socks5\""))
        XCTAssertTrue(events.contains("\"tls\": true"))
    }

    @MainActor
    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(8)
        while !condition() && Date() < deadline { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertTrue(condition(), "Timed out waiting for state transition")
    }

    @MainActor
    private func makeStore(fixture: ProxyFixture, preferences: AppPreferences? = nil,
                           defaults: UserDefaults? = nil) -> CodexStatusStore {
        CodexStatusStore(preferences: preferences, diagnostics: defaults ?? UserDefaults(suiteName: "QuotaViewProxyTests.temporary")!,
            widgetSnapshotWriter: QuotaViewWidgetSnapshotWriter(
                appGroupIdentifier: "com.quotaview.tests.disabled",
                containerURLProvider: { _ in nil }, timelineReloader: { _ in }),
            proxyClientFactory: { configuration in
                fixture.client(configuration: configuration,
                    environment: ["http_proxy": "http://127.0.0.1:\(fixture.port)"])
            })
    }
}

private final class ProxyFixture: @unchecked Sendable {
    let root: URL
    let port: String
    let executable: URL
    private let process: Process

    private init(root: URL, port: String, executable: URL, process: Process) {
        self.root = root; self.port = port; self.executable = executable; self.process = process
    }

    static func start(tls: Bool = false) async throws -> ProxyFixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("quotaview-proxy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "success".write(to: root.appendingPathComponent("mode"), atomically: true, encoding: .utf8)
        if tls { try Data().write(to: root.appendingPathComponent("tls")) }
        let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("scripts/test-support/proxy_fixture.py")
        let executable = root.appendingPathComponent("codex-fixture")
        let quoted = "'" + script.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        try "#!/bin/sh\nexec /usr/bin/python3 \(quoted) rpc\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [script.path, "serve", root.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let deadline = Date().addingTimeInterval(tls ? 15 : 5)
            let portFile = root.appendingPathComponent("port")
            while !FileManager.default.fileExists(atPath: portFile.path) && Date() < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            let port = try String(contentsOf: portFile, encoding: .utf8)
            return ProxyFixture(root: root, port: port, executable: executable, process: process)
        } catch {
            if process.isRunning { process.terminate() }
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }

    func configuration(scheme: ProxyConfiguration.Scheme = .http) -> ProxyConfiguration {
        .init(isEnabled: true, scheme: scheme, port: port)
    }
    func client(scheme: ProxyConfiguration.Scheme = .http, timeout: TimeInterval = 5) -> CodexAppServerClient {
        client(configuration: configuration(scheme: scheme), timeout: timeout)
    }
    func client(configuration: ProxyConfiguration, environment: [String: String] = [:],
                timeout: TimeInterval = 5) -> CodexAppServerClient {
        var environment = environment
        environment["PATH"] = "/usr/bin:/bin"
        return CodexAppServerClient(executablePath: executable.path, proxyConfiguration: configuration,
            environment: environment, startupTimeoutSeconds: 5, requestTimeoutSeconds: timeout)
    }
    func mode(_ mode: String) throws {
        try mode.write(to: root.appendingPathComponent("mode"), atomically: true, encoding: .utf8)
    }
    func events() throws -> String {
        try String(contentsOf: root.appendingPathComponent("events.jsonl"), encoding: .utf8)
    }
    func stop() {
        if process.isRunning { process.terminate() }
        try? FileManager.default.removeItem(at: root)
    }
}
