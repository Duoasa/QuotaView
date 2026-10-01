import AppKit
import Foundation
import SwiftUI
import XCTest
@testable import QuotaView
@testable import QuotaViewCore

final class Island073SmokeTests: XCTestCase {
    @MainActor
    func testPrimaryIslandSettingsRoutesAndLocalization() {
        let pages = IslandSettingsPage.allCases
        XCTAssertEqual(Set(pages.map(\.id)), Set(["general", "island", "usage", "codexConnection", "proxy", "about"]),
            "Only settings for the current primary interface should be reachable")
        for language in [AppPreferences.Language.simplifiedChinese, .english] {
            let copy = AppCopy(language: language)
            XCTAssertEqual(Set(pages.map { $0.title(copy) }).count, pages.count)
            for page in pages {
                XCTAssertFalse(page.title(copy).isEmpty)
                XCTAssertFalse(page.subtitle(copy).isEmpty)
                XCTAssertNotNil(NSImage(systemSymbolName: page.symbol, accessibilityDescription: nil))
            }
        }
    }

    @MainActor
    func testPersistedUsageAndEffectChoicesReachPrimaryDisplay() throws {
        let suite = "QuotaView.SettingsSmoke.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        preferences.showUsageSummary = false; preferences.showSparkQuota = false
        preferences.showCreditBalance = false; preferences.showDailyTokens = false
        preferences.showThirtyDayTokens = false; preferences.showLifetimeTokens = false
        preferences.showEstimatedCost = false; preferences.showTokenActivity = false
        preferences.showResetAction = false
        preferences.codexActivityProgressEffect = .sloshFlow
        let restored = AppPreferences(defaults: defaults)
        let hidden = IslandUsageOptions(preferences: restored)
        XCTAssertTrue(hidden.quota && hidden.spark && hidden.credits && hidden.reset)
        XCTAssertTrue(hidden.dailyTokens && hidden.monthlyTokens && hidden.lifetimeTokens && hidden.hasTokenMetrics)
        XCTAssertFalse(hidden.cost || hidden.activity)
        XCTAssertFalse(restored.showUsageSummary || restored.showResetAction,
            "Legacy settings stay stored without hiding required primary-island data")
        XCTAssertEqual(restored.codexActivityProgressEffect, .sloshFlow)
        restored.showEstimatedCost = true; restored.showLifetimeTokens = true
        let changed = IslandUsageOptions(preferences: restored)
        XCTAssertTrue(changed.cost && changed.lifetimeTokens && changed.hasTokenMetrics)
        XCTAssertFalse(changed.activity)
        XCTAssertTrue(changed.dailyTokens && changed.monthlyTokens)
        let board = IslandBoardState()
        let model = IslandLiveStore()
        var display = model.display(english: false, remaining: nil, enabled: true, privacy: false)
        display.usageOptions = hidden; display.effect = restored.codexActivityProgressEffect
        board.update(display, reduceMotion: true); board.pin(); board.openUsage()
        display.usageOptions = changed
        board.update(display, reduceMotion: true)
        XCTAssertEqual(board.display?.usageOptions, changed)
        XCTAssertEqual(board.display?.effect, .sloshFlow)
        XCTAssertTrue(board.showsUsage)
        XCTAssertEqual(board.presentation, .pinned, "Preference changes must preserve the user's current page and pin")
    }

    @MainActor
    func testChromeFitsPhysicalNotchOnUsageResetAndRequests() {
        let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let board = IslandBoardState()
        board.setGeometry(.init(frame: frame, safeTop: 32,
            left: CGRect(x: 0, y: 950, width: 666, height: 32),
            right: CGRect(x: 846, y: 950, width: 666, height: 32)))
        board.pin(); board.openUsage()
        let utilityPair = IslandChromeMetrics.buttonSize * 2 + 8
        XCTAssertGreaterThanOrEqual(board.headerSideWidth, utilityPair)
        board.openReset()
        XCTAssertGreaterThanOrEqual(board.headerSideWidth, utilityPair,
            "The reset page must fit pin/collapse beside the physical camera")
        XCTAssertGreaterThanOrEqual(board.headerHeight, IslandChromeMetrics.buttonSize)
        XCTAssertEqual(IslandVibeLayout.footerHeight, IslandChromeMetrics.footerHeight)
        XCTAssertEqual(IslandApprovalMetrics.footerHeight, IslandChromeMetrics.footerHeight)
        board.updateResetHeight(430); board.updateUsageHeight(640)
        XCTAssertEqual(board.expandedHeight, board.headerHeight + board.resetHeight)
        board.closeReset()
        XCTAssertEqual(board.expandedHeight, board.headerHeight + board.usageHeight)
    }

    @MainActor
    func testPrimaryIslandRefreshCoalescesAcrossPagesAndPreservesNavigation() async {
        let board = IslandBoardState()
        board.pin(); board.openUsage()
        var opens = 0
        board.onOpenSettings = { opens += 1 }
        board.onOpenSettings?()
        XCTAssertEqual(opens, 1)
        XCTAssertTrue(board.showsUsage)
        XCTAssertEqual(board.presentation, .pinned)
        let started = expectation(description: "Refresh started")
        var finish: CheckedContinuation<Void, Never>?
        var refreshes = 0
        board.onRefreshUsage = {
            refreshes += 1
            await withCheckedContinuation { continuation in
                finish = continuation
                started.fulfill()
            }
        }
        let first = Task { await board.refreshUsage() }
        await fulfillment(of: [started], timeout: 1)
        XCTAssertTrue(board.isRefreshingUsage)
        board.openReset()
        await board.refreshUsage()
        XCTAssertEqual(refreshes, 1, "Changing pages cannot start a second concurrent usage request")
        finish?.resume()
        await first.value
        XCTAssertFalse(board.isRefreshingUsage)
        XCTAssertTrue(board.showsReset)
        XCTAssertEqual(board.presentation, .pinned)
        board.onRefreshUsage = nil
        await board.refreshUsage()
        XCTAssertFalse(board.isRefreshingUsage)
    }

    @MainActor
    func testCompactTextAlwaysIncludesStatusAndFallbackTask() {
        let model = IslandLiveStore(); start(model, "compact", "one", at: Date())
        let board = IslandBoardState()
        var display = model.display(english: false, remaining: nil, enabled: true, privacy: false)
        for state in CodexActivityVisualState.allCases {
            display.state.tasks = [.init(id: 1, renderState: .init(visualState: state,
                approximateProgressFraction: nil, windowTitle: "测试任务", statusTitle: "状态", operation: "",
                accessibilityLabel: "测试任务"))]
            display.state.selectedID = 1
            board.update(display, reduceMotion: true)
            XCTAssertEqual(board.compactTaskText, "状态 · 测试任务")
            display.state.tasks = [.init(id: 1, renderState: .init(visualState: state,
                approximateProgressFraction: nil, windowTitle: "Test task", statusTitle: "Status", operation: "Status · Public update",
                accessibilityLabel: "Test task"))]
            board.update(display, reduceMotion: true)
            XCTAssertEqual(board.compactTaskText, "Status · Public update")
        }
        display.state.tasks = []; board.update(display, reduceMotion: true)
        XCTAssertFalse(board.compactTaskText.isEmpty)
    }
    @MainActor
    func testAutomaticTaskPreviewAndPendingConfirmationLifetime() {
        let model = IslandLiveStore(); let board = IslandBoardState(); let date = Date()
        func update(_ time: Date = date, enabled: Bool = true) {
            board.update(model.display(english: false, remaining: nil, enabled: enabled, privacy: false), reduceMotion: true, now: time)
        }
        update()
        start(model, "auto", "one", at: date); update()
        XCTAssertFalse(board.compact)
        XCTAssertEqual(board.automaticPreviewDeadline, date.addingTimeInterval(3))
        board.endPreview(); XCTAssertFalse(board.compact)
        update(date.addingTimeInterval(1))
        XCTAssertEqual(board.automaticPreviewDeadline, date.addingTimeInterval(3))
        board.finishAutomaticPreview(at: date.addingTimeInterval(2.9)); XCTAssertFalse(board.compact)
        board.finishAutomaticPreview(at: date.addingTimeInterval(3)); XCTAssertTrue(board.compact)
        model.receive(json("item/commandExecution/requestApproval", ["threadId": "auto", "turnId": "one", "command": "swift build"], id: 1))
        update(); XCTAssertFalse(board.compact); XCTAssertNil(board.automaticPreviewDeadline)
        board.endPreview(); board.dismissFromOutside(); board.collapse()
        XCTAssertFalse(board.compact)
        model.receive(json("serverRequest/resolved", ["threadId": "auto", "requestId": 1]))
        update(); XCTAssertTrue(board.compact)
        model.receive(json("turn/completed", ["threadId": "auto", "turn": ["id": "one", "status": "completed"]]))
        update(); XCTAssertFalse(board.compact)
        board.finishAutomaticPreview(at: date.addingTimeInterval(3)); XCTAssertTrue(board.compact)
        update(); XCTAssertTrue(board.compact, "Repeated completion snapshots must not replay")
        let baseline = IslandBoardState()
        baseline.update(model.display(english: false, remaining: nil, enabled: true, privacy: false), reduceMotion: true)
        XCTAssertTrue(baseline.compact)
        board.pin(); start(model, "auto", "two", at: date.addingTimeInterval(4)); update()
        XCTAssertEqual(board.presentation, .pinned); XCTAssertNil(board.automaticPreviewDeadline)
        board.finishAutomaticPreview(at: date.addingTimeInterval(10)); board.dismissFromOutside()
        XCTAssertEqual(board.presentation, .pinned)
        update(enabled: false); XCTAssertTrue(board.compact); XCTAssertNil(board.automaticPreviewDeadline)
    }
    @MainActor
    func testAutomaticPopupPreferencesPersistAndClampDuration() throws {
        let suite = "QuotaView.PopupSmoke.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        XCTAssertTrue(preferences.codexActivityAutomaticPopupEnabled)
        XCTAssertEqual(preferences.codexActivityAutomaticPopupDuration, 3)
        preferences.codexActivityAutomaticPopupEnabled = false
        preferences.codexActivityAutomaticPopupDuration = 7
        let restored = AppPreferences(defaults: defaults)
        XCTAssertFalse(restored.codexActivityAutomaticPopupEnabled)
        XCTAssertEqual(restored.codexActivityAutomaticPopupDuration, 7)
        restored.codexActivityAutomaticPopupDuration = 0
        XCTAssertEqual(restored.codexActivityAutomaticPopupDuration, 1)
        restored.codexActivityAutomaticPopupDuration = 99
        XCTAssertEqual(restored.codexActivityAutomaticPopupDuration, 10)
        XCTAssertEqual(AppPreferences(defaults: defaults).codexActivityAutomaticPopupDuration, 10)
        defaults.set(-20, forKey: "preferences.codexActivity.automaticPopupDuration")
        XCTAssertEqual(AppPreferences(defaults: defaults).codexActivityAutomaticPopupDuration, 1)
    }

    @MainActor
    func testDisabledAutomaticPopupsKeepTaskAndRequestEventsManual() {
        let model = IslandLiveStore(); let board = IslandBoardState(); let date = Date()
        func update() {
            var display = model.display(english: false, remaining: nil, enabled: true, privacy: false)
            display.automaticPopupEnabled = false
            board.update(display, reduceMotion: true, now: date)
        }
        update()
        start(model, "manual", "one", at: date); update()
        XCTAssertTrue(board.compact)
        model.receive(json("turn/completed", ["threadId": "manual", "turn": ["id": "one", "status": "completed"]])); update()
        XCTAssertTrue(board.compact)
        start(model, "manual", "two", at: date)
        model.receive(json("item/commandExecution/requestApproval", ["threadId": "manual", "turnId": "two", "command": "swift build"], id: 1)); update()
        XCTAssertTrue(board.compact)
        XCTAssertEqual(board.attentionCount, 1)
        XCTAssertNil(board.automaticPreviewDeadline)
        board.preview(); board.endPreview(); board.dismissFromOutside(); update()
        XCTAssertFalse(board.compact, "A request the user opened stays visible while pending")
        XCTAssertEqual(board.attentionCount, 1)
        model.receive(json("serverRequest/resolved", ["threadId": "manual", "requestId": 1])); update()
        XCTAssertTrue(board.compact)
    }

    @MainActor
    func testPopupDurationAndPreferenceChangesPreserveManualPages() {
        let model = IslandLiveStore(); let board = IslandBoardState(); let date = Date()
        func update(_ now: Date = date, enabled: Bool = true) {
            var display = model.display(english: false, remaining: nil, enabled: true, privacy: false)
            display.automaticPopupEnabled = enabled; display.automaticPopupDuration = 7
            board.update(display, reduceMotion: true, now: now)
        }
        update(); start(model, "duration", "one", at: date); update()
        XCTAssertEqual(board.automaticPreviewDeadline, date.addingTimeInterval(7))
        update(date.addingTimeInterval(2))
        XCTAssertEqual(board.automaticPreviewDeadline, date.addingTimeInterval(7))
        board.finishAutomaticPreview(at: date.addingTimeInterval(6.9)); XCTAssertFalse(board.compact)
        board.finishAutomaticPreview(at: date.addingTimeInterval(7)); XCTAssertTrue(board.compact)
        start(model, "duration", "two", at: date); update()
        update(enabled: false)
        XCTAssertTrue(board.compact); XCTAssertNil(board.automaticPreviewDeadline)
        board.preview(); update(enabled: false)
        XCTAssertFalse(board.compact)
        board.openUsage(); update(enabled: false)
        XCTAssertTrue(board.showsUsage); XCTAssertFalse(board.compact)
        board.pin(); start(model, "duration", "three", at: date); update()
        XCTAssertEqual(board.presentation, .pinned)
        XCTAssertNil(board.automaticPreviewDeadline)
        update(enabled: false)
        XCTAssertEqual(board.presentation, .pinned)
        XCTAssertTrue(board.showsUsage)
    }

    @MainActor
    func testCompactEffectPreviewUsesConcentricCorners() {
        let outer = SettingsEffectPreviewMetrics.outerCornerRadius
        let inset = SettingsEffectPreviewMetrics.inset
        let inner = SettingsEffectPreviewMetrics.previewCornerRadius
        XCTAssertEqual(outer, inner + inset)
        XCTAssertLessThanOrEqual(SettingsEffectPreviewMetrics.height, 32)
        let host = CodexActivityStateSmokePreviewHostView(effect: .stateSmoke)
        host.frame = .init(x: 0, y: 0, width: 112, height: SettingsEffectPreviewMetrics.height)
        host.update(effect: .stateSmoke, reduceMotion: true, cornerRadius: inner)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.subviews.first?.layer?.cornerRadius, inner)
        XCTAssertTrue(host.subviews.first?.layer?.masksToBounds == true)
        XCTAssertNotNil(NSImage(systemSymbolName: "rectangle.portrait.and.arrow.right", accessibilityDescription: nil))
    }

    func testActivityHeatmapFitsWidthAndPreservesTotals() {
        let date = Date(timeIntervalSince1970: 1790812800)
        let activity = [DailyTokenActivity(date: date, tokens: 123)]
        let daily = IslandActivityHeatmap(activity: activity, endingAt: date, mode: .daily)
        let weekly = IslandActivityHeatmap(activity: activity, endingAt: date, mode: .weekly)
        XCTAssertEqual(daily.cells.count, 371)
        XCTAssertEqual(weekly.cells.count, 53)
        XCTAssertEqual(daily.cells.compactMap(\.tokens).reduce(0, +), 123)
        XCTAssertEqual(weekly.cells.compactMap(\.tokens).reduce(0, +), 123)
        for width: CGFloat in [400, 596, 720] {
            XCTAssertEqual(IslandActivityHeatmap.cellSize(width: width) * 53 + IslandActivityHeatmap.gap * 52, width, accuracy: 0.001)
        }
    }
    func testWeeklyAndCumulativeUseSevenStackedCells() {
        let day = Date(timeIntervalSince1970: 1790812800)
        let previousWeek = day.addingTimeInterval(-7 * 86400)
        let activity = [DailyTokenActivity(date: previousWeek, tokens: 100), DailyTokenActivity(date: day, tokens: 600)]
        let weekly = IslandActivityHeatmap(activity: activity, endingAt: day, mode: .weekly)
        let cumulative = IslandActivityHeatmap(activity: activity, endingAt: day, mode: .cumulative, lifetimeTokens: 900)
        XCTAssertEqual(weekly.rows, 7)
        XCTAssertEqual(cumulative.cells.count, 53)
        XCTAssertEqual(weekly.cells[51].tokens, 100)
        XCTAssertEqual(weekly.cells[52].tokens, 600)
        XCTAssertEqual((0..<7).filter { weekly.isFilled(column: 51, row: $0) }.count, 2)
        XCTAssertFalse(weekly.isFilled(column: 51, row: 0))
        XCTAssertTrue(weekly.isFilled(column: 51, row: 6))
        XCTAssertEqual(cumulative.cells[51].tokens, 300)
        XCTAssertEqual(cumulative.cells[52].tokens, 900)
        XCTAssertTrue((0..<7).allSatisfy { cumulative.isFilled(column: 52, row: $0) })
        XCTAssertEqual(weekly.cellIndex(column: 51, row: 0), weekly.cellIndex(column: 51, row: 6))
    }
    @MainActor
    func testIslandArchiveOnlyHidesDisplayAndPreservesRequests() throws {
        let model = IslandLiveStore(); let date = Date()
        start(model, "first", "one", at: date); start(model, "second", "one", at: date)
        let id = model.tasks[0].id; let next = model.tasks[1].id
        model.receive(json("item/commandExecution/requestApproval", ["threadId": "first", "turnId": "one", "command": "swift build"], id: 7))
        let request = try XCTUnwrap(model.tasks[0].requests.first?.value)
        model.select(id)
        let board = IslandBoardState(); board.pin()
        func refresh() { board.update(model.display(english: false, remaining: nil, enabled: true, privacy: false), reduceMotion: true) }
        model.onChange = { refresh() }; refresh(); board.select(id)
        XCTAssertEqual(board.detailID, id)
        model.archiveFromIsland(id)
        XCTAssertEqual(model.tasks.count, 2)
        XCTAssertEqual(model.tasks[0].status, .waiting)
        XCTAssertEqual(model.tasks[0].requests.first?.value, request)
        XCTAssertEqual(model.selectedID, next)
        XCTAssertEqual(board.tasks.map(\.id), [next])
        XCTAssertNil(board.detailID)
        XCTAssertEqual(board.attentionCount, 0)
        XCTAssertEqual(board.presentation, .pinned)
        model.receive(json("thread/status/changed", ["threadId": "first", "status": ["type": "active", "activeFlags": ["waitingOnApproval"]]]))
        XCTAssertEqual(board.tasks.map(\.id), [next])
        model.receive(json("serverRequest/resolved", ["threadId": "first", "requestId": 7]))
        XCTAssertTrue(model.tasks[0].requests.isEmpty)
        XCTAssertEqual(board.tasks.map(\.id), [next])
        model.archiveFromIsland(next)
        XCTAssertTrue(board.tasks.isEmpty)
        XCTAssertEqual(model.selectedID, 0)
        XCTAssertFalse(board.display!.state.allCompleted)
        XCTAssertTrue(board.display!.activeRequestIDs.isEmpty)
    }

    @MainActor
    func testIslandArchivePersistsAcrossRestartUntilDifferentTurnStarts() throws {
        let suite = "QuotaViewArchiveSmoke-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let date = Date(); let model = IslandLiveStore(archiveDefaults: defaults)
        start(model, "chat", "old", at: date)
        model.receive(json("turn/completed", ["threadId": "chat", "turn": ["id": "old", "status": "completed"]]))
        model.archiveFromIsland(model.tasks[0].id)
        XCTAssertEqual(model.tasks[0].status, .completed)
        let restored = IslandLiveStore(archiveDefaults: defaults)
        func displayed() -> [CodexMultitaskRenderTask] { restored.display(english: false, remaining: nil, enabled: true, privacy: false).state.tasks }
        restored.receive(json("thread/snapshot", ["thread": ["id": "chat", "source": "vscode", "status": ["type": "active"]]]))
        XCTAssertTrue(displayed().isEmpty)
        start(restored, "chat", "old", at: date)
        XCTAssertTrue(displayed().isEmpty)
        restored.receive(json("turn/completed", ["threadId": "chat", "turn": ["id": "old", "status": "completed"]]))
        XCTAssertTrue(displayed().isEmpty)
        start(restored, "chat", "new", at: date.addingTimeInterval(1))
        XCTAssertEqual(displayed().count, 1)
        restored.receive(json("turn/completed", ["threadId": "chat", "turn": ["id": "old", "status": "completed"]]))
        XCTAssertEqual(displayed().first?.renderState.visualState, .thinking)
        XCTAssertTrue((defaults.dictionary(forKey: "island.archivedTurns") ?? [:]).isEmpty)
    }

    @MainActor
    func testTicketSweepStopsWhenHiddenReducedOrDetachedWithoutRestartingOnRefresh() throws {
        _ = NSApplication.shared
        let host = IslandResetTicketSweepHost(frame: NSRect(x: 0, y: 0, width: 53.677, height: 32))
        host.configure(active: true, reduceMotion: false)
        XCTAssertNil(host.sweepAnimation)
        let window = NSWindow(contentRect: host.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host; host.needsLayout = true; host.layoutSubtreeIfNeeded()
        let animation = try XCTUnwrap(host.sweepAnimation)
        XCTAssertEqual(animation.duration, 2)
        XCTAssertEqual(animation.keyTimes, [0, 0.10, 0.90, 1])
        XCTAssertTrue(animation.repeatCount.isInfinite)
        XCTAssertNil(host.hitTest(.init(x: 20, y: 15)))
        for _ in 0..<10 { host.configure(active: true, reduceMotion: false); host.layout() }
        XCTAssertEqual(host.sweepAnimation?.beginTime, animation.beginTime)
        host.configure(active: false, reduceMotion: false)
        XCTAssertNil(host.sweepAnimation)
        host.configure(active: true, reduceMotion: true)
        XCTAssertNil(host.sweepAnimation)
        host.configure(active: true, reduceMotion: false)
        XCTAssertNotNil(host.sweepAnimation)
        host.removeFromSuperview()
        XCTAssertNil(host.sweepAnimation)
    }

    @MainActor
    func testResetPageReturnInterruptionAndMotionCancellation() {
        let board = IslandBoardState()
        board.setGeometry(.init(frame: CGRect(x: 0, y: 0, width: 1280, height: 800)))
        board.pin(); board.openUsage(); board.updateUsageHeight(560)
        let canvas = board.expandedCanvasHeight
        board.openReset()
        let opening = board.resetTransitionSerial
        XCTAssertTrue(board.showsReset)
        XCTAssertTrue(board.resetTransitionInFlight)
        XCTAssertEqual(board.surfaceWidth, 378)
        XCTAssertEqual(board.expandedCanvasHeight, canvas)
        board.updateResetHeight(434)
        XCTAssertEqual(board.expandedHeight, board.headerHeight + 434)
        board.escape()
        let returning = board.resetTransitionSerial
        XCTAssertFalse(board.showsReset)
        XCTAssertTrue(board.resetTransitionInFlight)
        XCTAssertEqual(board.surfaceWidth, 680)
        board.finishResetTransition(serial: opening)
        XCTAssertTrue(board.resetTransitionInFlight, "Stale opening completion must not end return")
        board.finishResetTransition(serial: returning)
        XCTAssertFalse(board.resetTransitionInFlight)
        XCTAssertEqual(board.presentation, .pinned)
        var display = IslandLiveStore().display(english: false, remaining: nil, enabled: true, privacy: false)
        board.update(display, reduceMotion: true)
        board.openReset()
        XCTAssertTrue(board.showsReset)
        XCTAssertFalse(board.resetTransitionInFlight)
        board.escape(); board.escape()
        XCTAssertFalse(board.showsUsage)
        board.openUsage(); board.openReset()
        let live = IslandLiveStore()
        board.update(live.display(english: false, remaining: nil, enabled: true, privacy: false), reduceMotion: false)
        start(live, "reset-flow", "one", at: Date())
        board.update(live.display(english: false, remaining: nil, enabled: true, privacy: false), reduceMotion: false)
        XCTAssertTrue(board.showsReset)
        XCTAssertNil(board.automaticPreviewDeadline)
        display.visible = false; board.update(display, reduceMotion: false)
        XCTAssertFalse(board.showsReset)
        XCTAssertFalse(board.showsUsage)
        XCTAssertFalse(board.resetTransitionInFlight)
    }

    @MainActor
    func testResetTicketFlightUsesSameEasingBothDirectionsAndLifecycle() throws {
        _ = NSApplication.shared
        let source = CGRect(x: 500, y: 175, width: 53.6774, height: 32)
        let destination = CGRect(x: 239.355, y: 22, width: 201.29, height: 120)
        let initial = IslandResetTicketFlight.sample(progress: 0, source: source, destination: destination)
        let final = IslandResetTicketFlight.sample(progress: 1, source: source, destination: destination)
        XCTAssertEqual(initial.position, CGPoint(x: source.midX, y: source.midY))
        XCTAssertEqual(final.position.x, destination.midX, accuracy: 0.0001)
        XCTAssertEqual(final.position.y, destination.midY, accuracy: 0.0001)
        XCTAssertEqual(initial.transform.m11, source.width / 201.29, accuracy: 0.0001)
        XCTAssertEqual(final.transform.m11, 1, accuracy: 0.0001)
        let quarter = IslandResetTicketFlight.sample(progress: 0.25, source: source, destination: destination)
        let middle = IslandResetTicketFlight.sample(progress: 0.5, source: source, destination: destination)
        let threeQuarters = IslandResetTicketFlight.sample(progress: 0.75, source: source, destination: destination)
        XCTAssertLessThan(middle.transform.m11, 0, "Halfway through the full turn the back faces forward")
        XCTAssertLessThan(quarter.transform.m13 * threeQuarters.transform.m13, 0,
            "The two edge-on quarters must face opposite directions")
        let host = IslandResetTicketFlightHost(frame: CGRect(x: 0, y: 0, width: 680, height: 560))
        host.configure(serial: 1, toReset: true, active: true, source: source, destination: destination, reduceMotion: false)
        XCTAssertNil(host.flightAnimation)
        let window = NSWindow(contentRect: host.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.configure(serial: 1, toReset: true, active: true, source: source, destination: destination, reduceMotion: false)
        let opening = try XCTUnwrap(host.flightAnimation)
        XCTAssertEqual(opening.duration, IslandResetTicketFlight.duration)
        XCTAssertEqual(host.cardPosition.x, destination.midX, accuracy: 0.0001)
        for _ in 0..<10 {
            host.configure(serial: 1, toReset: true, active: true, source: source.offsetBy(dx: 4, dy: 4), destination: destination, reduceMotion: false)
        }
        XCTAssertEqual(host.flightAnimation?.beginTime, opening.beginTime)
        host.stop()
        host.configure(serial: 2, toReset: false, active: true, source: source, destination: destination, reduceMotion: false)
        let returning = try XCTUnwrap(host.flightAnimation)
        let forward = try XCTUnwrap(try XCTUnwrap(opening.animations?[0] as? CAKeyframeAnimation).values as? [NSValue])
        let backward = try XCTUnwrap(try XCTUnwrap(returning.animations?[0] as? CAKeyframeAnimation).values as? [NSValue])
        XCTAssertEqual(forward.count, backward.count)
        let distance = destination.midX - source.midX
        for (a, b) in zip(forward, backward) {
            let openingTravel = (a.pointValue.x - source.midX) / distance
            let returnTravel = (destination.midX - b.pointValue.x) / distance
            XCTAssertEqual(openingTravel, returnTravel, accuracy: 0.0001,
                "Opening and return must share the same elapsed-time rhythm")
        }
        XCTAssertGreaterThan((destination.midX - backward[1].pointValue.x) / distance, 0.05,
            "Return must move immediately instead of starting with the reversed settling phase")
        XCTAssertEqual(backward.last?.pointValue.x ?? .nan, source.midX, accuracy: 0.0001)
        XCTAssertEqual(backward.last?.pointValue.y ?? .nan, source.midY, accuracy: 0.0001)
        for point in backward.suffix(17) {
            XCTAssertLessThanOrEqual(abs((point.pointValue.x - source.midX) / distance), 0.025,
                "The final phase should settle near the usage-card anchor")
        }
        let returnTransforms = try XCTUnwrap(try XCTUnwrap(returning.animations?[1] as? CAKeyframeAnimation).values as? [NSValue])
        XCTAssertTrue(returnTransforms.contains { $0.caTransform3DValue.m11 < 0 },
            "The return must rotate through the back face while shrinking")
        XCTAssertTrue(returnTransforms.contains { $0.caTransform3DValue.m13 > 0.1 })
        XCTAssertTrue(returnTransforms.contains { $0.caTransform3DValue.m13 < -0.1 },
            "A full turn must pass both edge-on directions")
        let landing = try XCTUnwrap(returnTransforms.last).caTransform3DValue
        XCTAssertEqual(landing.m11, initial.transform.m11, accuracy: 0.0001)
        XCTAssertEqual(landing.m22, initial.transform.m22, accuracy: 0.0001)
        XCTAssertNil(host.hitTest(.init(x: 340, y: 82)))
        host.configure(serial: 3, toReset: true, active: true, source: source, destination: destination, reduceMotion: true)
        XCTAssertNil(host.flightAnimation)
        host.configure(serial: 4, toReset: true, active: true, source: source, destination: destination, reduceMotion: false)
        XCTAssertNotNil(host.flightAnimation)
        host.removeFromSuperview()
        XCTAssertNil(host.flightAnimation)
    }

    @MainActor
    func testResetPageReadsWeeklyQuotaAndPreservesUnknownCredits() {
        func snapshot(credits: Int?) -> CurrentCodexPresentation {
            .init(availability: .ready, planType: "pro", usedPercent: 10, remainingPercent: 90,
                windowDurationMinutes: 300, resetsAt: nil, quotaWindows: [
                    .init(id: CodexDomainCatalog.secondaryRateWindowID, usedPercent: 62, remainingPercent: 38,
                        windowDurationMinutes: 10080, resetsAt: nil)
                ], sparkQuota: nil, creditBalance: nil, hasCredits: false, unlimitedCredits: false,
                availableResetCredits: credits, lifetimeTokens: nil, recentDailyTokens: nil,
                recentDailyDate: nil, tokenActivity: [], lastUpdatedAt: Date(timeIntervalSince1970: 100))
        }
        let missing = IslandResetPageData(snapshot: nil)
        XCTAssertNil(missing.credits)
        XCTAssertNil(missing.remainingPercent)
        XCTAssertNil(missing.creditsAfterOne)
        XCTAssertFalse(missing.canPreview)
        let unknown = IslandResetPageData(snapshot: snapshot(credits: nil))
        XCTAssertNil(unknown.credits)
        XCTAssertFalse(unknown.canPreview)
        let available = IslandResetPageData(snapshot: snapshot(credits: 2))
        XCTAssertEqual(available.remainingPercent, 38)
        XCTAssertEqual(available.credits, 2)
        XCTAssertEqual(available.creditsAfterOne, 1)
        XCTAssertTrue(available.canPreview)
        let exhausted = IslandResetPageData(snapshot: snapshot(credits: 0))
        XCTAssertFalse(exhausted.canPreview)
        XCTAssertEqual(exhausted.creditsAfterOne, 0)
        XCTAssertEqual(exhausted.remainingPercent, 38, "Zero reset credits must not erase the actual quota")
        XCTAssertEqual(exhausted.creditAvailability, .empty)
        XCTAssertEqual(unknown.creditAvailability, .unknown)
        XCTAssertEqual(missing.creditAvailability, .unknown)
        let zh = AppCopy(language: .simplifiedChinese), en = AppCopy(language: .english)
        XCTAssertEqual(exhausted.actionTitle(previewed: false, copy: zh), "暂无可用重置卡")
        XCTAssertEqual(exhausted.actionTitle(previewed: true, copy: zh), "暂无可用重置卡", "Old demo feedback must not mask zero credits")
        XCTAssertEqual(exhausted.actionTitle(previewed: true, copy: en), "No reset credits available")
        XCTAssertEqual(unknown.actionTitle(previewed: true, copy: zh), "等待重置卡数据")
        XCTAssertEqual(missing.actionTitle(previewed: false, copy: en), "Waiting for reset credits")
        XCTAssertEqual(exhausted.caption(previewed: true, copy: zh), "没有可用重置次数")
        XCTAssertEqual(unknown.caption(previewed: true, copy: en), "Credits unavailable")
        XCTAssertEqual(available.actionTitle(previewed: true, copy: zh), "演示完成")
        // A refreshed last credit restores the action even though the demo's
        // projected after-use balance is zero. The actual snapshot is unchanged.
        let restored = IslandResetPageData(snapshot: snapshot(credits: 1))
        XCTAssertEqual(restored.creditAvailability, .available)
        XCTAssertTrue(restored.canPreview)
        XCTAssertEqual(restored.creditsAfterOne, 0)
        XCTAssertEqual(restored.actionTitle(previewed: false, copy: zh), "额度重置")
        XCTAssertEqual(restored.caption(previewed: false, copy: en), "Demo · 0 left after reset")
        XCTAssertEqual(restored.snapshot?.availableResetCredits, 1)
    }

    @MainActor
    func testUsagePagePreservesPinAndAdaptsToContentHeight() {
        let board = IslandBoardState()
        board.setGeometry(.init(frame: CGRect(x: 0, y: 0, width: 1280, height: 600)))
        board.pin(); board.openUsage()
        XCTAssertTrue(board.showsUsage)
        XCTAssertEqual(board.presentation, .pinned)
        board.updateUsageHeight(420)
        XCTAssertEqual(board.expandedHeight, board.headerHeight + 420)
        board.updateUsageHeight(580)
        XCTAssertEqual(board.expandedHeight, board.geometry.maximumExpandedHeight, "Long usage content scrolls while the footer stays inside the available display height")
        board.updateUsageHeight(.nan)
        XCTAssertEqual(board.usageHeight, 580)
        board.closeUsage()
        XCTAssertFalse(board.showsUsage)
        XCTAssertEqual(board.presentation, .pinned)
        board.openUsage(); board.collapse()
        XCTAssertFalse(board.showsUsage)
        XCTAssertTrue(board.compact)
    }
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
