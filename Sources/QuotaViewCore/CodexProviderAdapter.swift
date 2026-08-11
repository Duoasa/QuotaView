import Foundation

public enum CodexDomainCatalog {
    public static let providerID = ProviderID(rawValue: "codex")

    public static let providerEntity = EntityReference(
        id: EntityID(
            providerID: providerID,
            kind: .provider,
            nativeID: "account"
        ),
        kind: .provider
    )

    public static let primaryRateWindowID = EntityID(
        providerID: providerID,
        kind: .rateWindow,
        nativeID: "primary"
    )

    public static let sparkRateWindowID = EntityID(
        providerID: providerID,
        kind: .rateWindow,
        nativeID: "codex_bengalfox"
    )

    public static let usedFractionID = MetricID(
        providerID: providerID,
        namespace: "quota",
        name: "used-fraction"
    )
    public static let remainingFractionID = MetricID(
        providerID: providerID,
        namespace: "quota",
        name: "remaining-fraction"
    )
    public static let creditBalanceID = MetricID(
        providerID: providerID,
        namespace: "credits",
        name: "balance"
    )
    public static let resetCreditsID = MetricID(
        providerID: providerID,
        namespace: "quota",
        name: "reset-credits"
    )
    public static let lifetimeTokensID = MetricID(
        providerID: providerID,
        namespace: "tokens",
        name: "lifetime"
    )
    public static let dailyTokensID = MetricID(
        providerID: providerID,
        namespace: "tokens",
        name: "daily"
    )

    public static let definitions: [MetricDefinition] = [
        MetricDefinition(
            id: usedFractionID,
            labelKey: "codex.quota.used",
            valueKind: .percent,
            unit: .fraction,
            semantic: .gauge,
            allowedAggregations: [.latest, .minimum, .maximum, .average],
            sensitivity: .publicSummary,
            defaultDisplayPriority: 0
        ),
        MetricDefinition(
            id: remainingFractionID,
            labelKey: "codex.quota.remaining",
            valueKind: .percent,
            unit: .fraction,
            semantic: .gauge,
            allowedAggregations: [.latest, .minimum, .maximum, .average],
            sensitivity: .publicSummary,
            defaultDisplayPriority: 1
        ),
        MetricDefinition(
            id: creditBalanceID,
            labelKey: "codex.credits.balance",
            valueKind: .decimal,
            unit: .credits,
            semantic: .gauge,
            allowedAggregations: [.latest, .minimum, .maximum],
            sensitivity: .privateUsage,
            defaultDisplayPriority: 2
        ),
        MetricDefinition(
            id: resetCreditsID,
            labelKey: "codex.quota.resetCredits",
            valueKind: .count,
            unit: .count,
            semantic: .gauge,
            allowedAggregations: [.latest, .minimum, .maximum],
            sensitivity: .privateUsage,
            defaultDisplayPriority: 3
        ),
        MetricDefinition(
            id: lifetimeTokensID,
            labelKey: "codex.tokens.lifetime",
            valueKind: .count,
            unit: .tokens,
            semantic: .cumulativeCounter,
            allowedAggregations: [.latest, .delta],
            sensitivity: .privateUsage,
            defaultDisplayPriority: 4
        ),
        MetricDefinition(
            id: dailyTokensID,
            labelKey: "codex.tokens.daily",
            valueKind: .count,
            unit: .tokens,
            semantic: .intervalTotal,
            allowedAggregations: [.latest, .sum, .minimum, .maximum, .average],
            sensitivity: .privateUsage,
            defaultDisplayPriority: 5
        )
    ]
}

public struct CodexProviderAdapter: UsageProviderAdapter, Sendable {
    public let descriptor = ProviderDescriptor(
        id: CodexDomainCatalog.providerID,
        displayName: "Codex",
        capabilities: .currentQuotaViewFeatures,
        sourceKinds: [.localAppServer],
        resourceProfile: ProviderResourceProfile(
            minimumRefreshInterval: 60,
            startsSubprocess: true,
            typicalTimeout: 15,
            permitsParallelEnrichment: true,
            lowPowerMinimumInterval: 1_800
        ),
        supportsStableAccountScope: false
    )

    private let client: CodexAppServerClient

    public init(
        client: CodexAppServerClient = CodexAppServerClient()
    ) {
        self.client = client
    }

    public func availability() async -> ProviderAvailability {
        .available
    }

    public func fetch(
        _ request: ProviderFetchRequest
    ) async throws -> ProviderFetchResult {
        try Task.checkCancellation()

        let startedAt = Date()
        let includeUsage = request.capabilities.contains(.currentUsage)
            || request.capabilities.contains(.historicalUsage)
        let payload: CodexProviderPayload

        do {
            payload = try await client.fetchPayload(
                now: Date(),
                includeUsage: includeUsage
            )
        } catch {
            throw Self.mapClientError(error)
        }

        try Task.checkCancellation()
        let result = try Self.makeResult(
            payload: payload,
            duration: Date().timeIntervalSince(startedAt)
        )

        guard Date() <= request.deadline else {
            throw ProviderError.timedOut(stage: .fetch)
        }
        return result
    }

    public func stop() async {
        await client.stop()
    }

    public static func makeResult(
        payload: CodexProviderPayload,
        duration: TimeInterval = 0
    ) throws -> ProviderFetchResult {
        let limits = payload.rateLimits.rateLimitsByLimitId?["codex"]
            ?? payload.rateLimits.rateLimits

        guard let primary = limits.primary,
              let usedPercent = primary.usedPercent
        else {
            throw ProviderError.protocolViolation
        }
        guard (0...100).contains(usedPercent) else {
            throw ProviderError.protocolViolation
        }

        let usedFraction = Double(usedPercent) / 100
        let remainingFraction = 1 - usedFraction
        let reached = limits.rateLimitReachedType != nil
            || limits.spendControlReached == true
        let quotaRisk: QuotaRisk

        if reached || usedPercent >= 100 {
            quotaRisk = .exhausted
        } else if usedPercent >= 85 {
            quotaRisk = .warning
        } else {
            quotaRisk = .normal
        }

        let capturedAt = payload.capturedAt
        let rateWindow = RateWindow(
            id: CodexDomainCatalog.primaryRateWindowID,
            titleKey: "codex.quota.primary",
            period: primary.windowDurationMins.map {
                .duration(minutes: $0)
            } ?? .providerDefined,
            startsAt: nil,
            resetsAt: primary.resetsAt.map {
                Date(timeIntervalSince1970: TimeInterval($0))
            },
            usedFraction: usedFraction,
            remainingFraction: remainingFraction,
            sourcePrecision: .providerRounded,
            quotaRisk: quotaRisk
        )
        let sparkRateWindow = makeSparkRateWindow(
            from: payload.rateLimits
        )

        var currentMetrics: [MetricSample] = [
            sample(
                id: CodexDomainCatalog.usedFractionID,
                value: .percent(usedFraction),
                observedAt: capturedAt
            ),
            sample(
                id: CodexDomainCatalog.remainingFractionID,
                value: .percent(remainingFraction),
                observedAt: capturedAt
            )
        ]

        if let availableCount = payload.rateLimits
            .rateLimitResetCredits?.availableCount {
            guard availableCount >= 0 else {
                throw ProviderError.protocolViolation
            }
            currentMetrics.append(
                sample(
                    id: CodexDomainCatalog.resetCreditsID,
                    value: .count(Int64(availableCount)),
                    observedAt: capturedAt
                )
            )
        }

        let credits = limits.credits
        var balances: [Balance] = []
        if let credits {
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
                        observedAt: capturedAt
                    )
                )
            }
        }

        if let lifetimeTokens = payload.usage?.summary.lifetimeTokens {
            currentMetrics.append(
                sample(
                    id: CodexDomainCatalog.lifetimeTokensID,
                    value: .count(lifetimeTokens),
                    observedAt: capturedAt
                )
            )
        }

        let observations = makeDailyObservations(
            buckets: payload.usage?.dailyUsageBuckets ?? [],
            receivedAt: capturedAt
        )
        if let latestDaily = observations.max(
            by: { $0.observedAt < $1.observedAt }
        ) {
            currentMetrics.append(
                sample(
                    id: CodexDomainCatalog.dailyTokensID,
                    value: latestDaily.value,
                    observedAt: capturedAt
                )
            )
        }

        let plan = limits.planType
            .map { raw in
                PlanDescriptor(
                    rawValue: raw,
                    displayName: raw
                )
            }
        let snapshot = ProviderSnapshot(
            schemaVersion: 1,
            providerID: CodexDomainCatalog.providerID,
            capturedAt: capturedAt,
            availability: .available,
            accountScope: nil,
            plan: plan,
            rateWindows: [rateWindow] + [sparkRateWindow].compactMap { $0 },
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
                sourceLabel: "codex-app-server",
                duration: duration,
                optionalIssues: payload.optionalIssues
            )
        )
    }

    private static func makeSparkRateWindow(
        from response: AccountRateLimitsResponse
    ) -> RateWindow? {
        guard let limits = response
                .rateLimitsByLimitId?["codex_bengalfox"],
              let window = limits.primary,
              let usedPercent = window.usedPercent,
              (0...100).contains(usedPercent)
        else {
            return nil
        }

        let usedFraction = Double(usedPercent) / 100
        let remainingFraction = 1 - usedFraction
        let reached = limits.rateLimitReachedType != nil
            || limits.spendControlReached == true
        let quotaRisk: QuotaRisk

        if reached || usedPercent >= 100 {
            quotaRisk = .exhausted
        } else if usedPercent >= 85 {
            quotaRisk = .warning
        } else {
            quotaRisk = .normal
        }

        return RateWindow(
            id: CodexDomainCatalog.sparkRateWindowID,
            titleKey: "codex.quota.spark.weekly",
            period: window.windowDurationMins.map {
                .duration(minutes: $0)
            } ?? .providerDefined,
            startsAt: nil,
            resetsAt: window.resetsAt.map {
                Date(timeIntervalSince1970: TimeInterval($0))
            },
            usedFraction: usedFraction,
            remainingFraction: remainingFraction,
            sourcePrecision: .providerRounded,
            quotaRisk: quotaRisk
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

    private static func makeDailyObservations(
        buckets: [AccountTokenUsageDailyBucket],
        receivedAt: Date
    ) -> [MetricObservation] {
        let formatter = DateFormatter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        return buckets.compactMap { bucket in
            guard bucket.tokens >= 0,
                  let start = formatter.date(from: bucket.startDate),
                  let end = calendar.date(
                    byAdding: .day,
                    value: 1,
                    to: start
                  )
            else {
                return nil
            }

            return MetricObservation(
                definitionID: CodexDomainCatalog.dailyTokensID,
                entity: CodexDomainCatalog.providerEntity,
                value: .count(bucket.tokens),
                interval: DateInterval(start: start, end: end),
                observedAt: start,
                receivedAt: receivedAt,
                source: .providerHistoricalBucket,
                precision: .exact
            )
        }
    }

    private static func mapClientError(_ error: Error) -> ProviderError {
        guard let clientError =
                error as? CodexAppServerClient.ClientError
        else {
            if error is CancellationError {
                return .cancelled
            }
            return .transient(
                SanitizedErrorSummary(error.localizedDescription)
            )
        }

        switch clientError {
        case .executableNotFound:
            return .notConfigured
        case .requestTimedOut:
            return .timedOut(stage: .fetch)
        case .messageTooLarge, .invalidMessage:
            return .protocolViolation
        case .cancelled:
            return .cancelled
        case .connectionClosed, .launchFailed:
            return .unavailable
        case .server(let code, let message):
            if code == 401 || code == 403 {
                return .permissionDenied
            }
            return .transient(
                SanitizedErrorSummary(message)
            )
        }
    }
}
