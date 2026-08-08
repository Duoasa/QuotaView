import Combine
import Foundation
import QuotaViewCore
import SwiftUI

@MainActor
final class CodexStatusStore: ObservableObject {
    @Published private(set) var snapshot: CurrentCodexPresentation?
    @Published private(set) var providerState: ProviderLoadState
    @Published private(set) var isRefreshing = false
    @Published private(set) var providerError: ProviderError?
    private let coordinator: RefreshCoordinator
    private let providerID: ProviderID
    private let projector: CurrentCodexPresentationProjector
    private let diagnostics: UserDefaults
    private let widgetSnapshotWriter: QuotaViewWidgetSnapshotWriter
    private weak var preferences: AppPreferences?
    private var pollingTask: Task<Void, Never>?
    private var demandCancellable: AnyCancellable?
    private var widgetLocaleCancellable: AnyCancellable?

    init(
        provider: any UsageProviderAdapter,
        preferences: AppPreferences? = nil,
        diagnostics: UserDefaults = .standard,
        projector: CurrentCodexPresentationProjector =
            CurrentCodexPresentationProjector(),
        widgetSnapshotWriter: QuotaViewWidgetSnapshotWriter? = nil
    ) {
        let showsTokenUsage = preferences.map {
            $0.showDailyTokens || $0.showLifetimeTokens
        } ?? true
        let plan = Self.makeDemandPlan(
            providerID: provider.descriptor.id,
            includesTokenUsage: showsTokenUsage
        )

        self.coordinator = RefreshCoordinator(
            provider: provider,
            demand: plan
        )
        self.providerID = provider.descriptor.id
        self.providerState = .idle(lastSnapshot: nil)
        self.diagnostics = diagnostics
        self.projector = projector
        self.widgetSnapshotWriter =
            widgetSnapshotWriter ?? QuotaViewWidgetSnapshotWriter()
        self.preferences = preferences

        if let preferences {
            demandCancellable = Publishers.CombineLatest(
                preferences.$showDailyTokens,
                preferences.$showLifetimeTokens
            )
            .map { $0 || $1 }
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] includesTokenUsage in
                Task { @MainActor in
                    await self?.updateDemand(
                        includesTokenUsage: includesTokenUsage
                    )
                }
            }

            widgetLocaleCancellable = Publishers.CombineLatest3(
                preferences.$followsSystemLanguage,
                preferences.$customLanguage,
                preferences.$systemLocaleRevision
            )
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _ in
                self?.publishWidgetSnapshot()
            }
        }
    }

    var accessibilityStatus: String {
        if providerError != nil {
            return "QuotaView：Codex 数据连接不可用"
        }
        if let snapshot {
            return "Codex \(snapshot.availability.displayName)，剩余 \(snapshot.remainingPercent)%"
        }
        return "QuotaView 正在连接"
    }

    var hasCurrentCodexStatus: Bool {
        snapshot != nil && providerError == nil
    }

    var hasCodexSnapshot: Bool {
        snapshot != nil
    }

    var errorMessage: String? {
        providerError?.localizedDescription
    }

    func start() {
        guard pollingTask == nil else {
            return
        }

        pollingTask = Task { [weak self] in
            let clock = ContinuousClock()
            var nextTick = clock.now
            var isFirstRefresh = true

            while !Task.isCancelled {
                await self?.refresh(
                    reason: isFirstRefresh ? .startup : .background,
                    policy: .coalesce
                )
                isFirstRefresh = false

                nextTick += .seconds(60)
                let now = clock.now
                if nextTick <= now {
                    nextTick = now + .seconds(60)
                }

                do {
                    try await clock.sleep(until: nextTick)
                } catch {
                    break
                }
            }
        }
    }

    func refresh(
        reason: RefreshReason = .manual,
        policy: RefreshReplacementPolicy = .replace
    ) async {
        let previous = providerState.latestSnapshot
        providerState = .refreshing(previous: previous)
        isRefreshing = true

        let outcome = await coordinator.requestRefresh(
            reason: reason,
            policy: policy
        )

        switch outcome {
        case .applied(let result, _):
            guard let presentation =
                    projector.makePresentation(from: result)
            else {
                applyFailure(
                    .protocolViolation,
                    previous: previous
                )
                break
            }

            providerState = .available(result.snapshot)
            snapshot = presentation
            providerError = nil
            recordSuccess(presentation)
            publishWidgetSnapshot()

        case .failed(let error, _):
            applyFailure(error, previous: previous)

        case .disabled:
            applyFailure(
                .unavailable,
                previous: previous
            )

        case .stopped:
            snapshot = nil
            providerError = nil
            providerState = .idle(lastSnapshot: previous)

        case .discarded:
            break
        }

        isRefreshing = await coordinator.isRefreshing
        if !isRefreshing,
           case .refreshing(let previous) = providerState {
            providerState = .idle(lastSnapshot: previous)
        }
    }

    /// Invalidates presentation data when the user authorizes, replaces or
    /// disconnects the plugin data directory. A transient read error can keep
    /// the last valid snapshot, but a new bookmark must never inherit data
    /// from a previously paired plugin installation.
    func pluginDataConfigurationDidChange() async {
        await coordinator.configurationDidChange()
        snapshot = nil
        providerError = nil
        providerState = .idle(lastSnapshot: nil)
        clearPluginScopedDiagnostics()
        publishWidgetSnapshot()
        await refresh(
            reason: .configurationChanged,
            policy: .replace
        )
    }

    func stop() async {
        pollingTask?.cancel()
        pollingTask = nil
        await coordinator.stop()
        isRefreshing = false
    }

    private func applyFailure(
        _ error: ProviderError,
        previous: ProviderSnapshot?
    ) {
        providerState = .unavailable(
            previous: previous,
            error: error
        )
        // Keep the last valid presentation visible while the connection dot
        // and error state communicate that the newest refresh failed.
        // This avoids replacing real quota data with a fabricated zero or a
        // layout jump during transient plugin snapshot failures.
        providerError = error
        recordFailure(error)
        publishWidgetSnapshot()
    }

    private func recordSuccess(
        _ snapshot: CurrentCodexPresentation
    ) {
        diagnostics.set(
            snapshot.lastUpdatedAt.timeIntervalSince1970,
            forKey: "diagnostics.lastSuccessAt"
        )
        diagnostics.set(
            snapshot.usedPercent,
            forKey: "diagnostics.lastUsedPercent"
        )
        diagnostics.set(
            snapshot.availability.rawValue,
            forKey: "diagnostics.lastAvailability"
        )
        diagnostics.removeObject(
            forKey: "diagnostics.lastError"
        )
        diagnostics.removeObject(
            forKey: "diagnostics.lastErrorAt"
        )
    }

    private func recordFailure(_ error: Error) {
        diagnostics.set(
            error.localizedDescription,
            forKey: "diagnostics.lastError"
        )
        diagnostics.set(
            Date().timeIntervalSince1970,
            forKey: "diagnostics.lastErrorAt"
        )
    }

    private func clearPluginScopedDiagnostics() {
        for key in [
            "diagnostics.lastSuccessAt",
            "diagnostics.lastUsedPercent",
            "diagnostics.lastAvailability",
            "diagnostics.lastError",
            "diagnostics.lastErrorAt"
        ] {
            diagnostics.removeObject(forKey: key)
        }
    }

    private func updateDemand(
        includesTokenUsage: Bool
    ) async {
        let plan = Self.makeDemandPlan(
            providerID: providerID,
            includesTokenUsage: includesTokenUsage
        )
        await coordinator.updateDemand(plan)
        await refresh(
            reason: .configurationChanged,
            policy: .replace
        )
    }

    private static func makeDemandPlan(
        providerID: ProviderID,
        includesTokenUsage: Bool
    ) -> ProviderDemandPlan {
        var panelCapabilities: ProviderCapabilities = [
            .rateWindows,
            .balances
        ]
        if includesTokenUsage {
            panelCapabilities.formUnion([
                .currentUsage,
                .historicalUsage
            ])
        }

        let demandPlanner = DataDemandPlanner()
        let demands = [
            ConsumerDemand(
                consumer: .menuBar,
                providerID: providerID,
                capabilities: [.rateWindows],
                freshness: .interactive
            ),
            ConsumerDemand(
                consumer: .panel,
                providerID: providerID,
                capabilities: panelCapabilities,
                freshness: .interactive
            ),
            ConsumerDemand(
                consumer: .widget,
                providerID: providerID,
                capabilities: [
                    .rateWindows,
                    .balances,
                    .currentUsage,
                    .historicalUsage
                ],
                freshness: .background
            )
        ]

        return demandPlanner.plans(
            for: demands,
            enabledProviders: [providerID]
        )[providerID] ?? ProviderDemandPlan(
            providerID: providerID,
            capabilities: panelCapabilities,
            freshness: .interactive,
            consumers: [.menuBar, .panel, .widget]
        )
    }

    private func publishWidgetSnapshot() {
        let localeIdentifier = preferences?.resolvedLanguage
            .localeIdentifier
            ?? AppPreferences.Language.systemResolved.localeIdentifier
        widgetSnapshotWriter.publish(
            presentation: snapshot,
            isAvailable: hasCurrentCodexStatus,
            localeIdentifier: localeIdentifier
        )
    }
}
