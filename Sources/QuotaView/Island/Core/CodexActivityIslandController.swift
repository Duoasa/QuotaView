import AppKit
import QuartzCore
import QuotaViewCore

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
    private let canvas = NSView()
    private let canvasSize = NSSize(width: 640, height: 210)
    private var motion: ActivityIslandMotion
    private var pose: ActivityIslandMotion.Pose
    private var layoutPose: ActivityIslandMotion.Pose
    private var textPose: ActivityIslandMotion.Pose
    private var compactSize: NSSize
    private let panelInset: CGFloat
    private var transitionTimer: Timer?
    private var requestedPlayback = false
    private var reduceMotion = false
    private var hoverTransparency = CodexActivityIslandHoverTransparencyContract()
    private var hoverTransparencyPercent = CodexActivityIslandHoverTransparencyContract.defaultTransparencyPercent
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?

    init(
        initialState: CodexActivityRenderState,
        progressEffect: AppPreferences.CodexActivityProgressEffect,
        screenPlacement: AppPreferences.CodexActivityScreenPlacement,
        codexProcessIdentifier: pid_t?
    ) {
        let inset = CodexActivityIslandGeometry.panelInset
        panelInset = inset
        let hidden = ActivityIslandMotion.hiddenPose(inset: inset)
        pose = hidden
        layoutPose = hidden
        textPose = hidden
        motion = ActivityIslandMotion(pose: hidden)
        compactSize = CodexActivityIslandGeometry.panelSize(presentation: .compact, renderState: initialState)
        content = ActivityIslandContentView(initialState: initialState, progressEffect: progressEffect)
        panel = CodexActivityPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 210),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        canvas.wantsLayer = true
        canvas.layer?.masksToBounds = true
        canvas.addSubview(content)
        panel.contentView = canvas
        positionPanel(animated: false, screenPlacement: screenPlacement, codexProcessIdentifier: codexProcessIdentifier)
        renderPose()
        installHoverMonitors()
    }

    deinit {
        transitionTimer?.invalidate()
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
    }

    func update(
        renderState: CodexActivityRenderState,
        presentationMode: CodexActivityIslandPresentation,
        presentationAccessibilityValue: String,
        reduceMotion: Bool,
        progressEffect: AppPreferences.CodexActivityProgressEffect,
        hoverTransparencyPercent: Int,
        screenPlacement: AppPreferences.CodexActivityScreenPlacement,
        codexProcessIdentifier: pid_t?,
        playbackEnabled: Bool
    ) {
        let wasHidden = motion.target.visibility == 0
        self.reduceMotion = reduceMotion
        self.hoverTransparencyPercent = hoverTransparencyPercent
        requestedPlayback = playbackEnabled
        content.setReduceMotion(reduceMotion)
        content.update(renderState: renderState, progressEffect: progressEffect)
        content.setPresentationMode(presentationMode, accessibilityValue: presentationAccessibilityValue)
        compactSize = CodexActivityIslandGeometry.panelSize(presentation: .compact, renderState: renderState)
        let size = CodexActivityIslandGeometry.panelSize(presentation: presentationMode, renderState: renderState)
        motion.present(.init(width: size.width, height: size.height, visibility: 1),
                       at: ProcessInfo.processInfo.systemUptime,
                       resizeDuration: presentationMode.transitionDuration,
                       elasticResize: presentationMode == .expanded, reduceMotion: reduceMotion)
        positionPanel(animated: false, screenPlacement: screenPlacement, codexProcessIdentifier: codexProcessIdentifier)
        if wasHidden {
            hoverTransparency = CodexActivityIslandHoverTransparencyContract()
            panel.alphaValue = CodexActivityIslandHoverTransparencyContract.restingAlpha
        }
        // Apply the small/transparent first frame before exposing the window.
        advanceTransition()
        panel.orderFrontRegardless()
        synchronizePlayback()
        startTransitionIfNeeded()
        updateHoverAppearance(animated: !reduceMotion)
    }

    func hide(animated: Bool = true) {
        motion.hide(compact: .init(width: compactSize.width, height: compactSize.height, visibility: 1),
                    inset: panelInset, at: ProcessInfo.processInfo.systemUptime,
                    animated: animated && !reduceMotion && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        advanceTransition()
        startTransitionIfNeeded()
    }

    // Logical visibility ends when dismissal starts, so runtime screen polling can stop immediately.
    var isVisible: Bool { motion.target.visibility > 0 && panel.isVisible }

    func reposition(
        screenPlacement: AppPreferences.CodexActivityScreenPlacement,
        codexProcessIdentifier: pid_t?
    ) {
        guard isVisible else { return }
        positionPanel(animated: !reduceMotion, screenPlacement: screenPlacement,
                      codexProcessIdentifier: codexProcessIdentifier)
        updateHoverAppearance(animated: !reduceMotion)
    }

    private func positionPanel(
        animated: Bool,
        screenPlacement: AppPreferences.CodexActivityScreenPlacement,
        codexProcessIdentifier: pid_t?
    ) {
        guard let screen = targetScreen(for: screenPlacement, codexProcessIdentifier: codexProcessIdentifier) else { return }
        let visibleFrame = screen.visibleFrame
        let frame = NSRect(x: visibleFrame.midX - canvasSize.width / 2,
                           y: visibleFrame.maxY - canvasSize.height,
                           width: canvasSize.width, height: canvasSize.height)
        guard panel.frame != frame else { return }
        if animated && panel.isVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.20
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    private func startTransitionIfNeeded() {
        guard transitionTimer == nil, motion.isAnimating(at: ProcessInfo.processInfo.systemUptime) else { return }
        let timer = Timer(timeInterval: 1 / 60.0, repeats: true) { [weak self] _ in
            // This timer is installed exclusively on RunLoop.main below.
            MainActor.assumeIsolated { self?.advanceTransition() }
        }
        timer.tolerance = 0.002
        RunLoop.main.add(timer, forMode: .common)
        transitionTimer = timer
    }

    private func advanceTransition() {
        let now = ProcessInfo.processInfo.systemUptime
        pose = motion.sample(at: now)
        layoutPose = motion.sampleLayout(at: now)
        textPose = motion.sampleText(at: now)
        renderPose()
        if !motion.isAnimating(at: now) {
            transitionTimer?.invalidate()
            transitionTimer = nil
            if motion.target.visibility == 0 {
                panel.orderOut(nil)
                hoverTransparency = CodexActivityIslandHoverTransparencyContract()
                panel.alphaValue = CodexActivityIslandHoverTransparencyContract.restingAlpha
            }
        }
        synchronizePlayback()
        updateHoverAppearance(animated: !reduceMotion)
    }

    private func renderPose() {
        content.setPresentationLayoutSize(NSSize(width: layoutPose.width, height: layoutPose.height))
        content.frame = pose.frame(in: canvas.bounds, inset: panelInset)
        content.setTextLayoutFrame(textPose.frame(relativeTo: layoutPose, inset: panelInset), opacity: textPose.visibility)
        content.alphaValue = pose.visibility
        content.isHidden = pose.visibility == 0
        content.layoutSubtreeIfNeeded()
    }

    private func synchronizePlayback() {
        content.setPlaybackVisible(requestedPlayback && panel.isVisible
            && (pose.visibility > 0 || motion.target.visibility > 0))
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
        let hoverFrame = panel.convertToScreen(content.visibleSurfaceFrame(in: nil))
        let isHovering =
            panel.isVisible
            && pose.visibility > 0
            && hoverFrame.intersection(panel.frame).contains(NSEvent.mouseLocation)
        let targetChanged = hoverTransparency.update(
            isHovering: isHovering,
            transparencyPercent: hoverTransparencyPercent
        )
        let targetAlpha = hoverTransparency.targetAlpha

        guard animated, !reduceMotion else {
            panel.alphaValue = targetAlpha
            return
        }
        guard targetChanged else { return }

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
