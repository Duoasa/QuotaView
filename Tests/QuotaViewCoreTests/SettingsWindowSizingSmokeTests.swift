import AppKit
import XCTest
@testable import QuotaView

final class SettingsWindowSizingSmokeTests: XCTestCase {
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
