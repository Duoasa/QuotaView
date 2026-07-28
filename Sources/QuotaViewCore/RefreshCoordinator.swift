import Foundation

public enum RefreshReplacementPolicy: Sendable {
    case coalesce
    case replace
}

public enum RefreshCoordinatorResult: Sendable {
    case applied(
        result: ProviderFetchResult,
        context: PublicationContext
    )
    case failed(
        error: ProviderError,
        context: PublicationContext
    )
    case discarded
    case disabled
    case stopped
}

public actor RefreshCoordinator {
    private struct ActiveRefresh {
        let context: PublicationContext
        let task: Task<ProviderFetchResult, Error>
    }

    private struct CompletedRefresh {
        let context: PublicationContext
        let outcome: RefreshCoordinatorResult
    }

    public nonisolated let providerID: ProviderID

    private let provider: any UsageProviderAdapter
    private var generation: UInt64 = 0
    private var enablementRevision: UInt64 = 0
    private var configurationRevision: UInt64 = 0
    private var enabled: Bool
    private var demand: ProviderDemandPlan
    private var expectedAccountScope: String?
    private var activeRefresh: ActiveRefresh?
    private var lastCompletedRefresh: CompletedRefresh?
    private var isStopped = false

    public init(
        provider: any UsageProviderAdapter,
        enabled: Bool = true,
        demand: ProviderDemandPlan
    ) {
        self.provider = provider
        self.providerID = provider.descriptor.id
        self.enabled = enabled
        self.demand = demand
    }

    public var isRefreshing: Bool {
        activeRefresh != nil
    }

    public func requestRefresh(
        reason: RefreshReason,
        policy: RefreshReplacementPolicy
    ) async -> RefreshCoordinatorResult {
        guard !isStopped else {
            return .stopped
        }
        guard enabled, !demand.capabilities.isEmpty else {
            return .disabled
        }

        if let activeRefresh {
            switch policy {
            case .coalesce:
                return await finish(activeRefresh)
            case .replace:
                activeRefresh.task.cancel()
                generation &+= 1
                self.activeRefresh = nil
                await provider.stop()
            }
        }

        generation &+= 1
        let context = PublicationContext(
            providerID: providerID,
            generation: generation,
            enablementRevision: enablementRevision,
            configurationRevision: configurationRevision,
            requestedCapabilities: demand.capabilities,
            expectedAccountScope: expectedAccountScope
        )
        let timeout = timeoutInterval(for: reason)
        let request = ProviderFetchRequest(
            generation: context.generation,
            enablementRevision: context.enablementRevision,
            configurationRevision: context.configurationRevision,
            reason: reason,
            deadline: Date().addingTimeInterval(timeout),
            capabilities: context.requestedCapabilities,
            expectedAccountScope: context.expectedAccountScope,
            correlationID: UUID().uuidString
        )
        let provider = self.provider
        let task = Task.detached(priority: .utility) {
            try Task.checkCancellation()

            switch await provider.availability() {
            case .available:
                break
            case .unavailable(let error):
                throw error
            }

            try Task.checkCancellation()
            return try await provider.fetch(request)
        }
        let active = ActiveRefresh(context: context, task: task)
        activeRefresh = active
        return await finish(active)
    }

    public func setEnabled(_ newValue: Bool) async {
        guard enabled != newValue else {
            return
        }

        enabled = newValue
        enablementRevision &+= 1
        generation &+= 1

        guard !newValue else {
            return
        }

        activeRefresh?.task.cancel()
        activeRefresh = nil
        expectedAccountScope = nil
        await provider.stop()
    }

    public func updateDemand(_ newDemand: ProviderDemandPlan) async {
        guard demand != newDemand else {
            return
        }

        demand = newDemand
        configurationRevision &+= 1
        generation &+= 1
        activeRefresh?.task.cancel()
        activeRefresh = nil
        await provider.stop()
    }

    public func configurationDidChange() async {
        configurationRevision &+= 1
        generation &+= 1
        expectedAccountScope = nil
        activeRefresh?.task.cancel()
        activeRefresh = nil
        await provider.stop()
    }

    public func stop() async {
        guard !isStopped else {
            return
        }

        isStopped = true
        generation &+= 1
        activeRefresh?.task.cancel()
        activeRefresh = nil
        await provider.stop()
    }

    private func finish(
        _ active: ActiveRefresh
    ) async -> RefreshCoordinatorResult {
        do {
            let result = try await active.task.value

            if let completed = lastCompletedRefresh,
               completed.context == active.context {
                return completed.outcome
            }
            guard canPublish(active.context) else {
                return .discarded
            }
            guard accountScopeMatches(
                result.snapshot.accountScope,
                context: active.context
            ) else {
                activeRefresh = nil
                generation &+= 1
                expectedAccountScope = result.snapshot.accountScope?
                    .pseudonymousID
                return .discarded
            }

            activeRefresh = nil
            if result.snapshot.accountScope?.stability == .stable {
                expectedAccountScope = result.snapshot.accountScope?
                    .pseudonymousID
            }
            let outcome = RefreshCoordinatorResult.applied(
                result: result,
                context: active.context
            )
            lastCompletedRefresh = CompletedRefresh(
                context: active.context,
                outcome: outcome
            )
            return outcome
        } catch {
            if let completed = lastCompletedRefresh,
               completed.context == active.context {
                return completed.outcome
            }
            guard canPublish(active.context) else {
                return .discarded
            }

            activeRefresh = nil
            let outcome = RefreshCoordinatorResult.failed(
                error: Self.mapError(error),
                context: active.context
            )
            lastCompletedRefresh = CompletedRefresh(
                context: active.context,
                outcome: outcome
            )
            return outcome
        }
    }

    private func canPublish(_ context: PublicationContext) -> Bool {
        guard !isStopped,
              enabled,
              generation == context.generation,
              enablementRevision == context.enablementRevision,
              configurationRevision == context.configurationRevision,
              demand.capabilities == context.requestedCapabilities,
              expectedAccountScope == context.expectedAccountScope,
              activeRefresh?.context == context
        else {
            return false
        }

        return true
    }

    private func accountScopeMatches(
        _ accountScope: AccountScope?,
        context: PublicationContext
    ) -> Bool {
        guard let expected = context.expectedAccountScope else {
            return true
        }

        return accountScope?.pseudonymousID == expected
    }

    private func timeoutInterval(
        for reason: RefreshReason
    ) -> TimeInterval {
        let typical = max(
            provider.descriptor.resourceProfile.typicalTimeout,
            1
        )

        if reason == .startup {
            return max(typical, 45)
        }
        return typical
    }

    private nonisolated static func mapError(
        _ error: Error
    ) -> ProviderError {
        if let providerError = error as? ProviderError {
            return providerError
        }
        if error is CancellationError {
            return .cancelled
        }
        return .transient(
            SanitizedErrorSummary(error.localizedDescription)
        )
    }
}
