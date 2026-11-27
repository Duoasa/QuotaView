import ApplicationServices
import SwiftUI
import UniformTypeIdentifiers

private struct AgentSettingsDragItem: Codable, Transferable {
    let agentID: String
    static let contentType = UTType(exportedAs: "com.quotaview.agent-settings-item", conformingTo: .data)

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: contentType)
            .visibility(.ownProcess)
    }
}

/// Hovering moves an empty slot. Only the final drop writes the user's order.
struct AgentReorderPreview: Equatable {
    let agent: IslandAgentProvider
    let original: [IslandAgentProvider]
    private(set) var order: [IslandAgentProvider]

    init(agent: IslandAgentProvider, order: [IslandAgentProvider]) {
        self.agent = agent
        self.original = order
        self.order = order
    }

    mutating func update(at y: CGFloat, heights: [IslandAgentProvider: CGFloat]) {
        guard let current = order.firstIndex(of: agent) else { return }
        var top: CGFloat = 0
        var destination = 0
        for provider in order {
            let height = heights[provider] ?? SettingsLayoutMetrics.rowMinHeight
            if provider != agent && y >= top + height / 2 { destination += 1 }
            top += height + 1 // NativeSettingsDivider
        }
        if current != destination {
            order.remove(at: current)
            order.insert(agent, at: destination)
        }
    }

    var target: IslandAgentProvider? {
        order.firstIndex(of: agent).map { original[$0] }
    }
}

private struct AgentDragCancellation: ViewModifier {
    let onCancel: () -> Void

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.onDragSessionUpdated { session in
                if case let .ended(operation) = session.phase, operation != .move { onCancel() }
            }
        } else {
            content
        }
    }
}

private struct AgentListDropDelegate: DropDelegate {
    @Binding var source: IslandAgentProvider?
    @Binding var preview: AgentReorderPreview?
    let preferences: AppPreferences
    let heights: [IslandAgentProvider: CGFloat]

    func validateDrop(info: DropInfo) -> Bool {
        source != nil && info.hasItemsConforming(to: [AgentSettingsDragItem.contentType])
    }

    func dropEntered(info: DropInfo) { update(info) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(info)
        return DropProposal(operation: .move)
    }

    private func update(_ info: DropInfo) {
        guard let source else { return }
        var next = preview ?? AgentReorderPreview(agent: source, order: preferences.agentSettingsOrder)
        next.update(at: info.location.y, heights: heights)
        if next != preview { preview = next }
    }

    func dropExited(info: DropInfo) { preview = nil }

    func performDrop(info: DropInfo) -> Bool {
        defer { preview = nil; source = nil }
        guard validateDrop(info: info) else { return false }
        update(info)
        guard let preview, preview.original == preferences.agentSettingsOrder, let target = preview.target else { return false }
        preferences.moveAgentInSettings(preview.agent, to: target)
        return true
    }
}

struct AgentIntegrationSettings<Details: View>: View {
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var codex: CodexActivityRuntime
    @ObservedObject var claude: ClaudeCodeRuntime
    @ObservedObject var quotas: AgentQuotaStore
    @ObservedObject var dsh: NativeAgentRuntime
    @ObservedObject var kimi: NativeAgentRuntime
    @ObservedObject var cursor: NativeAgentRuntime
    @ObservedObject var geminiCLI: NativeAgentRuntime
    @ObservedObject var openCode: NativeAgentRuntime
    @ObservedObject var antigravity: NativeAgentRuntime
    @ObservedObject var copilotCLI: NativeAgentRuntime
    @ObservedObject var devinDesktop: NativeAgentRuntime
    @ObservedObject var devinCLI: NativeAgentRuntime
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragSource: IslandAgentProvider?
    @State private var dragPreview: AgentReorderPreview?
    @State private var rowHeights: [IslandAgentProvider: CGFloat] = [:]
    let selected: IslandAgentProvider?
    let openAgent: (IslandAgentProvider) -> Void
    let codexDetails: () -> Details
    private var copy: AppCopy { preferences.copy }

    init(preferences: AppPreferences, runtime: CodexActivityRuntime, selected: IslandAgentProvider?,
         openAgent: @escaping (IslandAgentProvider) -> Void, @ViewBuilder codexDetails: @escaping () -> Details) {
        self.selected = selected; self.openAgent = openAgent
        self.preferences = preferences; codex = runtime; claude = runtime.claudeCode; quotas = runtime.agentQuotas
        dsh = runtime.dsh; kimi = runtime.kimiCode; self.codexDetails = codexDetails
        cursor = runtime.cursor; geminiCLI = runtime.geminiCLI; openCode = runtime.openCode; antigravity = runtime.antigravity; copilotCLI = runtime.copilotCLI
        devinDesktop = runtime.devinDesktop; devinCLI = runtime.devinCLI
    }
    var body: some View {
        if let selected {
            let enabled = integrationBinding(selected)
            let title = copy.text("启用接入", "Enable integration")
            NativeSettingsCard {
                NativeSettingsRow(title: title, subtitle: connectionSummary(selected).description) {
                    if enabled.wrappedValue { checkConnectionButton(selected) }
                    integrationToggle(selected)
                }
                if enabled.wrappedValue {
                    capabilityRows(selected)
                }
                NativeSettingsDivider()
                if selected == .codex {
                    codexDetails().disabled(!enabled.wrappedValue)
                } else if selected == .claudeCode {
                    ClaudeCodeConnectionSettings(runtime: claude, preferences: preferences)
                } else if let runtime = nativeRuntime(selected) {
                    if selected.quotaSource != nil {
                        AgentQuotaSettings(store: quotas, provider: selected, copy: copy)
                            .id(selected).disabled(!enabled.wrappedValue)
                        NativeSettingsDivider()
                    }
                    nativeDetails(runtime)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: SettingsLayoutMetrics.sectionSpacing) {
                ConversationAccessibilitySettings(copy: copy)
                VStack(alignment: .leading, spacing: SettingsLayoutMetrics.headingSpacing) {
                    Text("Agent").font(.system(size: 13, weight: .semibold))
                        .padding(.leading, SettingsLayoutMetrics.cardInset)
                        .accessibilityAddTraits(.isHeader)
                    agentList
                }
            }
        }
    }

    private var agentList: some View {
        let order = dragPreview?.order ?? preferences.agentSettingsOrder
        return NativeSettingsCard {
            ForEach(order, id: \.self) { provider in
                VStack(spacing: 0) {
                    if provider != order.first { NativeSettingsDivider() }
                    let isGap = dragPreview?.agent == provider
                    row(provider)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowHeights[provider] = $0 }
                        .opacity(isGap ? 0 : 1)
                        .background {
                            if isGap {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.08))
                                    .padding(.horizontal, 4).padding(.vertical, 2)
                            }
                        }
                }
            }
        }
        .animation(reduceMotion ? nil : .interactiveSpring(response: 0.30, dampingFraction: 0.78), value: order)
        .onDrop(of: [AgentSettingsDragItem.contentType], delegate: AgentListDropDelegate(
            source: $dragSource, preview: $dragPreview, preferences: preferences, heights: rowHeights))
        .task(id: dragSource) {
            if #available(macOS 26.0, *) { return }
            guard let source = dragSource else { return }
            // Earlier SwiftUI has no source-end callback for a cancelled native drag.
            do {
                while NSEvent.pressedMouseButtons & 1 != 0 {
                    try await Task.sleep(for: .milliseconds(120))
                }
                // Let the destination receive mouse-up before discarding its preview.
                try await Task.sleep(for: .milliseconds(120))
                if dragSource == source { dragPreview = nil; dragSource = nil }
            } catch { return }
        }
        .onDisappear { dragPreview = nil; dragSource = nil }
    }

    private func row(_ provider: IslandAgentProvider) -> some View {
        let status = connectionSummary(provider)
        let detailsHint = copy.text("显示连接设置", "Show connection settings")
        return HStack(spacing: 8) {
            dragHandle(provider)
            Button { openAgent(provider) } label: {
                HStack(spacing: 6) {
                    HStack(spacing: SettingsLayoutMetrics.iconGap) {
                        AgentSettingsIcon(provider: provider)
                        Text(provider.displayName).font(SettingsLayoutMetrics.titleFont)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: status.health.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(status.health.color)
                    Text(status.health.label(copy))
                        .font(SettingsLayoutMetrics.detailFont)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, SettingsLayoutMetrics.rowVerticalInset)
                .frame(maxWidth: .infinity, minHeight: SettingsLayoutMetrics.rowMinHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(detailsHint)
            .accessibilityLabel(Text(provider.displayName))
            .accessibilityValue(Text(status.health.label(copy)))
            .accessibilityHint(Text(detailsHint))

            integrationToggle(provider)
        }
        .padding(.leading, SettingsLayoutMetrics.iconInset)
        .padding(.trailing, SettingsLayoutMetrics.cardInset)
        .background {
            // Include the row surface in the native drag image, inside the card's border.
            SettingsPalette.group.padding(1).allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .contentShape(.dragPreview, RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onDrag {
            let item = NSItemProvider()
            item.register(AgentSettingsDragItem(agentID: provider.rawValue))
            dragPreview = nil
            dragSource = provider
            return item
        }
        .modifier(AgentDragCancellation(onCancel: {
            if dragSource == provider { dragPreview = nil; dragSource = nil }
        }))
    }

    private func dragHandle(_ provider: IslandAgentProvider) -> some View {
        let hint = copy.text("拖动以调整 Agent 顺序", "Drag to reorder agents")
        return Image(systemName: "line.3.horizontal")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 22, height: SettingsLayoutMetrics.rowMinHeight)
            .contentShape(Rectangle())
            .help(hint)
            .accessibilityLabel(Text(provider.displayName + " · " + hint))
            .accessibilityAdjustableAction { direction in
                let order = preferences.agentSettingsOrder
                guard let index = order.firstIndex(of: provider) else { return }
                let destination: Int
                switch direction {
                case .increment: destination = index + 1
                case .decrement: destination = index - 1
                @unknown default: return
                }
                if order.indices.contains(destination) {
                    preferences.moveAgentInSettings(provider, to: order[destination])
                }
            }
    }

    private func integrationToggle(_ provider: IslandAgentProvider) -> some View {
        let enabled = integrationBinding(provider)
        let title = provider.displayName + " · " + copy.text("启用接入", "Enable integration")
        return Toggle(title, isOn: Binding(get: { enabled.wrappedValue }, set: { value in
            if value { connect(provider) } else { enabled.wrappedValue = false }
        }))
        .toggleStyle(.switch)
        .labelsHidden()
        .controlSize(.small)
        .disabled(isBusy(provider))
    }

    private func checkConnectionButton(_ provider: IslandAgentProvider) -> some View {
        let title = copy.text("检查连接", "Check connection")
        return Button { connect(provider) } label: {
            if isBusy(provider) { ProgressView().controlSize(.small) }
            else { Text(title) }
        }
        .buttonStyle(.bordered).controlSize(.small).disabled(isBusy(provider))
        .help(copy.text("连接额度和任务，启用支持的岛内审批与问答。", "Connect quota and tasks and enable supported approvals and replies in the island."))
        .accessibilityLabel(Text(provider.displayName + " · " + title))
    }

    private func isBusy(_ provider: IslandAgentProvider) -> Bool {
        if provider == .codex { return codex.hookOperation != .idle || codex.isChangingDataDirectory }
        if provider == .claudeCode, case .configuring = claude.status { return true }
        return nativeRuntime(provider)?.status == .configuring
    }

    private func connect(_ provider: IslandAgentProvider) {
        guard !isBusy(provider) else { return }
        let binding = integrationBinding(provider)
        let wasEnabled = binding.wrappedValue
        if provider == .claudeCode,
           quotas.defaults.object(forKey: "claudeCode.statusLineEnabled") == nil {
            preferences.claudeCodeStatusLineEnabled = true
        }
        if provider == .openCode, quotas.defaults.object(forKey: "integrations.openCode.interactions") == nil {
            preferences.openCodeInteractionsEnabled = true
        }
        if !wasEnabled { binding.wrappedValue = true }
        switch provider {
        case .codex:
            codex.refreshIntegrationQuota()
            switch codex.hookConnectionStatus {
            case .notInstalled, .installedNeedsRestart, .awaitingTrust, .abnormal:
                if codex.hookExplicitlyDisabled { codex.recheckAutomaticConnection() }
                else { codex.openCodexSecurityReview() }
            case .connected, .awaitingFirstEvent:
                codex.recheckAutomaticConnection()
                if codex.canConfigureSharedAnswers && !codex.desktopIgnoresDaemonPreference && codex.nativeConnectionState != .connected {
                    codex.requestSharedAnswers()
                }
            }
        case .claudeCode:
            if wasEnabled, case .failed = claude.status { claude.retry() }
            else { claude.refreshUsage() }
        default:
            if let runtime = nativeRuntime(provider), wasEnabled, runtime.status == .failed { runtime.retry() }
        }
        if provider == .antigravity && wasEnabled && !preferences.codexIslandPrivacy {
            Task { await antigravity.refreshAntigravityAccount(manual: true) }
        }
        quotas.connect(provider)
    }

    @ViewBuilder private func capabilityRows(_ provider: IslandAgentProvider) -> some View {
        let original = copy.text("在原会话中处理", "Use original chat")
        let available = copy.text("可在岛内处理支持的请求", "Handle supported requests in the island")
        let task = taskConnection(provider).label(copy)
        let approvals: String = {
            guard preferences.codexActivityIslandEnabled && !preferences.codexIslandPrivacy else { return original }
            switch provider {
            case .codex:
                return codex.liveIsland.model.usesLegacyDesktopAnswers || codex.canConfigureSharedAnswers ? available : original
            case .claudeCode: return preferences.claudeCodeInteractiveApprovals && (claude.status == .connected || claude.status == .awaitingEvent) ? available : original
            case .openCode: return preferences.openCodeInteractionsEnabled && (openCode.status == .waiting || openCode.status == .connected)
                ? copy.text("支持的 OpenCode 插件会话", "Supported OpenCode plugin sessions") : original
            case .devinDesktop, .devinCLI:
                guard let runtime = nativeRuntime(provider), runtime.devinInteractive, runtime.status == .waiting || runtime.status == .connected else { return original }
                return available
            case .dsh: return preferences.dshInteractiveApprovals && (dsh.status == .connected || dsh.status == .waiting) ? available : original
            case .antigravity: return preferences.antigravityInteractiveApprovals && AXIsProcessTrusted() && (antigravity.status == .connected || antigravity.status == .waiting) ? available : original
            default: return original
            }
        }()
        let answers: String = {
            switch provider {
            case .codex:
                guard preferences.codexActivityIslandEnabled && !preferences.codexIslandPrivacy else { return original }
                if codex.liveIsland.model.usesLegacyDesktopAnswers { return available }
                if codex.canUseNativeQuestionInput { return copy.text("可回答已打开的 Codex 问题卡", "Reply to an open Codex question card") }
                if codex.desktopIgnoresDaemonPreference { return original }
                return codex.nativeConnectionState == .connected
                    ? copy.text("可在同一共享会话中回答", "Reply in the same shared session") : original
            case .claudeCode, .openCode, .dsh, .antigravity: return approvals
            default: return original
            }
        }()
        let quota = quotaConnectionText(quotaConnection(provider), copy: copy)
        NativeSettingsDivider()
        NativeSettingsRow(title: copy.text("任务", "Tasks"), subtitle: task) { EmptyView() }
        NativeSettingsDivider()
        NativeSettingsRow(title: copy.text("额度", "Quota"), subtitle: quota) { EmptyView() }
        NativeSettingsDivider()
        NativeSettingsRow(title: copy.text("审批", "Approvals"), subtitle: approvals) { EmptyView() }
        NativeSettingsDivider()
        NativeSettingsRow(title: copy.text("问答", "Questions and answers"), subtitle: answers) { EmptyView() }
    }

    private func quotaConnection(_ provider: IslandAgentProvider) -> AgentQuotaStore.ConnectionState {
        guard !preferences.codexIslandPrivacy else { return .disabled }
        switch provider {
        case .codex:
            switch codex.islandUsage.state {
            case .current: return .ready
            case .loading: return .checking
            case .unavailable, .stale: return .unavailable
            }
        case .claudeCode:
            switch codex.liveIsland.claudeUsage?.quotaState {
            case .available: return .ready
            case .off: return .disabled
            default: return .checking
            }
        case .antigravity:
            guard let usage = codex.liveIsland.antigravityUsage, usage.didCheckAccount else { return .checking }
            return usage.account?.windows.isEmpty == false ? .ready : .unavailable
        default:
            guard quotas.isEnabled(provider) else { return .disabled }
            let key: IslandAgentProvider = provider.isDevin ? .devinDesktop : provider
            let state = quotas.connections[key] ?? .checking
            if state == .checking, codex.liveIsland.agentQuotas[key]?.report != nil { return .ready }
            return state
        }
    }

    private enum ConnectionHealth {
        case active, attention, waiting, disabled

        var symbol: String {
            switch self {
            case .active: "checkmark.circle.fill"
            case .attention: "exclamationmark.triangle.fill"
            case .waiting: "clock"
            case .disabled: "minus.circle"
            }
        }

        var color: Color {
            switch self {
            case .active: Color(nsColor: .systemGreen)
            case .attention: Color(nsColor: .systemYellow)
            case .waiting, .disabled: Color(nsColor: .systemRed)
            }
        }

        func label(_ copy: AppCopy) -> String {
            switch self {
            case .active: copy.text("已激活", "Active")
            case .attention: copy.text("需检查", "Needs attention")
            case .waiting: copy.text("等待连接", "Waiting for connection")
            case .disabled: copy.text("已停用", "Disabled")
            }
        }
    }

    private func connectionSummary(_ provider: IslandAgentProvider) -> (description: String, health: ConnectionHealth) {
        let task = taskConnection(provider)
        guard integrationBinding(provider).wrappedValue else {
            if provider != .codex && task == .failed { return (task.label(copy), .attention) }
            return (ConnectionHealth.disabled.label(copy), .disabled)
        }
        let quota = quotaConnection(provider)
        var description = task.label(copy)
        if quota != .disabled { description += " · " + quotaConnectionText(quota, copy: copy) }
        if provider == .codex && codex.canConfigureSharedAnswers && !codex.desktopIgnoresDaemonPreference
            && codex.answerLaunchState == .failed && codex.nativeConnectionState != .connected {
            description += " · " + copy.text("共享启动未完成。请检查 Codex 桌面版后重试。", "Shared launch did not finish. Check the Codex desktop app and retry.")
            return (description, .attention)
        }
        if task == .failed || task == .needsTrust || quota == .needsLogin || quota == .unavailable {
            return (description, .attention)
        }
        return (description, task == .connected || quota == .ready ? .active : .waiting)
    }

    private func integrationBinding(_ provider: IslandAgentProvider) -> Binding<Bool> {
        switch provider {
        case .codex: $preferences.codexIntegrationEnabled
        case .claudeCode: $preferences.claudeCodeEnabled
        case .dsh: $preferences.dshEnabled
        case .kimiCode: $preferences.kimiCodeEnabled
        case .cursor: $preferences.cursorEnabled
        case .geminiCLI: $preferences.geminiCLIEnabled
        case .openCode: $preferences.openCodeEnabled
        case .antigravity: $preferences.antigravityEnabled
        case .copilotCLI: $preferences.copilotCLIEnabled
        case .devinDesktop: $preferences.devinDesktopEnabled
        case .devinCLI: $preferences.devinCLIEnabled
        }
    }

    private enum TaskConnection {
        case connected, waiting, configuring, needsTrust, failed

        func label(_ copy: AppCopy) -> String {
            switch self {
            case .connected: copy.text("已连接", "Connected")
            case .waiting: copy.text("已配置，等待新会话", "Configured, waiting for a new session")
            case .configuring: copy.text("配置中", "Configuring")
            case .needsTrust: copy.text("需要授权", "Authorization required")
            case .failed: copy.text("需要处理", "Needs attention")
            }
        }
    }

    private func taskConnection(_ provider: IslandAgentProvider) -> TaskConnection {
        switch provider {
        case .codex:
            if !codex.hookExplicitlyDisabled {
                if case .failed = codex.bridgeStatus { return .failed }
                switch codex.hookConnectionStatus {
                case .awaitingTrust, .installedNeedsRestart: return .needsTrust
                case .abnormal: return .failed
                default: break
                }
            }
            if codex.localHealth.hasReadError { return .failed }
            return codex.isNativeActivityConnected || codex.hookConnectionStatus == .connected ? .connected : .waiting
        case .claudeCode:
            switch claude.status {
            case .connected: return .connected
            case .configuring: return .configuring
            case .failed: return .failed
            default: return .waiting
            }
        default:
            switch nativeRuntime(provider)?.status {
            case .connected: return .connected
            case .configuring: return .configuring
            case .failed: return .failed
            default: return .waiting
            }
        }
    }
    private func nativeRuntime(_ provider: IslandAgentProvider) -> NativeAgentRuntime? {
        switch provider {
        case .dsh: dsh; case .kimiCode: kimi
        case .cursor: cursor
        case .geminiCLI: geminiCLI
        case .openCode: openCode
        case .antigravity: antigravity
        case .copilotCLI: copilotCLI
        case .devinDesktop: devinDesktop
        case .devinCLI: devinCLI
        case .codex, .claudeCode: nil
        }
    }
    private func failureMessage(_ failure: NativeAgentInstaller.Failure?) -> String {
        switch failure {
        case .missingInstallation: copy.text("请先安装并启动一次该 Agent，再重试。", "Install and open the agent once, then retry.")
        case .invalidConfiguration: copy.text("无法安全更新配置。请检查配置格式与文件权限。", "Could not safely update the configuration. Check its format and file permissions.")
        case .configurationChanged: copy.text("配置正在被其他程序修改，请稍后重试。", "Another application changed the configuration. Retry shortly.")
        case .missingHelper: copy.text("连接组件缺失，请重新安装 QuotaView。", "The connection helper is missing. Reinstall QuotaView.")
        case .listenerUnavailable: copy.text("本地连接未能启动，请退出其他同渠道 QuotaView 后重试。", "The local listener could not start. Quit other copies of this QuotaView channel and retry.")
        case nil: copy.text("连接未完成，请重试。", "Setup did not finish. Please retry.")
        }
    }
    private func nativeDetails(_ runtime: NativeAgentRuntime) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if runtime.provider.isDevin {
                let title = copy.text("在灵动岛处理权限请求", "Handle permission prompts in the island")
                NativeSettingsRow(title: title, subtitle: runtime.provider.displayName) {
                    Toggle(title, isOn: runtime.provider == .devinCLI ? $preferences.devinCLIApprovals : $preferences.devinDesktopApprovals)
                        .labelsHidden().toggleStyle(.switch).disabled(!runtime.enabled)
                }
                NativeSettingsDivider()
            }
            if runtime.provider == .openCode {
                NativeSettingsRow(title: copy.text("岛内审批与问答", "Island approvals and replies"),
                    subtitle: copy.text("在新 OpenCode 会话中处理权限请求和单选问题。", "Handle permissions and single-choice questions in new OpenCode sessions.")) {
                    Toggle("", isOn: $preferences.openCodeInteractionsEnabled).labelsHidden().toggleStyle(.switch)
                        .accessibilityLabel(copy.text("岛内审批与问答", "Island approvals and replies")).disabled(!runtime.enabled)
                }
                NativeSettingsDivider()
            }
            if runtime.provider == .antigravity {
                NativeSettingsRow(title: "Antigravity CLI (agy)",
                    subtitle: copy.text("安装后可在后台刷新额度。未安装时从桌面端读取。", "Install to refresh quotas in the background. Without agy, QuotaView reads from the desktop app.")) {
                    switch runtime.agyInstallation {
                    case .installed:
                        Text(copy.text("已安装", "Installed")).font(.caption).foregroundStyle(.secondary)
                    case .installing:
                        ProgressView().controlSize(.small).accessibilityLabel(copy.text("正在安装 agy", "Installing agy"))
                    case .missing, .failed:
                        Button(copy.text("安装 agy", "Install agy")) { runtime.installAGY() }.controlSize(.small)
                    }
                }
                .onAppear { runtime.checkAGYInstallation() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    runtime.checkAGYInstallation()
                }
                if runtime.agyInstallation == .failed {
                    NativeSettingsNote(text: copy.text("agy 安装失败，可稍后重试。", "Could not install agy. Try again later."))
                }
                NativeSettingsDivider()
                NativeSettingsRow(title: copy.text("岛内审批与问答", "Island approvals and replies"),
                    subtitle: copy.text("通过辅助功能处理已打开的权限卡和单题。", "Use Accessibility to respond to open permission cards and single questions.")) {
                    Toggle(copy.text("岛内审批与问答", "Island approvals and replies"), isOn: $preferences.antigravityInteractiveApprovals)
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                        .disabled(!runtime.enabled)
                }
                NativeSettingsDivider()
            }
            if runtime.provider == .dsh {
                NativeSettingsRow(title: copy.text("岛内审批与问答", "Island approvals and replies"),
                    subtitle: runtime.provider.displayName) {
                    Toggle(copy.text("岛内审批与问答", "Island approvals and replies"), isOn: $preferences.dshInteractiveApprovals)
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                        .disabled(!runtime.enabled)
                }
                NativeSettingsDivider()
                NativeSettingsRow(title: copy.text("配置目录", "Configuration directories"),
                    subtitle: runtime.configuredHomes.isEmpty
                        ? copy.text("自动识别 DSH 及兼容客户端，也可添加自定义目录。", "Detects DSH and compatible clients. Custom directories can also be added.")
                        : copy.text("已接入 \(runtime.configuredHomes.count) 个配置目录。", "Connected to \(runtime.configuredHomes.count) configuration directories.")) {
                    HStack(spacing: 8) {
                        Button(copy.text("重新检查", "Recheck")) { runtime.retry() }.disabled(!runtime.enabled)
                        Button(copy.text("添加目录", "Add Directory")) { runtime.addConfigurationDirectory() }
                            .disabled(runtime.additionalHomes.count >= 32)
                    }.controlSize(.small).disabled(runtime.status == .configuring)
                }
                ForEach(runtime.additionalHomes, id: \.path) { home in
                    NativeSettingsDivider()
                    NativeSettingsRow(title: copy.text("自定义目录", "Custom directory"), subtitle: home.path) {
                        Button(copy.text("移除", "Remove")) { runtime.removeConfigurationDirectory(home) }
                            .controlSize(.small).disabled(runtime.status == .configuring)
                    }
                }
                if runtime.directorySelectionFailed {
                    NativeSettingsNote(text: copy.text("所选目录中没有找到有效的 DSH profile，请先启动一次客户端。",
                        "No valid DSH profile was found in this directory. Open the client once first."))
                }
            } else {
                NativeSettingsRow(title: copy.text("配置目录", "Configuration directory"), subtitle: runtime.installer.home.path) {
                    Button(copy.text("打开目录", "Open Directory")) { runtime.revealConfiguration() }.controlSize(.small)
                }
            }
            if runtime.provider == .devinDesktop {
                NativeSettingsNote(text: copy.text("显示 Devin Local 的本机任务；请在受信任的工作区中使用。", "Shows local Devin Local tasks. Use a trusted workspace."))
            }
            NativeSettingsDivider()
            if runtime.provider == .dsh {
                NativeSettingsNote(text: copy.text("更新接入后重启 DSH。待审批动作的参数仅在本机临时显示，不保存到任务历史；不支持的请求在 DSH 中处理。",
                    "Restart DSH after updating the integration. Pending action parameters are shown locally and never saved to task history; handle unsupported requests in DSH."))
            } else if runtime.provider == .antigravity || runtime.provider.isDevin {
                NativeSettingsNote(text: copy.text("新会话会自动连接；权限请求按上方设置处理。", "New sessions connect automatically. Permission requests follow the setting above."))
            } else if runtime.provider != .openCode {
                NativeSettingsNote(text: copy.text("启用后重启对应客户端；权限请求仍在原客户端确认。",
                                "Restart the client after enabling. Confirm permissions in the original client."))
            }
            if runtime.status == .failed {
                NativeSettingsDivider()
                NativeSettingsRow(title: copy.text("连接未完成", "Setup incomplete"),
                    subtitle: failureMessage(runtime.failure)) {
                    Button(copy.text("重试", "Retry")) { runtime.retry() }.controlSize(.small)
                }
            }
        }
    }
}

private struct ConversationAccessibilitySettings: View {
    let copy: AppCopy
    @State private var authorized = false
    @State private var automation: [ClaudeTerminalNavigation.Application: ClaudeTerminalNavigation.Permission] = [:]

    @State private var requesting: ClaudeTerminalNavigation.Application?
    @State private var refreshID = UUID()

    var body: some View {
        let title = copy.text("辅助功能权限", "Accessibility permission")
        let status = authorized ? copy.text("已授权", "Granted") : copy.text("未授权", "Not granted")
        let hint = copy.text("在系统设置中管理权限", "Manage permission in System Settings")
        NativeSettingsCard {
            NativeSettingsRow(title: title,
                subtitle: copy.text("辅助功能用于回答 Codex 问题、跳转 DSH 和 Antigravity 对话，以及读取 Antigravity 额度。",
                                    "Accessibility lets QuotaView answer Codex questions, open DSH and Antigravity conversations, and read Antigravity quotas."),
                symbol: "accessibility") {
                HStack(spacing: 8) {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Toggle(title, isOn: Binding(get: { authorized }, set: managePermission))
                        .labelsHidden().toggleStyle(.switch)
                        .accessibilityHint(hint).help(hint)
                }
            }
            ForEach(ClaudeTerminalNavigation.Application.allCases, id: \.self) { app in
                if let permission = automation[app] {
                    NativeSettingsDivider()
                    NativeSettingsRow(title: app == .terminal ? "Terminal" : "iTerm2",
                        subtitle: copy.text("自动化权限用于切换到运行 Claude Code 的标签页。", "Automation lets QuotaView select the tab running Claude Code."),
                        symbol: "terminal") {
                        if requesting == app {
                            ProgressView().controlSize(.small)
                                .accessibilityLabel(copy.text("正在请求授权", "Requesting permission"))
                        } else {
                            Button(permissionLabel(permission)) {
                                switch permission {
                                case .granted, .denied:
                                    if let pane = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                                        NSWorkspace.shared.open(pane)
                                    }
                                case .firstUse, .notRunning, .unavailable:
                                    Task { await requestAutomation(app, startIfNeeded: permission == .notRunning) }
                                }
                            }
                            .disabled(requesting != nil)
                        }
                    }
                }
            }
        }
        .task { await refreshPermissions() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refreshPermissions() }
        }
    }

    private func permissionLabel(_ permission: ClaudeTerminalNavigation.Permission) -> String {
        switch permission {
        case .granted: copy.text("已授权", "Granted")
        case .denied: copy.text("未授权 · 打开设置", "Not granted · Open Settings")
        case .firstUse: copy.text("请求授权", "Request permission")
        case .notRunning: copy.text("启动并请求授权", "Launch and request permission")
        case .unavailable: copy.text("状态不可用 · 重试", "Status unavailable · Retry")
        }
    }

    @MainActor private func requestAutomation(_ app: ClaudeTerminalNavigation.Application, startIfNeeded: Bool) async {
        guard requesting == nil else { return }
        requesting = app
        refreshID = UUID()
        automation[app] = await ClaudeTerminalNavigation.requestPermission(app, startIfNeeded: startIfNeeded)
        requesting = nil
    }

    @MainActor private func refreshPermissions() async {
        authorized = AXIsProcessTrusted()
        guard requesting == nil else { return }
        let id = UUID()
        refreshID = id
        let installed = ClaudeTerminalNavigation.Application.allCases.filter {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.rawValue) != nil
        }
        let states = await Task.detached(priority: .utility) {
            Dictionary(uniqueKeysWithValues: installed.map { ($0, ClaudeTerminalNavigation.permission($0)) })
        }.value
        if refreshID == id { automation = states }
    }

    private func managePermission(_ requested: Bool) {
        if requested && !AXIsProcessTrusted() {
            let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
        }
        if let pane = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(pane)
        }
    }
}

/// Shared brand artwork for integration rows and their detail titles.
struct AgentSettingsIcon: View {
    let provider: IslandAgentProvider
    private var background: Color {
        provider == .claudeCode ? .clear : .white
    }
    var body: some View {
        let size = SettingsLayoutMetrics.agentIconSize
        ZStack {
            background
            if let icon = IslandProviderIcon.settingsMark(for: provider) {
                // Official app artwork has a transparent margin around its tile.
                let isAppIcon = [IslandAgentProvider.codex, .claudeCode, .antigravity].contains(provider)
                let markSize = isAppIcon ? size * 1.25 : (provider == .kimiCode ? size : 19)
                Image(nsImage: icon).resizable().scaledToFit()
                    .frame(width: markSize, height: markSize)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

private struct AgentQuotaSettings: View {
    @ObservedObject var store: AgentQuotaStore
    let provider: IslandAgentProvider
    let copy: AppCopy
    @State private var credential = ""
    @State private var organization = ""
    @State private var kimiRegion = "china"
    @State private var status = ""
    @State private var manualExpanded = false
    var body: some View {
        let active = store.isEnabled(provider)
        let title = copy.text("后台读取额度", "Read quota in the background")
        NativeSettingsRow(title: title, subtitle: quotaConnectionText(store.connectionState(provider), copy: copy)) {
            Toggle(title, isOn: Binding(get: { active }, set: { store.enable($0, for: provider) }))
                .labelsHidden().toggleStyle(.switch)
        }
        if active {
            NativeSettingsDivider()
            NativeSettingsRow(title: copy.text("使用本机登录", "Use local sign-in"), subtitle: loginHint) {
                Button(copy.text("重新检查", "Recheck")) { store.retry(provider, allowCredentialPrompt: true) }
                    .controlSize(.small).disabled(store.connectionState(provider) == .checking)
            }
        }
        if active && provider != .geminiCLI {
            NativeSettingsDivider()
            NativeSettingsRow(title: copy.text("手动配置", "Manual configuration")) {
                Button(manualExpanded ? copy.text("收起", "Collapse") : copy.text("展开", "Expand")) { manualExpanded.toggle() }
                    .controlSize(.small)
            }
        }
        if active && manualExpanded && provider != .geminiCLI {
            NativeSettingsDivider()
            if provider == .kimiCode {
                NativeSettingsRow(title: copy.text("账号地区", "Account region")) {
                    Picker("", selection: $kimiRegion) {
                        Text("kimi.com").tag("china")
                        Text("kimi.ai").tag("international")
                    }.labelsHidden().fixedSize()
                }.onAppear { kimiRegion = store.savedKimiRegion }
                NativeSettingsDivider()
            }
            if provider.isDevin {
                NativeSettingsRow(title: copy.text("组织", "Organization")) {
                    TextField("Devin", text: $organization).frame(width: 170)
                }
                NativeSettingsDivider()
            }
            let label = switch provider {
            case .cursor: "Cursor Cookie"
            case .devinCLI, .devinDesktop: "Devin Bearer Token"
            case .copilotCLI: "GitHub Token"
            default: "API Key"
            }
            NativeSettingsRow(title: label, subtitle: status.isEmpty ? copy.text("凭据保存在本机钥匙串。", "Credentials are stored in your Mac keychain.") : status) {
                SecureField(label, text: $credential).frame(width: 130)
                Button(copy.text("保存", "Save")) {
                    save(credential)
                }.disabled(credential.isEmpty || (provider.isDevin && organization.isEmpty))
                Button(copy.text("移除", "Remove")) { save("") }
            }
        }
    }
    private var loginHint: String {
        switch provider {
        case .dsh:
            copy.text("自动使用环境变量或 DSH 已保存的 DeepSeek API Key 查询账户余额。也可手动添加。", "Reads the account balance using a DeepSeek API key from the environment or DSH. You can also add one manually.")
        case .devinCLI, .devinDesktop:
            copy.text("Devin 额度需要组织与访问凭据，请在手动配置中填写。", "Devin quota requires an organization and access credential in Manual configuration.")
        case .kimiCode:
            copy.text("使用 Kimi Code 的有效登录；过期后请先在 Kimi 中更新登录。", "Uses a valid Kimi Code sign-in. Renew it in Kimi when it expires.")
        default:
            copy.text("优先保留已保存的凭据，否则读取客户端已有登录。登录后点重新检查。", "Keeps saved credentials first, otherwise reads the client's existing sign-in. Recheck after signing in.")
        }
    }
    private func save(_ value: String) {
        let saved = store.save(value, organization: organization, kimiRegion: kimiRegion, for: provider)
        if saved { credential = "" }
        status = saved ? (value.isEmpty ? copy.text("已移除", "Removed") : copy.text("已保存", "Saved"))
            : copy.text("无法更新钥匙串。", "Could not update the keychain.")
    }
}

private func quotaConnectionText(_ state: AgentQuotaStore.ConnectionState, copy: AppCopy) -> String {
    switch state {
    case .disabled: copy.text("额度读取已关闭", "Quota reading is off")
    case .checking: copy.text("正在检查额度", "Checking quota")
    case .ready: copy.text("额度已连接", "Quota connected")
    case .needsLogin: copy.text("额度需要登录或授权", "Quota needs sign-in or permission")
    case .unavailable: copy.text("额度暂不可用", "Quota temporarily unavailable")
    }
}
