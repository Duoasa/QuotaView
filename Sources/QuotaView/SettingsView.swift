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

struct SettingsView: View {
    @ObservedObject var store: CodexStatusStore
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var activityRuntime: CodexActivityRuntime

    @Environment(\.colorScheme) private var colorScheme
    @State private var selection: SettingsPage? = .menuBar
    @State private var updatePlaceholderVisible = false
    @State private var codexActivityDetailsExpanded = false

    private var copy: AppCopy { preferences.copy }

    private enum SettingsPage: String, CaseIterable, Identifiable {
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
            case .codexActivity: "waveform.path.ecg.rectangle"
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
                copy.text("Codex 灵动岛", "Codex Island")
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
                    "配置 Codex 灵动岛连接与状态显示。",
                    "Configure the Codex island connection and status display."
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
                    "查看应用信息和软件更新状态。",
                    "View app information and software update status."
                )
            }
        }
    }

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

                settingsDetail(for: selection ?? .menuBar)
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
            List(selection: $selection) {
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

            preferenceToggle(
                copy.text("额度重置入口", "Quota reset entry"),
                subtitle: copy.text(
                    "当存在可用的重置时，在主面板中显示额度重置页面入口。",
                    "When a reset credit is available, show the quota-reset "
                        + "entry in the main panel."
                ),
                isOn: $preferences.showResetAction
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
                        "Codex 灵动岛",
                        "Codex Island"
                    ),
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

                        Button {
                            switch activityRuntime.connectionStatus {
                            case .notInstalled, .abnormal:
                                activityRuntime.enableCodexActivity()
                            case .installedNeedsRestart:
                                activityRuntime.restartCodex()
                            case .awaitingTrust:
                                activityRuntime.openCodexSecurityReview()
                            case .awaitingFirstEvent, .connected:
                                activityRuntime.disableCodexActivity()
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

                if codexActivityShowsNextStep {
                    NativeSettingsDivider()

                    NativeSettingsRow(
                        title: codexActivityNextStepTitle,
                        subtitle: codexActivityNextStepSubtitle
                    ) {}
                }

                NativeSettingsDivider()

                NativeSettingsNote(
                    text: copy.text(
                        "首次连接只需进行一次 Codex 安全确认。QuotaView 不读取提示词、命令正文、工具输出或会话记录。",
                        "First-time setup requires one Codex security review. QuotaView does not read prompts, command text, tool output, or transcripts."
                    )
                )

                NativeSettingsDivider()

                NativeSettingsRow(
                    title: copy.text(
                        "跟随当前 Codex 任务",
                        "Follow Current Codex Task"
                    ),
                    subtitle: copy.text(
                        "只读取 Codex 当前任务标题，用于在多个活动任务之间同步灵动岛；不会读取提示词、回复、命令或工具内容，也不会操作 Codex。",
                        "Reads only the current Codex task title to keep the island synchronized across active tasks. It does not read prompts, responses, commands, or tool content, and never controls Codex."
                    )
                ) {
                    Toggle(
                        copy.text(
                            "跟随当前 Codex 任务",
                            "Follow Current Codex Task"
                        ),
                        isOn: Binding(
                            get: {
                                preferences.followCurrentCodexTask
                            },
                            set: {
                                activityRuntime
                                    .setFollowCurrentTaskEnabled($0)
                            }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }

                if activityRuntime.focusTrackingStatus
                    == .permissionRequired
                {
                    NativeSettingsDivider()

                    NativeSettingsNote(
                        text: copy.text(
                            "需要在“系统设置 → 隐私与安全性 → 辅助功能”中允许 QuotaView。未授权时，多任务仍使用安全的自动优先级降级。",
                            "Allow QuotaView in System Settings → Privacy & Security → Accessibility. Without permission, multitasking safely falls back to automatic priority."
                        )
                    )
                }

                NativeSettingsDivider()

                DisclosureGroup(
                    isExpanded: $codexActivityDetailsExpanded
                ) {
                    VStack(alignment: .leading, spacing: 10) {
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
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
            }

            NativeSettingsCard {
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
        VStack(spacing: 0) {
            Spacer(minLength: 42)

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
                    copy.text("QuotaView 应用图标", "QuotaView app icon")
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

            Button {
                updatePlaceholderVisible = true
            } label: {
                Text(copy.text("检查更新…", "Check for Updates…"))
                    .frame(minWidth: 112)
            }
            .nativeSettingsActionStyle()
            .controlSize(.small)
            .padding(.top, 22)

            if updatePlaceholderVisible {
                Text(
                    copy.text(
                        "自动更新服务将在正式发布前接入。",
                        "The automatic update service will be connected before release."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 12)
                .transition(.opacity)
            }

            Spacer(minLength: 42)
        }
        .frame(maxWidth: .infinity, minHeight: 430)
        .animation(
            .easeOut(duration: 0.16),
            value: updatePlaceholderVisible
        )
    }

    private var versionAndBuildLabel: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0.3.2"
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "1"
        let isPreview = Bundle.main.object(
            forInfoDictionaryKey: "QuotaViewReleaseChannel"
        ) as? String == "preview"
        let channelSuffix = isPreview
            ? copy.text(" · 预览版", " · Preview")
            : ""
        return copy.text(
            "版本 \(version)（\(build)）",
            "Version \(version) (\(build))"
        ) + channelSuffix
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
        if activityRuntime.isConfiguring {
            return copy.text("正在准备", "Preparing")
        }
        if activityRuntime.isOpeningSecurityReview {
            return copy.text("正在打开", "Opening")
        }
        return switch activityRuntime.connectionStatus {
        case .notInstalled:
            copy.text("连接 Codex", "Connect Codex")
        case .abnormal:
            copy.text("修复连接", "Fix Connection")
        case .installedNeedsRestart:
            copy.text("重新启动 Codex", "Restart Codex")
        case .awaitingTrust:
            copy.text("打开安全确认", "Open Security Review")
        case .awaitingFirstEvent, .connected:
            copy.text("停用", "Disable")
        }
    }

    private var codexActivityActionHelp: String {
        return switch activityRuntime.connectionStatus {
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
                "停用 Codex 灵动岛连接。",
                "Disable the Codex island connection."
            )
        case .notInstalled, .abnormal:
            copy.text(
                "自动准备 Codex 连接，并立即显示未连接状态的灵动岛。",
                "Prepare the Codex connection automatically and show the disconnected activity island immediately."
            )
        }
    }

    private var codexActivityConnectionSubtitle: String {
        if activityRuntime.isConfiguring
            || activityRuntime.isOpeningSecurityReview
        {
            return copy.text(
                "正在自动准备连接，并立即显示“未连接 Codex”的灵动岛。",
                "Preparing the connection automatically and showing the Codex Not Connected island immediately."
            )
        }

        return switch activityRuntime.connectionStatus {
        case .notInstalled:
            copy.text(
                "连接后会立即呼出灵动岛，并自动完成连接准备。",
                "Connecting immediately shows the island and prepares the connection automatically."
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
            copy.text(
                "重启已经完成；发送一条新的 Codex 消息完成连接。",
                "Restart is complete. Send a new Codex message to finish connecting."
            )
        case .connected:
            copy.text(
                "连接已激活，灵动岛会实时显示 Codex 当前状态。",
                "The connection is active and the island now reflects the current Codex status."
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

        return switch activityRuntime.connectionStatus {
        case .notInstalled:
            copy.text("未启用", "Not Enabled")
        case .installedNeedsRestart, .awaitingTrust:
            copy.text("需要安全确认", "Security Review Needed")
        case .awaitingFirstEvent:
            copy.text("等待第一条消息", "Waiting for First Message")
        case .connected:
            copy.text("已连接", "Connected")
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

        return switch activityRuntime.connectionStatus {
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
        switch activityRuntime.hooksFeatureStatus {
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
        switch activityRuntime.connectionStatus {
        case .installedNeedsRestart, .awaitingTrust, .awaitingFirstEvent:
            true
        case .notInstalled, .connected, .abnormal:
            false
        }
    }

    private var codexActivityNextStepTitle: String {
        switch activityRuntime.connectionStatus {
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
            copy.text("发送一条新消息", "Send a New Message")
        case .notInstalled, .connected, .abnormal:
            ""
        }
    }

    private var codexActivityNextStepSubtitle: String {
        switch activityRuntime.connectionStatus {
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
            copy.text(
                "不会发送测试数据；收到重启后的第一条真实消息时，灵动岛会自动切换为活动状态。",
                "No test data is sent. The island switches to its active state after the first real message following restart."
            )
        case .notInstalled, .connected, .abnormal:
            ""
        }
    }

    private var codexActivityBridgeSubtitle: String {
        switch activityRuntime.bridgeStatus {
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
        switch activityRuntime.bridgeStatus {
        case .listening:
            copy.text("监听中", "Listening")
        case .stopped:
            copy.text("已停止", "Stopped")
        case .failed:
            copy.text("不可用", "Unavailable")
        }
    }

    private var codexActivityBridgeColor: Color {
        switch activityRuntime.bridgeStatus {
        case .listening:
            Color(nsColor: .systemGreen)
        case .stopped:
            Color(nsColor: .tertiaryLabelColor)
        case .failed:
            Color(nsColor: .systemRed)
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
