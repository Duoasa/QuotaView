import Foundation
import XCTest
@testable import QuotaView
import QuotaViewCore

final class ActivityStoreCollaboratorTests: XCTestCase {
    func testFallbackLookupCannotChangeANewerLegacyTurnOrReplaceAnExplicitName() throws {
        var cache = ActivityTitleCache()
        let first = CodexActivityTaskIdentity(sessionHash: "s", turnHash: nil, generation: 1)
        let second = CodexActivityTaskIdentity(sessionHash: "s", turnHash: nil, generation: 2)
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let old = try XCTUnwrap(cache.beginLookup(for: first, now: now))
        XCTAssertNil(cache.beginLookup(for: first, now: now.addingTimeInterval(9)))
        XCTAssertFalse(cache.finish(old, title: "Old fallback", current: second))
        let fresh = try XCTUnwrap(cache.beginLookup(for: second, now: now))
        XCTAssertTrue(cache.finish(fresh, title: " New fallback ", current: second))
        XCTAssertFalse(cache.finish(old, title: "Old fallback", current: second))
        XCTAssertEqual(cache.title(for: "s"), "New fallback")
        cache.remember("Thread title", session: "s", source: .threadTitle)
        cache.remember("Chosen name", session: "s", source: .explicitName)
        cache.remember("Later metadata", session: "s", source: .threadTitle)
        _ = cache.finish(fresh, title: "Late fallback", current: second)
        XCTAssertEqual(cache.title(for: "s"), "Chosen name")
        XCTAssertEqual(cache.source(for: "s"), .explicitName)
        XCTAssertNil(cache.beginLookup(for: second, now: now.addingTimeInterval(10)))
        cache.forget("s")
        XCTAssertFalse(cache.finish(fresh, title: "Retired", current: second))
        XCTAssertNil(cache.title(for: "s"))
    }

    func testLateChildRelationReplaysOnlyAdmittedChildObservationsForItsCurrentTurn() throws {
        var tracker = SubagentActivityTracker()
        var registry = CodexActivityTaskRegistry()
        let relation = try XCTUnwrap(CodexActivitySubagentIdentity(threadID: "child", parentThreadID: "parent"))
        let session = relation.sessionHash
        let start = CodexActivityEvent(event: .userPromptSubmit, sessionHash: session, turnHash: "one", source: .appServer)
        let latest = CodexActivityEvent(event: .preToolUse, sessionHash: session, turnHash: "one", source: .appServer)
        let admission = try XCTUnwrap(registry.admit(start, kind: .subagent, selectedSession: nil))
        XCTAssertFalse(admission.selectsTask)
        tracker.observe(start, startsTurn: admission.startsTurn)
        let execution = registry.subagentIdentity(for: session)
        XCTAssertTrue(tracker.replay(for: execution).isEmpty)
        XCTAssertTrue(tracker.register(relation))
        let continuation = try XCTUnwrap(registry.admit(latest, kind: .subagent, selectedSession: nil))
        tracker.observe(latest, startsTurn: continuation.startsTurn)
        let replay = tracker.replay(for: execution)
        XCTAssertEqual(replay.map(\.event), [.userPromptSubmit, .preToolUse])
        XCTAssertTrue(replay.allSatisfy { $0.sessionKind == .subagent })
        XCTAssertTrue(tracker.replay(for: registry.currentIdentity(for: session)).isEmpty)
        XCTAssertTrue(tracker.replay(for: .init(sessionHash: session, turnHash: "two")).isEmpty)
        let otherParent = try XCTUnwrap(CodexActivitySubagentIdentity(threadID: "child", parentThreadID: "other"))
        XCTAssertFalse(tracker.register(otherParent))
        XCTAssertEqual(tracker.identity(for: session), relation)
        tracker.markUnavailable(.appServer)
        XCTAssertTrue(tracker.replay(for: execution).isEmpty)
    }

    @MainActor
    func testDeadlineReplacementAndDisableCancelScheduledWork() async {
        let scheduler = MultitaskEntryScheduler()
        let fire = expectation(description: "replacement runs")
        let now = ProcessInfo.processInfo.systemUptime
        scheduler.schedule(now) { _ in XCTFail("Superseded callback ran") }
        scheduler.schedule(now + 0.005) { _ in fire.fulfill() }
        scheduler.schedule(now + 0.005) { _ in XCTFail("Duplicate deadline replaced the callback") }
        await fulfillment(of: [fire], timeout: 2)
        XCTAssertNil(scheduler.deadline)

        scheduler.schedule(now) { _ in XCTFail("Disabled scheduler fired") }
        scheduler.schedule(nil) { _ in XCTFail("Disabled scheduler allocated a deadline") }
        scheduler.schedule(nil) { _ in XCTFail("Repeated disable allocated a deadline") }
        await Task.yield()
        XCTAssertNil(scheduler.deadline)
    }
}
