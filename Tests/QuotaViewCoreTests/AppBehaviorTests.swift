import Foundation
import XCTest
@testable import QuotaView
@testable import QuotaViewCore

final class AppBehaviorTests: XCTestCase {
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
            AppPreferences.Language.english.rawValue,
            forKey: "preferences.language.custom"
        )

        let savedPreferences = AppPreferences(defaults: savedDefaults)

        XCTAssertFalse(savedPreferences.followsSystemAppearance)
        XCTAssertEqual(savedPreferences.customAppearance, .light)
        XCTAssertEqual(savedPreferences.glassMode, .frosted)
        XCTAssertFalse(savedPreferences.followsSystemLanguage)
        XCTAssertEqual(savedPreferences.customLanguage, .english)

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
