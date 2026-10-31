import AppKit
import SwiftUI
import XCTest
@testable import QuotaView
@testable import QuotaViewCore

final class CompletionOutlineFlowSmokeTests: XCTestCase {
    @MainActor func testCompletionFlowLoopsWithoutMovingContourOrRestartingOnRefresh() throws {
        let view = ActivityIslandCompletionOutlineView(frame: NSRect(x: 0, y: 0, width: 608, height: 70))
        view.usesContinuousCorners = true
        view.update(edgeEmphasis: .completion, reduceMotion: false, playbackVisible: true)
        view.layoutSubtreeIfNeeded()
        let contour = try XCTUnwrap(view.outlinePath)
        let flow = try XCTUnwrap(view.flowAnimation)
        XCTAssertEqual(flow.keyPath, "colors")
        XCTAssertEqual(flow.duration, 6)
        XCTAssertEqual(flow.repeatCount, .infinity)
        let frames = try XCTUnwrap(flow.values as? [[CGColor]])
        XCTAssertEqual(frames.first, frames.last, "Cycle boundary must not jump")
        XCTAssertTrue(frames.allSatisfy { $0.first == $0.last }, "Conic origin must not have a hard seam")
        XCTAssertEqual(Set(view.displayedColors), Set([CodexActivityIslandCompletionPalette.violet.cgColor,
            CodexActivityIslandCompletionPalette.blue.cgColor, CodexActivityIslandCompletionPalette.cyan.cgColor]))
        view.update(edgeEmphasis: .completion, reduceMotion: false, playbackVisible: true)
        XCTAssertEqual(view.flowAnimation?.beginTime, flow.beginTime)
        XCTAssertEqual(view.outlinePath, contour)
        view.update(edgeEmphasis: .completion, reduceMotion: true, playbackVisible: true)
        XCTAssertNil(view.flowAnimation)
        XCTAssertFalse(view.isHidden, "Reduced motion keeps a static colored outline")
        view.update(edgeEmphasis: .confirmationReminder, reduceMotion: false, playbackVisible: true)
        XCTAssertNil(view.flowAnimation)
        XCTAssertEqual(view.displayedColors[1], CodexActivityIslandConfirmationReminderContract.approvalColor.cgColor)
        view.update(edgeEmphasis: .completion, reduceMotion: false, playbackVisible: false)
        XCTAssertTrue(view.isHidden)
        XCTAssertNil(view.flowAnimation)
        view.update(edgeEmphasis: .completion, reduceMotion: false, playbackVisible: true)
        XCTAssertNotNil(view.flowAnimation)
        view.update(edgeEmphasis: .none, reduceMotion: false, playbackVisible: true)
        XCTAssertTrue(view.isHidden)
        XCTAssertNil(view.flowAnimation)
    }

    @MainActor func testCardHostStopsFlowForReducedMotionAndWhenDetached() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 608, height: 70),
            styleMask: .borderless, backing: .buffered, defer: false)
        let host = IslandQuantumProgressHost(frame: .zero)
        window.contentView = host
        let state = CodexActivityRenderState(visualState: .completed, approximateProgressFraction: 1,
            windowTitle: "Fixture", statusTitle: "Completed", operation: "", accessibilityLabel: "Fixture")
        host.configure(renderState: state, visible: true, reduceMotion: false)
        XCTAssertNotNil(host.completionOutlineFlow)
        XCTAssertNil(host.completionOutlinePulse, "Flow must not pulse outline brightness")
        host.configure(renderState: state, visible: true, reduceMotion: true)
        XCTAssertNil(host.completionOutlineFlow)
        host.configure(renderState: state, visible: true, reduceMotion: false)
        XCTAssertNotNil(host.completionOutlineFlow)
        host.removeFromSuperview()
        XCTAssertNil(host.completionOutlineFlow)
        window.contentView = host
        XCTAssertNotNil(host.completionOutlineFlow)
        host.stop()
        XCTAssertNil(host.completionOutlineFlow)
    }

    func testInactiveCardsShareOrbHueAtLowIntensityIncludingSolidFallback() {
        let environment = EnvironmentValues()
        for state in CodexActivityVisualState.allCases {
            let orb = CodexActivityRippleGlowContract.statusTint(for: state)
            let card = IslandTaskCardAppearance(visualState: state, hovered: false, selected: false)
            let tint = card.glassTint.resolve(in: environment)
            let solid = card.solidTint.resolve(in: environment)
            XCTAssertLessThan(max(tint.red, tint.green, tint.blue), 0.20)
            XCTAssertLessThan(max(solid.red, solid.green, solid.blue), 0.20)
            // A pale state wash retains the orb's component order and hue direction.
            XCTAssertEqual(tint.red > tint.green, orb.redComponent > orb.greenComponent)
            XCTAssertEqual(tint.blue > tint.green, orb.blueComponent > orb.greenComponent)
        }
        let focused = IslandTaskCardAppearance(visualState: .working, hovered: false, selected: true)
            .glassTint.resolve(in: environment)
        XCTAssertEqual(focused.red, 0)
        XCTAssertEqual(focused.green, 0)
        XCTAssertEqual(focused.blue, 0)
    }
}
