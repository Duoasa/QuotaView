import SwiftUI

struct AgentIntegrationSettings<Details: View>: View {
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var codex: CodexActivityRuntime
    @ObservedObject var claude: ClaudeCodeRuntime
    @ObservedObject var dsh: NativeAgentRuntime
    @ObservedObject var kimi: NativeAgentRuntime
    @State private var expanded: IslandAgentProvider?
    let codexDetails: () -> Details
    private var copy: AppCopy { preferences.copy }

    init(preferences: AppPreferences, runtime: CodexActivityRuntime, @ViewBuilder codexDetails: @escaping () -> Details) {
        self.preferences = preferences; codex = runtime; claude = runtime.claudeCode
        dsh = runtime.dsh; kimi = runtime.kimiCode; self.codexDetails = codexDetails
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            providerGroup(.codex, isOn: $preferences.codexIntegrationEnabled)
            providerGroup(.claudeCode, isOn: $preferences.claudeCodeEnabled)
            providerGroup(.dsh, isOn: $preferences.dshEnabled)
            providerGroup(.kimiCode, isOn: $preferences.kimiCodeEnabled)
        }
    }
    private func providerGroup(_ provider: IslandAgentProvider, isOn: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            NativeSettingsCard { row(provider, isOn: isOn) }
            if expanded == provider {
                Group {
                    switch provider {
                    case .codex: codexDetails().disabled(!preferences.codexIntegrationEnabled)
                    case .claudeCode: ClaudeCodeConnectionSettings(runtime: claude, preferences: preferences)
                    case .dsh: nativeDetails(dsh)
                    case .kimiCode: nativeDetails(kimi)
                    }
                }.padding(.leading, 22)
            }
        }
    }
    private func row(_ provider: IslandAgentProvider, isOn: Binding<Bool>) -> some View {
        let state = presentation(provider, enabled: isOn.wrappedValue)
        return HStack(spacing: 12) {
            Button { expanded = expanded == provider ? nil : provider } label: {
                HStack(spacing: 10) {
                    Image(systemName: expanded == provider ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                        .frame(width: 12, height: 22).accessibilityHidden(true)
                    AgentSettingsIcon(provider: provider)
                    Text(provider.displayName).font(.system(size: 13, weight: .medium))
                    Spacer(minLength: 8)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
                .help(copy.text("显示连接设置", "Show connection settings"))
                .accessibilityValue(expanded == provider ? copy.text("已展开", "Expanded") : copy.text("已收起", "Collapsed"))
            Label(state.title, systemImage: state.symbol)
                .font(.system(size: 12, weight: .medium)).foregroundStyle(state.color)
                .fixedSize()
                .frame(width: preferences.resolvedLanguage == .english ? 116 : 76, alignment: .leading)
            Toggle(provider.displayName, isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.mini)
                .tint(Color(nsColor: .secondaryLabelColor))
        }
        .frame(minHeight: 40).padding(.horizontal, 12)
    }
    private func presentation(_ provider: IslandAgentProvider, enabled: Bool) -> (title: String, symbol: String, color: Color) {
        let connected = (copy.text("已连接", "Connected"), "checkmark.circle.fill", Color(nsColor: .systemGreen))
        let waiting = (copy.text("等待会话", "Waiting"), "clock", Color(nsColor: .secondaryLabelColor))
        let configuring = (copy.text("配置中", "Configuring"), "arrow.triangle.2.circlepath", Color(nsColor: .systemOrange))
        let failed = (copy.text("需要处理", "Needs attention"), "exclamationmark.circle.fill", Color(nsColor: .systemOrange))
        if provider == .dsh || provider == .kimiCode {
            let runtime = provider == .dsh ? dsh : kimi
            if runtime.status == .failed { return failed }
            if runtime.status == .configuring { return configuring }
        }
        if provider == .claudeCode {
            if case .failed = claude.status { return failed }
            if case .configuring = claude.status { return configuring }
        }
        if !enabled { return (copy.text("已停用", "Disabled"), "minus.circle", .secondary) }
        switch provider {
        case .codex:
            if codex.isNativeActivityConnected { return connected }
            return codex.localHealth.hasReadError ? failed : waiting
        case .claudeCode:
            switch claude.status { case .connected: return connected; case .configuring: return configuring
            case .failed: return failed; default: return waiting }
        case .dsh, .kimiCode:
            let runtime = provider == .dsh ? dsh : kimi
            switch runtime.status { case .connected: return connected; case .configuring: return configuring
            case .failed: return failed; default: return waiting }
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
        NativeSettingsCard {
            if runtime.provider == .dsh {
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
            NativeSettingsDivider()
            NativeSettingsNote(text: runtime.provider == .dsh
                ? copy.text("启用后重启对应客户端；权限请求仍在原客户端确认。",
                            "Restart the client after enabling. Confirm permissions in the original client.")
                : copy.text("启动或重启 Kimi Code 会话以连接；权限请求仍在 Kimi Code 确认。",
                            "Start or restart a Kimi Code session to connect. Confirm permissions in Kimi Code."))
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

/// Shared app-shaped tiles for the connection list. Brand paths stay original;
/// the tile gives every source the same visual size and continuous corner radius.
private struct AgentSettingsIcon: View {
    let provider: IslandAgentProvider
    private var background: Color {
        provider == .claudeCode ? Color(red: 0.96, green: 0.94, blue: 0.90) : .white
    }
    var body: some View {
        ZStack {
            background
            if provider == .codex, let icon = IslandProviderIcon.image {
                // The bundled macOS app icon has 10% transparent canvas on each edge.
                Image(nsImage: icon).resizable().scaledToFit().frame(width: 27.5, height: 27.5)
            } else if let icon = IslandProviderIcon.settingsMark(for: provider) {
                Image(nsImage: icon).resizable().scaledToFit()
                    .frame(width: provider == .kimiCode ? 22 : 16, height: provider == .kimiCode ? 22 : 16)
            }
        }
        .frame(width: 22, height: 22)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
