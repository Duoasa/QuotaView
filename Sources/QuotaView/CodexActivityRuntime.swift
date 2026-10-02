import AppKit
import Combine
import Darwin
import Foundation
import QuotaViewCore

@MainActor
final class CodexActivityRuntime: ObservableObject {
    @Published private(set) var hookConnectionStatus:
        CodexActivityConnectionStatus = .notInstalled
    @Published private(set) var bridgeStatus:
        CodexActivityBridgeStatus = .stopped
    @Published private(set) var hooksFeatureStatus:
        CodexHooksFeatureStatus = .checking
    @Published private(set) var automaticConnection = CodexAutomaticActivityConnection(localHealth: .checking)
    var nativeConnectionState: CodexSharedAppServerConnectionState { automaticConnection.nativeState }
    var localHealth: CodexLocalActivityHealth { automaticConnection.localHealth }
    @Published private(set) var dataDirectoryURL: URL
    @Published private(set) var isChangingDataDirectory = false
    @Published private(set) var directorySelectionFailed = false
    @Published private(set) var hasCompatibilityHook = false
    @Published private(set) var compatibilityHookScope: CodexActivityHookInstaller.Scope?
    private var directoryTask: Task<Void, Never>?
    private static let dataDirectoryKey = "codexActivity.localDataDirectory"
    private let defaultDataDirectory: URL
    @Published private(set) var codexVersion: String?
    @Published private(set) var hookOperation: CodexHookOperation = .idle
    var isConfiguring: Bool { hookOperation.isConfiguring }
    var isOpeningSecurityReview: Bool { hookOperation == .reviewing }
    private var hookOperationRevision: UInt64 = 0
    private var hookEventGeneration: UInt64 = 0
    private var bridgeRunGeneration: UInt64 = 0

    let store: CodexActivityStore

    private let preferences: AppPreferences
    private let defaults: UserDefaults
    private var bridge: CodexActivityUnixBridge
    private var fileBridge: CodexActivityFileBridge
    private var installer: CodexActivityHookInstaller
    private var environmentInspector: CodexActivityEnvironmentInspector
    private let authenticationToken: String
    private let automaticHookSetupEnabled: Bool
    private let usesInjectedEnvironmentInspector: Bool
    // Configuration trust is established only by Codex native metadata. A
    // delivery proves receipt, but cannot reinstate revoked configuration trust.
    private var nativeHookTrusted = false
    private var currentRunDeliveredInstallation: String?
    private var bridgeRunStartedAt = Date()
    private var configurationClient: CodexAppServerClient?
    let liveIsland = IslandSession()
    private var preferenceCancellable: AnyCancellable?
    private var observationTask: Task<Void, Never>?
    private var desktopIPCClient: CodexDesktopIPCClient
    private var desktopObservationTask: Task<Void, Never>?
    private var desktopRunGeneration: UInt64 = 0
    private var desktopFollowedThreads: Set<String> = []
    private var observationsEnabled = false
    private var accessibilityCancellable: AnyCancellable?
    private var quotaStatusCancellable: AnyCancellable?
    private var islandUsage: IslandUsagePresentation = .loading
    private var workspaceCancellables: Set<AnyCancellable> = []
    private var setupTask: Task<Void, Never>?
    private var setupIslandRequested = false
    private var isRunning = false

    private enum DefaultsKey {
        static let setupEnabled = "codexActivity.setup.enabled"
        static let automaticHook = "codexActivity.setup.automaticHook"
        static let consentVersion = "codexActivity.setup.nativeConsentVersion"
        static let consentedInstallation = "codexActivity.setup.consentedInstallation"
        static let consentedEvents = "codexActivity.setup.consentedEvents"
        static let observedInstallation =
            "codexActivity.setup.observedInstallation"
        static let connectedInstallation =
            "codexActivity.setup.connectedInstallation"
        static let restartProcessIdentifier =
            "codexActivity.setup.restartProcessIdentifier"
        static let reviewConfirmedInstallation =
            "codexActivity.setup.reviewConfirmedInstallation"
    }

    init(
        preferences: AppPreferences,
        quotaStatusStore: CodexStatusStore? = nil,
        defaults: UserDefaults = .standard,
        hookInstaller: CodexActivityHookInstaller? = nil,
        hookEnvironmentInspector: CodexActivityEnvironmentInspector? = nil,
        defaultDataDirectory: URL = CodexLocalRolloutActivityClient.Configuration.live().codexHomeURL,
        activityStore: CodexActivityStore? = nil,
        desktopIPCClient: CodexDesktopIPCClient? = nil,
        automaticHookSetupEnabled: Bool = true
    ) {
        self.preferences = preferences
        self.defaults = defaults
        self.automaticHookSetupEnabled = automaticHookSetupEnabled
        usesInjectedEnvironmentInspector = hookEnvironmentInspector != nil
        self.defaultDataDirectory = defaultDataDirectory
        let root = defaults.string(forKey: Self.dataDirectoryKey).map { URL(fileURLWithPath: $0) }
            ?? defaultDataDirectory
        dataDirectoryURL = root
        self.desktopIPCClient = desktopIPCClient ?? CodexDesktopIPCClient(configuration: .init(
            socketURL: root.appendingPathComponent("ipc/ipc.sock")))
        let environment = CodexActivityDirectoryEnvironment.make(root: root)
        store = activityStore ?? CodexActivityStore(
            titleClient: CodexAppServerClient(environment: environment),
            sharedActivityClient: CodexSharedAppServerActivityClient(configuration: .live(environment: environment)),
            localRolloutActivityClient: CodexLocalRolloutActivityClient(configuration: .live(environment: environment)),
            compactDelay:
                TimeInterval(preferences.codexActivityCompactDelay),
            hiddenDelayAfterCompact: TimeInterval(
                preferences.codexActivityHiddenDelayAfterCompact
            ),
            sessionDirectory: root
        )

        let tokenKey = "codexActivity.bridge.authenticationToken"
        let token: String
        if let injected = hookInstaller?.authenticationToken {
            token = injected
        } else if let existing = defaults.string(forKey: tokenKey),
           !existing.isEmpty
        {
            token = existing
        } else {
            token = UUID().uuidString.lowercased()
            defaults.set(token, forKey: tokenKey)
        }

        authenticationToken = token
        let socketURL = hookInstaller?.socketURL ?? Self.defaultSocketURL()
        let queueURL = hookInstaller?.queueURL ?? Self.defaultQueueURL()
        let installer = hookInstaller ?? CodexActivityHookInstaller(
            socketURL: socketURL,
            authenticationToken: token,
            queueURL: queueURL,
            dataDirectoryURL: root
        )
        self.installer = installer
        bridge = CodexActivityUnixBridge(
            socketURL: socketURL,
            authenticationToken: token,
            installationIdentifier: installer.installationIdentifier
        )
        fileBridge = CodexActivityFileBridge(
            queueURL: queueURL,
            authenticationToken: token,
            installationIdentifier: installer.installationIdentifier
        )
        environmentInspector = hookEnvironmentInspector ?? CodexActivityEnvironmentInspector(dataDirectoryURL: root)

        liveIsland.onWake = { [weak self] in self?.recheckAutomaticConnection() }
        store.localPublicContentDidReceive = { [weak self] content in self?.liveIsland.model.receiveLocalContent(content) }
        store.publicMessageDidReceive = { [weak self] data in
            self?.liveIsland.model.receive(data)
            self?.followDesktopThread(in: data)
        }
        store.desktopProjectionDidReceive = { [weak self] projection, snapshot in
            self?.liveIsland.model.receiveDesktopProjection(projection, snapshot: snapshot)
        }
        liveIsland.model.responseCapability = { [weak self] wire in
            guard let self, isRunning, !isChangingDataDirectory, let handle = wire.desktopHandle else { return false }
            return handle.conversationID == wire.threadID && handle.turnID == wire.turnID
        }
        liveIsland.model.respond = { [weak self] wire, result in
            guard let self, isRunning, !isChangingDataDirectory, let handle = wire.desktopHandle else {
                throw CodexDesktopIPCError.staleRequest
            }
            _ = try await self.desktopIPCClient.submit(handle: handle, result: result.data)
        }
        liveIsland.model.desktopRequestSettlementDidReceive = { [weak self] session, turn, epoch, stillWaiting in
            self?.store.receiveDesktopRequestSettlement(sessionHash: session, turnHash: turn,
                                                       epoch: epoch, stillWaiting: stillWaiting)
        }
        liveIsland.model.nativeRequestSettlementDidReceive = { [weak self] settlement in
            self?.store.receiveRequestSettlement(settlement)
        }
        store.admittedActivityDidReceive = { [weak self] event in self?.liveIsland.model.receiveLegacy(event) }
        store.cumulativeTokensDidReceive = { [weak self] update in self?.liveIsland.model.receiveToken(update) }
        store.stateDidChange = { [weak self] in
            self?.render()
        }
        store.automaticConnectionDidChange = { [weak self] state in
            self?.handleAutomaticConnection(state)
        }
        if let quotaStatusStore {
            liveIsland.board.state.onRefreshUsage = { [weak quotaStatusStore] in
                await quotaStatusStore?.refresh()
            }
            islandUsage = quotaStatusStore.islandUsage
            quotaStatusCancellable = quotaStatusStore.$islandUsage
                .receive(on: RunLoop.main)
                .sink { [weak self] usage in
                    self?.islandUsage = usage
                    self?.render()
                }
        }
        preferenceCancellable = preferences.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.render()
                }
            }
        accessibilityCancellable = NotificationCenter.default.publisher(
            for: NSWorkspace
                .accessibilityDisplayOptionsDidChangeNotification
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            Task { @MainActor in
                self?.render()
            }
        }

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.publisher(
            for: NSWorkspace.didLaunchApplicationNotification
        )
        .merge(with: workspaceCenter.publisher(
            for: NSWorkspace.didTerminateApplicationNotification
        ))
        .receive(on: RunLoop.main)
        .sink { [weak self] notification in
            guard let application = notification.userInfo?[
                NSWorkspace.applicationUserInfoKey
            ] as? NSRunningApplication,
            application.bundleIdentifier == "com.openai.codex"
            else {
                return
            }
            Task { @MainActor in
                self?.refreshConnectionStatus()
            }
        }
        .store(in: &workspaceCancellables)

        NotificationCenter.default.publisher(
            for: NSApplication.didChangeScreenParametersNotification
        )
        .merge(with: workspaceCenter.publisher(
            for: NSWorkspace.didActivateApplicationNotification
        ))
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            Task { @MainActor in
                self?.render()
            }
        }
        .store(in: &workspaceCancellables)
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        startDesktopObservation()
        nativeHookTrusted = false
        currentRunDeliveredInstallation = nil
        bridgeRunStartedAt = Date()
        bridgeRunGeneration &+= 1
        let bridgeRun = bridgeRunGeneration
        let handler: CodexActivityDeliveryHandler = {
            [weak self] delivery, completion in
            Task { @MainActor in
                guard let self else {
                    completion(false)
                    return
                }
                guard self.isRunning, self.bridgeRunGeneration == bridgeRun else {
                    // An old listener cannot associate its delayed delivery with
                    // the installation selected by a later app/bridge run.
                    completion(true)
                    return
                }
                completion(await self.receiveCompatibilityActivity(delivery))
            }
        }
        var isListening = false
        var failures: [String] = []

        do {
            try fileBridge.start(handler: handler, deliveryReady: false)
            isListening = true
        } catch {
            failures.append(error.localizedDescription)
        }

        do {
            try bridge.start(handler: handler)
            isListening = true
        } catch {
            failures.append(error.localizedDescription)
        }

        bridgeStatus = isListening
            ? .listening
            : .failed(failures.joined(separator: " "))
        reconcileOnLaunch()
    }

    private func startDesktopObservation() {
        desktopRunGeneration &+= 1
        let run = desktopRunGeneration
        let client = desktopIPCClient
        desktopObservationTask?.cancel()
        desktopObservationTask = Task { [weak self] in
            guard let self, isRunning, desktopRunGeneration == run else { return }
            await client.start(snapshotHandler: { [weak self] snapshot in
                guard let self else { return }
                await self.receiveDesktopSnapshot(snapshot, run: run)
            }, stateHandler: { [weak self] state in
                guard let self else { return }
                await self.receiveDesktopConnection(state, run: run)
            }, invalidationHandler: { [weak self] invalidation in
                guard let self else { return }
                await self.receiveDesktopInvalidation(invalidation, run: run)
            })
        }
    }

    private func receiveDesktopSnapshot(_ snapshot: CodexDesktopConversationSnapshot, run: UInt64) async {
        guard isRunning, !isChangingDataDirectory, desktopRunGeneration == run,
              let projection = try? CodexDesktopRequestProjector.project(
                conversationID: snapshot.conversationID, conversationStateData: snapshot.conversationState) else { return }
        let admitted = await store.receiveDesktopProjection(projection, snapshot: snapshot)
        guard isRunning, !isChangingDataDirectory, desktopRunGeneration == run else { return }
        if admitted, ["completed", "interrupted", "failed"].contains(projection.status) {
            stopFollowingDesktopThread(snapshot.conversationID)
        }
        render()
    }

    private func receiveDesktopConnection(_ state: CodexDesktopIPCConnectionState, run: UInt64) {
        guard isRunning, desktopRunGeneration == run else { return }
        let connected = state == .connected
        store.setDesktopConnection(connected: connected)
        liveIsland.model.setDesktopConnection(connected: connected, epoch: nil)
        render()
    }

    private func receiveDesktopInvalidation(_ invalidation: CodexDesktopIPCInvalidation, run: UInt64) {
        guard isRunning, !isChangingDataDirectory, desktopRunGeneration == run else { return }
        store.invalidateDesktopProjection(conversationID: invalidation.conversationID, epoch: invalidation.connectionEpoch)
        liveIsland.model.invalidateDesktopResponses(conversationID: invalidation.conversationID, epoch: invalidation.connectionEpoch)
        render()
    }

    private func followDesktopThread(in data: Data) {
        guard isRunning, !isChangingDataDirectory, let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let params = envelope["params"] as? [String: Any],
              let threadID = params["threadId"] as? String ?? (params["thread"] as? [String: Any])?["id"] as? String,
              !threadID.isEmpty else { return }
        let method = envelope["method"] as? String ?? ""
        if ["turn/completed", "thread/archived", "thread/closed"].contains(method) {
            stopFollowingDesktopThread(threadID)
            return
        }
        guard !desktopFollowedThreads.contains(threadID), desktopFollowedThreads.count < 100 else { return }
        desktopFollowedThreads.insert(threadID)
        let client = desktopIPCClient
        let run = desktopRunGeneration
        Task { [weak self] in
            guard let self, isRunning, !isChangingDataDirectory, desktopRunGeneration == run,
                  desktopFollowedThreads.contains(threadID) else { return }
            try? await client.follow(conversationID: threadID, hostID: "local")
        }
    }

    func enableCompatibilityHook() {
        guard hookOperation == .idle, !isChangingDataDirectory else { return }
        defaults.set(true, forKey: DefaultsKey.automaticHook)
        reconcileHook(install: true)
    }

    /// Consent is scoped to QuotaView's exact user Hook definitions, never trust-all.
    func openCodexSecurityReview() {
        guard hookOperation == .idle, !isChangingDataDirectory else { return }
        defaults.set(true, forKey: DefaultsKey.automaticHook)
        reconcileHook(install: true, authorize: true)
    }

    func disableCompatibilityHook() {
        guard hookOperation == .idle, !isChangingDataDirectory else { return }
        // User intent is independent of best-effort filesystem cleanup. A failed
        // removal must never grant the repair path permission to reinstall.
        defaults.set(false, forKey: DefaultsKey.setupEnabled)
        defaults.set(false, forKey: DefaultsKey.automaticHook)
        for key in [DefaultsKey.consentVersion, DefaultsKey.consentedInstallation,
                    DefaultsKey.consentedEvents, DefaultsKey.observedInstallation,
                    DefaultsKey.connectedInstallation, DefaultsKey.restartProcessIdentifier,
                    DefaultsKey.reviewConfirmedInstallation] {
            defaults.removeObject(forKey: key)
        }
        nativeHookTrusted = false
        currentRunDeliveredInstallation = nil
        hookEventGeneration &+= 1
        setupIslandRequested = false
        store.compactionSourceUnavailable(.hook)
        let operation = beginHookOperation(.removing)
        let installer = installer
        setupTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                Result { try installer.uninstall() }
            }.value
            guard let self, !Task.isCancelled, hookOperationRevision == operation else { return }
            defer {
                if hookOperationRevision == operation, isRunning {
                    // Authentication is still scoped to this installation;
                    // opted-out Runtime discards residual cached deliveries.
                    fileBridge.setDeliveryReady(true)
                }
            }
            hookOperation = .idle
            switch result {
            case .success:
                hookConnectionStatus = .notInstalled
                hasCompatibilityHook = false
                compatibilityHookScope = nil
            case .failure(let error):
                // Keep the opt-out. These flags report resource residue, never
                // permission to execute or automatically recreate the channel.
                hasCompatibilityHook = (try? installer.hasQuotaViewHandlers()) ?? hasCompatibilityHook
                compatibilityHookScope = try? installer.installedScope()
                hookConnectionStatus = .abnormal(error.localizedDescription)
            }
            // App Server/local readers continue independently of Hook cleanup.
            render()
        }
    }

    func recheckAutomaticConnection() {
        guard !isChangingDataDirectory else { return }
        directorySelectionFailed = false
        if isRunning { startDesktopObservation() }
        Task { await store.recheckLocalDiscovery() }
    }

    var usesCustomDataDirectory: Bool { defaults.string(forKey: Self.dataDirectoryKey) != nil }

    func chooseDataDirectory() {
        guard !isChangingDataDirectory else { return }
        let copy = AppCopy(language: preferences.resolvedLanguage)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = dataDirectoryURL
        panel.message = copy.text("选择 Codex 数据目录（通常是 .codex，包含 sessions 文件夹）。", "Choose the Codex data directory (usually .codex, containing the sessions folder).")
        panel.prompt = copy.text("选择目录", "Choose Directory")
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in self?.selectDataDirectory(url) }
        }
    }

    private func stopFollowingDesktopThread(_ threadID: String) {
        guard desktopFollowedThreads.remove(threadID) != nil else { return }
        let client = desktopIPCClient
        let run = desktopRunGeneration
        Task { [weak self] in
            guard let self, isRunning, desktopRunGeneration == run,
                  !desktopFollowedThreads.contains(threadID) else { return }
            await client.unfollow(conversationID: threadID, hostID: "local")
        }
    }

    func selectDataDirectory(_ root: URL?) {
        guard !isChangingDataDirectory, hookOperation == .idle else { return }
        let target = root?.standardizedFileURL ?? defaultDataDirectory
        if root != nil {
            let sessions = target.appendingPathComponent("sessions")
            var directory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: sessions.path, isDirectory: &directory),
                  directory.boolValue, FileManager.default.isReadableFile(atPath: sessions.path),
                  FileManager.default.isExecutableFile(atPath: sessions.path) else {
                directorySelectionFailed = true
                return
            }
        }
        directorySelectionFailed = false
        isChangingDataDirectory = true
        fileBridge.setDeliveryReady(false)
        directoryTask = Task { [weak self] in
            guard let self else { return }
            // Revoke callbacks and actions before Store resets its admission scope.
            desktopRunGeneration &+= 1
            desktopObservationTask?.cancel(); desktopObservationTask = nil
            desktopFollowedThreads.removeAll()
            store.setDesktopConnection(connected: false)
            liveIsland.model.setDesktopConnection(connected: false, epoch: nil)
            await desktopIPCClient.stop()
            guard !Task.isCancelled else { return }
            guard await store.changeDataDirectory(target), !Task.isCancelled else {
                if !Task.isCancelled {
                    _ = await store.changeDataDirectory(dataDirectoryURL)
                    liveIsland.model.reset()
                    isChangingDataDirectory = false
                    directorySelectionFailed = true
                    fileBridge.setDeliveryReady(true)
                    if isRunning { startDesktopObservation() }
                }
                return
            }
            desktopIPCClient = CodexDesktopIPCClient(configuration: .init(
                socketURL: target.appendingPathComponent("ipc/ipc.sock")))
            liveIsland.model.reset()
            dataDirectoryURL = target
            hookEventGeneration &+= 1
            bridge.stop()
            fileBridge.stop()
            installer = CodexActivityHookInstaller(socketURL: Self.defaultSocketURL(),
                authenticationToken: authenticationToken, queueURL: Self.defaultQueueURL(), dataDirectoryURL: target)
            environmentInspector = CodexActivityEnvironmentInspector(
                executablePath: environmentInspector.executablePath, dataDirectoryURL: target)
            bridge = CodexActivityUnixBridge(socketURL: installer.socketURL,
                authenticationToken: authenticationToken, installationIdentifier: installer.installationIdentifier)
            fileBridge = CodexActivityFileBridge(queueURL: Self.defaultQueueURL(),
                authenticationToken: authenticationToken, installationIdentifier: installer.installationIdentifier)
            nativeHookTrusted = false
            currentRunDeliveredInstallation = nil
            bridgeRunStartedAt = Date()
            hasCompatibilityHook = false
            compatibilityHookScope = nil
            defaults.removeObject(forKey: DefaultsKey.observedInstallation)
            defaults.removeObject(forKey: DefaultsKey.connectedInstallation)
            if root == nil { defaults.removeObject(forKey: Self.dataDirectoryKey) }
            else { defaults.set(target.path, forKey: Self.dataDirectoryKey) }
            isChangingDataDirectory = false
            if isRunning { isRunning = false; start() }
        }
    }

    func refreshConnectionStatus() {
        guard !isConfiguring, !isOpeningSecurityReview, !isChangingDataDirectory else { return }
        if isRunning { startDesktopObservation() }
        reconcileHook(install: automaticHookEnabled)
    }

    var connectionPresentation: CodexActivityConnectionPresentation {
        .init(connection: automaticConnection, hookStatus: hookConnectionStatus)
    }

    var isNativeActivityConnected: Bool {
        nativeConnectionState == .connected
    }

    func stop() async {
        isRunning = false
        desktopRunGeneration &+= 1
        desktopObservationTask?.cancel(); desktopObservationTask = nil
        desktopFollowedThreads.removeAll()
        await desktopIPCClient.stop()
        store.setDesktopConnection(connected: false)
        liveIsland.model.setDesktopConnection(connected: false, epoch: nil)
        nativeHookTrusted = false
        currentRunDeliveredInstallation = nil
        bridgeRunGeneration &+= 1
        hookOperationRevision &+= 1
        hookEventGeneration &+= 1
        hookOperation = .idle
        directoryTask?.cancel()
        directoryTask = nil
        isChangingDataDirectory = false
        setupTask?.cancel()
        bridge.stop()
        fileBridge.stop()
        bridgeStatus = .stopped
        await configurationClient?.stop()
        configurationClient = nil
        await store.stop()
        observationTask?.cancel(); observationTask = nil; observationsEnabled = false
        liveIsland.stop()
    }

    var hookDirectoryPath: String { installer.hooksURL.deletingLastPathComponent().path }

    var diagnosticLogPath: String {
        CodexActivityDiagnostics.logURL.path
    }

    private func handleAutomaticConnection(_ state: CodexAutomaticActivityConnection) {
        automaticConnection = state
        if state.nativeState == .connected {
            setupIslandRequested = false
        }
        if isRunning { render() }
    }

    @discardableResult
    private func beginHookOperation(_ operation: CodexHookOperation) -> UInt64 {
        setupTask?.cancel()
        if let client = configurationClient { Task { await client.stop() } }
        configurationClient = nil
        hookOperationRevision &+= 1
        hookOperation = operation
        fileBridge.setDeliveryReady(false)
        return hookOperationRevision
    }

    private var compatibilityHookAdmissionEnabled: Bool {
        defaults.object(forKey: DefaultsKey.automaticHook) as? Bool != false
    }

    private var automaticHookEnabled: Bool {
        automaticHookSetupEnabled && compatibilityHookAdmissionEnabled
    }

    private func reconcileOnLaunch() {
        // Start the independent readers immediately while Hook maintenance runs.
        render()
        reconcileHook(install: automaticHookEnabled)
    }

    private func reconcileHook(install: Bool, authorize: Bool = false) {
        guard hookOperation == .idle, !isChangingDataDirectory else { return }
        if !usesInjectedEnvironmentInspector {
            environmentInspector = CodexActivityEnvironmentInspector(dataDirectoryURL: dataDirectoryURL)
        }
        let operation = beginHookOperation(authorize ? .reviewing : install ? .installing : .inspecting)
        let inspector = environmentInspector
        let installer = installer
        let root = dataDirectoryURL
        let client = CodexAppServerClient(executablePath: inspector.executablePath,
            environment: CodexActivityDirectoryEnvironment.make(root: root),
            startupTimeoutSeconds: 8, requestTimeoutSeconds: 8)
        configurationClient = client
        hooksFeatureStatus = .checking
        setupTask = Task { [weak self] in
            guard let self else { await client.stop(); return }
            defer {
                if hookOperationRevision == operation, isRunning {
                    // Inspect/repair has settled. Explicitly replay the retained
                    // queue rather than waiting for another filesystem write.
                    fileBridge.setDeliveryReady(true)
                }
            }
            do {
                if !install {
                    hasCompatibilityHook = try installer.hasQuotaViewHandlers()
                    if !hasCompatibilityHook {
                        compatibilityHookScope = nil
                        hooksFeatureStatus = .unavailable
                        hookConnectionStatus = .notInstalled
                        hookOperation = .idle
                        await client.stop()
                        render()
                        return
                    }
                    if !compatibilityHookAdmissionEnabled {
                        // An opted-out channel may leave resources after an I/O
                        // failure. Inspect residue without restoring native trust
                        // or admission, even when Codex retains the old hashes.
                        compatibilityHookScope = try? installer.installedScope()
                        nativeHookTrusted = false
                        currentRunDeliveredInstallation = nil
                        hooksFeatureStatus = .unavailable
                        hookConnectionStatus = .abnormal(preferences.copy.text(
                            "Hook 已停用，但仍有配置残留。请重试停用以完成清理。",
                            "Hooks are disabled, but configuration remains. Retry disabling to finish cleanup."))
                        hookOperation = .idle
                        await client.stop()
                        render()
                        return
                    }
                }
                var environment = try await Task.detached(priority: .utility) { try inspector.inspect() }.value
                guard !Task.isCancelled, hookOperationRevision == operation else { await client.stop(); return }
                if install, !environment.hooksEnabled {
                    // Codex owns parsing and effective configuration layers.
                    // Missing/failed metadata must never become permission to
                    // override an explicit user opt-out during maintenance.
                    let preference = try await client.readHookFeaturePreference(featureName: environment.hooksFeatureName)
                    guard !Task.isCancelled, hookOperationRevision == operation,
                          dataDirectoryURL == root else { await client.stop(); return }
                    environment = try await Task.detached(priority: .utility) {
                        try inspector.inspectAndEnableHooksIfNeeded(preference: preference)
                    }.value
                    guard !Task.isCancelled, hookOperationRevision == operation else { await client.stop(); return }
                }
                codexVersion = environment.version
                hooksFeatureStatus = environment.hooksEnabled ? .enabled : .disabled
                guard environment.hooksEnabled else {
                    hasCompatibilityHook = (try? installer.hasQuotaViewHandlers()) ?? false
                    throw HookSetupError.disabled(preferences.resolvedLanguage)
                }
                var definitionChanged = false
                if install {
                    let result = try await Task.detached(priority: .utility) { try installer.install() }.value
                    guard !Task.isCancelled, hookOperationRevision == operation else { await client.stop(); return }
                    definitionChanged = result.hookDefinitionChanged
                    if result.hookDefinitionChanged {
                        defaults.removeObject(forKey: DefaultsKey.observedInstallation)
                        defaults.removeObject(forKey: DefaultsKey.connectedInstallation)
                        nativeHookTrusted = false
                        currentRunDeliveredInstallation = nil
                    }
                    defaults.set(true, forKey: DefaultsKey.setupEnabled)
                }
                hasCompatibilityHook = try installer.hasQuotaViewHandlers()
                compatibilityHookScope = try installer.installedScope()
                guard hasCompatibilityHook, let scope = compatibilityHookScope else {
                    hookConnectionStatus = .notInstalled
                    hookOperation = .idle
                    await client.stop()
                    render()
                    return
                }
                let events = Set(scope.eventNames)
                var state = try await client.inspectOwnedHooks(sourceURL: installer.hooksURL,
                    command: installer.hookCommand, expectedEvents: events, cwds: [root])
                guard !Task.isCancelled, hookOperationRevision == operation else { await client.stop(); return }
                guard state.isComplete, state.isEnabled else { throw HookSetupError.incomplete(preferences.resolvedLanguage) }
                if !state.isTrusted && (authorize || (definitionChanged
                    && defaults.integer(forKey: DefaultsKey.consentVersion) == 1
                    && defaults.string(forKey: DefaultsKey.consentedInstallation) == installer.installationIdentifier
                    && defaults.string(forKey: DefaultsKey.consentedEvents) == events.sorted().joined(separator: ","))) {
                    // Recheck generation immediately before the only native configuration write.
                    guard !Task.isCancelled, hookOperationRevision == operation,
                          dataDirectoryURL == root else { await client.stop(); return }
                    state = try await client.authorizeOwnedHooks(sourceURL: installer.hooksURL,
                        command: installer.hookCommand, expectedEvents: events, cwds: [root])
                }
                guard !Task.isCancelled, hookOperationRevision == operation else { await client.stop(); return }
                nativeHookTrusted = state.isTrusted
                if authorize, state.isTrusted {
                    defaults.set(1, forKey: DefaultsKey.consentVersion)
                    defaults.set(installer.installationIdentifier, forKey: DefaultsKey.consentedInstallation)
                    defaults.set(events.sorted().joined(separator: ","), forKey: DefaultsKey.consentedEvents)
                }
                // Retire the old process-ID gate; real authenticated events never wait for an app restart.
                defaults.removeObject(forKey: DefaultsKey.restartProcessIdentifier)
                hookOperation = .idle
                updateConnectionStatusFromInstalledState()
            } catch {
                guard !Task.isCancelled, hookOperationRevision == operation else { await client.stop(); return }
                nativeHookTrusted = false
                hasCompatibilityHook = (try? installer.hasQuotaViewHandlers()) ?? hasCompatibilityHook
                compatibilityHookScope = try? installer.installedScope()
                if case CodexActivityEnvironmentInspector.InspectionError.hooksFeatureDisabled = error {
                    hooksFeatureStatus = .disabled
                } else if hooksFeatureStatus == .checking { hooksFeatureStatus = .unavailable }
                hookConnectionStatus = .abnormal(hookFailureDescription(error))
                hookOperation = .idle
                render()
            }
            await client.stop()
            if hookOperationRevision == operation { configurationClient = nil }
        }
    }

    private func hookFailureDescription(_ error: Error) -> String {
        let copy = preferences.copy
        if let error = error as? CodexHookConfigurationError {
            return switch error {
            case .incomplete: copy.text("Hook 配置未完整加载，请在 Codex 的 Hooks 设置中检查 QuotaView。", "Hooks have not fully loaded. Check QuotaView in Codex Hooks settings.")
            case .disabled: copy.text("QuotaView Hook 已在 Codex 中停用。", "QuotaView Hooks are disabled in Codex.")
            case .authorizationNotConfirmed: copy.text("Codex 尚未确认授权，请在 Hooks 设置中检查 QuotaView 后重试。", "Authorization was not confirmed. Check QuotaView in Codex Hooks settings and retry.")
            }
        }
        return error.localizedDescription
    }

    private enum HookSetupError: LocalizedError {
        case disabled(AppPreferences.Language), incomplete(AppPreferences.Language)
        var errorDescription: String? {
            switch self {
            case .disabled(let language): AppCopy(language: language).text("Codex 已禁用 Hooks。请在 Codex 设置中启用后重新检查。", "Hooks are disabled in Codex. Enable them in Codex Settings and recheck.")
            case .incomplete(let language): AppCopy(language: language).text("Codex 未完整加载 QuotaView Hook。请检查 Codex 的 Hooks 设置后重试。", "Codex has not fully loaded QuotaView Hooks. Check Codex Hooks settings and retry.")
            }
        }
    }

    private var hookEvidenceIdentifier: String {
        let identifier = installer.installationIdentifier
        // Full Hook activity cannot verify delivery of compression-only events.
        return compatibilityHookScope == .compaction ? identifier + ":compaction" : identifier
    }

    func receiveCompatibilityActivity(_ delivery: CodexActivityDelivery) async -> Bool {
        // Retry while launch inspection is pending; acknowledge and discard after
        // removal so cached Codex handlers cannot reactivate the optional channel.
        guard compatibilityHookAdmissionEnabled,
              !isChangingDataDirectory, hookOperation != .removing else { return true }
        guard hasCompatibilityHook else { return ![.inspecting, .installing].contains(hookOperation) }
        let eventGeneration = hookEventGeneration
        let activity = delivery.activity
        let installationID = hookEvidenceIdentifier
        var evidence = CodexActivityConnectionEvidence(
            observedInstallationID: defaults.string(
                forKey: DefaultsKey.observedInstallation
            ),
            connectedInstallationID: defaults.string(
                forKey: DefaultsKey.connectedInstallation
            )
        )
        evidence.record(
            event: activity.event,
            installationID: installationID,
            compactionOnly: compatibilityHookScope == .compaction
        )
        defaults.set(
            evidence.observedInstallationID,
            forKey: DefaultsKey.observedInstallation
        )
        if let connectedInstallationID =
            evidence.connectedInstallationID
        {
            defaults.set(
                connectedInstallationID,
                forKey: DefaultsKey.connectedInstallation
            )
        }
        // Persisted evidence describes historical receipt. Only a live event
        // produced in this bridge run establishes its current delivery health.
        if [.liveSocket, .liveQueue].contains(delivery.source), activity.occurredAt >= bridgeRunStartedAt {
            var freshEvidence = CodexActivityConnectionEvidence()
            freshEvidence.record(event: activity.event, installationID: installationID,
                compactionOnly: compatibilityHookScope == .compaction)
            if freshEvidence.connectedInstallationID == installationID {
                currentRunDeliveredInstallation = installationID
            }
        }
        // Receipt cannot turn an inspection failure or explicit opt-out into
        // an authorization prompt/success. Preserve Codex's configuration result.
        if nativeHookTrusted {
            updateConnectionStatusFromInstalledState()
            if hookConnectionStatus == .connected { setupIslandRequested = false }
        }
        let snapshotBeforeDelivery = store.snapshot
        let presentationBeforeDelivery = store.presentation
        let lifecycleBeforeDelivery = store.lifecycle
        await store.receiveClassified(delivery, admissionAllowed: { [weak self] in
            guard let self else { return false }
            return self.hasCompatibilityHook && self.hookEventGeneration == eventGeneration
                && self.hookOperation != .removing
        })
        let didApplyDelivery = store.snapshot != snapshotBeforeDelivery
            || store.presentation != presentationBeforeDelivery
            || store.lifecycle != lifecycleBeforeDelivery
        CodexActivityDiagnostics.record(
            delivery: delivery,
            outcome: didApplyDelivery
                ? "accepted_applied"
                : "accepted_ignored"
        )
        return true
    }

    private func updateConnectionStatusFromInstalledState() {
        if case .failed(let message) = bridgeStatus {
            hookConnectionStatus = .abnormal(message)
        } else if !nativeHookTrusted {
            hookConnectionStatus = .awaitingTrust
        } else if currentRunDeliveredInstallation == hookEvidenceIdentifier {
            hookConnectionStatus = .connected
        } else {
            hookConnectionStatus = .awaitingFirstEvent
        }
        render()
    }

    var onOpenSettings: (() -> Void)? {
        get { liveIsland.board.state.onOpenSettings }
        set { liveIsland.board.state.onOpenSettings = newValue }
    }

    private func render() {
        guard isRunning else { return }
        // The primary interface stays available for the application's lifetime.
        // Retired menu-bar/standalone-island visibility preferences do not hide it.
        let enabled = true
        if observationsEnabled != enabled {
            observationsEnabled = enabled
            let previous = observationTask
            observationTask = Task { [weak self] in
                await previous?.value
                guard let self, isRunning, observationsEnabled == enabled else { return }
                if enabled { store.startNativeActivityNotifications() }
                else { await store.stop() }
            }
        }
        store.setMultitaskEnabled(enabled)
        liveIsland.model.setConnection(store.automaticConnection.sharedState)
        for entry in store.multitask.entries {
            liveIsland.model.setTitle(store.title(for: entry.snapshot.sessionHash), for: entry.snapshot.sessionHash)
        }
        let current = islandUsage.state.isCurrent ? islandUsage.snapshot : nil
        liveIsland.update(english: preferences.resolvedLanguage == .english,
            remaining: current?.remainingPercent, enabled: enabled, privacy: preferences.codexIslandPrivacy,
            weeklyRemaining: current?.weeklyRemainingPercent,
            quotaResetsAt: current?.resetsAt, usageSnapshot: islandUsage.snapshot, usageState: islandUsage.state,
            usageOptions: .init(preferences: preferences), progressEffect: preferences.codexActivityProgressEffect,
            automaticPopupEnabled: preferences.codexActivityAutomaticPopupEnabled,
            automaticPopupDuration: preferences.codexActivityAutomaticPopupDuration)
    }

    private static func defaultSocketURL() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent(Bundle.main.bundleIdentifier == "com.quotaview.development073" ? "QuotaView-073-Development" : "QuotaView", isDirectory: true)
            .appendingPathComponent("codex-activity.sock")
    }

    private static func defaultQueueURL() -> URL {
        URL(
            fileURLWithPath:
                "/tmp/\(Bundle.main.bundleIdentifier == "com.quotaview.development073" ? "com.quotaview.development073" : "com.quotaview").codex-activity-\(getuid())",
            isDirectory: true
        )
    }
}
