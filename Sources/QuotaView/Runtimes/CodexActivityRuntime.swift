import AppKit
import Combine
import Darwin
import Foundation
import QuotaViewCore

enum CodexAnswerLaunchState: Equatable {
    case idle, requested, waitingForQuit, opening, opened(pid_t), failed

    // This desktop always adds a local plugin override. Its native daemon
    // preference requires an empty override list, even when a daemon is ready.
    static func ignoresDaemonPreference(version: String?, build: String?) -> Bool {
        version == "26.1117.41037" && build == "29803"
    }

    /// A status refresh may finish an explicit request exactly once.
    mutating func claimLaunch(eligible: Bool, desktopRunning: Bool) -> Bool {
        guard self == .requested || self == .waitingForQuit else { return false }
        guard eligible else { self = .idle; return false }
        if desktopRunning { self = .waitingForQuit; return false }
        self = .opening
        return true
    }
}

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
    private var decisionBridge: ClaudeCodeBridge?
    private var permissionRequests: [String: IslandCodexApprovalRequest] = [:]
    private var sharedQuestionRefreshTask: Task<Void, Never>?
    private var nativeCardScan: Task<Void, Never>?
    private var sharedQuestionRefreshID: UUID?
    private var lastSharedQuestionRefresh = Date.distantPast
    private var fileBridge: CodexActivityFileBridge
    private var installer: CodexActivityHookInstaller
    private var environmentInspector: CodexActivityEnvironmentInspector
    private let authenticationToken: String
    private let automaticHookSetupEnabled: Bool
    private let usesInjectedEnvironmentInspector: Bool
    // Configuration trust is established only by Codex native metadata. A
    // delivery proves receipt, but cannot reinstate revoked configuration trust.
    private var nativeHookTrusted = false
    @Published private(set) var answerLaunchState: CodexAnswerLaunchState = .idle
    @Published private(set) var desktopIgnoresDaemonPreference = false
    private var answerLaunchTask: Task<Void, Never>?
    var canConfigureSharedAnswers: Bool {
        isRunning && preferences.codexIntegrationEnabled && nativeHookTrusted
            && hasCompatibilityHook && compatibilityHookAdmissionEnabled && !isChangingDataDirectory
            && !liveIsland.model.usesLegacyDesktopAnswers
    }

    func requestSharedAnswers() {
        guard canConfigureSharedAnswers, !desktopIgnoresDaemonPreference, hookOperation == .idle else { return }
        answerLaunchState = .requested
        reconcileHook(install: false)
    }

    func cancelAnswerLaunch() {
        answerLaunchTask?.cancel()
        answerLaunchTask = nil
        answerLaunchState = .idle
    }

    /// Called only after fresh native Hook inspection. Ordinary status checks can
    /// finish an explicit pending request but never create one.
    private func continueAnswerLaunch() {
        guard answerLaunchState == .requested || answerLaunchState == .waitingForQuit else { return }
        let bundleID = "com.openai.codex"
        func codexIsRunning() -> Bool {
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains { !$0.isTerminated }
        }
        guard answerLaunchState.claimLaunch(eligible: canConfigureSharedAnswers && !desktopIgnoresDaemonPreference, desktopRunning: codexIsRunning()) else { return }
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              Bundle(url: app)?.bundleIdentifier == bundleID else { answerLaunchState = .failed; return }
        let cli = app.appendingPathComponent("Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex")
        let root = dataDirectoryURL
        let inspector = CodexActivityEnvironmentInspector(executablePath: cli.path, dataDirectoryURL: root)
        answerLaunchTask = Task { [weak self] in
            do {
                try Task.checkCancellation()
                let prepare = Task.detached(priority: .utility) { try inspector.prepareSharedAnswerService() }
                try await withTaskCancellationHandler { try await prepare.value } onCancel: { prepare.cancel() }
                guard let self, !Task.isCancelled else { return }
                guard canConfigureSharedAnswers, dataDirectoryURL == root else { cancelAnswerLaunch(); return }
                // If the user has opened another desktop in the meantime,
                // keep that process intact and allow an explicit retry.
                guard !codexIsRunning() else { answerLaunchState = .failed; return }
                let config = NSWorkspace.OpenConfiguration()
                config.environment = ["CODEX_APP_SERVER_USE_LOCAL_DAEMON": "1", "CODEX_HOME": root.path]
                let launched = try await NSWorkspace.shared.openApplication(at: app, configuration: config)
                guard !Task.isCancelled else { return }
                guard !launched.isTerminated else { answerLaunchState = .failed; return }
                answerLaunchState = .opened(launched.processIdentifier)
                try await Task.sleep(nanoseconds: 40_000_000_000)
                if answerLaunchState == .opened(launched.processIdentifier),
                   automaticConnection.sharedState != .connected { answerLaunchState = .failed }
            } catch {
                if !Task.isCancelled { self?.answerLaunchState = .failed }
            }
        }
    }

    private var currentRunDeliveredInstallation: String?
    private var bridgeRunStartedAt = Date()
    private var configurationClient: CodexAppServerClient?
    let liveIsland = IslandSession()
    private(set) lazy var claudeCode = ClaudeCodeRuntime(preferences: preferences, island: liveIsland, defaults: defaults)
    private(set) lazy var agentQuotas = AgentQuotaStore(preferences: preferences, defaults: defaults, island: liveIsland)
    private(set) lazy var dsh = NativeAgentRuntime(provider: .dsh, preferences: preferences, island: liveIsland, defaults: defaults)
    private(set) lazy var kimiCode = NativeAgentRuntime(provider: .kimiCode, preferences: preferences, island: liveIsland, defaults: defaults)
    private(set) lazy var cursor = NativeAgentRuntime(provider: .cursor, preferences: preferences, island: liveIsland, defaults: defaults)
    private(set) lazy var geminiCLI = NativeAgentRuntime(provider: .geminiCLI, preferences: preferences, island: liveIsland, defaults: defaults)
    private(set) lazy var openCode = NativeAgentRuntime(provider: .openCode, preferences: preferences, island: liveIsland, defaults: defaults)
    private(set) lazy var antigravity = NativeAgentRuntime(provider: .antigravity, preferences: preferences, island: liveIsland, defaults: defaults)
    private(set) lazy var copilotCLI = NativeAgentRuntime(provider: .copilotCLI, preferences: preferences, island: liveIsland, defaults: defaults)
    private(set) lazy var devinDesktop = NativeAgentRuntime(provider: .devinDesktop, preferences: preferences, island: liveIsland, defaults: defaults)
    private(set) lazy var devinCLI = NativeAgentRuntime(provider: .devinCLI, preferences: preferences, island: liveIsland, defaults: defaults)

    private var preferenceCancellable: AnyCancellable?
    private var observationTask: Task<Void, Never>?
    private var desktopIPCClient: CodexDesktopIPCClient
    private var desktopObservationTask: Task<Void, Never>?
    private var desktopRunGeneration: UInt64 = 0
    private var desktopFollowedThreads: Set<String> = []
    private var desktopDiagnosticStates: [String: String] = [:]
    private enum DesktopFollowSource: Hashable { case localRollout, shared }
    private var desktopFollowSources: [String: Set<DesktopFollowSource>] = [:]
    private var observationsEnabled = false
    private var accessibilityCancellable: AnyCancellable?
    private var quotaStatusCancellable: AnyCancellable?
    @Published private(set) var islandUsage: IslandUsagePresentation = .loading
    private weak var integrationQuotaStore: CodexStatusStore?
    var hookExplicitlyDisabled: Bool { defaults.object(forKey: DefaultsKey.automaticHook) as? Bool == false }
    func refreshIntegrationQuota() {
        guard preferences.codexIntegrationEnabled, !preferences.codexIslandPrivacy else { return }
        Task { await integrationQuotaStore?.refresh() }
    }
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
        self.desktopIPCClient = desktopIPCClient ?? CodexDesktopIPCClient(configuration: .live(
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
        store.localPublicContentDidReceive = { [weak self] content in
            self?.liveIsland.model.receiveLocalContent(content)
            self?.refreshSharedQuestionsIfNeeded()
            self?.refreshNativeQuestionInput()
        }
        store.threadMetadataDidReceive = { [weak self] identity, metadata in
            self?.liveIsland.model.receiveThreadMetadata(metadata, identity: identity)
        }
        store.subagentIdentityDidReceive = { [weak self] identity in self?.liveIsland.model.receiveSubagentIdentity(identity) }
        store.subagentActivityDidReceive = { [weak self] event in self?.liveIsland.model.receiveSubagentActivity(event) }
        store.subagentPublicContentDidReceive = { [weak self] content in self?.liveIsland.model.receiveLocalContent(content) }
        store.subagentPublicMessageDidReceive = { [weak self] data in self?.liveIsland.model.receiveSubagentPublicMessage(data) }
        store.subagentSourceUnavailable = { [weak self] source in self?.liveIsland.model.receiveSubagentSourceUnavailable(source) }
        store.subagentObservationDidWithdraw = { [weak self] session in self?.liveIsland.model.withdrawSubagentObservation(for: session) }
        store.localThreadActivityDidReceive = { [weak self] identity, active in
            if active { self?.followDesktopThread(identity.threadID, source: .localRollout) }
            else { self?.withdrawDesktopFollow(identity.threadID, source: .localRollout) }
        }
        store.publicMessageDidReceive = { [weak self] data in
            self?.liveIsland.model.receive(data)
            self?.followDesktopThread(in: data)
        }
        store.desktopProjectionDidReceive = { [weak self] projection, snapshot in
            guard let self, isRunning, !isChangingDataDirectory,
                  desktopFollowedThreads.contains(snapshot.conversationID) else { return }
            liveIsland.model.receiveDesktopProjection(projection, snapshot: snapshot)
        }
        liveIsland.model.responseCapability = { [weak self] wire in
            guard let self else { return false }
            if wire.isCodexPermissionHook { return self.canAnswerPermissionHook(wire) }
            if wire.sharedQuestionHandle != nil {
                return canConfigureSharedAnswers && !preferences.codexIslandPrivacy
                    && !isChangingDataDirectory && !liveIsland.model.usesLegacyDesktopAnswers
                    && automaticConnection.sharedState == .connected
            }
            if wire.nativeQuestionCard != nil { return canUseNativeQuestionInput }
            guard isRunning, preferences.codexIntegrationEnabled, !isChangingDataDirectory, let handle = wire.desktopHandle else { return false }
            return handle.conversationID == wire.threadID && handle.turnID == wire.turnID
        }
        liveIsland.model.respond = { [weak self] wire, result in
            guard let self else { throw CodexDesktopIPCError.staleRequest }
            if wire.isCodexPermissionHook {
                try self.answerPermissionHook(wire, result: result)
                return
            }
            if let handle = wire.sharedQuestionHandle {
                guard canConfigureSharedAnswers, !preferences.codexIslandPrivacy,
                      !isChangingDataDirectory, !liveIsland.model.usesLegacyDesktopAnswers,
                      automaticConnection.sharedState == .connected, wire.permits(result) else {
                    throw CodexDesktopIPCError.staleRequest
                }
                let answers = wire.questions.map { result["answers"][$0.id]["answers"].array.first?.text ?? "" }
                try await store.submitSharedQuestion(handle: handle, answers: answers)
                return
            }
            if let card = wire.nativeQuestionCard {
                guard canUseNativeQuestionInput, wire.permits(result), let q = wire.questions.first,
                      let answer = result["answers"][q.id]["answers"].array.first?.text else { throw CodexDesktopIPCError.staleRequest }
                let home = dataDirectoryURL, run = desktopRunGeneration
                try await CodexDesktopQuestionInput.submit(card, answer: answer, home: home) { [weak self] in
                    guard let self, canUseNativeQuestionInput, dataDirectoryURL == home, desktopRunGeneration == run else { return false }
                    return liveIsland.model.isSubmittingNativeQuestion(card)
                }
                return
            }
            guard isRunning, preferences.codexIntegrationEnabled, !isChangingDataDirectory, let handle = wire.desktopHandle else {
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
        store.hookExecutionDidRebind = { [weak self] session, turn in
            self?.liveIsland.model.withdrawHookExecution(session: session, turn: turn)
        }
        store.activitySessionKindDidResolve = { [weak self] key, kind in
            self?.liveIsland.model.setSessionKind(kind, for: key)
        }
        store.activityExecutionKindDidResolve = { [weak self] key, kind in
            self?.liveIsland.model.receiveExecutionSessionKind(kind, session: key)
        }
        store.cumulativeTokensDidReceive = { [weak self] update in self?.liveIsland.model.receiveToken(update) }
        store.stateDidChange = { [weak self] in
            self?.render()
        }
        store.automaticConnectionDidChange = { [weak self] state in
            self?.handleAutomaticConnection(state)
        }
        integrationQuotaStore = quotaStatusStore
        if let quotaStatusStore {
            liveIsland.board.state.resetController = quotaStatusStore.resetController
            liveIsland.board.state.onRefreshUsage = { [weak self, weak quotaStatusStore] in
                if let self, liveIsland.board.state.effectiveUsageProvider == .antigravity {
                    await antigravity.refreshAntigravityAccount(manual: true)
                    await antigravity.refreshAntigravityUsage()
                } else if let self, liveIsland.board.state.effectiveUsageProvider.quotaSource != nil {
                    await agentQuotas.refresh(liveIsland.board.state.effectiveUsageProvider)
                } else { await quotaStatusStore?.refresh() }
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
                if notification.name == NSWorkspace.didTerminateApplicationNotification,
                   self?.answerLaunchState == .opened(application.processIdentifier) {
                    self?.cancelAnswerLaunch()
                }
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

        let socket = installer.socketURL.deletingLastPathComponent().appendingPathComponent("codex-decision.sock")
        let decisions = ClaudeCodeBridge(socketURL: socket, authenticationToken: authenticationToken)
        do {
            try decisions.start(onMessage: { [weak self] message in
                Task { @MainActor in
                    guard let self, self.bridgeRunGeneration == bridgeRun else { return }
                    self.receivePermissionHook(message)
                }
            }, onDisconnect: { [weak self] id in
                Task { @MainActor in
                    guard let self, self.bridgeRunGeneration == bridgeRun else { return }
                    self.removePermissionHook(id)
                }
            })
            decisionBridge = decisions
        } catch { failures.append(error.localizedDescription) }

        bridgeStatus = isListening
            ? .listening
            : .failed(failures.joined(separator: " "))
        reconcileOnLaunch()
        claudeCode.start()
        agentQuotas.start()
        dsh.start(); kimiCode.start(); cursor.start(); geminiCLI.start(); openCode.start(); antigravity.start(); copilotCLI.start(); devinDesktop.start(); devinCLI.start()
    }

    private var permissionHookEnabled: Bool {
        isRunning && !isChangingDataDirectory && preferences.codexIntegrationEnabled
            && !preferences.codexIslandPrivacy && compatibilityHookAdmissionEnabled
            && nativeHookTrusted && hookOperation != .removing
    }

    private func receivePermissionHook(_ message: ClaudeCodeBridgeMessage) {
        guard message.awaitsDecision, let bridge = decisionBridge else { return }
        guard permissionHookEnabled, UUID(uuidString: message.eventID) != nil,
              let payload = (try? JSONSerialization.jsonObject(with: message.payload)) as? [String: Any],
              payload["installation"] as? String == installer.installationIdentifier,
              let session = payload["session"] as? String, let turn = payload["turn"] as? String,
              let command = payload["command"] as? String, !command.isEmpty else {
            bridge.resolve(eventID: message.eventID, decision: nil)
            return
        }
        var params: [String: Any] = ["threadId": session, "turnId": turn, "itemId": message.eventID,
            "codexPermissionHook": true, "command": command, "availableDecisions": ["accept", "decline"]]
        params["cwd"] = payload["cwd"] as? String
        params["reason"] = payload["reason"] as? String
        let envelope: [String: Any] = ["id": "codex-hook:" + message.eventID,
            "method": "item/commandExecution/requestApproval", "params": params]
        guard let data = try? JSONSerialization.data(withJSONObject: envelope),
              let wire = try? IslandCodexApprovalRequest(data: data) else {
            bridge.resolve(eventID: message.eventID, decision: nil)
            return
        }
        permissionRequests[message.eventID] = wire
        if liveIsland.model.observeCodexPermissionHook(wire, callHash: payload["call"] as? String) {
            bridge.admit(eventID: message.eventID)
        } else {
            permissionRequests.removeValue(forKey: message.eventID)
            bridge.resolve(eventID: message.eventID, decision: nil)
        }
    }

    private func canAnswerPermissionHook(_ wire: IslandCodexApprovalRequest) -> Bool {
        guard permissionHookEnabled, let pending = permissionRequests[wire.params["itemId"].text] else { return false }
        return pending.raw == wire.raw
    }

    private func answerPermissionHook(_ wire: IslandCodexApprovalRequest, result: IslandApprovalJSON) throws {
        let id = wire.params["itemId"].text
        guard canAnswerPermissionHook(wire), let bridge = decisionBridge else { throw CodexDesktopIPCError.staleRequest }
        let behavior: String
        switch result["decision"].text {
        case "accept": behavior = "allow"
        case "decline": behavior = "deny"
        default: throw CodexDesktopIPCError.invalidResponse
        }
        bridge.resolve(eventID: id, decision: ["behavior": behavior])
        removePermissionHook(id)
    }

    private func removePermissionHook(_ id: String) {
        guard let wire = permissionRequests.removeValue(forKey: id) else { return }
        liveIsland.model.resolveLocalHookRequest(sessionKey: wire.threadID, rpcID: wire.rpcID)
    }

    private func returnPendingPermissionHooks() {
        for id in Array(permissionRequests.keys) {
            decisionBridge?.resolve(eventID: id, decision: nil)
            removePermissionHook(id)
        }
    }

    private func startDesktopObservation() {
        desktopDiagnosticStates.removeAll()
        sharedQuestionRefreshTask?.cancel(); sharedQuestionRefreshTask = nil; sharedQuestionRefreshID = nil
        liveIsland.model.updateSharedQuestionCapabilities(handles: [])
        desktopRunGeneration &+= 1
        let run = desktopRunGeneration
        let client = desktopIPCClient
        desktopObservationTask?.cancel()
        desktopObservationTask = Task { [weak self] in
            guard let self, isRunning, preferences.codexIntegrationEnabled, desktopRunGeneration == run else { return }
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
            guard isRunning, !isChangingDataDirectory, desktopRunGeneration == run else { return }
            // Directory changes can bootstrap local activity while callbacks
            // are intentionally disabled. Replay only this Store's current,
            // bounded discovery intents after the Desktop observer is ready.
            for identity in store.localDesktopFollowIdentities { followDesktopThread(identity.threadID, source: .localRollout) }
        }
    }

    private func receiveDesktopSnapshot(_ snapshot: CodexDesktopConversationSnapshot, run: UInt64) async {
        guard isRunning, preferences.codexIntegrationEnabled, !isChangingDataDirectory, desktopRunGeneration == run,
              desktopFollowedThreads.contains(snapshot.conversationID) else { return }
        guard await desktopIPCClient.isCurrent(snapshot), isRunning,
              desktopRunGeneration == run, !isChangingDataDirectory,
              desktopFollowedThreads.contains(snapshot.conversationID) else {
            recordDesktopDiagnostic(snapshot.conversationID, outcome: "stale_stream",
                details: "epoch=\(snapshot.connectionEpoch) stream=\(snapshot.streamGeneration) revision=\(snapshot.revision)")
            return
        }
        let projection: CodexDesktopInteractionProjection
        do {
            projection = try snapshot.interactionProjection ?? CodexDesktopRequestProjector.project(
                conversationID: snapshot.conversationID, conversationStateData: snapshot.conversationState)
        } catch {
            recordDesktopDiagnostic(snapshot.conversationID, outcome: "projection_rejected", details: "epoch=\(snapshot.connectionEpoch)")
            return
        }
        let admitted = await store.receiveDesktopProjection(projection, snapshot: snapshot)
        guard isRunning, !isChangingDataDirectory, desktopRunGeneration == run else { return }
        guard desktopFollowedThreads.contains(snapshot.conversationID) else { return }
        let actionable = liveIsland.model.tasks.flatMap(\.requests).filter {
            $0.value.canRespond && $0.value.protocolRequest?.desktopHandle?.conversationID == snapshot.conversationID
        }.count
        let status = ["inProgress", "completed", "interrupted", "failed"].contains(projection.status) ? projection.status : "unknown"
        let wait: String
        switch projection.threadWaitStatus {
        case .running: wait = "running"
        case .unavailable: wait = "unavailable"
        case .waiting(let reason): wait = reason.rawValue
        }
        let session = CodexActivityPrivacy.hashIdentifier(snapshot.conversationID)
        let lifecycle = liveIsland.model.tasks.first { $0.key == session }?
            .requestLifecycle.desktopDiagnosticSummary(at: Date()) ?? "task_absent=true"
        let details = "epoch=\(snapshot.connectionEpoch) stream=\(snapshot.streamGeneration) revision=\(snapshot.revision) status=\(status) source_kind=\(projection.sourceKind.rawValue) authoritative=\(projection.pendingRequestsAreAuthoritative) owner_input=\(snapshot.supportsUntrustedAppInput) handles=\(snapshot.requests.count) actionable=\(actionable) native_wait=\(wait) \(lifecycle)"
        recordDesktopDiagnostic(snapshot.conversationID, outcome: admitted ? "snapshot_admitted" : "snapshot_rejected", details: details)
        if admitted, ["completed", "interrupted", "failed"].contains(projection.status) {
            stopFollowingDesktopThread(snapshot.conversationID)
        }
        render()
    }

    private func receiveDesktopConnection(_ state: CodexDesktopIPCConnectionState, run: UInt64) {
        guard isRunning, desktopRunGeneration == run else { return }
        let connected = state == .connected
        let outcome: String
        switch state {
        case .connecting: outcome = "connecting"
        case .connected: outcome = "connected"
        case .disconnected: outcome = "disconnected"
        }
        CodexActivityDiagnostics.recordDesktop(outcome: outcome)
        store.setDesktopConnection(connected: connected)
        liveIsland.model.setDesktopConnection(connected: connected, epoch: nil)
        render()
    }

    private func receiveDesktopInvalidation(_ invalidation: CodexDesktopIPCInvalidation, run: UInt64) {
        guard isRunning, !isChangingDataDirectory, desktopRunGeneration == run else { return }
        CodexActivityDiagnostics.recordDesktop(outcome: "resource_limit", conversationID: invalidation.conversationID,
            details: "epoch=\(invalidation.connectionEpoch) scope=\(invalidation.conversationID == nil ? "connection" : "conversation") reason=\(invalidation.diagnosticCode)")
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
        followDesktopThread(threadID)
    }

    private func followDesktopThread(_ threadID: String, source: DesktopFollowSource = .shared) {
        guard isRunning, !isChangingDataDirectory, !threadID.isEmpty, threadID.utf8.count <= 1024 else { return }
        guard desktopFollowedThreads.contains(threadID) || desktopFollowedThreads.count < 100 else { return }
        desktopFollowSources[threadID, default: []].insert(source)
        guard !desktopFollowedThreads.contains(threadID) else { return }
        desktopFollowedThreads.insert(threadID)
        let client = desktopIPCClient
        let run = desktopRunGeneration
        Task { [weak self] in
            guard let self, isRunning, !isChangingDataDirectory, desktopRunGeneration == run,
                  desktopFollowedThreads.contains(threadID) else { return }
            do { try await client.follow(conversationID: threadID, hostID: "local") }
            catch {
                guard isRunning, preferences.codexIntegrationEnabled, !isChangingDataDirectory, desktopRunGeneration == run,
                      desktopFollowedThreads.contains(threadID) else { return }
                recordDesktopDiagnostic(threadID, outcome: "follow_pending", details: "reason=\(Self.desktopDiagnosticError(error))")
            }
        }
    }

    private func recordDesktopDiagnostic(_ conversationID: String, outcome: String, details: String) {
        let value = "\(outcome) \(details)"
        guard desktopDiagnosticStates[conversationID] != value else { return }
        if desktopDiagnosticStates.count >= 100, desktopDiagnosticStates[conversationID] == nil,
           let evicted = desktopDiagnosticStates.keys.first { desktopDiagnosticStates.removeValue(forKey: evicted) }
        desktopDiagnosticStates[conversationID] = value
        CodexActivityDiagnostics.recordDesktop(outcome: outcome, conversationID: conversationID, details: details)
    }

    private static func desktopDiagnosticError(_ error: Error) -> String {
        guard let error = error as? CodexDesktopIPCError else { return "unavailable" }
        switch error {
        case .peerMismatch: return "peer_mismatch"
        case .unsupportedProtocol: return "unsupported_protocol"
        case .invalidMessage: return "invalid_message"
        case .resourceLimit: return "resource_limit"
        case .staleRequest: return "stale_request"
        case .alreadySubmitted: return "already_submitted"
        case .invalidResponse: return "invalid_response"
        case .outcomeUnknown: return "outcome_unknown"
        case .rejected: return "owner_rejected"
        case .unavailable: return "unavailable"
        }
    }

    func enableCompatibilityHook() {
        guard hookOperation == .idle, !isChangingDataDirectory else { return }
        answerLaunchState = canUseNativeQuestionInput ? .idle : .requested
        defaults.set(true, forKey: DefaultsKey.automaticHook)
        reconcileHook(install: true)
    }

    /// Consent is scoped to QuotaView's exact user Hook definitions, never trust-all.
    func openCodexSecurityReview() {
        guard hookOperation == .idle, !isChangingDataDirectory else { return }
        answerLaunchState = canUseNativeQuestionInput ? .idle : .requested
        defaults.set(true, forKey: DefaultsKey.automaticHook)
        reconcileHook(install: true, authorize: true)
    }

    func disableCompatibilityHook() {
        guard hookOperation == .idle, !isChangingDataDirectory else { return }
        cancelAnswerLaunch()
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

    private func withdrawDesktopFollow(_ threadID: String, source: DesktopFollowSource) {
        desktopFollowSources[threadID]?.remove(source)
        guard desktopFollowSources[threadID]?.isEmpty != false else { return }
        stopFollowingDesktopThread(threadID)
    }

    private func stopFollowingDesktopThread(_ threadID: String) {
        desktopFollowSources.removeValue(forKey: threadID)
        desktopDiagnosticStates.removeValue(forKey: threadID)
        guard desktopFollowedThreads.remove(threadID) != nil else { return }
        store.cancelDesktopAttachment(conversationID: threadID)
        // Detaching read-only discovery invalidates handles immediately, before
        // awaiting IPC unfollow. Preserve pending content and all wait evidence.
        let key = CodexActivityPrivacy.hashIdentifier(threadID)
        let epochs = Set(liveIsland.model.tasks.first(where: { $0.key == key })?.requests.compactMap {
            $0.value.protocolRequest?.desktopHandle?.connectionEpoch
        } ?? [])
        for epoch in epochs {
            store.invalidateDesktopProjection(conversationID: threadID, epoch: epoch)
            liveIsland.model.invalidateDesktopResponses(conversationID: threadID, epoch: epoch)
        }
        render()
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
        cancelAnswerLaunch()
        isChangingDataDirectory = true
        returnPendingPermissionHooks()
        fileBridge.setDeliveryReady(false)
        directoryTask = Task { [weak self] in
            guard let self else { return }
            // Revoke callbacks and actions before Store resets its admission scope.
            sharedQuestionRefreshTask?.cancel(); sharedQuestionRefreshTask = nil; sharedQuestionRefreshID = nil
            liveIsland.model.updateSharedQuestionCapabilities(handles: [])
            desktopRunGeneration &+= 1
            desktopObservationTask?.cancel(); desktopObservationTask = nil
            desktopFollowedThreads.removeAll(); desktopFollowSources.removeAll()
            store.setDesktopConnection(connected: false)
            liveIsland.model.setDesktopConnection(connected: false, epoch: nil)
            await desktopIPCClient.stop()
            guard !Task.isCancelled else { return }
            liveIsland.model.reset()
            guard await store.changeDataDirectory(target), !Task.isCancelled else {
                if !Task.isCancelled {
                    liveIsland.model.reset()
                    _ = await store.changeDataDirectory(dataDirectoryURL)
                    isChangingDataDirectory = false
                    directorySelectionFailed = true
                    fileBridge.setDeliveryReady(true)
                    if isRunning { startDesktopObservation() }
                }
                return
            }
            desktopIPCClient = CodexDesktopIPCClient(configuration: .live(
                socketURL: target.appendingPathComponent("ipc/ipc.sock")))
            dataDirectoryURL = target
            hookEventGeneration &+= 1
            decisionBridge?.stop(); decisionBridge = nil
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
        cancelAnswerLaunch()
        isRunning = false
        sharedQuestionRefreshTask?.cancel(); sharedQuestionRefreshTask = nil; sharedQuestionRefreshID = nil
        liveIsland.model.updateSharedQuestionCapabilities(handles: [])
        returnPendingPermissionHooks()
        decisionBridge?.stop(); decisionBridge = nil
        agentQuotas.stop()
        claudeCode.stop()
        dsh.stop(); kimiCode.stop(); cursor.stop(); geminiCLI.stop(); openCode.stop(); antigravity.stop(); copilotCLI.stop(); devinDesktop.stop(); devinCLI.stop()
        desktopRunGeneration &+= 1
        desktopObservationTask?.cancel(); desktopObservationTask = nil
        desktopFollowedThreads.removeAll(); desktopFollowSources.removeAll()
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
                let desktop = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex").flatMap(Bundle.init(url:))
                desktopIgnoresDaemonPreference = CodexAnswerLaunchState.ignoresDaemonPreference(
                    version: desktop?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                    build: desktop?.object(forInfoDictionaryKey: "CFBundleVersion") as? String
                )
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
                if state.isTrusted {
                    continueAnswerLaunch()
                } else if answerLaunchState != .requested {
                    cancelAnswerLaunch()
                }
            } catch {
                guard !Task.isCancelled, hookOperationRevision == operation else { await client.stop(); return }
                nativeHookTrusted = false
                hasCompatibilityHook = (try? installer.hasQuotaViewHandlers()) ?? hasCompatibilityHook
                compatibilityHookScope = try? installer.installedScope()
                if case CodexActivityEnvironmentInspector.InspectionError.hooksFeatureDisabled = error {
                    hooksFeatureStatus = .disabled
                } else if hooksFeatureStatus == .checking { hooksFeatureStatus = .unavailable }
                cancelAnswerLaunch()
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
        guard preferences.codexIntegrationEnabled, compatibilityHookAdmissionEnabled,
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

    var canUseNativeQuestionInput: Bool {
        isRunning && preferences.codexIntegrationEnabled && preferences.codexActivityIslandEnabled &&
            !preferences.codexIslandPrivacy && !isChangingDataDirectory &&
            !liveIsland.model.usesLegacyDesktopAnswers && AXIsProcessTrusted()
    }

    private func refreshNativeQuestionInput() {
        guard canUseNativeQuestionInput else {
            liveIsland.model.updateNativeQuestionCards([])
            return
        }
        guard nativeCardScan == nil,
              !liveIsland.model.nativeQuestionTargets(store.localDesktopFollowIdentities).isEmpty else { return }
        nativeCardScan = Task { [weak self] in
            guard let self else { return }
            defer { nativeCardScan = nil }
            while canUseNativeQuestionInput && !Task.isCancelled {
                let targets = liveIsland.model.nativeQuestionTargets(store.localDesktopFollowIdentities)
                guard !targets.isEmpty else { break }
                let home = dataDirectoryURL, generation = desktopRunGeneration
                let cards = await Task.detached(priority: .utility) { CodexDesktopQuestionInput.scan(targets, home: home) }.value
                guard canUseNativeQuestionInput, dataDirectoryURL == home, generation == desktopRunGeneration, !Task.isCancelled else { break }
                liveIsland.model.updateNativeQuestionCards(cards)
                try? await Task.sleep(nanoseconds: 1_200_000_000)
            }
        }
    }

    private func refreshSharedQuestionsIfNeeded() {
        guard canConfigureSharedAnswers, !preferences.codexIslandPrivacy,
              !isChangingDataDirectory, !liveIsland.model.usesLegacyDesktopAnswers,
              automaticConnection.sharedState == .connected else {
            sharedQuestionRefreshTask?.cancel(); sharedQuestionRefreshTask = nil; sharedQuestionRefreshID = nil
            liveIsland.model.updateSharedQuestionCapabilities(handles: [])
            return
        }
        guard sharedQuestionRefreshTask == nil, Date().timeIntervalSince(lastSharedQuestionRefresh) >= 1 else { return }
        let candidates = liveIsland.model.tasks.filter { task in
            !task.terminal && task.requests.contains {
                $0.value.protocolRequest?.localObservation?.asynchronous == true
                    && $0.value.protocolRequest?.sharedQuestionHandle == nil && $0.value.phase.canSubmit
            }
        }.prefix(8).compactMap { task -> (String, String)? in
            guard let turn = task.turnKey,
                  let identity = store.localDesktopFollowIdentities.first(where: {
                      CodexActivityPrivacy.hashIdentifier($0.threadID) == task.key
                  }) else { return nil }
            return (identity.threadID, turn)
        }
        guard !candidates.isEmpty else { return }
        lastSharedQuestionRefresh = Date()
        let run = desktopRunGeneration
        let refreshID = UUID()
        sharedQuestionRefreshID = refreshID
        sharedQuestionRefreshTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if sharedQuestionRefreshID == refreshID {
                    sharedQuestionRefreshTask = nil; sharedQuestionRefreshID = nil
                    if !Task.isCancelled { refreshSharedQuestionsIfNeeded() }
                }
            }
            for (thread, turn) in candidates {
                let handles = (try? await store.sharedQuestionHandles(threadID: thread, turnHash: turn)) ?? []
                guard !Task.isCancelled, isRunning, desktopRunGeneration == run, !isChangingDataDirectory,
                      canConfigureSharedAnswers, !preferences.codexIslandPrivacy,
                      automaticConnection.sharedState == .connected else { return }
                liveIsland.model.updateSharedQuestionCapabilities(threadID: thread, handles: handles)
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    private func render() {
        guard isRunning else { return }
        refreshSharedQuestionsIfNeeded()
        refreshNativeQuestionInput()
        // The primary interface stays available for the application's lifetime.
        // Retired menu-bar/standalone-island visibility preferences do not hide it.
        if !permissionHookEnabled { returnPendingPermissionHooks() }
        let enabled = true
        let observesCodex = preferences.codexIntegrationEnabled
        if !observesCodex, answerLaunchState != .idle { cancelAnswerLaunch() }
        liveIsland.model.setProviderEnabled(.codex, enabled: observesCodex)
        liveIsland.model.setProviderEnabled(.claudeCode, enabled: preferences.claudeCodeEnabled)
        if observationsEnabled != observesCodex {
            observationsEnabled = observesCodex
            let previous = observationTask
            observationTask = Task { [weak self] in
                await previous?.value
                guard let self, isRunning, observationsEnabled == observesCodex else { return }
                if observesCodex {
                    store.startNativeActivityNotifications()
                    startDesktopObservation()
                } else {
                    sharedQuestionRefreshTask?.cancel(); sharedQuestionRefreshTask = nil; sharedQuestionRefreshID = nil
                    liveIsland.model.updateSharedQuestionCapabilities(handles: [])
                    desktopRunGeneration &+= 1
                    desktopObservationTask?.cancel()
                    await desktopIPCClient.stop()
                    await store.stop()
                }
            }
        }
        store.setMultitaskEnabled(enabled)
        liveIsland.model.setConnection(store.automaticConnection.sharedState)
        for entry in store.multitask.entries {
            liveIsland.model.setTitle(store.title(for: entry.snapshot.sessionHash), for: entry.snapshot.sessionHash,
                                      source: store.titleSource(for: entry.snapshot.sessionHash))
        }
        let current = islandUsage.state.isCurrent ? islandUsage.snapshot : nil
        liveIsland.update(english: preferences.resolvedLanguage.usesLatinLayout,
            remaining: current?.remainingPercent, enabled: enabled, privacy: preferences.codexIslandPrivacy,
            weeklyRemaining: current?.weeklyRemainingPercent,
            quotaResetsAt: current?.resetsAt, usageSnapshot: islandUsage.snapshot, usageState: islandUsage.state,
            usageOptions: .init(preferences: preferences), cardOptions: .init(preferences: preferences), progressEffect: preferences.codexActivityProgressEffect,
            automaticPopupEnabled: preferences.codexActivityAutomaticPopupEnabled,
            automaticPopupDuration: preferences.codexActivityAutomaticPopupDuration,
            expandedWidth: preferences.codexIslandExpandedWidth,
            islandMaterial: preferences.islandMaterial,
            islandGlassAppearance: preferences.islandGlassAppearance,
            islandGlassDegree: preferences.islandGlassDegree,
            islandFloatingUsageEnabled: preferences.islandFloatingUsageEnabled,
            backgroundMemorySnapshots: store.backgroundMemorySnapshots,
            followsFocus: preferences.islandFollowsFocus, followsPointer: preferences.islandFollowsPointer, fixedScreenID: preferences.islandFixedScreenID, language: preferences.resolvedLanguage)
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
