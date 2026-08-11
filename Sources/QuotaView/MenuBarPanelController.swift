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

@MainActor
final class MenuBarPanelController: NSObject {
    private enum Metrics {
        static let contentWidth = QuotaViewFigmaMenu.designSize.width
        static let fallbackHeight = QuotaViewFigmaMenu.designSize.height
        static let screenEdgeInset: CGFloat = 8
        static let menuBarGap: CGFloat = 6
    }

    private let store: CodexStatusStore
    private let preferences: AppPreferences
    private let activityRuntime: CodexActivityRuntime
    private let updateController: AppUpdateController

    private var statusItem: NSStatusItem?
    private var panel: QuotaViewMenuPanel?
    private var hostingView: NSView?
    private var surfaceView: NSView?
    private var settingsWindowController: NSWindowController?
    private var cancellables = Set<AnyCancellable>()
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var resizeWorkItem: DispatchWorkItem?
    private var resizeAnimationTimer: Timer?
    private var resizeAnimationStartTime: TimeInterval = 0
    private var resizeAnimationStartFrame = NSRect.zero
    private var resizeAnimationTargetFrame: NSRect?
    private var resizeAnimationFixedTop: CGFloat = 0
    private var panelAnchor: PanelAnchor?
    private var isPresentingConfirmation = false
    private var glassSurfaceRequiresVisibleAttachment = true
    private var pendingGlassMode: QuotaViewGlassMode?

    private struct PanelAnchor {
        let screen: NSScreen
        let centerX: CGFloat
    }

    init(
        store: CodexStatusStore,
        preferences: AppPreferences,
        activityRuntime: CodexActivityRuntime,
        updateController: AppUpdateController
    ) {
        self.store = store
        self.preferences = preferences
        self.activityRuntime = activityRuntime
        self.updateController = updateController
        super.init()

        configureStatusItem()
        configurePanel()
        observeApplicationState()
        updateStatusItem()
        updateGlassSurface()
    }

    deinit {
        resizeAnimationTimer?.invalidate()
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
        }
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
        }
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )
        item.autosaveName = "QuotaView.StatusItem"

        if let button = item.button {
            button.target = self
            button.action = #selector(togglePanel(_:))
            button.imageScaling = .scaleProportionallyDown
            button.font = .systemFont(
                ofSize: NSFont.systemFontSize,
                weight: .semibold
            )
            button.toolTip = "QuotaView"
        }

        statusItem = item
    }

    private func configurePanel() {
        let panel = QuotaViewMenuPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: Metrics.contentWidth,
                height: Metrics.fallbackHeight
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        // Clear liquid glass uses the inactive/frosted presentation while
        // its window is non-key. This panel must be allowed to become key on
        // every presentation, not only when AppKit decides a control needs it.
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [
            .transient,
            .moveToActiveSpace,
            .fullScreenAuxiliary
        ]
        panel.animationBehavior = .utilityWindow
        panel.backgroundColor = .clear
        panel.isOpaque = false
        // NSPanel derives its built-in shadow from the rectangular window
        // frame, not from the rounded glass surface. The glass supplies its
        // own edge treatment, so keeping the window shadow disabled avoids
        // a faint square outline around the corners.
        panel.hasShadow = false

        let rootView = MenuBarPanelRoot(
            store: store,
            preferences: preferences,
            openSettingsAction: { [weak self] in
                self?.openSettings()
            },
            contentLayoutDidChange: { [weak self] in
                self?.scheduleResize()
            },
            prepareContentExpansion: { [weak self] height in
                self?.resizePanel(toContentHeight: height)
            },
            confirmationPresentationDidChange: { [weak self] isPresented in
                self?.setConfirmationPresentationActive(isPresented)
            }
        )
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = panel.contentView?.bounds ?? panel.frame
        hostingView.autoresizingMask = [.width, .height]
        hostingView.sizingOptions = [.intrinsicContentSize]

        let surface = makePanelSurface(
            hosting: hostingView,
            mode: preferences.glassMode
        )
        surface.frame = NSRect(
            origin: .zero,
            size: panel.frame.size
        )
        surface.autoresizingMask = [.width, .height]
        panel.contentView = surface

        self.panel = panel
        self.hostingView = hostingView
        surfaceView = surface

        installEventMonitors()
        scheduleResize()
    }

    private func makePanelSurface(
        hosting: NSView,
        mode: QuotaViewGlassMode
    ) -> NSView {
        if #available(macOS 26.0, *) {
            return QuotaViewLiquidGlassSurface(
                contentView: hosting,
                mode: mode
            )
        }
        return QuotaViewLegacyGlassSurface(
            contentView: hosting,
            mode: mode
        )
    }

    private func observeApplicationState() {
        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItem()
                self?.scheduleResize()
            }
            .store(in: &cancellables)

        preferences.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItem()
                self?.scheduleResize()
            }
            .store(in: &cancellables)

        preferences.$glassMode
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] mode in
                DispatchQueue.main.async {
                    self?.requestGlassSurfaceUpdate(for: mode)
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(
            for: NSApplication.didChangeScreenParametersNotification
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            guard self?.panel?.isVisible == true else { return }
            self?.positionPanel()
        }
        .store(in: &cancellables)
    }

    private func installEventMonitors() {
        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown]
        ) { [weak self] event in
            guard let self, self.panel?.isVisible == true else {
                return event
            }

            // The content-owned confirmation modal intentionally blocks
            // panel dismissal until the user confirms, cancels, or presses
            // Escape.
            if self.isPresentingConfirmation {
                return event
            }

            if event.type == .keyDown, event.keyCode == 53 {
                self.closePanel()
                return nil
            }

            let panelWindow = self.panel
            let statusWindow = self.statusItem?.button?.window
            if event.type != .keyDown,
               event.window !== panelWindow,
               event.window !== statusWindow {
                self.closePanel()
            }
            return event
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                guard self?.isPresentingConfirmation != true else {
                    return
                }
                self?.closePanel()
            }
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }

        let presentation = MenuBarStatusLabel(
            store: store,
            preferences: preferences
        )
        let title = presentation.statusTextParts.joined(separator: " ")

        button.image = preferences.showStatusIcon
            ? MenuBarBrandIcon.statusImage
            : nil
        button.title = title
        button.imagePosition = switch (
            preferences.showStatusIcon,
            title.isEmpty
        ) {
        case (true, false):
            .imageLeading
        case (true, true):
            .imageOnly
        default:
            .noImage
        }
        button.toolTip = presentation.statusAccessibilityText
        button.setAccessibilityLabel(
            presentation.statusAccessibilityText
        )
        statusItem?.length = NSStatusItem.variableLength

    }

    private func requestGlassSurfaceUpdate(
        for mode: QuotaViewGlassMode
    ) {
        pendingGlassMode = mode
        glassSurfaceRequiresVisibleAttachment = true

        guard panel?.isVisible == true else { return }
        makePanelKeyForGlassPresentation()
        updateGlassSurface(to: mode, force: true)
    }

    private func updateGlassSurface(
        to requestedMode: QuotaViewGlassMode? = nil,
        force: Bool = false
    ) {
        guard let panel, let hostingView else { return }

        let targetMode = requestedMode
            ?? pendingGlassMode
            ?? preferences.glassMode
        let modeMatches = currentGlassMode == targetMode

        // A glass view constructed or replaced while its panel is hidden
        // does not reliably establish its WindowServer backdrop until a
        // later geometry change. Keep the existing offscreen surface and
        // attach the requested one after the panel is ordered front.
        guard panel.isVisible else {
            if !modeMatches {
                glassSurfaceRequiresVisibleAttachment = true
            }
            return
        }

        guard force
                || !modeMatches
                || glassSurfaceRequiresVisibleAttachment
        else {
            return
        }

        if #available(macOS 26.0, *),
           let liquidGlass = surfaceView as? QuotaViewLiquidGlassSurface {
            liquidGlass.contentView = nil
        } else {
            hostingView.removeFromSuperview()
        }

        let replacement = makePanelSurface(
            hosting: hostingView,
            mode: targetMode
        )
        replacement.frame = NSRect(
            origin: .zero,
            size: panel.frame.size
        )
        replacement.autoresizingMask = [.width, .height]
        panel.contentView = replacement
        surfaceView = replacement
        if pendingGlassMode == targetMode {
            pendingGlassMode = nil
        }
        glassSurfaceRequiresVisibleAttachment = false
        resizePanelToFit()
        prepareGlassSurfaceForDisplay()
    }

    private var currentGlassMode: QuotaViewGlassMode? {
        if #available(macOS 26.0, *),
           let glass = surfaceView as? QuotaViewLiquidGlassSurface {
            return glass.mode
        }
        return (surfaceView as? QuotaViewLegacyGlassSurface)?.mode
    }

    private func prepareGlassSurfaceForDisplay() {
        guard let panel else { return }

        hostingView?.needsLayout = true
        hostingView?.layoutSubtreeIfNeeded()
        surfaceView?.needsLayout = true
        surfaceView?.needsDisplay = true
        surfaceView?.layoutSubtreeIfNeeded()
        panel.contentView?.needsDisplay = true
        panel.contentView?.displayIfNeeded()
        panel.displayIfNeeded()
    }

    @objc
    private func togglePanel(_ sender: Any?) {
        if panel?.isVisible == true {
            closePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let panel else { return }
        let targetMode = pendingGlassMode ?? preferences.glassMode

        capturePanelAnchor()
        resizePanelToFit()
        positionPanel()
        statusItem?.button?.highlight(true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        makePanelKeyForGlassPresentation()
        updateGlassSurface(
            to: targetMode,
            // Recreate clear glass on every open. This makes its active
            // appearance deterministic after the panel has been hidden.
            force: targetMode == .clear
        )
        prepareGlassSurfaceForDisplay()

        // Give the newly attached clear glass one WindowServer transaction
        // while fully transparent before fading the panel in.
        DispatchQueue.main.async { [weak panel] in
            guard let panel, panel.isVisible else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                context.timingFunction = CAMediaTimingFunction(
                    name: .easeOut
                )
                panel.animator().alphaValue = 1
            }
        }
    }

    private func closePanel() {
        guard let panel, panel.isVisible else { return }
        resizeWorkItem?.cancel()
        stopPanelResizeAnimation()
        if currentGlassMode == .clear {
            glassSurfaceRequiresVisibleAttachment = true
        }
        panel.orderOut(nil)
        panel.alphaValue = 1
        statusItem?.button?.highlight(false)
        panelAnchor = nil
    }

    private func setConfirmationPresentationActive(_ isActive: Bool) {
        isPresentingConfirmation = isActive
        guard let panel else { return }

        if isActive {
            NSApplication.shared.activate(ignoringOtherApps: true)
            panel.makeKey()
        }
    }

    private func makePanelKeyForGlassPresentation() {
        guard let panel else { return }

        panel.makeKey()
        guard !panel.isKeyWindow else { return }

        // `nonactivatingPanel` normally becomes key without activating its
        // LSUIElement app. If the system declines that transition, activation
        // is the last-resort path needed for a stable active glass surface.
        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.makeKey()
    }

    private func scheduleResize() {
        resizeWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.resizePanelToFit()
        }
        resizeWorkItem = workItem
        // Coalesce changes until the next main-loop layout pass, but do not
        // hold the old panel size for multiple visible frames. The previous
        // fixed 40 ms delay let SwiftUI render the new chart row count inside
        // the old window before AppKit caught up, which appeared as a jump.
        DispatchQueue.main.async(execute: workItem)
    }

    private func resizePanelToFit() {
        guard let hostingView, panel != nil else { return }

        hostingView.invalidateIntrinsicContentSize()
        hostingView.layoutSubtreeIfNeeded()
        var fittingSize = hostingView.fittingSize

        guard fittingSize.height.isFinite, fittingSize.height > 1 else {
            return
        }

        fittingSize.width = Metrics.contentWidth
        let height = ceil(fittingSize.height)
        resizePanel(toContentHeight: height)
    }

    private func resizePanel(toContentHeight height: CGFloat) {
        guard let panel else { return }

        setHostedContentHeight(height)
        let surfaceInsets = currentSurfaceInsets
        let contentSize = NSSize(
            width: Metrics.contentWidth
                + surfaceInsets.left
                + surfaceInsets.right,
            height: height
                + surfaceInsets.top
                + surfaceInsets.bottom
        )

        guard panel.isVisible else {
            panel.setContentSize(contentSize)
            return
        }

        let frameSize = panel.frameRect(
            forContentRect: NSRect(origin: .zero, size: contentSize)
        ).size
        guard let frame = anchoredPanelFrame(size: frameSize) else {
            panel.setContentSize(contentSize)
            return
        }

        if let activeTarget = resizeAnimationTargetFrame,
           NSEqualRects(activeTarget, frame) {
            return
        }
        guard !NSEqualRects(panel.frame, frame) else { return }

        let reducesMotion = NSWorkspace.shared
            .accessibilityDisplayShouldReduceMotion
        guard !reducesMotion else {
            stopPanelResizeAnimation()
            panel.setFrame(frame, display: true, animate: false)
            return
        }

        animatePanelBottomEdge(to: frame)
    }

    private func animatePanelBottomEdge(to requestedFrame: NSRect) {
        guard let panel else { return }

        stopPanelResizeAnimation()

        let startFrame = panel.frame
        let fixedTop = startFrame.maxY
        var targetFrame = requestedFrame
        targetFrame.origin.y = fixedTop - targetFrame.height

        resizeAnimationStartTime = ProcessInfo.processInfo.systemUptime
        resizeAnimationStartFrame = startFrame
        resizeAnimationTargetFrame = targetFrame
        resizeAnimationFixedTop = fixedTop

        let timer = Timer(
            timeInterval: 1.0 / 120.0,
            target: self,
            selector: #selector(advancePanelResizeAnimation(_:)),
            userInfo: nil,
            repeats: true
        )
        timer.tolerance = 1.0 / 240.0
        resizeAnimationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        advancePanelResizeAnimation(timer)
    }

    @objc
    private func advancePanelResizeAnimation(_ timer: Timer) {
        guard let panel,
              let targetFrame = resizeAnimationTargetFrame
        else {
            stopPanelResizeAnimation()
            return
        }

        let elapsed = ProcessInfo.processInfo.systemUptime
            - resizeAnimationStartTime
        let linearProgress = min(max(elapsed / 0.14, 0), 1)
        let easedProgress = 1 - pow(1 - linearProgress, 3)

        let width = interpolate(
            from: resizeAnimationStartFrame.width,
            to: targetFrame.width,
            progress: easedProgress
        )
        let height = interpolate(
            from: resizeAnimationStartFrame.height,
            to: targetFrame.height,
            progress: easedProgress
        )
        let x = interpolate(
            from: resizeAnimationStartFrame.minX,
            to: targetFrame.minX,
            progress: easedProgress
        )
        let frame = NSRect(
            x: x,
            y: resizeAnimationFixedTop - height,
            width: width,
            height: height
        )
        panel.setFrame(frame, display: true, animate: false)

        guard linearProgress >= 1 else { return }
        panel.setFrame(targetFrame, display: true, animate: false)
        stopPanelResizeAnimation()
    }

    private func stopPanelResizeAnimation() {
        resizeAnimationTimer?.invalidate()
        resizeAnimationTimer = nil
        resizeAnimationTargetFrame = nil
    }

    private func interpolate(
        from start: CGFloat,
        to end: CGFloat,
        progress: Double
    ) -> CGFloat {
        start + (end - start) * CGFloat(progress)
    }

    private var currentSurfaceInsets: NSEdgeInsets {
        if #available(macOS 26.0, *),
           let surface = surfaceView as? QuotaViewLiquidGlassSurface {
            return surface.panelInsets
        }
        return NSEdgeInsets()
    }

    private func setHostedContentHeight(_ height: CGFloat) {
        if #available(macOS 26.0, *),
           let surface = surfaceView as? QuotaViewLiquidGlassSurface {
            surface.setHostedContentHeight(height)
            return
        }

        (surfaceView as? QuotaViewLegacyGlassSurface)?
            .setHostedContentHeight(height)
    }

    private func positionPanel() {
        guard let panel,
              let frame = anchoredPanelFrame(size: panel.frame.size)
        else {
            return
        }
        panel.setFrameOrigin(frame.origin)
    }

    private func anchoredPanelFrame(size: NSSize) -> NSRect? {
        guard let panelAnchor else { return nil }

        return MenuBarPanelGeometry.anchoredFrame(
            size: size,
            centerX: panelAnchor.centerX,
            visibleFrame: panelAnchor.screen.visibleFrame,
            screenEdgeInset: Metrics.screenEdgeInset,
            menuBarGap: Metrics.menuBarGap
        )
    }

    private func capturePanelAnchor() {
        if
            let event = NSApplication.shared.currentEvent,
            let eventWindow = event.window,
            let screen = eventWindow.screen
        {
            let clickPoint = eventWindow.convertPoint(
                toScreen: event.locationInWindow
            )
            panelAnchor = PanelAnchor(
                screen: screen,
                centerX: clickPoint.x
            )
            return
        }

        guard
            let button = statusItem?.button,
            let buttonWindow = button.window,
            let screen = buttonWindow.screen ?? NSScreen.screens.first
        else {
            return
        }

        let buttonFrame = buttonWindow.convertToScreen(button.frame)
        panelAnchor = PanelAnchor(
            screen: screen,
            centerX: buttonFrame.midX
        )
    }

    private func openSettings() {
        closePanel()

        if let settingsWindowController {
            settingsWindowController.showWindow(nil)
            settingsWindowController.window?.makeKeyAndOrderFront(nil)
        } else {
            let rootView = QuotaViewSettingsWindowRoot(
                store: store,
                preferences: preferences,
                activityRuntime: activityRuntime,
                updateController: updateController
            )
            let hostingController = NSHostingController(
                rootView: rootView
            )
            let window = NSWindow(
                contentViewController: hostingController
            )
            window.title = preferences.copy.text(
                "QuotaView 设置",
                "QuotaView Settings"
            )
            window.styleMask = [
                .titled,
                .closable,
                .miniaturizable,
                .resizable,
                .fullSizeContentView
            ]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.titlebarSeparatorStyle = .none
            window.toolbar = nil
            window.isMovableByWindowBackground = true
            SettingsWindowMetrics.applyOuterShape(to: window)
            window.minSize = NSSize(width: 780, height: 560)
            window.setContentSize(
                NSSize(width: 872, height: 637)
            )
            window.isReleasedWhenClosed = false
            window.center()

            let controller = NSWindowController(window: window)
            settingsWindowController = controller
            controller.showWindow(nil)
            window.makeKeyAndOrderFront(nil)
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
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

private struct QuotaViewSettingsWindowRoot: View {
    @ObservedObject var store: CodexStatusStore
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var activityRuntime: CodexActivityRuntime
    @ObservedObject var updateController: AppUpdateController

    var body: some View {
        SettingsView(
            store: store,
            preferences: preferences,
            activityRuntime: activityRuntime,
            updateController: updateController
        )
        .environment(\.locale, preferences.locale)
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
