import AppKit
import QuotaViewCore
import SwiftUI

extension SettingsView {
    // This illustration responds only to preferences, never live tasks or timers.
    var islandStageVisual: some View {
        let geometry = activityRuntime.liveIsland.board.state.geometry
        return SettingsIslandPreview(preferences: preferences,
            expandedWidth: geometry.expandedWidth(preferred: preferences.codexIslandExpandedWidth),
            maximumExpandedWidth: geometry.maximumExpandedWidth)
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
    var islandSettings: some View {
        VStack(alignment: .leading, spacing: SettingsLayoutMetrics.sectionSpacing) {
            islandMaterialSettings
            settingsSection(copy.text("布局与显示", "Layout and display")) {
                NativeSettingsCard {
                    islandWidthSettings
                    NativeSettingsDivider()
                    preferenceToggle(copy.text("悬浮用量胶囊", "Floating usage capsule"),
                        symbol: "chart.pie.fill",
                        isOn: $preferences.islandFloatingUsageEnabled)
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
                NativeSettingsDivider()
                islandMaterialOption(.classic,
                    title: copy.text("经典纯色", "Classic solid"),
                    subtitle: copy.text("关闭背景、卡片与按钮的玻璃材质。遇到卡顿时可切换至此。", "Turn off glass on the background, cards and buttons. Choose this if glass feels slow."),
                    symbol: "rectangle.fill")
                if preferences.islandMaterial == .liquidGlass {
                    NativeSettingsDivider()
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
                NativeSettingsDivider()
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
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
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
}
