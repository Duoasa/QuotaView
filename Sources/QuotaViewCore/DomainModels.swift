import Foundation

public struct ProviderID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct MetricID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(
        providerID: ProviderID,
        namespace: String,
        name: String
    ) {
        self.rawValue = [
            providerID.rawValue,
            namespace,
            name
        ].joined(separator: ".")
    }
}

public enum EntityKind: String, Codable, Hashable, Sendable {
    case provider
    case rateWindow
    case model
    case agent
}

public struct EntityID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(
        providerID: ProviderID,
        kind: EntityKind,
        nativeID: String
    ) {
        self.rawValue = [
            providerID.rawValue,
            kind.rawValue,
            nativeID
        ].joined(separator: ".")
    }
}

public struct EntityReference: Hashable, Codable, Sendable {
    public let id: EntityID
    public let kind: EntityKind

    public init(id: EntityID, kind: EntityKind) {
        self.id = id
        self.kind = kind
    }
}

public enum AccountScopeStability: String, Codable, Sendable {
    case stable
    case currentProcessOnly
    case unavailable
}

public struct AccountScope: Equatable, Codable, Sendable {
    public let pseudonymousID: String
    public let stability: AccountScopeStability

    public init(
        pseudonymousID: String,
        stability: AccountScopeStability
    ) {
        self.pseudonymousID = pseudonymousID
        self.stability = stability
    }
}

public enum UnavailableReason: String, Codable, Sendable {
    case noSnapshot
    case providerDisabled
    case requiredDataMissing
    case timedOut
    case connectionFailed
    case unsupportedSchema
    case permissionDenied
    case unknown
}

public enum DataAvailability: Equatable, Sendable {
    case available
    case unavailable(reason: UnavailableReason)
}

public enum QuotaRisk: String, Codable, Sendable {
    case normal
    case warning
    case exhausted
    case unknown
}

public enum ServiceHealth: String, Codable, Sendable {
    case operational
    case degraded
    case outage
    case unknown
}

public struct PlanDescriptor: Equatable, Sendable {
    public let rawValue: String
    public let displayName: String

    public init(rawValue: String, displayName: String) {
        self.rawValue = rawValue
        self.displayName = displayName
    }
}

public enum WindowPeriod: Equatable, Sendable {
    case duration(minutes: Int)
    case providerDefined
}

public enum SourcePrecision: String, Codable, Sendable {
    case exact
    case providerRounded
    case derived
    case unknown
}

public struct RateWindow: Equatable, Sendable, Identifiable {
    public let id: EntityID
    public let titleKey: String
    public let period: WindowPeriod
    public let startsAt: Date?
    public let resetsAt: Date?
    public let usedFraction: Double?
    public let remainingFraction: Double?
    public let sourcePrecision: SourcePrecision
    public let quotaRisk: QuotaRisk

    public init(
        id: EntityID,
        titleKey: String,
        period: WindowPeriod,
        startsAt: Date?,
        resetsAt: Date?,
        usedFraction: Double?,
        remainingFraction: Double?,
        sourcePrecision: SourcePrecision,
        quotaRisk: QuotaRisk
    ) {
        self.id = id
        self.titleKey = titleKey
        self.period = period
        self.startsAt = startsAt
        self.resetsAt = resetsAt
        self.usedFraction = usedFraction
        self.remainingFraction = remainingFraction
        self.sourcePrecision = sourcePrecision
        self.quotaRisk = quotaRisk
    }
}

public enum MetricValueKind: String, Codable, Sendable {
    case percent
    case count
    case decimal
    case duration
    case timestamp
    case text
    case flag
}

public enum MetricUnit: Hashable, Sendable {
    case fraction
    case count
    case tokens
    case credits
    case seconds
    case timestamp
    case text
    case boolean
    case currency(code: String)
    case custom(String)
}

public enum MetricSemantic: String, Codable, Sendable {
    case gauge
    case intervalTotal
    case cumulativeCounter
    case eventCount
    case state
}

public enum MetricAggregation: String, Codable, Hashable, Sendable {
    case latest
    case minimum
    case maximum
    case average
    case sum
    case delta
}

public enum MetricSensitivity: String, Codable, Sendable {
    case publicSummary
    case privateUsage
    case restricted
}

public enum MetricValue: Equatable, Sendable {
    case percent(Double)
    case count(Int64)
    case decimal(Decimal)
    case duration(TimeInterval)
    case timestamp(Date)
    case text(String)
    case flag(Bool)
}

public struct MetricDefinition: Equatable, Sendable, Identifiable {
    public let id: MetricID
    public let labelKey: String
    public let valueKind: MetricValueKind
    public let unit: MetricUnit
    public let semantic: MetricSemantic
    public let allowedAggregations: Set<MetricAggregation>
    public let sensitivity: MetricSensitivity
    public let defaultDisplayPriority: Int

    public init(
        id: MetricID,
        labelKey: String,
        valueKind: MetricValueKind,
        unit: MetricUnit,
        semantic: MetricSemantic,
        allowedAggregations: Set<MetricAggregation>,
        sensitivity: MetricSensitivity,
        defaultDisplayPriority: Int
    ) {
        self.id = id
        self.labelKey = labelKey
        self.valueKind = valueKind
        self.unit = unit
        self.semantic = semantic
        self.allowedAggregations = allowedAggregations
        self.sensitivity = sensitivity
        self.defaultDisplayPriority = defaultDisplayPriority
    }
}

public struct MetricSample: Equatable, Sendable, Identifiable {
    public var id: String {
        [
            definitionID.rawValue,
            entity.id.rawValue,
            String(observedAt.timeIntervalSince1970)
        ].joined(separator: ":")
    }

    public let definitionID: MetricID
    public let entity: EntityReference
    public let value: MetricValue?
    public let availability: DataAvailability
    public let observedAt: Date

    public init(
        definitionID: MetricID,
        entity: EntityReference,
        value: MetricValue?,
        availability: DataAvailability,
        observedAt: Date
    ) {
        self.definitionID = definitionID
        self.entity = entity
        self.value = value
        self.availability = availability
        self.observedAt = observedAt
    }
}

public enum ObservationSource: String, Codable, Sendable {
    case sampledSnapshot
    case providerHistoricalBucket
    case derived
}

public struct MetricObservation: Equatable, Sendable {
    public let definitionID: MetricID
    public let entity: EntityReference
    public let value: MetricValue
    public let interval: DateInterval?
    public let observedAt: Date
    public let receivedAt: Date
    public let source: ObservationSource
    public let precision: SourcePrecision

    public init(
        definitionID: MetricID,
        entity: EntityReference,
        value: MetricValue,
        interval: DateInterval?,
        observedAt: Date,
        receivedAt: Date,
        source: ObservationSource,
        precision: SourcePrecision
    ) {
        self.definitionID = definitionID
        self.entity = entity
        self.value = value
        self.interval = interval
        self.observedAt = observedAt
        self.receivedAt = receivedAt
        self.source = source
        self.precision = precision
    }
}

public enum BalanceKind: String, Codable, Sendable {
    case credits
    case currency
    case providerDefined
}

public struct Balance: Equatable, Sendable, Identifiable {
    public let id: String
    public let kind: BalanceKind
    public let value: MetricValue?
    public let hasBalance: Bool
    public let isUnlimited: Bool

    public init(
        id: String,
        kind: BalanceKind,
        value: MetricValue?,
        hasBalance: Bool,
        isUnlimited: Bool
    ) {
        self.id = id
        self.kind = kind
        self.value = value
        self.hasBalance = hasBalance
        self.isUnlimited = isUnlimited
    }
}

public struct UsageEntity: Equatable, Sendable, Identifiable {
    public let id: EntityID
    public let displayName: String
    public let kind: EntityKind
    public let capabilities: Set<String>
    public let metrics: [MetricSample]

    public init(
        id: EntityID,
        displayName: String,
        kind: EntityKind,
        capabilities: Set<String>,
        metrics: [MetricSample]
    ) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.capabilities = capabilities
        self.metrics = metrics
    }
}

public struct ProviderSnapshot: Equatable, Sendable {
    public let schemaVersion: Int
    public let providerID: ProviderID
    public let capturedAt: Date
    public let availability: DataAvailability
    public let accountScope: AccountScope?
    public let plan: PlanDescriptor?
    public let rateWindows: [RateWindow]
    public let balances: [Balance]
    public let currentMetrics: [MetricSample]
    public let models: [UsageEntity]
    public let agents: [UsageEntity]
    public let serviceHealth: ServiceHealth

    public init(
        schemaVersion: Int,
        providerID: ProviderID,
        capturedAt: Date,
        availability: DataAvailability,
        accountScope: AccountScope?,
        plan: PlanDescriptor?,
        rateWindows: [RateWindow],
        balances: [Balance],
        currentMetrics: [MetricSample],
        models: [UsageEntity],
        agents: [UsageEntity],
        serviceHealth: ServiceHealth
    ) {
        self.schemaVersion = schemaVersion
        self.providerID = providerID
        self.capturedAt = capturedAt
        self.availability = availability
        self.accountScope = accountScope
        self.plan = plan
        self.rateWindows = rateWindows
        self.balances = balances
        self.currentMetrics = currentMetrics
        self.models = models
        self.agents = agents
        self.serviceHealth = serviceHealth
    }
}

public struct SanitizedErrorSummary: Equatable, Sendable {
    public let message: String

    public init(_ message: String) {
        let singleLine = message
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        self.message = String(singleLine.prefix(240))
    }
}

public struct SanitizedFetchDiagnostics: Equatable, Sendable {
    public let sourceLabel: String
    public let duration: TimeInterval
    public let optionalIssues: [SanitizedErrorSummary]

    public init(
        sourceLabel: String,
        duration: TimeInterval,
        optionalIssues: [SanitizedErrorSummary]
    ) {
        self.sourceLabel = sourceLabel
        self.duration = duration
        self.optionalIssues = optionalIssues
    }
}

public struct ProviderFetchResult: Equatable, Sendable {
    public let snapshot: ProviderSnapshot
    public let historicalObservations: [MetricObservation]
    public let diagnostics: SanitizedFetchDiagnostics

    public init(
        snapshot: ProviderSnapshot,
        historicalObservations: [MetricObservation],
        diagnostics: SanitizedFetchDiagnostics
    ) {
        self.snapshot = snapshot
        self.historicalObservations = historicalObservations
        self.diagnostics = diagnostics
    }
}

public enum ProviderStage: String, Codable, Sendable {
    case availability
    case launch
    case initialize
    case fetch
    case decode
    case stop
}

public enum ProviderError: Error, Equatable, Sendable {
    case unavailable
    case notConfigured
    case timedOut(stage: ProviderStage)
    case processExited(code: Int32?)
    case protocolViolation
    case unsupportedSchema
    case permissionDenied
    case cancelled
    case transient(SanitizedErrorSummary)
}

extension ProviderError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unavailable:
            "Codex 当前不可用。"
        case .notConfigured:
            "找不到 Codex。请安装 ChatGPT/Codex，或通过 CODEX_EXECUTABLE 指定路径。"
        case .timedOut:
            "读取 Codex 状态超时。"
        case .processExited(let code):
            if let code {
                "Codex App Server 已退出（\(code)）。"
            } else {
                "Codex App Server 已退出。"
            }
        case .protocolViolation:
            "Codex 返回了无法识别的数据。"
        case .unsupportedSchema:
            "当前 Codex 数据格式暂不受支持。"
        case .permissionDenied:
            "Codex 拒绝了当前只读请求。"
        case .cancelled:
            "Codex 状态读取已取消。"
        case .transient(let summary):
            summary.message
        }
    }
}

public enum ProviderLoadState: Equatable, Sendable {
    case idle(lastSnapshot: ProviderSnapshot?)
    case refreshing(previous: ProviderSnapshot?)
    case available(ProviderSnapshot)
    case unavailable(previous: ProviderSnapshot?, error: ProviderError)

    public var latestSnapshot: ProviderSnapshot? {
        switch self {
        case .idle(let snapshot):
            snapshot
        case .refreshing(let snapshot):
            snapshot
        case .available(let snapshot):
            snapshot
        case .unavailable(let snapshot, _):
            snapshot
        }
    }
}

public struct ApplicationDataState: Equatable, Sendable {
    public var providers: [ProviderID: ProviderLoadState]

    public init(providers: [ProviderID: ProviderLoadState] = [:]) {
        self.providers = providers
    }
}
