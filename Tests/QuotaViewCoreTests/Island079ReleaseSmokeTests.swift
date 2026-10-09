import AppKit
import MetalKit
import XCTest
@testable import QuotaView

final class Island079ReleaseSmokeTests: XCTestCase {
    @MainActor
    func testExpandedWidthDefaultsAndPersistenceAreBounded() throws {
        let suite = "QuotaView.Release079.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        XCTAssertEqual(preferences.codexIslandExpandedWidth, 680)
        for (input, expected) in [(420.0, 560.0), (610, 610), (900, 680),
                                  (.nan, 680), (.infinity, 680), (-.infinity, 680)] {
            preferences.codexIslandExpandedWidth = input
            XCTAssertEqual(AppPreferences(defaults: defaults).codexIslandExpandedWidth, expected)
            XCTAssertEqual(AppPreferences.IslandExpandedWidth.normalized(input), expected)
        }
    }

    func testExpandedWidthRespectsPhysicalNotchAndScreenBounds() {
        let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        for cameraWidth in [0.0, 180, 250, 360] {
            let leftWidth = (frame.width - cameraWidth) / 2
            let geometry = IslandNotchGeometry(frame: frame, safeTop: cameraWidth > 0 ? 32 : 0,
                left: CGRect(x: 0, y: 950, width: leftWidth, height: 32),
                right: CGRect(x: leftWidth + cameraWidth, y: 950, width: leftWidth, height: 32))
            XCTAssertEqual(geometry.cameraWidth, cameraWidth)
            XCTAssertEqual(geometry.expandedWidth(preferred: 560),
                           min(geometry.maximumExpandedWidth, max(560, cameraWidth + 360)))
            XCTAssertEqual(geometry.expandedWidth(preferred: 680), geometry.maximumExpandedWidth)
            XCTAssertEqual(geometry.expandedWidth(preferred: .nan), geometry.maximumExpandedWidth)
        }
        let narrow = IslandNotchGeometry(frame: CGRect(x: 0, y: 0, width: 600, height: 900))
        XCTAssertEqual(narrow.expandedWidth(preferred: 560), 552)
        XCTAssertEqual(narrow.expandedWidth(preferred: 680), 552)
    }

    @MainActor
    func testWidthChangesPreserveUsageNavigationAndIndependentSurfaces() {
        let board = IslandBoardState()
        board.setGeometry(.init(frame: CGRect(x: 0, y: 0, width: 1512, height: 982)))
        let model = IslandLiveStore()
        var display = model.display(english: true, remaining: 80, enabled: true, privacy: false)
        board.update(display, reduceMotion: true)
        let originalCompact = board.compactWidth
        let originalReset = board.resetWidth
        board.pin()
        display.expandedWidth = 560
        board.update(display, reduceMotion: true)
        XCTAssertEqual(board.expandedWidth, 560)
        board.openUsage()
        display.expandedWidth = 610
        board.update(display, reduceMotion: true)
        XCTAssertEqual(board.surfaceWidth, 610)
        XCTAssertTrue(board.showsUsage)
        XCTAssertEqual(board.presentation, .pinned)
        board.openReset()
        XCTAssertEqual(board.surfaceWidth, originalReset)
        XCTAssertEqual(board.compactWidth, originalCompact)
        XCTAssertEqual(board.maximumExpandedWidth, 680)
    }

    @MainActor
    func testLivePreviewKeepsBudgetAndPausesOffWindow() throws {
        for effect in [AppPreferences.CodexActivityProgressEffect.stateSmoke, .dropField, .sloshFlow] {
            let host = CodexActivityStateSmokePreviewHostView(effect: effect)
            host.frame = CGRect(x: 0, y: 0, width: 210, height: 56)
            host.update(effect: effect, reduceMotion: false, cornerRadius: 4)
            host.layoutSubtreeIfNeeded()
            let metal = try XCTUnwrap(host.subviews.first as? MTKView)
            XCTAssertEqual(metal.preferredFramesPerSecond, 24)
            XCTAssertFalse(metal.autoResizeDrawable)
            XCTAssertEqual(metal.drawableSize, CGSize(width: 210, height: 56))
            XCTAssertTrue(metal.isPaused, "Detached previews must not render in the background")
            XCTAssertEqual(host.layer?.cornerRadius, 4)
            XCTAssertEqual(metal.layer?.cornerRadius, 4)
            XCTAssertTrue(metal.layer?.masksToBounds == true)
            XCTAssertNil(host.hitTest(CGPoint(x: 10, y: 10)))
            host.update(effect: effect, reduceMotion: true, playbackEnabled: false)
            host.stop()
            XCTAssertTrue(metal.isPaused)
        }
    }
}
