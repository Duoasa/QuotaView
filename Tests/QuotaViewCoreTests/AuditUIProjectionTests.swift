import Foundation
import XCTest
@testable import QuotaView
@testable import QuotaViewCore

@MainActor final class AuditUIProjectionTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_790_888_000)
    private func setup() -> (CodexActivityStore, IslandLiveStore) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = CodexActivityStore(titleClient: .init(executablePath: nil),
            sharedActivityClient: .init(configuration: .init(isEnabled: false, socketURL: root.appendingPathComponent("unused"), executablePath: nil)),
            localRolloutActivityClient: .init(configuration: .init(isEnabled: false, codexHomeURL: root)),
            sessionDirectory: root, sessionKindResolver: { $0.sessionKind ?? .user })
        let model = IslandLiveStore()
        CodexActivityRuntime.connectActivityProjection(store: store, model: model)
        return (store, model)
    }
    private func event(_ type: CodexActivityHookEvent, offset: TimeInterval = 0, source: CodexActivityEventSource = .hook,
                       plan: CodexActivityPlanProgress? = nil, planSource: CodexActivityPlanSource? = nil,
                       goal: CodexActivityGoalStatus? = nil) -> CodexActivityEvent {
        .init(event: type, sessionHash: "session", turnHash: "turn", planProgress: plan, sessionKind: .user,
              source: source, planSource: planSource, goalStatus: goal, occurredAt: date.addingTimeInterval(offset))
    }
    func testProductionProjectionKeepsStrongerPlanThroughFinalDisplay() throws {
        let (store, model) = setup()
        store.receive(event(.userPromptSubmit))
        store.receive(event(.preToolUse, offset: 1, source: .localRollout,
            plan: .init(completedSteps: 2, inProgressSteps: 1, pendingSteps: 1), planSource: .localRollout))
        store.receive(event(.preToolUse, offset: 2, plan: .init(completedSteps: 3, inProgressSteps: 1, pendingSteps: 0), planSource: .legacyTool))
        XCTAssertEqual(try XCTUnwrap(model.tasks.first?.progress), 0.525, accuracy: 0.001)
        let display = model.display(english: false, remaining: nil, enabled: true, privacy: false, at: date.addingTimeInterval(3))
        XCTAssertLessThanOrEqual(try XCTUnwrap(display.state.tasks.first?.renderState.approximateProgressFraction), 0.525)
    }
    func testScopedEmptyPlanUsesProductionDecodedBindingWithoutReencodingOrLiveDecode() async throws {
        let (store, model) = setup()
        CodexActivityRuntime.connectPublicContentProjection(store: store, model: model)
        let start = try JSONSerialization.data(withJSONObject: ["method": "turn/started", "params": [
            "threadId": "thread", "turnId": "turn", "turn": ["id": "turn", "status": "inProgress"]]])
        let plan = try JSONSerialization.data(withJSONObject: ["method": "turn/plan/updated", "params": [
            "threadId": "thread", "turnId": "turn", "plan": [["status": "completed"], ["status": "inProgress"]]]])
        let empty = try JSONSerialization.data(withJSONObject: ["method": "turn/plan/updated", "params": [
            "threadId": "thread", "turnId": "turn", "plan": [[String: String]]()]])
        await store.receiveScopedPublicMessage(start, connectionEpoch: 1, at: date)
        await store.receiveScopedPublicMessage(plan, connectionEpoch: 1, at: date.addingTimeInterval(1))
        let expected = model.tasks.first?.progress
        XCTAssertNotNil(expected)
        await store.receiveScopedPublicMessage(empty, connectionEpoch: 1, at: date.addingTimeInterval(2))
        XCTAssertNil(model.tasks.first?.progress, "An authoritative empty native plan clears the native estimate")
        XCTAssertNotEqual(model.tasks.first?.status, .completed)
        XCTAssertEqual(model.publicEnvelopeDecodeCount, 0)
        XCTAssertEqual(store.forwardedPublicSerializationCount, 0)
        // Compatibility clients still receive their original Data entrypoint.
        let legacy = IslandLiveStore()
        store.publicMessageDidReceive = { legacy.receive($0) }
        await store.receiveScopedPublicMessage(plan, connectionEpoch: 1, at: date.addingTimeInterval(3))
        XCTAssertEqual(legacy.publicEnvelopeDecodeCount, 1)
        XCTAssertEqual(store.forwardedPublicSerializationCount, 1)
    }
    func testLostCompactionSourceChangesProductionCardAndCanRecover() throws {
        let (store, model) = setup()
        store.receive(event(.userPromptSubmit)); store.receive(event(.preCompact, offset: 1, source: .localRollout))
        store.compactionSourceUnavailable(.localRollout)
        XCTAssertEqual(model.display(english: false, remaining: nil, enabled: true, privacy: false).state.tasks.first?.renderState.visualState, .unavailable)
        store.receive(event(.postCompact, offset: 2, source: .localRollout))
        XCTAssertEqual(model.tasks.first?.status, .thinking)
    }
    func testFreshSessionEndRetiresWaitWithoutInventingCompletionAndLateEventsCannotRevive() throws {
        let (store, model) = setup()
        store.receive(event(.preToolUse)); store.receive(event(.permissionRequest, offset: 1))
        store.receive(event(.sessionEnd, offset: 2))
        XCTAssertNotEqual(model.tasks.first?.status, .waiting)
        XCTAssertNotEqual(model.tasks.first?.status, .completed)
        XCTAssertTrue(try XCTUnwrap(model.tasks.first).requests.isEmpty)
        XCTAssertNotNil(model.tasks.first?.endedAt)
        store.receive(event(.preToolUse, offset: 1.5))
        XCTAssertNotEqual(model.tasks.first?.status, .working)
    }
    func testGoalStopUsesResolvedLifecycleAndOnlyCompleteReachesOneHundredPercent() throws {
        for goal in [CodexActivityGoalStatus.active, .blocked, .usageLimited, .complete] {
            let (store, model) = setup()
            store.receive(event(.userPromptSubmit)); store.receive(event(.postToolUse, offset: 1, goal: goal))
            store.receive(event(.stop, offset: 2))
            if goal == .complete { XCTAssertEqual(model.tasks.first?.status, .completed); XCTAssertEqual(model.tasks.first?.progress, 1) }
            else { XCTAssertNotEqual(model.tasks.first?.status, .completed); XCTAssertNotEqual(model.tasks.first?.progress, 1) }
        }
    }
}
