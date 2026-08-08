import Foundation

public struct CodexPluginUsageRateWindow:
    Codable,
    Equatable,
    Sendable
{
    public let usedPercent: Int
    public let windowDurationMins: Int?
    public let resetsAt: Int64?

    public init(
        usedPercent: Int,
        windowDurationMins: Int?,
        resetsAt: Int64?
    ) {
        self.usedPercent = usedPercent
        self.windowDurationMins = windowDurationMins
        self.resetsAt = resetsAt
    }
}

public struct CodexPluginUsageCredits:
    Codable,
    Equatable,
    Sendable
{
    public let hasCredits: Bool
    public let unlimited: Bool
    public let balance: String?

    public init(
        hasCredits: Bool,
        unlimited: Bool,
        balance: String?
    ) {
        self.hasCredits = hasCredits
        self.unlimited = unlimited
        self.balance = balance
    }
}

/// The presentation-oriented, credential-free snapshot written by the
/// QuotaView for Codex plugin. It deliberately excludes account identifiers,
/// email, OAuth tokens, reset-credit inventory, prompts, paths and raw Codex
/// RPC responses.
public struct CodexPluginUsageSnapshot:
    Codable,
    Equatable,
    Sendable
{
    public let bridgeProtocolVersion: Int
    public let installationIdentifier: String
    public let usageSchemaVersion: Int
    public let capturedAt: Date
    public let source: String
    public let planType: String?
    public let primary: CodexPluginUsageRateWindow
    public let credits: CodexPluginUsageCredits?
    public let limitReached: Bool
    public let lifetimeTokens: Int64?
    public let recentDailyTokens: Int64?
    public let recentDailyDate: String?

    public init(
        bridgeProtocolVersion: Int,
        installationIdentifier: String,
        usageSchemaVersion: Int,
        capturedAt: Date,
        source: String,
        planType: String?,
        primary: CodexPluginUsageRateWindow,
        credits: CodexPluginUsageCredits?,
        limitReached: Bool,
        lifetimeTokens: Int64?,
        recentDailyTokens: Int64?,
        recentDailyDate: String?
    ) {
        self.bridgeProtocolVersion = bridgeProtocolVersion
        self.installationIdentifier = installationIdentifier
        self.usageSchemaVersion = usageSchemaVersion
        self.capturedAt = capturedAt
        self.source = source
        self.planType = planType
        self.primary = primary
        self.credits = credits
        self.limitReached = limitReached
        self.lifetimeTokens = lifetimeTokens
        self.recentDailyTokens = recentDailyTokens
        self.recentDailyDate = recentDailyDate
    }
}

public enum CodexPluginUsageSnapshotDecoder {
    public static func snapshot(
        from data: Data,
        manifest: CodexPluginBridgeManifest,
        now: Date = Date()
    ) throws -> CodexPluginUsageSnapshot {
        guard data.count
            <= CodexPluginBridgeContract.maximumUsageSnapshotBytes
        else {
            throw CodexPluginBridgeValidationError.oversized
        }
        try validateFieldAllowlist(data)

        let snapshot: CodexPluginUsageSnapshot
        do {
            snapshot = try decoder.decode(
                CodexPluginUsageSnapshot.self,
                from: data
            )
        } catch {
            throw CodexPluginBridgeValidationError.malformed
        }

        guard manifest.capabilities.contains(
            CodexPluginBridgeContract.usageCapability
        ) else {
            throw CodexPluginBridgeValidationError.missingUsageCapability
        }
        guard snapshot.bridgeProtocolVersion
            == CodexPluginBridgeContract.protocolVersion
        else {
            throw CodexPluginBridgeValidationError.incompatibleProtocol
        }
        guard snapshot.usageSchemaVersion
            == CodexPluginBridgeContract.usageSchemaVersion
        else {
            throw CodexPluginBridgeValidationError.incompatibleUsageSchema
        }
        guard snapshot.installationIdentifier
            == manifest.installationIdentifier
        else {
            throw CodexPluginBridgeValidationError.installationMismatch
        }
        guard snapshot.source == "codex-app-server" else {
            throw CodexPluginBridgeValidationError.invalidUsageSnapshot
        }

        let age = now.timeIntervalSince(snapshot.capturedAt)
        guard age <= CodexPluginBridgeContract.maximumUsageSnapshotAge else {
            throw CodexPluginBridgeValidationError.usageSnapshotExpired
        }
        guard age >= -CodexPluginBridgeContract.maximumFutureSkew else {
            throw CodexPluginBridgeValidationError.eventFromFuture
        }
        guard (0...100).contains(snapshot.primary.usedPercent),
              snapshot.primary.windowDurationMins.map({
                  (1...525_600).contains($0)
              }) ?? true,
              snapshot.primary.resetsAt.map({ $0 > 0 }) ?? true,
              snapshot.lifetimeTokens.map({ $0 >= 0 }) ?? true,
              snapshot.recentDailyTokens.map({ $0 >= 0 }) ?? true
        else {
            throw CodexPluginBridgeValidationError.invalidUsageSnapshot
        }

        if let planType = snapshot.planType,
           !isSafeText(planType, maximumLength: 64)
        {
            throw CodexPluginBridgeValidationError.invalidUsageSnapshot
        }
        if let balance = snapshot.credits?.balance {
            guard balance.utf8.count <= 64,
                  Decimal(
                      string: balance,
                      locale: Locale(identifier: "en_US_POSIX")
                  ) != nil
            else {
                throw CodexPluginBridgeValidationError.invalidUsageSnapshot
            }
        }

        switch (
            snapshot.recentDailyTokens,
            snapshot.recentDailyDate
        ) {
        case (nil, nil):
            break
        case (.some, let date?):
            guard Self.dayFormatter.date(from: date) != nil,
                  date.utf8.count == 10
            else {
                throw CodexPluginBridgeValidationError
                    .invalidUsageSnapshot
            }
        default:
            throw CodexPluginBridgeValidationError.invalidUsageSnapshot
        }

        return snapshot
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static func validateFieldAllowlist(_ data: Data) throws {
        let value: Any
        do {
            value = try JSONSerialization.jsonObject(
                with: data,
                options: []
            )
        } catch {
            throw CodexPluginBridgeValidationError.malformed
        }
        guard let object = value as? [String: Any],
              Set(object.keys).isSubset(of: topLevelFields),
              let primary = object["primary"] as? [String: Any],
              Set(primary.keys).isSubset(of: primaryFields)
        else {
            throw CodexPluginBridgeValidationError.invalidUsageSnapshot
        }
        if let credits = object["credits"],
           !(credits is NSNull)
        {
            guard let creditObject = credits as? [String: Any],
                  Set(creditObject.keys).isSubset(of: creditFields)
            else {
                throw CodexPluginBridgeValidationError.invalidUsageSnapshot
            }
        }
    }

    private static let topLevelFields: Set<String> = [
        "bridgeProtocolVersion",
        "installationIdentifier",
        "usageSchemaVersion",
        "capturedAt",
        "source",
        "planType",
        "primary",
        "credits",
        "limitReached",
        "lifetimeTokens",
        "recentDailyTokens",
        "recentDailyDate"
    ]

    private static let primaryFields: Set<String> = [
        "usedPercent",
        "windowDurationMins",
        "resetsAt"
    ]

    private static let creditFields: Set<String> = [
        "hasCredits",
        "unlimited",
        "balance"
    ]

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }()

    private static func isSafeText(
        _ value: String,
        maximumLength: Int
    ) -> Bool {
        guard !value.isEmpty, value.count <= maximumLength else {
            return false
        }
        return value.unicodeScalars.allSatisfy { scalar in
            !CharacterSet.controlCharacters.contains(scalar)
                && !isBidirectionalControl(scalar)
        }
    }

    private static func isBidirectionalControl(
        _ scalar: Unicode.Scalar
    ) -> Bool {
        switch scalar.value {
        case 0x061C, 0x200E, 0x200F,
             0x202A...0x202E,
             0x2066...0x2069:
            true
        default:
            false
        }
    }
}
