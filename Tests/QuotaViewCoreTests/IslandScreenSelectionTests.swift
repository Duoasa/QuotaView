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
}
