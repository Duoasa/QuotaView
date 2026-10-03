import Foundation
import XCTest
@testable import QuotaView
@testable import QuotaViewCore

final class IslandMemoryActivitySmokeTests: XCTestCase {
    private func message(_ method: String, _ params: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["method": method, "params": params])
    }
    private func snapshot(_ state: CodexActivityVisualState, key: String = "memory", time: Double = 100,
                          operation: CodexActivityOperationKey = .usingTool) -> CodexActivitySnapshot {
        .init(sessionHash: key, state: state, workspaceName: "memories", operationKey: operation,
              toolCategory: nil, approximateProgressFraction: nil, occurredAt: Date(timeIntervalSince1970: time))
    }

    @MainActor func testLateMemoryIdentityRemovesRowAndCannotReenterViaLegacyOrPublicEvents() throws {
        let model = IslandLiveStore()
        try model.receive(message("turn/started", ["threadId": "background", "turn": ["id": "one"]]))
        XCTAssertEqual(model.tasks.count, 1)
        try model.receive(message("thread/snapshot", ["thread": ["id": "background", "source": "unknown",
            "thread_source": "memory_consolidation", "status": ["type": "active"]]]))
        XCTAssertTrue(model.tasks.isEmpty)
        XCTAssertEqual(model.selectedID, 0)
        try model.receive(message("turn/started", ["threadId": "background", "turn": ["id": "two"]]))
        model.receiveLegacy(.init(event: .preToolUse, sessionHash: CodexActivityPrivacy.hashIdentifier("background"),
            sessionKind: .unknown))
        XCTAssertTrue(model.tasks.isEmpty)
        XCTAssertTrue(model.display(english: false, remaining: nil, enabled: true, privacy: false).activeRequestIDs.isEmpty)
        model.reset()
        try model.receive(message("turn/started", ["threadId": "background", "turn": ["id": "new-root"]]))
        XCTAssertEqual(model.tasks.count, 1, "Changing the data-root generation must clear old classification")
    }

    @MainActor func testMemoryTitleDoesNotClassifyAUserConversation() throws {
        let model = IslandLiveStore()
        try model.receive(message("thread/started", ["thread": ["id": "user", "name": "memories",
            "source": "cli", "threadSource": "user", "status": ["type": "active"]]]))
        XCTAssertEqual(model.tasks.count, 1)
        XCTAssertEqual(model.tasks.first?.title, "memories")
    }

    @MainActor func testBackgroundOnlyDisplayKeepsUserCountsAndPopupEmpty() {
        let model = IslandLiveStore()
        var display = model.display(english: false, remaining: nil, enabled: true, privacy: false)
        let board = IslandBoardState()
        board.update(display, reduceMotion: true)
        display.backgroundMemorySnapshots = [snapshot(.thinking)]
        board.update(display, reduceMotion: true)
        XCTAssertTrue(board.tasks.isEmpty)
        XCTAssertEqual(board.runningCount, 0)
        XCTAssertEqual(board.attentionCount, 0)
        XCTAssertTrue(board.compact, "Background work must not automatically open the island")
        XCTAssertEqual(board.memoryActivity?.visualState, .thinking)
        XCTAssertTrue(board.memoryActivity?.playbackEnabled == true)
        display.backgroundMemorySnapshots = [snapshot(.completed, time: 101, operation: .turnCompleted)]
        board.update(display, reduceMotion: true)
        XCTAssertTrue(board.compact, "Memory completion must not show the user completion popup")
        XCTAssertEqual(board.memoryActivity?.label(english: false), "记忆整理 · 整理完成")
        XCTAssertTrue(board.memoryActivity?.playbackEnabled == false)
    }

    func testRunningMemoryWinsOverNewerCompletedJobAndStaleStateDoesNotAnimate() throws {
        let activity = try XCTUnwrap(IslandMemoryActivity(snapshots: [snapshot(.thinking, key: "active", time: 99),
            snapshot(.completed, key: "finished", time: 101)]))
        XCTAssertEqual(activity.snapshot.sessionHash, "active")
        XCTAssertEqual(activity.count, 2)
        let stale = try XCTUnwrap(IslandMemoryActivity(snapshots: [snapshot(.unavailable)]))
        XCTAssertFalse(stale.playbackEnabled)
        XCTAssertEqual(stale.label(english: false), "记忆整理 · 状态待更新")
        XCTAssertEqual(stale.label(english: true), "Memory consolidation · Status unavailable")
    }

    func testFailureAndInterruptionRetainTheirRealMeaning() throws {
        let failed = try XCTUnwrap(IslandMemoryActivity(snapshots: [snapshot(.error, operation: .turnFailed)]))
        XCTAssertEqual(failed.label(english: false), "记忆整理 · 整理失败")
        XCTAssertFalse(failed.playbackEnabled)
        let interrupted = try XCTUnwrap(IslandMemoryActivity(snapshots: [snapshot(.standby, operation: .turnInterrupted)]))
        XCTAssertEqual(interrupted.label(english: true), "Memory consolidation · Interrupted")
        XCTAssertFalse(interrupted.playbackEnabled)
        XCTAssertNil(IslandMemoryActivity(snapshots: []))
    }
}
