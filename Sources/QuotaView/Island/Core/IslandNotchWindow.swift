import AppKit
import Combine
import SwiftUI
import QuotaViewCore

// Geometry uses NSScreen's public safe/auxiliary regions, not model-specific sizes.
struct IslandNotchGeometry: Equatable {
    let screenFrame: CGRect
    let usableBottomY: CGFloat
    let cameraWidth: CGFloat
    let centerX: CGFloat
    let bandHeight: CGFloat
    let isSimulated: Bool
    var hasCamera: Bool { cameraWidth > 0 }
    var compactWidth: CGFloat { hasCamera && !isSimulated ? cameraWidth + 280 : IslandVibeLayout.compactWidth }
    var maximumExpandedWidth: CGFloat {
        min(max(IslandVibeLayout.expandedWidth, compactWidth + 64), screenFrame.width - 48)
    }
    var minimumExpandedWidth: CGFloat {
        // 144 pt of usable toolbar space on each side, plus insets and camera clearance.
        min(maximumExpandedWidth, max(CGFloat(AppPreferences.IslandExpandedWidth.range.lowerBound), cameraWidth + 360))
    }
    func expandedWidth(preferred: Double) -> CGFloat {
        let requested = AppPreferences.IslandExpandedWidth.normalized(preferred)
        if requested == AppPreferences.IslandExpandedWidth.defaultValue { return maximumExpandedWidth }
        return min(maximumExpandedWidth, max(minimumExpandedWidth, CGFloat(requested)))
    }
    var maximumExpandedHeight: CGFloat { max(0, screenFrame.maxY - usableBottomY - IslandVibeLayout.screenBottomClearance) }
    init(frame: CGRect, safeTop: CGFloat = 0, left: CGRect? = nil, right: CGRect? = nil, simulated: Bool = false, visibleFrame: CGRect? = nil) {
        screenFrame = frame
        // Keep the top attached to the display edge, reserving only the Dock/bottom clearance.
        usableBottomY = max(frame.minY, min(frame.maxY, visibleFrame?.minY ?? frame.minY))
        isSimulated = simulated
        if safeTop > 0, let left, let right, right.minX > left.maxX {
            cameraWidth = right.minX - left.maxX
            centerX = (left.maxX + right.minX) / 2
            bandHeight = simulated ? safeTop : max(32, safeTop)
        } else {
            cameraWidth = 0; centerX = frame.midX; bandHeight = 30
        }
    }
    static func simulated(in frame: CGRect, visibleFrame: CGRect? = nil) -> Self {
        // Fit the mock camera inside the existing 340 x 30 compact island.
        let halfWidth = (frame.width - 96) / 2
        return Self(frame: frame, safeTop: 30,
            left: CGRect(x: frame.minX, y: frame.maxY - 30, width: halfWidth, height: 30),
            right: CGRect(x: frame.midX + 48, y: frame.maxY - 30, width: halfWidth, height: 30),
            simulated: true, visibleFrame: visibleFrame)
    }
}

// One continuous silhouette grows from the display edge. Hardware avoidance
// belongs to the content layout, not a narrow neck above a separate wide tray.
struct IslandNotchShape: Shape {
    var bottomRadius: CGFloat
    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        // Vibe Island's visible reference uses small concave top corners and
        // larger convex bottom corners. Scale both continuously on expansion.
        let lip = min(bottomRadius * 2 / 3, min(IslandVibeLayout.maximumNotchLip, min(w / 6, h / 3)))
        let bottom = min(bottomRadius, min((w - lip * 2) / 2, h / 2))
        let arc: CGFloat = 0.5522847498
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: w, y: 0))
        // Small concave upper corners join the screen, with no horizontal shelf.
        p.addCurve(to: CGPoint(x: w - lip, y: lip), control1: CGPoint(x: w - lip * arc, y: 0), control2: CGPoint(x: w - lip, y: lip * (1 - arc)))
        p.addLine(to: CGPoint(x: w - lip, y: h - bottom))
        p.addCurve(to: CGPoint(x: w - lip - bottom, y: h), control1: CGPoint(x: w - lip, y: h - bottom * (1 - arc)), control2: CGPoint(x: w - lip - bottom * (1 - arc), y: h))
        p.addLine(to: CGPoint(x: lip + bottom, y: h))
        p.addCurve(to: CGPoint(x: lip, y: h - bottom), control1: CGPoint(x: lip + bottom * (1 - arc), y: h), control2: CGPoint(x: lip, y: h - bottom * (1 - arc)))
        p.addLine(to: CGPoint(x: lip, y: lip))
        p.addCurve(to: CGPoint(x: 0, y: 0), control1: CGPoint(x: lip, y: lip * (1 - arc)), control2: CGPoint(x: lip * arc, y: 0))
        p.closeSubpath(); return p
    }
}

private enum IslandSurfaceMotion {
    static let duration: Double = 0.38
    static let contentDuration: Double = 0.23
    static var animation: Animation { .timingCurve(0.22, 1, 0.36, 1, duration: duration) }
    static var timingFunction: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
    }
}

// Only this lightweight backdrop tree animates its layout. Task/approval content
// and the native window keep their final frames throughout a transition.
@MainActor
private final class IslandGlassGeometry: ObservableObject {
    struct Value: Equatable {
        var rect: CGRect
        var radius: CGFloat
        var compact: Bool
    }
    @Published private(set) var value: Value
    @Published private(set) var degree: Double
    @Published private(set) var generation = 0
    private var animationDeadline: CFTimeInterval = 0

    init(value: Value, degree: Double) {
        self.value = value
        self.degree = degree
    }

    func update(value: Value, degree: Double, animated: Bool) {
        if self.degree != degree { self.degree = degree }
        if animated {
            guard self.value != value else { return }
            // Stable identity lets SwiftUI retarget from the current interpolated
            // geometry, including an immediate reversal before the first ends.
            animationDeadline = CACurrentMediaTime() + IslandSurfaceMotion.duration
            withAnimation(IslandSurfaceMotion.animation) { self.value = value }
        } else {
            let wasAnimating = animationDeadline > CACurrentMediaTime()
            guard self.value != value || wasAnimating else { return }
            animationDeadline = 0
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                self.value = value
                // Snap only when motion is explicitly disabled or the window
                // geometry changes; normal page changes never reset identity.
                if wasAnimating { generation &+= 1 }
            }
        }
    }

    func stop() {
        guard animationDeadline > CACurrentMediaTime() else { return }
        animationDeadline = 0
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { generation &+= 1 }
    }

}

/// Uses the existing snapshot and session clock; never issues a quota request.
struct IslandFloatingQuotaPeriods {
    static func windows(_ windows: [CodexQuotaWindowPresentation]) -> [CodexQuotaWindowPresentation?] {
        let short = windows.first { $0.windowDurationMinutes == 300 }
        let week = windows.first { $0.windowDurationMinutes == 10080 }
        return short.map { [$0, week] } ?? [week]
    }
}

private struct IslandFloatingUsageCapsule: View {
    @ObservedObject var state: IslandBoardState
    @ObservedObject var geometry: IslandGlassGeometry

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if state.showsFloatingUsage {
                IslandUsageCapsuleContent(windows: state.display?.usageSnapshot?.quotaWindows ?? [],
                    current: state.display?.usageState.isCurrent == true,
                    english: state.english, now: state.floatingUsageClock.now)
                    .environment(\.appLanguage, state.language)
                .position(x: geometry.value.rect.midX, y: geometry.value.rect.maxY + 24)
            }
        }
        .id(geometry.generation)
        .modifier(IslandGlassColorScheme())
        .modifier(IslandGlassAppearanceContext(appearance: state.display?.islandGlassAppearance ?? .dark,
            material: state.display?.islandMaterial ?? .liquidGlass))
        .environment(\.islandLiquidGlassEnabled, state.display?.islandMaterial != .classic)
        .allowsHitTesting(false)
    }

}

/// Shared artwork; callers supply either live usage or isolated settings illustration data.
struct IslandUsageCapsuleContent: View {
    @Environment(\.appLanguage) private var appLanguage
    let windows: [CodexQuotaWindowPresentation]
    let current: Bool
    let english: Bool
    let now: Date
    @Environment(\.colorScheme) private var colorScheme
    private var ink: Color { colorScheme == .light ? .black : .white }
    private var solid: Color { Color(white: colorScheme == .dark ? 0.12 : 0.92) }

    var body: some View {
        let periods = IslandFloatingQuotaPeriods.windows(windows)
        HStack(spacing: 12) {
            ForEach(periods.indices, id: \.self) { index in
                if index > 0 { Capsule().fill(ink.opacity(0.22)).frame(width: 1, height: 12) }
                period(periods[index], short: periods.count == 2 && index == 0)
            }
        }
        .font(.system(size: 12, weight: .medium)).foregroundStyle(ink)
        .padding(.horizontal, 12).frame(height: 32).fixedSize()
        .modifier(IslandNativeBackdropMaterial(shape: Capsule(), solidTint: solid))
    }

    private func period(_ window: CodexQuotaWindowPresentation?, short: Bool) -> some View {
        let percent = current ? window?.remainingPercent : nil
        let copy = AppCopy(language: appLanguage ?? (english ? .english : .simplifiedChinese))
        let countdown = copy.quotaCountdown(until: current ? window?.resetsAt : nil, now: now)
        let title = (short ? copy.text("5小时", "5h") : copy.text("周额度", "Weekly"))
        let value = percent.map { "\(min(100, max(0, $0)))%" } ?? "—"
        return HStack(spacing: 6) {
            IslandQuotaRing(remainingPercent: percent)
            Text(title)
            Text(value).monospacedDigit()
            Text(window?.resetsAt != nil && current ? copy.text("\(countdown)重置", "Resets in \(countdown)") : copy.text("重置时间 —", "Reset —"))
                .foregroundStyle(ink.opacity(0.78)).monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(copy.text("\(title)，剩余 \(value)，\(countdown)后重置", "\(title), \(value) remaining, resets in \(countdown)"))
    }
}

private struct IslandExpandedGlassBackdrop: View {
    @ObservedObject var geometry: IslandGlassGeometry
    @ObservedObject var state: IslandBoardState

    var body: some View {
        let value = geometry.value
        let shape = IslandNotchShape(bottomRadius: value.radius)
        let stops = AppPreferences.IslandGlassDegree.gradientStops(geometry.degree)
        ZStack(alignment: .topLeading) {
            Color.clear
            Color.clear
                .frame(width: value.rect.width, height: value.rect.height)
                .modifier(IslandNativeBackdropMaterial(shape: shape))
                .overlay {
                    // Only the shade is clipped. Native glass owns its contour.
                    LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
                    .clipShape(shape)
                }
                .overlay { shape.fill(.black).opacity(value.compact ? 1 : 0) }
                .position(x: value.rect.midX, y: value.rect.midY)
        }
        .id(geometry.generation)
        .modifier(IslandGlassColorScheme())
        .modifier(IslandGlassAppearanceContext(appearance: state.display?.islandGlassAppearance ?? .dark,
            material: state.display?.islandMaterial ?? .liquidGlass))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Shared untinted material for the island shell, floating capsule and settings preview.
struct IslandNativeBackdropMaterial<Outline: Shape>: ViewModifier {
    var shape: Outline
    var solidTint: Color = .black
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.islandLiquidGlassEnabled) private var liquidGlassEnabled

    func body(content: Content) -> some View {
        if reduceTransparency || !liquidGlassEnabled {
            content.background(solidTint, in: shape)
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.clear, in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
        }
    }
}

/// Fixed window and content frames; a small native backdrop tree owns geometry
/// interpolation, while the classic shell keeps its existing path animation.
@MainActor
final class IslandNotchSurface: NSView {
    override var isFlipped: Bool { true }
    private let state: IslandBoardState
    let confirmationGlow = ActivityIslandCompletionGlowView(frame: .zero)
    private let shell = CAShapeLayer()
    private let clipping = CAShapeLayer()
    private let glassContainer = NSView()
    private var glassMaterial: NSHostingView<IslandExpandedGlassBackdrop>?
    private var glassGeometry: IslandGlassGeometry?
    private let floatingUsageGeometry = IslandGlassGeometry(value: .init(rect: .zero, radius: 0, compact: true), degree: 0)
    private var floatingUsageHost: NSHostingView<IslandFloatingUsageCapsule>?
    private let content = NSView()
    private let compactHost: NSHostingView<IslandBoardView>
    private let expandedHost: NSHostingView<IslandBoardView>
    private let taskScrollLink: IslandTaskScrollLink
    private(set) var targetRect = CGRect.zero
    private var lastCompact: Bool?
    private(set) var transitionCount = 0
    private(set) var layoutCommitCount = 0


    init(state: IslandBoardState) {
        self.state = state
        taskScrollLink = state.taskScrollLink
        compactHost = NSHostingView(rootView: IslandBoardView(state: state, compactContent: true))
        expandedHost = NSHostingView(rootView: IslandBoardView(state: state, compactContent: false))
        super.init(frame: .zero)
        wantsLayer = true; content.wantsLayer = true
        compactHost.wantsLayer = true; expandedHost.wantsLayer = true
        compactHost.sizingOptions = []; expandedHost.sizingOptions = []
        shell.fillColor = NSColor.black.cgColor
        shell.shadowColor = NSColor.black.cgColor
        shell.shadowOpacity = 0.26; shell.shadowRadius = 10
        shell.shadowOffset = CGSize(width: 0, height: 4)
        // Restore the full reminder fill; attenuate its parent so the pulse
        // cannot animate the original full brightness back in.
        confirmationGlow.drawsOnlyEdge = false
        confirmationGlow.alphaValue = 0.28
        addSubview(confirmationGlow)
        confirmationGlow.layer?.zPosition = -1
        layer?.addSublayer(shell)
        // One native backdrop for the whole expanded island. No snapshots,
        // private filters or display links. Cards own their separate content.
        glassContainer.wantsLayer = true
        addSubview(glassContainer)
        addSubview(content); content.layer?.mask = clipping
        content.addSubview(expandedHost); content.addSubview(compactHost)
        let usageHost = NSHostingView(rootView: IslandFloatingUsageCapsule(state: state, geometry: floatingUsageGeometry))
        usageHost.sizingOptions = []
        floatingUsageHost = usageHost
        addSubview(usageHost)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func synchronizeGlassMaterial(enabled: Bool, rect: CGRect, radius: CGFloat,
                                          compact: Bool, degree: Double, animated: Bool) {
        guard enabled else {
            glassMaterial?.removeFromSuperview()
            glassMaterial = nil
            glassGeometry = nil
            return
        }
        let value = IslandGlassGeometry.Value(rect: rect, radius: radius, compact: compact)
        if let glassMaterial, let glassGeometry {
            if glassMaterial.frame != glassContainer.bounds { glassMaterial.frame = glassContainer.bounds }
            glassGeometry.update(value: value, degree: degree, animated: animated)
        } else {
            let geometry = IslandGlassGeometry(value: value, degree: degree)
            let host = NSHostingView(rootView: IslandExpandedGlassBackdrop(geometry: geometry, state: state))
            host.sizingOptions = []
            host.frame = glassContainer.bounds
            glassGeometry = geometry
            glassMaterial = host
            glassContainer.addSubview(host)
            host.layoutSubtreeIfNeeded()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stop() }
    }

    override func viewWillDraw() {
        // Final pre-display boundary, including a late clamp within the same
        // native layout pass. No frame is drawn at the temporary top position.
        taskScrollLink.finishLayoutChange()
        super.viewWillDraw()
    }

    func update(state: IslandBoardState, animated: Bool) {
        let newRect = CGRect(x: (bounds.width - state.surfaceWidth) / 2, y: 0,
                             width: state.surfaceWidth, height: state.height)
        let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let usesGlass = state.display?.islandMaterial != .classic && !reduceTransparency
        let changed = targetRect != newRect || lastCompact != state.compact || content.frame != bounds
            || glassContainer.isHidden == usesGlass
        let radius: CGFloat = state.compact ? 13 : 24
        let compactFrame = CGRect(x: (bounds.width - state.compactWidth) / 2,
                                  y: bounds.height - state.geometry.bandHeight,
                                  width: state.compactWidth, height: state.geometry.bandHeight)
        let expandedFrame = CGRect(x: (bounds.width - state.expandedWidth) / 2,
                                   y: bounds.height - state.expandedCanvasHeight,
                                   width: state.expandedWidth, height: state.expandedCanvasHeight)
        // content is unflipped. Its hosted views are laid out once at final size.
        CATransaction.begin(); CATransaction.setDisableActions(true)
        if confirmationGlow.frame != bounds { confirmationGlow.frame = bounds }
        if content.frame != bounds { content.frame = bounds }
        if glassContainer.frame != bounds { glassContainer.frame = bounds }
        glassContainer.isHidden = !usesGlass
        // The native material owns each card's outline. Do not flatten these
        // backdrop-sampling descendants through the whole-island mask either.
        content.layer?.mask = usesGlass ? nil : clipping
        shell.fillColor = usesGlass ? NSColor.clear.cgColor : NSColor.black.cgColor
        if compactHost.frame != compactFrame { compactHost.frame = compactFrame; layoutCommitCount += 1 }
        if expandedHost.frame != expandedFrame { expandedHost.frame = expandedFrame; layoutCommitCount += 1 }
        if taskScrollLink.isChangingLayout { expandedHost.layoutSubtreeIfNeeded() }
        CATransaction.commit()
        if floatingUsageHost?.frame != bounds { floatingUsageHost?.frame = bounds }
        floatingUsageGeometry.update(value: .init(rect: newRect, radius: radius, compact: state.compact), degree: 0, animated: animated)
        if !animated { cancelAnimations() }
        synchronizeGlassMaterial(enabled: usesGlass, rect: newRect, radius: radius,
            compact: state.compact,
            degree: state.display?.islandGlassDegree ?? AppPreferences.IslandGlassDegree.defaultValue,
            animated: animated)
        confirmationGlow.confirmationColor = state.showsResetConfirmationGlow ? .systemRed : nil
        confirmationGlow.update(
            edgeEmphasis: state.showsResetConfirmationGlow || state.tasks.contains { IslandBoardState.needsAttention($0) }
                ? .confirmationReminder : .none,
            reduceMotion: state.reduceMotion || state.display?.playbackEnabled != true,
            playbackVisible: state.display?.visible == true && window != nil)
        confirmationGlow.updateIslandConfirmationPulse(animated: state.playback)
        guard changed else { return }
        let oldPath = shell.presentation()?.path ?? shell.path
        let path = shapePath(rect: newRect, radius: radius)
        // Mask lives on an unflipped content layer; mirror only its geometry.
        var mirror = CGAffineTransform(translationX: 0, y: bounds.height).scaledBy(x: 1, y: -1)
        let maskPath = path.copy(using: &mirror)!
        let oldMask = clipping.presentation()?.path ?? clipping.path
        let duration = IslandSurfaceMotion.duration
        let sourceInset = CodexActivityIslandCompletionGlowGeometry.sourceInset
        let glowPath = shapePath(rect: newRect.insetBy(dx: sourceInset, dy: sourceInset), radius: radius - sourceInset)
        confirmationGlow.setIslandContour(glowPath.copy(using: &mirror)!,
            duration: animated && !confirmationGlow.isHidden ? duration : nil)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        shell.path = path; shell.shadowPath = path; clipping.path = maskPath
        // The classic shadowPath paints a full dark silhouette beneath clear glass.
        // Native glass already supplies its own depth; avoid doubling that backing.
        shell.shadowOpacity = usesGlass ? 0 : (state.compact ? 0.10 : 0.26)
        shell.shadowRadius = state.compact ? 5 : 10
        CATransaction.commit()
        if animated, let oldPath, let oldMask {
            transitionCount += 1
            animate(layer: shell, key: "path", from: oldPath, to: path, duration: duration)
            animate(layer: shell, key: "shadowPath", from: oldPath, to: path, duration: duration)
            animate(layer: clipping, key: "path", from: oldMask, to: maskPath, duration: duration)
        }
        if lastCompact != state.compact {
            setContent(compactHost, visible: state.compact, animated: animated)
            setContent(expandedHost, visible: !state.compact, animated: animated)
        }
        targetRect = newRect; lastCompact = state.compact
        compactHost.setAccessibilityHidden(!state.compact)
        expandedHost.setAccessibilityHidden(state.compact)
    }
    private func shapePath(rect: CGRect, radius: CGFloat) -> CGPath {
        var transform = CGAffineTransform(translationX: rect.minX, y: rect.minY)
        return IslandNotchShape(bottomRadius: radius).path(in: CGRect(origin: .zero, size: rect.size)).cgPath.copy(using: &transform)!
    }
    private func animate(layer: CALayer, key: String, from: Any, to: Any, duration: Double) {
        let animation = CABasicAnimation(keyPath: key)
        animation.fromValue = from; animation.toValue = to; animation.duration = duration
        animation.timingFunction = IslandSurfaceMotion.timingFunction
        layer.add(animation, forKey: key)
    }
    private func setContent(_ host: NSView, visible: Bool, animated: Bool) {
        guard let layer = host.layer else { return }
        let previous = layer.presentation()?.opacity ?? layer.opacity
        let oldTransform = layer.presentation()?.transform ?? layer.transform
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.opacity = visible ? 1 : 0
        layer.transform = visible ? CATransform3DIdentity : CATransform3DMakeTranslation(0, 5, 0)
        CATransaction.commit()
        if animated {
            animate(layer: layer, key: "opacity", from: previous, to: layer.opacity, duration: IslandSurfaceMotion.contentDuration)
            animate(layer: layer, key: "transform", from: NSValue(caTransform3D: oldTransform),
                    to: NSValue(caTransform3D: layer.transform), duration: IslandSurfaceMotion.duration)
        }
    }
    func containsSurfacePoint(_ point: CGPoint) -> Bool {
        (shell.presentation()?.path ?? shell.path)?.contains(point) ?? false
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        // AppKit supplies hitTest points in the superview's coordinates. This
        // surface is flipped; using the raw point mirrors the clickable areas.
        let local = convert(point, from: superview)
        guard containsSurfacePoint(local) else { return nil }
        let host: NSView = lastCompact == true ? compactHost : expandedHost
        return host.hitTest(convert(local, to: content))
    }
    var hasActiveAnimations: Bool {
        [shell, clipping, compactHost.layer, expandedHost.layer].compactMap { $0 }
            .contains { !($0.animationKeys() ?? []).isEmpty }
            || (confirmationGlow.layer?.sublayers ?? []).contains { !($0.animationKeys() ?? []).isEmpty }
    }
    func cancelAnimations() {
        [shell, clipping, compactHost.layer, expandedHost.layer].compactMap { $0 }.forEach { $0.removeAllAnimations() }
        confirmationGlow.cancelIslandContourAnimations()
    }
    func stop() {
        cancelAnimations()
        glassGeometry?.stop()
        floatingUsageGeometry.stop()
        confirmationGlow.update(edgeEmphasis: .none, reduceMotion: true, playbackVisible: false)
    }
}

private final class IslandNotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    // AppKit compatibility hooks, NOT public SDK API; approved 2026-10-11.
    // Keep only this island's material active, including its first hover open.
    // Actual key status, first responder and event routing remain untouched.
    // These constant appearance queries are safe off the main thread too.
    @objc(hasKeyAppearance)
    private nonisolated func islandKeyAppearance() -> Bool { true }

    @objc(_hasKeyAppearance)
    private nonisolated func islandInternalKeyAppearance() -> Bool { true }

    @objc(_hasActiveAppearance)
    private nonisolated func islandActiveAppearance() -> Bool { true }

    @objc(_hasActiveAppearanceIgnoringKeyFocus)
    private nonisolated func islandActiveAppearanceIgnoringKeyFocus() -> Bool { true }
}

@MainActor
final class IslandBoardController {
    let state = IslandBoardState()
    private let panel: NSPanel
    let surface: IslandNotchSurface
    private let presentsWindows: Bool
    private var monitors: [Any] = []
    private var screenObserver: NSObjectProtocol?
    private var hoverOpen: DispatchWorkItem?
    private var hoverClose: DispatchWorkItem?
    private var transitionHitUpdate: DispatchWorkItem?
    private var pointerInside = false
    private var suppressHoverUntilExit = false
    private var lastPresentation: IslandBoardState.Presentation = .resting
    var screen: NSScreen?
    private var simulateHardwareNotch = false
    var onSelect: ((Int) -> Void)?
    var onConfirmation: ((Int, UUID, IslandConfirmationDecision) -> Void)?
    var onClaimConfirmation: ((Int, UUID) -> Void)?
    var onDismissConfirmation: ((Int, UUID) -> Void)?
    var isVisible: Bool { panel.isVisible }
    var frame: CGRect { panel.frame }
    var blocksPointerScreenSwitch: Bool {
        guard panel.isVisible else { return false }
        if containsPointer() || (panel.isKeyWindow && panel.firstResponder is NSTextView) { return true }
        if case .submitting = state.approval?.request.phase { return true }
        return false
    }
    func move(to destination: NSScreen) {
        guard screen != destination else { return }
        hoverOpen?.cancel(); hoverClose?.cancel(); hoverOpen = nil; hoverClose = nil
        pointerInside = false; suppressHoverUntilExit = false
        screen = destination
        syncGeometry(); refresh()
    }
    init(presentsWindows: Bool = true) {
        self.presentsWindows = presentsWindows
        panel = IslandNotchPanel(contentRect: .init(x: 0, y: 0, width: 468, height: 352),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        surface = IslandNotchSurface(state: state)
        panel.isReleasedWhenClosed = false; panel.isFloatingPanel = true
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.canHide = false
        panel.hidesOnDeactivate = false; panel.level = .init(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        panel.animationBehavior = .none; panel.contentView = surface
        panel.title = (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "QuotaView")
            + " · " + state.text("任务", "Tasks")
        panel.isExcludedFromWindowsMenu = false
        panel.acceptsMouseMovedEvents = true
        state.onSelect = { [weak self] in self?.onSelect?($0) }
        state.onConfirmation = { [weak self] id, requestID, decision in self?.onConfirmation?(id, requestID, decision) }
        state.onClaimConfirmation = { [weak self] id, requestID in self?.onClaimConfirmation?(id, requestID) }
        state.onDismissConfirmation = { [weak self] id, requestID in self?.onDismissConfirmation?(id, requestID) }
        state.onChange = { [weak self] in self?.refresh() }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .keyDown], handler: { [weak self] event in
            guard let self, panel.isVisible else { return event }
            trackPointer()
            if event.type == .keyDown, event.keyCode == 53, panel.isKeyWindow, !(panel.firstResponder is NSTextView) {
                state.escape(); return nil
            }
            if event.type == .leftMouseDown || event.type == .rightMouseDown { dismissOutside() }
            return event
        }) { monitors.append(local) }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            self?.trackPointer()
            if event.type == .leftMouseDown || event.type == .rightMouseDown { self?.dismissOutside() }
        }) { monitors.append(global) }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.syncGeometry(); self?.refresh() }
            }
    }
    deinit {
        monitors.forEach(NSEvent.removeMonitor)
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        hoverOpen?.cancel(); hoverClose?.cancel(); transitionHitUpdate?.cancel()
    }
    private func syncGeometry() {
        let target = screen.flatMap { requested in NSScreen.screens.first { $0 == requested } } ?? NSScreen.main
        guard let target else { return }
        if simulateHardwareNotch {
            state.setGeometry(.simulated(in: target.frame, visibleFrame: target.visibleFrame))
            return
        }
        state.setGeometry(IslandNotchGeometry(frame: target.frame, safeTop: target.safeAreaInsets.top,
            left: target.auxiliaryTopLeftArea, right: target.auxiliaryTopRightArea, visibleFrame: target.visibleFrame))
    }
    func update(model: CodexMultitaskDisplay, reduceMotion: Bool, simulateHardwareNotch: Bool = false) {
        self.simulateHardwareNotch = simulateHardwareNotch
        syncGeometry(); state.update(model, reduceMotion: reduceMotion)
    }
    private func refresh() {
        if state.presentation == .resting && lastPresentation != .resting {
            suppressHoverUntilExit = pointerInside
            hoverOpen?.cancel(); hoverOpen = nil
        }
        let becamePinned = state.presentation == .pinned && lastPresentation != .pinned
        lastPresentation = state.presentation
        let area = state.geometry.screenFrame
        // Reserve the usable display height once, allowing confirmation content
        // to grow without resizing the native window on each request or animation frame.
        let width = state.maximumExpandedWidth + IslandVibeLayout.outerEffectInset * 2
        let height = min(area.height, state.geometry.maximumExpandedHeight + IslandVibeLayout.screenBottomClearance)
        // Anchor to the actual display edge, never the menu-bar-excluding visibleFrame.
        let next = CGRect(x: state.geometry.centerX - width / 2, y: area.maxY - height, width: width, height: height)
        let geometryChanged = panel.frame != next
        if geometryChanged { panel.setFrame(next, display: false) }
        surface.update(state: state, animated: panel.isVisible && !geometryChanged && !state.reduceMotion && state.display?.visible == true)
        if state.display?.visible == true && presentsWindows {
            if !panel.isVisible {
                panel.orderFrontRegardless()
                NSApp.addWindowsItem(panel, title: panel.title, filename: false)
            }
            if becamePinned { panel.makeKey() }
        } else {
            hoverOpen?.cancel(); hoverClose?.cancel(); hoverOpen = nil; hoverClose = nil
            pointerInside = false; suppressHoverUntilExit = false
            panel.orderOut(nil)
        }
        // Do not synthesize a hover entry on launch/resize; only real mouse events
        // drive the dwell timer. This also prevents collapse/reopen loops.
        panel.ignoresMouseEvents = !containsPointer()
        transitionHitUpdate?.cancel(); transitionHitUpdate = nil
        if panel.isVisible && !state.reduceMotion {
            // One completion check releases transparent space even when the
            // pointer stays still while the shell shrinks underneath it.
            let work = DispatchWorkItem { [weak self] in
                guard let self, panel.isVisible else { return }
                transitionHitUpdate = nil; trackPointer()
            }
            transitionHitUpdate = work
            DispatchQueue.main.asyncAfter(deadline: .now() + IslandSurfaceMotion.duration + 0.02, execute: work)
        }
    }
    private func containsPointer() -> Bool {
        let point = NSEvent.mouseLocation
        let local = CGPoint(x: point.x - panel.frame.minX, y: panel.frame.maxY - point.y)
        return surface.containsSurfacePoint(local)
    }
    private func trackPointer() {
        guard panel.isVisible else { return }
        let inside = containsPointer()
        panel.ignoresMouseEvents = !inside
        guard inside != pointerInside else { return }
        pointerInside = inside
        hoverOpen?.cancel(); hoverClose?.cancel(); hoverOpen = nil; hoverClose = nil
        if inside && state.compact && !suppressHoverUntilExit {
            let work = DispatchWorkItem { [weak self] in
                guard let self, pointerInside, panel.isVisible, !suppressHoverUntilExit else { return }
                hoverOpen = nil; state.preview()
            }
            hoverOpen = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        } else if !inside {
            suppressHoverUntilExit = false
            if state.presentation == .preview {
                let work = DispatchWorkItem { [weak self] in
                    guard let self, !pointerInside, !(panel.firstResponder is NSTextView), state.approval?.request.phase.canSubmit != false else { return }
                    hoverClose = nil; state.endPreview()
                }
                hoverClose = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
            }
        }
    }
    private func dismissOutside() {
        if panel.isVisible && !containsPointer() && !state.compact { state.dismissFromOutside() }
    }
    func stop() {
        surface.stop()
        transitionHitUpdate?.cancel(); transitionHitUpdate = nil
        hoverOpen?.cancel(); hoverClose?.cancel(); hoverOpen = nil; hoverClose = nil
        if var display = state.display { display.visible = false; state.update(display, reduceMotion: state.reduceMotion) }
        panel.orderOut(nil)
        NSApp.removeWindowsItem(panel)
    }
}
