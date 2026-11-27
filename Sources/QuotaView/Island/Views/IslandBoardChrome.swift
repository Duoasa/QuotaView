import AppKit
import Combine
import SwiftUI
import QuotaViewCore

// Measured from the visible native Vibe Island reference, in logical points.
// Shared metrics keep row layout, hit regions and the fixed canvas consistent.
enum IslandVibeLayout {
    static let expandedWidth: CGFloat = 680
    static let compactWidth: CGFloat = 340
    static let compactContentGap: CGFloat = 16
    static let headerHeight: CGFloat = 36
    static let footerHeight: CGFloat = IslandChromeMetrics.footerHeight
    static let outerEffectInset = CodexActivityIslandProgressBarGeometry.effectInset
    static let screenBottomClearance = outerEffectInset
    static let rowHeight: CGFloat = contentInset * 2 + textRowHeight * 2 + lineGap
    static let subagentRowHeight: CGFloat = textRowHeight + contentInset
    static let rowSpacing: CGFloat = 8
    static let rowPitch: CGFloat = rowHeight + rowSpacing
    static let minimumDetailHeight: CGFloat = rowHeight
    static let maximumDetailViewportHeight: CGFloat = rowHeight * 2 + rowSpacing
    static let listInset: CGFloat = 28
    static let listVerticalInset: CGFloat = 12
    static let maximumNotchLip: CGFloat = 16
    static let scrollRailWidth: CGFloat = 14
    static let scrollThumbWidth: CGFloat = 6
    static let scrollRailGap: CGFloat = 8
    // Equal visible spacing on both sides of the thumb, inside the notch lip.
    static let scrollRailTrailingInset = maximumNotchLip + scrollRailGap - (scrollRailWidth - scrollThumbWidth) / 2
    static let scrollingListTrailingInset = maximumNotchLip + scrollRailGap * 2 + scrollThumbWidth
    static let rowRadius: CGFloat = 16
    static var rowShape: RoundedRectangle { RoundedRectangle(cornerRadius: rowRadius, style: .continuous) }
    static func continuousContour(in rect: CGRect, radius: CGFloat) -> CGPath {
        RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect).cgPath
    }
    static let iconSlot: CGFloat = 34
    static let orbDiameter: CGFloat = 28
    static let contentGap: CGFloat = 12
    static let contentInset: CGFloat = 10
    static let textRowHeight: CGFloat = 18
    static let lineGap: CGFloat = 6
    static let titleFont: CGFloat = 13
    static let operationFont: CGFloat = 11
    static let metadataFont: CGFloat = 10
    static let taskActionSize: CGFloat = 24
    static let taskActionIconSize: CGFloat = 16
    static let taskActionOpticalInset = (taskActionSize - taskActionIconSize) / 2
}

// One optical alignment and hit region for every expanded-page toolbar.
enum IslandChromeMetrics {
    static let horizontalInset: CGFloat = 28
    static let labelInset: CGFloat = 8
    static let buttonSize: CGFloat = 24
    static let fontSize: CGFloat = 12
    static let iconFont = Font.system(size: 11, weight: .semibold)
    static let quotaRingDiameter: CGFloat = 12
    static let quotaRingLineWidth: CGFloat = 2
    static let quotaRingLeadingInset = (buttonSize - quotaRingDiameter) / 2
    static let bottomInset: CGFloat = 12
    static let footerHeight = buttonSize + bottomInset
    static let font = Font.system(size: fontSize, weight: .medium)
    static let navigationFont = Font.system(size: fontSize, weight: .regular)
    static let providerIconDiameter: CGFloat = 16
    static let providerLeadingInset = (buttonSize - providerIconDiameter) / 2
    static let providerTrailingInset: CGFloat = 12
}

private struct IslandGlassActiveKey: EnvironmentKey {
    static let defaultValue = true
}
private struct IslandLiquidGlassEnabledKey: EnvironmentKey {
    static let defaultValue = true
}
private struct IslandGlassColorSchemeKey: EnvironmentKey {
    static let defaultValue = ColorScheme.dark
}
extension EnvironmentValues {
    var islandGlassColorScheme: ColorScheme {
        get { self[IslandGlassColorSchemeKey.self] }
        set { self[IslandGlassColorSchemeKey.self] = newValue }
    }
    var islandLiquidGlassEnabled: Bool {
        get { self[IslandLiquidGlassEnabledKey.self] }
        set { self[IslandLiquidGlassEnabledKey.self] = newValue }
    }
    var islandGlassActive: Bool {
        get { self[IslandGlassActiveKey.self] }
        set { self[IslandGlassActiveKey.self] = newValue }
    }
}

/// Follow the application's system appearance, independently of the dark settings
/// window. One public AppKit observation, with no polling or preference writes.
@MainActor
final class IslandSystemAppearance: ObservableObject {
    static let shared = IslandSystemAppearance()
    @Published private(set) var colorScheme: ColorScheme
    private var observation: NSKeyValueObservation?

    private init() {
        colorScheme = NSApplication.shared.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
        observation = NSApplication.shared.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                let scheme: ColorScheme = NSApplication.shared.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
                if self?.colorScheme != scheme { self?.colorScheme = scheme }
            }
        }
    }
}

struct IslandGlassAppearanceContext: ViewModifier {
    var appearance: AppPreferences.IslandGlassAppearance
    var material: AppPreferences.IslandMaterial
    @ObservedObject private var system = IslandSystemAppearance.shared
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        content.environment(\.islandGlassColorScheme,
            appearance.colorScheme(system: system.colorScheme, material: material, reduceTransparency: reduceTransparency))
    }
}

/// Apply only to exposed glass chrome. The black gradient and cards stay dark.
struct IslandGlassColorScheme: ViewModifier {
    @Environment(\.islandGlassColorScheme) private var scheme
    func body(content: Content) -> some View { content.environment(\.colorScheme, scheme) }
}

/// Explicit foreground for nonactivating panels; the scoped appearance is still
/// resolved from the system, but foreground brightness never depends on focus.
struct IslandGlassForeground: ViewModifier {
    @Environment(\.islandGlassColorScheme) private var scheme
    func body(content: Content) -> some View {
        content.foregroundStyle((scheme == .light ? Color.black : .white).opacity(0.86))
    }
}

// Shared native material: static styling, system batching, no per-frame work.
// Applied to cards and controls; chart cells and task archive icons stay plain.
struct IslandGlassSurface<Outline: InsettableShape>: ViewModifier {
    let outline: Outline
    var tint: Color = .black.opacity(0.28)
    var solidTint: Color = Color(white: 0.14)
    var clearSurface = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.islandGlassActive) private var active
    @Environment(\.islandLiquidGlassEnabled) private var liquidGlassEnabled
    @Environment(\.self) private var environment
    private var usesSolidFill: Bool { reduceTransparency || !liquidGlassEnabled }
    private var separatesDarkTint: Bool {
        guard #available(macOS 27.0, *) else { return false }
        let color = tint.resolve(in: environment)
        // macOS 27 composites near-black native tints as an opaque-looking
        // material. Keep light controls and semantic accent tints unchanged.
        return color.opacity > 0 && max(color.red, color.green, color.blue) <= 0.2
    }
    @available(macOS 26.0, *)
    private var material: Glass {
        guard active && !usesSolidFill else { return .identity }
        let glass: Glass = clearSurface ? .clear : .regular
        // Clear glass avoids regular's pale backing under our separate dark
        // fill. The fill supplies the charcoal tone and limited backdrop color.
        return separatesDarkTint ? .clear : glass.tint(tint)
    }
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            // Keep the content/anchor identity when a page becomes hidden.
            // Identity disables the material without replacing the card subtree.
            content
                .background {
                    if active && !usesSolidFill && separatesDarkTint {
                        // Retain the original fill strength, independently of
                        // native tint compositing, without dimming text/icons.
                        outline.fill(tint).allowsHitTesting(false)
                    }
                }
                .glassEffect(material, in: outline)
                .background {
                    if active && usesSolidFill { outline.fill(solidTint) }
                }
                .overlay {
                    if active && usesSolidFill {
                        outline.strokeBorder(.white.opacity(reduceTransparency ? 0.30 : 0.12), lineWidth: 0.5).allowsHitTesting(false)
                    }
                }
        } else {
            content.background {
                if active {
                    if usesSolidFill { outline.fill(solidTint) }
                    else if clearSurface { outline.fill(.ultraThinMaterial) }
                    else { outline.fill(.regularMaterial).overlay(outline.fill(solidTint.opacity(0.85))) }
                }
            }
            .overlay {
                if active {
                    outline.strokeBorder(.white.opacity(reduceTransparency ? 0.30 : 0.24), lineWidth: 0.5)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}

extension View {
    func islandGlass<Outline: InsettableShape>(_ outline: Outline, tint: Color = .black.opacity(0.28), solidTint: Color = Color(white: 0.14), clearSurface: Bool = false) -> some View {
        modifier(IslandGlassSurface(outline: outline, tint: tint, solidTint: solidTint, clearSurface: clearSurface))
    }
}

// Center fitting titles on the island, but let overflowing titles use the
// actual space between the Orb and statistics instead of a hidden side copy.
struct IslandCompactContentLayout: Layout {
    var gap: CGFloat = IslandVibeLayout.compactContentGap
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return CGSize(width: max(0, proposal.width ?? sizes.reduce(0) { $0 + $1.width } + gap * 2),
            height: max(0, proposal.height ?? sizes.map(\.height).max() ?? 0))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let orb = subviews[0].sizeThatFits(.unspecified)
        let title = subviews[1].sizeThatFits(.unspecified)
        let statistics = subviews[2].sizeThatFits(.unspecified)
        let leading = bounds.minX + orb.width + gap
        let trailing = bounds.maxX - statistics.width - gap
        let titleWidth = min(title.width, max(0, trailing - leading))
        let center = titleWidth > 0
            ? min(max(bounds.midX, leading + titleWidth / 2), trailing - titleWidth / 2)
            : min(leading, bounds.maxX)
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading,
            proposal: .init(width: orb.width, height: orb.height))
        subviews[1].place(at: CGPoint(x: center, y: bounds.midY), anchor: .center,
            proposal: .init(width: titleWidth, height: bounds.height))
        subviews[2].place(at: CGPoint(x: bounds.maxX, y: bounds.midY), anchor: .trailing,
            proposal: .init(width: statistics.width, height: statistics.height))
    }
}

struct IslandChromeFooter<Leading: View, Trailing: View>: View {
    @Environment(\.islandGlassColorScheme) private var scheme
    let leading: Leading
    let trailing: Trailing
    init(@ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.leading = leading(); self.trailing = trailing()
    }
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            leading.padding(.leading, IslandChromeMetrics.labelInset)
            Spacer(minLength: 8)
            trailing
        }.font(IslandChromeMetrics.font)
            .foregroundStyle((scheme == .light ? Color.black : .white).opacity(0.86))
            .frame(height: IslandChromeMetrics.buttonSize)
            .padding(.horizontal, IslandChromeMetrics.horizontalInset)
            .padding(.bottom, IslandChromeMetrics.bottomInset)
            .modifier(IslandGlassColorScheme())
    }
}

// Keep the toolbar reachable when restored cards exceed the display height.
struct IslandPageLayout<Content: View, Footer: View>: View {
    let maximumHeight: CGFloat?
    let onHeightChange: (CGFloat) -> Void
    let content: Content
    let footer: Footer
    @State private var contentHeight: CGFloat = 400
    init(maximumHeight: CGFloat?, onHeightChange: @escaping (CGFloat) -> Void,
         @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.maximumHeight = maximumHeight; self.onHeightChange = onHeightChange
        self.content = content(); self.footer = footer()
    }
    private var measuredContent: some View {
        content.fixedSize(horizontal: false, vertical: true)
            .background { GeometryReader { proxy in
                Color.clear.preference(key: IslandPageContentHeightKey.self, value: proxy.size.height)
            } }
            .onPreferenceChange(IslandPageContentHeightKey.self) {
                if $0.isFinite && $0 > 0 { contentHeight = ceil($0) }
            }
    }
    var body: some View {
        VStack(spacing: 10) {
            if let maximumHeight {
                ScrollView(.vertical) { measuredContent }
                    .scrollIndicators(.automatic)
                    .frame(height: min(contentHeight, max(0, maximumHeight - IslandChromeMetrics.footerHeight - 10)))
            } else { measuredContent }
            footer
        }.fixedSize(horizontal: false, vertical: true)
            .background { GeometryReader { proxy in
                Color.clear.preference(key: IslandPageHeightKey.self, value: proxy.size.height)
            } }
            .onPreferenceChange(IslandPageHeightKey.self, perform: onHeightChange)
    }
}
private struct IslandPageContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
private struct IslandPageHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

@MainActor
enum IslandProviderIcon {
    private static var bundle: Bundle {
        #if SWIFT_PACKAGE
        Bundle.module
        #else
        Bundle.main
        #endif
    }
    static let image = bundle.url(forResource: "CodexProviderIcon", withExtension: "png").flatMap { NSImage(contentsOf: $0) }
    static let codexMark = bundle.image(forResource: NSImage.Name("CodexProviderMark"))
    static let claudeImage = bundle.image(forResource: NSImage.Name("ClaudeProviderIcon"))
    static let claudeApplicationIcon = bundle.image(forResource: NSImage.Name("ClaudeApplicationIcon"))
    private static let dshBrandMark = bundle.image(forResource: NSImage.Name("DSHProviderMark"))
    private static let kimiApplicationIcon = bundle.image(forResource: NSImage.Name("KimiCodeProviderIcon"))
    private static let antigravityIcon = bundle.image(forResource: NSImage.Name("AntigravityApplicationIcon"))
    static func settingsMark(for provider: IslandAgentProvider) -> NSImage? {
        switch provider {
        case .codex: image
        case .claudeCode: claudeApplicationIcon
        case .dsh: dshBrandMark
        case .kimiCode: kimiApplicationIcon
        case .cursor: bundle.image(forResource: NSImage.Name("CursorProviderMark"))
        case .geminiCLI: bundle.image(forResource: NSImage.Name("GeminiCLIProviderMark"))
        case .antigravity: antigravityIcon
        case .openCode: bundle.image(forResource: NSImage.Name("OpenCodeProviderMark"))
        case .copilotCLI: bundle.image(forResource: NSImage.Name("CopilotCLIProviderMark"))
        case .devinDesktop, .devinCLI: bundle.image(forResource: NSImage.Name("DevinProviderMark"))
        }
    }
    static let dshImage = NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: "DSH")
    static let kimiImage = NSImage(systemSymbolName: "k.circle.fill", accessibilityDescription: "Kimi Code")
    static func image(for provider: IslandAgentProvider) -> NSImage? {
        switch provider { case .codex: image; case .claudeCode: claudeApplicationIcon; case .dsh: dshImage; case .kimiCode: kimiImage
        case .cursor, .geminiCLI, .openCode, .antigravity, .copilotCLI, .devinDesktop, .devinCLI: settingsMark(for: provider)
        }
    }
    static func usageMark(for provider: IslandAgentProvider) -> NSImage? {
        provider == .codex ? codexMark : claudeImage
    }
}

enum IslandBoardStyle {
    static let secondary = Color(nsColor: IslandTextPalette.secondary)
    static let muted = Color(nsColor: IslandTextPalette.muted)
    static let attention = Color(nsColor: CodexActivityIslandConfirmationReminderContract.approvalColor)
    static let confirmationHighlight = attention
    static let failure = Color(nsColor: .init(srgbRed: 0.95, green: 0.43, blue: 0.42, alpha: 1))
    static func statusColor(_ state: CodexActivityVisualState) -> Color {
        // Color marks a need for attention; ordinary state names use the text hierarchy.
        switch state {
        case .awaitingConfirmation: attention
        case .error: failure
        case .completed: Color(red: 0.36, green: 0.80, blue: 0.55)
        case .unavailable, .disconnectedCodex, .standby: muted
        case .thinking, .working, .compactingContext: Color(white: 0.92)
        }
    }
    static func attentionColor(for tasks: [CodexMultitaskRenderTask]) -> Color {
        if tasks.contains(where: { $0.renderState.visualState == .error }) { return failure }
        if tasks.contains(where: { $0.renderState.visualState == .awaitingConfirmation }) { return attention }
        return secondary
    }
    static func quotaColor(for percent: Int?) -> Color {
        switch CodexActivityQuotaRingContract.riskBand(for: percent) {
        case .healthy: secondary
        case .warning: attention
        case .critical: failure
        case .unavailable: muted
        }
    }
    static func icon(_ state: CodexActivityVisualState) -> String {
        switch state {
        case .completed: "checkmark"
        case .awaitingConfirmation: "hand.raised.fill"
        case .error: "exclamationmark"
        case .unavailable: "questionmark"
        case .compactingContext: "arrow.triangle.2.circlepath"
        default: "sparkle"
        }
    }
}

struct IslandQuotaRing: View {
    let remainingPercent: Int?
    var body: some View {
        let fraction = CGFloat(min(100, max(0, remainingPercent ?? 0))) / 100
        let color = Color(nsColor: CodexActivityQuotaRingContract.color(for: remainingPercent))
        ZStack {
            Circle().stroke(Color(white: 0.18), lineWidth: IslandChromeMetrics.quotaRingLineWidth)
            Circle().trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: IslandChromeMetrics.quotaRingLineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }.padding(IslandChromeMetrics.quotaRingLineWidth / 2)
            .frame(width: IslandChromeMetrics.quotaRingDiameter, height: IslandChromeMetrics.quotaRingDiameter).accessibilityHidden(true)
    }
}

// Shared footer actions avoid the camera safe area and retain one order on every page.
struct IslandUtilityActions: View {
    @ObservedObject var state: IslandBoardState
    @Environment(\.colorScheme) private var scheme
    private var ink: Color { scheme == .light ? .black : .white }
    var body: some View {
        HStack(spacing: 8) {
            Button {
                Task { await state.refreshUsage() }
            } label: {
                Group {
                    if state.isRefreshingUsage { ProgressView().controlSize(.mini).tint(ink) }
                    else { Image(systemName: "arrow.clockwise").font(IslandChromeMetrics.iconFont) }
                }.frame(width: IslandChromeMetrics.buttonSize, height: IslandChromeMetrics.buttonSize).contentShape(Rectangle())
            }
            .disabled(state.isRefreshingUsage || state.onRefreshUsage == nil)
            .accessibilityLabel(state.isRefreshingUsage ? state.text("刷新中", "Refreshing") : state.text("刷新用量", "Refresh usage"))
            .help(state.text("刷新用量", "Refresh usage"))
            Button { state.onOpenSettings?() } label: {
                Image(systemName: "gearshape").font(IslandChromeMetrics.iconFont).frame(width: IslandChromeMetrics.buttonSize, height: IslandChromeMetrics.buttonSize).contentShape(Rectangle())
            }
            .disabled(state.onOpenSettings == nil)
            .accessibilityLabel(state.text("设置", "Settings"))
            .help(state.text("打开 QuotaView 设置", "Open QuotaView settings"))
        }
        .font(IslandChromeMetrics.font).foregroundStyle(ink)
        .buttonStyle(IslandUtilityButtonStyle(clearSurface: true))
        .fixedSize(horizontal: true, vertical: false)
    }
}
struct IslandUtilityButtonStyle: ButtonStyle {
    var clearSurface = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Capsule())
            // Explicit contrast avoids inactive nonactivating-panel label dimming.
            // The black header inherits dark; only exposed chrome inherits light.
            .foregroundStyle(colorScheme == .light ? Color.black : .white)
            .islandGlass(Capsule(), tint: clearSurface ? .white.opacity(colorScheme == .light ? 0.22 : 0.04) : .black.opacity(0.28),
                         clearSurface: clearSurface)
            .brightness(configuration.isPressed ? -0.08 : hovered ? 0.05 : 0)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
            .onHover { hovered = isEnabled && $0 }
            .onChange(of: isEnabled) { _, enabled in if !enabled { hovered = false } }
            .onDisappear { hovered = false }
    }
}
