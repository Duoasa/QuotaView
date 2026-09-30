import AppKit
import SwiftUI

// Liquid geometry migrated from the user-reviewed isolated prototype.
enum CodexMultitaskGeometry {
    static let diameter = CodexActivityIslandPresentation.compactSurfaceSize.height
    static let satelliteWidth = diameter * 2
    static let gap: CGFloat = 12
    static let bridgeCutoff: CGFloat = 12
    static let separationTime: TimeInterval = 0.36
    static let duration: TimeInterval = 0.42
    static let bounce = 0.15
    static let spring = Spring(duration: duration, bounce: bounce)
    static var mainSize: NSSize {
        let size = CodexActivityIslandGeometry.panelSize(presentation: .expanded, state: .working)
        let inset = CodexActivityIslandGeometry.panelInset
        return NSSize(width: size.width - inset * 2, height: size.height - inset * 2)
    }
    static var compactSize: NSSize {
        let size = CodexActivityIslandGeometry.panelSize(presentation: .compact, state: .completed)
        let inset = CodexActivityIslandGeometry.panelInset
        return NSSize(width: size.width - inset * 2, height: size.height - inset * 2)
    }
    // Coordinates relative to the fixed screen center. Input order is never sorted by activity.
    static func frames(ids: [Int], selected: Int, compact: Bool) -> [Int: CGRect] {
        guard let index = ids.firstIndex(of: selected) else { return [:] }
        let size = compact ? compactSize : mainSize
        var result: [Int: CGRect] = [selected: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)]
        for (i, id) in ids.enumerated() where id != selected {
            let distance = abs(i - index)
            let center = (size.width / 2 + gap + satelliteWidth / 2 + CGFloat(distance - 1) * (satelliteWidth + gap)) * (i < index ? -1 : 1)
            result[id] = CGRect(x: center - satelliteWidth / 2, y: -diameter / 2, width: satelliteWidth, height: diameter)
        }
        return result
    }
    // No thin long connector: disappear while the neck is still at least 5 pt thick.
    static func bridge(_ left: CGRect, _ right: CGRect) -> CGPath? {
        let gap = right.minX - left.maxX
        guard gap > -8, gap < bridgeCutoff, abs(left.midY - right.midY) < 12 else { return nil }
        let radius = min(left.height, right.height) / 2
        let halfNeck = min(12, radius * 0.46) * pow(max(0, 1 - max(0, gap) / bridgeCutoff), 0.7)
        guard halfNeck >= 2.5 else { return nil }
        let inset: CGFloat = 7
        let anchor = min(18, radius * 0.7)
        let x1 = left.maxX - inset, x2 = right.minX + inset
        let mid = (x1 + x2) / 2, y = (left.midY + right.midY) / 2
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x1, y: left.midY + anchor))
        path.addCurve(to: CGPoint(x: mid, y: y + halfNeck), control1: CGPoint(x: x1 + 3, y: left.midY + anchor - 5), control2: CGPoint(x: mid - 3, y: y + halfNeck))
        path.addCurve(to: CGPoint(x: x2, y: right.midY + anchor), control1: CGPoint(x: mid + 3, y: y + halfNeck), control2: CGPoint(x: x2 - 3, y: right.midY + anchor - 5))
        path.addLine(to: CGPoint(x: x2, y: right.midY - anchor))
        path.addCurve(to: CGPoint(x: mid, y: y - halfNeck), control1: CGPoint(x: x2 - 3, y: right.midY - anchor + 5), control2: CGPoint(x: mid + 3, y: y - halfNeck))
        path.addCurve(to: CGPoint(x: x1, y: left.midY - anchor), control1: CGPoint(x: mid - 3, y: y - halfNeck), control2: CGPoint(x: x1 + 3, y: left.midY - anchor + 5))
        path.closeSubpath()
        return path
    }

}

struct CodexMultitaskMotion {
    struct Pose {
        var frame: CGRect
        var opacity: Double = 1
        var capsule: Double = 0
        var contourRecoil: Double = 0
        var shellJelly: Double = 0
        var labelOpacity: Double = 1
        // Logical content layout before shared shell/content deformation.
        var contentLayoutSize: CGSize?
    }
    struct Birth {
        var donor: Int
        var delay: TimeInterval
        var side: CGFloat = 1
    }
    struct FocusHandoff {
        var previous: Int
        var current: Int
        var elapsed: TimeInterval
        var showsPrevious: Bool { elapsed < 0.12 }
        var textOpacity: CGFloat {
            let fraction = showsPrevious ? elapsed / 0.12 : (elapsed - 0.12) / 0.16
            let p = min(1, max(0, fraction)), eased = p * p * (3 - 2 * p)
            return showsPrevious ? 1 - eased : eased
        }
    }
    struct Track {
        var origin: Pose
        var target: Pose
        var velocity: [Double] = [0, 0, 0, 0, 0, 0]
        var affected: Bool
        var birth: Birth?
        var release: TimeInterval?
        var holdsMainFrame = false
    }
    private(set) var tracks: [Int: Track] = [:]
    private(set) var started: TimeInterval = 0
    private(set) var animated = false
    private var completion: CodexMultitaskCompletion?
    private var selectedID: Int?
    private var handoff: FocusHandoff?
    var settling: TimeInterval {
        let release = tracks.values.compactMap(\.release).max() ?? 0
        return release + min(1.2, max(0.65, CodexMultitaskGeometry.spring.settlingDuration))
    }
    func isAnimating(_ now: TimeInterval) -> Bool {
        if let completion { return animated && completion.isAnimating(now) }
        return animated && now - started < settling
    }
    mutating func gatherCompleted(selected: Int, started: TimeInterval, now: TimeInterval, animate: Bool) {
        let current = sample(now)
        handoff = nil
        completion = CodexMultitaskCompletion(origin: current, selected: selected, started: started)
        animated = animate
    }

    mutating func retarget(_ targets: [Int: Pose], selected: Int, now: TimeInterval, animate: Bool) {
        let old = sample(now)
        let previousMain = selectedID
        let wasCompleting = completion != nil
        completion = nil
        var updated: [Int: Track] = [:]
        let newborns = targets.keys.filter { old[$0] == nil }.sorted()
        let outgoing = animate && !wasCompleting && newborns.contains(selected)
            ? previousMain.flatMap { old[$0] != nil && targets[$0] != nil ? $0 : nil } : nil
        handoff = outgoing.map { FocusHandoff(previous: $0, current: selected, elapsed: 0) }
        let donor = old[selected] == nil ? nil : selected
        let birthRelease = old.isEmpty || newborns.isEmpty ? nil : Optional(CodexMultitaskGeometry.separationTime)
        for (id, target) in targets {
            var origin = old[id] ?? target
            if old[id] == nil {
                let previous = donor.flatMap { old[$0] }
                let x = previous.map { $0.frame.maxX - target.frame.width * 0.65 } ?? -target.frame.width * 0.12
                origin = Pose(frame: CGRect(x: x, y: -target.frame.height * 0.35, width: target.frame.width * 0.7, height: target.frame.height * 0.7), opacity: 0)
            }
            if id == selected, let outgoing { origin = old[outgoing]! }
            let velocity = tracks[id].map { velocityOf($0, now: now) } ?? [0, 0, 0, 0, 0, 0]
            let countChanged = Set(old.keys) != Set(targets.keys)
            var birth: Birth?
            if let donor, let index = newborns.firstIndex(of: id), target.frame.width <= CodexMultitaskGeometry.satelliteWidth + 1 {
                birth = Birth(donor: donor, delay: Double(index) * 0.09)
            }
            if id == outgoing {
                // The existing task becomes the left bud; its full-size body is
                // transferred to the new focused task, rather than resized twice.
                birth = Birth(donor: selected, delay: 0, side: -1)
            }
            updated[id] = Track(origin: animate ? origin : target, target: target, velocity: animate ? velocity : [0, 0, 0, 0, 0, 0], affected: origin.frame != target.frame || origin.opacity != target.opacity || (countChanged && (id == selected || id == donor)), birth: animate ? birth : nil, release: animate ? birth.map { CodexMultitaskGeometry.separationTime + $0.delay } ?? birthRelease : nil, holdsMainFrame: id == selected && origin.frame == target.frame)
        }
        tracks = updated; started = now; animated = animate; selectedID = selected
    }

    func activeHandoff(_ now: TimeInterval) -> FocusHandoff? {
        guard var handoff, isAnimating(now) else { return nil }
        handoff.elapsed = max(0, now - started)
        return handoff
    }

    func activeBirths(_ now: TimeInterval) -> [Int: Birth] {
        guard completion == nil, isAnimating(now) else { return [:] }
        return tracks.compactMapValues(\.birth)
    }
    private func vector(_ pose: Pose) -> [Double] {
        [pose.frame.midX, pose.frame.midY, pose.frame.width, pose.frame.height, pose.opacity, pose.capsule]
    }
    private func velocityOf(_ track: Track, now: TimeInterval) -> [Double] {
        guard isAnimating(now) else { return [0, 0, 0, 0, 0, 0] }
        if track.birth != nil {
            // Retarget a staged birth from its currently displayed position and velocity.
            let step = 0.001
            let first = sample(now), second = sample(now + step)
            if let id = tracks.first(where: { $0.value.birth?.donor == track.birth?.donor && $0.value.target.frame == track.target.frame })?.key,
               let a = first[id], let b = second[id] {
                return zip(vector(a), vector(b)).map { ($1 - $0) / step }
            }
        }
        let a = vector(track.origin), b = vector(track.target)
        return (0..<6).map {
            let delay = $0 == 5 ? (track.release ?? 0) : 0
            return CodexMultitaskGeometry.spring.velocity(target: b[$0] - a[$0], initialVelocity: track.velocity[$0], time: max(0, now - started - delay))
        }
    }
    func sample(_ now: TimeInterval) -> [Int: Pose] {
        if let completion {
            return completion.sample(animated ? now : completion.started + completion.duration)
        }
        guard isAnimating(now) else { return tracks.mapValues(\.target) }
        let elapsed = max(0, now - started)
        var result = tracks.mapValues { track in
            let a = vector(track.origin), b = vector(track.target)
            let value = (0..<6).map { index in
                let delay = index == 5 ? (track.release ?? 0) : 0
                return a[index] + CodexMultitaskGeometry.spring.value(target: b[index] - a[index], initialVelocity: track.velocity[index], time: max(0, elapsed - delay))
            }
            let reboundTime = max(0, elapsed - (track.release ?? 0))
            let jelly = 0.055 * sin(reboundTime / 0.34 * .pi * 2) * exp(-reboundTime * 7)
            // Keep layout fixed; the production shell gets its own spring transform.
            let amount = track.affected && !track.holdsMainFrame ? jelly : 0
            let width = max(2, value[2] * (1 + amount)), height = max(2, value[3] * (1 - amount))
            let contour = (track.holdsMainFrame && track.affected ? abs(jelly) * 2.8 : 0) + track.origin.contourRecoil * exp(-elapsed * 12)
            let shellJelly = (track.holdsMainFrame && track.affected ? 0.13 * sin(reboundTime / 0.28 * .pi * 2) * exp(-reboundTime * 5.5) : 0) + track.origin.shellJelly * exp(-elapsed * 12)
            let label = track.origin.labelOpacity + (track.target.labelOpacity - track.origin.labelOpacity) * min(1, elapsed / 0.16)
            let originLayout = track.origin.contentLayoutSize ?? track.origin.frame.size
            let contentSize = CGSize(width: max(2, value[2] + (originLayout.width - a[2]) * exp(-elapsed * 12)),
                                     height: max(2, value[3] + (originLayout.height - a[3]) * exp(-elapsed * 12)))
            return Pose(frame: CGRect(x: value[0] - width / 2, y: value[1] - height / 2, width: width, height: height), opacity: min(1, max(0, value[4])), capsule: min(1, max(0, value[5])), contourRecoil: contour, shellJelly: shellJelly, labelOpacity: label, contentLayoutSize: contentSize)
        }
        // A deliberate bud/neck/release sequence keeps the liquid bridge on screen long
        // enough to read. New siblings are slightly staggered, never shot past the neck.
        for id in tracks.keys.sorted() {
            guard let track = tracks[id], let birth = track.birth, let source = result[birth.donor] else { continue }
            let t = max(0, elapsed - birth.delay)
            func ease(_ x: Double) -> Double { let p = min(1, max(0, x)); return p * p * (3 - 2 * p) }
            let grow = ease(t / 0.18)
            let stretch = ease((t - 0.14) / 0.22)
            let released = max(0, t - CodexMultitaskGeometry.separationTime)
            let settle = CodexMultitaskGeometry.spring.value(target: 1, time: released)
            let jelly = 0.14 * sin(released / 0.28 * .pi * 2) * exp(-released * 5.5)
            let scale = 0.60 + 0.40 * grow
            let width = track.target.frame.width * scale * (1 + jelly)
            let height = track.target.frame.height * scale * (1 - jelly)
            let gap = t < 0.14 ? -20 + 14 * ease(t / 0.14) : -6 + 17 * stretch
            let edge = birth.side > 0 ? source.frame.maxX : source.frame.minX
            let attachedX = edge + birth.side * (gap + width / 2)
            let x = attachedX + (track.target.frame.midX - attachedX) * settle
            result[id] = Pose(frame: CGRect(x: x - width / 2, y: source.frame.midY - height / 2, width: width, height: height), opacity: min(track.target.opacity, ease(t / 0.07)), capsule: 1, labelOpacity: ease((t - 0.26) / 0.16), contentLayoutSize: track.target.frame.size)
        }
        return result
    }
}


import AppKit

// Terminal collection. Never aggregates partially completed tasks.
struct CodexMultitaskCompletion {
    let origin: [Int: CodexMultitaskMotion.Pose]
    let selected: Int
    let started: TimeInterval
    let order: [Int]
    let sides: [Int: CGFloat]

    init(origin: [Int: CodexMultitaskMotion.Pose], selected: Int, started: TimeInterval) {
        self.origin = origin; self.selected = selected; self.started = started
        let center = origin[selected]?.frame.midX ?? 0
        order = origin.keys.filter { $0 != selected }.sorted {
            let a = abs(origin[$0]!.frame.midX - center), b = abs(origin[$1]!.frame.midX - center)
            return abs(a - b) < 0.01 ? $0 < $1 : a < b
        }
        sides = origin.mapValues { $0.frame.midX < center ? -1 : 1 }
    }
    var duration: TimeInterval { CodexMultitaskCompletionTiming.duration(taskCount: origin.count) }
    func isAnimating(_ now: TimeInterval) -> Bool { now - started < duration }
    func sample(_ now: TimeInterval) -> [Int: CodexMultitaskMotion.Pose] {
        guard let main = origin[selected] else { return origin }
        let elapsed = max(0, now - started)
        func ease(_ value: Double) -> Double { let p = max(0, min(1, value)); return p * p * (3 - 2 * p) }
        var result = origin
        // Every satellite uses one shared clock: no per-task delay or extra wait.
        let t = elapsed - CodexMultitaskCompletionTiming.lead
        for id in order {
            guard var pose = origin[id] else { continue }
            let side = sides[id]!
            let approach = ease(t / 0.16)
            let neck = ease((t - 0.16) / 0.16)
            let absorb = ease((t - 0.32) / 0.14)
            let edge = side > 0 ? main.frame.maxX : main.frame.minX
            let startCenter = pose.frame.midX
            let touchCenter = edge + side * (pose.frame.width / 2 + 2)
            let neckCenter = edge + side * (pose.frame.width / 2 - 6)
            let endCenter = edge - side * 18
            let x = startCenter + (touchCenter - startCenter) * approach
                + (neckCenter - touchCenter) * neck + (endCenter - neckCenter) * absorb
            let pulse = t > 0.18 ? 0.08 * sin((t - 0.18) / 0.28 * .pi * 2) * exp(-(t - 0.18) * 6) : 0
            let scale = 1 - 0.82 * absorb
            let width = pose.frame.width * scale * (1 + pulse), height = pose.frame.height * scale * (1 - pulse)
            pose.contentLayoutSize = pose.contentLayoutSize ?? pose.frame.size
            pose.frame = CGRect(x: x - width / 2, y: main.frame.midY - height / 2, width: width, height: height)
            pose.opacity *= 1 - absorb
            pose.labelOpacity *= 1 - ease((t - 0.29) / 0.12)
            result[id] = pose
        }
        // One shared impact; more tasks must not multiply the main island's rebound.
        let recoilTime = t - 0.34
        let mainJelly = recoilTime > 0 ? 0.11 * sin(recoilTime / 0.28 * .pi * 2) * exp(-recoilTime * 5.5) : 0
        result[selected]?.shellJelly = elapsed >= duration ? 0 : max(-0.12, min(0.12, mainJelly))
        result[selected]?.capsule = 1
        return result
    }
}

// Aggregate data only. ActivityIslandContentView owns every font, text column,
// quota value and compact ring for both single-task and multitask main islands.
struct CodexMultitaskCompletionSummary {
    let count: Int
    let english: Bool
    let totalTokens: Int64?
    let remainingPercent: Int?
    private var copy: AppCopy { AppCopy(language: english ? .english : .simplifiedChinese) }
    var title: String { copy.text("已完成全部任务", "All tasks completed") }
    var compactTitle: String { Self.compactTitle(count: count, english: english) }
    var tokens: String {
        let value = totalTokens.map(CodexActivityTokenUsageFormatter.string) ?? "—"
        return copy.text("总计 \(value) tokens", "Total \(value) tokens")
    }
    private static func compactTitle(count: Int, english: Bool) -> String {
        AppCopy(language: english ? .english : .simplifiedChinese)
            .text("全部完成 · \(count) 项任务", "All done · \(count) tasks")
    }
    static func compactWidth(count: Int, english: Bool) -> CGFloat {
        CodexActivityIslandProgressBarGeometry.compactCompletionSurfaceWidth(
            for: compactTitle(count: count, english: english))
    }
    func applying(to state: CodexActivityRenderState) -> CodexActivityRenderState {
        let quota = remainingPercent.map { "\(min(100, max(0, $0)))%" } ?? "—"
        return CodexActivityRenderState(
            taskIdentity: state.taskIdentity, visualState: state.visualState,
            approximateProgressFraction: state.approximateProgressFraction,
            windowTitle: state.windowTitle, statusTitle: compactTitle,
            operation: state.operation, tokenUsageTitle: state.tokenUsageTitle,
            completionReceiptStatus: title, completionReceiptDetail: tokens,
            completionQuotaRemainingPercent: remainingPercent,
            isConfirmationReminderActive: state.isConfirmationReminderActive,
            accessibilityLabel: "\(compactTitle) · \(tokens) · \(copy.text("额度剩余", "Quota remaining")) \(quota)")
    }
}


import AppKit

// Presentation is ALWAYS the existing single-island timeline, including its logical
// layout and text sampling. CodexMultitaskMotion only arranges the extra task bodies.
struct CodexMultitaskPresentation {
    struct Sample {
        var shell: ActivityIslandMotion.Pose
        var layout: ActivityIslandMotion.Pose
        var text: ActivityIslandMotion.Pose

        func surface(in canvas: CGRect) -> CGRect {
            let inset = CodexActivityIslandGeometry.panelInset
            return shell.frame(in: canvas, inset: inset).insetBy(
                dx: inset * shell.width / layout.width,
                dy: inset * shell.height / layout.height)
        }
    }
    private(set) var motion: ActivityIslandMotion?

    mutating func update(visible: Bool, compact: Bool, at time: TimeInterval, animate: Bool, compactWidth: CGFloat? = nil) {
        let mode: CodexActivityIslandPresentation = compact ? .compact : .expanded
        var size = CodexActivityIslandGeometry.panelSize(presentation: mode, state: .working)
        let inset = CodexActivityIslandGeometry.panelInset
        if compact, let compactWidth { size.width = compactWidth + inset * 2 }
        let target = visible ? ActivityIslandMotion.Pose(width: size.width, height: size.height, visibility: 1)
            : ActivityIslandMotion.hiddenPose(inset: inset)
        if motion == nil {
            // Use the original single-island reveal from behind the menu bar.
            motion = ActivityIslandMotion(pose: ActivityIslandMotion.hiddenPose(inset: inset))
        }
        if motion?.target != target || !animate {
            if visible {
                motion?.present(target, at: time, resizeDuration: mode.transitionDuration,
                                elasticResize: mode == .expanded, reduceMotion: !animate)
            } else {
                var compactSize = CodexActivityIslandGeometry.panelSize(presentation: .compact, state: .completed)
                if let compactWidth { compactSize.width = compactWidth + inset * 2 }
                motion?.hide(compact: .init(width: compactSize.width, height: compactSize.height, visibility: 1),
                             inset: inset, at: time, animated: animate)
            }
        }
    }

    func sample(at time: TimeInterval) -> Sample? {
        guard let motion else { return nil }
        return Sample(shell: motion.sample(at: time), layout: motion.sampleLayout(at: time), text: motion.sampleText(at: time))
    }
    func isAnimating(at time: TimeInterval) -> Bool { motion?.isAnimating(at: time) == true }
    mutating func settle() {
        if let target = motion?.target { motion = ActivityIslandMotion(pose: target) }
    }
}
