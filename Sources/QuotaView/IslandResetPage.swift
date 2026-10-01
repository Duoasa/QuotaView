import AppKit
import SwiftUI
import QuotaViewCore

// Both card slots live in one fixed canvas. Anchors follow measured layout, so
// language, real values and notch hardware do not require hard-coded origins.
enum IslandResetTicketSlot: Hashable { case usage, reset }
struct IslandResetTicketAnchors: PreferenceKey {
    static var defaultValue: [IslandResetTicketSlot: Anchor<CGRect>] = [:]
    static func reduce(value: inout [IslandResetTicketSlot: Anchor<CGRect>], nextValue: () -> [IslandResetTicketSlot: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

struct IslandResetPageData {
    let snapshot: CurrentCodexPresentation?
    var credits: Int? { snapshot?.availableResetCredits.map { max(0, $0) } }
    var remainingPercent: Int? {
        let window = snapshot?.quotaWindows.first { $0.windowDurationMinutes == 10080 } ?? snapshot?.quotaWindows.first
        return (window?.remainingPercent ?? snapshot?.remainingPercent).map { min(100, max(0, $0)) }
    }
    var creditsAfterOne: Int? { credits.map { max(0, $0 - 1) } }
    var canPreview: Bool { (credits ?? 0) > 0 && remainingPercent != nil }
}

struct IslandResetPage: View {
    let data: IslandResetPageData
    let usageState: IslandUsagePresentation.State
    let english: Bool
    let playbackEnabled: Bool
    let hidesTicket: Bool
    let onRefresh: (() async -> Void)?
    let onHeightChange: (CGFloat) -> Void
    @State private var refreshing = false
    @State private var previewed = false
    private var copy: AppCopy { .init(language: english ? .english : .simplifiedChinese) }
    private let secondary = Color(white: 0.68)

    var body: some View {
        VStack(spacing: 10) {
            VStack(spacing: 16) {
                VStack(spacing: 12) {
                    IslandResetTicket(playbackEnabled: playbackEnabled, size: IslandResetTicketFlight.cardSize)
                        .opacity(hidesTicket ? 0 : 1)
                        .anchorPreference(key: IslandResetTicketAnchors.self, value: .bounds) { [.reset: $0] }
                        .accessibilityHidden(true)
                    HStack(spacing: 4) {
                        Text(copy.text("额度重置", "Quota reset")).foregroundStyle(secondary)
                        Text(data.credits.map { copy.text("\($0)次", "\($0) left") } ?? "—")
                    }.font(AstaSans.regular(16))
                }.padding(.vertical, 12).frame(maxWidth: .infinity)

                if usageState.isStale {
                    Text(copy.text("上次成功数据 · 等待刷新", "Last successful data · awaiting refresh"))
                        .font(AstaSans.regular(10)).foregroundStyle(secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Text(usageState.isStale ? copy.text("上次读取额度", "Last read quota") : copy.text("当前可用额度", "Current Quota Available")).foregroundStyle(secondary)
                    Spacer(minLength: 8)
                    Text(data.remainingPercent.map { "\($0)%" } ?? "—").monospacedDigit()
                }.font(AstaSans.regular(10))

                VStack(alignment: .leading, spacing: 10) {
                    Text(copy.text("⚠️ 重置前请注意", "⚠️ Before Resetting")).foregroundStyle(.white)
                    warning(copy.text("此操作会消耗 1 次额度重置机会。", "This action consumes one reset credit."))
                    warning(copy.text("符合条件的 Codex 用量周期将立即重置。", "Your eligible Codex usage cycle resets immediately."))
                    warning(copy.text("额度重置完成后无法撤销。", "A completed quota reset cannot be undone."))
                }.font(AstaSans.regular(10)).padding(14.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(white: 0.055), in: RoundedRectangle(cornerRadius: 14))
                    .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(Color(white: 0.13), lineWidth: 0.5) }

                Button { previewed = true } label: {
                    Text(previewed ? copy.text("演示完成", "Preview complete") : copy.text("额度重置", "Quota Reset"))
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity).frame(height: IslandApprovalMetrics.buttonHeight)
                }.buttonStyle(IslandApprovalActionStyle(primary: false, destructive: true))
                    .frame(maxWidth: .infinity).disabled(!data.canPreview)
                    .accessibilityLabel(copy.text("额度重置演示", "Quota reset preview"))
                    .accessibilityHint(copy.text("仅演示，不消耗次数或重置真实额度", "Preview only; no credit is consumed and no real quota is reset"))
            }

            HStack(spacing: 8) {
                Text((data.snapshot?.lastUpdatedAt).map {
                    copy.text("更新于 ", "Updated ") + $0.formatted(date: .omitted, time: .shortened)
                } ?? copy.text("等待更新", "Waiting for data"))
                Spacer(minLength: 0)
                Text(caption).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
                Button {
                    guard !refreshing else { return }
                    refreshing = true
                    Task { await onRefresh?(); refreshing = false }
                } label: {
                    Label(refreshing ? copy.text("刷新中", "Refreshing") : copy.text("刷新", "Refresh"), systemImage: "arrow.clockwise")
                        .padding(.horizontal, 10).frame(height: 26)
                        .background(Color(white: 0.10), in: Capsule())
                }.buttonStyle(.plain).disabled(refreshing || onRefresh == nil)
            }.font(AstaSans.regular(10)).foregroundStyle(secondary)
        }.padding(.horizontal, 28).padding(.top, 10).padding(.bottom, 14)
            .fixedSize(horizontal: false, vertical: true)
            .background { GeometryReader { proxy in Color.clear.preference(key: IslandResetPageHeightKey.self, value: proxy.size.height) } }
            .onPreferenceChange(IslandResetPageHeightKey.self, perform: onHeightChange)
            .foregroundStyle(.white)
            .accessibilityElement(children: .contain)
    }
    private var caption: String {
        if previewed { return copy.text("未消耗次数或重置额度", "No credit or quota changed") }
        guard let count = data.creditsAfterOne else { return copy.text("次数不可用", "Credits unavailable") }
        if !data.canPreview { return copy.text("没有可用重置次数", "No reset credits available") }
        return copy.text("演示 · 重置后剩余 \(count) 次", "Demo · \(count) left after reset")
    }
    private func warning(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Text("•")
            Text(text).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
        }.foregroundStyle(secondary)
    }
}
private struct IslandResetPageHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
// A reversible, sampled 3D flight. Only the card's compositor layers animate;
// both pages retain their final layout throughout the transition.
enum IslandResetTicketFlight {
    static let cardSize = CGSize(width: 201.29, height: 120)
    static let duration: TimeInterval = 0.76
    struct Sample {
        let position: CGPoint
        let transform: CATransform3D
    }
    static func sample(progress: CGFloat, source: CGRect, destination: CGRect) -> Sample {
        let lift = sin(.pi * progress)
        let width = source.width + (destination.width - source.width) * progress
        let height = source.height + (destination.height - source.height) * progress
        var transform = CATransform3DIdentity
        transform.m34 = -1 / 650
        transform = CATransform3DRotate(transform, lift * .pi / 10, 1, 0, 0)
        // Unwrapped yaw completes a full turn; sampled matrices preserve the
        // 90°/180°/270° faces instead of interpolating identical 0°/360° endpoints.
        transform = CATransform3DRotate(transform, -progress * .pi * 2, 0, 1, 0)
        transform = CATransform3DRotate(transform, -lift * .pi / 30, 0, 0, 1)
        transform = CATransform3DScale(transform, width / cardSize.width, height / cardSize.height, 1)
        return Sample(position: .init(x: source.midX + (destination.midX - source.midX) * progress,
            y: source.midY + (destination.midY - source.midY) * progress - 24 * lift), transform: transform)
    }
    // Quick lift, gentle overshoot, then settle. The same curve and samples are
    // traversed backwards on return, including the lift and 3D rotation.
    static func progress(at time: Double) -> CGFloat {
        let t = min(1, max(0, time))
        if t <= 0.72 {
            let u = t / 0.72
            return CGFloat(1.025 * (1 - pow(1 - u, 3)))
        }
        let u = (t - 0.72) / 0.28
        return CGFloat(1 + 0.025 * pow(1 - u, 2))
    }
}

final class IslandResetTicketFlightHost: NSView {
    override var isFlipped: Bool { true }
    private let card = CALayer()
    private let face = CALayer()
    private let mark = CALayer()
    private static let animationKey = "island.reset-ticket.flight"
    private var serial: UInt64?
    private var movingToReset = false
    private var startedAt: CFTimeInterval = 0
    private var flightDuration: TimeInterval = 0
    private var startProgress: CGFloat = 0
    private var endProgress: CGFloat = 1
    private var source = CGRect.zero
    private var destination = CGRect.zero
    var flightAnimation: CAAnimationGroup? { card.animation(forKey: Self.animationKey) as? CAAnimationGroup }
    var cardPosition: CGPoint { card.position }
    var cardTransform: CATransform3D { card.transform }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(card)
        card.bounds = CGRect(origin: .zero, size: IslandResetTicketFlight.cardSize)
        card.isDoubleSided = true
        card.addSublayer(face); card.addSublayer(mark)
        face.frame = card.bounds
        mark.bounds = CGRect(x: 0, y: 0, width: 45.3649, height: 45.302)
        mark.position = CGPoint(x: card.bounds.midX, y: card.bounds.midY)
        var faceRect = face.bounds, markRect = mark.bounds
        face.contents = NSImage(named: "IslandResetTicket")?.cgImage(forProposedRect: &faceRect, context: nil, hints: nil)
        mark.contents = NSImage(named: "IslandResetMark")?.cgImage(forProposedRect: &markRect, context: nil, hints: nil)
        face.contentsGravity = .resizeAspect; mark.contentsGravity = .resizeAspect
        face.contentsScale = 2; mark.contentsScale = 2
        card.shadowColor = NSColor.black.cgColor; card.shadowOpacity = 0.2
        card.shadowRadius = 5; card.shadowOffset = CGSize(width: 0, height: 3)
        card.shadowPath = CGPath(roundedRect: card.bounds, cornerWidth: 8.625, cornerHeight: 8.625, transform: nil)
        card.isHidden = true
    }
    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if window == nil { stop() } }
    func configure(serial: UInt64, toReset: Bool, active: Bool, source: CGRect, destination: CGRect, reduceMotion: Bool) {
        guard active, !reduceMotion, window != nil, Self.valid(source), Self.valid(destination) else { stop(); return }
        guard self.serial != serial else { return }
        let reversing = flightAnimation != nil && movingToReset != toReset
        let now = CACurrentMediaTime()
        let from = reversing ? currentProgress(at: now) : (toReset ? CGFloat(0) : CGFloat(1))
        let to: CGFloat = toReset ? 1 : 0
        let oldPosition = card.presentation()?.position
        let oldTransform = card.presentation()?.transform
        if !reversing { self.source = source; self.destination = destination }
        self.serial = serial; movingToReset = toReset
        startedAt = now; flightDuration = IslandResetTicketFlight.duration
        startProgress = from; endProgress = to
        let steps = 60
        let samples = (0...steps).map { index -> IslandResetTicketFlight.Sample in
            let time = Double(index) / Double(steps)
            // Return visits the exact opening samples in reverse order.
            let p: CGFloat = toReset ? IslandResetTicketFlight.progress(at: time)
                : 1 - IslandResetTicketFlight.progress(at: 1 - time)
            return IslandResetTicketFlight.sample(progress: from + (to - from) * p, source: self.source, destination: self.destination)
        }
        let position = CAKeyframeAnimation(keyPath: "position")
        position.values = samples.map { NSValue(point: $0.position) }
        let transform = CAKeyframeAnimation(keyPath: "transform")
        transform.values = samples.map { NSValue(caTransform3D: $0.transform) }
        if reversing, let oldPosition, let oldTransform {
            position.values?[0] = NSValue(point: oldPosition)
            transform.values?[0] = NSValue(caTransform3D: oldTransform)
        }
        let final = IslandResetTicketFlight.sample(progress: to, source: self.source, destination: self.destination)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        card.isHidden = false; card.position = final.position; card.transform = final.transform
        CATransaction.commit()
        let animation = CAAnimationGroup()
        position.duration = flightDuration; transform.duration = flightDuration
        animation.animations = [position, transform]; animation.duration = flightDuration
        animation.beginTime = card.convertTime(now, from: nil)
        animation.isRemovedOnCompletion = false; animation.fillMode = .forwards
        card.add(animation, forKey: Self.animationKey)
    }
    private func currentProgress(at now: CFTimeInterval) -> CGFloat {
        let time = min(1, max(0, (now - startedAt) / max(0.001, flightDuration)))
        let p = movingToReset ? IslandResetTicketFlight.progress(at: time) : 1 - IslandResetTicketFlight.progress(at: 1 - time)
        return startProgress + (endProgress - startProgress) * p
    }
    private static func valid(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite && rect.width.isFinite && rect.height.isFinite && rect.width > 0 && rect.height > 0
    }
    func stop() {
        serial = nil; card.removeAnimation(forKey: Self.animationKey)
        CATransaction.begin(); CATransaction.setDisableActions(true); card.isHidden = true; CATransaction.commit()
    }
}
struct IslandResetTicketFlightView: NSViewRepresentable {
    let serial: UInt64
    let toReset: Bool
    let active: Bool
    let source: CGRect
    let destination: CGRect
    let reduceMotion: Bool
    func makeNSView(context: Context) -> IslandResetTicketFlightHost { .init(frame: .zero) }
    func updateNSView(_ view: IslandResetTicketFlightHost, context: Context) {
        view.configure(serial: serial, toReset: toReset, active: active, source: source, destination: destination, reduceMotion: reduceMotion)
    }
    static func dismantleNSView(_ view: IslandResetTicketFlightHost, coordinator: ()) { view.stop() }
}
