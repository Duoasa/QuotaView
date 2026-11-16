import Foundation
import XCTest
import QuotaViewCore
@testable import QuotaView

final class TaskCardSettingsSmokeTests: XCTestCase {
    @MainActor func testDefaultsAndIndependentPersistence() throws {
        let suite = "QuotaView.CardSettingsSmoke." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        XCTAssertEqual(IslandTaskCardOptions(preferences: preferences), IslandTaskCardOptions())
        preferences.cardShowsTokens = false
        preferences.cardShowsModel = false
        let restored = IslandTaskCardOptions(preferences: AppPreferences(defaults: defaults))
        XCTAssertTrue(restored.outputRate)
        XCTAssertTrue(restored.duration)
        XCTAssertFalse(restored.tokens)
        XCTAssertFalse(restored.model)
        XCTAssertTrue(IslandSettingsPage.allCases.contains(.cards))
    }

    @MainActor func testCardOptionsProjectWithoutLosingTaskData() throws {
        let model = IslandLiveStore(), now = Date()
        let session = "card-settings", turn = "turn"
        model.receiveLegacy(.init(event: .userPromptSubmit, sessionHash: session, turnHash: turn,
            occurredAt: now.addingTimeInterval(-120)))
        let metadata = try JSONSerialization.data(withJSONObject: ["type": "metadata",
            "model": String(repeating: "long-model-", count: 12), "effort": "high"])
        model.receiveLocalContent(.init(publicSessionHash: session, turnHash: turn, data: metadata, occurredAt: now))
        let sample = try XCTUnwrap(CodexOutputRateSample(outputTokens: 300, startedAt: now.addingTimeInterval(-5), endedAt: now))
        model.receiveOutputRate(session: session, turn: turn, latest: sample, average: sample)
        model.receiveToken(.init(sessionHash: session, turnHash: turn, cumulativeTotalTokens: 1234, lastReportedTotalTokens: 1234))
        for bits in 0..<16 {
            var options = IslandTaskCardOptions()
            options.outputRate = bits & 1 != 0
            options.tokens = bits & 2 != 0
            options.duration = bits & 4 != 0
            options.model = bits & 8 != 0
            let display = model.display(english: true, remaining: nil, enabled: true, privacy: false, at: now, cardOptions: options)
            let card = try XCTUnwrap(display.state.tasks.first)
            let metadata = try XCTUnwrap(display.sessionMetadata[card.id])
            XCTAssertEqual(card.cardOptions, options)
            XCTAssertEqual(card.outputRate != nil, options.outputRate)
            XCTAssertEqual(card.renderState.tokenUsageTitle != nil, options.tokens)
            XCTAssertEqual(metadata.elapsedSeconds != nil, options.duration)
            XCTAssertEqual(!metadata.modelTitle.isEmpty, options.model)
            XCTAssertEqual(metadata.usesExtraLine, options.model)
            if !options.model { XCTAssertEqual(metadata.primaryContentHeight(width: 656), IslandVibeLayout.rowHeight) }
        }
        XCTAssertEqual(model.tasks[0].tokens, 1234)
        XCTAssertEqual(model.tasks[0].outputRate, sample)
        XCTAssertFalse(model.tasks[0].model.isEmpty)
        let restored = model.display(english: true, remaining: nil, enabled: true, privacy: false, at: now)
        XCTAssertEqual(restored.state.tasks.first?.outputRate, sample)
        XCTAssertNotNil(restored.state.tasks.first?.renderState.tokenUsageTitle)
    }
}
