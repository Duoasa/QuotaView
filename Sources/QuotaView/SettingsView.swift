import AppKit
import QuotaViewCore
import SwiftUI

enum SettingsWindowMetrics {
    static let outerCornerRadius: CGFloat = 36
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
    case general, island, usage, codexConnection, proxy, about
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .island: "sparkles.rectangle.stack.fill"
        case .usage: "chart.bar.xaxis"
        case .codexConnection: "point.3.connected.trianglepath.dotted"
        case .proxy: "network"
        case .about: "info.circle.fill"
        }
    }
    var color: NSColor {
        switch self {
        case .general: .systemBlue
        case .island: .systemPurple
        case .usage: .systemPink
        case .codexConnection: .systemCyan
        case .proxy: .systemTeal
        case .about: .systemIndigo
        }
    }
    func title(_ copy: AppCopy) -> String {
        switch self {
        case .general: copy.text("通用", "General")
        case .island: copy.text("灵动岛", "Island")
        case .usage: copy.text("用量显示", "Usage display")
        case .codexConnection: copy.text("Codex 连接", "Codex connection")
        case .proxy: copy.text("网络代理", "Network proxy")
        case .about: copy.text("关于", "About")
        }
    }
    func subtitle(_ copy: AppCopy) -> String {
        switch self {
        case .general: copy.text("语言、设置窗口外观与退出。", "Language, settings appearance and quitting.")
        case .island: copy.text("管理隐私显示与任务卡片特效。", "Manage privacy and task-card effects.")
        case .usage: copy.text("选择用量页中显示的数据与统计图表。", "Choose the data and charts shown on the usage page.")
        case .codexConnection: copy.text("查看本机 Codex 连接，管理数据目录与兼容 Hook。", "Review local Codex connectivity, data directories and compatibility Hooks.")
        case .proxy: copy.text("为额度和账户用量查询设置代理。", "Set a proxy for quota and account usage requests.")
        case .about: copy.text("应用版本与软件更新。", "App version and software updates.")
        }
    }
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
    @State private var codexActivityDetailsExpanded = false
    @State private var codexCompatibilityExpanded = false

    private var copy: AppCopy { preferences.copy }

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            HStack(spacing: 0) {
                settingsSidebar
                    .frame(width: 200)
                    .padding(.leading, SettingsWindowMetrics.sidebarInset)
                    .padding(.trailing, SettingsWindowMetrics.sidebarInset)
                    .padding(.vertical, SettingsWindowMetrics.sidebarInset)

                settingsDetail(for: selection ?? .general)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .tint(Color(nsColor: .controlAccentColor))
        .buttonStyle(SettingsActionButtonStyle())
        .frame(
            minWidth: 780,
            idealWidth: 872,
            minHeight: 560,
            idealHeight: 637
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
        .background {
            SettingsWindowConfigurator()
        }
    }

    private var settingsSidebar: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        sidebarSectionTitle(copy.text("应用", "App"))
                        settingsNavigation([.general, .island, .usage])
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        sidebarSectionTitle(copy.text("服务", "Services"))
                        settingsNavigation([.codexConnection, .proxy])
                    }
                }.padding(.horizontal, 10).padding(.top, 48)
            }.scrollIndicators(.never)
            Button { selection = .about; focusedPage = .about } label: {
                Label { Text(IslandSettingsPage.about.title(copy)) } icon: {
                    SettingsSidebarIcon(symbol: IslandSettingsPage.about.symbol, color: Color(nsColor: IslandSettingsPage.about.color))
                }.font(.body.weight(.medium)).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).frame(height: 36)
            }.buttonStyle(SettingsNavigationButtonStyle(selected: selection == .about))
                .focused($focusedPage, equals: .about)
                .onKeyPress(.upArrow) { navigateSettings(from: .about, offset: -1) }
                .onKeyPress(.downArrow) { .handled }
                .accessibilityValue(selection == .about ? copy.text("已选择", "Selected") : "")
                .padding(.horizontal, 10).padding(.bottom, 12)
        }
        .nativeSettingsSidebarSurface(
            fallbackCornerRadius:
                SettingsWindowMetrics.fallbackSidebarCornerRadius
        )
        .overlay(alignment: .topLeading) {
            SettingsTrafficLightHost()
                .frame(width: 84, height: 44)
        }
    }

    private func sidebarSectionTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            .padding(.horizontal, 12)
    }
    private func settingsNavigation(_ pages: [IslandSettingsPage]) -> some View {
        ForEach(pages) { page in
            Button { selection = page; focusedPage = page } label: {
                Label { Text(page.title(copy)) } icon: {
                    SettingsSidebarIcon(symbol: page.symbol, color: Color(nsColor: page.color))
                }.font(.body.weight(.medium)).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).frame(height: 36)
            }.buttonStyle(SettingsNavigationButtonStyle(selected: selection == page))
                .focused($focusedPage, equals: page)
                .accessibilityValue(selection == page ? copy.text("已选择", "Selected") : "")
                .onKeyPress(.downArrow) { navigateSettings(from: page, offset: 1) }
                .onKeyPress(.upArrow) { navigateSettings(from: page, offset: -1) }
        }
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
            VStack(alignment: .leading, spacing: 22) {
                settingsHeader(for: page)

                switch page {
                case .general: generalSettings
                case .island: islandSettings
                case .usage: usageSettings
                case .codexConnection: codexConnectionSettings
                case .proxy: proxySettings
                case .about: aboutSettings
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 26)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .id(page)
        .transition(.opacity)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: selection)
    }

    private func settingsHeader(
        for page: IslandSettingsPage
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                SettingsSidebarIcon(symbol: page.symbol, color: Color(nsColor: page.color))
                    .scaleEffect(1.25).frame(width: 28, height: 28)
                Text(page.title(copy)).font(.system(size: 22, weight: .semibold)).foregroundStyle(.primary)
            }

            Text(page.subtitle(copy))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
                    subtitle: copy.text("默认关闭，修改后保存生效。", "Off by default. Save to apply changes.")
                ) {
                    Toggle(copy.text("自定义代理", "Custom proxy"), isOn: $proxyDraft.isEnabled)
                        .labelsHidden().toggleStyle(.switch).tint(Color(nsColor: .secondaryLabelColor)).controlSize(.small)
                        .help(copy.text("使用指定代理查询额度和账户用量。", "Use this proxy for quota and account usage."))
                }
                NativeSettingsDivider()
                NativeSettingsRow(title: copy.text("协议", "Protocol")) {
                    SettingsValueMenu(title: copy.text("代理协议", "Proxy protocol"), selection: $proxyDraft.scheme,
                        options: [(.http, "HTTP"), (.socks5, "SOCKS5")])
                    .disabled(!proxyDraft.isEnabled)
                }
                NativeSettingsDivider()
                NativeSettingsRow(
                    title: copy.text("服务器地址", "Server address"),
                    subtitle: copy.text("填写 IP 或主机名，无需协议前缀。", "Enter an IP or hostname without a protocol prefix.")
                ) {
                    TextField("127.0.0.1", text: $proxyDraft.host)
                        .textFieldStyle(.roundedBorder).frame(width: 190)
                        .accessibilityLabel(copy.text("代理服务器地址", "Proxy server address"))
                        .disabled(!proxyDraft.isEnabled)
                }
                NativeSettingsDivider()
                NativeSettingsRow(title: copy.text("端口", "Port")) {
                    TextField("7890", text: $proxyDraft.port)
                        .textFieldStyle(.roundedBorder).frame(width: 100)
                        .accessibilityLabel(copy.text("代理端口", "Proxy port"))
                        .disabled(!proxyDraft.isEnabled)
                }
            }
            Text(copy.text(
                "支持无需账号密码的 HTTP / SOCKS5 代理。仅影响 QuotaView 的额度和账户用量查询。",
                "Supports HTTP / SOCKS5 proxies without authentication. Applies only to QuotaView quota and account usage requests."
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
                .help(copy.text("关闭自定义代理并恢复默认设置。", "Turn off the custom proxy and restore default settings."))
                Spacer(minLength: 0)
                if store.proxyTestState == .testing {
                    Button(copy.text("取消测试", "Cancel Test")) { store.cancelProxyTest() }
                } else {
                    Button(copy.text("连接测试", "Test Connection")) {
                        store.testProxyConnection(proxyDraft)
                    }
                    .disabled(!proxyDraft.isEnabled || proxyValidationFailure != nil)
                    .help(copy.text("使用当前填写的代理实际查询额度，不保存设置。", "Query quota using this draft proxy without saving it."))
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
                 ? copy.text("当前设置已保存。", "Current settings are saved.")
                 : copy.text("有未保存的更改。", "You have unsaved changes."))
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
                SettingsAppearancePreview(mode: value).frame(height: 70)
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
                    preferenceToggle(copy.text("隐私显示", "Private display"),
                        subtitle: copy.text("隐藏任务标题、正文和请求内容，统计页隐藏账户数据。", "Hide task titles, text and request contents, and conceal account data on the usage page."),
                        isOn: $preferences.codexIslandPrivacy)
                }
            }
            settingsSection(copy.text("任务卡片特效", "Task-card effects")) {
                LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 12) {
                    ForEach(AppPreferences.CodexActivityProgressEffect.allCases) { effect in
                        Button { preferences.codexActivityProgressEffect = effect } label: {
                            VStack(spacing: 10) {
                                CodexActivityProgressEffectPreview(effect: effect, reduceMotion: reduceMotion)
                                    .frame(height: 96).clipShape(RoundedRectangle(cornerRadius: 10))
                                    .allowsHitTesting(false).accessibilityHidden(true)
                                Text(copy.text(effect.displayName.simplifiedChinese, effect.displayName.english))
                                    .font(.system(size: 13, weight: .medium))
                            }.frame(maxWidth: .infinity)
                        }.buttonStyle(SettingsVisualOptionStyle(selected: preferences.codexActivityProgressEffect == effect))
                            .accessibilityLabel(copy.text(effect.displayName.simplifiedChinese, effect.displayName.english))
                            .accessibilityValue(preferences.codexActivityProgressEffect == effect ? copy.text("已选择", "Selected") : "")
                    }
                }
                Text(copy.text("预览使用实际特效渲染器；自动遵循 macOS 的减少动态效果。", "Previews use the actual effect renderer and respect macOS Reduce Motion."))
                    .font(.callout).foregroundStyle(.secondary)
            }
            settingsSection(copy.text("任务与提醒", "Tasks and attention")) {
                NativeSettingsCard {
                    NativeSettingsRow(title: copy.text("显示位置", "Display location"),
                        subtitle: copy.text("常驻主屏幕顶部；无刘海屏幕使用居中的紧凑形态。", "Stays at the top of the primary display; uses a centered compact form on displays without a notch.")) {}
                    NativeSettingsDivider()
                    NativeSettingsRow(title: copy.text("展开与归档", "Expansion and archiving"),
                        subtitle: copy.text("任务启动与完成时展开 3 秒；待确认保持展开，固定后由你收起。卡片归档只清理灵动岛显示。", "Opens for 3 seconds when tasks start or finish. Pending requests keep it open; pinned pages stay open until collapsed. Archiving only clears the island display.")) {}
                }
            }
        }
    }

    private var usageSettings: some View {
        VStack(alignment: .leading, spacing: 24) {
            settingsSection(copy.text("页面预览", "Page preview")) {
                SettingsUsagePreview(store: store, preferences: preferences)
                Text(copy.text("预览随选项立即更新，显示当前数据；隐私模式下隐藏统计。", "The preview updates immediately with your choices and current data. Privacy mode conceals statistics."))
                    .font(.callout).foregroundStyle(.secondary)
            }
            settingsSection(copy.text("额度与账户", "Quota and account")) {
                NativeSettingsCard {
                    preferenceToggle(copy.text("周期用量概览", "Quota overview"), subtitle: copy.text("显示可用周期的剩余量、已用量和重置时间。", "Show available cycles, remaining quota, used quota and reset times."), isOn: $preferences.showUsageSummary)
                    NativeSettingsDivider()
                    preferenceToggle(copy.text("Spark 周额度", "Spark weekly quota"), subtitle: copy.text("有可用数据时显示 Spark 周额度。", "Show Spark weekly quota when data is available."), isOn: $preferences.showSparkQuota)
                    NativeSettingsDivider()
                    preferenceToggle(copy.text("Credits 余额", "Credits balance"), subtitle: copy.text("显示账户可用的 Credits 余额。", "Show the account's available Credits balance."), isOn: $preferences.showCreditBalance)
                    NativeSettingsDivider()
                    preferenceToggle(copy.text("额度重置入口", "Quota reset entry"), subtitle: copy.text("显示重置卡入口，包括 0 次时的空状态。", "Show the reset-card entry, including its empty state at zero credits."), isOn: $preferences.showResetAction)
                }
            }
            settingsSection(copy.text("Token 统计", "Token statistics")) {
                NativeSettingsCard {
                    preferenceToggle(copy.text("最近一天 Token", "Latest day tokens"), subtitle: copy.text("显示最近一个统计日的 Token 用量。", "Show token usage for the latest reporting day."), isOn: $preferences.showDailyTokens)
                    NativeSettingsDivider()
                    preferenceToggle(copy.text("30 日 Token", "30-day tokens"), subtitle: copy.text("显示最近 30 天的 Token 总用量。", "Show total token usage for the last 30 days."), isOn: $preferences.showThirtyDayTokens)
                    NativeSettingsDivider()
                    preferenceToggle(copy.text("累计 Token", "Total tokens"), subtitle: copy.text("显示当前账户的累计 Token 用量。", "Show lifetime token usage for the current account."), isOn: $preferences.showLifetimeTokens)
                }
            }
            settingsSection(copy.text("统计图表", "Charts")) {
                NativeSettingsCard {
                    preferenceToggle(copy.text("成本估算", "Cost estimate"), subtitle: copy.text("显示最近 30 天的估算成本和趋势图；估算值不是账单。", "Show estimated costs and the trend for the last 30 days; estimates are not bills."), isOn: $preferences.showEstimatedCost)
                    NativeSettingsDivider()
                    preferenceToggle(copy.text("Token 活动", "Token activity"), subtitle: copy.text("显示活动热力图，支持每天、每周与累计总量。", "Show the activity heatmap with daily, weekly and cumulative modes."), isOn: $preferences.showTokenActivity)
                }
            }
        }
    }

    private var codexConnectionSettings: some View {
        VStack(spacing: 16) {
            NativeSettingsCard {
                NativeSettingsRow(
                    title: copy.text("Codex 自动连接", "Automatic Codex Connection"),
                    subtitle: activityRuntime.connectionPresentation.automaticSubtitle(copy)
                ) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(activityRuntime.isNativeActivityConnected
                                  ? Color(nsColor: .systemGreen)
                                  : activityRuntime.localHealth.hasReadError
                                    ? Color(nsColor: .systemRed)
                                    : Color(nsColor: .tertiaryLabelColor))
                            .frame(width: 5, height: 5)
                            .accessibilityHidden(true)
                        Text(activityRuntime.connectionPresentation.automaticStatusTitle(copy))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }

                NativeSettingsDivider()
                NativeSettingsRow(
                    title: copy.text("自动连接数据目录", "Automatic Connection Directory"),
                    subtitle: activityRuntime.dataDirectoryURL.path
                ) {
                    HStack(spacing: 8) {
                        Button(copy.text("重新检查", "Recheck")) { activityRuntime.recheckAutomaticConnection() }
                            .help(copy.text("只读检查当前目录，不修改 Hook。", "Check the current directory without changing Hooks."))
                        Menu {
                            Button(copy.text("选择目录…", "Choose Directory…")) { activityRuntime.chooseDataDirectory() }
                            Button(copy.text("恢复默认目录", "Restore Default Directory")) { activityRuntime.selectDataDirectory(nil) }
                                .disabled(!activityRuntime.usesCustomDataDirectory)
                        } label: { Text(copy.text("目录", "Directory")) }
                    }
                    .controlSize(.small)
                    .disabled(activityRuntime.isChangingDataDirectory)
                }
                if activityRuntime.directorySelectionFailed {
                    NativeSettingsNote(text: copy.text(
                        "所选目录必须包含可读取的 sessions 文件夹。原目录保持不变。",
                        "Choose a directory containing a readable sessions folder. The original directory is still selected."
                    ))
                }

                NativeSettingsDivider()
                NativeSettingsNote(text: codexActivityPrivacyNote)
                NativeSettingsDivider()

                DisclosureGroup(isExpanded: $codexCompatibilityExpanded) {
                    VStack(alignment: .leading, spacing: 0) {
                        NativeSettingsNote(text: copy.text(
                            "仅在自动连接无法满足使用需要时手动配置。Hook 的安装和信任状态独立于自动连接；自动连接的数据目录选择不会移动已有 Hook。",
                            "Configure manually only if automatic connection does not meet your needs. Hook installation and trust are independent; changing the automatic connection directory does not move existing Hooks."
                        ), horizontalPadding: 0)
                        NativeSettingsRow(
                            title: copy.text(
                                "兼容 Hook",
                                "Compatibility Hook"
                            ),
                            subtitle: codexActivityConnectionSubtitle,
                            horizontalPadding: 0
                        ) {
                            HStack(spacing: 10) {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(codexActivityConnectionColor)
                                        .frame(width: 5, height: 5)
                                        .accessibilityHidden(true)

                                    Text(codexActivityConnectionStatusTitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .accessibilityElement(children: .combine)

                                Button {
                                    switch activityRuntime.hookConnectionStatus {
                                    case .notInstalled, .abnormal:
                                        activityRuntime.enableCompatibilityHook()
                                    case .installedNeedsRestart:
                                        activityRuntime.restartCodex()
                                    case .awaitingTrust:
                                        activityRuntime.openCodexSecurityReview()
                                    case .awaitingFirstEvent, .connected:
                                        activityRuntime.disableCompatibilityHook()
                                    }
                                } label: {
                                    if activityRuntime.isConfiguring
                                        || activityRuntime.isOpeningSecurityReview
                                    {
                                        ProgressView()
                                            .controlSize(.small)
                                            .frame(minWidth: 92)
                                    } else {
                                        Text(codexActivityActionTitle)
                                            .frame(minWidth: 92)
                                    }
                                }
                                .nativeSettingsActionStyle()
                                .controlSize(.small)
                                .disabled(
                                    activityRuntime.isConfiguring
                                        || activityRuntime.isOpeningSecurityReview
                                )
                                .help(codexActivityActionHelp)
                                .accessibilityLabel(codexActivityActionTitle)
                            }
                        }

                        if activityRuntime.hasCompatibilityHook,
                           activityRuntime.hookConnectionStatus != .connected,
                           activityRuntime.hookConnectionStatus != .awaitingFirstEvent {
                            NativeSettingsRow(
                                title: copy.text("移除兼容 Hook", "Remove Compatibility Hook"),
                                subtitle: copy.text("仅移除 QuotaView 的 Hook，自动连接继续工作。", "Remove only QuotaView Hooks; automatic connection keeps working."),
                                horizontalPadding: 0
                            ) {
                                Button(copy.text("移除", "Remove")) { activityRuntime.disableCompatibilityHook() }
                                    .nativeSettingsActionStyle()
                                    .controlSize(.small)
                                    .disabled(activityRuntime.isConfiguring || activityRuntime.isOpeningSecurityReview)
                            }
                        }

                        if codexActivityShowsNextStep {
                            Divider()

                            NativeSettingsRow(
                                title: codexActivityNextStepTitle,
                                subtitle: codexActivityNextStepSubtitle,
                                horizontalPadding: 0
                            ) {}
                        }

                        DisclosureGroup(
                            isExpanded: $codexActivityDetailsExpanded
                        ) {
                            VStack(alignment: .leading, spacing: 10) {
                                LabeledContent(copy.text("Hook 配置目录", "Hook Configuration Directory"),
                                               value: activityRuntime.hookDirectoryPath)
                                LabeledContent(
                                    copy.text("Codex 版本", "Codex version"),
                                    value: codexEnvironmentSubtitle
                                )
                                LabeledContent(
                                    copy.text("活动支持", "Activity support"),
                                    value: codexHooksFeatureTitle
                                )
                                LabeledContent(
                                    copy.text("本地连接", "Local connection"),
                                    value: codexActivityBridgeStatusTitle
                                )
                                Text(codexActivityBridgeSubtitle)
                                    .foregroundStyle(.tertiary)
                                Text(copy.text(
                                    "诊断日志：\(activityRuntime.diagnosticLogPath)",
                                    "Diagnostic log: \(activityRuntime.diagnosticLogPath)"
                                ))
                                .foregroundStyle(.tertiary)
                                .textSelection(.enabled)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 10)
                        } label: {
                            Text(copy.text("连接详情", "Connection Details"))
                                .font(.body.weight(.medium))
                        }
                        .padding(.vertical, 11)
                    }
                    .padding(.top, 10)
                } label: {
                    Text(copy.text("兼容选项：Hook", "Compatibility Options: Hook"))
                        .font(.body.weight(.medium))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
            }

            NativeSettingsCard {
                NativeSettingsNote(text: copy.text(
                    "选中任务使用量子噪点，其他任务使用 AI 球。待确认辉光与噪点以 3 秒周期同步；减少动态效果时显示静态反馈。当前连接为观察模式，真实批准在 Codex 中处理。", "Selected tasks use quantum noise; other tasks use the orb. Confirmation glow and noise share a 3-second cycle; Reduce Motion uses static feedback. This connection observes activity; handle approvals in Codex."))
            }
        }
        .onAppear {
            activityRuntime.refreshConnectionStatus()
        }
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
            NativeSettingsRow(title: copy.text("App 语言", "App language"), subtitle: languageSummary) {
                SettingsValueMenu(title: copy.text("App 语言", "App language"), selection: languageSelection,
                    options: [("system", copy.text("跟随系统", "System")), (AppPreferences.Language.simplifiedChinese.rawValue, "简体中文"), (AppPreferences.Language.english.rawValue, "English")])
            }
        }
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary).padding(.leading, 10)
            content()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 22) {
            settingsSection(copy.text("语言", "Language")) { languageSettings }
            settingsSection(copy.text("设置窗口外观", "Settings appearance")) { appearanceSettings }
            NativeSettingsCard {
                NativeSettingsRow(title: copy.text("退出 QuotaView", "Quit QuotaView"),
                    subtitle: copy.text("关闭灵动岛并停止本地观察，Codex 中的任务继续运行。", "Close the island and stop local observation. Tasks in Codex continue running.")) {
                    Button(copy.text("退出软件", "Quit App"), role: .destructive) { NSApplication.shared.terminate(nil) }
                        .buttonStyle(SettingsActionButtonStyle()).controlSize(.small)
                        .accessibilityLabel(copy.text("退出 QuotaView", "Quit QuotaView"))
                }
            }
        }
    }

    private var aboutSettings: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 18) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().interpolation(.high).scaledToFit().frame(width: 96, height: 96)
                    .accessibilityLabel(copy.text("QuotaView 应用图标", "QuotaView app icon"))
                VStack(alignment: .leading, spacing: 6) {
                    Text("QuotaView").font(.system(size: 24, weight: .semibold))
                    Text(copy.text("Codex 任务与用量灵动岛", "Codex task and usage island")).font(.callout).foregroundStyle(.secondary)
                    Text(versionAndBuildLabel).font(.caption).foregroundStyle(.tertiary)
                }
            }.padding(.vertical, 8)
            settingsSection(copy.text("软件更新", "Software updates")) {
                NativeSettingsCard {
                    if updateController.availability == .available {
                        NativeSettingsRow(title: copy.text("检查更新", "Check for updates"), subtitle: updateStatusText) {
                            Button(copy.text("检查更新…", "Check for Updates…")) { updateController.checkForUpdates() }
                                .nativeSettingsActionStyle().disabled(!updateController.canCheckForUpdates).help(updateCheckHelpText)
                        }
                        NativeSettingsDivider()
                        NativeSettingsRow(title: copy.text("自动检查更新", "Automatically check for updates")) {
                            Toggle(copy.text("自动检查更新", "Automatically check for updates"), isOn: Binding(
                                get: { updateController.automaticallyChecksForUpdates },
                                set: { updateController.setAutomaticallyChecksForUpdates($0) }))
                                .labelsHidden().toggleStyle(.switch).tint(Color(nsColor: .secondaryLabelColor)).controlSize(.small)
                        }
                    } else {
                        NativeSettingsRow(title: copy.text("当前构建", "Current build"), subtitle: updateStatusText) {}
                    }
                }
            }
        }
    }

    private var updateCheckHelpText: String {
        if updateController.availability == .available {
            return copy.text(
                "立即通过签名更新源检查新版本。",
                "Check the signed update feed for a new version now."
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
                "开启后每 24 小时自动检查；下载与安装始终需要你的确认。",
                "When enabled, QuotaView checks every 24 hours; downloads and installation always require your confirmation."
            )
        case .debugBuild:
            return copy.text(
                "调试构建不会连接在线更新服务。",
                "Debug builds do not connect to the online update service."
            )
        case .notApplicationBundle:
            return copy.text(
                "当前运行方式不支持在线更新。",
                "The current launch environment does not support online updates."
            )
        case .unexpectedBundleIdentifier,
             .untrustedSignature:
            return copy.text(
                "只有经 QuotaView 正式签名的应用支持在线更新。",
                "Online updates are available only in an officially signed QuotaView app."
            )
        case .invalidConfiguration:
            return copy.text(
                "更新服务配置不可用，请重新安装正式版本。",
                "The update service is unavailable. Reinstall the official release."
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
        isOn: Binding<Bool>
    ) -> some View {
        NativeSettingsRow(
            title: title,
            subtitle: subtitle
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
                "当前随系统显示为\(current)模式。",
                "Currently using the system \(current.lowercased()) appearance."
            )
        }

        let selected = preferences.customAppearance == .dark
            ? copy.text("深色", "dark")
            : copy.text("浅色", "light")
        return copy.text(
            "设置窗口将固定使用\(selected)模式。",
            "Settings will always use the \(selected) appearance."
        )
    }

    private var languageSummary: String {
        if preferences.followsSystemLanguage {
            let language = preferences.resolvedLanguage == .simplifiedChinese
                ? "简体中文"
                : "English"
            return copy.text(
                "当前系统语言适配为\(language)。",
                "The current system language resolves to \(language)."
            )
        }

        let language = preferences.customLanguage == .simplifiedChinese
            ? "简体中文"
            : "English"
        return copy.text(
            "QuotaView 将固定使用\(language)。",
            "QuotaView will always use \(language)."
        )
    }

    private var codexActivityActionTitle: String {
        if activityRuntime.isConfiguring {
            return copy.text("正在准备", "Preparing")
        }
        if activityRuntime.isOpeningSecurityReview {
            return copy.text("正在打开", "Opening")
        }
        return switch activityRuntime.hookConnectionStatus {
        case .notInstalled:
            copy.text("配置 Hook", "Configure Hook")
        case .abnormal:
            copy.text("重试配置", "Retry Setup")
        case .installedNeedsRestart:
            copy.text("重新启动 Codex", "Restart Codex")
        case .awaitingTrust:
            copy.text("打开安全确认", "Open Security Review")
        case .awaitingFirstEvent, .connected:
            copy.text("停用 Hook", "Disable Hook")
        }
    }

    private var codexActivityActionHelp: String {
        return switch activityRuntime.hookConnectionStatus {
        case .installedNeedsRestart:
            copy.text(
                "安全确认已完成；重新启动 Codex 以激活连接。",
                "The security review is complete. Restart Codex to activate the connection."
            )
        case .awaitingTrust:
            copy.text(
                "等待 CLI 首次加载完成并自动进入 Hooks 页面后，再按 T。",
                "Wait for the CLI to finish loading and enter the Hooks page before pressing T."
            )
        case .awaitingFirstEvent, .connected:
            copy.text(
                "仅停用兼容 Hook，保留自动任务流。",
                "Disable only the compatibility Hook; keep automatic task streams running."
            )
        case .notInstalled, .abnormal:
            copy.text(
                "安装兼容 Hook，并进入 Codex 安全确认流程。",
                "Install the compatibility Hook and open the Codex security review."
            )
        }
    }

    private var codexActivityConnectionSubtitle: String {
        if activityRuntime.isConfiguring
            || activityRuntime.isOpeningSecurityReview
        {
            return copy.text(
                "正在准备兼容 Hook，自动任务流仍会独立连接。",
                "Preparing the compatibility Hook; automatic task streams connect independently."
            )
        }

        return switch activityRuntime.hookConnectionStatus {
        case .notInstalled:
            copy.text(
                "按需安装兼容 Hook；自动连接无需此步骤。",
                "Install the compatibility Hook if needed; automatic connection does not require this step."
            )
        case .installedNeedsRestart:
            copy.text(
                "安全确认已经完成；点击一次即可安全退出并重新打开 Codex。",
                "The security review is complete. Restart Codex here with one click."
            )
        case .awaitingTrust:
            copy.text(
                "等待 CLI 完成首次加载；QuotaView 自动输入 /hooks 并进入 Hooks 页面后，再按 T。",
                "Wait for the CLI to finish its first load. Press T only after QuotaView enters /hooks and opens the Hooks page."
            )
        case .awaitingFirstEvent:
            activityRuntime.compatibilityHookScope == .compaction ? copy.text(
                "已配置压缩开始与结束 Hook，尚未收到压缩事件。",
                "Compaction start and end Hooks are configured. No compaction event has been received yet."
            ) : copy.text(
                "重启已经完成；发送一条新的 Codex 消息完成连接。",
                "Restart is complete. Send a new Codex message to finish connecting."
            )
        case .connected:
            copy.text(
                "已收到兼容 Hook 事件。停用 Hook 不会关闭自动任务流。",
                "Compatibility Hook events have been received. Disabling the Hook keeps automatic task streams running."
            )
        case .abnormal(let message):
            message
        }
    }

    private var codexActivityConnectionStatusTitle: String {
        if activityRuntime.isConfiguring
            || activityRuntime.isOpeningSecurityReview
        {
            return copy.text("正在准备", "Preparing")
        }

        return switch activityRuntime.hookConnectionStatus {
        case .notInstalled:
            copy.text("未启用", "Not Enabled")
        case .installedNeedsRestart, .awaitingTrust:
            copy.text("需要安全确认", "Security Review Needed")
        case .awaitingFirstEvent:
            activityRuntime.compatibilityHookScope == .compaction
                ? copy.text("等待压缩事件", "Waiting for Compaction")
                : copy.text("等待第一条消息", "Waiting for First Message")
        case .connected:
            copy.text("Hook 已连接", "Hook Connected")
        case .abnormal:
            copy.text("需要处理", "Needs Attention")
        }
    }

    private var codexActivityConnectionColor: Color {
        if activityRuntime.isConfiguring
            || activityRuntime.isOpeningSecurityReview
        {
            return Color(nsColor: .systemBlue)
        }

        return switch activityRuntime.hookConnectionStatus {
        case .connected:
            Color(nsColor: .systemGreen)
        case .installedNeedsRestart,
             .awaitingTrust,
             .awaitingFirstEvent:
            Color(nsColor: .systemOrange)
        case .abnormal:
            Color(nsColor: .systemRed)
        case .notInstalled:
            Color(nsColor: .tertiaryLabelColor)
        }
    }

    private var codexEnvironmentSubtitle: String {
        activityRuntime.codexVersion ?? copy.text(
            "正在检测 Codex 版本…",
            "Detecting the Codex version…"
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

    private var codexActivityShowsNextStep: Bool {
        switch activityRuntime.hookConnectionStatus {
        case .installedNeedsRestart, .awaitingTrust, .awaitingFirstEvent:
            true
        case .notInstalled, .connected, .abnormal:
            false
        }
    }

    private var codexActivityNextStepTitle: String {
        switch activityRuntime.hookConnectionStatus {
        case .installedNeedsRestart:
            copy.text(
                "重新启动 Codex",
                "Restart Codex"
            )
        case .awaitingTrust:
            copy.text(
                "等待 Hooks 页面，再按 T",
                "Wait for Hooks, Then Press T"
            )
        case .awaitingFirstEvent:
            activityRuntime.compatibilityHookScope == .compaction
                ? copy.text("等待自然压缩", "Wait for Natural Compaction")
                : copy.text("发送一条新消息", "Send a New Message")
        case .notInstalled, .connected, .abnormal:
            ""
        }
    }

    private var codexActivityNextStepSubtitle: String {
        switch activityRuntime.hookConnectionStatus {
        case .installedNeedsRestart:
            copy.text(
                "QuotaView 会安全退出并重新打开 Codex；重新启动后无需再次配置。",
                "QuotaView safely quits and reopens Codex. No further setup is needed after restart."
            )
        case .awaitingTrust:
            copy.text(
                "请先等待 CLI 完成首次加载。QuotaView 会自动输入 /hooks；只有看到 Hooks 页面和“Press t to trust all”提示后再按 T，不要在普通输入框中提前按键。",
                "Wait for the CLI to finish its first load. QuotaView enters /hooks automatically. Press T only after the Hooks page shows “Press t to trust all”; do not press it in the normal prompt."
            )
        case .awaitingFirstEvent:
            activityRuntime.compatibilityHookScope == .compaction ? copy.text(
                "当前仅接收压缩事件，普通聊天消息不会完成此项验证。正常使用 Codex 即可，无需专门触发压缩；收到真实压缩事件后会更新连接状态。",
                "This setup receives only compaction events; ordinary chat messages do not verify it. Use Codex normally without forcing compaction. The connection status updates when a real compaction event arrives."
            ) : copy.text(
                "不会发送测试数据；收到重启后的第一条真实消息时，灵动岛会自动切换为活动状态。",
                "No test data is sent. The island switches to its active state after the first real message following restart."
            )
        case .notInstalled, .connected, .abnormal:
            ""
        }
    }

    private var codexActivityBridgeSubtitle: String {
        return switch activityRuntime.bridgeStatus {
        case .listening:
            copy.text(
                "通过当前用户的本地 Unix Socket 接收脱敏事件；受限时自动回退到权限隔离的本地队列。",
                "Receives sanitized events through a current-user Unix socket and automatically falls back to a permission-isolated local queue when restricted."
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

    private var codexActivityPrivacyNote: String {
        copy.text(
            "只读连接本机 Codex，展示任务状态、公开内容、计划与用量；批准和其他任务操作仍由 Codex 处理。",
            "Observe local Codex task state, public content, plans and usage. Codex continues to handle approvals and other task actions."
        )
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
        window.minSize = NSSize(width: 780, height: 560)

        if coordinator.configuredWindow !== window {
            coordinator.configuredWindow = window
            window.setContentSize(
                NSSize(width: 872, height: 637)
            )
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

private struct CodexActivityProgressEffectPreview: NSViewRepresentable {
    let effect: AppPreferences.CodexActivityProgressEffect
    let reduceMotion: Bool

    func makeNSView(
        context: Context
    ) -> CodexActivityStateSmokePreviewHostView {
        let view = CodexActivityStateSmokePreviewHostView(effect: effect)
        view.update(effect: effect, reduceMotion: reduceMotion)
        return view
    }

    func updateNSView(
        _ view: CodexActivityStateSmokePreviewHostView,
        context: Context
    ) {
        view.update(effect: effect, reduceMotion: reduceMotion)
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
    @Environment(\.colorSchemeContrast) private var contrast

    private enum Metrics {
        static let size: CGFloat = 22
        static let inset: CGFloat = 3
        static let symbolSize = size - inset * 2
        static let cornerRadius: CGFloat = 5
    }

    var body: some View {
        Image(systemName: symbol)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .symbolRenderingMode(.monochrome)
            .font(.system(size: Metrics.symbolSize, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: Metrics.symbolSize, height: Metrics.symbolSize)
            .padding(Metrics.inset)
            .frame(width: Metrics.size, height: Metrics.size)
            .fixedSize()
            .background {
                RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                    .fill(color.gradient)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
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

private struct SettingsVisualOptionStyle: ButtonStyle {
    let selected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(.primary).padding(12)
            .background(Color.primary.opacity(configuration.isPressed ? 0.10 : hovered ? 0.06 : 0.025),
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(selected ? Color(nsColor: .controlAccentColor) : Color(nsColor: .separatorColor), lineWidth: selected ? 1.5 : 0.5)
            }.contentShape(RoundedRectangle(cornerRadius: 12))
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

// Scale the production usage layout, including real/missing/private states, rather than a second mock layout.
private struct SettingsUsagePreview: View {
    @ObservedObject var store: CodexStatusStore
    @ObservedObject var preferences: AppPreferences
    @State private var height: CGFloat = 500
    @State private var board = IslandBoardState()
    private let scale: CGFloat = 0.62
    var body: some View {
        IslandUsageBento(snapshot: store.islandUsage.snapshot, usageState: store.islandUsage.state,
            english: preferences.resolvedLanguage == .english, contentWidth: 624,
            options: .init(preferences: preferences), privacy: preferences.codexIslandPrivacy,
            playbackEnabled: false, hidesTicket: false, onReset: {}, utilities: .init(state: board),
            onHeightChange: { height = $0 })
            .frame(width: 680, height: height, alignment: .topLeading)
            .background(.black, in: RoundedRectangle(cornerRadius: 24))
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: 680 * scale, height: height * scale, alignment: .topLeading)
            .clipped().allowsHitTesting(false).accessibilityHidden(true)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct NativeSettingsCard<Content: View>: View {
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
    let horizontalPadding: CGFloat
    let control: Control

    init(
        title: String,
        subtitle: String? = nil,
        horizontalPadding: CGFloat = 18,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.subtitle = subtitle
        self.horizontalPadding = horizontalPadding
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
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

private struct NativeSettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 18)
    }
}

private struct NativeSettingsNote: View {
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
