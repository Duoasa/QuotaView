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
