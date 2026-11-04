import XCTest
@testable import QuotaView

final class IslandScreenSelectionTests: XCTestCase {
    @MainActor func testFixedDisplayDisconnectAndReconnect() {
        XCTAssertEqual(IslandScreenSelection.resolvedID(followsFocus: false, fixedID: "external", focusedID: "main", available: ["main", "external"]), "external")
        XCTAssertEqual(IslandScreenSelection.resolvedID(followsFocus: false, fixedID: "external", focusedID: nil, available: ["main"]), "main")
        XCTAssertEqual(IslandScreenSelection.resolvedID(followsFocus: false, fixedID: "external", focusedID: nil, available: ["main", "external"]), "external")
    }
    @MainActor func testFocusOverridesFixedSelectionAndHandlesNoDisplays() {
        XCTAssertEqual(IslandScreenSelection.resolvedID(followsFocus: true, fixedID: "main", focusedID: "external", available: ["main", "external"]), "external")
        XCTAssertNil(IslandScreenSelection.resolvedID(followsFocus: true, fixedID: "main", focusedID: "external", available: []))
    }
    @MainActor func testPreferenceSurvivesRestart() {
        let suite = "IslandScreenSelectionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        XCTAssertFalse(preferences.islandFollowsFocus)
        preferences.islandFollowsFocus = true
        preferences.islandFixedScreenID = "external-uuid"
        let reloaded = AppPreferences(defaults: defaults)
        XCTAssertTrue(reloaded.islandFollowsFocus)
        XCTAssertEqual(reloaded.islandFixedScreenID, "external-uuid")
    }
    func testPointerDwellRejectsBoundaryPassThroughAndInteraction() {
        var dwell = IslandPointerScreenDwell()
        XCTAssertNil(dwell.destination(pointer: "external", current: "main", blocked: false, now: 0))
        XCTAssertNil(dwell.destination(pointer: "main", current: "main", blocked: false, now: 0.1))
        XCTAssertNil(dwell.destination(pointer: "external", current: "main", blocked: false, now: 0.2))
        XCTAssertNil(dwell.destination(pointer: "external", current: "main", blocked: true, now: 0.4))
        XCTAssertNil(dwell.destination(pointer: "external", current: "main", blocked: false, now: 0.5))
        XCTAssertEqual(dwell.destination(pointer: "external", current: "main", blocked: false, now: 0.66), "external")
        XCTAssertNil(dwell.destination(pointer: "external", current: "external", blocked: false, now: 0.9))
    }
    func testPointerDwellRestartsAfterMissingScreenOrModeChange() {
        var dwell = IslandPointerScreenDwell()
        XCTAssertNil(dwell.destination(pointer: "external", current: "main", blocked: false, now: 0))
        XCTAssertNil(dwell.destination(pointer: nil, current: "main", blocked: false, now: 0.2))
        XCTAssertNil(dwell.destination(pointer: "external", current: "main", blocked: false, now: 0.3))
        dwell.reset()
        XCTAssertNil(dwell.destination(pointer: "external", current: "main", blocked: false, now: 0.5))
        XCTAssertEqual(dwell.destination(pointer: "external", current: "main", blocked: false, now: 0.7), "external")
    }
    @MainActor func testFollowModesAreExclusiveAndPreserveFixedDisplay() {
        let suite = "IslandScreenSelectionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        XCTAssertFalse(preferences.islandFollowsPointer)
        preferences.islandFixedScreenID = "external"
        preferences.islandFollowsFocus = true
        preferences.islandFollowsPointer = true
        XCTAssertFalse(preferences.islandFollowsFocus)
        let reloaded = AppPreferences(defaults: defaults)
        XCTAssertTrue(reloaded.islandFollowsPointer)
        XCTAssertFalse(reloaded.islandFollowsFocus)
        reloaded.islandFollowsFocus = true
        XCTAssertFalse(reloaded.islandFollowsPointer)
        reloaded.islandFollowsFocus = false
        XCTAssertEqual(reloaded.islandFixedScreenID, "external")
    }
}
