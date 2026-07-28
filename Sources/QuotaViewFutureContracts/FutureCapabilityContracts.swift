import Foundation
import QuotaViewCore

public struct ChartID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct ChartDescriptor: Equatable, Sendable, Identifiable {
    public let id: ChartID
    public let titleKey: String
    public let requiredMetricIDs: Set<MetricID>
    public let supportedEntityKinds: Set<EntityKind>
    public let preferredAggregation: MetricAggregation
    public let maximumPointCount: Int

    public init(
        id: ChartID,
        titleKey: String,
        requiredMetricIDs: Set<MetricID>,
        supportedEntityKinds: Set<EntityKind>,
        preferredAggregation: MetricAggregation,
        maximumPointCount: Int
    ) {
        self.id = id
        self.titleKey = titleKey
        self.requiredMetricIDs = requiredMetricIDs
        self.supportedEntityKinds = supportedEntityKinds
        self.preferredAggregation = preferredAggregation
        self.maximumPointCount = max(maximumPointCount, 1)
    }
}

/// Stable IDs allow future settings to add metrics and charts without
/// coupling persistence to individual SwiftUI switches.
public struct DisplayPreferences:
    Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public var enabledProviders: Set<ProviderID>
    public var panelMetricIDs: [MetricID]
    public var visibleChartIDs: [ChartID]
    public var menuBarMetricIDs: [MetricID]
    public var widgetMetricIDs: [MetricID]

    public init(
        schemaVersion: Int = 1,
        enabledProviders: Set<ProviderID>,
        panelMetricIDs: [MetricID],
        visibleChartIDs: [ChartID],
        menuBarMetricIDs: [MetricID],
        widgetMetricIDs: [MetricID]
    ) {
        self.schemaVersion = schemaVersion
        self.enabledProviders = enabledProviders
        self.panelMetricIDs = panelMetricIDs
        self.visibleChartIDs = visibleChartIDs
        self.menuBarMetricIDs = menuBarMetricIDs
        self.widgetMetricIDs = widgetMetricIDs
    }
}

public struct HistoryQuery: Equatable, Sendable {
    public let providerID: ProviderID
    public let accountScopeID: String?
    public let metricIDs: Set<MetricID>
    public let entityIDs: Set<EntityID>
    public let interval: DateInterval
    public let maximumPointCount: Int

    public init(
        providerID: ProviderID,
        accountScopeID: String?,
        metricIDs: Set<MetricID>,
        entityIDs: Set<EntityID>,
        interval: DateInterval,
        maximumPointCount: Int
    ) {
        self.providerID = providerID
        self.accountScopeID = accountScopeID
        self.metricIDs = metricIDs
        self.entityIDs = entityIDs
        self.interval = interval
        self.maximumPointCount = max(maximumPointCount, 1)
    }
}

public protocol MetricHistoryStoring: Sendable {
    func ingest(
        _ observations: [MetricObservation]
    ) async throws

    func observations(
        matching query: HistoryQuery
    ) async throws -> [MetricObservation]

    func removeAll(
        for providerID: ProviderID
    ) async throws

    func stop() async
}

/// Used until bounded SQLite history is implemented. It deliberately does
/// not touch disk and therefore preserves the current lightweight behavior.
public struct DisabledMetricHistoryStore:
    MetricHistoryStoring, Sendable {
    public init() {}

    public func ingest(
        _ observations: [MetricObservation]
    ) async throws {}

    public func observations(
        matching query: HistoryQuery
    ) async throws -> [MetricObservation] {
        []
    }

    public func removeAll(
        for providerID: ProviderID
    ) async throws {}

    public func stop() async {}
}

public enum QuotaNotificationEvent: Equatable, Sendable {
    case thresholdCrossed(
        providerID: ProviderID,
        windowID: EntityID,
        remainingFraction: Double
    )
    case exhausted(
        providerID: ProviderID,
        windowID: EntityID
    )
    case cycleReset(
        providerID: ProviderID,
        windowID: EntityID
    )
    case recovered(providerID: ProviderID)
    case serviceHealthChanged(
        providerID: ProviderID,
        health: ServiceHealth
    )
}

public struct NotificationCycleState:
    Equatable, Codable, Sendable {
    public let providerID: ProviderID
    public let accountScopeID: String
    public let windowID: String
    public let cycleID: String
    public var deliveredEventKeys: Set<String>
    public var unavailableSince: Date?
    public var lastSuccessfulAt: Date?

    public init(
        providerID: ProviderID,
        accountScopeID: String,
        windowID: String,
        cycleID: String,
        deliveredEventKeys: Set<String> = [],
        unavailableSince: Date? = nil,
        lastSuccessfulAt: Date? = nil
    ) {
        self.providerID = providerID
        self.accountScopeID = accountScopeID
        self.windowID = windowID
        self.cycleID = cycleID
        self.deliveredEventKeys = deliveredEventKeys
        self.unavailableSince = unavailableSince
        self.lastSuccessfulAt = lastSuccessfulAt
    }
}

public protocol QuotaNotificationEvaluating: Sendable {
    func events(
        from previous: ProviderSnapshot?,
        to current: ProviderSnapshot,
        now: Date
    ) -> [QuotaNotificationEvent]
}

public protocol QuotaNotificationScheduling: Sendable {
    func schedule(
        _ events: [QuotaNotificationEvent]
    ) async

    func stop() async
}

/// Notification permission and scheduling are intentionally absent in 0.2.0.
public struct DisabledQuotaNotificationScheduler:
    QuotaNotificationScheduling, Sendable {
    public init() {}

    public func schedule(
        _ events: [QuotaNotificationEvent]
    ) async {}

    public func stop() async {}
}
