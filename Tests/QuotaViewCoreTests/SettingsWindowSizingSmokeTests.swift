import AppKit
import SwiftUI
import XCTest
@testable import QuotaView

final class SettingsWindowSizingSmokeTests: XCTestCase {
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
