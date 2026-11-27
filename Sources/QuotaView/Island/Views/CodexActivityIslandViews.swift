import AppKit
import QuartzCore
import QuotaViewCore

private extension CodexActivityVisualState {
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

let activitySupportingLineHeight: CGFloat = 18
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

private final class ActivityIslandSurfaceView: NSView {
    private let tintView = NSView()
    private var resolvedCornerRadius: CGFloat = 34

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.cornerRadius = 34
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        tintView.wantsLayer = true
        // The effects fade to transparent on completion. Keep a solid black base
        // underneath instead of revealing desktop-dependent HUD material.
        tintView.layer?.backgroundColor = NSColor.black.cgColor
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
        tintView.frame = bounds
    }

    func setCornerRadius(_ radius: CGFloat) {
        let normalized = max(0, radius)
        guard resolvedCornerRadius != normalized else { return }
        resolvedCornerRadius = normalized
        applyCornerRadius()
    }

    func useTransparentBase() {
        // Task cards supply their own native glass behind this effect host.
        tintView.isHidden = true
    }

    private func applyCornerRadius() {
        let radius = min(resolvedCornerRadius, bounds.height / 2)
        layer?.cornerRadius = radius
        tintView.layer?.cornerRadius = radius
        tintView.layer?.cornerCurve = .continuous
    }
}

final class ActivityIslandContentView: NSView {
    // Optional multitask contour. The single-island path keeps all defaults unchanged.
    private var multitaskCapsule: CGFloat = 0
    private var multitaskContourRecoil: CGFloat = 0
    private var multitaskJelly: CGFloat = 0
    private var multitaskDidApplyJelly = false
    private(set) var multitaskSurfaceCornerRadius: CGFloat = 0
    var multitaskShellTransform: CGAffineTransform { shadowHost.layer?.affineTransform() ?? .identity }
    var multitaskTextTransform: CGAffineTransform { textHost.layer?.affineTransform() ?? .identity }
    var multitaskDisplayedText: [String] { [kickerLabel.stringValue, titleLabel.stringValue, detailLabel.stringValue, tokenUsageLabel.stringValue] }

    func setMultitaskContour(capsule: CGFloat, recoil: CGFloat, jelly: CGFloat = 0) {
        guard multitaskCapsule != capsule || multitaskContourRecoil != recoil || multitaskJelly != jelly else { return }
        multitaskCapsule = capsule
        multitaskContourRecoil = recoil
        multitaskJelly = jelly
        needsLayout = true
    }

    private func multitaskResetJelly() {
        multitaskDidApplyJelly = false
        CATransaction.begin(); CATransaction.setDisableActions(true)
        shadowHost.layer?.setAffineTransform(.identity)
        textHost.layer?.setAffineTransform(.identity)
        CATransaction.commit()
    }

    private func multitaskApplyJelly() {
        guard multitaskJelly != 0 else { return }
        multitaskDidApplyJelly = true
        // A short squash / overshoot / settle, about two visible oscillations.
        // The shared ancestor carries skin, effects, text, icons and completion copy.
        let x = 1 + multitaskJelly * 0.28
        let y = 1 - multitaskJelly
        func centered(_ layer: CALayer?, x: CGFloat, y: CGFloat) {
            guard let layer else { return }
            let dx = layer.bounds.width * (0.5 - layer.anchorPoint.x)
            let dy = layer.bounds.height * (0.5 - layer.anchorPoint.y)
            layer.setAffineTransform(CGAffineTransform(a: x, b: 0, c: 0, d: y, tx: (1 - x) * dx, ty: (1 - y) * dy))
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        centered(shadowHost.layer, x: x, y: y)
        CATransaction.commit()
    }

    private func multitaskCornerRadius(base: CGFloat, height: CGFloat) -> CGFloat {
        guard multitaskCapsule != 0 || multitaskContourRecoil != 0 else { multitaskSurfaceCornerRadius = base; return base }
        let capsuleRadius = height / 2
        let shape = base + (capsuleRadius - base) * min(1, max(0, multitaskCapsule))
        // Recoil moves the contour inward and back while preserving all four bounds.
        multitaskSurfaceCornerRadius = max(0, min(capsuleRadius, shape - height * multitaskContourRecoil * 0.5))
        return multitaskSurfaceCornerRadius
    }

    private let textHost = NSView()
    private var textLayoutFrame: NSRect?
    private var presentationLayoutSize: NSSize?
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
        surface.addSubview(textHost)

        stateSmokeView.isHidden = true
        stateSmokeView.setEffect(progressEffect)
        stateSmokeView.setPlaybackEnabled(false)

        kickerLabel.font = activityFont(
            "AstaSans-SemiBold",
            size: 11.5,
            fallbackWeight: .semibold
        )
        kickerLabel.textColor = NSColor.white.withAlphaComponent(0.46)
        textHost.addSubview(kickerLabel)

        titleLabel.font = activityFont(
            "AstaSans-SemiBold",
            size: 18,
            fallbackWeight: .semibold
        )
        titleLabel.textColor = .white
        textHost.addSubview(titleLabel)

        compactTitleLabel.font = activityFont(
            "AstaSans-SemiBold",
            size:
                CodexActivityIslandPresentation
                .compactTitleFontSize,
            fallbackWeight: .semibold
        )
        compactTitleLabel.textColor = .white
        compactTitleLabel.horizontalAlignment = .center
        textHost.addSubview(compactTitleLabel)

        detailLabel.font = activityFont(
            "AstaSans-Regular",
            size: 11.5,
            fallbackWeight: .regular
        )
        textHost.addSubview(detailLabel)

        tokenUsageLabel.horizontalAlignment = .trailing
        textHost.addSubview(tokenUsageLabel)

        completionStatusLabel.horizontalAlignment = .leading
        completionStatusLabel.textColor = .white
        textHost.addSubview(completionStatusLabel)

        completionDetailLabel.horizontalAlignment = .leading
        completionDetailLabel.textColor = NSColor.white.withAlphaComponent(
            0.68
        )
        textHost.addSubview(completionDetailLabel)

        completionQuotaValueLabel.horizontalAlignment = .leading
        completionQuotaValueLabel.textColor = .white
        textHost.addSubview(completionQuotaValueLabel)

        completionQuotaSymbolLabel.horizontalAlignment = .leading
        completionQuotaSymbolLabel.textColor = .white
        textHost.addSubview(completionQuotaSymbolLabel)

        textHost.addSubview(compactQuotaRingView)

        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = activityStatusDotSide / 2
        textHost.addSubview(statusDot)

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

        if multitaskDidApplyJelly { multitaskResetJelly() }
        defer { multitaskApplyJelly() }
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
        // Keep logical text layout stable; the common parent supplies visual spring scaling.
        textHost.frame = surface.convert((textLayoutFrame ?? bounds).insetBy(dx: panelInset, dy: panelInset), from: self)
        let textBounds = textHost.bounds
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
        let textProgress = activityExpansionProgress(
            surfaceHeight: textBounds.height,
            expandedSurfaceHeight: expandedSurfaceHeight
        )
        let surfaceCornerRadius = multitaskCornerRadius(base: activityIslandSurfaceCornerRadius(
            style: islandStyle,
            surfaceHeight: surfaceBounds.height,
            expansionProgress: progress
        ), height: surfaceBounds.height)
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
            expansionProgress: textProgress
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
            textBounds.width - textStart - textTrailing
        )
        let supportingAlpha = min(
            max((textProgress - 0.42) / 0.58, 0),
            1
        )
        let expandedTitleAlpha = min(
            max((textProgress - 0.18) / 0.82, 0),
            1
        )
        let compactTitleAlpha = min(
            max((0.58 - textProgress) / 0.58, 0),
            1
        )
        let textLayout = activityCenteredTextLayout(
            surfaceHeight: textBounds.height
        )
        let progressTextLayout = activityProgressTextLayout(
            surfaceHeight: textBounds.height
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
            (textBounds.height - activityStatusLineHeight) / 2

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
                textBounds.width
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
                    progress: textProgress
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
        let completionQuotaWidths =
            CodexActivityIslandProgressBarGeometry.completionQuotaTextWidths(
                value: completionQuotaValueLabel.stringValue,
                symbol: completionQuotaSymbolLabel.stringValue,
                valueFont: completionQuotaValueLabel.font,
                symbolFont: completionQuotaSymbolLabel.font,
                backingScaleFactor: window?.backingScaleFactor ?? 2
            )
        let completionQuotaGroupWidth = completionQuotaWidths.value
            + completionQuotaWidths.symbol
        let completionQuotaGroupX = completionRightX
            + completionRightWidth
            - completionQuotaGroupWidth
        let completionQuotaGroupHeight: CGFloat = 34
        let completionQuotaGroupY =
            (textBounds.height - completionQuotaGroupHeight) / 2
        completionQuotaValueLabel.frame = NSRect(
            x: completionQuotaGroupX,
            y: completionQuotaGroupY,
            width: completionQuotaWidths.value,
            height: completionQuotaGroupHeight
        )
        completionQuotaSymbolLabel.frame = NSRect(
            x: completionQuotaValueLabel.frame.maxX,
            y: completionQuotaGroupY + 2,
            width: completionQuotaWidths.symbol,
            height: completionQuotaGroupHeight - 4
        )
        if showsCompletionReceipt {
            let compactInset =
                CodexActivityIslandProgressBarGeometry
                .compactCompletionInset
            compactQuotaRingView.frame =
                CodexActivityIslandProgressBarGeometry
                .compactQuotaRingFrame(
                    in: textBounds
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
                height: textBounds.height
            )
        } else {
            compactQuotaRingView.frame = .zero
            compactTitleLabel.horizontalAlignment = .center
            var compactTitleFrame =
                CodexActivityIslandTextGeometry.compactTitleFrame(
                    style: islandStyle,
                    surfaceWidth: textBounds.width
                )
            compactTitleFrame.size.height = textBounds.height
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

    func setTextLayoutFrame(_ frame: NSRect, opacity: CGFloat = 1) {
        textHost.alphaValue = min(max(opacity, 0), 1)
        guard textLayoutFrame != frame else { return }
        textLayoutFrame = frame
        needsLayout = true
    }

    func setPresentationLayoutSize(_ size: NSSize) {
        guard presentationLayoutSize != size else { return }
        presentationLayoutSize = size
        synchronizeLogicalBounds()
        needsLayout = true
    }

    func visibleSurfaceFrame(in target: NSView?) -> NSRect {
        // Convert the actual surface so elastic scaling also applies to its inset.
        surface.convert(surface.bounds, to: target)
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
        // Frame is the animated visual size. Bounds is the layout before shared elastic scaling.
        let logicalSize = presentationLayoutSize ?? frame.size

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

// Reuses the single-island progress renderer and its completion skin.
@MainActor
final class IslandQuantumProgressHost: NSView {
    private let surface = ActivityIslandSurfaceView()
    private let effect = ActivityStateSmokeMetalView(frame: .zero, taskCard: true)
    private let glow = ActivityIslandCompletionGlowView(frame: .zero)
    private let outline = ActivityIslandCompletionOutlineView(frame: .zero)
    private var renderState: CodexActivityRenderState?
    private var defersCompletionSkin = false
    private var completionRiseStart: CFTimeInterval?
    private var requestedVisible = false
    private var reduceMotion = false
    private var primaryContentHeight: CGFloat?
    private var hasLaidOutEffect = false
    private(set) var effectLayoutCommitCount = 0
    var effectFrame: CGRect { effect.frame }
    var glowIsAttachedToCard: Bool { glow.superview === self }
    var glowFrameInWindow: CGRect { glow.convert(glow.bounds, to: nil) }
    var isRendering: Bool { effect.isRendererAvailable && !effect.isPaused }
    var effectAvailable: Bool { effect.isRendererAvailable }
    var effectIsHidden: Bool { effect.isHidden }
    var progressPosition: Float? { effect.displayedProgressPosition }
    var confirmationPulse: CAAnimationGroup? { effect.layer?.animation(forKey: IslandConfirmationPulse.key) as? CAAnimationGroup }
    var completionPulse: CAAnimationGroup? { glow.islandPulse }
    var completionOutlineFlow: CAKeyframeAnimation? { outline.flowAnimation }
    var completionOutlinePulse: CAAnimationGroup? { outline.layer?.animation(forKey: IslandConfirmationPulse.key) as? CAAnimationGroup }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        addSubview(glow); addSubview(surface); addSubview(outline)
        surface.useTransparentBase()
        glow.drawsOnlyEdge = true
        glow.usesContinuousCorners = true
        outline.usesContinuousCorners = true
        outline.completionRevealDelay = 0
        surface.addSubview(effect)
        effect.setEffect(.dropField)
        effect.setPlaybackEnabled(false)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func layout() {
        super.layout()
        // Child activity shares the glass card, but never enlarges the progress
        // canvas. Keep that canvas top-aligned in AppKit's coordinate space;
        // the independent completion outline/glow still follow the full card.
        let height = min(bounds.height, max(0, primaryContentHeight ?? bounds.height))
        let surfaceFrame = CGRect(x: bounds.minX, y: isFlipped ? bounds.minY : bounds.maxY - height,
            width: bounds.width, height: height)
        if surface.frame != surfaceFrame { surface.frame = surfaceFrame }
        surface.setCornerRadius(IslandVibeLayout.rowRadius)
        let effectGeometryChanged = effect.frame != surface.bounds
        if effectGeometryChanged {
            effect.frame = surface.bounds
            effectLayoutCommitCount += 1
        }
        let glowFrame = bounds.insetBy(dx: -30, dy: -30)
        if glow.frame != glowFrame { glow.frame = glowFrame }
        glow.setIslandInset(30); glow.setIslandCornerRadius(IslandVibeLayout.rowRadius)
        if outline.frame != bounds { outline.frame = bounds }
        outline.setIslandCornerRadius(IslandVibeLayout.rowRadius)
        if effectGeometryChanged || !hasLaidOutEffect { effect.redrawIfPaused() }
        hasLaidOutEffect = true
    }
    func configure(renderState: CodexActivityRenderState, visible: Bool, reduceMotion: Bool,
                   progressEffect: AppPreferences.CodexActivityProgressEffect = .dropField,
                   primaryContentHeight: CGFloat? = nil, defersCompletionSkin: Bool = false,
                   completionRiseStart: CFTimeInterval? = nil) {
        self.defersCompletionSkin = defersCompletionSkin
        self.completionRiseStart = completionRiseStart
        if self.primaryContentHeight != primaryContentHeight {
            self.primaryContentHeight = primaryContentHeight
            needsLayout = true
        }
        effect.setEffect(progressEffect)
        let newlyBound = self.renderState == nil || self.renderState?.taskIdentity != renderState.taskIdentity
        // Selecting an already completed receipt should not replay its fill.
        let completedReceipt = newlyBound && renderState.visualState == .completed
        self.renderState = renderState
        self.requestedVisible = visible
        self.reduceMotion = reduceMotion
        effect.setReduceMotion(reduceMotion || completedReceipt)
        effect.setState(renderState.visualState, taskIdentity: renderState.taskIdentity)
        effect.setApproximateProgress(renderState.approximateProgressFraction)
        if newlyBound { effect.restoreProgressPosition(renderState.approximateProgressFraction) }
        effect.setReduceMotion(reduceMotion)
        synchronizePlayback()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        synchronizePlayback()
    }
    private func synchronizePlayback() {
        let visible = requestedVisible && window != nil
        guard let renderState else { return }
        let confirming = renderState.visualState == .awaitingConfirmation
        if defersCompletionSkin && renderState.visualState == .completed {
            outline.completionRiseStart = nil
            effect.setPlaybackEnabled(visible)
            glow.update(edgeEmphasis: .none, reduceMotion: true, playbackVisible: false)
            outline.update(edgeEmphasis: .none, reduceMotion: true, playbackVisible: false)
            glow.updateIslandConfirmationPulse(animated: false)
            return
        }
        // Waiting keeps the selected progress effect at its current position.
        // Confirmation emphasis is an independent outline/glow, not a replacement.
        effect.setPlaybackEnabled(visible)
        IslandConfirmationPulse.update(effect.layer, animated: false)
        let emphasis: CodexActivityIslandEdgeEmphasis = confirming ? .confirmationReminder : CodexActivityIslandConfirmationReminderContract.edgeEmphasis(
            visualState: renderState.visualState,
            reminderActive: renderState.isConfirmationReminderActive,
            completionEffectAvailable: effect.isRendererAvailable)
        if visible && !reduceMotion && emphasis == .completion {
            outline.completionRiseStart = completionRiseStart
        } else {
            outline.completionRiseStart = nil
        }
        glow.update(edgeEmphasis: emphasis, reduceMotion: reduceMotion, playbackVisible: visible)
        outline.update(edgeEmphasis: emphasis, reduceMotion: reduceMotion || confirming, playbackVisible: visible)
        let completionBreathing = visible && !reduceMotion && (renderState.visualState == .completed || confirming)
        glow.updateIslandConfirmationPulse(animated: completionBreathing, riseStart: outline.completionRiseStart)
        // The outline circulates without pulsing its brightness; only the bloom breathes.
        IslandConfirmationPulse.update(outline.layer, animated: false)
    }
    func stop() { requestedVisible = false; synchronizePlayback() }


}
