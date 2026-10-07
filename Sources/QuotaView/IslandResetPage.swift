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
    enum CreditAvailability: Equatable { case unknown, empty, available }
    let snapshot: CurrentCodexPresentation?
    var creditAvailability: CreditAvailability {
        guard let credits else { return .unknown }
        return credits == 0 ? .empty : .available
    }
    var credits: Int? { snapshot?.availableResetCredits.map { max(0, $0) } }
    var remainingPercent: Int? {
        let window = snapshot?.quotaWindows.first { $0.windowDurationMinutes == 10080 } ?? snapshot?.quotaWindows.first
        return (window?.remainingPercent ?? snapshot?.remainingPercent).map { min(100, max(0, $0)) }
    }
    var creditsAfterOne: Int? { credits.map { max(0, $0 - 1) } }
    var canPreview: Bool { creditAvailability == .available && remainingPercent != nil }
    func actionTitle(previewed: Bool, copy: AppCopy) -> String {
        switch creditAvailability {
        case .empty: return copy.text("暂无可用重置卡", "No reset credits available")
        case .unknown: return copy.text("等待重置卡数据", "Waiting for reset credits")
        case .available:
            guard remainingPercent != nil else { return copy.text("等待额度数据", "Waiting for quota data") }
            return previewed ? copy.text("演示完成", "Preview complete") : copy.text("额度重置", "Quota Reset")
        }
    }
    func caption(previewed: Bool, copy: AppCopy) -> String {
        switch creditAvailability {
        case .empty: return copy.text("没有可用重置次数", "No reset credits available")
        case .unknown: return copy.text("次数不可用", "Credits unavailable")
        case .available:
            guard canPreview, let count = creditsAfterOne else { return copy.text("等待额度数据", "Waiting for quota data") }
            if previewed { return copy.text("未消耗次数或重置额度", "No credit or quota changed") }
            return copy.text("演示 · 重置后剩余 \(count) 次", "Demo · \(count) left after reset")
        }
    }
}

struct IslandResetPage: View {
    let data: IslandResetPageData
    let usageState: IslandUsagePresentation.State
    let english: Bool
    let playbackEnabled: Bool
    let hidesTicket: Bool
    let utilities: IslandUtilityActions
    var maximumHeight: CGFloat? = nil
    let onHeightChange: (CGFloat) -> Void
    var provider: IslandAgentProvider = .codex
    @State private var previewed = false
    @State private var copiedCommand = false
    private var isClaude: Bool { provider == .claudeCode }
    static let claudeResetCommand = "/limit-reset"
    private var copy: AppCopy { .init(language: english ? .english : .simplifiedChinese) }
    private let secondary = Color(white: 0.68)

    var body: some View {
        IslandPageLayout(maximumHeight: maximumHeight, onHeightChange: onHeightChange) {
            VStack(spacing: 10) {
            VStack(spacing: 16) {
                VStack(spacing: 12) {
                    IslandResetTicket(playbackEnabled: playbackEnabled, size: IslandResetTicketFlight.cardSize, provider: provider)
                        .opacity(hidesTicket ? 0 : 1)
                        .anchorPreference(key: IslandResetTicketAnchors.self, value: .bounds) { [.reset: $0] }
                        .accessibilityHidden(true)
                    HStack(spacing: 4) {
                        Text(copy.text("额度重置", "Quota reset")).foregroundStyle(secondary)
                        if isClaude {
                            Text(Self.claudeResetCommand).font(.system(size: 14, weight: .semibold, design: .monospaced))
                        } else {
                            Text(data.credits.map { copy.text("\($0)次", "\($0) left") } ?? "—")
                        }
                    }.font(AstaSans.semiBold(15)).tracking(-0.15)
                }.padding(.vertical, 12).frame(maxWidth: .infinity)

                if usageState.isStale {
                    Text(copy.text("显示上次数据", "Showing previous data"))
                        .font(AstaSans.regular(10.5)).foregroundStyle(secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Text(usageState.isStale ? copy.text("上次额度", "Previous quota") : copy.text("可用额度", "Available quota")).foregroundStyle(secondary)
                    Spacer(minLength: 8)
                    Text(data.remainingPercent.map { "\($0)%" } ?? "—")
                        .font(AstaSans.medium(11)).monospacedDigit()
                }.font(AstaSans.regular(11))

                VStack(alignment: .leading, spacing: 8) {
                    if isClaude {
                        Text(copy.text("在 Claude Code 中使用重置", "Use resets in Claude Code"))
                            .font(AstaSans.semiBold(11)).foregroundStyle(.white)
                        warning(copy.text("运行 /limit-reset 查看剩余次数与使用期限。", "Run /limit-reset to see resets left and their deadline."))
                        warning(copy.text("每次重置立即恢复额度，每周重置日保持不变。", "Each reset refills your limits now; your weekly reset day stays the same."))
                        warning(copy.text("QuotaView 只读取本机数据，不会替你使用重置。", "QuotaView reads local data only and never uses a reset for you."))
                    } else {
                    switch data.creditAvailability {
                    case .empty:
                        Text(copy.text("暂无可用重置卡", "No reset credits available"))
                            .font(AstaSans.semiBold(11)).foregroundStyle(.white)
                        Text(copy.text("返回用量页查看额度与恢复时间。", "Return to usage to check your quota and reset time."))
                            .foregroundStyle(secondary).fixedSize(horizontal: false, vertical: true)
                    case .unknown:
                        Text(copy.text("重置卡数据暂不可用", "Reset credits unavailable"))
                            .font(AstaSans.semiBold(11)).foregroundStyle(.white)
                        Text(copy.text("刷新以获取重置次数。", "Refresh to check reset credits."))
                            .foregroundStyle(secondary).fixedSize(horizontal: false, vertical: true)
                    case .available:
                        Text(copy.text("⚠️ 重置须知", "⚠️ Before resetting"))
                            .font(AstaSans.semiBold(11)).foregroundStyle(.white)
                        warning(copy.text("重置会消耗 1 次机会。", "Resetting uses one reset credit."))
                        warning(copy.text("立即重置符合条件的 Codex 用量周期。", "Eligible Codex usage cycles reset immediately."))
                        warning(copy.text("重置后无法撤销。", "A reset cannot be undone."))
                    }
                    }
                }.font(AstaSans.regular(11)).lineSpacing(3).padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(white: 0.055), in: RoundedRectangle(cornerRadius: 14))
                    .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(Color(white: 0.13), lineWidth: 0.5) }

                if isClaude {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(Self.claudeResetCommand, forType: .string)
                        copiedCommand = true
                    } label: {
                        Text(copiedCommand ? copy.text("已复制，到 Claude Code 中粘贴运行", "Copied — paste it in Claude Code")
                            : copy.text("复制 /limit-reset", "Copy /limit-reset"))
                            .font(AstaSans.semiBold(13))
                            .frame(maxWidth: .infinity).frame(height: IslandApprovalMetrics.buttonHeight)
                    }.buttonStyle(IslandApprovalActionStyle(primary: false))
                        .frame(maxWidth: .infinity)
                        .accessibilityHint(copy.text("复制命令，不会使用重置", "Copies the command; no reset is used"))
                } else {
                Button {
                    guard data.canPreview else { return }
                    previewed = true
                } label: {
                    Text(data.actionTitle(previewed: previewed, copy: copy))
                        .font(AstaSans.semiBold(13))
                        .frame(maxWidth: .infinity).frame(height: IslandApprovalMetrics.buttonHeight)
                }.buttonStyle(IslandApprovalActionStyle(primary: false, destructive: true))
                    .frame(maxWidth: .infinity).disabled(!data.canPreview)
                    .accessibilityLabel(data.canPreview ? copy.text("额度重置演示", "Quota reset preview") : data.actionTitle(previewed: false, copy: copy))
                    .accessibilityHint(data.canPreview
                        ? copy.text("仅演示，次数与真实额度不变", "Preview only; real credits and quota stay unchanged")
                        : copy.text("刷新数据或返回用量", "Refresh or return to usage"))
                }
            }

            Text(isClaude ? copy.text("重置次数与期限只在 Claude Code 中显示。", "Resets left and deadlines are shown only in Claude Code.")
                 : data.caption(previewed: previewed, copy: copy))
                .font(AstaSans.regular(10.5)).lineSpacing(2).foregroundStyle(secondary)
                .fixedSize(horizontal: false, vertical: true)
            }.padding(.horizontal, IslandVibeLayout.listInset).padding(.top, 10)
        } footer: {
            IslandChromeFooter {
                Text((data.snapshot?.lastUpdatedAt).map {
                    copy.text("更新于 ", "Updated ") + $0.formatted(date: .omitted, time: .shortened)
                } ?? copy.text("等待更新", "Waiting for data")).lineLimit(1)
            } trailing: { utilities }
        }.foregroundStyle(.white)
            .accessibilityElement(children: .contain)
            .onChange(of: data.credits) { _, _ in previewed = false }
            .onChange(of: provider) { _, _ in previewed = false; copiedCommand = false }
    }
    private func warning(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Text("•")
            Text(text).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
        }.foregroundStyle(secondary)
    }
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
    // Both directions start moving immediately, then gently overshoot and settle.
    // Reverse the spatial progress on return, keeping the elapsed-time easing forward.
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
    var provider: IslandAgentProvider = .codex {
        didSet { if provider != oldValue { applyArtwork() } }
    }
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
        applyArtwork()
        face.contentsGravity = .resizeAspect; mark.contentsGravity = .resizeAspect
        face.contentsScale = 2; mark.contentsScale = 2
        card.shadowColor = NSColor.black.cgColor; card.shadowOpacity = 0.2
        card.shadowRadius = 5; card.shadowOffset = CGSize(width: 0, height: 3)
        card.shadowPath = CGPath(roundedRect: card.bounds, cornerWidth: 8.625, cornerHeight: 8.625, transform: nil)
        card.isHidden = true
    }
    required init?(coder: NSCoder) { nil }
    private func applyArtwork() {
        var faceRect = face.bounds, markRect = mark.bounds
        face.contents = NSImage(named: IslandResetTicketArtwork.faceName(provider))?
            .cgImage(forProposedRect: &faceRect, context: nil, hints: nil)
        mark.contents = IslandResetTicketArtwork.mark(provider)?.cgImage(forProposedRect: &markRect, context: nil, hints: nil)
    }
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
            let p = IslandResetTicketFlight.progress(at: time)
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
        let p = IslandResetTicketFlight.progress(at: time)
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
    var provider: IslandAgentProvider = .codex
    func makeNSView(context: Context) -> IslandResetTicketFlightHost { .init(frame: .zero) }
    func updateNSView(_ view: IslandResetTicketFlightHost, context: Context) {
        view.provider = provider
        view.configure(serial: serial, toReset: toReset, active: active, source: source, destination: destination, reduceMotion: reduceMotion)
    }
    static func dismantleNSView(_ view: IslandResetTicketFlightHost, coordinator: ()) { view.stop() }
}
