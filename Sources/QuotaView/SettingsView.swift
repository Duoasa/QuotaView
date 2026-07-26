import AppKit
import QuotaViewCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: CodexStatusStore
    @ObservedObject var preferences: AppPreferences

    @Environment(\.colorScheme) private var colorScheme

    private var copy: AppCopy { preferences.copy }

    var body: some View {
        Form {
            menuBarSection
            panelSection
            appearanceSection
            languageSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .quotaViewGlassContainer(spacing: 14)
        .quotaViewWindowSurface()
        .frame(width: 560)
        .frame(minHeight: 560)
        .navigationTitle(copy.text("设置", "Settings"))
    }

    private var menuBarSection: some View {
        Section {
            menuBarPreview

            menuBarToggle(
                component: .statusIcon,
                title: copy.text("状态图标", "Status icon"),
                symbol: "bolt.circle.fill"
            )
            menuBarToggle(
                component: .remainingQuota,
                title: copy.text("剩余额度百分比", "Remaining quota percentage"),
                symbol: "percent"
            )
            menuBarToggle(
                component: .resetCountdown,
                title: copy.text("下次重置倒计时", "Next reset countdown"),
                symbol: "clock.arrow.circlepath"
            )

            Text(
                copy.text(
                    "至少保留一项，避免状态栏入口不可见。",
                    "At least one item stays visible so the menu bar entry cannot disappear."
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        } header: {
            Label(
                copy.text("菜单栏标签", "Menu bar label"),
                systemImage: "menubar.rectangle"
            )
        }
    }

    private var panelSection: some View {
        Section {
            preferenceToggle(
                copy.text("周期用量概览", "Quota overview"),
                symbol: "chart.donut",
                isOn: $preferences.showUsageSummary
            )
            preferenceToggle(
                copy.text("下次刷新时间", "Next reset time"),
                symbol: "arrow.clockwise",
                isOn: $preferences.showNextReset
            )
            preferenceToggle(
                copy.text("Credits 余额", "Credits balance"),
                symbol: "creditcard.fill",
                isOn: $preferences.showCreditBalance
            )
            preferenceToggle(
                copy.text("最近一天 Token", "Recent daily tokens"),
                symbol: "textformat.123",
                isOn: $preferences.showDailyTokens
            )
            preferenceToggle(
                copy.text("累计 Token", "Lifetime tokens"),
                symbol: "sum",
                isOn: $preferences.showLifetimeTokens
            )
            preferenceToggle(
                copy.text("额度刷新入口", "Quota reset entry"),
                symbol: "arrow.counterclockwise.circle",
                isOn: $preferences.showResetAction
            )
        } header: {
            Label(
                copy.text("弹出面板内容", "Popover content"),
                systemImage: "rectangle.on.rectangle"
            )
        } footer: {
            Text(
                copy.text(
                    "修改后会立即反映在 QuotaView 面板中。",
                    "Changes appear in the QuotaView popover immediately."
                )
            )
        }
    }

    private var appearanceSection: some View {
        Section {
            Toggle(
                copy.text("跟随系统外观", "Follow system appearance"),
                isOn: $preferences.followsSystemAppearance
            )
            .quotaViewSwitchStyle()

            Picker(
                copy.text("自定义显示模式", "Custom appearance"),
                selection: $preferences.customAppearance
            ) {
                Label(
                    copy.text("浅色", "Light"),
                    systemImage: "sun.max.fill"
                )
                .tag(AppPreferences.AppearanceMode.light)

                Label(
                    copy.text("深色", "Dark"),
                    systemImage: "moon.fill"
                )
                .tag(AppPreferences.AppearanceMode.dark)
            }
            .pickerStyle(.segmented)
            .disabled(preferences.followsSystemAppearance)

            Text(appearanceSummary)
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker(
                copy.text("玻璃质感", "Glass appearance"),
                selection: $preferences.glassMode
            ) {
                Label(
                    copy.text("磨砂", "Frosted"),
                    systemImage: "circle.dotted"
                )
                .tag(QuotaViewGlassMode.frosted)

                Label(
                    copy.text("清透", "Clear"),
                    systemImage: "drop.fill"
                )
                .tag(QuotaViewGlassMode.clear)
            }
            .pickerStyle(.segmented)

            Text(glassModeSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Label(
                copy.text("外观", "Appearance"),
                systemImage: "circle.lefthalf.filled"
            )
        }
    }

    private var languageSection: some View {
        Section {
            Toggle(
                copy.text("跟随系统语言", "Follow system language"),
                isOn: $preferences.followsSystemLanguage
            )
            .quotaViewSwitchStyle()

            Picker(
                copy.text("自定义语言", "Custom language"),
                selection: $preferences.customLanguage
            ) {
                Text("简体中文")
                    .tag(AppPreferences.Language.simplifiedChinese)
                Text("English")
                    .tag(AppPreferences.Language.english)
            }
            .disabled(preferences.followsSystemLanguage)

            Text(languageSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Label(
                copy.text("语言", "Language"),
                systemImage: "globe"
            )
        }
    }

    private var menuBarPreview: some View {
        HStack {
            Spacer()

            MenuBarStatusLabel(
                store: store,
                preferences: preferences
            )
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .codexGlass(
                cornerRadius: 8,
                tintOpacity: 0.1
            )

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func menuBarToggle(
        component: AppPreferences.MenuBarComponent,
        title: String,
        symbol: String
    ) -> some View {
        Toggle(
            isOn: preferences.binding(for: component)
        ) {
            Label(title, systemImage: symbol)
        }
        .disabled(
            preferences.isVisible(component)
            && !preferences.canHide(component)
        )
        .quotaViewSwitchStyle()
    }

    private func preferenceToggle(
        _ title: String,
        symbol: String,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            Label(title, systemImage: symbol)
        }
        .quotaViewSwitchStyle()
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
                    "深色模式使用清透单层玻璃，不额外叠加暗色洗层。",
                    "Dark mode uses a single clear glass layer without an extra dark wash."
                )
            }
            return copy.text(
                "浅色模式使用清透单层玻璃，不额外叠加乳白洗层。",
                "Light mode uses a single clear glass layer without an extra milky wash."
            )
        }
    }
}

struct MenuBarStatusLabel: View {
    @ObservedObject var store: CodexStatusStore
    @ObservedObject var preferences: AppPreferences

    private var copy: AppCopy { preferences.copy }

    var body: some View {
        MenuBarStatusContent(
            showsIcon: preferences.showStatusIcon,
            textParts: [
                preferences.showRemainingQuota
                    ? remainingLabel
                    : nil,
                preferences.showResetCountdown
                    ? countdownLabel
                    : nil
            ].compactMap { $0 },
            accessibilityText: accessibilityStatus
        )
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
        _ availability: CodexSnapshot.Availability
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

private struct MenuBarBrandIcon: View {
    private enum Metrics {
        static let glyphWidth: CGFloat = 15
        static let height: CGFloat = 16
        static let nativeTextGap: CGFloat = 3
        static let desiredTextGap: CGFloat = 8
        static let trailingGutter = desiredTextGap - nativeTextGap
        static let canvasWidth = glyphWidth + trailingGutter
    }

    private static let image: NSImage = {
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
        Image(nsImage: Self.image)
            .frame(
                width: Metrics.canvasWidth,
                height: Metrics.height
            )
    }
}
