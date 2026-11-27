import AppKit
import QuotaViewCore

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
        case .expanded: ActivityIslandMotion.revealDuration
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
    static let defaultVisibilityPercent = 20
    static let defaultTransparencyPercent = 100 - defaultVisibilityPercent
    static let transparencyRange = 0...100
    static let transitionDuration: TimeInterval = 0.14

    private(set) var targetAlpha: CGFloat = restingAlpha

    mutating func update(isHovering: Bool, transparencyPercent: Int) -> Bool {
        let alpha = Self.alpha(isHovering: isHovering, transparencyPercent: transparencyPercent)
        guard alpha != targetAlpha else { return false }
        targetAlpha = alpha
        return true
    }

    static func normalizedTransparencyPercent(_ value: Int) -> Int {
        min(max(value, transparencyRange.lowerBound), transparencyRange.upperBound)
    }

    static func alpha(
        isHovering: Bool,
        transparencyPercent: Int = defaultTransparencyPercent
    ) -> CGFloat {
        guard isHovering else { return restingAlpha }
        return CGFloat(100 - normalizedTransparencyPercent(transparencyPercent)) / 100
    }

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
    // Match the awaiting-confirmation orb’s warm upper highlight. Keep quota
    // warning and quantum particle palettes independent.
    static let approvalColor = NSColor(srgbRed: 1, green: 0.56, blue: 0.12, alpha: 1)
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

    static func compactCompletionSurfaceWidth(for title: String) -> CGFloat {
        let font = activityFont("AstaSans-SemiBold",
            size: CodexActivityIslandPresentation.compactTitleFontSize, fallbackWeight: .semibold)
        let textWidth = ceil(activitySingleLineWidth(text: title, font: font))
        let rightEndcap = CodexActivityIslandPresentation.compactSurfaceSize.height / 2
        return max(fixedCompactSurfaceWidth, compactCompletionInset + textWidth
                   + compactCompletionGap + compactQuotaRingDiameter / 2 + rightEndcap)
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
        activitySingleLineWidth(text: text, font: font)
    }

    static func completionQuotaTextWidths(
        value: String,
        symbol: String,
        valueFont: NSFont,
        symbolFont: NSFont,
        backingScaleFactor: CGFloat
    ) -> (value: CGFloat, symbol: CGFloat) {
        let scale = max(1, backingScaleFactor)
        func pixelWidth(_ text: String, font: NSFont) -> CGFloat {
            ceil(activitySingleLineWidth(text: text, font: font) * scale) / scale
        }

        // Reserve the symbol independently: (value + symbol) - value can be
        // slightly narrower than the glyph at values such as 27.
        let symbolWidth = min(
            pixelWidth(symbol, font: symbolFont),
            completionRightColumnWidth
        )
        let valueWidth = min(
            pixelWidth(value, font: valueFont),
            max(0, completionRightColumnWidth - symbolWidth)
        )
        return (valueWidth, symbolWidth)
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

extension CodexActivityVisualState {
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

}

extension CodexActivityVisualState {
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

}

func activityInterpolate(
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
