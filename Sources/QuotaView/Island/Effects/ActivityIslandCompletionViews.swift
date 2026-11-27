import AppKit
import QuartzCore
import QuotaViewCore

struct CodexActivityIslandCompletionPalette {
    static let violet = NSColor(srgbRed: 0.55, green: 0.36, blue: 1.00, alpha: 1)
    static let blue = NSColor(srgbRed: 0.31, green: 0.63, blue: 1.00, alpha: 1)
    static let cyan = NSColor(srgbRed: 0.43, green: 0.89, blue: 1.00, alpha: 1)
    static let gradientLocations: [NSNumber] = [0, 0.52, 1]
    static let flowDuration: CFTimeInterval = 6
    static let flowLocations: [NSNumber] = [0.0, 1.0 / 3, 2.0 / 3, 1.0].map { NSNumber(value: $0) }
    // Closing each frame with its first color avoids a seam at the conic origin.
    static let flowFrames: [[CGColor]] = [
        [violet.cgColor, blue.cgColor, cyan.cgColor, violet.cgColor],
        [cyan.cgColor, violet.cgColor, blue.cgColor, cyan.cgColor],
        [blue.cgColor, cyan.cgColor, violet.cgColor, blue.cgColor],
        [violet.cgColor, blue.cgColor, cyan.cgColor, violet.cgColor],
    ]
}

enum CodexActivityQuotaRiskBand: Equatable {
    case unavailable
    case healthy
    case warning
    case critical
}

struct CodexActivityQuotaRingContract {
    static let trackOpacity: CGFloat = 0.22

    static func riskBand(
        for remainingPercent: Int?
    ) -> CodexActivityQuotaRiskBand {
        guard let remainingPercent else { return .unavailable }
        switch min(max(remainingPercent, 0), 100) {
        case 50...: return .healthy
        case 20..<50: return .warning
        default: return .critical
        }
    }

    static func color(for remainingPercent: Int?) -> NSColor {
        switch riskBand(for: remainingPercent) {
        case .healthy:
            NSColor(
                srgbRed: 0,
                green: 1,
                blue: 17.0 / 255.0,
                alpha: 1
            )
        case .warning:
            CodexActivityIslandConfirmationReminderContract.warningColor
        case .critical:
            NSColor(
                srgbRed: 1,
                green: 69.0 / 255.0,
                blue: 58.0 / 255.0,
                alpha: 1
            )
        case .unavailable:
            NSColor.white.withAlphaComponent(0.34)
        }
    }
}

final class ActivityIslandCompletionGlowView: NSView {
    var consoleContour: CGPath?
    var usesContinuousCorners = false
    var drawsOnlyEdge = false {
        didSet {
            guard drawsOnlyEdge != oldValue else { return }
            applyColors()
            needsLayout = true
        }
    }
    // Optional satellite styling; nil preserves the existing main-island palette
    // and completion sequence.
    var completionColor: NSColor? { didSet { applyColors() } }
    var confirmationColor: NSColor? {
        didSet { if confirmationColor != oldValue { applyColors() } }
    }
    var displayedGlowColors: [CGColor] { [violetGlowLayer.shadowColor, cyanGlowLayer.shadowColor].compactMap { $0 } }
    var completionRevealDelay: CFTimeInterval?
    private enum AnimationKey {
        static let reveal = "quotaview.activity.completion-glow.reveal"
        static let breathRadius =
            "quotaview.activity.completion-glow.radius"
    }

    private let violetGlowLayer = CAShapeLayer()
    private let cyanGlowLayer = CAShapeLayer()
    private let edgeOnlyMask = CAShapeLayer()
    private var edgeEmphasis = CodexActivityIslandEdgeEmphasis.none
    private var reduceMotion = false
    private var playbackVisible = false
    private var islandCornerRadius: CGFloat = 34
    private var islandInset =
        CodexActivityIslandPresentation.panelInset

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = false

        configureGlowLayer(
            violetGlowLayer,
            color: CodexActivityIslandCompletionPalette.violet,
            horizontalOffset: -2
        )
        configureGlowLayer(
            cyanGlowLayer,
            color: CodexActivityIslandCompletionPalette.cyan,
            horizontalOffset: 2
        )
        layer?.addSublayer(violetGlowLayer)
        layer?.addSublayer(cyanGlowLayer)
        isHidden = true
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func layout() {
        super.layout()
        let islandRect = bounds.insetBy(
            dx: islandInset,
            dy: islandInset
        )
        let islandRadius = min(
            islandCornerRadius,
            islandRect.height / 2
        )
        let glowSourceRect =
            CodexActivityIslandCompletionGlowGeometry.sourceRect(
                in: islandRect
            )
        let glowSourceRadius =
            CodexActivityIslandCompletionGlowGeometry
            .sourceCornerRadius(
                in: islandRect,
                islandCornerRadius: islandRadius
            )
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let glowPath = consoleContour ?? (usesContinuousCorners
            ? IslandVibeLayout.continuousContour(in: glowSourceRect, radius: glowSourceRadius)
            : CGPath(
            roundedRect: glowSourceRect,
            cornerWidth: glowSourceRadius,
            cornerHeight: glowSourceRadius,
            transform: nil
        ))
        let shadowPath = drawsOnlyEdge
            ? glowPath.copy(strokingWithWidth: CodexActivityIslandCompletionGlowGeometry.outlineWidth,
                lineCap: .round, lineJoin: .round, miterLimit: 2)
            : glowPath
        for glowLayer in [violetGlowLayer, cyanGlowLayer] {
            glowLayer.frame = bounds
            glowLayer.path = glowPath
            glowLayer.shadowPath = shadowPath
        }
        if drawsOnlyEdge && consoleContour == nil {
            // Cut out the text area from the glow only, never from a glass
            // ancestor. Keep a narrow inner rim and the existing outer bloom.
            let rimWidth: CGFloat = 2
            let interior = islandRect.insetBy(dx: rimWidth, dy: rimWidth)
            let maskPath = CGMutablePath()
            maskPath.addRect(bounds)
            if interior.width > 0 && interior.height > 0 {
                let radius = max(0, islandRadius - rimWidth)
                maskPath.addPath(usesContinuousCorners
                    ? IslandVibeLayout.continuousContour(in: interior, radius: radius)
                    : CGPath(roundedRect: interior, cornerWidth: radius, cornerHeight: radius, transform: nil))
            }
            edgeOnlyMask.frame = bounds
            edgeOnlyMask.fillColor = NSColor.black.cgColor
            edgeOnlyMask.fillRule = .evenOdd
            edgeOnlyMask.path = maskPath
            layer?.mask = edgeOnlyMask
        } else {
            layer?.mask = nil
        }
        CATransaction.commit()
    }

    func setIslandInset(_ inset: CGFloat) {
        let normalized = max(0, inset)
        guard islandInset != normalized else { return }
        islandInset = normalized
        needsLayout = true
    }

    func setIslandCornerRadius(_ radius: CGFloat) {
        let normalized = max(0, radius)
        guard islandCornerRadius != normalized else { return }
        islandCornerRadius = normalized
        needsLayout = true
    }

    func update(
        edgeEmphasis: CodexActivityIslandEdgeEmphasis,
        reduceMotion: Bool,
        playbackVisible: Bool
    ) {
        guard self.edgeEmphasis != edgeEmphasis
                || self.reduceMotion != reduceMotion
                || self.playbackVisible != playbackVisible
        else {
            return
        }

        let previousEmphasis = self.edgeEmphasis
        let wasShowing = previousEmphasis != .none
            && self.playbackVisible
        self.edgeEmphasis = edgeEmphasis
        self.reduceMotion = reduceMotion
        self.playbackVisible = playbackVisible
        applyColors()
        applyState(
            delaysReveal: !wasShowing
                || previousEmphasis != edgeEmphasis
        )
    }

    private func applyState(delaysReveal: Bool) {
        let glowLayers = [violetGlowLayer, cyanGlowLayer]
        glowLayers.forEach { $0.removeAllAnimations() }

        let shouldShow = edgeEmphasis != .none && playbackVisible
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for glowLayer in glowLayers {
            glowLayer.opacity = shouldShow ? 1 : 0
            glowLayer.shadowOpacity = shouldShow
                ? CodexActivityIslandCompletionGlowGeometry
                    .shadowOpacity
                : 0
            glowLayer.shadowRadius = shouldShow
                ? CodexActivityIslandCompletionGlowGeometry
                    .restingShadowRadius
                : 0
        }
        CATransaction.commit()
        isHidden = !shouldShow

        guard shouldShow, !reduceMotion else { return }

        let now = violetGlowLayer.convertTime(
            CACurrentMediaTime(),
            from: nil
        )
        let revealDelay: CFTimeInterval = edgeEmphasis == .completion
            ? (completionRevealDelay ?? CodexActivityStateSmokeContract.completionGlowDelay)
            : 0
        let revealDuration: CFTimeInterval =
            edgeEmphasis == .confirmationReminder
            ? CodexActivityIslandConfirmationReminderContract
                .revealDuration
            : CodexActivityStateSmokeContract.completionGlowFadeDuration
        var breathBeginTime = now
        if delaysReveal {
            let reveal = CABasicAnimation(keyPath: "opacity")
            reveal.fromValue = 0
            reveal.toValue = 1
            reveal.beginTime = now + revealDelay
            reveal.duration = revealDuration
            reveal.fillMode = .backwards
            reveal.timingFunction = CAMediaTimingFunction(
                name: .easeOut
            )
            for glowLayer in glowLayers {
                glowLayer.add(reveal, forKey: AnimationKey.reveal)
            }
            breathBeginTime = reveal.beginTime + reveal.duration
        }

        let breathRadius = CAKeyframeAnimation(keyPath: "shadowRadius")
        breathRadius.values = [
            CodexActivityIslandCompletionGlowGeometry
                .restingShadowRadius,
            CodexActivityIslandCompletionGlowGeometry
                .peakShadowRadius,
            CodexActivityIslandCompletionGlowGeometry
                .restingShadowRadius,
        ]
        breathRadius.keyTimes = [0, 0.5, 1]
        breathRadius.beginTime = breathBeginTime
        breathRadius.duration =
            CodexActivityStateSmokeContract
                .completionGlowBreathDuration
        breathRadius.repeatCount = .infinity
        breathRadius.timingFunctions = [
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
        ]
        for glowLayer in glowLayers {
            glowLayer.add(
                breathRadius,
                forKey: AnimationKey.breathRadius
            )
        }
    }

    private func applyColors() {
        let colors: (NSColor, NSColor)
        switch edgeEmphasis {
        case .completion, .none:
            colors = (
                completionColor ?? CodexActivityIslandCompletionPalette.violet,
                completionColor ?? CodexActivityIslandCompletionPalette.cyan
            )
        case .confirmationReminder:
            let warning =
                confirmationColor ?? CodexActivityIslandConfirmationReminderContract
                .approvalColor
            colors = (warning, warning)
        }
        for (layer, color) in zip(
            [violetGlowLayer, cyanGlowLayer],
            [colors.0, colors.1]
        ) {
            layer.fillColor = drawsOnlyEdge ? NSColor.clear.cgColor : color.cgColor
            layer.strokeColor = drawsOnlyEdge ? color.cgColor : nil
            layer.lineWidth = CodexActivityIslandCompletionGlowGeometry.outlineWidth
            layer.shadowColor = color.cgColor
        }
    }

    private func configureGlowLayer(
        _ glowLayer: CAShapeLayer,
        color: NSColor,
        horizontalOffset: CGFloat
    ) {
        glowLayer.fillColor = color.cgColor
        glowLayer.strokeColor = nil
        glowLayer.shadowColor = color.cgColor
        glowLayer.shadowOffset = CGSize(
            width: horizontalOffset,
            height: 0
        )
        glowLayer.masksToBounds = false
    }
}

final class ActivityIslandCompletionOutlineView: NSView {
    var usesContinuousCorners = false
    var completionColor: NSColor? {
        didSet {
            guard completionColor != oldValue else { return }
            applyColors()
            applyState(delaysReveal: false)
        }
    }
    var completionRiseStart: CFTimeInterval?
    var completionRevealDelay: CFTimeInterval?
    private enum AnimationKey {
        static let flow = "quotaview.activity.completion-outline.flow"
        static let reveal =
            "quotaview.activity.completion-outline.reveal"
    }

    private let outlineGradientLayer = CAGradientLayer()
    private let outlineMaskLayer = CAShapeLayer()
    private var edgeEmphasis = CodexActivityIslandEdgeEmphasis.none
    private var reduceMotion = false
    private var playbackVisible = false
    private var islandCornerRadius: CGFloat = 34

    var flowAnimation: CAKeyframeAnimation? {
        outlineGradientLayer.animation(forKey: AnimationKey.flow) as? CAKeyframeAnimation
    }
    var displayedColors: [CGColor] { outlineGradientLayer.colors as? [CGColor] ?? [] }
    var outlinePath: CGPath? { outlineMaskLayer.path }
    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        outlineGradientLayer.colors = [
            CodexActivityIslandCompletionPalette.violet.cgColor,
            CodexActivityIslandCompletionPalette.blue.cgColor,
            CodexActivityIslandCompletionPalette.cyan.cgColor,
        ]
        outlineGradientLayer.locations =
            CodexActivityIslandCompletionPalette.gradientLocations
        outlineGradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        outlineGradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        outlineMaskLayer.fillColor = NSColor.clear.cgColor
        outlineMaskLayer.strokeColor = NSColor.white.cgColor
        outlineMaskLayer.lineWidth =
            CodexActivityIslandCompletionGlowGeometry.outlineWidth
        outlineGradientLayer.mask = outlineMaskLayer
        layer?.addSublayer(outlineGradientLayer)
        isHidden = true
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func layout() {
        super.layout()
        let halfWidth =
            CodexActivityIslandCompletionGlowGeometry.outlineWidth / 2
        let outlineRect = bounds.insetBy(
            dx: halfWidth,
            dy: halfWidth
        )
        let outlineRadius = max(
            0,
            min(islandCornerRadius, bounds.height / 2) - halfWidth
        )
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let path = usesContinuousCorners
            ? IslandVibeLayout.continuousContour(in: outlineRect, radius: outlineRadius)
            : CGPath(
            roundedRect: outlineRect,
            cornerWidth: outlineRadius,
            cornerHeight: outlineRadius,
            transform: nil
        )
        outlineGradientLayer.frame = bounds
        outlineMaskLayer.frame = bounds
        outlineMaskLayer.path = path
        CATransaction.commit()
    }

    func setIslandCornerRadius(_ radius: CGFloat) {
        let normalized = max(0, radius)
        guard islandCornerRadius != normalized else { return }
        islandCornerRadius = normalized
        needsLayout = true
    }

    func update(
        edgeEmphasis: CodexActivityIslandEdgeEmphasis,
        reduceMotion: Bool,
        playbackVisible: Bool
    ) {
        guard self.edgeEmphasis != edgeEmphasis
                || self.reduceMotion != reduceMotion
                || self.playbackVisible != playbackVisible
        else {
            return
        }

        let previousEmphasis = self.edgeEmphasis
        let wasShowing = previousEmphasis != .none
            && self.playbackVisible
        self.edgeEmphasis = edgeEmphasis
        self.reduceMotion = reduceMotion
        self.playbackVisible = playbackVisible
        applyColors()
        applyState(
            delaysReveal: !wasShowing
                || previousEmphasis != edgeEmphasis
        )
    }

    private func applyState(delaysReveal: Bool) {
        outlineGradientLayer.removeAllAnimations()
        let shouldShow = edgeEmphasis != .none && playbackVisible
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        outlineGradientLayer.opacity = shouldShow ? 1 : 0
        CATransaction.commit()
        isHidden = !shouldShow
        needsLayout = true

        guard shouldShow, !reduceMotion else { return }
        if edgeEmphasis == .completion && completionColor == nil {
            let flow = CAKeyframeAnimation(keyPath: "colors")
            flow.values = CodexActivityIslandCompletionPalette.flowFrames
            flow.keyTimes = CodexActivityIslandCompletionPalette.flowLocations
            flow.duration = CodexActivityIslandCompletionPalette.flowDuration
            flow.repeatCount = .infinity
            flow.calculationMode = .linear
            flow.beginTime = outlineGradientLayer.convertTime(CACurrentMediaTime(), from: nil)
            outlineGradientLayer.add(flow, forKey: AnimationKey.flow)
        }
        guard delaysReveal else { return }
        let now = outlineGradientLayer.convertTime(
            CACurrentMediaTime(),
            from: nil
        )
        let reveal = CABasicAnimation(keyPath: "opacity")
        reveal.fromValue = 0
        reveal.toValue = 1
        reveal.beginTime = now + (
            edgeEmphasis == .completion
                ? (completionRevealDelay ?? CodexActivityStateSmokeContract.completionGlowDelay)
                : 0
        )
        reveal.duration = edgeEmphasis == .confirmationReminder
            ? CodexActivityIslandConfirmationReminderContract
                .revealDuration
            : CodexActivityStateSmokeContract.completionGlowFadeDuration
        reveal.fillMode = .backwards
        reveal.timingFunction = CAMediaTimingFunction(name: .easeOut)
        if edgeEmphasis == .completion, let completionRiseStart {
            reveal.beginTime = outlineGradientLayer.convertTime(completionRiseStart, from: nil)
            reveal.duration = IslandConfirmationPulse.riseDuration
            reveal.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        }
        outlineGradientLayer.add(
            reveal,
            forKey: AnimationKey.reveal
        )
    }

    private func applyColors() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        if edgeEmphasis == .completion && completionColor == nil {
            outlineGradientLayer.type = .conic
            outlineGradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
            outlineGradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
            outlineGradientLayer.locations = CodexActivityIslandCompletionPalette.flowLocations
            outlineGradientLayer.colors = CodexActivityIslandCompletionPalette.flowFrames[0]
        } else {
            outlineGradientLayer.type = .axial
            outlineGradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
            outlineGradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
            outlineGradientLayer.locations = CodexActivityIslandCompletionPalette.gradientLocations
            let color = edgeEmphasis == .confirmationReminder
                ? CodexActivityIslandConfirmationReminderContract.approvalColor
                : completionColor ?? CodexActivityIslandCompletionPalette.cyan
            outlineGradientLayer.colors = [color.withAlphaComponent(0.76).cgColor,
                                           color.cgColor, color.withAlphaComponent(0.76).cgColor]
        }
    }
}

final class ActivityIslandQuotaRingView: NSView {
    private let trackLayer = CAShapeLayer()
    private let progressLayer = CAShapeLayer()
    private let valueLabel = ActivitySingleLineTextView()
    private var remainingPercent: Int?
    private var hasConfiguredValue = false

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        for ringLayer in [trackLayer, progressLayer] {
            ringLayer.fillColor = NSColor.clear.cgColor
            ringLayer.lineWidth =
                CodexActivityIslandProgressBarGeometry
                .compactQuotaRingLineWidth
            ringLayer.lineCap = .round
            layer?.addSublayer(ringLayer)
        }

        valueLabel.font = activityFont(
            "AstaSans-Regular",
            size: 11.5,
            fallbackWeight: .regular
        )
        valueLabel.textColor = .white
        valueLabel.horizontalAlignment = .center
        addSubview(valueLabel)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func layout() {
        super.layout()
        let lineWidth =
            CodexActivityIslandProgressBarGeometry
            .compactQuotaRingLineWidth
        let ringRect = bounds.insetBy(
            dx: lineWidth / 2,
            dy: lineWidth / 2
        )
        let center = CGPoint(x: ringRect.midX, y: ringRect.midY)
        let radius = max(0, min(ringRect.width, ringRect.height) / 2)
        let startAngle = CGFloat.pi / 2
        let fraction = CGFloat(
            min(max(remainingPercent ?? 0, 0), 100)
        ) / 100

        let trackPath = CGPath(
            ellipseIn: ringRect,
            transform: nil
        )
        let progressPath = CGMutablePath()
        if fraction > 0 {
            progressPath.addArc(
                center: center,
                radius: radius,
                startAngle: startAngle,
                endAngle: startAngle - 2 * .pi * fraction,
                clockwise: true
            )
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackLayer.frame = bounds
        trackLayer.path = trackPath
        progressLayer.frame = bounds
        progressLayer.path = progressPath
        valueLabel.frame = bounds
        CATransaction.commit()
    }

    func update(remainingPercent: Int?) {
        let normalized = remainingPercent.map {
            min(max($0, 0), 100)
        }
        guard !hasConfiguredValue || self.remainingPercent != normalized
        else {
            return
        }
        hasConfiguredValue = true
        self.remainingPercent = normalized
        let color = CodexActivityQuotaRingContract.color(
            for: normalized
        )
        trackLayer.strokeColor = color.withAlphaComponent(
            CodexActivityQuotaRingContract.trackOpacity
        ).cgColor
        progressLayer.strokeColor = color.cgColor
        valueLabel.stringValue = normalized.map(String.init) ?? "—"
        needsLayout = true
    }
}

// One compositor clock and envelope for the waiting card and whole-island glow.
// Newly mounted/resumed layers join the current phase instead of starting over.
enum IslandConfirmationPulse {
    static let key = "console.confirmation-glow.pulse"
    static let duration: CFTimeInterval = 3
    static let riseStartFraction = 0.12
    static let peakFraction = 0.52
    static var riseDuration: CFTimeInterval { duration * (peakFraction - riseStartFraction) }
    private static let epoch = CACurrentMediaTime()
    static var restingRiseStart: CFTimeInterval { epoch + duration * riseStartFraction }

    @MainActor
    static func update(_ layer: CALayer?, animated: Bool, includesRadius: Bool = false, minimumOpacity: Double = 0,
                       riseStart: CFTimeInterval? = nil) {
        guard let layer else { return }
        guard animated else { layer.removeAnimation(forKey: key); return }
        guard layer.animation(forKey: key) == nil else { return }
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [minimumOpacity, minimumOpacity, 1, minimumOpacity, minimumOpacity]
        var animations = [opacity]
        if includesRadius {
            let radius = CAKeyframeAnimation(keyPath: "shadowRadius")
            let resting = CodexActivityIslandCompletionGlowGeometry.restingShadowRadius
            radius.values = [resting, resting, CodexActivityIslandCompletionGlowGeometry.peakShadowRadius, resting, resting]
            animations.append(radius)
        }
        for animation in animations {
            animation.keyTimes = [0, NSNumber(value: riseStartFraction), NSNumber(value: peakFraction), 0.92, 1]
            animation.duration = duration
            animation.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: 4)
        }
        let pulse = CAAnimationGroup()
        pulse.animations = animations
        pulse.duration = duration
        pulse.repeatCount = .infinity
        let cycleStart = riseStart.map { $0 - duration * riseStartFraction } ?? epoch
        pulse.beginTime = layer.convertTime(cycleStart, from: nil)
        layer.add(pulse, forKey: key)
    }
}

// Notch-only contour and breathing overrides; production sources stay intact.
extension ActivityIslandCompletionGlowView {
    var islandPulse: CAAnimationGroup? { violetGlowLayer.animation(forKey: IslandConfirmationPulse.key) as? CAAnimationGroup }
    func updateIslandConfirmationPulse(animated: Bool, riseStart: CFTimeInterval? = nil) {
        for layer in [violetGlowLayer, cyanGlowLayer] {
            layer.removeAnimation(forKey: AnimationKey.reveal)
            layer.removeAnimation(forKey: AnimationKey.breathRadius)
            IslandConfirmationPulse.update(layer, animated: !isHidden && animated, includesRadius: true, riseStart: riseStart)
        }
    }

    func setIslandContour(_ path: CGPath, duration: CFTimeInterval?) {
        let layers = [violetGlowLayer, cyanGlowLayer]
        let previous = layers.map { $0.presentation()?.path ?? $0.path }
        consoleContour = path
        needsLayout = true
        layoutSubtreeIfNeeded()
        for (layer, oldPath) in zip(layers, previous) {
            for key in ["path", "shadowPath"] {
                layer.removeAnimation(forKey: key)
                if let duration, let oldPath {
                    let animation = CABasicAnimation(keyPath: key)
                    animation.fromValue = oldPath; animation.toValue = path
                    animation.duration = duration
                    animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
                    layer.add(animation, forKey: key)
                }
            }
        }
    }
    func cancelIslandContourAnimations() {
        for layer in [violetGlowLayer, cyanGlowLayer] {
            layer.removeAnimation(forKey: "path")
            layer.removeAnimation(forKey: "shadowPath")
        }
    }
}
