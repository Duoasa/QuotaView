import Foundation

public enum OperationUnavailableReason: String, Codable, Sendable {
    case notImplemented
    case providerUnsupported
    case userDisabled
    case missingStableAccountScope
    case unsafeToExecute
}

public struct OfficialOperationDescriptor: Equatable, Sendable {
    public let providerID: ProviderID
    public let operationID: String
    public let supportsIdempotency: Bool
    public let supportsResultReconciliation: Bool

    public init(
        providerID: ProviderID,
        operationID: String,
        supportsIdempotency: Bool,
        supportsResultReconciliation: Bool
    ) {
        self.providerID = providerID
        self.operationID = operationID
        self.supportsIdempotency = supportsIdempotency
        self.supportsResultReconciliation =
            supportsResultReconciliation
    }
}

public enum AccountOperationAvailability: Equatable, Sendable {
    case unavailable(reason: OperationUnavailableReason)
    case demoOnly
    case officialManual(descriptor: OfficialOperationDescriptor)
    case officialAutomatic(descriptor: OfficialOperationDescriptor)
}

public struct QuotaActionRequest: Equatable, Sendable {
    public let providerID: ProviderID
    public let windowID: EntityID?
    public let requestedAt: Date

    public init(
        providerID: ProviderID,
        windowID: EntityID?,
        requestedAt: Date = Date()
    ) {
        self.providerID = providerID
        self.windowID = windowID
        self.requestedAt = requestedAt
    }
}

public enum ActionRejection: String, Codable, Sendable {
    case unsupportedAuthorization
    case unavailable
    case staleState
    case accountChanged
    case windowChanged
    case noCredits
    case killSwitchEnabled
    case outcomeUnknown
}

public enum ActionPreflight: Equatable, Sendable {
    case allowed
    case rejected(ActionRejection)
}

public struct OneShotAuthorization: Equatable, Sendable {
    public let authorizationID: UUID
    public let providerID: ProviderID
    public let accountScopeID: String
    public let expiresAt: Date

    public init(
        authorizationID: UUID,
        providerID: ProviderID,
        accountScopeID: String,
        expiresAt: Date
    ) {
        self.authorizationID = authorizationID
        self.providerID = providerID
        self.accountScopeID = accountScopeID
        self.expiresAt = expiresAt
    }
}

public struct AutomaticRuleGrant: Equatable, Sendable {
    public let grantID: UUID
    public let providerID: ProviderID
    public let accountScopeID: String
    public let maximumExecutionsPerCycle: Int
    public let expiresAt: Date

    public init(
        grantID: UUID,
        providerID: ProviderID,
        accountScopeID: String,
        maximumExecutionsPerCycle: Int,
        expiresAt: Date
    ) {
        self.grantID = grantID
        self.providerID = providerID
        self.accountScopeID = accountScopeID
        self.maximumExecutionsPerCycle =
            maximumExecutionsPerCycle
        self.expiresAt = expiresAt
    }
}

public enum ActionAuthorization: Equatable, Sendable {
    case demo
    case manual(OneShotAuthorization)
    case automatic(AutomaticRuleGrant)
}

public struct SanitizedActionReceipt: Equatable, Sendable {
    public let correlationID: UUID
    public let providerID: ProviderID
    public let completedAt: Date
    public let isSimulation: Bool

    public init(
        correlationID: UUID,
        providerID: ProviderID,
        completedAt: Date,
        isSimulation: Bool
    ) {
        self.correlationID = correlationID
        self.providerID = providerID
        self.completedAt = completedAt
        self.isSimulation = isSimulation
    }
}

public enum QuotaActionResult: Equatable, Sendable {
    case simulated(receipt: SanitizedActionReceipt)
    case succeeded(receipt: SanitizedActionReceipt)
    case rejected(ActionRejection)
    case failed(SanitizedErrorSummary)
    case outcomeUnknown(correlationID: UUID)
}

public protocol QuotaActionPreflighting: Sendable {
    func preflight(_ request: QuotaActionRequest) async
        -> ActionPreflight
}

public protocol QuotaActionExecutor: Sendable {
    func execute(
        _ request: QuotaActionRequest,
        authorization: ActionAuthorization
    ) async -> QuotaActionResult
}

public struct DemoQuotaActionExecutor: QuotaActionPreflighting,
    QuotaActionExecutor, Sendable {
    public init() {}

    public func preflight(
        _ request: QuotaActionRequest
    ) async -> ActionPreflight {
        .allowed
    }

    public func execute(
        _ request: QuotaActionRequest,
        authorization: ActionAuthorization
    ) async -> QuotaActionResult {
        guard authorization == .demo else {
            return .rejected(.unsupportedAuthorization)
        }

        return .simulated(
            receipt: SanitizedActionReceipt(
                correlationID: UUID(),
                providerID: request.providerID,
                completedAt: Date(),
                isSimulation: true
            )
        )
    }
}

public struct UnavailableQuotaActionExecutor:
    QuotaActionPreflighting, QuotaActionExecutor, Sendable {
    public init() {}

    public func preflight(
        _ request: QuotaActionRequest
    ) async -> ActionPreflight {
        .rejected(.unavailable)
    }

    public func execute(
        _ request: QuotaActionRequest,
        authorization: ActionAuthorization
    ) async -> QuotaActionResult {
        .rejected(.unavailable)
    }
}
