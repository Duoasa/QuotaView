import Foundation
import XCTest
@testable import QuotaView
@testable import QuotaViewCore

@MainActor
final class CodexActivityCompactHideAuditTests: XCTestCase {
    private func makeStore(compact: TimeInterval = 0.02,
                           hidden: TimeInterval = 0.15) -> CodexActivityStore {
        CodexActivityStore(titleClient: CodexAppServerClient(executablePath: nil),
                           compactDelay: compact, hiddenDelayAfterCompact: hidden)
    }

    private func event(_ type: CodexActivityHookEvent, session: String = "selected",
                       turn: String? = "turn", source: CodexActivityEventSource = .localRollout,
                       kind: CodexActivitySessionKind = .user) -> CodexActivityEvent {
        CodexActivityEvent(event: type, sessionHash: session, turnHash: turn,
                           sessionKind: kind, source: source)
    }

    private func finish(_ store: CodexActivityStore) {
        store.receive(event(.userPromptSubmit))
        store.receive(event(.stop))
        XCTAssertEqual(store.snapshot?.state, .completed)
    }

    private func waitFor(_ state: CodexActivityPresentation, in store: CodexActivityStore,
                         timeout: TimeInterval = 2) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while store.presentation != state && Date() < deadline {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(store.presentation, state)
    }

    private func deliverLateEvents(to store: CodexActivityStore) {
        // Different transports/IDs must not repeatedly extend a terminal receipt.
        for source: CodexActivityEventSource in [.localRollout, .appServer, .hook] {
            store.receive(event(.stop, source: source))
            store.receive(event(.userPromptSubmit, source: source))
            store.receive(event(.permissionRequest, turn: nil, source: source))
            store.receive(event(.postToolUse, source: source))
        }
        store.receive(event(.stop, session: "background"))
        store.receive(event(.userPromptSubmit, session: "guardian", kind: .internalTask))
        store.receive(event(.stop, session: "guardian", kind: .internalTask))
    }

    func testCompactReceiptHidesDespiteLateEventsAndDoesNotReopen() async throws {
        let store = makeStore()
        finish(store)
        try await waitFor(.compact, in: store)
        let deadline = Date().addingTimeInterval(0.45)
        while Date() < deadline {
            deliverLateEvents(to: store)
            // Re-publishing unchanged settings must not restart the countdown.
            store.updateInactivityDelays(compactDelay: 0.02, hiddenDelayAfterCompact: 0.15)
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(store.presentation, .hidden)
        XCTAssertEqual(store.snapshot?.state, .completed)
        XCTAssertFalse(store.shouldPlayVisualEffects)
        await store.stop()
    }

    func testChangingHiddenDelayWhileCompactSchedulesNewHide() async throws {
        let store = makeStore(hidden: 30)
        finish(store)
        try await waitFor(.compact, in: store)
        store.updateInactivityDelays(compactDelay: 0.02, hiddenDelayAfterCompact: 0.03)
        try await waitFor(.hidden, in: store)
        await store.stop()
    }

    func testNewTurnCancelsOldHideAndNextCompletionStillHides() async throws {
        let store = makeStore(hidden: 0.05)
        finish(store)
        try await waitFor(.compact, in: store)
        store.receive(event(.userPromptSubmit, turn: "next"))
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(store.presentation, .expanded)
        XCTAssertEqual(store.lifecycle, .active)
        store.receive(event(.stop, turn: "next"))
        try await waitFor(.hidden, in: store)
        await store.stop()
    }

    func testRealDefaultTwentyThenOneHundredSecondCountdown() async throws {
        guard ProcessInfo.processInfo.environment["QUOTAVIEW_RUN_REALTIME_HIDE_TEST"] == "1" else {
            throw XCTSkip("Opt in to the real 120-second countdown audit")
        }
        let store = CodexActivityStore(titleClient: CodexAppServerClient(executablePath: nil))
        XCTAssertEqual(AppPreferences.CodexActivityTiming.defaultCompactDelay, 20)
        XCTAssertEqual(AppPreferences.CodexActivityTiming.defaultHiddenDelayAfterCompact, 100)
        var compactAt: Date?
        var hiddenAt: Date?
        store.stateDidChange = { [weak store] in
            guard let store else { return }
            if store.presentation == .compact && compactAt == nil { compactAt = Date() }
            if store.presentation == .hidden && hiddenAt == nil { hiddenAt = Date() }
        }
        let started = Date()
        finish(store)
        let deadline = started.addingTimeInterval(130)
        while store.presentation != .hidden && Date() < deadline {
            deliverLateEvents(to: store)
            store.updateInactivityDelays(compactDelay: 20, hiddenDelayAfterCompact: 100)
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertEqual(store.presentation, .hidden)
        if let compactAt, let hiddenAt {
            let compactElapsed = compactAt.timeIntervalSince(started)
            let hiddenElapsed = hiddenAt.timeIntervalSince(compactAt)
            XCTAssertGreaterThanOrEqual(compactElapsed, 19.9)
            XCTAssertLessThan(compactElapsed, 25)
            XCTAssertGreaterThanOrEqual(hiddenElapsed, 99.9)
            XCTAssertLessThan(hiddenElapsed, 105)
            print("Hide audit: compact after \(compactElapsed)s; hidden after another \(hiddenElapsed)s")
        } else { XCTFail("Missing compact/hidden transitions") }
        deliverLateEvents(to: store)
        XCTAssertEqual(store.presentation, .hidden)
        await store.stop()
    }
}
