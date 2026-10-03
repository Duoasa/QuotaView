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

// Exact geometry supplies visibility and a one-shot anchor across structural
// detail changes. Native gestures remain continuous and cancel restoration.
struct IslandTaskListLayout: Equatable {
    let taskIDs: [Int]
    let detailID: Int?
    var detailHeight: CGFloat = IslandVibeLayout.minimumDetailHeight
    var rowHeights: [Int: CGFloat] = [:]

    struct Anchor {
        let element: IslandListElement
        let inset: CGFloat
    }
    var contentHeight: CGFloat {
        guard !taskIDs.isEmpty else { return IslandVibeLayout.rowHeight + IslandVibeLayout.listVerticalInset * 2 }
        return taskIDs.reduce(IslandVibeLayout.listVerticalInset * 2 - IslandVibeLayout.rowSpacing) {
            $0 + (rowHeights[$1] ?? IslandVibeLayout.rowHeight) + IslandVibeLayout.rowSpacing
                + ($1 == detailID ? detailHeight + IslandVibeLayout.rowSpacing : 0)
        }
    }
    func anchor(at offset: CGFloat) -> Anchor? {
        var cursor = IslandVibeLayout.listVerticalInset
        for (index, id) in taskIDs.enumerated() {
            let rowHeight = rowHeights[id] ?? IslandVibeLayout.rowHeight
            if offset < cursor + rowHeight + IslandVibeLayout.rowSpacing {
                return Anchor(element: .task(id), inset: offset - cursor)
            }
            cursor += rowHeight + IslandVibeLayout.rowSpacing
            if id == detailID {
                if offset < cursor + detailHeight + IslandVibeLayout.rowSpacing {
                    return Anchor(element: .detail(id), inset: offset - cursor)
                }
                cursor += detailHeight + IslandVibeLayout.rowSpacing
            }
            if index == taskIDs.count - 1 { return Anchor(element: .task(id), inset: rowHeight) }
        }
        return nil
    }
    func offset(for anchor: Anchor) -> CGFloat? {
        var cursor = IslandVibeLayout.listVerticalInset
        for id in taskIDs {
            let rowHeight = rowHeights[id] ?? IslandVibeLayout.rowHeight
            switch anchor.element {
            case .task(let anchoredID) where anchoredID == id:
                return cursor + min(rowHeight + IslandVibeLayout.rowSpacing, anchor.inset)
            case .detail(let anchoredID) where anchoredID == id:
                return id == detailID
                    ? cursor + rowHeight + IslandVibeLayout.rowSpacing + min(detailHeight, max(0, anchor.inset))
                    : cursor // Removed detail returns to its owning card, within final bounds.
            default: break
            }
            cursor += rowHeight + IslandVibeLayout.rowSpacing
            if id == detailID { cursor += detailHeight + IslandVibeLayout.rowSpacing }
        }
        return nil
    }

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

    func residentTaskIDs(offset: CGFloat, viewport: CGFloat) -> Set<Int> {
        let margin = IslandVibeLayout.rowPitch * 4
        return Set(visibleElements(offset: offset - margin, viewport: viewport + margin * 2).map {
            switch $0 { case .task(let id), .detail(let id): return id }
        })
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
    func prepareLayoutChange() { probe?.prepareLayoutChange() }
    var isChangingLayout: Bool { probe?.isChangingLayout == true }
    func finishLayoutChange() { probe?.finishLayoutChange() }
    func transitionResidents(layout: IslandTaskListLayout, viewport: CGFloat) -> Set<Int> {
        probe?.transitionResidents(layout: layout, viewport: viewport) ?? []
    }
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
    private var scheduledVisibility: IslandListVisibility?
    private var onVisibilityChange: (IslandListVisibility) -> Void = { _ in }
    private weak var scrollLink: IslandTaskScrollLink?
    private var oldPostsFrameChanges = false
    private weak var observedClip: NSClipView?
    private var observedClipSize = CGSize.zero
    private weak var observedDocument: NSView?
    private var oldPostsBoundsChanges = false
    private var listLayout = IslandTaskListLayout(taskIDs: [], detailID: nil)
    private var viewportHeight: CGFloat?
    private var pendingAnchor: IslandTaskListLayout.Anchor?
    private var restorationLayout: IslandTaskListLayout?
    private var restorationWork: DispatchWorkItem?
    private var restorationEpoch: UInt64 = 0
    private var restoringPosition = false
    private var active = false
    var isAttached: Bool { scroll != nil }
    var observationCount: Int { observations.count }
    var isChangingLayout: Bool { pendingAnchor != nil }

    deinit {
        restorationWork?.cancel()
        visibilityWork?.cancel()
        observations.forEach(NotificationCenter.default.removeObserver)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    func configure(layout: IslandTaskListLayout, active: Bool,
                   onVisibilityChange: @escaping (IslandListVisibility) -> Void = { _ in },
                   link: IslandTaskScrollLink? = nil, viewportHeight: CGFloat? = nil) {
        self.listLayout = layout; self.active = active
        self.viewportHeight = viewportHeight
        if pendingAnchor != nil { restorationLayout = layout }
        if !active { cancelRestoration() }
        self.onVisibilityChange = onVisibilityChange
        if scrollLink !== link { scrollLink?.detach(self); scrollLink = link }
        scrollLink?.attach(self)
        attachIfNeeded()
        restorePositionIfReady()
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
    override func layout() { super.layout(); attachIfNeeded(); restorePositionIfReady(); updateRail() }
    private func attachIfNeeded() {
        guard let found = enclosingScrollView else { if scroll != nil { detach() }; return }
        guard found !== scroll || found.contentView !== observedClip || found.documentView !== observedDocument else { return }
        // A SwiftUI document replacement inside the same scroll view belongs to
        // the same layout transaction; only a different scroll owner cancels it.
        let sameScroll = found === scroll
        detach(cancelPending: !sameScroll)
        scroll = found
        observedClip = found.contentView; observedDocument = found.documentView
        observedClipSize = found.contentView.bounds.size
        scrollLink?.attach(self)
        oldPostsBoundsChanges = found.contentView.postsBoundsChangedNotifications
        found.contentView.postsBoundsChangedNotifications = true
        observe(NSView.boundsDidChangeNotification, object: found.contentView) { probe in
            if let clip = probe.observedClip, clip.bounds.size != probe.observedClipSize {
                probe.observedClipSize = clip.bounds.size
                probe.restorePositionIfReady()
            }
            // Legacy wheel input changes origin before didLiveScroll arrives.
            // An origin-only change must never synchronously undo that gesture.
            probe.publishVisibility(); probe.updateRail()
        }
        observe(NSScrollView.willStartLiveScrollNotification, object: found) { $0.userDidScroll() }
        observe(NSScrollView.didLiveScrollNotification, object: found) { $0.userDidScroll() }
        if let document = found.documentView {
            oldPostsFrameChanges = document.postsFrameChangedNotifications
            document.postsFrameChangedNotifications = true
            observe(NSView.frameDidChangeNotification, object: document) {
                $0.restorePositionIfReady(); $0.publishVisibility(); $0.updateRail()
            }
        }
        updateRail()
        publishVisibility()
    }
    private func publishVisibility() {
        // Intermediate native clamps are layout bookkeeping, not a new visible
        // region. Keep mounted rows and effect playback until the anchor commits.
        guard pendingAnchor == nil, let clip = scroll?.contentView else { return }
        // Only row entry/exit publishes SwiftUI state, never every scroll pixel.
        var elements = IslandListVisibility()
        if active {
            elements.visible = listLayout.visibleElements(offset: clip.bounds.minY, viewport: clip.bounds.height)
            // Keep four neighboring rows warm on each side; only viewport rows play.
            elements.residentTaskIDs = listLayout.residentTaskIDs(offset: clip.bounds.minY, viewport: clip.bounds.height)
        }
        guard scheduledVisibility != elements else { return }
        visibilityWork?.cancel()
        visibilityWork = nil; scheduledVisibility = nil
        guard lastVisibleElements != elements else { return }
        scheduledVisibility = elements
        let work = DispatchWorkItem { [weak self] in
            guard let self, pendingAnchor == nil, scheduledVisibility == elements else { return }
            visibilityWork = nil; scheduledVisibility = nil
            lastVisibleElements = elements
            onVisibilityChange(elements)
        }
        visibilityWork = work
        DispatchQueue.main.async(execute: work)
    }
    private func observe(_ name: Notification.Name, object: AnyObject, action: @escaping (IslandTaskScrollProbe) -> Void) {
        observations.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self { action(self) } }
        })
    }
    private func updateRail() {
        guard pendingAnchor == nil, let scroll, let document = scroll.documentView else { return }
        scrollLink?.update(.init(offset: scroll.contentView.bounds.minY,
                                viewport: scroll.contentView.bounds.height, content: document.frame.height,
                                visible: active))
    }
    func prepareLayoutChange() {
        guard active, let clip = scroll?.contentView else { return }
        // Capture before Published state or the hosting frame changes. Capturing
        // in updateNSView can already see AppKit's transient zero-range clamp.
        if pendingAnchor == nil { pendingAnchor = listLayout.anchor(at: clip.bounds.minY) }
        restorationEpoch &+= 1; restorationWork?.cancel(); restorationWork = nil
        restorationLayout = nil
        visibilityWork?.cancel(); visibilityWork = nil; scheduledVisibility = nil
    }
    private func cancelRestoration() {
        restorationEpoch &+= 1; restorationWork?.cancel(); restorationWork = nil
        pendingAnchor = nil; restorationLayout = nil
    }
    private func userDidScroll() {
        cancelRestoration(); publishVisibility(); updateRail()
    }
    func finishLayoutChange() { restorePositionIfReady(commit: true) }
    func transitionResidents(layout: IslandTaskListLayout, viewport: CGFloat) -> Set<Int> {
        guard let pendingAnchor, let proposed = layout.offset(for: pendingAnchor) else { return [] }
        let offset = min(max(0, layout.contentHeight - viewport), max(0, proposed))
        // The new SwiftUI body can mount target rows before native layout. This
        // does not publish transient visibility or start offscreen playback.
        return layout.residentTaskIDs(offset: offset, viewport: viewport)
    }
    private func restorePositionIfReady(commit: Bool = false) {
        guard !restoringPosition, active, let anchor = pendingAnchor, let target = restorationLayout,
              let viewportHeight, let scroll, let document = scroll.documentView else { return }
        let clip = scroll.contentView
        let documentReady = abs(document.frame.height - target.contentHeight) < 1
            || abs(document.frame.height - max(target.contentHeight, viewportHeight)) < 1
        guard abs(clip.bounds.height - viewportHeight) < 1, documentReady else { return }
        guard let proposed = target.offset(for: anchor) else { cancelRestoration(); return }
        let y = min(max(0, document.frame.height - clip.bounds.height), max(0, proposed))
        // Move inside the native layout pass, before a frame can show the clamp.
        // Retain the checkpoint until commit so later notifications in this same
        // pass can repair another clamp; new user gestures always revoke it.
        restoringPosition = true
        defer { restoringPosition = false }
        if abs(clip.bounds.minY - y) > 0.1 {
            clip.scroll(to: CGPoint(x: clip.bounds.minX, y: y))
            scroll.reflectScrolledClipView(clip)
        }
        if commit {
            cancelRestoration(); publishVisibility(); updateRail()
        } else if restorationWork == nil {
            let epoch = restorationEpoch
            let work = DispatchWorkItem { [weak self] in
                guard let self, restorationEpoch == epoch else { return }
                restorationWork = nil
                finishLayoutChange()
            }
            restorationWork = work
            // Only the transaction's cleanup is queued. Position is already
            // correct, and the surface also commits immediately before drawing.
            DispatchQueue.main.async(execute: work)
        }
    }
    func scrollFromRail(_ rail: IslandTaskScrollRail) {
        guard active, let scroll, let document = scroll.documentView else { return }
        cancelRestoration()
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
    func detach(cancelPending: Bool = true) {
        if cancelPending { cancelRestoration() }
        visibilityWork?.cancel(); visibilityWork = nil; scheduledVisibility = nil; lastVisibleElements = nil
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
    var viewportHeight: CGFloat? = nil
    func makeNSView(context: Context) -> IslandTaskScrollProbe { .init(frame: .zero) }
    func updateNSView(_ view: IslandTaskScrollProbe, context: Context) {
        view.configure(layout: layout, active: active, onVisibilityChange: onVisibilityChange, link: link, viewportHeight: viewportHeight)
    }
    static func dismantleNSView(_ view: IslandTaskScrollProbe, coordinator: ()) { view.detach() }
}
