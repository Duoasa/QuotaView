import AppKit
import CoreText
import QuartzCore

enum ActivityTextHorizontalAlignment: Equatable {
    case leading
    case center
    case trailing
}

private func activitySingleLinePlacement(
    in bounds: NSRect,
    imageBounds: CGRect,
    alignment: ActivityTextHorizontalAlignment
) -> CGPoint {
    let baselineX: CGFloat
    switch alignment {
    case .leading:
        baselineX = bounds.minX
    case .center:
        baselineX = bounds.midX - imageBounds.midX
    case .trailing:
        baselineX = bounds.maxX - imageBounds.maxX
    }
    return CGPoint(
        x: baselineX,
        y: bounds.midY - imageBounds.midY
    )
}

func activitySingleLineWidth(text: String, font: NSFont) -> CGFloat {
    let line = CTLineCreateWithAttributedString(
        NSAttributedString(string: text, attributes: [.font: font])
    )
    return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
}

func activityTruncatedLine(
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
    // Layout arithmetic can lose a few ULPs at an exact-fit boundary. Do not
    // replace otherwise fitting text with an ellipsis; real overflow still
    // takes the normal truncation path. This is far smaller than a pixel.
    let roundingTolerance = max(1, max(sourceWidth, abs(maximumWidth))).ulp * 8
    guard sourceWidth - maximumWidth > roundingTolerance else { return sourceLine }

    let tokenLine = CTLineCreateWithAttributedString(
        NSAttributedString(string: "…", attributes: attributes)
    )
    let tokenWidth = CGFloat(CTLineGetTypographicBounds(tokenLine, nil, nil, nil))
    guard tokenWidth - maximumWidth <= roundingTolerance else {
        return CTLineCreateWithAttributedString(NSAttributedString(string: ""))
    }

    // Mixed-script fallback and emoji shaping can produce a truncated line
    // wider than CoreText's requested width. Verify the result before drawing
    // into the clipped label, with a bounded retry using the measured excess.
    var truncationWidth = max(0, maximumWidth)
    for _ in 0..<4 {
        guard let line = CTLineCreateTruncatedLine(
            sourceLine, Double(truncationWidth), .end, tokenLine
        ) else { return tokenLine }
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let excess = width - maximumWidth
        if excess <= roundingTolerance { return line }
        truncationWidth = max(0, truncationWidth - excess - roundingTolerance)
    }
    return tokenLine
}

private func activityDrawSingleLine(
    text: String,
    font: NSFont,
    color: NSColor,
    in bounds: NSRect,
    alignment: ActivityTextHorizontalAlignment,
    context: CGContext
) {
    guard !text.isEmpty, bounds.width > 0, bounds.height > 0 else {
        return
    }
    let line = activityTruncatedLine(
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
    context.textPosition = activitySingleLinePlacement(
        in: bounds,
        imageBounds: imageBounds,
        alignment: alignment
    )
    CTLineDraw(line, context)
    context.restoreGState()
}

private final class ActivityTextMaskLayer: CALayer {
    var text = "" { didSet { setNeedsDisplay() } }
    var textFont = NSFont.systemFont(ofSize: 13) {
        didSet { setNeedsDisplay() }
    }
    var textAlignment = ActivityTextHorizontalAlignment.leading {
        didSet { setNeedsDisplay() }
    }

    override func draw(in context: CGContext) {
        activityDrawSingleLine(
            text: text,
            font: textFont,
            color: .white,
            in: bounds,
            alignment: textAlignment,
            context: context
        )
    }
}

final class ActivitySingleLineTextView: NSView {
    private static let shimmerAnimationKey = "operation-highlight-sweep"
    private static let shimmerDuration: CFTimeInterval = 2.6

    private let shimmerLayer = CAGradientLayer()
    private let shimmerMaskLayer = ActivityTextMaskLayer()
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
    var horizontalAlignment = ActivityTextHorizontalAlignment.leading {
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
            NSColor.white.withAlphaComponent(
                CodexActivityIslandTextContrast
                    .operationShimmerShoulderAlpha
            ).cgColor,
            NSColor.white.withAlphaComponent(
                CodexActivityIslandTextContrast
                    .operationShimmerPeakAlpha
            ).cgColor,
            NSColor.white.withAlphaComponent(
                CodexActivityIslandTextContrast
                    .operationShimmerShoulderAlpha
            ).cgColor,
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
        activityDrawSingleLine(
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

func activityFont(
    _ name: String,
    size: CGFloat,
    fallbackWeight: NSFont.Weight
) -> NSFont {
    if let font = AstaSansFontRegistrar.font(named: name, size: size) {
        return font as NSFont
    }
    return NSFont.systemFont(ofSize: size, weight: fallbackWeight)
}
