import AppKit
import QuotaViewCore
import SwiftUI

enum SettingsWindowMetrics {
    static let defaultContentSize = NSSize(width: 872, height: 760)
    static let minimumContentSize = NSSize(width: 780, height: 560)
    static let outerCornerRadius: CGFloat = 36
    static let contentMaxWidth: CGFloat = 744
    static let contentInset: CGFloat = 32
    static let sidebarInset: CGFloat = 16
    static let fallbackSidebarCornerRadius: CGFloat =
        outerCornerRadius - sidebarInset

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

enum IslandSettingsPage: String, CaseIterable, Identifiable {
    case general, island, usage, connections, proxy, feedback, about
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .island: "sparkles.rectangle.stack.fill"
        case .usage: "chart.bar.xaxis"
        case .connections: "point.3.connected.trianglepath.dotted"
        case .proxy: "network"
        case .feedback: "ladybug.fill"
        case .about: "info.circle.fill"
        }
    }
    var color: NSColor {
        switch self {
        case .general: .systemBlue
        case .island: .systemPurple
        case .usage: .systemPink
        case .connections: .systemCyan
        case .proxy: .systemTeal
        case .feedback: .systemOrange
        case .about: .systemIndigo
        }
    }
    func title(_ copy: AppCopy) -> String {
        switch self {
        case .general: copy.text("通用", "General")
        case .island: copy.text("灵动岛", "Island")
        case .usage: copy.text("用量显示", "Usage display")
        case .connections: copy.text("连接", "Connections")
        case .proxy: copy.text("网络代理", "Network proxy")
        case .feedback: copy.text("Bug 反馈", "Bug feedback")
        case .about: copy.text("关于", "About")
        }
    }
    func subtitle(_ copy: AppCopy) -> String {
        switch self {
        case .general: copy.text("语言、设置窗口外观与应用控制。", "Language, settings appearance and app controls.")
        case .island: copy.text("灵动岛的隐私、自动弹出与任务特效。", "Privacy, automatic popups and task effects for the island.")
        case .usage: copy.text("选择用量页显示的可选模块。", "Choose the optional modules on the usage page.")
        case .connections: copy.text("管理 Codex、Claude Code、DSH 和 Kimi Code 的任务接入。", "Manage task integrations for Codex, Claude Code, DSH and Kimi Code.")
        case .proxy: copy.text("查询额度与用量时使用的网络代理。", "The network proxy used for quota and usage queries.")
        case .feedback: copy.text("遇到问题时，通过以下方式联系我们。", "Reach us here when something goes wrong.")
        case .about: copy.text("版本信息与软件更新。", "Version information and software updates.")
        }
    }
}

enum SettingsFeedbackResources {
    @MainActor
    static let appIcon: NSImage = {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) { return image }
        return NSImage(named: "QuotaViewAppIcon") ?? NSApplication.shared.applicationIconImage
    }()

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

    private var copy: AppCopy { preferences.copy }

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    settingsTopBar
                        .zIndex(1)
                    settingsStage(for: selection ?? .general)
                }
                .frame(maxWidth: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
                settingsDetail(for: selection ?? .general)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .tint(Color(nsColor: .controlAccentColor))
        .buttonStyle(SettingsActionButtonStyle())
        .frame(
            minWidth: SettingsWindowMetrics.minimumContentSize.width,
            idealWidth: SettingsWindowMetrics.defaultContentSize.width,
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

    // Narrow windows retain every destination and expand only the current label.
    private static let navigationGroups: [[IslandSettingsPage]] = [
        [.general, .island, .usage], [.connections, .proxy, .feedback], [.about]
    ]

    private var settingsTopBar: some View {
        ViewThatFits(in: .horizontal) {
            settingsNavigationPill(showsAllLabels: true)
            settingsNavigationPill(showsAllLabels: false)
        }
        .padding(.horizontal, 96)
        .frame(maxWidth: .infinity)
        .frame(height: 60)
        .overlay(alignment: .topLeading) {
            SettingsTrafficLightHost()
                .frame(width: 84, height: 44)
                .padding(.leading, 8)
                .padding(.top, 9)
        }
    }

    private func settingsNavigationPill(showsAllLabels: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(Self.navigationGroups.enumerated()), id: \.offset) { index, group in
                if index > 0 {
                    Capsule().fill(Color.primary.opacity(0.16)).frame(width: 1, height: 14)
                        .padding(.horizontal, 5).accessibilityHidden(true)
                }
                ForEach(group) { page in
                    settingsNavigationItem(page, showsLabel: showsAllLabels || selection == page)
                }
            }
        }
        .padding(4)
        .background(Color.primary.opacity(0.10), in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous)
            .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1))
        .fixedSize()
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86), value: selection)
    }

    private func settingsNavigationItem(_ page: IslandSettingsPage, showsLabel: Bool) -> some View {
        let selected = selection == page
        return Button { selection = page; focusedPage = page } label: {
            HStack(spacing: 6) {
                Image(systemName: page.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selected ? Color.white : Color.secondary)
                    .frame(width: 15, height: 15)
                if showsLabel {
                    Text(page.title(copy))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(selected ? Color.white : Color.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .padding(.horizontal, showsLabel ? 11 : 8)
            .frame(height: 28)
            .background {
                if selected {
                    Capsule(style: .continuous)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.13) : Color.black.opacity(0.70))
                }
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(SettingsIslandNavigationButtonStyle())
        .focused($focusedPage, equals: page)
        .help(page.title(copy))
        .accessibilityLabel(page.title(copy))
        .accessibilityValue(selected ? copy.text("已选择", "Selected") : "")
        .onKeyPress(.rightArrow) { navigateSettings(from: page, offset: 1) }
        .onKeyPress(.leftArrow) { navigateSettings(from: page, offset: -1) }
    }

    private func navigateSettings(from page: IslandSettingsPage, offset: Int) -> KeyPress.Result {
        let pages = IslandSettingsPage.allCases
        guard let index = pages.firstIndex(of: page) else { return .ignored }
        let next = pages[max(0, min(pages.count - 1, index + offset))]
        selection = next; focusedPage = next
        return .handled
    }

    private func settingsDetail(
        for page: IslandSettingsPage
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                settingsPageHeading(for: page)
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
            .padding(.top, 24)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .id(page)
        .transition(.opacity)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: selection)
    }

    private func settingsPageHeading(for page: IslandSettingsPage) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                SettingsSidebarIcon(symbol: page.symbol, color: Color(nsColor: page.color), size: 28)
                Text(page.title(copy))
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            Text(page.subtitle(copy))
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func settingsStage(for page: IslandSettingsPage) -> some View {
        // Only these pages need a separate illustration above their controls.
        if page == .island || page == .proxy || page == .about {
            let height: CGFloat = page == .island ? 212 : 160
            settingsStageVisual(for: page)
                .environment(\.colorScheme, .dark)
                .frame(maxWidth: 760)
                .frame(height: height)
                .padding(.horizontal, SettingsWindowMetrics.contentInset)
                .padding(.top, 12)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func settingsStageVisual(for page: IslandSettingsPage) -> some View {
        switch page {
        case .general, .usage, .connections, .feedback: EmptyView()
        case .island: islandStageVisual
        case .proxy:
            supplementarySettingsStage(width: 500) { proxyStageVisual }
        case .about:
            supplementarySettingsStage(width: 400) { aboutStageVisual }
        }
    }

    private func supplementarySettingsStage<Content: View>(width: CGFloat, @ViewBuilder content: @escaping () -> Content) -> some View {
        SettingsDesktopPreview {
            content()
                .frame(maxWidth: width)
                .padding(12)
                .padding(.horizontal, 24)
        }
    }

    // This illustration responds only to preferences, never live tasks or timers.
    private var islandStageVisual: some View {
        SettingsIslandPreview(preferences: preferences)
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

    // Proxy: the path a quota request takes, drawn from the draft being edited.
    private var proxyStageVisual: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 0) {
                proxyStageNode(title: "QuotaView", image: SettingsFeedbackResources.appIcon)
                proxyStageConnector(segment: 0)
                proxyStageNode(
                    title: proxyDraft.isEnabled ? (proxyDraft.scheme == .http ? "HTTP" : "SOCKS5") : copy.text("直连", "Direct"),
                    symbol: proxyDraft.isEnabled ? "network" : "arrow.up.right")
                .contentTransition(.opacity)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: proxyDraft.isEnabled)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: proxyDraft.scheme)
                proxyStageConnector(segment: 1)
                proxyStageNode(title: copy.text("用量服务", "Usage service"), symbol: "cloud")
            }
            HStack(spacing: 9) {
                if proxyDraft.isEnabled {
                    Text(proxyStageAddress).monospacedDigit()
                        .lineLimit(1).truncationMode(.middle).help(proxyStageAddress)
                    Text("·").accessibilityHidden(true)
                }
                HStack(spacing: 5) {
                    Image(systemName: proxyStageStatus.symbol)
                        .foregroundStyle(proxyStageStatus.tint).accessibilityHidden(true)
                    Text(proxyStageStatus.text).lineLimit(1)
                }
                .fixedSize()
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(SettingsIllustrationPalette.secondary)
            .shadow(color: SettingsIllustrationPalette.shadow, radius: 3, y: 1)
            .contentTransition(.opacity)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: proxyStageStatus.text)
        }
        .accessibilityElement(children: .combine)
    }

    private func proxyStageNode(title: String, image: NSImage? = nil, symbol: String = "app") -> some View {
        VStack(spacing: 9) {
            Group {
                if let image {
                    Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                        .frame(width: 36, height: 36)
                } else {
                    Image(systemName: symbol).font(.system(size: 24, weight: .regular))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 52, height: 52)
            .modifier(SettingsProxyIconSurface())
            .accessibilityHidden(true)
            Text(title).font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white).lineLimit(1)
                .shadow(color: SettingsIllustrationPalette.shadow, radius: 3, y: 1)
        }
        .frame(width: 104)
    }

    private func proxyStageConnector(segment: Int) -> some View {
        HStack(spacing: 3) {
            Capsule().fill(Color.white.opacity(0.30)).frame(height: 1)
                .overlay {
                    SettingsProxyFlow(isActive: proxyStageFlowActive,
                                      isTesting: store.proxyTestState == .testing,
                                      segment: segment, reduceMotion: reduceMotion)
                        .frame(height: 10)
                }
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .medium)).foregroundStyle(Color.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity).frame(height: 52)
        .shadow(color: SettingsIllustrationPalette.shadow, radius: 2, y: 1)
        .accessibilityHidden(true)
    }

    private var proxyStageFlowActive: Bool {
        // Decorative route direction, not a measurement of live network traffic.
        guard proxyDraft.isEnabled else { return true }
        if case .failed = store.proxyTestState { return false }
        return proxyValidationFailure == nil
    }

    private var proxyStageAddress: String {
        guard proxyDraft.isEnabled else { return copy.text("未启用自定义代理", "No custom proxy") }
        let host = proxyDraft.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = proxyDraft.port.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, !port.isEmpty else { return copy.text("请填写地址与端口", "Enter host and port") }
        return host + ":" + port
    }

    private var proxyStageStatus: (symbol: String, text: String, tint: Color) {
        guard proxyDraft.isEnabled else {
            return ("arrow.up.right", copy.text("直连模式", "Direct connection"), SettingsIllustrationPalette.secondary)
        }
        if proxyValidationFailure != nil {
            return ("exclamationmark.circle.fill", copy.text("请检查代理配置", "Check proxy configuration"), .orange)
        }
        return switch store.proxyTestState {
        case .idle: ("circle.dashed", copy.text("未测试", "Not tested"), SettingsIllustrationPalette.secondary)
        case .testing: ("hourglass", copy.text("测试中", "Testing"), .white)
        case .success: ("checkmark.circle.fill", copy.text("可连接", "Reachable"), .green)
        case .failed: ("xmark.circle.fill", copy.text("连接失败", "Failed"), .red)
        }
    }

    // About: identity and the exact build that is running.
    private var aboutStageVisual: some View {
        HStack(spacing: 22) {
            Image(nsImage: SettingsFeedbackResources.appIcon)
                .resizable().interpolation(.high).scaledToFit().frame(width: 80, height: 80)
                .shadow(color: SettingsIllustrationPalette.shadow, radius: 10, y: 5)
                .accessibilityLabel(copy.text("QuotaView 应用图标", "QuotaView app icon"))
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("QuotaView").font(.system(size: 28, weight: .semibold)).foregroundStyle(.white)
                    Text(copy.text("Codex 任务与用量灵动岛", "Codex task and usage island"))
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Color.white.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .shadow(color: SettingsIllustrationPalette.shadow, radius: 3, y: 1)
                Text(versionAndBuildLabel)
                    .font(.system(size: 11, weight: .medium)).monospacedDigit()
                    .foregroundStyle(SettingsIllustrationPalette.secondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .shadow(color: SettingsIllustrationPalette.shadow, radius: 3, y: 1)
                    .textSelection(.enabled)
            }
        }
        // Center the visible icon/text group, excluding unused trailing space.
        .fixedSize(horizontal: true, vertical: false)
    }

    private var proxyValidationFailure: ProxyConnectionFailure? {
        do { _ = try proxyDraft.validated(); return nil }
        catch { return .classify(error) }
    }

    private var proxySettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            NativeSettingsCard {
                NativeSettingsRow(
                    title: copy.text("自定义代理", "Custom proxy"),
                    subtitle: copy.text("保存后生效。", "Save to apply changes."),
                    symbol: "network", symbolColor: Color(nsColor: .systemTeal)
                ) {
                    Toggle(copy.text("自定义代理", "Custom proxy"), isOn: $proxyDraft.isEnabled)
                        .labelsHidden().toggleStyle(.switch).tint(Color(nsColor: .secondaryLabelColor)).controlSize(.small)
                        .help(copy.text("使用此代理查询额度与用量。", "Use this proxy for quota and usage."))
                }
                NativeSettingsDivider(leading: NativeSettingsDivider.iconLeading)
                NativeSettingsRow(title: copy.text("协议", "Protocol"),
                    symbol: "arrow.left.arrow.right", symbolColor: Color(nsColor: .systemIndigo)) {
                    SettingsValueMenu(title: copy.text("代理协议", "Proxy protocol"), selection: $proxyDraft.scheme,
                        options: [(.http, "HTTP"), (.socks5, "SOCKS5")])
                    .disabled(!proxyDraft.isEnabled)
                }
                NativeSettingsDivider(leading: NativeSettingsDivider.iconLeading)
                NativeSettingsRow(
                    title: copy.text("服务器地址", "Server address"),
                    subtitle: copy.text("IP 或主机名，不含协议。", "IP or hostname, without a protocol prefix."),
                    symbol: "server.rack", symbolColor: Color(nsColor: .systemGray)
                ) {
                    TextField("127.0.0.1", text: $proxyDraft.host)
                        .textFieldStyle(.roundedBorder).frame(width: 190)
                        .accessibilityLabel(copy.text("代理服务器地址", "Proxy server address"))
                        .disabled(!proxyDraft.isEnabled)
                }
                NativeSettingsDivider(leading: NativeSettingsDivider.iconLeading)
                NativeSettingsRow(title: copy.text("端口", "Port"),
                    symbol: "number", symbolColor: Color(nsColor: .systemGray)) {
                    TextField("7890", text: $proxyDraft.port)
                        .textFieldStyle(.roundedBorder).frame(width: 100)
                        .accessibilityLabel(copy.text("代理端口", "Proxy port"))
                        .disabled(!proxyDraft.isEnabled)
                }
            }
            Text(copy.text(
                "支持无需认证的 HTTP / SOCKS5 代理。",
                "Supports HTTP / SOCKS5 proxies without authentication."
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
            HStack(spacing: 8) {
                if store.proxyTestState == .testing {
                    ProgressView().controlSize(.small)
                }
                Text(copy.proxyTestStatus(store.proxyTestState))
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(proxyDraft == preferences.proxyConfiguration
                 ? copy.text("已保存", "Saved")
                 : copy.text("有未保存的更改", "Unsaved changes"))
                .font(.footnote).foregroundStyle(.secondary)
        }
        .onAppear { proxyDraft = preferences.proxyConfiguration }
        .onDisappear { store.cancelProxyTest() }
        .onChange(of: proxyDraft) { _, _ in
            proxySaveFailure = nil
            store.cancelProxyTest()
        }
    }

    private var appearanceSelection: Binding<String> {
        .init(get: { preferences.followsSystemAppearance ? "system" : preferences.customAppearance.rawValue },
              set: { value in
                  preferences.followsSystemAppearance = value == "system"
                  if let mode = AppPreferences.AppearanceMode(rawValue: value) { preferences.customAppearance = mode }
              })
    }

    private var appearanceSettings: some View {
        NativeSettingsCard {
            HStack(spacing: 12) {
                appearanceOption("system", copy.text("跟随系统", "System"))
                appearanceOption("light", copy.text("浅色", "Light"))
                appearanceOption("dark", copy.text("深色", "Dark"))
            }.padding(18)
            NativeSettingsDivider()
            NativeSettingsNote(text: appearanceSummary)
        }
    }

    private func appearanceOption(_ value: String, _ title: String) -> some View {
        Button { appearanceSelection.wrappedValue = value } label: {
            VStack(spacing: 9) {
                SettingsAppearancePreview(mode: value)
                    .frame(width: value == "system" ? nil : 120, height: 70)
                Text(title).font(.system(size: 13, weight: .medium))
            }.frame(maxWidth: .infinity)
        }.buttonStyle(SettingsVisualOptionStyle(selected: appearanceSelection.wrappedValue == value))
            .accessibilityLabel(title)
            .accessibilityValue(appearanceSelection.wrappedValue == value ? copy.text("已选择", "Selected") : "")
    }

    private var islandSettings: some View {
        VStack(alignment: .leading, spacing: 24) {
            settingsSection(copy.text("显示", "Display")) {
                NativeSettingsCard {
                    preferenceToggle(copy.text("隐私模式", "Privacy mode"),
                        subtitle: copy.text("隐藏任务内容和账户数据。", "Hide task contents and account data."),
                        symbol: "eye.slash.fill", color: .systemGray,
                        isOn: $preferences.codexIslandPrivacy)
                }
            }
            settingsSection(copy.text("任务特效", "Task effects")) {
                LazyVGrid(columns: Array(repeating: .init(.flexible()), count: AppPreferences.CodexActivityProgressEffect.allCases.count), spacing: 8) {
                    ForEach(AppPreferences.CodexActivityProgressEffect.allCases) { effect in
                        Button { preferences.codexActivityProgressEffect = effect } label: {
                            Text(copy.text(effect.displayName.simplifiedChinese, effect.displayName.english))
                        }.buttonStyle(SettingsEffectOptionStyle(effect: effect, selected: preferences.codexActivityProgressEffect == effect))
                            .accessibilityLabel(copy.text(effect.displayName.simplifiedChinese, effect.displayName.english))
                            .accessibilityValue(preferences.codexActivityProgressEffect == effect ? copy.text("已选择", "Selected") : "")
                    }
                }
            }
            settingsSection(copy.text("自动展开", "Automatic opening")) {
                NativeSettingsCard {
                    preferenceToggle(copy.text("自动弹出", "Automatic popups"),
                        subtitle: copy.text("新任务、完成或待确认时弹出。", "Open for new tasks, completions and requests."),
                        symbol: "macwindow.badge.plus", color: .systemPurple,
                        isOn: $preferences.codexActivityAutomaticPopupEnabled)
                    NativeSettingsDivider(leading: NativeSettingsDivider.iconLeading)
                    NativeSettingsRow(title: copy.text("停留时间", "Stay open for"),
                        subtitle: copy.text("待确认或固定时保持展开。", "Stay open for pending requests or when pinned."),
                        symbol: "timer", symbolColor: Color(nsColor: .systemOrange)) {
                        SettingsValueMenu(title: copy.text("停留时间", "Popup duration"),
                            selection: $preferences.codexActivityAutomaticPopupDuration,
                            options: AppPreferences.CodexActivityAutomaticPopupTiming.durationRange.map {
                                ($0, copy.text("\($0) 秒", "\($0) s"))
                            })
                            .disabled(!preferences.codexActivityAutomaticPopupEnabled)
                    }
                }
            }
        }
    }

    private var usageSettings: some View {
        settingsSection(copy.text("可选模块", "Optional modules")) {
            NativeSettingsCard {
                preferenceToggle(copy.text("成本估算", "Cost estimate"),
                    subtitle: copy.text("最近 30 天的估算成本。", "Estimated costs for the last 30 days."),
                    symbol: "dollarsign.circle.fill", color: .systemGreen,
                    isOn: $preferences.showEstimatedCost)
                NativeSettingsDivider(leading: NativeSettingsDivider.iconLeading)
                preferenceToggle(copy.text("Token 活动", "Token activity"),
                    subtitle: copy.text("每日、每周和累计用量。", "Daily, weekly and cumulative usage."),
                    symbol: "square.grid.3x3.fill", color: .systemBlue,
                    isOn: $preferences.showTokenActivity)
                NativeSettingsDivider()
                NativeSettingsNote(text: copy.text(
                    "额度、Token 统计与账户信息始终显示；关闭的模块不占位。",
                    "Quota, token totals and account details are always shown; hidden modules leave no gap."))
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
    private var languageSettings: some View {
        NativeSettingsCard {
            NativeSettingsRow(title: copy.text("语言", "Language"), subtitle: languageSummary,
                symbol: "globe", symbolColor: Color(nsColor: .systemBlue)) {
                SettingsValueMenu(title: copy.text("语言", "Language"), selection: languageSelection,
                    options: [("system", copy.text("跟随系统", "System")), (AppPreferences.Language.simplifiedChinese.rawValue, "简体中文"), (AppPreferences.Language.english.rawValue, "English")])
            }
        }
    }

    private func settingsSection<Content: View>(
        _ title: String,
        provider: IslandAgentProvider? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if let provider, let icon = IslandProviderIcon.image(for: provider) {
                    Image(nsImage: icon).resizable().scaledToFit()
                        .padding(provider == .claudeCode ? 4 : 0)
                        .frame(width: 22, height: 22)
                        .background(provider == .claudeCode
                            ? Color(red: 0.96, green: 0.94, blue: 0.91) : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .accessibilityHidden(true)
                }
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)
            }
            .padding(.leading, 10)
            content()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 22) {
            settingsSection(copy.text("语言", "Language")) { languageSettings }
            settingsSection(copy.text("设置窗口外观", "Settings appearance")) { appearanceSettings }
            Button(role: .destructive) { showsQuitConfirmation = true } label: {
                Label(copy.text("退出 QuotaView", "Quit QuotaView"), systemImage: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 14, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18).frame(height: 52)
            }
            .buttonStyle(SettingsQuitRowStyle())
        }
    }

    private var feedbackSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button { showsFeedbackQRCode = true } label: {
                feedbackRow(
                    title: copy.text("QQ群", "QQ group"),
                    detail: copy.text("群号：1108649282", "Group: 1108649282"),
                    symbol: "qrcode", color: .systemBlue
                )
            }
            .buttonStyle(SettingsFeedbackRowStyle())
            .help(copy.text("显示群二维码", "Show the group QR code"))

            Link(destination: SettingsFeedbackResources.issuesURL) {
                feedbackRow(
                    title: "GitHub Issues",
                    detail: "Duoasa / QuotaView",
                    symbol: "chevron.left.forwardslash.chevron.right", color: .systemGray,
                    trailingSymbol: "arrow.up.right"
                )
            }
            .buttonStyle(SettingsFeedbackRowStyle())
            .help(copy.text("在浏览器中打开反馈页面", "Open the feedback page in your browser"))
        }
    }

    private func feedbackRow(title: String, detail: String, symbol: String, color: NSColor,
                             trailingSymbol: String = "chevron.right") -> some View {
        HStack(spacing: 14) {
            SettingsSidebarIcon(symbol: symbol, color: Color(nsColor: color), size: 30)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 14, weight: .medium))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Image(systemName: trailingSymbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
        VStack(alignment: .leading, spacing: 22) {
            settingsSection(copy.text("软件更新", "Software updates")) {
                NativeSettingsCard {
                    if updateController.availability == .available {
                        NativeSettingsRow(title: copy.text("检查更新", "Check for updates"), subtitle: updateStatusText,
                            symbol: "arrow.triangle.2.circlepath", symbolColor: Color(nsColor: .systemBlue)) {
                            Button(copy.text("检查更新…", "Check for Updates…")) { updateController.checkForUpdates() }
                                .nativeSettingsActionStyle().disabled(!updateController.canCheckForUpdates).help(updateCheckHelpText)
                        }
                        NativeSettingsDivider(leading: NativeSettingsDivider.iconLeading)
                        NativeSettingsRow(title: copy.text("自动检查更新", "Automatically check for updates"),
                            symbol: "clock.arrow.circlepath", symbolColor: Color(nsColor: .systemGreen)) {
                            Toggle(copy.text("自动检查更新", "Automatically check for updates"), isOn: Binding(
                                get: { updateController.automaticallyChecksForUpdates },
                                set: { updateController.setAutomaticallyChecksForUpdates($0) }))
                                .labelsHidden().toggleStyle(.switch).tint(Color(nsColor: .secondaryLabelColor)).controlSize(.small)
                        }
                    } else {
                        NativeSettingsRow(title: copy.text("当前构建", "Current build"), subtitle: updateStatusText,
                            symbol: "hammer.fill", symbolColor: Color(nsColor: .systemGray)) {}
                    }
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
        subtitle: String,
        symbol: String,
        color: NSColor,
        isOn: Binding<Bool>
    ) -> some View {
        NativeSettingsRow(
            title: title,
            subtitle: subtitle,
            symbol: symbol,
            symbolColor: Color(nsColor: color)
        ) {
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch).tint(Color(nsColor: .secondaryLabelColor))
                .controlSize(.small)
        }
    }

    private var appearanceSummary: String {
        if preferences.followsSystemAppearance {
            let current = colorScheme == .dark
                ? copy.text("深色", "Dark")
                : copy.text("浅色", "Light")
            return copy.text(
                "跟随系统：\(current)",
                "System appearance: \(current.lowercased())"
            )
        }

        let selected = preferences.customAppearance == .dark
            ? copy.text("深色", "dark")
            : copy.text("浅色", "light")
        return copy.text(
            "设置窗口使用\(selected)模式。",
            "Settings use the \(selected) appearance."
        )
    }

    private var languageSummary: String {
        if preferences.followsSystemLanguage {
            let language = preferences.resolvedLanguage == .simplifiedChinese
                ? "简体中文"
                : "English"
            return copy.text(
                "跟随系统：\(language)",
                "System language: \(language)"
            )
        }

        let language = preferences.customLanguage == .simplifiedChinese
            ? "简体中文"
            : "English"
        return copy.text(
            "使用\(language)",
            "Use \(language)"
        )
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

/// A bounded, static desktop surface shared by the settings illustrations.
private struct SettingsDesktopPreview<Content: View>: View {
    var alignment: Alignment = .center
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: alignment) {
                SettingsIslandPreviewAssets.image("Wallpaper")
                    .resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
                content()
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: alignment)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}

/// Permanent, static settings illustration. It has no task store, renderer,
/// timers or request handles; its controls are decorative, not live buttons.
private struct SettingsIslandPreview: View {
    @ObservedObject var preferences: AppPreferences
    private var copy: AppCopy { preferences.copy }
    private let secondary = Color(white: 133.0 / 255)
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
        return copy.text(effect.simplifiedChinese, effect.english) + ", " + privacy
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                SettingsIslandPreviewAssets.image("Wallpaper")
                    .resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                VStack(spacing: 0) {
                    header
                    taskCard.padding(.horizontal, 24).padding(.vertical, 12)
                    footer
                }
                .frame(width: 510, height: 150.4, alignment: .top)
                .background(alignment: .top) {
                    // The 150 pt silhouette's SVG includes its original shadow margins.
                    SettingsIslandPreviewAssets.image("Notch")
                        .frame(width: 530, height: 171).offset(y: -7.5)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(copy.text("灵动岛外观预览", "Island appearance preview"))
        .accessibilityValue(accessibilityValue)
        .transaction { $0.animation = nil }
    }

    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4.8) {
                SettingsIslandPreviewAssets.image("QuotaRing").frame(width: 11.2, height: 11.2)
                Text(copy.text("46% · 4 天", "46% · 4 d"))
                    .font(.system(size: 9.6, weight: .medium)).foregroundStyle(.white).fixedSize()
            }
            .padding(.leading, 6.4).frame(height: 22.4)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                icon("pin")
                icon("chevron.up")
            }
            .frame(height: 28, alignment: .top)
        }
        .padding(.horizontal, 20).frame(height: 36)
    }

    private var taskCard: some View {
        VStack(spacing: 5) {
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
            .frame(height: 16)
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
            .font(.system(size: 11)).frame(height: 14)
        }
        .lineLimit(1)
        .foregroundStyle(secondary)
        .padding(.leading, 10).padding(.trailing, 8)
        .frame(height: 60)
        .background {
            GeometryReader { geometry in
                let name = preferences.codexActivityProgressEffect == .dropField ? "QuantumCard"
                    : SettingsIslandPreviewAssets.effectName(preferences.codexActivityProgressEffect)
                SettingsIslandPreviewAssets.image(name).resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(white: 0.125), lineWidth: 1))
    }

    private var footer: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(copy.text("1 个会话", "1 session")).fixedSize()
                .padding(.leading, 6.4).frame(height: 22.4)
            Spacer(minLength: 0)
            HStack(spacing: 6.4) {
                Text(copy.text("1 工作中", "1 working")).fixedSize()
                icon("arrow.clockwise")
                icon("gearshape")
            }
            .frame(width: 310.4, height: 22.4, alignment: .trailing)
        }
        .font(.system(size: 9.6, weight: .medium)).foregroundStyle(secondary)
        .padding(.horizontal, 20).padding(.vertical, 4)
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 9.6, weight: .medium))
            .foregroundStyle(secondary).frame(width: 22.4, height: 22.4)
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
        .background(Color(white: 0.05).opacity(0.77), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(white: 0.16), lineWidth: 1))
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

/// Confine the material to small icon plates, leaving labels and paths open.
private struct SettingsProxyIconSurface: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5))
                .shadow(color: SettingsIllustrationPalette.shadow, radius: 6, y: 3)
        }
    }
}

/// Decorative route flow runs slowly and speeds up during an actual test.
/// Two compositor layers share a clock; no per-frame settings updates or polling.
private struct SettingsProxyFlow: NSViewRepresentable {
    let isActive: Bool
    let isTesting: Bool
    let segment: Int
    let reduceMotion: Bool

    func makeNSView(context: Context) -> FlowView { FlowView(frame: .zero) }
    func updateNSView(_ nsView: FlowView, context: Context) {
        nsView.configure(enabled: isActive && !reduceMotion, isTesting: isTesting, segment: segment)
    }
    static func dismantleNSView(_ nsView: FlowView, coordinator: ()) {
        nsView.configure(enabled: false, isTesting: false, segment: 0)
    }

    final class FlowView: NSView {
        private let packet = CAGradientLayer()
        private var enabled = false
        private var duration: CFTimeInterval = 4.8
        private var segment = 0
        private var renderedSize = CGSize.zero
        private static let animationKey = "settings.proxy.flow"

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.masksToBounds = true
            packet.colors = [NSColor.white.withAlphaComponent(0).cgColor,
                             NSColor.white.cgColor, NSColor.white.withAlphaComponent(0).cgColor]
            packet.startPoint = CGPoint(x: 0, y: 0.5)
            packet.endPoint = CGPoint(x: 1, y: 0.5)
            packet.cornerRadius = 1
            packet.shadowColor = NSColor.white.cgColor
            packet.shadowOpacity = 0.6
            packet.shadowRadius = 2
            packet.shadowOffset = .zero
            packet.isHidden = true
            layer?.addSublayer(packet)
        }
        required init?(coder: NSCoder) { nil }
        deinit { NotificationCenter.default.removeObserver(self) }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            if let window {
                for name in [NSWindow.didChangeOcclusionStateNotification,
                             NSWindow.didMiniaturizeNotification,
                             NSWindow.didDeminiaturizeNotification] {
                    NotificationCenter.default.addObserver(self, selector: #selector(visibilityChanged),
                                                           name: name, object: window)
                }
            }
            updateAnimation()
        }

        @objc private func visibilityChanged(_ notification: Notification) { updateAnimation() }

        func configure(enabled: Bool, isTesting: Bool, segment: Int) {
            let nextDuration = isTesting ? 1.6 : 4.8
            if duration != nextDuration || self.segment != segment {
                duration = nextDuration
                self.segment = segment
                packet.removeAnimation(forKey: Self.animationKey)
            }
            self.enabled = enabled
            updateAnimation()
        }

        override func layout() {
            super.layout()
            if renderedSize != bounds.size {
                renderedSize = bounds.size
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                packet.bounds = CGRect(x: 0, y: 0, width: 28, height: 2)
                packet.position = CGPoint(x: -14, y: bounds.midY)
                CATransaction.commit()
                packet.removeAnimation(forKey: Self.animationKey)
            }
            updateAnimation()
        }

        private func updateAnimation() {
            let playing = enabled && window?.occlusionState.contains(.visible) == true
                && window?.isMiniaturized == false && !isHiddenOrHasHiddenAncestor
                && bounds.width > 0 && bounds.height > 0
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            packet.isHidden = !playing
            CATransaction.commit()
            guard playing else {
                packet.removeAnimation(forKey: Self.animationKey)
                return
            }
            guard packet.animation(forKey: Self.animationKey) == nil else { return }
            let motion = CAKeyframeAnimation(keyPath: "position.x")
            motion.values = [-14, bounds.width + 14, bounds.width + 14]
            motion.keyTimes = [0, 0.45, 1]
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 1, 0, 0]
            fade.keyTimes = [0, 0.06, 0.38, 0.45, 1]
            motion.duration = duration
            fade.duration = duration
            let sequence = CAAnimationGroup()
            sequence.animations = [motion, fade]
            sequence.duration = duration
            sequence.repeatCount = .infinity
            // A shared media-time origin keeps the left/right links sequential.
            sequence.beginTime = 1
            sequence.timeOffset = Double(segment) * duration / 2
            packet.add(sequence, forKey: Self.animationKey)
        }
    }
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
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.toolbar = nil
        window.isMovableByWindowBackground = true
        SettingsWindowMetrics.applyOuterShape(to: window)
        window.hasShadow = true
        window.minSize = SettingsWindowMetrics.minimumContentSize

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

private struct SettingsSidebarIcon: View {
    let symbol: String
    let color: Color
    // 22 pt is the sidebar/row size; inset and radius keep the same proportions at any size.
    var size: CGFloat = 22
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

// Native menus with the reference's plain value and circular chevrons.
private struct SettingsValueMenu<Selection: Hashable>: View {
    let title: String
    @Binding var selection: Selection
    let options: [(Selection, String)]
    var body: some View {
        Menu {
            ForEach(Array(options.enumerated()), id: \.offset) { item in
                Button { selection = item.element.0 } label: {
                    if selection == item.element.0 { Label(item.element.1, systemImage: "checkmark") }
                    else { Text(item.element.1) }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Text(options.first { $0.0 == selection }?.1 ?? "—")
                    .font(.system(size: 14, weight: .medium)).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }.frame(minHeight: 28)
        }.menuIndicator(.hidden).buttonStyle(.plain)
            .fixedSize(horizontal: true, vertical: true)
            .accessibilityLabel(title).accessibilityValue(options.first { $0.0 == selection }?.1 ?? "—")
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
                        in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8)).opacity(enabled ? 1 : 0.4)
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
                        in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10)).onHover { hovered = $0 }
            .onDisappear { hovered = false }
    }
}

enum SettingsEffectPreviewMetrics {
    static let outerCornerRadius: CGFloat = 12
    static let inset: CGFloat = 8
    static let previewCornerRadius = outerCornerRadius - inset
    static let height: CGFloat = 56
}

private struct SettingsQuitRowStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(Color(nsColor: .systemRed))
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .systemRed).opacity(0.06))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : hovered ? 0.06 : 0))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
            .background(Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.10 : hovered ? 0.05 : 0))
                    .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
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
        VStack(spacing: 8) {
            // The grid owns the viewport width; an aspect-fill image must not
            // enlarge that width when the preview height changes.
            GeometryReader { geometry in
                SettingsIslandPreviewAssets.image(SettingsIslandPreviewAssets.effectName(effect))
                    .resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            }
                .frame(height: SettingsEffectPreviewMetrics.height)
                .clipShape(RoundedRectangle(cornerRadius: SettingsEffectPreviewMetrics.previewCornerRadius, style: .continuous))
                .padding(SettingsEffectPreviewMetrics.inset)
                .background(Color.primary.opacity(configuration.isPressed ? 0.10 : hovered ? 0.06 : 0.025),
                            in: RoundedRectangle(cornerRadius: SettingsEffectPreviewMetrics.outerCornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: SettingsEffectPreviewMetrics.outerCornerRadius, style: .continuous)
                        .strokeBorder(selected ? Color(nsColor: .controlAccentColor) : Color(nsColor: .separatorColor), lineWidth: selected ? 1.5 : 0.5)
                }
                .allowsHitTesting(false).accessibilityHidden(true)
            configuration.label.font(.system(size: 12, weight: .medium)).foregroundStyle(.primary)
                .lineLimit(1).minimumScaleFactor(0.85)
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

// A schematic of the settings window; shapes communicate appearance without sample account data.
private struct SettingsAppearancePreview: View {
    let mode: String
    var body: some View {
        HStack(spacing: 4) {
            if mode != "dark" { window(dark: false) }
            if mode != "light" { window(dark: true) }
        }.accessibilityHidden(true)
    }
    private func window(dark: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 3) {
                ForEach([NSColor.systemRed, .systemOrange, .systemGreen], id: \.self) { color in
                    Circle().fill(Color(nsColor: color)).frame(width: 4, height: 4)
                }
            }
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 3).fill(Color(nsColor: .systemPurple).opacity(0.25)).frame(width: 20)
                VStack(spacing: 4) {
                    ForEach(0..<3) { _ in
                        RoundedRectangle(cornerRadius: 2).fill((dark ? Color.white : .black).opacity(0.10))
                    }
                }
            }
        }.padding(7).frame(maxWidth: .infinity)
            .background(dark ? Color(white: 0.15) : Color(white: 0.94), in: RoundedRectangle(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5) }
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
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
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
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
            .strokeBorder(
                Color(nsColor: .separatorColor),
                lineWidth: 0.5
            )
        }
        .clipShape(
            RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
        )
    }
}

struct NativeSettingsRow<Control: View>: View {
    let title: String
    let subtitle: String?
    let symbol: String?
    let symbolColor: Color
    let horizontalPadding: CGFloat
    let control: Control

    init(
        title: String,
        subtitle: String? = nil,
        symbol: String? = nil,
        symbolColor: Color = Color(nsColor: .systemGray),
        horizontalPadding: CGFloat = 18,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.symbolColor = symbolColor
        self.horizontalPadding = horizontalPadding
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            HStack(alignment: .center, spacing: NativeSettingsDivider.iconGap) {
            if let symbol {
                SettingsSidebarIcon(symbol: symbol, color: symbolColor)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            }

            control
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, minHeight: 52)
        .contentShape(Rectangle())
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
    static let iconGap: CGFloat = 12
    // Row padding + 22 pt icon + gap: the divider starts under the row title.
    static let iconLeading: CGFloat = 18 + 22 + iconGap
    var leading: CGFloat = 18
    var body: some View {
        Divider()
            .padding(.leading, leading)
    }
}

struct NativeSettingsNote: View {
    let text: String
    var horizontalPadding: CGFloat = 18

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 13)
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
