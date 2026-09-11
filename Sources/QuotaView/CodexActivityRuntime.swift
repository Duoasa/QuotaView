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
    private var island: CodexActivityIslandPanelController?
    private var preferenceCancellable: AnyCancellable?
    private var timingPreferenceCancellable: AnyCancellable?
    private var accessibilityCancellable: AnyCancellable?
    private var screenTrackingCancellable: AnyCancellable?
    private var quotaStatusCancellable: AnyCancellable?
    private var currentQuotaPresentation: CurrentCodexPresentation?
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

        let socketURL = Self.defaultSocketURL()
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

        store.stateDidChange = { [weak self] in
            self?.render()
        }
        store.automaticConnectionDidChange = { [weak self] state in
            self?.handleAutomaticConnection(state)
        }
        if let quotaStatusStore {
            currentQuotaPresentation = quotaStatusStore.hasCurrentCodexStatus
                ? quotaStatusStore.snapshot
                : nil
            quotaStatusCancellable = Publishers.CombineLatest(
                quotaStatusStore.$snapshot,
                quotaStatusStore.$errorMessage
            )
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot, errorMessage in
                self?.currentQuotaPresentation = errorMessage == nil
                    ? snapshot
                    : nil
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
        timingPreferenceCancellable = Publishers.CombineLatest(
            preferences.$codexActivityCompactDelay,
            preferences.$codexActivityHiddenDelayAfterCompact
        )
        .dropFirst()
        .receive(on: RunLoop.main)
        .sink { [weak self] compactDelay, hiddenDelay in
            self?.store.updateInactivityDelays(
                compactDelay: TimeInterval(compactDelay),
                hiddenDelayAfterCompact: TimeInterval(hiddenDelay)
            )
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
        store.startNativeActivityNotifications()
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
        island?.hide()
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
                updateConnectionStatusFromInstalledState()
                hasCompatibilityHook = true
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
                let installed = (try? installer.isInstalled()) ?? false
                // A first install has no reason to invoke Hook feature commands.
                let environment = (try? handlers.get()) == true
                    ? Result { try inspector.inspect() } : nil
                return (handlers, installed, environment)
            }.value
            guard let self, !Task.isCancelled, hookOperationRevision == operation else { return }
            hookOperation = .idle
            let (handlers, installed, environment) = inspection
            switch handlers {
            case .success(let exists):
                hasCompatibilityHook = exists
                if !exists {
                    hooksFeatureStatus = .unavailable
                    hookConnectionStatus = .notInstalled
                    setupIslandRequested = false
                } else if let environment {
                    switch environment {
                    case .success(let value):
                        codexVersion = value.version
                        hooksFeatureStatus = value.hooksEnabled ? .enabled : .disabled
                        if installed, value.hooksEnabled { updateConnectionStatusFromInstalledState() }
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

        let installationID = installer.installationIdentifier
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
            installationID: installationID
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
        let evidenceStatus = evidence.status(for: installationID)
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

    private func render() {
        defer { reconcileScreenTracking() }

        guard preferences.codexActivityIslandEnabled else {
            island?.hide()
            return
        }

        if shouldRenderDisconnectedIsland {
            renderDisconnectedIsland()
            return
        }

        guard let snapshot = store.snapshot,
              store.presentation != .hidden
        else {
            island?.hide()
            return
        }

        let title = store.resolvedThreadTitle
            ?? snapshot.workspaceName.map { "Codex · \($0)" }
            ?? "Codex"
        let copy = CodexActivityCopy(
            language: preferences.resolvedLanguage
        )
        let currentTurnTokenUsage = store.currentTurnTokenUsage
        let tokenUsageTitle = currentTurnTokenUsage.map {
            copy.tokenUsageTitle(totalTokens: $0)
        }
        let showsCompletionReceipt =
            CodexActivityTurnTokenUsagePresentationContract
            .showsCompletionReceipt(
                visualState: snapshot.state,
                operationKey: snapshot.operationKey,
                totalTokens: currentTurnTokenUsage
            )
        let completionQuotaRemainingPercent = showsCompletionReceipt
            ? currentQuotaPresentation?.remainingPercent
            : nil
        let baseAccessibilityLabel = copy.accessibilityLabel(
            windowTitle: title,
            statusTitle: copy.statusTitle(for: snapshot.state),
            operation: copy.operation(for: snapshot.operationKey),
            approximateProgressFraction:
                snapshot.approximateProgressFraction,
            tokenUsageTitle: tokenUsageTitle
        )
        let renderState = CodexActivityRenderState(
            taskIdentity: snapshot.taskIdentity,
            visualState: snapshot.state,
            approximateProgressFraction:
                snapshot.approximateProgressFraction,
            windowTitle: title,
            statusTitle: copy.statusTitle(for: snapshot.state),
            operation: copy.operation(
                for: snapshot.operationKey
            ),
            tokenUsageTitle: tokenUsageTitle,
            completionReceiptStatus: showsCompletionReceipt
                ? copy.statusTitle(for: snapshot.state)
                : nil,
            completionReceiptDetail: showsCompletionReceipt
                ? currentTurnTokenUsage.map {
                    copy.completionTokenUsageDetail(totalTokens: $0)
                }
                : nil,
            completionQuotaRemainingPercent:
                completionQuotaRemainingPercent,
            isConfirmationReminderActive:
                store.isConfirmationReminderActive,
            accessibilityLabel: showsCompletionReceipt
                ? baseAccessibilityLabel
                    + copy.completionQuotaAccessibilitySuffix(
                        remainingPercent:
                            completionQuotaRemainingPercent
                    )
                : baseAccessibilityLabel
        )
        let presentation: CodexActivityIslandPresentation =
            store.presentation == .compact ? .compact : .expanded
        let codexProcessIdentifier =
            Self.runningCodexProcessIdentifier()

        if island == nil {
            island = CodexActivityIslandPanelController(
                initialState: renderState,
                progressEffect:
                    preferences.codexActivityProgressEffect,
                screenPlacement:
                    preferences.codexActivityScreenPlacement,
                codexProcessIdentifier: codexProcessIdentifier
            )
        }
        island?.update(
            renderState: renderState,
            presentationMode: presentation,
            presentationAccessibilityValue:
                copy.presentationAccessibilityValue(presentation),
            reduceMotion:
                NSWorkspace.shared
                .accessibilityDisplayShouldReduceMotion,
            progressEffect: preferences.codexActivityProgressEffect,
            screenPlacement: preferences.codexActivityScreenPlacement,
            codexProcessIdentifier: codexProcessIdentifier,
            playbackEnabled: store.shouldPlayVisualEffects
        )
    }

    private func reconcileScreenTracking() {
        let shouldTrack = preferences.codexActivityIslandEnabled
            && preferences.codexActivityScreenPlacement == .codexScreen
            && island?.isVisible == true

        guard shouldTrack else {
            screenTrackingCancellable?.cancel()
            screenTrackingCancellable = nil
            return
        }
        guard screenTrackingCancellable == nil else { return }

        screenTrackingCancellable = Timer.publish(
            every: 1,
            on: .main,
            in: .common
        )
        .autoconnect()
        .sink { [weak self] _ in
            Task { @MainActor in
                guard let self,
                      let island = self.island,
                      island.isVisible
                else {
                    return
                }
                island.reposition(
                    screenPlacement: .codexScreen,
                    codexProcessIdentifier:
                        Self.runningCodexProcessIdentifier()
                )
            }
        }
    }

    private var shouldRenderDisconnectedIsland: Bool {
        connectionPresentation.showsHookSetupIsland(
            explicitlyRequested: setupIslandRequested
        )
    }

    private func renderDisconnectedIsland() {
        let copy = CodexActivityCopy(
            language: preferences.resolvedLanguage
        )
        let statusTitle = copy.statusTitle(
            for: .disconnectedCodex
        )
        let operation = copy.disconnectedOperation(
            for: hookConnectionStatus,
            isConfiguring: isConfiguring || isOpeningSecurityReview
        )
        let renderState = CodexActivityRenderState(
            visualState: .disconnectedCodex,
            approximateProgressFraction: nil,
            windowTitle: "QuotaView",
            statusTitle: statusTitle,
            operation: operation,
            accessibilityLabel: copy.accessibilityLabel(
                windowTitle: "QuotaView",
                statusTitle: statusTitle,
                operation: operation,
                approximateProgressFraction: nil
            )
        )
        let codexProcessIdentifier =
            Self.runningCodexProcessIdentifier()

        if island == nil {
            island = CodexActivityIslandPanelController(
                initialState: renderState,
                progressEffect:
                    preferences.codexActivityProgressEffect,
                screenPlacement:
                    preferences.codexActivityScreenPlacement,
                codexProcessIdentifier: codexProcessIdentifier
            )
        }
        island?.update(
            renderState: renderState,
            presentationMode: .expanded,
            presentationAccessibilityValue:
                copy.presentationAccessibilityValue(.expanded),
            reduceMotion:
                NSWorkspace.shared
                .accessibilityDisplayShouldReduceMotion,
            progressEffect: preferences.codexActivityProgressEffect,
            screenPlacement: preferences.codexActivityScreenPlacement,
            codexProcessIdentifier: codexProcessIdentifier,
            playbackEnabled: false
        )
    }

    private static func defaultSocketURL() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("QuotaView", isDirectory: true)
            .appendingPathComponent("codex-activity.sock")
    }

    private static func defaultQueueURL() -> URL {
        URL(
            fileURLWithPath:
                "/tmp/com.quotaview.codex-activity-\(getuid())",
            isDirectory: true
        )
    }
}
