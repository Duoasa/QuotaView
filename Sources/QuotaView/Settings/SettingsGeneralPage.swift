import AppKit
import QuotaViewCore
import SwiftUI

extension SettingsView {
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
    private var appearanceAndLanguageSettings: some View {
        NativeSettingsCard {
            SettingsChoiceRow(title: copy.text("外观", "Appearance"), symbol: "circle.lefthalf.filled") {
                ForEach(AppPreferences.IslandGlassAppearance.allCases) { appearance in
                    glassAppearanceOption(appearance)
                }
            }
            NativeSettingsDivider()
            NativeSettingsRow(title: copy.text("语言", "Language"),
                symbol: "globe") {
                SettingsValueMenu(title: copy.text("语言", "Language"), selection: languageSelection,
                    options: [("system", systemLanguageOption)] + AppPreferences.Language.allCases.map { ($0.rawValue, $0.nativeName) })
            }
        }
    }

    private func screenOptions(for availableScreens: [NSScreen]) -> [(String, String)] {
        var options = [("", copy.text("主屏幕", "Main display"))]
        options += availableScreens.enumerated().map { index, screen in
            (IslandScreenSelection.identifier(screen), "\(index + 1) · \(screen.localizedName)")
        }
        if !options.contains(where: { $0.0 == preferences.islandFixedScreenID }) {
            options.append((preferences.islandFixedScreenID, copy.text("所选屏幕未连接", "Selected display disconnected")))
        }
        return options
    }

    func generalSettings(availableScreens: [NSScreen]) -> some View {
        VStack(alignment: .leading, spacing: SettingsLayoutMetrics.sectionSpacing) {
            appearanceAndLanguageSettings
            settingsSection(copy.text("灵动岛显示位置", "Island display")) {
                NativeSettingsCard { islandScreenSettings(for: availableScreens) }
                if availableScreens.count < 2 {
                    NativeSettingsNote(text: copy.text("连接多台显示器后，屏幕跟随会自动生效。", "Display following takes effect when multiple displays are connected."))
                }
            }
            settingsSection(copy.text("交互与隐私", "Behavior and privacy")) {
                NativeSettingsCard {
                    preferenceToggle(copy.text("自动弹出", "Automatic popups"),
                        subtitle: copy.text("新任务、完成或待确认时弹出。", "Open for new tasks, completions and requests."),
                        symbol: "macwindow.badge.plus",
                        isOn: $preferences.codexActivityAutomaticPopupEnabled)
                    NativeSettingsDivider()
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
                    NativeSettingsDivider()
                    preferenceToggle(copy.text("隐私模式", "Privacy mode"),
                        subtitle: copy.text("隐藏任务内容和账户数据。", "Hide task contents and account data."),
                        symbol: "eye.slash.fill",
                        isOn: $preferences.codexIslandPrivacy)
                }
            }
        }
    }

    private func islandScreenSettings(for availableScreens: [NSScreen]) -> some View {
        Group {
            NativeSettingsRow(title: copy.text("跟随活动窗口", "Follow active window"),
                symbol: "display.2") {
                Toggle("", isOn: $preferences.islandFollowsFocus).labelsHidden()
                    .toggleStyle(.switch).controlSize(.mini)
                    .accessibilityLabel(copy.text("焦点屏幕跟随", "Follow focused display"))
            }
            NativeSettingsDivider()
            NativeSettingsRow(title: copy.text("跟随鼠标所在屏幕", "Follow pointer display"),
                symbol: "cursorarrow.motionlines") {
                Toggle("", isOn: $preferences.islandFollowsPointer).labelsHidden()
                    .toggleStyle(.switch).controlSize(.mini)
                    .accessibilityLabel(copy.text("跟随鼠标所在屏幕", "Follow pointer display"))
            }
            if !preferences.islandFollowsFocus && !preferences.islandFollowsPointer {
                NativeSettingsDivider()
                NativeSettingsRow(title: copy.text("固定屏幕", "Fixed display"),
                    subtitle: copy.text("断开时暂回主屏，重新连接后恢复。", "Falls back to the main display until reconnected."),
                    symbol: "display") {
                    SettingsValueMenu(title: copy.text("固定屏幕", "Fixed display"),
                        selection: $preferences.islandFixedScreenID, options: screenOptions(for: availableScreens))
                }
            }
        }
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
}
