import AppKit
import SwiftUI

enum CodexTheme {
    // This palette is sampled from the current official Codex app icon.
    // QuotaView remains a separate product and does not reuse OpenAI marks.
    static let accent = Color(
        red: 79.0 / 255.0,
        green: 106.0 / 255.0,
        blue: 244.0 / 255.0
    )
    static let accentHighlight = Color(
        red: 176.0 / 255.0,
        green: 166.0 / 255.0,
        blue: 255.0 / 255.0
    )
    static let accentDeep = Color(
        red: 52.0 / 255.0,
        green: 43.0 / 255.0,
        blue: 255.0 / 255.0
    )

    static let accentGradient = LinearGradient(
        colors: [accentHighlight, accent, accentDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

}

enum QuotaViewTypography {
    // Keep the status-panel type scale independent of the glass material so
    // clear and frosted modes always present the same information hierarchy.
    static let menuTitle = AstaSans.semiBold(16)
    static let menuSubtitle = AstaSans.medium(12.5)
    static let navigationTitle = AstaSans.semiBold(15)
    static let status = AstaSans.semiBold(12.5)
    static let sectionLabel = AstaSans.semiBold(13)
    static let body = AstaSans.medium(13.5)
    static let bodyStrong = AstaSans.semiBold(13.5)
    static let small = AstaSans.medium(12.5)
    static let smallStrong = AstaSans.semiBold(12.5)
    static let tiny = AstaSans.medium(11.5)
    static let heroValue = AstaSans.semiBold(34)
    static let ringValue = AstaSans.semiBold(20)
    static let toolbar = AstaSans.medium(13)
    static let primaryAction = AstaSans.semiBold(14)
}

enum QuotaViewGlassMode: String, CaseIterable, Identifiable {
    case frosted
    case clear

    var id: String { rawValue }
}

private struct QuotaViewGlassModeKey: EnvironmentKey {
    static let defaultValue = QuotaViewGlassMode.clear
}

extension EnvironmentValues {
    var quotaViewGlassMode: QuotaViewGlassMode {
        get { self[QuotaViewGlassModeKey.self] }
        set { self[QuotaViewGlassModeKey.self] = newValue }
    }
}

struct QuotaViewAmbientBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [
                    CodexTheme.accentHighlight.opacity(
                        colorScheme == .dark ? 0.18 : 0.12
                    ),
                    .clear
                ],
                center: .topLeading,
                startRadius: 0,
                endRadius: 310
            )

            RadialGradient(
                colors: [
                    CodexTheme.accent.opacity(
                        colorScheme == .dark ? 0.14 : 0.09
                    ),
                    .clear
                ],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 280
            )

            LinearGradient(
                colors: [
                    Color.primary.opacity(
                        colorScheme == .dark ? 0.035 : 0.02
                    ),
                    .clear,
                    CodexTheme.accentDeep.opacity(
                        colorScheme == .dark ? 0.05 : 0.025
                    )
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct QuotaViewMenuContentBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.quotaViewGlassMode) private var glassMode

    @ViewBuilder
    var body: some View {
        Group {
            if glassMode == .frosted {
                ZStack {
                    (colorScheme == .dark ? Color.black : Color.white)
                        .opacity(colorScheme == .dark ? 0.22 : 0.24)

                    RadialGradient(
                        colors: [
                            CodexTheme.accentHighlight.opacity(0.025),
                            .clear
                        ],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 300
                    )

                    RadialGradient(
                        colors: [
                            CodexTheme.accent.opacity(0.018),
                            .clear
                        ],
                        center: .bottomTrailing,
                        startRadius: 0,
                        endRadius: 280
                    )

                    LinearGradient(
                        colors: [
                            Color.white.opacity(
                                colorScheme == .dark ? 0.025 : 0.04
                            ),
                            .clear,
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            } else {
                // The AppKit panel already owns the clear glass surface.
                // Keeping this layer transparent leaves the sampled
                // background unobstructed.
                Color.clear
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct QuotaViewMenuContentModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background {
            QuotaViewMenuContentBackground()
        }
    }
}

private enum QuotaViewReadabilityRole {
    case primary
    case secondary
    case tertiary

    var semanticColor: Color {
        switch self {
        case .primary:
            .primary
        case .secondary:
            .secondary
        case .tertiary:
            Color(nsColor: .tertiaryLabelColor)
        }
    }
}

private struct QuotaViewReadableForegroundModifier: ViewModifier {
    let role: QuotaViewReadabilityRole

    func body(content: Content) -> some View {
        // System label colors participate in macOS vibrancy and respond to
        // appearance and accessibility contrast settings. Avoid replacing
        // them with fixed black/white values or hand-authored halos.
        content.foregroundStyle(role.semanticColor)
    }
}

private struct QuotaViewColoredForegroundModifier: ViewModifier {
    let color: Color

    func body(content: Content) -> some View {
        content.foregroundStyle(color)
    }
}

private struct QuotaViewSeparatorModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.overlay(Color(nsColor: .separatorColor))
    }
}

enum QuotaViewButtonInteractionKind: Equatable {
    case compact
    case regular

    var cornerRadius: CGFloat {
        12
    }

    var isCompact: Bool {
        self == .compact
    }
}

private struct QuotaViewInteractiveButtonStyle: ButtonStyle {
    let kind: QuotaViewButtonInteractionKind

    func makeBody(configuration: Configuration) -> some View {
        QuotaViewInteractiveButtonBody(
            label: configuration.label,
            isPressed: configuration.isPressed,
            kind: kind
        )
    }
}

private struct QuotaViewInteractiveButtonBody<Label: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    let label: Label
    let isPressed: Bool
    let kind: QuotaViewButtonInteractionKind

    @State private var isHovering = false

    var body: some View {
        label
            .background(
                interactionOverlayColor,
                in: RoundedRectangle(
                    cornerRadius: kind.cornerRadius,
                    style: .continuous
                )
            )
            .scaleEffect(scale)
            .opacity(isEnabled ? 1 : 0.55)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.14),
                value: isHovering
            )
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.08),
                value: isPressed
            )
            .onHover { hovering in
                isHovering = isEnabled && hovering
            }
            .onChange(of: isEnabled) {
                if !isEnabled {
                    isHovering = false
                }
            }
    }

    private var scale: CGFloat {
        guard !reduceMotion, isEnabled else { return 1 }

        if isPressed {
            return kind.isCompact ? 0.94 : 0.985
        }
        if isHovering, kind.isCompact {
            return 1.04
        }
        return 1
    }

    private var interactionOverlayColor: Color {
        guard isEnabled else { return .clear }

        if isPressed {
            return Color.black.opacity(
                colorScheme == .light ? 0.10 : 0.18
            )
        }
        if isHovering {
            return Color.white.opacity(
                colorScheme == .light ? 0.16 : 0.10
            )
        }
        return .clear
    }
}

private struct CodexGlassModifier: ViewModifier {
    @Environment(\.quotaViewGlassMode) private var glassMode

    let cornerRadius: CGFloat
    let interactive: Bool
    let tintColor: Color?
    let tintOpacity: Double

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            let glass = glassMode == .clear
                ? Glass.clear.interactive(interactive)
                : Glass.regular
                    .tint(tintColor?.opacity(tintOpacity))
                    .interactive(interactive)

            content
                .glassEffect(
                    glass,
                    in: RoundedRectangle(
                        cornerRadius: cornerRadius,
                        style: .continuous
                    )
                )
        } else {
            let material: Material = glassMode == .clear
                ? .thinMaterial
                : .regularMaterial

            content
                .background(
                    material,
                    in: RoundedRectangle(
                        cornerRadius: cornerRadius,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: cornerRadius,
                        style: .continuous
                    )
                    .stroke(
                        (
                            glassMode == .clear
                                ? Color.primary.opacity(0.10)
                                : (tintColor ?? CodexTheme.accent)
                                    .opacity(max(tintOpacity, 0.08))
                        ),
                        lineWidth: 1
                    )
                }
        }
    }
}

extension View {
    func quotaViewInteractiveButton(
        _ kind: QuotaViewButtonInteractionKind = .regular
    ) -> some View {
        buttonStyle(
            QuotaViewInteractiveButtonStyle(kind: kind)
        )
    }

    func quotaViewMenuContentSurface() -> some View {
        modifier(QuotaViewMenuContentModifier())
    }

    func quotaViewPrimaryText() -> some View {
        modifier(
            QuotaViewReadableForegroundModifier(role: .primary)
        )
    }

    func quotaViewSecondaryText() -> some View {
        modifier(
            QuotaViewReadableForegroundModifier(role: .secondary)
        )
    }

    func quotaViewTertiaryText() -> some View {
        modifier(
            QuotaViewReadableForegroundModifier(role: .tertiary)
        )
    }

    func quotaViewColoredForeground(_ color: Color) -> some View {
        modifier(QuotaViewColoredForegroundModifier(color: color))
    }

    func quotaViewSeparator() -> some View {
        modifier(QuotaViewSeparatorModifier())
    }

    func codexGlass(
        cornerRadius: CGFloat,
        interactive: Bool = false,
        tintColor: Color? = CodexTheme.accent,
        tintOpacity: Double = 0.14
    ) -> some View {
        modifier(
            CodexGlassModifier(
                cornerRadius: cornerRadius,
                interactive: interactive,
                tintColor: tintColor,
                tintOpacity: tintOpacity
            )
        )
    }

    @ViewBuilder
    func codexProminentButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            self
                .buttonStyle(.glassProminent)
                .tint(CodexTheme.accent)
        } else {
            self
                .buttonStyle(.borderedProminent)
                .tint(CodexTheme.accent)
        }
    }

    @ViewBuilder
    func codexToolbarButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.borderless)
        }
    }

    func quotaViewSwitchStyle() -> some View {
        // Standard switches automatically adopt Apple's Liquid Glass design
        // when the app is built with Xcode 26 and runs on macOS 26.
        self
            .toggleStyle(.switch)
            .tint(CodexTheme.accent)
    }

    @ViewBuilder
    func quotaViewGlassContainer(spacing: CGFloat = 12) -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                self
            }
        } else {
            self
        }
    }

    @ViewBuilder
    func quotaViewWindowSurface() -> some View {
        if #available(macOS 26.0, *) {
            self.background {
                QuotaViewAmbientBackground()
                    .ignoresSafeArea()
            }
        } else {
            self
                .background(.regularMaterial)
                .background {
                    QuotaViewAmbientBackground()
                        .ignoresSafeArea()
                }
        }
    }
}
