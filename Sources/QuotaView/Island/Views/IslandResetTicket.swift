import AppKit
import SwiftUI
import QuotaViewCore

// Usage stays inside the notch; charts reuse the menu's quota/cost data contracts.
// The pointer tracks the fixed 53.677 × 32 pt plane, never the transformed
// face. SwiftUI interpolates only the small visual layers; layout stays fixed.
/// Provider marks sit on QuotaView-designed card faces. The Claude silhouette
/// is shared with task/usage icons and tinted cream on its clay face.
enum IslandResetTicketArtwork {
    static let claudeMarkColor = NSColor(red: 1, green: 0.957, blue: 0.925, alpha: 1)
    static func faceName(_ provider: IslandAgentProvider) -> String {
        provider == .codex ? "IslandResetTicket" : "IslandClaudeResetTicket"
    }
    @MainActor static let claudeMark: NSImage? = IslandProviderIcon.claudeImage.map { source in
        NSImage(size: source.size, flipped: false) { rect in
            source.draw(in: rect)
            claudeMarkColor.setFill()
            rect.fill(using: .sourceIn)
            return true
        }
    }
    private static let emptyFaceSize = CGSize(width: 201.29, height: 120)
    private static let emptyMarkSize = CGSize(width: 45.3649, height: 45.302)
    // Rasterize once at 2x. Empty cards use ordinary immutable bitmaps, not a
    // deferred AppKit drawing handler or an opacity group containing NSViews.
    @MainActor private static func bitmap(size: CGSize, draw: (CGContext, CGRect) -> Void) -> CGImage? {
        let width = Int(ceil(size.width * 2)), height = Int(ceil(size.height * 2))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        else { return nil }
        context.scaleBy(x: CGFloat(width) / size.width, y: CGFloat(height) / size.height)
        draw(context, CGRect(origin: .zero, size: size))
        return context.makeImage()
    }
    @MainActor static let emptyFaceCGImage = bitmap(size: emptyFaceSize) { context, rect in
        context.addPath(CGPath(roundedRect: rect, cornerWidth: 8.625, cornerHeight: 8.625, transform: nil))
        context.clip()
        context.setFillColor(CGColor(red: 0.28, green: 0.28, blue: 0.28, alpha: 1))
        context.fill(rect)
        let colors = [CGColor(red: 0.34, green: 0.34, blue: 0.34, alpha: 1),
                      CGColor(red: 0.25, green: 0.25, blue: 0.25, alpha: 1)] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: rect.maxY),
                end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
        }
    }
    @MainActor static let emptyMarkCGImage = bitmap(size: emptyMarkSize) { context, rect in
        // The mathematical empty-set sign ∅ as cached geometry: no font lookup
        // or text layout on the first transition to an exhausted card.
        context.setStrokeColor(CGColor(red: 0.60, green: 0.60, blue: 0.60, alpha: 1))
        context.setLineWidth(2.3)
        context.setLineCap(.round)
        context.strokeEllipse(in: CGRect(x: rect.midX - 12.5, y: rect.midY - 12.5, width: 25, height: 25))
        context.move(to: CGPoint(x: rect.midX - 12.5, y: rect.midY - 14))
        context.addLine(to: CGPoint(x: rect.midX + 12.5, y: rect.midY + 14))
        context.strokePath()
    }
    @MainActor static let emptyFace = emptyFaceCGImage.map { NSImage(cgImage: $0, size: emptyFaceSize) }
        ?? NSImage(size: emptyFaceSize)
    @MainActor static let emptyMark = emptyMarkCGImage.map { NSImage(cgImage: $0, size: emptyMarkSize) }
        ?? NSImage(size: emptyMarkSize)
    @MainActor static func mark(_ provider: IslandAgentProvider, isEmpty: Bool = false) -> NSImage? {
        if isEmpty { return emptyMark }
        return provider == .codex ? NSImage(named: "IslandResetMark") : claudeMark
    }
}

struct IslandResetTicket: View {
    let playbackEnabled: Bool
    var size = CGSize(width: 53.6774, height: 32)
    var provider: IslandAgentProvider = .codex
    var isEmpty = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tilt = CGSize.zero
    @State private var hovered = false
    private var scale: CGFloat { size.height / 32 }
    private var motion: CGSize { reduceMotion ? .zero : tilt }
    var body: some View {
        ZStack {
            ZStack {
                if isEmpty {
                    Image(nsImage: IslandResetTicketArtwork.emptyFace).resizable().scaledToFit()
                } else {
                    Image(IslandResetTicketArtwork.faceName(provider)).resizable().scaledToFit()
                    RadialGradient(colors: [.white.opacity(hovered ? 0.28 : 0), .clear],
                        center: UnitPoint(x: 0.5 + motion.width * 0.25, y: 0.5 + motion.height * 0.25),
                        startRadius: 0, endRadius: 42 * scale)
                        .clipShape(RoundedRectangle(cornerRadius: 2.3 * scale))
                }
                Group {
                    if isEmpty {
                        Image(nsImage: IslandResetTicketArtwork.emptyMark).resizable().scaledToFit()
                    } else if provider == .codex {
                        Image("IslandResetMark").resizable().scaledToFit()
                    } else if let mark = IslandResetTicketArtwork.claudeMark {
                        Image(nsImage: mark).resizable().scaledToFit()
                    }
                }.frame(width: 12.0973 * scale, height: 12.0805 * scale)
                    .offset(x: motion.width * 0.9 * scale, y: motion.height * 0.6 * scale)
                if !isEmpty {
                    IslandResetTicketSweep(active: playbackEnabled)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .frame(width: size.width, height: size.height)
            .rotation3DEffect(.degrees(Double(-motion.height * 7)), axis: (x: 1, y: 0, z: 0), perspective: 0.4)
            .rotation3DEffect(.degrees(Double(motion.width * 10)), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
            .shadow(color: .black.opacity(hovered ? 0.3 : 0), radius: hovered ? 4 * min(2, scale) : 0,
                x: -motion.width * 2 * scale, y: hovered ? 3 * min(2, scale) : 0)
            .allowsHitTesting(false)
        }
        .frame(width: size.width, height: size.height).contentShape(Rectangle())
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.86), value: tilt)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: hovered)
        .onContinuousHover { phase in
            switch phase {
            case .active(let point):
                guard point.x.isFinite, point.y.isFinite else { return }
                hovered = true
                tilt = CGSize(width: min(1, max(-1, point.x / size.width * 2 - 1)),
                    height: min(1, max(-1, point.y / size.height * 2 - 1)))
            case .ended: hovered = false; tilt = .zero
            }
        }
        .onDisappear { hovered = false; tilt = .zero }
    }
}
// One compositor animation on the ticket face. No frame timer, page redraw,
// data refresh or hover dependency. Hidden/detached/reduced-motion views stop.
final class IslandResetTicketSweepHost: NSView {
    private let stripe = CAGradientLayer()
    private static let animationKey = "island.reset-ticket.sweep"
    private var enabled = false
    private var renderedSize = CGSize.zero
    var sweepAnimation: CAKeyframeAnimation? { stripe.animation(forKey: Self.animationKey) as? CAKeyframeAnimation }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true; layer?.cornerRadius = 2.3
        stripe.colors = [NSColor.white.withAlphaComponent(0).cgColor,
            NSColor.white.withAlphaComponent(0.18).cgColor, NSColor.white.withAlphaComponent(0.70).cgColor,
            NSColor.white.withAlphaComponent(0.18).cgColor, NSColor.white.withAlphaComponent(0).cgColor]
        stripe.locations = [0, 0.3, 0.5, 0.7, 1]
        stripe.startPoint = CGPoint(x: 0, y: 0.5); stripe.endPoint = CGPoint(x: 1, y: 0.5)
        stripe.isHidden = true; layer?.addSublayer(stripe)
    }
    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateAnimation() }
    func configure(active: Bool, reduceMotion: Bool) {
        let next = active && !reduceMotion
        guard enabled != next else { return }
        enabled = next; updateAnimation()
    }
    override func layout() {
        super.layout()
        if renderedSize != bounds.size {
            renderedSize = bounds.size
            CATransaction.begin(); CATransaction.setDisableActions(true)
            layer?.cornerRadius = 2.3 * bounds.height / 32
            stripe.bounds = CGRect(x: 0, y: 0, width: 20 * bounds.height / 32, height: bounds.height * 3)
            stripe.position = CGPoint(x: bounds.midX, y: bounds.midY)
            stripe.setAffineTransform(CGAffineTransform(rotationAngle: -.pi / 7))
            CATransaction.commit()
            stripe.removeAnimation(forKey: Self.animationKey)
        }
        updateAnimation()
    }
    private func updateAnimation() {
        guard enabled, window != nil, bounds.width > 0, bounds.height > 0 else { stop(); return }
        CATransaction.begin(); CATransaction.setDisableActions(true); stripe.isHidden = false; CATransaction.commit()
        guard sweepAnimation == nil else { return }
        let travel = bounds.width + bounds.height
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.values = [-travel, -travel, travel, travel]
        animation.keyTimes = [0, 0.10, 0.90, 1]
        animation.timingFunctions = [.init(name: .linear), .init(name: .easeInEaseOut), .init(name: .linear)]
        animation.duration = 2; animation.repeatCount = .infinity
        animation.beginTime = stripe.convertTime(CACurrentMediaTime(), from: nil)
        stripe.add(animation, forKey: Self.animationKey)
    }
    func stop() {
        stripe.removeAnimation(forKey: Self.animationKey)
        CATransaction.begin(); CATransaction.setDisableActions(true); stripe.isHidden = true; CATransaction.commit()
    }
}
private struct IslandResetTicketSweep: NSViewRepresentable {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeNSView(context: Context) -> IslandResetTicketSweepHost { .init(frame: .zero) }
    func updateNSView(_ view: IslandResetTicketSweepHost, context: Context) {
        view.configure(active: active, reduceMotion: reduceMotion)
    }
    static func dismantleNSView(_ view: IslandResetTicketSweepHost, coordinator: ()) { view.stop() }
}
