import AppKit
import QuotaViewCore
import SwiftUI

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
struct SettingsGlassAppearanceThumbnail: View {
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
struct SettingsIslandPreview: View {
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
                if preferences.cardShowsModel {
                    Text("6 Sol · High").font(.system(size: 10, weight: .semibold)).fixedSize()
                    if preferences.cardShowsDuration {
                        Rectangle().fill(Color(white: 61.0 / 255)).frame(width: 1, height: 9)
                    }
                }
                if preferences.cardShowsDuration {
                    Text("2m").font(.system(size: 10, weight: .semibold)).fixedSize()
                }
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
                if preferences.cardShowsOutputRate || preferences.cardShowsTokens {
                    HStack(spacing: 3) {
                        if preferences.cardShowsOutputRate {
                            Image(systemName: "hare.circle")
                            Text("34 tok/s")
                            if preferences.cardShowsTokens {
                                Rectangle().fill(Color(white: 0.24)).frame(width: 1, height: 9)
                            }
                        }
                        if preferences.cardShowsTokens { Text("128K tok") }
                    }.font(.system(size: 10, weight: .medium)).monospacedDigit().fixedSize()
                }
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

enum SettingsEffectPreviewMetrics {
    static let previewCornerRadius = IslandVibeLayout.rowRadius
    static let inset: CGFloat = 3
    static let outerCornerRadius = previewCornerRadius + inset
    static let height: CGFloat = 44
}

struct SettingsEffectOptionStyle: ButtonStyle {
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
