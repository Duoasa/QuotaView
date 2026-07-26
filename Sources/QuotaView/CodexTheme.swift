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

enum QuotaViewGlassMode: String, CaseIterable, Identifiable {
    case frosted
    case clear

    var id: String { rawValue }
}

private struct QuotaViewGlassModeKey: EnvironmentKey {
    static let defaultValue = QuotaViewGlassMode.frosted
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
                // MenuBarExtra already owns the native glass surface. Keeping
                // the clear mode free of an additional wash lets that single
                // system layer sample the wallpaper without adding a second
                // rounded edge.
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

private struct CodexGlassModifier: ViewModifier {
    @Environment(\.quotaViewGlassMode) private var glassMode

    let cornerRadius: CGFloat
    let interactive: Bool
    let tintColor: Color?
    let tintOpacity: Double

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(
                    Glass.regular
                        .tint(
                            tintColor?.opacity(
                                tintOpacity
                                * (glassMode == .clear ? 0.6 : 1)
                            )
                        )
                        .interactive(interactive),
                    in: RoundedRectangle(
                        cornerRadius: cornerRadius,
                        style: .continuous
                    )
                )
                .shadow(
                    color: CodexTheme.accent.opacity(
                        (interactive ? 0.13 : 0.07)
                        * (glassMode == .clear ? 0.55 : 1)
                    ),
                    radius: (interactive ? 12 : 8)
                        * (glassMode == .clear ? 0.55 : 1),
                    y: 4
                )
        } else {
            content
                .background(
                    .regularMaterial,
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
                        (tintColor ?? CodexTheme.accent).opacity(
                            max(
                                tintOpacity
                                * (glassMode == .clear ? 0.6 : 1),
                                0.08
                            )
                        ),
                        lineWidth: 1
                    )
                }
        }
    }
}

extension View {
    func quotaViewMenuContentSurface() -> some View {
        modifier(QuotaViewMenuContentModifier())
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
