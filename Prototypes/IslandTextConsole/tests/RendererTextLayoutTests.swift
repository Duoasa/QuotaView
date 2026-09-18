import AppKit
import MetalKit
import XCTest
@testable import QuotaView

// Runs against the console's byte-matched renderer with internal visibility.
// No window, screenshot, or production activity source is needed.
final class RendererTextLayoutTests: XCTestCase {
    func testIslandBaseRemainsOpaqueBlackWhenCompletionEffectClears() throws {
        func descendants(of node: NSView) -> [NSView] {
            [node] + node.subviews.flatMap { descendants(of: $0) }
        }
        for effect in AppPreferences.CodexActivityProgressEffect.allCases {
            let working = CodexActivityRenderState(visualState: .working, approximateProgressFraction: 0.4,
                windowTitle: "DEBUG surface fixture", statusTitle: "Working", operation: "Audit",
                accessibilityLabel: "DEBUG black surface regression")
            let completed = CodexActivityRenderState(visualState: .completed, approximateProgressFraction: 1,
                windowTitle: "DEBUG surface fixture", statusTitle: "已完成", operation: "完成",
                completionReceiptStatus: "已完成", completionReceiptDetail: "100 tokens",
                completionQuotaRemainingPercent: 27, accessibilityLabel: "DEBUG black surface regression")
            let view = ActivityIslandContentView(initialState: working, progressEffect: effect)
            view.setPlaybackVisible(false)
            view.setReduceMotion(true)
            for state in [working, completed, working] {
                view.update(renderState: state, progressEffect: effect)
                for mode in CodexActivityIslandPresentation.allCases {
                    let size = CodexActivityIslandGeometry.panelSize(presentation: mode, renderState: state)
                    view.setPresentationLayoutSize(size)
                    view.frame = NSRect(origin: .zero, size: size)
                    view.layoutSubtreeIfNeeded()
                    let surface = try XCTUnwrap(descendants(of: view).first {
                        String(describing: type(of: $0)) == "ActivityIslandSurfaceView"
                    })
                    XCTAssertFalse(descendants(of: surface).contains { $0 is NSVisualEffectView },
                                   "Completion must not expose a desktop-dependent material")
                    // The first child is the backing below the transparent Metal effect and text.
                    let base = try XCTUnwrap(surface.subviews.first)
                    let color = try XCTUnwrap(base.layer?.backgroundColor.flatMap(NSColor.init(cgColor:))?.usingColorSpace(.sRGB))
                    XCTAssertEqual(base.frame, surface.bounds)
                    XCTAssertEqual(base.alphaValue, 1)
                    XCTAssertEqual(color.alphaComponent, 1)
                    XCTAssertEqual(color.redComponent, 0, accuracy: 0.000001)
                    XCTAssertEqual(color.greenComponent, 0, accuracy: 0.000001)
                    XCTAssertEqual(color.blueComponent, 0, accuracy: 0.000001)
                }
            }
        }
    }

    func testTextKeepsItsLayoutAndSharesTheContainerSpringTransform() {
        let canvas = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 210))
        let inset = CodexActivityIslandGeometry.panelInset
        for completed in [false, true] {
          for effect in AppPreferences.CodexActivityProgressEffect.allCases {
            let state = CodexActivityRenderState(
                visualState: completed ? .completed : .working,
                approximateProgressFraction: completed ? 1 : 0.42,
                windowTitle: "超长任务标题 👩🏽‍💻 / A long mixed-script task title",
                statusTitle: completed ? "已完成" : "执行中",
                operation: "正在执行步骤 / Running tool → café",
                tokenUsageTitle: "本次 783,800 tokens",
                completionReceiptStatus: completed ? "已完成" : nil,
                completionReceiptDetail: completed ? "783,800 tokens" : nil,
                completionQuotaRemainingPercent: completed ? 27 : nil,
                isConfirmationReminderActive: false,
                accessibilityLabel: "DEBUG text layout regression"
            )
            let view = ActivityIslandContentView(initialState: state, progressEffect: effect)
            view.setPlaybackVisible(false)
            canvas.addSubview(view)
            let size = CodexActivityIslandGeometry.panelSize(presentation: .expanded, renderState: state)
            let small = CodexActivityIslandGeometry.panelSize(presentation: .compact, renderState: state)
            let expanded = ActivityIslandMotion.Pose(width: size.width, height: size.height, visibility: 1)
            let compact = ActivityIslandMotion.Pose(width: small.width, height: small.height, visibility: 1)

            func apply(_ shell: ActivityIslandMotion.Pose, _ layout: ActivityIslandMotion.Pose,
                       _ text: ActivityIslandMotion.Pose) {
                view.setPresentationLayoutSize(NSSize(width: layout.width, height: layout.height))
                view.frame = shell.frame(in: canvas.bounds, inset: inset)
                view.setTextLayoutFrame(text.frame(relativeTo: layout, inset: inset), opacity: text.visibility)
                view.layoutSubtreeIfNeeded()
            }
            func labels(in node: NSView) -> [NSView] {
                let own = String(describing: type(of: node)) == "ActivitySingleLineTextView" ? [node] : []
                return own + node.subviews.flatMap { labels(in: $0) }
            }
            apply(expanded, expanded, expanded)
            let textViews = labels(in: view)
            XCTAssertGreaterThanOrEqual(textViews.count, 9)
            let reference = textViews.map { ($0.convert($0.bounds, to: canvas), $0.bounds.size, $0.alphaValue) }
            for start in [ActivityIslandMotion.hiddenPose(inset: inset), compact] {
                var motion = ActivityIslandMotion(pose: start)
                motion.present(expanded, at: 0, resizeDuration: ActivityIslandMotion.revealDuration,
                               elasticResize: true, reduceMotion: false)
                for step in 28...82 {
                    let time = Double(step) / 100
                    let shell = motion.sample(at: time)
                    let layout = motion.sampleLayout(at: time)
                    apply(shell, layout, motion.sampleText(at: time))
                    // AppKit frame/bounds conversion can differ by a few floating-point ULPs.
                    XCTAssertEqual(view.bounds.width, expanded.width, accuracy: 0.000001)
                    XCTAssertEqual(view.bounds.height, expanded.height, accuracy: 0.000001)
                    let finalFrame = expanded.frame(in: canvas.bounds, inset: inset)
                    let actualFrame = shell.frame(in: canvas.bounds, inset: inset)
                    let scaleX = shell.width / layout.width
                    let scaleY = shell.height / layout.height
                    for (label, expected) in zip(textViews, reference) {
                        let actual = label.convert(label.bounds, to: canvas)
                        XCTAssertEqual(actual.minX, actualFrame.minX + (expected.0.minX - finalFrame.minX) * scaleX, accuracy: 0.000001)
                        XCTAssertEqual(actual.minY, actualFrame.minY + (expected.0.minY - finalFrame.minY) * scaleY, accuracy: 0.000001)
                        XCTAssertEqual(actual.width, expected.0.width * scaleX, accuracy: 0.000001)
                        XCTAssertEqual(actual.height, expected.0.height * scaleY, accuracy: 0.000001)
                        XCTAssertEqual(label.bounds.size, expected.1)
                        XCTAssertEqual(label.alphaValue, expected.2)
                    }
                }
            }
            view.removeFromSuperview()
          }
        }
    }

    func testStoppingPlaybackPausesAllMetalViewsIncludingAfterEffectChange() throws {
        let state = CodexActivityRenderState(visualState: .working, approximateProgressFraction: 0.4,
            windowTitle: "DEBUG playback fixture", statusTitle: "执行中", operation: "Running",
            accessibilityLabel: "DEBUG playback regression")
        let view = ActivityIslandContentView(initialState: state, progressEffect: .dropField)
        func metalViews(in node: NSView) -> [MTKView] {
            ((node as? MTKView).map { [$0] } ?? []) + node.subviews.flatMap { metalViews(in: $0) }
        }
        let renderers = metalViews(in: view)
        try XCTSkipIf(renderers.isEmpty, "Metal unavailable")
        for effect in AppPreferences.CodexActivityProgressEffect.allCases {
            view.update(renderState: state, progressEffect: effect)
            view.setPlaybackVisible(true)
            view.setPlaybackVisible(false)
            XCTAssertTrue(renderers.allSatisfy(\.isPaused), "Hidden effect: \(effect)")
            view.setReduceMotion(true)
            view.update(renderState: state, progressEffect: effect)
            XCTAssertTrue(renderers.allSatisfy(\.isPaused))
            view.setReduceMotion(false)
        }
    }

    func testHoverBoundsFollowTheRenderedSurfaceDuringSharedRebound() {
        let canvas = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 210))
        let state = CodexActivityRenderState(visualState: .working, approximateProgressFraction: 0.4,
            windowTitle: "DEBUG hover fixture", statusTitle: "Working", operation: "Audit",
            accessibilityLabel: "DEBUG hover regression")
        let view = ActivityIslandContentView(initialState: state, progressEffect: .dropField)
        view.setPlaybackVisible(false)
        canvas.addSubview(view)
        let inset = CodexActivityIslandGeometry.panelInset
        let size = CodexActivityIslandGeometry.panelSize(presentation: .expanded, renderState: state)
        let target = ActivityIslandMotion.Pose(width: size.width, height: size.height, visibility: 1)
        var motion = ActivityIslandMotion(pose: ActivityIslandMotion.hiddenPose(inset: inset))
        motion.present(target, at: 0, resizeDuration: 0.82, elasticResize: true, reduceMotion: false)
        for millisecond in stride(from: 0, through: 820, by: 4) {
            let time = Double(millisecond) / 1000
            let shell = motion.sample(at: time)
            let layout = motion.sampleLayout(at: time)
            view.setPresentationLayoutSize(NSSize(width: layout.width, height: layout.height))
            view.frame = shell.frame(in: canvas.bounds, inset: inset)
            view.layoutSubtreeIfNeeded()
            let hit = view.visibleSurfaceFrame(in: canvas)
            let scaleX = shell.width / layout.width
            let scaleY = shell.height / layout.height
            XCTAssertEqual(hit.minX, view.frame.minX + inset * scaleX, accuracy: 0.000001)
            XCTAssertEqual(hit.minY, view.frame.minY + inset * scaleY, accuracy: 0.000001)
            XCTAssertEqual(hit.maxX, view.frame.maxX - inset * scaleX, accuracy: 0.000001)
            XCTAssertEqual(hit.maxY, view.frame.maxY - inset * scaleY, accuracy: 0.000001)
        }
    }
}
