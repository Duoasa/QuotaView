import AppKit
import CoreText
import MetalKit
import QuartzCore
import QuotaViewCore
import simd

struct CodexActivityRenderState: Equatable {
    let taskIdentity: CodexActivityTaskIdentity?
    let visualState: CodexActivityVisualState
    let approximateProgressFraction: Double?
    let windowTitle: String
    let statusTitle: String
    let operation: String
    let tokenUsageTitle: String?
    let completionReceiptStatus: String?
    let completionReceiptDetail: String?
    let completionQuotaRemainingPercent: Int?
    let isConfirmationReminderActive: Bool
    let accessibilityLabel: String

    init(
        taskIdentity: CodexActivityTaskIdentity? = nil,
        visualState: CodexActivityVisualState,
        approximateProgressFraction: Double?,
        windowTitle: String,
        statusTitle: String,
        operation: String,
        tokenUsageTitle: String? = nil,
        completionReceiptStatus: String? = nil,
        completionReceiptDetail: String? = nil,
        completionQuotaRemainingPercent: Int? = nil,
        isConfirmationReminderActive: Bool = false,
        accessibilityLabel: String
    ) {
        self.taskIdentity = taskIdentity
        self.visualState = visualState
        self.approximateProgressFraction = approximateProgressFraction
        self.windowTitle = windowTitle
        self.statusTitle = statusTitle
        self.operation = operation
        self.tokenUsageTitle = tokenUsageTitle
        self.completionReceiptStatus = completionReceiptStatus
        self.completionReceiptDetail = completionReceiptDetail
        self.completionQuotaRemainingPercent =
            completionQuotaRemainingPercent
        self.isConfirmationReminderActive =
            isConfirmationReminderActive
        self.accessibilityLabel = accessibilityLabel
    }
}

enum CodexActivityIslandPresentation: Int, CaseIterable {
    case expanded
    case compact

    static let panelInset: CGFloat = 10
    static let compactSurfaceSize = NSSize(width: 250, height: 52)
    static let compactOrbInset: CGFloat = 12
    static let compactTextGap: CGFloat = 14
    static let compactTitleFontSize: CGFloat = 14
    static let shadowRadius: CGFloat = 7
    static let shadowVerticalOffset: CGFloat = -2

    static var compactOrbDiameter: CGFloat {
        compactSurfaceSize.height - compactOrbInset * 2
    }

    static var compactOrbLeading: CGFloat {
        compactOrbInset
    }

    static var compactOrbCanvasSide: CGFloat {
        compactOrbDiameter / CGFloat(activityOrbSphereRadius)
    }

    var transitionDuration: TimeInterval {
        switch self {
        case .expanded: 0.30
        case .compact: 0.28
        }
    }

    func panelSize(for state: CodexActivityVisualState) -> NSSize {
        switch self {
        case .expanded:
            state.activityWindowSize
        case .compact:
            NSSize(
                width: Self.compactSurfaceSize.width
                    + Self.panelInset * 2,
                height: Self.compactSurfaceSize.height
                    + Self.panelInset * 2
            )
        }
    }
}

struct CodexActivityIslandGeometry {
    static let panelInset =
        CodexActivityIslandProgressBarGeometry.effectInset

    static func panelSize(
        presentation: CodexActivityIslandPresentation,
        state _: CodexActivityVisualState
    ) -> NSSize {
        switch presentation {
        case .expanded:
            return CodexActivityIslandProgressBarGeometry
                .expandedPanelSize(
                    windowTitle: "",
                    operation: "",
                    statusTitle: ""
                )
        case .compact:
            return CodexActivityIslandProgressBarGeometry
                .compactPanelSize(statusTitle: "")
        }
    }

    static func panelSize(
        presentation: CodexActivityIslandPresentation,
        renderState: CodexActivityRenderState
    ) -> NSSize {
        switch presentation {
        case .expanded:
            return CodexActivityIslandProgressBarGeometry
                .expandedPanelSize(
                    windowTitle: renderState.windowTitle,
                    operation: renderState.operation,
                    statusTitle: renderState.statusTitle
                )
        case .compact:
            return CodexActivityIslandProgressBarGeometry
                .compactPanelSize(
                    statusTitle: renderState.statusTitle
                )
        }
    }
}

struct CodexActivityIslandHoverTransparencyContract {
    static let restingAlpha: CGFloat = 1
    static let hoveredAlpha: CGFloat = 0.20
    static let transitionDuration: TimeInterval = 0.14

    static func visibleSurfaceFrame(
        panelFrame: NSRect,
        panelInset: CGFloat
    ) -> NSRect {
        panelFrame.insetBy(dx: panelInset, dy: panelInset)
    }
}

enum CodexActivityIslandEdgeEmphasis: Equatable {
    case none
    case completion
    case confirmationReminder
}

struct CodexActivityIslandConfirmationReminderContract {
    static let warningColor = NSColor(
        srgbRed: 1,
        green: 0.80,
        blue: 0,
        alpha: 1
    )
    static let revealDuration: CFTimeInterval = 0.20

    static func edgeEmphasis(
        visualState: CodexActivityVisualState,
        reminderActive: Bool,
        completionEffectAvailable: Bool
    ) -> CodexActivityIslandEdgeEmphasis {
        if visualState == .completed, completionEffectAvailable {
            return .completion
        }
        if visualState == .awaitingConfirmation, reminderActive {
            return .confirmationReminder
        }
        return .none
    }
}

struct CodexActivityIslandProgressBarGeometry {
    static let compactWhitespaceRetention: CGFloat = 0.60
    static let effectInset: CGFloat = 30
    static let textInset: CGFloat = 20
    static let verticalTextInset: CGFloat = 14
    static let expandedCornerRadius: CGFloat = 20
    static let columnGap: CGFloat = 14
    static let titleDetailGap: CGFloat = 4
    static let titleDotGap: CGFloat = 8
    static let titleFontSize: CGFloat = 12.5
    static let detailFontSize: CGFloat = 11.5
    static let statusFontSize: CGFloat = 15
    static let tokenUsageFontSize = detailFontSize
    static let completionStatusFontSize: CGFloat = 16
    static let completionDetailFontSize: CGFloat = 11
    static let completionQuotaValueFontSize: CGFloat = 28
    static let completionQuotaSymbolFontSize: CGFloat = 14
    static let completionLeftColumnWidth: CGFloat = 214
    static let completionRightColumnWidth: CGFloat = 128
    static let completionColumnGap: CGFloat = 20
    static let compactCompletionInset: CGFloat = 18
    static let compactCompletionGap: CGFloat = 12
    static let compactQuotaRingDiameter: CGFloat = 30
    static let compactQuotaRingLineWidth: CGFloat = 3.5
    static let maximumLeftColumnWidth: CGFloat = 210
    static let maximumStatusColumnWidth: CGFloat = 138

    static func compactPanelSize(
        statusTitle _: String
    ) -> NSSize {
        NSSize(
            width:
                fixedCompactSurfaceWidth
                + effectInset * 2,
            height:
                CodexActivityIslandPresentation
                .compactSurfaceSize.height
                + effectInset * 2
        )
    }

    static func compactSurfaceWidth(
        statusTitle _: String
    ) -> CGFloat {
        fixedCompactSurfaceWidth
    }

    static func compactQuotaRingFrame(
        in surfaceBounds: NSRect
    ) -> NSRect {
        let diameter = compactQuotaRingDiameter
        let capsuleRadius = surfaceBounds.height / 2
        let center = NSPoint(
            x: surfaceBounds.maxX - capsuleRadius,
            y: surfaceBounds.midY
        )
        return NSRect(
            x: center.x - diameter / 2,
            y: center.y - diameter / 2,
            width: diameter,
            height: diameter
        )
    }

    static var fixedCompactSurfaceWidth: CGFloat {
        let originalWidth =
            CodexActivityIslandPresentation.compactSurfaceSize.width
        let textWidth = maximumLocalizedCompactStatusTextWidth
        let originalWhitespace = max(0, originalWidth - textWidth)
        return textWidth
            + originalWhitespace * compactWhitespaceRetention
    }

    static var maximumLocalizedCompactStatusTextWidth: CGFloat {
        allLocalizedStatusTitles
            .map(compactStatusTextWidth)
            .max() ?? 0
    }

    static var allLocalizedStatusTitles: [String] {
        AppPreferences.Language.allCases.flatMap { language in
            let copy = CodexActivityCopy(language: language)
            return CodexActivityVisualState.allCases.map {
                copy.statusTitle(for: $0)
            }
        }
    }

    static func compactStatusTextWidth(
        for text: String
    ) -> CGFloat {
        min(
            measuredWidth(
                for: text,
                font: activityFont(
                    "AstaSans-SemiBold",
                    size:
                        CodexActivityIslandPresentation
                        .compactTitleFontSize,
                    fallbackWeight: .semibold
                )
            ),
            CodexActivityIslandPresentation.compactSurfaceSize.width
        )
    }

    static var maximumExpandedPanelWidth: CGFloat {
        textInset * 2
            + maximumLeftColumnWidth
            + columnGap
            + maximumStatusColumnWidth
            + effectInset * 2
    }

    static var expandedSurfaceHeight: CGFloat {
        activitySupportingLineHeight * 2
            + titleDetailGap
            + verticalTextInset * 2
    }

    static var expandedPanelHeight: CGFloat {
        expandedSurfaceHeight
            + effectInset * 2
    }

    static func expandedPanelSize(
        windowTitle _: String,
        operation _: String,
        statusTitle _: String
    ) -> NSSize {
        return NSSize(
            width: maximumExpandedPanelWidth,
            height: expandedPanelHeight
        )
    }

    private static func measuredWidth(
        for text: String,
        font: NSFont
    ) -> CGFloat {
        NSAttributedString(
            string: text,
            attributes: [.font: font]
        ).size().width
    }
}

struct CodexActivityIslandCompletionGlowGeometry {
    static let sourceInset: CGFloat = 1.25
    static let outlineWidth: CGFloat = 1
    static let restingShadowRadius: CGFloat = 5.5
    static let peakShadowRadius: CGFloat = 9.5
    static let shadowOpacity: Float = 1

    static func sourceRect(in islandRect: NSRect) -> NSRect {
        islandRect.insetBy(dx: sourceInset, dy: sourceInset)
    }

    static func sourceCornerRadius(
        in islandRect: NSRect,
        islandCornerRadius: CGFloat
    ) -> CGFloat {
        max(
            0,
            min(islandCornerRadius, islandRect.height / 2)
                - sourceInset
        )
    }
}

struct CodexActivityIslandTextContrast {
    static let progressTaskTitleColor =
        NSColor(calibratedWhite: 0.88, alpha: 1)
    static let progressOperationColor =
        NSColor(calibratedWhite: 0.76, alpha: 1)
    static let operationShimmerShoulderAlpha: CGFloat = 0.24
    static let operationShimmerPeakAlpha: CGFloat = 1
    static let statusDotBorderWidth: CGFloat = 0.5
    static let statusDotBorderColor =
        NSColor.black.withAlphaComponent(0.82)
}

private extension CodexActivityVisualState {
    var activityWindowSize: NSSize {
        switch self {
        case .standby:
            NSSize(width: 304, height: 112)
        case .completed, .error:
            NSSize(width: 374, height: 132)
        case .disconnectedCodex, .unavailable:
            NSSize(width: 390, height: 132)
        case .thinking,
             .working,
             .compactingContext,
             .awaitingConfirmation:
            NSSize(width: 444, height: 152)
        }
    }

    var activityAccentColor: NSColor {
        switch self {
        case .disconnectedCodex:
            NSColor(
                calibratedRed: 0.48,
                green: 0.54,
                blue: 0.64,
                alpha: 1
            )
        case .standby:
            NSColor(
                calibratedRed: 0.44,
                green: 0.52,
                blue: 0.68,
                alpha: 1
            )
        case .thinking:
            NSColor(
                calibratedRed: 0.55,
                green: 0.42,
                blue: 1.00,
                alpha: 1
            )
        case .working:
            NSColor(
                calibratedRed: 0.17,
                green: 0.83,
                blue: 0.91,
                alpha: 1
            )
        case .compactingContext:
            NSColor(calibratedWhite: 0.98, alpha: 1)
        case .awaitingConfirmation:
            NSColor(
                calibratedRed: 1.00,
                green: 0.70,
                blue: 0.24,
                alpha: 1
            )
        case .completed:
            NSColor(
                calibratedRed: 0.43,
                green: 0.89,
                blue: 1.00,
                alpha: 1
            )
        case .error:
            NSColor(
                calibratedRed: 1.00,
                green: 0.31,
                blue: 0.37,
                alpha: 1
            )
        case .unavailable:
            NSColor(
                calibratedRed: 0.55,
                green: 0.57,
                blue: 0.61,
                alpha: 1
            )
        }
    }

    var activityShowsOperationSweep: Bool {
        switch self {
        case .thinking, .working, .compactingContext:
            true
        case .disconnectedCodex,
             .standby,
             .awaitingConfirmation,
             .completed,
             .error,
             .unavailable:
            false
        }
    }

    var activityOrbStyle: ActivityOrbStyle {
        switch self {
        case .disconnectedCodex:
            ActivityOrbStyle(
                primary: activityRGBA(0.13, 0.17, 0.24),
                secondary: activityRGBA(0.28, 0.34, 0.44),
                accent: activityRGBA(0.48, 0.57, 0.70),
                speed: 0.032,
                speedFloor: 0.24,
                motionCycle: 17.0,
                tempo: 0.44,
                response: 1.15,
                energy: 0.46,
                turbulence: 0.08,
                pulse: 0.06,
                desaturation: 0.34,
                volume: 0.38,
                refraction: 0.42
            )
        case .standby:
            ActivityOrbStyle(
                primary: activityRGBA(0.12, 0.23, 0.42),
                secondary: activityRGBA(0.25, 0.35, 0.58),
                accent: activityRGBA(0.44, 0.56, 0.75),
                speed: 0.045,
                speedFloor: 0.28,
                motionCycle: 16.0,
                tempo: 0.58,
                response: 1.25,
                energy: 0.50,
                turbulence: 0.12,
                pulse: 0.05,
                desaturation: 0.18,
                volume: 0.44,
                refraction: 0.50
            )
        case .thinking:
            ActivityOrbStyle(
                primary: activityRGBA(0.20, 0.12, 0.68),
                secondary: activityRGBA(0.50, 0.23, 0.88),
                accent: activityRGBA(0.34, 0.57, 1.00),
                speed: 0.14,
                speedFloor: 0.22,
                motionCycle: 11.0,
                tempo: 0.82,
                response: 1.55,
                energy: 0.86,
                turbulence: 0.34,
                pulse: 0.18,
                desaturation: 0,
                volume: 0.76,
                refraction: 0.74
            )
        case .working:
            ActivityOrbStyle(
                primary: activityRGBA(0.04, 0.30, 0.78),
                secondary: activityRGBA(0.02, 0.65, 0.90),
                accent: activityRGBA(0.28, 0.94, 0.84),
                speed: 0.24,
                speedFloor: 0.18,
                motionCycle: 8.5,
                tempo: 1.05,
                response: 1.85,
                energy: 1.02,
                turbulence: 0.58,
                pulse: 0.22,
                desaturation: 0,
                volume: 0.94,
                refraction: 0.84
            )
        case .compactingContext:
            ActivityOrbStyle(
                primary: activityRGBA(0.50, 0.56, 0.66),
                secondary: activityRGBA(0.82, 0.86, 0.93),
                accent: activityRGBA(1.00, 1.00, 1.00),
                speed: 0.16,
                speedFloor: 0.20,
                motionCycle: 9.5,
                tempo: 0.90,
                response: 1.80,
                energy: 1.02,
                turbulence: 0.48,
                pulse: 0.30,
                desaturation: 0.12,
                volume: 0.94,
                refraction: 0.90,
                compression: 1
            )
        case .awaitingConfirmation:
            ActivityOrbStyle(
                primary: activityRGBA(0.55, 0.21, 0.02),
                secondary: activityRGBA(0.95, 0.46, 0.05),
                accent: activityRGBA(1.00, 0.78, 0.22),
                speed: 0.075,
                speedFloor: 0.18,
                motionCycle: 12.0,
                tempo: 0.72,
                response: 1.45,
                energy: 0.92,
                turbulence: 0.20,
                pulse: 0.46,
                desaturation: 0,
                volume: 0.68,
                refraction: 0.82
            )
        case .completed:
            ActivityOrbStyle(
                primary: activityRGBA(0.18, 0.12, 0.52),
                secondary: activityRGBA(0.26, 0.48, 0.88),
                accent: activityRGBA(0.43, 0.89, 1.00),
                speed: 0.055,
                speedFloor: 0.20,
                motionCycle: 13.0,
                tempo: 0.55,
                response: 1.20,
                energy: 0.82,
                turbulence: 0.12,
                pulse: 0.12,
                desaturation: 0,
                volume: 0.62,
                refraction: 0.68
            )
        case .error:
            ActivityOrbStyle(
                primary: activityRGBA(0.55, 0.01, 0.05),
                secondary: activityRGBA(0.92, 0.08, 0.14),
                accent: activityRGBA(1.00, 0.36, 0.22),
                speed: 0.13,
                speedFloor: 0.22,
                motionCycle: 8.0,
                tempo: 0.92,
                response: 2.10,
                energy: 0.96,
                turbulence: 0.62,
                pulse: 0.28,
                desaturation: 0,
                volume: 0.82,
                refraction: 0.62
            )
        case .unavailable:
            ActivityOrbStyle(
                primary: activityRGBA(0.23, 0.25, 0.30),
                secondary: activityRGBA(0.36, 0.38, 0.43),
                accent: activityRGBA(0.50, 0.53, 0.58),
                speed: 0.015,
                speedFloor: 0.15,
                motionCycle: 18.0,
                tempo: 0.28,
                response: 1.00,
                energy: 0.36,
                turbulence: 0.03,
                pulse: 0,
                desaturation: 0.88,
                volume: 0.24,
                refraction: 0.18
            )
        }
    }
}

private func activityExpansionProgress(
    surfaceHeight: CGFloat,
    expandedSurfaceHeight: CGFloat
) -> CGFloat {
    let compactHeight =
        CodexActivityIslandPresentation.compactSurfaceSize.height
    let range = max(expandedSurfaceHeight - compactHeight, 1)
    return min(max((surfaceHeight - compactHeight) / range, 0), 1)
}

private func activityInterpolate(
    from start: CGFloat,
    to end: CGFloat,
    progress: CGFloat
) -> CGFloat {
    start + (end - start) * progress
}

func activityIslandSurfaceCornerRadius(
    style: AppPreferences.CodexActivityIslandStyle,
    surfaceHeight: CGFloat,
    expansionProgress: CGFloat
) -> CGFloat {
    let defaultRadius = min(34, surfaceHeight / 2)
    guard style == .progressBar else { return defaultRadius }

    let compactRadius =
        CodexActivityIslandPresentation.compactSurfaceSize.height / 2
    let radius = activityInterpolate(
        from: compactRadius,
        to:
            CodexActivityIslandProgressBarGeometry
            .expandedCornerRadius,
        progress: expansionProgress
    )
    return min(surfaceHeight / 2, radius)
}

struct CodexActivityIslandTextGeometry {
    static func expandedStatusAlignment(
        style: AppPreferences.CodexActivityIslandStyle
    ) -> ActivityTextHorizontalAlignment {
        style == .progressBar ? .trailing : .leading
    }

    static func textStart(
        style: AppPreferences.CodexActivityIslandStyle,
        compactStart: CGFloat,
        expandedStart: CGFloat,
        expansionProgress: CGFloat
    ) -> CGFloat {
        let resolvedExpandedStart =
            style == .progressBar
            ? CodexActivityIslandProgressBarGeometry.textInset
            : expandedStart
        return compactStart
            + (resolvedExpandedStart - compactStart) * expansionProgress
    }

    static func compactTitleFrame(
        style: AppPreferences.CodexActivityIslandStyle,
        surfaceWidth: CGFloat
    ) -> NSRect {
        let leading =
            style == .progressBar
            ? 0
            : CodexActivityIslandPresentation.compactOrbLeading
                + CodexActivityIslandPresentation.compactOrbDiameter
        return NSRect(
            x: leading,
            y: 0,
            width: max(0, surfaceWidth - leading),
            height: CodexActivityIslandPresentation.compactSurfaceSize.height
        )
    }
}

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

private func activityTruncatedLine(
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

private final class ActivitySingleLineTextView: NSView {
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

private struct ActivityExpandedTextLayout {
    var kickerY: CGFloat
    var titleY: CGFloat
    var detailY: CGFloat
    var statusDotY: CGFloat
}

private struct ActivityProgressTextLayout {
    var titleY: CGFloat
    var detailY: CGFloat
    var statusDotY: CGFloat
}

private let activitySupportingLineHeight: CGFloat = 18
private let activityStatusLineHeight: CGFloat = 26
private let activityTextRowGap: CGFloat = 4
private let activityStatusDotSide: CGFloat = 6

private func activityCenteredTextLayout(
    surfaceHeight: CGFloat
) -> ActivityExpandedTextLayout {
    let stackHeight =
        activitySupportingLineHeight * 2
        + activityStatusLineHeight
        + activityTextRowGap * 2
    let stackBottom = (surfaceHeight - stackHeight) / 2
    let detailY = stackBottom
    let titleY =
        detailY + activitySupportingLineHeight + activityTextRowGap
    let kickerY =
        titleY + activityStatusLineHeight + activityTextRowGap
    return ActivityExpandedTextLayout(
        kickerY: kickerY,
        titleY: titleY,
        detailY: detailY,
        statusDotY:
            kickerY
            + (activitySupportingLineHeight - activityStatusDotSide) / 2
    )
}

private func activityProgressTextLayout(
    surfaceHeight: CGFloat
) -> ActivityProgressTextLayout {
    let stackHeight =
        activitySupportingLineHeight * 2
        + CodexActivityIslandProgressBarGeometry.titleDetailGap
    let stackBottom = (surfaceHeight - stackHeight) / 2
    let detailY = stackBottom
    let titleY =
        detailY
        + activitySupportingLineHeight
        + CodexActivityIslandProgressBarGeometry.titleDetailGap
    return ActivityProgressTextLayout(
        titleY: titleY,
        detailY: detailY,
        statusDotY:
            titleY
            + (activitySupportingLineHeight - activityStatusDotSide) / 2
    )
}

private func activityRGBA(
    _ red: Float,
    _ green: Float,
    _ blue: Float,
    _ alpha: Float = 1
) -> SIMD4<Float> {
    SIMD4<Float>(red, green, blue, alpha)
}

private struct ActivityOrbStyle {
    var primary: SIMD4<Float>
    var secondary: SIMD4<Float>
    var accent: SIMD4<Float>
    var speed: Float
    var speedFloor: Float
    var motionCycle: Float
    var tempo: Float
    var response: Float
    var energy: Float
    var turbulence: Float
    var pulse: Float
    var desaturation: Float
    var volume: Float
    var refraction: Float
    var compression: Float = 0

    mutating func approach(
        _ target: ActivityOrbStyle,
        factor: Float
    ) {
        primary += (target.primary - primary) * factor
        secondary += (target.secondary - secondary) * factor
        accent += (target.accent - accent) * factor
        speed += (target.speed - speed) * factor
        speedFloor += (target.speedFloor - speedFloor) * factor
        motionCycle += (target.motionCycle - motionCycle) * factor
        tempo += (target.tempo - tempo) * factor
        response += (target.response - response) * factor
        energy += (target.energy - energy) * factor
        turbulence += (target.turbulence - turbulence) * factor
        pulse += (target.pulse - pulse) * factor
        desaturation += (target.desaturation - desaturation) * factor
        volume += (target.volume - volume) * factor
        refraction += (target.refraction - refraction) * factor
        compression += (target.compression - compression) * factor
    }
}

private func activityMotionSpeedMultiplier(
    elapsed: Float,
    speedFloor: Float,
    cycle: Float
) -> Float {
    let safeCycle = max(cycle, 0.001)
    let position =
        max(elapsed, 0).truncatingRemainder(dividingBy: safeCycle)
        / safeCycle
    let envelope = 0.5 - 0.5 * cos(position * 2 * .pi)
    let floor = min(max(speedFloor, 0), 1)
    return floor + (1 - floor) * envelope
}

private func activityCompressionPulse(
    elapsed: Float,
    cycle: Float
) -> Float {
    let safeCycle = max(cycle, 0.001)
    let position =
        max(elapsed, 0).truncatingRemainder(dividingBy: safeCycle)
        / safeCycle
    return 0.5 - 0.5 * cos(position * 2 * .pi)
}

private func activityCompressionBounce(
    elapsed: Float,
    cycle: Float
) -> Float {
    let safeCycle = max(cycle, 0.001)
    let phase =
        max(elapsed, 0).truncatingRemainder(dividingBy: safeCycle)
        / safeCycle

    func raisedCosinePulse(center: Float, halfWidth: Float) -> Float {
        let distance = abs(phase - center)
        guard distance < halfWidth else { return 0 }
        return 0.5 + 0.5 * cos(.pi * distance / halfWidth)
    }

    let primary = raisedCosinePulse(center: 0.34, halfWidth: 0.20)
    let rebound =
        raisedCosinePulse(center: 0.64, halfWidth: 0.14) * 0.46
    return max(primary, rebound)
}

private struct ActivityOrbUniforms {
    var resolution: SIMD2<Float>
    var time: Float
    var motionPhase: Float
    var energy: Float
    var turbulence: Float
    var pulse: Float
    var desaturation: Float
    var volume: Float
    var refraction: Float
    var tempo: Float
    var motionEnergy: Float
    var compression: Float
    var compressionPulse: Float
    var compressionBounce: Float
    var reserved1: Float
    var primary: SIMD4<Float>
    var secondary: SIMD4<Float>
    var accent: SIMD4<Float>
}

private let activityOrbMotionSpeedScale: Float = 16.0
private let activityOrbRotationPhaseGain: Float = 1.45
private let activityOrbFluidPhaseGain: Float = 2.80
private let activityOrbSurfacePhaseGain: Float = 2.20
private let activityCompressionCycle: Float = 3.2
private let activityOrbSphereRadius: Float = 0.535

private let activityOrbShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

struct ActivityOrbUniforms {
    float2 resolution;
    float time;
    float motionPhase;

    float energy;
    float turbulence;
    float pulse;
    float desaturation;

    float volume;
    float refraction;
    float tempo;
    float motionEnergy;

    float compression;
    float compressionPulse;
    float compressionBounce;
    float reserved1;

    float4 primary;
    float4 secondary;
    float4 accent;
};

vertex VertexOut activityOrbVertex(uint vertexID [[vertex_id]]) {
    const float2 positions[3] = {
        float2(-1.0, -1.0),
        float2( 3.0, -1.0),
        float2(-1.0,  3.0)
    };

    VertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.uv = positions[vertexID] * 0.5 + 0.5;
    return out;
}

float activityHash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float activityValueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(
            activityHash21(i),
            activityHash21(i + float2(1.0, 0.0)),
            u.x
        ),
        mix(
            activityHash21(i + float2(0.0, 1.0)),
            activityHash21(i + 1.0),
            u.x
        ),
        u.y
    );
}

float activitySoftBand(float distance, float width) {
    float normalized = distance / max(width, 0.0001);
    return exp(-normalized * normalized);
}

float2 activityRotate2D(float2 value, float angle) {
    float cosine = cos(angle);
    float sine = sin(angle);
    return float2(
        value.x * cosine - value.y * sine,
        value.x * sine + value.y * cosine
    );
}

float3 activityRotateVolume(float3 value, float time) {
    value.xz = activityRotate2D(value.xz, time * 0.31 + 0.42);
    value.xy = activityRotate2D(value.xy, -time * 0.23 - 0.18);
    value.yz = activityRotate2D(value.yz, time * 0.17 + 0.28);
    return value;
}

float activityFluidField(
    float3 point,
    float time,
    float turbulence
) {
    float3 warped = point;
    warped.x += sin(point.y * 3.2 + time * 1.10) *
        (0.10 + turbulence * 0.10);
    warped.y += sin(point.z * 3.8 - time * 0.84) *
        (0.09 + turbulence * 0.12);
    warped.z += cos(point.x * 4.1 + time * 0.72) *
        (0.08 + turbulence * 0.11);

    float broad =
        sin(warped.x * 3.8 + time * 0.55) +
        sin(warped.y * 4.4 - time * 0.47) +
        sin(warped.z * 4.0 + time * 0.38);
    float detail =
        sin((warped.x + warped.y) * 7.2 - time * 0.92) +
        cos((warped.y - warped.z) * 6.1 + time * 0.68);

    return broad * 0.30 + detail * 0.13;
}

fragment float4 activityOrbFragment(
    VertexOut in [[stage_in]],
    constant ActivityOrbUniforms &u [[buffer(0)]]
) {
    float2 p = (in.uv - 0.5) * 2.0;
    p.x *= u.resolution.x / max(u.resolution.y, 1.0);

    float rotationTime =
        u.motionPhase * \(activityOrbRotationPhaseGain);
    float fluidTime =
        u.motionPhase * \(activityOrbFluidPhaseGain);
    float surfaceTime =
        u.motionPhase * \(activityOrbSurfacePhaseGain);
    float radius = length(p);
    float angle = atan2(p.y, p.x);
    float compressionAmount =
        u.compression *
        (
            0.20 +
            u.compressionPulse * 0.62 +
            u.compressionBounce * 0.28
        );
    float wholeSphereCompression =
        u.compression * u.compressionBounce;
    float directionalPressure =
        0.5 +
        0.5 * cos(angle * 2.0 + u.time * 0.42);
    float animatedTurbulence =
        u.turbulence * (0.84 + u.motionEnergy * 0.20);
    float breathing =
        sin(u.time * u.tempo) *
        (0.006 + u.pulse * 0.010);
    float sphereRadius =
        \(activityOrbSphereRadius) +
        breathing -
        compressionAmount *
        (0.034 + directionalPressure * 0.018) -
        wholeSphereCompression * 0.050;
    float sphereDistance = abs(radius - sphereRadius);

    if (radius > sphereRadius + 0.18) {
        return float4(0.0);
    }

    float3 primary = u.primary.rgb;
    float3 secondary = u.secondary.rgb;
    float3 accent = u.accent.rgb;

    float normalizedRadius = radius / max(sphereRadius, 0.001);
    float inside = 1.0 - step(1.0, normalizedRadius);
    float zExtent = sqrt(
        max(0.0, 1.0 - normalizedRadius * normalizedRadius)
    );
    float3 normal = normalize(float3(
        p / max(sphereRadius, 0.001),
        zExtent
    ));

    float fresnel = pow(
        saturate(1.0 - max(normal.z, 0.0)),
        2.25
    );
    float rim = smoothstep(0.10, 0.96, fresnel);
    float3 keyLight = normalize(float3(-0.48, 0.64, 0.82));
    float specular = pow(
        saturate(dot(normal, keyLight)),
        38.0
    );

    float3 volumeColor = float3(0.0);
    float volumeAlpha = 0.0;
    constexpr int sampleCount = 20;

    for (int index = 0; index < sampleCount; ++index) {
        float samplePosition =
            (float(index) + 0.5) / float(sampleCount);
        float sampleZ = mix(-zExtent, zExtent, samplePosition);
        float3 samplePoint = float3(
            p / max(sphereRadius, 0.001),
            sampleZ
        );
        float inwardScale =
            1.0 +
            compressionAmount *
            (
                0.18 +
                0.16 * (1.0 - abs(sampleZ))
            );
        samplePoint.xy *= inwardScale;
        samplePoint.z *= 1.0 + compressionAmount * 0.12;
        samplePoint = activityRotateVolume(
            samplePoint,
            rotationTime *
                (0.72 + animatedTurbulence * 0.42)
        );

        float field = activityFluidField(
            samplePoint * (1.16 + animatedTurbulence * 0.22),
            fluidTime,
            animatedTurbulence
        );
        float ribbon = exp(
            -abs(field) * (5.6 - u.volume * 1.8)
        );
        float filament = exp(
            -abs(
                field +
                sin(
                    samplePoint.x * 6.0 -
                    samplePoint.z * 4.0 +
                    fluidTime
                ) * 0.20
            ) * 12.0
        );
        float depthFade =
            0.46 +
            0.54 * sin(samplePosition * M_PI_F);
        float density =
            (ribbon * 0.62 + filament * 0.52) *
            depthFade *
            (0.018 + u.volume * 0.020) *
            (1.0 + compressionAmount * 0.46);

        float colorPhase = fract(
            samplePosition * 0.78 +
            field * 0.15 +
            angle / (2.0 * M_PI_F) -
            fluidTime * 0.035
        );
        float3 sampleColor =
            colorPhase < 0.5
            ? mix(primary, secondary, colorPhase * 2.0)
            : mix(
                secondary,
                accent,
                (colorPhase - 0.5) * 2.0
            );

        float remaining = 1.0 - volumeAlpha;
        volumeColor +=
            remaining *
            sampleColor *
            density *
            (1.65 + u.energy * 1.12);
        volumeAlpha += remaining * density;
    }

    volumeColor *= inside;
    volumeAlpha *= inside;

    float normalizedX = p.x / max(sphereRadius, 0.001);
    float normalizedY = p.y / max(sphereRadius, 0.001);
    float projectedWaveA =
        normalizedY -
        sin(
            normalizedX * (4.2 + animatedTurbulence * 1.8) +
            surfaceTime * 1.55 +
            zExtent * 2.1
        ) * (0.17 + animatedTurbulence * 0.08);
    float projectedWaveB =
        normalizedX +
        cos(
            normalizedY * (4.8 + animatedTurbulence * 1.2) -
            surfaceTime * 1.12 -
            zExtent * 1.7
        ) * (0.15 + animatedTurbulence * 0.07);
    float projectedRibbonA = activitySoftBand(
        projectedWaveA,
        0.065 + animatedTurbulence * 0.020
    );
    float projectedRibbonB = activitySoftBand(
        projectedWaveB,
        0.080 + animatedTurbulence * 0.018
    );
    float projectedRibbon =
        inside *
        (projectedRibbonA * 0.72 + projectedRibbonB * 0.44) *
        (0.38 + zExtent * 0.62);
    float inwardFront = mix(
        0.92,
        0.18,
        u.compressionPulse
    );
    float inwardBand =
        exp(
            -abs(normalizedRadius - inwardFront) *
            (16.0 + u.compressionPulse * 8.0)
        ) *
        inside *
        u.compression;
    float compressedCore =
        exp(-normalizedRadius * 5.2) *
        inside *
        u.compression *
        u.compressionPulse;
    projectedRibbon +=
        inwardBand *
        (0.36 + u.compressionPulse * 0.28);
    float projectedPhase =
        0.5 +
        0.5 * sin(
            angle * 2.4 -
            surfaceTime * 1.3 +
            zExtent * 3.4
        );
    float3 projectedColor = mix(
        mix(primary, secondary, projectedPhase),
        accent,
        saturate(
            projectedRibbonB * 0.44 +
            inwardBand * 0.72 +
            compressedCore * 0.26
        )
    );

    float chromaRed = activitySoftBand(
        abs(radius - sphereRadius - 0.006 * u.refraction),
        0.012 + u.refraction * 0.005
    );
    float chromaGreen = activitySoftBand(
        abs(radius - sphereRadius),
        0.011
    );
    float chromaBlue = activitySoftBand(
        abs(radius - sphereRadius + 0.008 * u.refraction),
        0.014 + u.refraction * 0.004
    );
    float3 chromaticRim = float3(
        chromaRed,
        chromaGreen,
        chromaBlue
    );
    chromaticRim *= mix(
        primary,
        accent,
        0.5 +
            0.5 * sin(angle * 2.0 - surfaceTime * 1.2)
    );

    float caustic =
        pow(
            max(
                0.0,
                0.5 +
                0.5 *
                cos(
                    angle * 1.4 -
                    surfaceTime * 1.8 -
                    0.7
                )
            ),
            18.0
        ) *
        activitySoftBand(sphereDistance, 0.026);
    float halo = exp(
        -sphereDistance * (12.0 - u.energy * 1.8)
    );

    float glassTint = inside * (
        0.035 +
        rim * 0.14 +
        specular * 0.24
    );
    float3 glassColor =
        mix(primary, accent, fresnel) * glassTint +
        float3(0.72, 0.86, 1.0) * specular * 0.54;

    float3 color =
        volumeColor * (1.18 + u.volume * 0.74) +
        projectedColor *
            projectedRibbon *
            (0.32 + u.volume * 0.64) +
        mix(primary, secondary, projectedPhase) *
            inside *
            zExtent *
            0.035 *
            u.volume +
        glassColor +
        chromaticRim * (0.34 + u.refraction * 0.50) +
        accent * caustic * (0.60 + u.energy * 0.72) +
        mix(secondary, accent, 0.76) *
            (
                inwardBand * 0.34 +
                compressedCore * 0.24
            ) +
        mix(primary, secondary, 0.5) *
            halo *
            0.075 *
            u.energy;

    float luma = dot(color, float3(0.299, 0.587, 0.114));
    color = mix(color, float3(luma), saturate(u.desaturation));

    float alpha =
        volumeAlpha * (0.82 + u.volume * 0.42) +
        projectedRibbon * (0.18 + u.volume * 0.28) +
        inwardBand * 0.12 +
        compressedCore * 0.08 +
        rim * inside * (0.24 + u.refraction * 0.30) +
        specular * inside * 0.48 +
        max(max(chromaRed, chromaGreen), chromaBlue) * 0.64 +
        halo * 0.10 * u.energy;

    alpha *= 1.0 - smoothstep(
        sphereRadius + 0.12,
        sphereRadius + 0.18,
        radius
    );
    color *=
        0.94 +
        0.06 *
        sin(u.time * u.tempo * 0.78) *
        u.pulse;

    return float4(max(color, 0.0), saturate(alpha));
}
"""

private final class ActivityOrbRenderer: NSObject, MTKViewDelegate {
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let startTime = CACurrentMediaTime()
    private var lastFrameTime = CACurrentMediaTime()

    private var currentStyle: ActivityOrbStyle
    private var targetStyle: ActivityOrbStyle
    private var activeState: CodexActivityVisualState
    private var reduceMotion = false
    private var stateElapsed: Float = 0
    private var motionPhase: Float = 0

    init?(
        view: MTKView,
        initialState: CodexActivityVisualState
    ) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue()
        else {
            return nil
        }

        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(
            red: 0,
            green: 0,
            blue: 0,
            alpha: 0
        )
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.framebufferOnly = true
        view.wantsLayer = true
        view.layer?.isOpaque = false

        do {
            let library = try device.makeLibrary(
                source: activityOrbShaderSource,
                options: nil
            )
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(
                name: "activityOrbVertex"
            )
            descriptor.fragmentFunction = library.makeFunction(
                name: "activityOrbFragment"
            )
            descriptor.colorAttachments[0].pixelFormat =
                view.colorPixelFormat

            if let attachment = descriptor.colorAttachments[0] {
                attachment.isBlendingEnabled = true
                attachment.sourceRGBBlendFactor = .sourceAlpha
                attachment.destinationRGBBlendFactor =
                    .oneMinusSourceAlpha
                attachment.sourceAlphaBlendFactor = .one
                attachment.destinationAlphaBlendFactor =
                    .oneMinusSourceAlpha
            }

            pipelineState = try device.makeRenderPipelineState(
                descriptor: descriptor
            )
        } catch {
            return nil
        }

        self.commandQueue = commandQueue
        currentStyle = initialState.activityOrbStyle
        targetStyle = initialState.activityOrbStyle
        activeState = initialState
        super.init()
        view.delegate = self
    }

    func setState(_ state: CodexActivityVisualState) {
        if state != activeState {
            activeState = state
            stateElapsed = 0
        }
        targetStyle = state.activityOrbStyle
        if reduceMotion {
            currentStyle = targetStyle
        }
    }

    func setReduceMotion(_ enabled: Bool, in view: MTKView) {
        guard reduceMotion != enabled else { return }
        reduceMotion = enabled
        if enabled {
            currentStyle = targetStyle
            view.isPaused = true
            view.enableSetNeedsDisplay = true
            view.needsDisplay = true
        } else {
            stateElapsed = 0
            lastFrameTime = CACurrentMediaTime()
            view.enableSetNeedsDisplay = false
            view.isPaused = false
        }
    }

    func mtkView(
        _ view: MTKView,
        drawableSizeWillChange size: CGSize
    ) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor =
                view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: renderPassDescriptor
              )
        else {
            return
        }

        let now = CACurrentMediaTime()
        let delta = Float(min(now - lastFrameTime, 1.0 / 15.0))
        lastFrameTime = now

        if reduceMotion {
            currentStyle = targetStyle
        } else {
            let transitionFactor = min(
                1,
                delta * max(0.4, targetStyle.response)
            )
            currentStyle.approach(
                targetStyle,
                factor: transitionFactor
            )
            stateElapsed += delta
            let speedMultiplier = activityMotionSpeedMultiplier(
                elapsed: stateElapsed,
                speedFloor: currentStyle.speedFloor,
                cycle: currentStyle.motionCycle
            )
            motionPhase +=
                delta *
                currentStyle.speed *
                speedMultiplier *
                activityOrbMotionSpeedScale
            if motionPhase > 4096 {
                motionPhase.formTruncatingRemainder(dividingBy: 4096)
            }
        }

        let motionEnergy = reduceMotion
            ? Float(0)
            : activityMotionSpeedMultiplier(
                elapsed: stateElapsed,
                speedFloor: 0,
                cycle: currentStyle.motionCycle
            )
        let compressionPulse = reduceMotion
            ? Float(0.72)
            : activityCompressionPulse(
                elapsed: stateElapsed,
                cycle: activityCompressionCycle
            )
        let compressionBounce = reduceMotion
            ? Float(0.68)
            : activityCompressionBounce(
                elapsed: stateElapsed,
                cycle: activityCompressionCycle
            )

        var uniforms = ActivityOrbUniforms(
            resolution: SIMD2<Float>(
                Float(max(view.drawableSize.width, 1)),
                Float(max(view.drawableSize.height, 1))
            ),
            time: reduceMotion ? 0.35 : Float(now - startTime),
            motionPhase: motionPhase,
            energy: currentStyle.energy,
            turbulence: reduceMotion
                ? 0.04
                : currentStyle.turbulence,
            pulse: reduceMotion ? 0 : currentStyle.pulse,
            desaturation: currentStyle.desaturation,
            volume: currentStyle.volume,
            refraction: currentStyle.refraction,
            tempo: reduceMotion ? 0 : currentStyle.tempo,
            motionEnergy: motionEnergy,
            compression: currentStyle.compression,
            compressionPulse: compressionPulse,
            compressionBounce: compressionBounce,
            reserved1: 0,
            primary: currentStyle.primary,
            secondary: currentStyle.secondary,
            accent: currentStyle.accent
        )

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentBytes(
            &uniforms,
            length: MemoryLayout<ActivityOrbUniforms>.stride,
            index: 0
        )
        encoder.drawPrimitives(
            type: .triangle,
            vertexStart: 0,
            vertexCount: 3
        )
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

private final class ActivityMetalOrbView: MTKView {
    private var renderer: ActivityOrbRenderer?

    init(
        frame: NSRect,
        initialState: CodexActivityVisualState
    ) {
        super.init(
            frame: frame,
            device: MTLCreateSystemDefaultDevice()
        )
        renderer = ActivityOrbRenderer(
            view: self,
            initialState: initialState
        )
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setState(_ state: CodexActivityVisualState) {
        renderer?.setState(state)
        if isPaused {
            needsDisplay = true
        }
    }

    func setReduceMotion(_ enabled: Bool) {
        renderer?.setReduceMotion(enabled, in: self)
    }

    func redrawIfPaused() {
        if isPaused {
            needsDisplay = true
        }
    }
}

private final class ActivitySelectableOrbView: NSView {
    private let particleView: ActivityMetalOrbView
    private var rippleGlowView: ActivityRippleGlowMetalView?
    private var activeView: NSView
    private var state: CodexActivityVisualState
    private var animation: AppPreferences.CodexActivityOrbAnimation
    private var reduceMotion = false
    private var playbackEnabled = true

    override var isOpaque: Bool { false }

    init(
        frame: NSRect,
        initialState: CodexActivityVisualState,
        animation: AppPreferences.CodexActivityOrbAnimation
    ) {
        state = initialState
        self.animation = animation
        particleView = ActivityMetalOrbView(
            frame: frame,
            initialState: initialState
        )
        activeView = particleView
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(particleView)
        setAnimation(animation)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        activeView.frame = bounds
        redrawIfPaused()
    }

    func setAnimation(
        _ newAnimation: AppPreferences.CodexActivityOrbAnimation
    ) {
        let requestedView: NSView
        switch newAnimation {
        case .particleOrb:
            requestedView = particleView
        case .rippleGlow:
            if rippleGlowView == nil {
                let candidate = ActivityRippleGlowMetalView(
                    frame: bounds,
                    initialState: state
                )
                if candidate.isRendererAvailable {
                    rippleGlowView = candidate
                }
            }
            requestedView = rippleGlowView ?? particleView
        }

        animation = newAnimation
        guard activeView !== requestedView else {
            setReduceMotion(reduceMotion)
            return
        }

        particleView.setReduceMotion(true)
        rippleGlowView?.setReduceMotion(true)
        activeView.removeFromSuperview()
        activeView = requestedView
        activeView.frame = bounds
        addSubview(activeView)
        updatePlaybackState()
    }

    func setState(_ newState: CodexActivityVisualState) {
        state = newState
        particleView.setState(newState)
        rippleGlowView?.setState(newState)
        redrawIfPaused()
    }

    func setReduceMotion(_ enabled: Bool) {
        reduceMotion = enabled
        updatePlaybackState()
    }

    func setPlaybackEnabled(_ enabled: Bool) {
        playbackEnabled = enabled
        updatePlaybackState()
    }

    private func updatePlaybackState() {
        particleView.setReduceMotion(
            reduceMotion
                || !playbackEnabled
                || activeView !== particleView
        )
        if let rippleGlowView {
            rippleGlowView.setReduceMotion(
                reduceMotion
                    || !playbackEnabled
                    || activeView !== rippleGlowView
            )
        }
    }

    func redrawIfPaused() {
        particleView.redrawIfPaused()
        rippleGlowView?.redrawIfPaused()
    }
}

private final class ActivityIslandSurfaceView: NSView {
    private let materialView = NSVisualEffectView()
    private let tintView = NSView()
    private var resolvedCornerRadius: CGFloat = 34

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
        applyCornerRadius()
        materialView.frame = bounds
        tintView.frame = bounds
    }

    func setCornerRadius(_ radius: CGFloat) {
        let normalized = max(0, radius)
        guard resolvedCornerRadius != normalized else { return }
        resolvedCornerRadius = normalized
        applyCornerRadius()
    }

    private func applyCornerRadius() {
        let radius = min(resolvedCornerRadius, bounds.height / 2)
        layer?.cornerRadius = radius
        tintView.layer?.cornerRadius = radius
        tintView.layer?.cornerCurve = .continuous
    }
}

struct CodexActivityIslandCompletionPalette {
    static let violet = NSColor(
        srgbRed: 0.55,
        green: 0.36,
        blue: 1.00,
        alpha: 1
    )
    static let blue = NSColor(
        srgbRed: 0.31,
        green: 0.63,
        blue: 1.00,
        alpha: 1
    )
    static let cyan = NSColor(
        srgbRed: 0.43,
        green: 0.89,
        blue: 1.00,
        alpha: 1
    )
    static let gradientLocations: [NSNumber] = [0, 0.52, 1]
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

private final class ActivityIslandCompletionGlowView: NSView {
    private enum AnimationKey {
        static let reveal = "quotaview.activity.completion-glow.reveal"
        static let breathRadius =
            "quotaview.activity.completion-glow.radius"
    }

    private let violetGlowLayer = CAShapeLayer()
    private let cyanGlowLayer = CAShapeLayer()
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
        let glowPath = CGPath(
            roundedRect: glowSourceRect,
            cornerWidth: glowSourceRadius,
            cornerHeight: glowSourceRadius,
            transform: nil
        )
        for glowLayer in [violetGlowLayer, cyanGlowLayer] {
            glowLayer.frame = bounds
            glowLayer.path = glowPath
            glowLayer.shadowPath = glowPath
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
            ? CodexActivityStateSmokeContract.completionGlowDelay
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
                CodexActivityIslandCompletionPalette.violet,
                CodexActivityIslandCompletionPalette.cyan
            )
        case .confirmationReminder:
            let warning =
                CodexActivityIslandConfirmationReminderContract
                .warningColor
            colors = (warning, warning)
        }
        for (layer, color) in zip(
            [violetGlowLayer, cyanGlowLayer],
            [colors.0, colors.1]
        ) {
            layer.fillColor = color.cgColor
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

private final class ActivityIslandCompletionOutlineView: NSView {
    private enum AnimationKey {
        static let reveal =
            "quotaview.activity.completion-outline.reveal"
    }

    private let outlineGradientLayer = CAGradientLayer()
    private let outlineMaskLayer = CAShapeLayer()
    private var edgeEmphasis = CodexActivityIslandEdgeEmphasis.none
    private var reduceMotion = false
    private var playbackVisible = false
    private var islandCornerRadius: CGFloat = 34

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
        let path = CGPath(
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

        guard shouldShow, !reduceMotion, delaysReveal else { return }
        let now = outlineGradientLayer.convertTime(
            CACurrentMediaTime(),
            from: nil
        )
        let reveal = CABasicAnimation(keyPath: "opacity")
        reveal.fromValue = 0
        reveal.toValue = 1
        reveal.beginTime = now + (
            edgeEmphasis == .completion
                ? CodexActivityStateSmokeContract.completionGlowDelay
                : 0
        )
        reveal.duration = edgeEmphasis == .confirmationReminder
            ? CodexActivityIslandConfirmationReminderContract
                .revealDuration
            : CodexActivityStateSmokeContract.completionGlowFadeDuration
        reveal.fillMode = .backwards
        reveal.timingFunction = CAMediaTimingFunction(name: .easeOut)
        outlineGradientLayer.add(
            reveal,
            forKey: AnimationKey.reveal
        )
    }

    private func applyColors() {
        switch edgeEmphasis {
        case .completion, .none:
            outlineGradientLayer.colors = [
                CodexActivityIslandCompletionPalette.violet.cgColor,
                CodexActivityIslandCompletionPalette.blue.cgColor,
                CodexActivityIslandCompletionPalette.cyan.cgColor,
            ]
        case .confirmationReminder:
            let warning =
                CodexActivityIslandConfirmationReminderContract
                .warningColor
            outlineGradientLayer.colors = [
                warning.withAlphaComponent(0.76).cgColor,
                warning.cgColor,
                warning.withAlphaComponent(0.76).cgColor,
            ]
        }
    }
}

private final class ActivityIslandQuotaRingView: NSView {
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

private final class ActivityIslandContentView: NSView {
    private let shadowHost = NSView()
    private let completionGlowView =
        ActivityIslandCompletionGlowView(frame: .zero)
    private let completionOutlineView =
        ActivityIslandCompletionOutlineView(frame: .zero)
    private let surface = ActivityIslandSurfaceView()
    private let stateSmokeView =
        ActivityStateSmokeMetalView(frame: .zero)
    private let orbView: ActivitySelectableOrbView
    private let kickerLabel = ActivitySingleLineTextView()
    private let titleLabel = ActivitySingleLineTextView()
    private let compactTitleLabel = ActivitySingleLineTextView()
    private let detailLabel = ActivitySingleLineTextView()
    private let tokenUsageLabel = ActivitySingleLineTextView()
    private let completionStatusLabel = ActivitySingleLineTextView()
    private let completionDetailLabel = ActivitySingleLineTextView()
    private let completionQuotaValueLabel = ActivitySingleLineTextView()
    private let completionQuotaSymbolLabel = ActivitySingleLineTextView()
    private let compactQuotaRingView = ActivityIslandQuotaRingView()
    private let statusDot = NSView()

    private var renderState: CodexActivityRenderState
    private let islandStyle:
        AppPreferences.CodexActivityIslandStyle = .progressBar
    private var progressEffect:
        AppPreferences.CodexActivityProgressEffect
    private var reduceMotion = false
    private var playbackVisible = false

    override var isOpaque: Bool { false }

    init(
        initialState: CodexActivityRenderState,
        progressEffect: AppPreferences.CodexActivityProgressEffect
    ) {
        renderState = initialState
        self.progressEffect = progressEffect
        orbView = ActivitySelectableOrbView(
            frame: .zero,
            initialState: initialState.visualState,
            animation: .particleOrb
        )
        super.init(frame: .zero)

        wantsLayer = true

        shadowHost.wantsLayer = true
        shadowHost.layer?.shadowColor = NSColor.black.cgColor
        shadowHost.layer?.shadowOpacity = 0.42
        shadowHost.layer?.shadowRadius =
            CodexActivityIslandPresentation.shadowRadius
        shadowHost.layer?.shadowOffset = CGSize(
            width: 0,
            height:
                CodexActivityIslandPresentation.shadowVerticalOffset
        )
        addSubview(shadowHost)

        shadowHost.addSubview(completionGlowView)
        shadowHost.addSubview(surface)
        shadowHost.addSubview(completionOutlineView)
        surface.addSubview(stateSmokeView)
        surface.addSubview(orbView)

        stateSmokeView.isHidden = true
        stateSmokeView.setEffect(progressEffect)
        stateSmokeView.setPlaybackEnabled(false)

        kickerLabel.font = activityFont(
            "AstaSans-SemiBold",
            size: 11.5,
            fallbackWeight: .semibold
        )
        kickerLabel.textColor = NSColor.white.withAlphaComponent(0.46)
        surface.addSubview(kickerLabel)

        titleLabel.font = activityFont(
            "AstaSans-SemiBold",
            size: 18,
            fallbackWeight: .semibold
        )
        titleLabel.textColor = .white
        surface.addSubview(titleLabel)

        compactTitleLabel.font = activityFont(
            "AstaSans-SemiBold",
            size:
                CodexActivityIslandPresentation
                .compactTitleFontSize,
            fallbackWeight: .semibold
        )
        compactTitleLabel.textColor = .white
        compactTitleLabel.horizontalAlignment = .center
        surface.addSubview(compactTitleLabel)

        detailLabel.font = activityFont(
            "AstaSans-Regular",
            size: 11.5,
            fallbackWeight: .regular
        )
        surface.addSubview(detailLabel)

        tokenUsageLabel.horizontalAlignment = .trailing
        surface.addSubview(tokenUsageLabel)

        completionStatusLabel.horizontalAlignment = .leading
        completionStatusLabel.textColor = .white
        surface.addSubview(completionStatusLabel)

        completionDetailLabel.horizontalAlignment = .leading
        completionDetailLabel.textColor = NSColor.white.withAlphaComponent(
            0.68
        )
        surface.addSubview(completionDetailLabel)

        completionQuotaValueLabel.horizontalAlignment = .leading
        completionQuotaValueLabel.textColor = .white
        surface.addSubview(completionQuotaValueLabel)

        completionQuotaSymbolLabel.horizontalAlignment = .leading
        completionQuotaSymbolLabel.textColor = .white
        surface.addSubview(completionQuotaSymbolLabel)

        surface.addSubview(compactQuotaRingView)

        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = activityStatusDotSide / 2
        surface.addSubview(statusDot)

        update(
            renderState: initialState,
            progressEffect: progressEffect
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()

        let panelInset = CodexActivityIslandGeometry.panelInset
        shadowHost.frame = bounds.insetBy(
            dx: panelInset,
            dy: panelInset
        )
        completionGlowView.frame = shadowHost.bounds.insetBy(
            dx: -panelInset,
            dy: -panelInset
        )
        completionGlowView.setIslandInset(panelInset)
        surface.frame = shadowHost.bounds
        completionOutlineView.frame = shadowHost.bounds

        let surfaceBounds = surface.bounds
        stateSmokeView.frame = surfaceBounds
        stateSmokeView.redrawIfPaused()

        let expandedSurfaceHeight =
            islandStyle == .progressBar
            ? CodexActivityIslandProgressBarGeometry
                .expandedSurfaceHeight
            : max(
                renderState.visualState.activityWindowSize.height
                    - panelInset * 2,
                CodexActivityIslandPresentation
                    .compactSurfaceSize.height
            )
        let progress = activityExpansionProgress(
            surfaceHeight: surfaceBounds.height,
            expandedSurfaceHeight: expandedSurfaceHeight
        )
        let surfaceCornerRadius = activityIslandSurfaceCornerRadius(
            style: islandStyle,
            surfaceHeight: surfaceBounds.height,
            expansionProgress: progress
        )
        surface.setCornerRadius(surfaceCornerRadius)
        completionGlowView.setIslandCornerRadius(
            surfaceCornerRadius
        )
        completionOutlineView.setIslandCornerRadius(
            surfaceCornerRadius
        )
        shadowHost.layer?.shadowPath = CGPath(
            roundedRect: shadowHost.bounds,
            cornerWidth: surfaceCornerRadius,
            cornerHeight: surfaceCornerRadius,
            transform: nil
        )
        let expandedOrbSide = max(
            CodexActivityIslandPresentation.compactOrbCanvasSide,
            min(124, max(68, expandedSurfaceHeight - 10))
        )
        let orbCanvasSide = activityInterpolate(
            from:
                CodexActivityIslandPresentation
                .compactOrbCanvasSide,
            to: expandedOrbSide,
            progress: progress
        )
        let compactOrbCanvasLeading =
            CodexActivityIslandPresentation.compactOrbLeading
            - (
                CodexActivityIslandPresentation.compactOrbCanvasSide
                - CodexActivityIslandPresentation.compactOrbDiameter
            ) / 2
        let orbX = activityInterpolate(
            from: compactOrbCanvasLeading,
            to: 4,
            progress: progress
        )
        let orbFrame = NSRect(
            x: orbX,
            y: (surfaceBounds.height - orbCanvasSide) / 2,
            width: orbCanvasSide,
            height: orbCanvasSide
        )
        orbView.frame = orbFrame
        orbView.redrawIfPaused()

        let compactTextStart =
            CodexActivityIslandPresentation.compactOrbLeading
            + CodexActivityIslandPresentation.compactOrbDiameter
            + CodexActivityIslandPresentation.compactTextGap
        let expandedTextStart = 4 + expandedOrbSide + 2
        let textStart = CodexActivityIslandTextGeometry.textStart(
            style: islandStyle,
            compactStart: compactTextStart,
            expandedStart: expandedTextStart,
            expansionProgress: progress
        )
        let usesProgressLayout = islandStyle == .progressBar
        let statusColumnWidth =
            CodexActivityIslandProgressBarGeometry
            .maximumStatusColumnWidth
        let textTrailing = usesProgressLayout
            ? CodexActivityIslandProgressBarGeometry.textInset
                + statusColumnWidth
                + CodexActivityIslandProgressBarGeometry.columnGap
            : 18
        let textWidth = max(
            0,
            surfaceBounds.width - textStart - textTrailing
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
        let textLayout = activityCenteredTextLayout(
            surfaceHeight: surfaceBounds.height
        )
        let progressTextLayout = activityProgressTextLayout(
            surfaceHeight: surfaceBounds.height
        )

        let showsCompletionReceipt =
            renderState.completionReceiptStatus != nil
                && renderState.completionReceiptDetail != nil
        let standardContentAlpha: CGFloat = showsCompletionReceipt ? 0 : 1
        kickerLabel.alphaValue = supportingAlpha * standardContentAlpha
        detailLabel.alphaValue = supportingAlpha * standardContentAlpha
        statusDot.alphaValue = supportingAlpha * standardContentAlpha
        titleLabel.alphaValue = expandedTitleAlpha * standardContentAlpha
        tokenUsageLabel.alphaValue = renderState.tokenUsageTitle == nil
            ? 0
            : supportingAlpha * standardContentAlpha
        completionStatusLabel.alphaValue = showsCompletionReceipt
            ? supportingAlpha
            : 0
        completionDetailLabel.alphaValue = showsCompletionReceipt
            ? supportingAlpha
            : 0
        completionQuotaValueLabel.alphaValue = showsCompletionReceipt
            ? supportingAlpha
            : 0
        completionQuotaSymbolLabel.alphaValue = showsCompletionReceipt
            ? supportingAlpha
            : 0
        compactQuotaRingView.alphaValue = showsCompletionReceipt
            ? compactTitleAlpha
            : 0
        compactTitleLabel.alphaValue = compactTitleAlpha
        let centeredStatusY =
            (surfaceBounds.height - activityStatusLineHeight) / 2

        if usesProgressLayout {
            kickerLabel.frame = NSRect(
                x:
                    textStart
                    + activityStatusDotSide
                    + CodexActivityIslandProgressBarGeometry
                        .titleDotGap,
                y: progressTextLayout.titleY,
                width: max(
                    0,
                    textWidth
                        - activityStatusDotSide
                        - CodexActivityIslandProgressBarGeometry
                            .titleDotGap
                ),
                height: activitySupportingLineHeight
            )
            statusDot.frame = NSRect(
                x: textStart,
                y: progressTextLayout.statusDotY,
                width: activityStatusDotSide,
                height: activityStatusDotSide
            )
            detailLabel.frame = NSRect(
                x: textStart,
                y: progressTextLayout.detailY,
                width: textWidth,
                height: activitySupportingLineHeight
            )
            let statusColumnX =
                surfaceBounds.width
                - CodexActivityIslandProgressBarGeometry.textInset
                - statusColumnWidth
            let hasTokenUsage = renderState.tokenUsageTitle != nil
            titleLabel.frame = NSRect(
                x: statusColumnX,
                y: hasTokenUsage
                    ? progressTextLayout.titleY
                    : centeredStatusY,
                width: statusColumnWidth,
                height: hasTokenUsage
                    ? activitySupportingLineHeight
                    : activityStatusLineHeight
            )
            tokenUsageLabel.frame = NSRect(
                x: statusColumnX,
                y: progressTextLayout.detailY,
                width: statusColumnWidth,
                height: activitySupportingLineHeight
            )
        } else {
            kickerLabel.frame = NSRect(
                x: textStart + 12,
                y: textLayout.kickerY,
                width: max(0, textWidth - 12),
                height: activitySupportingLineHeight
            )
            statusDot.frame = NSRect(
                x: textStart,
                y: textLayout.statusDotY,
                width: activityStatusDotSide,
                height: activityStatusDotSide
            )
            titleLabel.frame = NSRect(
                x: textStart,
                y: activityInterpolate(
                    from: centeredStatusY,
                    to: textLayout.titleY,
                    progress: progress
                ),
                width: textWidth,
                height: activityStatusLineHeight
            )
            detailLabel.frame = NSRect(
                x: textStart,
                y: textLayout.detailY,
                width: textWidth,
                height: activitySupportingLineHeight
            )
            tokenUsageLabel.frame = .zero
        }
        let completionX =
            CodexActivityIslandProgressBarGeometry.textInset
        let completionLeftWidth =
            CodexActivityIslandProgressBarGeometry
            .completionLeftColumnWidth
        let completionRightX = completionX
            + completionLeftWidth
            + CodexActivityIslandProgressBarGeometry
                .completionColumnGap
        let completionRightWidth =
            CodexActivityIslandProgressBarGeometry
            .completionRightColumnWidth
        completionStatusLabel.frame = NSRect(
            x: completionX,
            y: progressTextLayout.titleY,
            width: completionLeftWidth,
            height: activitySupportingLineHeight
        )
        completionDetailLabel.frame = NSRect(
            x: completionX,
            y: progressTextLayout.detailY,
            width: completionLeftWidth,
            height: activitySupportingLineHeight
        )
        let completionQuotaValueWidth = min(
            NSAttributedString(
                string: completionQuotaValueLabel.stringValue,
                attributes: [.font: completionQuotaValueLabel.font]
            ).size().width,
            completionRightWidth
        )
        let completionQuotaSymbolWidth = min(
            NSAttributedString(
                string: completionQuotaSymbolLabel.stringValue,
                attributes: [.font: completionQuotaSymbolLabel.font]
            ).size().width,
            completionRightWidth
        )
        let completionQuotaGroupWidth = min(
            completionQuotaValueWidth + completionQuotaSymbolWidth,
            completionRightWidth
        )
        let completionQuotaGroupX = completionRightX
            + completionRightWidth
            - completionQuotaGroupWidth
        let completionQuotaGroupHeight: CGFloat = 34
        let completionQuotaGroupY =
            (surfaceBounds.height - completionQuotaGroupHeight) / 2
        completionQuotaValueLabel.frame = NSRect(
            x: completionQuotaGroupX,
            y: completionQuotaGroupY,
            width: min(
                completionQuotaValueWidth,
                completionQuotaGroupWidth
            ),
            height: completionQuotaGroupHeight
        )
        completionQuotaSymbolLabel.frame = NSRect(
            x: completionQuotaValueLabel.frame.maxX,
            y: completionQuotaGroupY + 2,
            width: max(
                0,
                completionQuotaGroupWidth
                    - completionQuotaValueLabel.frame.width
            ),
            height: completionQuotaGroupHeight - 4
        )
        if showsCompletionReceipt {
            let compactInset =
                CodexActivityIslandProgressBarGeometry
                .compactCompletionInset
            compactQuotaRingView.frame =
                CodexActivityIslandProgressBarGeometry
                .compactQuotaRingFrame(
                    in: surfaceBounds
                )
            compactTitleLabel.horizontalAlignment = .leading
            compactTitleLabel.frame = NSRect(
                x: compactInset,
                y: 0,
                width: max(
                    0,
                    compactQuotaRingView.frame.minX
                        - CodexActivityIslandProgressBarGeometry
                            .compactCompletionGap
                        - compactInset
                ),
                height: surfaceBounds.height
            )
        } else {
            compactQuotaRingView.frame = .zero
            compactTitleLabel.horizontalAlignment = .center
            var compactTitleFrame =
                CodexActivityIslandTextGeometry.compactTitleFrame(
                    style: islandStyle,
                    surfaceWidth: surfaceBounds.width
                )
            compactTitleFrame.size.height = surfaceBounds.height
            compactTitleLabel.frame = compactTitleFrame
        }
        shadowHost.layer?.shadowOpacity = Float(
            activityInterpolate(
                from: 0.30,
                to: 0.42,
                progress: progress
            )
        )
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        synchronizeLogicalBounds()
    }

    func update(
        renderState: CodexActivityRenderState,
        progressEffect: AppPreferences.CodexActivityProgressEffect
    ) {
        self.renderState = renderState
        self.progressEffect = progressEffect
        configureTypography()
        kickerLabel.stringValue = renderState.windowTitle
        titleLabel.stringValue = renderState.statusTitle
        compactTitleLabel.stringValue = renderState.statusTitle
        detailLabel.stringValue = renderState.operation
        tokenUsageLabel.stringValue = renderState.tokenUsageTitle ?? ""
        completionStatusLabel.stringValue =
            renderState.completionReceiptStatus ?? ""
        completionDetailLabel.stringValue =
            renderState.completionReceiptDetail ?? ""
        if renderState.completionReceiptStatus != nil {
            completionQuotaValueLabel.stringValue =
                renderState.completionQuotaRemainingPercent
                .map { String(min(max($0, 0), 100)) } ?? "—"
            completionQuotaSymbolLabel.stringValue =
                renderState.completionQuotaRemainingPercent == nil
                ? ""
                : "%"
        } else {
            completionQuotaValueLabel.stringValue = ""
            completionQuotaSymbolLabel.stringValue = ""
        }
        compactQuotaRingView.update(
            remainingPercent:
                renderState.completionQuotaRemainingPercent
        )
        let sweeps =
            renderState.visualState.activityShowsOperationSweep
        kickerLabel.textColor =
            CodexActivityIslandTextContrast
            .progressTaskTitleColor
        detailLabel.textColor =
            CodexActivityIslandTextContrast
            .progressOperationColor
        tokenUsageLabel.textColor =
            CodexActivityIslandTextContrast
            .progressOperationColor
        statusDot.layer?.borderWidth =
            CodexActivityIslandTextContrast
            .statusDotBorderWidth
        statusDot.layer?.borderColor =
            CodexActivityIslandTextContrast
            .statusDotBorderColor.cgColor
        detailLabel.shimmerEnabled = sweeps
        statusDot.layer?.backgroundColor =
            renderState.visualState.activityAccentColor.cgColor
        orbView.setAnimation(.particleOrb)
        orbView.setState(renderState.visualState)
        stateSmokeView.setState(renderState.visualState, taskIdentity: renderState.taskIdentity)
        stateSmokeView.setEffect(progressEffect)
        stateSmokeView.setApproximateProgress(
            renderState.approximateProgressFraction
        )
        applyVisualEffectPlayback()
        synchronizeLogicalBounds()
        needsLayout = true

        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(renderState.accessibilityLabel)
    }

    private func configureTypography() {
        kickerLabel.font = activityFont(
            "AstaSans-SemiBold",
            size:
                CodexActivityIslandProgressBarGeometry
                .titleFontSize,
            fallbackWeight: .semibold
        )
        titleLabel.font = activityFont(
            "AstaSans-SemiBold",
            size:
                CodexActivityIslandProgressBarGeometry
                .statusFontSize,
            fallbackWeight: .semibold
        )
        detailLabel.font = activityFont(
            "AstaSans-Regular",
            size:
                CodexActivityIslandProgressBarGeometry
                .detailFontSize,
            fallbackWeight: .regular
        )
        tokenUsageLabel.font = activityFont(
            "AstaSans-Regular",
            size:
                CodexActivityIslandProgressBarGeometry
                .tokenUsageFontSize,
            fallbackWeight: .regular
        )
        completionStatusLabel.font = activityFont(
            "AstaSans-SemiBold",
            size:
                CodexActivityIslandProgressBarGeometry
                .completionStatusFontSize,
            fallbackWeight: .semibold
        )
        completionDetailLabel.font = activityFont(
            "AstaSans-Regular",
            size:
                CodexActivityIslandProgressBarGeometry
                .completionDetailFontSize,
            fallbackWeight: .regular
        )
        completionQuotaValueLabel.font = activityFont(
            "AstaSans-SemiBold",
            size:
                CodexActivityIslandProgressBarGeometry
                .completionQuotaValueFontSize,
            fallbackWeight: .semibold
        )
        completionQuotaSymbolLabel.font = activityFont(
            "AstaSans-SemiBold",
            size:
                CodexActivityIslandProgressBarGeometry
                .completionQuotaSymbolFontSize,
            fallbackWeight: .semibold
        )
        titleLabel.horizontalAlignment =
            CodexActivityIslandTextGeometry
            .expandedStatusAlignment(style: .progressBar)
    }

    func setReduceMotion(_ enabled: Bool) {
        reduceMotion = enabled
        applyVisualEffectPlayback()
        detailLabel.setReduceMotion(enabled)
    }

    func setPlaybackVisible(_ visible: Bool) {
        playbackVisible = visible
        applyVisualEffectPlayback()
    }

    func setPresentationMode(
        _: CodexActivityIslandPresentation,
        accessibilityValue: String
    ) {
        synchronizeLogicalBounds()
        needsLayout = true
        setAccessibilityValue(accessibilityValue)
    }

    private func synchronizeLogicalBounds() {
        let logicalSize = frame.size

        guard bounds.origin != .zero || bounds.size != logicalSize else {
            return
        }
        super.setBoundsOrigin(.zero)
        super.setBoundsSize(logicalSize)
    }

    private var isUsingStateSmoke: Bool {
        stateSmokeView.isRendererAvailable
    }

    private func applyVisualEffectPlayback() {
        let usesStateSmoke = isUsingStateSmoke
        let edgeEmphasis =
            CodexActivityIslandConfirmationReminderContract
            .edgeEmphasis(
                visualState: renderState.visualState,
                reminderActive:
                    renderState.isConfirmationReminderActive,
                completionEffectAvailable: usesStateSmoke
            )
        orbView.setAnimation(.particleOrb)
        stateSmokeView.isHidden = !usesStateSmoke
        orbView.isHidden = usesStateSmoke
        stateSmokeView.setReduceMotion(reduceMotion)
        stateSmokeView.setPlaybackEnabled(
            usesStateSmoke && playbackVisible
        )
        completionGlowView.update(
            edgeEmphasis: edgeEmphasis,
            reduceMotion: reduceMotion,
            playbackVisible: playbackVisible
        )
        completionOutlineView.update(
            edgeEmphasis: edgeEmphasis,
            reduceMotion: reduceMotion,
            playbackVisible: playbackVisible
        )
        orbView.setReduceMotion(reduceMotion)
        orbView.setPlaybackEnabled(
            !usesStateSmoke && playbackVisible
        )
        needsLayout = true
    }
}

private final class CodexActivityPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct CodexActivityScreenLocator {
    struct DisplayGeometry: Equatable {
        let id: CGDirectDisplayID
        let bounds: CGRect
    }

    static func screen(
        forProcessIdentifier processIdentifier: pid_t,
        screens: [NSScreen] = NSScreen.screens
    ) -> NSScreen? {
        guard processIdentifier > 0,
              let windowInfo = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
              ) as? [[String: Any]]
        else {
            return nil
        }

        let windowBounds = windowInfo.compactMap { entry -> CGRect? in
            guard let ownerPID = entry[
                kCGWindowOwnerPID as String
            ] as? NSNumber,
            ownerPID.int32Value == processIdentifier,
            let layer = entry[kCGWindowLayer as String] as? NSNumber,
            layer.intValue == 0,
            ((entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue
                ?? 1) > 0,
            let boundsDictionary = entry[
                kCGWindowBounds as String
            ] as? NSDictionary,
            let bounds = CGRect(
                dictionaryRepresentation: boundsDictionary
            ),
            bounds.width > 1,
            bounds.height > 1
            else {
                return nil
            }
            return bounds
        }

        let displayGeometries = screens.compactMap {
            screen -> DisplayGeometry? in
            let screenNumberKey = NSDeviceDescriptionKey(
                "NSScreenNumber"
            )
            guard let screenNumber = screen.deviceDescription[
                screenNumberKey
            ] as? NSNumber
            else {
                return nil
            }
            let displayID = CGDirectDisplayID(
                screenNumber.uint32Value
            )
            return DisplayGeometry(
                id: displayID,
                bounds: CGDisplayBounds(displayID)
            )
        }

        guard let displayID = bestDisplayID(
            windowBounds: windowBounds,
            displays: displayGeometries
        ) else {
            return nil
        }

        return screens.first { screen in
            let key = NSDeviceDescriptionKey("NSScreenNumber")
            guard let number = screen.deviceDescription[key]
                as? NSNumber
            else {
                return false
            }
            return number.uint32Value == displayID
        }
    }

    static func bestDisplayID(
        windowBounds: [CGRect],
        displays: [DisplayGeometry]
    ) -> CGDirectDisplayID? {
        guard let largestWindow = (
            windowBounds
                .filter { $0.width > 1 && $0.height > 1 }
                .max(by: { area(of: $0) < area(of: $1) })
        )
        else {
            return nil
        }

        let bestMatch = displays
            .map { display in
                (
                    display.id,
                    area(of: largestWindow.intersection(display.bounds))
                )
            }
            .filter { $0.1 > 0 }
            .max { left, right in
                if left.1 != right.1 {
                    return left.1 < right.1
                }
                return left.0 > right.0
            }
        return bestMatch?.0
    }

    private static func area(of rect: CGRect) -> CGFloat {
        guard !rect.isNull, !rect.isInfinite else { return 0 }
        return max(0, rect.width) * max(0, rect.height)
    }
}

@MainActor
final class CodexActivityIslandPanelController {
    private let panel: CodexActivityPanel
    private let content: ActivityIslandContentView
    private var presentationMode:
        CodexActivityIslandPresentation = .expanded
    private var targetSize: NSSize
    private let panelInset: CGFloat
    private var reduceMotion = false
    private var isPointerHovering = false
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?

    init(
        initialState: CodexActivityRenderState,
        progressEffect: AppPreferences.CodexActivityProgressEffect,
        screenPlacement:
            AppPreferences.CodexActivityScreenPlacement,
        codexProcessIdentifier: pid_t?
    ) {
        panelInset = CodexActivityIslandGeometry.panelInset
        targetSize = CodexActivityIslandGeometry.panelSize(
            presentation: .expanded,
            renderState: initialState
        )
        content = ActivityIslandContentView(
            initialState: initialState,
            progressEffect: progressEffect
        )
        panel = CodexActivityPanel(
            contentRect: NSRect(
                origin: .zero,
                size: targetSize
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [
            .transient,
            .moveToActiveSpace,
            .fullScreenAuxiliary
        ]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        panel.contentView = content

        positionPanel(
            size: targetSize,
            animated: false,
            screenPlacement: screenPlacement,
            codexProcessIdentifier: codexProcessIdentifier
        )
        installHoverMonitors()
    }

    deinit {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
        }
    }

    func update(
        renderState: CodexActivityRenderState,
        presentationMode: CodexActivityIslandPresentation,
        presentationAccessibilityValue: String,
        reduceMotion: Bool,
        progressEffect: AppPreferences.CodexActivityProgressEffect,
        screenPlacement:
            AppPreferences.CodexActivityScreenPlacement,
        codexProcessIdentifier: pid_t?,
        playbackEnabled: Bool
    ) {
        let modeChanged = self.presentationMode != presentationMode
        self.presentationMode = presentationMode
        self.reduceMotion = reduceMotion

        content.setReduceMotion(reduceMotion)
        content.update(
            renderState: renderState,
            progressEffect: progressEffect
        )
        content.setPresentationMode(
            presentationMode,
            accessibilityValue: presentationAccessibilityValue
        )
        content.setPlaybackVisible(playbackEnabled)

        let duration = modeChanged
            ? presentationMode.transitionDuration
            : 0.44
        targetSize = CodexActivityIslandGeometry.panelSize(
            presentation: presentationMode,
            renderState: renderState
        )
        positionPanel(
            size: targetSize,
            animated: !reduceMotion,
            duration: duration,
            screenPlacement: screenPlacement,
            codexProcessIdentifier: codexProcessIdentifier
        )
        panel.orderFrontRegardless()
        updateHoverAppearance(animated: !reduceMotion)
    }

    func hide() {
        content.setPlaybackVisible(false)
        isPointerHovering = false
        panel.alphaValue =
            CodexActivityIslandHoverTransparencyContract.restingAlpha
        panel.orderOut(nil)
    }

    var isVisible: Bool {
        panel.isVisible
    }

    func reposition(
        screenPlacement:
            AppPreferences.CodexActivityScreenPlacement,
        codexProcessIdentifier: pid_t?
    ) {
        positionPanel(
            size: targetSize,
            animated: true,
            duration: 0.20,
            screenPlacement: screenPlacement,
            codexProcessIdentifier: codexProcessIdentifier
        )
    }

    private func positionPanel(
        size: NSSize,
        animated: Bool,
        duration: TimeInterval = 0.44,
        screenPlacement:
            AppPreferences.CodexActivityScreenPlacement,
        codexProcessIdentifier: pid_t?
    ) {
        guard let screen = targetScreen(
            for: screenPlacement,
            codexProcessIdentifier: codexProcessIdentifier
        ) else {
            return
        }
        let visibleFrame = screen.visibleFrame
        let topInsetCompensation = max(
            0,
            panelInset - CodexActivityIslandPresentation.panelInset
        )
        let targetFrame = NSRect(
            x: visibleFrame.midX - size.width / 2,
            y:
                visibleFrame.maxY
                - size.height
                - 6
                + topInsetCompensation,
            width: size.width,
            height: size.height
        )

        guard panel.frame != targetFrame else { return }

        guard animated, panel.isVisible else {
            panel.setFrame(targetFrame, display: true)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(
                name: .easeInEaseOut
            )
            panel.animator().setFrame(targetFrame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.updateHoverAppearance(
                    animated: !self.reduceMotion
                )
            }
        }
    }

    private func installHoverMonitors() {
        let mask: NSEvent.EventTypeMask = [
            .mouseMoved,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged
        ]

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: mask
        ) { [weak self] event in
            self?.updateHoverAppearance()
            return event
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: mask
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateHoverAppearance()
            }
        }
    }

    private func updateHoverAppearance(animated: Bool = true) {
        let hoverFrame =
            CodexActivityIslandHoverTransparencyContract
            .visibleSurfaceFrame(
                panelFrame: panel.frame,
                panelInset: panelInset
            )
        let isHovering =
            panel.isVisible
            && hoverFrame.contains(NSEvent.mouseLocation)
        guard isHovering != isPointerHovering else { return }

        isPointerHovering = isHovering
        let targetAlpha = isHovering
            ? CodexActivityIslandHoverTransparencyContract.hoveredAlpha
            : CodexActivityIslandHoverTransparencyContract.restingAlpha

        guard animated, !reduceMotion else {
            panel.alphaValue = targetAlpha
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration =
                CodexActivityIslandHoverTransparencyContract
                .transitionDuration
            context.timingFunction = CAMediaTimingFunction(
                name: .easeOut
            )
            panel.animator().alphaValue = targetAlpha
        }
    }

    private func targetScreen(
        for placement: AppPreferences.CodexActivityScreenPlacement,
        codexProcessIdentifier: pid_t?
    ) -> NSScreen? {
        if placement == .codexScreen,
           let codexProcessIdentifier,
           let codexScreen = CodexActivityScreenLocator.screen(
            forProcessIdentifier: codexProcessIdentifier
           ) {
            return codexScreen
        }
        return NSScreen.main ?? NSScreen.screens.first
    }
}

private func activityFont(
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
