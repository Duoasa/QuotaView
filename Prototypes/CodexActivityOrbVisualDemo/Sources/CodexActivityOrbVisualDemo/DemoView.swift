import AppKit
import CoreText
import SwiftUI

// PROTOTYPE-ONLY: this shell mirrors the production AppKit/CoreText island.
// The only visual component replaced by the prototype is the orb view.

enum OrbPresentation: String, CaseIterable, Identifiable {
    case expanded
    case compact

    static let panelInset: CGFloat = 10
    static let compactSurfaceSize = CGSize(width: 250, height: 52)
    static let compactOrbInset: CGFloat = 12
    static let compactTextGap: CGFloat = 14
    static let compactTitleFontSize: CGFloat = 14
    static let shadowRadius: CGFloat = 7
    static let shadowVerticalOffset: CGFloat = -2
    static let productionOrbSphereRadius: CGFloat = 0.535

    static var compactOrbDiameter: CGFloat {
        compactSurfaceSize.height - compactOrbInset * 2
    }

    static var compactOrbLeading: CGFloat {
        compactOrbInset
    }

    static var compactOrbCanvasSide: CGFloat {
        compactOrbDiameter / productionOrbSphereRadius
    }

    var id: Self { self }

    var title: String {
        switch self {
        case .expanded: "展开态"
        case .compact: "紧凑态"
        }
    }

    func panelSize(for state: DemoActivityState) -> CGSize {
        switch self {
        case .expanded:
            state.expandedPanelSize
        case .compact:
            CGSize(
                width: Self.compactSurfaceSize.width
                    + Self.panelInset * 2,
                height: Self.compactSurfaceSize.height
                    + Self.panelInset * 2
            )
        }
    }

    func surfaceSize(for state: DemoActivityState) -> CGSize {
        let panel = panelSize(for: state)
        return CGSize(
            width: panel.width - Self.panelInset * 2,
            height: panel.height - Self.panelInset * 2
        )
    }

    func orbCanvasSide(for state: DemoActivityState) -> CGFloat {
        switch self {
        case .compact:
            return Self.compactOrbCanvasSide
        case .expanded:
            let expandedSurfaceHeight = max(
                state.expandedPanelSize.height - Self.panelInset * 2,
                Self.compactSurfaceSize.height
            )
            return max(
                Self.compactOrbCanvasSide,
                min(124, max(68, expandedSurfaceHeight - 10))
            )
        }
    }
}

private enum DemoDesktopBackdrop: String, CaseIterable, Identifiable {
    case neutral
    case dark
    case light

    var id: Self { self }

    var title: String {
        switch self {
        case .neutral: "中性"
        case .dark: "深色"
        case .light: "浅色"
        }
    }

    var color: Color {
        switch self {
        case .neutral:
            Color(red: 0.15, green: 0.17, blue: 0.22)
        case .dark:
            Color(red: 0.025, green: 0.03, blue: 0.045)
        case .light:
            Color(red: 0.86, green: 0.88, blue: 0.92)
        }
    }
}

private func islandExpansionProgress(
    surfaceHeight: CGFloat,
    expandedSurfaceHeight: CGFloat
) -> CGFloat {
    let compactHeight = OrbPresentation.compactSurfaceSize.height
    let range = max(expandedSurfaceHeight - compactHeight, 1)
    return min(max((surfaceHeight - compactHeight) / range, 0), 1)
}

private func islandInterpolate(
    from start: CGFloat,
    to end: CGFloat,
    progress: CGFloat
) -> CGFloat {
    start + (end - start) * progress
}

private enum IslandTextHorizontalAlignment: Equatable {
    case leading
    case center
}

private func islandSingleLinePlacement(
    in bounds: NSRect,
    imageBounds: CGRect,
    alignment: IslandTextHorizontalAlignment
) -> CGPoint {
    let baselineX: CGFloat
    switch alignment {
    case .leading:
        baselineX = bounds.minX
    case .center:
        baselineX = bounds.midX - imageBounds.midX
    }
    return CGPoint(
        x: baselineX,
        y: bounds.midY - imageBounds.midY
    )
}

private func islandTruncatedLine(
    text: String,
    font: NSFont,
    color: NSColor,
    maximumWidth: CGFloat
) -> CTLine {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color
    ]
    let source = NSAttributedString(
        string: text,
        attributes: attributes
    )
    let sourceLine = CTLineCreateWithAttributedString(source)
    let sourceWidth = CGFloat(
        CTLineGetTypographicBounds(sourceLine, nil, nil, nil)
    )
    guard sourceWidth > maximumWidth else { return sourceLine }

    let tokenLine = CTLineCreateWithAttributedString(
        NSAttributedString(string: "…", attributes: attributes)
    )
    return CTLineCreateTruncatedLine(
        sourceLine,
        Double(max(0, maximumWidth)),
        .end,
        tokenLine
    ) ?? tokenLine
}

private func islandDrawSingleLine(
    text: String,
    font: NSFont,
    color: NSColor,
    in bounds: NSRect,
    alignment: IslandTextHorizontalAlignment,
    context: CGContext
) {
    guard !text.isEmpty, bounds.width > 0, bounds.height > 0 else {
        return
    }
    let line = islandTruncatedLine(
        text: text,
        font: font,
        color: color,
        maximumWidth: bounds.width
    )
    let imageBounds = CTLineGetImageBounds(line, nil)
    guard !imageBounds.isNull,
          imageBounds.width > 0,
          imageBounds.height > 0
    else {
        return
    }

    context.saveGState()
    context.textMatrix = .identity
    context.textPosition = islandSingleLinePlacement(
        in: bounds,
        imageBounds: imageBounds,
        alignment: alignment
    )
    CTLineDraw(line, context)
    context.restoreGState()
}

private final class IslandTextMaskLayer: CALayer {
    var text = "" { didSet { setNeedsDisplay() } }
    var textFont = NSFont.systemFont(ofSize: 13) {
        didSet { setNeedsDisplay() }
    }
    var textAlignment = IslandTextHorizontalAlignment.leading {
        didSet { setNeedsDisplay() }
    }

    override func draw(in context: CGContext) {
        islandDrawSingleLine(
            text: text,
            font: textFont,
            color: .white,
            in: bounds,
            alignment: textAlignment,
            context: context
        )
    }
}

private final class IslandSingleLineTextView: NSView {
    private static let shimmerAnimationKey = "operation-highlight-sweep"
    private static let shimmerDuration: CFTimeInterval = 2.6

    private let shimmerLayer = CAGradientLayer()
    private let shimmerMaskLayer = IslandTextMaskLayer()
    private var reduceMotion = false

    var stringValue = "" {
        didSet {
            needsDisplay = true
            updateShimmerMask()
            restartShimmerIfNeeded()
        }
    }
    var font = NSFont.systemFont(ofSize: 13) {
        didSet {
            needsDisplay = true
            updateShimmerMask()
        }
    }
    var textColor = NSColor.labelColor {
        didSet { needsDisplay = true }
    }
    var horizontalAlignment = IslandTextHorizontalAlignment.leading {
        didSet {
            needsDisplay = true
            updateShimmerMask()
        }
    }
    var shimmerEnabled = false {
        didSet { updateShimmerPlayback() }
    }

    override var isOpaque: Bool { false }
    override var isFlipped: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = true

        shimmerLayer.colors = [
            NSColor.clear.cgColor,
            NSColor.white.withAlphaComponent(0.08).cgColor,
            NSColor.white.withAlphaComponent(0.92).cgColor,
            NSColor.white.withAlphaComponent(0.08).cgColor,
            NSColor.clear.cgColor
        ]
        shimmerLayer.locations = [-0.58, -0.42, -0.26, -0.10, 0.06]
        shimmerLayer.startPoint = CGPoint(x: 0, y: 0.5)
        shimmerLayer.endPoint = CGPoint(x: 1, y: 0.5)
        shimmerLayer.mask = shimmerMaskLayer
        shimmerLayer.isHidden = true
        layer?.addSublayer(shimmerLayer)
        updateShimmerMask()
    }

    convenience init() {
        self.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }
        islandDrawSingleLine(
            text: stringValue,
            font: font,
            color: textColor,
            in: bounds,
            alignment: horizontalAlignment,
            context: context
        )
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shimmerLayer.frame = bounds
        shimmerMaskLayer.frame = shimmerLayer.bounds
        let scale = window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
        shimmerLayer.contentsScale = scale
        shimmerMaskLayer.contentsScale = scale
        CATransaction.commit()
        shimmerMaskLayer.setNeedsDisplay()
    }

    func setReduceMotion(_ enabled: Bool) {
        reduceMotion = enabled
        updateShimmerPlayback()
    }

    private func updateShimmerMask() {
        shimmerMaskLayer.text = stringValue
        shimmerMaskLayer.textFont = font
        shimmerMaskLayer.textAlignment = horizontalAlignment
    }

    private func restartShimmerIfNeeded() {
        guard shimmerEnabled, !reduceMotion else { return }
        shimmerLayer.removeAnimation(forKey: Self.shimmerAnimationKey)
        addShimmerAnimation()
    }

    private func updateShimmerPlayback() {
        let shouldAnimate = shimmerEnabled && !reduceMotion
        shimmerLayer.isHidden = !shouldAnimate
        if shouldAnimate {
            if shimmerLayer.animation(
                forKey: Self.shimmerAnimationKey
            ) == nil {
                addShimmerAnimation()
            }
        } else {
            shimmerLayer.removeAnimation(forKey: Self.shimmerAnimationKey)
        }
    }

    private func addShimmerAnimation() {
        let animation = CABasicAnimation(keyPath: "locations")
        animation.fromValue = [-0.58, -0.42, -0.26, -0.10, 0.06]
        animation.toValue = [0.94, 1.10, 1.26, 1.42, 1.58]
        animation.duration = Self.shimmerDuration
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(
            name: .easeInEaseOut
        )
        shimmerLayer.add(
            animation,
            forKey: Self.shimmerAnimationKey
        )
    }
}

private struct IslandExpandedTextLayout {
    var kickerY: CGFloat
    var titleY: CGFloat
    var detailY: CGFloat
    var statusDotY: CGFloat
}

private let islandSupportingLineHeight: CGFloat = 18
private let islandStatusLineHeight: CGFloat = 26
private let islandTextRowGap: CGFloat = 4
private let islandStatusDotSide: CGFloat = 6

private func islandCenteredTextLayout(
    surfaceHeight: CGFloat
) -> IslandExpandedTextLayout {
    let stackHeight =
        islandSupportingLineHeight * 2
        + islandStatusLineHeight
        + islandTextRowGap * 2
    let stackBottom = (surfaceHeight - stackHeight) / 2
    let detailY = stackBottom
    let titleY =
        detailY + islandSupportingLineHeight + islandTextRowGap
    let kickerY =
        titleY + islandStatusLineHeight + islandTextRowGap
    return IslandExpandedTextLayout(
        kickerY: kickerY,
        titleY: titleY,
        detailY: detailY,
        statusDotY:
            kickerY
            + (islandSupportingLineHeight - islandStatusDotSide) / 2
    )
}

private final class ProductionIslandSurfaceView: NSView {
    private let materialView = NSVisualEffectView()
    private let tintView = NSView()

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.cornerRadius = 34
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        materialView.material = .hudWindow
        materialView.blendingMode = .behindWindow
        materialView.state = .active
        addSubview(materialView)

        tintView.wantsLayer = true
        tintView.layer?.backgroundColor = NSColor.black
            .withAlphaComponent(0.72)
            .cgColor
        tintView.layer?.borderColor = NSColor.white
            .withAlphaComponent(0.10)
            .cgColor
        tintView.layer?.borderWidth = 0.5
        addSubview(tintView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let radius = min(34, bounds.height / 2)
        layer?.cornerRadius = radius
        materialView.frame = bounds
        tintView.frame = bounds
        tintView.layer?.cornerRadius = radius
        tintView.layer?.cornerCurve = .continuous
    }
}

private final class ProductionIslandContentView: NSView {
    private let shadowHost = NSView()
    private let surface = ProductionIslandSurfaceView()
    private let orbView: LiquidOrbHostView
    private let kickerLabel = IslandSingleLineTextView()
    private let titleLabel = IslandSingleLineTextView()
    private let compactTitleLabel = IslandSingleLineTextView()
    private let detailLabel = IslandSingleLineTextView()
    private let statusDot = NSView()

    private var state: DemoActivityState

    override var isOpaque: Bool { false }

    init(initialState: DemoActivityState) {
        state = initialState
        orbView = LiquidOrbHostView(
            frame: .zero,
            initialState: initialState
        )
        super.init(frame: .zero)

        wantsLayer = true

        shadowHost.wantsLayer = true
        shadowHost.layer?.shadowColor = NSColor.black.cgColor
        shadowHost.layer?.shadowOpacity = 0.42
        shadowHost.layer?.shadowRadius = OrbPresentation.shadowRadius
        shadowHost.layer?.shadowOffset = CGSize(
            width: 0,
            height: OrbPresentation.shadowVerticalOffset
        )
        addSubview(shadowHost)

        shadowHost.addSubview(surface)
        surface.addSubview(orbView)

        kickerLabel.font = islandFont(
            "AstaSans-SemiBold",
            size: 11.5,
            fallbackWeight: .semibold
        )
        kickerLabel.textColor = NSColor.white.withAlphaComponent(0.46)
        surface.addSubview(kickerLabel)

        titleLabel.font = islandFont(
            "AstaSans-SemiBold",
            size: 18,
            fallbackWeight: .semibold
        )
        titleLabel.textColor = .white
        surface.addSubview(titleLabel)

        compactTitleLabel.font = islandFont(
            "AstaSans-SemiBold",
            size: OrbPresentation.compactTitleFontSize,
            fallbackWeight: .semibold
        )
        compactTitleLabel.textColor = .white
        compactTitleLabel.horizontalAlignment = .center
        surface.addSubview(compactTitleLabel)

        detailLabel.font = islandFont(
            "AstaSans-Regular",
            size: 11.5,
            fallbackWeight: .regular
        )
        surface.addSubview(detailLabel)

        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = islandStatusDotSide / 2
        surface.addSubview(statusDot)

        update(state: initialState, paused: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()

        let panelInset = OrbPresentation.panelInset
        shadowHost.frame = bounds.insetBy(
            dx: panelInset,
            dy: panelInset
        )
        surface.frame = shadowHost.bounds

        let surfaceBounds = surface.bounds
        shadowHost.layer?.shadowPath = CGPath(
            roundedRect: shadowHost.bounds,
            cornerWidth: min(34, shadowHost.bounds.height / 2),
            cornerHeight: min(34, shadowHost.bounds.height / 2),
            transform: nil
        )

        let expandedSurfaceHeight = max(
            state.expandedPanelSize.height - panelInset * 2,
            OrbPresentation.compactSurfaceSize.height
        )
        let progress = islandExpansionProgress(
            surfaceHeight: surfaceBounds.height,
            expandedSurfaceHeight: expandedSurfaceHeight
        )
        let expandedOrbSide = max(
            OrbPresentation.compactOrbCanvasSide,
            min(124, max(68, expandedSurfaceHeight - 10))
        )
        let orbCanvasSide = islandInterpolate(
            from: OrbPresentation.compactOrbCanvasSide,
            to: expandedOrbSide,
            progress: progress
        )
        let compactOrbCanvasLeading =
            OrbPresentation.compactOrbLeading
            - (
                OrbPresentation.compactOrbCanvasSide
                - OrbPresentation.compactOrbDiameter
            ) / 2
        let orbX = islandInterpolate(
            from: compactOrbCanvasLeading,
            to: 4,
            progress: progress
        )
        orbView.frame = NSRect(
            x: orbX,
            y: (surfaceBounds.height - orbCanvasSide) / 2,
            width: orbCanvasSide,
            height: orbCanvasSide
        )

        let compactTextStart =
            OrbPresentation.compactOrbLeading
            + OrbPresentation.compactOrbDiameter
            + OrbPresentation.compactTextGap
        let expandedTextStart = 4 + expandedOrbSide + 2
        let textStart = islandInterpolate(
            from: compactTextStart,
            to: expandedTextStart,
            progress: progress
        )
        let textWidth = max(
            0,
            surfaceBounds.width - textStart - 18
        )
        let supportingAlpha = min(
            max((progress - 0.42) / 0.58, 0),
            1
        )
        let expandedTitleAlpha = min(
            max((progress - 0.18) / 0.82, 0),
            1
        )
        let compactTitleAlpha = min(
            max((0.58 - progress) / 0.58, 0),
            1
        )
        let textLayout = islandCenteredTextLayout(
            surfaceHeight: surfaceBounds.height
        )

        kickerLabel.alphaValue = supportingAlpha
        detailLabel.alphaValue = supportingAlpha
        statusDot.alphaValue = supportingAlpha
        titleLabel.alphaValue = expandedTitleAlpha
        compactTitleLabel.alphaValue = compactTitleAlpha

        kickerLabel.frame = NSRect(
            x: textStart + 12,
            y: textLayout.kickerY,
            width: max(0, textWidth - 12),
            height: islandSupportingLineHeight
        )
        statusDot.frame = NSRect(
            x: textStart,
            y: textLayout.statusDotY,
            width: islandStatusDotSide,
            height: islandStatusDotSide
        )
        let centeredStatusY =
            (surfaceBounds.height - islandStatusLineHeight) / 2
        titleLabel.frame = NSRect(
            x: textStart,
            y: islandInterpolate(
                from: centeredStatusY,
                to: textLayout.titleY,
                progress: progress
            ),
            width: textWidth,
            height: islandStatusLineHeight
        )
        compactTitleLabel.frame = NSRect(
            x:
                OrbPresentation.compactOrbLeading
                + OrbPresentation.compactOrbDiameter,
            y: 0,
            width: max(
                0,
                surfaceBounds.width
                    - OrbPresentation.compactOrbLeading
                    - OrbPresentation.compactOrbDiameter
            ),
            height: surfaceBounds.height
        )
        detailLabel.frame = NSRect(
            x: textStart,
            y: textLayout.detailY,
            width: textWidth,
            height: islandSupportingLineHeight
        )
        shadowHost.layer?.shadowOpacity = Float(
            islandInterpolate(
                from: 0.30,
                to: 0.42,
                progress: progress
            )
        )
    }

    func update(state: DemoActivityState, paused: Bool) {
        self.state = state
        kickerLabel.stringValue = state.windowTitle
        titleLabel.stringValue = state.statusTitle
        compactTitleLabel.stringValue = state.statusTitle
        detailLabel.stringValue = state.operation
        detailLabel.textColor = NSColor.white.withAlphaComponent(
            state.showsOperationSweep ? 0.42 : 0.64
        )
        detailLabel.shimmerEnabled = state.showsOperationSweep
        statusDot.layer?.backgroundColor = state.accentColor.cgColor
        orbView.setState(state)
        orbView.setPaused(paused)
        detailLabel.setReduceMotion(paused)
        needsLayout = true

        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(
            "\(state.windowTitle)，状态：\(state.statusTitle)，当前操作：\(state.operation)"
        )
    }
}

private struct ProductionIslandRepresentable: NSViewRepresentable {
    let state: DemoActivityState
    let paused: Bool

    func makeNSView(context: Context) -> ProductionIslandContentView {
        ProductionIslandContentView(initialState: state)
    }

    func updateNSView(
        _ view: ProductionIslandContentView,
        context: Context
    ) {
        view.update(state: state, paused: paused)
    }
}

private func islandFont(
    _ name: String,
    size: CGFloat,
    fallbackWeight: NSFont.Weight
) -> NSFont {
    NSFont(name: name, size: size)
        ?? NSFont.systemFont(
            ofSize: size,
            weight: fallbackWeight
        )
}

struct OrbVisualDemoView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var state = DemoActivityState.thinking
    @State private var presentation = OrbPresentation.expanded
    @State private var backdrop = DemoDesktopBackdrop.neutral
    @State private var manuallyPaused = false
    @State private var rendererIdentity = UUID()

    private var effectivePaused: Bool {
        manuallyPaused || reduceMotion
    }

    private var panelSize: CGSize {
        presentation.panelSize(for: state)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            stage
            stateControls
            displayControls
            diagnostics
        }
        .padding(24)
        .frame(minWidth: 760, minHeight: 680)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("生产单灵动岛外壳 · 新 AI 球 Demo")
                .font(.system(size: 22, weight: .semibold))
            Text("外壳、CoreText 排版和几何复用当前实现；仅替换球体渲染器。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var stage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(backdrop.color)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(
                            Color(nsColor: .separatorColor),
                            lineWidth: 0.5
                        )
                }

            ProductionIslandRepresentable(
                state: state,
                paused: effectivePaused
            )
            .id(rendererIdentity)
            .frame(width: panelSize.width, height: panelSize.height)
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.44),
                value: state
            )
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.30),
                value: presentation
            )
        }
        .frame(maxWidth: .infinity)
        .frame(height: 280)
    }

    private var stateControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("运行状态")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 8),
                    count: 5
                ),
                spacing: 8
            ) {
                ForEach(DemoActivityState.allCases) { item in
                    Button {
                        state = item
                    } label: {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(Color(nsColor: item.accentColor))
                                .frame(width: 7, height: 7)
                            Text(item.pickerTitle)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(state == item ? Color.accentColor : nil)
                    .accessibilityLabel("切换为\(item.statusTitle)状态")
                }
            }
        }
    }

    private var displayControls: some View {
        HStack(alignment: .bottom, spacing: 20) {
            controlPicker("显示形态", selection: $presentation)
                .frame(width: 210)
            controlPicker("桌面背景", selection: $backdrop)
                .frame(width: 240)

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 8) {
                Text("动画")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button(manuallyPaused ? "继续" : "暂停") {
                        manuallyPaused.toggle()
                    }
                    .disabled(reduceMotion)

                    Button("重新开始") {
                        rendererIdentity = UUID()
                        manuallyPaused = false
                    }
                }
            }
        }
    }

    private func controlPicker<Value>(
        _ title: String,
        selection: Binding<Value>
    ) -> some View where Value: CaseIterable & Hashable & Identifiable,
        Value.AllCases: RandomAccessCollection,
        Value.ID == Value
    {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker(title, selection: selection) {
                ForEach(Value.allCases) { item in
                    Text(displayTitle(for: item)).tag(item)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
        }
    }

    private func displayTitle<Value>(for value: Value) -> String {
        if let presentation = value as? OrbPresentation {
            return presentation.title
        }
        if let backdrop = value as? DemoDesktopBackdrop {
            return backdrop.title
        }
        return String(describing: value)
    }

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(
                "\(state.rawValue) · Style 9 · Circle 0.535 · "
                    + "\(String(format: "%.2f", state.orbConfiguration.effectiveSpeed))× Speed · "
                    + "\(Int(presentation.orbCanvasSide(for: state))) pt Canvas"
            )
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)

            if reduceMotion {
                Text("系统“减少动态效果”已开启，AI 球和操作文字扫光保持静止。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
