import SwiftUI
import QuotaViewCore

struct ClaudeCodeConnectionSettings: View {
    @ObservedObject var runtime: ClaudeCodeRuntime
    @ObservedObject var preferences: AppPreferences
    @State private var connectionDetailsExpanded = false

    private var copy: AppCopy { preferences.copy }

    var body: some View {
        NativeSettingsCard {
            NativeSettingsRow(title: copy.text("连接 Claude Code", "Connect Claude Code"), subtitle: statusSubtitle) {
                HStack(spacing: 10) {
                    NativeSettingsConnectionStatus(title: statusTitle, color: statusColor)
                    if case .failed = runtime.status {
                        Button(copy.text("重试", "Retry")) { runtime.retry() }
                            .controlSize(.small)
                    }
                    if case .configuring = runtime.status { ProgressView().controlSize(.small) }
                    Toggle(copy.text("连接 Claude Code", "Connect Claude Code"), isOn: $preferences.claudeCodeEnabled)
                        .labelsHidden().toggleStyle(.switch).tint(Color(nsColor: .secondaryLabelColor)).controlSize(.small)
                }
            }
            NativeSettingsDivider()
            NativeSettingsRow(title: copy.text("配置目录", "Configuration directory"), subtitle: runtime.configurationDirectory.path) {
                HStack(spacing: 8) {
                    Button(copy.text("显示设置文件", "Show Settings File")) { runtime.revealSettingsFile() }
                        .disabled(!runtime.installerState.settingsExist)
                }.controlSize(.small)
            }
            NativeSettingsDivider()
            NativeSettingsRow(
                title: copy.text("在灵动岛处理权限请求", "Handle permission prompts in the island"),
                subtitle: copy.text("关闭后灵动岛只显示提醒，请在终端确认。", "When off, the island only shows a reminder; confirm in the terminal.")
            ) {
                Toggle(copy.text("在灵动岛处理权限请求", "Handle permission prompts in the island"),
                       isOn: $preferences.claudeCodeInteractiveApprovals)
                    .labelsHidden().toggleStyle(.switch).tint(Color(nsColor: .secondaryLabelColor)).controlSize(.small)
                    .disabled(!preferences.claudeCodeEnabled)
            }
            NativeSettingsDivider()
            NativeSettingsRow(
                title: copy.text("读取官方用量窗口", "Read official usage windows"),
                subtitle: copy.text("通过 Claude Code 状态栏读取 5 小时与每周用量，原有状态栏输出保持不变。",
                                    "Reads 5-hour and weekly usage through the Claude Code status line; your existing status line output is kept.")
            ) {
                Toggle(copy.text("读取官方用量窗口", "Read official usage windows"), isOn: $preferences.claudeCodeStatusLineEnabled)
                    .labelsHidden().toggleStyle(.switch).tint(Color(nsColor: .secondaryLabelColor)).controlSize(.small)
                    .disabled(!preferences.claudeCodeEnabled)
            }
            NativeSettingsDivider()
            NativeSettingsConnectionDetails(copy: copy, isExpanded: $connectionDetailsExpanded) {
                NativeSettingsNote(text: copy.text(
                    "启用后在 settings.json 中添加 QuotaView 的 Hook，首次修改前自动备份。停用时只移除这些条目，恢复原有状态栏。任务与会话记录仅在本机读取。",
                    "Adds QuotaView hooks to settings.json with a backup before the first change. Disabling removes only these entries and restores your status line. Tasks and transcripts are read locally."
                ), horizontalPadding: 0)
            }
        }
    }

    private var statusTitle: String {
        switch runtime.status {
        case .disabled: copy.text("已停用", "Disabled")
        case .configuring: copy.text("配置中", "Configuring")
        case .awaitingEvent: copy.text("等待会话", "Awaiting session")
        case .connected: copy.text("已连接", "Connected")
        case .failed: copy.text("需要处理", "Needs Attention")
        }
    }
    private var statusSubtitle: String {
        switch runtime.status {
        case .disabled: copy.text("在灵动岛显示 Claude Code 任务、处理权限请求并统计用量。",
                                  "Show Claude Code tasks in the island, handle permission prompts and track usage.")
        case .configuring: copy.text("正在更新 Claude Code 设置…", "Updating Claude Code settings…")
        case .awaitingEvent: copy.text("新的或重启后的 Claude Code 会话会自动连接。", "New or restarted Claude Code sessions connect automatically.")
        case .connected: copy.text("已收到 Claude Code 事件。", "Receiving Claude Code events.")
        case .failed(let message): message
        }
    }
    private var statusColor: Color {
        switch runtime.status {
        case .connected: Color(nsColor: .systemGreen)
        case .awaitingEvent, .configuring: Color(nsColor: .systemOrange)
        case .failed: Color(nsColor: .systemRed)
        case .disabled: Color(nsColor: .tertiaryLabelColor)
        }
    }
}

/// Connection summary for the development mainline's existing settings header.
struct ClaudeCodeConnectionStage: View {
    @ObservedObject var runtime: ClaudeCodeRuntime
    let copy: AppCopy

    private var presentation: (String, Color) {
        switch runtime.status {
        case .disabled: (copy.text("已停用", "Disabled"), .secondary)
        case .configuring: (copy.text("配置中", "Configuring"), .orange)
        case .awaitingEvent: (copy.text("等待会话", "Awaiting session"), .orange)
        case .connected: (copy.text("已连接", "Connected"), .green)
        case .failed: (copy.text("需要处理", "Needs attention"), .red)
        }
    }

    var body: some View {
        SettingsConnectionSummary(provider: .claudeCode,
            status: presentation.0, color: presentation.1,
            detail: copy.text("会话自动连接", "Automatic session connection"))
    }
}
