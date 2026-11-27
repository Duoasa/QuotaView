import Combine
import Foundation
import LocalAuthentication
import Security

extension IslandAgentProvider {
    var quotaSource: String? {
        switch self {
        case .dsh: "deepseek"
        case .kimiCode: "kimi"
        case .openCode: "opencodego"
        case .geminiCLI: "gemini"
        case .copilotCLI: "copilot"
        case .cursor: "cursor"
        case .devinCLI, .devinDesktop: "devin"
        default: nil
        }
    }
    var quotaName: String {
        switch self {
        case .openCode: "OpenCode Go"
        case .dsh: "DeepSeek"
        case .devinDesktop, .devinCLI: "Devin"
        default: displayName
        }
    }
}

struct AgentQuotaReport: Equatable, Sendable {
    struct Window: Equatable, Sendable {
        let title: String
        let remaining: Int
        let resetsAt: Date?
    }
    let provider: String
    let windows: [Window]
    let balance: String?
    let updatedAt: Date
}

enum AgentQuotaState: Equatable {
    case loading, unavailable, current(AgentQuotaReport)
    var report: AgentQuotaReport? {
        if case let .current(value) = self { return value }; return nil
    }
}

private enum QuotaCredentials {
    static func query(_ source: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "QuotaView") + ".agent-quota",
         kSecAttrAccount as String: source]
    }
    static func read(_ source: String) -> Data? {
        var query = query(source)
        query[kSecReturnData as String] = true
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        if status == errSecItemNotFound { return Data() }
        return status == errSecSuccess ? value as? Data : nil
    }
    static func save(_ value: Data, source: String) -> Bool {
        let query = query(source)
        if value.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        let fields = [kSecValueData as String: value]
        let status = SecItemUpdate(query as CFDictionary, fields as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var item = query
        item[kSecValueData as String] = value
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
}

@MainActor
final class AgentQuotaStore: ObservableObject {
    let preferences: AppPreferences
    let defaults: UserDefaults
    let island: IslandSession
    private var observation: AnyCancellable?
    private var timers: [IslandAgentProvider: Task<Void, Never>] = [:]
    private var generations: [IslandAgentProvider: UUID] = [:]
    enum ConnectionState: Equatable { case disabled, checking, ready, needsLogin, unavailable }
    @Published private(set) var connections: [IslandAgentProvider: ConnectionState] = [:]
    private var fetching: [IslandAgentProvider: Task<Result<AgentQuotaReport, Error>, Never>] = [:]
    init(preferences: AppPreferences, defaults: UserDefaults, island: IslandSession) {
        self.preferences = preferences; self.defaults = defaults; self.island = island
    }
    func isEnabled(_ agent: IslandAgentProvider) -> Bool {
        guard let id = agent.quotaSource else { return false }
        return defaults.bool(forKey: "quota.read." + id)
    }
    func enable(_ enabled: Bool, for agent: IslandAgentProvider) {
        guard let id = agent.quotaSource else { return }
        objectWillChange.send()
        defaults.set(enabled, forKey: "quota.read." + id)
        reconcile(promptFor: enabled ? agent : nil)
    }

    /// Connecting is explicit consent to discover existing local login, but an
    /// earlier quota opt-out survives reconnects and application upgrades.
    func connect(_ provider: IslandAgentProvider) {
        guard let source = provider.quotaSource else { return }
        if defaults.object(forKey: "quota.read." + source) == nil {
            defaults.set(true, forKey: "quota.read." + source)
        }
        guard isEnabled(provider) else { return }
        retry(provider, allowCredentialPrompt: true)
    }

    func connectionState(_ provider: IslandAgentProvider) -> ConnectionState {
        guard isEnabled(provider) else { return .disabled }
        return connections[provider.isDevin ? .devinDesktop : provider] ?? .unavailable
    }

    func retry(_ provider: IslandAgentProvider, allowCredentialPrompt: Bool = false) {
        let target: IslandAgentProvider = provider.isDevin ? .devinDesktop : provider
        cancel(target)
        reconcile(promptFor: allowCredentialPrompt ? target : nil)
    }

    var savedKimiRegion: String { defaults.string(forKey: "quota.kimi.region") ?? "china" }

    func save(_ value: String, organization: String, kimiRegion: String, for agent: IslandAgentProvider) -> Bool {
        guard let source = agent.quotaSource, value.utf8.count <= 12_000,
              organization.utf8.count <= 256 else { return false }
        let data = value.isEmpty ? Data() : (try? JSONEncoder().encode(["credential": value, "organization": organization, "kimiRegion": kimiRegion]))
        guard let data, QuotaCredentials.save(data, source: source) else { return false }
        if agent == .kimiCode {
            if value.isEmpty { defaults.removeObject(forKey: "quota.kimi.region") }
            else { defaults.set(kimiRegion, forKey: "quota.kimi.region") }
        }
        let target: IslandAgentProvider = agent.isDevin ? .devinDesktop : agent
        cancel(target); reconcile()
        return true
    }
    func start() {
        guard observation == nil else { return }
        observation = preferences.objectWillChange.receive(on: RunLoop.main).sink { [weak self] _ in self?.reconcile() }
        reconcile()
    }
    func stop() {
        observation = nil
        for provider in Array(timers.keys) { cancel(provider) }
    }
    private func cancel(_ provider: IslandAgentProvider) {
        timers.removeValue(forKey: provider)?.cancel()
        generations[provider] = nil
        fetching.removeValue(forKey: provider)?.cancel()
        island.agentQuotas[provider] = nil
        connections[provider] = nil
    }
    private func integrationActive(_ provider: IslandAgentProvider) -> Bool {
        switch provider {
        case .geminiCLI: preferences.geminiCLIEnabled
        case .copilotCLI: preferences.copilotCLIEnabled
        case .cursor: preferences.cursorEnabled
        case .dsh: preferences.dshEnabled
        case .openCode: preferences.openCodeEnabled
        case .kimiCode: preferences.kimiCodeEnabled
        case .devinDesktop: preferences.devinDesktopEnabled || preferences.devinCLIEnabled
        default: false
        }
    }
    private func reconcile(promptFor: IslandAgentProvider? = nil) {
        guard observation != nil else { return }
        for provider in IslandAgentProvider.allCases where provider.quotaSource != nil && provider != .devinCLI {
            let active = isEnabled(provider) && integrationActive(provider) && !preferences.codexIslandPrivacy
            if !active {
                if timers[provider] != nil { cancel(provider) }
            } else if timers[provider] == nil {
                generations[provider] = UUID()
                island.agentQuotas[provider] = .loading
                connections[provider] = .checking
                timers[provider] = Task { [weak self] in
                    var prompt = promptFor == provider || (provider.isDevin && promptFor?.isDevin == true)
                    while !Task.isCancelled {
                        await self?.refresh(provider, allowCredentialPrompt: prompt)
                        prompt = false
                        do { try await Task.sleep(for: .seconds(300)) } catch { return }
                    }
                }
            }
        }
    }
    func refresh(_ requested: IslandAgentProvider, allowCredentialPrompt: Bool = false) async {
        let provider: IslandAgentProvider = requested.isDevin ? .devinDesktop : requested
        guard let id = generations[provider], fetching[provider] == nil, let source = provider.quotaSource else { return }
        connections[provider] = .checking
        let read = Task.detached(priority: .utility) { () -> Result<AgentQuotaReport, Error> in
            guard let input = QuotaCredentials.read(source) else { return .failure(URLError(.userAuthenticationRequired)) }
            do {
                return .success(try await NativeQuotaClient(allowCredentialPrompt: allowCredentialPrompt).fetch(provider, credentialData: input))
            } catch { return .failure(error) }
        }
        fetching[provider] = read
        let result = await read.value
        guard generations[provider] == id else { return }
        fetching[provider] = nil
        switch result {
        case .success(let report):
            island.agentQuotas[provider] = .current(report)
            connections[provider] = .ready
        case .failure(let error):
            island.agentQuotas[provider] = .unavailable
            let code = (error as? NativeQuotaClient.HTTPStatus)?.code
            connections[provider] = (error as? URLError)?.code == .userAuthenticationRequired || code == 401 || code == 403
                ? .needsLogin : .unavailable
        }
    }
}
