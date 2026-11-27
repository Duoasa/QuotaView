import Foundation
import CoreGraphics

// Shared island presentation timing. Rendered effects retain their own continuous clocks.
struct ActivityIslandMotion {
    enum Curve { case easeInOut, resize }

    struct Pose: Equatable {
        var width: CGFloat
        var height: CGFloat
        var visibility: CGFloat
        var topOffset: CGFloat = 0

        func frame(in bounds: CGRect, inset: CGFloat) -> CGRect {
            // The canvas ends at the menu bar's bottom edge; clip the emerging seed above it.
            // Match production: 6 pt placement gap + 10 pt original panel inset.
            let top = bounds.maxY + inset - 16 + topOffset
            return CGRect(x: bounds.midX - width / 2, y: top - height, width: width, height: height)
        }

        func frame(relativeTo shell: Pose, inset: CGFloat) -> CGRect {
            let shellFrame = shell.frame(in: .zero, inset: inset)
            return frame(in: .zero, inset: inset).offsetBy(dx: -shellFrame.minX, dy: -shellFrame.minY)
        }
    }

    private var origin: Pose
    private var layoutOrigin: Pose
    private var textOrigin: Pose
    private(set) var target: Pose
    private var startedAt: TimeInterval = 0
    private var duration: TimeInterval = 0
    private var waypoint: Pose?
    private var waypointDuration: TimeInterval = 0
    private var springReveal = false
    private var curve: Curve = .resize
    static let revealDuration: TimeInterval = 0.82
    static let textFadeOutDuration: TimeInterval = 0.08
    static let textRevealDelay: TimeInterval = 0.12
    static let textFadeInDuration: TimeInterval = 0.14

    init(pose: Pose) { origin = pose; layoutOrigin = pose; textOrigin = pose; target = pose }

    // Content refreshes may arrive every frame. Only a changed presentation starts a timeline.
    mutating func present(_ pose: Pose, at time: TimeInterval, resizeDuration: TimeInterval,
                          elasticResize: Bool = false, reduceMotion: Bool) {
        if reduceMotion {
            retarget(pose, at: time, duration: 0)
        } else if target.visibility == 0 {
            show(expanded: pose, at: time, duration: Self.revealDuration)
        } else if target != pose {
            if elasticResize {
                show(expanded: pose, at: time, duration: resizeDuration)
            } else {
                retarget(pose, at: time, duration: resizeDuration)
            }
        }
    }

    mutating func retarget(_ target: Pose, at time: TimeInterval, duration: TimeInterval, curve: Curve = .resize) {
        let currentText = sampleText(at: time)
        let currentLayout = sampleLayout(at: time)
        origin = sample(at: time)
        layoutOrigin = currentLayout
        textOrigin = currentText
        self.target = target
        startedAt = time
        self.duration = max(0, duration)
        waypoint = nil
        waypointDuration = 0
        springReveal = false
        self.curve = curve
    }

    static func hiddenPose(inset: CGFloat) -> Pose {
        Pose(width: 2 * inset + 84, height: 2 * inset + 8, visibility: 0, topOffset: 30)
    }

    mutating func show(expanded: Pose, at time: TimeInterval, duration: TimeInterval) {
        retarget(expanded, at: time, duration: duration)
        springReveal = duration > 0
    }

    mutating func hide(compact: Pose, inset: CGFloat, at time: TimeInterval, animated: Bool) {
        // Repeated hidden snapshots must not restart the exit animation.
        guard target.visibility > 0 else {
            if !animated { retarget(Self.hiddenPose(inset: inset), at: time, duration: 0) }
            return
        }
        let current = sample(at: time)
        retarget(Self.hiddenPose(inset: inset), at: time, duration: animated ? 0.28 : 0, curve: .easeInOut)
        guard animated else { return }
        if current.width > compact.width || current.height > compact.height {
            // An interrupted entrance may still be smaller than compact on one axis.
            // Dismissal must not enlarge that axis on its way to the compact envelope.
            waypoint = Pose(width: min(compact.width, current.width),
                            height: min(compact.height, current.height), visibility: current.visibility)
            waypointDuration = 0.28
            duration += waypointDuration
        }
    }

    func isAnimating(at time: TimeInterval) -> Bool {
        let end = target.visibility > 0 ? max(duration, textFadeInStart + Self.textFadeInDuration) : duration
        return (origin != target || layoutOrigin != target || textOrigin != target) && duration > 0 && time < startedAt + end
    }

    private var textFadeInStart: TimeInterval {
        springReveal ? min(Self.textRevealDelay, duration) : duration
    }

    func sampleText(at time: TimeInterval) -> Pose {
        guard duration > 0 else { return target }
        let elapsed = max(0, time - startedAt)
        if textOrigin.visibility > 0 && elapsed < Self.textFadeOutDuration {
            // Fade the outgoing logical layout before swapping it at zero opacity.
            var text = textOrigin
            text.visibility *= 1 - fade(elapsed / Self.textFadeOutDuration)
            return text
        }
        // Swap layouts while invisible, then let the shared visual transform carry the new content.
        var text = target
        text.visibility *= fade((elapsed - textFadeInStart) / Self.textFadeInDuration)
        return text
    }

    private func fade(_ progress: TimeInterval) -> CGFloat {
        let t = CGFloat(min(max(progress, 0), 1))
        return t * t * (3 - 2 * t)
    }

    func sample(at time: TimeInterval) -> Pose {
        sample(at: time, origin: origin, allowsOvershoot: true)
    }

    func sampleLayout(at time: TimeInterval) -> Pose {
        sample(at: time, origin: layoutOrigin, allowsOvershoot: false)
    }

    private func sample(at time: TimeInterval, origin: Pose, allowsOvershoot: Bool) -> Pose {
        guard duration > 0 else { return target }
        if springReveal {
            let t = min(max((time - startedAt) / duration, 0), 1)
            if t >= 1 { return target }
            // Distinct damped responses stretch vertically first, then widen and settle.
            // Start with zero velocity and preserve the current pose when interrupted.
            let width = spring(t, decay: 8, frequency: 10.5, allowsOvershoot: allowsOvershoot)
            let height = spring(t, decay: 7, frequency: 15, allowsOvershoot: allowsOvershoot)
            let entrance = CGFloat(min(t / 0.18, 1))
            let opacity = 1 - pow(1 - entrance, 3)
            return Pose(width: origin.width + (target.width - origin.width) * width,
                        height: origin.height + (target.height - origin.height) * height,
                        visibility: origin.visibility + (target.visibility - origin.visibility) * opacity,
                        topOffset: origin.topOffset + (target.topOffset - origin.topOffset) * width)
        }
        if let waypoint {
            if time < startedAt + waypointDuration {
                return interpolate(origin, waypoint, elapsed: time - startedAt, duration: waypointDuration, curve: curve)
            }
            return interpolate(waypoint, target, elapsed: time - startedAt - waypointDuration,
                               duration: duration - waypointDuration, curve: curve)
        }
        return interpolate(origin, target, elapsed: time - startedAt, duration: duration, curve: curve)
    }

    private func spring(_ time: Double, decay: Double, frequency: Double, allowsOvershoot: Bool) -> CGFloat {
        // Logical geometry stops at the first arrival. The remaining spring response is
        // a shared frame-to-bounds transform of the shell, text, icons, and effects.
        let firstArrival = (Double.pi / 2 + atan(decay / frequency)) / frequency
        if !allowsOvershoot && time >= firstArrival { return 1 }
        return CGFloat(1 - exp(-decay * time) * (cos(frequency * time) + decay / frequency * sin(frequency * time)))
    }

    private func interpolate(_ origin: Pose, _ target: Pose, elapsed: TimeInterval, duration: TimeInterval, curve: Curve) -> Pose {
        let t = CGFloat(min(max(elapsed / duration, 0), 1))
        // Resize starts and ends at rest, with a short acceleration and a longer slowdown.
        // Its derivative 12*t*(1-t)^2 stays nonnegative: only show() can overshoot.
        let fraction = curve == .resize ? t * t * (6 - 8 * t + 3 * t * t) : t * t * (3 - 2 * t)
        return Pose(width: origin.width + (target.width - origin.width) * fraction,
                    height: origin.height + (target.height - origin.height) * fraction,
                    visibility: origin.visibility + (target.visibility - origin.visibility) * fraction,
                    topOffset: origin.topOffset + (target.topOffset - origin.topOffset) * fraction)
    }
}
