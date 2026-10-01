import AppKit
import CoreText
import SwiftUI

// Text luminance is encoded in RGB, never by blending white over its backdrop.
enum IslandTextPalette {
    static let secondary = NSColor(srgbRed: 179 / 255, green: 179 / 255, blue: 179 / 255, alpha: 1)
    static let muted = NSColor(srgbRed: 125 / 255, green: 125 / 255, blue: 125 / 255, alpha: 1)
    static let detail = NSColor(srgbRed: 195 / 255, green: 195 / 255, blue: 195 / 255, alpha: 1)
}

// Native presentation: text movement stays in Core Animation, outside SwiftUI layout.
final class IslandScrollingTextHost: NSView {
    private let textTrack = CALayer()
    private let textLayer = CATextLayer()
    private let repeatedTextLayer = CATextLayer()
    private let shimmerLayer = CAGradientLayer()
    private let shimmerMaskTrack = CALayer()
    private let shimmerMask = CATextLayer()
    private let repeatedShimmerMask = CATextLayer()
    private static let scrollKey = "console.text.scroll"
    private static let shimmerKey = "console.text.shimmer"
    private var text = ""
    private var font = NSFont.systemFont(ofSize: 13)
    private var color = NSColor.white
    private var visible = false
    private var reduceMotion = false
    private var shimmering = false
    private var layoutKey: LayoutKey?
    private struct LayoutKey: Equatable {
        var text: String
        var font: NSFont
        var color: NSColor
        var size: CGSize
        var scale: CGFloat
        var animate: Bool
        var shimmer: Bool
    }
    var scrollAnimation: CAKeyframeAnimation? { textTrack.animation(forKey: Self.scrollKey) as? CAKeyframeAnimation }
    var shimmerAnimation: CAKeyframeAnimation? { shimmerLayer.animation(forKey: Self.shimmerKey) as? CAKeyframeAnimation }
    private(set) var scrollDistance: CGFloat = 0
    var textColorAlpha: CGFloat { color.alphaComponent }
    var shimmerColorAlphas: [CGFloat] { (shimmerLayer.colors as? [CGColor] ?? []).map(\.alpha) }

    static func width(of text: String, font: NSFont) -> CGFloat {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        return ceil(CTLineGetTypographicBounds(line, nil, nil, nil)) + 2
    }
    static func height(for font: NSFont) -> CGFloat { ceil(font.ascender - font.descender + font.leading) }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        textLayer.isWrapped = false
        repeatedTextLayer.isWrapped = false
        shimmerMask.isWrapped = false
        repeatedShimmerMask.isWrapped = false
        textTrack.addSublayer(textLayer)
        textTrack.addSublayer(repeatedTextLayer)
        layer?.addSublayer(textTrack)
        shimmerLayer.startPoint = CGPoint(x: 0, y: 0.5)
        shimmerLayer.endPoint = CGPoint(x: 1, y: 0.5)
        shimmerMaskTrack.addSublayer(shimmerMask)
        shimmerMaskTrack.addSublayer(repeatedShimmerMask)
        shimmerLayer.mask = shimmerMaskTrack
        layer?.addSublayer(shimmerLayer)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); needsLayout = true; layoutSubtreeIfNeeded() }
    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); needsLayout = true }

    func configure(text: String, font: NSFont, color: NSColor, visible: Bool, reduceMotion: Bool, shimmer: Bool) {
        self.text = text; self.font = font; self.color = color.withAlphaComponent(1)
        self.visible = visible; self.reduceMotion = reduceMotion; shimmering = shimmer
        needsLayout = true
        layoutSubtreeIfNeeded()
    }
    func stop() { visible = false; needsLayout = true; layoutSubtreeIfNeeded() }

    override func layout() {
        super.layout()
        let animate = visible && window != nil && !reduceMotion && bounds.width > 0 && !text.isEmpty
        let key = LayoutKey(text: text, font: font, color: color, size: bounds.size,
                            scale: window?.backingScaleFactor ?? 2, animate: animate, shimmer: animate && shimmering)
        guard layoutKey != key else { return }
        layoutKey = key
        textTrack.removeAnimation(forKey: Self.scrollKey)
        shimmerMaskTrack.removeAnimation(forKey: Self.scrollKey)
        shimmerLayer.removeAnimation(forKey: Self.shimmerKey)
        let measured = Self.width(of: text, font: font)
        scrollDistance = animate ? max(0, measured - bounds.width) : 0
        let scrolling = scrollDistance > 1
        let loopDistance = measured + 32
        let height = Self.height(for: font)
        let textFrame = CGRect(x: 0, y: (bounds.height - height) / 2,
                               width: scrolling ? measured : max(0, bounds.width), height: height)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        textTrack.frame = bounds
        // Shimmer is the sole glyph layer while active, using opaque RGB stops.
        textTrack.isHidden = key.shimmer
        textLayer.frame = textFrame
        textLayer.string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        textLayer.truncationMode = scrolling ? .none : .end
        textLayer.contentsScale = key.scale
        repeatedTextLayer.frame = textFrame.offsetBy(dx: loopDistance, dy: 0)
        repeatedTextLayer.string = textLayer.string
        repeatedTextLayer.truncationMode = .none
        repeatedTextLayer.contentsScale = key.scale
        repeatedTextLayer.isHidden = !scrolling
        shimmerLayer.frame = bounds
        shimmerLayer.isHidden = !key.shimmer
        // Opaque RGB equivalents of the dark Codex reference; no text opacity.
        // Preserve each text role's opaque base color instead of replacing it
        // with a dim shared gray while shimmering.
        shimmerLayer.colors = [color.withAlphaComponent(1).cgColor, NSColor.white.cgColor,
                               NSColor.white.cgColor, color.withAlphaComponent(1).cgColor]
        shimmerMaskTrack.frame = bounds
        shimmerMask.frame = textFrame
        shimmerMask.string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.white])
        shimmerMask.truncationMode = textLayer.truncationMode
        shimmerMask.contentsScale = key.scale
        repeatedShimmerMask.frame = repeatedTextLayer.frame
        repeatedShimmerMask.string = shimmerMask.string
        repeatedShimmerMask.truncationMode = .none
        repeatedShimmerMask.contentsScale = key.scale
        repeatedShimmerMask.isHidden = !scrolling
        CATransaction.commit()
        if scrolling {
            let pause = 1.2
            let travel = Double(scrollDistance) / 26
            let continuation = Double(loopDistance - scrollDistance) / 26
            let duration = 2 * pause + travel + continuation
            let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
            // The next copy enters from the right; the loop reset is visually identical.
            animation.values = [0, 0, -scrollDistance, -scrollDistance, -loopDistance]
            animation.keyTimes = [0, NSNumber(value: pause / duration), NSNumber(value: (pause + travel) / duration),
                                  NSNumber(value: (2 * pause + travel) / duration), 1]
            animation.duration = duration; animation.repeatCount = .infinity; animation.calculationMode = .linear
            animation.beginTime = textTrack.convertTime(CACurrentMediaTime(), from: nil)
            textTrack.add(animation, forKey: Self.scrollKey)
            if key.shimmer { shimmerMaskTrack.add(animation, forKey: Self.scrollKey) }
        }
        if key.shimmer {
            // Fixed half-width of the supplied Retina reference phrase (~170 pt),
            // not half of each arbitrary label. Codex uses a 40%-60% flat crest,
            // a 1 s / 48-step sweep, 4 s cadence and a 600 ms initial delay.
            let band: CGFloat = 85
            let width = max(1, bounds.width)
            let travel = min(measured, width) + band * 1.5
            let stops: [CGFloat] = [0, 0.4, 0.6, 1]
            let frames = (0...48).map { frame in
                stops.map { NSNumber(value: Double((-band + travel * CGFloat(frame) / 48 + $0 * band) / width)) }
            }
            let animation = CAKeyframeAnimation(keyPath: "locations")
            shimmerLayer.locations = frames[0]
            animation.values = frames + [frames[48]]
            animation.keyTimes = (0...48).map { NSNumber(value: Double($0) / 48 / 4) } + [1]
            animation.calculationMode = .discrete
            animation.duration = 4; animation.repeatCount = .infinity
            animation.beginTime = shimmerLayer.convertTime(CACurrentMediaTime(), from: nil) + 0.6
            shimmerLayer.add(animation, forKey: Self.shimmerKey)
        }
    }
}

struct IslandScrollingText: NSViewRepresentable {
    let text: String
    let font: NSFont
    var color: NSColor = .white
    let visible: Bool
    let reduceMotion: Bool
    var shimmer = false
    func makeNSView(context: Context) -> IslandScrollingTextHost { .init(frame: .zero) }
    func updateNSView(_ view: IslandScrollingTextHost, context: Context) {
        view.configure(text: text, font: font, color: color, visible: visible, reduceMotion: reduceMotion, shimmer: shimmer)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: IslandScrollingTextHost, context: Context) -> CGSize? {
        CGSize(width: max(0, proposal.width ?? IslandScrollingTextHost.width(of: text, font: font)),
               height: IslandScrollingTextHost.height(for: font))
    }
    static func dismantleNSView(_ view: IslandScrollingTextHost, coordinator: ()) { view.stop() }
}

struct IslandOperationText: Equatable {
    let status: String
    let detail: String
    init(operation: String, statusTitle: String, completed: Bool) {
        let operation = operation.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = operation.components(separatedBy: " · ")
        if parts.count > 1, let prefix = parts.first, !prefix.isEmpty, prefix.count <= 24 {
            status = completed ? statusTitle : prefix
            detail = completed && ![statusTitle, "已完成", "Completed"].contains(prefix)
                ? operation : parts.dropFirst().joined(separator: " · ")
        } else {
            status = statusTitle
            detail = operation == statusTitle ? "" : operation
        }
    }
}
