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

struct AppVersionInfo: Equatable {
    let marketingVersion: String
    let buildNumber: String

    init(marketingVersion: String?, buildNumber: String?) {
        self.marketingVersion = Self.displayValue(marketingVersion)
        self.buildNumber = Self.displayValue(buildNumber)
    }

    init(bundle: Bundle) {
        self.init(
            marketingVersion: bundle.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String,
            buildNumber: bundle.object(
                forInfoDictionaryKey: "CFBundleVersion"
            ) as? String
        )
    }

    func label(copy: AppCopy) -> String {
        copy.text(
            "版本 \(marketingVersion)（Build \(buildNumber)）",
            "Version \(marketingVersion) (Build \(buildNumber))"
        )
    }

    private static func displayValue(_ value: String?) -> String {
        guard let value = value?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !value.isEmpty else {
            return "—"
        }
        return value
    }
}

struct AppStorePublicLinkConfiguration: Equatable {
    let status: String
    let rawURL: String

    init(status: String?, rawURL: String?) {
        self.status = status?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ) ?? ""
        self.rawURL = rawURL?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ) ?? ""
    }

    init(
        bundle: Bundle,
        statusKey: String,
        urlKey: String
    ) {
        self.init(
            status: bundle.object(
                forInfoDictionaryKey: statusKey
            ) as? String,
            rawURL: bundle.object(
                forInfoDictionaryKey: urlKey
            ) as? String
        )
    }

    var publishedURL: URL? {
        guard status == "published",
              !rawURL.isEmpty,
              !rawURL.contains("["),
              !rawURL.contains("]"),
              let url = URL(string: rawURL),
              url.scheme?.lowercased() == "https",
              url.host?.isEmpty == false,
              url.user == nil,
              url.password == nil else {
            return nil
        }
        return url
    }
}

enum SettingsPage: String, CaseIterable, Identifiable {
    case menuBar
    case popover
    case codexActivity
    case appearance
    case language
    case general

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .menuBar: "menubar.rectangle"
        case .popover: "rectangle.on.rectangle"
        case .codexActivity: "link"
        case .appearance: "circle.lefthalf.filled"
        case .language: "globe"
        case .general: "gearshape"
        }
    }

    func title(_ copy: AppCopy) -> String {
        switch self {
        case .menuBar:
            copy.text("菜单栏", "Menu Bar")
        case .popover:
            copy.text("面板内容", "Popover")
        case .codexActivity:
            copy.text("连接与灵动岛", "Connection & Island")
        case .appearance:
            copy.text("外观", "Appearance")
        case .language:
            copy.text("语言", "Language")
        case .general:
            copy.text("通用", "General")
        }
    }

    func subtitle(_ copy: AppCopy) -> String {
        switch self {
        case .menuBar:
            copy.text(
                "选择菜单栏中持续显示的信息。",
                "Choose the information that remains visible in the menu bar."
            )
        case .popover:
            copy.text(
                "管理 QuotaView 主面板中的数据和操作。",
                "Manage the data and actions shown in the QuotaView popover."
            )
        case .codexActivity:
            copy.text(
                "通过官方 Codex 登录和配套插件获取用量与任务状态。",
                "Use official Codex sign-in and the companion plugin for usage and activity status."
            )
        case .appearance:
            copy.text(
                "设置窗口外观和状态栏面板的玻璃质感。",
                "Set the window appearance and the menu panel's glass treatment."
            )
        case .language:
            copy.text(
                "选择 QuotaView 界面使用的语言。",
                "Choose the language used throughout QuotaView."
            )
        case .general:
            copy.text(
                "查看应用信息、当前版本与隐私政策。",
                "View app information, the current version, and privacy policy."
            )
        }
    }
}

@MainActor
final class SettingsNavigation: ObservableObject {
    @Published var selection: SettingsPage? = .menuBar

    func showConnectionAndIsland() {
        selection = .codexActivity
    }
}

struct SettingsView: View {
    @ObservedObject var store: CodexStatusStore
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var activityRuntime: CodexActivityRuntime
    @ObservedObject var navigation: SettingsNavigation

    @Environment(\.colorScheme) private var colorScheme
    @State private var codexActivityDetailsExpanded = false

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

                settingsDetail(for: navigation.selection ?? .menuBar)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .tint(Color(nsColor: .controlAccentColor))
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
            List(selection: $navigation.selection) {
                Section {
                    ForEach(SettingsPage.allCases) { page in
                        Label(
                            page.title(copy),
                            systemImage: page.symbol
                        )
                        .font(.body.weight(.medium))
                        .padding(.vertical, 4)
                        .tag(page)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .padding(.top, 44)
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

    private func settingsDetail(
        for page: SettingsPage
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                settingsHeader(for: page)

                switch page {
                case .menuBar:
                    menuBarSettings
                case .popover:
                    popoverSettings
                case .codexActivity:
                    codexActivitySettings
                case .appearance:
                    appearanceSettings
                case .language:
                    languageSettings
                case .general:
                    generalSettings
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 26)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func settingsHeader(
        for page: SettingsPage
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(page.title(copy))
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.primary)

            Text(page.subtitle(copy))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var menuBarSettings: some View {
        NativeSettingsCard {
            NativeSettingsRow(
                title: copy.text("菜单栏预览", "Menu bar preview"),
                subtitle: copy.text(
                    "预览会随下方选项即时更新。",
                    "The preview updates immediately with the options below."
                )
            ) {
                menuBarPreview
            }

            NativeSettingsDivider()

            menuBarToggle(
                component: .statusIcon,
                title: copy.text("状态图标", "Status icon"),
                subtitle: copy.text(
                    "在菜单栏中显示 QuotaView 图标。",
                    "Show the QuotaView icon in the menu bar."
                )
            )

            NativeSettingsDivider()

            menuBarToggle(
                component: .remainingQuota,
                title: copy.text(
                    "剩余额度百分比",
                    "Remaining quota percentage"
                ),
                subtitle: copy.text(
                    "显示当前周期的剩余额度。",
                    "Show the quota remaining in the current cycle."
                )
            )

            NativeSettingsDivider()

            menuBarToggle(
                component: .resetCountdown,
                title: copy.text(
                    "下次重置倒计时",
                    "Next reset countdown"
                ),
                subtitle: copy.text(
                    "显示距离下次用量周期重置的时间。",
                    "Show the time until the next usage-cycle reset."
                )
            )

            NativeSettingsDivider()

            NativeSettingsNote(
                text: copy.text(
                    "至少保留一项，避免菜单栏入口不可见。",
                    "At least one item stays visible so the menu bar entry cannot disappear."
                )
            )
        }
    }

    private var popoverSettings: some View {
        NativeSettingsCard {
            preferenceToggle(
                copy.text("周期用量概览", "Quota overview"),
                subtitle: copy.text(
                    "显示当前周期的已用量和剩余量。",
                    "Show used and remaining quota for the current cycle."
                ),
                isOn: $preferences.showUsageSummary
            )

            NativeSettingsDivider()

            preferenceToggle(
                copy.text("下次重置时间", "Next reset time"),
                subtitle: copy.text(
                    "显示当前用量周期的重置倒计时。",
                    "Show the reset countdown for the current usage cycle."
                ),
                isOn: $preferences.showNextReset
            )

            NativeSettingsDivider()

            preferenceToggle(
                copy.text("Credits 余额", "Credits balance"),
                subtitle: copy.text(
                    "显示账户可用的 Credits 余额。",
                    "Show the available Credits balance for the account."
                ),
                isOn: $preferences.showCreditBalance
            )

            NativeSettingsDivider()

            preferenceToggle(
                copy.text("最近一天 Token", "Recent daily tokens"),
                subtitle: copy.text(
                    "显示最近一个统计日的 Token 用量。",
                    "Show token usage for the most recent reporting day."
                ),
                isOn: $preferences.showDailyTokens
            )

            NativeSettingsDivider()

            preferenceToggle(
                copy.text("累计 Token", "Lifetime tokens"),
                subtitle: copy.text(
                    "显示当前账户的累计 Token 用量。",
                    "Show lifetime token usage for the current account."
                ),
                isOn: $preferences.showLifetimeTokens
            )

            NativeSettingsDivider()

            NativeSettingsNote(
                text: copy.text(
                    "修改会立即反映在 QuotaView 状态栏面板中。",
                    "Changes appear in the QuotaView menu bar panel immediately."
                )
            )
        }
    }

    private var appearanceSettings: some View {
        VStack(spacing: 16) {
            NativeSettingsCard {
                NativeSettingsRow(
                    title: copy.text(
                        "跟随系统外观",
                        "Follow system appearance"
                    ),
                    subtitle: copy.text(
                        "自动使用 macOS 当前的浅色或深色外观。",
                        "Automatically use the current macOS light or dark appearance."
                    )
                ) {
                    Toggle(
                        copy.text(
                            "跟随系统外观",
                            "Follow system appearance"
                        ),
                        isOn: $preferences.followsSystemAppearance
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }

                NativeSettingsDivider()

                NativeSettingsRow(
                    title: copy.text(
                        "自定义显示模式",
                        "Custom appearance"
                    )
                ) {
                    Picker(
                        copy.text(
                            "自定义显示模式",
                            "Custom appearance"
                        ),
                        selection: $preferences.customAppearance
                    ) {
                        Label(
                            copy.text("浅色", "Light"),
                            systemImage: "sun.max"
                        )
                        .tag(AppPreferences.AppearanceMode.light)

                        Label(
                            copy.text("深色", "Dark"),
                            systemImage: "moon"
                        )
                        .tag(AppPreferences.AppearanceMode.dark)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .disabled(preferences.followsSystemAppearance)
                }

                NativeSettingsDivider()

                NativeSettingsNote(text: appearanceSummary)
            }

            NativeSettingsCard {
                NativeSettingsRow(
                    title: copy.text("玻璃质感", "Glass appearance"),
                    subtitle: copy.text(
                        "只影响菜单栏弹出面板。",
                        "Applies only to the menu bar panel."
                    )
                ) {
                    Picker(
                        copy.text("玻璃质感", "Glass appearance"),
                        selection: $preferences.glassMode
                    ) {
                        Text(copy.text("磨砂", "Frosted"))
                            .tag(QuotaViewGlassMode.frosted)
                        Text(copy.text("清透", "Clear"))
                            .tag(QuotaViewGlassMode.clear)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                }

                NativeSettingsDivider()

                NativeSettingsNote(text: glassModeSummary)
            }
        }
    }

    private var codexActivitySettings: some View {
        VStack(spacing: 16) {
            NativeSettingsCard {
                NativeSettingsRow(
                    title: copy.text(
                        "官方 Codex 账号",
                        "Official Codex account"
                    ),
                    subtitle: copy.text(
                        "登录由 Codex 官方应用管理；QuotaView 不会获取或保存登录 Token。",
                        "Sign-in is managed by the official Codex app; QuotaView never receives or stores sign-in tokens."
                    )
                ) {
                    Button(copy.text("打开 Codex", "Open Codex")) {
                        activityRuntime.openOfficialCodex()
                    }
                    .nativeSettingsActionStyle()
                    .controlSize(.small)
                    .help(copy.text(
                        "打开官方 Codex 并完成登录",
                        "Open official Codex and complete sign-in"
                    ))
                }

                NativeSettingsDivider()

                NativeSettingsRow(
                    title: copy.text(
                        "QuotaView for Codex 插件",
                        "QuotaView for Codex plugin"
                    ),
                    subtitle: copy.text(
                        "安装、启用与 Hooks 信任全部在 Codex 中完成。",
                        "Installation, enablement, and Hooks trust are handled inside Codex."
                    )
                ) {
                    Button(copy.text("安装指南", "Setup Guide")) {
                        activityRuntime.openInstallationGuide()
                    }
                    .nativeSettingsActionStyle()
                    .controlSize(.small)
                    .help(copy.text("打开插件安装指南", "Open plugin setup guide"))
                    .accessibilityLabel(
                        copy.text("打开插件安装指南", "Open plugin setup guide")
                    )
                }

                NativeSettingsDivider()

                NativeSettingsRow(
                    title: copy.text("只读数据目录", "Read-only data folder"),
                    subtitle: codexActivityConnectionSubtitle
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

                        Button(codexActivityActionTitle) {
                            switch activityRuntime.connectionStatus {
                            case .connected, .stale,
                                 .pairedWaitingForEvent:
                                activityRuntime.disconnectPluginData()
                            case .notConfigured, .awaitingAuthorization,
                                 .reauthorizationRequired, .incompatible,
                                 .malformedData:
                                activityRuntime
                                    .choosePluginDataDirectory()
                            }
                        }
                        .nativeSettingsActionStyle()
                        .controlSize(.small)
                        .disabled(activityRuntime.isAuthorizingDirectory)
                        .help(codexActivityActionTitle)
                        .accessibilityLabel(codexActivityActionTitle)
                    }
                }

                NativeSettingsDivider()

                DisclosureGroup(
                    isExpanded: $codexActivityDetailsExpanded
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        LabeledContent(
                            copy.text("插件版本", "Plugin version"),
                            value: activityRuntime.pluginVersion ?? "—"
                        )
                        LabeledContent(
                            copy.text("分发渠道", "Distribution channel"),
                            value: activityRuntime.distributionChannel ?? "—"
                        )
                        LabeledContent(
                            copy.text("最近用量快照", "Latest usage snapshot"),
                            value: codexActivityLastUsageTitle
                        )
                        LabeledContent(
                            copy.text("最近事件", "Latest event"),
                            value: codexActivityLastEventTitle
                        )
                        if let issue = activityRuntime.connectionIssue {
                            Text(codexActivityIssueText(issue))
                                .foregroundStyle(
                                    codexActivityIssueColor(issue)
                                )
                        }
                        Text(copy.text(
                            "QuotaView 只读取用户明确授权目录中的脱敏用量快照和活动事件；不会读取凭证或修改 Codex 配置。",
                            "QuotaView only reads sanitized usage snapshots and activity events from the folder you explicitly authorize; it never reads credentials or modifies Codex settings."
                        ))
                            .foregroundStyle(.tertiary)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
                } label: {
                    Text(copy.text("连接详情", "Connection Details"))
                        .font(.body.weight(.medium))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 11)

                NativeSettingsDivider()

                NativeSettingsNote(
                    text: copy.text(
                        "用量图表与 Codex 灵动岛均已包含在 QuotaView 中；完成官方 Codex 登录、安装插件并配对目录后即可使用。",
                        "Usage charts and Codex Island are included with QuotaView. Sign in through official Codex, install the plugin, and pair its folder to use them."
                    )
                )
            }

            NativeSettingsCard {
                NativeSettingsRow(
                    title: copy.text("灵动岛", "Codex Island"),
                    subtitle: copy.text(
                        "显示 Codex 任务活动状态；关闭后仍会继续读取用量与连接数据。",
                        "Show Codex task activity. Usage and connection data continue updating when it is off."
                    )
                ) {
                    Toggle(
                        copy.text("灵动岛", "Codex Island"),
                        isOn: $preferences.showCodexIsland
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help(copy.text(
                        "开启或关闭 Codex 灵动岛",
                        "Turn Codex Island on or off"
                    ))
                    .accessibilityLabel(copy.text(
                        "灵动岛",
                        "Codex Island"
                    ))
                }

                NativeSettingsDivider()

                NativeSettingsRow(
                    title: copy.text(
                        "自适应显示",
                        "Adaptive presentation"
                    ),
                    subtitle: copy.text(
                        "任务活动时展开；完成 20 秒后缩为最小态，完成满 2 分钟后隐藏。任何新活动都会立即重新展开。",
                        "Expands during activity, compacts 20 seconds after completion, and hides two minutes after completion. New activity expands it immediately."
                    )
                ) {
                    Text(copy.text("自动", "Automatic"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                NativeSettingsDivider()

                NativeSettingsNote(
                    text: copy.text(
                        "开启“减少动态效果”时，窗口与球体使用静态状态反馈。",
                        "When Reduce Motion is enabled, the window and orb use static state feedback."
                    )
                )
            }
        }
        .onAppear {
            activityRuntime.refreshConnectionStatus()
        }
    }

    private var languageSettings: some View {
        NativeSettingsCard {
            NativeSettingsRow(
                title: copy.text(
                    "跟随系统语言",
                    "Follow system language"
                ),
                subtitle: copy.text(
                    "根据 macOS 首选语言自动切换。",
                    "Automatically follow the preferred macOS language."
                )
            ) {
                Toggle(
                    copy.text(
                        "跟随系统语言",
                        "Follow system language"
                    ),
                    isOn: $preferences.followsSystemLanguage
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            NativeSettingsDivider()

            NativeSettingsRow(
                title: copy.text("自定义语言", "Custom language")
            ) {
                Picker(
                    copy.text("自定义语言", "Custom language"),
                    selection: $preferences.customLanguage
                ) {
                    Text("简体中文")
                        .tag(AppPreferences.Language.simplifiedChinese)
                    Text("English")
                        .tag(AppPreferences.Language.english)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .disabled(preferences.followsSystemLanguage)
            }

            NativeSettingsDivider()

            NativeSettingsNote(text: languageSummary)
        }
    }

    private var generalSettings: some View {
        VStack(spacing: 22) {
            VStack(spacing: 0) {
                Spacer(minLength: 28)

                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .shadow(
                        color: Color.black.opacity(0.18),
                        radius: 10,
                        x: 0,
                        y: 5
                    )
                    .accessibilityLabel(
                        copy.text(
                            "QuotaView 应用图标",
                            "QuotaView app icon"
                        )
                    )

                Text("QuotaView")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.top, 18)

                Text(
                    copy.text(
                        "本地 Codex 用量监视器",
                        "Local Codex quota monitor"
                    )
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

                Text(versionAndBuildLabel)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 10)

                Spacer(minLength: 28)
            }
            .frame(maxWidth: .infinity, minHeight: 330)

            NativeSettingsCard {
                NativeSettingsRow(
                    title: copy.text("隐私政策", "Privacy policy"),
                    subtitle: copy.text(
                        "了解 QuotaView 如何处理账号、用量和本地插件数据。",
                        "Learn how QuotaView handles account, usage, and local plugin data."
                    )
                ) {
                    privacyPolicyControl
                }

                NativeSettingsDivider()

                NativeSettingsRow(
                    title: copy.text("支持", "Support"),
                    subtitle: copy.text(
                        "获取账号连接、额度、小组件、购买和灵动岛帮助。",
                        "Get help with account connection, quota, widgets, purchases, and Codex Island."
                    )
                ) {
                    supportControl
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var privacyPolicyControl: some View {
        if let url = privacyPolicyConfiguration.publishedURL {
            Link(destination: url) {
                Label(
                    copy.text("查看", "View"),
                    systemImage: "arrow.up.right"
                )
            }
            .controlSize(.small)
            .help(copy.text("打开隐私政策", "Open privacy policy"))
            .accessibilityLabel(
                copy.text(
                    "打开 QuotaView 隐私政策",
                    "Open QuotaView privacy policy"
                )
            )
        } else {
            Text(copy.text("待发布", "Pending publication"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .help(
                    copy.text(
                        "隐私政策公开发布后可在此查看。",
                        "The privacy policy will be available here after publication."
                    )
                )
                .accessibilityLabel(
                    copy.text(
                        "隐私政策尚未发布",
                        "Privacy policy has not been published"
                    )
                )
        }
    }

    private var privacyPolicyConfiguration: AppStorePublicLinkConfiguration {
        AppStorePublicLinkConfiguration(
            bundle: .main,
            statusKey: "QuotaViewPrivacyPolicyStatus",
            urlKey: "QuotaViewPrivacyPolicyURL"
        )
    }

    @ViewBuilder
    private var supportControl: some View {
        if let url = supportConfiguration.publishedURL {
            Link(destination: url) {
                Label(
                    copy.text("查看", "View"),
                    systemImage: "arrow.up.right"
                )
            }
            .controlSize(.small)
            .help(copy.text("打开支持页面", "Open support page"))
            .accessibilityLabel(
                copy.text(
                    "打开 QuotaView 支持页面",
                    "Open QuotaView support page"
                )
            )
        } else {
            Text(copy.text("待发布", "Pending publication"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .help(
                    copy.text(
                        "支持页面公开发布后可在此查看。",
                        "Support will be available here after publication."
                    )
                )
                .accessibilityLabel(
                    copy.text(
                        "支持页面尚未发布",
                        "Support page has not been published"
                    )
                )
        }
    }

    private var supportConfiguration: AppStorePublicLinkConfiguration {
        AppStorePublicLinkConfiguration(
            bundle: .main,
            statusKey: "QuotaViewSupportStatus",
            urlKey: "QuotaViewSupportURL"
        )
    }

    private var versionAndBuildLabel: String {
        AppVersionInfo(bundle: .main).label(copy: copy)
    }

    private var menuBarPreview: some View {
        MenuBarStatusLabel(
            store: store,
            preferences: preferences
        )
        .font(.system(size: 12, weight: .semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Color(nsColor: .quaternaryLabelColor)
                .opacity(colorScheme == .dark ? 0.28 : 0.14),
            in: Capsule()
        )
        .overlay {
            Capsule()
                .strokeBorder(
                    Color(nsColor: .separatorColor),
                    lineWidth: 0.5
                )
        }
    }

    private func menuBarToggle(
        component: AppPreferences.MenuBarComponent,
        title: String,
        subtitle: String
    ) -> some View {
        NativeSettingsRow(
            title: title,
            subtitle: subtitle
        ) {
            Toggle(
                title,
                isOn: preferences.binding(for: component)
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(
                preferences.isVisible(component)
                && !preferences.canHide(component)
            )
        }
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
                .toggleStyle(.switch)
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
            "QuotaView 将固定使用\(selected)模式。",
            "QuotaView will always use the \(selected) appearance."
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

    private var glassModeSummary: String {
        switch preferences.glassMode {
        case .frosted:
            if colorScheme == .dark {
                return copy.text(
                    "深色模式使用烟灰磨砂，优先保证内容可读性。",
                    "Dark mode uses a smoky frosted surface for stronger legibility."
                )
            }
            return copy.text(
                "浅色模式使用乳白磨砂，优先保证内容可读性。",
                "Light mode uses a milky frosted surface for stronger legibility."
            )

        case .clear:
            if colorScheme == .dark {
                return copy.text(
                    "深色模式使用中性暗色压光，降低背景干扰并保留清透质感。",
                    "Dark mode applies neutral dimming to reduce background interference while preserving clear glass."
                )
            }
            return copy.text(
                "浅色模式使用中性亮色提光，降低背景干扰并保留清透质感。",
                "Light mode applies neutral brightening to reduce background interference while preserving clear glass."
            )
        }
    }

    private var codexActivityActionTitle: String {
        if activityRuntime.isAuthorizingDirectory {
            return copy.text("等待授权", "Authorizing")
        }
        return switch activityRuntime.connectionStatus {
        case .connected, .stale, .pairedWaitingForEvent:
            copy.text("断开", "Disconnect")
        case .notConfigured, .awaitingAuthorization,
             .reauthorizationRequired, .incompatible, .malformedData:
            copy.text("选择目录", "Choose Folder")
        }
    }

    private var codexActivityConnectionSubtitle: String {
        if activityRuntime.isAuthorizingDirectory {
            return copy.text(
                "等待你在系统面板中选择插件数据目录。",
                "Waiting for you to choose the plugin data folder in the system panel."
            )
        }

        return switch activityRuntime.connectionStatus {
        case .notConfigured:
            copy.text(
                "尚未授权插件的 PLUGIN_DATA 目录。",
                "The plugin PLUGIN_DATA folder has not been authorized."
            )
        case .awaitingAuthorization:
            copy.text(
                "需要在系统目录选择器中确认只读访问。",
                "Confirm read-only access in the system folder picker."
            )
        case .pairedWaitingForEvent:
            copy.text(
                "握手有效；请在 Codex 中完成登录并开始一个任务。",
                "The handshake is valid; sign in through Codex and start a task."
            )
        case .connected:
            copy.text(
                "最近收到了有效的脱敏 Codex 数据。",
                "Valid sanitized Codex data was received recently."
            )
        case .stale:
            copy.text(
                "连接曾经可用，但最近没有新事件。",
                "The connection worked before, but no recent event has arrived."
            )
        case .reauthorizationRequired:
            copy.text("目录授权已失效，请重新选择。", "Folder access expired; choose it again.")
        case .incompatible:
            copy.text("插件协议与当前 App 版本不兼容。", "The plugin protocol is incompatible with this app version.")
        case .malformedData:
            activityRuntime.connectionIssue.map(codexActivityIssueText)
                ?? copy.text(
                    "插件数据无法验证。",
                    "The plugin data could not be verified."
                )
        }
    }

    private var codexActivityConnectionStatusTitle: String {
        if activityRuntime.isAuthorizingDirectory {
            return copy.text("正在准备", "Preparing")
        }

        return switch activityRuntime.connectionStatus {
        case .notConfigured:
            copy.text("未配对", "Not Paired")
        case .awaitingAuthorization:
            copy.text("等待授权", "Awaiting Access")
        case .pairedWaitingForEvent:
            copy.text("等待事件", "Waiting for Event")
        case .connected:
            copy.text("已连接", "Connected")
        case .stale:
            copy.text("连接过期", "Stale")
        case .reauthorizationRequired:
            copy.text("需要重新授权", "Access Required")
        case .incompatible:
            copy.text("版本不兼容", "Incompatible")
        case .malformedData:
            copy.text("数据异常", "Invalid Data")
        }
    }

    private func codexActivityIssueText(
        _ issue: CodexPluginConnectionIssue
    ) -> String {
        switch issue {
        case .someMalformedEvents:
            copy.text(
                "部分格式异常的插件事件已被安全忽略。",
                "Some malformed plugin events were safely ignored."
            )
        case .folderAuthorizationFailed:
            copy.text(
                "无法授权所选插件数据目录。",
                "The selected plugin data folder could not be authorized."
            )
        case .bookmarkExpired:
            copy.text(
                "目录读取授权已失效，请重新选择。",
                "Read access to the folder expired. Choose it again."
            )
        case .readFailed:
            copy.text(
                "无法读取已授权的插件数据。",
                "The authorized plugin data could not be read."
            )
        case .validation(let error):
            switch error {
            case .oversized:
                copy.text("插件数据文件过大。", "A plugin data file is too large.")
            case .malformed:
                copy.text("插件数据格式异常。", "The plugin data is malformed.")
            case .wrongPlugin:
                copy.text(
                    "所选目录不属于 QuotaView for Codex。",
                    "The selected folder does not belong to QuotaView for Codex."
                )
            case .incompatibleProtocol, .incompatibleEventSchema,
                 .incompatibleUsageSchema:
                copy.text(
                    "插件版本与当前 QuotaView 不兼容。",
                    "The plugin version is incompatible with this version of QuotaView."
                )
            case .invalidInstallationIdentifier, .missingCapability,
                 .missingUsageCapability, .invalidMetadata:
                copy.text("插件握手信息无效。", "The plugin handshake is invalid.")
            case .installationMismatch, .sequenceMismatch:
                copy.text(
                    "插件事件与当前安装不匹配。",
                    "The plugin event does not match the paired installation."
                )
            case .invalidActivityIdentifier, .invalidWorkspaceName:
                copy.text(
                    "插件事件包含不安全的元数据。",
                    "The plugin event contains unsafe metadata."
                )
            case .eventExpired:
                copy.text("插件事件已过期。", "The plugin event has expired.")
            case .eventFromFuture:
                copy.text(
                    "插件事件时间戳无效。",
                    "The plugin event timestamp is invalid."
                )
            case .usageSnapshotMissing:
                copy.text(
                    "插件尚未生成用量快照。",
                    "The plugin has not generated a usage snapshot yet."
                )
            case .usageSnapshotExpired:
                copy.text(
                    "插件用量快照已过期。",
                    "The plugin usage snapshot is out of date."
                )
            case .invalidUsageSnapshot:
                copy.text(
                    "插件用量快照格式异常。",
                    "The plugin usage snapshot is invalid."
                )
            }
        }
    }

    private func codexActivityIssueColor(
        _ issue: CodexPluginConnectionIssue
    ) -> Color {
        issue == .someMalformedEvents
            ? Color(nsColor: .systemOrange)
            : Color(nsColor: .systemRed)
    }

    private var codexActivityConnectionColor: Color {
        if activityRuntime.isAuthorizingDirectory {
            return Color(nsColor: .systemBlue)
        }

        return switch activityRuntime.connectionStatus {
        case .connected:
            Color(nsColor: .systemGreen)
        case .awaitingAuthorization,
             .pairedWaitingForEvent,
             .stale:
            Color(nsColor: .systemOrange)
        case .reauthorizationRequired, .incompatible, .malformedData:
            Color(nsColor: .systemRed)
        case .notConfigured:
            Color(nsColor: .tertiaryLabelColor)
        }
    }

    private var codexActivityLastEventTitle: String {
        activityRuntime.lastEventAt?.formatted(
            date: .omitted,
            time: .standard
        ) ?? "—"
    }

    private var codexActivityLastUsageTitle: String {
        activityRuntime.lastUsageAt?.formatted(
            date: .omitted,
            time: .standard
        ) ?? "—"
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

    @ViewBuilder
    func nativeSettingsActionStyle() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
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
                cornerRadius: 12,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 12,
                style: .continuous
            )
            .strokeBorder(
                Color(nsColor: .separatorColor),
                lineWidth: 0.5
            )
        }
        .clipShape(
            RoundedRectangle(
                cornerRadius: 12,
                style: .continuous
            )
        )
    }
}

private struct NativeSettingsRow<Control: View>: View {
    let title: String
    let subtitle: String?
    let control: Control

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.subtitle = subtitle
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)

                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 18)

            control
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, minHeight: 52)
        .contentShape(Rectangle())
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

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MenuBarStatusLabel: View {
    @ObservedObject var store: CodexStatusStore
    @ObservedObject var preferences: AppPreferences

    private var copy: AppCopy { preferences.copy }

    var body: some View {
        MenuBarStatusContent(
            showsIcon: preferences.showStatusIcon,
            textParts: statusTextParts,
            accessibilityText: statusAccessibilityText
        )
    }

    var statusTextParts: [String] {
        [
            preferences.showRemainingQuota
                ? remainingLabel
                : nil,
            preferences.showResetCountdown
                ? countdownLabel
                : nil
        ].compactMap { $0 }
    }

    var statusAccessibilityText: String {
        accessibilityStatus
    }

    private var remainingLabel: String {
        guard let snapshot = store.snapshot else { return "—%" }
        return "\(snapshot.remainingPercent)%"
    }

    private var countdownLabel: String {
        guard let resetDate = store.snapshot?.resetsAt else { return "—" }
        let remaining = max(Int(resetDate.timeIntervalSinceNow), 0)
        let days = remaining / 86_400
        let hours = (remaining % 86_400) / 3_600
        let minutes = (remaining % 3_600) / 60

        if days > 0 {
            return copy.text("\(days)天", "\(days)d")
        }
        if hours > 0 {
            return copy.text("\(hours)时", "\(hours)h")
        }
        return copy.text("\(max(minutes, 1))分", "\(max(minutes, 1))m")
    }

    private var accessibilityStatus: String {
        if let error = store.providerError {
            return copy.text(
                "QuotaView：\(copy.providerErrorText(error))",
                "QuotaView: \(copy.providerErrorText(error))"
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

private extension AppCopy {
    func providerErrorText(_ error: ProviderError) -> String {
        switch error {
        case .unavailable:
            text("Codex 用量服务当前不可用。", "Codex usage is currently unavailable.")
        case .notConfigured:
            text("尚未配对 Codex 插件数据目录。", "The Codex plugin data folder has not been paired.")
        case .authenticationRequired:
            text(
                "请在官方 Codex 中登录 ChatGPT 账号。",
                "Sign in to your ChatGPT account through official Codex."
            )
        case .timedOut:
            text("读取 Codex 用量超时。", "The Codex usage request timed out.")
        case .processExited:
            text("Codex 数据进程意外退出。", "The Codex data process exited unexpectedly.")
        case .protocolViolation:
            text("Codex 返回了无法识别的数据。", "Codex returned an unrecognized response.")
        case .unsupportedSchema:
            text(
                "当前 Codex 数据格式暂不受支持。",
                "This Codex data format is not supported yet."
            )
        case .permissionDenied:
            text("Codex 拒绝了只读用量请求。", "Codex denied the read-only usage request.")
        case .cancelled:
            text("Codex 用量刷新已取消。", "The Codex usage refresh was cancelled.")
        case .transient:
            text(
                "Codex 用量暂时无法刷新，请稍后重试。",
                "Codex usage could not be refreshed. Try again later."
            )
        }
    }
}

private struct MenuBarStatusContent: View {
    let showsIcon: Bool
    let textParts: [String]
    let accessibilityText: String

    var body: some View {
        HStack(spacing: 3) {
            if showsIcon {
                MenuBarBrandIcon()
            }

            if !textParts.isEmpty {
                Text(verbatim: textParts.joined(separator: " "))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
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
