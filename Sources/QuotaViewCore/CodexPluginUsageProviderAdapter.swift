import Foundation

public struct CodexPluginUsageProviderAdapter:
    UsageProviderAdapter,
    Sendable
{
    public typealias SnapshotLoader = @Sendable () async throws
        -> CodexPluginUsageSnapshot

    public let descriptor = ProviderDescriptor(
        id: CodexDomainCatalog.providerID,
        displayName: "Codex",
        capabilities: .currentQuotaViewFeatures,
        sourceKinds: [.pluginSanitizedSnapshot],
        resourceProfile: ProviderResourceProfile(
            minimumRefreshInterval: 60,
            startsSubprocess: false,
            typicalTimeout: 2,
            permitsParallelEnrichment: false,
            lowPowerMinimumInterval: 1_800
        ),
        supportsStableAccountScope: false
    )

    private let loadSnapshot: SnapshotLoader
    private let now: @Sendable () -> Date

    public init(
        loadSnapshot: @escaping SnapshotLoader,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.loadSnapshot = loadSnapshot
        self.now = now
    }

    public func availability() async -> ProviderAvailability {
        .available
    }

    public func fetch(
        _ request: ProviderFetchRequest
    ) async throws -> ProviderFetchResult {
        try Task.checkCancellation()
        guard now() <= request.deadline else {
            throw ProviderError.timedOut(stage: .fetch)
        }

        let startedAt = now()
        let usage: CodexPluginUsageSnapshot
        do {
            usage = try await loadSnapshot()
        } catch let error as ProviderError {
            throw error
        } catch let error as CodexPluginBridgeValidationError {
            throw Self.mapValidationError(error)
        } catch is CancellationError {
            throw ProviderError.cancelled
        } catch {
            throw ProviderError.unavailable
        }

        try Task.checkCancellation()
        guard now() <= request.deadline else {
            throw ProviderError.timedOut(stage: .fetch)
        }
        return try Self.makeResult(
            usage: usage,
            duration: now().timeIntervalSince(startedAt)
        )
    }

    public func stop() async {}

    public static func makeResult(
        usage: CodexPluginUsageSnapshot,
        duration: TimeInterval = 0
    ) throws -> ProviderFetchResult {
        let usedPercent = usage.primary.usedPercent
        guard (0...100).contains(usedPercent) else {
            throw ProviderError.protocolViolation
        }

        let usedFraction = Double(usedPercent) / 100
        let remainingFraction = 1 - usedFraction
        let quotaRisk: QuotaRisk
        if usage.limitReached || usedPercent >= 100 {
            quotaRisk = .exhausted
        } else if usedPercent >= 85 {
            quotaRisk = .warning
        } else {
            quotaRisk = .normal
        }

        let rateWindow = RateWindow(
            id: CodexDomainCatalog.primaryRateWindowID,
            titleKey: "codex.quota.primary",
            period: usage.primary.windowDurationMins.map {
                .duration(minutes: $0)
            } ?? .providerDefined,
            startsAt: nil,
            resetsAt: usage.primary.resetsAt.map {
                Date(timeIntervalSince1970: TimeInterval($0))
            },
            usedFraction: usedFraction,
            remainingFraction: remainingFraction,
            sourcePrecision: .providerRounded,
            quotaRisk: quotaRisk
        )

        var currentMetrics = [
            sample(
                id: CodexDomainCatalog.usedFractionID,
                value: .percent(usedFraction),
                observedAt: usage.capturedAt
            ),
            sample(
                id: CodexDomainCatalog.remainingFractionID,
                value: .percent(remainingFraction),
                observedAt: usage.capturedAt
            )
        ]
        var balances: [Balance] = []

        if let credits = usage.credits {
            let decimalValue = credits.balance.flatMap {
                Decimal(
                    string: $0,
                    locale: Locale(identifier: "en_US_POSIX")
                )
            }
            balances.append(
                Balance(
                    id: CodexDomainCatalog.creditBalanceID.rawValue,
                    kind: .credits,
                    value: decimalValue.map(MetricValue.decimal),
                    hasBalance: credits.hasCredits,
                    isUnlimited: credits.unlimited
                )
            )
            if let decimalValue {
                currentMetrics.append(
                    sample(
                        id: CodexDomainCatalog.creditBalanceID,
                        value: .decimal(decimalValue),
                        observedAt: usage.capturedAt
                    )
                )
            }
        }

        if let lifetimeTokens = usage.lifetimeTokens {
            currentMetrics.append(
                sample(
                    id: CodexDomainCatalog.lifetimeTokensID,
                    value: .count(lifetimeTokens),
                    observedAt: usage.capturedAt
                )
            )
        }

        let observations = dailyObservation(from: usage)
        if let observation = observations.first {
            currentMetrics.append(
                sample(
                    id: CodexDomainCatalog.dailyTokensID,
                    value: observation.value,
                    observedAt: usage.capturedAt
                )
            )
        }

        let plan = usage.planType.flatMap { raw -> PlanDescriptor? in
            let trimmed = raw.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !trimmed.isEmpty else { return nil }
            return PlanDescriptor(rawValue: trimmed, displayName: trimmed)
        }
        let snapshot = ProviderSnapshot(
            schemaVersion: 1,
            providerID: CodexDomainCatalog.providerID,
            capturedAt: usage.capturedAt,
            availability: .available,
            accountScope: nil,
            plan: plan,
            rateWindows: [rateWindow],
            balances: balances,
            currentMetrics: currentMetrics,
            models: [],
            agents: [],
            serviceHealth: .unknown
        )

        return ProviderFetchResult(
            snapshot: snapshot,
            historicalObservations: observations,
            diagnostics: SanitizedFetchDiagnostics(
                sourceLabel: "codex-plugin-snapshot",
                duration: duration,
                optionalIssues: []
            )
        )
    }

    private static func sample(
        id: MetricID,
        value: MetricValue,
        observedAt: Date
    ) -> MetricSample {
        MetricSample(
            definitionID: id,
            entity: CodexDomainCatalog.providerEntity,
            value: value,
            availability: .available,
            observedAt: observedAt
        )
    }

    private static func dailyObservation(
        from usage: CodexPluginUsageSnapshot
    ) -> [MetricObservation] {
        guard let tokenCount = usage.recentDailyTokens,
              let dateString = usage.recentDailyDate,
              let start = dayFormatter.date(from: dateString),
              let end = calendar.date(
                  byAdding: .day,
                  value: 1,
                  to: start
              )
        else {
            return []
        }
        return [
            MetricObservation(
                definitionID: CodexDomainCatalog.dailyTokensID,
                entity: CodexDomainCatalog.providerEntity,
                value: .count(tokenCount),
                interval: DateInterval(start: start, end: end),
                observedAt: start,
                receivedAt: usage.capturedAt,
                source: .providerHistoricalBucket,
                precision: .exact
            )
        ]
    }

    private static func mapValidationError(
        _ error: CodexPluginBridgeValidationError
    ) -> ProviderError {
        switch error {
        case .missingUsageCapability:
            .notConfigured
        case .usageSnapshotMissing:
            .authenticationRequired
        case .incompatibleProtocol, .incompatibleUsageSchema:
            .unsupportedSchema
        case .usageSnapshotExpired:
            .unavailable
        case .oversized, .malformed, .installationMismatch,
             .invalidUsageSnapshot, .eventFromFuture:
            .protocolViolation
        default:
            .unavailable
        }
    }

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }()
}
