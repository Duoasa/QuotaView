import AppKit
import CoreText
import XCTest
@testable import QuotaView
@testable import QuotaViewCore

/// Bounded, local smoke coverage; no native connection, model request or UI automation.
final class CodexMultitaskSmokeTests: XCTestCase {
    private func event(_ kind: CodexActivityHookEvent, _ session: String, turn: String = "turn-1",
                       at: Date = Date(), completion: CodexActivityTurnCompletionStatus? = nil) -> CodexActivityEvent {
        .init(event: kind, sessionHash: session, turnHash: turn, sessionKind: .user,
              source: .localRollout, turnCompletionStatus: completion, occurredAt: at)
    }
    private func snapshot(_ session: String, state: CodexActivityVisualState = .working,
                          turn: String = "turn-1") -> CodexActivitySnapshot {
        .init(sessionHash: session, taskIdentity: .init(sessionHash: session, turnHash: turn),
              state: state, workspaceName: nil, operationKey: .usingTool, toolCategory: nil,
              approximateProgressFraction: nil, occurredAt: Date())
    }
    @MainActor
    func testPreferenceDefaultsOffAndPersists() {
        let suite = "QuotaView.MultitaskSmoke.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        XCTAssertFalse(preferences.codexActivityMultitaskEnabled)
        preferences.codexActivityMultitaskEnabled = true
        XCTAssertTrue(AppPreferences(defaults: defaults).codexActivityMultitaskEnabled)
        preferences.codexActivityMultitaskEnabled = false
        XCTAssertFalse(AppPreferences(defaults: defaults).codexActivityMultitaskEnabled)
    }
    @MainActor
    func testRealEventReductionKeepsTaskStateTokensAndManualSelectionIndependent() async throws {
        let store = CodexActivityStore(titleClient: CodexAppServerClient(executablePath: nil))
        let now = Date()
        store.receive(event(.userPromptSubmit, "a", at: now))
        store.receive(event(.userPromptSubmit, "b", at: now.addingTimeInterval(1)))
        store.setMultitaskEnabled(true)
        XCTAssertEqual(Set(store.multitask.entries.map { $0.snapshot.sessionHash }), ["a", "b"])
        XCTAssertNil(store.multitaskTotalTokenUsage)
        let a = try XCTUnwrap(store.multitask.entries.first { $0.snapshot.sessionHash == "a" })
        let b = try XCTUnwrap(store.multitask.entries.first { $0.snapshot.sessionHash == "b" })
        store.selectMultitaskTask(a.id)
        for (session, tokens) in [("a", Int64(120)), ("b", Int64(340))] {
            store.receive(CodexActivityTokenUsageUpdate(sessionHash: session, turnHash: "turn-1",
                cumulativeTotalTokens: tokens, lastReportedTotalTokens: tokens,
                directTurnTotalTokens: tokens, occurredAt: now.addingTimeInterval(2)))
        }
        store.receive(event(.preCompact, "b", at: now.addingTimeInterval(3)))
        XCTAssertEqual(store.multitask.selectedID, a.id)
        XCTAssertEqual(store.multitask.entries.first { $0.id == b.id }?.snapshot.state, .compactingContext)
        XCTAssertEqual(store.tokenUsage(for: "a"), 120)
        XCTAssertEqual(store.tokenUsage(for: "b"), 340)
        XCTAssertEqual(store.multitaskTotalTokenUsage, 460)
        store.receive(event(.userPromptSubmit, "internal", at: now.addingTimeInterval(4)).classified(as: .internalTask))
        XCTAssertEqual(store.multitask.entries.count, 2)
        store.receive(event(.stop, "a", at: now.addingTimeInterval(5), completion: .completed))
        XCTAssertFalse(store.multitask.allCompleted)
        XCTAssertNil(store.multitask.nextDeadline)
        store.receive(event(.stop, "b", at: now.addingTimeInterval(6), completion: .completed))
        XCTAssertTrue(store.multitask.allCompleted)
        let deadline = store.multitask.nextDeadline
        store.receive(event(.stop, "b", at: now.addingTimeInterval(6), completion: .completed))
        XCTAssertEqual(store.multitask.nextDeadline, deadline)
        XCTAssertEqual(store.multitaskTotalTokenUsage, 460, "Selection and repeated completion cannot double-count usage")
        let single = store.snapshot
        store.setMultitaskEnabled(false)
        XCTAssertTrue(store.multitask.entries.isEmpty)
        XCTAssertNil(store.multitaskTotalTokenUsage)
        XCTAssertNil(store.multitask.nextDeadline)
        XCTAssertEqual(store.snapshot, single, "Opt-out preserves the original single-island path")
        await store.stop()
        XCTAssertFalse(store.multitask.enabled)
    }
    func testCompletionGatingOrderingCancellationAndRestart() throws {
        var state = CodexActivityMultitaskState()
        state.setEnabled(true)
        state.updateDelays(compact: 0.1, hidden: 1, now: 0)
        func add(_ session: String, _ now: Double) {
            state.receive(snapshot(session), lifecycle: .active, compactionSource: nil, now: now, permitsNewEntry: true)
        }
        add("a", 0); add("b", 1); add("c", 2)
        XCTAssertEqual(state.entries.map { $0.snapshot.sessionHash }, ["a", "c", "b"])
        let a = try XCTUnwrap(state.selectedID)
        state.receive(snapshot("a", state: .completed), lifecycle: .completed, compactionSource: nil, now: 3, permitsNewEntry: true)
        state.receive(snapshot("c", state: .completed), lifecycle: .completed, compactionSource: nil, now: 3, permitsNewEntry: true)
        state.receive(snapshot("b", state: .error), lifecycle: .idle, compactionSource: nil, now: 3, permitsNewEntry: true)
        XCTAssertFalse(state.allCompleted)
        XCTAssertNil(state.nextDeadline)
        state.receive(snapshot("b", state: .completed), lifecycle: .completed, compactionSource: nil, now: 4, permitsNewEntry: true)
        let deadline = try XCTUnwrap(state.nextDeadline)
        XCTAssertEqual(deadline, 4 + CodexMultitaskCompletionTiming.duration(taskCount: 3))
        XCTAssertEqual(state.selectedID, a)
        add("d", 4.2)
        state.advance(now: deadline)
        XCTAssertEqual(state.presentation, .expanded)
        XCTAssertNil(state.completionStartedAt)
        XCTAssertNil(state.nextDeadline)
        state.receive(snapshot("d", state: .completed), lifecycle: .completed, compactionSource: nil, now: 6, permitsNewEntry: true)
        state.advance(now: 8)
        XCTAssertEqual(state.presentation, .compact)
        state.advance(now: 10)
        XCTAssertEqual(state.presentation, .hidden)
        state.receive(snapshot("a", turn: "turn-2"), lifecycle: .active, compactionSource: nil, now: 11, permitsNewEntry: true)
        XCTAssertEqual(state.entries.count, 1)
        XCTAssertEqual(state.selected?.snapshot.sessionHash, "a")
        XCTAssertEqual(state.presentation, .expanded)
    }
    @MainActor
    func testStaleReplayAndCompactionDisconnectDoNotReportSuccess() async throws {
        let store = CodexActivityStore(titleClient: CodexAppServerClient(executablePath: nil))
        let now = Date()
        store.receive(.init(source: .startupReplay,
            activity: event(.postToolUse, "old", at: now.addingTimeInterval(-60))))
        store.setMultitaskEnabled(true)
        XCTAssertTrue(store.multitask.entries.isEmpty)
        store.receive(event(.userPromptSubmit, "a", at: now))
        store.receive(event(.preCompact, "a", at: now.addingTimeInterval(1)))
        store.compactionSourceUnavailable(.localRollout)
        XCTAssertEqual(store.multitask.selected?.lifecycle, .unconfirmed)
        XCTAssertEqual(store.multitask.selected?.snapshot.state, .unavailable)
        XCTAssertFalse(store.multitask.allCompleted)
        store.receive(event(.preToolUse, "a", at: now.addingTimeInterval(2)))
        XCTAssertEqual(store.multitask.selected?.lifecycle, .active)
        await store.stop()
    }
    @MainActor
    func testNativeShellDefaultsAndSimultaneousFusion() throws {
        _ = NSApplication.shared
        let render = CodexActivityRenderState(visualState: .working, approximateProgressFraction: nil,
            windowTitle: "Task", statusTitle: "Working", operation: "Tool", accessibilityLabel: "Task working")
        let node = CodexMultitaskTaskNode(frame: .zero)
        node.configure(task: .init(id: 1, renderState: render), english: true, effect: .dropField, reduceMotion: true)
        let pose = CodexMultitaskMotion.Pose(frame: CGRect(origin: .zero, size: CodexMultitaskGeometry.mainSize))
        node.apply(pose, isMain: true, compact: false)
        let renderer = try XCTUnwrap(node.renderer)
        XCTAssertEqual(renderer.multitaskSurfaceCornerRadius, CodexActivityIslandProgressBarGeometry.expandedCornerRadius, accuracy: 0.01)
        XCTAssertEqual(renderer.multitaskShellTransform, .identity)
        var jelly = pose; jelly.capsule = 1; jelly.shellJelly = 0.09
        node.apply(jelly, isMain: true, compact: false)
        XCTAssertEqual(renderer.multitaskShellTransform.d, 0.91, accuracy: 0.001)
        XCTAssertEqual(renderer.multitaskTextTransform, .identity, "Content inherits shell transform")
        node.apply(pose, isMain: true, compact: false)
        XCTAssertEqual(renderer.multitaskShellTransform, .identity)
        let frames = CodexMultitaskGeometry.frames(ids: [1, 2, 3, 4], selected: 3, compact: false)
        XCTAssertEqual(frames[3]?.midX, 0)
        XCTAssertEqual(frames[2]?.size, NSSize(width: 104, height: 52))
        XCTAssertEqual(try XCTUnwrap(frames[2]).minX - XCTUnwrap(frames[1]).maxX, 12, accuracy: 0.001)
        var motion = CodexMultitaskMotion()
        motion.retarget(frames.mapValues { .init(frame: $0) }, selected: 3, now: 0, animate: false)
        motion.gatherCompleted(selected: 3, started: 1, now: 1, animate: true)
        let gathering = motion.sample(1.3)
        for id in [1, 2, 4] { XCTAssertNotEqual(gathering[id]?.frame, frames[id]) }
        let finished = motion.sample(3)
        for id in [1, 2, 4] { XCTAssertEqual(finished[id]?.opacity, 0) }
        node.setPlayback(false)
    }

    func testStatusNoticeKeepsLatestStateWithoutRepeatingOrExtending() {
        var notice = CodexMultitaskStatusNotice()
        notice.observe(.working, at: 0)
        XCTAssertFalse(notice.isShowing(at: 0), "Initial snapshot displays the title")
        notice.observe(.compactingContext, at: 1)
        XCTAssertTrue(notice.isShowing(at: 1))
        let deadline = notice.expiresAt, revision = notice.revision
        notice.observe(.compactingContext, at: 2)
        XCTAssertEqual(notice.expiresAt, deadline)
        XCTAssertEqual(notice.revision, revision)
        notice.observe(.awaitingConfirmation, at: 2.1)
        XCTAssertEqual(notice.state, .awaitingConfirmation)
        XCTAssertEqual(notice.revision, revision + 1)
        XCTAssertTrue(notice.isShowing(at: 4.4))
        XCTAssertFalse(notice.isShowing(at: 4.6))
        notice.cancel()
        notice.observe(.awaitingConfirmation, at: 5)
        XCTAssertFalse(notice.isShowing(at: 5), "Reappearing doesn't replay an old notice")
    }

    @MainActor
    func testSatelliteUsesRealStateAndFullSurfaceEffectWithStaticFallback() async throws {
        _ = NSApplication.shared
        let node = CodexMultitaskTaskNode(frame: .zero)
        let pose = CodexMultitaskMotion.Pose(frame: CGRect(x: 0, y: 0, width: 104, height: 52))
        func configure(_ state: CodexActivityVisualState, reduced: Bool = false) {
            let render = CodexActivityRenderState(visualState: state, approximateProgressFraction: 0.1,
                windowTitle: "需要完整显示的任务标题", statusTitle: CodexActivityCopy(language: .simplifiedChinese).statusTitle(for: state),
                operation: "", accessibilityLabel: "Task")
            node.configure(task: .init(id: 1, renderState: render), english: false, effect: .dropField, reduceMotion: reduced)
            node.setPresented(true); node.setPlayback(true)
            node.apply(pose, isMain: false, compact: false)
        }
        configure(.working)
        XCTAssertEqual(node.displayedSatelliteTitle, "需要完整显示的任务标题")
        XCTAssertNotNil(node.satelliteTitleScrollAnimation)
        XCTAssertEqual(node.satelliteTitleFrame.midX, 52)
        XCTAssertEqual(node.satelliteTitleFrame.width, 80)
        XCTAssertFalse(node.satelliteStatusOutline.isHidden)
        XCTAssertEqual(node.satelliteStatusColor, CodexActivityVisualState.working.activityAccentColor)
        let effect = try XCTUnwrap(node.satelliteEffect)
        XCTAssertTrue(effect.isRendererAvailable, "Compiles the shared Metal pipeline locally")
        XCTAssertTrue(effect.fullSurfacePresentation)
        XCTAssertEqual(effect.alphaValue, 1, accuracy: 0.001)
        XCTAssertEqual(effect.preferredFramesPerSecond, 30)
        XCTAssertFalse(effect.isPaused)
        configure(.compactingContext)
        XCTAssertEqual(node.displayedSatelliteTitle, "压缩上下文")
        XCTAssertNil(node.satelliteTitleScrollAnimation, "The state notice temporarily takes over the title viewport")
        XCTAssertEqual(node.satelliteStatusColor, CodexActivityVisualState.compactingContext.activityAccentColor)
        configure(.awaitingConfirmation, reduced: true)
        XCTAssertEqual(node.displayedSatelliteTitle, "待确认")
        XCTAssertEqual(node.satelliteStatusColor, CodexActivityVisualState.awaitingConfirmation.activityAccentColor)
        XCTAssertTrue(effect.isPaused, "Reduce Motion immediately stops full-field rendering")
        configure(.error)
        XCTAssertEqual(node.satelliteStatusColor, CodexActivityVisualState.error.activityAccentColor)
        XCTAssertEqual(node.displayedSatelliteTitle, "失败")
        try await Task.sleep(nanoseconds: 2_600_000_000)
        XCTAssertEqual(node.displayedSatelliteTitle, "需要完整显示的任务标题", "The live one-shot callback restores the title without a new event")
        // Unhosted AppKit layers drop CA animations on transaction commit. The
        // direct marquee smoke verifies the animation; here verify callback state.
        XCTAssertTrue(node.satelliteTitleIsScrolling, "The restored long title scrolls again")
        node.setPresented(false); node.setPlayback(false)
        XCTAssertNil(node.satelliteTitleScrollAnimation)
        XCTAssertTrue(effect.isPaused)
        node.setPresented(true); node.apply(pose, isMain: false, compact: false)
        XCTAssertEqual(node.displayedSatelliteTitle, "需要完整显示的任务标题")
        XCTAssertEqual(node.satelliteStatusColor, CodexActivityVisualState.error.activityAccentColor,
                       "Returning to the title retains the real task indicator")
        let single = ActivityStateSmokeMetalView(frame: .zero)
        XCTAssertFalse(single.fullSurfacePresentation, "Single-task effect defaults remain unchanged")
        single.setPlaybackEnabled(false)
    }

    @MainActor
    func testSatelliteTitleFallbackAndMarqueeShowsEntireTextWithoutRefreshRestart() throws {
        _ = NSApplication.shared
        let copy = CodexActivityCopy(language: .simplifiedChinese)
        XCTAssertEqual(copy.taskTitle(resolvedTitle: nil, workspaceName: "widget"), "widget")
        XCTAssertEqual(copy.taskTitle(resolvedTitle: "Codex · 标题中的真实名称", workspaceName: "widget"),
                       "Codex · 标题中的真实名称", "Only the generated fallback loses the prefix")
        XCTAssertEqual(CodexActivityCopy(language: .english).taskTitle(resolvedTitle: "  ", workspaceName: nil), "Untitled task")
        let view = CodexMultitaskMarqueeView(frame: CGRect(x: 0, y: 0, width: 64, height: 20))
        view.stringValue = "这是需要完整滚动显示的很长任务标题"
        view.setScrollingEnabled(true, reduceMotion: false)
        let first = try XCTUnwrap(view.scrollAnimation)
        XCTAssertGreaterThan(view.scrollDistance, 64)
        XCTAssertEqual((first.values?[2] as? NSNumber)?.doubleValue, -Double(view.scrollDistance))
        XCTAssertEqual(first.repeatCount, .infinity)
        XCTAssertEqual((first.keyTimes?[1].doubleValue ?? 0) * first.duration, 1.2, accuracy: 0.001)
        for _ in 0..<5 {
            view.setScrollingEnabled(true, reduceMotion: false)
            view.needsLayout = true; view.layoutSubtreeIfNeeded()
        }
        XCTAssertEqual(view.scrollAnimation?.beginTime, first.beginTime)
        view.setScrollingEnabled(false, reduceMotion: false)
        XCTAssertNil(view.scrollAnimation)
        view.setScrollingEnabled(true, reduceMotion: true)
        XCTAssertNil(view.scrollAnimation)
        view.stringValue = "API"
        view.setScrollingEnabled(true, reduceMotion: false)
        XCTAssertNil(view.scrollAnimation, "Short titles stay still")
        XCTAssertEqual(view.stringValue, "API")
    }

    @MainActor
    func testCompletedSatelliteBreathesGreenWithoutStatusIconAndCleansUp() throws {
        _ = NSApplication.shared
        let node = CodexMultitaskTaskNode(frame: .zero)
        var pose = CodexMultitaskMotion.Pose(frame: CGRect(x: 0, y: 0, width: 104, height: 52))
        pose.shellJelly = 0.09
        func configure(_ state: CodexActivityVisualState, reduced: Bool = false, isMain: Bool = false) {
            let render = CodexActivityRenderState(visualState: state, approximateProgressFraction: nil,
                windowTitle: "完成的任务", statusTitle: "已完成", operation: "", accessibilityLabel: "Task")
            node.configure(task: .init(id: 1, renderState: render), english: false, effect: .dropField, reduceMotion: reduced)
            node.setPresented(true); node.setPlayback(true)
            node.apply(pose, isMain: isMain, compact: false)
        }
        configure(.completed)
        XCTAssertEqual(node.displayedSatelliteTitle, "完成的任务")
        XCTAssertEqual(node.satelliteTitleFrame.midX, 52)
        let glow = node.satelliteCompletionGlow, outline = node.satelliteStatusOutline
        XCTAssertFalse(glow.isHidden); XCTAssertFalse(outline.isHidden)
        XCTAssertEqual(glow.completionColor, .systemGreen)
        XCTAssertEqual(outline.completionColor, .systemGreen)
        XCTAssertTrue(glow.superview === outline.superview)
        XCTAssertEqual(try XCTUnwrap(glow.superview?.layer?.affineTransform().d), 0.91, accuracy: 0.001)
        XCTAssertEqual(glow.superview?.layer?.masksToBounds, false)
        XCTAssertGreaterThan(glow.frame.width, 104, "External glow has room around the clipped black capsule")
        let layers = try XCTUnwrap(glow.layer?.sublayers)
        let key = "quotaview.activity.completion-glow.radius"
        let breath = try XCTUnwrap(layers.first?.animation(forKey: key))
        XCTAssertEqual(breath.repeatCount, .infinity)
        XCTAssertEqual(layers.first?.shadowColor, NSColor.systemGreen.cgColor)
        configure(.completed)
        XCTAssertEqual(layers.first?.animation(forKey: key)?.beginTime, breath.beginTime,
                       "Repeated completion never restarts the breath")
        configure(.completed, reduced: true)
        XCTAssertFalse(glow.isHidden); XCTAssertNil(layers.first?.animation(forKey: key))
        configure(.working)
        XCTAssertTrue(glow.isHidden); XCTAssertFalse(outline.isHidden)
        XCTAssertEqual(outline.completionColor, CodexActivityVisualState.working.activityAccentColor)
        for state in CodexActivityVisualState.allCases {
            configure(state)
            XCTAssertFalse(outline.isHidden)
            XCTAssertEqual(outline.completionColor, state == .completed ? .systemGreen : state.activityAccentColor)
            let colors = (outline.layer?.sublayers?.first as? CAGradientLayer)?.colors as? [CGColor]
            XCTAssertEqual(colors?[1], (state == .completed ? NSColor.systemGreen : state.activityAccentColor).cgColor)
            XCTAssertEqual(glow.isHidden, state != .completed)
        }
        configure(.working)
        XCTAssertTrue(layers.allSatisfy { ($0.animationKeys() ?? []).isEmpty })
        configure(.completed)
        node.setPresented(false); node.setPlayback(false)
        XCTAssertTrue(glow.isHidden); XCTAssertTrue(outline.isHidden)
        XCTAssertTrue(layers.allSatisfy { ($0.animationKeys() ?? []).isEmpty })
        configure(.completed, isMain: true)
        XCTAssertTrue(glow.isHidden, "The main renderer owns its own completion decoration")
        node.setPresented(false); node.setPlayback(false)
        XCTAssertNil(ActivityIslandCompletionGlowView(frame: .zero).completionColor)
        XCTAssertNil(ActivityIslandCompletionOutlineView(frame: .zero).completionRevealDelay)
    }

    @MainActor
    func testCompletionReceiptTotalQuotaAlignmentAndConcentricRing() throws {
        _ = NSApplication.shared
        func descendants<T: NSView>(_ view: NSView, of type: T.Type) -> [T] {
            view.subviews.flatMap { child in
                (child as? T).map { [$0] } ?? descendants(child, of: type)
            }
        }
        let source = CodexActivityRenderState(visualState: .completed, approximateProgressFraction: 1,
            windowTitle: "真实任务", statusTitle: "已完成", operation: "", accessibilityLabel: "Completed")
        for english in [false, true] {
            for count in [4, 128] {
                let summary = CodexMultitaskCompletionSummary(count: count, english: english,
                    totalTokens: 24_800, remainingPercent: 100)
                let aggregate = summary.applying(to: source)
                XCTAssertEqual(aggregate.completionReceiptDetail, english ? "Total 24.8K tokens" : "总计 24.8K tokens")
                XCTAssertTrue(aggregate.statusTitle.contains(String(count)))
                for compact in [false, true] {
                    let mode: CodexActivityIslandPresentation = compact ? .compact : .expanded
                    let width = compact ? CodexMultitaskCompletionSummary.compactWidth(count: count, english: english)
                        : CodexMultitaskGeometry.mainSize.width
                    let size = NSSize(width: width, height: compact ? 52 : CodexMultitaskGeometry.mainSize.height)
                    let inset = CodexActivityIslandGeometry.panelInset
                    let base = NSSize(width: size.width + inset * 2, height: size.height + inset * 2)
                    let timeline = ActivityIslandMotion.Pose(width: base.width, height: base.height, visibility: 1)
                    let node = CodexMultitaskTaskNode(frame: .zero)
                    node.configure(task: .init(id: 1, renderState: source), english: english,
                        effect: .dropField, reduceMotion: true, completionCount: count,
                        totalTokens: 24_800, remainingPercent: 100)
                    var pose = CodexMultitaskMotion.Pose(frame: CGRect(origin: .zero, size: size))
                    pose.capsule = 1
                    node.apply(pose, isMain: true, compact: compact,
                        presentation: .init(shell: timeline, layout: timeline, text: timeline))
                    let renderer = try XCTUnwrap(node.renderer)
                    let single = ActivityIslandContentView(initialState: aggregate, progressEffect: .dropField)
                    single.setReduceMotion(true)
                    single.setPresentationMode(mode, accessibilityValue: "")
                    single.setPresentationLayoutSize(base)
                    single.frame = renderer.frame
                    single.setTextLayoutFrame(CGRect(origin: .zero, size: base))
                    single.layoutSubtreeIfNeeded()
                    let actual = descendants(renderer, of: ActivitySingleLineTextView.self)
                    let expected = descendants(single, of: ActivitySingleLineTextView.self)
                    XCTAssertEqual(actual.count, expected.count, "No independent overlay or duplicate text layout")
                    for (mainText, singleText) in zip(actual, expected) {
                        XCTAssertEqual(mainText.stringValue, singleText.stringValue)
                        XCTAssertEqual(mainText.font, singleText.font)
                        XCTAssertEqual(mainText.frame, singleText.frame)
                        XCTAssertEqual(mainText.horizontalAlignment, singleText.horizontalAlignment)
                        XCTAssertEqual(mainText.alphaValue, singleText.alphaValue)
                    }
                    if compact {
                        let ring = try XCTUnwrap(descendants(renderer, of: ActivityIslandQuotaRingView.self).first)
                        ring.layoutSubtreeIfNeeded()
                        let host = try XCTUnwrap(ring.superview)
                        XCTAssertEqual(ring.frame.midX, host.bounds.maxX - 26)
                        XCTAssertEqual(ring.frame.midY, host.bounds.midY)
                        let label = try XCTUnwrap(actual.first { $0.stringValue == summary.compactTitle && $0.alphaValue > 0.5 })
                        XCTAssertLessThanOrEqual(activitySingleLineWidth(text: label.stringValue, font: label.font), label.bounds.width)
                        XCTAssertLessThanOrEqual(label.frame.maxX + 12, ring.frame.minX)
                        for shape in ring.layer?.sublayers?.compactMap({ $0 as? CAShapeLayer }) ?? [] {
                            XCTAssertEqual(try XCTUnwrap(shape.path).boundingBoxOfPath.midX, 15, accuracy: 0.001)
                            XCTAssertEqual(try XCTUnwrap(shape.path).boundingBoxOfPath.midY, 15, accuracy: 0.001)
                        }
                    }
                    node.setPlayback(false); single.setPlaybackVisible(false)
                }
            }
        }
        let unknown = CodexMultitaskCompletionSummary(count: 4, english: false,
            totalTokens: nil, remainingPercent: nil).applying(to: source)
        XCTAssertEqual(unknown.completionReceiptDetail, "总计 — tokens")
        XCTAssertNil(unknown.completionQuotaRemainingPercent)
    }
}
