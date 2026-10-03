import AppKit
import XCTest
@testable import QuotaView

final class IslandScrollRestorationSmokeTests: XCTestCase {
    @MainActor
    private final class FlippedDocument: NSView {
        override var isFlipped: Bool { true }
    }

    @MainActor
    private final class Fixture {
        let scroll: NSScrollView
        let document: FlippedDocument
        let probe = IslandTaskScrollProbe(frame: .zero)
        let link: IslandTaskScrollLink
        var visibility: [IslandListVisibility] = []

        init(layout: IslandTaskListLayout, viewport: CGFloat, offset: CGFloat, link: IslandTaskScrollLink? = nil) {
            _ = NSApplication.shared
            self.link = link ?? IslandTaskScrollLink()
            scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 680, height: viewport))
            scroll.borderType = .noBorder
            scroll.hasVerticalScroller = false
            scroll.hasHorizontalScroller = false
            scroll.contentInsets = .init()
            document = FlippedDocument(frame: NSRect(x: 0, y: 0, width: 680, height: layout.contentHeight))
            scroll.documentView = document
            document.addSubview(probe)
            scroll.tile()
            configure(layout, viewport: viewport)
            move(to: offset)
        }

        var offset: CGFloat { scroll.contentView.bounds.minY }

        func configure(_ layout: IslandTaskListLayout, viewport: CGFloat) {
            probe.configure(layout: layout, active: true, onVisibilityChange: { [weak self] in self?.visibility.append($0) },
                link: link, viewportHeight: viewport)
        }

        func resizeDocument(_ layout: IslandTaskListLayout) {
            document.setFrameSize(NSSize(width: 680, height: layout.contentHeight))
        }

        func resizeViewport(_ height: CGFloat) {
            scroll.setFrameSize(NSSize(width: 680, height: height))
            scroll.tile()
        }

        func move(to offset: CGFloat) {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: offset))
            scroll.reflectScrolledClipView(scroll.contentView)
        }

        func finishLayout() {
            scroll.layoutSubtreeIfNeeded()
            probe.layout()
            // Native position is corrected during layout. Drain only transaction
            // cleanup and visibility delivery, without driving application UI.
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        }
    }

    private var collapsed: IslandTaskListLayout {
        .init(taskIDs: [1, 2, 3, 4, 5], detailID: nil)
    }

    private var expanded: IslandTaskListLayout {
        .init(taskIDs: [1, 2, 3, 4, 5], detailID: 5, detailHeight: 100)
    }

    @MainActor
    func testOpeningLowerTaskDetailPreservesViewportWithoutAutomaticSelectionScroll() {
        XCTAssertEqual(collapsed.contentHeight, 356)
        XCTAssertEqual(expanded.contentHeight, 464)
        let fixture = Fixture(layout: collapsed, viewport: 288, offset: 68)
        fixture.link.prepareLayoutChange()
        fixture.configure(expanded, viewport: 396)
        fixture.resizeDocument(expanded)
        fixture.resizeViewport(396)
        fixture.finishLayout()
        XCTAssertEqual(fixture.offset, 68, accuracy: 0.01,
            "Opening an inline detail must not move the selected card to the top")
    }

    @MainActor
    func testClosingLowerTaskRestoresAfterDocumentShrinksBeforeViewport() {
        let fixture = Fixture(layout: expanded, viewport: 396, offset: 68)
        fixture.probe.prepareLayoutChange()
        fixture.configure(collapsed, viewport: 288)
        fixture.resizeDocument(collapsed)
        // Reproduce AppKit's temporary clamp while the old 396 pt viewport
        // is taller than the new 356 pt document.
        fixture.move(to: 0)
        fixture.probe.layout()
        XCTAssertEqual(fixture.offset, 0, accuracy: 0.01,
            "Restoration must wait until both native dimensions reach the target")
        fixture.resizeViewport(288)
        fixture.finishLayout()
        fixture.configure(collapsed, viewport: 288)
        XCTAssertEqual(fixture.offset, 68, accuracy: 0.01,
            "The temporary zero-range clamp must not erase the user's lower-list position")
    }

    @MainActor
    func testClosingLowerTaskAlsoPreservesOffsetWhenViewportShrinksFirst() {
        let fixture = Fixture(layout: expanded, viewport: 396, offset: 68)
        fixture.link.prepareLayoutChange()
        fixture.configure(collapsed, viewport: 288)
        fixture.resizeViewport(288)
        fixture.probe.layout()
        fixture.resizeDocument(collapsed)
        fixture.finishLayout()
        XCTAssertEqual(fixture.offset, 68, accuracy: 0.01)
    }

    @MainActor
    func testSettledRestorationRunsOnceAndDoesNotEnforceOffsetOnRefresh() {
        let fixture = Fixture(layout: expanded, viewport: 396, offset: 68)
        fixture.link.prepareLayoutChange()
        fixture.configure(collapsed, viewport: 288)
        fixture.resizeDocument(collapsed)
        fixture.move(to: 0)
        fixture.resizeViewport(288)
        fixture.finishLayout()
        XCTAssertEqual(fixture.offset, 68, accuracy: 0.01)
        fixture.move(to: 24)
        for _ in 0..<3 {
            fixture.configure(collapsed, viewport: 288)
            fixture.finishLayout()
        }
        XCTAssertEqual(fixture.offset, 24, accuracy: 0.01,
            "Regular refreshes must not reapply an already consumed checkpoint")
    }

    @MainActor
    func testNativeGestureStartCancelsPendingRestoration() {
        let fixture = Fixture(layout: expanded, viewport: 396, offset: 68)
        fixture.link.prepareLayoutChange()
        fixture.configure(collapsed, viewport: 288)
        fixture.resizeDocument(collapsed)
        fixture.move(to: 0)
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: fixture.scroll)
        fixture.resizeViewport(288)
        fixture.finishLayout()
        XCTAssertEqual(fixture.offset, 0, accuracy: 0.01,
            "A new native gesture owns the viewport even before final layout")
    }

    @MainActor
    func testLegacyMouseLiveScrollCancelsWithoutGestureStartNotification() {
        let fixture = Fixture(layout: expanded, viewport: 396, offset: 68)
        fixture.link.prepareLayoutChange()
        fixture.configure(collapsed, viewport: 288)
        fixture.resizeViewport(288)
        fixture.move(to: 30)
        NotificationCenter.default.post(name: NSScrollView.didLiveScrollNotification, object: fixture.scroll)
        fixture.resizeDocument(collapsed)
        fixture.finishLayout()
        XCTAssertEqual(fixture.offset, 30, accuracy: 0.01,
            "Legacy mouse scrolling may have no willStart/didEnd pair")
    }

    @MainActor
    func testGestureCancelsPendingLayoutCommitBeforeItFinishes() {
        let fixture = Fixture(layout: expanded, viewport: 396, offset: 68)
        fixture.link.prepareLayoutChange()
        fixture.configure(collapsed, viewport: 288)
        fixture.resizeDocument(collapsed)
        fixture.move(to: 0)
        fixture.resizeViewport(288)
        fixture.configure(collapsed, viewport: 288)
        // Geometry is corrected synchronously, but the transaction remains open
        // until its final commit. New input revokes the checkpoint immediately.
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: fixture.scroll)
        fixture.move(to: 20)
        fixture.finishLayout()
        XCTAssertEqual(fixture.offset, 20, accuracy: 0.01,
            "Layout cleanup must never move the viewport after a newer user gesture")
    }

    @MainActor
    func testFinalLayoutRestoresBeforeNextMainQueueTurn() {
        let fixture = Fixture(layout: expanded, viewport: 396, offset: 68)
        fixture.link.prepareLayoutChange()
        fixture.configure(collapsed, viewport: 288)
        fixture.resizeDocument(collapsed)
        fixture.move(to: 0)
        fixture.resizeViewport(288)
        fixture.probe.layout()
        XCTAssertEqual(fixture.offset, 68, accuracy: 0.01,
            "A drawable final layout must not expose the temporary top position for one frame")
    }

    @MainActor
    func testDisplayCommitRepairsLateNativeClampBeforeDrawing() {
        let fixture = Fixture(layout: expanded, viewport: 396, offset: 68)
        fixture.link.prepareLayoutChange()
        fixture.configure(collapsed, viewport: 288)
        fixture.resizeDocument(collapsed)
        fixture.resizeViewport(288)
        fixture.probe.layout()
        fixture.move(to: 0) // Another clamp after the first final-size notification.
        fixture.link.finishLayoutChange()
        XCTAssertEqual(fixture.offset, 68, accuracy: 0.01)
        XCTAssertFalse(fixture.link.isChangingLayout)
        fixture.finishLayout()
        XCTAssertEqual(fixture.offset, 68, accuracy: 0.01)
    }

    @MainActor
    func testLegacyWheelOriginBeforeLiveNotificationRetainsUserPosition() {
        let fixture = Fixture(layout: expanded, viewport: 396, offset: 68)
        fixture.link.prepareLayoutChange()
        fixture.configure(collapsed, viewport: 288)
        fixture.resizeDocument(collapsed)
        fixture.resizeViewport(288)
        fixture.probe.layout()
        fixture.move(to: 30)
        XCTAssertEqual(fixture.offset, 30, accuracy: 0.01,
            "Bounds notification arrives before legacy didLiveScroll and must not undo input")
        NotificationCenter.default.post(name: NSScrollView.didLiveScrollNotification, object: fixture.scroll)
        fixture.link.finishLayoutChange()
        fixture.finishLayout()
        XCTAssertEqual(fixture.offset, 30, accuracy: 0.01)
    }

    @MainActor
    func testTransientClampDoesNotPublishWrongVisibleRowsOrRailPosition() {
        let before = IslandTaskListLayout(taskIDs: Array(1...30), detailID: 30, detailHeight: 100)
        let after = IslandTaskListLayout(taskIDs: Array(1...30), detailID: nil)
        let fixture = Fixture(layout: before, viewport: 396, offset: 1_600)
        let rail = IslandTaskScrollRail(frame: NSRect(x: 0, y: 0, width: 14, height: 396))
        fixture.link.attach(rail)
        fixture.finishLayout()
        let committed = fixture.visibility
        let fraction = rail.doubleValue
        fixture.link.prepareLayoutChange()
        fixture.configure(after, viewport: 288)
        fixture.resizeDocument(after)
        fixture.move(to: 0)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        XCTAssertEqual(fixture.visibility, committed, "Temporary native geometry cannot remount upper cards")
        XCTAssertEqual(rail.doubleValue, fraction, accuracy: 0.001, "The rail must not flash at the top")
        fixture.resizeViewport(288)
        fixture.probe.layout()
        XCTAssertEqual(fixture.offset, 1_600, accuracy: 0.01)
        fixture.link.finishLayoutChange()
        fixture.finishLayout()
        XCTAssertEqual(fixture.visibility.last?.visible, after.visibleElements(offset: 1_600, viewport: 288))
    }

    @MainActor
    func testLongRemovedDetailPrewarmsFinalRowsBeforeVisibilityDelivery() {
        let before = IslandTaskListLayout(taskIDs: Array(1...20), detailID: 2, detailHeight: 900)
        let after = IslandTaskListLayout(taskIDs: Array(1...20), detailID: nil)
        let fixture = Fixture(layout: before, viewport: 200, offset: 600)
        fixture.finishLayout()
        XCTAssertFalse(fixture.visibility.last!.residentTaskIDs.contains(5))
        fixture.link.prepareLayoutChange()
        let residents = fixture.link.transitionResidents(layout: after, viewport: 200)
        XCTAssertTrue(residents.contains(5), "The new body must mount target rows before native drawing")
        XCTAssertEqual(fixture.visibility.last?.visible, before.visibleElements(offset: 600, viewport: 200),
            "Prewarming must not start playback for a region that is not yet visible")
        fixture.configure(after, viewport: 200)
        fixture.resizeDocument(after)
        fixture.link.finishLayoutChange()
        fixture.finishLayout()
        XCTAssertEqual(fixture.offset, 80, accuracy: 0.01)
        XCTAssertEqual(fixture.visibility.last?.residentTaskIDs, after.residentTaskIDs(offset: 80, viewport: 200))
    }

    @MainActor
    func testDetachingProbeCancelsOldLayoutCheckpoint() {
        let fixture = Fixture(layout: expanded, viewport: 396, offset: 68)
        fixture.link.prepareLayoutChange()
        fixture.configure(collapsed, viewport: 288)
        fixture.resizeDocument(collapsed)
        fixture.move(to: 0)
        fixture.probe.detach()
        XCTAssertFalse(fixture.probe.isAttached)
        fixture.resizeViewport(288)
        fixture.configure(collapsed, viewport: 288)
        fixture.finishLayout()
        XCTAssertEqual(fixture.offset, 0, accuracy: 0.01,
            "A later attachment must not resurrect a canceled checkpoint")
    }

    @MainActor
    func testEmptyAndNonoverflowingListsStayAtNativeZeroBoundary() {
        for layout in [IslandTaskListLayout(taskIDs: [], detailID: nil),
                       IslandTaskListLayout(taskIDs: [1, 2, 3], detailID: nil)] {
            let fixture = Fixture(layout: expanded, viewport: 396, offset: 68)
            fixture.link.prepareLayoutChange()
            fixture.configure(layout, viewport: 288)
            fixture.resizeDocument(layout)
            fixture.resizeViewport(288)
            fixture.finishLayout()
            XCTAssertEqual(fixture.offset, 0, accuracy: 0.01,
                "Restoration must obey the final native scroll range")
        }
    }

    @MainActor
    func testTaskAnchorMovesWithDetailAboveInsteadOfKeepingObsoletePixelOffset() {
        let before = IslandTaskListLayout(taskIDs: Array(1...10), detailID: 2, detailHeight: 100)
        let after = IslandTaskListLayout(taskIDs: Array(1...10), detailID: nil)
        // Row 5 starts at 392 before removal and 284 afterward. Keep the
        // same task and 10 pt within its row, rather than the old 402 pt.
        let fixture = Fixture(layout: before, viewport: 200, offset: 402)
        fixture.link.prepareLayoutChange()
        fixture.configure(after, viewport: 200)
        fixture.resizeDocument(after)
        fixture.finishLayout()
        XCTAssertEqual(fixture.offset, 294, accuracy: 0.01,
            "The task visible at the viewport edge must survive geometry changes above it")
    }

    @MainActor
    func testViewportInsideRemovedDetailReturnsToItsOwningTask() {
        let before = IslandTaskListLayout(taskIDs: Array(1...10), detailID: 2, detailHeight: 100)
        let after = IslandTaskListLayout(taskIDs: Array(1...10), detailID: nil)
        let fixture = Fixture(layout: before, viewport: 200, offset: 180)
        fixture.link.prepareLayoutChange()
        fixture.configure(after, viewport: 200)
        fixture.resizeDocument(after)
        fixture.finishLayout()
        XCTAssertEqual(fixture.offset, 80, accuracy: 0.01,
            "When the anchored detail disappears, show its owning card rather than an unrelated later task")
    }

    @MainActor
    func testIndependentRailInteractionCancelsPendingRestoration() {
        let fixture = Fixture(layout: expanded, viewport: 396, offset: 68)
        fixture.link.prepareLayoutChange()
        fixture.configure(collapsed, viewport: 288)
        fixture.resizeViewport(288)
        let rail = IslandTaskScrollRail(frame: NSRect(x: 0, y: 0, width: 14, height: 288))
        rail.doubleValue = 0.25
        fixture.probe.scrollFromRail(rail)
        XCTAssertEqual(fixture.offset, 44, accuracy: 0.01)
        fixture.resizeDocument(collapsed)
        fixture.finishLayout()
        XCTAssertEqual(fixture.offset, 44, accuracy: 0.01,
            "The independent rail must own the offset after interaction, just like a native gesture")
    }

    @MainActor
    func testBoardSelectionAndDismissalCaptureBeforePublishedGeometryChanges() throws {
        let model = IslandLiveStore()
        for index in 1...5 {
            let message = try JSONSerialization.data(withJSONObject: [
                "method": "turn/started",
                "params": ["threadId": "task-\(index)", "turn": ["id": "turn-\(index)"]]
            ])
            model.receive(message)
        }
        let board = IslandBoardState()
        board.update(model.display(english: false, remaining: nil, enabled: true, privacy: false), reduceMotion: true)
        board.pin()
        let ids = board.visibleTasks.map(\.id)
        let lowerID = try XCTUnwrap(ids.last)
        let before = IslandTaskListLayout(taskIDs: ids, detailID: nil, rowHeights: board.rowHeights)
        let viewport = board.listHeight
        let offset = before.contentHeight - viewport
        XCTAssertGreaterThan(offset, 0)
        let fixture = Fixture(layout: before, viewport: viewport, offset: offset, link: board.taskScrollLink)

        board.select(lowerID)
        XCTAssertEqual(board.inlineDetail?.id, lowerID)
        let opened = IslandTaskListLayout(taskIDs: ids, detailID: lowerID,
            detailHeight: board.detailHeight, rowHeights: board.rowHeights)
        fixture.configure(opened, viewport: board.listHeight)
        fixture.resizeDocument(opened)
        fixture.resizeViewport(board.listHeight)
        fixture.finishLayout()
        XCTAssertEqual(fixture.offset, offset, accuracy: 0.01)

        board.dismissDetail()
        XCTAssertNil(board.inlineDetail)
        fixture.configure(before, viewport: board.listHeight)
        fixture.resizeDocument(before)
        fixture.move(to: 0)
        fixture.resizeViewport(board.listHeight)
        fixture.finishLayout()
        XCTAssertEqual(fixture.offset, offset, accuracy: 0.01,
            "Board actions must checkpoint before SwiftUI can observe the new detail state")
    }
}
