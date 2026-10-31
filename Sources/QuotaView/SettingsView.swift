import AppKit
import QuotaViewCore
import SwiftUI

enum SettingsWindowMetrics {
    // User-confirmed fixed width (2026-11-01).
    static let fixedContentWidth: CGFloat = 820
    static let defaultContentSize = NSSize(width: fixedContentWidth, height: 680)
    static let minimumContentSize = NSSize(width: fixedContentWidth, height: 560)
    static let outerCornerRadius: CGFloat = 24
    static let contentMaxWidth: CGFloat = 560
    static let contentInset: CGFloat = 20
    static let sidebarWidth: CGFloat = 180
    static let sidebarInset: CGFloat = 16
    static let fallbackSidebarCornerRadius: CGFloat =
        outerCornerRadius - sidebarInset

    @MainActor
    static func applySizingPolicy(to window: NSWindow) {
        let maximumHeight = max(minimumContentSize.height, window.contentMaxSize.height)
        window.contentMinSize = minimumContentSize
        window.contentMaxSize = NSSize(width: fixedContentWidth, height: maximumHeight)
        window.collectionBehavior.remove([.fullScreenPrimary, .fullScreenAllowsTiling])
        window.collectionBehavior.insert([.fullScreenNone, .fullScreenDisallowsTiling])
        window.standardWindowButton(.zoomButton)?.isEnabled = false
    }

    @MainActor
    static func applyOuterShape(to window: NSWindow) {
        window.isOpaque = false
        window.backgroundColor = .clear

        guard let contentView = window.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = outerCornerRadius
        contentView.layer?.cornerCurve = .continuous
        contentView.layer?.masksToBounds = true
        window.invalidateShadow()
    }
}

@MainActor
final class QuotaViewSettingsWindow: NSWindow {
    override func zoom(_ sender: Any?) {}
    override func toggleFullScreen(_ sender: Any?) {}
}

// Shared rhythm for detail pages; sidebar navigation keeps its own compact metrics.
enum SettingsLayoutMetrics {
    static let pageTopInset: CGFloat = 24
    static let pageBottomInset: CGFloat = 28
    static let sectionSpacing: CGFloat = 24
    static let itemSpacing: CGFloat = 12
    static let headingSpacing: CGFloat = 8
    static let cardInset: CGFloat = 12
    static let cardCornerRadius: CGFloat = 12
    static let rowMinHeight: CGFloat = 44
    static let describedRowMinHeight: CGFloat = 56
    static let rowVerticalInset: CGFloat = 10
    static let iconSize: CGFloat = 20
    static let iconGap: CGFloat = 8
    static let choiceWidth: CGFloat = 276
    static let previewBottomInset: CGFloat = 28
}

enum IslandSettingsPage: String, CaseIterable, Identifiable {
    case general, island, usage, connections, proxy, feedback, about
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .island: "sparkles.rectangle.stack.fill"
        case .usage: "chart.bar.fill"
        case .connections: "cpu.fill"
        case .proxy: "network"
        case .feedback: "ladybug.fill"
        case .about: "info.circle.fill"
        }
    }
    var color: NSColor {
        switch self {
        case .island, .connections: .systemBlue
        case .usage: .systemPurple
        case .feedback: .systemOrange
        default: .systemGray
        }
    }
    func title(_ copy: AppCopy) -> String {
        switch self {
        case .general: copy.text("通用", "General")
        case .island: copy.text("灵动岛", "Island")
        case .usage: copy.text("用量显示", "Usage display")
        case .connections: copy.text("Agent 接入", "Agent integration")
        case .proxy: copy.text("网络代理", "Network proxy")
        case .feedback: copy.text("Bug 反馈", "Bug feedback")
        case .about: copy.text("关于", "About")
        }
    }

}

enum SettingsFeedbackResources {
    @MainActor
    static let appIcon: NSImage = {
        // Prefer the original PNG; the compiled ICNS only carries reduced representations.
        if let image = NSImage(named: "QuotaViewAppIcon") { return image }
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) { return image }
        return NSApplication.shared.applicationIconImage
    }()

    static let repositoryURL = URL(string: "https://github.com/Duoasa/QuotaView")!
    static let issuesURL = URL(string: "https://github.com/Duoasa/QuotaView/issues")!

    @MainActor
    static let groupQRCode: NSImage? = {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        return bundle.url(forResource: "QuotaViewFeedbackQQ", withExtension: "jpg")
            .flatMap { NSImage(contentsOf: $0) }
    }()
}

struct SettingsView: View {
    @ObservedObject var store: CodexStatusStore
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var activityRuntime: CodexActivityRuntime
    @ObservedObject var updateController: AppUpdateController

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: IslandSettingsPage? = .general
    @FocusState private var focusedPage: IslandSettingsPage?
    @State private var proxyDraft = ProxyConfiguration.default
    @State private var proxySaveFailure: ProxyConnectionFailure?
    @State private var codexConnectionDetailsExpanded = false
    @State private var showsQuitConfirmation = false
    @State private var showsFeedbackQRCode = false
    @State private var availableScreens = NSScreen.screens
    @State private var islandHeaderHeight: CGFloat = 294
    @State private var settingsScrollOffset: CGFloat = 0
    @State private var settingsViewportWidth: CGFloat?

    private var copy: AppCopy { preferences.copy }

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            HStack(spacing: 0) {
                settingsSidebar
                    .frame(width: SettingsWindowMetrics.sidebarWidth)
                settingsDetail(for: selection ?? .general)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            availableScreens = NSScreen.screens
        }
        .environment(\.appLanguage, preferences.resolvedLanguage)
        .environment(\.colorScheme, .dark)
        .tint(Color(nsColor: .controlAccentColor))
        .buttonStyle(SettingsActionButtonStyle())
        .frame(
            minWidth: SettingsWindowMetrics.minimumContentSize.width,
            idealWidth: SettingsWindowMetrics.defaultContentSize.width,
            maxWidth: SettingsWindowMetrics.fixedContentWidth,
            minHeight: SettingsWindowMetrics.minimumContentSize.height,
            idealHeight: SettingsWindowMetrics.defaultContentSize.height
        )
        .containerShape(
            RoundedRectangle(
                cornerRadius: SettingsWindowMetrics.outerCornerRadius,
                style: .continuous
            )
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: SettingsWindowMetrics.outerCornerRadius,
                style: .continuous
            )
        )
        .ignoresSafeArea(.container, edges: .top)
        .alert(copy.text("退出 QuotaView？", "Quit QuotaView?"), isPresented: $showsQuitConfirmation) {
            Button(copy.text("取消", "Cancel"), role: .cancel) {}
            Button(copy.text("退出", "Quit"), role: .destructive) {
                NSApplication.shared.terminate(nil)
            }
        } message: {
            Text(copy.text("Codex 任务会继续运行。", "Codex tasks will keep running."))
        }
        .sheet(isPresented: $showsFeedbackQRCode) {
            feedbackQRCode
        }
        .background {
            SettingsWindowConfigurator()
        }
    }

    private static let navigationGroups: [[IslandSettingsPage]] = [
        [.general, .island, .usage], [.connections, .proxy], [.feedback, .about]
    ]

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsTrafficLightHost()
                .frame(width: 84, height: 44)
                .padding(.leading, 8)
                .padding(.top, 9)
            ScrollView {
                VStack(spacing: 20) {
                    ForEach(Array(Self.navigationGroups.enumerated()), id: \.offset) { index, group in
                        VStack(spacing: 4) {
                            ForEach(group) { page in settingsNavigationItem(page) }
                        }
                    }
                }.padding(.horizontal, 10).padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
            .padding(.top, 12)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        // Keep the sidebar material, but anchor it in a deeper neutral black.
        .background {
            ZStack {
                Rectangle().fill(.regularMaterial)
                Color.black.opacity(0.60)
            }
            .ignoresSafeArea(edges: [.top, .bottom])
        }
    }

    private func settingsNavigationItem(_ page: IslandSettingsPage) -> some View {
        let selected = selection == page
        return Button { selection = page; focusedPage = page } label: {
            HStack(spacing: 10) {
                SettingsSidebarIcon(symbol: page.symbol, color: Color(nsColor: page.color), size: 20)
                Text(page.title(copy))
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .focused($focusedPage, equals: page)
        .help(page.title(copy))
        .accessibilityLabel(page.title(copy))
        .accessibilityValue(selected ? copy.text("已选择", "Selected") : "")
        .onKeyPress(.downArrow) { navigateSettings(from: page, offset: 1) }
        .onKeyPress(.upArrow) { navigateSettings(from: page, offset: -1) }
    }

    private func navigateSettings(from page: IslandSettingsPage, offset: Int) -> KeyPress.Result {
        let pages = IslandSettingsPage.allCases
        guard let index = pages.firstIndex(of: page) else { return .ignored }
        let next = pages[max(0, min(pages.count - 1, index + offset))]
        selection = next; focusedPage = next
        return .handled
    }

    private func settingsDetail(for page: IslandSettingsPage) -> some View {
        Group {
            if page == .island, #available(macOS 26.0, *) {
                ScrollView {
                    islandSettings
                        .frame(maxWidth: SettingsWindowMetrics.contentMaxWidth, alignment: .topLeading)
                        .padding(.horizontal, SettingsWindowMetrics.contentInset)
                        .padding(.top, SettingsLayoutMetrics.itemSpacing)
                        .padding(.bottom, SettingsLayoutMetrics.pageBottomInset)
                        .frame(maxWidth: .infinity)
                        .background {
                            SettingsScrollPositionReader { _, width in settingsViewportWidth = width }
                        }
                }
                .safeAreaBar(edge: .top, alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: SettingsLayoutMetrics.itemSpacing) {
                        settingsPageHeading(for: page)
                        settingsStage(for: page)
                    }
                    .frame(maxWidth: SettingsWindowMetrics.contentMaxWidth, alignment: .leading)
                    .padding(.horizontal, SettingsWindowMetrics.contentInset)
                    .padding(.top, SettingsLayoutMetrics.pageTopInset)
                    .padding(.bottom, SettingsLayoutMetrics.previewBottomInset)
                    .frame(maxWidth: .infinity)
                    .frame(width: settingsViewportWidth)
                }
                .scrollEdgeEffectStyle(.soft, for: .top)
            } else {
                legacySettingsDetail(for: page)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .id(page)
        .transition(.opacity)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: selection)
    }

    private func legacySettingsDetail(
        for page: IslandSettingsPage
    ) -> some View {
        ZStack(alignment: .topLeading) {
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsLayoutMetrics.sectionSpacing) {
                    if page != .about && page != .island { settingsPageHeading(for: page) }
                    switch page {
                    case .general: generalSettings
                    case .island: islandSettings
                    case .usage: usageSettings
                    case .connections: connectionSettings
                    case .proxy: proxySettings
                    case .feedback: feedbackSettings
                    case .about: aboutSettings
                    }
                }
                .frame(maxWidth: SettingsWindowMetrics.contentMaxWidth, alignment: .topLeading)
                .padding(.horizontal, SettingsWindowMetrics.contentInset)
                .padding(.top, page == .island ? islandHeaderHeight + SettingsLayoutMetrics.itemSpacing : SettingsLayoutMetrics.pageTopInset)
                .padding(.bottom, SettingsLayoutMetrics.pageBottomInset)
                .frame(maxWidth: .infinity)
                .background {
                    if page == .island {
                        SettingsScrollPositionReader { offset, width in
                            settingsScrollOffset = offset
                            settingsViewportWidth = width
                        }
                    }
                }
            }
            if page == .island {
                VStack(alignment: .leading, spacing: SettingsLayoutMetrics.itemSpacing) {
                    settingsPageHeading(for: page)
                    settingsStage(for: page)
                }
                .frame(maxWidth: SettingsWindowMetrics.contentMaxWidth, alignment: .leading)
                .padding(.horizontal, SettingsWindowMetrics.contentInset)
                .padding(.top, SettingsLayoutMetrics.pageTopInset)
                .padding(.bottom, SettingsLayoutMetrics.previewBottomInset)
                .frame(maxWidth: .infinity)
                .frame(width: settingsViewportWidth)
                .background {
                    SettingsPinnedPreviewBackdrop(progress: min(1, settingsScrollOffset / 48))
                }
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: SettingsHeaderHeightKey.self, value: geometry.size.height)
                    }
                }
                .onPreferenceChange(SettingsHeaderHeightKey.self) { if $0 > 0 { islandHeaderHeight = $0 } }
                .zIndex(1)
            }
        }
    }

    private func settingsPageHeading(for page: IslandSettingsPage) -> some View {
        HStack(spacing: 10) {
            SettingsDetailIcon(symbol: page.symbol)
            Text(page.title(copy))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func settingsStage(for page: IslandSettingsPage) -> some View {
        if page == .island {
            islandStageVisual
                .environment(\.colorScheme, .dark)
                .frame(maxWidth: SettingsWindowMetrics.contentMaxWidth)
                .frame(height: 210)
                .frame(maxWidth: .infinity)
        }
    }

    // This illustration responds only to preferences, never live tasks or timers.
    private var islandStageVisual: some View {
        let geometry = activityRuntime.liveIsland.board.state.geometry
        return SettingsIslandPreview(preferences: preferences,
            expandedWidth: geometry.expandedWidth(preferred: preferences.codexIslandExpandedWidth),
            maximumExpandedWidth: geometry.maximumExpandedWidth)
    }

    // Both providers remain visible at a glance; their settings stay independent.
    private var connectionStageVisual: some View {
        HStack(spacing: 16) {
            SettingsConnectionSummary(provider: .codex,
                status: activityRuntime.connectionPresentation.automaticStatusTitle(copy),
                color: appServerStageColor,
                detail: copy.text("本机自动连接", "Automatic local connection"))
            ClaudeCodeConnectionStage(runtime: activityRuntime.claudeCode, copy: copy)
        }
    }

    private var appServerStageColor: Color {
        if activityRuntime.isNativeActivityConnected { return SettingsStagePalette.live }
        return activityRuntime.localHealth.hasReadError ? SettingsStagePalette.failure : SettingsStagePalette.faint
    }

    // About uses the page's solid background and the exact running build.
    private var aboutIdentity: some View {
        VStack(spacing: 18) {
            Image(nsImage: SettingsFeedbackResources.appIcon)
                .resizable().interpolation(.high).scaledToFit()
                .frame(width: 96, height: 96)
                .accessibilityLabel(copy.text("QuotaView 应用图标", "QuotaView app icon"))
            Text("QuotaView")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 4) {
                Text(copy.text("Codex 任务与用量灵动岛", "Codex task and usage island"))
                Text(versionAndBuildLabel)
                    .monospacedDigit()
                    .textSelection(.enabled)
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            if let buildDateLabel {
                Text(buildDateLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            if let copyright = Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String,
               !copyright.isEmpty {
                Text(copyright)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var proxyValidationFailure: ProxyConnectionFailure? {
        do { _ = try proxyDraft.validated(); return nil }
        catch { return .classify(error) }
    }

    private var proxySettings: some View {
        VStack(alignment: .leading, spacing: SettingsLayoutMetrics.itemSpacing) {
            NativeSettingsCard {
                NativeSettingsRow(
                    title: copy.text("自定义代理", "Custom proxy"),
                    symbol: "network"
                ) {
                    Toggle(copy.text("自定义代理", "Custom proxy"), isOn: $proxyDraft.isEnabled)
                        .labelsHidden().toggleStyle(.switch).tint(Color(nsColor: .secondaryLabelColor)).controlSize(.mini)
                        .help(copy.text("使用此代理查询额度与用量。", "Use this proxy for quota and usage."))
                }
                NativeSettingsDivider(leading: NativeSettingsDivider.iconLeading)
                NativeSettingsRow(title: copy.text("协议", "Protocol"),
                    symbol: "arrow.left.arrow.right") {
                    SettingsValueMenu(title: copy.text("代理协议", "Proxy protocol"), selection: $proxyDraft.scheme,
                        options: [(.http, "HTTP"), (.socks5, "SOCKS5")])
                    .disabled(!proxyDraft.isEnabled)
                }
                NativeSettingsDivider(leading: NativeSettingsDivider.iconLeading)
                NativeSettingsRow(
                    title: copy.text("服务器地址", "Server address"),
                    subtitle: copy.text("IP 或主机名，不含协议。", "IP or hostname, without a protocol prefix."),
                    symbol: "server.rack"
                ) {
                    SettingsTextField(placeholder: "127.0.0.1", text: $proxyDraft.host)
                        .frame(width: 190)
                        .accessibilityLabel(copy.text("代理服务器地址", "Proxy server address"))
                        .disabled(!proxyDraft.isEnabled)
                }
                NativeSettingsDivider(leading: NativeSettingsDivider.iconLeading)
                NativeSettingsRow(title: copy.text("端口", "Port"),
                    symbol: "number") {
                    SettingsTextField(placeholder: "7890", text: $proxyDraft.port)
                        .frame(width: 100)
                        .accessibilityLabel(copy.text("代理端口", "Proxy port"))
                        .disabled(!proxyDraft.isEnabled)
                }
            }
            Text(copy.text(
                "仅支持无需认证的代理；用于额度与用量查询。",
                "For quota and usage queries. Proxy authentication is not supported."
            ))
            .font(.callout).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if let failure = proxySaveFailure ?? proxyValidationFailure {
                Text(copy.proxyFailure(failure))
                    .font(.callout).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                Button(copy.text("恢复默认", "Restore Defaults")) {
                    store.cancelProxyTest()
                    preferences.restoreProxyDefaults()
                    proxyDraft = preferences.proxyConfiguration
                    proxySaveFailure = nil
                }
                .help(copy.text("关闭代理并恢复默认值。", "Turn off the proxy and restore defaults."))
                Spacer(minLength: 0)
                if store.proxyTestState == .testing {
                    Button(copy.text("取消测试", "Cancel Test")) { store.cancelProxyTest() }
                } else {
                    Button(copy.text("连接测试", "Test Connection")) {
                        store.testProxyConnection(proxyDraft)
                    }
                    .disabled(!proxyDraft.isEnabled || proxyValidationFailure != nil)
                    .help(copy.text("测试当前代理，不保存设置。", "Test this proxy without saving changes."))
                }
                Button(copy.text("保存", "Save")) {
                    do {
                        try preferences.saveProxyConfiguration(proxyDraft)
                        proxyDraft = preferences.proxyConfiguration
                        proxySaveFailure = nil
                    } catch { proxySaveFailure = .classify(error) }
                }
                .buttonStyle(SettingsActionButtonStyle(prominent: true))
                .disabled(proxyDraft == preferences.proxyConfiguration || proxyValidationFailure != nil)
            }
            if store.proxyTestState != .idle {
                HStack(spacing: 8) {
                    if store.proxyTestState == .testing {
                        ProgressView().controlSize(.small)
                    }
                    Text(copy.proxyTestStatus(store.proxyTestState))
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if proxyDraft != preferences.proxyConfiguration {
                Text(copy.text("有未保存的更改", "Unsaved changes"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .onAppear { proxyDraft = preferences.proxyConfiguration }
        .onDisappear { store.cancelProxyTest() }
        .onChange(of: proxyDraft) { _, _ in
            proxySaveFailure = nil
            store.cancelProxyTest()
        }
    }

    private var islandWidthRange: ClosedRange<Double> {
        let geometry = activityRuntime.liveIsland.board.state.geometry
        let upper = min(AppPreferences.IslandExpandedWidth.range.upperBound, Double(geometry.maximumExpandedWidth))
        return min(upper, Double(geometry.minimumExpandedWidth))...upper
    }
    private var islandWidthSelection: Binding<Double> {
        Binding(get: { min(islandWidthRange.upperBound, max(islandWidthRange.lowerBound, preferences.codexIslandExpandedWidth)) },
                set: { preferences.codexIslandExpandedWidth = AppPreferences.IslandExpandedWidth.normalized($0) })
    }
    private var islandSettings: some View {
        VStack(alignment: .leading, spacing: SettingsLayoutMetrics.sectionSpacing) {
            islandMaterialSettings
            settingsSection(copy.text("布局与显示", "Layout and display")) {
                NativeSettingsCard {
                    islandWidthSettings
                    NativeSettingsDivider(leading: NativeSettingsDivider.iconLeading)
                    preferenceToggle(copy.text("悬浮用量胶囊", "Floating usage capsule"),
                        symbol: "chart.pie.fill",
                        isOn: $preferences.islandFloatingUsageEnabled)
                }
            }

        }
    }

    private var usageSettings: some View {
        VStack(alignment: .leading, spacing: SettingsLayoutMetrics.sectionSpacing) {
            settingsSection(copy.text("可选模块", "Optional modules")) {
                NativeSettingsCard {
                    preferenceToggle(copy.text("近 30 天成本估算", "30-day cost estimate"),
                        symbol: "dollarsign.circle.fill",
                        isOn: $preferences.showEstimatedCost)
                    NativeSettingsDivider(leading: NativeSettingsDivider.iconLeading)
                    preferenceToggle(copy.text("Token 活动", "Token activity"),
                        subtitle: copy.text("每日 · 每周 · 累计", "Daily · Weekly · Total"),
                        symbol: "square.grid.3x3.fill",
                        isOn: $preferences.showTokenActivity)
                }
            }
            settingsSection(copy.text("操作保护", "Action protection")) {
                NativeSettingsCard {
                    preferenceToggle(copy.text("禁用重置卡使用", "Disable reset credit use"),
                        subtitle: copy.text("停用 Codex 重置按钮，避免误操作。", "Disable the Codex reset button to prevent accidental use."),
                        symbol: "lock.fill", isOn: $preferences.resetCreditUsageDisabled)
                }
            }
        }
    }

    private var connectionSettings: some View {
        AgentIntegrationSettings(preferences: preferences, runtime: activityRuntime) {
            codexConnectionSettings
        }
    }

    private var codexConnectionSettings: some View {
        NativeSettingsCard {
            NativeSettingsRow(
                title: copy.text("连接 Codex", "Connect Codex"),
                subtitle: activityRuntime.connectionPresentation.automaticSubtitle(copy)
            ) {
                HStack(spacing: 10) {
                    NativeSettingsConnectionStatus(
                        title: activityRuntime.connectionPresentation.automaticStatusTitle(copy),
                        color: activityRuntime.isNativeActivityConnected
                            ? Color(nsColor: .systemGreen)
                            : activityRuntime.localHealth.hasReadError
                                ? Color(nsColor: .systemRed)
                                : Color(nsColor: .tertiaryLabelColor)
                    )
                    Button(copy.text("重新检查", "Recheck")) { activityRuntime.recheckAutomaticConnection() }
                        .controlSize(.small)
                        .disabled(activityRuntime.isChangingDataDirectory || activityRuntime.hookOperation != .idle)
                        .help(copy.text("只读检查当前目录，不修改 Hook。", "Check the current directory without changing Hooks."))
                }
            }
            NativeSettingsDivider()
            NativeSettingsRow(
                title: copy.text("数据目录", "Data directory"),
                subtitle: activityRuntime.dataDirectoryURL.path
            ) {
                Menu {
                    Button(copy.text("选择目录…", "Choose Directory…")) { activityRuntime.chooseDataDirectory() }
                    Button(copy.text("恢复默认目录", "Restore Default Directory")) { activityRuntime.selectDataDirectory(nil) }
                        .disabled(!activityRuntime.usesCustomDataDirectory)
                } label: { Text(copy.text("更改目录", "Change Directory")) }
                    .controlSize(.small)
                    .disabled(activityRuntime.isChangingDataDirectory || activityRuntime.hookOperation != .idle)
            }
            if activityRuntime.directorySelectionFailed {
                NativeSettingsNote(text: copy.text(
                    "所选目录缺少可读取的 sessions 文件夹。",
                    "The selected directory needs a readable sessions folder."
                ))
            }
            NativeSettingsDivider()
            NativeSettingsRow(
                title: copy.text("任务事件连接", "Task event connection"),
                subtitle: codexActivityConnectionSubtitle
            ) {
                HStack(spacing: 10) {
                    NativeSettingsConnectionStatus(title: codexActivityConnectionStatusTitle, color: codexActivityConnectionColor)
                    codexHookAction
                }
            }
            if activityRuntime.hasCompatibilityHook,
               activityRuntime.hookConnectionStatus != .connected,
               activityRuntime.hookConnectionStatus != .awaitingFirstEvent {
                NativeSettingsDivider()
                NativeSettingsRow(
                    title: copy.text("停用任务事件连接", "Disable task event connection"),
                    subtitle: copy.text("自动读取任务记录继续工作。", "Automatic task record reading stays active.")
                ) {
                    Button(copy.text("停用", "Disable")) { activityRuntime.disableCompatibilityHook() }
                        .nativeSettingsActionStyle()
                        .controlSize(.small)
                        .disabled(activityRuntime.hookOperation != .idle || activityRuntime.isChangingDataDirectory)
                }
            }
            NativeSettingsDivider()
            NativeSettingsConnectionDetails(copy: copy, isExpanded: $codexConnectionDetailsExpanded) {
                NativeSettingsNote(text: copy.text(
                    "任务与用量来自本机 Codex。任务事件通过 Hook 补充，首次使用需在 Codex 中授权。停用只移除 QuotaView 的 Hook。",
                    "Tasks and usage come from local Codex. Hooks provide additional task events and require authorization in Codex on first use. Disabling removes only QuotaView hooks."
                ), horizontalPadding: 0)
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent(copy.text("Hook 配置目录", "Hook Configuration Directory"),
                                   value: activityRuntime.hookDirectoryPath)
                    LabeledContent(copy.text("Codex 版本", "Codex version"), value: codexEnvironmentSubtitle)
                    LabeledContent(copy.text("活动支持", "Activity support"), value: codexHooksFeatureTitle)
                    LabeledContent(copy.text("本地连接", "Local connection"), value: codexActivityBridgeStatusTitle)
                    Text(codexActivityBridgeSubtitle).foregroundStyle(.tertiary)
                    LabeledContent(copy.text("诊断日志", "Diagnostic log"), value: activityRuntime.diagnosticLogPath)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.bottom, 10)
            }
        }
        .onAppear { activityRuntime.refreshConnectionStatus() }
    }

    private var codexHookAction: some View {
        Button {
            switch activityRuntime.hookConnectionStatus {
            case .notInstalled:
                activityRuntime.enableCompatibilityHook()
            case .abnormal:
                activityRuntime.refreshConnectionStatus()
            case .installedNeedsRestart, .awaitingTrust:
                activityRuntime.openCodexSecurityReview()
            case .awaitingFirstEvent, .connected:
                activityRuntime.disableCompatibilityHook()
            }
        } label: {
            if activityRuntime.isConfiguring || activityRuntime.isOpeningSecurityReview {
                ProgressView().controlSize(.small)
            } else {
                Text(codexActivityActionTitle)
            }
        }
        .nativeSettingsActionStyle()
        .controlSize(.small)
        .disabled(activityRuntime.hookOperation != .idle || activityRuntime.isChangingDataDirectory)
        .help(codexActivityActionHelp)
        .accessibilityLabel(codexActivityActionTitle)
    }

    private var languageSelection: Binding<String> {
        .init(get: { preferences.followsSystemLanguage ? "system" : preferences.customLanguage.rawValue },
              set: { value in
                  preferences.followsSystemLanguage = value == "system"
                  if let language = AppPreferences.Language(rawValue: value) { preferences.customLanguage = language }
              })
    }
    private var systemLanguageOption: String {
        guard preferences.followsSystemLanguage else { return copy.text("跟随系统", "System") }
        let language = preferences.resolvedLanguage.nativeName
        return copy.text("跟随系统 · \(language)", "System · \(language)")
    }
    private var languageSettings: some View {
        NativeSettingsCard {
            NativeSettingsRow(title: copy.text("语言", "Language"),
                symbol: "globe") {
                SettingsValueMenu(title: copy.text("语言", "Language"), selection: languageSelection,
                    options: [("system", systemLanguageOption)] + AppPreferences.Language.allCases.map { ($0.rawValue, $0.nativeName) })
            }
        }
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: SettingsLayoutMetrics.headingSpacing) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
                .padding(.leading, SettingsLayoutMetrics.cardInset)
            VStack(alignment: .leading, spacing: SettingsLayoutMetrics.itemSpacing, content: content)
                .frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var screenOptions: [(String, String)] {
        var options = [("", copy.text("主屏幕", "Main display"))]
        options += availableScreens.enumerated().map { index, screen in
            (IslandScreenSelection.identifier(screen), "\(index + 1) · \(screen.localizedName)")
        }
        if !options.contains(where: { $0.0 == preferences.islandFixedScreenID }) {
            options.append((preferences.islandFixedScreenID, copy.text("所选屏幕未连接", "Selected display disconnected")))
        }
        return options
    }

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: SettingsLayoutMetrics.sectionSpacing) {
            languageSettings
            settingsSection(copy.text("灵动岛显示位置", "Island display")) {
                NativeSettingsCard { islandScreenSettings }
                if availableScreens.count < 2 {
                    NativeSettingsNote(text: copy.text("连接多台显示器后，焦点跟随会自动生效。", "Focus following takes effect when multiple displays are connected."))
                }
            }
            settingsSection(copy.text("交互与隐私", "Behavior and privacy")) {
                NativeSettingsCard {
                    preferenceToggle(copy.text("自动弹出", "Automatic popups"),
                        subtitle: copy.text("新任务、完成或待确认时弹出。", "Open for new tasks, completions and requests."),
                        symbol: "macwindow.badge.plus",
                        isOn: $preferences.codexActivityAutomaticPopupEnabled)
                    NativeSettingsDivider(leading: NativeSettingsDivider.iconLeading)
                    NativeSettingsRow(title: copy.text("停留时间", "Stay open for"),
                        subtitle: copy.text("待确认或固定时保持展开。", "Stay open for pending requests or when pinned."),
                        symbol: "timer") {
                        SettingsValueMenu(title: copy.text("停留时间", "Popup duration"),
                            selection: $preferences.codexActivityAutomaticPopupDuration,
                            options: AppPreferences.CodexActivityAutomaticPopupTiming.durationRange.map {
                                ($0, copy.text("\($0) 秒", "\($0) s"))
                            })
                            .disabled(!preferences.codexActivityAutomaticPopupEnabled)
                    }
                    NativeSettingsDivider(leading: NativeSettingsDivider.iconLeading)
                    preferenceToggle(copy.text("隐私模式", "Privacy mode"),
                        subtitle: copy.text("隐藏任务内容和账户数据。", "Hide task contents and account data."),
                        symbol: "eye.slash.fill",
                        isOn: $preferences.codexIslandPrivacy)
                }
            }
            Button(role: .destructive) { showsQuitConfirmation = true } label: {
                Text(copy.text("退出 QuotaView", "Quit QuotaView"))
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, SettingsLayoutMetrics.cardInset).frame(height: SettingsLayoutMetrics.rowMinHeight)
            }
            .buttonStyle(SettingsQuitRowStyle())
        }
    }

    private var islandScreenSettings: some View {
        Group {
            NativeSettingsRow(title: copy.text("跟随活动窗口", "Follow active window"),
                symbol: "display.2") {
                Toggle("", isOn: $preferences.islandFollowsFocus).labelsHidden()
                    .toggleStyle(.switch).tint(Color(nsColor: .secondaryLabelColor)).controlSize(.mini)
                    .accessibilityLabel(copy.text("焦点屏幕跟随", "Follow focused display"))
            }
            if !preferences.islandFollowsFocus {
                NativeSettingsDivider(leading: NativeSettingsDivider.iconLeading)
                NativeSettingsRow(title: copy.text("固定屏幕", "Fixed display"),
                    subtitle: copy.text("断开时暂回主屏，重新连接后恢复。", "Falls back to the main display until reconnected."),
                    symbol: "display") {
                    SettingsValueMenu(title: copy.text("固定屏幕", "Fixed display"),
                        selection: $preferences.islandFixedScreenID, options: screenOptions)
                }
            }
        }
    }

    private var islandWidthSettings: some View {
        NativeSettingsRow(title: copy.text("展开宽度", "Expanded width"),
            symbol: "arrow.left.and.right") {
            HStack(spacing: 12) {
                Slider(value: islandWidthSelection, in: islandWidthRange, step: 8)
                    .controlSize(.small).frame(minWidth: 80, idealWidth: 110, maxWidth: 150)
                    .disabled(islandWidthRange.lowerBound == islandWidthRange.upperBound)
                    .accessibilityLabel(copy.text("展开宽度", "Expanded width"))
                    .help(copy.text("调整任务列表与用量页宽度。", "Adjust the task list and usage page width."))
                    .accessibilityValue("\(Int(islandWidthSelection.wrappedValue)) pt")
                Text("\(Int(islandWidthSelection.wrappedValue)) pt")
                    .font(.callout.monospacedDigit()).frame(width: 52, alignment: .trailing)
            }
        }
    }

    private var islandMaterialSettings: some View {
        settingsSection(copy.text("外观", "Appearance")) {
            NativeSettingsCard {
                islandMaterialOption(.liquidGlass,
                    title: copy.text("液态玻璃", "Liquid Glass"),
                    subtitle: copy.text("通透材质、自然高光与深色玻璃卡片。", "Translucent surfaces, natural highlights and dark glass cards."),
                    symbol: "drop.fill")
                NativeSettingsDivider(leading: NativeSettingsDivider.iconLeading)
                islandMaterialOption(.classic,
                    title: copy.text("经典纯色", "Classic solid"),
                    subtitle: copy.text("关闭背景、卡片与按钮的玻璃材质。遇到卡顿时可切换至此。", "Turn off glass on the background, cards and buttons. Choose this if glass feels slow."),
                    symbol: "rectangle.fill")
                if preferences.islandMaterial == .liquidGlass {
                    NativeSettingsDivider(leading: NativeSettingsDivider.iconLeading)
                    SettingsChoiceRow(title: copy.text("玻璃外观", "Glass appearance"), symbol: "circle.lefthalf.filled") {
                        ForEach(AppPreferences.IslandGlassAppearance.allCases) { appearance in
                            glassAppearanceOption(appearance)
                        }
                    }
                    NativeSettingsDivider(leading: NativeSettingsDivider.iconLeading)
                    NativeSettingsRow(title: copy.text("玻璃程度", "Glass amount"), symbol: "slider.horizontal.3") {
                        HStack(spacing: 8) {
                            Text(copy.text("黑色", "Black"))
                            Slider(value: $preferences.islandGlassDegree, in: 0.2...0.8)
                                .accessibilityLabel(copy.text("玻璃程度", "Glass amount"))
                                .accessibilityValue(copy.text("黑色区域 \(Int(((1 - preferences.islandGlassDegree) * 100).rounded()))%", "Black area \(Int(((1 - preferences.islandGlassDegree) * 100).rounded()))%"))
                            Text(copy.text("玻璃", "Glass"))
                        }
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(width: SettingsLayoutMetrics.choiceWidth)
                    }
                }
                NativeSettingsDivider(leading: NativeSettingsDivider.iconLeading)
                SettingsChoiceRow(title: copy.text("任务特效", "Task effects"), symbol: "sparkles") {
                    ForEach(AppPreferences.CodexActivityProgressEffect.allCases) { effect in
                        let selected = preferences.codexActivityProgressEffect == effect
                        Button { preferences.codexActivityProgressEffect = effect } label: {
                            Text(copy.named(effect.displayName.simplifiedChinese, effect.displayName.english))
                        }
                        .buttonStyle(SettingsEffectOptionStyle(effect: effect, selected: selected))
                        .accessibilityLabel(copy.named(effect.displayName.simplifiedChinese, effect.displayName.english))
                        .accessibilityValue(selected ? copy.text("已选择", "Selected") : copy.text("未选择", "Not selected"))
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
            if #unavailable(macOS 26.0) {
                NativeSettingsNote(text: copy.text("原生液态玻璃需要 macOS 26 或更新版本；当前系统使用半透明材质。", "Native Liquid Glass requires macOS 26 or later; this system uses translucent material."))
            }
        }
    }

    private func islandMaterialOption(_ mode: AppPreferences.IslandMaterial, title: String,
                                      subtitle: String, symbol: String) -> some View {
        let selected = preferences.islandMaterial == mode
        return Button { preferences.islandMaterial = mode } label: {
            NativeSettingsRow(title: title, subtitle: subtitle, symbol: symbol) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
        .accessibilityValue(selected ? copy.text("已选择", "Selected") : copy.text("未选择", "Not selected"))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func glassAppearanceOption(_ appearance: AppPreferences.IslandGlassAppearance) -> some View {
        let selected = preferences.islandGlassAppearance == appearance
        return Button { preferences.islandGlassAppearance = appearance } label: {
            VStack(spacing: 5) {
                SettingsGlassAppearanceThumbnail(appearance: appearance)
                    .frame(height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .padding(3)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
                    }
                Text(appearance.title(copy)).font(.system(size: 11, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? .primary : .secondary)
            }.frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(appearance.title(copy))
        .accessibilityValue(selected ? copy.text("已选择", "Selected") : copy.text("未选择", "Not selected"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var feedbackSettings: some View {
        VStack(alignment: .leading, spacing: SettingsLayoutMetrics.itemSpacing) {
            Button { showsFeedbackQRCode = true } label: {
                feedbackRow(
                    title: copy.text("QQ群", "QQ group"),
                    detail: copy.text("群号：1108649282", "Group: 1108649282"),
                    symbol: "qrcode"
                )
            }
            .buttonStyle(SettingsFeedbackRowStyle())
            .help(copy.text("显示群二维码", "Show the group QR code"))

            Link(destination: SettingsFeedbackResources.issuesURL) {
                feedbackRow(
                    title: "GitHub Issues",
                    detail: "Duoasa / QuotaView",
                    symbol: "chevron.left.forwardslash.chevron.right",
                    trailingSymbol: "arrow.up.right"
                )
            }
            .buttonStyle(SettingsFeedbackRowStyle())
            .help(copy.text("在浏览器中打开反馈页面", "Open the feedback page in your browser"))
        }
    }

    private func feedbackRow(title: String, detail: String, symbol: String,
                             trailingSymbol: String = "chevron.right") -> some View {
        HStack(spacing: 10) {
            SettingsDetailIcon(symbol: symbol)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Image(systemName: trailingSymbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, SettingsLayoutMetrics.cardInset)
        .padding(.vertical, SettingsLayoutMetrics.rowVerticalInset)
        .frame(minHeight: SettingsLayoutMetrics.describedRowMinHeight)
        .contentShape(RoundedRectangle(cornerRadius: SettingsLayoutMetrics.cardCornerRadius, style: .continuous))
    }

    private var feedbackQRCode: some View {
        VStack(spacing: 16) {
            if let image = SettingsFeedbackResources.groupQRCode {
                SettingsFeedbackQRCodeImage(image: image)
                    .accessibilityLabel(copy.text(
                        "QuotaView 反馈群二维码，群号 1108649282",
                        "QuotaView feedback group QR code, group 1108649282"
                    ))
            } else {
                Text(copy.text("二维码暂时无法显示。", "The QR code is unavailable."))
                    .foregroundStyle(.secondary)
            }
            Button(copy.text("关闭", "Close")) { showsFeedbackQRCode = false }
                .keyboardShortcut(.cancelAction)
        }
        .padding(24)
        .frame(width: 360)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var aboutSettings: some View {
        VStack(alignment: .leading, spacing: SettingsLayoutMetrics.sectionSpacing) {
            aboutIdentity
            settingsSection(copy.text("软件更新", "Software updates")) {
                NativeSettingsCard {
                    if updateController.availability == .available {
                        NativeSettingsRow(title: copy.text("自动检查更新", "Automatically check for updates"),
                            subtitle: copy.text("每 24 小时；安装前确认。", "Every 24 hours; confirm before installing."),
                            symbol: "clock.arrow.circlepath") {
                            Toggle(copy.text("自动检查更新", "Automatically check for updates"), isOn: Binding(
                                get: { updateController.automaticallyChecksForUpdates },
                                set: { updateController.setAutomaticallyChecksForUpdates($0) }))
                                .labelsHidden().toggleStyle(.switch).tint(Color(nsColor: .secondaryLabelColor)).controlSize(.mini)
                        }
                        NativeSettingsDivider()
                        HStack {
                            Spacer(minLength: 0)
                            Button(copy.text("检查更新…", "Check for Updates…")) { updateController.checkForUpdates() }
                                .nativeSettingsActionStyle().disabled(!updateController.canCheckForUpdates).help(updateCheckHelpText)
                        }.padding(.horizontal, 12).padding(.vertical, 8)
                    } else {
                        NativeSettingsRow(title: copy.text("当前构建", "Current build"), subtitle: updateStatusText,
                            symbol: "hammer.fill") {}
                    }
                }
            }
            if BrandAnnouncementController.isAvailable {
                NativeSettingsCard {
                    NativeSettingsRow(title: copy.text("更新与公告", "Updates & announcements"),
                        symbol: "list.bullet.clipboard.fill") {
                        Button(copy.text("查看", "View")) {
                            BrandAnnouncementController.shared.showPreview(copy: copy)
                        }.nativeSettingsActionStyle()
                    }
                }
            }
            NativeSettingsCard {
                NativeSettingsRow(title: "GitHub", subtitle: "Duoasa / QuotaView", symbol: "chevron.left.forwardslash.chevron.right") {
                    Link(destination: SettingsFeedbackResources.repositoryURL) {
                        Label(copy.text("访问", "Visit"), systemImage: "arrow.up.right")
                    }
                    .nativeSettingsActionStyle()
                    .help(copy.text("在浏览器中打开 QuotaView GitHub 仓库", "Open the QuotaView GitHub repository in your browser"))
                    .accessibilityLabel(copy.text("访问 QuotaView GitHub 仓库", "Visit the QuotaView GitHub repository"))
                }
            }
        }
    }

    private var updateCheckHelpText: String {
        if updateController.availability == .available {
            return copy.text(
                "检查是否有新版本。",
                "Check for a new version."
            )
        }
        return copy.text(
            "当前构建不支持在线更新。",
            "This build does not support online updates."
        )
    }

    private var updateStatusText: String {
        switch updateController.availability {
        case .available:
            return copy.text(
                "每 24 小时检查一次，安装前会询问。",
                "Check every 24 hours and ask before installing."
            )
        case .debugBuild:
            return copy.text(
                "调试版不支持在线更新。",
                "Online updates are unavailable in debug builds."
            )
        case .notApplicationBundle:
            return copy.text(
                "当前运行方式不支持在线更新。",
                "The current launch environment does not support online updates."
            )
        case .unexpectedBundleIdentifier,
             .untrustedSignature:
            return copy.text(
                "请使用正式签名版本以获取更新。",
                "Use an officially signed release to receive updates."
            )
        case .invalidConfiguration:
            return copy.text(
                "更新配置无效，请重新安装正式版。",
                "Update configuration is invalid. Reinstall the official release."
            )
        }
    }

    private var buildDateLabel: String? {
        guard let executableURL = Bundle.main.executableURL,
              let date = try? executableURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        else { return nil }
        let formatter = DateFormatter()
        formatter.locale = preferences.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let formatted = formatter.string(from: date)
        return copy.text("构建于 \(formatted)", "Built on \(formatted)")
    }

    private var versionAndBuildLabel: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0.4.0"
        let build = Bundle.main.object(
            forInfoDictionaryKey: "QuotaViewDisplayBuildNumber"
        ) as? String ?? Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "1"
        let isPreview = Bundle.main.object(
            forInfoDictionaryKey: "QuotaViewReleaseChannel"
        ) as? String == "preview"
        let previewNumber = Bundle.main.object(
            forInfoDictionaryKey: "QuotaViewPreviewNumber"
        ) as? String ?? "1"
        let channelSuffix = isPreview ? " · Preview \(previewNumber)" : ""
        return copy.text(
            "版本 \(version)（\(build)）\(channelSuffix)",
            "Version \(version) (\(build))\(channelSuffix)"
        )
    }

    private func preferenceToggle(
        _ title: String,
        subtitle: String? = nil,
        symbol: String,
        isOn: Binding<Bool>
    ) -> some View {
        NativeSettingsRow(
            title: title,
            subtitle: subtitle,
            symbol: symbol
        ) {
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch).tint(Color(nsColor: .secondaryLabelColor))
                .controlSize(.mini)
        }
    }


    private var codexActivityActionTitle: String {
        if activityRuntime.isConfiguring { return copy.text("正在配置", "Configuring") }
        if activityRuntime.isOpeningSecurityReview { return copy.text("正在授权", "Authorizing") }
        return switch activityRuntime.hookConnectionStatus {
        case .notInstalled: copy.text("启用 Hook", "Enable Hooks")
        case .abnormal: copy.text("重新检查", "Recheck")
        case .installedNeedsRestart, .awaitingTrust: copy.text("授权连接", "Authorize")
        case .awaitingFirstEvent, .connected: copy.text("停用 Hook", "Disable Hooks")
        }
    }

    private var codexActivityActionHelp: String {
        switch activityRuntime.hookConnectionStatus {
        case .installedNeedsRestart, .awaitingTrust:
            copy.text("通过 Codex 授权 QuotaView 的任务事件 Hook。", "Authorize QuotaView task event Hooks through Codex.")
        case .awaitingFirstEvent, .connected:
            copy.text("停用 Hook，App Server 连接继续工作。", "Disable Hooks; the App Server connection keeps working.")
        case .notInstalled, .abnormal:
            copy.text("检查并维护 QuotaView Hook，不更改其他 Hook。", "Check and maintain QuotaView Hooks while preserving other Hooks.")
        }
    }

    private var codexActivityConnectionSubtitle: String {
        if activityRuntime.isConfiguring { return copy.text("正在检查并自动配置…", "Checking and configuring automatically…") }
        if activityRuntime.isOpeningSecurityReview { return copy.text("正在通过 Codex 验证授权…", "Verifying authorization through Codex…") }
        return switch activityRuntime.hookConnectionStatus {
        case .notInstalled: copy.text("Hook 已停用，可随时重新启用。", "Hooks are off. Enable them at any time.")
        case .installedNeedsRestart, .awaitingTrust:
            copy.text("已自动配置。授权后即可接收任务事件，无需终端配置。", "Configured automatically. Authorize to receive task events without terminal setup.")
        case .awaitingFirstEvent: copy.text("Codex 已确认授权，等待新的任务事件。", "Authorization verified by Codex; waiting for task activity.")
        case .connected: copy.text("已接收任务事件，补充任务与上下文压缩状态。", "Receiving task events for task and context compaction updates.")
        case .abnormal(let message): message
        }
    }

    private var codexActivityConnectionStatusTitle: String {
        if activityRuntime.isConfiguring { return copy.text("正在配置", "Configuring") }
        if activityRuntime.isOpeningSecurityReview { return copy.text("正在授权", "Authorizing") }
        return switch activityRuntime.hookConnectionStatus {
        case .notInstalled: copy.text("已停用", "Disabled")
        case .installedNeedsRestart, .awaitingTrust: copy.text("待授权", "Authorization Needed")
        case .awaitingFirstEvent: copy.text("已授权", "Authorized")
        case .connected: copy.text("已连接", "Connected")
        case .abnormal: copy.text("需要处理", "Needs Attention")
        }
    }

    private var codexActivityConnectionColor: Color {
        if activityRuntime.isConfiguring || activityRuntime.isOpeningSecurityReview { return Color(nsColor: .systemBlue) }
        return switch activityRuntime.hookConnectionStatus {
        case .connected: Color(nsColor: .systemGreen)
        case .installedNeedsRestart, .awaitingTrust, .awaitingFirstEvent: Color(nsColor: .systemOrange)
        case .abnormal: Color(nsColor: .systemRed)
        case .notInstalled: Color(nsColor: .tertiaryLabelColor)
        }
    }

    private var codexEnvironmentSubtitle: String {
        activityRuntime.codexVersion ?? copy.text(
            "检测版本中…",
            "Checking version…"
        )
    }

    private var codexHooksFeatureTitle: String {
        return switch activityRuntime.hooksFeatureStatus {
        case .checking:
            copy.text("检测中", "Checking")
        case .enabled:
            copy.text("Hooks 已启用", "Hooks Enabled")
        case .disabled:
            copy.text("Hooks 未启用", "Hooks Disabled")
        case .unavailable:
            copy.text("Hooks 不可用", "Hooks Unavailable")
        }
    }

    private var codexActivityBridgeSubtitle: String {
        return switch activityRuntime.bridgeStatus {
        case .listening:
            copy.text(
                "通过本地连接接收任务事件。",
                "Receives task events through a local connection."
            )
        case .stopped:
            copy.text(
                "事件桥接尚未启动。",
                "The event bridge is not running."
            )
        case .failed(let message):
            message
        }
    }

    private var codexActivityBridgeStatusTitle: String {
        return switch activityRuntime.bridgeStatus {
        case .listening:
            copy.text("监听中", "Listening")
        case .stopped:
            copy.text("已停止", "Stopped")
        case .failed:
            copy.text("不可用", "Unavailable")
        }
    }

    private var codexActivityBridgeColor: Color {
        return switch activityRuntime.bridgeStatus {
        case .listening:
            Color(nsColor: .systemGreen)
        case .stopped:
            Color(nsColor: .tertiaryLabelColor)
        case .failed:
            Color(nsColor: .systemRed)
        }
    }

}

// Stage colours come from the island itself: true black, the #202020 card
// line, and the island's own completed / attention / failure hues.
private enum SettingsStagePalette {
    static let primary = Color.white.opacity(0.92)
    static let secondary = Color.white.opacity(0.58)
    static let faint = Color.white.opacity(0.3)
    static let live = Color(red: 0.36, green: 0.80, blue: 0.55)
    static let attention = Color(red: 1, green: 0.76, blue: 0.44)
    static let failure = Color(red: 0.95, green: 0.43, blue: 0.42)
}

/// Display only the QR region of the bundled 1284 × 2289 poster, including
/// its quiet border. The original pixels/resource stay intact at every size.
private struct SettingsFeedbackQRCodeImage: View {
    let image: NSImage
    private static let region = CGRect(x: 180.0 / 1284, y: 724.0 / 2289,
                                       width: 924.0 / 1284, height: 924.0 / 2289)

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width / Self.region.width
            let height = geometry.size.height / Self.region.height
            Image(nsImage: image).resizable().interpolation(.high)
                .frame(width: width, height: height)
                .offset(x: -width * Self.region.minX, y: -height * Self.region.minY)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipped()
    }
}

/// Bundled Figma snapshots replace the settings page's live shader previews.
private enum SettingsIslandPreviewAssets {
    static var bundle: Bundle {
        #if SWIFT_PACKAGE
        Bundle.module
        #else
        Bundle.main
        #endif
    }

    static func image(_ name: String) -> Image {
        Image("SettingsIslandPreview" + name, bundle: bundle)
    }

    static func effectName(_ effect: AppPreferences.CodexActivityProgressEffect) -> String {
        switch effect {
        case .stateSmoke: "StateSmoke"
        case .dropField: "QuantumNoise"
        case .sloshFlow: "LiquidWave"
        }
    }
}

private enum SettingsPreviewContour {
    static var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 20, style: .continuous) }
}

// The single live card preview reuses the bounded 24 fps renderer; option tiles stay images.
private struct SettingsLiveEffectPreview: NSViewRepresentable {
    let effect: AppPreferences.CodexActivityProgressEffect
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeNSView(context: Context) -> CodexActivityStateSmokePreviewHostView {
        CodexActivityStateSmokePreviewHostView(effect: effect)
    }
    func updateNSView(_ view: CodexActivityStateSmokePreviewHostView, context: Context) {
        view.update(effect: effect, reduceMotion: reduceMotion, cornerRadius: IslandVibeLayout.rowRadius)
        if !view.isRendererAvailable {
            view.setFallbackImage(SettingsIslandPreviewAssets.bundle.image(forResource:
                "SettingsIslandPreview" + SettingsIslandPreviewAssets.effectName(effect)))
        }
    }
    static func dismantleNSView(_ view: CodexActivityStateSmokePreviewHostView, coordinator: ()) {
        view.stop()
    }
}

/// Static Light / Dark / Auto illustrations, following macOS Appearance settings.
/// Auto combines two halves of the same miniature desktop, without live windows.
private struct SettingsGlassAppearanceThumbnail: View {
    let appearance: AppPreferences.IslandGlassAppearance

    var body: some View {
        ZStack {
            if appearance == .automatic {
                desktop(dark: false).mask {
                    HStack(spacing: 0) { Rectangle(); Color.clear }
                }
                desktop(dark: true).mask {
                    HStack(spacing: 0) { Color.clear; Rectangle() }
                }
            } else {
                desktop(dark: appearance == .dark)
            }
        }.accessibilityHidden(true)
    }

    private func desktop(dark: Bool) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                SettingsIslandPreviewAssets.image("Wallpaper")
                    .resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    .overlay(dark ? Color.indigo.opacity(0.35) : Color.white.opacity(0.08))
                Rectangle().fill(dark ? Color.black.opacity(0.35) : Color.white.opacity(0.5))
                    .frame(height: 10)
                    .overlay(alignment: .leading) {
                        Image(systemName: "apple.logo").font(.system(size: 7)).foregroundStyle(.white)
                            .padding(.leading, 5)
                    }
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(dark ? Color(white: 0.16) : Color(white: 0.94))
                    .overlay(alignment: .top) {
                        UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4)
                            .fill(Color.blue).frame(height: 8).padding(3)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(.white.opacity(0.5), lineWidth: 0.5)
                    }
                    .frame(width: geometry.size.width * 0.55, height: 23)
                    .offset(x: 6, y: 15)
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(dark ? Color(white: 0.055) : Color(white: 0.97))
                    .overlay(alignment: .topLeading) {
                        HStack(spacing: 4) {
                            ForEach([Color.red, .yellow, .green].indices, id: \.self) { index in
                                Circle().fill([Color.red, .yellow, .green][index]).frame(width: 6, height: 6)
                            }
                        }.padding(9)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.white.opacity(dark ? 0.16 : 0.65), lineWidth: 0.5)
                    }
                    .frame(width: geometry.size.width * 0.76, height: 48)
                    .offset(x: geometry.size.width * 0.25, y: 42)
            }.clipped()
        }
    }
}

private struct SettingsPreviewWallpaperTone: ViewModifier {
    @Environment(\.islandGlassColorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(scheme == .dark ? Color.black.opacity(0.42) : Color.white.opacity(0.14))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: scheme)
    }
}

/// Settings illustration with native materials, image wallpaper and one live task effect.
/// It has no task store, lifecycle timers or request handles.
private struct SettingsIslandPreview: View {
    @ObservedObject var preferences: AppPreferences
    let expandedWidth: CGFloat
    let maximumExpandedWidth: CGFloat
    private var copy: AppCopy { preferences.copy }
    private let secondary = Color(white: 133.0 / 255)
    private var previewHeight: CGFloat { IslandVibeLayout.headerHeight + IslandVibeLayout.rowHeight + IslandVibeLayout.listVerticalInset * 2 + IslandChromeMetrics.footerHeight }
    // Map the effective production width to the existing 510 pt illustration.
    // Reflow its content rather than scaling text, icons or the desktop backdrop.
    private var islandWidth: CGFloat { 510 * min(1, expandedWidth / max(1, maximumExpandedWidth)) }
    private var taskTitle: String {
        preferences.codexIslandPrivacy ? copy.text("Codex 任务", "Codex task")
            : copy.text("整理项目资料", "Organize project notes")
    }
    private var taskOperation: String {
        // Keep the privacy preview explicit instead of leaving an empty field.
        preferences.codexIslandPrivacy ? copy.text("内容已隐藏", "Content hidden")
            : copy.text("汇总文档，准备更新说明", "Summarizing notes for release")
    }
    private var accessibilityValue: String {
        let effect = preferences.codexActivityProgressEffect.displayName
        let privacy = preferences.codexIslandPrivacy
            ? copy.text("隐私模式已开启", "Privacy mode is on")
            : copy.text("隐私模式已关闭", "Privacy mode is off")
        let width = copy.text("展开宽度 \(Int(expandedWidth)) pt", "Expanded width \(Int(expandedWidth)) pt")
        return [copy.named(effect.simplifiedChinese, effect.english), privacy, width].joined(separator: ", ")
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                SettingsIslandPreviewAssets.image("Wallpaper")
                    .resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .modifier(SettingsPreviewWallpaperTone())
                    .clipShape(SettingsPreviewContour.shape)
                VStack(spacing: 0) {
                    header
                    taskCard.padding(.horizontal, IslandVibeLayout.listInset).padding(.vertical, IslandVibeLayout.listVerticalInset)
                    footer
                }
                .frame(width: islandWidth, height: previewHeight, alignment: .top)
                .background(alignment: .top) {
                    // Share the toolbar/card height budget so the footer stays inside the shell.
                    previewBackdrop
                        .modifier(IslandGlassColorScheme())
                        .frame(width: islandWidth, height: previewHeight)
                }
                if preferences.islandFloatingUsageEnabled && !preferences.codexIslandPrivacy {
                    // Fixed dual-period illustration; weekly sample matches the preview header.
                    // Never reads account data and never injects into the live island.
                    IslandUsageCapsuleContent(windows: [
                        .init(id: CodexDomainCatalog.primaryRateWindowID, usedPercent: 28, remainingPercent: 72,
                              windowDurationMinutes: 300, resetsAt: Date(timeIntervalSince1970: 3 * 3600 + 20 * 60)),
                        .init(id: CodexDomainCatalog.secondaryRateWindowID, usedPercent: 54, remainingPercent: 46,
                              windowDurationMinutes: 10080, resetsAt: Date(timeIntervalSince1970: 4 * 86400))
                    ], current: true, english: preferences.resolvedLanguage.usesLatinLayout,
                       now: Date(timeIntervalSince1970: 0))
                    .modifier(IslandGlassColorScheme())
                    .padding(.top, previewHeight + 8)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .environment(\.islandLiquidGlassEnabled, preferences.islandMaterial == .liquidGlass)
        .modifier(IslandGlassAppearanceContext(appearance: preferences.islandGlassAppearance, material: preferences.islandMaterial))
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(copy.text("灵动岛外观预览", "Island appearance preview"))
        .accessibilityValue(accessibilityValue)
        .transaction { $0.animation = nil }
    }

    @ViewBuilder private var previewBackdrop: some View {
        let shape = IslandNotchShape(bottomRadius: 24)
        if preferences.islandMaterial == .classic {
            shape.fill(.black)
        } else {
            ZStack {
                Color.clear.modifier(IslandNativeBackdropMaterial(shape: shape))
                let stops = AppPreferences.IslandGlassDegree.gradientStops(preferences.islandGlassDegree)
                LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
                    .clipShape(shape)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                SettingsIslandPreviewAssets.image("QuotaRing").frame(width: IslandChromeMetrics.quotaRingDiameter, height: IslandChromeMetrics.quotaRingDiameter)
                Text(copy.text("46% · 4 天", "46% · 4 d"))
                    .font(IslandChromeMetrics.font).foregroundStyle(.white).fixedSize()
            }
            .padding(.leading, IslandChromeMetrics.quotaRingLeadingInset)
            .padding(.trailing, IslandChromeMetrics.labelInset).frame(height: IslandChromeMetrics.buttonSize)
            .islandGlass(Capsule(), tint: .white.opacity(0.04), clearSurface: true)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                icon("pin")
                icon("chevron.up")
            }
            .frame(height: IslandChromeMetrics.buttonSize)
        }
        .padding(.horizontal, IslandChromeMetrics.horizontalInset).frame(height: IslandVibeLayout.headerHeight)
    }

    private var taskCard: some View {
        VStack(spacing: IslandVibeLayout.lineGap) {
            HStack(spacing: 6) {
                Text(taskTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .fixedSize()
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("6 Sol · High").font(.system(size: 10, weight: .semibold)).fixedSize()
                Rectangle().fill(Color(white: 61.0 / 255)).frame(width: 1, height: 9)
                Text("2m").font(.system(size: 10, weight: .semibold)).fixedSize()
                Image(systemName: "archivebox").font(.system(size: 12, weight: .medium))
                    .frame(width: 16, height: 16, alignment: .topLeading)
            }
            .frame(height: IslandVibeLayout.textRowHeight)
            HStack(spacing: 8) {
                Text(copy.text("工作中", "Working"))
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Color(white: 0.93)).fixedSize()
                Text("·").foregroundStyle(Color(white: 0.60))
                Text(taskOperation)
                    .foregroundStyle(Color(white: 0.80))
                    .fixedSize()
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("128K tokens")
                    .font(.system(size: 10, weight: .medium)).fixedSize()
            }
            .font(.system(size: 11)).frame(height: IslandVibeLayout.textRowHeight)
        }
        .lineLimit(1)
        .foregroundStyle(secondary)
        .padding(IslandVibeLayout.contentInset)
        .frame(height: IslandVibeLayout.rowHeight)
        .background {
            GeometryReader { geometry in
                SettingsLiveEffectPreview(effect: preferences.codexActivityProgressEffect)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipShape(IslandVibeLayout.rowShape)
            }
        }
        .islandGlass(IslandVibeLayout.rowShape, tint: .black.opacity(0.42), solidTint: Color(white: 0.055))
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(copy.text("1 个会话", "1 session")).fixedSize()
                .padding(.leading, IslandChromeMetrics.labelInset)
            Spacer(minLength: 0)
            Text(copy.text("1 工作中", "1 working")).fixedSize()
            icon("arrow.clockwise")
            icon("gearshape")
        }
        .font(IslandChromeMetrics.font).modifier(IslandGlassForeground())
        .frame(height: IslandChromeMetrics.buttonSize)
        .padding(.horizontal, IslandChromeMetrics.horizontalInset)
        .padding(.bottom, IslandChromeMetrics.bottomInset)
        .modifier(IslandGlassColorScheme())
    }

    private func icon(_ name: String) -> some View {
        Button {} label: {
            Image(systemName: name).font(IslandChromeMetrics.iconFont)
                .frame(width: IslandChromeMetrics.buttonSize, height: IslandChromeMetrics.buttonSize)
        }.buttonStyle(IslandUtilityButtonStyle(clearSurface: true))
    }

}

struct SettingsConnectionSummary: View {
    let provider: IslandAgentProvider
    let status: String
    let color: Color
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                if let icon = IslandProviderIcon.image(for: provider) {
                    Image(nsImage: icon).resizable().scaledToFit().frame(width: 16, height: 16)
                        .accessibilityHidden(true)
                }
                Text(provider.displayName).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SettingsStagePalette.primary).fixedSize()
                Spacer(minLength: 6)
                Circle().fill(color).frame(width: 5, height: 5).accessibilityHidden(true)
                Text(status).font(.system(size: 11)).foregroundStyle(SettingsStagePalette.secondary)
                    .lineLimit(1)
            }
            Text(detail).font(.system(size: 10)).foregroundStyle(SettingsStagePalette.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(Color(white: 0.05).opacity(0.77), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(white: 0.16), lineWidth: 1))
        .help([provider.displayName, status, detail].joined(separator: " · "))
        .accessibilityElement(children: .combine)
    }
}

private struct SettingsIslandNavigationButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Capsule(style: .continuous)
                .fill(Color.primary.opacity(configuration.isPressed ? 0.10 : hovered ? 0.06 : 0)))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
            .onHover { hovered = $0 }
            .onDisappear { hovered = false }
    }
}

private enum SettingsIllustrationPalette {
    static let secondary = Color.white.opacity(0.80)
    static let shadow = Color.black.opacity(0.24)
}

private struct NativeSettingsSidebarSurface: ViewModifier {
    let fallbackCornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(
                    Glass.regular,
                    in: ConcentricRectangle()
                )
                .clipShape(ConcentricRectangle())
        } else {
            content
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(
                        cornerRadius: fallbackCornerRadius,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: fallbackCornerRadius,
                        style: .continuous
                    )
                    .strokeBorder(
                        Color(nsColor: .separatorColor),
                        lineWidth: 0.75
                    )
                }
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: fallbackCornerRadius,
                        style: .continuous
                    )
                )
        }
    }
}

private extension View {
    func nativeSettingsSidebarSurface(
        fallbackCornerRadius: CGFloat
    ) -> some View {
        modifier(
            NativeSettingsSidebarSurface(
                fallbackCornerRadius: fallbackCornerRadius
            )
        )
    }

    func nativeSettingsActionStyle() -> some View {
        self.buttonStyle(SettingsActionButtonStyle())
    }

}

private struct SettingsWindowConfigurator: NSViewRepresentable {
    final class Coordinator {
        weak var configuredWindow: NSWindow?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configureWindow(for: view, coordinator: context.coordinator)
        }
        return view
    }

    func updateNSView(
        _ nsView: NSView,
        context: Context
    ) {
        DispatchQueue.main.async {
            configureWindow(
                for: nsView,
                coordinator: context.coordinator
            )
        }
    }

    private func configureWindow(
        for view: NSView,
        coordinator: Coordinator
    ) {
        guard let window = view.window else { return }

        window.styleMask.insert(.fullSizeContentView)
        window.appearance = NSAppearance(named: .darkAqua)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.toolbar = nil
        window.isMovableByWindowBackground = true
        SettingsWindowMetrics.applyOuterShape(to: window)
        window.hasShadow = true
        SettingsWindowMetrics.applySizingPolicy(to: window)

        if coordinator.configuredWindow !== window {
            coordinator.configuredWindow = window
            window.setContentSize(SettingsWindowMetrics.defaultContentSize)
        }
    }
}

private struct SettingsTrafficLightHost: NSViewRepresentable {
    func makeNSView(context: Context) -> TrafficLightHostingView {
        TrafficLightHostingView(frame: .zero)
    }

    func updateNSView(
        _ nsView: TrafficLightHostingView,
        context: Context
    ) {
        nsView.installWindowButtons()
    }

    final class TrafficLightHostingView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                self?.installWindowButtons()
            }
        }

        override func layout() {
            super.layout()
            installWindowButtons()
        }

        func installWindowButtons() {
            guard let window else { return }

            let buttonTypes: [NSWindow.ButtonType] = [
                .closeButton,
                .miniaturizeButton,
                .zoomButton
            ]
            let xOrigins: [CGFloat] = [11, 35, 59]

            for (buttonType, xOrigin) in zip(
                buttonTypes,
                xOrigins
            ) {
                guard let button = window.standardWindowButton(
                    buttonType
                ) else {
                    continue
                }

                if button.superview !== self {
                    addSubview(button)
                }
                if buttonType == .zoomButton { button.isEnabled = false }

                button.setFrameOrigin(
                    NSPoint(
                        x: xOrigin,
                        y: bounds.height
                            - 18
                            - button.bounds.height / 2
                    )
                )
            }
        }
    }
}

private struct CodexActivityPreviewOptionButtonStyle: ButtonStyle {
    let isSelected: Bool
    let isHovered: Bool
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .background(
                backgroundColor(isPressed: configuration.isPressed),
                in: RoundedRectangle(
                    cornerRadius: 10,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 10,
                    style: .continuous
                )
                .strokeBorder(
                    isSelected
                        ? Color(nsColor: .controlAccentColor)
                        : Color(nsColor: .separatorColor),
                    lineWidth: isSelected ? 1.5 : 0.5
                )
            }
            .scaleEffect(
                !reduceMotion && configuration.isPressed
                    ? 0.985
                    : 1
            )
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.08),
                value: configuration.isPressed
            )
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isPressed {
            return Color(nsColor: .controlAccentColor).opacity(0.14)
        }
        if isSelected {
            return Color(nsColor: .controlAccentColor).opacity(0.10)
        }
        if isHovered {
            return Color(nsColor: .controlAccentColor).opacity(0.05)
        }
        return Color(nsColor: .windowBackgroundColor)
    }
}

private struct CodexActivityTimingControl: View {
    let title: String
    let subtitle: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let secondsLabel: String

    private var values: [Int] {
        Array(stride(
            from: range.lowerBound,
            through: range.upperBound,
            by: step
        ))
    }

    private var sliderValue: Binding<Double> {
        Binding(
            get: { Double(value) },
            set: { value = Int($0.rounded()) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body.weight(.medium))
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 18)

                Text("\(value) \(secondsLabel)")
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 58, alignment: .trailing)
            }

            Slider(
                value: sliderValue,
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: Double(step)
            )
            .controlSize(.small)
            .accessibilityLabel(title)
            .accessibilityValue("\(value) \(secondsLabel)")

            HStack(alignment: .top, spacing: 0) {
                ForEach(values, id: \.self) { tick in
                    VStack(spacing: 3) {
                        Rectangle()
                            .fill(Color(nsColor: .tertiaryLabelColor))
                            .frame(
                                width: 1,
                                height: tick.isMultiple(of: 15) ? 6 : 4
                            )

                        if tick == range.lowerBound
                            || tick == range.upperBound
                        {
                            Text("\(tick)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        } else {
                            Color.clear.frame(height: 11)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
    }
}

private struct SettingsDetailIcon: View {
    let symbol: String

    var body: some View {
        SettingsSidebarIcon(
            symbol: symbol,
            color: Color(nsColor: .systemGray),
            size: SettingsLayoutMetrics.iconSize
        )
    }
}

private struct SettingsSidebarIcon: View {
    let symbol: String
    let color: Color
    // Sidebar and row icons share a 20 pt footprint; other sizes retain these proportions.
    var size: CGFloat = 20
    @Environment(\.colorSchemeContrast) private var contrast

    private var inset: CGFloat { (size * 3 / 22).rounded() }
    private var symbolSize: CGFloat { size - inset * 2 }
    private var cornerRadius: CGFloat { size * 5 / 22 }

    var body: some View {
        Image(systemName: symbol)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .symbolRenderingMode(.monochrome)
            .font(.system(size: symbolSize, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: symbolSize, height: symbolSize)
            .padding(inset)
            .frame(width: size, height: size)
            .fixedSize()
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(color.gradient)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(contrast == .increased ? 0.6 : 0.18), lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }
}

// A pop-up selection control lets AppKit position and highlight the selected item.
private struct SettingsValueMenu<Selection: Hashable>: NSViewRepresentable {
    let title: String
    @Binding var selection: Selection
    let options: [(Selection, String)]
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection, options: options) }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.isBordered = false
        button.controlSize = .small
        button.font = .systemFont(ofSize: 13)
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectItem(_:))
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.selection = $selection
        context.coordinator.options = options
        let titles = options.map { $0.1 }
        if button.itemTitles != titles {
            button.removeAllItems()
            // Add individual items so distinct values may share a localized label.
            for title in titles {
                button.menu?.addItem(NSMenuItem(title: title, action: nil, keyEquivalent: ""))
            }
        }
        button.selectItem(at: options.firstIndex { $0.0 == selection } ?? -1)
        button.isEnabled = isEnabled && !options.isEmpty
        button.setAccessibilityLabel(title)
        button.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
        let size = nsView.intrinsicContentSize
        return CGSize(width: size.width, height: max(24, size.height))
    }

    final class Coordinator: NSObject {
        var selection: Binding<Selection>
        var options: [(Selection, String)]

        init(selection: Binding<Selection>, options: [(Selection, String)]) {
            self.selection = selection
            self.options = options
        }

        @objc func selectItem(_ sender: NSPopUpButton) {
            let index = sender.indexOfSelectedItem
            guard options.indices.contains(index) else { return }
            selection.wrappedValue = options[index].0
        }
    }
}

private struct SettingsActionButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        let color = configuration.role == .destructive ? Color(nsColor: .systemRed)
            : prominent ? Color(nsColor: .controlAccentColor) : Color.primary
        configuration.label.font(.system(size: 13, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(color.opacity(configuration.isPressed ? 0.15 : hovered ? 0.10 : 0.06),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous)).opacity(enabled ? 1 : 0.4)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
            .onHover { hovered = enabled && $0 }
            .onChange(of: enabled) { _, value in if !value { hovered = false } }
            .onDisappear { hovered = false }
    }
}

private struct SettingsNavigationButtonStyle: ButtonStyle {
    let selected: Bool
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(.primary)
            .background(Color.primary.opacity(configuration.isPressed ? 0.13 : selected ? 0.10 : hovered ? 0.05 : 0),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous)).onHover { hovered = $0 }
            .onDisappear { hovered = false }
    }
}

enum SettingsEffectPreviewMetrics {
    static let previewCornerRadius = IslandVibeLayout.rowRadius
    static let inset: CGFloat = 3
    static let outerCornerRadius = previewCornerRadius + inset
    static let height: CGFloat = 44
}

private struct SettingsQuitRowStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(Color(nsColor: .systemRed))
            .background {
                RoundedRectangle(cornerRadius: SettingsLayoutMetrics.cardCornerRadius, style: .continuous)
                    .fill(.clear)
                    .background { SettingsGroupSurface() }
                    .overlay {
                        RoundedRectangle(cornerRadius: SettingsLayoutMetrics.cardCornerRadius, style: .continuous)
                            .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : hovered ? 0.06 : 0))
                    }
            }
            .contentShape(RoundedRectangle(cornerRadius: SettingsLayoutMetrics.cardCornerRadius, style: .continuous))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
            .onHover { hovered = $0 }.onDisappear { hovered = false }
    }
}

private struct SettingsFeedbackRowStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .background { SettingsGroupSurface() }
            .overlay {
                RoundedRectangle(cornerRadius: SettingsLayoutMetrics.cardCornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.10 : hovered ? 0.05 : 0))
                    .allowsHitTesting(false)
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
            .onHover { hovered = $0 }
            .onDisappear { hovered = false }
    }
}

private struct SettingsEffectOptionStyle: ButtonStyle {
    let effect: AppPreferences.CodexActivityProgressEffect
    let selected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 5) {
            // The grid owns the viewport width; an aspect-fill image must not
            // enlarge that width when the preview height changes.
            GeometryReader { geometry in
                SettingsIslandPreviewAssets.image(SettingsIslandPreviewAssets.effectName(effect))
                    .resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .background(Color(red: 0.065, green: 0.052, blue: 0.080))
                    .clipped()
            }
                .frame(height: SettingsEffectPreviewMetrics.height)
                .clipShape(RoundedRectangle(cornerRadius: SettingsEffectPreviewMetrics.previewCornerRadius, style: .continuous))
                .padding(SettingsEffectPreviewMetrics.inset)
                .background(Color.primary.opacity(configuration.isPressed ? 0.10 : hovered ? 0.06 : 0.025),
                            in: RoundedRectangle(cornerRadius: SettingsEffectPreviewMetrics.outerCornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: SettingsEffectPreviewMetrics.outerCornerRadius, style: .continuous)
                        .strokeBorder(selected ? Color(nsColor: .controlAccentColor) : .clear, lineWidth: 2)
                }
                .allowsHitTesting(false).accessibilityHidden(true)
            configuration.label.font(.system(size: 11, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? .primary : .secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity).contentShape(Rectangle())
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
        .onHover { hovered = $0 }.onDisappear { hovered = false }
    }
}

private struct SettingsVisualOptionStyle: ButtonStyle {
    let selected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(.primary).padding(12)
            .background(Color.primary.opacity(configuration.isPressed ? 0.10 : hovered ? 0.06 : 0.025),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Color(nsColor: .controlAccentColor) : Color(nsColor: .separatorColor), lineWidth: selected ? 1.5 : 0.5)
            }.contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
            .onHover { hovered = $0 }.onDisappear { hovered = false }
    }
}

/// Both providers use the same status and disclosure layout; their capabilities stay independent.
struct NativeSettingsConnectionStatus: View {
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 5, height: 5).accessibilityHidden(true)
            Text(title).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

struct NativeSettingsConnectionDetails<Content: View>: View {
    let copy: AppCopy
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 0, content: content)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(copy.text("连接详情", "Connection Details"))
                .font(.body.weight(.medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct SettingsScrollPositionReader: NSViewRepresentable {
    let onChange: (CGFloat, CGFloat) -> Void

    func makeNSView(context: Context) -> ObserverView { ObserverView() }
    func updateNSView(_ view: ObserverView, context: Context) {
        view.onChange = onChange
        DispatchQueue.main.async { [weak view] in view?.connect() }
    }
    static func dismantleNSView(_ view: ObserverView, coordinator: ()) { view.disconnect() }

    final class ObserverView: NSView {
        var onChange: ((CGFloat, CGFloat) -> Void)?
        private weak var scrollView: NSScrollView?
        private var observations: [NSObjectProtocol] = []
        private var lastMetrics: CGSize?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { disconnect() }
            else { DispatchQueue.main.async { [weak self] in self?.connect() } }
        }
        override func layout() {
            super.layout()
            DispatchQueue.main.async { [weak self] in self?.connect() }
        }
        func connect() {
            guard let scroll = enclosingScrollView else { return }
            if scrollView !== scroll {
                disconnect()
                scrollView = scroll
                scroll.contentView.postsBoundsChangedNotifications = true
                scroll.contentView.postsFrameChangedNotifications = true
                for name in [NSView.boundsDidChangeNotification, NSView.frameDidChangeNotification] {
                    observations.append(NotificationCenter.default.addObserver(forName: name, object: scroll.contentView, queue: .main) { [weak self] _ in self?.report() })
                }
            }
            report()
        }
        func report() {
            guard let scroll = scrollView, let document = scroll.documentView else { return }
            let visible = scroll.contentView.documentVisibleRect
            let offset = document.isFlipped ? visible.minY - document.bounds.minY : document.bounds.maxY - visible.maxY
            let metrics = CGSize(width: scroll.contentView.bounds.width, height: max(0, offset))
            guard metrics.width > 0, metrics != lastMetrics else { return }
            lastMetrics = metrics
            onChange?(metrics.height, metrics.width)
        }
        func disconnect() {
            observations.forEach(NotificationCenter.default.removeObserver)
            observations.removeAll()
            scrollView = nil
            lastMetrics = nil
        }
    }
}

private struct SettingsHeaderHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 294
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct SettingsPinnedPreviewBackdrop: View {
    let progress: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if reduceTransparency {
                Rectangle().fill(Color(nsColor: .windowBackgroundColor)).opacity(progress)
            } else {
                SettingsPinnedPreviewMaterial(progress: progress)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct SettingsPinnedPreviewMaterial: NSViewRepresentable {
    let progress: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        Self.configure(view, progress: progress)
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        Self.configure(view, progress: progress)
    }
    static func configure(_ view: NSVisualEffectView, progress: CGFloat) {
        view.material = .headerView
        view.blendingMode = .withinWindow
        view.state = .active
        // Fade the native backdrop itself. SwiftUI opacity/masks can flatten its sampling layer.
        view.alphaValue = max(0, min(1, progress))
    }
}

private struct SettingsChoiceRow<Choices: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let choices: () -> Choices

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            HStack(spacing: SettingsLayoutMetrics.iconGap) {
                SettingsDetailIcon(symbol: symbol)
                Text(title).font(.system(size: 13, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
            HStack(alignment: .top, spacing: 12, content: choices)
                .frame(width: SettingsLayoutMetrics.choiceWidth)
        }
        .padding(SettingsLayoutMetrics.cardInset)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

private struct SettingsGroupSurface: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        RoundedRectangle(cornerRadius: SettingsLayoutMetrics.cardCornerRadius, style: .continuous)
            .fill(Color(nsColor: .windowBackgroundColor))
            .overlay {
                RoundedRectangle(cornerRadius: SettingsLayoutMetrics.cardCornerRadius, style: .continuous)
                    .fill(colorScheme == .dark
                        ? Color.white.opacity(contrast == .increased ? 0.12 : 0.045)
                        : Color.white.opacity(contrast == .increased ? 1 : 0.7))
            }
            .allowsHitTesting(false)
    }
}

struct NativeSettingsCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity)
        .background { SettingsGroupSurface() }
        .clipShape(
            RoundedRectangle(
                cornerRadius: SettingsLayoutMetrics.cardCornerRadius,
                style: .continuous
            )
        )
    }
}

struct NativeSettingsRow<Control: View>: View {
    let title: String
    let subtitle: String?
    let symbol: String?
    let horizontalPadding: CGFloat
    let control: Control

    init(
        title: String,
        subtitle: String? = nil,
        symbol: String? = nil,
        horizontalPadding: CGFloat = SettingsLayoutMetrics.cardInset,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.horizontalPadding = horizontalPadding
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(alignment: .center, spacing: NativeSettingsDivider.iconGap) {
            if let symbol {
                SettingsDetailIcon(symbol: symbol)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            }

            control.controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, SettingsLayoutMetrics.rowVerticalInset)
        .frame(maxWidth: .infinity, minHeight: subtitle == nil
            ? SettingsLayoutMetrics.rowMinHeight : SettingsLayoutMetrics.describedRowMinHeight)
        .contentShape(Rectangle())
    }
}

/// A full-height editing surface independent of the row's compact control size.
private struct SettingsTextField: View {
    let placeholder: String
    @Binding var text: String
    @Environment(\.isEnabled) private var isEnabled
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .controlSize(.regular)
            .font(.system(size: 13))
            .focused($isFocused)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(isFocused ? Color.accentColor : Color(nsColor: .separatorColor),
                                  lineWidth: isFocused ? 1.5 : 0.5)
                    .allowsHitTesting(false)
            }
            .opacity(isEnabled ? 1 : 0.5)
    }
}

struct NativeSettingsSegmentedPicker<
    Selection: Hashable,
    Content: View
>: View {
    let title: String
    @Binding var selection: Selection
    let content: Content

    init(
        _ title: String,
        selection: Binding<Selection>,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        _selection = selection
        self.content = content()
    }

    var body: some View {
        Picker(title, selection: $selection) {
            content
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(.small)
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct NativeSettingsDivider: View {
    static let iconGap = SettingsLayoutMetrics.iconGap
    // Keep separators aligned with the text column.
    static let iconLeading = SettingsLayoutMetrics.cardInset + SettingsLayoutMetrics.iconSize + iconGap
    var leading: CGFloat = SettingsLayoutMetrics.cardInset
    var body: some View {
        Divider()
            .padding(.leading, leading)
    }
}

struct NativeSettingsNote: View {
    let text: String
    var horizontalPadding: CGFloat = 12

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MenuBarStatusLabel: View {
    @ObservedObject var store: CodexStatusStore
    @ObservedObject var preferences: AppPreferences
    var now: Date = Date()

    private var copy: AppCopy { preferences.copy }

    var body: some View {
        HStack(spacing: 3) {
            if let image = statusImage {
                Image(nsImage: image)
            }
            if !statusTextParts.isEmpty {
                Text(verbatim: statusTextParts.joined(separator: " "))
                    .monospacedDigit()
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(statusAccessibilityText)
    }

    var statusImage: NSImage? {
        if showsDualQuota && (preferences.showRemainingQuota || preferences.showResetCountdown) {
            return MenuBarQuotaImage.make(
                rows: quotaRows, showsIcon: preferences.showStatusIcon,
                showsQuota: preferences.showRemainingQuota
            )
        }
        return preferences.showStatusIcon ? MenuBarBrandIcon.statusImage : nil
    }

    var showsDualQuota: Bool {
        MenuBarQuotaImage.showsDualQuota(windows: store.snapshot?.quotaWindows ?? [])
    }

    var quotaRows: [MenuBarQuotaImage.Row] {
        MenuBarQuotaImage.rows(windows: store.snapshot?.quotaWindows ?? [],
            showsCountdown: preferences.showResetCountdown, now: now, copy: copy)
    }

    var singleQuotaRow: MenuBarQuotaImage.Row {
        MenuBarQuotaImage.singleRow(windows: store.snapshot?.quotaWindows ?? [],
            showsCountdown: preferences.showResetCountdown, now: now, copy: copy)
    }

    var statusTextParts: [String] {
        guard !showsDualQuota else { return [] }
        var parts: [String] = []
        if preferences.showRemainingQuota { parts.append(singleQuotaRow.value) }
        if preferences.showResetCountdown { parts.append(countdownLabel) }
        return parts
    }

    var statusAccessibilityText: String {
        var parts = [accessibilityStatus]
        if showsDualQuota {
            parts += MenuBarQuotaImage.rows(windows: store.snapshot?.quotaWindows ?? [],
                showsCountdown: true, now: now, copy: copy).map { row in
                copy.text("\(row.label) 剩余 \(row.value)，距重置 \(row.countdown ?? "—")",
                          "\(row.label) \(row.value) remaining, resets in \(row.countdown ?? "—")")
            }
        } else {
            parts.append(copy.text("\(singleQuotaRow.label) 剩余 \(singleQuotaRow.value)，距重置 \(countdownLabel)",
                                   "\(singleQuotaRow.label) \(singleQuotaRow.value) remaining, resets in \(countdownLabel)"))
        }
        return parts.joined(separator: ", ")
    }

    private var countdownLabel: String {
        MenuBarQuotaImage.countdown(until: store.snapshot?.resetsAt, now: now, copy: copy)
    }

    private var accessibilityStatus: String {
        if let error = store.errorMessage {
            return copy.text(
                "QuotaView：\(error)",
                "QuotaView: \(error)"
            )
        }
        if let snapshot = store.snapshot {
            return copy.text(
                "Codex \(availabilityLabel(snapshot.availability))，剩余 \(snapshot.remainingPercent)%",
                "Codex \(availabilityLabel(snapshot.availability)), \(snapshot.remainingPercent)% remaining"
            )
        }
        return copy.text(
            "QuotaView 正在连接",
            "QuotaView is connecting"
        )
    }

    private func availabilityLabel(
        _ availability: CurrentCodexPresentation.Availability
    ) -> String {
        switch availability {
        case .ready: copy.text("可用", "Available")
        case .limited: copy.text("受限", "Limited")
        case .exhausted: copy.text("已用尽", "Exhausted")
        }
    }
}

// A template image lets NSStatusBarButton apply the system menu-bar tint,
// including highlighted, light and dark appearances. Settings uses the same image.
enum MenuBarQuotaImage {
    struct Row: Equatable {
        let label: String
        let remaining: Int?
        var countdown: String? = nil
        var value: String { remaining.map { "\($0)%" } ?? "—%" }
    }

    // Follow the actual windows, not a subscription-name assumption. A weekly-only
    // Pro snapshot uses a native percentage and countdown text.
    static func showsDualQuota(windows: [CodexQuotaWindowPresentation]) -> Bool {
        windows.contains { $0.id == CodexDomainCatalog.primaryRateWindowID }
            && windows.contains { $0.id == CodexDomainCatalog.secondaryRateWindowID }
    }

    static func countdown(until reset: Date?, now: Date, copy: AppCopy) -> String {
        guard let reset else { return "—" }
        let seconds = max(0, reset.timeIntervalSince(now))
        if seconds == 0 { return copy.text("待刷新", "Due") }
        if seconds >= 86_400 { return copy.text("\(Int(seconds / 86_400))天", "\(Int(seconds / 86_400))d") }
        if seconds >= 3_600 { return copy.text("\(Int(seconds / 3_600))时", "\(Int(seconds / 3_600))h") }
        return copy.text("\(max(1, Int(ceil(seconds / 60))))分", "\(max(1, Int(ceil(seconds / 60))))m")
    }

    static func rows(windows: [CodexQuotaWindowPresentation], showsCountdown: Bool = false,
                     now: Date = Date(), copy: AppCopy = AppCopy(language: .english)) -> [Row] {
        [CodexDomainCatalog.primaryRateWindowID, CodexDomainCatalog.secondaryRateWindowID]
            .map { id in
                let window = windows.first { $0.id == id }
                return Row(label: periodLabel(window?.windowDurationMinutes),
                           remaining: window.map { min(100, max(0, $0.remainingPercent)) },
                           countdown: showsCountdown ? countdown(until: window?.resetsAt, now: now, copy: copy) : nil)
            }
    }

    static func singleRow(windows: [CodexQuotaWindowPresentation], showsCountdown: Bool,
                          now: Date, copy: AppCopy) -> Row {
        let window = windows.first { $0.id == CodexDomainCatalog.primaryRateWindowID }
            ?? windows.first { $0.id == CodexDomainCatalog.secondaryRateWindowID }
        return Row(label: periodLabel(window?.windowDurationMinutes),
                   remaining: window.map { min(100, max(0, $0.remainingPercent)) },
                   countdown: showsCountdown ? countdown(until: window?.resetsAt, now: now, copy: copy) : nil)
    }

    private static func periodLabel(_ minutes: Int?) -> String {
        guard let minutes, minutes > 0 else { return "—" }
        if minutes % 1_440 == 0 { return "\(minutes / 1_440)d" }
        if minutes % 60 == 0 { return "\(minutes / 60)h" }
        return "\(minutes)m"
    }

    static func make(rows: [Row], showsIcon: Bool, showsQuota: Bool = true) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let labelWidth = max(14, rows.map { ($0.label as NSString).size(withAttributes: attributes).width }.max() ?? 14)
        let valueWidth = ("100%" as NSString).size(withAttributes: attributes).width.rounded(.up)
        let origin: CGFloat = showsIcon ? 23 : 0
        let barX = origin + labelWidth + 5
        let barWidth: CGFloat = 24
        let valueX = barX + barWidth + 5
        let countdownX = showsQuota ? valueX + valueWidth + 6 : barX
        let countdownWidth = rows.compactMap(\.countdown).map {
            max(("00m" as NSString).size(withAttributes: attributes).width,
                ($0 as NSString).size(withAttributes: attributes).width)
        }.max()
        let size = NSSize(width: countdownWidth.map { countdownX + $0 } ?? (valueX + valueWidth), height: 22)
        let image = NSImage(size: size, flipped: false) { _ in
            if showsIcon {
                MenuBarBrandIcon.statusImage.draw(in: NSRect(x: 0, y: 3, width: 20, height: 16))
            }
            for (index, row) in rows.prefix(2).enumerated() {
                let y: CGFloat = index == 0 ? 11 : 0
                (row.label as NSString).draw(at: NSPoint(x: origin, y: y), withAttributes: attributes)
                if showsQuota {
                let track = NSRect(x: barX, y: y + 4, width: barWidth, height: 4)
                NSColor.black.withAlphaComponent(0.22).setFill()
                NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2).fill()
                if let remaining = row.remaining, remaining > 0 {
                    NSColor.black.setFill()
                    NSGraphicsContext.saveGraphicsState()
                    NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2).addClip()
                    NSRect(x: track.minX, y: track.minY,
                           width: barWidth * CGFloat(remaining) / 100, height: track.height).fill()
                    NSGraphicsContext.restoreGraphicsState()
                }
                let width = (row.value as NSString).size(withAttributes: attributes).width
                (row.value as NSString).draw(at: NSPoint(x: valueX + valueWidth - width, y: y), withAttributes: attributes)
                }
                if let countdown = row.countdown {
                    (countdown as NSString).draw(at: NSPoint(x: countdownX, y: y), withAttributes: attributes)
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

struct MenuBarBrandIcon: View {
    private enum Metrics {
        static let glyphWidth: CGFloat = 15
        static let height: CGFloat = 16
        static let nativeTextGap: CGFloat = 3
        static let desiredTextGap: CGFloat = 8
        static let trailingGutter = desiredTextGap - nativeTextGap
        static let canvasWidth = glyphWidth + trailingGutter
    }

    static let statusImage: NSImage = {
        let canvasSize = NSSize(
            width: Metrics.canvasWidth,
            height: Metrics.height
        )

        guard let source = NSImage(named: "QuotaViewMenuIcon") else {
            let image = NSImage(size: canvasSize)
            image.isTemplate = true
            return image
        }

        let image = NSImage(
            size: canvasSize,
            flipped: false
        ) { _ in
            source.draw(
                in: NSRect(
                    x: 0,
                    y: 0,
                    width: Metrics.glyphWidth,
                    height: Metrics.height
                ),
                from: NSRect(origin: .zero, size: source.size),
                operation: .sourceOver,
                fraction: 1
            )
            return true
        }
        image.isTemplate = true
        return image
    }()

    var body: some View {
        Image(nsImage: Self.statusImage)
            .frame(
                width: Metrics.canvasWidth,
                height: Metrics.height
            )
    }
}


extension AppCopy {
    func proxyFailure(_ failure: ProxyConnectionFailure) -> String {
        switch failure {
        case .invalidHost:
            text("请输入有效 IP 或主机名，不要包含协议、路径或账号密码。", "Enter a valid IP or hostname without a protocol, path, or credentials.")
        case .invalidPort:
            text("端口必须是 1–65535 的整数。", "Port must be an integer from 1 to 65535.")
        case .authenticationUnsupported:
            text("首版不支持需要账号密码的代理。", "Proxies requiring a username or password are not supported.")
        case .codexNotFound:
            text("找不到 Codex，请先安装 Codex。", "Codex was not found. Install Codex first.")
        case .timedOut:
            text("查询超时，请检查代理地址、端口和网络。", "The request timed out. Check the proxy address, port, and network.")
        case .permissionDenied:
            text("无法访问账户额度，请检查 Codex 登录状态和账户权限。", "Quota access was denied. Check your Codex sign-in and account permissions.")
        case .invalidResponse:
            text("连接未返回有效额度数据。", "The connection did not return valid quota data.")
        case .connectionFailed:
            text("额度查询失败，请检查代理是否可用，以及 Codex 是否已登录。", "Quota request failed. Check that the proxy is available and Codex is signed in.")
        }
    }

    func proxyTestStatus(_ state: ProxyConnectionTestState) -> String {
        switch state {
        case .idle: text("连接测试会通过代理查询账户额度。", "The connection test queries account quota through the proxy.")
        case .testing: text("正在通过代理查询额度…", "Querying quota through the proxy…")
        case .success: text("连接成功，已获取有效额度数据。", "Connected. Valid quota data was received.")
        case .failed(let failure): proxyFailure(failure)
        }
    }
}
