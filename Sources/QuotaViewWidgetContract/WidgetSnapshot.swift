import Foundation

public enum QuotaViewWidgetConfiguration {
    public static let kind = "QuotaViewUsageWidget"
    public static let defaultAppGroupIdentifier =
        "BUUH229D5Q.com.quotaview.shared"
    public static let snapshotFileName = "QuotaViewWidgetSnapshot.json"
    public static let snapshotLifetime: TimeInterval = 15 * 60
    public static let minimumTimelineReloadInterval: TimeInterval = 5 * 60
}

public enum WidgetDataAvailability: String, Codable, Sendable {
    case available
    case unavailable
}

/// Converts Codex app-server plan identifiers into the current public names
/// used by OpenAI. Unknown values deliberately stay undisclosed instead of
/// being presented as an invented subscription name.
public enum OpenAIPlanDisplayName {
    public static func resolve(_ rawValue: String?) -> String? {
        guard let rawValue else {
            return nil
        }

        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        switch normalized {
        case "free":
            return "Free"
        case "go":
            return "Go"
        case "plus":
            return "Plus"
        case "prolite", "pro_lite", "pro_5x":
            return "Pro 5x"
        case "pro", "pro_20x":
            return "Pro 20x"
        case "team", "self_serve_business_usage_based", "business":
            return "Business"
        case "enterprise_cbp_usage_based", "enterprise":
            return "Enterprise"
        case "edu", "education":
            return "Edu"
        case "api", "api_key":
            return "API Key"
        default:
            return nil
        }
    }
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

public enum WidgetAuxiliaryMetricIdentifier {
    public static let creditsBalance = "credits-balance"
    public static let todayTokens = "today-tokens"
    public static let lifetimeTokens = "lifetime-tokens"
}

public struct ProviderWidgetPayload:
    Codable, Equatable, Sendable {
    public let providerID: String
    public let displayName: String
    public let plan: String?
    public let primaryWindow: WidgetQuotaWindow?
    public let auxiliaryMetrics: [WidgetAuxiliaryMetric]

    public init(
        providerID: String,
        displayName: String,
        plan: String?,
        primaryWindow: WidgetQuotaWindow?,
        auxiliaryMetrics: [WidgetAuxiliaryMetric]
    ) {
        self.providerID = providerID
        self.displayName = displayName
        self.plan = plan
        self.primaryWindow = primaryWindow
        self.auxiliaryMetrics = Array(auxiliaryMetrics.prefix(3))
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
              provider.auxiliaryMetrics.count <= 3,
              provider.auxiliaryMetrics.allSatisfy({
                  !$0.id.isEmpty
                      && $0.id.utf8.count <= 64
                      && !$0.label.isEmpty
                      && $0.label.utf8.count <= 64
                      && $0.formattedValue.utf8.count <= 64
              })
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

public struct WidgetSnapshotFileStore: Sendable {
    public let fileURL: URL
    public let codec: WidgetSnapshotCodec

    public init(
        containerURL: URL,
        codec: WidgetSnapshotCodec = WidgetSnapshotCodec()
    ) {
        self.fileURL = containerURL.appendingPathComponent(
            QuotaViewWidgetConfiguration.snapshotFileName,
            isDirectory: false
        )
        self.codec = codec
    }

    public func write(
        _ snapshot: QuotaViewWidgetSnapshot
    ) throws {
        let data = try codec.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }

    public func read(
        now: Date
    ) throws -> QuotaViewWidgetSnapshot {
        let data = try Data(contentsOf: fileURL)
        return try codec.decode(data, now: now)
    }
}
