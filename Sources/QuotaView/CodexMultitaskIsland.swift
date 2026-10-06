import AppKit
import SwiftUI
import QuotaViewCore

// A clipped text viewport, animated within the same jelly container as the
// satellite shell. No per-frame timer or duplicate title copies are needed.
final class CodexMultitaskMarqueeView: NSView {
    private let textLayer = CATextLayer()
    private static let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
    private static let scrollKey = "quotaview.satellite.title-scroll"
    private var scrollingEnabled = false
    private var reduceMotion = false
    private var layoutKey: LayoutKey?
    private struct LayoutKey: Equatable {
        var text: String
        var size: CGSize
        var alignment: NSTextAlignment
        var scrolling: Bool
    }
    var stringValue = "" {
        didSet { if oldValue != stringValue { needsLayout = true } }
    }
    var alignment = NSTextAlignment.left {
        didSet { if oldValue != alignment { needsLayout = true } }
    }
    var scrollAnimation: CAKeyframeAnimation? { textLayer.animation(forKey: Self.scrollKey) as? CAKeyframeAnimation }
    private(set) var scrollDistance: CGFloat = 0
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; layer?.masksToBounds = true
        textLayer.isWrapped = false
        textLayer.contentsScale = 2
        layer?.addSublayer(textLayer)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        textLayer.contentsScale = window?.backingScaleFactor ?? 2
    }
    func setScrollingEnabled(_ enabled: Bool, reduceMotion: Bool) {
        if scrollingEnabled != enabled || self.reduceMotion != reduceMotion {
            scrollingEnabled = enabled; self.reduceMotion = reduceMotion; needsLayout = true
        }
        layoutSubtreeIfNeeded()
    }
    override func layout() {
        super.layout()
        let measured = ceil((stringValue as NSString).size(withAttributes: [.font: Self.font]).width)
        let available = max(0, bounds.width - 4)
        let overflow = max(0, measured - available)
        let scrolling = scrollingEnabled && !reduceMotion && bounds.width > 0 && overflow > 0
        let key = LayoutKey(text: stringValue, size: bounds.size, alignment: alignment, scrolling: scrolling)
        guard layoutKey != key else { return }
        layoutKey = key
        textLayer.removeAnimation(forKey: Self.scrollKey)
        scrollDistance = scrolling ? overflow : 0
        CATransaction.begin(); CATransaction.setDisableActions(true)
        textLayer.alignmentMode = !scrolling && alignment == .center ? .center : .left
        textLayer.truncationMode = scrolling ? .none : .end
        textLayer.string = NSAttributedString(string: stringValue, attributes: [.font: Self.font, .foregroundColor: NSColor.white])
        let lineHeight = ceil(Self.font.ascender - Self.font.descender + Self.font.leading)
        textLayer.frame = CGRect(x: 2, y: (bounds.height - lineHeight) / 2, width: scrolling ? measured : available, height: lineHeight)
        CATransaction.commit()
        guard scrolling else { return }
        let pause: TimeInterval = 1.2
        let travel = max(0.8, Double(overflow) / 22)
        let duration = 2 * (pause + travel)
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.values = [0, 0, -overflow, -overflow, 0]
        animation.keyTimes = [0, NSNumber(value: pause / duration), NSNumber(value: (pause + travel) / duration),
                              NSNumber(value: (2 * pause + travel) / duration), 1]
        animation.duration = duration; animation.repeatCount = .infinity
        animation.calculationMode = .linear
        animation.beginTime = textLayer.convertTime(CACurrentMediaTime(), from: nil)
        textLayer.add(animation, forKey: Self.scrollKey)
    }
}

// A latest-state notice, not a queue of every hook/tool event. Repeated state,
// title, quota and token updates never extend its deadline or repeat the sweep.
struct CodexMultitaskStatusNotice {
    static let duration: TimeInterval = 2.4
    private(set) var state: CodexActivityVisualState?
    private(set) var expiresAt: TimeInterval?
    private(set) var revision = 0
    mutating func observe(_ next: CodexActivityVisualState, at now: TimeInterval) {
        guard next != state else { return }
        if state != nil { expiresAt = now + Self.duration; revision += 1 }
        state = next
    }
    func isShowing(at now: TimeInterval) -> Bool { expiresAt.map { now < $0 } ?? false }
    mutating func cancel() { expiresAt = nil }
}

final class CodexMultitaskTaskNode: NSView {
    private let satelliteScaleHost = NSView()
    private let satelliteJellyHost = NSView()
    private let satelliteBody = NSView()
    let satelliteCompletionGlow = ActivityIslandCompletionGlowView(frame: .zero)
    let satelliteStatusOutline = ActivityIslandCompletionOutlineView(frame: .zero)
    private let shortLabel = CodexMultitaskMarqueeView(frame: .zero)
    private let statusFlow = NSView()
    private let flowLayer = CAGradientLayer()
    private(set) var satelliteEffect: ActivityStateSmokeMetalView?
    private var notice = CodexMultitaskStatusNotice()
    private var noticeReturn: DispatchWorkItem?
    private var shownNoticeRevision = -1
    private var isMain = true
    private var presented = true
    private var usesSatelliteSurface = false
    private(set) var renderer: ActivityIslandContentView?
    private var task: CodexMultitaskRenderTask?
    private var english = false
    private var effect: AppPreferences.CodexActivityProgressEffect = .dropField
    private var reduceMotion = false
    private var playback = false
    private var completionCount: Int?
    private var totalTokens: Int64?
    private var remainingPercent: Int?
    var displayedTask: CodexMultitaskRenderTask? { task }
    var displayedSatelliteTitle: String { shortLabel.stringValue }
    var satelliteTitleFrame: CGRect { shortLabel.frame }
    var satelliteStatusColor: NSColor? { satelliteStatusOutline.completionColor }
    var satelliteTitleScrollAnimation: CAKeyframeAnimation? { shortLabel.scrollAnimation }
    var satelliteTitleIsScrolling: Bool { shortLabel.scrollDistance > 0 }
    private(set) var displayedTextOpacity: CGFloat = 1
    var onSelect: (() -> Void)?
    override var isOpaque: Bool { false }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        satelliteScaleHost.wantsLayer = true
        satelliteJellyHost.wantsLayer = true
        // Glow belongs outside the clipped black surface. All of these children
        // inherit the same jelly transform so its outline cannot lag behind.
        layer?.masksToBounds = false
        satelliteScaleHost.layer?.masksToBounds = false
        satelliteJellyHost.layer?.masksToBounds = false
        satelliteBody.wantsLayer = true
        addSubview(satelliteScaleHost); satelliteScaleHost.addSubview(satelliteJellyHost)
        satelliteJellyHost.addSubview(satelliteCompletionGlow)
        satelliteJellyHost.addSubview(satelliteBody)
        satelliteJellyHost.addSubview(satelliteStatusOutline)
        satelliteCompletionGlow.completionColor = .systemGreen
        satelliteStatusOutline.completionColor = .systemGreen
        satelliteCompletionGlow.completionRevealDelay = 0
        satelliteStatusOutline.completionRevealDelay = 0
        satelliteCompletionGlow.alphaValue = 0.55
        statusFlow.wantsLayer = true
        statusFlow.layer?.addSublayer(flowLayer)
        flowLayer.startPoint = CGPoint(x: 0, y: 0.5); flowLayer.endPoint = CGPoint(x: 1, y: 0.5)
        flowLayer.locations = [0, 0.5, 1]; flowLayer.opacity = 0
        satelliteBody.addSubview(statusFlow); satelliteBody.addSubview(shortLabel)
        setAccessibilityElement(true); setAccessibilityRole(.button)
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { noticeReturn?.cancel() }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0.1 else { return nil }
        return bounds.contains(convert(point, from: superview)) ? self : nil
    }
    override func mouseDown(with event: NSEvent) { onSelect?() }
    override func accessibilityPerformPress() -> Bool { onSelect?(); return true }
    func configure(task: CodexMultitaskRenderTask, english: Bool, effect: AppPreferences.CodexActivityProgressEffect, reduceMotion: Bool,
                   completionCount: Int? = nil,
                   totalTokens: Int64? = nil, remainingPercent: Int? = nil) {
        guard self.task != task || self.english != english || self.effect != effect || self.reduceMotion != reduceMotion
                || self.completionCount != completionCount
                || self.totalTokens != totalTokens || self.remainingPercent != remainingPercent else { return }
        notice.observe(task.renderState.visualState, at: ProcessInfo.processInfo.systemUptime)
        self.task = task; self.english = english; self.effect = effect; self.reduceMotion = reduceMotion
        self.completionCount = completionCount
        self.totalTokens = totalTokens; self.remainingPercent = remainingPercent
        satelliteStatusOutline.completionColor = task.color
        toolTip = "\(task.title) · \(task.renderState.statusTitle)"
        setAccessibilityLabel(toolTip)
        if let renderer { renderer.update(renderState: renderState, progressEffect: effect); renderer.setReduceMotion(reduceMotion) }
    }
    func takeRenderer(from previous: CodexMultitaskTaskNode) {
        renderer?.setPlaybackVisible(false); renderer?.removeFromSuperview()
        renderer = previous.renderer; previous.renderer = nil
        if let renderer {
            renderer.removeFromSuperview()
            addSubview(renderer, positioned: .below, relativeTo: satelliteScaleHost)
        }
    }
    private var renderState: CodexActivityRenderState {
        let state = task!.renderState
        guard let completionCount else { return state }
        return CodexMultitaskCompletionSummary(count: completionCount, english: english,
            totalTokens: totalTokens, remainingPercent: remainingPercent).applying(to: state)
    }
    func apply(_ pose: CodexMultitaskMotion.Pose, isMain: Bool, compact: Bool,
               presentation: CodexMultitaskPresentation.Sample? = nil, selectionTextOpacity: CGFloat = 1) {
        let frame = pose.frame
        self.isMain = isMain
        displayedTextOpacity = selectionTextOpacity
        self.frame = frame; bounds = CGRect(origin: .zero, size: frame.size); alphaValue = pose.opacity
        let satelliteWidth = CodexMultitaskGeometry.satelliteWidth
        let contentSize = pose.contentLayoutSize ?? frame.size
        let expansion = min(1, max(0, (contentSize.width - satelliteWidth) / (CodexMultitaskGeometry.mainSize.width - satelliteWidth)))
        let showsRenderer = isMain || contentSize.width > satelliteWidth + 4
        usesSatelliteSurface = !showsRenderer
        // The production surface owns the main contour; a second black rectangular
        // backdrop would remain visible underneath a correctly rounded capsule.
        // The same frame/bounds mapping deforms the surface, title and status outline.
        // Keep the logical layout independent of jelly; a swollen circle must not
        // accidentally enter the full renderer or change its label fade.
        satelliteScaleHost.frame = bounds
        satelliteScaleHost.bounds = CGRect(origin: .zero, size: contentSize)
        satelliteJellyHost.frame = satelliteScaleHost.bounds
        satelliteBody.frame = satelliteJellyHost.bounds
        satelliteBody.layer?.backgroundColor = showsRenderer ? NSColor.clear.cgColor : NSColor.black.cgColor
        satelliteBody.layer?.cornerRadius = contentSize.height / 2
        satelliteBody.layer?.masksToBounds = !showsRenderer
        let glowInset = CodexActivityIslandGeometry.panelInset
        satelliteCompletionGlow.frame = satelliteJellyHost.bounds.insetBy(dx: -glowInset, dy: -glowInset)
        satelliteCompletionGlow.setIslandInset(glowInset)
        satelliteCompletionGlow.setIslandCornerRadius(contentSize.height / 2)
        satelliteStatusOutline.frame = satelliteJellyHost.bounds
        satelliteStatusOutline.setIslandCornerRadius(contentSize.height / 2)
        updateSatelliteEmphasis()
        satelliteCompletionGlow.layoutSubtreeIfNeeded()
        satelliteStatusOutline.layoutSubtreeIfNeeded()
        if let layer = satelliteJellyHost.layer {
            // A previous main can retain a decaying impulse during a focus change.
            // Its satellite copy must follow the same impulse as the full renderer.
            let x = 1 + pose.shellJelly * 0.28, y = 1 - pose.shellJelly
            let dx = layer.bounds.width * (0.5 - layer.anchorPoint.x)
            let dy = layer.bounds.height * (0.5 - layer.anchorPoint.y)
            CATransaction.begin(); CATransaction.setDisableActions(true)
            layer.setAffineTransform(CGAffineTransform(a: x, b: 0, c: 0, d: y, tx: (1 - x) * dx, ty: (1 - y) * dy))
            CATransaction.commit()
        }
        if showsRenderer, task != nil {
            if renderer == nil {
                let view = ActivityIslandContentView(initialState: renderState, progressEffect: effect)
                renderer = view; addSubview(view, positioned: .below, relativeTo: satelliteScaleHost)
            }
            let mode: CodexActivityIslandPresentation = isMain && compact ? .compact : .expanded
            let base = presentation.map { NSSize(width: $0.layout.width, height: $0.layout.height) }
                ?? CodexActivityIslandGeometry.panelSize(presentation: mode, renderState: renderState)
            let inset = CodexActivityIslandGeometry.panelInset
            let scaleX = frame.width / (base.width - inset * 2), scaleY = frame.height / (base.height - inset * 2)
            renderer?.setPresentationMode(mode, accessibilityValue: CodexActivityCopy(language: english ? .english : .simplifiedChinese).presentationAccessibilityValue(mode))
            renderer?.setMultitaskContour(capsule: isMain ? pose.capsule : 1, recoil: pose.contourRecoil, jelly: pose.shellJelly)
            renderer?.setPresentationLayoutSize(base)
            renderer?.frame = CGRect(x: -inset * scaleX, y: -inset * scaleY, width: base.width * scaleX, height: base.height * scaleY)
            if let presentation {
                renderer?.setTextLayoutFrame(presentation.text.frame(relativeTo: presentation.layout, inset: inset),
                                             opacity: presentation.text.visibility * selectionTextOpacity)
            } else {
                let textAlpha = compact && isMain ? 1 : min(1, max(0, (expansion - 0.72) / 0.28))
                renderer?.setTextLayoutFrame(CGRect(origin: .zero, size: base), opacity: textAlpha)
            }
            renderer?.setReduceMotion(reduceMotion)
            renderer?.setPlaybackVisible(playback && isMain)
            renderer?.layoutSubtreeIfNeeded()
        } else if let renderer {
            renderer.setPlaybackVisible(false); renderer.removeFromSuperview(); self.renderer = nil
        }
        // Reuse the selected effect and its real state profile at original brightness.
        // Full-surface presentation is opt-in and never receives a fake progress.
        if !showsRenderer, presented, task != nil {
            if satelliteEffect == nil {
                let view = ActivityStateSmokeMetalView(frame: satelliteBody.bounds)
                view.setPlaybackEnabled(false); view.setFullSurfacePresentation(true)
                view.alphaValue = 1
                satelliteBody.addSubview(view, positioned: .below, relativeTo: statusFlow)
                satelliteEffect = view
            }
            satelliteEffect?.isHidden = !playback; satelliteEffect?.frame = satelliteBody.bounds
            satelliteEffect?.setReduceMotion(reduceMotion)
            satelliteEffect?.setEffect(effect)
            satelliteEffect?.setState(renderState.visualState, taskIdentity: renderState.taskIdentity)
            satelliteEffect?.setPlaybackEnabled(playback)
        } else {
            satelliteEffect?.setPlaybackEnabled(false); satelliteEffect?.isHidden = true
        }
        let labelAlpha = isMain ? 0 : max(0, 1 - expansion * 4) * pose.labelOpacity
        shortLabel.alphaValue = labelAlpha
        shortLabel.alignment = .center
        let titleHeight: CGFloat = 20
        shortLabel.frame = CGRect(x: 12, y: (contentSize.height - titleHeight) / 2,
                                 width: max(0, contentSize.width - 24), height: titleHeight)
        statusFlow.frame = satelliteBody.bounds; statusFlow.alphaValue = labelAlpha
        CATransaction.begin(); CATransaction.setDisableActions(true)
        flowLayer.frame = CGRect(x: 0, y: 0, width: contentSize.width * 0.6, height: contentSize.height)
        CATransaction.commit()
        refreshSatelliteLabel()
    }
    private func updateSatelliteEmphasis() {
        let emphasis: CodexActivityIslandEdgeEmphasis = task?.renderState.visualState == .completed ? .completion : .none
        let visible = presented && playback && !isMain && usesSatelliteSurface
        satelliteCompletionGlow.update(edgeEmphasis: emphasis, reduceMotion: reduceMotion, playbackVisible: visible)
        // Every state keeps its real color at the edge; only completion breathes.
        satelliteStatusOutline.update(edgeEmphasis: task == nil ? .none : .completion,
                                      reduceMotion: reduceMotion, playbackVisible: visible)
    }
    private func refreshSatelliteLabel() {
        guard let task else { return }
        if isMain || !presented { notice.cancel() }
        let now = ProcessInfo.processInfo.systemUptime
        let showing = notice.isShowing(at: now)
        let copy = AppCopy(language: english ? .english : .simplifiedChinese)
        let status: String
        switch task.renderState.visualState {
        case .compactingContext: status = copy.text("压缩上下文", "Compacting")
        case .awaitingConfirmation: status = copy.text("待确认", "Needs input")
        case .disconnectedCodex: status = copy.text("未连接", "Offline")
        default: status = task.renderState.statusTitle
        }
        let text = showing ? status : task.title
        if shortLabel.stringValue != text {
            if !reduceMotion, presented, !isMain {
                let fade = CATransition(); fade.type = .fade; fade.duration = 0.16
                shortLabel.layer?.add(fade, forKey: "statusText")
            }
            shortLabel.stringValue = text
        }
        if showing, shownNoticeRevision != notice.revision, let deadline = notice.expiresAt {
            shownNoticeRevision = notice.revision
            noticeReturn?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.refreshSatelliteLabel() }
            noticeReturn = work
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0, deadline - now), execute: work)
            flowLayer.removeAnimation(forKey: "statusSweep")
            if !reduceMotion {
                flowLayer.colors = [NSColor.clear.cgColor, task.color.withAlphaComponent(0.28).cgColor, NSColor.clear.cgColor]
                let travel = CABasicAnimation(keyPath: "transform.translation.x")
                travel.fromValue = -flowLayer.bounds.width; travel.toValue = statusFlow.bounds.width
                let brightness = CAKeyframeAnimation(keyPath: "opacity")
                brightness.values = [0, 1, 1, 0]; brightness.keyTimes = [0, 0.15, 0.8, 1]
                let group = CAAnimationGroup(); group.animations = [travel, brightness]
                group.duration = 0.9; group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                flowLayer.add(group, forKey: "statusSweep")
            }
        }
        if !showing || reduceMotion {
            flowLayer.removeAnimation(forKey: "statusSweep")
            if !showing { noticeReturn?.cancel(); noticeReturn = nil }
        }
        shortLabel.setScrollingEnabled(presented && playback && !isMain && usesSatelliteSurface
                                       && !showing && shortLabel.alphaValue > 0.01, reduceMotion: reduceMotion)
    }
    func setPresented(_ enabled: Bool) {
        presented = enabled
        if !enabled { notice.cancel(); noticeReturn?.cancel(); noticeReturn = nil; flowLayer.removeAllAnimations() }
        if !enabled { shortLabel.setScrollingEnabled(false, reduceMotion: reduceMotion) }
        updateSatelliteEmphasis()
    }
    func setPlayback(_ enabled: Bool) {
        playback = enabled; renderer?.setPlaybackVisible(enabled)
        if let satelliteEffect { satelliteEffect.setPlaybackEnabled(enabled && !satelliteEffect.isHidden) }
        if !enabled { shortLabel.setScrollingEnabled(false, reduceMotion: reduceMotion) }
        updateSatelliteEmphasis()
    }
}
