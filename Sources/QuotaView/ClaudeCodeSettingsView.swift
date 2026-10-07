import SwiftUI
import QuotaViewCore

struct ClaudeCodeConnectionSettings: View {
    @ObservedObject var runtime: ClaudeCodeRuntime
    @ObservedObject var preferences: AppPreferences

    private var copy: AppCopy { preferences.copy }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            NativeSettingsCard {
                NativeSettingsRow(title: copy.text("连接 Claude Code", "Connect Claude Code"), subtitle: statusSubtitle) {
                    HStack(spacing: 10) {
                        HStack(spacing: 8) {
                            Circle().fill(statusColor).frame(width: 5, height: 5).accessibilityHidden(true)
                            Text(statusTitle).font(.caption).foregroundStyle(.secondary)
                        }.accessibilityElement(children: .combine)
                        if case .configuring = runtime.status { ProgressView().controlSize(.small) }
                        Toggle(copy.text("连接 Claude Code", "Connect Claude Code"), isOn: $preferences.claudeCodeEnabled)
                            .labelsHidden().toggleStyle(.switch).tint(Color(nsColor: .secondaryLabelColor)).controlSize(.small)
                    }
                }
                NativeSettingsDivider()
                NativeSettingsRow(title: copy.text("配置目录", "Configuration directory"), subtitle: runtime.configurationDirectory.path) {
                    HStack(spacing: 8) {
                        if case .failed = runtime.status {
                            Button(copy.text("重试", "Retry")) { runtime.retry() }
                        }
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
                NativeSettingsNote(text: copy.text(
                    "启用后 QuotaView 会在 settings.json 中添加自己的 Hook（首次修改前备份为 settings.json.quotaview-backup），停用时只移除这些条目。Hook 事件与会话记录只在本机读取，用于灵动岛与用量统计。",
                    "When enabled, QuotaView adds its own hooks to settings.json (backed up first as settings.json.quotaview-backup) and removes only those entries when disabled. Hook events and transcripts are read locally for the island and usage statistics."))
            }
            if preferences.claudeCodeEnabled { usageCard }
        }
    }

    private var usageCard: some View {
        let usage = runtime.usagePresentation
        return NativeSettingsCard {
            NativeSettingsRow(title: copy.text("套餐", "Plan"), subtitle: copy.text("来自本机 Claude Code 账户资料", "From the local Claude Code profile")) {
                Text(usage?.planName ?? "—").font(.callout).foregroundStyle(.secondary)
            }
            NativeSettingsDivider()
            NativeSettingsRow(title: copy.text("5 小时额度", "5-hour quota"), subtitle: resetText(usage?.fiveHour)) {
                Text(percent(usage?.fiveHour)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            NativeSettingsDivider()
            NativeSettingsRow(title: copy.text("每周额度", "Weekly quota"), subtitle: resetText(usage?.sevenDay)) {
                Text(percent(usage?.sevenDay)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            NativeSettingsDivider()
            NativeSettingsRow(title: copy.text("30 天 Tokens", "30-day tokens"), subtitle: costSubtitle) {
                Text(monthlyTokens.map { CodexActivityTokenUsageFormatter.string(for: $0) } ?? "—")
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            if usage?.quotaState != .available {
                NativeSettingsDivider()
                NativeSettingsNote(text: preferences.claudeCodeStatusLineEnabled
                    ? copy.text("等待 Claude Code 刷新状态栏后显示官方额度。", "Official quota appears after Claude Code refreshes its status line.")
                    : copy.text("开启“读取官方用量窗口”后显示 5 小时与每周额度。", "Turn on “Read official usage windows” to show 5-hour and weekly quota."))
            }
        }
    }

    private var recentDays: [ClaudeCodeUsageSummary.Day] {
        guard let usage = runtime.usage else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.startOfDay(for: ClaudeCodeUsageScanner.localDay(Date()))
        guard let start = calendar.date(byAdding: .day, value: -29, to: today) else { return [] }
        return usage.days.filter { $0.date >= start && $0.date <= today }
    }
    private var monthlyTokens: Int64? { runtime.usage == nil ? nil : recentDays.reduce(0) { $0 + $1.tokens } }
    private var costSubtitle: String {
        guard runtime.usage != nil else { return copy.text("正在读取本机会话记录…", "Reading local transcripts…") }
        let costs = recentDays.map(\.estimatedCost)
        guard !costs.contains(where: { $0 == nil }) else {
            return copy.text("部分模型无公开价格，未估算成本", "Some models have no published price; cost not estimated")
        }
        let total = costs.compactMap { $0 }.reduce(0, +)
        let money = total.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US")))
        return copy.text("估算成本 \(money) · 按公开单价，非账单", "Estimated \(money) at list prices · not a bill")
    }

    private func percent(_ window: CodexQuotaWindowPresentation?) -> String {
        window.map { copy.text("剩余 \($0.remainingPercent)%", "\($0.remainingPercent)% left") } ?? "—"
    }
    private func resetText(_ window: CodexQuotaWindowPresentation?) -> String? {
        guard let date = window?.resetsAt else { return nil }
        return copy.text("重置于 ", "Resets ") + date.formatted(date: .abbreviated, time: .shortened)
    }

    private var statusTitle: String {
        switch runtime.status {
        case .disabled: copy.text("已停用", "Disabled")
        case .configuring: copy.text("配置中", "Configuring")
        case .awaitingEvent: copy.text("已配置", "Configured")
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
            status: presentation.0, color: presentation.1, detail: "Hook → QuotaView")
    }
}
