import Foundation
import XCTest
@testable import QuotaViewCore

final class AuditLifecycleSessionEndTests: XCTestCase {
    private func event(_ type: CodexActivityHookEvent, turn: String? = "new", source: CodexActivityEventSource = .localRollout,
                       at: TimeInterval, session: String = "same") -> CodexActivityEvent {
        .init(event: type, sessionHash: session, turnHash: turn, source: source,
              occurredAt: Date(timeIntervalSince1970: at))
    }

    func testLateSessionEndCannotTombstoneANewerTurn() {
        for oldTurn: String? in [nil, "old"] {
            for priorHook in [false, true] {
                for endFirst in [false, true] {
                    var registry = CodexActivityTaskRegistry()
                    if endFirst {
                        XCTAssertNil(registry.admit(event(.sessionEnd, turn: oldTurn, source: .hook, at: 90), kind: .user, selectedSession: nil))
                    }
                    if priorHook {
                        _ = registry.admit(event(.userPromptSubmit, turn: "old", source: .hook, at: 80), kind: .user, selectedSession: nil)
                    }
                    _ = registry.admit(event(.userPromptSubmit, at: 100), kind: .user, selectedSession: nil)
                    XCTAssertNil(registry.admit(event(.sessionEnd, turn: oldTurn, source: .hook, at: 90), kind: .user, selectedSession: "same"))
                    XCTAssertNotNil(registry.admit(event(.preToolUse, at: 110), kind: .user, selectedSession: "same"))
                    XCTAssertTrue(registry.permitsPublicAttachment(session: "same", turn: "new", source: .localRollout, occurredAt: Date(timeIntervalSince1970: 110)))
                }
            }
        }
    }

    func testFreshSessionEndSettlesOnlyItsOwnSessionAndMatchingTurn() {
        var registry = CodexActivityTaskRegistry()
        _ = registry.admit(event(.userPromptSubmit, at: 100), kind: .user, selectedSession: nil)
        _ = registry.admit(event(.userPromptSubmit, at: 100, session: "parallel"), kind: .user, selectedSession: "same")
        XCTAssertNil(registry.admit(event(.sessionEnd, turn: "foreign", source: .hook, at: 110), kind: .user, selectedSession: "same"))
        XCTAssertNotNil(registry.admit(event(.sessionEnd, turn: nil, source: .hook, at: 110), kind: .user, selectedSession: "same"))
        XCTAssertNil(registry.admit(event(.preToolUse, at: 120), kind: .user, selectedSession: "same"))
        XCTAssertNotNil(registry.admit(event(.preToolUse, at: 120, session: "parallel"), kind: .user, selectedSession: "same"))
    }
}
