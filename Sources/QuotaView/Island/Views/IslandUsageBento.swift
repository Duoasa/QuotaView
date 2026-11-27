import AppKit
import SwiftUI
import QuotaViewCore
#if canImport(QuotaViewWidgetContract)
import QuotaViewWidgetContract
#endif

// The badge and the capsule's leading semicircle share the same center.
private struct IslandUsageProviderIcon: View {
    let provider: IslandAgentProvider

    var body: some View {
        ZStack {
            Circle().fill(provider != .claudeCode ? Color.white : Color(red: 217 / 255, green: 119 / 255, blue: 87 / 255))
            if provider.quotaSource != nil {
                IslandTaskProviderIcon(provider: provider, size: IslandChromeMetrics.providerIconDiameter)
            } else if provider == .antigravity, let icon = IslandProviderIcon.settingsMark(for: provider) {
                Image(nsImage: icon).renderingMode(.original).resizable().scaledToFill().clipShape(Circle())
            } else if let mark = IslandProviderIcon.usageMark(for: provider) {
                Image(nsImage: mark).renderingMode(.template).resizable().scaledToFit()
                    .foregroundStyle(provider == .codex ? Color.black : Color.white)
                    .frame(width: 11, height: 11)
            }
        }
        .frame(width: IslandChromeMetrics.providerIconDiameter, height: IslandChromeMetrics.providerIconDiameter)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

private struct IslandChartHoverAnchor: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

// Keep native scrolling/hit areas; only the visible horizontal rail is slimmer.
private final class IslandChartScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        let slot = rect(for: .knobSlot)
        NSColor(white: 0.13, alpha: 1).setFill()
        NSBezierPath(roundedRect: CGRect(x: slot.minX, y: bounds.midY - 1.5,
            width: slot.width, height: 3), xRadius: 1.5, yRadius: 1.5).fill()
        let knob = rect(for: .knob)
        NSColor(white: 0.48, alpha: 1).setFill()
        NSBezierPath(roundedRect: CGRect(x: knob.minX, y: bounds.midY - 2,
            width: knob.width, height: 4), xRadius: 2, yRadius: 2).fill()
    }
}

private struct IslandChartScrollStyle: NSViewRepresentable {
    final class Probe: NSView {
        private weak var scroll: NSScrollView?
        private var original: NSScroller?
        private var rail: IslandChartScroller?
        private var originalStyle: NSScroller.Style = .legacy
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); attach() }
        override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); attach() }
        override func layout() { super.layout(); attach() }
        func attach() {
            guard let found = enclosingScrollView, found !== scroll else { return }
            detach()
            scroll = found
            original = found.horizontalScroller
            originalStyle = found.scrollerStyle
            let rail = IslandChartScroller(frame: CGRect(x: 0, y: 0, width: 100, height: 12))
            rail.controlSize = .small
            rail.target = original?.target
            rail.action = original?.action
            self.rail = rail
            found.scrollerStyle = .legacy
            found.horizontalScroller = rail
        }
        func detach() {
            if let scroll, scroll.horizontalScroller === rail {
                scroll.horizontalScroller = original
                scroll.scrollerStyle = originalStyle
            }
            scroll = nil; original = nil; rail = nil
        }
    }
    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ view: Probe, context: Context) { view.attach() }
    static func dismantleNSView(_ view: Probe, coordinator: ()) { view.detach() }
}

/// Preserve readable marks and put the newest column at the trailing edge.
/// Data-value refreshes do not disturb a user who is browsing older history.
private struct IslandRecentChartScroll<Content: View>: View {
    let plotWidth: CGFloat
    let viewportWidth: CGFloat
    let plotHeight: CGFloat
    let resetID: String
    @ViewBuilder let content: () -> Content
    private var overflows: Bool { plotWidth > viewportWidth + 0.5 }

    var body: some View {
        Group {
            if overflows {
                ScrollViewReader { scroll in
                    ScrollView(.horizontal) {
                        content().frame(width: plotWidth, height: plotHeight)
                            .background(IslandChartScrollStyle()).id("recent-chart")
                    }
                    .defaultScrollAnchor(.trailing)
                    .scrollIndicators(.visible)
                    .onAppear { scroll.scrollTo("recent-chart", anchor: .trailing) }
                    .onChange(of: resetID) { _, _ in scroll.scrollTo("recent-chart", anchor: .trailing) }
                    .onChange(of: viewportWidth) { _, _ in scroll.scrollTo("recent-chart", anchor: .trailing) }
                }
            } else {
                content().frame(width: plotWidth, height: plotHeight)
            }
        }
        .frame(width: viewportWidth, height: plotHeight + (overflows ? 14 : 0), alignment: .trailing)
    }
}

struct IslandUsageBento: View {
    @Environment(\.appLanguage) private var appLanguage
    let snapshot: CurrentCodexPresentation?
    let usageState: IslandUsagePresentation.State
    let english: Bool
    let contentWidth: CGFloat
    let options: IslandUsageOptions
    let privacy: Bool
    let playbackEnabled: Bool
    let hidesTicket: Bool
    let onReset: () -> Void
    let utilities: IslandUtilityActions
    var maximumHeight: CGFloat? = nil
    let onHeightChange: (CGFloat) -> Void
    var claudeUsage: IslandClaudeUsage? = nil
    var antigravityUsage: AntigravityUsage? = nil
    var agentQuotas: [IslandAgentProvider: AgentQuotaState] = [:]
    private var externalQuota: AgentQuotaState? { agentQuotas[provider.wrappedValue] }
    private var providers: [IslandAgentProvider] {
        [.codex] + (claudeUsage == nil ? [] : [.claudeCode]) + (antigravityUsage == nil ? [] : [.antigravity])
            + IslandAgentProvider.allCases.filter { agentQuotas[$0] != nil }
    }
    private var showsAntigravity: Bool { provider.wrappedValue == .antigravity && antigravityUsage != nil }
    /// Owned by the board so the reset page follows the selected source.
    var provider: Binding<IslandAgentProvider> = .constant(.codex)
    var displayedResetCredits: Int? { IslandResetPageData(snapshot: current).credits }
    var resetCardIsEmpty: Bool { displayedResetCredits == 0 }
    private var showsClaude: Bool { provider.wrappedValue == .claudeCode && claudeUsage != nil }
    private var current: CurrentCodexPresentation? { externalQuota != nil || showsAntigravity ? nil : showsClaude ? claudeUsage?.presentation : snapshot }
    private var activeUsageState: IslandUsagePresentation.State { showsClaude ? .current : usageState }
    private var activeOptions: IslandUsageOptions {
        guard showsClaude else { return options }
        // Claude Code has no Spark quota; its quota cards stay even while
        // windows are unknown, so both sources share one page layout.
        var value = options
        value.spark = false
        return value
    }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var resetHovered = false
    @State private var selectedDay: Date?
    @State private var hoveredCost: Date?
    @State private var hoveredActivity: Int?
    @State private var selectedActivity: Date?
    @State private var activityMode: IslandActivityHeatmap.Mode = .daily
    @StateObject private var chartCache = IslandUsageChartCache()
    private let secondary = Color(white: 0.84)
    private func text(_ zh: LocalizedCopy, _ en: LocalizedCopy) -> String { AppCopy(language: appLanguage ?? (english ? .english : .simplifiedChinese)).text(zh, en) }
    private func tokens(_ value: Int64?) -> String { value.map { CodexActivityTokenUsageFormatter.string(for: $0) } ?? "—" }
    private func money(_ value: Double?) -> String { value.map { $0.formatted(.currency(code: "USD").locale(Locale(identifier: copy.language.localeIdentifier))) } ?? "—" }
    private var copy: AppCopy { .init(language: appLanguage ?? (english ? .english : .simplifiedChinese)) }
    private var charts: IslandUsageChartCache.Models {
        chartCache.models(provider: provider.wrappedValue, activity: showsAntigravity ? antigravityUsage?.days ?? [] : current?.tokenActivity ?? [],
                          lifetimeTokens: showsAntigravity ? antigravityUsage?.total : current?.lifetimeTokens, endingAt: Date())
    }
    private var chart: EstimatedCostChartModel { charts.cost }
    private func surface<Content: View>(highlightBottom: Bool = false, contentInset: CGFloat = 14, @ViewBuilder content: () -> Content) -> some View {
        // Native glass owns its content, rather than elevating a separate clear
        // background above ordinary text/charts in a shared glass container.
        content().padding(contentInset).frame(maxWidth: .infinity, alignment: .leading)
            .islandGlass(RoundedRectangle(cornerRadius: 14, style: .continuous),
                tint: Color(white: highlightBottom ? 0.12 : 0.075).opacity(0.75),
                solidTint: Color(white: highlightBottom ? 0.12 : 0.075))
    }
    private func heading(_ title: String) -> some View {
        Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(secondary)
    }
    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        surface { VStack(alignment: .leading, spacing: 10) { heading(title); content() } }
    }
    private func quotaCountdown(_ date: Date?) -> String {
        guard let date else { return "—" }
        let hours = max(0, Int(ceil(date.timeIntervalSinceNow / 3600)))
        let days = hours / 24, remainder = hours % 24
        if days > 0 {
            return text("\(days)天\(remainder)小时后重置", "Resets in \(days)d \(remainder)h")
        }
        return text("\(hours)小时后重置", "Resets in \(hours)h")
    }
    var body: some View {
        IslandPageLayout(maximumHeight: maximumHeight, onHeightChange: onHeightChange) {
            pageContent
        } footer: {
                IslandChromeFooter {
                    if let date = externalQuota != nil ? externalQuota?.report?.updatedAt : showsAntigravity ? antigravityUsage?.account?.updatedAt ?? antigravityUsage?.updatedAt : current?.lastUpdatedAt {
                        Text(text("更新于 ", "Updated ") + date.formatted(date: .omitted, time: .shortened))
                    } else { Text(text("等待数据", "Waiting for data")) }
                } trailing: { utilities }
        }.foregroundStyle(.white)
            .onChange(of: activeOptions.cost) { _, visible in if !visible { selectedDay = nil; hoveredCost = nil } }
            .onChange(of: activeOptions.activity) { _, visible in if !visible { selectedActivity = nil; hoveredActivity = nil } }
            .onChange(of: contentWidth) { _, _ in hoveredCost = nil; hoveredActivity = nil }
            .onDisappear { hoveredCost = nil; hoveredActivity = nil }
    }
    private var pageContent: some View {
        VStack(spacing: 10) {
                if providers.count > 3 && !privacy {
                    ScrollView(.horizontal) { providerSwitch }.scrollIndicators(.hidden)
                } else if providers.count > 1 && !privacy { providerSwitch }
                if !privacy, let externalQuota {
                    card(provider.wrappedValue.quotaName) {
                        if let report = externalQuota.report {
                            if let balance = report.balance { Text(balance).font(.headline) }
                            ForEach(report.windows, id: \.title) { window in
                                quotaContent(title: window.title, percent: window.remaining, status: quotaCountdown(window.resetsAt))
                            }
                        } else {
                            Text(externalQuota == .loading ? text("等待数据", "Waiting for data")
                                : text("额度暂不可用，请检查 Agent 接入中的账号设置。", "Quota unavailable. Check the account in Agent integrations."))
                        }
                    }
                } else if !privacy, showsAntigravity, let usage = antigravityUsage {
                    summaryCard.fixedSize(horizontal: false, vertical: true)
                    if options.activity && !usage.days.isEmpty { activityCard }
                    if usage.days.isEmpty && usage.account == nil {
                        card(text("用量数据", "Usage data")) {
                            Text(text("等待数据", "Waiting for data"))
                        }
                    }
                } else if privacy || current == nil {
                    card(text("用量数据", "Usage data")) {
                        Text(privacy ? text("隐私模式已开启", "Privacy mode is on") : activeUsageState.message(copy: copy))
                            .font(.system(size: 14, weight: .medium))
                        Text(privacy ? text("可在设置中关闭隐私模式。", "Turn off privacy mode in Settings.") : text("稍后刷新以重新获取。", "Refresh to try again.")).font(.system(size: 11)).foregroundStyle(secondary)
                    }
                } else {
                    if activeUsageState.isStale {
                        Text(copy.text("显示上次数据", "Showing previous data") + " · " + activeUsageState.message(copy: copy))
                            .font(.system(size: 10)).foregroundStyle(secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
                    }
                    overview
                    // Elevate at the sibling-card boundary: a chart-local zIndex cannot
                    // place its tooltip above a different card's surface.
                    if activeOptions.cost { costCard.zIndex(hoveredCost == nil ? 0 : 1) }
                    if activeOptions.activity { activityCard.zIndex(hoveredActivity == nil ? 0 : 1) }
                }
        }.padding(.horizontal, IslandVibeLayout.listInset).padding(.top, 10)
    }
    @ViewBuilder private var overview: some View {
        let hasSpark = activeOptions.spark && current?.sparkQuota != nil
        if activeOptions.quota || hasSpark || activeOptions.hasTokenMetrics {
            HStack(alignment: .top, spacing: 10) {
                summaryCard
                accountCard.frame(width: min(204, max(168, contentWidth * 0.327)))
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            accountCard
        }
    }

    private var sectionDivider: some View {
        Rectangle().fill(Color(white: 0.21)).frame(height: 0.5).accessibilityHidden(true)
    }

    private var columnDivider: some View {
        Rectangle().fill(Color(white: 0.21)).frame(width: 0.5).accessibilityHidden(true)
    }

    private var summaryCard: some View {
        surface {
            VStack(alignment: .leading, spacing: 12) {
                if activeOptions.quota { quotaWindows }
                if activeOptions.spark, let spark = current?.sparkQuota {
                    if activeOptions.quota { sectionDivider }
                    metric(text("Spark 周额度", "Spark weekly quota"), value: "\(spark.remainingPercent)%")
                }
                if activeOptions.hasTokenMetrics || showsAntigravity {
                    if activeOptions.quota || (activeOptions.spark && current?.sparkQuota != nil) { sectionDivider }
                    summaryMetrics
                }
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func quotaRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 10, content: content)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func antigravityQuota(_ window: AntigravityAccount.Window) -> some View {
        quotaContent(title: antigravityQuotaTitle(window.title), percent: window.remaining,
                     status: quotaCountdown(window.resetsAt))
    }

    @ViewBuilder private var quotaWindows: some View {
        if showsAntigravity {
            if let windows = antigravityUsage?.account?.windows, !windows.isEmpty {
                ForEach(0..<((windows.count + 1) / 2), id: \.self) { row in
                    if row > 0 { sectionDivider }
                    quotaRow {
                        antigravityQuota(windows[row * 2])
                        if row * 2 + 1 < windows.count {
                            columnDivider
                            antigravityQuota(windows[row * 2 + 1])
                        }
                    }
                }
            } else {
                let status = antigravityUsage?.didCheckAccount == true
                    ? text("实时额度暂不可用", "Live quota unavailable")
                    : text("等待数据", "Waiting for data")
                quotaContent(title: text("额度剩余", "Quota remaining"), percent: nil, status: status)
            }
        } else if showsClaude, let claude = claudeUsage {
            quotaRow {
                claudeQuotaCard(claude.fiveHour, title: text("5 小时额度", "5-hour quota"), state: claude.quotaState)
                columnDivider
                claudeQuotaCard(claude.sevenDay, title: text("每周额度", "Weekly quota"), state: claude.quotaState)
            }
        } else if let windows = current?.quotaWindows, let first = windows.first {
            quotaRow {
                ForEach(windows) { window in
                    if window.id != first.id { columnDivider }
                    quotaCard(window)
                }
            }
        } else {
            quotaCard(nil)
        }
    }

    private var summaryMetrics: some View {
        HStack(alignment: .top, spacing: 10) {
            if activeOptions.dailyTokens {
                metric(text("最近一天 Tokens", "Latest day tokens"),
                       value: tokens(showsAntigravity ? antigravityUsage?.days.last?.tokens : current?.recentDailyTokens))
            }
            if activeOptions.monthlyTokens {
                if activeOptions.dailyTokens { columnDivider }
                metric(text("30 天 Tokens", "30-day tokens"), value: tokens(chart.periodTokens))
            }
            if activeOptions.lifetimeTokens {
                if activeOptions.dailyTokens || activeOptions.monthlyTokens { columnDivider }
                metric(text("累计 Tokens", "Total tokens"),
                       value: tokens(showsAntigravity ? antigravityUsage?.total : current?.lifetimeTokens))
            }
            if showsAntigravity {
                if activeOptions.hasTokenMetrics { columnDivider }
                metric(text("订阅套餐", "Subscription plan"), value: antigravityUsage?.account?.displayPlan ?? "—")
                    .accessibilityElement(children: .combine)
                    .help(text("仅在额度来源提供套餐名称时显示。", "Shown when the quota source reports a plan name."))
            }
        }.fixedSize(horizontal: false, vertical: true)
    }

    private var providerSwitch: some View {
        HStack(spacing: 6) {
            ForEach(providers, id: \.self) { value in
                let selected = (providers.contains(provider.wrappedValue) ? provider.wrappedValue : .codex) == value
                Button { provider.wrappedValue = value; selectedDay = nil; hoveredCost = nil; selectedActivity = nil; hoveredActivity = nil } label: {
                    HStack(spacing: 6) {
                        IslandUsageProviderIcon(provider: value)
                        Text(value.quotaName).font(IslandChromeMetrics.navigationFont).lineLimit(1)
                    }
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.leading, IslandChromeMetrics.providerLeadingInset)
                        .padding(.trailing, IslandChromeMetrics.providerTrailingInset)
                        .frame(height: IslandChromeMetrics.buttonSize)
                        .foregroundStyle(selected ? .white : secondary)
                        .background {
                            // Brand artwork stays above the glass compositor at full opacity.
                            Color.clear
                                .islandGlass(Capsule(), tint: selected ? .white.opacity(0.20) : .black.opacity(0.28))
                                .allowsHitTesting(false)
                        }
                        .contentShape(Capsule())
                }.buttonStyle(.plain)
                    .accessibilityLabel(value.quotaName)
                    .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }.accessibilityElement(children: .contain)
            .accessibilityLabel(text("用量来源", "Usage source"))
    }
    private func antigravityQuotaTitle(_ title: String) -> String {
        switch title {
        case "Gemini weekly": text("Gemini 周额度", "Gemini weekly")
        case "Claude/GPT weekly": text("Claude/GPT 周额度", "Claude/GPT weekly")
        default: title
        }
    }

    private func quotaCard(_ window: CodexQuotaWindowPresentation?) -> some View {
        let title: String
        switch window?.windowDurationMinutes {
        case 300: title = text("5 小时额度", "5-hour quota")
        case 10080: title = text("每周额度", "Weekly quota")
        case .some(let minutes): title = text("\(minutes)分钟额度", "\(minutes)-minute quota")
        case .none: title = text("额度剩余", "Quota remaining")
        }
        return quotaContent(title: title, percent: window?.remainingPercent ?? current?.remainingPercent,
                            status: quotaCountdown(window?.resetsAt ?? current?.resetsAt))
    }
    /// Unknown Claude windows keep the card and say why the value is missing.
    private func claudeQuotaCard(_ window: CodexQuotaWindowPresentation?, title: String,
                                 state: IslandClaudeUsage.QuotaState) -> some View {
        let status: String
        let help: String?
        switch (window, state) {
        case (.some(let window), _): status = quotaCountdown(window.resetsAt); help = nil
        case (nil, .off):
            status = text("未开启", "Off")
            help = text("在设置 › 连接 › Claude Code 中开启“读取官方用量窗口”。", "Turn on “Read official usage windows” in Settings › Connections › Claude Code.")
        case (nil, _):
            status = text("等待刷新", "Waiting")
            help = text("Claude Code 刷新状态栏后显示。", "Appears after Claude Code refreshes its status line.")
        }
        return quotaContent(title: title, percent: window?.remainingPercent, status: status)
            .help(help ?? "")
            .accessibilityElement(children: .combine)
            .accessibilityHint(help ?? "")
    }
    private func quotaContent(title: String, percent: Int?, status: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    heading(title).fixedSize()
                    Spacer(minLength: 4)
                    Text(status).font(.system(size: 10, weight: .medium)).foregroundStyle(secondary).fixedSize()
                }
                VStack(alignment: .leading, spacing: 4) {
                    heading(title)
                    Text(status).font(.system(size: 10, weight: .medium)).foregroundStyle(secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(spacing: 9) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .lastTextBaseline) {
                        quotaPercent(percent)
                        if percent != nil {
                            Text(text("剩余", "left")).font(AstaSans.regular(10.5)).foregroundStyle(secondary).fixedSize()
                        }
                        Spacer(minLength: 4)
                        quotaUsed(percent)
                    }
                    HStack(alignment: .lastTextBaseline) {
                        quotaPercent(percent)
                        Spacer(minLength: 4)
                        quotaUsed(percent)
                    }
                    VStack(alignment: .leading, spacing: 4) { quotaPercent(percent); quotaUsed(percent) }
                }
                GeometryReader { proxy in
                    let fraction = CGFloat(min(100, max(0, percent ?? 0))) / 100
                    HStack(spacing: fraction > 0 && fraction < 1 ? 1 : 0) {
                        if fraction > 0 {
                            RoundedRectangle(cornerRadius: 2).fill(Color(nsColor: CodexActivityQuotaRingContract.color(for: percent)))
                                .frame(width: max(0, proxy.size.width * fraction - (fraction < 1 ? 0.5 : 0)))
                        }
                        if fraction < 1 { RoundedRectangle(cornerRadius: 2).fill(Color(white: 0.32)) }
                    }.clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(Color(white: 0.22), lineWidth: 0.5) }
                }.frame(height: 8).accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private func quotaPercent(_ percent: Int?) -> some View {
        Text(percent.map { "\($0)%" } ?? "—").font(AstaSans.semiBold(21)).tracking(-0.21).fixedSize()
    }
    private func quotaUsed(_ percent: Int?) -> some View {
        Text(percent.map { text("已使用 \(100 - min(100, max(0, $0)))%", "\(100 - min(100, max(0, $0)))% Used") } ?? "—")
            .font(AstaSans.regular(10.5)).foregroundStyle(secondary).fixedSize()
    }
    private var accountCard: some View {
        surface(highlightBottom: resetHovered && !hidesTicket, contentInset: 0) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                heading(text("账户", "Account"))
                Text(showsClaude ? (claudeUsage?.planName ?? "Claude Code") : current.flatMap { OpenAIPlanDisplayName.resolve($0.planType) } ?? "—")
                    .font(.system(size: 16, weight: .semibold))
                Spacer(minLength: 10)
                if activeOptions.credits {
                HStack {
                    Text(showsClaude ? text("额外用量", "Extra usage") : text("积分余额", "Credit balance")).foregroundStyle(secondary)
                    Spacer()
                    Text(showsClaude ? claudeExtraUsage : current?.creditBalance ?? "—")
                }.font(.system(size: 10))
                }
                }.padding(.horizontal, 14).padding(.top, 14)
                    .padding(.bottom, activeOptions.reset ? 10 : 14)
                if activeOptions.reset {
                Rectangle().fill(Color(white: 0.21)).frame(height: 0.5)
                    .padding(.horizontal, 14)
                Button(action: onReset) {
                    HStack {
                        IslandResetTicket(playbackEnabled: playbackEnabled, provider: showsClaude ? .claudeCode : .codex,
                                          isEmpty: resetCardIsEmpty).opacity(hidesTicket ? 0 : 1)
                            .anchorPreference(key: IslandResetTicketAnchors.self, value: .bounds) { [.usage: $0] }
                            .accessibilityHidden(true)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 7) {
                            HStack(spacing: 4) {
                                Text(text("额度重置", "Quota reset")).foregroundStyle(secondary)
                            }
                            if showsClaude {
                                Text(IslandResetPage.claudeResetCommand).font(.system(size: 10, weight: .medium, design: .monospaced))
                            } else {
                                Text(displayedResetCredits.map {
                                    $0 == 0 ? copy.text("0次 · 暂无可用", "0 left · unavailable") : copy.text("\($0)次", "\($0) left")
                                } ?? "—")
                            }
                        }.font(.system(size: 10))
                    }
                    // The label owns all space beneath the divider, including
                    // the account surface's side and bottom padding.
                    .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 14)
                    .frame(maxWidth: .infinity).contentShape(Rectangle())
                }.buttonStyle(IslandResetTicketButtonStyle())
                    .onHover { resetHovered = $0 && !hidesTicket }
                    .accessibilityLabel(showsClaude ? copy.text("打开 Claude 额度重置说明", "Open Claude quota reset")
                        : copy.text("打开额度重置", "Open quota reset"))
                    .accessibilityHint(showsClaude ? copy.text("在 Claude Code 中运行 /limit-reset 使用重置", "Run /limit-reset in Claude Code to use a reset")
                        : displayedResetCredits == 0
                        ? copy.text("无可用重置卡，点击查看", "No reset credits; open for details")
                        : copy.text("额度重置演示", "Quota reset preview"))
                }
            }.frame(maxHeight: .infinity, alignment: .topLeading)
        }
        .onChange(of: hidesTicket) { _, hidden in if hidden { resetHovered = false } }
        .onDisappear { resetHovered = false }
    }
    private var claudeExtraUsage: String {
        switch claudeUsage?.extraUsageEnabled {
        case true?: return claudeUsage?.extraUsagePercent.map { text("已用 \($0)%", "\($0)% used") } ?? text("已开启", "On")
        case false?: return text("未开启", "Off")
        case nil: return "—"
        }
    }
    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(secondary).lineLimit(1).minimumScaleFactor(0.8)
            Text(value).font(AstaSans.semiBold(21)).tracking(-0.21).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private var chartCellWidth: CGFloat { max(8, IslandActivityHeatmap.cellSize(width: contentWidth - 28)) }
    private var costPlotWidth: CGFloat {
        CGFloat(chart.days.count) * chartCellWidth + CGFloat(max(0, chart.days.count - 1)) * IslandActivityHeatmap.gap
    }
    private var costPlotViewportWidth: CGFloat { min(costPlotWidth, max(104, contentWidth - 28 - 208 - 28)) }
    private var costSummaryWidth: CGFloat { max(1, (contentWidth - 28 - costPlotViewportWidth - 28) / 2) }
    private var activityPlotWidth: CGFloat { max(contentWidth - 28, 53 * 10 + 52 * IslandActivityHeatmap.gap) }
    private var recentChartID: String { "\(provider.wrappedValue.rawValue)-\(chart.days.last?.date.timeIntervalSinceReferenceDate ?? 0)" }
    private var costCard: some View {
        let chart = self.chart
        let selectedCost = chart.days.first { $0.date == selectedDay }
        return surface {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    heading(text("成本估算", "Cost estimate"))
                    Text(money(chart.periodCost)).font(AstaSans.semiBold(21)).tracking(-0.21)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Text(text("最近 30 天", "Last 30 days")).font(.system(size: 10)).foregroundStyle(secondary)
                }.frame(width: costSummaryWidth, alignment: .leading)
                IslandRecentChartScroll(plotWidth: costPlotWidth, viewportWidth: costPlotViewportWidth,
                                        plotHeight: 58, resetID: recentChartID) {
                    costChart(chart)
                }
                .overlayPreferenceValue(IslandChartHoverAnchor.self) { anchor in
                    if let day = chart.days.first(where: { $0.date == hoveredCost }) {
                        chartTooltip(anchor: anchor, height: 78) {
                            Text(day.date.formatted(.dateTime.year().month().day()))
                            Text(money(day.estimatedCost) + text(" · 估算值", " · estimated"))
                            Text(tokens(day.tokens) + " Tokens")
                        }
                    }
                }
                .padding(.top, 14).zIndex(10)
                VStack(alignment: .trailing, spacing: 10) {
                    Text(selectedCost.map { $0.date.formatted(.dateTime.month().day()) } ?? text("最近一天", "Latest day"))
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(secondary)
                    Text(money(selectedCost != nil ? selectedCost?.estimatedCost : chart.latestCost))
                        .font(AstaSans.semiBold(17)).tracking(-0.17).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Text(text("估算值 · 非账单", "Estimate · not a bill"))
                        .font(.system(size: 10)).foregroundStyle(secondary).lineLimit(1).minimumScaleFactor(0.8)
                }.frame(width: costSummaryWidth, alignment: .trailing)
            }.fixedSize(horizontal: false, vertical: true)
        }
    }
    private func costChart(_ chart: EstimatedCostChartModel) -> some View {
            GeometryReader { proxy in
            HStack(alignment: .bottom, spacing: IslandActivityHeatmap.gap) {
                ForEach(chart.days) { day in
                    Button { selectedDay = selectedDay == day.date ? nil : day.date } label: {
                        RoundedRectangle(cornerRadius: min(2, chartCellWidth / 4))
                            .fill(selectedDay == day.date || hoveredCost == day.date
                                ? Color.white
                                : costBarColor(day.estimatedCost, maximum: chart.maximumCost))
                            .overlay {
                                if selectedDay == day.date || hoveredCost == day.date {
                                    RoundedRectangle(cornerRadius: min(2, chartCellWidth / 4)).strokeBorder(.white, lineWidth: 1)
                                }
                            }
                            .frame(width: chartCellWidth, height: max(3, proxy.size.height * (day.estimatedCost ?? 0) / max(0.001, chart.maximumCost)))
                            .frame(height: proxy.size.height, alignment: .bottom).contentShape(Rectangle())
                    }.buttonStyle(.plain).onHover { inside in
                        if inside {
                            if hoveredCost != day.date { hoveredCost = day.date }
                        } else if hoveredCost == day.date { hoveredCost = nil }
                    }.accessibilityLabel(day.date.formatted(date: .abbreviated, time: .omitted) + ": " + money(day.estimatedCost))
                    .anchorPreference(key: IslandChartHoverAnchor.self, value: .bounds) { hoveredCost == day.date ? $0 : nil }
                }
            }.zIndex(10)
            }
    }
    private var activityCard: some View {
        let grid = charts.activity(mode: activityMode)
        return surface {
            VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                heading(text("Token 活动", "Token activity"))
                if let cell = grid.cells.first(where: { $0.date == selectedActivity }) {
                    Text(cell.date.formatted(.dateTime.month().day()) + " · " + tokens(cell.tokens))
                        .font(.system(size: 10)).foregroundStyle(secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                ForEach(IslandActivityHeatmap.Mode.allCases, id: \.self) { mode in
                    Button { activityMode = mode; selectedActivity = nil; hoveredActivity = nil } label: {
                        Text(activityLabel(mode)).font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 8)
                            .foregroundStyle(activityMode == mode ? .white : secondary)
                            .padding(.vertical, 4)
                            .islandGlass(Capsule(), tint: activityMode == mode ? .white.opacity(0.20) : .black.opacity(0.28))
                    }.buttonStyle(.plain)
                }
            }
            IslandRecentChartScroll(plotWidth: activityPlotWidth, viewportWidth: contentWidth - 28,
                                    plotHeight: IslandActivityHeatmap.chartHeight(width: activityPlotWidth),
                                    resetID: recentChartID + "-\(activityMode)") {
                let size = IslandActivityHeatmap.cellSize(width: activityPlotWidth)
                let gap = IslandActivityHeatmap.gap
                let pitch = size + gap
                VStack(alignment: .leading, spacing: 8) {
                    if voiceOverEnabled || NSApp.isFullKeyboardAccessEnabled {
                        activityButtons(grid, size: size)
                    } else {
                        activityCanvas(grid, size: size)
                            .accessibilityRepresentation { activityButtons(grid, size: size) }
                    }
                    ZStack(alignment: .topLeading) {
                        ForEach(grid.months, id: \.column) { month in
                            Text(month.date.formatted(.dateTime.month(.abbreviated).locale(Locale(identifier: copy.language.localeIdentifier))))
                                .font(.system(size: 9)).foregroundStyle(secondary)
                                .fixedSize().offset(x: min(CGFloat(month.column) * pitch, max(0, activityPlotWidth - 25)))
                        }
                    }.frame(height: 13)
                }
            }
            .overlayPreferenceValue(IslandChartHoverAnchor.self) { anchor in
                if let index = hoveredActivity, grid.cells.indices.contains(index) {
                    let cell = grid.cells[index]
                    chartTooltip(anchor: anchor, height: 58) {
                        Text(activityDate(cell.date))
                        Text(activityTokens(cell.tokens))
                    }
                }
            }.zIndex(10)
            }
        }
    }
    private func activityCanvas(_ grid: IslandActivityHeatmap, size: CGFloat) -> some View {
        let pitch = size + IslandActivityHeatmap.gap
        let height = CGFloat(grid.rows) * pitch - IslandActivityHeatmap.gap
        let hovered = hoveredActivity
        let selected = selectedActivity
        return Canvas { context, _ in
            for column in 0..<53 {
                for row in 0..<grid.rows {
                    let index = grid.cellIndex(column: column, row: row)
                    let cell = grid.cells[index]
                    guard !cell.future else { continue }
                    let highlighted = hovered == index || selected == cell.date
                    let rect = CGRect(x: CGFloat(column) * pitch, y: CGFloat(row) * pitch, width: size, height: size)
                    let path = Path(roundedRect: rect, cornerRadius: min(2, size / 4))
                    context.fill(path, with: .color(activityColor(grid, column: column, row: row, highlighted: highlighted)))
                    if grid.mode == .daily && highlighted {
                        context.stroke(Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 1.5),
                                       with: .color(.white), lineWidth: 1)
                    }
                }
            }
        }
        .frame(width: activityPlotWidth, height: height)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            let index: Int?
            switch phase {
            case .active(let point): index = grid.cellIndex(at: point, size: size)
            case .ended: index = nil
            }
            if index != hoveredActivity { hoveredActivity = index }
        }
        .onTapGesture { point in
            if let index = grid.cellIndex(at: point, size: size) { selectedActivity = grid.cells[index].date }
        }
        .overlay(alignment: .topLeading) {
            if let index = hoveredActivity, grid.cells.indices.contains(index) {
                let column = grid.mode == .daily ? index / grid.rows : index
                let row = grid.mode == .daily ? index % grid.rows : 0
                Color.clear.frame(width: size, height: size)
                    .anchorPreference(key: IslandChartHoverAnchor.self, value: .bounds) { $0 }
                    .offset(x: CGFloat(column) * pitch, y: CGFloat(row) * pitch)
                    .allowsHitTesting(false)
            }
        }
    }

    private func activityColor(_ grid: IslandActivityHeatmap, column: Int, row: Int, highlighted: Bool) -> Color {
        if grid.mode == .daily { return heatColor(grid.cells[grid.cellIndex(column: column, row: row)].tokens, maximum: grid.maximum) }
        guard grid.isFilled(column: column, row: row) else { return Color(white: 0.13) }
        return highlighted ? Color(red: 0.39, green: 0.71, blue: 1) : Color(red: 0.02, green: 0.53, blue: 0.92)
    }

    private func activityButtons(_ grid: IslandActivityHeatmap, size: CGFloat) -> some View {
        HStack(alignment: .top, spacing: IslandActivityHeatmap.gap) {
            ForEach(0..<53, id: \.self) { column in
                VStack(spacing: IslandActivityHeatmap.gap) {
                    ForEach(0..<grid.rows, id: \.self) { row in
                        let index = grid.cellIndex(column: column, row: row)
                        let cell = grid.cells[index]
                        Button { selectedActivity = cell.date } label: {
                            RoundedRectangle(cornerRadius: min(2, size / 4))
                                .fill(activityColor(grid, column: column, row: row, highlighted: hoveredActivity == index || cell.date == selectedActivity))
                                .frame(width: size, height: size)
                                .overlay { if activityMode == .daily && (cell.date == selectedActivity || hoveredActivity == index) { RoundedRectangle(cornerRadius: 2).strokeBorder(.white, lineWidth: 1) } }
                        }.buttonStyle(.plain).disabled(cell.future)
                            .onHover { inside in
                                if inside && !cell.future {
                                    if hoveredActivity != index { hoveredActivity = index }
                                } else if hoveredActivity == index { hoveredActivity = nil }
                            }
                            .opacity(cell.future ? 0 : 1)
                            .accessibilityLabel(cell.date.formatted(date: .abbreviated, time: .omitted) + ": " + tokens(cell.tokens))
                            .anchorPreference(key: IslandChartHoverAnchor.self, value: .bounds) {
                                hoveredActivity == index && (activityMode == .daily || row == 0) ? $0 : nil
                            }
                    }
                }
            }
        }
    }

    private func chartTooltip<Content: View>(anchor: Anchor<CGRect>?, height: CGFloat,
                                            @ViewBuilder content: @escaping () -> Content) -> some View {
        GeometryReader { proxy in
            if let anchor {
                let rect = proxy[anchor]
                let width = min(214, proxy.size.width)
                // Resolve after the scroll view: the tooltip stays in the visible
                // viewport and cannot be cut off by the plot's clipping layer.
                if rect.maxX > 0 && rect.minX < proxy.size.width {
                    VStack(alignment: .leading, spacing: 3, content: content)
                        .font(.system(size: 11)).foregroundStyle(.white)
                        .padding(.horizontal, 11).padding(.vertical, 8)
                        .frame(width: width, alignment: .leading)
                        .background(Color(white: 0.17), in: RoundedRectangle(cornerRadius: 12))
                        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Color(white: 0.23), lineWidth: 1) }
                        .shadow(color: .black.opacity(0.25), radius: 5, y: 2)
                        .offset(x: min(max(0, rect.midX - width / 2), max(0, proxy.size.width - width)),
                                y: rect.minY - height)
                }
            }
        }.allowsHitTesting(false)
    }
    private func activityDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: copy.language.localeIdentifier)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.setLocalizedDateFormatFromTemplate("yMMMd")
        let label = formatter.string(from: date)
        switch activityMode {
        case .daily: return label
        case .weekly: return label + text(" 起的一周", " · week starting")
        case .cumulative: return text("累计至 ", "Total through ") + label + text(" 起的一周", " · week starting")
        }
    }
    private func activityTokens(_ value: Int64?) -> String {
        guard let value else { return text("暂无数据", "No data") }
        let label: String
        if [.simplifiedChinese, .traditionalChinese].contains(copy.language) && value >= 100_000_000 { label = String(format: "%.1f亿", Double(value) / 100_000_000) }
        else if [.simplifiedChinese, .traditionalChinese].contains(copy.language) && value >= 10_000 { label = String(format: "%.1f万", Double(value) / 10_000) }
        else { label = value.formatted() }
        return label + text(" 个 Token", " tokens")
    }
    private func costBarColor(_ value: Double?, maximum: Double) -> Color {
        guard let value, value > 0 else { return Color(white: 0.18) }
        let level = value / max(0.001, maximum)
        return Color(white: level < 0.25 ? 0.35 : level < 0.5 ? 0.48 : level < 0.75 ? 0.62 : 0.76)
    }
    private func heatColor(_ value: Int64?, maximum: Int64) -> Color {
        guard let value, value > 0 else { return Color(white: 0.18) }
        let level = Double(value) / Double(max(1, maximum))
        if level < 0.25 { return Color(red: 0.02, green: 0.23, blue: 0.40) }
        if level < 0.5 { return Color(red: 0.02, green: 0.35, blue: 0.61) }
        if level < 0.75 { return Color(red: 0.02, green: 0.53, blue: 0.92) }
        return Color(red: 0.39, green: 0.71, blue: 1)
    }
    private func activityLabel(_ mode: IslandActivityHeatmap.Mode) -> String {
        switch mode {
        case .daily: text("每天", "Daily")
        case .weekly: text("每周", "Weekly")
        case .cumulative: text("累计", "Cumulative")
        }
    }
}

private struct IslandResetTicketButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.985)
            .brightness(configuration.isPressed ? -0.06 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
