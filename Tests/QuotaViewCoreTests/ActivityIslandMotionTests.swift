import XCTest
import CoreGraphics
@testable import QuotaView

final class ActivityIslandMotionTests: XCTestCase {
    private let expanded = ActivityIslandMotion.Pose(width: 462, height: 128, visibility: 1)
    private let compact = ActivityIslandMotion.Pose(width: 310, height: 112, visibility: 1)
    private let inset: CGFloat = 30

    func testSpringEmergesBehindMenuBarAndSettlesAtOriginalPosition() {
        let hidden = ActivityIslandMotion.hiddenPose(inset: inset)
        let bounds = CGRect(x: 0, y: 0, width: 640, height: 210)
        var motion = ActivityIslandMotion(pose: hidden)
        motion.present(expanded, at: 0, resizeDuration: 0.3, reduceMotion: false)
        XCTAssertGreaterThanOrEqual(hidden.frame(in: bounds, inset: inset).minY + inset, bounds.maxY)
        let frames = (0...820).map { motion.sample(at: Double($0) / 1000) }
        XCTAssertTrue(frames.contains { $0.width > expanded.width })
        XCTAssertTrue(frames.contains { $0.height > expanded.height })
        XCTAssertTrue(frames.allSatisfy { $0.width < expanded.width * 1.12 && $0.height < expanded.height * 1.15 })
        XCTAssertTrue(frames.allSatisfy { $0.width > inset * 2 && $0.height > inset * 2 && (0...1).contains($0.visibility) })
        XCTAssertEqual(motion.sample(at: 1), expanded)
        XCTAssertEqual(expanded.frame(in: bounds, inset: inset).minY, bounds.maxY - expanded.height - 6 + 20)
    }

    func testNonelasticResizeStartsGentlyAndRemainsMonotonicWithoutOvershoot() {
        for (start, end) in [(expanded, compact), (compact, expanded)] {
            var motion = ActivityIslandMotion(pose: start)
            motion.present(end, at: 0, resizeDuration: 0.3, reduceMotion: false)
            let frames = (0...100).map { motion.sample(at: Double($0) * 0.003) }
            let sign: CGFloat = end.width > start.width ? 1 : -1
            for (previous, current) in zip(frames, frames.dropFirst()) {
                XCTAssertGreaterThanOrEqual((current.width - previous.width) * sign, -0.000001)
                XCTAssertGreaterThanOrEqual((current.height - previous.height) * sign, -0.000001)
                XCTAssertTrue((min(start.width, end.width)...max(start.width, end.width)).contains(current.width))
            }
            let middle = motion.sample(at: 0.15)
            XCTAssertGreaterThan(abs(middle.width - start.width), abs(end.width - start.width) / 2)
            // Equal frame intervals accelerate gently from rest, then slow to a stop.
            let steps = zip(frames, frames.dropFirst()).map { abs($1.width - $0.width) }
            XCTAssertLessThan(steps[0], steps[1])
            XCTAssertLessThan(steps[1], steps[10])
            XCTAssertLessThan(steps[90], steps[75])
            XCTAssertLessThan(steps[99], steps[98])
            let distance = abs(end.width - start.width)
            XCTAssertLessThan(steps[0], distance * 0.001)
            XCTAssertLessThan(steps[99], distance * 0.001)
            motion.present(start, at: 0.15, resizeDuration: 0.3, reduceMotion: false)
            XCTAssertEqual(motion.sample(at: 0.15), middle)
            XCTAssertEqual(motion.sample(at: 0.5), start)
        }
    }

    func testCompactExpansionUsesRevealSpringWithoutMovingAnchorOrFading() {
        var motion = ActivityIslandMotion(pose: compact)
        let duration = CodexActivityIslandPresentation.expanded.transitionDuration
        motion.present(expanded, at: 0, resizeDuration: duration, elasticResize: true, reduceMotion: false)
        let frames = (0...820).map { motion.sample(at: Double($0) / 1000) }
        XCTAssertEqual(frames.first, compact)
        XCTAssertTrue(frames.contains { $0.width > expanded.width })
        XCTAssertTrue(frames.contains { $0.height > expanded.height })
        XCTAssertTrue(frames.allSatisfy { $0.topOffset == 0 && $0.visibility == 1 })
        XCTAssertTrue(frames.allSatisfy { $0.width < expanded.width * 1.12 && $0.height < expanded.height * 1.15 })
        XCTAssertLessThan(frames[10].width - compact.width, frames[20].width - frames[10].width)
        XCTAssertEqual(motion.sample(at: duration), expanded)
        XCTAssertFalse(motion.isAnimating(at: duration))
    }

    func testElasticExpansionSurvivesRefreshAndCanReverseOrReduceMotion() {
        var motion = ActivityIslandMotion(pose: compact)
        let duration = CodexActivityIslandPresentation.expanded.transitionDuration
        motion.present(expanded, at: 0, resizeDuration: duration, elasticResize: true, reduceMotion: false)
        let reference = motion
        for time in [0.05, 0.1, 0.15] {
            motion.present(expanded, at: time, resizeDuration: duration, elasticResize: true, reduceMotion: false)
            XCTAssertEqual(motion.sample(at: time), reference.sample(at: time))
        }
        let current = motion.sample(at: 0.2)
        motion.present(compact, at: 0.2, resizeDuration: 0.28, reduceMotion: false)
        XCTAssertEqual(motion.sample(at: 0.2), current)
        let shrinking = (0...100).map { motion.sample(at: 0.2 + Double($0) * 0.0028) }
        for (previous, next) in zip(shrinking, shrinking.dropFirst()) {
            XCTAssertLessThanOrEqual(next.width, previous.width)
            XCTAssertGreaterThanOrEqual(next.width, compact.width)
        }
        XCTAssertEqual(motion.sample(at: 0.5), compact)
        motion.present(expanded, at: 1, resizeDuration: duration, elasticResize: true, reduceMotion: false)
        motion.present(expanded, at: 1.1, resizeDuration: duration, elasticResize: true, reduceMotion: true)
        XCTAssertEqual(motion.sample(at: 1.1), expanded)
        XCTAssertFalse(motion.isAnimating(at: 1.1))
    }

    func testRepeatedRealStateRefreshDoesNotRestartEntrance() {
        var motion = ActivityIslandMotion(pose: ActivityIslandMotion.hiddenPose(inset: inset))
        motion.present(expanded, at: 0, resizeDuration: 0.3, reduceMotion: false)
        let reference = motion
        for index in 1...100 {
            let time = Double(index) * 0.01
            motion.present(expanded, at: time, resizeDuration: 0.3, reduceMotion: false)
            XCTAssertEqual(motion.sample(at: time), reference.sample(at: time))
        }
        XCTAssertFalse(motion.isAnimating(at: 1))
        XCTAssertEqual(motion.sample(at: 1), expanded)
    }

    func testLogicalLayoutStopsAtFirstArrivalWhileSharedVisualGeometryRebounds() {
        for start in [ActivityIslandMotion.hiddenPose(inset: inset), compact] {
            var motion = ActivityIslandMotion(pose: start)
            motion.present(expanded, at: 0, resizeDuration: ActivityIslandMotion.revealDuration,
                           elasticResize: true, reduceMotion: false)
            let textFrames = (0...280).map { motion.sampleText(at: Double($0) / 1000) }
            for (previous, current) in zip(textFrames, textFrames.dropFirst()) {
                XCTAssertGreaterThanOrEqual(current.width, previous.width - 0.000001)
                XCTAssertGreaterThanOrEqual(current.height, previous.height - 0.000001)
                XCTAssertLessThanOrEqual(current.width, expanded.width)
                XCTAssertLessThanOrEqual(current.height, expanded.height)
            }
            XCTAssertNotEqual(motion.sample(at: 0.35), motion.sample(at: 0.45))
            for step in 28...82 {
                let time = Double(step) / 100
                let shell = motion.sample(at: time)
                let text = motion.sampleText(at: time)
                XCTAssertEqual(text.width, expanded.width)
                XCTAssertEqual(text.height, expanded.height)
                XCTAssertTrue((0...1).contains(text.visibility))
                if time >= 0.5 { XCTAssertEqual(text.visibility, 1) }
                let layout = motion.sampleLayout(at: time)
                XCTAssertEqual(layout, expanded)
                XCTAssertEqual(text.frame(relativeTo: layout, inset: inset).origin, .zero)
                // Layout is stable even when the common frame/bounds scale is not one.
                if time == 0.35 {
                    XCTAssertGreaterThan(shell.width / layout.width, 1)
                    XCTAssertNotEqual(shell.height / layout.height, 1)
                }
            }
        }
    }

    func testTextLayoutChangesOnlyWhileInvisibleAndTimerIncludesIncomingFade() {
        for (start, end, elastic) in [(expanded, compact, false), (compact, expanded, true)] {
            var motion = ActivityIslandMotion(pose: start)
            let duration = elastic ? ActivityIslandMotion.revealDuration : 0.28
            motion.present(end, at: 0, resizeDuration: duration, elasticResize: elastic, reduceMotion: false)
            var previous = motion.sampleText(at: 0)
            for step in 1...1000 {
                let time = Double(step) / 1000
                let current = motion.sampleText(at: time)
                if current.width != previous.width || current.height != previous.height {
                    XCTAssertLessThan(previous.visibility, 0.001)
                    XCTAssertEqual(current.visibility, 0)
                }
                XCTAssertTrue((0...1).contains(current.visibility))
                previous = current
            }
            if !elastic {
                XCTAssertEqual(motion.sample(at: 0.3), compact)
                XCTAssertLessThan(motion.sampleText(at: 0.3).visibility, 1)
                XCTAssertTrue(motion.isAnimating(at: 0.3), "Do not stop the timer at the shell endpoint")
            }
            XCTAssertEqual(motion.sampleText(at: 1), end)
            XCTAssertFalse(motion.isAnimating(at: 1))
        }
    }

    func testRapidCommandsKeepVisiblePosesContinuousAndEventuallyStop() {
        let hidden = ActivityIslandMotion.hiddenPose(inset: inset)
        let size = CodexActivityIslandGeometry.panelSize(presentation: .compact, state: .working)
        let actualCompact = ActivityIslandMotion.Pose(width: size.width, height: size.height, visibility: 1)
        var motion = ActivityIslandMotion(pose: hidden)
        // Deterministic irregular timing crosses fade, arrival, overshoot and hide boundaries.
        var time: Double = 30 * 24 * 3600
        for index in 0..<1000 {
            time += [0.001, 0.017, 0.043, 0.079, 0.121, 0.279, 0.419, 0.821][index % 8]
            let before = [motion.sample(at: time), motion.sampleLayout(at: time), motion.sampleText(at: time)]
            switch index % 5 {
            case 0, 2:
                motion.present(expanded, at: time, resizeDuration: 0.82, elasticResize: true, reduceMotion: false)
            case 1:
                motion.present(actualCompact, at: time, resizeDuration: 0.28, reduceMotion: false)
            default:
                motion.hide(compact: actualCompact, inset: inset, at: time, animated: true)
            }
            let after = [motion.sample(at: time), motion.sampleLayout(at: time), motion.sampleText(at: time)]
            for (old, new) in zip(before, after) where old.visibility > 0 {
                XCTAssertEqual(old.width, new.width, accuracy: 0.000001)
                XCTAssertEqual(old.height, new.height, accuracy: 0.000001)
                XCTAssertEqual(old.topOffset, new.topOffset, accuracy: 0.000001)
                XCTAssertEqual(old.visibility, new.visibility, accuracy: 0.000001)
            }
            for offset in [0.0, 0.001, 0.08, 0.14, 0.28, 0.56, 0.82, 1] {
                for pose in [motion.sample(at: time + offset), motion.sampleLayout(at: time + offset),
                             motion.sampleText(at: time + offset)] {
                    XCTAssertTrue(pose.width.isFinite && pose.height.isFinite && pose.topOffset.isFinite)
                    XCTAssertGreaterThan(pose.width, 2 * inset)
                    XCTAssertGreaterThan(pose.height, 2 * inset)
                    XCTAssertTrue((0...1).contains(pose.visibility))
                }
            }
            XCTAssertFalse(motion.isAnimating(at: time + 1))
        }
        motion.hide(compact: actualCompact, inset: inset, at: time + 1, animated: false)
        XCTAssertEqual(motion.sample(at: time + 1), hidden)
        XCTAssertEqual(motion.sampleText(at: time + 1), hidden)
        XCTAssertFalse(motion.isAnimating(at: time + 1))
    }

    func testSleepingPastAnimationEndSettlesAtLargeSystemUptime() {
        let start: Double = 365 * 24 * 3600
        var motion = ActivityIslandMotion(pose: ActivityIslandMotion.hiddenPose(inset: inset))
        motion.present(expanded, at: start, resizeDuration: 0.82, elasticResize: true, reduceMotion: false)
        XCTAssertNotEqual(motion.sample(at: start + 0.15), motion.sample(at: start + 0.15 + 1 / 60))
        XCTAssertEqual(motion.sample(at: start + 3600), expanded)
        XCTAssertEqual(motion.sampleLayout(at: start + 3600), expanded)
        XCTAssertEqual(motion.sampleText(at: start + 3600), expanded)
        XCTAssertFalse(motion.isAnimating(at: start + 3600))
    }

    func testDismissalDuringEntranceNeverGrowsEitherDimension() {
        let large = CodexActivityIslandGeometry.panelSize(presentation: .expanded, state: .working)
        let small = CodexActivityIslandGeometry.panelSize(presentation: .compact, state: .working)
        let destination = ActivityIslandMotion.Pose(width: large.width, height: large.height, visibility: 1)
        let waypoint = ActivityIslandMotion.Pose(width: small.width, height: small.height, visibility: 1)
        let hidden = ActivityIslandMotion.hiddenPose(inset: inset)
        var entrance = ActivityIslandMotion(pose: hidden)
        entrance.present(destination, at: 0, resizeDuration: 0.82, elasticResize: true, reduceMotion: false)
        for millisecond in stride(from: 0, through: 820, by: 4) {
            let time = Double(millisecond) / 1000
            var dismissed = entrance
            var previous = entrance.sample(at: time)
            dismissed.hide(compact: waypoint, inset: inset, at: time, animated: true)
            XCTAssertEqual(dismissed.sample(at: time), previous)
            for step in 1...57 {
                let current = dismissed.sample(at: time + Double(step) / 100)
                XCTAssertLessThanOrEqual(current.width, previous.width + 0.000001, "hide at \(time)")
                XCTAssertLessThanOrEqual(current.height, previous.height + 0.000001, "hide at \(time)")
                XCTAssertLessThanOrEqual(current.visibility, previous.visibility + 0.000001)
                previous = current
            }
            XCTAssertEqual(dismissed.sample(at: time + 1), hidden)
            XCTAssertFalse(dismissed.isAnimating(at: time + 1))
        }
    }

    func testTextAndShellRemainContinuousWhenSpringIsInterrupted() {
        var motion = ActivityIslandMotion(pose: compact)
        motion.present(expanded, at: 0, resizeDuration: ActivityIslandMotion.revealDuration,
                       elasticResize: true, reduceMotion: false)
        let shell = motion.sample(at: 0.04)
        let text = motion.sampleText(at: 0.04)
        XCTAssertNotEqual(shell, text)
        motion.present(compact, at: 0.04, resizeDuration: 0.28, reduceMotion: false)
        XCTAssertEqual(motion.sample(at: 0.04), shell)
        XCTAssertEqual(motion.sampleText(at: 0.04), text)
        XCTAssertEqual(motion.sampleText(at: 0.5), compact)
        motion.present(expanded, at: 1, resizeDuration: ActivityIslandMotion.revealDuration,
                       elasticResize: true, reduceMotion: false)
        let beforeHide = motion.sampleText(at: 1.1)
        motion.hide(compact: compact, inset: inset, at: 1.1, animated: true)
        XCTAssertEqual(motion.sampleText(at: 1.1).visibility, beforeHide.visibility)
        let beforeShow = motion.sampleText(at: 1.2)
        motion.present(expanded, at: 1.2, resizeDuration: ActivityIslandMotion.revealDuration,
                       elasticResize: true, reduceMotion: false)
        XCTAssertEqual(motion.sampleText(at: 1.2).visibility, beforeShow.visibility)
        motion.present(expanded, at: 1.3, resizeDuration: ActivityIslandMotion.revealDuration,
                       elasticResize: true, reduceMotion: true)
        XCTAssertEqual(motion.sampleText(at: 1.3), expanded)
        XCTAssertFalse(motion.isAnimating(at: 1.3))
    }

    func testRepeatedHiddenSnapshotsFinishBothExitStages() {
        var motion = ActivityIslandMotion(pose: expanded)
        motion.hide(compact: compact, inset: inset, at: 0, animated: true)
        let reference = motion
        XCTAssertEqual(motion.sample(at: 0.28), compact)
        XCTAssertLessThan(motion.sample(at: 0.42).visibility, 1)
        for index in 1...100 {
            let time = Double(index) * 0.01
            motion.hide(compact: compact, inset: inset, at: time, animated: true)
            XCTAssertEqual(motion.sample(at: time), reference.sample(at: time))
        }
        XCTAssertEqual(motion.sample(at: 1), ActivityIslandMotion.hiddenPose(inset: inset))
        XCTAssertFalse(motion.isAnimating(at: 1))
    }

    func testActivityReturningDuringExitCancelsOldDismissal() {
        var motion = ActivityIslandMotion(pose: expanded)
        motion.hide(compact: compact, inset: inset, at: 0, animated: true)
        let current = motion.sample(at: 0.4)
        motion.present(expanded, at: 0.4, resizeDuration: 0.3, reduceMotion: false)
        XCTAssertEqual(motion.sample(at: 0.4), current)
        XCTAssertGreaterThan(motion.sample(at: 0.56).visibility, current.visibility)
        XCTAssertEqual(motion.sample(at: 1.3), expanded)
    }

    func testDisableAndReduceMotionStopAnInFlightTransitionImmediately() {
        var motion = ActivityIslandMotion(pose: ActivityIslandMotion.hiddenPose(inset: inset))
        motion.present(expanded, at: 0, resizeDuration: 0.3, reduceMotion: false)
        motion.hide(compact: compact, inset: inset, at: 0.1, animated: false)
        XCTAssertEqual(motion.sample(at: 0.1), ActivityIslandMotion.hiddenPose(inset: inset))
        XCTAssertFalse(motion.isAnimating(at: 0.1))
        motion.present(expanded, at: 1, resizeDuration: 0.3, reduceMotion: false)
        motion.present(expanded, at: 1.1, resizeDuration: 0.3, reduceMotion: true)
        XCTAssertEqual(motion.sample(at: 1.1), expanded)
        XCTAssertFalse(motion.isAnimating(at: 1.1))
        motion.hide(compact: compact, inset: inset, at: 2, animated: true)
        motion.hide(compact: compact, inset: inset, at: 2.1, animated: false)
        XCTAssertFalse(motion.isAnimating(at: 2.1))
        XCTAssertEqual(motion.sample(at: 2.1).visibility, 0)
    }
}
