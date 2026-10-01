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

    let store: CodexActivityStore

    private let preferences: AppPreferences
    private let defaults: UserDefaults
    private let bridge: CodexActivityUnixBridge
    private let fileBridge: CodexActivityFileBridge
    private let installer: CodexActivityHookInstaller
    private let environmentInspector: CodexActivityEnvironmentInspector
    private let securityReviewLauncher: CodexSecurityReviewLauncher
    let liveIsland = IslandSession()
    private var preferenceCancellable: AnyCancellable?
    private var observationTask: Task<Void, Never>?
    private var observationsEnabled = false
    private var accessibilityCancellable: AnyCancellable?
    private var quotaStatusCancellable: AnyCancellable?
    private var islandUsage: IslandUsagePresentation = .loading
    private var workspaceCancellables: Set<AnyCancellable> = []
    private var setupTask: Task<Void, Never>?
    private var securityReviewObservationTask: Task<Void, Never>?
    private var setupIslandRequested = false
    private var isInspectingCompatibilityHook: Bool { hookOperation == .inspecting }
    private var isRunning = false

    private enum DefaultsKey {
        static let setupEnabled = "codexActivity.setup.enabled"
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
        activityStore: CodexActivityStore? = nil
    ) {
        self.preferences = preferences
        self.defaults = defaults
        self.defaultDataDirectory = defaultDataDirectory
        let root = defaults.string(forKey: Self.dataDirectoryKey).map { URL(fileURLWithPath: $0) }
            ?? defaultDataDirectory
        dataDirectoryURL = root
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
        if let existing = defaults.string(forKey: tokenKey),
           !existing.isEmpty
        {
            token = existing
        } else {
            token = UUID().uuidString.lowercased()
            defaults.set(token, forKey: tokenKey)
        }

        let socketURL = hookInstaller?.socketURL ?? Self.defaultSocketURL()
        let queueURL = Self.defaultQueueURL()
        let installer = hookInstaller ?? CodexActivityHookInstaller(
            socketURL: socketURL,
            authenticationToken: token
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
        environmentInspector = hookEnvironmentInspector ?? CodexActivityEnvironmentInspector()
        securityReviewLauncher = CodexSecurityReviewLauncher(
            codexExecutablePath: environmentInspector.executablePath
        )

        liveIsland.onWake = { [weak self] in self?.recheckAutomaticConnection() }
        store.localPublicContentDidReceive = { [weak self] content in self?.liveIsland.model.receiveLocalContent(content) }
        store.publicMessageDidReceive = { [weak self] data in self?.liveIsland.model.receive(data) }
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
        let handler: CodexActivityDeliveryHandler = {
            [weak self] delivery, completion in
            Task { @MainActor in
                guard let self else {
                    completion(false)
                    return
                }
                completion(await self.receiveCompatibilityActivity(delivery))
            }
        }
        var isListening = false
        var failures: [String] = []

        do {
            try fileBridge.start(handler: handler)
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

    func enableCompatibilityHook() {
        setupIslandRequested = true
        render()
        configure()
    }

    func openCodexSecurityReview() {
        guard !isConfiguring, !isOpeningSecurityReview else { return }
        securityReviewObservationTask?.cancel()
        let operation = beginHookOperation(.reviewing)
        setupIslandRequested = true
        render()

        let launcher = securityReviewLauncher
        let baselineProcessIdentifier =
            Self.runningCodexProcessIdentifier().map(Int.init) ?? 0
        setupTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                Result { try launcher.prepareLauncher() }
            }.value
            guard let self, !Task.isCancelled, hookOperationRevision == operation else { return }

            switch result {
            case .success(let launcherURL):
                guard NSWorkspace.shared.open(launcherURL) else {
                    hookOperation = .idle
                    hookConnectionStatus = .abnormal(
                        CodexSecurityReviewLauncher.LaunchError
                            .couldNotOpenTerminal.localizedDescription
                    )
                    render()
                    return
                }

                defaults.set(
                    baselineProcessIdentifier,
                    forKey: DefaultsKey.restartProcessIdentifier
                )
                defaults.removeObject(
                    forKey: DefaultsKey.observedInstallation
                )
                defaults.removeObject(
                    forKey: DefaultsKey.connectedInstallation
                )
                defaults.removeObject(
                    forKey: DefaultsKey.reviewConfirmedInstallation
                )
                hookConnectionStatus = .awaitingTrust
                hookOperation = .idle
                observeSecurityReviewCompletion()
                render()
            case .failure(let error):
                hookOperation = .idle
                hookConnectionStatus = .abnormal(
                    error.localizedDescription
                )
                render()
            }
        }
    }

    func disableCompatibilityHook() {
        guard !isConfiguring, !isOpeningSecurityReview else { return }
        let operation = beginHookOperation(.removing)
        hookEventGeneration &+= 1
        securityReviewObservationTask?.cancel()
        let installer = installer
        setupTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                Result { try installer.uninstall() }
            }.value
            guard let self, !Task.isCancelled, hookOperationRevision == operation else { return }
            hookOperation = .idle
            switch result {
            case .success:
                defaults.set(false, forKey: DefaultsKey.setupEnabled)
                defaults.removeObject(
                    forKey: DefaultsKey.observedInstallation
                )
                defaults.removeObject(
                    forKey: DefaultsKey.connectedInstallation
                )
                defaults.removeObject(
                    forKey: DefaultsKey.restartProcessIdentifier
                )
                defaults.removeObject(
                    forKey: DefaultsKey.reviewConfirmedInstallation
                )
                setupIslandRequested = false
                hookConnectionStatus = .notInstalled
                hasCompatibilityHook = false
                compatibilityHookScope = nil
                store.compactionSourceUnavailable(.hook)
                // Removing a fallback must not erase the native task presentation.
                render()
            case .failure(let error):
                hookConnectionStatus = .abnormal(
                    error.localizedDescription
                )
                render()
            }
        }
    }

    func restartCodex() {
        guard !isConfiguring, !isOpeningSecurityReview else { return }
        let workspace = NSWorkspace.shared
        let runningApplication = NSRunningApplication
            .runningApplications(
                withBundleIdentifier: "com.openai.codex"
            )
            .first
        guard let applicationURL = runningApplication?.bundleURL
            ?? workspace.urlForApplication(
                withBundleIdentifier: "com.openai.codex"
            )
        else {
            hookConnectionStatus = .abnormal(
                localizedSetupMessage(
                    chinese: "找不到可以重新启动的 Codex 应用。",
                    english:
                        "QuotaView could not find the Codex application."
                )
            )
            render()
            return
        }

        let operation = beginHookOperation(.restarting)
        setupIslandRequested = true
        render()

        setupTask = Task { [weak self] in
            guard let self, !Task.isCancelled, hookOperationRevision == operation else { return }
            if let runningApplication,
               !runningApplication.isTerminated
            {
                guard runningApplication.terminate() else {
                    self.finishCodexRestart(
                        errorMessage: self.localizedSetupMessage(
                            chinese: "Codex 拒绝了重新启动请求。",
                            english:
                                "Codex declined the restart request."
                        )
                    )
                    return
                }
                for _ in 0..<40 where !runningApplication.isTerminated && !Task.isCancelled {
                    try? await Task.sleep(
                        nanoseconds: 250_000_000
                    )
                }
                guard !Task.isCancelled, hookOperationRevision == operation else { return }
                guard runningApplication.isTerminated else {
                    self.finishCodexRestart(
                        errorMessage: self.localizedSetupMessage(
                            chinese:
                                "Codex 尚未退出，请保存当前任务后重试。",
                            english:
                                "Codex is still running. Save the current task and try again."
                        )
                    )
                    return
                }
            }

            workspace.openApplication(
                at: applicationURL,
                configuration: NSWorkspace.OpenConfiguration()
            ) { [weak self] _, error in
                Task { @MainActor in
                    guard let self, self.hookOperationRevision == operation else { return }
                    self.finishCodexRestart(
                        errorMessage: error?.localizedDescription
                    )
                }
            }
        }
    }

    func recheckAutomaticConnection() {
        guard !isChangingDataDirectory else { return }
        directorySelectionFailed = false
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

    func selectDataDirectory(_ root: URL?) {
        guard !isChangingDataDirectory else { return }
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
        directoryTask = Task { [weak self] in
            guard let self else { return }
            guard await store.changeDataDirectory(target), !Task.isCancelled else {
                if !Task.isCancelled { isChangingDataDirectory = false }
                return
            }
            liveIsland.model.reset()
            dataDirectoryURL = target
            if root == nil { defaults.removeObject(forKey: Self.dataDirectoryKey) }
            else { defaults.set(target.path, forKey: Self.dataDirectoryKey) }
            isChangingDataDirectory = false
        }
    }

    func refreshConnectionStatus() {
        guard !isConfiguring, !isOpeningSecurityReview else { return }
        inspectEnvironmentAndInstallation()
    }

    var connectionPresentation: CodexActivityConnectionPresentation {
        .init(connection: automaticConnection, hookStatus: hookConnectionStatus)
    }

    var isNativeActivityConnected: Bool {
        nativeConnectionState == .connected
    }

    func stop() async {
        isRunning = false
        hookOperationRevision &+= 1
        hookEventGeneration &+= 1
        hookOperation = .idle
        directoryTask?.cancel()
        directoryTask = nil
        isChangingDataDirectory = false
        setupTask?.cancel()
        securityReviewObservationTask?.cancel()
        bridge.stop()
        fileBridge.stop()
        bridgeStatus = .stopped
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
        hookOperationRevision &+= 1
        hookOperation = operation
        return hookOperationRevision
    }

    private func reconcileOnLaunch() {
        // Existing installations are inspected, never repaired implicitly.
        inspectEnvironmentAndInstallation()
    }

    private func configure() {
        guard !isConfiguring, !isOpeningSecurityReview else { return }
        let operation = beginHookOperation(.installing)
        hooksFeatureStatus = .checking

        let inspector = environmentInspector
        let installer = installer
        setupTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                Result {
                    let environment =
                        try inspector.inspectAndEnableHooksIfNeeded()
                    let installation = try installer.install()
                    return CodexActivitySetupResult.installed(
                        environment: environment,
                        hookDefinitionChanged:
                            installation.hookDefinitionChanged
                    )
                }
            }.value

            guard let self, !Task.isCancelled, hookOperationRevision == operation else { return }
            hookOperation = .idle
            switch result {
            case .success(.installed(
                let environment,
                let hookDefinitionChanged
            )):
                codexVersion = environment.version
                hooksFeatureStatus = .enabled
                defaults.set(true, forKey: DefaultsKey.setupEnabled)

                if hookDefinitionChanged
                    || environment.didEnableHooks
                {
                    defaults.removeObject(
                        forKey: DefaultsKey.observedInstallation
                    )
                    defaults.removeObject(
                        forKey: DefaultsKey.connectedInstallation
                    )
                    defaults.removeObject(
                        forKey: DefaultsKey.restartProcessIdentifier
                    )
                    defaults.removeObject(
                        forKey: DefaultsKey.reviewConfirmedInstallation
                    )
                }
                hasCompatibilityHook = true
                compatibilityHookScope = .all
                updateConnectionStatusFromInstalledState()
                if hookConnectionStatus != .connected
                {
                    openCodexSecurityReview()
                }
            case .failure(let error):
                hasCompatibilityHook = (try? installer.hasQuotaViewHandlers()) ?? hasCompatibilityHook
                hooksFeatureStatus = .unavailable
                hookConnectionStatus = .abnormal(
                    error.localizedDescription
                )
                render()
            }
        }
    }

    private func inspectEnvironmentAndInstallation() {
        let operation = beginHookOperation(.inspecting)
        let inspector = environmentInspector
        let installer = installer
        setupTask = Task { [weak self] in
            let inspection = await Task.detached(priority: .utility) {
                let handlers = Result { try installer.hasQuotaViewHandlers() }
                let scope = try? installer.installedScope()
                // A first install has no reason to invoke Hook feature commands.
                let environment = (try? handlers.get()) == true
                    ? Result { try inspector.inspect() } : nil
                return (handlers, scope, environment)
            }.value
            guard let self, !Task.isCancelled, hookOperationRevision == operation else { return }
            hookOperation = .idle
            let (handlers, scope, environment) = inspection
            compatibilityHookScope = scope
            switch handlers {
            case .success(let exists):
                hasCompatibilityHook = exists
                if !exists {
                    store.compactionSourceUnavailable(.hook)
                    hooksFeatureStatus = .unavailable
                    hookConnectionStatus = .notInstalled
                    setupIslandRequested = false
                } else if let environment {
                    switch environment {
                    case .success(let value):
                        codexVersion = value.version
                        hooksFeatureStatus = value.hooksEnabled ? .enabled : .disabled
                        if scope != nil, value.hooksEnabled { updateConnectionStatusFromInstalledState() }
                        else { hookConnectionStatus = .abnormal(preferences.copy.text("兼容 Hook 需要手动修复。", "Compatibility Hook needs manual repair.")) }
                    case .failure(let error):
                        hooksFeatureStatus = .unavailable
                        hookConnectionStatus = .abnormal(error.localizedDescription)
                    }
                }
            case .failure(let error):
                hooksFeatureStatus = .unavailable
                // Keep removal available for a known installation even if inspection fails.
                hasCompatibilityHook = defaults.bool(forKey: DefaultsKey.setupEnabled)
                hookConnectionStatus = .abnormal(error.localizedDescription)
            }
            render()
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
        guard hasCompatibilityHook else { return !isInspectingCompatibilityHook }
        let eventGeneration = hookEventGeneration
        let activity = delivery.activity
        guard canAcceptActivityAfterRequiredRestart() else {
            render()
            CodexActivityDiagnostics.record(
                delivery: delivery,
                outcome: "rejected_restart_required"
            )
            return false
        }

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
        updateConnectionStatusFromInstalledState()
        if hookConnectionStatus == .connected {
            setupIslandRequested = false
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

    private func canAcceptActivityAfterRequiredRestart() -> Bool {
        guard let baselineProcessIdentifier = defaults.object(
            forKey: DefaultsKey.restartProcessIdentifier
        ) as? Int
        else {
            return true
        }

        guard let currentProcessIdentifier =
            Self.runningCodexProcessIdentifier(),
            CodexActivityRestartRequirement(
                baselineProcessIdentifier: baselineProcessIdentifier
            ).isSatisfied(
                currentProcessIdentifier: currentProcessIdentifier
            )
        else {
            return false
        }

        defaults.removeObject(
            forKey: DefaultsKey.restartProcessIdentifier
        )
        return true
    }

    private func updateConnectionStatusFromInstalledState() {
        if case .failed(let message) = bridgeStatus {
            hookConnectionStatus = .abnormal(message)
            render()
            return
        }

        let installationID = installer.installationIdentifier
        let reviewConfirmed = defaults.string(
            forKey: DefaultsKey.reviewConfirmedInstallation
        ) == installationID

        if let restartProcessIdentifier = defaults.object(
            forKey: DefaultsKey.restartProcessIdentifier
        ) as? Int {
            if restartProcessIdentifier == 0, reviewConfirmed {
                defaults.removeObject(
                    forKey: DefaultsKey.restartProcessIdentifier
                )
            } else {
                let currentProcessIdentifier =
                    Self.runningCodexProcessIdentifier()
                let requirement = CodexActivityRestartRequirement(
                    baselineProcessIdentifier: restartProcessIdentifier
                )
                if !requirement.isSatisfied(
                    currentProcessIdentifier: currentProcessIdentifier
                ) {
                    hookConnectionStatus =
                        CodexActivitySetupStatusResolver.resolve(
                            evidenceStatus: .awaitingTrust,
                            reviewConfirmed: reviewConfirmed,
                            requiresRestart: true
                        )
                    render()
                    return
                }
                defaults.removeObject(
                    forKey: DefaultsKey.restartProcessIdentifier
                )
            }
        }

        let evidence = CodexActivityConnectionEvidence(
            observedInstallationID: defaults.string(
                forKey: DefaultsKey.observedInstallation
            ),
            connectedInstallationID: defaults.string(
                forKey: DefaultsKey.connectedInstallation
            )
        )
        let evidenceStatus = evidence.status(for: hookEvidenceIdentifier)
        hookConnectionStatus = CodexActivitySetupStatusResolver.resolve(
            evidenceStatus: evidenceStatus,
            reviewConfirmed: reviewConfirmed,
            requiresRestart: false
        )
        if hookConnectionStatus == .connected {
            setupIslandRequested = false
        }
        render()
    }

    private func observeSecurityReviewCompletion() {
        securityReviewObservationTask?.cancel()
        let completionURL = securityReviewLauncher.reviewCompletionURL
        let installationID = installer.installationIdentifier
        securityReviewObservationTask = Task { [weak self] in
            for _ in 0..<1_200 {
                guard let self, !Task.isCancelled else { return }
                if FileManager.default.fileExists(
                    atPath: completionURL.path
                ) {
                    let result = try? String(
                        contentsOf: completionURL,
                        encoding: .utf8
                    ).trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    try? FileManager.default.removeItem(
                        at: completionURL
                    )
                    if result == "confirmed" {
                        self.defaults.set(
                            installationID,
                            forKey:
                                DefaultsKey.reviewConfirmedInstallation
                        )
                        self.updateConnectionStatusFromInstalledState()
                    } else {
                        self.hookConnectionStatus = .abnormal(
                            self.localizedSetupMessage(
                                chinese:
                                    "Codex 安全确认未完成，请重试。",
                                english:
                                    "The Codex security review did not complete. Try again."
                            )
                        )
                        self.render()
                    }
                    return
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    private func finishCodexRestart(errorMessage: String?) {
        hookOperation = .idle
        if let errorMessage {
            hookConnectionStatus = .abnormal(errorMessage)
            render()
        } else {
            updateConnectionStatusFromInstalledState()
        }
    }

    private func localizedSetupMessage(
        chinese: String,
        english: String
    ) -> String {
        switch preferences.resolvedLanguage {
        case .simplifiedChinese: chinese
        case .english: english
        }
    }

    private static func runningCodexProcessIdentifier() -> pid_t? {
        NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.openai.codex"
        )
        .first(where: { !$0.isTerminated })?
        .processIdentifier
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
