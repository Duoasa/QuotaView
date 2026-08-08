import AppKit
import Combine
import Darwin
import Foundation
import QuotaViewCore

enum CodexPluginConnectionStatus: Equatable {
    case notConfigured
    case awaitingAuthorization
    case pairedWaitingForEvent
    case connected
    case stale
    case reauthorizationRequired
    case incompatible
    case malformedData
}

enum CodexPluginConnectionIssue: Equatable {
    case someMalformedEvents
    case folderAuthorizationFailed
    case bookmarkExpired
    case readFailed
    case validation(CodexPluginBridgeValidationError)
}

@MainActor
final class CodexActivityRuntime: ObservableObject {
    typealias BridgeReader = @Sendable (
        Data,
        CodexPluginBridgeCursor?
    ) throws -> BridgeReadResult

    @Published private(set) var connectionStatus:
        CodexPluginConnectionStatus = .notConfigured
    @Published private(set) var pluginVersion: String?
    @Published private(set) var distributionChannel: String?
    @Published private(set) var lastEventAt: Date?
    @Published private(set) var lastUsageAt: Date?
    @Published private(set) var connectionIssue:
        CodexPluginConnectionIssue?
    @Published private(set) var isAuthorizingDirectory = false

    let store: CodexActivityStore
    var onBridgeConfigurationChanged: (() -> Void)?
    var onUsageSnapshotChanged: (() -> Void)?

    private let preferences: AppPreferences
    private let defaults: UserDefaults
    private let bridgeReader: BridgeReader
    private var island: CodexActivityIslandPanelController?
    private var pollingTask: Task<Void, Never>?
    private var preferenceCancellable: AnyCancellable?
    private var islandPreferenceCancellable: AnyCancellable?
    private var accessibilityCancellable: AnyCancellable?
    private var bridgeRevision: UInt64 = 0
    private var activePollRevision: UInt64?

    enum DefaultsKey {
        static let bookmark = "codexPlugin.bridge.bookmark"
        static let cursorInstallation =
            "codexPlugin.bridge.cursor.installation"
        static let cursorSequence = "codexPlugin.bridge.cursor.sequence"
        static let lastEventAt = "codexPlugin.bridge.lastEventAt"
    }

    init(
        preferences: AppPreferences,
        defaults: UserDefaults = .standard,
        bridgeReader: @escaping BridgeReader = {
            try CodexActivityRuntime.readBridge(
                bookmark: $0,
                cursor: $1,
                consumesEvents: true
            )
        }
    ) {
        self.preferences = preferences
        self.defaults = defaults
        self.bridgeReader = bridgeReader
        self.store = CodexActivityStore()
        let persistedEventTime = defaults.double(
            forKey: DefaultsKey.lastEventAt
        )
        if persistedEventTime > 0 {
            lastEventAt = Date(timeIntervalSince1970: persistedEventTime)
        }

        store.stateDidChange = { [weak self] in
            self?.render()
        }
        preferenceCancellable = preferences.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in self?.render() }
            }
        islandPreferenceCancellable = preferences.$showCodexIsland
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] isEnabled in
                Task { @MainActor in
                    guard isEnabled else {
                        self?.island?.hide()
                        return
                    }
                    self?.render()
                }
            }
        accessibilityCancellable = NotificationCenter.default.publisher(
            for: NSWorkspace
                .accessibilityDisplayOptionsDidChangeNotification
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            Task { @MainActor in self?.render() }
        }
    }

    func start() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollOnce()
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    break
                }
            }
        }
    }

    func handlePairingURL(_ url: URL) {
        do {
            let request = try CodexPluginPairingRequest(url: url)
            connectionStatus = .awaitingAuthorization
            connectionIssue = nil
            choosePluginDataDirectory(pathHint: request.pathHint)
        } catch let error as CodexPluginBridgeValidationError {
            connectionStatus = .malformedData
            connectionIssue = .validation(error)
        } catch {
            connectionStatus = .malformedData
            connectionIssue = .readFailed
        }
    }

    func choosePluginDataDirectory(pathHint: String? = nil) {
        guard !isAuthorizingDirectory else { return }
        isAuthorizingDirectory = true
        connectionStatus = .awaitingAuthorization
        connectionIssue = nil

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = preferences.copy.text("授权读取", "Allow Read Access")
        panel.message = preferences.copy.text(
            "请选择 QuotaView for Codex 插件的 PLUGIN_DATA 目录。QuotaView 只会读取脱敏用量快照和活动事件。",
            "Choose the QuotaView for Codex PLUGIN_DATA folder. QuotaView reads sanitized usage snapshots and activity events only."
        )
        if let pathHint,
           pathHint.hasPrefix("/"),
           !pathHint.contains("\0"),
           pathHint.utf8.count <= 1_024
        {
            let hintedURL = URL(
                fileURLWithPath: pathHint,
                isDirectory: true
            )
            panel.directoryURL = hintedURL.deletingLastPathComponent()
        }

        panel.begin { [weak self] response in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isAuthorizingDirectory = false
                guard response == .OK, let url = panel.url else {
                    self.connectionStatus = self.defaults.data(
                        forKey: DefaultsKey.bookmark
                    ) == nil ? .notConfigured : .pairedWaitingForEvent
                    return
                }
                await self.authorizeDirectory(url)
            }
        }
    }

    func disconnectPluginData() {
        bridgeRevision &+= 1
        defaults.removeObject(forKey: DefaultsKey.bookmark)
        clearPersistedBridgeProgress()
        pluginVersion = nil
        distributionChannel = nil
        connectionIssue = nil
        connectionStatus = .notConfigured
        lastUsageAt = nil
        onBridgeConfigurationChanged?()
    }

    func refreshConnectionStatus() {
        Task { [weak self] in
            await self?.pollOnce()
        }
    }

    func openInstallationGuide() {
        let configuredURL = Bundle.main.object(
            forInfoDictionaryKey: "QuotaViewCodexPluginGuideURL"
        ) as? String
        guard let url = URL(
            string: configuredURL
                ?? "https://github.com/Duoasa/QuotaView-for-Codex"
        ), url.scheme == "https" else { return }
        NSWorkspace.shared.open(url)
    }

    func openOfficialCodex() {
        let applicationURL = URL(
            fileURLWithPath: "/Applications/ChatGPT.app",
            isDirectory: true
        )
        guard FileManager.default.fileExists(atPath: applicationURL.path)
        else { return }
        NSWorkspace.shared.openApplication(
            at: applicationURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    func stop() async {
        bridgeRevision &+= 1
        pollingTask?.cancel()
        pollingTask = nil
        await store.stop()
        island?.hide()
    }

    private func authorizeDirectory(_ url: URL) async {
        bridgeRevision &+= 1
        let revision = bridgeRevision
        do {
            let manifest = try await Task.detached {
                try Self.validateDirectoryAndReadManifest(
                    at: url,
                    now: Date()
                )
            }.value
            guard revision == bridgeRevision else { return }
            let bookmark = try url.bookmarkData(
                options: [
                    .withSecurityScope,
                    .securityScopeAllowOnlyReadAccess
                ],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            guard revision == bridgeRevision else { return }
            let oldInstallation = defaults.string(
                forKey: DefaultsKey.cursorInstallation
            )
            defaults.set(bookmark, forKey: DefaultsKey.bookmark)
            if oldInstallation != manifest.installationIdentifier {
                clearPersistedBridgeProgress()
            }
            pluginVersion = manifest.pluginVersion
            distributionChannel = manifest.distributionChannel
            connectionStatus = .pairedWaitingForEvent
            connectionIssue = nil
            onBridgeConfigurationChanged?()
            await pollOnce()
        } catch let error as CodexPluginBridgeValidationError {
            guard revision == bridgeRevision else { return }
            applyValidationError(error)
        } catch {
            guard revision == bridgeRevision else { return }
            connectionStatus = .malformedData
            connectionIssue = .folderAuthorizationFailed
        }
    }

    func pollOnce() async {
        let revision = bridgeRevision
        guard activePollRevision != revision else { return }
        activePollRevision = revision
        defer {
            if activePollRevision == revision {
                activePollRevision = nil
            }
        }
        guard let bookmark = defaults.data(
            forKey: DefaultsKey.bookmark
        ) else {
            connectionStatus = .notConfigured
            return
        }
        let cursor = currentCursor
        let bridgeReader = self.bridgeReader
        do {
            let result = try await Task.detached {
                try bridgeReader(bookmark, cursor)
            }.value
            guard revision == bridgeRevision else { return }
            let installationIdentifier =
                result.manifest.installationIdentifier
            if let cursor,
               cursor.installationIdentifier != installationIdentifier
            {
                clearPersistedBridgeProgress()
            }
            let previousUsageAt = lastUsageAt
            pluginVersion = result.manifest.pluginVersion
            distributionChannel = result.manifest.distributionChannel
            lastUsageAt = result.usageSnapshot?.capturedAt
            connectionIssue = result.skippedMalformedEvents > 0
                ? .someMalformedEvents
                : nil

            if let cursor = result.cursor,
               cursor.installationIdentifier == installationIdentifier
            {
                persist(cursor: cursor)
            }
            let now = Date()
            for envelope in result.envelopes
            where now.timeIntervalSince(envelope.activity.occurredAt) <= 120
            {
                store.receive(envelope.activity)
                lastEventAt = envelope.activity.occurredAt
                defaults.set(
                    envelope.activity.occurredAt.timeIntervalSince1970,
                    forKey: DefaultsKey.lastEventAt
                )
            }
            updateConnectedState(
                status: result.status
            )
            if let lastUsageAt, lastUsageAt != previousUsageAt {
                onUsageSnapshotChanged?()
            }
        } catch BridgeReadError.staleBookmark {
            guard revision == bridgeRevision else { return }
            connectionStatus = .reauthorizationRequired
            connectionIssue = .bookmarkExpired
            store.hide()
            lastUsageAt = nil
        } catch let error as CodexPluginBridgeValidationError {
            guard revision == bridgeRevision else { return }
            applyValidationError(error)
        } catch {
            guard revision == bridgeRevision else { return }
            connectionStatus = .malformedData
            connectionIssue = .readFailed
            store.hide()
        }
    }

    private var currentCursor: CodexPluginBridgeCursor? {
        guard let installationIdentifier = defaults.string(
            forKey: DefaultsKey.cursorInstallation
        ) else { return nil }
        let sequence = UInt64(
            max(defaults.integer(forKey: DefaultsKey.cursorSequence), 0)
        )
        return CodexPluginBridgeCursor(
            installationIdentifier: installationIdentifier,
            sequence: sequence
        )
    }

    private func persist(cursor: CodexPluginBridgeCursor) {
        defaults.set(
            cursor.installationIdentifier,
            forKey: DefaultsKey.cursorInstallation
        )
        defaults.set(
            Int64(clamping: cursor.sequence),
            forKey: DefaultsKey.cursorSequence
        )
    }

    private func clearPersistedBridgeProgress() {
        defaults.removeObject(forKey: DefaultsKey.cursorInstallation)
        defaults.removeObject(forKey: DefaultsKey.cursorSequence)
        defaults.removeObject(forKey: DefaultsKey.lastEventAt)
        lastEventAt = nil
        store.hide()
    }

    private func updateConnectedState(
        status: CodexPluginBridgeStatus?
    ) {
        let newestDate = [
            lastEventAt,
            lastUsageAt,
            status?.lastSuccessfulWriteAt
        ]
            .compactMap { $0 }
            .max()
        guard let newestDate else {
            connectionStatus = .pairedWaitingForEvent
            return
        }
        // A readable bridge and a valid usage snapshot remain connected while
        // Codex is idle. Hook events are only emitted when Codex does work,
        // so using a short activity interval here incorrectly reports an
        // expired connection after a quiet period. The bridge contract already
        // bounds both event and usage-snapshot freshness to 24 hours.
        connectionStatus = Date().timeIntervalSince(newestDate)
            <= CodexPluginBridgeContract.maximumUsageSnapshotAge
            ? .connected
            : .stale
    }

    private func applyValidationError(
        _ error: CodexPluginBridgeValidationError
    ) {
        switch error {
        case .incompatibleProtocol, .incompatibleEventSchema,
             .incompatibleUsageSchema:
            connectionStatus = .incompatible
        default:
            connectionStatus = .malformedData
        }
        connectionIssue = .validation(error)
        store.hide()
    }

    private func render() {
        guard preferences.showCodexIsland,
              let snapshot = store.snapshot,
              store.presentation != .hidden
        else {
            island?.hide()
            return
        }

        let title = snapshot.workspaceName.map { "Codex · \($0)" }
            ?? "Codex"
        let copy = CodexActivityCopy(
            language: preferences.resolvedLanguage
        )
        let renderState = CodexActivityRenderState(
            visualState: snapshot.state,
            windowTitle: title,
            statusTitle: copy.statusTitle(for: snapshot.state),
            operation: copy.operation(for: snapshot.operationKey),
            accessibilityLabel: copy.accessibilityLabel(
                windowTitle: title,
                statusTitle: copy.statusTitle(for: snapshot.state),
                operation: copy.operation(for: snapshot.operationKey)
            )
        )
        let presentation: CodexActivityIslandPresentation =
            store.presentation == .compact ? .compact : .expanded
        if island == nil {
            island = CodexActivityIslandPanelController(
                initialState: renderState
            )
        }
        island?.update(
            renderState: renderState,
            presentationMode: presentation,
            presentationAccessibilityValue:
                copy.presentationAccessibilityValue(presentation),
            reduceMotion:
                NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
    }

    nonisolated private static func validateDirectoryAndReadManifest(
        at url: URL,
        now: Date
    ) throws -> CodexPluginBridgeManifest {
        try validateDirectory(url)
        let bridgeURL = url.appendingPathComponent(
            "bridge.json",
            isDirectory: false
        )
        try validateRegularFile(
            bridgeURL,
            maximumBytes: CodexPluginBridgeContract.maximumManifestBytes
        )
        return try CodexPluginBridgeDecoder.manifest(
            from: Data(contentsOf: bridgeURL, options: .mappedIfSafe),
            now: now
        )
    }

    nonisolated static func readBridge(
        bookmark: Data,
        cursor: CodexPluginBridgeCursor?,
        consumesEvents: Bool
    ) throws -> BridgeReadResult {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        guard !isStale else { throw BridgeReadError.staleBookmark }
        guard url.startAccessingSecurityScopedResource() else {
            throw BridgeReadError.staleBookmark
        }
        defer { url.stopAccessingSecurityScopedResource() }

        return try readBridgeDirectory(
            at: url,
            cursor: cursor,
            consumesEvents: consumesEvents
        )
    }

    /// Reads an already-authorized bridge directory. Production callers reach
    /// this through a security-scoped bookmark; release validation can provide
    /// an explicit directory to exercise the exact same parser and filesystem
    /// checks against events emitted by a real Codex host.
    nonisolated static func readBridgeDirectory(
        at url: URL,
        cursor: CodexPluginBridgeCursor?,
        consumesEvents: Bool,
        now: Date = Date()
    ) throws -> BridgeReadResult {

        let manifest = try validateDirectoryAndReadManifest(
            at: url,
            now: now
        )
        var status: CodexPluginBridgeStatus?
        let statusURL = url.appendingPathComponent("status.json")
        if FileManager.default.fileExists(atPath: statusURL.path) {
            try validateRegularFile(
                statusURL,
                maximumBytes:
                    CodexPluginBridgeContract.maximumStatusBytes
            )
            status = try CodexPluginBridgeDecoder.status(
                from: Data(
                    contentsOf: statusURL,
                    options: .mappedIfSafe
                ),
                manifest: manifest,
                now: now
            )
        }

        var usageSnapshot: CodexPluginUsageSnapshot?
        if manifest.capabilities.contains(
            CodexPluginBridgeContract.usageCapability
        ) {
            let usageURL = url.appendingPathComponent("usage.json")
            if FileManager.default.fileExists(atPath: usageURL.path) {
                try validateRegularFile(
                    usageURL,
                    maximumBytes:
                        CodexPluginBridgeContract.maximumUsageSnapshotBytes
                )
                do {
                    usageSnapshot = try CodexPluginUsageSnapshotDecoder
                        .snapshot(
                            from: Data(
                                contentsOf: usageURL,
                                options: .mappedIfSafe
                            ),
                            manifest: manifest,
                            now: now
                        )
                } catch {
                    guard consumesEvents else { throw error }
                }
            }
        }

        guard consumesEvents else {
            return BridgeReadResult(
                manifest: manifest,
                status: status,
                usageSnapshot: usageSnapshot,
                envelopes: [],
                cursor: cursor,
                skippedMalformedEvents: 0
            )
        }

        let eventsURL = url.appendingPathComponent(
            "events",
            isDirectory: true
        )
        try validateDirectory(eventsURL)
        let fileURLs = try FileManager.default.contentsOfDirectory(
            at: eventsURL,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileSizeKey
            ],
            options: [.skipsHiddenFiles]
        )
        guard fileURLs.count
            <= CodexPluginBridgeContract.maximumEventFiles
        else {
            throw CodexPluginBridgeValidationError.oversized
        }
        let sequencedFiles = fileURLs.compactMap { fileURL ->
            (UInt64, URL)? in
            guard let sequence = CodexPluginBridgeDecoder.eventSequence(
                fromFileName: fileURL.lastPathComponent
            ) else { return nil }
            return (sequence, fileURL)
        }.sorted { $0.0 < $1.0 }

        var nextCursor = cursor
        var envelopes: [CodexPluginActivityEnvelope] = []
        var skippedMalformedEvents = 0
        for (sequence, fileURL) in sequencedFiles {
            if let nextCursor,
               nextCursor.installationIdentifier
                    == manifest.installationIdentifier,
               sequence <= nextCursor.sequence
            {
                continue
            }
            do {
                try validateRegularFile(
                    fileURL,
                    maximumBytes:
                        CodexPluginBridgeContract.maximumEventBytes
                )
                if let envelope = try CodexPluginBridgeDecoder
                    .activityEnvelope(
                        from: Data(
                            contentsOf: fileURL,
                            options: .mappedIfSafe
                        ),
                        fileSequence: sequence,
                        manifest: manifest,
                        cursor: nextCursor,
                        now: now
                    )
                {
                    envelopes.append(envelope)
                }
                nextCursor = CodexPluginBridgeCursor(
                    installationIdentifier:
                        manifest.installationIdentifier,
                    sequence: sequence
                )
            } catch let error as CodexPluginBridgeValidationError {
                switch error {
                case .incompatibleProtocol, .incompatibleEventSchema:
                    throw error
                case .eventExpired:
                    // Expiration is normal retention behavior, not malformed
                    // plugin data. Advance past the old event without showing
                    // a persistent connection warning after a fresh pairing.
                    nextCursor = CodexPluginBridgeCursor(
                        installationIdentifier:
                            manifest.installationIdentifier,
                        sequence: sequence
                    )
                default:
                    skippedMalformedEvents += 1
                    nextCursor = CodexPluginBridgeCursor(
                        installationIdentifier:
                            manifest.installationIdentifier,
                        sequence: sequence
                    )
                }
            }
        }
        return BridgeReadResult(
            manifest: manifest,
            status: status,
            usageSnapshot: usageSnapshot,
            envelopes: envelopes,
            cursor: nextCursor,
            skippedMalformedEvents: skippedMalformedEvents
        )
    }

    nonisolated private static func validateDirectory(
        _ url: URL
    ) throws {
        let values = try url.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey
        ])
        guard values.isDirectory == true,
              values.isSymbolicLink != true
        else {
            throw CodexPluginBridgeValidationError.malformed
        }
        let attributes = try FileManager.default.attributesOfItem(
            atPath: url.path
        )
        guard let owner = attributes[.ownerAccountID] as? NSNumber,
              owner.uint32Value == geteuid(),
              let permissions = attributes[.posixPermissions] as? NSNumber,
              permissions.intValue & 0o022 == 0
        else {
            throw CodexPluginBridgeValidationError.malformed
        }
    }

    nonisolated private static func validateRegularFile(
        _ url: URL,
        maximumBytes: Int
    ) throws {
        let values = try url.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey
        ])
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              let fileSize = values.fileSize,
              fileSize <= maximumBytes
        else {
            throw CodexPluginBridgeValidationError.malformed
        }
        let attributes = try FileManager.default.attributesOfItem(
            atPath: url.path
        )
        guard let owner = attributes[.ownerAccountID] as? NSNumber,
              owner.uint32Value == geteuid(),
              let permissions = attributes[.posixPermissions] as? NSNumber,
              permissions.intValue & 0o022 == 0
        else {
            throw CodexPluginBridgeValidationError.malformed
        }
    }
}

enum BridgeReadError: Error {
    case staleBookmark
}

struct BridgeReadResult: Sendable {
    let manifest: CodexPluginBridgeManifest
    let status: CodexPluginBridgeStatus?
    let usageSnapshot: CodexPluginUsageSnapshot?
    let envelopes: [CodexPluginActivityEnvelope]
    let cursor: CodexPluginBridgeCursor?
    let skippedMalformedEvents: Int
}

actor CodexPluginUsageSnapshotSource {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() throws -> CodexPluginUsageSnapshot {
        guard let bookmark = defaults.data(
            forKey: CodexActivityRuntime.DefaultsKey.bookmark
        ) else {
            throw ProviderError.notConfigured
        }

        do {
            let result = try CodexActivityRuntime.readBridge(
                bookmark: bookmark,
                cursor: nil,
                consumesEvents: false
            )
            guard result.manifest.capabilities.contains(
                CodexPluginBridgeContract.usageCapability
            ) else {
                throw CodexPluginBridgeValidationError
                    .missingUsageCapability
            }
            guard let usageSnapshot = result.usageSnapshot else {
                throw CodexPluginBridgeValidationError
                    .usageSnapshotMissing
            }
            return usageSnapshot
        } catch BridgeReadError.staleBookmark {
            throw ProviderError.notConfigured
        }
    }
}
