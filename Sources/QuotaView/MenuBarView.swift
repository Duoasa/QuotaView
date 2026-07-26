import AppKit
import QuotaViewCore
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var store: CodexStatusStore
    @ObservedObject var preferences: AppPreferences

    @Environment(\.openSettings) private var openSettings

    @State private var route: Route = .overview
    @State private var hasAcknowledgedReset = false
    @State private var isShowingFinalConfirmation = false
    @State private var demoResultMessage: String?

    private enum Route {
        case overview
        case resetDetails
    }

    private struct MetricItem: Identifiable {
        let id: String
        let icon: String
        let title: String
        let value: String
    }

    private var copy: AppCopy { preferences.copy }

    var body: some View {
        VStack(spacing: 0) {
            if route == .overview {
                header
            } else {
                resetHeader
            }

            Divider()
                .opacity(0.55)

            Group {
                if let snapshot = store.snapshot {
                    if route == .overview {
                        snapshotContent(snapshot)
                    } else {
                        resetDetailsContent(snapshot)
                    }
                } else if let error = store.errorMessage {
                    errorContent(error)
                } else {
                    loadingContent
                }
            }
            .padding(18)

            Divider()
                .opacity(0.55)

            if route == .overview {
                footer
            } else {
                resetFooter
            }
        }
        .frame(width: 344)
        .quotaViewMenuContentSurface()
        .animation(.easeInOut(duration: 0.18), value: route)
        .alert(
            copy.text(
                "最后确认刷新额度？",
                "Final confirmation to reset quota?"
            ),
            isPresented: $isShowingFinalConfirmation
        ) {
            Button(copy.text("取消", "Cancel"), role: .cancel) {}
            Button(
                copy.text("确认演示刷新", "Confirm demo reset"),
                role: .destructive
            ) {
                completeDemoReset()
            }
        } message: {
            Text(
                copy.text(
                    "正式接入后，此操作将消耗 1 次刷新机会且无法撤销。"
                    + "当前版本仅演示流程，不会调用真实接口。",
                    "Once the live integration is enabled, this action will "
                    + "consume one reset credit and cannot be undone. "
                    + "This version only demonstrates the flow and never "
                    + "calls the live endpoint."
                )
            )
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image("QuotaViewAppIcon")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 34, height: 34)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("QuotaView")
                    .font(.system(size: 14, weight: .semibold))

                Text(copy.text("本机 Codex 用量监控", "Local Codex quota monitor"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            statusBadge
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private var resetHeader: some View {
        HStack(spacing: 10) {
            Button {
                returnToOverview()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(copy.text("返回用量概览", "Return to quota overview"))

            Text(copy.text("额度刷新", "Quota reset"))
                .font(.system(size: 14, weight: .semibold))

            Spacer()

            Label(
                copy.text("演示", "Demo"),
                systemImage: "shield.lefthalf.filled"
            )
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .codexGlass(
                    cornerRadius: 999,
                    tintOpacity: 0.08
                )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    @ViewBuilder
    private var statusBadge: some View {
        if let snapshot = store.snapshot {
            Label(
                availabilityLabel(snapshot.availability),
                systemImage: statusSymbol(for: snapshot.availability)
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(statusColor(for: snapshot.availability))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                statusColor(for: snapshot.availability).opacity(0.12),
                in: Capsule()
            )
        } else if store.errorMessage != nil {
            Label(copy.text("离线", "Offline"), systemImage: "wifi.slash")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(.red.opacity(0.12), in: Capsule())
        } else {
            ProgressView()
                .controlSize(.small)
        }
    }

    private func snapshotContent(_ snapshot: CodexSnapshot) -> some View {
        let metrics = metricItems(snapshot)

        return VStack(spacing: 18) {
            if preferences.showUsageSummary {
                HStack(spacing: 20) {
                    UsageRing(
                        usedPercent: snapshot.usedPercent,
                        availability: snapshot.availability,
                        copy: copy
                    )

                    VStack(alignment: .leading, spacing: 7) {
                        Text(copy.text("本周期剩余", "Remaining this cycle"))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("\(snapshot.remainingPercent)%")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())

                        HStack(spacing: 5) {
                            Text(snapshot.planType.uppercased())
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(CodexTheme.accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    CodexTheme.accent.opacity(0.1),
                                    in: RoundedRectangle(cornerRadius: 4)
                                )

                            if let window = windowLabel(
                                snapshot.windowDurationMinutes
                            ) {
                                Text(window)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }
            }

            if !metrics.isEmpty {
                VStack(spacing: 0) {
                    ForEach(
                        Array(metrics.enumerated()),
                        id: \.element.id
                    ) { index, metric in
                        if index > 0 {
                            Divider().padding(.leading, 30)
                        }

                        metricRow(
                            icon: metric.icon,
                            title: metric.title,
                            value: metric.value
                        )
                    }
                }
                .padding(.horizontal, 4)
            }

            if preferences.showResetAction {
                resetCreditsEntry(snapshot)
            }

            if let error = store.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Text(
                    copy.text(
                        "更新于 \(updatedTime(snapshot.lastUpdatedAt))",
                        "Updated \(updatedTime(snapshot.lastUpdatedAt))"
                    )
                )
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer()

                if store.isRefreshing {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
        }
    }

    private func resetCreditsEntry(_ snapshot: CodexSnapshot) -> some View {
        Button {
            openResetDetails()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.counterclockwise.circle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(CodexTheme.accent)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(copy.text("额度刷新", "Quota reset"))
                        .font(.subheadline.weight(.semibold))

                    Text(
                        copy.text(
                            "重置符合条件的 Codex 使用周期",
                            "Reset an eligible Codex usage cycle"
                        )
                    )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Text(
                    copy.text(
                        "\(snapshot.availableResetCredits) 次",
                        "\(snapshot.availableResetCredits) available"
                    )
                )
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(CodexTheme.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        CodexTheme.accent.opacity(0.14),
                        in: Capsule()
                    )

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .codexGlass(
            cornerRadius: 12,
            interactive: true,
            tintOpacity: 0.12
        )
        .accessibilityLabel(
            copy.text(
                "额度刷新，\(snapshot.availableResetCredits) 次可用，打开详情",
                "Quota reset, \(snapshot.availableResetCredits) available, open details"
            )
        )
    }

    private func resetDetailsContent(_ snapshot: CodexSnapshot) -> some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Image(systemName: "ticket.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(CodexTheme.accent)
                    .padding(.bottom, 2)

                Text("\(snapshot.availableResetCredits)")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(CodexTheme.accent)
                    .monospacedDigit()
                    .contentTransition(.numericText())

                Text(copy.text("次可用", "reset credits available"))
                    .font(.headline)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                copy.text(
                    "可用额度刷新次数 \(snapshot.availableResetCredits)",
                    "\(snapshot.availableResetCredits) quota reset credits available"
                )
            )

            HStack {
                Text(copy.text("当前额度可用", "Current quota available"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(snapshot.remainingPercent)%")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(CodexTheme.accent)
                    .monospacedDigit()
            }

            Divider()

            VStack(alignment: .leading, spacing: 11) {
                Text(copy.text("刷新前请确认", "Before resetting"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                resetFact(
                    icon: "arrow.counterclockwise",
                    text: copy.text(
                        "将消耗 1 次刷新机会",
                        "Consumes one reset credit"
                    )
                )
                resetFact(
                    icon: "clock.arrow.circlepath",
                    text: copy.text(
                        "恢复符合条件的 Codex 使用额度",
                        "Restores an eligible Codex quota"
                    )
                )
                resetFact(
                    icon: "nosign",
                    text: copy.text(
                        "正式刷新操作无法撤销",
                        "A live reset cannot be undone"
                    )
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle(
                copy.text(
                    "我已阅读并理解以上说明",
                    "I have read and understand the information above"
                ),
                isOn: $hasAcknowledgedReset
            )
            .toggleStyle(.checkbox)
            .font(.caption)
            .disabled(!snapshot.canUseResetCredit)

            Button {
                isShowingFinalConfirmation = true
            } label: {
                HStack {
                    Spacer()
                    Text(copy.text("使用 1 次刷新", "Use one reset"))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            .codexProminentButtonStyle()
            .controlSize(.large)
            .disabled(
                !snapshot.canUseResetCredit
                || !hasAcknowledgedReset
            )

            Text(resetActionCaption(snapshot))
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let demoResultMessage {
                Label(demoResultMessage, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
            }

        }
        .frame(maxWidth: .infinity, minHeight: 360, alignment: .top)
    }

    private func resetFact(icon: String, text: String) -> some View {
        Label {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CodexTheme.accent)
                .frame(width: 18)
        }
    }

    private var loadingContent: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            Text(copy.text("正在连接 Codex…", "Connecting to Codex…"))
                .font(.subheadline)
            Text(
                copy.text(
                    "首次读取可能需要 20–30 秒",
                    "The first request may take 20–30 seconds"
                )
            )
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 250)
    }

    private func errorContent(_ error: String) -> some View {
        VStack(spacing: 13) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 30))
                .foregroundStyle(.orange)

            Text(copy.text("无法读取 Codex", "Unable to read Codex"))
                .font(.headline)

            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(copy.text("重新连接", "Reconnect")) {
                Task {
                    await store.refresh()
                }
            }
            .codexProminentButtonStyle()
        }
        .frame(maxWidth: .infinity, minHeight: 250)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                Task {
                    await store.refresh()
                }
            } label: {
                Label(
                    copy.text("同步数据", "Sync"),
                    systemImage: "arrow.clockwise"
                )
            }
            .disabled(store.isRefreshing)

            Button {
                openCodex()
            } label: {
                Label(
                    copy.text("打开 Codex", "Open Codex"),
                    systemImage: "arrow.up.forward.app"
                )
            }

            Spacer()

            Button {
                showSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .help(copy.text("打开设置", "Open Settings"))

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .help(copy.text("退出 QuotaView", "Quit QuotaView"))
        }
        .codexToolbarButtonStyle()
        .font(.caption)
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private var resetFooter: some View {
        HStack(spacing: 10) {
            Button {
                Task {
                    await store.refresh()
                }
            } label: {
                Label(
                    copy.text("同步数据", "Sync"),
                    systemImage: "arrow.clockwise"
                )
            }
            .disabled(store.isRefreshing)

            Spacer()

            if store.isRefreshing {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Label(
                    copy.text(
                        "演示模式 · 不消耗次数",
                        "Demo mode · No credits consumed"
                    ),
                    systemImage: "info.circle"
                )
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            }

            Button {
                showSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .help(copy.text("打开设置", "Open Settings"))
        }
        .codexToolbarButtonStyle()
        .font(.caption)
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private func metricRow(
        icon: String,
        title: String,
        value: String
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CodexTheme.accent)
                .frame(width: 20)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(.vertical, 10)
    }

    private func metricItems(_ snapshot: CodexSnapshot) -> [MetricItem] {
        var items: [MetricItem] = []

        if preferences.showNextReset {
            items.append(
                MetricItem(
                    id: "nextReset",
                    icon: "arrow.clockwise",
                    title: copy.text("下次刷新", "Next reset"),
                    value: resetCountdown(snapshot.resetsAt)
                )
            )
        }

        if preferences.showCreditBalance {
            items.append(
                MetricItem(
                    id: "credits",
                    icon: "creditcard.fill",
                    title: copy.text("Credits 余额", "Credits balance"),
                    value: creditLabel(snapshot)
                )
            )
        }

        if preferences.showDailyTokens {
            items.append(
                MetricItem(
                    id: "dailyTokens",
                    icon: "textformat.123",
                    title: recentUsageTitle(snapshot.recentDailyDate),
                    value: tokenLabel(snapshot.recentDailyTokens)
                )
            )
        }

        if preferences.showLifetimeTokens {
            items.append(
                MetricItem(
                    id: "lifetimeTokens",
                    icon: "sum",
                    title: copy.text("累计 Token", "Lifetime tokens"),
                    value: tokenLabel(snapshot.lifetimeTokens)
                )
            )
        }

        return items
    }

    private func statusColor(
        for availability: CodexSnapshot.Availability
    ) -> Color {
        switch availability {
        case .ready: .green
        case .limited: .orange
        case .exhausted: .red
        }
    }

    private func statusSymbol(
        for availability: CodexSnapshot.Availability
    ) -> String {
        switch availability {
        case .ready: "checkmark.circle.fill"
        case .limited: "exclamationmark.circle.fill"
        case .exhausted: "xmark.octagon.fill"
        }
    }

    private func availabilityLabel(
        _ availability: CodexSnapshot.Availability
    ) -> String {
        switch availability {
        case .ready: copy.text("可用", "Available")
        case .limited: copy.text("受限", "Limited")
        case .exhausted: copy.text("已用尽", "Exhausted")
        }
    }

    private func windowLabel(_ minutes: Int?) -> String? {
        guard let minutes else { return nil }
        if minutes % 10_080 == 0 {
            return copy.text(
                "\(minutes / 10_080) 周窗口",
                "\(minutes / 10_080)-week window"
            )
        }
        if minutes % 1_440 == 0 {
            return copy.text(
                "\(minutes / 1_440) 天窗口",
                "\(minutes / 1_440)-day window"
            )
        }
        if minutes % 60 == 0 {
            return copy.text(
                "\(minutes / 60) 小时窗口",
                "\(minutes / 60)-hour window"
            )
        }
        return copy.text(
            "\(minutes) 分钟窗口",
            "\(minutes)-minute window"
        )
    }

    private func creditLabel(_ snapshot: CodexSnapshot) -> String {
        if snapshot.unlimitedCredits {
            return copy.text("无限", "Unlimited")
        }
        return snapshot.creditBalance ?? copy.text("不可用", "Unavailable")
    }

    private func recentUsageTitle(_ date: String?) -> String {
        guard let date else {
            return copy.text("最近一天 Token", "Recent daily tokens")
        }
        return copy.text("\(date) Token", "\(date) tokens")
    }

    private func tokenLabel(_ tokens: Int64?) -> String {
        guard let tokens else { return "—" }
        return tokens.formatted(
            .number
                .notation(.compactName)
                .locale(preferences.locale)
        )
    }

    private func resetCountdown(_ resetDate: Date?) -> String {
        guard let resetDate else {
            return copy.text("未提供", "Unavailable")
        }

        let remaining = Int(resetDate.timeIntervalSinceNow)
        guard remaining > 0 else {
            return copy.text("即将刷新", "Resetting soon")
        }

        let days = remaining / 86_400
        let hours = (remaining % 86_400) / 3_600
        let minutes = (remaining % 3_600) / 60

        if days > 0 {
            return copy.text(
                "\(days) 天 \(hours) 小时",
                "\(days)d \(hours)h"
            )
        }
        if hours > 0 {
            return copy.text(
                "\(hours) 小时 \(minutes) 分",
                "\(hours)h \(minutes)m"
            )
        }
        return copy.text(
            "\(max(minutes, 1)) 分钟",
            "\(max(minutes, 1))m"
        )
    }

    private func resetActionCaption(_ snapshot: CodexSnapshot) -> String {
        guard snapshot.canUseResetCredit else {
            return copy.text(
                "当前没有可用刷新次数",
                "No reset credits are currently available"
            )
        }
        return copy.text(
            "刷新后剩余 \(snapshot.availableResetCreditsAfterOne) 次",
            "\(snapshot.availableResetCreditsAfterOne) will remain after reset"
        )
    }

    private func updatedTime(_ date: Date) -> String {
        date.formatted(
            Date.FormatStyle(date: .omitted, time: .shortened)
                .locale(preferences.locale)
        )
    }

    private func openResetDetails() {
        hasAcknowledgedReset = false
        demoResultMessage = nil
        route = .resetDetails
    }

    private func returnToOverview() {
        hasAcknowledgedReset = false
        isShowingFinalConfirmation = false
        demoResultMessage = nil
        route = .overview
    }

    private func completeDemoReset() {
        // The live account/rateLimitResetCredit/consume call is intentionally
        // deferred until the product flow is complete.
        hasAcknowledgedReset = false
        demoResultMessage = copy.text(
            "演示确认完成；未调用真实接口，也未消耗刷新次数。",
            "Demo confirmation completed. No live endpoint was called "
            + "and no reset credit was consumed."
        )
    }

    private func showSettings() {
        openSettings()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func openCodex() {
        let chatGPTURL = URL(fileURLWithPath: "/Applications/ChatGPT.app")
        guard FileManager.default.fileExists(atPath: chatGPTURL.path) else {
            return
        }

        NSWorkspace.shared.openApplication(
            at: chatGPTURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
}

private struct UsageRing: View {
    let usedPercent: Int
    let availability: CodexSnapshot.Availability
    let copy: AppCopy

    private var color: Color {
        switch availability {
        case .ready: CodexTheme.accent
        case .limited: .orange
        case .exhausted: .red
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 9)

            Circle()
                .trim(from: 0, to: CGFloat(usedPercent) / 100)
                .stroke(
                    color,
                    style: StrokeStyle(
                        lineWidth: 9,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 1) {
                Text("\(usedPercent)%")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(copy.text("已用", "Used"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 92, height: 92)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            copy.text(
                "已使用 \(usedPercent)%",
                "\(usedPercent)% used"
            )
        )
    }
}
