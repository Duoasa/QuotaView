import Foundation
import XCTest
@testable import QuotaViewCore

final class AuditRefreshTransitionGateTests: XCTestCase {
    private func coordinator(_ provider: AuditRefreshGateProvider) -> RefreshCoordinator {
        .init(provider: provider, demand: .init(providerID: provider.descriptor.id,
            capabilities: [.rateWindows], freshness: .interactive, consumers: [.panel]))
    }

    func testReplacementResumingAfterStopOrDisableDoesNotFetch() async {
        for disable in [false, true] {
            let provider = AuditRefreshGateProvider(holdLimit: 1)
            let coordinator = coordinator(provider)
            let first = Task { await coordinator.requestRefresh(reason: .background, policy: .coalesce) }
            await provider.waitForFetch(1)
            let replacing = Task { await coordinator.requestRefresh(reason: .manual, policy: .replace) }
            await provider.waitForFirstStop()
            if disable { await coordinator.setEnabled(false) } else { await coordinator.stop() }
            await provider.releaseFirstStop()
            let outcome = await replacing.value
            if disable {
                guard case .disabled = outcome else { XCTFail("Replacement resumed after disable"); await provider.releaseFetches(); _ = await first.value; continue }
            } else {
                guard case .stopped = outcome else { XCTFail("Replacement resumed after stop"); await provider.releaseFetches(); _ = await first.value; continue }
            }
            let count = await provider.fetchCount
            let refreshing = await coordinator.isRefreshing
            XCTAssertEqual(count, 1)
            XCTAssertFalse(refreshing)
            await provider.releaseFetches()
            guard case .discarded = await first.value else { return XCTFail("Cancelled provider's late success was published") }
        }
    }

    func testSuspendedReplacementDoesNotOverwriteNewerRefresh() async {
        let provider = AuditRefreshGateProvider()
        let coordinator = coordinator(provider)
        let first = Task { await coordinator.requestRefresh(reason: .background, policy: .coalesce) }
        await provider.waitForFetch(1)
        let replacing = Task { await coordinator.requestRefresh(reason: .manual, policy: .replace) }
        await provider.waitForFirstStop()
        let latest = Task { await coordinator.requestRefresh(reason: .panelOpened, policy: .replace) }
        await provider.waitForFetch(2)
        await provider.releaseFirstStop()
        guard case .discarded = await replacing.value else { await provider.releaseFetches(); _ = await first.value; _ = await latest.value; return XCTFail("Older replacement stole the active context") }
        let count = await provider.fetchCount
        XCTAssertEqual(count, 2)
        await provider.releaseFetches()
        guard case .applied = await latest.value else { return XCTFail("Latest refresh lost publication ownership") }
        guard case .discarded = await first.value else { return XCTFail("Old late success should be discarded") }
        let refreshing = await coordinator.isRefreshing
        XCTAssertFalse(refreshing)
        await coordinator.stop()
    }
}

/// Explicit entered/release gates; fetch deliberately ignores cancellation.
private actor AuditRefreshGateProvider: UsageProviderAdapter {
    nonisolated let descriptor = ProviderDescriptor(id: CodexDomainCatalog.providerID,
        displayName: "Fixture", capabilities: [.rateWindows], sourceKinds: [.localAppServer],
        resourceProfile: .init(minimumRefreshInterval: 1, startsSubprocess: false,
            typicalTimeout: 1, permitsParallelEnrichment: false, lowPowerMinimumInterval: 1),
        supportsStableAccountScope: false)
    private(set) var fetchCount = 0
    private var stopCount = 0
    private var firstStopReleased = false
    private var fetchesReleased = false
    private var fetchWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var stopWaiters: [CheckedContinuation<Void, Never>] = []
    private var stopGate: CheckedContinuation<Void, Never>?
    private var fetchGates: [CheckedContinuation<Void, Never>] = []
    private let holdLimit: Int
    init(holdLimit: Int = 2) { self.holdLimit = holdLimit }

    func availability() async -> ProviderAvailability { .available }
    func fetch(_ request: ProviderFetchRequest) async throws -> ProviderFetchResult {
        fetchCount += 1
        let ready = fetchWaiters.filter { $0.0 <= fetchCount }
        fetchWaiters.removeAll { $0.0 <= fetchCount }
        ready.forEach { $0.1.resume() }
        if !fetchesReleased, fetchCount <= holdLimit { await withCheckedContinuation { fetchGates.append($0) } }
        return .init(snapshot: .init(schemaVersion: 1, providerID: descriptor.id,
            capturedAt: Date(timeIntervalSince1970: Double(request.generation)), availability: .available,
            accountScope: nil, plan: nil, rateWindows: [], balances: [], currentMetrics: [],
            models: [], agents: [], serviceHealth: .unknown), historicalObservations: [],
            diagnostics: .init(sourceLabel: "fixture", duration: 0, optionalIssues: []))
    }
    func stop() async {
        stopCount += 1
        guard stopCount == 1 else { return }
        stopWaiters.forEach { $0.resume() }; stopWaiters.removeAll()
        if !firstStopReleased { await withCheckedContinuation { stopGate = $0 } }
    }
    func waitForFetch(_ count: Int) async {
        if fetchCount < count { await withCheckedContinuation { fetchWaiters.append((count, $0)) } }
    }
    func waitForFirstStop() async {
        if stopCount == 0 { await withCheckedContinuation { stopWaiters.append($0) } }
    }
    func releaseFirstStop() { firstStopReleased = true; stopGate?.resume(); stopGate = nil }
    func releaseFetches() { fetchesReleased = true; fetchGates.forEach { $0.resume() }; fetchGates.removeAll() }
}
