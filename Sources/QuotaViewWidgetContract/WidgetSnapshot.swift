import Foundation

public enum WidgetDataAvailability: String, Codable, Sendable {
    case available
    case unavailable
}

public struct WidgetQuotaWindow: Codable, Equatable, Sendable {
    public let usedFraction: Double?
    public let remainingFraction: Double?
    public let resetsAt: Date?

    public init(
        usedFraction: Double?,
        remainingFraction: Double?,
        resetsAt: Date?
    ) {
        self.usedFraction = usedFraction
        self.remainingFraction = remainingFraction
        self.resetsAt = resetsAt
    }
}

public struct WidgetAuxiliaryMetric:
    Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let formattedValue: String

    public init(
        id: String,
        label: String,
        formattedValue: String
    ) {
        self.id = id
        self.label = label
        self.formattedValue = formattedValue
    }
}

public struct ProviderWidgetPayload:
    Codable, Equatable, Sendable {
    public let providerID: String
    public let displayName: String
    public let plan: String?
    public let primaryWindow: WidgetQuotaWindow?
    public let auxiliaryMetrics: [WidgetAuxiliaryMetric]
    public let availableResetCredits: Int?

    public init(
        providerID: String,
        displayName: String,
        plan: String?,
        primaryWindow: WidgetQuotaWindow?,
        auxiliaryMetrics: [WidgetAuxiliaryMetric],
        availableResetCredits: Int?
    ) {
        self.providerID = providerID
        self.displayName = displayName
        self.plan = plan
        self.primaryWindow = primaryWindow
        self.auxiliaryMetrics = Array(auxiliaryMetrics.prefix(2))
        self.availableResetCredits = availableResetCredits
    }
}

public struct QuotaViewWidgetSnapshot:
    Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let generatedAt: Date
    public let expiresAt: Date
    public let updatedAt: Date?
    public let localeIdentifier: String
    public let availability: WidgetDataAvailability
    public let provider: ProviderWidgetPayload?

    public init(
        schemaVersion: Int = currentSchemaVersion,
        generatedAt: Date,
        expiresAt: Date,
        updatedAt: Date?,
        localeIdentifier: String,
        availability: WidgetDataAvailability,
        provider: ProviderWidgetPayload?
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.expiresAt = expiresAt
        self.updatedAt = updatedAt
        self.localeIdentifier = localeIdentifier
        self.availability = availability
        self.provider = provider
    }
}

public enum WidgetSnapshotCodecError:
    Error, Equatable, Sendable {
    case tooLarge
    case corrupt
    case unsupportedSchema(Int)
    case expired
    case invalidPayload
}

public struct WidgetSnapshotCodec: Sendable {
    public static let targetEncodedBytes = 16 * 1_024
    public static let hardMaximumEncodedBytes = 64 * 1_024

    public let maximumEncodedBytes: Int

    public init(
        maximumEncodedBytes: Int = hardMaximumEncodedBytes
    ) {
        self.maximumEncodedBytes = min(
            max(maximumEncodedBytes, 1),
            Self.hardMaximumEncodedBytes
        )
    }

    public func encode(
        _ snapshot: QuotaViewWidgetSnapshot
    ) throws -> Data {
        try validate(snapshot, now: nil)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)

        guard data.count <= maximumEncodedBytes else {
            throw WidgetSnapshotCodecError.tooLarge
        }
        return data
    }

    public func decode(
        _ data: Data,
        now: Date
    ) throws -> QuotaViewWidgetSnapshot {
        guard data.count <= maximumEncodedBytes else {
            throw WidgetSnapshotCodecError.tooLarge
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let snapshot: QuotaViewWidgetSnapshot
        do {
            snapshot = try decoder.decode(
                QuotaViewWidgetSnapshot.self,
                from: data
            )
        } catch {
            throw WidgetSnapshotCodecError.corrupt
        }

        try validate(snapshot, now: now)
        return snapshot
    }

    private func validate(
        _ snapshot: QuotaViewWidgetSnapshot,
        now: Date?
    ) throws {
        guard snapshot.schemaVersion
                == QuotaViewWidgetSnapshot.currentSchemaVersion
        else {
            throw WidgetSnapshotCodecError.unsupportedSchema(
                snapshot.schemaVersion
            )
        }
        guard snapshot.expiresAt > snapshot.generatedAt else {
            throw WidgetSnapshotCodecError.invalidPayload
        }
        if let now, snapshot.expiresAt <= now {
            throw WidgetSnapshotCodecError.expired
        }
        guard snapshot.localeIdentifier.utf8.count <= 64 else {
            throw WidgetSnapshotCodecError.invalidPayload
        }

        if snapshot.availability == .available,
           snapshot.provider == nil {
            throw WidgetSnapshotCodecError.invalidPayload
        }
        guard let provider = snapshot.provider else {
            return
        }
        guard !provider.providerID.isEmpty,
              provider.providerID.utf8.count <= 128,
              !provider.displayName.isEmpty,
              provider.displayName.utf8.count <= 128,
              provider.auxiliaryMetrics.count <= 2,
              provider.availableResetCredits.map({ $0 >= 0 }) ?? true
        else {
            throw WidgetSnapshotCodecError.invalidPayload
        }

        let fractions = [
            provider.primaryWindow?.usedFraction,
            provider.primaryWindow?.remainingFraction
        ].compactMap { $0 }
        guard fractions.allSatisfy({ (0...1).contains($0) }) else {
            throw WidgetSnapshotCodecError.invalidPayload
        }
    }
}
