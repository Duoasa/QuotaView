import Foundation
import CoreGraphics

func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.000001 }
let expanded = ConsoleMotion.Pose(width: 462, height: 128, visibility: 1)
let compact = ConsoleMotion.Pose(width: 310, height: 112, visibility: 1)
let bounds = CGRect(x: 0, y: 0, width: 640, height: 210)
var motion = ConsoleMotion(pose: expanded)

// Contraction accelerates gently and slows to rest without any rebound.
for (start, end, duration) in [(expanded, compact, 0.28)] {
    var resize = ConsoleMotion(pose: start)
    resize.retarget(end, at: 0, duration: duration)
    let values = (0...100).map { resize.sample(at: Double($0) / 100 * duration) }
    let direction: CGFloat = end.width > start.width ? 1 : -1
    for (previous, current) in zip(values, values.dropFirst()) {
        assert((current.width - previous.width) * direction >= -0.000001)
        assert((current.height - previous.height) * direction >= -0.000001)
        assert(current.width >= min(start.width, end.width) && current.width <= max(start.width, end.width))
        assert(current.height >= min(start.height, end.height) && current.height <= max(start.height, end.height))
    }
    let half = resize.sample(at: duration / 2)
    assert(abs(half.width - start.width) > abs(end.width - start.width) / 2)
    let steps = zip(values, values.dropFirst()).map { abs($1.width - $0.width) }
    assert(steps[0] < steps[1] && steps[1] < steps[10])
    assert(steps[90] < steps[75] && steps[99] < steps[98])
    assert(steps[0] < abs(end.width - start.width) * 0.001)
    assert(steps[99] < abs(end.width - start.width) * 0.001)
    assert(values.last == end)
}

// A rapid reversal starts at the current displayed pose instead of either endpoint.
motion.retarget(compact, at: 0, duration: 0.28)
let halfway = motion.sample(at: 0.14)
assert(halfway.width < expanded.width && halfway.width > compact.width)
assert(near(halfway.frame(in: bounds, inset: 30).maxY, expanded.frame(in: bounds, inset: 30).maxY))
motion.present(expanded, at: 0.14, resizeDuration: ConsoleMotion.revealDuration,
               elasticResize: true, reduceMotion: false)
assert(motion.sample(at: 0.14) == halfway)
assert(motion.sample(at: 1) == expanded && !motion.isAnimating(at: 1))

// Compact expansion reuses the reveal spring while retaining its visible anchor and opacity.
motion = ConsoleMotion(pose: compact)
motion.present(expanded, at: 0, resizeDuration: ConsoleMotion.revealDuration,
               elasticResize: true, reduceMotion: false)
let expansion = (0...820).map { motion.sample(at: Double($0) / 1000) }
assert(expansion.first == compact && expansion.last == expanded)
assert(expansion.contains { $0.width > expanded.width })
assert(expansion.contains { $0.height > expanded.height })
assert(expansion.allSatisfy { $0.topOffset == 0 && $0.visibility == 1 })
assert(expansion.allSatisfy { $0.width < expanded.width * 1.12 && $0.height < expanded.height * 1.15 })

// Terminal rebound is a shared visual transform over stable logical geometry.
for start in [compact, ConsoleMotion.hiddenPose(inset: 30)] {
    var reveal = ConsoleMotion(pose: start)
    reveal.present(expanded, at: 0, resizeDuration: ConsoleMotion.revealDuration,
                   elasticResize: true, reduceMotion: false)
    for step in 28...82 {
        let time = Double(step) / 100
        let shell = reveal.sample(at: time)
        let layout = reveal.sampleLayout(at: time)
        let text = reveal.sampleText(at: time)
        assert(layout.width == expanded.width && layout.height == expanded.height)
        assert(text.width == expanded.width && text.height == expanded.height)
        assert((0...1).contains(text.visibility))
        if time >= 0.5 { assert(text.visibility == 1) }
        let shellFrame = shell.frame(in: bounds, inset: 30)
        let localText = text.frame(relativeTo: layout, inset: 30)
        let scaleX = shell.width / layout.width
        let scaleY = shell.height / layout.height
        assert(near(localText.width * scaleX, shellFrame.width))
        assert(near(localText.height * scaleY, shellFrame.height))
    }
}

// Emergence starts as a clipped seed above the menu bar and grows with a bounded jelly rebound.
let seed = ConsoleMotion.hiddenPose(inset: 30)
motion = ConsoleMotion(pose: seed)
motion.show(expanded: expanded, at: 1, duration: ConsoleMotion.revealDuration)
assert(motion.sample(at: 1) == seed)
let seedFrame = seed.frame(in: bounds, inset: 30)
assert(seedFrame.minY + 30 >= bounds.maxY) // Visible surface is still behind the bar.
let samples = (0...820).map { motion.sample(at: 1 + Double($0) / 1000) }
assert(samples.contains { $0.width > expanded.width })
assert(samples.contains { $0.height > expanded.height })
assert(samples.allSatisfy { $0.width <= expanded.width * 1.12 && $0.height <= expanded.height * 1.15 })
assert(samples.allSatisfy { $0.width > 60 && $0.height > 60 && (0...1).contains($0.visibility) })
let early = motion.sample(at: 1 + ConsoleMotion.revealDuration * 0.1)
let middle = motion.sample(at: 1 + ConsoleMotion.revealDuration * 0.2)
assert(middle.width - early.width > early.width - seed.width) // Accelerate before braking.
assert(motion.sample(at: 1.9) == expanded)
assert(near(expanded.frame(in: bounds, inset: 30).maxY - 30, bounds.maxY - 16))
// Same final panel origin as production's visibleFrame - size - 6 + (30 - 10).
assert(near(expanded.frame(in: bounds, inset: 30).minY, bounds.maxY - expanded.height - 6 + 20))

// Hide must reach the complete compact state before opacity starts decreasing.
motion.hide(compact: compact, inset: 30, at: 2, animated: true)
let shrinking = motion.sample(at: 2.14)
assert(shrinking.width < expanded.width && shrinking.width > compact.width)
assert(shrinking.visibility == 1)
let compactPhase = motion.sample(at: 2.28)
assert(near(compactPhase.width, compact.width) && near(compactPhase.height, compact.height))
assert(near(compactPhase.visibility, 1))
let fading = motion.sample(at: 2.42)
assert(fading.width < compact.width && fading.visibility > 0 && fading.visibility < 1)
assert(motion.sample(at: 2.6) == ConsoleMotion.hiddenPose(inset: 30))

// Reopening during hide cancels both hide stages and springs continuously from the current pose.
motion.hide(compact: compact, inset: 30, at: 3, animated: false)
motion.show(expanded: expanded, at: 3, duration: 0)
motion.hide(compact: compact, inset: 30, at: 4, animated: true)
let partialPose = motion.sample(at: 4.42)
motion.show(expanded: expanded, at: 4.42, duration: ConsoleMotion.revealDuration)
assert(motion.sample(at: 4.42) == partialPose)
assert(motion.sample(at: 5.3) == expanded)

// Hiding an already compact island skips the redundant size stage.
motion = ConsoleMotion(pose: compact)
motion.hide(compact: compact, inset: 30, at: 6, animated: true)
assert(motion.sample(at: 6.14).visibility < 1)
assert(motion.sample(at: 6.3) == ConsoleMotion.hiddenPose(inset: 30))
for step in 0...100 {
    let frame = motion.sample(at: 6 + Double(step) / 100).frame(in: bounds, inset: 30)
    assert(frame.width > 60 && frame.height > 60)
    assert(near(frame.midX, bounds.midX))
}

// Reduced motion settles without queued compact or hide stages.
motion.show(expanded: expanded, at: 7, duration: 0)
assert(motion.sample(at: 7) == expanded && !motion.isAnimating(at: 7))
motion.hide(compact: compact, inset: 30, at: 8, animated: false)
assert(motion.sample(at: 8).visibility == 0 && !motion.isAnimating(at: 8))
print("Console motion checks passed: gentle resize start/stop, bounded nonlinear resize, menu-bar emergence, jelly rebound, two-stage hide, interruption, compact hide, reduced motion.")
