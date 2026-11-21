import ApplicationServices
import SwiftUI

struct AgentIntegrationSettings<Details: View>: View {
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var codex: CodexActivityRuntime
    @ObservedObject var claude: ClaudeCodeRuntime
    @ObservedObject var dsh: NativeAgentRuntime
    @ObservedObject var kimi: NativeAgentRuntime
    @ObservedObject var cursor: NativeAgentRuntime
    @ObservedObject var geminiCLI: NativeAgentRuntime
    @ObservedObject var openCode: NativeAgentRuntime
    @ObservedObject var antigravity: NativeAgentRuntime
    @ObservedObject var copilotCLI: NativeAgentRuntime
    @ObservedObject var devinDesktop: NativeAgentRuntime
    @ObservedObject var devinCLI: NativeAgentRuntime
    let selected: IslandAgentProvider?
    let openAgent: (IslandAgentProvider) -> Void
    let codexDetails: () -> Details
    private var copy: AppCopy { preferences.copy }

    init(preferences: AppPreferences, runtime: CodexActivityRuntime, selected: IslandAgentProvider?,
         openAgent: @escaping (IslandAgentProvider) -> Void, @ViewBuilder codexDetails: @escaping () -> Details) {
        self.selected = selected; self.openAgent = openAgent
        self.preferences = preferences; codex = runtime; claude = runtime.claudeCode
        dsh = runtime.dsh; kimi = runtime.kimiCode; self.codexDetails = codexDetails
        cursor = runtime.cursor; geminiCLI = runtime.geminiCLI; openCode = runtime.openCode; antigravity = runtime.antigravity; copilotCLI = runtime.copilotCLI
        devinDesktop = runtime.devinDesktop; devinCLI = runtime.devinCLI
    }
    var body: some View {
        if let selected {
            let enabled = integrationBinding(selected)
            let title = copy.text("启用接入", "Enable integration")
            NativeSettingsCard {
                NativeSettingsRow(title: title, subtitle: presentation(selected, enabled: enabled.wrappedValue)) {
                    Toggle(title, isOn: enabled).labelsHidden().toggleStyle(.switch)
                }
                NativeSettingsDivider()
                if selected == .codex {
                    codexDetails().disabled(!enabled.wrappedValue)
                } else if selected == .claudeCode {
                    ClaudeCodeConnectionSettings(runtime: claude, preferences: preferences)
                } else if let runtime = nativeRuntime(selected) {
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
                    NativeSettingsCard {
                        ForEach(IslandAgentProvider.allCases, id: \.self) { provider in
                            if provider != IslandAgentProvider.allCases.first {
                                NativeSettingsDivider()
                            }
                            row(provider)
                        }
                    }
                }
            }
        }
    }

    private func row(_ provider: IslandAgentProvider) -> some View {
        let status = presentation(provider, enabled: integrationBinding(provider).wrappedValue)
        return Button { openAgent(provider) } label: {
            SettingsListRow(title: provider.displayName, subtitle: status) {
                AgentSettingsIcon(provider: provider)
            } control: {
                Image(systemName: "chevron.forward")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .help(copy.text("显示连接设置", "Show connection settings"))
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

    private func presentation(_ provider: IslandAgentProvider, enabled: Bool) -> String {
        let connected = copy.text("已连接", "Connected")
        let waiting = copy.text("等待会话", "Waiting")
        let configuring = copy.text("配置中", "Configuring")
        let failed = copy.text("需要处理", "Needs attention")
        if let runtime = nativeRuntime(provider) {
            if runtime.status == .failed { return failed }
            if runtime.status == .configuring { return configuring }
        }
        if provider == .claudeCode {
            if case .failed = claude.status { return failed }
            if case .configuring = claude.status { return configuring }
        }
        if !enabled { return copy.text("已停用", "Disabled") }
        switch provider {
        case .codex:
            if codex.isNativeActivityConnected { return connected }
            return codex.localHealth.hasReadError ? failed : waiting
        case .claudeCode:
            switch claude.status { case .connected: return connected; case .configuring: return configuring
            case .failed: return failed; default: return waiting }
        case .dsh, .kimiCode, .cursor, .geminiCLI, .openCode, .antigravity, .copilotCLI, .devinDesktop, .devinCLI:
            let runtime = nativeRuntime(provider)!
            switch runtime.status { case .connected: return connected; case .configuring: return configuring
            case .failed: return failed; default: return waiting }
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
            if runtime.provider == .antigravity {
                NativeSettingsRow(title: copy.text("在灵动岛处理权限请求", "Handle permission prompts in the island"),
                    subtitle: copy.text("运行命令或读写文件前，可在岛内允许一次、拒绝或交回 Antigravity。", "Review commands, file reads, and edits before execution, or hand them back to Antigravity.")) {
                    Toggle(copy.text("在灵动岛处理权限请求", "Handle permission prompts in the island"), isOn: $preferences.antigravityInteractiveApprovals)
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                        .disabled(!runtime.enabled)
                }
                NativeSettingsDivider()
            }
            if runtime.provider == .dsh {
                NativeSettingsRow(title: copy.text("在灵动岛处理权限请求", "Handle permission prompts in the island"),
                    subtitle: copy.text("仅本次允许或拒绝；关闭后在 DSH 中处理。", "Allow once or decline; when off, handle requests in DSH.")) {
                    Toggle(copy.text("在灵动岛处理权限请求", "Handle permission prompts in the island"), isOn: $preferences.dshInteractiveApprovals)
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
            } else {
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

    var body: some View {
        let title = copy.text("辅助功能权限", "Accessibility permission")
        let status = authorized ? copy.text("已授权", "Granted") : copy.text("未授权", "Not granted")
        let hint = copy.text("在系统设置中管理权限", "Manage permission in System Settings")
        NativeSettingsCard {
            NativeSettingsRow(title: title,
                subtitle: copy.text("在官方 DSH 和 Antigravity 中使用「前往对话」需要此权限。",
                                    "Go to conversation requires this permission in the official DSH and Antigravity apps."),
                symbol: "accessibility") {
                HStack(spacing: 8) {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Toggle(title, isOn: Binding(get: { authorized }, set: managePermission))
                        .labelsHidden().toggleStyle(.switch)
                        .accessibilityHint(hint).help(hint)
                }
            }
        }
        .onAppear { authorized = AXIsProcessTrusted() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            authorized = AXIsProcessTrusted()
        }
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

/// Shared app-shaped tiles for the connection list. Brand paths stay original;
/// the tile gives every source the same visual size and continuous corner radius.
private struct AgentSettingsIcon: View {
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
