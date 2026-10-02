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
    private var bridge: CodexActivityUnixBridge
    private var fileBridge: CodexActivityFileBridge
    private var installer: CodexActivityHookInstaller
    private var environmentInspector: CodexActivityEnvironmentInspector
    private let authenticationToken: String
    private let automaticHookSetupEnabled: Bool
    private let usesInjectedEnvironmentInspector: Bool
    private var nativeHookTrusted = false
    private var configurationClient: CodexAppServerClient?
    let liveIsland = IslandSession()
    private var preferenceCancellable: AnyCancellable?
    private var observationTask: Task<Void, Never>?
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
        defaults.set(true, forKey: DefaultsKey.automaticHook)
        reconcileHook(install: true)
    }

    /// Consent is scoped to QuotaView's exact user Hook definitions, never trust-all.
    func openCodexSecurityReview() {
        reconcileHook(install: true, authorize: true)
    }

    func disableCompatibilityHook() {
        guard !isConfiguring, !isOpeningSecurityReview else { return }
        let operation = beginHookOperation(.removing)
        hookEventGeneration &+= 1
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
                defaults.set(false, forKey: DefaultsKey.automaticHook)
                defaults.removeObject(forKey: DefaultsKey.consentVersion)
                defaults.removeObject(forKey: DefaultsKey.consentedInstallation)
                defaults.removeObject(forKey: DefaultsKey.consentedEvents)
                nativeHookTrusted = false
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
        directoryTask = Task { [weak self] in
            guard let self else { return }
            guard await store.changeDataDirectory(target), !Task.isCancelled else {
                if !Task.isCancelled { isChangingDataDirectory = false }
                return
            }
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
        guard !isConfiguring, !isOpeningSecurityReview else { return }
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
        return hookOperationRevision
    }

    private var automaticHookEnabled: Bool {
        automaticHookSetupEnabled && (defaults.object(forKey: DefaultsKey.automaticHook) as? Bool ?? true)
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
                }
                let environment = try await Task.detached(priority: .utility) { try install ? inspector.inspectAndEnableHooksIfNeeded() : inspector.inspect() }.value
                guard !Task.isCancelled, hookOperationRevision == operation else { await client.stop(); return }
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
        nativeHookTrusted = true
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

    private func updateConnectionStatusFromInstalledState() {
        if case .failed(let message) = bridgeStatus {
            hookConnectionStatus = .abnormal(message)
        } else if !nativeHookTrusted {
            hookConnectionStatus = .awaitingTrust
        } else if defaults.string(forKey: DefaultsKey.connectedInstallation) == hookEvidenceIdentifier {
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
