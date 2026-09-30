import AppKit
import SwiftUI

enum IslandListElement: Hashable {
    case task(Int)
    case detail(Int)
}

struct IslandListVisibility: Equatable {
    var visible: Set<IslandListElement> = []
    var residentTaskIDs: Set<Int> = []
}

// Exact row geometry tracks visibility only. Native scrolling is continuous;
// this layout never computes a target offset or moves the content after a gesture.
struct IslandTaskListLayout: Equatable {
    let taskIDs: [Int]
    let detailID: Int?
    var detailHeight: CGFloat = IslandVibeLayout.minimumDetailHeight
    var rowHeights: [Int: CGFloat] = [:]

    func visibleElements(offset: CGFloat, viewport: CGFloat) -> Set<IslandListElement> {
        var result: Set<IslandListElement> = []
        var cursor: CGFloat = IslandVibeLayout.listVerticalInset
        for id in taskIDs {
            let rowHeight = rowHeights[id] ?? IslandVibeLayout.rowHeight
            if cursor < offset + viewport && cursor + rowHeight > offset { result.insert(.task(id)) }
            cursor += rowHeight
            if id == detailID {
                cursor += IslandVibeLayout.rowSpacing
                if cursor < offset + viewport && cursor + detailHeight > offset { result.insert(.detail(id)) }
                cursor += detailHeight
            }
            cursor += IslandVibeLayout.rowSpacing
        }
        return result
    }

}

// The rail is an independent sibling of ScrollView, never its managed scroller.
// Progress moves CALayers directly; no scroll-offset state is published to SwiftUI.
@MainActor
final class IslandTaskScrollLink {
    struct Metrics: Equatable {
        var offset: CGFloat = 0
        var viewport: CGFloat = 0
        var content: CGFloat = 0
        var visible = false
        var maximum: CGFloat { max(0, content - viewport) }
        var fraction: Double { maximum > 0 ? Double(min(1, max(0, offset / maximum))) : 0 }
    }
    private weak var probe: IslandTaskScrollProbe?
    private weak var rail: IslandTaskScrollRail?
    private var metrics = Metrics()
    func attach(_ probe: IslandTaskScrollProbe) { self.probe = probe }
    func attach(_ rail: IslandTaskScrollRail) {
        self.rail = rail; rail.link = self; rail.update(metrics)
    }
    func detach(_ probe: IslandTaskScrollProbe) {
        guard self.probe === probe else { return }
        self.probe = nil; metrics.visible = false; rail?.update(metrics)
    }
    func detach(_ rail: IslandTaskScrollRail) {
        if self.rail === rail { self.rail = nil }
    }
    func update(_ metrics: Metrics) {
        guard self.metrics != metrics else { return }
        self.metrics = metrics; rail?.update(metrics)
    }
    func move(_ rail: IslandTaskScrollRail) { probe?.scrollFromRail(rail) }
}

@MainActor
final class IslandTaskScrollRail: NSScroller {
    weak var link: IslandTaskScrollLink?
    private let track = CALayer()
    private let thumb = CALayer()
    var thumbFrame: CGRect { thumb.frame }
    var thumbColor: CGColor? { thumb.backgroundColor }
    override class var isCompatibleWithOverlayScrollers: Bool { false }
    override var wantsUpdateLayer: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; controlSize = .small; scrollerStyle = .legacy
        target = self; action = #selector(didScroll(_:))
        track.backgroundColor = NSColor(srgbRed: 0.22, green: 0.22, blue: 0.22, alpha: 1).cgColor
        thumb.backgroundColor = NSColor(srgbRed: 0.72, green: 0.72, blue: 0.72, alpha: 1).cgColor
        track.cornerRadius = 2; thumb.cornerRadius = IslandVibeLayout.scrollThumbWidth / 2
        layer?.addSublayer(track); layer?.addSublayer(thumb)
    }
    required init?(coder: NSCoder) { fatalError() }
    func update(_ metrics: IslandTaskScrollLink.Metrics) {
        isHidden = !metrics.visible || metrics.maximum <= 0
        isEnabled = metrics.maximum > 0
        knobProportion = metrics.content > 0 ? min(1, metrics.viewport / metrics.content) : 1
        doubleValue = metrics.fraction
        refreshLayers()
    }
    override func layout() { super.layout(); refreshLayers() }
    override func updateLayer() { refreshLayers() }
    private func refreshLayers() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        track.frame = CGRect(x: bounds.midX - 2, y: 0, width: 4, height: bounds.height)
        let knob = rect(for: .knob)
        let width = IslandVibeLayout.scrollThumbWidth
        thumb.frame = CGRect(x: bounds.midX - width / 2, y: knob.minY, width: width, height: knob.height)
        CATransaction.commit()
    }
    @objc private func didScroll(_ sender: IslandTaskScrollRail) { link?.move(sender) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct IslandTaskScrollRailView: NSViewRepresentable {
    let link: IslandTaskScrollLink
    let label: String
    func makeNSView(context: Context) -> IslandTaskScrollRail {
        let rail = IslandTaskScrollRail(frame: CGRect(x: 0, y: 0, width: IslandVibeLayout.scrollRailWidth, height: 100))
        link.attach(rail)
        return rail
    }
    func updateNSView(_ rail: IslandTaskScrollRail, context: Context) {
        link.attach(rail); rail.setAccessibilityLabel(label)
    }
    static func dismantleNSView(_ rail: IslandTaskScrollRail, coordinator: ()) {
        rail.link?.detach(rail); rail.link = nil
    }
}

// Observe native clip/document geometry for visibility and the independent rail.
// No wheel monitor, gesture state, settling timer or scroll animation is installed.
@MainActor
final class IslandTaskScrollProbe: NSView {
    private weak var scroll: NSScrollView?
    private var observations: [NSObjectProtocol] = []
    private var visibilityWork: DispatchWorkItem?
    private var lastVisibleElements: IslandListVisibility?
    private var onVisibilityChange: (IslandListVisibility) -> Void = { _ in }
    private weak var scrollLink: IslandTaskScrollLink?
    private var oldPostsFrameChanges = false
    private weak var observedClip: NSClipView?
    private weak var observedDocument: NSView?
    private var oldPostsBoundsChanges = false
    private var listLayout = IslandTaskListLayout(taskIDs: [], detailID: nil)
    private var active = false
    var isAttached: Bool { scroll != nil }
    var observationCount: Int { observations.count }

    deinit {
        visibilityWork?.cancel()
        observations.forEach(NotificationCenter.default.removeObserver)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    func configure(layout: IslandTaskListLayout, active: Bool,
                   onVisibilityChange: @escaping (IslandListVisibility) -> Void = { _ in },
                   link: IslandTaskScrollLink? = nil) {
        self.listLayout = layout; self.active = active
        self.onVisibilityChange = onVisibilityChange
        if scrollLink !== link { scrollLink?.detach(self); scrollLink = link }
        scrollLink?.attach(self)
        attachIfNeeded()
        updateRail()
        publishVisibility()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { detach() }
        else { attachIfNeeded() }
    }
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        attachIfNeeded()
    }
    override func layout() { super.layout(); attachIfNeeded(); updateRail() }
    private func attachIfNeeded() {
        guard let found = enclosingScrollView else { if scroll != nil { detach() }; return }
        guard found !== scroll || found.contentView !== observedClip || found.documentView !== observedDocument else { return }
        detach()
        scroll = found
        observedClip = found.contentView; observedDocument = found.documentView
        scrollLink?.attach(self)
        oldPostsBoundsChanges = found.contentView.postsBoundsChangedNotifications
        found.contentView.postsBoundsChangedNotifications = true
        observe(NSView.boundsDidChangeNotification, object: found.contentView) { probe in
            probe.publishVisibility(); probe.updateRail()
        }
        if let document = found.documentView {
            oldPostsFrameChanges = document.postsFrameChangedNotifications
            document.postsFrameChangedNotifications = true
            observe(NSView.frameDidChangeNotification, object: document) { $0.updateRail() }
        }
        updateRail()
        publishVisibility()
    }
    private func publishVisibility() {
        guard let clip = scroll?.contentView else { return }
        // Only row entry/exit publishes SwiftUI state, never every scroll pixel.
        var elements = IslandListVisibility()
        if active {
            elements.visible = listLayout.visibleElements(offset: clip.bounds.minY, viewport: clip.bounds.height)
            // Keep four neighboring rows warm on each side; only viewport rows play.
            let margin = IslandVibeLayout.rowPitch * 4
            elements.residentTaskIDs = Set(listLayout.visibleElements(offset: clip.bounds.minY - margin,
                viewport: clip.bounds.height + margin * 2).compactMap { element in
                    if case .task(let id) = element { return id }
                    return nil
                })
        }
        guard lastVisibleElements != elements else { return }
        lastVisibleElements = elements
        visibilityWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onVisibilityChange(elements) }
        visibilityWork = work
        DispatchQueue.main.async(execute: work)
    }
    private func observe(_ name: Notification.Name, object: AnyObject, action: @escaping (IslandTaskScrollProbe) -> Void) {
        observations.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self { action(self) } }
        })
    }
    private func updateRail() {
        guard let scroll, let document = scroll.documentView else { return }
        scrollLink?.update(.init(offset: scroll.contentView.bounds.minY,
                                viewport: scroll.contentView.bounds.height, content: document.frame.height,
                                visible: active))
    }
    func scrollFromRail(_ rail: IslandTaskScrollRail) {
        guard active, let scroll, let document = scroll.documentView else { return }
        let clip = scroll.contentView
        let maximum = max(0, document.frame.height - clip.bounds.height)
        let y: CGFloat
        switch rail.hitPart {
        case .incrementLine: y = clip.bounds.minY + IslandVibeLayout.rowPitch
        case .decrementLine: y = clip.bounds.minY - IslandVibeLayout.rowPitch
        case .incrementPage: y = clip.bounds.minY + clip.bounds.height
        case .decrementPage: y = clip.bounds.minY - clip.bounds.height
        default: y = CGFloat(rail.doubleValue) * maximum
        }
        clip.scroll(to: CGPoint(x: clip.bounds.minX, y: min(maximum, max(0, y))))
        scroll.reflectScrolledClipView(clip)
    }
    func detach() {
        visibilityWork?.cancel(); visibilityWork = nil; lastVisibleElements = nil
        observations.forEach(NotificationCenter.default.removeObserver); observations.removeAll()
        scrollLink?.detach(self)
        observedClip?.postsBoundsChangedNotifications = oldPostsBoundsChanges
        observedDocument?.postsFrameChangedNotifications = oldPostsFrameChanges
        scroll = nil; observedClip = nil; observedDocument = nil
    }
}

struct IslandTaskScrollConfiguration: NSViewRepresentable {
    let layout: IslandTaskListLayout
    let active: Bool
    let onVisibilityChange: (IslandListVisibility) -> Void
    let link: IslandTaskScrollLink
    func makeNSView(context: Context) -> IslandTaskScrollProbe { .init(frame: .zero) }
    func updateNSView(_ view: IslandTaskScrollProbe, context: Context) {
        view.configure(layout: layout, active: active, onVisibilityChange: onVisibilityChange, link: link)
    }
    static func dismantleNSView(_ view: IslandTaskScrollProbe, coordinator: ()) { view.detach() }
}
