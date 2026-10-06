import AppKit
import Combine
import SwiftUI

enum MenuBarPanelGeometry {
    static func anchoredFrame(
        size: NSSize,
        centerX: CGFloat,
        visibleFrame: NSRect,
        screenEdgeInset: CGFloat,
        menuBarGap: CGFloat
    ) -> NSRect {
        var x = centerX - size.width / 2
        x = max(
            visibleFrame.minX + screenEdgeInset,
            min(
                x,
                visibleFrame.maxX - size.width - screenEdgeInset
            )
        )

        let y = visibleFrame.maxY - size.height - menuBarGap
        return NSRect(
            x: x.rounded(),
            y: y.rounded(),
            width: size.width,
            height: size.height
        )
    }
}

private struct MenuBarPanelRoot: View {
    @ObservedObject var store: CodexStatusStore
    @ObservedObject var preferences: AppPreferences

    let openSettingsAction: () -> Void
    let contentLayoutDidChange: () -> Void
    let prepareContentExpansion: (CGFloat) -> Void
    let confirmationPresentationDidChange: (Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            MenuBarView(
                store: store,
                preferences: preferences,
                openSettingsAction: openSettingsAction,
                contentLayoutDidChange: contentLayoutDidChange,
                prepareContentExpansion: prepareContentExpansion,
                confirmationPresentationDidChange:
                    confirmationPresentationDidChange
            )

            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .environment(\.locale, preferences.locale)
        .environment(\.quotaViewGlassMode, preferences.glassMode)
    }
}

private final class QuotaViewMenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@available(macOS 26.0, *)
private final class QuotaViewLiquidGlassSurface: NSView {
    let mode: QuotaViewGlassMode

    private let glassView = NSGlassEffectView()
    private let compositionView: QuotaViewGlassCompositionView
    private let dropShadowView: QuotaViewFigmaDropShadowView?

    var panelInsets: NSEdgeInsets {
        mode == .clear
            ? FigmaClearGlassSpec.windowInsets
            : NSEdgeInsets()
    }

    var contentView: NSView? {
        get { compositionView.hostedContentView }
        set { compositionView.replaceHostedContentView(with: newValue) }
    }

    func setHostedContentHeight(_ height: CGFloat) {
        compositionView.setHostedContentHeight(height)
    }

    init(
        contentView: NSView,
        mode: QuotaViewGlassMode
    ) {
        self.mode = mode
        compositionView = QuotaViewGlassCompositionView(
            contentView: contentView,
            usesFigmaChrome: mode == .clear
        )
        dropShadowView = mode == .clear
            ? QuotaViewFigmaDropShadowView()
            : nil
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        glassView.cornerRadius = FigmaClearGlassSpec.cornerRadius
        glassView.style = mode == .clear ? .clear : .regular
        // Figma's appearance-specific neutral fill is rendered by the
        // composition layer. A transparent native tint keeps the
        // WindowServer backdrop free of product/theme color while retaining
        // live refraction.
        glassView.tintColor = mode == .clear ? .clear : nil
        glassView.contentView = compositionView
        glassView.wantsLayer = true
        glassView.layer?.cornerRadius = glassView.cornerRadius
        glassView.layer?.cornerCurve = .continuous
        glassView.layer?.masksToBounds = true
        if let dropShadowView {
            addSubview(dropShadowView)
        }
        addSubview(glassView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()

        let insets = panelInsets
        glassView.frame = NSRect(
            x: insets.left,
            y: insets.bottom,
            width: max(0, bounds.width - insets.left - insets.right),
            height: max(0, bounds.height - insets.top - insets.bottom)
        )
        dropShadowView?.frame = bounds
        dropShadowView?.glassFrame = glassView.frame
    }
}

private enum FigmaClearGlassSpec {
    // QuotaView Page UI node 1:712 is the production overview size:
    // 274 × 433 pt. Its values map one-to-one to AppKit points.
    static let cornerRadius: CGFloat = 21
    static let darkFillOpacity: CGFloat = 0.20
    static let lightFillOpacity: CGFloat = 0.26
    static let systemBackdropOpacity: CGFloat = 0.60

    static let innerShadowOpacity: CGFloat = 0.12
    static let innerShadowRadius: CGFloat = 30
    static let innerShadowOffsets = [
        NSSize(width: 6, height: 3),
        NSSize(width: -3.75, height: -3)
    ]

    static let dropShadowOpacity: CGFloat = 0.20
    static let dropShadowRadius: CGFloat = 15
    static let dropShadowOffset = NSSize(
        width: 0,
        height: 18
    )

    // Transparent room for the Figma drop shadow. The shadow remains inside
    // the clear NSPanel and therefore cannot reintroduce a square window edge.
    static let windowInsets = NSEdgeInsets(
        top: 3,
        left: 18,
        bottom: 36,
        right: 18
    )

    // Figma GLASS values from node 1:712:
    // radius 18, refraction 0.88, depth 88, light angle 320°,
    // light intensity 0.40, dispersion 0.80, splay 0.12.
    //
    // AppKit exposes these optics as the fixed `.clear` compositor profile
    // rather than as public scalar properties. NSGlassEffectView is retained
    // as the single live-backdrop layer; duplicating it with a blur material
    // would conflict with Figma's own one-glass-layer rendering rule.
    static let frostRadius: CGFloat = 18
    static let refraction: CGFloat = 0.88
    static let depth: CGFloat = 88
    static let lightAngle: CGFloat = 320
    static let lightIntensity: CGFloat = 0.40
    static let dispersion: CGFloat = 0.80
    static let splay: CGFloat = 0.12
}

private final class QuotaViewGlassCompositionView: NSView {
    private let backdropBlurView: QuotaViewBackdropBlurView?
    private let chromeView: QuotaViewFigmaGlassChromeView?
    private(set) var hostedContentView: NSView?
    private var hostedContentHeight: CGFloat?

    override var isFlipped: Bool { true }

    init(
        contentView: NSView,
        usesFigmaChrome: Bool
    ) {
        backdropBlurView = usesFigmaChrome
            ? QuotaViewBackdropBlurView(
                cornerRadius: FigmaClearGlassSpec.cornerRadius
            )
            : nil
        chromeView = usesFigmaChrome
            ? QuotaViewFigmaGlassChromeView()
            : nil
        hostedContentView = contentView
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = FigmaClearGlassSpec.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        if let backdropBlurView {
            addSubview(backdropBlurView)
        }
        if let chromeView {
            addSubview(chromeView)
        }
        addSubview(contentView)
        contentView.autoresizingMask = [.width]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        backdropBlurView?.frame = bounds
        chromeView?.frame = bounds
        hostedContentView?.frame = NSRect(
            x: bounds.minX,
            y: bounds.minY,
            width: bounds.width,
            height: hostedContentHeight ?? bounds.height
        )
    }

    func setHostedContentHeight(_ height: CGFloat) {
        guard hostedContentHeight != height else { return }
        hostedContentHeight = height
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    func replaceHostedContentView(with contentView: NSView?) {
        guard hostedContentView !== contentView else { return }
        hostedContentView?.removeFromSuperview()
        hostedContentView = contentView

        if let contentView {
            addSubview(contentView)
            contentView.frame = bounds
            contentView.autoresizingMask = [.width]
        }
    }
}

private final class QuotaViewBackdropBlurView: NSView {
    private let cornerRadius: CGFloat
    private let materialView = NSVisualEffectView()

    override var isOpaque: Bool { false }

    init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        // This is the only background-softening layer. Keep the live neutral
        // system material, but blend it below the clear Liquid Glass surface
        // so it improves readability without becoming a frosted overlay.
        materialView.material = .underWindowBackground
        materialView.blendingMode = .withinWindow
        materialView.state = .active
        materialView.alphaValue = FigmaClearGlassSpec.systemBackdropOpacity
        materialView.wantsLayer = true
        materialView.layer?.cornerRadius = cornerRadius
        materialView.layer?.cornerCurve = .continuous
        materialView.layer?.masksToBounds = true
        addSubview(materialView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        materialView.frame = bounds
    }
}

private final class QuotaViewFigmaGlassChromeView: NSView {
    override var isOpaque: Bool { false }
    override var isFlipped: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let radius = min(
            FigmaClearGlassSpec.cornerRadius,
            min(bounds.width, bounds.height) / 2
        )
        let shape = NSBezierPath(
            roundedRect: bounds,
            xRadius: radius,
            yRadius: radius
        )

        let fillColor = usesLightAppearance
            ? NSColor.white.withAlphaComponent(
                FigmaClearGlassSpec.lightFillOpacity
            )
            : NSColor.black.withAlphaComponent(
                FigmaClearGlassSpec.darkFillOpacity
            )
        fillColor.setFill()
        shape.fill()

        for offset in FigmaClearGlassSpec.innerShadowOffsets {
            drawInnerShadow(in: shape, offset: offset)
        }

        // Latest Page 3 nodes use the same subtle 0.5 pt neutral boundary:
        // white over dark glass and black over light glass.
        (
            usesLightAppearance ? NSColor.black : NSColor.white
        ).withAlphaComponent(0.08).setStroke()
        shape.lineWidth = 0.5
        shape.stroke()
    }

    private func drawInnerShadow(
        in shape: NSBezierPath,
        offset: NSSize
    ) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        shape.addClip()

        let expansion = FigmaClearGlassSpec.innerShadowRadius * 3
        let inverse = NSBezierPath(
            rect: bounds.insetBy(dx: -expansion, dy: -expansion)
        )
        inverse.append(shape)
        inverse.windingRule = .evenOdd

        let shadow = NSShadow()
        shadow.shadowColor = (
            usesLightAppearance ? NSColor.white : NSColor.black
        ).withAlphaComponent(
            FigmaClearGlassSpec.innerShadowOpacity
        )
        shadow.shadowBlurRadius = FigmaClearGlassSpec.innerShadowRadius
        shadow.shadowOffset = offset
        shadow.set()

        NSColor.black.setFill()
        inverse.fill()
    }

    private var usesLightAppearance: Bool {
        effectiveAppearance.bestMatch(
            from: [.aqua, .darkAqua]
        ) == .aqua
    }
}

private final class QuotaViewFigmaDropShadowView: NSView {
    var glassFrame: NSRect = .zero {
        didSet {
            if glassFrame != oldValue {
                needsDisplay = true
            }
        }
    }

    override var isOpaque: Bool { false }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !glassFrame.isEmpty else { return }

        let shape = NSBezierPath(
            roundedRect: glassFrame,
            xRadius: FigmaClearGlassSpec.cornerRadius,
            yRadius: FigmaClearGlassSpec.cornerRadius
        )
        let outside = NSBezierPath(rect: bounds)
        outside.append(shape)
        outside.windingRule = .evenOdd

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        outside.addClip()

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(
            FigmaClearGlassSpec.dropShadowOpacity
        )
        shadow.shadowBlurRadius = FigmaClearGlassSpec.dropShadowRadius
        shadow.shadowOffset = NSSize(
            width: FigmaClearGlassSpec.dropShadowOffset.width,
            height: -FigmaClearGlassSpec.dropShadowOffset.height
        )
        shadow.set()

        NSColor.black.setFill()
        shape.fill()
    }
}

private final class QuotaViewLegacyGlassSurface: NSVisualEffectView {
    let mode: QuotaViewGlassMode

    private let backdropBlurView: QuotaViewBackdropBlurView?
    private let hostedContentView: NSView
    private var hostedContentHeight: CGFloat?

    init(
        contentView: NSView,
        mode: QuotaViewGlassMode
    ) {
        self.mode = mode
        hostedContentView = contentView
        backdropBlurView = mode == .clear
            ? QuotaViewBackdropBlurView(
                cornerRadius: FigmaClearGlassSpec.cornerRadius
            )
            : nil
        super.init(frame: .zero)
        material = mode == .clear ? .hudWindow : .popover
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = FigmaClearGlassSpec.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        maskImage = Self.roundedMask

        if let backdropBlurView {
            backdropBlurView.frame = bounds
            backdropBlurView.autoresizingMask = [.width, .height]
            addSubview(backdropBlurView)
        }
        contentView.frame = bounds
        contentView.autoresizingMask = [.width]
        addSubview(contentView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        backdropBlurView?.frame = bounds
        let contentHeight = hostedContentHeight ?? bounds.height
        hostedContentView.frame = NSRect(
            x: bounds.minX,
            y: bounds.maxY - contentHeight,
            width: bounds.width,
            height: contentHeight
        )
    }

    func setHostedContentHeight(_ height: CGFloat) {
        guard hostedContentHeight != height else { return }
        hostedContentHeight = height
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    private static let roundedMask: NSImage = {
        let radius = FigmaClearGlassSpec.cornerRadius
        let edge = radius + 1
        let size = NSSize(
            width: edge * 2 + 2,
            height: edge * 2 + 2
        )
        let image = NSImage(
            size: size,
            flipped: false
        ) { bounds in
            NSColor.white.setFill()
            NSBezierPath(
                roundedRect: bounds,
                xRadius: radius,
                yRadius: radius
            ).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(
            top: edge,
            left: edge,
            bottom: edge,
            right: edge
        )
        image.resizingMode = .stretch
        return image
    }()
}
