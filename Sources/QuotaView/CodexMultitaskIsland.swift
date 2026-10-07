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


struct CodexMultitaskRenderTask: Equatable {
    let id: Int
    let renderState: CodexActivityRenderState
    var playbackEnabled = true
    var hasPendingRequest = false
    var provider: IslandAgentProvider = .codex
    var title: String { renderState.windowTitle }
    var color: NSColor {
        renderState.visualState == .completed ? .systemGreen : renderState.visualState.activityAccentColor
    }
}
/// A bounded background summary, independent of user selection, counts and popups.
struct IslandMemoryActivity: Equatable {
    let snapshot: CodexActivitySnapshot
    let count: Int
    init?(snapshots: [CodexActivitySnapshot]) {
        guard let representative = snapshots.sorted(by: {
            let lhs = Self.isInFlight($0), rhs = Self.isInFlight($1)
            if lhs != rhs { return lhs }
            if $0.occurredAt != $1.occurredAt { return $0.occurredAt > $1.occurredAt }
            return $0.sessionHash < $1.sessionHash
        }).first else { return nil }
        snapshot = representative; count = snapshots.count
    }
    private static func isInFlight(_ snapshot: CodexActivitySnapshot) -> Bool {
        [.thinking, .working, .compactingContext, .awaitingConfirmation, .unavailable, .disconnectedCodex].contains(snapshot.state)
    }
    var visualState: CodexActivityVisualState { snapshot.state }
    var playbackEnabled: Bool {
        [.thinking, .working, .compactingContext, .awaitingConfirmation].contains(snapshot.state)
    }
    func label(english: Bool) -> String {
        let copy = AppCopy(language: english ? .english : .simplifiedChinese)
        let status: String
        switch snapshot.state {
        case .thinking, .working, .compactingContext: status = copy.text("正在整理", "Organizing")
        case .awaitingConfirmation: status = copy.text("等待处理", "Awaiting action")
        case .completed: status = copy.text("整理完成", "Completed")
        case .error: status = copy.text("整理失败", "Failed")
        case .unavailable, .disconnectedCodex: status = copy.text("状态待更新", "Status unavailable")
        case .standby:
            status = snapshot.operationKey == .turnInterrupted
                ? copy.text("已中断", "Interrupted") : copy.text("待运行", "Idle")
        }
        let title = copy.text("记忆整理", "Memory consolidation") + " · " + status
        return count > 1 ? title + copy.text("（\(count) 个后台任务）", " (\(count) background tasks)") : title
    }
}

struct CodexMultitaskDisplay: Equatable {
    struct State: Equatable {
        var tasks: [CodexMultitaskRenderTask]
        var selectedID: Int
        var allCompleted: Bool
        var compact: Bool
        var receiptStartedAt: TimeInterval?
    }
    var state: State
    var english: Bool
    var effect: AppPreferences.CodexActivityProgressEffect
    var visible = true
    var playbackEnabled = true
    var totalTokens: Int64?
    var remainingPercent: Int?
    var weeklyRemainingPercent: Int? = nil
    var quotaResetsAt: Date? = nil
    var usageSnapshot: CurrentCodexPresentation? = nil
    var claudeUsage: IslandClaudeUsage? = nil
    var usageState: IslandUsagePresentation.State = .loading
    var usageOptions = IslandUsageOptions()
    var automaticPopupEnabled = true
    var automaticPopupDuration = AppPreferences.CodexActivityAutomaticPopupTiming.defaultDuration
    var sessionMetadata: [Int: IslandSessionMetadata] = [:]
    var taskDetails: [Int: IslandTaskDetailData] = [:]
    var connectionTitle: String = ""
    var privacyMode = false
    var activeRequestIDs: Set<UUID> = []
    // Background memory work has its own lifecycle and never becomes a session row.
    var backgroundMemorySnapshots: [CodexActivitySnapshot] = []
}

@MainActor
final class CodexMultitaskIslandController: NSObject {
    private let panel: NSPanel
    private let canvas = NSView()
    private let bridges = CAShapeLayer()
    private var nodes: [Int: CodexMultitaskTaskNode] = [:]
    private var motion = CodexMultitaskMotion()
    private var presentation = CodexMultitaskPresentation()
    private var completionKey: String?
    private var handoffContent: (destination: Int, previous: CodexMultitaskRenderTask, opacity: CGFloat)?
    private var targets: [Int: CodexMultitaskMotion.Pose] = [:]
    private var model: CodexMultitaskDisplay?
    private var reduceMotion = false
    private var stopped = false
    private var timer: Timer?
    private var monitors: [Any] = []
    private var renderedFrames: [Int: CGRect] = [:]
    private var controlVisible: Bool { !stopped }
    var screen: NSScreen?
    var onSelect: ((Int) -> Void)?
    var isVisible: Bool { panel.isVisible && model?.visible == true }

    override init() {
        panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 1400, height: 230), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.isReleasedWhenClosed = false; panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false; panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        panel.animationBehavior = .none; panel.acceptsMouseMovedEvents = true
        canvas.wantsLayer = true; canvas.layer?.masksToBounds = true
        bridges.fillColor = NSColor.black.cgColor
        bridges.actions = ["path": NSNull(), "bounds": NSNull(), "position": NSNull()]
        canvas.layer?.addSublayer(bridges); panel.contentView = canvas
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] _ in self?.hitRegion() }) { monitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] event in self?.hitRegion(); return event }) { monitors.append(monitor) }
    }
    deinit {
        timer?.invalidate(); monitors.forEach(NSEvent.removeMonitor)
    }
    func update(model: CodexMultitaskDisplay, reduceMotion: Bool) {
        self.model = model; self.reduceMotion = reduceMotion; stopped = false
        let now = ProcessInfo.processInfo.systemUptime
        let ids = model.state.tasks.map(\.id)
        let allDone = model.state.allCompleted && ids.count > 1
        presentation.update(visible: model.visible, compact: model.state.compact, at: now, animate: !reduceMotion && controlVisible,
                            compactWidth: allDone ? CodexMultitaskCompletionSummary.compactWidth(count: ids.count, english: model.english) : nil)
        let newCompletionKey = allDone ? model.state.receiptStartedAt.map { "\($0)-\(model.state.selectedID)" } : nil
        let collectionChanged = newCompletionKey != completionKey
        for id in Array(nodes.keys) where !ids.contains(id) { nodes[id]?.setPresented(false); nodes[id]?.setPlayback(false); nodes[id]?.removeFromSuperview(); nodes[id] = nil }
        for task in model.state.tasks {
            if nodes[task.id] == nil { let node = CodexMultitaskTaskNode(frame: .zero); nodes[task.id] = node; canvas.addSubview(node) }
            nodes[task.id]?.onSelect = { [weak self] in self?.onSelect?(task.id) }
        }
        // The task arrangement remains expanded. The production timeline owns ALL
        // show/hide and compact/expand geometry, so liquid motion cannot replace it.
        let frames = CodexMultitaskGeometry.frames(ids: ids, selected: model.state.selectedID, compact: false)
        let next = frames.mapValues { CodexMultitaskMotion.Pose(frame: $0) }.map { id, pose -> (Int, CodexMultitaskMotion.Pose) in
            var pose = pose
            pose.capsule = ids.count > 1 ? 1 : 0
            if id != model.state.selectedID && !model.visible { pose.opacity = 0 }
            return (id, pose)
        }
        let newTargets = Dictionary(uniqueKeysWithValues: next)
        let changed = Set(targets.keys) != Set(newTargets.keys) || newTargets.contains { targets[$0.key]?.frame != $0.value.frame || targets[$0.key]?.opacity != $0.value.opacity || targets[$0.key]?.capsule != $0.value.capsule }
        targets = newTargets
        if collectionChanged || (newCompletionKey == nil && (changed || reduceMotion)) {
            motion.retarget(targets, selected: model.state.selectedID, now: now,
                            animate: !reduceMotion && controlVisible && newCompletionKey == nil)
            if let handoff = motion.activeHandoff(now), let source = nodes[handoff.previous], let previous = source.displayedTask {
                handoffContent = (handoff.current, previous, source.displayedTextOpacity)
                nodes[handoff.current]?.takeRenderer(from: source)
            } else { handoffContent = nil }
        }
        if newCompletionKey != nil && (collectionChanged || reduceMotion) {
            motion.gatherCompleted(selected: model.state.selectedID, started: model.state.receiptStartedAt ?? now,
                                   now: now, animate: !reduceMotion && controlVisible)
        }
        completionKey = newCompletionKey
        updateTaskMenu(); positionPanel(); render()
        if (motion.isAnimating(now) || presentation.isAnimating(at: now)) && timer == nil {
            let timer = Timer(timeInterval: 1 / 60.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.render() }
            }
            timer.tolerance = 0.002; RunLoop.main.add(timer, forMode: .common); self.timer = timer
        }

    }
    private func positionPanel() {
        guard let screen = screen else { return }
        let area = screen.visibleFrame
        panel.setFrame(CGRect(x: area.minX, y: area.maxY - 230, width: area.width, height: 230), display: false)
        if model != nil { render() }
    }
    private func render() {
        guard let model, !stopped else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard let single = presentation.sample(at: now) else { return }
        let sampled = motion.sample(now)
        let handoff = motion.activeHandoff(now)
        if handoff == nil { handoffContent = nil }
        let surface = single.surface(in: canvas.bounds)
        let scaleX = surface.width / CodexMultitaskGeometry.mainSize.width
        let scaleY = surface.height / CodexMultitaskGeometry.mainSize.height
        let anchor = CGPoint(x: surface.midX, y: surface.midY)
        renderedFrames = [:]
        for task in model.state.tasks {
            guard let pose = sampled[task.id], let node = nodes[task.id] else { continue }
            var display = pose
            display.contentLayoutSize = pose.contentLayoutSize ?? pose.frame.size
            let isMain = task.id == model.state.selectedID
            let previousContent = isMain && handoff?.showsPrevious == true && handoffContent?.destination == task.id ? handoffContent : nil
            let allDone = model.state.allCompleted && model.state.tasks.count > 1
            node.configure(task: previousContent?.previous ?? task, english: model.english, effect: model.effect, reduceMotion: reduceMotion,
                           completionCount: allDone && isMain ? model.state.tasks.count : nil,
                           totalTokens: model.totalTokens, remainingPercent: model.remainingPercent)
            display.frame = CGRect(x: anchor.x + pose.frame.minX * scaleX, y: anchor.y + pose.frame.minY * scaleY,
                                   width: pose.frame.width * scaleX, height: pose.frame.height * scaleY)
            display.opacity *= single.shell.visibility
            // A single task takes the original renderer path without any new jelly or
            // contour overlay. Multi-task impulses layer on top only when applicable.
            if model.state.tasks.count == 1 {
                display.capsule = 0; display.contourRecoil = 0; display.shellJelly = 0
            }
            let presented = controlVisible && model.visible && display.opacity > 0.01 && display.frame.intersects(canvas.bounds)
            node.setPresented(presented)
            node.setPlayback(presented && model.playbackEnabled && task.playbackEnabled)
            let expansion = min(1, max(0, (pose.frame.width - CodexMultitaskGeometry.satelliteWidth) / (CodexMultitaskGeometry.mainSize.width - CodexMultitaskGeometry.satelliteWidth)))
            let handoffAlpha = handoff?.current == task.id ? (handoff?.textOpacity ?? 1) * (previousContent?.opacity ?? 1) : 1
            node.apply(display, isMain: isMain, compact: model.state.compact, presentation: isMain ? single : nil,
                       selectionTextOpacity: min(1, max(0, (expansion - 0.72) / 0.28)) * handoffAlpha)
            if display.opacity > 0.1 { renderedFrames[task.id] = display.frame }
        }
        let path = CGMutablePath()
        if motion.isAnimating(now) && !reduceMotion {
            let births = motion.activeBirths(now)
            let ordered = model.state.tasks.filter { births[$0.id] == nil }.compactMap { renderedFrames[$0.id] }
            for pair in zip(ordered, ordered.dropFirst()) {
                if let bridge = CodexMultitaskGeometry.bridge(pair.0, pair.1) { path.addPath(bridge) }
            }
            for (id, birth) in births {
                guard let source = renderedFrames[birth.donor], let child = renderedFrames[id] else { continue }
                if let bridge = birth.side > 0 ? CodexMultitaskGeometry.bridge(source, child) : CodexMultitaskGeometry.bridge(child, source) { path.addPath(bridge) }
            }
        }
        bridges.path = path
        if !motion.isAnimating(now) && !presentation.isAnimating(at: now) { timer?.invalidate(); timer = nil }
        hitRegion()
        if controlVisible && renderedFrames.count > 0 { if !panel.isVisible { panel.orderFrontRegardless() } }
        else { panel.orderOut(nil) }
    }
    private func hitRegion() {
        let cursor = panel.convertPoint(fromScreen: NSEvent.mouseLocation)
        panel.ignoresMouseEvents = !renderedFrames.values.contains { $0.contains(cursor) }
    }

    private func updateTaskMenu() {
        guard let model else { return }
        let menu = NSMenu()
        for task in model.state.tasks {
            let item = NSMenuItem(title: "\(task.title) · \(task.renderState.statusTitle)", action: #selector(selectFromMenu(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = task.id
            item.state = task.id == model.state.selectedID ? .on : .off
            menu.addItem(item)
        }
        canvas.menu = menu
        nodes.values.forEach { $0.menu = menu }
    }
    @objc private func selectFromMenu(_ item: NSMenuItem) {
        if let id = item.representedObject as? Int { onSelect?(id) }
    }
    func reposition(on screen: NSScreen?) { self.screen = screen; positionPanel() }
    func hide(animated: Bool = true) {
        guard var model, model.visible else { return }
        model.visible = false
        update(model: model, reduceMotion: reduceMotion || !animated)
    }
    func stop() {
        stopped = true; timer?.invalidate(); timer = nil
        monitors.forEach(NSEvent.removeMonitor); monitors.removeAll()
        nodes.values.forEach { $0.setPresented(false); $0.setPlayback(false) }; panel.orderOut(nil)
        model = nil
    }
}
