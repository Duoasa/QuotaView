import AppKit
import Foundation
import XCTest
@testable import QuotaView
@testable import QuotaViewCore

@MainActor
final class IslandQuantumRenderingSmokeTests: XCTestCase {
    private let identity = CodexActivityTaskIdentity(sessionHash: "task", turnHash: "turn")

    private func makeEffect() throws -> ActivityStateSmokeMetalView {
        _ = NSApplication.shared
        let effect = ActivityStateSmokeMetalView(frame: .init(x: 0, y: 0, width: 624, height: 60))
        guard effect.isRendererAvailable else { throw XCTSkip("Metal unavailable") }
        effect.setEffect(.dropField)
        effect.setState(.thinking, taskIdentity: identity)
        effect.setApproximateProgress(0.65)
        effect.setPlaybackEnabled(true)
        XCTAssertFalse(effect.isPaused)
        XCTAssertEqual(effect.preferredFramesPerSecond, 60)
        return effect
    }

    func testRunningBusinessUpdatesPreserveNextFrameClockInterval() throws {
        let effect = try makeEffect()
        defer { effect.setPlaybackEnabled(false) }
        let reference = try XCTUnwrap(effect.playbackClockReference)
        // Tool/answer state can change between two frames. That time still
        // belongs to the next simulation step, even with several updates.
        for state: CodexActivityVisualState in [.working, .awaitingConfirmation, .thinking, .compactingContext, .working] {
            effect.setState(state, taskIdentity: identity)
            effect.setApproximateProgress(0.7)
            XCTAssertFalse(effect.isPaused)
            XCTAssertEqual(effect.playbackClockReference, reference)
        }
    }

    func testOnlyRealPlaybackAndReducedMotionBoundariesResetClock() throws {
        let effect = try makeEffect()
        defer { effect.setPlaybackEnabled(false) }
        let running = try XCTUnwrap(effect.playbackClockReference)
        effect.setPlaybackEnabled(false)
        XCTAssertTrue(effect.isPaused)
        let hidden = try XCTUnwrap(effect.playbackClockReference)
        XCTAssertGreaterThan(hidden, running)
        effect.setState(.working, taskIdentity: identity)
        XCTAssertEqual(effect.playbackClockReference, hidden)
        effect.setPlaybackEnabled(true)
        XCTAssertFalse(effect.isPaused)
        let resumed = try XCTUnwrap(effect.playbackClockReference)
        XCTAssertGreaterThan(resumed, hidden)
        effect.setReduceMotion(true)
        XCTAssertTrue(effect.isPaused, "A known progress value permits a static reduced-motion frame")
        let reduced = try XCTUnwrap(effect.playbackClockReference)
        XCTAssertGreaterThan(reduced, resumed)
        effect.setState(.thinking, taskIdentity: identity)
        effect.setPlaybackEnabled(false)
        effect.setPlaybackEnabled(true)
        XCTAssertEqual(effect.playbackClockReference, reduced, "Hidden/showing while already static cannot resume the simulation")
        effect.setReduceMotion(false)
        XCTAssertFalse(effect.isPaused)
        XCTAssertGreaterThan(try XCTUnwrap(effect.playbackClockReference), reduced)
    }

    func testRepeatedCardLayoutDoesNotResizeCanvasOrReplayProgress() throws {
        _ = NSApplication.shared
        let host = IslandQuantumProgressHost(frame: .init(x: 0, y: 0, width: 624, height: 60))
        guard host.effectAvailable else { throw XCTSkip("Metal unavailable") }
        let state = CodexActivityRenderState(taskIdentity: identity, visualState: .working,
            approximateProgressFraction: 0.65, windowTitle: "QuotaView", statusTitle: "Working",
            operation: "exec", accessibilityLabel: "Working")
        host.configure(renderState: state, visible: false, reduceMotion: true)
        host.layout()
        XCTAssertEqual(host.effectFrame, host.bounds)
        XCTAssertEqual(host.effectLayoutCommitCount, 1)
        let progress = try XCTUnwrap(host.progressPosition)
        for _ in 0..<8 {
            host.configure(renderState: state, visible: false, reduceMotion: true)
            host.layout()
        }
        XCTAssertEqual(host.effectLayoutCommitCount, 1)
        XCTAssertEqual(try XCTUnwrap(host.progressPosition), progress)
        host.frame.size.width = 600
        host.layout()
        XCTAssertEqual(host.effectFrame, host.bounds)
        XCTAssertEqual(host.effectLayoutCommitCount, 2)
        XCTAssertEqual(try XCTUnwrap(host.progressPosition), progress)
        host.stop()
    }
}
