import AppKit
import QuotaViewCore
import SwiftUI

extension SettingsView {
    var cardSettings: some View {
        NativeSettingsCard {
            preferenceToggle(copy.text("速率", "Output rate"), symbol: "speedometer", isOn: $preferences.cardShowsOutputRate)
            NativeSettingsDivider()
            preferenceToggle(copy.text("任务 Token", "Task tokens"), symbol: "number", isOn: $preferences.cardShowsTokens)
            NativeSettingsDivider()
            preferenceToggle(copy.text("任务耗时", "Task duration"), symbol: "timer", isOn: $preferences.cardShowsDuration)
            NativeSettingsDivider()
            preferenceToggle(copy.text("模型显示", "Model display"), symbol: "cpu", isOn: $preferences.cardShowsModel)
        }
    }
}
