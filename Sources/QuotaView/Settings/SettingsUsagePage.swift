import AppKit
import QuotaViewCore
import SwiftUI

extension SettingsView {
    var usageSettings: some View {
        VStack(alignment: .leading, spacing: SettingsLayoutMetrics.sectionSpacing) {
            settingsSection(copy.text("可选模块", "Optional modules")) {
                NativeSettingsCard {
                    preferenceToggle(copy.text("近 30 天成本估算", "30-day cost estimate"),
                        symbol: "dollarsign.circle.fill",
                        isOn: $preferences.showEstimatedCost)
                    NativeSettingsDivider()
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
}
