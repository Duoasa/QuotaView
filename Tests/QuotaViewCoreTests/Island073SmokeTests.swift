import AppKit
import Foundation
import SwiftUI
import XCTest
@testable import QuotaView
@testable import QuotaViewCore

final class Island073SmokeTests: XCTestCase {
    @MainActor
    func testCompletedGlowStaysAttachedAcrossScrollAndRelayout() throws {
        _ = NSApplication.shared
        let model = IslandLiveStore(); start(model, "a", "one", at: Date())
        model.receive(json("turn/completed", ["threadId": "a", "turn": ["id": "one", "status": "completed"]]))
        let render = model.display(english: false, remaining: nil, enabled: true, privacy: false).state.tasks[0].renderState
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 400), styleMask: .borderless, backing: .buffered, defer: false)
        let island = IslandNotchSurface(state: IslandBoardState()); window.contentView = island
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 40, width: 680, height: 240)); island.addSubview(scroll)
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 680, height: 700)); scroll.documentView = document
        scroll.contentView.postsBoundsChangedNotifications = true
        let host = IslandQuantumProgressHost(frame: NSRect(x: 20, y: 180, width: 640, height: 60)); document.addSubview(host)
        host.configure(renderState: render, visible: true, reduceMotion: false); host.layoutSubtreeIfNeeded()
        XCTAssertTrue(host.glowIsAttachedToCard)
        XCTAssertTrue(host.glowFrameInWindow.contains(host.convert(host.bounds, to: nil)))
        let before = host.glowFrameInWindow
        scroll.contentView.setBoundsOrigin(NSPoint(x: 0, y: 50))
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        XCTAssertEqual(abs(host.glowFrameInWindow.minY - before.minY), 50, accuracy: 0.01)
        host.frame.origin.y += 90
        XCTAssertTrue(host.glowFrameInWindow.contains(host.convert(host.bounds, to: nil)))
        host.stop(); XCTAssertTrue(host.glowIsAttachedToCard)
        XCTAssertNil(host.completionPulse)
    }
    @MainActor
    func testCompletedGlowUsesThreeSecondFullDarkCycle() throws {
        _ = NSApplication.shared
        let model = IslandLiveStore(); start(model, "a", "one", at: Date())
        model.receive(json("turn/completed", ["threadId": "a", "turn": ["id": "one", "status": "completed"]]))
        let render = model.display(english: false, remaining: nil, enabled: true, privacy: false).state.tasks[0].renderState
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 60), styleMask: .borderless, backing: .buffered, defer: false)
        let host = IslandQuantumProgressHost(frame: .zero); window.contentView = host
        host.configure(renderState: render, visible: true, reduceMotion: false)
        let pulse = try XCTUnwrap(host.completionPulse)
        XCTAssertNil(host.completionOutlinePulse, "Completion outline stays steady while outer glow breathes")
        XCTAssertEqual(pulse.duration, 3)
        let opacity = try XCTUnwrap(pulse.animations?.first as? CAKeyframeAnimation)
        XCTAssertEqual((opacity.values as? [NSNumber])?.map(\.doubleValue), [0, 0, 1, 0, 0])
        host.configure(renderState: render, visible: true, reduceMotion: true)
        XCTAssertNil(host.completionPulse)
        host.configure(renderState: render, visible: true, reduceMotion: false)
        host.stop(); XCTAssertNil(host.completionPulse)
    }
    @MainActor
    func testReferenceShimmerKeepsFixedBandAndStopsForReducedMotion() throws {
        _ = NSApplication.shared
        for width: CGFloat in [40, 500] {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 20), styleMask: .borderless, backing: .buffered, defer: false)
            let text = IslandScrollingTextHost(frame: NSRect(x: 0, y: 0, width: width, height: 20)); window.contentView = text
            text.configure(text: "Thinking about the next step", font: .systemFont(ofSize: 11), color: IslandTextPalette.detail, visible: true, reduceMotion: false, shimmer: true)
            let animation = try XCTUnwrap(text.shimmerAnimation)
            let first = try XCTUnwrap((animation.values as? [[NSNumber]])?.first)
            XCTAssertEqual((first.last!.doubleValue - first.first!.doubleValue) * Double(width), 85, accuracy: 0.01)
            XCTAssertEqual(animation.duration, 4)
            XCTAssertTrue(text.shimmerColorAlphas.allSatisfy { $0 == 1 })
            text.configure(text: "Thinking", font: .systemFont(ofSize: 11), color: IslandTextPalette.detail, visible: true, reduceMotion: true, shimmer: true)
            XCTAssertNil(text.shimmerAnimation)
        }
    }
    func testWeeklyQuotaSegmentsPreservePartialFill() {
        let values = IslandQuotaSegments.fractions(remaining: 59)
        XCTAssertEqual(values[0], 1)
        XCTAssertEqual(values[1], 0.77, accuracy: 0.0001)
        XCTAssertEqual(values[2], 0)
        for percent in 0...100 {
            XCTAssertEqual(IslandQuotaSegments.fractions(remaining: percent).reduce(0, +) / 3, CGFloat(percent) / 100, accuracy: 0.0001)
        }
        XCTAssertEqual(IslandQuotaSegments.fractions(remaining: nil), [0, 0, 0])
    }
    @MainActor
    func testCompletedCardKeepsOrbPlaybackAndStopsWhenHidden() throws {
        _ = NSApplication.shared
        let model = IslandLiveStore(); start(model, "a", "one", at: Date())
        model.receive(json("turn/completed", ["threadId": "a", "turn": ["id": "one", "status": "completed"]]))
        let display = model.display(english: false, remaining: nil, enabled: true, privacy: false)
        let task = try XCTUnwrap(display.state.tasks.first)
        XCTAssertTrue(task.playbackEnabled)
        XCTAssertEqual(task.renderState.visualState, .completed)
        XCTAssertFalse(IslandBoardState.isRunning(task), "Visual playback must not change task status/counts")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 80, height: 80), styleMask: .borderless, backing: .buffered, defer: false)
        let orb = IslandActivityOrbHost(state: .completed)
        window.contentView = orb
        orb.configure(state: .completed, playback: task.playbackEnabled)
        XCTAssertTrue(orb.playbackActive)
        orb.configure(state: .completed, playback: false)
        XCTAssertFalse(orb.playbackActive)
        orb.configure(state: .completed, playback: true)
        window.contentView = nil
        XCTAssertFalse(orb.playbackActive)
    }
    @MainActor
    func testDelayedRolloutCompletionSurvivesNewerSocketReceiptTime() throws {
        let model = IslandLiveStore(); let date = Date(timeIntervalSince1970: 1000)
        let session = CodexActivityPrivacy.hashIdentifier("a"), turn = CodexActivityPrivacy.hashIdentifier("one")
        start(model, "a", "one", at: date)
        model.receiveLegacy(.init(event: .userPromptSubmit, sessionHash: session, turnHash: turn,
            sessionKind: .user, source: .localRollout, occurredAt: date))
        model.receive(json("item/completed", ["threadId": "a", "turnId": "one",
            "item": ["id": "final", "type": "agentMessage", "text": "Done"]]), at: date.addingTimeInterval(12))
        model.receiveLegacy(.init(event: .stop, sessionHash: session, turnHash: turn,
            sessionKind: .user, source: .localRollout, turnCompletionStatus: .completed,
            occurredAt: date.addingTimeInterval(10)))
        XCTAssertEqual(model.tasks[0].status, .completed)
        XCTAssertEqual(model.tasks[0].endedAt, date.addingTimeInterval(10))
        let display = model.display(english: false, remaining: nil, enabled: true, privacy: false)
        XCTAssertEqual(display.state.tasks[0].renderState.visualState, .completed)
        XCTAssertEqual(display.state.tasks[0].renderState.approximateProgressFraction, 1)
        model.receive(json("item/completed", ["threadId": "a", "turnId": "one",
            "item": ["id": "late", "type": "agentMessage", "text": "Late"]]), at: date.addingTimeInterval(13))
        XCTAssertEqual(model.tasks[0].status, .completed)
        start(model, "a", "two", at: date.addingTimeInterval(20))
        model.receiveLegacy(.init(event: .stop, sessionHash: session, turnHash: turn,
            sessionKind: .user, source: .localRollout, turnCompletionStatus: .completed,
            occurredAt: date.addingTimeInterval(10)))
        XCTAssertEqual(model.tasks[0].status, .thinking)
    }

    @MainActor
    func testMissingPlanReusesSingleIslandProgressResolver() throws {
        let model = IslandLiveStore(); let date = Date(timeIntervalSince1970: 1000)
        start(model, "a", "one", at: date); start(model, "b", "other", at: date)
        func display(_ seconds: Double) -> CodexMultitaskDisplay {
            model.display(english: false, remaining: nil, enabled: true, privacy: false, at: date.addingTimeInterval(seconds))
        }
        XCTAssertNil(model.tasks[0].progress)
        XCTAssertEqual(display(0).state.tasks[0].renderState.approximateProgressFraction, 0.01)
        XCTAssertEqual(display(3).state.tasks[0].renderState.approximateProgressFraction, 0.01)
        let before = try XCTUnwrap(display(20).state.tasks[0].renderState.approximateProgressFraction)
        XCTAssertGreaterThan(before, 0.4); XCTAssertLessThanOrEqual(before, 0.5)
        model.select(model.tasks[1].id)
        let away = try XCTUnwrap(display(30).state.tasks[0].renderState.approximateProgressFraction)
        model.select(model.tasks[0].id)
        let restored = display(30).state.tasks[0].renderState
        XCTAssertGreaterThanOrEqual(away, before)
        XCTAssertEqual(restored.approximateProgressFraction, away)
        // Recreating the selected NSView must not replay its fill from zero.
        for _ in 0..<2 {
            let host = IslandQuantumProgressHost(frame: NSRect(x: 0, y: 0, width: 600, height: 60))
            host.configure(renderState: restored, visible: false, reduceMotion: false)
            if host.effectAvailable { XCTAssertEqual(try XCTUnwrap(host.progressPosition), Float(away), accuracy: 0.001) }
        }
        model.receive(json("turn/plan/updated", ["threadId": "a", "turnId": "one",
            "plan": [["step": "First", "status": "inProgress"], ["step": "Second", "status": "pending"]]]), at: date.addingTimeInterval(31))
        XCTAssertEqual(try XCTUnwrap(model.tasks[0].progress), 0.05, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(display(31).state.tasks[0].renderState.approximateProgressFraction), away)
        start(model, "a", "two", at: date.addingTimeInterval(32))
        XCTAssertNil(model.tasks[0].progress)
        XCTAssertEqual(display(32).state.tasks[0].renderState.approximateProgressFraction, 0.01)
    }

    @MainActor
    func testOnlyExplicitPinKeepsExpansionPinned() {
        let model = IslandLiveStore(); start(model, "a", "one", at: Date())
        let board = IslandBoardState()
        board.update(model.display(english: false, remaining: nil, enabled: true, privacy: false), reduceMotion: true)
        board.preview(); board.select(model.tasks[0].id)
        XCTAssertEqual(board.presentation, .preview)
        board.endPreview(); XCTAssertTrue(board.compact)
        board.toggleCompact(); XCTAssertEqual(board.presentation, .preview)
        board.pin(); board.select(model.tasks[0].id); board.endPreview(); board.dismissFromOutside()
        XCTAssertEqual(board.presentation, .pinned)
        board.collapse(); board.preview(); board.dismissFromOutside()
        XCTAssertTrue(board.compact)
    }
    private func json(_ method: String, _ params: [String: Any], id: Any? = nil) -> Data {
        var value: [String: Any] = ["method": method, "params": params]
        if let id { value["id"] = id }
        return try! JSONSerialization.data(withJSONObject: value)
    }
    @MainActor
    private func start(_ model: IslandLiveStore, _ thread: String, _ turn: String, at date: Date) {
        model.receive(json("turn/started", ["threadId": thread, "turn": ["id": turn], "startedAtMs": date.timeIntervalSince1970 * 1000]), at: date)
    }
    func testNumericServerRequestIsForwardedAndPrivateItemsAreExcluded() async throws {
        actor Capture {
            var messages: [Data] = []
            func append(_ data: Data) { messages.append(data) }
            func count() -> Int { messages.count }
        }
        let capture = Capture(); let client = CodexSharedAppServerActivityClient()
        await client.setPublicMessageHandler { await capture.append($0) }
        try await client.handleJSONMessage(json("thread/started", ["thread": ["id": "a", "source": "cli", "status": ["type": "idle"]]]))
        try await client.handleJSONMessage(json("item/commandExecution/requestApproval", ["threadId": "a", "availableDecisions": ["accept", "decline"]], id: 1))
        let before = await capture.count(); XCTAssertEqual(before, 2)
        try await client.handleJSONMessage(json("item/started", ["threadId": "a", "item": ["id": "private", "type": "reasoning"]]))
        try await client.handleJSONMessage(json("item/reasoning/textDelta", ["threadId": "a", "delta": "private"]))
        let after = await capture.count(); XCTAssertEqual(after, before)
    }
    @MainActor
    func testActiveSnapshotUsesLocalIdentityAndPublicFallbackWithoutResurrection() throws {
        let model = IslandLiveStore(); let date = Date()
        model.setConnection(.connected)
        model.receive(json("thread/snapshot", ["thread": ["id": "a", "source": "cli", "status": ["type": "active"], "name": "Real task"]]))
        let hash = CodexActivityPrivacy.hashIdentifier("a"), turn = CodexActivityPrivacy.hashIdentifier("one")
        model.receiveLegacy(.init(event: .userPromptSubmit, sessionHash: hash, turnHash: turn, sessionKind: .user, source: .localRollout, occurredAt: date))
        XCTAssertEqual(model.tasks[0].turnKey, turn)
        let line = try JSONSerialization.data(withJSONObject: ["type": "response_item", "payload": ["type": "message", "role": "assistant", "channel": "commentary", "content": [["type": "output_text", "text": "Public fallback"]]]])
        let content = try XCTUnwrap(CodexLocalPublicContent.decode(line, sessionHash: hash, activeTurnHash: turn))
        model.receiveLocalContent(content); XCTAssertEqual(model.tasks[0].entries.first?.text.chinese, "Public fallback")
        model.receiveLegacy(.init(event: .stop, sessionHash: hash, turnHash: turn, sessionKind: .user, source: .localRollout, turnCompletionStatus: .completed, occurredAt: date.addingTimeInterval(1)))
        XCTAssertEqual(model.tasks[0].status, .completed)
        model.receiveLegacy(.init(event: .preToolUse, sessionHash: hash, turnHash: turn, sessionKind: .user, source: .localRollout, occurredAt: date.addingTimeInterval(2)))
        XCTAssertEqual(model.tasks[0].status, .completed)
    }
    @MainActor
    func testStableOrderTerminalGuardAndUnknownValues() throws {
        let model = IslandLiveStore(); let date = Date(timeIntervalSince1970: 1000)
        start(model, "a", "one", at: date); start(model, "b", "two", at: date)
        let first = model.tasks[0].id; model.select(first)
        model.receive(json("turn/completed", ["threadId": "a", "turn": ["id": "one", "status": "completed"]]), at: date.addingTimeInterval(10))
        start(model, "a", "one", at: date.addingTimeInterval(11))
        XCTAssertEqual(model.tasks[0].status, .completed)
        start(model, "a", "next", at: date.addingTimeInterval(12))
        model.receive(json("item/started", ["threadId": "a", "turnId": "one", "item": ["id": "old", "type": "commandExecution", "command": "old"]]))
        XCTAssertEqual(model.tasks[0].status, .thinking)
        XCTAssertEqual(model.tasks.map(\.threadID), ["a", "b"]); XCTAssertEqual(model.selectedID, first)
        let display = model.display(english: false, remaining: nil, enabled: true, privacy: false, at: date.addingTimeInterval(80))
        XCTAssertNil(display.totalTokens); XCTAssertNil(display.state.tasks[0].renderState.tokenUsageTitle)
        XCTAssertEqual(display.sessionMetadata[first]?.elapsedSeconds, 68)
        XCTAssertEqual(display.sessionMetadata[first]?.modelTitle, "模型未知")
    }
    @MainActor
    func testRequestQueuePreservesDraftAndExpiresAtResolution() throws {
        let model = IslandLiveStore(); let date = Date()
        start(model, "a", "one", at: date)
        let params: [String: Any] = ["threadId": "a", "turnId": "one", "itemId": "tool", "command": "swift build", "availableDecisions": ["accept", "decline", "cancel"]]
        model.receive(json("item/commandExecution/requestApproval", params, id: 1))
        let original = try XCTUnwrap(model.tasks[0].requests.first?.value)
        model.receive(json("item/commandExecution/requestApproval", params, id: 1))
        XCTAssertEqual(model.tasks[0].requests.count, 1); XCTAssertFalse(original.canRespond)
        model.receive(json("item/commandExecution/requestApproval", params, id: "1"))
        XCTAssertEqual(model.tasks[0].requests.count, 2, "String and numeric RPC IDs are distinct")
        let board = IslandBoardState(); let first = model.tasks[0].id
        func update() { board.update(model.display(english: false, remaining: nil, enabled: true, privacy: false), reduceMotion: true) }
        update(); var draft = IslandApprovalDraft(); draft.values["answer"] = "preserved"
        board.approvalDraftBinding(for: original.id).wrappedValue = draft
        model.nextRequest(first); update(); model.nextRequest(first); update()
        XCTAssertEqual(board.approvalDraftBinding(for: original.id).wrappedValue.values["answer"], "preserved")
        model.receive(json("serverRequest/resolved", ["threadId": "a", "requestId": 1]))
        update(); XCTAssertTrue(board.approvalDraftBinding(for: original.id).wrappedValue.values.isEmpty)
        XCTAssertEqual(model.tasks[0].requests.count, 1)
        start(model, "a", "next", at: date.addingTimeInterval(1))
        model.receive(json("item/commandExecution/requestApproval", params, id: 99))
        XCTAssertTrue(model.tasks[0].requests.isEmpty, "Previous turn cannot install an approval on a newer turn")
    }
    @MainActor
    func testTenTypedRequestsReachPresentationAndAdaptiveContent() throws {
        _ = NSApplication.shared
        for (name, _) in IslandApprovalFixtures.names {
            let model = IslandLiveStore(); let wire = try IslandApprovalFixtures.request(name)
            model.receive(wire.raw)
            let display = model.display(english: false, remaining: nil, enabled: true, privacy: false)
            let task = try XCTUnwrap(display.state.tasks.first)
            let request = try XCTUnwrap(display.taskDetails[task.id]?.confirmation)
            XCTAssertEqual(request.protocolRequest?.kind, wire.kind, name)
            XCTAssertFalse(request.canRespond, name)
            let width: CGFloat = 610
            let metrics = IslandApprovalMetrics(request: request, width: width, english: false, maximumViewportHeight: 300)
            XCTAssertLessThanOrEqual(metrics.viewportHeight, 300)
            let view = IslandApprovalView(task: task, metadata: display.sessionMetadata[task.id], request: request, metrics: metrics,
                english: false, visible: false, playbackEnabled: false, reduceMotion: true, scrollLink: .init(), draft: .constant(.init()), onDecision: { _, _ in })
            let host = NSHostingView(rootView: view.requestContent.frame(width: width).fixedSize(horizontal: false, vertical: true))
            host.layoutSubtreeIfNeeded()
            XCTAssertEqual(host.fittingSize.height, metrics.contentHeight - IslandVibeLayout.rowSpacing, accuracy: 3, name)
        }
        let missing = try IslandCodexApprovalRequest(data: json("item/commandExecution/requestApproval", ["threadId": "a", "command": "build"], id: 42))
        XCTAssertTrue(missing.actions.isEmpty, "No invented choices when the source omits availableDecisions")
    }
    @MainActor
    func testNonblockingQuestionAndFailedToolDoNotEndTurn() throws {
        let model = IslandLiveStore(); start(model, "a", "one", at: Date())
        model.receive(json("item/tool/requestUserInput", ["threadId": "a", "turnId": "one", "questions": [["id": "q", "question": "Choose", "options": [["label": "A", "description": "A"]]]]], id: 3))
        XCTAssertEqual(model.tasks[0].status, .thinking)
        model.receive(json("item/started", ["threadId": "a", "turnId": "one", "item": ["id": "tool", "type": "commandExecution", "command": "false"]]))
        model.receive(json("item/completed", ["threadId": "a", "turnId": "one", "item": ["id": "tool", "type": "commandExecution", "command": "false", "status": "failed", "exitCode": 1]]))
        XCTAssertEqual(model.tasks[0].status, .thinking); XCTAssertEqual(model.tasks[0].entries.last?.kind, .failure)
        XCTAssertTrue(model.display(english: false, remaining: nil, enabled: true, privacy: false).state.tasks[0].hasPendingRequest)
        model.receive(json("thread/status/changed", ["threadId": "a", "status": ["type": "active", "activeFlags": ["waitingOnUserInput"]]]))
        XCTAssertEqual(model.tasks[0].status, .waiting)
    }
    @MainActor
    func testLocalContentCannotActivateHistoricalTaskOrExposeReasoning() throws {
        let hash = CodexActivityPrivacy.hashIdentifier("a"); let turn = CodexActivityPrivacy.hashIdentifier("one")
        func line(_ type: String, _ payload: [String: Any]) -> Data {
            try! JSONSerialization.data(withJSONObject: ["type": type, "payload": payload, "timestamp": "2026-09-30T00:00:00Z"])
        }
        XCTAssertNil(CodexLocalPublicContent.decode(line("response_item", ["type": "reasoning", "summary": "private"]), sessionHash: hash, activeTurnHash: turn))
        XCTAssertNil(CodexLocalPublicContent.decode(line("response_item", ["type": "message", "role": "assistant", "channel": "analysis", "content": [["type": "output_text", "text": "private"]]]), sessionHash: hash, activeTurnHash: turn))
        let content = try XCTUnwrap(CodexLocalPublicContent.decode(line("response_item", ["type": "message", "role": "assistant", "channel": "commentary", "content": [["type": "output_text", "text": "Reading the requested source"]]]), sessionHash: hash, activeTurnHash: turn))
        let model = IslandLiveStore(); model.receiveLocalContent(content)
        XCTAssertTrue(model.tasks.isEmpty)
        model.receiveLegacy(.init(event: .userPromptSubmit, sessionHash: hash, turnHash: turn, sessionKind: .user, source: .localRollout, occurredAt: Date()))
        XCTAssertEqual(model.tasks[0].entries.first?.text.chinese, "Reading the requested source")
        let privateDisplay = model.display(english: false, remaining: nil, enabled: true, privacy: true)
        XCTAssertTrue(privateDisplay.taskDetails[model.tasks[0].id]!.entries.isEmpty)
        XCTAssertEqual(privateDisplay.state.tasks[0].title, "Codex 任务")
    }
    @MainActor
    func testLongModelRowsUseExactVisibilityAndCacheIsBounded() throws {
        let metadata = IslandSessionMetadata(modelName: String(repeating: "Unrecognized-Model-", count: 20), reasoningEffort: "Ultra", elapsedSeconds: nil)
        let height = metadata.cardHeight(width: 600); XCTAssertGreaterThan(height, 60)
        let layout = IslandTaskListLayout(taskIDs: [1, 2], detailID: nil, rowHeights: [1: height])
        XCTAssertEqual(layout.visibleElements(offset: 0, viewport: 59), [.task(1)])
        let model = IslandLiveStore(); start(model, "a", "one", at: Date())
        for i in 0..<220 {
            model.receive(json("item/completed", ["threadId": "a", "turnId": "one", "item": ["id": "m\(i)", "type": "agentMessage", "text": String(repeating: "x", count: 16000)]]))
        }
        XCTAssertLessThanOrEqual(model.tasks[0].entries.count, 200)
        XCTAssertLessThanOrEqual(model.tasks[0].entries.reduce(0) { $0 + $1.text.chinese.utf8.count }, 2_097_152)
        XCTAssertGreaterThan(model.tasks[0].removedEntryCount, 0)
    }
    @MainActor
    func testPresentationBenchmarkWith128Tasks() throws {
        let model = IslandLiveStore(); let date = Date()
        for i in 0..<128 { start(model, "task-\(i)", "turn-\(i)", at: date) }
        let board = IslandBoardState(); board.setGeometry(.init(frame: CGRect(x: 0, y: 0, width: 1440, height: 900)))
        var samples: [Double] = []
        for _ in 0..<120 {
            let begin = CFAbsoluteTimeGetCurrent()
            board.update(model.display(english: false, remaining: nil, enabled: true, privacy: false), reduceMotion: true)
            _ = board.rowHeights; _ = board.listHeight
            _ = IslandTaskListLayout(taskIDs: model.tasks.map(\.id), detailID: nil, rowHeights: board.rowHeights).visibleElements(offset: 1200, viewport: board.listHeight)
            samples.append((CFAbsoluteTimeGetCurrent() - begin) * 1000)
        }
        samples.sort(); print("ISLAND073_PRESENTATION_P95_MS=\(samples[114]) MAX_MS=\(samples.last!)")
        XCTAssertTrue(board.showsScrollRail); XCTAssertLessThanOrEqual(board.listHeight, board.geometry.maximumExpandedHeight)
    }
}
