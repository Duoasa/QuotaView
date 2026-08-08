#if SWIFT_PACKAGE
import XCTest
@testable import QuotaViewCore
@testable import QuotaViewFutureContracts

final class ArchitectureTests: XCTestCase {
    func testDemandPlannerMergesConsumersWithoutDisabledProviders() {
        let providerID = ProviderID(rawValue: "codex")
        let disabledID = ProviderID(rawValue: "disabled")
        let planner = DataDemandPlanner()
        let plans = planner.plans(
            for: [
                ConsumerDemand(
                    consumer: .panel,
                    providerID: providerID,
                    capabilities: [.rateWindows, .balances],
                    freshness: .interactive
                ),
                ConsumerDemand(
                    consumer: .history,
                    providerID: providerID,
                    capabilities: [.historicalUsage],
                    freshness: .lowPriority
                ),
                ConsumerDemand(
                    consumer: .panel,
                    providerID: disabledID,
                    capabilities: [.rateWindows],
                    freshness: .interactive
                )
            ],
            enabledProviders: [providerID]
        )

        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(
            plans[providerID]?.capabilities,
            [.rateWindows, .balances, .historicalUsage]
        )
        XCTAssertEqual(
            plans[providerID]?.consumers,
            [.panel, .history]
        )
        XCTAssertEqual(
            plans[providerID]?.freshness,
            .interactive
        )
    }

    func testReplacementRejectsLateOlderGeneration() async {
        let provider = StubProvider { request in
            if request.reason == .background {
                try await Task.sleep(for: .milliseconds(200))
            } else {
                try await Task.sleep(for: .milliseconds(10))
            }
            return Self.makeFetchResult(
                capturedAt: Date(
                    timeIntervalSince1970:
                        TimeInterval(request.generation)
                )
            )
        }
        let coordinator = RefreshCoordinator(
            provider: provider,
            demand: ProviderDemandPlan(
                providerID: provider.descriptor.id,
                capabilities: [.rateWindows],
                freshness: .interactive,
                consumers: [.panel]
            )
        )

        async let older = coordinator.requestRefresh(
            reason: .background,
            policy: .coalesce
        )
        try? await Task.sleep(for: .milliseconds(30))
        let newer = await coordinator.requestRefresh(
            reason: .manual,
            policy: .replace
        )
        let olderResult = await older

        guard case .applied(let result, let context) = newer else {
            return XCTFail("New generation was not applied")
        }
        XCTAssertEqual(
            result.snapshot.capturedAt.timeIntervalSince1970,
            TimeInterval(context.generation)
        )
        guard case .discarded = olderResult else {
            return XCTFail("Older generation should be discarded")
        }
    }

    func testCoalescedCallersReceiveTheSameAppliedGeneration() async {
        let calls = CallCounter()
        let provider = StubProvider { request in
            await calls.increment()
            try await Task.sleep(for: .milliseconds(30))
            return Self.makeFetchResult(
                capturedAt: Date(
                    timeIntervalSince1970:
                        TimeInterval(request.generation)
                )
            )
        }
        let coordinator = RefreshCoordinator(
            provider: provider,
            demand: ProviderDemandPlan(
                providerID: provider.descriptor.id,
                capabilities: [.rateWindows],
                freshness: .interactive,
                consumers: [.panel]
            )
        )

        async let first = coordinator.requestRefresh(
            reason: .background,
            policy: .coalesce
        )
        try? await Task.sleep(for: .milliseconds(5))
        async let second = coordinator.requestRefresh(
            reason: .background,
            policy: .coalesce
        )

        let firstOutcome = await first
        let secondOutcome = await second
        let outcomes = [firstOutcome, secondOutcome]
        let generations = outcomes.compactMap { outcome -> UInt64? in
            guard case .applied(_, let context) = outcome else {
                return nil
            }
            return context.generation
        }

        XCTAssertEqual(generations.count, 2)
        XCTAssertEqual(Set(generations).count, 1)
        let callCount = await calls.value
        XCTAssertEqual(callCount, 1)
    }

    func testDisabledProviderDoesNotFetch() async {
        let calls = CallCounter()
        let provider = StubProvider { _ in
            await calls.increment()
            return Self.makeFetchResult()
        }
        let coordinator = RefreshCoordinator(
            provider: provider,
            enabled: false,
            demand: ProviderDemandPlan(
                providerID: provider.descriptor.id,
                capabilities: [.rateWindows],
                freshness: .interactive,
                consumers: [.panel]
            )
        )

        let result = await coordinator.requestRefresh(
            reason: .manual,
            policy: .replace
        )

        guard case .disabled = result else {
            return XCTFail("Disabled provider should not refresh")
        }
        let callCount = await calls.value
        XCTAssertEqual(callCount, 0)
    }

    func testStableAccountChangeRejectsFirstMismatchedResult()
        async {
        let scopes = AccountScopeSequence(["account-a", "account-b", "account-b"])
        let provider = StubProvider { _ in
            let scope = await scopes.next()
            return Self.makeFetchResult(
                accountScope: AccountScope(
                    pseudonymousID: scope,
                    stability: .stable
                )
            )
        }
        let coordinator = RefreshCoordinator(
            provider: provider,
            demand: ProviderDemandPlan(
                providerID: provider.descriptor.id,
                capabilities: [.rateWindows],
                freshness: .interactive,
                consumers: [.panel]
            )
        )

        let initial = await coordinator.requestRefresh(
            reason: .startup,
            policy: .replace
        )
        let accountChanged = await coordinator.requestRefresh(
            reason: .background,
            policy: .replace
        )
        let confirmed = await coordinator.requestRefresh(
            reason: .background,
            policy: .replace
        )

        guard case .applied(let initialResult, _) = initial else {
            return XCTFail("Initial account should be accepted")
        }
        XCTAssertEqual(
            initialResult.snapshot.accountScope?.pseudonymousID,
            "account-a"
        )
        guard case .discarded = accountChanged else {
            return XCTFail(
                "First result for a changed account must be discarded"
            )
        }
        guard case .applied(let confirmedResult, _) = confirmed else {
            return XCTFail("Confirmed changed account should be accepted")
        }
        XCTAssertEqual(
            confirmedResult.snapshot.accountScope?.pseudonymousID,
            "account-b"
        )
    }

    func testStaticRegistryRejectsDuplicateProviderIDs() throws {
        let first = StubProvider { _ in Self.makeFetchResult() }
        let second = StubProvider { _ in Self.makeFetchResult() }

        XCTAssertThrowsError(
            try StaticProviderRegistry(adapters: [first, second])
        ) { error in
            XCTAssertEqual(
                error as? ProviderRegistryError,
                .duplicateProviderID(CodexDomainCatalog.providerID)
            )
        }
    }

    func testDisabledFutureCapabilitiesPerformNoWork() async throws {
        let store = DisabledMetricHistoryStore()
        let now = Date(timeIntervalSince1970: 1_785_000_000)
        let query = HistoryQuery(
            providerID: CodexDomainCatalog.providerID,
            accountScopeID: nil,
            metricIDs: [CodexDomainCatalog.usedFractionID],
            entityIDs: [CodexDomainCatalog.providerEntity.id],
            interval: DateInterval(
                start: now.addingTimeInterval(-3_600),
                end: now
            ),
            maximumPointCount: 0
        )

        try await store.ingest([])
        let observations = try await store.observations(
            matching: query
        )
        try await store.removeAll(
            for: CodexDomainCatalog.providerID
        )
        await store.stop()

        XCTAssertTrue(observations.isEmpty)
        XCTAssertEqual(query.maximumPointCount, 1)

        let scheduler = DisabledQuotaNotificationScheduler()
        await scheduler.schedule([])
        await scheduler.stop()
    }

    func testDisplayPreferencesPreserveUnknownStableIDs()
        throws {
        let preferences = DisplayPreferences(
            enabledProviders: [
                CodexDomainCatalog.providerID,
                ProviderID(rawValue: "future-provider")
            ],
            panelMetricIDs: [
                CodexDomainCatalog.remainingFractionID,
                MetricID(rawValue: "future-provider.usage.unknown")
            ],
            visibleChartIDs: [
                ChartID(rawValue: "codex.tokens.trend")
            ],
            menuBarMetricIDs: [
                CodexDomainCatalog.remainingFractionID
            ],
            widgetMetricIDs: [
                MetricID(rawValue: "future-provider.usage.unknown")
            ]
        )

        let data = try JSONEncoder().encode(preferences)
        let decoded = try JSONDecoder().decode(
            DisplayPreferences.self,
            from: data
        )

        XCTAssertEqual(decoded, preferences)
    }

    private static func makeFetchResult(
        capturedAt: Date = Date(timeIntervalSince1970: 1),
        accountScope: AccountScope? = nil
    ) -> ProviderFetchResult {
        let window = RateWindow(
            id: CodexDomainCatalog.primaryRateWindowID,
            titleKey: "codex.quota.primary",
            period: .duration(minutes: 10_080),
            startsAt: nil,
            resetsAt: nil,
            usedFraction: 0.25,
            remainingFraction: 0.75,
            sourcePrecision: .providerRounded,
            quotaRisk: .normal
        )
        let snapshot = ProviderSnapshot(
            schemaVersion: 1,
            providerID: CodexDomainCatalog.providerID,
            capturedAt: capturedAt,
            availability: .available,
            accountScope: accountScope,
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

private struct StubProvider: UsageProviderAdapter, Sendable {
    let descriptor = ProviderDescriptor(
        id: CodexDomainCatalog.providerID,
        displayName: "Codex",
        capabilities: [.rateWindows],
        sourceKinds: [.localAppServer],
        resourceProfile: ProviderResourceProfile(
            minimumRefreshInterval: 1,
            startsSubprocess: false,
            typicalTimeout: 1,
            permitsParallelEnrichment: false,
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

private actor CallCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

private actor AccountScopeSequence {
    private var values: [String]

    init(_ values: [String]) {
        self.values = values
    }

    func next() -> String {
        guard !values.isEmpty else {
            return "unexpected"
        }
        return values.removeFirst()
    }
}
#endif
