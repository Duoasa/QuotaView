import Foundation
import XCTest
@testable import QuotaViewCore

final class CodexActivityModelsTests: XCTestCase {
    func testHookEventsMapToConfirmedVisualStates() {
        let expected: [CodexActivityHookEvent: CodexActivityVisualState] = [
            .sessionStart: .standby,
            .sessionEnd: .standby,
            .userPromptSubmit: .thinking,
            .preToolUse: .working,
            .permissionRequest: .awaitingConfirmation,
            .postToolUse: .thinking,
            .preCompact: .compactingContext,
            .postCompact: .thinking,
            .subagentStart: .working,
            .subagentStop: .thinking,
            .stop: .completed
        ]

        for event in CodexActivityHookEvent.allCases {
            let activity = CodexActivityEvent(
                event: event,
                sessionHash: "session"
            )
            XCTAssertEqual(
                CodexActivityReducer.snapshot(for: activity)?.state,
                expected[event],
                "\(event.rawValue) must keep the approved state semantics"
            )
        }

        let compactResume = CodexActivityEvent(
            event: .sessionStart,
            sessionHash: "session",
            sessionStartSource: .compact
        )
        XCTAssertEqual(
            CodexActivityReducer.snapshot(for: compactResume)?.state,
            .thinking
        )
        XCTAssertEqual(
            CodexActivityReducer.snapshot(for: compactResume)?.operationKey,
            .continuingAfterCompaction
        )

        XCTAssertFalse(
            CodexActivityHookEvent.allCases.contains { event in
                CodexActivityReducer.snapshot(
                    for: CodexActivityEvent(
                        event: event,
                        sessionHash: "session"
                    )
                )?.state == .disconnectedCodex
            },
            "The disconnected state is a local setup presentation, not a synthesized hook event."
        )
    }

    func testToolCategoriesNeverExposeCanonicalToolName() {
        XCTAssertEqual(
            CodexActivityPrivacy.toolCategory(for: "Bash"),
            .shell
        )
        XCTAssertEqual(
            CodexActivityPrivacy.toolCategory(for: "apply_patch"),
            .fileEdit
        )
        XCTAssertEqual(
            CodexActivityPrivacy.toolCategory(
                for: "mcp__filesystem__read_file"
            ),
            .mcp
        )
        XCTAssertEqual(
            CodexActivityPrivacy.toolCategory(for: "spawn_agent"),
            .subagent
        )
        XCTAssertEqual(
            CodexActivityPrivacy.toolCategory(for: "update_plan"),
            .localTool
        )
    }

    func testSessionHashIsStableAndDoesNotContainSourceIdentifier() {
        let identifier = "thr_private-session-id"
        let first = CodexActivityPrivacy.hashIdentifier(identifier)
        let second = CodexActivityPrivacy.hashIdentifier(identifier)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 64)
        XCTAssertFalse(first.contains(identifier))
    }

    func testWorkspacePathIsReducedToLastComponent() {
        XCTAssertEqual(
            CodexActivityPrivacy.workspaceName(
                from: "/Users/example/Documents/QuotaView"
            ),
            "QuotaView"
        )
        XCTAssertNil(CodexActivityPrivacy.workspaceName(from: nil))
    }

    func testThreadMetadataPrefersExplicitNameWithoutUsingPreview() {
        let metadata = CodexThreadMetadata(
            id: "thread",
            sessionId: "session",
            cwd: "/Users/example/Documents/widget",
            name: "QuotaView 0.3.1"
        )
        XCTAssertEqual(
            metadata.privacySafeDisplayName,
            "QuotaView 0.3.1"
        )
        XCTAssertTrue(
            metadata.matches(
                sessionHash:
                    CodexActivityPrivacy.hashIdentifier("thread")
            )
        )
    }

    func testSessionEndHidesImmediatelyAndStopStartsIdleCycle() {
        XCTAssertTrue(
            CodexActivityReducer.shouldHideImmediately(
                after: CodexActivityEvent(
                    event: .sessionEnd,
                    sessionHash: "session"
                )
            )
        )
        XCTAssertTrue(
            CodexActivityReducer.shouldStartInactivityCycle(
                after: CodexActivityEvent(
                    event: .stop,
                    sessionHash: "session"
                )
            )
        )
        XCTAssertFalse(
            CodexActivityReducer.shouldStartInactivityCycle(
                after: CodexActivityEvent(
                    event: .preToolUse,
                    sessionHash: "session"
                )
            )
        )
        XCTAssertFalse(
            CodexActivityReducer.shouldStartInactivityCycle(
                after: CodexActivityEvent(
                    event: .sessionStart,
                    sessionHash: "session",
                    sessionStartSource: .compact
                )
            )
        )
    }
}
