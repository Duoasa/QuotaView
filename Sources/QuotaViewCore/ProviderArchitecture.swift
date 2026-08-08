import Foundation

public struct ProviderCapabilities: OptionSet, Hashable, Sendable {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    public static let currentUsage = Self(rawValue: 1 << 0)
    public static let rateWindows = Self(rawValue: 1 << 1)
    public static let balances = Self(rawValue: 1 << 2)
    public static let historicalUsage = Self(rawValue: 1 << 3)
    public static let modelBreakdown = Self(rawValue: 1 << 4)
    public static let agentBreakdown = Self(rawValue: 1 << 5)
    public static let serviceHealth = Self(rawValue: 1 << 6)
    public static let officialActions = Self(rawValue: 1 << 8)

    public static let currentQuotaViewFeatures: Self = [
        .currentUsage,
        .rateWindows,
        .balances,
        .historicalUsage
    ]
}

public enum OfficialSourceKind: String, Codable, Sendable {
    case localCLI
    case localAppServer
    case pluginSanitizedSnapshot
    case officialStatusAPI
}

public struct ProviderResourceProfile: Equatable, Sendable {
    public let minimumRefreshInterval: TimeInterval
    public let startsSubprocess: Bool
    public let typicalTimeout: TimeInterval
    public let permitsParallelEnrichment: Bool
    public let lowPowerMinimumInterval: TimeInterval

    public init(
        minimumRefreshInterval: TimeInterval,
        startsSubprocess: Bool,
        typicalTimeout: TimeInterval,
        permitsParallelEnrichment: Bool,
        lowPowerMinimumInterval: TimeInterval
    ) {
        self.minimumRefreshInterval = minimumRefreshInterval
        self.startsSubprocess = startsSubprocess
        self.typicalTimeout = typicalTimeout
        self.permitsParallelEnrichment = permitsParallelEnrichment
        self.lowPowerMinimumInterval = lowPowerMinimumInterval
    }
}

public struct ProviderDescriptor: Equatable, Sendable {
    public let id: ProviderID
    public let displayName: String
    public let capabilities: ProviderCapabilities
    public let sourceKinds: Set<OfficialSourceKind>
    public let resourceProfile: ProviderResourceProfile
    public let supportsStableAccountScope: Bool

    public init(
        id: ProviderID,
        displayName: String,
        capabilities: ProviderCapabilities,
        sourceKinds: Set<OfficialSourceKind>,
        resourceProfile: ProviderResourceProfile,
        supportsStableAccountScope: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.capabilities = capabilities
        self.sourceKinds = sourceKinds
        self.resourceProfile = resourceProfile
        self.supportsStableAccountScope = supportsStableAccountScope
    }
}

public enum ProviderAvailability: Equatable, Sendable {
    case available
    case unavailable(ProviderError)
}

public enum RefreshReason: String, Codable, Sendable {
    case startup
    case panelOpened
    case manual
    case background
    case configurationChanged
    case providerChanged
    case systemWake
    case resetBoundary
}

public struct ProviderFetchRequest: Sendable {
    public let generation: UInt64
    public let enablementRevision: UInt64
    public let configurationRevision: UInt64
    public let reason: RefreshReason
    public let deadline: Date
    public let capabilities: ProviderCapabilities
    public let expectedAccountScope: String?
    public let correlationID: String

    public init(
        generation: UInt64,
        enablementRevision: UInt64,
        configurationRevision: UInt64,
        reason: RefreshReason,
        deadline: Date,
        capabilities: ProviderCapabilities,
        expectedAccountScope: String?,
        correlationID: String
    ) {
        self.generation = generation
        self.enablementRevision = enablementRevision
        self.configurationRevision = configurationRevision
        self.reason = reason
        self.deadline = deadline
        self.capabilities = capabilities
        self.expectedAccountScope = expectedAccountScope
        self.correlationID = correlationID
    }
}

public protocol UsageProviderAdapter: Sendable {
    var descriptor: ProviderDescriptor { get }

    func availability() async -> ProviderAvailability
    func fetch(_ request: ProviderFetchRequest) async throws
        -> ProviderFetchResult
    func stop() async
}

public enum ProviderRegistryError: Error, Equatable, Sendable {
    case duplicateProviderID(ProviderID)
}

/// A deliberately static registry keeps provider discovery auditable and
/// avoids loading plug-ins or executable code at runtime.
public struct StaticProviderRegistry: Sendable {
    public let descriptors: [ProviderDescriptor]

    private let adapters: [ProviderID: any UsageProviderAdapter]

    public init(
        adapters: [any UsageProviderAdapter]
    ) throws {
        var indexed: [ProviderID: any UsageProviderAdapter] = [:]

        for adapter in adapters {
            let id = adapter.descriptor.id
            guard indexed[id] == nil else {
                throw ProviderRegistryError.duplicateProviderID(id)
            }
            indexed[id] = adapter
        }

        self.adapters = indexed
        self.descriptors = indexed.values
            .map(\.descriptor)
            .sorted { $0.id.rawValue < $1.id.rawValue }
    }

    public func adapter(
        for providerID: ProviderID
    ) -> (any UsageProviderAdapter)? {
        adapters[providerID]
    }
}

public enum DataConsumer: String, Codable, Hashable, Sendable {
    case menuBar
    case panel
    case dataDetail
    case history
    case widget
    case notifications
}

public enum FreshnessRequirement: Equatable, Sendable {
    case interactive
    case background
    case lowPriority
}

public struct ConsumerDemand: Equatable, Sendable {
    public let consumer: DataConsumer
    public let providerID: ProviderID
    public let capabilities: ProviderCapabilities
    public let freshness: FreshnessRequirement

    public init(
        consumer: DataConsumer,
        providerID: ProviderID,
        capabilities: ProviderCapabilities,
        freshness: FreshnessRequirement
    ) {
        self.consumer = consumer
        self.providerID = providerID
        self.capabilities = capabilities
        self.freshness = freshness
    }
}

public struct ProviderDemandPlan: Equatable, Sendable {
    public let providerID: ProviderID
    public let capabilities: ProviderCapabilities
    public let freshness: FreshnessRequirement?
    public let consumers: Set<DataConsumer>

    public init(
        providerID: ProviderID,
        capabilities: ProviderCapabilities,
        freshness: FreshnessRequirement?,
        consumers: Set<DataConsumer>
    ) {
        self.providerID = providerID
        self.capabilities = capabilities
        self.freshness = freshness
        self.consumers = consumers
    }
}

public struct DataDemandPlanner: Sendable {
    public init() {}

    public func plans(
        for demands: [ConsumerDemand],
        enabledProviders: Set<ProviderID>
    ) -> [ProviderID: ProviderDemandPlan] {
        var grouped: [ProviderID: [ConsumerDemand]] = [:]

        for demand in demands
        where enabledProviders.contains(demand.providerID) {
            grouped[demand.providerID, default: []].append(demand)
        }

        return grouped.mapValues { providerDemands in
            let providerID = providerDemands[0].providerID
            let capabilities = providerDemands.reduce(
                into: ProviderCapabilities()
            ) { result, demand in
                result.formUnion(demand.capabilities)
            }
            let freshness = providerDemands
                .map(\.freshness)
                .min(by: Self.isMoreUrgent)

            return ProviderDemandPlan(
                providerID: providerID,
                capabilities: capabilities,
                freshness: freshness,
                consumers: Set(providerDemands.map(\.consumer))
            )
        }
    }

    private static func isMoreUrgent(
        _ lhs: FreshnessRequirement,
        _ rhs: FreshnessRequirement
    ) -> Bool {
        priority(lhs) < priority(rhs)
    }

    private static func priority(
        _ requirement: FreshnessRequirement
    ) -> Int {
        switch requirement {
        case .interactive: 0
        case .background: 1
        case .lowPriority: 2
        }
    }
}

public struct PublicationContext: Equatable, Sendable {
    public let providerID: ProviderID
    public let generation: UInt64
    public let enablementRevision: UInt64
    public let configurationRevision: UInt64
    public let requestedCapabilities: ProviderCapabilities
    public let expectedAccountScope: String?

    public init(
        providerID: ProviderID,
        generation: UInt64,
        enablementRevision: UInt64,
        configurationRevision: UInt64,
        requestedCapabilities: ProviderCapabilities,
        expectedAccountScope: String?
    ) {
        self.providerID = providerID
        self.generation = generation
        self.enablementRevision = enablementRevision
        self.configurationRevision = configurationRevision
        self.requestedCapabilities = requestedCapabilities
        self.expectedAccountScope = expectedAccountScope
    }
}
