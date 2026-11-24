import AppKit
import SwiftUI
import XCTest
@testable import QuotaView

final class SettingsWindowSizingSmokeTests: XCTestCase {
    @MainActor func testAgentOrderPersistsMovesAndAppendsMissingAgents() throws {
        let suite = "AgentOrder-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let prefs = AppPreferences(defaults: defaults)
        let initial = IslandAgentProvider.allCases
        XCTAssertEqual(prefs.agentSettingsOrder, initial)
        prefs.moveAgentInSettings(.devinCLI, to: .codex)
        XCTAssertEqual(prefs.agentSettingsOrder, [.devinCLI] + initial.dropLast())
        XCTAssertEqual(AppPreferences(defaults: defaults).agentSettingsOrder, prefs.agentSettingsOrder)
        prefs.moveAgentInSettings(.devinCLI, to: .devinDesktop)
        prefs.moveAgentInSettings(.codex, to: .codex)
        XCTAssertEqual(prefs.agentSettingsOrder, initial)
        XCTAssertEqual(AppPreferences(defaults: defaults).agentSettingsOrder, initial)

        defaults.set(["dsh", "retired-agent", "dsh", "codex"], forKey: "preferences.settings.agentOrder")
        let restored = AppPreferences(defaults: defaults).agentSettingsOrder
        XCTAssertEqual(restored, [.dsh, .codex] + initial.filter { $0 != .dsh && $0 != .codex })
    }

    func testAgentDragPreviewCrossesMidpointsAndHoldsItsGapUntilReversed() {
        let order: [IslandAgentProvider] = [.codex, .claudeCode, .dsh, .kimiCode]
        let heights: [IslandAgentProvider: CGFloat] = [.claudeCode: 72]
        var preview = AgentReorderPreview(agent: .codex, order: order)

        preview.update(at: 88, heights: heights)
        XCTAssertEqual(preview.order, order)
        preview.update(at: 90, heights: heights)
        XCTAssertEqual(preview.order, [.claudeCode, .codex, .dsh, .kimiCode])
        preview.update(at: 87, heights: heights)
        XCTAssertEqual(preview.target, .claudeCode)
        preview.update(at: 36, heights: heights)
        XCTAssertEqual(preview.target, .claudeCode)
        preview.update(at: 35, heights: heights)
        XCTAssertEqual(preview.order, order)
        preview.update(at: 1_000, heights: heights)
        XCTAssertEqual(preview.order, [.claudeCode, .dsh, .kimiCode, .codex])
        XCTAssertEqual(preview.target, .kimiCode)
        XCTAssertEqual(preview.original, order)
        preview.update(at: 0, heights: heights)
        XCTAssertEqual(preview.order, order)
    }

    @MainActor func testAgentHoverChangesOnlyPreviewAndDropSavesThatOrder() throws {
        let suite = "AgentHover-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        let original = preferences.agentSettingsOrder
        var preview = AgentReorderPreview(agent: .devinCLI, order: original)
        preview.update(at: 0, heights: [:])
        XCTAssertEqual(preferences.agentSettingsOrder, original)
        XCTAssertNil(defaults.object(forKey: "preferences.settings.agentOrder"))
        preferences.moveAgentInSettings(preview.agent, to: try XCTUnwrap(preview.target))
        XCTAssertEqual(preferences.agentSettingsOrder, preview.order)
        XCTAssertEqual(AppPreferences(defaults: defaults).agentSettingsOrder, preview.order)
    }

    func testNavigationAcrossAgentAndSidebarPages() {
        var history = SettingsNavigationHistory()
        history.back()
        XCTAssertEqual(history.current, .page(.general))
        history.visit(.page(.connections))
        history.visit(.agent(.dsh))
        history.visit(.agent(.dsh))
        XCTAssertEqual(history.current.page, .connections)
        history.back()
        XCTAssertEqual(history.current, .page(.connections))
        history.forward()
        XCTAssertEqual(history.current, .agent(.dsh))
        history.visit(.page(.usage))
        history.back()
        XCTAssertEqual(history.current, .agent(.dsh))
        history.visit(.page(.cards))
        history.forward()
        XCTAssertEqual(history.current, .page(.cards))
        XCTAssertTrue(history.next.isEmpty)
    }

    @MainActor func testNavigationHeaderOccupiesNativeTitlebarAfterSidebar() throws {
        _ = NSApplication.shared
        let window = QuotaViewSettingsWindow(contentRect: NSRect(origin: .zero, size: SettingsWindowMetrics.defaultContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        SettingsWindowMetrics.configureTitlebar(of: window)
        let header = SettingsTitlebarHeader<Text>()
        header.update(Text("General"), in: window)
        header.update(Text("Agent integration"), in: window)
        window.contentView?.superview?.layoutSubtreeIfNeeded()

        XCTAssertEqual(window.titlebarAccessoryViewControllers.count, 1)
        let view = try XCTUnwrap(window.titlebarAccessoryViewControllers.first?.view)
        XCTAssertTrue(view.window === window)
        let frame = view.convert(view.bounds, to: nil)
        XCTAssertEqual(frame.minX, SettingsWindowMetrics.sidebarWidth, accuracy: 1)
        XCTAssertEqual(frame.maxY, window.frame.height, accuracy: 1)
        XCTAssertEqual(frame.height, SettingsWindowMetrics.headerHeight, accuracy: 1)
        XCTAssertEqual(frame.maxX, window.frame.width, accuracy: 1)
        let frameView = try XCTUnwrap(window.contentView?.superview)
        let backButtonCenter = NSPoint(x: frame.minX + 26, y: frame.midY)
        let hit = try XCTUnwrap(frameView.hitTest(frameView.convert(backButtonCenter, from: nil)))
        XCTAssertTrue(hit === view || hit.isDescendant(of: view))
        header.detach()
        XCTAssertTrue(window.titlebarAccessoryViewControllers.isEmpty)
    }

    @MainActor func testSettingsWindowFollowsGlassAppearanceAndRestoresInheritance() {
        _ = NSApplication.shared
        let window = QuotaViewSettingsWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        SettingsWindowMetrics.applyAppearance(.light, to: window)
        XCTAssertEqual(window.appearance?.name, .aqua)
        SettingsWindowMetrics.applyAppearance(.dark, to: window)
        XCTAssertEqual(window.appearance?.name, .darkAqua)
        SettingsWindowMetrics.applyAppearance(.automatic, to: window)
        XCTAssertNil(window.appearance)
    }

    @MainActor func testSettingsWidthIsFixedWhileHeightRemainsResizableAndZoomIsDisabled() {
        _ = NSApplication.shared
        let window = QuotaViewSettingsWindow(contentRect: NSRect(origin: .zero, size: SettingsWindowMetrics.defaultContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        SettingsWindowMetrics.applySizingPolicy(to: window)
        XCTAssertEqual(window.contentMinSize.width, 820)
        XCTAssertEqual(window.contentMaxSize.width, 820)
        XCTAssertGreaterThan(window.contentMaxSize.height, window.contentMinSize.height)
        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertEqual(window.standardWindowButton(.zoomButton)?.isEnabled, false)
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenNone))
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenDisallowsTiling))
        let original = window.frame
        window.zoom(nil)
        XCTAssertEqual(window.frame, original)
        window.toggleFullScreen(nil)
        XCTAssertFalse(window.styleMask.contains(.fullScreen))
        XCTAssertEqual(window.frame, original)
    }
}
