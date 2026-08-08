import Combine
import Foundation
import XCTest
@testable import QuotaView
@testable import QuotaViewCore
import QuotaViewWidgetContract

final class AppBehaviorTests: XCTestCase {
    @MainActor
    func testMenuUsagePromptYieldsToAnyValidSnapshot() {
        XCTAssertTrue(
            MenuUsageConnectionPolicy.showsPrompt(hasSnapshot: false)
        )
        XCTAssertFalse(
            MenuUsageConnectionPolicy.showsPrompt(hasSnapshot: true)
        )
    }

    @MainActor
    func testSettingsNavigationTargetsConnectionAndIslandPage() {
        let navigation = SettingsNavigation()

        XCTAssertEqual(navigation.selection, .menuBar)
        navigation.showConnectionAndIsland()
        XCTAssertEqual(navigation.selection, .codexActivity)
    }


    @MainActor
    func testPluginDisconnectIgnoresLateBridgeReadFailure() async {
        let context = makeBlockingPluginRuntime()
        defer {
            context.defaults.removePersistentDomain(
                forName: context.suiteName
            )
            context.reader.release()
        }

        context.defaults.set(
            Data([0x01]),
            forKey: "codexPlugin.bridge.bookmark"
        )
        let polling = Task { await context.runtime.pollOnce() }
        let didStart = await context.reader.waitUntilStarted()
        XCTAssertTrue(didStart)

        context.runtime.disconnectPluginData()
        context.reader.release()
        await polling.value

        XCTAssertEqual(context.runtime.connectionStatus, .notConfigured)
        XCTAssertNil(context.runtime.connectionIssue)
        await context.runtime.stop()
    }

    @MainActor
    func testPluginStopIgnoresLateBridgeReadFailure() async {
        let context = makeBlockingPluginRuntime()
        defer {
            context.defaults.removePersistentDomain(
                forName: context.suiteName
            )
            context.reader.release()
        }

        context.defaults.set(
            Data([0x01]),
            forKey: "codexPlugin.bridge.bookmark"
        )
        let polling = Task { await context.runtime.pollOnce() }
        let didStart = await context.reader.waitUntilStarted()
        XCTAssertTrue(didStart)

        await context.runtime.stop()
        context.reader.release()
        await polling.value

        XCTAssertEqual(context.runtime.connectionStatus, .notConfigured)
        XCTAssertNil(context.runtime.connectionIssue)
    }

    @MainActor
    func testPluginNewRevisionPollDoesNotWaitForStaleRead() async {
        let suiteName = "QuotaView.PluginRuntimeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let reader = SupersededBridgeReader()
        let runtime = CodexActivityRuntime(
            preferences: AppPreferences(defaults: defaults),
            defaults: defaults,
            bridgeReader: { [reader] bookmark, cursor in
                try reader.read(bookmark, cursor, true)
            }
        )
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            reader.releaseFirst()
        }

        defaults.set(Data([0x01]), forKey: "codexPlugin.bridge.bookmark")
        let stalePoll = Task { await runtime.pollOnce() }
        let firstDidStart = await reader.waitUntilFirstStarted()
        XCTAssertTrue(firstDidStart)

        runtime.disconnectPluginData()
        defaults.set(Data([0x02]), forKey: "codexPlugin.bridge.bookmark")
        let currentPoll = Task { await runtime.pollOnce() }
        let secondDidStart = await reader.waitUntilSecondStarted()
        XCTAssertTrue(secondDidStart)
        await currentPoll.value

        XCTAssertEqual(runtime.pluginVersion, "1.0.0-current")
        XCTAssertEqual(runtime.connectionStatus, .pairedWaitingForEvent)
        XCTAssertNil(runtime.connectionIssue)

        reader.releaseFirst()
        await stalePoll.value
        XCTAssertEqual(runtime.pluginVersion, "1.0.0-current")
        XCTAssertEqual(runtime.connectionStatus, .pairedWaitingForEvent)
        await runtime.stop()
    }

    @MainActor
    func testPluginInstallationChangeClearsPriorProgress() async {
        let suiteName = "QuotaView.PluginRuntimeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(Data([0x01]), forKey: "codexPlugin.bridge.bookmark")
        defaults.set(
            "install-previous",
            forKey: "codexPlugin.bridge.cursor.installation"
        )
        defaults.set(42, forKey: "codexPlugin.bridge.cursor.sequence")
        defaults.set(
            Date().timeIntervalSince1970,
            forKey: "codexPlugin.bridge.lastEventAt"
        )
        let manifest = CodexPluginBridgeManifest(
            pluginID: "quotaview",
            pluginVersion: "1.0.0-reinstalled",
            distributionChannel: "git-marketplace",
            bridgeProtocolVersion: 1,
            eventSchemaVersion: 1,
            installationIdentifier: "install-reinstalled",
            createdAt: Date(),
            capabilities: ["codex-activity-events"]
        )
        let runtime = CodexActivityRuntime(
            preferences: AppPreferences(defaults: defaults),
            defaults: defaults,
            bridgeReader: { _, cursor in
                BridgeReadResult(
                    manifest: manifest,
                    status: nil,
                    usageSnapshot: nil,
                    envelopes: [],
                    cursor: cursor,
                    skippedMalformedEvents: 0
                )
            }
        )
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        XCTAssertNotNil(runtime.lastEventAt)
        await runtime.pollOnce()

        XCTAssertEqual(runtime.pluginVersion, "1.0.0-reinstalled")
        XCTAssertEqual(runtime.connectionStatus, .pairedWaitingForEvent)
        XCTAssertNil(runtime.lastEventAt)
        XCTAssertNil(
            defaults.string(
                forKey: "codexPlugin.bridge.cursor.installation"
            )
        )
        XCTAssertNil(
            defaults.object(forKey: "codexPlugin.bridge.cursor.sequence")
        )
        XCTAssertNil(
            defaults.object(forKey: "codexPlugin.bridge.lastEventAt")
        )
        await runtime.stop()
    }

    @MainActor
    func testIdleValidUsageSnapshotDoesNotExpireConnection() async {
        let suiteName = "QuotaView.PluginRuntimeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(
            Data([0x01]),
            forKey: "codexPlugin.bridge.bookmark"
        )
        let manifest = CodexPluginBridgeManifest(
            pluginID: "quotaview",
            pluginVersion: "1.0.0-preview.3",
            distributionChannel: "git-marketplace",
            bridgeProtocolVersion: 1,
            eventSchemaVersion: CodexPluginBridgeContract.eventSchemaVersion,
            installationIdentifier: "install-idle",
            createdAt: Date(),
            capabilities: [
                CodexPluginBridgeContract.activityCapability,
                CodexPluginBridgeContract.usageCapability
            ]
        )
        let usage = CodexPluginUsageSnapshot(
            bridgeProtocolVersion: 1,
            installationIdentifier: manifest.installationIdentifier,
            usageSchemaVersion: CodexPluginBridgeContract.usageSchemaVersion,
            capturedAt: Date().addingTimeInterval(-30 * 60),
            source: "codex-app-server",
            planType: "plus",
            primary: CodexPluginUsageRateWindow(
                usedPercent: 25,
                windowDurationMins: 10_080,
                resetsAt: Int64(Date().timeIntervalSince1970) + 3_600
            ),
            credits: nil,
            limitReached: false,
            lifetimeTokens: 123,
            recentDailyTokens: nil,
            recentDailyDate: nil
        )
        let runtime = CodexActivityRuntime(
            preferences: AppPreferences(defaults: defaults),
            defaults: defaults,
            bridgeReader: { _, cursor in
                BridgeReadResult(
                    manifest: manifest,
                    status: nil,
                    usageSnapshot: usage,
                    envelopes: [],
                    cursor: cursor,
                    skippedMalformedEvents: 0
                )
            }
        )
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        await runtime.pollOnce()

        XCTAssertEqual(runtime.connectionStatus, .connected)
        XCTAssertEqual(runtime.lastUsageAt, usage.capturedAt)
        await runtime.stop()
    }

    @MainActor
    func testUsageSnapshotOlderThanBridgeFreshnessIsStale() async {
        let suiteName = "QuotaView.PluginRuntimeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(
            Data([0x01]),
            forKey: "codexPlugin.bridge.bookmark"
        )
        let manifest = CodexPluginBridgeManifest(
            pluginID: "quotaview",
            pluginVersion: "1.0.0-preview.3",
            distributionChannel: "git-marketplace",
            bridgeProtocolVersion: 1,
            eventSchemaVersion: CodexPluginBridgeContract.eventSchemaVersion,
            installationIdentifier: "install-stale",
            createdAt: Date(),
            capabilities: [
                CodexPluginBridgeContract.activityCapability,
                CodexPluginBridgeContract.usageCapability
            ]
        )
        let usage = CodexPluginUsageSnapshot(
            bridgeProtocolVersion: 1,
            installationIdentifier: manifest.installationIdentifier,
            usageSchemaVersion: CodexPluginBridgeContract.usageSchemaVersion,
            capturedAt: Date().addingTimeInterval(
                -CodexPluginBridgeContract.maximumUsageSnapshotAge - 60
            ),
            source: "codex-app-server",
            planType: "plus",
            primary: CodexPluginUsageRateWindow(
                usedPercent: 25,
                windowDurationMins: 10_080,
                resetsAt: Int64(Date().timeIntervalSince1970) + 3_600
            ),
            credits: nil,
            limitReached: false,
            lifetimeTokens: 123,
            recentDailyTokens: nil,
            recentDailyDate: nil
        )
        let runtime = CodexActivityRuntime(
            preferences: AppPreferences(defaults: defaults),
            defaults: defaults,
            bridgeReader: { _, cursor in
                BridgeReadResult(
                    manifest: manifest,
                    status: nil,
                    usageSnapshot: usage,
                    envelopes: [],
                    cursor: cursor,
                    skippedMalformedEvents: 0
                )
            }
        )
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        await runtime.pollOnce()

        XCTAssertEqual(runtime.connectionStatus, .stale)
        await runtime.stop()
    }

    func testExpiredPluginEventAdvancesCursorWithoutMalformedWarning()
        throws
    {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "QuotaView.ExpiredEventTests.\(UUID().uuidString)",
            isDirectory: true
        )
        let events = root.appendingPathComponent(
            "events",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: events,
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: root) }

        let now = Date(timeIntervalSince1970: 1_786_000_000)
        let formatter = ISO8601DateFormatter()
        let installationID = "install-expired-event"
        let sessionHash = String(repeating: "a", count: 64)
        let manifest = Data(
            """
            {
              "pluginId": "quotaview",
              "pluginVersion": "1.0.0-preview.3",
              "distributionChannel": "git-marketplace",
              "bridgeProtocolVersion": 1,
              "eventSchemaVersion": 1,
              "installationIdentifier": "\(installationID)",
              "createdAt": "\(formatter.string(from: now.addingTimeInterval(-3_600)))",
              "capabilities": ["codex-activity-events"]
            }
            """.utf8
        )
        try manifest.write(to: root.appendingPathComponent("bridge.json"))

        func event(sequence: Int, occurredAt: Date) -> Data {
            Data(
                """
                {
                  "bridgeProtocolVersion": 1,
                  "installationIdentifier": "\(installationID)",
                  "sequence": \(sequence),
                  "activity": {
                    "schemaVersion": 1,
                    "event": "Stop",
                    "sessionHash": "\(sessionHash)",
                    "turnHash": null,
                    "workspaceName": "QuotaView",
                    "toolCategory": null,
                    "sessionStartSource": null,
                    "occurredAt": "\(formatter.string(from: occurredAt))"
                  }
                }
                """.utf8
            )
        }
        try event(
            sequence: 1,
            occurredAt: now.addingTimeInterval(
                -CodexPluginBridgeContract.maximumEventAge - 1
            )
        ).write(
            to: events.appendingPathComponent("000000000001.json")
        )
        try event(sequence: 2, occurredAt: now).write(
            to: events.appendingPathComponent("000000000002.json")
        )

        let result = try CodexActivityRuntime.readBridgeDirectory(
            at: root,
            cursor: nil,
            consumesEvents: true,
            now: now
        )

        XCTAssertEqual(result.skippedMalformedEvents, 0)
        XCTAssertEqual(result.envelopes.map(\.sequence), [2])
        XCTAssertEqual(result.cursor?.sequence, 2)
    }

    func testAppStorePanelMaximumHeightExcludesQuotaResetFlow() {
        XCTAssertEqual(QuotaViewFigmaMenu.designSize.width, 274)
        XCTAssertEqual(QuotaViewFigmaMenu.designSize.height, 373)
    }

    @MainActor
    private func makeBlockingPluginRuntime() -> PluginRuntimeTestContext {
        let suiteName = "QuotaView.PluginRuntimeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let reader = BlockingBridgeReader()
        let runtime = CodexActivityRuntime(
            preferences: AppPreferences(defaults: defaults),
            defaults: defaults,
            bridgeReader: { [reader] bookmark, cursor in
                try reader.read(bookmark, cursor, true)
            }
        )
        return PluginRuntimeTestContext(
            suiteName: suiteName,
            defaults: defaults,
            reader: reader,
            runtime: runtime
        )
    }

    func testAppVersionInfoFormatsLocalizedVersionAndBuild() {
        let info = AppVersionInfo(
            marketingVersion: "1.0.0",
            buildNumber: "3"
        )
        XCTAssertEqual(
            info.label(copy: AppCopy(language: .simplifiedChinese)),
            "版本 1.0.0（Build 3）"
        )
        XCTAssertEqual(
            info.label(copy: AppCopy(language: .english)),
            "Version 1.0.0 (Build 3)"
        )
    }

    func testAppVersionInfoDoesNotInventMissingBundleValues() {
        let info = AppVersionInfo(
            marketingVersion: "  ",
            buildNumber: nil
        )
        XCTAssertEqual(info.marketingVersion, "—")
        XCTAssertEqual(info.buildNumber, "—")
    }

    func testPublicLinkRequiresPublishedHTTPSConfiguration() {
        let published = AppStorePublicLinkConfiguration(
            status: "published",
            rawURL: "https://example.com/privacy"
        )
        XCTAssertEqual(
            published.publishedURL,
            URL(string: "https://example.com/privacy")
        )

        XCTAssertNil(
            AppStorePublicLinkConfiguration(
                status: "draft",
                rawURL: "https://example.com/privacy"
            ).publishedURL
        )
        XCTAssertNil(
            AppStorePublicLinkConfiguration(
                status: "published",
                rawURL: "http://example.com/privacy"
            ).publishedURL
        )
        XCTAssertNil(
            AppStorePublicLinkConfiguration(
                status: "published",
                rawURL: "https://user@example.com/privacy"
            ).publishedURL
        )
        XCTAssertNil(
            AppStorePublicLinkConfiguration(
                status: "published",
                rawURL: "https://example.com/[PRIVACY]"
            ).publishedURL
        )
    }

    func testCodexActivityProductionInactivityTiming() {
        XCTAssertEqual(CodexActivityStore.compactDelay, 20)
        XCTAssertEqual(
            CodexActivityStore.compactDelay
                + CodexActivityStore.hiddenDelayAfterCompact,
            120
        )
        XCTAssertEqual(CodexActivityStore.missingStopHideDelay, 120)
    }

    @MainActor
    func testCodexActivityCompletesThenCompactsAndHides() async {
        let store = CodexActivityStore(
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
            compactDelay: 0.02,
            hiddenDelayAfterCompact: 0.02
        )
        store.receive(
            CodexActivityEvent(
                event: .stop,
                sessionHash: "session"
            )
        )
        try? await Task.sleep(nanoseconds: 8_000_000)
        store.receive(
            CodexActivityEvent(
                event: .preToolUse,
                sessionHash: "session",
                toolCategory: .fileEdit
            )
        )
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(store.presentation, .expanded)
        XCTAssertEqual(store.snapshot?.operationKey, .editingFiles)
        await store.stop()
    }

    @MainActor
    func testPostToolUseHidesWhenStopEventIsMissing() async {
        let store = CodexActivityStore(
            compactDelay: 1,
            hiddenDelayAfterCompact: 1,
            missingStopHideDelay: 0.02
        )
        store.receive(
            CodexActivityEvent(
                event: .postToolUse,
                sessionHash: "session",
                toolCategory: .fileEdit
            )
        )
        XCTAssertEqual(store.presentation, .expanded)
        XCTAssertEqual(store.snapshot?.state, .thinking)

        for _ in 0..<100 where store.presentation != .hidden {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(store.presentation, .hidden)
        XCTAssertEqual(store.snapshot?.state, .thinking)
        await store.stop()
    }

    @MainActor
    func testNewActivityCancelsMissingStopFallback() async {
        let store = CodexActivityStore(
            compactDelay: 1,
            hiddenDelayAfterCompact: 1,
            missingStopHideDelay: 0.02
        )
        store.receive(
            CodexActivityEvent(
                event: .postToolUse,
                sessionHash: "session"
            )
        )
        try? await Task.sleep(nanoseconds: 8_000_000)
        store.receive(
            CodexActivityEvent(
                event: .preToolUse,
                sessionHash: "session",
                toolCategory: .shell
            )
        )
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(store.presentation, .expanded)
        XCTAssertEqual(store.snapshot?.operationKey, .executingShell)
        await store.stop()
    }

    @MainActor
    func testOlderActivityCannotOverwriteNewerState() async {
        let store = CodexActivityStore()
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
        XCTAssertEqual(store.snapshot?.state, .working)
        XCTAssertEqual(store.presentation, .expanded)
        await store.stop()
    }

    @MainActor
    func testActivityOlderThanSessionEndCannotReopenIsland() async {
        let store = CodexActivityStore()
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
        XCTAssertEqual(store.snapshot?.occurredAt, endedAt)
        await store.stop()
    }

    @MainActor
    func testNativePreferenceDefaults() {
        let suiteName = "QuotaViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferences(defaults: defaults)

        XCTAssertTrue(preferences.showStatusIcon)
        XCTAssertTrue(preferences.showRemainingQuota)
        XCTAssertFalse(preferences.showResetCountdown)
        XCTAssertTrue(preferences.showUsageSummary)
        XCTAssertTrue(preferences.showNextReset)
        XCTAssertTrue(preferences.showCreditBalance)
        XCTAssertTrue(preferences.showDailyTokens)
        XCTAssertTrue(preferences.showLifetimeTokens)
        XCTAssertTrue(preferences.showCodexIsland)
        XCTAssertTrue(preferences.followsSystemAppearance)
        XCTAssertTrue(preferences.followsSystemLanguage)
        XCTAssertEqual(preferences.glassMode, .clear)
    }

    @MainActor
    func testCodexIslandPreferencePersistsDisabledState() {
        let suiteName = "QuotaViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = AppPreferences(defaults: defaults)
        preferences.showCodexIsland = false

        XCTAssertFalse(
            AppPreferences(defaults: defaults).showCodexIsland
        )
    }

    @MainActor
    func testLatestProviderFailureKeepsStalePresentation() async {
        let suiteName = "QuotaViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let outcomes = AppOutcomeSequence()
        let provider = AppStubProvider { _ in
            if await outcomes.shouldFail() {
                throw ProviderError.unavailable
            }
            return Self.makeFetchResult()
        }
        let store = CodexStatusStore(
            provider: provider,
            diagnostics: defaults
        )

        await store.refresh()
        XCTAssertNotNil(store.snapshot)
        XCTAssertTrue(store.hasCurrentCodexStatus)
        await store.refresh()
        XCTAssertNotNil(store.snapshot)
        XCTAssertFalse(store.hasCurrentCodexStatus)
        guard case .unavailable = store.providerState else {
            return XCTFail("Latest provider failure must be unavailable")
        }
        await store.stop()
    }

    @MainActor
    func testAuthenticationFailureIsPresentedWithoutAppOwnedLogin() async {
        let provider = AppStubProvider { _ in
            throw ProviderError.authenticationRequired
        }
        let store = CodexStatusStore(provider: provider)
        await store.refresh()

        XCTAssertEqual(
            store.errorMessage,
            ProviderError.authenticationRequired.localizedDescription
        )
        await store.stop()
    }

    @MainActor
    func testPluginDataChangeClearsPriorSnapshot() async {
        let suiteName = "QuotaViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        let outcomes = AppOutcomeSequence()
        let provider = AppStubProvider { _ in
            if await outcomes.shouldFail() {
                throw ProviderError.authenticationRequired
            }
            return Self.makeFetchResult(accountScopeID: "account-a")
        }
        let store = CodexStatusStore(
            provider: provider,
            diagnostics: defaults,
            widgetSnapshotWriter: QuotaViewWidgetSnapshotWriter(
                appGroupIdentifier: "group.test.quotaview",
                containerURLProvider: { _ in temporaryDirectory },
                timelineReloader: { _ in }
            )
        )

        await store.refresh()
        XCTAssertNotNil(store.snapshot)
        XCTAssertNotNil(
            defaults.object(forKey: "diagnostics.lastSuccessAt")
        )
        let availableWidgetSnapshot = try? WidgetSnapshotFileStore(
            containerURL: temporaryDirectory
        ).read(now: Date())
        XCTAssertEqual(availableWidgetSnapshot?.availability, .available)

        await store.pluginDataConfigurationDidChange()

        XCTAssertNil(store.snapshot)
        XCTAssertFalse(store.hasCurrentCodexStatus)
        XCTAssertEqual(store.providerError, .authenticationRequired)
        guard case .unavailable(let previous, let error) =
                store.providerState
        else {
            return XCTFail("Signed-out state must be unavailable")
        }
        XCTAssertNil(previous)
        XCTAssertEqual(error, .authenticationRequired)
        XCTAssertNil(
            defaults.object(forKey: "diagnostics.lastSuccessAt")
        )
        XCTAssertNil(
            defaults.object(forKey: "diagnostics.lastUsedPercent")
        )
        let signedOutWidgetSnapshot = try? WidgetSnapshotFileStore(
            containerURL: temporaryDirectory
        ).read(now: Date())
        XCTAssertEqual(signedOutWidgetSnapshot?.availability, .unavailable)
        XCTAssertNil(signedOutWidgetSnapshot?.provider)
        await store.stop()
    }

    @MainActor
    func testPluginDataChangeAcceptsFirstNewResult() async {
        let outcomes = AppAccountSwitchSequence()
        let provider = AppStubProvider { _ in
            let outcome = await outcomes.next()
            return Self.makeFetchResult(
                accountScopeID: outcome.accountScopeID,
                usedFraction: outcome.usedFraction
            )
        }
        let store = CodexStatusStore(provider: provider)

        await store.refresh()
        XCTAssertEqual(store.snapshot?.usedPercent, 25)

        await store.pluginDataConfigurationDidChange()

        XCTAssertEqual(store.snapshot?.usedPercent, 75)
        XCTAssertNil(store.providerError)
        guard case .available(let snapshot) = store.providerState else {
            return XCTFail("The first new-account result must be applied")
        }
        XCTAssertEqual(snapshot.accountScope?.pseudonymousID, "account-b")
        await store.stop()
    }

    private static func makeFetchResult(
        accountScopeID: String? = nil,
        usedFraction: Double = 0.25
    ) -> ProviderFetchResult {
        let capturedAt = Date(timeIntervalSince1970: 1_785_000_000)
        let window = RateWindow(
            id: CodexDomainCatalog.primaryRateWindowID,
            titleKey: "codex.quota.primary",
            period: .duration(minutes: 10_080),
            startsAt: nil,
            resetsAt: capturedAt.addingTimeInterval(3_600),
            usedFraction: usedFraction,
            remainingFraction: 1 - usedFraction,
            sourcePrecision: .providerRounded,
            quotaRisk: .normal
        )
        return ProviderFetchResult(
            snapshot: ProviderSnapshot(
                schemaVersion: 1,
                providerID: CodexDomainCatalog.providerID,
                capturedAt: capturedAt,
                availability: .available,
                accountScope: accountScopeID.map {
                    AccountScope(
                        pseudonymousID: $0,
                        stability: .stable
                    )
                },
                plan: PlanDescriptor(
                    rawValue: "plus",
                    displayName: "plus"
                ),
                rateWindows: [window],
                balances: [],
                currentMetrics: [],
                models: [],
                agents: [],
                serviceHealth: .unknown
            ),
            historicalObservations: [],
            diagnostics: SanitizedFetchDiagnostics(
                sourceLabel: "test",
                duration: 0,
                optionalIssues: []
            )
        )
    }

}


@MainActor
private struct PluginRuntimeTestContext {
    let suiteName: String
    let defaults: UserDefaults
    let reader: BlockingBridgeReader
    let runtime: CodexActivityRuntime
}

private final class BlockingBridgeReader: @unchecked Sendable {
    private let started = DispatchSemaphore(value: 0)
    private let released = DispatchSemaphore(value: 0)

    func read(
        _ bookmark: Data,
        _ cursor: CodexPluginBridgeCursor?,
        _ consumesEvents: Bool
    ) throws -> BridgeReadResult {
        started.signal()
        released.wait()
        throw BridgeReaderTestError.failed
    }

    func waitUntilStarted() async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async { [started] in
                continuation.resume(
                    returning: started.wait(timeout: .now() + 2)
                        == .success
                )
            }
        }
    }

    func release() {
        released.signal()
    }
}

private final class SupersededBridgeReader: @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0
    private let firstStarted = DispatchSemaphore(value: 0)
    private let secondStarted = DispatchSemaphore(value: 0)
    private let firstReleased = DispatchSemaphore(value: 0)

    func read(
        _ bookmark: Data,
        _ cursor: CodexPluginBridgeCursor?,
        _ consumesEvents: Bool
    ) throws -> BridgeReadResult {
        lock.lock()
        callCount += 1
        let call = callCount
        lock.unlock()

        if call == 1 {
            firstStarted.signal()
            firstReleased.wait()
            throw BridgeReaderTestError.failed
        }

        secondStarted.signal()
        return BridgeReadResult(
            manifest: CodexPluginBridgeManifest(
                pluginID: "quotaview",
                pluginVersion: "1.0.0-current",
                distributionChannel: "git-marketplace",
                bridgeProtocolVersion: 1,
                eventSchemaVersion: 1,
                installationIdentifier: "install-current",
                createdAt: Date(),
                capabilities: ["codex-activity-events"]
            ),
            status: nil,
            usageSnapshot: nil,
            envelopes: [],
            cursor: nil,
            skippedMalformedEvents: 0
        )
    }

    func waitUntilFirstStarted() async -> Bool {
        await wait(for: firstStarted)
    }

    func waitUntilSecondStarted() async -> Bool {
        await wait(for: secondStarted)
    }

    func releaseFirst() {
        firstReleased.signal()
    }

    private func wait(for semaphore: DispatchSemaphore) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(
                    returning: semaphore.wait(timeout: .now() + 2)
                        == .success
                )
            }
        }
    }
}

private enum BridgeReaderTestError: Error {
    case failed
}

private struct AppStubProvider: UsageProviderAdapter, Sendable {
    let descriptor = ProviderDescriptor(
        id: CodexDomainCatalog.providerID,
        displayName: "Codex",
        capabilities: .currentQuotaViewFeatures,
        sourceKinds: [.pluginSanitizedSnapshot],
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

    func availability() async -> ProviderAvailability { .available }

    func fetch(
        _ request: ProviderFetchRequest
    ) async throws -> ProviderFetchResult {
        try await handler(request)
    }

    func stop() async {}
}

private actor AppOutcomeSequence {
    private var callCount = 0

    func shouldFail() -> Bool {
        defer { callCount += 1 }
        return callCount > 0
    }
}

private actor AppAccountSwitchSequence {
    private var callCount = 0

    func next() -> (accountScopeID: String, usedFraction: Double) {
        defer { callCount += 1 }
        return callCount == 0
            ? ("account-a", 0.25)
            : ("account-b", 0.75)
    }
}
