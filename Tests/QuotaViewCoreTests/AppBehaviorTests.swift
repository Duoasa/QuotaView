import Foundation
import XCTest
@testable import QuotaView
@testable import QuotaViewCore

final class AppBehaviorTests: XCTestCase {
    func testCodexActivityProductionInactivityTiming() {
        XCTAssertEqual(CodexActivityStore.compactDelay, 20)
        XCTAssertEqual(
            CodexActivityStore.compactDelay
                + CodexActivityStore.hiddenDelayAfterCompact,
            120
        )
    }

    func testCodexActivityConnectionRequiresRealPromptSubmission() {
        var evidence = CodexActivityConnectionEvidence(
            observedInstallationID: nil,
            connectedInstallationID: nil
        )

        evidence.record(
            event: .sessionStart,
            installationID: "installation"
        )
        XCTAssertEqual(
            evidence.observedInstallationID,
            "installation"
        )
        XCTAssertNil(evidence.connectedInstallationID)
        XCTAssertEqual(
            evidence.status(for: "installation"),
            .awaitingFirstEvent
        )

        evidence.record(
            event: .preToolUse,
            installationID: "installation"
        )
        XCTAssertNil(evidence.connectedInstallationID)

        evidence.record(
            event: .userPromptSubmit,
            installationID: "installation"
        )
        XCTAssertEqual(
            evidence.connectedInstallationID,
            "installation"
        )
        XCTAssertEqual(
            evidence.status(for: "installation"),
            .connected
        )
        XCTAssertEqual(
            evidence.status(for: "different-installation"),
            .awaitingTrust
        )
    }

    func testCodexActivityRestartRequirementRejectsSetupCLIEvents()
    {
        let requirement = CodexActivityRestartRequirement(
            baselineProcessIdentifier: 140
        )

        XCTAssertFalse(
            requirement.isSatisfied(currentProcessIdentifier: nil)
        )
        XCTAssertFalse(
            requirement.isSatisfied(currentProcessIdentifier: 140)
        )
        XCTAssertTrue(
            requirement.isSatisfied(currentProcessIdentifier: 141)
        )

        let noRunningCodexRequirement =
            CodexActivityRestartRequirement(
                baselineProcessIdentifier: 0
            )
        XCTAssertTrue(
            noRunningCodexRequirement.isSatisfied(
                currentProcessIdentifier: 141
            )
        )
    }

    func testCodexActivitySetupSeparatesTrustRestartAndFirstEvent()
    {
        XCTAssertEqual(
            CodexActivitySetupStatusResolver.resolve(
                evidenceStatus: .awaitingTrust,
                reviewConfirmed: false,
                requiresRestart: true
            ),
            .awaitingTrust
        )
        XCTAssertEqual(
            CodexActivitySetupStatusResolver.resolve(
                evidenceStatus: .awaitingTrust,
                reviewConfirmed: true,
                requiresRestart: true
            ),
            .installedNeedsRestart
        )
        XCTAssertEqual(
            CodexActivitySetupStatusResolver.resolve(
                evidenceStatus: .awaitingTrust,
                reviewConfirmed: true,
                requiresRestart: false
            ),
            .awaitingFirstEvent
        )
        XCTAssertEqual(
            CodexActivitySetupStatusResolver.resolve(
                evidenceStatus: .connected,
                reviewConfirmed: true,
                requiresRestart: false
            ),
            .connected
        )
    }

    func testCodexSecurityReviewLauncherPreparesPrivateCommand()
        throws
    {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(
                "QuotaViewSecurityReviewTests-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? fileManager.removeItem(at: rootURL) }
        try fileManager.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )

        let codexURL = rootURL.appendingPathComponent(
            "Codex CLI With Spaces"
        )
        try Data(
            """
            #!/bin/bash
            sleep 2.5
            if IFS= read -r -t 0 early_command; then
                exit 17
            fi
            printf '› '
            for step in 1 2 3 4 5; do
                printf 'Checking startup list %s\\n' "$step"
                sleep 0.2
            done
            if IFS= read -r -t 0 early_command; then
                exit 18
            fi
            IFS= read -r command
            test "$command" = "/hooks"
            printf '11 hooks need review before they can run.\\n'
            printf 'Press t to trust all; enter to review hooks; esc to close\\n'
            IFS= read -r -n 1 trust_key
            test "$trust_key" = "t" -o "$trust_key" = "T"
            printf 'Press enter to view hooks; esc to close\\n'
            sleep 2
            """.utf8
        ).write(to: codexURL)
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: codexURL.path
        )

        let launcher = CodexSecurityReviewLauncher(
            codexExecutablePath: codexURL.path,
            launcherDirectoryURL: rootURL.appendingPathComponent(
                "Launchers",
                isDirectory: true
            )
        )
        let launcherURL = try launcher.prepareLauncher()
        let expectURL = launcherURL.deletingLastPathComponent()
            .appendingPathComponent("QuotaViewHookReview.exp")
        let launcherContents = try String(
            contentsOf: launcherURL,
            encoding: .utf8
        )
        let expectContents = try String(
            contentsOf: expectURL,
            encoding: .utf8
        )
        let launcherPermissions = try XCTUnwrap(
            try fileManager.attributesOfItem(
                atPath: launcherURL.path
            )[.posixPermissions] as? NSNumber
        )
        let expectPermissions = try XCTUnwrap(
            try fileManager.attributesOfItem(
                atPath: expectURL.path
            )[.posixPermissions] as? NSNumber
        )

        XCTAssertTrue(launcherContents.contains("/usr/bin/expect"))
        XCTAssertTrue(launcherContents.contains(codexURL.path))
        XCTAssertTrue(expectContents.contains(#"send -- "/hooks\r""#))
        XCTAssertTrue(expectContents.contains(#"-re {›}"#))
        XCTAssertTrue(
            expectContents.contains(
                #"set quiet_deadline [expr {[clock milliseconds] + 3000}]"#
            )
        )
        XCTAssertTrue(
            expectContents.contains(
                #"-re {Press t to trust all}"#
            )
        )
        XCTAssertFalse(expectContents.contains("after 1800"))
        XCTAssertEqual(launcherPermissions.intValue & 0o777, 0o700)
        XCTAssertEqual(expectPermissions.intValue & 0o777, 0o700)

        let process = Process()
        let standardInput = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/expect")
        process.arguments = [
            expectURL.path,
            codexURL.path,
            launcher.reviewCompletionURL.path
        ]
        process.standardInput = standardInput
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        standardInput.fileHandleForWriting.write(Data("t".utf8))
        try standardInput.fileHandleForWriting.close()
        process.waitUntilExit()
        XCTAssertEqual(
            process.terminationStatus,
            0,
            "The launcher must enter /hooks through Codex's own PTY."
        )
        XCTAssertEqual(
            try String(
                contentsOf: launcher.reviewCompletionURL,
                encoding: .utf8
            ).trimmingCharacters(in: .whitespacesAndNewlines),
            "confirmed"
        )
        let completionPermissions = try XCTUnwrap(
            try fileManager.attributesOfItem(
                atPath: launcher.reviewCompletionURL.path
            )[.posixPermissions] as? NSNumber
        )
        XCTAssertEqual(
            completionPermissions.intValue & 0o777,
            0o600
        )
    }

    @MainActor
    func testCodexActivityCompletesThenCompactsAndHides() async {
        let store = CodexActivityStore(
            titleClient: CodexAppServerClient(executablePath: nil),
            compactDelay: 0.02,
            hiddenDelayAfterCompact: 0.20
        )
        store.receive(
            CodexActivityEvent(
                event: .stop,
                sessionHash: "session"
            )
        )
        XCTAssertEqual(store.presentation, .expanded)
        XCTAssertEqual(store.snapshot?.state, .completed)

        for _ in 0..<100 where store.presentation != .compact {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(store.presentation, .compact)

        for _ in 0..<100 where store.presentation != .hidden {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(store.presentation, .hidden)
        await store.stop()
    }

    @MainActor
    func testNewCodexActivityCancelsPendingCompaction() async {
        let store = CodexActivityStore(
            titleClient: CodexAppServerClient(executablePath: nil),
            compactDelay: 0.02,
            hiddenDelayAfterCompact: 0.02
        )
        store.receive(
            CodexActivityEvent(
                event: .stop,
                sessionHash: "session",
                occurredAt: Date()
            )
        )
        try? await Task.sleep(nanoseconds: 8_000_000)
        store.receive(
            CodexActivityEvent(
                event: .preToolUse,
                sessionHash: "session",
                toolCategory: .fileEdit,
                occurredAt: Date()
            )
        )

        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(store.presentation, .expanded)
        XCTAssertEqual(store.snapshot?.state, .working)
        XCTAssertEqual(store.snapshot?.operationKey, .editingFiles)
        await store.stop()
    }

    @MainActor
    func testOlderActivityCannotOverwriteNewerState() async {
        let store = CodexActivityStore(
            titleClient: CodexAppServerClient(executablePath: nil),
            compactDelay: 0.01,
            hiddenDelayAfterCompact: 0.01
        )
        let now = Date()
        store.receive(
            CodexActivityEvent(
                event: .preToolUse,
                sessionHash: "session",
                toolCategory: .fileEdit,
                occurredAt: now
            )
        )
        store.receive(
            CodexActivityEvent(
                event: .stop,
                sessionHash: "session",
                occurredAt: now.addingTimeInterval(-1)
            )
        )

        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(store.snapshot?.state, .working)
        XCTAssertEqual(store.presentation, .expanded)
        await store.stop()
    }

    @MainActor
    func testActivityOlderThanSessionEndCannotReopenIsland() async {
        let store = CodexActivityStore(
            titleClient: CodexAppServerClient(executablePath: nil)
        )
        let endedAt = Date()
        store.receive(
            CodexActivityEvent(
                event: .preToolUse,
                sessionHash: "session",
                occurredAt: endedAt.addingTimeInterval(-2)
            )
        )
        store.receive(
            CodexActivityEvent(
                event: .sessionEnd,
                sessionHash: "session",
                occurredAt: endedAt
            )
        )
        store.receive(
            CodexActivityEvent(
                event: .postToolUse,
                sessionHash: "session",
                occurredAt: endedAt.addingTimeInterval(-1)
            )
        )

        XCTAssertEqual(store.presentation, .hidden)
        XCTAssertNil(store.snapshot)
        XCTAssertTrue(store.tasks.isEmpty)
        await store.stop()
    }

    @MainActor
    func testCodexActivityKeepsInterleavedSessionsIndependent() async {
        let store = CodexActivityStore(
            titleClient: CodexAppServerClient(executablePath: nil),
            compactDelay: 0.02,
            hiddenDelayAfterCompact: 0.20
        )
        let now = Date()
        store.receive(
            CodexActivityEvent(
                event: .stop,
                sessionHash: "completed-session",
                occurredAt: now
            )
        )
        store.receive(
            CodexActivityEvent(
                event: .preToolUse,
                sessionHash: "working-session",
                toolCategory: .fileEdit,
                occurredAt: now.addingTimeInterval(1)
            )
        )

        for _ in 0..<200 where store.tasks.first(where: {
            $0.sessionHash == "completed-session"
        })?.presentation != .compact {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(store.tasks.count, 2)
        XCTAssertEqual(
            store.tasks.first {
                $0.sessionHash == "completed-session"
            }?.presentation,
            .compact
        )
        XCTAssertEqual(
            store.tasks.first {
                $0.sessionHash == "working-session"
            }?.presentation,
            .expanded
        )
        XCTAssertEqual(store.presentation, .expanded)
        XCTAssertEqual(store.primarySessionHash, "working-session")
        await store.stop()
    }

    @MainActor
    func testSessionEndRemovesOnlyItsOwnTask() async {
        let store = CodexActivityStore(
            titleClient: CodexAppServerClient(executablePath: nil)
        )
        let now = Date()
        for sessionHash in ["first", "second"] {
            store.receive(
                CodexActivityEvent(
                    event: .preToolUse,
                    sessionHash: sessionHash,
                    occurredAt: now
                )
            )
        }

        store.receive(
            CodexActivityEvent(
                event: .sessionEnd,
                sessionHash: "first",
                occurredAt: now.addingTimeInterval(1)
            )
        )

        XCTAssertEqual(store.tasks.map(\.sessionHash), ["second"])
        XCTAssertEqual(store.primarySessionHash, "second")
        XCTAssertEqual(store.presentation, .expanded)
        await store.stop()
    }

    @MainActor
    func testFocusedTaskDoesNotYieldToBackgroundAttention() async {
        let store = CodexActivityStore(
            titleClient: CodexAppServerClient(executablePath: nil)
        )
        let now = Date()
        store.receive(
            CodexActivityEvent(
                event: .preToolUse,
                sessionHash: "focused",
                occurredAt: now
            )
        )
        store.receive(
            CodexActivityEvent(
                event: .preToolUse,
                sessionHash: "background",
                occurredAt: now.addingTimeInterval(1)
            )
        )
        store.focusTask(sessionHash: "focused")
        store.receive(
            CodexActivityEvent(
                event: .permissionRequest,
                sessionHash: "background",
                occurredAt: now.addingTimeInterval(2)
            )
        )

        XCTAssertEqual(store.primarySessionHash, "focused")
        XCTAssertEqual(
            store.tasks.first {
                $0.sessionHash == "background"
            }?.snapshot.state,
            .awaitingConfirmation
        )
        await store.stop()
    }

    @MainActor
    func testAutomaticFallbackPrefersAttentionThenRecentActivity() async {
        let store = CodexActivityStore(
            titleClient: CodexAppServerClient(executablePath: nil)
        )
        let now = Date()
        store.receive(
            CodexActivityEvent(
                event: .preToolUse,
                sessionHash: "first",
                occurredAt: now
            )
        )
        store.receive(
            CodexActivityEvent(
                event: .postToolUse,
                sessionHash: "second",
                occurredAt: now.addingTimeInterval(1)
            )
        )
        XCTAssertEqual(store.primarySessionHash, "second")

        store.receive(
            CodexActivityEvent(
                event: .permissionRequest,
                sessionHash: "first",
                occurredAt: now.addingTimeInterval(2)
            )
        )
        XCTAssertEqual(store.primarySessionHash, "first")
        await store.stop()
    }

    @MainActor
    func testAllCompletedTasksCompactAsOneCluster() async {
        let store = CodexActivityStore(
            titleClient: CodexAppServerClient(executablePath: nil),
            compactDelay: 0.02,
            hiddenDelayAfterCompact: 0.20
        )
        for sessionHash in ["first", "second"] {
            store.receive(
                CodexActivityEvent(
                    event: .stop,
                    sessionHash: sessionHash
                )
            )
        }

        for _ in 0..<100 where store.presentation != .compact {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(store.presentation, .compact)
        XCTAssertTrue(store.tasks.allSatisfy {
            $0.presentation == .compact
        })

        store.expandCompactDetail()
        XCTAssertEqual(store.presentation, .expanded)
        await store.stop()
    }

    func testProductionTaskRailUsesContiguousThreeTaskWindow() {
        let tasks = (0..<8).map { index in
            CodexActivityRenderState(
                sessionHash: "session-\(index)",
                visualState: .working,
                windowTitle: "Task \(index)",
                statusTitle: "Working",
                operation: "Running",
                accessibilityLabel: "Task \(index), Working"
            )
        }

        XCTAssertEqual(
            codexActivityRailWindowStart(
                tasks: tasks,
                primarySessionHash: "session-0"
            ),
            0
        )
        XCTAssertEqual(
            codexActivityRailWindowStart(
                tasks: tasks,
                primarySessionHash: "session-3"
            ),
            1
        )
        XCTAssertEqual(
            codexActivityRailWindowStart(
                tasks: tasks,
                primarySessionHash: "session-7"
            ),
            5
        )
    }

    func testFocusedTaskReaderIsBoundedAndReadOnly() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot
            .appendingPathComponent("Sources/QuotaView")
            .appendingPathComponent("CodexFocusedTaskTitleReader.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("maximumTraversalDepth"))
        XCTAssertTrue(source.contains("maximumVisitedElements"))
        XCTAssertTrue(source.contains("kAXTitleAttribute"))
        XCTAssertTrue(source.contains("kAXButtonRole"))
        XCTAssertFalse(source.contains("AXUIElementPerformAction"))
        XCTAssertFalse(source.contains("kAXValueAttribute"))
        XCTAssertFalse(source.contains("CGEventPost"))
        XCTAssertFalse(source.contains("kAXPressAction"))
    }

    func testCodexActivityHookInstallerPreservesExistingHooks() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(
                "QuotaViewHookInstallerTests-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? fileManager.removeItem(at: rootURL) }
        try fileManager.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )

        let hooksURL = rootURL.appendingPathComponent("hooks.json")
        let helperURL = rootURL.appendingPathComponent(
            "BundledQuotaViewActivityHook"
        )
        let installedHelperURL = rootURL
            .appendingPathComponent("Application Support")
            .appendingPathComponent("QuotaViewActivityHook")
        try fileManager.createDirectory(
            at: installedHelperURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: helperURL)
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: helperURL.path
        )

        let existingRoot: [String: Any] = [
            "description": "Existing hooks",
            "hooks": [
                "PostToolUse": [[
                    "matcher": "Bash",
                    "hooks": [[
                        "type": "command",
                        "command": "/usr/bin/true"
                    ]]
                ]]
            ]
        ]
        try JSONSerialization.data(
            withJSONObject: existingRoot,
            options: [.prettyPrinted]
        ).write(to: hooksURL)

        let installer = CodexActivityHookInstaller(
            socketURL: rootURL.appendingPathComponent(
                "Activity Socket.sock"
            ),
            authenticationToken: "token'with-quote",
            hooksURL: hooksURL,
            helperURL: helperURL,
            installedHelperURL: installedHelperURL
        )
        let firstInstallation = try installer.install()
        let secondInstallation = try installer.install()
        XCTAssertTrue(firstInstallation.hookDefinitionChanged)
        XCTAssertFalse(secondInstallation.hookDefinitionChanged)
        XCTAssertTrue(try installer.isInstalled())
        XCTAssertEqual(
            try Data(contentsOf: installedHelperURL),
            try Data(contentsOf: helperURL)
        )

        var installedRoot = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: hooksURL)
            ) as? [String: Any]
        )
        XCTAssertEqual(
            installedRoot["description"] as? String,
            "Existing hooks"
        )
        let installedHooks = try XCTUnwrap(
            installedRoot["hooks"] as? [String: Any]
        )
        for event in CodexActivityHookEvent.allCases {
            let groups = try XCTUnwrap(
                installedHooks[event.rawValue] as? [[String: Any]]
            )
            let commands = groups.flatMap { group in
                (group["hooks"] as? [[String: Any]] ?? [])
                    .compactMap { $0["command"] as? String }
            }
            XCTAssertEqual(
                commands.filter {
                    $0.contains("QuotaViewActivityHook")
                }.count,
                1
            )
            XCTAssertTrue(
                commands.contains {
                    $0.contains(installedHelperURL.path)
                        && !$0.contains(helperURL.path)
                        && $0.contains("--installation-id")
                }
            )
        }
        let postToolGroups = try XCTUnwrap(
            installedHooks[
                CodexActivityHookEvent.postToolUse.rawValue
            ] as? [[String: Any]]
        )
        XCTAssertTrue(
            postToolGroups.flatMap {
                $0["hooks"] as? [[String: Any]] ?? []
            }.contains {
                $0["command"] as? String == "/usr/bin/true"
            }
        )
        XCTAssertTrue(
            fileManager.fileExists(
                atPath: hooksURL.appendingPathExtension(
                    "quotaview-backup"
                ).path
            )
        )

        try installer.uninstall()
        XCTAssertFalse(try installer.isInstalled())
        XCTAssertFalse(
            fileManager.fileExists(atPath: installedHelperURL.path)
        )
        installedRoot = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: hooksURL)
            ) as? [String: Any]
        )
        let uninstalledHooks = try XCTUnwrap(
            installedRoot["hooks"] as? [String: Any]
        )
        XCTAssertTrue(
            uninstalledHooks.values.allSatisfy { value in
                guard let groups = value as? [[String: Any]] else {
                    return false
                }
                return groups.flatMap {
                    $0["hooks"] as? [[String: Any]] ?? []
                }.allSatisfy {
                    !(($0["command"] as? String) ?? "")
                        .contains("QuotaViewActivityHook")
                }
            }
        )
        XCTAssertTrue(
            (uninstalledHooks["PostToolUse"] as? [[String: Any]] ?? [])
                .flatMap {
                    $0["hooks"] as? [[String: Any]] ?? []
                }
                .contains {
                    $0["command"] as? String == "/usr/bin/true"
                }
        )
    }

    func testCodexEnvironmentInspectorEnablesHooksWhenNeeded()
        throws
    {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(
                "QuotaViewCodexEnvironmentTests-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? fileManager.removeItem(at: rootURL) }
        try fileManager.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )

        let executableURL = rootURL.appendingPathComponent("codex")
        let markerURL = rootURL.appendingPathComponent("hooks-enabled")
        let script = """
        #!/bin/sh
        if [ "$1" = "--version" ]; then
          echo "codex-cli 0.test"
          exit 0
        fi
        if [ "$1" = "features" ] && [ "$2" = "list" ]; then
          if [ -f "\(markerURL.path)" ]; then
            echo "hooks stable true"
          else
            echo "hooks stable false"
          fi
          exit 0
        fi
        if [ "$1" = "features" ] && [ "$2" = "enable" ] && [ "$3" = "hooks" ]; then
          /usr/bin/touch "\(markerURL.path)"
          exit 0
        fi
        exit 1
        """
        try Data(script.utf8).write(to: executableURL)
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: executableURL.path
        )

        let inspector = CodexActivityEnvironmentInspector(
            executablePath: executableURL.path,
            timeout: 2
        )
        let result = try inspector.inspectAndEnableHooksIfNeeded()
        XCTAssertEqual(result.version, "codex-cli 0.test")
        XCTAssertTrue(result.hooksEnabled)
        XCTAssertTrue(result.didEnableHooks)
        XCTAssertTrue(
            fileManager.fileExists(atPath: markerURL.path)
        )
    }

    func testCodexActivityHookInstallerRejectsInvalidHooksShape()
        throws
    {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(
                "QuotaViewInvalidHookTests-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? fileManager.removeItem(at: rootURL) }
        try fileManager.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        let hooksURL = rootURL.appendingPathComponent("hooks.json")
        let helperURL = rootURL.appendingPathComponent(
            "QuotaViewActivityHook"
        )
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: helperURL)
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: helperURL.path
        )
        let original = Data(#"{"hooks":["invalid"]}"#.utf8)
        try original.write(to: hooksURL)

        let installer = CodexActivityHookInstaller(
            socketURL: rootURL.appendingPathComponent("activity.sock"),
            authenticationToken: "token",
            hooksURL: hooksURL,
            helperURL: helperURL
        )
        XCTAssertThrowsError(try installer.install())
        XCTAssertEqual(try Data(contentsOf: hooksURL), original)
    }

    func testCodexActivityFileBridgeAcceptsOnlyAuthenticatedEvents()
        throws
    {
        let fileManager = FileManager.default
        let queueURL = fileManager.temporaryDirectory
            .appendingPathComponent(
                "QuotaViewActivityQueueTests-\(UUID().uuidString)",
                isDirectory: true
            )
        let bridge = CodexActivityFileBridge(
            queueURL: queueURL,
            authenticationToken: "expected-token",
            installationIdentifier: "expected-installation"
        )
        defer {
            bridge.stop()
            try? fileManager.removeItem(at: queueURL)
        }

        let received = expectation(
            description: "Authenticated file event received"
        )
        received.expectedFulfillmentCount = 1
        try bridge.start { event in
            XCTAssertEqual(event.event, .preToolUse)
            XCTAssertEqual(event.sessionHash, "session-hash")
            XCTAssertEqual(event.toolCategory, .fileEdit)
            received.fulfill()
        }

        let event = CodexActivityEvent(
            event: .preToolUse,
            sessionHash: "session-hash",
            toolCategory: .fileEdit,
            occurredAt: Date()
        )
        let invalidEnvelope = CodexActivityBridgeEnvelope(
            authenticationToken: "wrong-token",
            installationIdentifier: "expected-installation",
            activity: event
        )
        let staleInstallationEnvelope = CodexActivityBridgeEnvelope(
            authenticationToken: "expected-token",
            installationIdentifier: "old-installation",
            activity: event
        )
        let validEnvelope = CodexActivityBridgeEnvelope(
            authenticationToken: "expected-token",
            installationIdentifier: "expected-installation",
            activity: event
        )
        try JSONEncoder().encode(invalidEnvelope).write(
            to: queueURL.appendingPathComponent(
                "event-0-invalid.json"
            ),
            options: .atomic
        )
        try JSONEncoder().encode(staleInstallationEnvelope).write(
            to: queueURL.appendingPathComponent(
                "event-1-stale-installation.json"
            ),
            options: .atomic
        )
        try JSONEncoder().encode(validEnvelope).write(
            to: queueURL.appendingPathComponent(
                "event-2-valid.json"
            ),
            options: .atomic
        )

        wait(for: [received], timeout: 1)
    }

    @MainActor
    func testNativePreferenceDefaults() {
        let suiteName = "QuotaViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let preferences = AppPreferences(defaults: defaults)

        XCTAssertTrue(preferences.showStatusIcon)
        XCTAssertTrue(preferences.showRemainingQuota)
        XCTAssertFalse(preferences.showResetCountdown)
        XCTAssertTrue(preferences.showUsageSummary)
        XCTAssertTrue(preferences.showNextReset)
        XCTAssertTrue(preferences.showCreditBalance)
        XCTAssertTrue(preferences.showDailyTokens)
        XCTAssertTrue(preferences.showLifetimeTokens)
        XCTAssertTrue(preferences.showResetAction)
        XCTAssertTrue(preferences.followsSystemAppearance)
        XCTAssertTrue(preferences.followsSystemLanguage)
        XCTAssertEqual(preferences.customAppearance, .dark)
        XCTAssertEqual(preferences.customLanguage, .simplifiedChinese)
        XCTAssertEqual(preferences.glassMode, .clear)
        XCTAssertFalse(preferences.followCurrentCodexTask)
        XCTAssertEqual(
            defaults.string(
                forKey: "preferences.appearance.glassPreset"
            ),
            "clear"
        )
    }

    @MainActor
    func testSavedNativePreferencesAndLegacyGlassMigration() {
        let savedSuiteName = "QuotaViewTests.\(UUID().uuidString)"
        let savedDefaults = UserDefaults(suiteName: savedSuiteName)!
        defer {
            savedDefaults.removePersistentDomain(forName: savedSuiteName)
        }
        savedDefaults.set(
            false,
            forKey: "preferences.appearance.followsSystem"
        )
        savedDefaults.set(
            AppPreferences.AppearanceMode.light.rawValue,
            forKey: "preferences.appearance.custom"
        )
        savedDefaults.set(
            QuotaViewGlassMode.frosted.rawValue,
            forKey: "preferences.appearance.glassPreset"
        )
        savedDefaults.set(
            false,
            forKey: "preferences.language.followsSystem"
        )
        savedDefaults.set(
            true,
            forKey: "preferences.codexActivity.followCurrentTask"
        )
        savedDefaults.set(
            AppPreferences.Language.english.rawValue,
            forKey: "preferences.language.custom"
        )

        let savedPreferences = AppPreferences(defaults: savedDefaults)

        XCTAssertFalse(savedPreferences.followsSystemAppearance)
        XCTAssertEqual(savedPreferences.customAppearance, .light)
        XCTAssertEqual(savedPreferences.glassMode, .frosted)
        XCTAssertFalse(savedPreferences.followsSystemLanguage)
        XCTAssertEqual(savedPreferences.customLanguage, .english)
        XCTAssertTrue(savedPreferences.followCurrentCodexTask)

        let legacySuiteName = "QuotaViewTests.\(UUID().uuidString)"
        let legacyDefaults = UserDefaults(suiteName: legacySuiteName)!
        defer {
            legacyDefaults.removePersistentDomain(forName: legacySuiteName)
        }
        legacyDefaults.set(
            "legacy-ultra-thin",
            forKey: "preferences.appearance.glassPreset"
        )

        let migratedPreferences = AppPreferences(defaults: legacyDefaults)

        XCTAssertEqual(migratedPreferences.glassMode, .clear)
        XCTAssertEqual(
            legacyDefaults.string(
                forKey: "preferences.appearance.glassPreset"
            ),
            "clear"
        )
    }

    @MainActor
    func testWidgetKeepsOptionalUsageDemandForDetailedMetrics() async {
        let suiteName = "QuotaViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults.set(
            false,
            forKey: "preferences.panel.showDailyTokens"
        )
        defaults.set(
            false,
            forKey: "preferences.panel.showLifetimeTokens"
        )
        let preferences = AppPreferences(defaults: defaults)
        let recorder = FetchRequestRecorder()
        let provider = AppStubProvider { request in
            await recorder.record(request)
            return Self.makeFetchResult(resetCredits: nil)
        }
        let store = CodexStatusStore(
            provider: provider,
            preferences: preferences,
            diagnostics: defaults
        )

        await store.refresh()
        let request = await recorder.lastRequest

        XCTAssertNotNil(request)
        XCTAssertTrue(
            request?.capabilities.contains(.currentUsage) ?? false
        )
        XCTAssertTrue(
            request?.capabilities.contains(.historicalUsage) ?? false
        )
        XCTAssertTrue(
            request?.capabilities.contains(.rateWindows) ?? false
        )
        XCTAssertTrue(
            request?.capabilities.contains(.balances) ?? false
        )
        await store.stop()
    }

    @MainActor
    func testDemoResetUsesSimulationBoundary() async {
        let suiteName = "QuotaViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let provider = AppStubProvider { _ in
            Self.makeFetchResult(resetCredits: 2)
        }
        let store = CodexStatusStore(
            provider: provider,
            diagnostics: defaults
        )

        await store.refresh()

        XCTAssertTrue(store.hasAvailableResetCredit)
        XCTAssertEqual(store.operationAvailability, .demoOnly)
        let didSimulate = await store.performDemoReset()
        XCTAssertTrue(didSimulate)
        await store.stop()
    }

    @MainActor
    func testMissingOptionalValuesRemainUnavailable() async {
        let suiteName = "QuotaViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let provider = AppStubProvider { _ in
            Self.makeFetchResult(resetCredits: nil)
        }
        let store = CodexStatusStore(
            provider: provider,
            diagnostics: defaults
        )

        await store.refresh()

        XCTAssertNil(store.snapshot?.availableResetCredits)
        XCTAssertNil(store.snapshot?.creditBalance)
        XCTAssertNil(store.snapshot?.recentDailyTokens)
        XCTAssertNil(store.snapshot?.lifetimeTokens)
        XCTAssertFalse(store.hasAvailableResetCredit)
        await store.stop()
    }

    @MainActor
    func testZeroResetCreditsDoNotExposeDemoAction() async {
        let suiteName = "QuotaViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let provider = AppStubProvider { _ in
            Self.makeFetchResult(resetCredits: 0)
        }
        let store = CodexStatusStore(
            provider: provider,
            diagnostics: defaults
        )

        await store.refresh()

        XCTAssertEqual(store.snapshot?.availableResetCredits, 0)
        XCTAssertFalse(store.hasAvailableResetCredit)
        let didSimulate = await store.performDemoReset()
        XCTAssertFalse(didSimulate)
        await store.stop()
    }

    @MainActor
    func testLatestProviderFailureClearsPresentation() async {
        let suiteName = "QuotaViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let outcomes = AppOutcomeSequence()
        let provider = AppStubProvider { _ in
            if await outcomes.shouldFail() {
                throw ProviderError.unavailable
            }
            return Self.makeFetchResult(resetCredits: 1)
        }
        let store = CodexStatusStore(
            provider: provider,
            diagnostics: defaults
        )

        await store.refresh()
        XCTAssertNotNil(store.snapshot)
        XCTAssertTrue(store.hasCurrentCodexStatus)

        await store.refresh()
        XCTAssertNil(store.snapshot)
        XCTAssertFalse(store.hasCurrentCodexStatus)
        XCTAssertNotNil(store.errorMessage)
        guard case .unavailable = store.providerState else {
            await store.stop()
            return XCTFail("Latest provider failure must be unavailable")
        }
        await store.stop()
    }

    private static func makeFetchResult(
        resetCredits: Int?
    ) -> ProviderFetchResult {
        let capturedAt = Date(timeIntervalSince1970: 1_785_000_000)
        let window = RateWindow(
            id: CodexDomainCatalog.primaryRateWindowID,
            titleKey: "codex.quota.primary",
            period: .duration(minutes: 10_080),
            startsAt: nil,
            resetsAt: capturedAt.addingTimeInterval(3_600),
            usedFraction: 0.25,
            remainingFraction: 0.75,
            sourcePrecision: .providerRounded,
            quotaRisk: .normal
        )
        var metrics: [MetricSample] = []
        if let resetCredits {
            metrics.append(
                MetricSample(
                    definitionID: CodexDomainCatalog.resetCreditsID,
                    entity: CodexDomainCatalog.providerEntity,
                    value: .count(Int64(resetCredits)),
                    availability: .available,
                    observedAt: capturedAt
                )
            )
        }
        let snapshot = ProviderSnapshot(
            schemaVersion: 1,
            providerID: CodexDomainCatalog.providerID,
            capturedAt: capturedAt,
            availability: .available,
            accountScope: nil,
            plan: PlanDescriptor(
                rawValue: "plus",
                displayName: "plus"
            ),
            rateWindows: [window],
            balances: [],
            currentMetrics: metrics,
            models: [],
            agents: [],
            serviceHealth: .unknown
        )
        return ProviderFetchResult(
            snapshot: snapshot,
            historicalObservations: [],
            diagnostics: SanitizedFetchDiagnostics(
                sourceLabel: "test",
                duration: 0,
                optionalIssues: []
            )
        )
    }
}

private struct AppStubProvider:
    UsageProviderAdapter, Sendable {
    let descriptor = ProviderDescriptor(
        id: CodexDomainCatalog.providerID,
        displayName: "Codex",
        capabilities: .currentQuotaViewFeatures,
        sourceKinds: [.localAppServer],
        resourceProfile: ProviderResourceProfile(
            minimumRefreshInterval: 1,
            startsSubprocess: false,
            typicalTimeout: 1,
            permitsParallelEnrichment: true,
            lowPowerMinimumInterval: 1
        ),
        supportsStableAccountScope: false
    )

    private let handler: @Sendable (
        ProviderFetchRequest
    ) async throws -> ProviderFetchResult

    init(
        handler: @escaping @Sendable (
            ProviderFetchRequest
        ) async throws -> ProviderFetchResult
    ) {
        self.handler = handler
    }

    func availability() async -> ProviderAvailability {
        .available
    }

    func fetch(
        _ request: ProviderFetchRequest
    ) async throws -> ProviderFetchResult {
        try await handler(request)
    }

    func stop() async {}
}

private actor FetchRequestRecorder {
    private(set) var lastRequest: ProviderFetchRequest?

    func record(_ request: ProviderFetchRequest) {
        lastRequest = request
    }
}

private actor AppOutcomeSequence {
    private var callCount = 0

    func shouldFail() -> Bool {
        defer { callCount += 1 }
        return callCount > 0
    }
}
