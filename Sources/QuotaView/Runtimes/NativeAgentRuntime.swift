import AppKit
import Combine
import Foundation
import QuotaViewCore
#if SWIFT_PACKAGE
import QuotaViewActivityHookSupport
#endif

/// Owns the local listener, configuration and generation for one agent surface.
/// Interactive adapters get the first opportunity to handle a bridge message.
@MainActor
final class NativeAgentRuntime: ObservableObject {
    enum Status: Equatable { case disabled, configuring, waiting, connected, failed }
    @Published private(set) var status: Status = .disabled
    @Published private(set) var failure: NativeAgentInstaller.Failure?
    @Published private(set) var configuredHomes: [URL] = []
    @Published private(set) var additionalHomes: [URL]
    @Published private(set) var directorySelectionFailed = false
    enum AGYInstallation { case missing, installing, installed, failed }
    @Published private(set) var agyInstallation: AGYInstallation = .missing

    func checkAGYInstallation() { antigravity?.checkAGYInstallation() }
    func installAGY() { antigravity?.installAGY() }

    var provider: IslandAgentProvider { context.provider }
    var installer: NativeAgentInstaller { context.installer }
    private var preferences: AppPreferences { context.preferences }
    private var island: IslandSession { context.island }
    private var bridge: ClaudeCodeBridge { context.bridge }
    private let defaults: UserDefaults
    private var observation: AnyCancellable?
    private var configurationTask: Task<Void, Never>?
    private let context: NativeAgentHookContext
    private var approvalRouteEnabled: Bool?
    private var applied: Bool?
    private var interaction: (any NativeHookInteractionAdapter)?
    private var devin: DevinAgentAdapter?
    private var antigravity: AntigravityAgentAdapter?
    private lazy var hook = GenericHookAgentAdapter(context: context, devin: devin, antigravity: antigravity, openCode: openCode, dsh: dsh)

    var devinInteractive: Bool { devin?.interactive == true }
    private var dshInteractive: Bool {
        preferences.dshInteractiveApprovals && preferences.codexActivityIslandEnabled && !preferences.codexIslandPrivacy
    }
    typealias AnswerNativeQuestion = @MainActor (AntigravityDesktopApproval.Card, String, () -> Bool) async -> Bool
    private var openCode: OpenCodeInteractionAdapter?
    private var openCodeInteractive: Bool {
        provider == .openCode && preferences.openCodeInteractionsEnabled &&
            preferences.codexActivityIslandEnabled && !preferences.codexIslandPrivacy
    }
    private var dsh: DSHInteractionAdapter?

    init(provider: IslandAgentProvider, preferences: AppPreferences, island: IslandSession, defaults: UserDefaults, installer suppliedInstaller: NativeAgentInstaller? = nil,
         readApprovalCards: ((Set<UUID>) async -> [UUID: AntigravityDesktopApproval.Card])? = nil,
         pressApprovalButton: @escaping (AntigravityDesktopApproval.Card, Bool) -> Bool = AntigravityDesktopApproval.press,
         answerNativeQuestion: @escaping AnswerNativeQuestion = AntigravityDesktopApproval.answer) {
        self.defaults = defaults
        additionalHomes = (provider == .dsh ? defaults.stringArray(forKey: "integrations.dsh.additionalHomes") ?? [] : []).prefix(32)
            .filter { $0.hasPrefix("/") }.map { URL(fileURLWithPath: $0) }
        let key = "integrations." + provider.rawValue + ".token"
        let token = defaults.string(forKey: key) ?? UUID().uuidString
        defaults.set(token, forKey: key)
        let channel = String(CodexActivityPrivacy.hashIdentifier(ClaudeCodeChannel.identifier).prefix(12))
        let socket = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("qv-\(channel)-\(provider.rawValue)/events.sock")
        let installer = suppliedInstaller ?? NativeAgentInstaller(provider: provider, socketURL: socket, authenticationToken: token)
        let bridge = ClaudeCodeBridge(socketURL: installer.socketURL, authenticationToken: installer.authenticationToken)
        context = NativeAgentHookContext(provider: provider, preferences: preferences, island: island, installer: installer, bridge: bridge)
        if provider.isDevin {
            devin = DevinAgentAdapter(context: context)
            interaction = devin
        }
        if provider == .openCode {
            openCode = OpenCodeInteractionAdapter(model: island.model, bridge: bridge) { [weak self] key in
                guard let self, context.running, context.listening, enabled, openCodeInteractive,
                      let session = context.sessions[key], session.active, session.parent == nil,
                      let turn = session.turn, let nativeTurn = session.nativeTurn, let epoch = session.epoch
                else { return nil }
                return .init(id: turn, nativeID: nativeTurn, epoch: epoch)
            }
            interaction = openCode
        }
        if provider == .antigravity {
            let adapter = AntigravityAgentAdapter(context: context, readsInstalledAccount: suppliedInstaller == nil,
                readApprovalCards: readApprovalCards ?? { ids in
                    guard suppliedInstaller == nil else { return [:] }
                    return await Task.detached(priority: .utility) { AntigravityDesktopApproval.scan(ids) }.value
                }, pressApprovalButton: pressApprovalButton, answerNativeQuestion: answerNativeQuestion)
            adapter.installationChanged = { [weak self] in self?.agyInstallation = $0 }
            adapter.accountAvailabilityChanged = { [weak self] in self?.objectWillChange.send() }
            antigravity = adapter
        }
        if provider == .dsh {
            dsh = DSHInteractionAdapter(model: island.model, bridge: bridge, home: installer.home,
                isInteractive: { [weak self] in self?.dshInteractive == true },
                currentTurn: { [weak self] key in
                    guard let self, context.running, context.listening, enabled, let session = context.sessions[key], session.active,
                          let turn = session.turn else { return nil }
                    return .init(id: turn, nativeID: session.nativeTurn, epoch: session.epoch, isChild: session.parent != nil)
                })
            interaction = dsh
        }
    }

    var enabled: Bool { context.enabled }

    func start() {
        guard !context.running else { return }; context.running = true
        observation = preferences.objectWillChange.receive(on: RunLoop.main).sink { [weak self] _ in
            Task { @MainActor in self?.reconcile() }
        }
        reconcile()
    }
    func stop() {
        context.running = false; observation = nil; context.revision = UUID(); applied = nil
        stopListening(); status = .disabled
    }
    func retry() { reconcile(force: true) }
    func revealConfiguration() { NSWorkspace.shared.open(installer.home) }
    func addConfigurationDirectory() {
        guard provider == .dsh, additionalHomes.count < 32 else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.message = preferences.copy.text("选择兼容客户端的 DSH 数据目录或 profiles 目录。", "Choose the compatible client's DSH data directory or profiles directory.")
        guard panel.runModal() == .OK, let selected = panel.url else { return }
        Task { [weak self] in
            let home = await Task.detached(priority: .utility) { NativeAgentInstaller.dshHome(for: selected) }.value
            guard let self else { return }
            directorySelectionFailed = home == nil
            guard let home else { return }
            if !additionalHomes.contains(home) && !configuredHomes.contains(home) {
                additionalHomes.append(home)
                defaults.set(additionalHomes.map(\.path), forKey: "integrations.dsh.additionalHomes")
            }
            if enabled { retry() }
        }
    }
    func removeConfigurationDirectory(_ home: URL) {
        guard provider == .dsh else { return }
        additionalHomes.removeAll { $0 == home }
        defaults.set(additionalHomes.map(\.path), forKey: "integrations.dsh.additionalHomes")
        // Reconcile even while disabled to clean any previously installed block.
        retry()
    }
    private func reconcile(force: Bool = false) {
        antigravity?.refreshApprovalMonitor()
        if let dsh, !enabled || !dshInteractive { dsh.releaseAll() }
        if !openCodeInteractive {
            openCode?.closeAll()
        }
        if !devinInteractive { devin?.closeAll() }
        if preferences.codexIslandPrivacy {
            for (key, session) in context.sessions where session.terminalBinding != nil {
                if let id = session.terminalBinding { ClaudeTerminalNavigation.bind(nil, to: id) }
                context.sessions[key]?.terminalBinding = nil
                context.sessions[key]?.conversation = nil
                context.publishMetadata(key)
            }
        }
        let interactive = openCodeInteractive || devinInteractive || (provider == .dsh && dshInteractive)
        if context.running, enabled, context.listening, provider == .openCode || provider.isDevin || provider == .dsh, approvalRouteEnabled != interactive {
            do {
                try installer.writeRoute(interactiveApprovals: interactive)
                approvalRouteEnabled = interactive
            } catch { failure = .invalidConfiguration; status = .failed }
        }
        guard context.running, force || applied != enabled else { return }
        let enabled = enabled
        let wasConfigured = applied != nil || FileManager.default.fileExists(atPath: installer.route.path)
        applied = enabled; context.revision = UUID()
        let current = context.revision
        stopListening()
        if enabled { antigravity?.start() }
        failure = nil; configuredHomes = []
        guard enabled || wasConfigured else { status = .disabled; return }
        status = .configuring
        let previous = configurationTask
        let installer = installer
        let additionalHomes = additionalHomes
        let approvals = interactive
        configurationTask = Task { [weak self] in
            await previous?.value
            let result = await Task.detached(priority: .utility) { () -> Result<[URL], NativeAgentInstaller.Failure> in
                do { return .success(try installer.configure(enabled: enabled, additionalHomes: additionalHomes, interactiveApprovals: approvals)) }
                catch let error as NativeAgentInstaller.Failure { return .failure(error) }
                catch { return .failure(.invalidConfiguration) }
            }.value
            guard let self, context.running, context.revision == current else { return }
            switch result {
            case .success(let homes): configuredHomes = homes
            case .failure(let error): failure = error; status = .failed; return
            }
            guard enabled else {
                status = .disabled
                await installer.configureConversationEditor(enabled: false)
                return
            }
            do {
                try bridge.start(onMessage: { [weak self] message in
                    Task { @MainActor in
                        guard let self, self.context.revision == current else { return }
                        self.receive(message)
                    }
                }, onDisconnect: { [weak self] id in
                    Task { @MainActor in
                        guard let self, self.context.revision == current else { return }
                        self.interaction?.disconnected(eventID: id)
                    }
                })
                context.listening = true; status = .waiting
                if provider == .openCode || provider.isDevin || provider == .dsh {
                    approvalRouteEnabled = approvals
                    reconcile()
                }
            } catch { self.failure = .listenerUnavailable; status = .failed; return }
            await installer.configureConversationEditor(enabled: true)
        }
    }

    private func receive(_ message: ClaudeCodeBridgeMessage) {
        if interaction?.handle(message) == true { return }
        hook.receive(message, homes: configuredHomes) {
            if status != .connected { status = .connected }
        }
    }

    private func stopListening() {
        devin?.stop()
        openCode?.closeAll()
        antigravity?.stop()
        dsh?.stop()
        hook.stop()
        if context.listening { bridge.stop() }; context.listening = false
        for (key, value) in context.sessions {
            if let id = value.terminalBinding { ClaudeTerminalNavigation.bind(nil, to: id) }
            if let turn = value.turn { island.model.withdrawHookExecution(session: key, turn: turn) }
            if value.parent != nil { island.model.withdrawSubagentObservation(for: key) }
        }
        context.sessions.removeAll()
    }

    func refreshAntigravityAccount(manual: Bool = false) async {
        await antigravity?.refreshAntigravityAccount(manual: manual)
    }

    func refreshAntigravityUsage() async {
        await antigravity?.refreshAntigravityUsage()
    }

    nonisolated static func antigravityUsage(_ file: URL, step: Int?, start: Date, end: Date) -> (step: Int, output: Int64, total: Int64?)? {
        AntigravityAgentAdapter.antigravityUsage(file, step: step, start: start, end: end)
    }
}
