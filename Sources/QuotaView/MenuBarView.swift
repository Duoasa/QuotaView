import AppKit
import QuotaViewCore
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var store: CodexStatusStore

    @State private var route: Route = .overview
    @State private var hasAcknowledgedReset = false
    @State private var isShowingFinalConfirmation = false
    @State private var demoResultMessage: String?

    private enum Route {
        case overview
        case resetDetails
    }

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
        .background(.regularMaterial)
        .animation(.easeInOut(duration: 0.18), value: route)
        .alert(
            "最后确认刷新额度？",
            isPresented: $isShowingFinalConfirmation
        ) {
            Button("取消", role: .cancel) {}
            Button("确认演示刷新", role: .destructive) {
                completeDemoReset()
            }
        } message: {
            Text(
                "正式接入后，此操作将消耗 1 次刷新机会且无法撤销。"
                + "当前版本仅演示流程，不会调用真实接口。"
            )
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.indigo, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Image(systemName: "terminal.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text("QuotaView")
                    .font(.system(size: 14, weight: .semibold))

                Text("本机 Codex 用量监控")
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
            .help("返回用量概览")

            Text("额度刷新")
                .font(.system(size: 14, weight: .semibold))

            Spacer()

            Label("演示", systemImage: "shield.lefthalf.filled")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    @ViewBuilder
    private var statusBadge: some View {
        if let snapshot = store.snapshot {
            Label(
                snapshot.availability.displayName,
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
            Label("离线", systemImage: "wifi.slash")
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
        VStack(spacing: 18) {
            HStack(spacing: 20) {
                UsageRing(
                    usedPercent: snapshot.usedPercent,
                    availability: snapshot.availability
                )

                VStack(alignment: .leading, spacing: 7) {
                    Text("本周期剩余")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("\(snapshot.remainingPercent)%")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())

                    HStack(spacing: 5) {
                        Text(snapshot.planType.uppercased())
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.indigo)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))

                        if let window = windowLabel(snapshot.windowDurationMinutes) {
                            Text(window)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer(minLength: 0)
            }

            VStack(spacing: 0) {
                metricRow(
                    icon: "arrow.clockwise",
                    title: "下次刷新",
                    value: resetCountdown(snapshot.resetsAt)
                )

                Divider().padding(.leading, 30)

                metricRow(
                    icon: "creditcard.fill",
                    title: "Credits 余额",
                    value: creditLabel(snapshot)
                )

                Divider().padding(.leading, 30)

                metricRow(
                    icon: "textformat.123",
                    title: recentUsageTitle(snapshot.recentDailyDate),
                    value: tokenLabel(snapshot.recentDailyTokens)
                )

                Divider().padding(.leading, 30)

                metricRow(
                    icon: "sum",
                    title: "累计 Token",
                    value: tokenLabel(snapshot.lifetimeTokens)
                )
            }
            .padding(.horizontal, 12)
            .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))

            resetCreditsEntry(snapshot)

            if let error = store.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Text("更新于 \(snapshot.lastUpdatedAt.formatted(date: .omitted, time: .shortened))")
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
                    .foregroundStyle(.indigo)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text("额度刷新")
                        .font(.subheadline.weight(.semibold))

                    Text("重置符合条件的 Codex 使用周期")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Text("\(snapshot.availableResetCredits) 次")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.indigo)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.indigo.opacity(0.14), in: Capsule())

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.indigo.opacity(0.18), lineWidth: 1)
        }
        .accessibilityLabel(
            "额度刷新，\(snapshot.availableResetCredits) 次可用，打开详情"
        )
    }

    private func resetDetailsContent(_ snapshot: CodexSnapshot) -> some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Image(systemName: "ticket.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.indigo)
                    .padding(.bottom, 2)

                Text("\(snapshot.availableResetCredits)")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(.indigo)
                    .monospacedDigit()
                    .contentTransition(.numericText())

                Text("次可用")
                    .font(.headline)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "可用额度刷新次数 \(snapshot.availableResetCredits)"
            )

            HStack {
                Text("当前额度可用")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(snapshot.remainingPercent)%")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.indigo)
                    .monospacedDigit()
            }

            Divider()

            VStack(alignment: .leading, spacing: 11) {
                Text("刷新前请确认")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                resetFact(
                    icon: "arrow.counterclockwise",
                    text: "将消耗 1 次刷新机会"
                )
                resetFact(
                    icon: "clock.arrow.circlepath",
                    text: "恢复符合条件的 Codex 使用额度"
                )
                resetFact(
                    icon: "nosign",
                    text: "正式刷新操作无法撤销"
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle(
                "我已阅读并理解以上说明",
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
                    Text("使用 1 次刷新")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.indigo)
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
                .foregroundStyle(.indigo)
                .frame(width: 18)
        }
    }

    private var loadingContent: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            Text("正在连接 Codex…")
                .font(.subheadline)
            Text("首次读取可能需要 20–30 秒")
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

            Text("无法读取 Codex")
                .font(.headline)

            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button("重新连接") {
                Task {
                    await store.refresh()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 250)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                Task {
                    await store.refresh()
                }
            } label: {
                Label("同步数据", systemImage: "arrow.clockwise")
            }
            .disabled(store.isRefreshing)

            Button {
                openCodex()
            } label: {
                Label("打开 Codex", systemImage: "arrow.up.forward.app")
            }

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .help("退出 QuotaView")
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private var resetFooter: some View {
        HStack {
            Button {
                Task {
                    await store.refresh()
                }
            } label: {
                Label("同步数据", systemImage: "arrow.clockwise")
            }
            .disabled(store.isRefreshing)

            Spacer()

            if store.isRefreshing {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Label(
                    "演示模式 · 不消耗次数",
                    systemImage: "info.circle"
                )
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            }
        }
        .buttonStyle(.borderless)
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
                .foregroundStyle(.indigo)
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

    private func windowLabel(_ minutes: Int?) -> String? {
        guard let minutes else { return nil }
        if minutes % 10_080 == 0 {
            return "\(minutes / 10_080) 周窗口"
        }
        if minutes % 1_440 == 0 {
            return "\(minutes / 1_440) 天窗口"
        }
        if minutes % 60 == 0 {
            return "\(minutes / 60) 小时窗口"
        }
        return "\(minutes) 分钟窗口"
    }

    private func creditLabel(_ snapshot: CodexSnapshot) -> String {
        if snapshot.unlimitedCredits {
            return "无限"
        }
        return snapshot.creditBalance ?? "不可用"
    }

    private func recentUsageTitle(_ date: String?) -> String {
        guard let date else { return "最近一天 Token" }
        return "\(date) Token"
    }

    private func tokenLabel(_ tokens: Int64?) -> String {
        guard let tokens else { return "—" }
        return tokens.formatted(.number.notation(.compactName))
    }

    private func resetCountdown(_ resetDate: Date?) -> String {
        guard let resetDate else { return "未提供" }

        let remaining = Int(resetDate.timeIntervalSinceNow)
        guard remaining > 0 else { return "即将刷新" }

        let days = remaining / 86_400
        let hours = (remaining % 86_400) / 3_600
        let minutes = (remaining % 3_600) / 60

        if days > 0 {
            return "\(days) 天 \(hours) 小时"
        }
        if hours > 0 {
            return "\(hours) 小时 \(minutes) 分"
        }
        return "\(max(minutes, 1)) 分钟"
    }

    private func resetActionCaption(_ snapshot: CodexSnapshot) -> String {
        guard snapshot.canUseResetCredit else {
            return "当前没有可用刷新次数"
        }
        return "刷新后剩余 \(snapshot.availableResetCreditsAfterOne) 次"
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
        demoResultMessage = "演示确认完成；未调用真实接口，也未消耗刷新次数。"
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

    private var color: Color {
        switch availability {
        case .ready: .indigo
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
                Text("已用")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 92, height: 92)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("已使用 \(usedPercent)%")
    }
}
