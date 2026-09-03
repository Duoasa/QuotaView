import Foundation
import XCTest
@testable import QuotaViewCore

final class CodexAppServerActivityNotificationDecoderTests: XCTestCase {
    func testLocalRolloutKeepsOnlyLifecycleAndTokenFields() throws {
        let sessionHash = CodexActivityPrivacy.hashIdentifier(
            "private-session"
        )
        let turnHash = CodexActivityPrivacy.hashIdentifier("private-turn")
        var decoder = CodexLocalRolloutLineDecoder(
            sessionHash: sessionHash,
            workspaceName: "widget"
        )

        let started = try XCTUnwrap(
            decoder.decode(line: Data(
                #"{"timestamp":"2026-09-04T00:00:00.000Z","type":"event_msg","ordinal":1,"payload":{"type":"task_started","turn_id":"private-turn","private_prompt":"do not retain"}}"#.utf8
            ))
        )
        guard case .activity(let startedEvent) = started.update else {
            return XCTFail("Expected task start")
        }
        XCTAssertEqual(startedEvent.event, .userPromptSubmit)
        XCTAssertEqual(startedEvent.source, .localRollout)
        XCTAssertEqual(startedEvent.sessionHash, sessionHash)
        XCTAssertEqual(startedEvent.turnHash, turnHash)
        XCTAssertEqual(startedEvent.workspaceName, "widget")

        let tokens = try XCTUnwrap(
            decoder.decode(line: Data(
                #"{"timestamp":"2026-09-04T00:00:01.000Z","type":"event_msg","ordinal":2,"payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":90,"output_tokens":10,"total_tokens":100},"last_token_usage":{"input_tokens":18,"output_tokens":2,"total_tokens":20}},"rate_limits":{"private":"ignored"}}}"#.utf8
            ))
        )
        guard case .tokenUsage(let tokenUpdate) = tokens.update else {
            return XCTFail("Expected token usage")
        }
        XCTAssertEqual(tokenUpdate.sessionHash, sessionHash)
        XCTAssertEqual(tokenUpdate.turnHash, turnHash)
        XCTAssertEqual(tokenUpdate.cumulativeTotalTokens, 100)
        XCTAssertEqual(tokenUpdate.lastReportedTotalTokens, 20)

        let completed = try XCTUnwrap(
            decoder.decode(line: Data(
                #"{"timestamp":"2026-09-04T00:00:02.000Z","type":"event_msg","ordinal":3,"payload":{"type":"task_complete","turn_id":"private-turn","last_agent_message":"do not retain"}}"#.utf8
            ))
        )
        guard case .activity(let completedEvent) = completed.update else {
            return XCTFail("Expected task completion")
        }
        XCTAssertEqual(completedEvent.event, .stop)
        XCTAssertEqual(
            completedEvent.turnCompletionStatus,
            .completed
        )
        XCTAssertFalse(String(reflecting: started).contains("private-turn"))
        XCTAssertFalse(String(reflecting: completed).contains("do not retain"))
    }

    func testLocalRolloutParsesDirectAndWrappedPlansAsCountsOnly()
        throws {
        let sessionHash = CodexActivityPrivacy.hashIdentifier("session")
        var decoder = CodexLocalRolloutLineDecoder(
            sessionHash: sessionHash
        )
        _ = decoder.decode(line: Data(
            #"{"type":"event_msg","ordinal":1,"payload":{"type":"task_started","turn_id":"turn"}}"#.utf8
        ))

        let direct = try XCTUnwrap(
            decoder.decode(line: Data(
                #"{"type":"response_item","ordinal":2,"payload":{"type":"function_call","name":"update_plan","arguments":"{\"explanation\":\"private\",\"plan\":[{\"step\":\"private first\",\"status\":\"completed\"},{\"step\":\"private second\",\"status\":\"in_progress\"}] }"}}"#.utf8
            ))
        )
        guard case .activity(let directEvent) = direct.update else {
            return XCTFail("Expected direct plan")
        }
        XCTAssertEqual(
            directEvent.planProgress,
            CodexActivityPlanProgress(
                completedSteps: 1,
                inProgressSteps: 1,
                pendingSteps: 0
            )
        )
        XCTAssertEqual(directEvent.planSource, .localRollout)

        let wrappedObject: [String: Any] = [
            "type": "response_item",
            "ordinal": 3,
            "payload": [
                "type": "custom_tool_call",
                "name": "exec",
                "input": """
                // tools.update_plan({plan:[{status:'completed'}]})
                const privateText = "tools.update_plan({plan:[{status:'completed'}]})";
                await tools.update_plan({plan:[
                  {step:'private first',status:'completed'},
                  {step:'private second',status:'in_progress'},
                  {step:'private third',status:'pending'}
                ]});
                """
            ]
        ]
        let wrappedLine = try JSONSerialization.data(
            withJSONObject: wrappedObject
        )
        let wrapped = try XCTUnwrap(decoder.decode(line: wrappedLine))
        guard case .activity(let wrappedEvent) = wrapped.update else {
            return XCTFail("Expected wrapped plan")
        }
        XCTAssertEqual(
            wrappedEvent.planProgress,
            CodexActivityPlanProgress(
                completedSteps: 1,
                inProgressSteps: 1,
                pendingSteps: 1
            )
        )
        XCTAssertFalse(String(reflecting: wrapped).contains("private first"))
        XCTAssertFalse(String(reflecting: wrapped).contains("privateText"))
    }

    func testLocalRolloutIgnoresContentRecordsAndMalformedCounts() {
        var decoder = CodexLocalRolloutLineDecoder(
            sessionHash: CodexActivityPrivacy.hashIdentifier("session")
        )
        XCTAssertNil(decoder.decode(line: Data(
            #"{"type":"response_item","payload":{"type":"message","content":[{"text":"private response"}]}}"#.utf8
        )))
        XCTAssertNil(decoder.decode(line: Data(
            #"{"type":"response_item","payload":{"type":"reasoning","summary":["private reasoning"]}}"#.utf8
        )))
        _ = decoder.decode(line: Data(
            #"{"type":"event_msg","payload":{"type":"task_started","turn_id":"turn"}}"#.utf8
        ))
        XCTAssertNil(decoder.decode(line: Data(
            #"{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":20.5},"last_token_usage":{"total_tokens":10}}}}"#.utf8
        )))
        XCTAssertNil(decoder.decode(line: Data(repeating: 0x20, count:
            CodexLocalRolloutLineDecoder.maximumLineBytes + 1
        )))
    }

    func testLocalRolloutClientReplaysOnlyActiveTurnThenTailsCompletion()
        async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sessions = root
            .appendingPathComponent("sessions/2026/09/04", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sessions,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let rollout = sessions.appendingPathComponent("active.jsonl")
        let initial = """
        {"type":"session_meta","payload":{"id":"private-session","cwd":"/private/widget"}}
        {"type":"event_msg","ordinal":1,"payload":{"type":"task_started","turn_id":"private-turn"}}
        {"type":"event_msg","ordinal":2,"payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":100},"last_token_usage":{"total_tokens":20}}}}

        """
        try Data(initial.utf8).write(to: rollout)

        let sink = LocalRolloutSink()
        let client = CodexLocalRolloutActivityClient(
            configuration: .init(
                isEnabled: true,
                codexHomeURL: root,
                pollIntervalSeconds: 0.1,
                candidateRefreshSeconds: 0.1,
                maximumCandidateCount: 2,
                startupTailBytes: 1_048_576
            )
        )
        await client.start(
            handler: { record, replay in
                await sink.append(record: record, replay: replay)
            },
            connectionStateHandler: { state in
                await sink.append(state: state)
            }
        )
        try await Task.sleep(nanoseconds: 300_000_000)

        let handle = try FileHandle(forWritingTo: rollout)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(
            "{\"type\":\"event_msg\",\"ordinal\":3,\"payload\":{\"type\":\"task_complete\",\"turn_id\":\"private-turn\"}}\n".utf8
        ))
        try handle.close()
        try await Task.sleep(nanoseconds: 300_000_000)
        await client.stop()

        let result = await sink.snapshot()
        XCTAssertTrue(result.states.contains(.connected))
        XCTAssertEqual(result.records.filter(\.replay).count, 2)
        XCTAssertEqual(result.records.filter { !$0.replay }.count, 1)
        guard case .activity(let completion) = result.records.last?.record.update
        else {
            return XCTFail("Expected tailed completion")
        }
        XCTAssertEqual(completion.event, .stop)
    }

    func testNativePlanKeepsOnlyStatusCountsAndHashedIdentifiers()
        throws {
        let line = #"{"method":"turn/plan/updated","emittedAtMs":1788451200123,"params":{"threadId":"private-thread","turnId":"private-turn","explanation":"private explanation","plan":[{"step":"private first","status":"completed"},{"step":"private second","status":"inProgress"},{"step":"private third","status":"pending"},{"step":"private fourth","status":"pending"}]}}"#

        let event = try XCTUnwrap(
            CodexAppServerActivityNotificationDecoder.decode(line: line)
        )

        XCTAssertEqual(event.schemaVersion, 3)
        XCTAssertEqual(event.event, .preToolUse)
        XCTAssertEqual(event.source, .appServer)
        XCTAssertEqual(event.planSource, .appServer)
        XCTAssertEqual(
            event.sessionHash,
            CodexActivityPrivacy.hashIdentifier("private-thread")
        )
        XCTAssertEqual(
            event.turnHash,
            CodexActivityPrivacy.hashIdentifier("private-turn")
        )
        XCTAssertEqual(
            event.planProgress,
            CodexActivityPlanProgress(
                completedSteps: 1,
                inProgressSteps: 1,
                pendingSteps: 2
            )
        )
        XCTAssertEqual(
            event.occurredAt.timeIntervalSince1970,
            1_788_451_200.123,
            accuracy: 0.0001
        )
        let reflected = String(reflecting: event)
        XCTAssertFalse(reflected.contains("private first"))
        XCTAssertFalse(reflected.contains("private explanation"))
        XCTAssertFalse(reflected.contains("private-thread"))
    }

    func testTurnOutcomesKeepCompletionTruth() throws {
        let completed = try XCTUnwrap(decodeTurn(status: "completed"))
        XCTAssertEqual(completed.event, .stop)
        XCTAssertEqual(completed.turnCompletionStatus, .completed)
        XCTAssertEqual(
            CodexActivityReducer.snapshot(for: completed)?
                .approximateProgressFraction,
            1
        )

        let interrupted = try XCTUnwrap(decodeTurn(status: "interrupted"))
        XCTAssertEqual(interrupted.event, .interrupt)
        XCTAssertEqual(interrupted.turnCompletionStatus, .interrupted)
        XCTAssertEqual(
            CodexActivityReducer.snapshot(for: interrupted)?.state,
            .standby
        )
        XCTAssertNil(
            CodexActivityReducer.snapshot(for: interrupted)?
                .approximateProgressFraction
        )

        let failed = try XCTUnwrap(decodeTurn(status: "failed"))
        XCTAssertEqual(failed.event, .stop)
        XCTAssertEqual(failed.turnCompletionStatus, .failed)
        XCTAssertEqual(
            CodexActivityReducer.snapshot(for: failed)?.state,
            .error
        )
        XCTAssertNil(
            CodexActivityReducer.snapshot(for: failed)?
                .approximateProgressFraction
        )
        XCTAssertNil(decodeTurn(status: "unknown"))
    }

    func testGoalAndWaitNotificationsDoNotInventPlanProgress() throws {
        let goal = try XCTUnwrap(
            CodexAppServerActivityNotificationDecoder.decode(
                line: #"{"method":"thread/goal/updated","params":{"threadId":"thread","turnId":"turn","goal":{"objective":"private objective","status":"active"}}}"#
            )
        )
        XCTAssertEqual(goal.toolCategory, .goal)
        XCTAssertEqual(goal.goalStatus, .active)
        XCTAssertNil(goal.planProgress)
        XCTAssertNil(
            CodexActivityReducer.snapshot(for: goal)?
                .approximateProgressFraction
        )
        XCTAssertFalse(String(reflecting: goal).contains("private objective"))

        let approval = try XCTUnwrap(
            CodexAppServerActivityNotificationDecoder.decode(
                line: #"{"method":"thread/status/changed","params":{"threadId":"thread","status":{"type":"active","activeFlags":["waitingOnApproval"]}}}"#
            )
        )
        XCTAssertEqual(approval.waitReason, .approval)
        XCTAssertEqual(
            CodexActivityReducer.snapshot(for: approval)?.operationKey,
            .awaitingApproval
        )

        let userInput = try XCTUnwrap(
            CodexAppServerActivityNotificationDecoder.decode(
                line: #"{"method":"thread/status/changed","params":{"threadId":"thread","status":{"type":"active","activeFlags":["waitingOnUserInput"]}}}"#
            )
        )
        XCTAssertEqual(userInput.waitReason, .userInput)
        XCTAssertEqual(
            CodexActivityReducer.snapshot(for: userInput)?.operationKey,
            .awaitingUserInput
        )
    }

    func testTokenUsageKeepsOnlyCountsAndHashedTurnIdentity() throws {
        let line = #"{"method":"thread/tokenUsage/updated","emittedAtMs":1788451200456,"params":{"threadId":"private-thread","turnId":"private-turn","tokenUsage":{"total":{"inputTokens":12000,"cachedInputTokens":9000,"outputTokens":800,"reasoningOutputTokens":200,"totalTokens":13000},"last":{"inputTokens":4000,"cachedInputTokens":3000,"outputTokens":500,"reasoningOutputTokens":100,"totalTokens":4500},"modelContextWindow":272000}}}"#

        let update = try XCTUnwrap(
            CodexAppServerActivityNotificationDecoder.decodeTokenUsage(
                line: line
            )
        )

        XCTAssertEqual(
            update.sessionHash,
            CodexActivityPrivacy.hashIdentifier("private-thread")
        )
        XCTAssertEqual(
            update.turnHash,
            CodexActivityPrivacy.hashIdentifier("private-turn")
        )
        XCTAssertEqual(update.cumulativeTotalTokens, 13_000)
        XCTAssertEqual(update.lastReportedTotalTokens, 4_500)
        XCTAssertEqual(
            update.occurredAt.timeIntervalSince1970,
            1_788_451_200.456,
            accuracy: 0.0001
        )
        XCTAssertFalse(String(reflecting: update).contains("private-thread"))
        XCTAssertFalse(String(reflecting: update).contains("private-turn"))
        XCTAssertNil(
            CodexAppServerActivityNotificationDecoder.decode(line: line)
        )
    }

    func testMalformedTokenUsageIsRejected() {
        XCTAssertNil(
            CodexAppServerActivityNotificationDecoder.decodeTokenUsage(
                line: #"{"method":"thread/tokenUsage/updated","params":{"threadId":"thread","turnId":"turn","tokenUsage":{"total":{"totalTokens":100},"last":{"totalTokens":101}}}}"#
            )
        )
        XCTAssertNil(
            CodexAppServerActivityNotificationDecoder.decodeTokenUsage(
                line: #"{"method":"thread/tokenUsage/updated","params":{"threadId":"thread","turnId":"turn","tokenUsage":{"total":{"totalTokens":100.5},"last":{"totalTokens":20}}}}"#
            )
        )
        XCTAssertNil(
            CodexAppServerActivityNotificationDecoder.decodeTokenUsage(
                line: #"{"method":"thread/tokenUsage/updated","params":{"threadId":"thread","turnId":"","tokenUsage":{"total":{"totalTokens":100},"last":{"totalTokens":20}}}}"#
            )
        )
    }

    func testMalformedUnknownAndOversizedPlansAreRejected() throws {
        XCTAssertNil(
            CodexAppServerActivityNotificationDecoder.decode(
                line: #"{"id":1,"result":{}}"#
            )
        )
        XCTAssertNil(
            CodexAppServerActivityNotificationDecoder.decode(
                line: #"{"method":"turn/plan/updated","params":{"threadId":"thread","turnId":"turn","plan":[{"status":"doing"}]}}"#
            )
        )

        let plan = (0...CodexActivityPlanProgress.maximumStepCount).map {
            ["step": "private \($0)", "status": "pending"]
        }
        let object: [String: Any] = [
            "method": "turn/plan/updated",
            "params": [
                "threadId": "thread",
                "turnId": "turn",
                "plan": plan
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: object)
        XCTAssertNil(
            CodexAppServerActivityNotificationDecoder.decode(data: data)
        )
    }

    private func decodeTurn(
        status: String
    ) -> CodexActivityEvent? {
        CodexAppServerActivityNotificationDecoder.decode(
            line: """
            {"method":"turn/completed","params":{"threadId":"thread","turn":{"id":"turn","status":"\(status)"}}}
            """
        )
    }
}

private actor LocalRolloutSink {
    private(set) var records: [(
        record: CodexLocalRolloutDecodedRecord,
        replay: Bool
    )] = []
    private(set) var states: [CodexSharedAppServerConnectionState] = []

    func append(record: CodexLocalRolloutDecodedRecord, replay: Bool) {
        records.append((record, replay))
    }

    func append(state: CodexSharedAppServerConnectionState) {
        states.append(state)
    }

    func snapshot() -> (
        records: [(record: CodexLocalRolloutDecodedRecord, replay: Bool)],
        states: [CodexSharedAppServerConnectionState]
    ) {
        (records, states)
    }
}
