import AppKit
import Combine
import Darwin
import Foundation
import QuotaViewCore

enum CodexActivityConnectionStatus: Equatable {
    case notInstalled
    case installedNeedsRestart
    case awaitingTrust
    case awaitingFirstEvent
    case connected
    case abnormal(String)
}

enum CodexHooksFeatureStatus: Equatable {
    case checking
    case enabled
    case disabled
    case unavailable
}

enum CodexActivityBridgeStatus: Equatable {
    case stopped
    case listening
    case failed(String)
}

@MainActor
final class CodexActivityStore: ObservableObject {
    nonisolated static let compactDelay: TimeInterval = 20
    nonisolated static let hiddenDelayAfterCompact: TimeInterval = 100

    struct TaskState: Equatable, Identifiable {
        let sessionHash: String
        var snapshot: CodexActivitySnapshot
        var resolvedThreadTitle: String?
        var presentation: CodexActivityPresentation

        var id: String { sessionHash }
    }

    @Published private(set) var tasks: [TaskState] = []
    @Published private(set) var primarySessionHash: String?
    @Published private(set) var presentation:
        CodexActivityPresentation = .hidden

    var snapshot: CodexActivitySnapshot? {
        primaryTask?.snapshot
    }

    var resolvedThreadTitle: String? {
        primaryTask?.resolvedThreadTitle
    }

    var primaryTask: TaskState? {
        guard let primarySessionHash else { return nil }
        return tasks.first { $0.sessionHash == primarySessionHash }
    }

    var resolvedTaskTitles: [String] {
        tasks.compactMap(\.resolvedThreadTitle)
    }

    var stateDidChange: (() -> Void)?

    private let titleClient: CodexAppServerClient
    private let compactDelayNanoseconds: UInt64
    private let hiddenDelayNanoseconds: UInt64
    private var inactivityTasks: [String: Task<Void, Never>] = [:]
    private var titleTasks: [String: Task<Void, Never>] = [:]
    private var titleCache: [String: String] = [:]
    private var titleAttemptedAt: [String: Date] = [:]
    private var latestEventAtBySession: [String: Date] = [:]
    private var revisions: [String: UInt64] = [:]
    private var focusedSessionHash: String?
    private var keepsFocusedPrimary = false
    private var manuallyExpanded = false

    init(
        titleClient: CodexAppServerClient = CodexAppServerClient(),
        compactDelay: TimeInterval = CodexActivityStore.compactDelay,
        hiddenDelayAfterCompact: TimeInterval =
            CodexActivityStore.hiddenDelayAfterCompact
    ) {
        self.titleClient = titleClient
        compactDelayNanoseconds = UInt64(
            max(compactDelay, 0) * 1_000_000_000
        )
        hiddenDelayNanoseconds = UInt64(
            max(hiddenDelayAfterCompact, 0) * 1_000_000_000
        )
    }

    func receive(_ event: CodexActivityEvent) {
        guard let nextSnapshot = CodexActivityReducer.snapshot(for: event)
        else {
            return
        }

        if let latestEventAt = latestEventAtBySession[event.sessionHash],
           event.occurredAt < latestEventAt
        {
            return
        }
        latestEventAtBySession[event.sessionHash] = event.occurredAt

        let eventRevision = (revisions[event.sessionHash] ?? 0) &+ 1
        revisions[event.sessionHash] = eventRevision
        inactivityTasks[event.sessionHash]?.cancel()
        inactivityTasks[event.sessionHash] = nil
        manuallyExpanded = false

        if CodexActivityReducer.shouldHideImmediately(after: event) {
            removeTask(sessionHash: event.sessionHash)
            return
        }

        if let index = taskIndex(for: event.sessionHash) {
            tasks[index].snapshot = nextSnapshot
            tasks[index].presentation = .expanded
            tasks[index].resolvedThreadTitle = titleCache[event.sessionHash]
        } else {
            tasks.append(
                TaskState(
                    sessionHash: event.sessionHash,
                    snapshot: nextSnapshot,
                    resolvedThreadTitle: titleCache[event.sessionHash],
                    presentation: .expanded
                )
            )
        }

        choosePrimaryTask()
        recomputePresentationAndNotify()

        resolveTitleIfNeeded(
            for: event.sessionHash,
            revision: eventRevision
        )

        if CodexActivityReducer.shouldStartInactivityCycle(after: event) {
            scheduleInactivityCycle(
                sessionHash: event.sessionHash,
                revision: eventRevision
            )
        }
    }

    func focusTask(matchingResolvedTitle title: String) {
        let normalizedTitle = title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalizedTitle.isEmpty else { return }

        let matches = tasks.filter {
            $0.resolvedThreadTitle == normalizedTitle
        }
        guard matches.count == 1 else { return }

        focusTask(sessionHash: matches[0].sessionHash)
    }

    func focusTask(sessionHash: String) {
        guard tasks.contains(where: {
            $0.sessionHash == sessionHash
        }) else {
            return
        }
        focusedSessionHash = sessionHash
        keepsFocusedPrimary = true
        guard primarySessionHash != sessionHash else { return }
        primarySessionHash = sessionHash
        notifyChange()
    }

    func releaseFocusedTask() {
        guard focusedSessionHash != nil || keepsFocusedPrimary else {
            return
        }
        focusedSessionHash = nil
        keepsFocusedPrimary = false
        let previousPrimary = primarySessionHash
        choosePrimaryTask()
        if previousPrimary != primarySessionHash {
            notifyChange()
        }
    }

    func expandCompactDetail() {
        guard tasks.count > 1, presentation == .compact else { return }
        manuallyExpanded = true
        presentation = .expanded
        notifyChange()
    }

    func hide() {
        revisions = revisions.mapValues { $0 &+ 1 }
        inactivityTasks.values.forEach { $0.cancel() }
        titleTasks.values.forEach { $0.cancel() }
        inactivityTasks.removeAll()
        titleTasks.removeAll()
        tasks.removeAll()
        primarySessionHash = nil
        focusedSessionHash = nil
        keepsFocusedPrimary = false
        manuallyExpanded = false
        presentation = .hidden
        notifyChange()
    }

    func stop() async {
        hide()
        await titleClient.stop()
    }

    private func resolveTitleIfNeeded(
        for sessionHash: String,
        revision: UInt64
    ) {
        guard titleCache[sessionHash] == nil,
              titleTasks[sessionHash] == nil
        else {
            return
        }
        if let attemptedAt = titleAttemptedAt[sessionHash],
           Date().timeIntervalSince(attemptedAt) < 10
        {
            return
        }

        titleAttemptedAt[sessionHash] = Date()
        titleTasks[sessionHash] = Task { [weak self, titleClient] in
            let title = try? await titleClient.fetchThreadDisplayName(
                matchingSessionHash: sessionHash
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                self.titleTasks[sessionHash] = nil
                guard let index = self.taskIndex(for: sessionHash) else {
                    return
                }
                if let title {
                    self.titleCache[sessionHash] = title
                    self.tasks[index].resolvedThreadTitle = title
                }
                if (self.revisions[sessionHash] ?? 0) >= revision {
                    self.notifyChange()
                }
            }
        }
    }

    private func scheduleInactivityCycle(
        sessionHash: String,
        revision: UInt64
    ) {
        inactivityTasks[sessionHash] = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(
                    nanoseconds: compactDelayNanoseconds
                )
                guard !Task.isCancelled,
                      self.revisions[sessionHash] == revision,
                      let index = self.taskIndex(for: sessionHash)
                else {
                    return
                }
                self.tasks[index].presentation = .compact
                self.recomputePresentationAndNotify()

                try await Task.sleep(
                    nanoseconds: hiddenDelayNanoseconds
                )
                guard !Task.isCancelled,
                      self.revisions[sessionHash] == revision
                else {
                    return
                }
                self.removeTask(sessionHash: sessionHash)
            } catch {
                return
            }
        }
    }

    private func taskIndex(for sessionHash: String) -> Int? {
        tasks.firstIndex { $0.sessionHash == sessionHash }
    }

    private func choosePrimaryTask() {
        if let focusedSessionHash,
           tasks.contains(where: { $0.sessionHash == focusedSessionHash })
        {
            primarySessionHash = focusedSessionHash
            return
        }

        if keepsFocusedPrimary,
           let primarySessionHash,
           tasks.contains(where: { $0.sessionHash == primarySessionHash })
        {
            return
        }

        let current = primarySessionHash.flatMap { sessionHash in
            tasks.first { $0.sessionHash == sessionHash }
        }
        let candidate = tasks.max { lhs, rhs in
            let lhsPriority = Self.automaticPriority(lhs.snapshot.state)
            let rhsPriority = Self.automaticPriority(rhs.snapshot.state)
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }
            return lhs.snapshot.occurredAt < rhs.snapshot.occurredAt
        }

        guard let candidate else {
            primarySessionHash = nil
            return
        }

        guard let current else {
            primarySessionHash = candidate.sessionHash
            return
        }

        let currentPriority = Self.automaticPriority(current.snapshot.state)
        let candidatePriority = Self.automaticPriority(
            candidate.snapshot.state
        )
        if candidatePriority > currentPriority {
            primarySessionHash = candidate.sessionHash
        } else if candidatePriority == currentPriority,
                  candidate.snapshot.occurredAt
                    > current.snapshot.occurredAt
        {
            primarySessionHash = candidate.sessionHash
        }
    }

    private func removeTask(sessionHash: String) {
        inactivityTasks[sessionHash]?.cancel()
        inactivityTasks[sessionHash] = nil
        titleTasks[sessionHash]?.cancel()
        titleTasks[sessionHash] = nil
        titleCache.removeValue(forKey: sessionHash)
        titleAttemptedAt.removeValue(forKey: sessionHash)
        tasks.removeAll { $0.sessionHash == sessionHash }

        if focusedSessionHash == sessionHash {
            focusedSessionHash = nil
            keepsFocusedPrimary = false
        }
        if primarySessionHash == sessionHash {
            primarySessionHash = nil
        }
        choosePrimaryTask()
        recomputePresentationAndNotify()
    }

    private func recomputePresentationAndNotify() {
        if tasks.isEmpty {
            presentation = .hidden
            manuallyExpanded = false
        } else if manuallyExpanded
                    || tasks.contains(where: {
                        $0.presentation == .expanded
                    })
        {
            presentation = .expanded
        } else {
            presentation = .compact
        }
        notifyChange()
    }

    private nonisolated static func automaticPriority(
        _ state: CodexActivityVisualState
    ) -> Int {
        switch state {
        case .awaitingConfirmation: 5
        case .error: 4
        case .thinking, .working, .compactingContext: 3
        case .completed: 2
        case .standby, .unavailable, .disconnectedCodex: 1
        }
    }

    private func notifyChange() {
        stateDidChange?()
    }
}

@MainActor
final class CodexActivityRuntime: ObservableObject {
    @Published private(set) var connectionStatus:
        CodexActivityConnectionStatus = .notInstalled
    @Published private(set) var bridgeStatus:
        CodexActivityBridgeStatus = .stopped
    @Published private(set) var hooksFeatureStatus:
        CodexHooksFeatureStatus = .checking
    @Published private(set) var codexVersion: String?
    @Published private(set) var isConfiguring = false
    @Published private(set) var isOpeningSecurityReview = false
    @Published private(set) var focusTrackingStatus:
        CodexActivityFocusTrackingStatus = .disabled

    let store: CodexActivityStore

    private let preferences: AppPreferences
    private let defaults: UserDefaults
    private let bridge: CodexActivityUnixBridge
    private let fileBridge: CodexActivityFileBridge
    private let installer: CodexActivityHookInstaller
    private let environmentInspector: CodexActivityEnvironmentInspector
    private let securityReviewLauncher: CodexSecurityReviewLauncher
    private let focusedTaskTitleReader = CodexFocusedTaskTitleReader()
    private var island: CodexActivityIslandPanelController?
    private var preferenceCancellable: AnyCancellable?
    private var accessibilityCancellable: AnyCancellable?
    private var workspaceCancellables: Set<AnyCancellable> = []
    private var setupTask: Task<Void, Never>?
    private var securityReviewObservationTask: Task<Void, Never>?
    private var focusPollingTask: Task<Void, Never>?
    private var setupIslandRequested = false

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
        defaults: UserDefaults = .standard
    ) {
        self.preferences = preferences
        self.defaults = defaults
        store = CodexActivityStore()

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
        let installer = CodexActivityHookInstaller(
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
        environmentInspector = CodexActivityEnvironmentInspector()
        securityReviewLauncher = CodexSecurityReviewLauncher(
            codexExecutablePath: environmentInspector.executablePath
        )

        store.stateDidChange = { [weak self] in
            self?.render()
            self?.synchronizeFocusTracking()
        }
        preferenceCancellable = preferences.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.render()
                    self?.synchronizeFocusTracking()
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
    }

    func start() {
        let handler: (CodexActivityEvent) -> Void = { [weak self] activity in
            Task { @MainActor in
                self?.receive(activity)
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
        synchronizeFocusTracking()
        reconcileOnLaunch()
    }

    func setFollowCurrentTaskEnabled(_ enabled: Bool) {
        preferences.followCurrentCodexTask = enabled
        if enabled {
            _ = focusedTaskTitleReader.requestAccess()
        }
        synchronizeFocusTracking()
    }

    func enableCodexActivity() {
        setupIslandRequested = true
        render()
        configure(previouslyEnabledOnly: false)
    }

    func openCodexSecurityReview() {
        guard !isConfiguring, !isOpeningSecurityReview else { return }
        securityReviewObservationTask?.cancel()
        isOpeningSecurityReview = true
        setupIslandRequested = true
        render()

        let launcher = securityReviewLauncher
        let baselineProcessIdentifier =
            Self.runningCodexProcessIdentifier().map(Int.init) ?? 0
        Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                Result { try launcher.prepareLauncher() }
            }.value
            guard let self, !Task.isCancelled else { return }

            switch result {
            case .success(let launcherURL):
                guard NSWorkspace.shared.open(launcherURL) else {
                    isOpeningSecurityReview = false
                    connectionStatus = .abnormal(
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
                connectionStatus = .awaitingTrust
                isOpeningSecurityReview = false
                observeSecurityReviewCompletion()
                render()
            case .failure(let error):
                isOpeningSecurityReview = false
                connectionStatus = .abnormal(
                    error.localizedDescription
                )
                render()
            }
        }
    }

    func disableCodexActivity() {
        guard !isConfiguring else { return }
        isConfiguring = true
        setupTask?.cancel()
        securityReviewObservationTask?.cancel()
        let installer = installer
        setupTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                Result { try installer.uninstall() }
            }.value
            guard let self, !Task.isCancelled else { return }
            isConfiguring = false
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
                connectionStatus = .notInstalled
                store.hide()
                island?.hide()
            case .failure(let error):
                connectionStatus = .abnormal(
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
            connectionStatus = .abnormal(
                localizedSetupMessage(
                    chinese: "找不到可以重新启动的 Codex 应用。",
                    english:
                        "QuotaView could not find the Codex application."
                )
            )
            render()
            return
        }

        isConfiguring = true
        setupIslandRequested = true
        render()

        Task { [weak self] in
            guard let self else { return }
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
                for _ in 0..<40 where !runningApplication.isTerminated {
                    try? await Task.sleep(
                        nanoseconds: 250_000_000
                    )
                }
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
                    self?.finishCodexRestart(
                        errorMessage: error?.localizedDescription
                    )
                }
            }
        }
    }

    func refreshConnectionStatus() {
        guard !isConfiguring else { return }
        inspectEnvironmentAndInstallation()
    }

    func stop() async {
        setupTask?.cancel()
        securityReviewObservationTask?.cancel()
        focusPollingTask?.cancel()
        focusPollingTask = nil
        bridge.stop()
        fileBridge.stop()
        bridgeStatus = .stopped
        await store.stop()
        island?.hide()
    }

    var diagnosticLogPath: String {
        CodexActivityDiagnostics.logURL.path
    }

    private func reconcileOnLaunch() {
        let installer = installer
        let optedIn = defaults.bool(forKey: DefaultsKey.setupEnabled)
        Task { [weak self] in
            let shouldReconcile = await Task.detached(priority: .utility) {
                let hasExistingHandler =
                    (try? installer.hasQuotaViewHandlers()) ?? false
                return optedIn || hasExistingHandler
            }.value
            guard let self, !Task.isCancelled else { return }
            if shouldReconcile {
                configure(previouslyEnabledOnly: true)
            } else {
                inspectEnvironmentAndInstallation()
            }
        }
    }

    private func configure(previouslyEnabledOnly: Bool) {
        guard !isConfiguring else { return }
        isConfiguring = true
        hooksFeatureStatus = .checking
        setupTask?.cancel()

        let inspector = environmentInspector
        let installer = installer
        setupTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                Result {
                    if previouslyEnabledOnly {
                        let hasExistingHandler =
                            try installer.hasQuotaViewHandlers()
                        guard hasExistingHandler else {
                            return CodexActivitySetupResult.notInstalled
                        }
                    }

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

            guard let self, !Task.isCancelled else { return }
            isConfiguring = false
            switch result {
            case .success(.notInstalled):
                defaults.set(false, forKey: DefaultsKey.setupEnabled)
                setupIslandRequested = false
                connectionStatus = .notInstalled
                render()
                inspectEnvironmentAndInstallation()
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
                if !previouslyEnabledOnly,
                   connectionStatus != .connected
                {
                    openCodexSecurityReview()
                }
            case .failure(let error):
                hooksFeatureStatus = .unavailable
                connectionStatus = .abnormal(
                    error.localizedDescription
                )
                render()
            }
        }
    }

    private func inspectEnvironmentAndInstallation() {
        setupTask?.cancel()
        hooksFeatureStatus = .checking
        let inspector = environmentInspector
        let installer = installer
        setupTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                Result {
                    let environment = try inspector.inspect()
                    let installed = try installer.isInstalled()
                    return (environment, installed)
                }
            }.value
            guard let self, !Task.isCancelled else { return }
            switch result {
            case .success(let (environment, installed)):
                codexVersion = environment.version
                hooksFeatureStatus = environment.hooksEnabled
                    ? .enabled
                    : .disabled
                if installed {
                    defaults.set(true, forKey: DefaultsKey.setupEnabled)
                    updateConnectionStatusFromInstalledState()
                } else {
                    connectionStatus = .notInstalled
                    setupIslandRequested = false
                    render()
                }
            case .failure(let error):
                hooksFeatureStatus = .unavailable
                if defaults.bool(forKey: DefaultsKey.setupEnabled) {
                    connectionStatus = .abnormal(
                        error.localizedDescription
                    )
                } else {
                    connectionStatus = .notInstalled
                }
                render()
            }
        }
    }

    private func receive(_ activity: CodexActivityEvent) {
        if defaults.bool(forKey: DefaultsKey.setupEnabled) {
            guard canAcceptActivityAfterRequiredRestart() else {
                render()
                return
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
            if connectionStatus == .connected {
                setupIslandRequested = false
            }
        }
        store.receive(activity)
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
            connectionStatus = .abnormal(message)
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
                    connectionStatus =
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
        connectionStatus = CodexActivitySetupStatusResolver.resolve(
            evidenceStatus: evidenceStatus,
            reviewConfirmed: reviewConfirmed,
            requiresRestart: false
        )
        if connectionStatus == .connected {
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
                        self.connectionStatus = .abnormal(
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
        isConfiguring = false
        if let errorMessage {
            connectionStatus = .abnormal(errorMessage)
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
        if shouldRenderDisconnectedIsland {
            renderDisconnectedIsland()
            return
        }

        guard let primaryTask = store.primaryTask,
              store.presentation != .hidden,
              !store.tasks.isEmpty
        else {
            island?.hide()
            return
        }

        let copy = CodexActivityCopy(
            language: preferences.resolvedLanguage
        )
        let renderTasks = store.tasks.map { task in
            let title = task.resolvedThreadTitle
                ?? task.snapshot.workspaceName.map { "Codex · \($0)" }
                ?? "Codex"
            let statusTitle = copy.statusTitle(
                for: task.snapshot.state
            )
            let operation = copy.operation(
                for: task.snapshot.operationKey
            )
            return CodexActivityRenderState(
                sessionHash: task.sessionHash,
                visualState: task.snapshot.state,
                windowTitle: title,
                statusTitle: statusTitle,
                operation: operation,
                accessibilityLabel: copy.accessibilityLabel(
                    windowTitle: title,
                    statusTitle: statusTitle,
                    operation: operation
                )
            )
        }
        let primarySessionHash = primaryTask.sessionHash
        let primaryIndex = renderTasks.firstIndex {
            $0.sessionHash == primarySessionHash
        } ?? 0
        let railStart = codexActivityRailWindowStart(
            tasks: renderTasks,
            primarySessionHash: primarySessionHash
        )
        let hiddenBefore = railStart
        let hiddenAfter = max(
            0,
            renderTasks.count
                - railStart
                - CodexActivityTaskRailMetrics.visibleRowCount
        )
        let cluster = CodexActivityClusterRenderState(
            tasks: renderTasks,
            primarySessionHash: primarySessionHash,
            taskRailTitle: copy.taskRailTitle,
            taskCounterText: copy.taskCounterText(
                current: primaryIndex + 1,
                total: renderTasks.count
            ),
            overflowText: copy.taskOverflowText(
                hiddenBefore: hiddenBefore,
                hiddenAfter: hiddenAfter
            ),
            compactCountText: copy.compactTaskCountText(
                renderTasks.count
            ),
            accessibilityLabel: copy.clusterAccessibilityLabel(
                taskCount: renderTasks.count,
                primaryTitle: renderTasks[primaryIndex].windowTitle,
                attentionCount: renderTasks.filter {
                    $0.visualState == .awaitingConfirmation
                        || $0.visualState == .error
                }.count
            ),
            compactExpandLabel: copy.expandTaskDetailsLabel,
            compactExpandHelp: copy.expandTaskDetailsHelp
        )
        let presentation: CodexActivityIslandPresentation =
            store.presentation == .compact ? .compact : .expanded

        if island == nil {
            island = CodexActivityIslandPanelController(
                initialCluster: cluster,
                onExpandRequested: { [weak store] in
                    store?.expandCompactDetail()
                }
            )
        }
        island?.update(
            cluster: cluster,
            presentationMode: presentation,
            presentationAccessibilityValue:
                copy.presentationAccessibilityValue(presentation),
            reduceMotion:
                NSWorkspace.shared
                .accessibilityDisplayShouldReduceMotion
        )
    }

    private func synchronizeFocusTracking() {
        guard preferences.followCurrentCodexTask else {
            focusPollingTask?.cancel()
            focusPollingTask = nil
            focusTrackingStatus = .disabled
            store.releaseFocusedTask()
            return
        }

        guard focusedTaskTitleReader.isTrusted else {
            if focusTrackingStatus == .permissionRequired,
               focusPollingTask != nil {
                return
            }
            focusPollingTask?.cancel()
            focusTrackingStatus = .permissionRequired
            store.releaseFocusedTask()
            focusPollingTask = Task { [weak self] in
                while let self, !Task.isCancelled {
                    if self.focusedTaskTitleReader.isTrusted {
                        self.focusPollingTask = nil
                        self.synchronizeFocusTracking()
                        return
                    }
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
            return
        }

        focusTrackingStatus = .tracking
        guard focusPollingTask == nil else { return }
        focusPollingTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.resolveFocusedCodexTaskIfNeeded()
                try? await Task.sleep(nanoseconds: 650_000_000)
            }
        }
    }

    private func resolveFocusedCodexTaskIfNeeded() async {
        guard preferences.followCurrentCodexTask else { return }
        guard focusedTaskTitleReader.isTrusted else {
            synchronizeFocusTracking()
            return
        }
        guard store.tasks.count > 1,
              let application = NSWorkspace.shared.frontmostApplication,
              application.bundleIdentifier == "com.openai.codex"
        else {
            return
        }

        let knownTitles = store.resolvedTaskTitles
        guard !knownTitles.isEmpty else { return }
        let processIdentifier = application.processIdentifier
        let reader = focusedTaskTitleReader
        let title = await Task.detached(priority: .utility) {
            reader.currentTaskTitle(
                processIdentifier: processIdentifier,
                matching: knownTitles
            )
        }.value
        guard let title, !Task.isCancelled else { return }
        store.focusTask(matchingResolvedTitle: title)
    }

    private var shouldRenderDisconnectedIsland: Bool {
        guard connectionStatus != .connected else { return false }
        return setupIslandRequested
            || defaults.bool(forKey: DefaultsKey.setupEnabled)
    }

    private func renderDisconnectedIsland() {
        let copy = CodexActivityCopy(
            language: preferences.resolvedLanguage
        )
        let statusTitle = copy.statusTitle(
            for: .disconnectedCodex
        )
        let operation = copy.disconnectedOperation(
            for: connectionStatus,
            isConfiguring: isConfiguring || isOpeningSecurityReview
        )
        let renderState = CodexActivityRenderState(
            sessionHash: "quotaview-connection",
            visualState: .disconnectedCodex,
            windowTitle: "QuotaView",
            statusTitle: statusTitle,
            operation: operation,
            accessibilityLabel: copy.accessibilityLabel(
                windowTitle: "QuotaView",
                statusTitle: statusTitle,
                operation: operation
            )
        )
        let cluster = CodexActivityClusterRenderState(
            tasks: [renderState],
            primarySessionHash: renderState.sessionHash,
            taskRailTitle: copy.taskRailTitle,
            taskCounterText: copy.taskCounterText(
                current: 1,
                total: 1
            ),
            overflowText: "",
            compactCountText: copy.compactTaskCountText(1),
            accessibilityLabel: renderState.accessibilityLabel,
            compactExpandLabel: copy.expandTaskDetailsLabel,
            compactExpandHelp: copy.expandTaskDetailsHelp
        )

        if island == nil {
            island = CodexActivityIslandPanelController(
                initialCluster: cluster,
                onExpandRequested: { [weak store] in
                    store?.expandCompactDetail()
                }
            )
        }
        island?.update(
            cluster: cluster,
            presentationMode: .expanded,
            presentationAccessibilityValue:
                copy.presentationAccessibilityValue(.expanded),
            reduceMotion:
                NSWorkspace.shared
                .accessibilityDisplayShouldReduceMotion
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

private struct CodexActivityCopy {
    let language: AppPreferences.Language

    func statusTitle(for state: CodexActivityVisualState) -> String {
        switch (language, state) {
        case (.simplifiedChinese, .disconnectedCodex):
            "未连接 Codex"
        case (.simplifiedChinese, .standby): "空闲"
        case (.simplifiedChinese, .thinking): "思考中"
        case (.simplifiedChinese, .working): "工作中"
        case (.simplifiedChinese, .compactingContext):
            "正在压缩上下文"
        case (.simplifiedChinese, .awaitingConfirmation): "待确认"
        case (.simplifiedChinese, .completed): "已完成"
        case (.simplifiedChinese, .error): "失败"
        case (.simplifiedChinese, .unavailable): "未载入"
        case (.english, .disconnectedCodex): "Codex Not Connected"
        case (.english, .standby): "Idle"
        case (.english, .thinking): "Thinking"
        case (.english, .working): "Working"
        case (.english, .compactingContext): "Compacting Context"
        case (.english, .awaitingConfirmation): "Awaiting Confirmation"
        case (.english, .completed): "Completed"
        case (.english, .error): "Failed"
        case (.english, .unavailable): "Not Loaded"
        }
    }

    func disconnectedOperation(
        for status: CodexActivityConnectionStatus,
        isConfiguring: Bool
    ) -> String {
        if isConfiguring {
            return switch language {
            case .simplifiedChinese:
                "正在准备 Codex 灵动岛连接"
            case .english:
                "Preparing the Codex island connection"
            }
        }

        return switch (language, status) {
        case (.simplifiedChinese, .notInstalled):
            "在 QuotaView 设置中连接 Codex 灵动岛"
        case (.simplifiedChinese, .installedNeedsRestart):
            "完成安全确认后重新启动 Codex"
        case (.simplifiedChinese, .awaitingTrust):
            "请在打开的 Codex 窗口完成安全确认"
        case (.simplifiedChinese, .awaitingFirstEvent):
            "向 Codex 发送一条新消息以完成连接"
        case (.simplifiedChinese, .connected):
            "Codex 灵动岛连接已激活"
        case (.simplifiedChinese, .abnormal):
            "连接遇到问题，请返回 QuotaView 设置"
        case (.english, .notInstalled):
            "Connect the Codex island in QuotaView Settings"
        case (.english, .installedNeedsRestart):
            "Restart Codex after completing the security review"
        case (.english, .awaitingTrust):
            "Complete the security review in the opened Codex window"
        case (.english, .awaitingFirstEvent):
            "Send a new Codex message to finish connecting"
        case (.english, .connected):
            "Codex activity is active"
        case (.english, .abnormal):
            "Connection needs attention in QuotaView Settings"
        }
    }

    func operation(for key: CodexActivityOperationKey) -> String {
        switch (language, key) {
        case (.simplifiedChinese, .connectingSession):
            "正在连接 Codex 会话"
        case (.simplifiedChinese, .sessionEnded):
            "Codex 会话已结束"
        case (.simplifiedChinese, .analyzingRequest):
            "正在分析新的任务"
        case (.simplifiedChinese, .executingShell):
            "正在执行终端操作"
        case (.simplifiedChinese, .editingFiles):
            "正在修改项目文件"
        case (.simplifiedChinese, .callingExternalTool):
            "正在调用外部工具"
        case (.simplifiedChinese, .coordinatingSubagent):
            "正在协调子任务"
        case (.simplifiedChinese, .usingLocalTool):
            "正在执行本地工具"
        case (.simplifiedChinese, .usingTool):
            "正在执行工具操作"
        case (.simplifiedChinese, .awaitingApproval):
            "有一项操作需要你的批准"
        case (.simplifiedChinese, .reviewingToolResult):
            "正在检查工具执行结果"
        case (.simplifiedChinese, .compactingContext):
            "正在整理较早消息以释放上下文空间"
        case (.simplifiedChinese, .continuingAfterCompaction):
            "上下文整理完成，正在继续任务"
        case (.simplifiedChinese, .subagentStarted):
            "子任务已启动"
        case (.simplifiedChinese, .subagentStopped):
            "正在汇总子任务结果"
        case (.simplifiedChinese, .turnCompleted):
            "当前任务已完成"
        case (.simplifiedChinese, .bridgeUnavailable):
            "Codex 灵动岛连接不可用"
        case (.simplifiedChinese, .malformedEvent):
            "收到无法识别的 Codex 状态事件"
        case (.english, .connectingSession):
            "Connecting to the Codex session"
        case (.english, .sessionEnded):
            "The Codex session ended"
        case (.english, .analyzingRequest):
            "Analyzing the new task"
        case (.english, .executingShell):
            "Running a terminal operation"
        case (.english, .editingFiles):
            "Editing project files"
        case (.english, .callingExternalTool):
            "Calling an external tool"
        case (.english, .coordinatingSubagent):
            "Coordinating a subtask"
        case (.english, .usingLocalTool):
            "Running a local tool"
        case (.english, .usingTool):
            "Running a tool"
        case (.english, .awaitingApproval):
            "An operation needs your approval"
        case (.english, .reviewingToolResult):
            "Reviewing the tool result"
        case (.english, .compactingContext):
            "Condensing earlier messages to free context"
        case (.english, .continuingAfterCompaction):
            "Context compacted; continuing the task"
        case (.english, .subagentStarted):
            "A subtask started"
        case (.english, .subagentStopped):
            "Summarizing subtask results"
        case (.english, .turnCompleted):
            "The current task is complete"
        case (.english, .bridgeUnavailable):
            "The Codex island connection is unavailable"
        case (.english, .malformedEvent):
            "Received an unrecognized Codex status event"
        }
    }

    func accessibilityLabel(
        windowTitle: String,
        statusTitle: String,
        operation: String
    ) -> String {
        switch language {
        case .simplifiedChinese:
            "\(windowTitle)，状态：\(statusTitle)，"
                + "当前操作：\(operation)"
        case .english:
            "\(windowTitle), status: \(statusTitle), "
                + "current operation: \(operation)"
        }
    }

    var taskRailTitle: String {
        switch language {
        case .simplifiedChinese: "任务"
        case .english: "Tasks"
        }
    }

    func taskCounterText(current: Int, total: Int) -> String {
        "\(current)/\(total)"
    }

    func taskOverflowText(
        hiddenBefore: Int,
        hiddenAfter: Int
    ) -> String {
        switch language {
        case .simplifiedChinese:
            switch (hiddenBefore, hiddenAfter) {
            case (0, 0): ""
            case (0, _): "后 \(hiddenAfter)"
            case (_, 0): "前 \(hiddenBefore)"
            default: "前 \(hiddenBefore) · 后 \(hiddenAfter)"
            }
        case .english:
            switch (hiddenBefore, hiddenAfter) {
            case (0, 0): ""
            case (0, _): "\(hiddenAfter) after"
            case (_, 0): "\(hiddenBefore) before"
            default: "\(hiddenBefore) before · \(hiddenAfter) after"
            }
        }
    }

    func compactTaskCountText(_ count: Int) -> String {
        switch language {
        case .simplifiedChinese: "共 \(count) 项"
        case .english: "\(count) Tasks"
        }
    }

    func clusterAccessibilityLabel(
        taskCount: Int,
        primaryTitle: String,
        attentionCount: Int
    ) -> String {
        switch language {
        case .simplifiedChinese:
            return "共 \(taskCount) 个任务，当前任务：\(primaryTitle)"
                + (attentionCount > 0
                    ? "，\(attentionCount) 个任务需要注意"
                    : "")
        case .english:
            return "\(taskCount) tasks, current task: \(primaryTitle)"
                + (attentionCount > 0
                    ? ", \(attentionCount) need attention"
                    : "")
        }
    }

    var expandTaskDetailsLabel: String {
        switch language {
        case .simplifiedChinese: "展开任务详情"
        case .english: "Expand Task Details"
        }
    }

    var expandTaskDetailsHelp: String {
        switch language {
        case .simplifiedChinese: "将紧凑态灵动岛展开为多任务详情。"
        case .english:
            "Expands the compact island to show multitask details."
        }
    }

    func presentationAccessibilityValue(
        _ presentation: CodexActivityIslandPresentation
    ) -> String {
        switch (language, presentation) {
        case (.simplifiedChinese, .expanded): "展开"
        case (.simplifiedChinese, .compact): "紧凑"
        case (.english, .expanded): "Expanded"
        case (.english, .compact): "Compact"
        }
    }
}

private final class CodexActivityUnixBridge {
    enum BridgeError: LocalizedError {
        case socketCreationFailed
        case socketPathTooLong
        case bindFailed
        case listenFailed

        var errorDescription: String? {
            switch self {
            case .socketCreationFailed:
                "无法创建 Codex 灵动岛监听端口。"
            case .socketPathTooLong:
                "Codex 灵动岛监听路径过长。"
            case .bindFailed:
                "无法绑定 Codex 灵动岛监听端口。"
            case .listenFailed:
                "无法启动 Codex 灵动岛监听。"
            }
        }
    }

    private let socketURL: URL
    private let authenticationToken: String
    private let installationIdentifier: String
    private let queue = DispatchQueue(
        label: "com.duoasa.QuotaView.codex-activity-bridge",
        qos: .utility
    )
    private var source: DispatchSourceRead?
    private var descriptor: Int32 = -1
    private var handler: ((CodexActivityEvent) -> Void)?

    init(
        socketURL: URL,
        authenticationToken: String,
        installationIdentifier: String
    ) {
        self.socketURL = socketURL
        self.authenticationToken = authenticationToken
        self.installationIdentifier = installationIdentifier
    }

    func start(
        handler: @escaping (CodexActivityEvent) -> Void
    ) throws {
        stop()
        self.handler = handler

        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: socketURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        unlink(socketURL.path)

        let pathBytes = Array(socketURL.path.utf8CString)
        var address = sockaddr_un()
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path)
        else {
            throw BridgeError.socketPathTooLong
        }

        let listener = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0 else {
            throw BridgeError.socketCreationFailed
        }
        descriptor = listener

        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            destination.initializeMemory(as: UInt8.self, repeating: 0)
            pathBytes.withUnsafeBytes { source in
                destination.copyBytes(from: source)
            }
        }

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(
                to: sockaddr.self,
                capacity: 1
            ) { socketAddress in
                Darwin.bind(
                    listener,
                    socketAddress,
                    socklen_t(MemoryLayout<sockaddr_un>.size)
                )
            }
        }
        guard bindResult == 0 else {
            Darwin.close(listener)
            descriptor = -1
            throw BridgeError.bindFailed
        }

        chmod(socketURL.path, S_IRUSR | S_IWUSR)
        guard Darwin.listen(listener, 16) == 0 else {
            Darwin.close(listener)
            descriptor = -1
            unlink(socketURL.path)
            throw BridgeError.listenFailed
        }

        let flags = fcntl(listener, F_GETFL)
        _ = fcntl(listener, F_SETFL, flags | O_NONBLOCK)

        let source = DispatchSource.makeReadSource(
            fileDescriptor: listener,
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.acceptAvailableConnections()
        }
        self.source = source
        source.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
        if descriptor >= 0 {
            Darwin.close(descriptor)
            descriptor = -1
        }
        unlink(socketURL.path)
        handler = nil
    }

    private func acceptAvailableConnections() {
        guard descriptor >= 0 else { return }
        while true {
            let connection = Darwin.accept(descriptor, nil, nil)
            guard connection >= 0 else { return }
            read(connection: connection)
        }
    }

    private func read(connection: Int32) {
        defer { Darwin.close(connection) }
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(
            connection,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &timeout,
            socklen_t(MemoryLayout<timeval>.size)
        )
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8_192)

        while data.count <= 65_536 {
            let count = Darwin.recv(
                connection,
                &buffer,
                buffer.count,
                0
            )
            guard count > 0 else { break }
            data.append(buffer, count: count)

            if let envelope = try? JSONDecoder().decode(
                CodexActivityBridgeEnvelope.self,
                from: data
            ) {
                guard authenticationTokensMatch(
                    envelope.authenticationToken,
                    authenticationToken
                ),
                authenticationTokensMatch(
                    envelope.installationIdentifier,
                    installationIdentifier
                )
                else {
                    return
                }
                handler?(envelope.activity)
                return
            }
        }
    }
}

final class CodexActivityFileBridge {
    enum BridgeError: LocalizedError {
        case queueCreationFailed
        case unsafeQueueDirectory
        case queueWatchFailed

        var errorDescription: String? {
            switch self {
            case .queueCreationFailed:
                "无法创建 Codex 灵动岛事件队列。"
            case .unsafeQueueDirectory:
                "Codex 灵动岛事件队列的权限不安全。"
            case .queueWatchFailed:
                "无法监听 Codex 灵动岛事件队列。"
            }
        }
    }

    private static let maximumPayloadBytes = 65_536
    private static let maximumQueuedFiles = 128
    private static let staleEventAge: TimeInterval = 300

    private let queueURL: URL
    private let authenticationToken: String
    private let installationIdentifier: String
    private let queue = DispatchQueue(
        label: "com.duoasa.QuotaView.codex-activity-file-bridge",
        qos: .utility
    )
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: Int32 = -1
    private var handler: ((CodexActivityEvent) -> Void)?

    init(
        queueURL: URL,
        authenticationToken: String,
        installationIdentifier: String
    ) {
        self.queueURL = queueURL
        self.authenticationToken = authenticationToken
        self.installationIdentifier = installationIdentifier
    }

    func start(
        handler: @escaping (CodexActivityEvent) -> Void
    ) throws {
        stop()
        try prepareQueueDirectory()
        self.handler = handler

        let directoryDescriptor = Darwin.open(
            queueURL.path,
            O_EVTONLY | O_CLOEXEC
        )
        guard directoryDescriptor >= 0 else {
            self.handler = nil
            throw BridgeError.queueWatchFailed
        }
        descriptor = directoryDescriptor

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: directoryDescriptor,
            eventMask: [.write, .extend],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.drainAvailableEvents()
        }
        self.source = source
        source.resume()
        queue.async { [weak self] in
            self?.drainAvailableEvents()
        }
    }

    func stop() {
        source?.cancel()
        source = nil
        if descriptor >= 0 {
            Darwin.close(descriptor)
            descriptor = -1
        }
        handler = nil
    }

    private func prepareQueueDirectory() throws {
        let path = queueURL.path
        var metadata = stat()
        if lstat(path, &metadata) == 0 {
            guard metadata.st_uid == getuid(),
                  metadata.st_mode & S_IFMT == S_IFDIR
            else {
                throw BridgeError.unsafeQueueDirectory
            }
        } else {
            guard mkdir(path, S_IRWXU) == 0 else {
                throw BridgeError.queueCreationFailed
            }
        }

        guard chmod(path, S_IRWXU) == 0,
              lstat(path, &metadata) == 0,
              metadata.st_uid == getuid(),
              metadata.st_mode & S_IFMT == S_IFDIR,
              metadata.st_mode & (S_IRWXG | S_IRWXO) == 0
        else {
            throw BridgeError.unsafeQueueDirectory
        }
    }

    private func drainAvailableEvents() {
        let fileManager = FileManager.default
        guard let urls = try? fileManager.contentsOfDirectory(
            at: queueURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let eventURLs = urls
            .filter {
                $0.pathExtension == "json"
                    && $0.lastPathComponent.hasPrefix("event-")
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var events: [CodexActivityEvent] = []
        for url in eventURLs.prefix(Self.maximumQueuedFiles) {
            defer { unlink(url.path) }
            guard let data = readPayload(at: url),
                  let envelope = try? JSONDecoder().decode(
                      CodexActivityBridgeEnvelope.self,
                      from: data
                  ),
                  authenticationTokensMatch(
                      envelope.authenticationToken,
                      authenticationToken
                  ),
                  authenticationTokensMatch(
                      envelope.installationIdentifier,
                      installationIdentifier
                  ),
                  abs(envelope.activity.occurredAt.timeIntervalSinceNow)
                    <= Self.staleEventAge
            else {
                continue
            }
            events.append(envelope.activity)
        }

        for url in eventURLs.dropFirst(Self.maximumQueuedFiles) {
            unlink(url.path)
        }

        events.sort { $0.occurredAt < $1.occurredAt }
        for event in events {
            handler?(event)
        }
    }

    private func readPayload(at url: URL) -> Data? {
        let fileDescriptor = Darwin.open(
            url.path,
            O_RDONLY | O_NOFOLLOW | O_CLOEXEC
        )
        guard fileDescriptor >= 0 else { return nil }
        defer { Darwin.close(fileDescriptor) }

        var metadata = stat()
        guard fstat(fileDescriptor, &metadata) == 0,
              metadata.st_uid == getuid(),
              metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_size > 0,
              metadata.st_size <= Self.maximumPayloadBytes
        else {
            return nil
        }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8_192)
        while data.count <= Self.maximumPayloadBytes {
            let count = Darwin.read(
                fileDescriptor,
                &buffer,
                min(
                    buffer.count,
                    Self.maximumPayloadBytes + 1 - data.count
                )
            )
            guard count >= 0 else { return nil }
            guard count > 0 else { return data }
            data.append(buffer, count: count)
        }
        return nil
    }
}

private func authenticationTokensMatch(
    _ received: String,
    _ expected: String
) -> Bool {
    let receivedBytes = Array(received.utf8)
    let expectedBytes = Array(expected.utf8)
    guard receivedBytes.count == expectedBytes.count else {
        return false
    }
    var difference: UInt8 = 0
    for index in receivedBytes.indices {
        difference |= receivedBytes[index] ^ expectedBytes[index]
    }
    return difference == 0
}

private enum CodexActivitySetupResult {
    case notInstalled
    case installed(
        environment: CodexActivityEnvironmentInspection,
        hookDefinitionChanged: Bool
    )
}

struct CodexActivityConnectionEvidence: Equatable {
    var observedInstallationID: String?
    var connectedInstallationID: String?

    mutating func record(
        event: CodexActivityHookEvent,
        installationID: String
    ) {
        observedInstallationID = installationID
        if event == .userPromptSubmit {
            connectedInstallationID = installationID
        }
    }

    func status(
        for installationID: String
    ) -> CodexActivityConnectionStatus {
        if connectedInstallationID == installationID {
            return .connected
        }
        if observedInstallationID == installationID {
            return .awaitingFirstEvent
        }
        return .awaitingTrust
    }
}

struct CodexActivityRestartRequirement: Equatable {
    let baselineProcessIdentifier: Int

    func isSatisfied(
        currentProcessIdentifier: pid_t?
    ) -> Bool {
        guard let currentProcessIdentifier else { return false }
        return Int(currentProcessIdentifier)
            != baselineProcessIdentifier
    }
}

struct CodexActivitySetupStatusResolver {
    static func resolve(
        evidenceStatus: CodexActivityConnectionStatus,
        reviewConfirmed: Bool,
        requiresRestart: Bool
    ) -> CodexActivityConnectionStatus {
        if requiresRestart {
            return reviewConfirmed
                ? .installedNeedsRestart
                : .awaitingTrust
        }
        if evidenceStatus == .awaitingTrust, reviewConfirmed {
            return .awaitingFirstEvent
        }
        return evidenceStatus
    }
}

struct CodexActivityEnvironmentInspection: Sendable {
    let version: String
    let hooksEnabled: Bool
    let didEnableHooks: Bool
}

struct CodexActivityEnvironmentInspector: Sendable {
    enum InspectionError: LocalizedError {
        case codexUnavailable
        case commandFailed(String)
        case commandTimedOut
        case hooksFeatureUnavailable

        var errorDescription: String? {
            switch self {
            case .codexUnavailable:
                "找不到支持 Hooks 的 Codex 安装。"
            case .commandFailed(let message):
                "检测 Codex 环境失败：\(message)"
            case .commandTimedOut:
                "检测 Codex 环境超时。"
            case .hooksFeatureUnavailable:
                "当前 Codex 版本未提供 Hooks 功能。"
            }
        }
    }

    private struct CommandResult {
        let standardOutput: String
        let standardError: String
    }

    let executablePath: String?
    let timeout: TimeInterval

    init(
        executablePath: String? = CodexExecutableLocator.locate(),
        timeout: TimeInterval = 8
    ) {
        self.executablePath = executablePath
        self.timeout = max(timeout, 1)
    }

    func inspect() throws -> CodexActivityEnvironmentInspection {
        guard let executablePath else {
            throw InspectionError.codexUnavailable
        }
        let versionResult = try run(
            executablePath: executablePath,
            arguments: ["--version"]
        )
        let version = versionResult.standardOutput
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !version.isEmpty else {
            throw InspectionError.commandFailed(
                versionResult.standardError
            )
        }

        let featureResult = try run(
            executablePath: executablePath,
            arguments: ["features", "list"]
        )
        guard let hooksEnabled = Self.hooksEnabled(
            in: featureResult.standardOutput
        ) else {
            throw InspectionError.hooksFeatureUnavailable
        }
        return CodexActivityEnvironmentInspection(
            version: version,
            hooksEnabled: hooksEnabled,
            didEnableHooks: false
        )
    }

    func inspectAndEnableHooksIfNeeded()
        throws -> CodexActivityEnvironmentInspection
    {
        let current = try inspect()
        guard !current.hooksEnabled else { return current }
        guard let executablePath else {
            throw InspectionError.codexUnavailable
        }

        _ = try run(
            executablePath: executablePath,
            arguments: ["features", "enable", "hooks"]
        )
        let updated = try inspect()
        guard updated.hooksEnabled else {
            throw InspectionError.hooksFeatureUnavailable
        }
        return CodexActivityEnvironmentInspection(
            version: updated.version,
            hooksEnabled: true,
            didEnableHooks: true
        )
    }

    private func run(
        executablePath: String,
        arguments: [String]
    ) throws -> CommandResult {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = standardOutput
        process.standardError = standardError

        do {
            try process.run()
        } catch {
            throw InspectionError.commandFailed(
                error.localizedDescription
            )
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        guard !process.isRunning else {
            process.terminate()
            process.waitUntilExit()
            throw InspectionError.commandTimedOut
        }

        let outputData = standardOutput.fileHandleForReading
            .readDataToEndOfFile()
        let errorData = standardError.fileHandleForReading
            .readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let error = String(data: errorData, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            let message = error
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw InspectionError.commandFailed(
                message.isEmpty ? "exit \(process.terminationStatus)" : message
            )
        }
        return CommandResult(
            standardOutput: output,
            standardError: error
        )
    }

    private static func hooksEnabled(in output: String) -> Bool? {
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.first == "hooks" else { continue }
            if fields.last == "true" { return true }
            if fields.last == "false" { return false }
        }
        return nil
    }
}

struct CodexSecurityReviewLauncher: Sendable {
    enum LaunchError: LocalizedError {
        case codexUnavailable
        case expectUnavailable
        case couldNotPrepareLauncher
        case couldNotOpenTerminal

        var errorDescription: String? {
            switch self {
            case .codexUnavailable:
                "找不到可用于安全确认的 Codex CLI。"
            case .expectUnavailable:
                "当前系统缺少打开 Codex 安全确认所需的终端组件。"
            case .couldNotPrepareLauncher:
                "无法准备 Codex 安全确认窗口。"
            case .couldNotOpenTerminal:
                "无法打开 Codex 安全确认窗口。"
            }
        }
    }

    let codexExecutablePath: String?
    let launcherDirectoryURL: URL
    let reviewCompletionURL: URL

    init(
        codexExecutablePath: String?,
        launcherDirectoryURL: URL? = nil,
        reviewCompletionURL: URL? = nil
    ) {
        self.codexExecutablePath = codexExecutablePath
        let resolvedLauncherDirectoryURL: URL
        if let launcherDirectoryURL {
            resolvedLauncherDirectoryURL = launcherDirectoryURL
        } else {
            resolvedLauncherDirectoryURL = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
                .appendingPathComponent("QuotaView", isDirectory: true)
                .appendingPathComponent("Launchers", isDirectory: true)
        }
        self.launcherDirectoryURL = resolvedLauncherDirectoryURL
        self.reviewCompletionURL = reviewCompletionURL
            ?? resolvedLauncherDirectoryURL.appendingPathComponent(
                "QuotaViewHookReviewComplete"
            )
    }

    func prepareLauncher() throws -> URL {
        guard let codexExecutablePath,
              FileManager.default.isExecutableFile(
                atPath: codexExecutablePath
              )
        else {
            throw LaunchError.codexUnavailable
        }
        guard FileManager.default.isExecutableFile(
            atPath: "/usr/bin/expect"
        ) else {
            throw LaunchError.expectUnavailable
        }

        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(
                at: launcherDirectoryURL,
                withIntermediateDirectories: true
            )
            chmod(launcherDirectoryURL.path, S_IRWXU)

            let expectURL = launcherDirectoryURL
                .appendingPathComponent("QuotaViewHookReview.exp")
            let launcherURL = launcherDirectoryURL
                .appendingPathComponent("Open Codex Security Review.command")
            if fileManager.fileExists(
                atPath: reviewCompletionURL.path
            ) {
                try fileManager.removeItem(at: reviewCompletionURL)
            }
            let expectScript = """
            #!/usr/bin/expect -f
            set timeout 180
            set codex_path [lindex $argv 0]
            set completion_path [lindex $argv 1]
            proc write_result {path value} {
                set result_file [open $path w]
                puts $result_file $value
                close $result_file
                file attributes $path -permissions 0600
            }
            spawn -noecho $codex_path
            expect {
                -re {›} {
                }
                timeout {
                    write_result $completion_path "failed:prompt-timeout"
                    puts stderr "Timed out waiting for the Codex prompt."
                    exit 124
                }
                eof {
                    catch wait result
                    exit [lindex $result 3]
                }
            }

            set setup_deadline [expr {[clock milliseconds] + 240000}]
            set review_ready 0
            for {set attempt 0} {$attempt < 6 && !$review_ready} {incr attempt} {
                set quiet_deadline [expr {[clock milliseconds] + 3000}]
                while {[clock milliseconds] < $setup_deadline} {
                    set timeout 1
                    expect {
                        -re {.+} {
                            set quiet_deadline [expr {[clock milliseconds] + 3000}]
                        }
                        timeout {
                        }
                        eof {
                            catch wait result
                            exit [lindex $result 3]
                        }
                    }
                    if {[clock milliseconds] >= $quiet_deadline} {
                        break
                    }
                }

                send -- "/hooks\\r"
                set timeout 15
                expect {
                    -re {Press t to trust all} {
                        set review_ready 1
                    }
                    -re {Press enter to view hooks} {
                        write_result $completion_path "confirmed"
                        close
                        catch wait
                        exit 0
                    }
                    timeout {
                    }
                    eof {
                        catch wait result
                        exit [lindex $result 3]
                    }
                }
            }
            if {!$review_ready} {
                write_result $completion_path "failed:review-timeout"
                puts stderr "Timed out opening the Codex hook review."
                exit 125
            }

            interact {
                -re {[tT]} {
                    send -- $interact_out(0,string)
                    set timeout 30
                    expect {
                        -re {Press enter to view hooks} {
                            write_result $completion_path "confirmed"
                            close
                            catch wait
                            exit 0
                        }
                        timeout {
                            write_result $completion_path "failed:trust-not-confirmed"
                            puts stderr "Codex did not confirm hook trust."
                            exit 126
                        }
                        eof {
                            catch wait result
                            exit [lindex $result 3]
                        }
                    }
                }
            }
            """
            let launcherScript = """
            #!/bin/zsh
            exec /usr/bin/expect \
            \(Self.shellQuote(expectURL.path)) \
            \(Self.shellQuote(codexExecutablePath)) \
            \(Self.shellQuote(reviewCompletionURL.path))
            """

            try Data(expectScript.utf8).write(
                to: expectURL,
                options: .atomic
            )
            try Data(launcherScript.utf8).write(
                to: launcherURL,
                options: .atomic
            )
            chmod(expectURL.path, S_IRUSR | S_IWUSR | S_IXUSR)
            chmod(launcherURL.path, S_IRUSR | S_IWUSR | S_IXUSR)
            return launcherURL
        } catch {
            throw LaunchError.couldNotPrepareLauncher
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(
            of: "'",
            with: "'\\''"
        ) + "'"
    }
}

enum CodexActivityDiagnostics {
    static var logURL: URL {
        URL(
            fileURLWithPath:
                "/tmp/com.quotaview.codex-activity-\(getuid())",
            isDirectory: true
        )
        .appendingPathComponent("diagnostics.log")
    }
}

struct CodexActivityHookInstaller: Sendable {
    enum InstallationError: LocalizedError {
        case helperUnavailable
        case invalidHooksFile
        case helperInstallationFailed

        var errorDescription: String? {
            switch self {
            case .helperUnavailable:
                "当前 QuotaView 构建中缺少活动 Hook 辅助程序。"
            case .invalidHooksFile:
                "现有 Codex hooks.json 不是有效的 JSON 对象。"
            case .helperInstallationFailed:
                "无法将 Codex 灵动岛 Helper 安装到固定路径。"
            }
        }
    }

    struct InstallationResult: Sendable {
        let hookDefinitionChanged: Bool
    }

    private static let commandMarker = "QuotaViewActivityHook"
    private static let eventNames = CodexActivityHookEvent.allCases
        .map(\.rawValue)

    let socketURL: URL
    let authenticationToken: String
    let hooksURL: URL
    let bundledHelperURL: URL
    let installedHelperURL: URL

    init(
        socketURL: URL,
        authenticationToken: String,
        hooksURL: URL? = nil,
        helperURL: URL? = nil,
        installedHelperURL: URL? = nil
    ) {
        self.socketURL = socketURL
        self.authenticationToken = authenticationToken
        self.hooksURL = hooksURL
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex", isDirectory: true)
                .appendingPathComponent("hooks.json")
        self.bundledHelperURL = helperURL
            ?? Bundle.main.bundleURL
                .appendingPathComponent("Contents/Helpers")
                .appendingPathComponent(Self.commandMarker)
        if let installedHelperURL {
            self.installedHelperURL = installedHelperURL
        } else if hooksURL != nil || helperURL != nil {
            self.installedHelperURL = self.bundledHelperURL
        } else {
            self.installedHelperURL = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
                .appendingPathComponent("QuotaView", isDirectory: true)
                .appendingPathComponent("Helpers", isDirectory: true)
                .appendingPathComponent(Self.commandMarker)
        }
    }

    var installationIdentifier: String {
        CodexActivityPrivacy.hashIdentifier(baseHookCommand())
    }

    func isInstalled() throws -> Bool {
        guard FileManager.default.fileExists(atPath: hooksURL.path) else {
            return false
        }
        let root = try readRoot()
        let hooks = try readHooks(from: root)
        let expectedCommand = hookCommand()
        return Self.eventNames.allSatisfy { eventName in
            guard let groups = hooks[eventName] as? [[String: Any]]
            else {
                return false
            }
            return groups.contains { group in
                handlers(in: group).contains {
                    command(in: $0) == expectedCommand
                }
            }
        }
    }

    func hasQuotaViewHandlers() throws -> Bool {
        guard FileManager.default.fileExists(atPath: hooksURL.path) else {
            return false
        }
        let hooks = try readHooks(from: readRoot())
        return hooks.values.contains { value in
            guard let groups = value as? [[String: Any]] else {
                return false
            }
            return groups.contains { group in
                handlers(in: group).contains {
                    command(in: $0).contains(Self.commandMarker)
                }
            }
        }
    }

    func install() throws -> InstallationResult {
        guard FileManager.default.isExecutableFile(
            atPath: bundledHelperURL.path
        )
        else {
            throw InstallationError.helperUnavailable
        }

        let hookDefinitionChanged = try !isInstalled()
        try installHelper()

        var root = try readRoot(allowMissing: true)
        var hooks = try readHooks(from: root)
        hooks = removingQuotaViewHandlers(from: hooks)

        let command = hookCommand()

        for eventName in Self.eventNames {
            var groups = hooks[eventName] as? [[String: Any]] ?? []
            let timeout = eventName == HookEventName.sessionEnd ? 1 : 2
            groups.append([
                "hooks": [[
                    "type": "command",
                    "command": command,
                    "timeout": timeout
                ]]
            ])
            hooks[eventName] = groups
        }

        root["hooks"] = hooks
        try writeRoot(root)
        return InstallationResult(
            hookDefinitionChanged: hookDefinitionChanged
        )
    }

    func uninstall() throws {
        if FileManager.default.fileExists(atPath: hooksURL.path) {
            var root = try readRoot()
            let hooks = try readHooks(from: root)
            root["hooks"] = removingQuotaViewHandlers(from: hooks)
            try writeRoot(root)
        }
        if installedHelperURL != bundledHelperURL,
           FileManager.default.fileExists(atPath: installedHelperURL.path)
        {
            try FileManager.default.removeItem(at: installedHelperURL)
        }
    }

    private func readRoot(
        allowMissing: Bool = false
    ) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: hooksURL.path) else {
            if allowMissing {
                return [
                    "description":
                        "User-level Codex hooks, including QuotaView activity."
                ]
            }
            return [:]
        }

        let data = try Data(contentsOf: hooksURL)
        guard let object = try JSONSerialization.jsonObject(with: data)
            as? [String: Any]
        else {
            throw InstallationError.invalidHooksFile
        }
        return object
    }

    private func readHooks(
        from root: [String: Any]
    ) throws -> [String: Any] {
        guard let value = root["hooks"] else {
            return [:]
        }
        guard let hooks = value as? [String: Any] else {
            throw InstallationError.invalidHooksFile
        }

        for value in hooks.values {
            guard let groups = value as? [[String: Any]] else {
                throw InstallationError.invalidHooksFile
            }
            for group in groups {
                guard group["hooks"] as? [[String: Any]] != nil else {
                    throw InstallationError.invalidHooksFile
                }
            }
        }
        return hooks
    }

    private func writeRoot(_ root: [String: Any]) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: hooksURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if fileManager.fileExists(atPath: hooksURL.path) {
            let backupURL = hooksURL.appendingPathExtension(
                "quotaview-backup"
            )
            if !fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.copyItem(at: hooksURL, to: backupURL)
            }
        }

        let data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: hooksURL, options: .atomic)
        chmod(hooksURL.path, S_IRUSR | S_IWUSR)
    }

    private func installHelper() throws {
        if bundledHelperURL == installedHelperURL {
            guard FileManager.default.isExecutableFile(
                atPath: installedHelperURL.path
            ) else {
                throw InstallationError.helperInstallationFailed
            }
            return
        }

        let fileManager = FileManager.default
        let directoryURL = installedHelperURL
            .deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        chmod(directoryURL.path, S_IRWXU)

        let temporaryURL = directoryURL.appendingPathComponent(
            ".\(Self.commandMarker)-\(UUID().uuidString)",
            isDirectory: false
        )
        do {
            try fileManager.copyItem(
                at: bundledHelperURL,
                to: temporaryURL
            )
            chmod(temporaryURL.path, S_IRWXU)
            if fileManager.fileExists(atPath: installedHelperURL.path) {
                _ = try fileManager.replaceItemAt(
                    installedHelperURL,
                    withItemAt: temporaryURL
                )
            } else {
                try fileManager.moveItem(
                    at: temporaryURL,
                    to: installedHelperURL
                )
            }
            chmod(installedHelperURL.path, S_IRWXU)
            guard fileManager.isExecutableFile(
                atPath: installedHelperURL.path
            ) else {
                throw InstallationError.helperInstallationFailed
            }
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            if error is InstallationError {
                throw error
            }
            throw InstallationError.helperInstallationFailed
        }
    }

    private func removingQuotaViewHandlers(
        from hooks: [String: Any]
    ) -> [String: Any] {
        var result = hooks
        for (eventName, value) in hooks {
            guard let groups = value as? [[String: Any]] else {
                continue
            }

            let cleanedGroups = groups.compactMap { group -> [String: Any]? in
                let remaining = handlers(in: group).filter {
                    !command(in: $0).contains(Self.commandMarker)
                }
                guard !remaining.isEmpty else { return nil }
                var updated = group
                updated["hooks"] = remaining
                return updated
            }
            result[eventName] = cleanedGroups
        }
        return result
    }

    private func handlers(
        in group: [String: Any]
    ) -> [[String: Any]] {
        group["hooks"] as? [[String: Any]] ?? []
    }

    private func command(in handler: [String: Any]) -> String {
        handler["command"] as? String ?? ""
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func hookCommand() -> String {
        [
            baseHookCommand(),
            "--installation-id",
            shellQuote(installationIdentifier)
        ].joined(separator: " ")
    }

    private func baseHookCommand() -> String {
        [
            shellQuote(installedHelperURL.path),
            "--socket",
            shellQuote(socketURL.path),
            "--token",
            shellQuote(authenticationToken)
        ].joined(separator: " ")
    }

    private enum HookEventName {
        static let sessionEnd = "SessionEnd"
    }
}
