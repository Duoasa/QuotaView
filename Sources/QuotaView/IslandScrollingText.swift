import AppKit
import CoreText
import SwiftUI

extension NSAttributedString.Key {
    static let islandInlineImage = NSAttributedString.Key("QuotaView.islandInlineImage")
}

// Text luminance is encoded in RGB, never by blending white over its backdrop.
enum IslandTextPalette {
    static let secondary = NSColor(srgbRed: 179 / 255, green: 179 / 255, blue: 179 / 255, alpha: 1)
    static let muted = NSColor(srgbRed: 125 / 255, green: 125 / 255, blue: 125 / 255, alpha: 1)
    static let detail = NSColor(srgbRed: 195 / 255, green: 195 / 255, blue: 195 / 255, alpha: 1)
}

// Rich activity uses a known CoreText baseline. CATextLayer's first-line
// placement remains unchanged for ordinary text and the shimmer mask.
private final class IslandRichTextLayer: CALayer {
    private(set) var line: CTLine?
    private(set) var baseline: CGFloat = 0
    override init() { super.init(); isGeometryFlipped = false }
    override init(layer: Any) {
        super.init(layer: layer)
        if let source = layer as? IslandRichTextLayer {
            line = source.line; baseline = source.baseline
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    func configure(line: CTLine?, baseline: CGFloat) {
        self.line = line; self.baseline = baseline
        setNeedsDisplay()
    }
    override func draw(in context: CGContext) {
        guard let line else { return }
        context.saveGState()
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: 0, y: baseline)
        CTLineDraw(line, context)
        context.restoreGState()
    }
}

// Native presentation: text movement stays in Core Animation, outside SwiftUI layout.
final class IslandScrollingTextHost: NSView {
    private let textTrack = CALayer()
    private let textLayer = CATextLayer()
    private let repeatedTextLayer = CATextLayer()
    private let richTextLayer = IslandRichTextLayer()
    private let repeatedRichTextLayer = IslandRichTextLayer()
    private let shimmerLayer = CAGradientLayer()
    private let shimmerMaskTrack = CALayer()
    private let shimmerMask = CATextLayer()
    private let repeatedShimmerMask = CATextLayer()
    private var inlineImageLayers: [CALayer] = []
    private var repeatedInlineImageLayers: [CALayer] = []
    private var inlineImageSources: [NSImage] = []
    private var inlineImageScale: CGFloat = 0
    private static let inlineImageSize: CGFloat = 14
    private(set) var richLineTruncated = false
    private static let scrollKey = "console.text.scroll"
    private static let shimmerKey = "console.text.shimmer"
    private var text = ""
    private var attributedText: NSAttributedString?
    private var streamIdentity: String?
    private var font = NSFont.systemFont(ofSize: 13)
    private var color = NSColor.white
    private var visible = false
    private var reduceMotion = false
    private var shimmering = false
    private var layoutKey: LayoutKey?
    private var scrollGeometry: ScrollGeometry?
    private struct LayoutKey: Equatable {
        var text: String
        var attributedText: NSAttributedString?
        var streamIdentity: String?
        var font: NSFont
        var color: NSColor
        var size: CGSize
        var scale: CGFloat
        var animate: Bool
        var shimmer: Bool
    }
    private struct ScrollGeometry: Equatable {
        var measuredWidth: CGFloat
        var lineHeight: CGFloat
        var size: CGSize
        var scale: CGFloat
        var animate: Bool
    }
    var scrollAnimation: CAKeyframeAnimation? { textTrack.animation(forKey: Self.scrollKey) as? CAKeyframeAnimation }
    var shimmerAnimation: CAKeyframeAnimation? { shimmerLayer.animation(forKey: Self.shimmerKey) as? CAKeyframeAnimation }
    private(set) var scrollDistance: CGFloat = 0
    var textColorAlpha: CGFloat { color.alphaComponent }
    var shimmerColorAlphas: [CGFloat] { (shimmerLayer.colors as? [CGColor] ?? []).map(\.alpha) }
    var renderedAttributedText: NSAttributedString? { textLayer.string as? NSAttributedString }
    var inlineImageFrames: [CGRect] { inlineImageLayers.map(\.frame) }
    var visibleInlineImageFrames: [CGRect] { inlineImageLayers.filter { !$0.isHidden }.map(\.frame) }
    var richTextBaseline: CGFloat { richTextLayer.frame.minY + richTextLayer.baseline }
    var richTextCapHeight: CGFloat { font.capHeight }
    var renderedRichLine: CTLine? { richTextLayer.line }
    var inlineImagesHaveContents: Bool { inlineImageLayers.allSatisfy { $0.contents != nil } }
    var repeatedInlineImagesVisible: Bool { repeatedInlineImageLayers.contains { !$0.isHidden } }

    static func width(of text: String, font: NSFont) -> CGFloat {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        return ceil(CTLineGetTypographicBounds(line, nil, nil, nil)) + 2
    }
    static func height(for font: NSFont) -> CGFloat { ceil(font.ascender - font.descender + font.leading) }
    static func width(of text: NSAttributedString) -> CGFloat {
        ceil(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(text), nil, nil, nil)) + 2
    }
    static func height(for text: NSAttributedString, font: NSFont) -> CGFloat {
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        _ = CTLineGetTypographicBounds(CTLineCreateWithAttributedString(text), &ascent, &descent, &leading)
        var hasImage = false
        text.enumerateAttribute(.islandInlineImage, in: NSRange(location: 0, length: text.length)) { value, _, stop in
            if value is NSImage { hasImage = true; stop.pointee = true }
        }
        return max(height(for: font), ceil(ascent + descent + leading), hasImage ? inlineImageSize : 0)
    }

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
        textTrack.addSublayer(richTextLayer)
        textTrack.addSublayer(repeatedRichTextLayer)
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
    override func viewDidHide() { super.viewDidHide(); needsLayout = true; layoutSubtreeIfNeeded() }
    override func viewDidUnhide() { super.viewDidUnhide(); needsLayout = true; layoutSubtreeIfNeeded() }

    func configure(text: String, font: NSFont, color: NSColor, visible: Bool, reduceMotion: Bool, shimmer: Bool) {
        self.text = text; self.font = font; self.color = color.withAlphaComponent(1)
        attributedText = nil
        streamIdentity = nil
        self.visible = visible; self.reduceMotion = reduceMotion; shimmering = shimmer
        needsLayout = true
        layoutSubtreeIfNeeded()
    }
    func configure(attributedText: NSAttributedString, font: NSFont, visible: Bool, reduceMotion: Bool,
                   streamIdentity: String? = nil) {
        let normalized = NSMutableAttributedString(attributedString: attributedText)
        attributedText.enumerateAttributes(in: NSRange(location: 0, length: attributedText.length)) { attributes, range, _ in
            var attributes = attributes
            attributes[.font] = attributes[.font] ?? font
            attributes[.foregroundColor] = (attributes[.foregroundColor] as? NSColor ?? .white).withAlphaComponent(1)
            normalized.setAttributes(attributes, range: range)
        }
        self.attributedText = NSAttributedString(attributedString: normalized)
        self.streamIdentity = streamIdentity
        text = normalized.string; self.font = font; color = .white
        self.visible = visible; self.reduceMotion = reduceMotion; shimmering = false
        needsLayout = true
        layoutSubtreeIfNeeded()
    }
    func stop() { visible = false; needsLayout = true; layoutSubtreeIfNeeded() }

    override func layout() {
        super.layout()
        let animate = visible && !isHiddenOrHasHiddenAncestor && window != nil
            && !reduceMotion && bounds.width > 0 && !text.isEmpty
        let key = LayoutKey(text: text, attributedText: attributedText, streamIdentity: streamIdentity,
                            font: font, color: color, size: bounds.size,
                            scale: window?.backingScaleFactor ?? 2, animate: animate, shimmer: animate && shimmering)
        guard layoutKey != key else { return }
        let previousKey = layoutKey
        layoutKey = key
        let renderedText = attributedText ?? NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        let measured = Self.width(of: renderedText)
        let height = attributedText.map { Self.height(for: $0, font: font) } ?? Self.height(for: font)
        let geometry = ScrollGeometry(measuredWidth: measured, lineHeight: height, size: bounds.size, scale: key.scale, animate: animate)
        let previousAnimation = textTrack.animation(forKey: Self.scrollKey)
        let sameRichStream = attributedText != nil && previousKey?.attributedText != nil
            && previousKey?.streamIdentity == streamIdentity
        // A duration or status repaint with compatible geometry must not restart
        // the rich lane's travel. Preserve its existing animation and beginTime.
        let preserveScroll = sameRichStream && scrollGeometry == geometry && previousAnimation != nil
        // Status labels can change width many times during the opening pause.
        // Stable membership retains the stream's clock while values adapt to
        // new widths, so repeated updates cannot keep postponing that pause.
        let preservedBeginTime = streamIdentity != nil && sameRichStream && animate
            && scrollGeometry?.animate == true && scrollGeometry?.size == geometry.size
            && scrollGeometry?.scale == geometry.scale && scrollGeometry?.lineHeight == geometry.lineHeight
            ? previousAnimation?.beginTime : nil
        scrollGeometry = geometry
        if !preserveScroll { textTrack.removeAnimation(forKey: Self.scrollKey) }
        shimmerMaskTrack.removeAnimation(forKey: Self.scrollKey)
        shimmerLayer.removeAnimation(forKey: Self.shimmerKey)
        scrollDistance = animate ? max(0, measured - bounds.width) : 0
        let scrolling = scrollDistance > 1
        let loopDistance = measured + 32
        let textFrame = CGRect(x: 0, y: (bounds.height - height) / 2,
                               width: scrolling ? measured : max(0, bounds.width), height: height)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        textTrack.frame = bounds
        // Shimmer is the sole glyph layer while active, using opaque RGB stops.
        textTrack.isHidden = key.shimmer
        textLayer.frame = textFrame
        textLayer.string = renderedText
        textLayer.truncationMode = scrolling ? .none : .end
        textLayer.contentsScale = key.scale
        let rich = attributedText != nil
        textLayer.isHidden = rich
        repeatedTextLayer.frame = textFrame.offsetBy(dx: loopDistance, dy: 0)
        repeatedTextLayer.string = textLayer.string
        repeatedTextLayer.truncationMode = .none
        repeatedTextLayer.contentsScale = key.scale
        repeatedTextLayer.isHidden = rich || !scrolling
        richTextLayer.frame = textFrame
        richTextLayer.contentsScale = key.scale
        richTextLayer.isHidden = !rich
        repeatedRichTextLayer.frame = textFrame.offsetBy(dx: loopDistance, dy: 0)
        repeatedRichTextLayer.contentsScale = key.scale
        repeatedRichTextLayer.isHidden = !rich || !scrolling
        // The body font's cap-height centre, rather than the largest run's
        // ascent, is shared with every avatar on this lane.
        let baseline = (height - font.capHeight) / 2
        if !rich { richLineTruncated = false }
        let richLine = rich ? makeRichLine(renderedText, width: textFrame.width, truncate: !scrolling) : nil
        richTextLayer.configure(line: richLine, baseline: baseline)
        repeatedRichTextLayer.configure(line: richLine, baseline: baseline)
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
        updateInlineImages(line: richLine, loopDistance: loopDistance, scale: key.scale, scrolling: scrolling,
            visualCentre: textFrame.minY + baseline + font.capHeight / 2)
        CATransaction.commit()
        if scrolling && !preserveScroll {
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
            animation.beginTime = preservedBeginTime ?? textTrack.convertTime(CACurrentMediaTime(), from: nil)
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

    private func makeRichLine(_ text: NSAttributedString, width: CGFloat, truncate: Bool) -> CTLine? {
        richLineTruncated = false
        guard width > 0 else { return nil }
        let line = CTLineCreateWithAttributedString(text)
        guard truncate, CTLineGetTypographicBounds(line, nil, nil, nil) > Double(width) else { return line }
        richLineTruncated = true
        let tokenColor = text.length > 0 ? text.attribute(.foregroundColor, at: text.length - 1, effectiveRange: nil) : nil
        let token = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: [
            .font: font, .foregroundColor: tokenColor as? NSColor ?? .white
        ]))
        return CTLineCreateTruncatedLine(line, Double(width), .end, token)
    }

    private func updateInlineImages(line: CTLine?, loopDistance: CGFloat, scale: CGFloat, scrolling: Bool,
                                    visualCentre: CGFloat) {
        var images: [(image: NSImage, offset: CGFloat)] = []
        // Inspect the actual drawn line, including its truncation. An avatar
        // removed together with its marker must not overlay the ellipsis.
        if let line {
            for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                let attributes = CTRunGetAttributes(run) as NSDictionary
                guard let image = attributes[NSAttributedString.Key.islandInlineImage] as? NSImage else { continue }
                let range = CTRunGetStringRange(run)
                let offset = CTLineGetOffsetForStringIndex(line, range.location, nil)
                images.append((image, offset))
            }
        }
        while inlineImageLayers.count > images.count {
            inlineImageLayers.removeLast().removeFromSuperlayer()
            repeatedInlineImageLayers.removeLast().removeFromSuperlayer()
        }
        while inlineImageLayers.count < images.count {
            let first = CALayer(), repeated = CALayer()
            first.contentsGravity = .resizeAspect; repeated.contentsGravity = .resizeAspect
            textTrack.addSublayer(first); textTrack.addSublayer(repeated)
            inlineImageLayers.append(first); repeatedInlineImageLayers.append(repeated)
        }
        for (index, item) in images.enumerated() {
            let first = inlineImageLayers[index], repeated = repeatedInlineImageLayers[index]
            if index >= inlineImageSources.count || inlineImageSources[index] !== item.image
                || inlineImageScale != scale || first.contents == nil {
                var proposed = CGRect(x: 0, y: 0, width: Self.inlineImageSize * scale, height: Self.inlineImageSize * scale)
                let pixels = item.image.cgImage(forProposedRect: &proposed, context: nil, hints: nil)
                first.contents = pixels; repeated.contents = pixels
            }
            first.contentsScale = scale; repeated.contentsScale = scale
            first.frame = CGRect(x: item.offset, y: visualCentre - Self.inlineImageSize / 2,
                width: Self.inlineImageSize, height: Self.inlineImageSize)
            first.isHidden = item.offset < 0 || (!scrolling && first.frame.maxX > bounds.width)
            repeated.frame = first.frame.offsetBy(dx: loopDistance, dy: 0)
            repeated.isHidden = !scrolling
        }
        inlineImageSources = images.map(\.image); inlineImageScale = scale
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

struct IslandAttributedScrollingText: NSViewRepresentable {
    let text: NSAttributedString
    let font: NSFont
    let visible: Bool
    let reduceMotion: Bool
    var streamIdentity: String? = nil
    func makeNSView(context: Context) -> IslandScrollingTextHost { .init(frame: .zero) }
    func updateNSView(_ view: IslandScrollingTextHost, context: Context) {
        view.configure(attributedText: text, font: font, visible: visible, reduceMotion: reduceMotion, streamIdentity: streamIdentity)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: IslandScrollingTextHost, context: Context) -> CGSize? {
        CGSize(width: max(0, proposal.width ?? IslandScrollingTextHost.width(of: text)),
               height: IslandScrollingTextHost.height(for: text, font: font))
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
