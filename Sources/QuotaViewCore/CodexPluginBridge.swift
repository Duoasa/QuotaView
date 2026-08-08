import Foundation

public enum CodexPluginBridgeContract {
    public static let pluginID = "quotaview"
    public static let protocolVersion = 1
    public static let eventSchemaVersion =
        CodexActivityEvent.currentSchemaVersion
    public static let usageSchemaVersion = 1
    public static let activityCapability = "codex-activity-events"
    public static let usageCapability = "codex-usage-snapshot"
    public static let capability = activityCapability
    public static let maximumManifestBytes = 64 * 1_024
    public static let maximumStatusBytes = 64 * 1_024
    public static let maximumEventBytes = 64 * 1_024
    public static let maximumUsageSnapshotBytes = 128 * 1_024
    public static let maximumEventFiles = 1_024
    public static let maximumEventAge: TimeInterval = 24 * 60 * 60
    public static let maximumUsageSnapshotAge: TimeInterval = 24 * 60 * 60
    public static let maximumFutureSkew: TimeInterval = 5 * 60
}

public struct CodexPluginBridgeManifest: Codable, Equatable, Sendable {
    public let pluginID: String
    public let pluginVersion: String
    public let distributionChannel: String
    public let bridgeProtocolVersion: Int
    public let eventSchemaVersion: Int
    public let installationIdentifier: String
    public let createdAt: Date
    public let capabilities: [String]

    enum CodingKeys: String, CodingKey {
        case pluginID = "pluginId"
        case pluginVersion
        case distributionChannel
        case bridgeProtocolVersion
        case eventSchemaVersion
        case installationIdentifier
        case createdAt
        case capabilities
    }

    public init(
        pluginID: String,
        pluginVersion: String,
        distributionChannel: String,
        bridgeProtocolVersion: Int,
        eventSchemaVersion: Int,
        installationIdentifier: String,
        createdAt: Date,
        capabilities: [String]
    ) {
        self.pluginID = pluginID
        self.pluginVersion = pluginVersion
        self.distributionChannel = distributionChannel
        self.bridgeProtocolVersion = bridgeProtocolVersion
        self.eventSchemaVersion = eventSchemaVersion
        self.installationIdentifier = installationIdentifier
        self.createdAt = createdAt
        self.capabilities = capabilities
    }
}

public struct CodexPluginBridgeStatus: Codable, Equatable, Sendable {
    public let bridgeProtocolVersion: Int
    public let installationIdentifier: String
    public let latestSequence: UInt64
    public let lastSuccessfulWriteAt: Date?
    public let diagnosticStatus: String?

    public init(
        bridgeProtocolVersion: Int,
        installationIdentifier: String,
        latestSequence: UInt64,
        lastSuccessfulWriteAt: Date?,
        diagnosticStatus: String?
    ) {
        self.bridgeProtocolVersion = bridgeProtocolVersion
        self.installationIdentifier = installationIdentifier
        self.latestSequence = latestSequence
        self.lastSuccessfulWriteAt = lastSuccessfulWriteAt
        self.diagnosticStatus = diagnosticStatus
    }
}

public struct CodexPluginActivityEnvelope: Codable, Equatable, Sendable {
    public let bridgeProtocolVersion: Int
    public let installationIdentifier: String
    public let sequence: UInt64
    public let activity: CodexActivityEvent

    public init(
        bridgeProtocolVersion: Int,
        installationIdentifier: String,
        sequence: UInt64,
        activity: CodexActivityEvent
    ) {
        self.bridgeProtocolVersion = bridgeProtocolVersion
        self.installationIdentifier = installationIdentifier
        self.sequence = sequence
        self.activity = activity
    }
}

public struct CodexPluginBridgeCursor: Codable, Equatable, Sendable {
    public let installationIdentifier: String
    public let sequence: UInt64

    public init(
        installationIdentifier: String,
        sequence: UInt64
    ) {
        self.installationIdentifier = installationIdentifier
        self.sequence = sequence
    }
}

public enum CodexPluginBridgeValidationError:
    Error,
    Equatable,
    Sendable
{
    case oversized
    case malformed
    case wrongPlugin
    case incompatibleProtocol
    case incompatibleEventSchema
    case incompatibleUsageSchema
    case invalidInstallationIdentifier
    case missingCapability
    case missingUsageCapability
    case invalidMetadata
    case installationMismatch
    case sequenceMismatch
    case invalidActivityIdentifier
    case invalidWorkspaceName
    case eventExpired
    case eventFromFuture
    case usageSnapshotMissing
    case usageSnapshotExpired
    case invalidUsageSnapshot
}

extension CodexPluginBridgeValidationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .oversized:
            "The Codex plugin data file is too large."
        case .malformed:
            "The Codex plugin data is malformed."
        case .wrongPlugin:
            "The selected folder does not belong to QuotaView for Codex."
        case .incompatibleProtocol, .incompatibleEventSchema,
             .incompatibleUsageSchema:
            "The Codex plugin data format is incompatible with this version of QuotaView."
        case .invalidInstallationIdentifier, .invalidMetadata:
            "The Codex plugin handshake is invalid."
        case .missingCapability:
            "The Codex plugin does not provide activity events."
        case .missingUsageCapability:
            "The Codex plugin does not provide a sanitized usage snapshot."
        case .installationMismatch, .sequenceMismatch:
            "The Codex plugin event does not match the selected installation."
        case .invalidActivityIdentifier, .invalidWorkspaceName:
            "The Codex plugin event contains invalid metadata."
        case .eventExpired:
            "The Codex plugin event is too old to replay."
        case .eventFromFuture:
            "The Codex plugin event timestamp is invalid."
        case .usageSnapshotMissing:
            "The Codex plugin has not written a usage snapshot yet."
        case .usageSnapshotExpired:
            "The Codex plugin usage snapshot is out of date."
        case .invalidUsageSnapshot:
            "The Codex plugin usage snapshot contains invalid data."
        }
    }
}

public enum CodexPluginBridgeDecoder {
    public static func manifest(
        from data: Data,
        now: Date = Date()
    ) throws -> CodexPluginBridgeManifest {
        guard data.count <= CodexPluginBridgeContract.maximumManifestBytes
        else {
            throw CodexPluginBridgeValidationError.oversized
        }
        let manifest: CodexPluginBridgeManifest
        do {
            manifest = try decoder.decode(
                CodexPluginBridgeManifest.self,
                from: data
            )
        } catch {
            throw CodexPluginBridgeValidationError.malformed
        }
        guard manifest.pluginID == CodexPluginBridgeContract.pluginID else {
            throw CodexPluginBridgeValidationError.wrongPlugin
        }
        guard manifest.bridgeProtocolVersion
            == CodexPluginBridgeContract.protocolVersion
        else {
            throw CodexPluginBridgeValidationError.incompatibleProtocol
        }
        guard manifest.eventSchemaVersion
            == CodexPluginBridgeContract.eventSchemaVersion
        else {
            throw CodexPluginBridgeValidationError.incompatibleEventSchema
        }
        guard isSafeInstallationIdentifier(
            manifest.installationIdentifier
        ) else {
            throw CodexPluginBridgeValidationError
                .invalidInstallationIdentifier
        }
        guard manifest.capabilities.contains(
            CodexPluginBridgeContract.activityCapability
        ) else {
            throw CodexPluginBridgeValidationError.missingCapability
        }
        guard isSafeMetadata(manifest.pluginVersion, maximumLength: 64),
              isSafeMetadata(
                  manifest.distributionChannel,
                  maximumLength: 64
              ),
              manifest.createdAt.timeIntervalSince(now)
                <= CodexPluginBridgeContract.maximumFutureSkew
        else {
            throw CodexPluginBridgeValidationError.invalidMetadata
        }
        return manifest
    }

    public static func status(
        from data: Data,
        manifest: CodexPluginBridgeManifest,
        now: Date = Date()
    ) throws -> CodexPluginBridgeStatus {
        guard data.count <= CodexPluginBridgeContract.maximumStatusBytes else {
            throw CodexPluginBridgeValidationError.oversized
        }
        let status: CodexPluginBridgeStatus
        do {
            status = try decoder.decode(
                CodexPluginBridgeStatus.self,
                from: data
            )
        } catch {
            throw CodexPluginBridgeValidationError.malformed
        }
        guard status.bridgeProtocolVersion
            == CodexPluginBridgeContract.protocolVersion
        else {
            throw CodexPluginBridgeValidationError.incompatibleProtocol
        }
        guard status.installationIdentifier
            == manifest.installationIdentifier
        else {
            throw CodexPluginBridgeValidationError.installationMismatch
        }
        if let diagnosticStatus = status.diagnosticStatus,
           !isSafeMetadata(diagnosticStatus, maximumLength: 160)
        {
            throw CodexPluginBridgeValidationError.invalidMetadata
        }
        let hasValidWriteDate = status.lastSuccessfulWriteAt.map {
            $0.timeIntervalSince(now)
                <= CodexPluginBridgeContract.maximumFutureSkew
        } ?? true
        guard status.latestSequence <= 999_999_999_999,
              hasValidWriteDate
        else {
            throw CodexPluginBridgeValidationError.invalidMetadata
        }
        return status
    }

    public static func activityEnvelope(
        from data: Data,
        fileSequence: UInt64,
        manifest: CodexPluginBridgeManifest,
        cursor: CodexPluginBridgeCursor?,
        now: Date = Date()
    ) throws -> CodexPluginActivityEnvelope? {
        guard data.count <= CodexPluginBridgeContract.maximumEventBytes else {
            throw CodexPluginBridgeValidationError.oversized
        }
        let envelope: CodexPluginActivityEnvelope
        do {
            envelope = try decoder.decode(
                CodexPluginActivityEnvelope.self,
                from: data
            )
        } catch {
            throw CodexPluginBridgeValidationError.malformed
        }
        guard envelope.bridgeProtocolVersion
            == CodexPluginBridgeContract.protocolVersion
        else {
            throw CodexPluginBridgeValidationError.incompatibleProtocol
        }
        guard envelope.installationIdentifier
            == manifest.installationIdentifier
        else {
            throw CodexPluginBridgeValidationError.installationMismatch
        }
        guard envelope.sequence == fileSequence else {
            throw CodexPluginBridgeValidationError.sequenceMismatch
        }
        if let cursor,
           cursor.installationIdentifier == envelope.installationIdentifier,
           envelope.sequence <= cursor.sequence
        {
            return nil
        }
        guard envelope.activity.schemaVersion
            == CodexPluginBridgeContract.eventSchemaVersion
        else {
            throw CodexPluginBridgeValidationError.incompatibleEventSchema
        }
        guard isSHA256(envelope.activity.sessionHash),
              envelope.activity.turnHash.map(isSHA256) ?? true
        else {
            throw CodexPluginBridgeValidationError.invalidActivityIdentifier
        }
        if let workspaceName = envelope.activity.workspaceName {
            guard isSafeWorkspaceName(workspaceName) else {
                throw CodexPluginBridgeValidationError.invalidWorkspaceName
            }
        }
        let age = now.timeIntervalSince(envelope.activity.occurredAt)
        guard age <= CodexPluginBridgeContract.maximumEventAge else {
            throw CodexPluginBridgeValidationError.eventExpired
        }
        guard age >= -CodexPluginBridgeContract.maximumFutureSkew else {
            throw CodexPluginBridgeValidationError.eventFromFuture
        }
        return envelope
    }

    public static func eventSequence(
        fromFileName fileName: String
    ) -> UInt64? {
        guard fileName.hasSuffix(".json") else { return nil }
        let stem = String(fileName.dropLast(5))
        guard stem.count == 12,
              stem.allSatisfy(\.isNumber),
              let sequence = UInt64(stem),
              sequence > 0
        else {
            return nil
        }
        return sequence
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static func isSafeInstallationIdentifier(
        _ value: String
    ) -> Bool {
        guard (8...128).contains(value.count) else { return false }
        return value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0)
                || $0 == "-"
                || $0 == "_"
                || $0 == "."
        }
    }

    private static func isSafeMetadata(
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

    private static func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.unicodeScalars.allSatisfy {
            ("0"..."9").contains(Character($0))
                || ("a"..."f").contains(Character($0))
        }
    }

    private static func isSafeWorkspaceName(_ value: String) -> Bool {
        guard isSafeMetadata(value, maximumLength: 80) else {
            return false
        }
        return !value.contains("/")
            && !value.contains("\\")
            && value != "."
            && value != ".."
    }
}

public struct CodexPluginPairingRequest: Equatable, Sendable {
    public let pathHint: String?

    public init(url: URL) throws {
        guard url.scheme?.lowercased() == "quotaview",
              url.host?.lowercased() == "pair",
              url.path.isEmpty || url.path == "/",
              url.user == nil,
              url.password == nil,
              url.port == nil,
              url.fragment == nil
        else {
            throw CodexPluginBridgeValidationError.malformed
        }
        guard let components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            throw CodexPluginBridgeValidationError.malformed
        }
        let allowedNames = Set(["protocol", "plugin", "pathHint"])
        let items = components.queryItems ?? []
        guard Set(items.map(\.name)).isSubset(of: allowedNames),
              items.filter({ $0.name == "protocol" }).count == 1,
              items.filter({ $0.name == "plugin" }).count == 1,
              items.filter({ $0.name == "pathHint" }).count <= 1,
              items.first(where: { $0.name == "protocol" })?.value
                == String(CodexPluginBridgeContract.protocolVersion),
              items.first(where: { $0.name == "plugin" })?.value
                == CodexPluginBridgeContract.pluginID
        else {
            throw CodexPluginBridgeValidationError.malformed
        }
        let pathHint = items.first(where: { $0.name == "pathHint" })?.value
        guard pathHint.map({
            $0.utf8.count <= 1_024
                && !$0.contains("\0")
                && ($0.isEmpty || $0.hasPrefix("/"))
        }) ?? true else {
            throw CodexPluginBridgeValidationError.oversized
        }
        self.pathHint = pathHint?.isEmpty == true ? nil : pathHint
    }
}
