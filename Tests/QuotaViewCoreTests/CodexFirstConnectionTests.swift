import Foundation
import SQLite3
import XCTest
@testable import QuotaView
@testable import QuotaViewCore

@MainActor
final class CodexFirstConnectionTests: XCTestCase {
    private let hookStates: [CodexActivityConnectionStatus] = [
        .notInstalled, .awaitingTrust, .installedNeedsRestart,
        .awaitingFirstEvent, .connected, .abnormal("Hook setup failed")
    ]

    func testAutomaticCopyDoesNotInheritHookInstallationOrTrustState() {
        for hook in hookStates {
            let waiting = CodexActivityConnectionPresentation(
                connection: .init(localHealth: .waitingForRecords), hookStatus: hook
            )
            XCTAssertEqual(waiting.automaticStatusTitle(.init(language: .simplifiedChinese)),
                           "等待首次任务")
            XCTAssertEqual(waiting.automaticStatusTitle(.init(language: .english)),
                           "Waiting for First Task")
            XCTAssertEqual(waiting.automaticSubtitle(.init(language: .simplifiedChinese)),
                CodexActivityConnectionPresentation(connection: .init(localHealth: .waitingForRecords), hookStatus: .notInstalled)
                    .automaticSubtitle(.init(language: .simplifiedChinese)))

            let connected = CodexActivityConnectionPresentation(
                connection: .init(localHealth: .receiving), hookStatus: hook
            )
            XCTAssertEqual(connected.automaticStatusTitle(.init(language: .simplifiedChinese)),
                           "已收到任务活动")
            XCTAssertEqual(connected.automaticStatusTitle(.init(language: .english)),
                           "Task Activity Received")
            XCTAssertEqual(connected.hookStatus, hook,
                           "Automatic connection must not manufacture Hook trust or connection")

            let disabled = CodexActivityConnectionPresentation(
                connection: .init(localHealth: .disabled), hookStatus: hook
            )
            XCTAssertEqual(disabled.automaticStatusTitle(.init(language: .simplifiedChinese)),
                           "自动读取已禁用")
            XCTAssertEqual(disabled.automaticStatusTitle(.init(language: .english)),
                           "Automatic Reading Disabled")
        }
    }

    func testSetupIslandRequiresExplicitActionAndCannotCoverAConnectedSource() {
        for native in [CodexSharedAppServerConnectionState.disabled, .discovering, .connected] {
            for hook in hookStates {
                let presentation = CodexActivityConnectionPresentation(
                    connection: .init(sharedState: native), hookStatus: hook
                )
                XCTAssertFalse(presentation.showsHookSetupIsland(explicitlyRequested: false),
                               "An unfinished old Hook setup must not request an island on launch")
                if native == .connected || hook == .connected {
                    XCTAssertFalse(presentation.showsHookSetupIsland(explicitlyRequested: true))
                } else {
                    XCTAssertTrue(presentation.showsHookSetupIsland(explicitlyRequested: true))
                }
            }
        }
    }

    func testFreshCodexDirectoryConnectsAndCompletesWithoutAnyHookSetup() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuotaViewFirstConnection-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = makeStore(root: root, localEnabled: true)
        store.startNativeActivityNotifications()
        do {
            try await waitUntil { store.nativeConnectionState == .discovering }
            // Give the live discovery loop time to inspect a missing sessions directory.
            try await Task.sleep(nanoseconds: 200_000_000)
            XCTAssertEqual(store.nativeConnectionState, .discovering)
            XCTAssertNil(store.snapshot)
            XCTAssertEqual(store.presentation, .hidden)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))

            let sessions = root.appendingPathComponent("sessions/2026/09/11")
            try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
            let rollout = sessions.appendingPathComponent("new-task.jsonl")
            let initial = """
            {"type":"session_meta","payload":{"id":"fresh-session","cwd":"/private/test-project","source":"cli"}}
            {"timestamp":"\(timestamp())","type":"event_msg","payload":{"type":"task_started","turn_id":"fresh-turn"}}

            """
            try Data(initial.utf8).write(to: rollout)
            try await waitUntil {
                store.nativeConnectionState == .connected && store.snapshot != nil
            }
            XCTAssertEqual(store.lifecycle, .active)
            XCTAssertNotEqual(store.presentation, .hidden)
            let untrustedHook = CodexActivityConnectionPresentation(
                connection: store.automaticConnection, hookStatus: .awaitingTrust
            )
            XCTAssertFalse(untrustedHook.showsHookSetupIsland(explicitlyRequested: true))

            let handle = try FileHandle(forWritingTo: rollout)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(
                "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\",\"turn_id\":\"fresh-turn\"}}\n".utf8
            ))
            try handle.close()
            try await waitUntil { store.lifecycle == .completed }
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("hooks.json").path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("config.toml").path))
            await store.stop()
            XCTAssertEqual(store.nativeConnectionState, .disabled)
        } catch {
            await store.stop()
            throw error
        }
    }

    func testDisabledAutomaticClientsFinishDiscoveryWithoutInventingAConnection() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuotaViewDisabledConnection-\(UUID().uuidString)")
        let store = makeStore(root: root, localEnabled: false)
        store.startNativeActivityNotifications()
        do {
            try await waitUntil { store.nativeConnectionState == .disabled }
            XCTAssertNil(store.snapshot)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
            await store.stop()
            store.startNativeActivityNotifications()
            try await waitUntil { store.nativeConnectionState == .disabled }
            await store.stop()
        } catch {
            await store.stop()
            throw error
        }
    }

    func testReadableHistoryAndUnknownEventsAreReadyWithoutShowingActivity() async throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeRollout(root, id: "quiet", lines: [
            ["type": "event_msg", "payload": ["type": "future_optional_event"]]
        ])
        let store = makeStore(root: root, localEnabled: true)
        store.startNativeActivityNotifications()
        try await waitUntil { store.localHealth == .ready }
        XCTAssertNil(store.snapshot)
        XCTAssertEqual(store.presentation, .hidden)
        await store.recheckLocalDiscovery()
        XCTAssertEqual(store.localHealth, .ready)
        XCTAssertNil(store.snapshot)
        await store.stop()
    }

    func testUnfinishedHistoryWaitsForIncrementalActivityAndRecoversTokens() async throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try writeRollout(root, id: "old", lines: [
            startRecord("old-turn", timestamp: "2020-01-01T00:00:00Z"), tokenRecord(100, last: 100)
        ])
        let store = makeStore(root: root, localEnabled: true)
        store.startNativeActivityNotifications()
        try await waitUntil { store.localHealth == .ready }
        XCTAssertNil(store.snapshot, "An absent completion is not live evidence")
        await store.recheckLocalDiscovery()
        XCTAssertNil(store.snapshot)
        try append(tokenRecord(150, last: 50), to: file)
        try await waitUntil { store.currentTurnTokenUsage == 150 }
        XCTAssertEqual(store.lifecycle, .active)
        XCTAssertNotEqual(store.presentation, .hidden)
        try append(["type": "event_msg", "payload": ["type": "task_complete", "turn_id": "old-turn"]], to: file)
        try await waitUntil { store.lifecycle == .completed }
        await store.stop()
    }

    func testLateCompletionAndInvalidTimestampsNeverWakeHistoricalTask() async throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try writeRollout(root, id: "old", lines: [startRecord("old-turn", timestamp: "not-a-date")])
        let store = makeStore(root: root, localEnabled: true)
        store.startNativeActivityNotifications()
        try await waitUntil { store.localHealth == .ready }
        XCTAssertNil(store.snapshot)
        try append(["type": "event_msg", "payload": ["type": "task_complete", "turn_id": "old-turn"]], to: file)
        try await waitUntil { store.localHealth == .receiving }
        XCTAssertNil(store.snapshot)
        XCTAssertEqual(store.presentation, .hidden)
        await store.stop()
    }

    func testNonemptyStaleDatabaseDoesNotMaskNewTaskAndRecheckDoesNotReplayIt() async throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let oldFile = try writeRollout(root, id: "old", lines: [])
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(root.appendingPathComponent("state_5.sqlite").path, &database), SQLITE_OK)
        let escaped = oldFile.path.replacingOccurrences(of: "'", with: "''")
        let sql = "CREATE TABLE threads(id TEXT, rollout_path TEXT, cwd TEXT, archived INTEGER, updated_at_ms INTEGER); INSERT INTO threads VALUES('old','\(escaped)','/private/test',0,1);"
        XCTAssertEqual(sqlite3_exec(database, sql, nil, nil, nil), SQLITE_OK)
        sqlite3_close(database)
        let databaseBefore = try Data(contentsOf: root.appendingPathComponent("state_5.sqlite"))
        let store = makeStore(root: root, localEnabled: true)
        store.startNativeActivityNotifications()
        try await waitUntil { store.localHealth == .ready }
        try writeRollout(root, id: "new", lines: [startRecord("new-turn", timestamp: timestamp())])
        try await waitUntil { store.snapshot?.sessionHash == CodexActivityPrivacy.hashIdentifier("new") }
        XCTAssertEqual(store.lifecycle, .active)
        let before = store.snapshot
        await store.recheckLocalDiscovery()
        XCTAssertEqual(store.snapshot, before)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("state_5.sqlite")), databaseBefore)
        await store.stop()
    }

    func testUnreadableDirectoryAndFileRecoverAfterReadOnlyRecheck() async throws {
        let root = try fixtureRoot()
        let sessions = root.appendingPathComponent("sessions")
        let file = try writeRollout(root, id: "quiet", lines: [])
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: sessions.path)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: sessions.path)
        let store = makeStore(root: root, localEnabled: true)
        store.startNativeActivityNotifications()
        try await waitUntil { store.localHealth == .unreadable }
        XCTAssertNil(store.snapshot)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: sessions.path)
        await store.recheckLocalDiscovery()
        try await waitUntil { store.localHealth == .ready }
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        await store.recheckLocalDiscovery()
        try await waitUntil { store.localHealth == .unreadable }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        await store.recheckLocalDiscovery()
        try await waitUntil { store.localHealth == .ready }
        XCTAssertNil(store.snapshot)
        await store.stop()
    }

    func testIncompatibleMetadataIsExplicitAndPartialMetadataCanRecover() async throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("sessions/unknown.jsonl")
        try Data("{\"type\":\"session_meta\",\"payload\":{\"future_id\":\"unknown\"}}\n".utf8).write(to: file)
        let store = makeStore(root: root, localEnabled: true)
        store.startNativeActivityNotifications()
        try await waitUntil { store.localHealth == .unsupported }
        try Data("{\"type\":\"session_meta\"".utf8).write(to: file)
        await store.recheckLocalDiscovery()
        try await waitUntil { store.localHealth == .waitingForRecords }
        try writeRollout(root, id: "unknown", lines: [])
        await store.recheckLocalDiscovery()
        try await waitUntil { store.localHealth == .ready }
        XCTAssertNil(store.snapshot)
        await store.stop()
    }

    func testHealthCopyRemainsSeparateFromEveryHookState() {
        for hook in hookStates {
            for health in [CodexLocalActivityHealth.checking, .waitingForRecords, .ready,
                           .receiving, .unreadable, .unsupported, .disabled] {
                let model = CodexActivityConnectionPresentation(connection: .init(localHealth: health),
                    hookStatus: hook)
                for language in [AppPreferences.Language.simplifiedChinese, .english] {
                    let copy = AppCopy(language: language)
                    XCTAssertFalse(model.automaticStatusTitle(copy).isEmpty)
                    XCTAssertFalse(model.automaticSubtitle(copy).isEmpty)
                }
                XCTAssertEqual(model.hookStatus, hook)
            }
        }
    }

    func testHookInspectionIsReadOnlyAndUntrustedInstallationCanBeRemoved() async throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let hooks = root.appendingPathComponent("hooks.json")
        let helper = root.appendingPathComponent("QuotaViewActivityHook")
        let other = ["type": "command", "command": "/usr/bin/true"]
        let own = ["type": "command", "command": helper.path + " old-installation"]
        try JSONSerialization.data(withJSONObject: ["hooks": ["UserPromptSubmit": [["hooks": [other, own]]]]]).write(to: hooks)
        let installer = CodexActivityHookInstaller(socketURL: root.appendingPathComponent("test.sock"),
            authenticationToken: "isolated-test", hooksURL: hooks, helperURL: helper,
            installedHelperURL: helper)
        let domain = "QuotaViewFirstConnection-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let gate = ClassificationGate(entered: expectation(description: "Hook classification in flight"))
        let store = makeStore(root: root, localEnabled: false, sessionKindResolver: { _ in await gate.wait() })
        let runtime = CodexActivityRuntime(preferences: AppPreferences(defaults: defaults),
            defaults: defaults, hookInstaller: installer,
            hookEnvironmentInspector: .init(executablePath: nil), activityStore: store)
        let original = try Data(contentsOf: hooks)
        runtime.refreshConnectionStatus()
        try await waitUntil { runtime.hasCompatibilityHook && runtime.hooksFeatureStatus == .unavailable }
        XCTAssertEqual(try Data(contentsOf: hooks), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: helper.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("config.toml").path))
        let inFlight = Task { await runtime.receiveCompatibilityActivity(.init(source: .liveSocket,
            activity: .init(event: .userPromptSubmit, sessionHash: "in-flight-hook",
                turnHash: "turn", source: .hook))) }
        await fulfillment(of: [gate.entered], timeout: 2)
        runtime.disableCompatibilityHook()
        try await waitUntil { !runtime.isConfiguring && !runtime.hasCompatibilityHook }
        XCTAssertFalse(try installer.hasQuotaViewHandlers())
        await gate.release()
        let inFlightAcknowledged = await inFlight.value
        XCTAssertTrue(inFlightAcknowledged)
        XCTAssertNil(store.snapshot, "An event classified before removal cannot be admitted afterward")
        let late = CodexActivityDelivery(source: .liveSocket, activity: .init(
            event: .userPromptSubmit, sessionHash: "late-hook", turnHash: "late-turn", source: .hook
        ))
        let acknowledged = await runtime.receiveCompatibilityActivity(late)
        XCTAssertTrue(acknowledged, "Removed Hook events must not stay in the retry queue")
        XCTAssertNil(runtime.store.snapshot, "Cached handlers cannot reactivate a removed Hook")
        let remaining = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: hooks)) as? [String: Any])
        let groups = try XCTUnwrap((remaining["hooks"] as? [String: Any])?["UserPromptSubmit"] as? [[String: Any]])
        let commands = groups.flatMap { $0["hooks"] as? [[String: Any]] ?? [] }.compactMap { $0["command"] as? String }
        XCTAssertEqual(commands, ["/usr/bin/true"])
        await runtime.stop()
    }

    func testCustomDirectoryValidationPersistenceAndSourceReset() async throws {
        let first = try fixtureRoot(), second = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: first); try? FileManager.default.removeItem(at: second) }
        try writeRollout(first, id: "first", lines: [startRecord("old", timestamp: "2020-01-01T00:00:00Z")])
        try writeRollout(second, id: "second", lines: [])
        let domain = "QuotaViewDirectory-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let runtime = CodexActivityRuntime(preferences: AppPreferences(defaults: defaults), defaults: defaults, defaultDataDirectory: first)
        let initial = runtime.dataDirectoryURL
        runtime.selectDataDirectory(first.appendingPathComponent("missing"))
        XCTAssertTrue(runtime.directorySelectionFailed)
        XCTAssertEqual(runtime.dataDirectoryURL, initial)
        runtime.selectDataDirectory(first)
        try await waitUntil { !runtime.isChangingDataDirectory && runtime.localHealth == .ready }
        XCTAssertNil(runtime.store.snapshot)
        runtime.selectDataDirectory(second)
        try await waitUntil { !runtime.isChangingDataDirectory && runtime.localHealth == .ready }
        XCTAssertEqual(runtime.dataDirectoryURL.path, second.path)
        XCTAssertEqual(defaults.string(forKey: "codexActivity.localDataDirectory"), second.path)
        XCTAssertNil(runtime.store.snapshot)
        await runtime.stop()
        let restored = CodexActivityRuntime(preferences: AppPreferences(defaults: defaults), defaults: defaults)
        XCTAssertEqual(restored.dataDirectoryURL.path, second.path)
        XCTAssertTrue(restored.usesCustomDataDirectory)
        await restored.stop()
        runtime.selectDataDirectory(nil)
        try await waitUntil { !runtime.isChangingDataDirectory && runtime.localHealth == .ready }
        XCTAssertEqual(runtime.dataDirectoryURL.path, first.path)
        XCTAssertFalse(runtime.usesCustomDataDirectory)
        XCTAssertNil(runtime.store.snapshot)
        await runtime.stop()
    }

    func testBoundedDiscoveryContinuesBeyondFirstPage() async throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        // More files than one traversal batch; ordinary unknown files must not starve tasks.
        for index in 0..<1100 {
            try Data("{}\n".utf8).write(to: root.appendingPathComponent("sessions/ignored-\(index).jsonl"))
        }
        let file = try writeRollout(root, id: "user", lines: [startRecord("turn", timestamp: "2020-01-01T00:00:00Z")])
        let store = makeStore(root: root, localEnabled: true)
        store.startNativeActivityNotifications()
        try await waitUntil { store.localHealth == .ready }
        XCTAssertNil(store.snapshot)
        try append(tokenRecord(20, last: 20), to: file)
        try await waitUntil { store.currentTurnTokenUsage == 20 }
        await store.recheckLocalDiscovery()
        XCTAssertEqual(store.currentTurnTokenUsage, 20)
        await store.stop()
    }

    func testMergedDirectoryDiscoveryDoesNotBypassDatabaseInternalTaskClassification() async throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("sessions/internal.jsonl")
        try Data("{\"type\":\"session_meta\",\"payload\":{\"id\":\"internal\"}}\n".utf8).write(to: file)
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(root.appendingPathComponent("state_5.sqlite").path, &database), SQLITE_OK)
        let path = file.path.replacingOccurrences(of: "'", with: "''")
        let sql = "CREATE TABLE threads(id TEXT,rollout_path TEXT,cwd TEXT,source TEXT,thread_source TEXT,archived INTEGER,updated_at_ms INTEGER); INSERT INTO threads VALUES('internal','\(path)',NULL,'vscode','guardian_review',0,1);"
        XCTAssertEqual(sqlite3_exec(database, sql, nil, nil, nil), SQLITE_OK)
        sqlite3_close(database)
        let store = makeStore(root: root, localEnabled: true)
        store.startNativeActivityNotifications()
        try await waitUntil { store.localHealth == .waitingForRecords }
        try append(startRecord("internal-turn", timestamp: timestamp()), to: file)
        try append(tokenRecord(100, last: 100), to: file)
        await store.recheckLocalDiscovery()
        XCTAssertEqual(store.localHealth, .waitingForRecords)
        XCTAssertNil(store.snapshot)
        await store.stop()
    }

    func testDatabaseInternalClassificationSurvivesAFullCandidatePage() async throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let internalFile = try writeRollout(root, id: "internal", lines: [])
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(root.appendingPathComponent("state_5.sqlite").path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, "CREATE TABLE threads(id TEXT,rollout_path TEXT,cwd TEXT,source TEXT,thread_source TEXT,archived INTEGER,updated_at_ms INTEGER)", nil, nil, nil), SQLITE_OK)
        for index in 0..<30 {
            let id = "user-\(index)"
            let file = try writeRollout(root, id: id, lines: [])
            let path = file.path.replacingOccurrences(of: "'", with: "''")
            XCTAssertEqual(sqlite3_exec(db, "INSERT INTO threads VALUES('\(id)','\(path)',NULL,'cli','user',0,2)", nil, nil, nil), SQLITE_OK)
        }
        let path = internalFile.path.replacingOccurrences(of: "'", with: "''")
        XCTAssertEqual(sqlite3_exec(db, "INSERT INTO threads VALUES('internal','\(path)',NULL,'cli','guardian_review',0,1)", nil, nil, nil), SQLITE_OK)
        try append(startRecord("internal-turn", timestamp: timestamp()), to: internalFile)
        let discovery = CodexLocalRolloutDiscovery(codexHomeURL: root, maximumCandidateCount: 24, fileManager: .default)
        let candidates = discovery.recentCandidates()
        XCTAssertFalse(candidates.contains { $0.sessionHash == CodexActivityPrivacy.hashIdentifier("internal") },
            "Directory merging must keep internal exclusions beyond the first candidate page")
    }

    func testAuditAtomicReplacementCannotReuseThePreviousTurnDecoder() async throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try writeRollout(root, id: "user", lines: [startRecord("old-turn", timestamp: "2020-01-01T00:00:00Z")])
        let store = makeStore(root: root, localEnabled: true)
        store.startNativeActivityNotifications()
        try await waitUntil { store.localHealth == .ready }
        let replacement = try writeRollout(root, id: "replacement", lines: [
            startRecord("new-turn", timestamp: "2021-01-01T00:00:00Z"),
            ["type": "optional", "payload": ["padding": String(repeating: "x", count: 4096)]],
            tokenRecord(200, last: 200)
        ])
        // Preserve the same session identity while atomically replacing its inode.
        let text = String(decoding: try Data(contentsOf: replacement), as: UTF8.self)
            .replacingOccurrences(of: "replacement", with: "user")
        try FileManager.default.removeItem(at: replacement)
        try Data(text.utf8).write(to: file, options: .atomic)
        await store.recheckLocalDiscovery()
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertNil(store.snapshot, "A replacement's historical bytes are not fresh activity")
        try append(tokenRecord(250, last: 50), to: file)
        try await waitUntil { store.currentTurnTokenUsage == 250 }
        XCTAssertEqual(store.snapshot?.taskIdentity?.turnHash, CodexActivityPrivacy.hashIdentifier("new-turn"))
        await store.stop()
    }

    func testAuditReplacingHealthSubscriberPublishesCurrentHealth() async throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeRollout(root, id: "quiet", lines: [])
        let client = CodexLocalRolloutActivityClient(configuration: .init(isEnabled: true, codexHomeURL: root))
        let first = expectation(description: "initial ready")
        await client.start(handler: { _, _ in }, connectionStateHandler: { _ in },
            healthHandler: { if $0 == .ready { first.fulfill() } })
        await fulfillment(of: [first], timeout: 2)
        let second = expectation(description: "new subscriber receives current ready")
        await client.start(handler: { _, _ in }, connectionStateHandler: { _ in },
            healthHandler: { if $0 == .ready { second.fulfill() } })
        await fulfillment(of: [second], timeout: 1)
        await client.stop()
    }

    func testAuditFreshTokenConfirmationCanSelectARecoveredTask() async throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try writeRollout(root, id: "old", lines: [startRecord("turn", timestamp: "2020-01-01T00:00:00Z")])
        let store = makeStore(root: root, localEnabled: true)
        store.startNativeActivityNotifications()
        try await waitUntil { store.localHealth == .ready }
        store.receive(.init(event: .userPromptSubmit, sessionHash: "recent", turnHash: "recent-turn", sessionKind: .user, source: .appServer))
        store.receive(.init(event: .stop, sessionHash: "recent", turnHash: "recent-turn", sessionKind: .user, source: .appServer, turnCompletionStatus: .completed))
        try append(tokenRecord(30, last: 30), to: file)
        try await waitUntil { store.localHealth == .receiving }
        XCTAssertEqual(store.snapshot?.sessionHash, CodexActivityPrivacy.hashIdentifier("old"))
        XCTAssertEqual(store.currentTurnTokenUsage, 30)
        XCTAssertEqual(store.lifecycle, .active)
        await store.stop()
    }

    func testRecoveredTaskKnownToSharedServiceKeepsItsTurnTokens() async throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try writeRollout(root, id: "old", lines: [startRecord("turn", timestamp: "2020-01-01T00:00:00Z")])
        let store = makeStore(root: root, localEnabled: true)
        store.startNativeActivityNotifications()
        try await waitUntil { store.localHealth == .ready }
        let session = CodexActivityPrivacy.hashIdentifier("old"), turn = CodexActivityPrivacy.hashIdentifier("turn")
        store.receive(.init(event: .userPromptSubmit, sessionHash: session, turnHash: turn, sessionKind: .user, source: .appServer))
        store.receive(CodexActivityTokenUsageUpdate(sessionHash: session, turnHash: turn,
            cumulativeTotalTokens: 100, lastReportedTotalTokens: 100, directTurnTotalTokens: 100))
        store.receive(.init(event: .userPromptSubmit, sessionHash: "recent", turnHash: "other", sessionKind: .user, source: .appServer))
        store.receive(.init(event: .stop, sessionHash: "recent", turnHash: "other", sessionKind: .user, source: .appServer, turnCompletionStatus: .completed))
        try append(tokenRecord(120, last: 20), to: file)
        try await waitUntil { store.localHealth == .receiving }
        XCTAssertEqual(store.snapshot?.sessionHash, session)
        XCTAssertEqual(store.currentTurnTokenUsage, 100, "Legacy confirmation must preserve direct turn usage")
        XCTAssertEqual(store.lifecycle, .active)
        await store.stop()
    }

    func testSharedServiceAvailabilitySurvivesMissingOrUnreadableLocalRecords() {
        let copy = AppCopy(language: .simplifiedChinese)
        for health in [CodexLocalActivityHealth.waitingForRecords, .unreadable, .unsupported, .disabled] {
            let connection = CodexAutomaticActivityConnection(localHealth: health, sharedState: .connected)
            let presentation = CodexActivityConnectionPresentation(connection: connection, hookStatus: .awaitingTrust)
            XCTAssertEqual(connection.nativeState, .connected)
            XCTAssertEqual(presentation.automaticStatusTitle(copy), "服务已连接")
            XCTAssertFalse(presentation.automaticSubtitle(copy).contains("请在 Codex 中运行一条任务"))
            if health == .unreadable { XCTAssertTrue(presentation.automaticSubtitle(copy).contains("读取权限")) }
            XCTAssertFalse(presentation.showsHookSetupIsland(explicitlyRequested: true))
        }
    }

    func testStopRejectsClassificationAlreadyInFlight() async throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = ClassificationGate(entered: expectation(description: "classification in flight"))
        let store = makeStore(root: root, localEnabled: false, sessionKindResolver: { _ in await gate.wait() })
        let delivery = Task { await store.receiveClassified(.init(source: .liveSocket,
            activity: .init(event: .userPromptSubmit, sessionHash: "old", turnHash: "turn", source: .appServer))) }
        await fulfillment(of: [gate.entered], timeout: 2)
        await store.stop()
        await gate.release()
        await delivery.value
        XCTAssertNil(store.snapshot)
        XCTAssertEqual(store.presentation, .hidden)
        XCTAssertEqual(store.nativeConnectionState, .disabled)
    }

    func testDirectoryChangeRejectsPreviousDirectoryClassification() async throws {
        let first = try fixtureRoot(), second = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: first); try? FileManager.default.removeItem(at: second) }
        try writeRollout(second, id: "quiet", lines: [])
        let gate = ClassificationGate(entered: expectation(description: "old directory classification"))
        let store = makeStore(root: first, localEnabled: true, sessionKindResolver: { _ in await gate.wait() })
        let delivery = Task { await store.receiveClassified(.init(source: .liveSocket,
            activity: .init(event: .userPromptSubmit, sessionHash: "old-root", turnHash: "turn", source: .localRollout))) }
        await fulfillment(of: [gate.entered], timeout: 2)
        let changed = await store.changeDataDirectory(second)
        XCTAssertTrue(changed)
        try await waitUntil { store.localHealth == .ready }
        await gate.release()
        await delivery.value
        XCTAssertNil(store.snapshot)
        XCTAssertEqual(store.presentation, .hidden)
        await store.stop()
    }

    func testRecoveryCannotCrossTurnsAndOnlyEvictsTheOldestPendingSession() {
        var recovery = CodexLocalActivityRecovery(capacity: 2)
        func context(_ session: String, _ turn: String) -> CodexLocalRolloutDecodedRecord {
            .init(eventID: nil, update: .activity(.init(event: .userPromptSubmit,
                sessionHash: session, turnHash: turn, source: .localRollout)), requiresLiveConfirmation: true)
        }
        func token(_ session: String, _ turn: String) -> CodexLocalRolloutDecodedRecord {
            .init(eventID: nil, update: .tokenUsage(.init(sessionHash: session, turnHash: turn,
                cumulativeTotalTokens: 20, lastReportedTotalTokens: 20)))
        }
        XCTAssertNil(recovery.project(context("a", "one")))
        XCTAssertTrue(recovery.project(token("a", "two"))!.context.isEmpty)
        for session in ["a", "b", "c"] { XCTAssertNil(recovery.project(context(session, "one"))) }
        XCTAssertTrue(recovery.project(token("a", "one"))!.context.isEmpty)
        XCTAssertEqual(recovery.project(token("b", "one"))!.context.count, 1)
        XCTAssertEqual(recovery.project(token("c", "one"))!.context.count, 1)
    }

    private func fixtureRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("QuotaViewOnboarding-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        return root
    }

    private func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    private func startRecord(_ turn: String, timestamp: String) -> [String: Any] {
        ["timestamp": timestamp, "type": "event_msg", "payload": ["type": "task_started", "turn_id": turn]]
    }

    private func tokenRecord(_ total: Int, last: Int) -> [String: Any] {
        ["type": "event_msg", "payload": ["type": "token_count", "info": ["total_token_usage": ["total_tokens": total], "last_token_usage": ["total_tokens": last]]]]
    }

    @discardableResult
    private func writeRollout(_ root: URL, id: String, lines: [[String: Any]]) throws -> URL {
        let file = root.appendingPathComponent("sessions/\(id).jsonl")
        var data = Data()
        for record in [["type": "session_meta", "payload": ["id": id, "source": "cli"]]] + lines {
            data.append(try JSONSerialization.data(withJSONObject: record)); data.append(10)
        }
        try data.write(to: file)
        return file
    }

    private func append(_ record: [String: Any], to file: URL) throws {
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        var data = try JSONSerialization.data(withJSONObject: record); data.append(10)
        try handle.write(contentsOf: data)
    }

    private func makeStore(root: URL, localEnabled: Bool,
                           sessionKindResolver: (@Sendable (CodexActivityEvent) async -> CodexActivitySessionKind)? = nil) -> CodexActivityStore {
        CodexActivityStore(
            titleClient: CodexAppServerClient(executablePath: nil),
            sharedActivityClient: CodexSharedAppServerActivityClient(configuration: .init(
                isEnabled: false, socketURL: root.appendingPathComponent("unused.sock"),
                executablePath: nil
            )),
            localRolloutActivityClient: CodexLocalRolloutActivityClient(configuration: .init(
                isEnabled: localEnabled, codexHomeURL: root,
                pollIntervalSeconds: 0.1, candidateRefreshSeconds: 0.1
            )),
            sessionDirectory: root, sessionKindResolver: sessionKindResolver
        )
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(condition(), "Timed out waiting for automatic task discovery")
    }
}

private actor ClassificationGate {
    nonisolated let entered: XCTestExpectation
    private var continuation: CheckedContinuation<CodexActivitySessionKind, Never>?
    init(entered: XCTestExpectation) { self.entered = entered }
    func wait() async -> CodexActivitySessionKind {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            entered.fulfill()
        }
    }
    func release() { continuation?.resume(returning: .user); continuation = nil }
}
