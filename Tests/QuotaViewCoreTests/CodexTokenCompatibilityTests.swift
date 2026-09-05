import Foundation
import XCTest
@testable import QuotaView
@testable import QuotaViewCore

final class CodexTokenCompatibilityTests: XCTestCase {
    private let session = CodexActivityPrivacy.hashIdentifier("thread")
    private let turn = CodexActivityPrivacy.hashIdentifier("turn")

    private func line(_ type: String, _ payload: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["type": type, "payload": payload])
    }

    private func startLine() throws -> Data {
        try line("event_msg", ["type": "task_started", "turn_id": "turn"])
    }

    private func directLine(_ total: Any, thread: String = "thread", turn: String = "turn") throws -> Data {
        try line("token_usage_record", [
            "thread_id": thread, "turn_id": turn,
            "response_id": "private-response", "session_id": "private-session",
            "root_turn_id": "private-root", "private_body": "never retain",
            "usage": ["total_tokens": 100],
            "turn_token_usage": ["total_tokens": total],
            "thread_token_usage": ["total_tokens": 2_000_000]
        ])
    }

    private func legacyLine(_ total: Int64, last: Int64) throws -> Data {
        try line("event_msg", ["type": "token_count", "info": [
            "total_token_usage": ["total_tokens": total],
            "last_token_usage": ["total_tokens": last]
        ]])
    }

    @MainActor
    private func store() -> CodexActivityStore {
        let store = CodexActivityStore(titleClient: CodexAppServerClient(executablePath: nil))
        store.receive(CodexActivityEvent(
            event: .userPromptSubmit, sessionHash: session,
            turnHash: turn, source: .localRollout
        ))
        return store
    }

    private func update(_ total: Int64, last: Int64, direct: Int64? = nil,
                        turn: String? = nil, at: Date = Date()) -> CodexActivityTokenUsageUpdate {
        CodexActivityTokenUsageUpdate(
            sessionHash: session, turnHash: turn ?? self.turn,
            cumulativeTotalTokens: total, lastReportedTotalTokens: last,
            directTurnTotalTokens: direct, occurredAt: at
        )
    }

    func testDirectRecordRequiresActiveMatchingTurnAndDropsPrivateFields() throws {
        var decoder = CodexLocalRolloutLineDecoder(sessionHash: session)
        XCTAssertNil(decoder.decode(line: try directLine(151_228)))
        _ = decoder.decode(line: try startLine())
        XCTAssertNil(decoder.decode(line: try directLine(151_228, thread: "other")))
        XCTAssertNil(decoder.decode(line: try directLine(151_228, turn: "other")))
        let record = try XCTUnwrap(decoder.decode(line: try directLine(151_228)))
        guard case .tokenUsage(let usage) = record.update else { return XCTFail("Expected usage") }
        XCTAssertEqual(usage.directTurnTotalTokens, 151_228)
        XCTAssertEqual(usage.turnHash, turn)
        XCTAssertFalse(String(reflecting: record).contains("private-"))
        XCTAssertFalse(String(reflecting: record).contains("never retain"))
        _ = decoder.decode(line: try line("event_msg", ["type": "task_complete", "turn_id": "turn"]))
        XCTAssertNil(decoder.decode(line: try directLine(151_228)))
    }

    func testMalformedDirectCountsAreRejected() throws {
        var decoder = CodexLocalRolloutLineDecoder(sessionHash: session)
        _ = decoder.decode(line: try startLine())
        for value: Any in [-1, true, 101.5, "151228", 9.223372036854776e18, 99, 2_000_001] {
            XCTAssertNil(decoder.decode(line: try directLine(value)), "Invalid count: \(value)")
        }
    }

    func testLateTerminalCannotClearNewTurnAndIntegerBoundaryIsSafe() throws {
        var decoder = CodexLocalRolloutLineDecoder(sessionHash: session)
        _ = decoder.decode(line: try startLine())
        for type in ["task_complete", "turn_aborted"] {
            XCTAssertNil(decoder.decode(line: try line("event_msg", ["type": type, "turn_id": "old-turn"])))
        }
        let record = try XCTUnwrap(decoder.decode(line: try line("token_usage_record", [
            "thread_id": "thread", "turn_id": "turn",
            "usage": ["total_tokens": 0],
            "turn_token_usage": ["total_tokens": Int64.max],
            "thread_token_usage": ["total_tokens": Int64.max]
        ])))
        guard case .tokenUsage(let usage) = record.update else { return XCTFail("Expected usage") }
        XCTAssertEqual(usage.directTurnTotalTokens, Int64.max)
    }

    @MainActor
    func testLegacyResetAtNewTurnDoesNotSubtractPriorSessionBaseline() async {
        let store = store()
        store.receive(update(32_375_978, last: 100))
        store.receive(CodexActivityEvent(event: .stop, sessionHash: session, turnHash: turn))
        store.receive(CodexActivityEvent(event: .userPromptSubmit, sessionHash: session, turnHash: "second"))
        store.receive(update(151_228, last: 151_228, turn: "second"))
        XCTAssertEqual(store.currentTurnTokenUsage, 151_228)
        await store.stop()
    }

    @MainActor
    func testLegacyResetWithinTurnPreservesSegmentsAndRejectsOutOfOrder() async {
        let store = store()
        let date = Date()
        store.receive(update(10_000, last: 4_000, at: date))
        store.receive(update(16_000, last: 6_000, at: date.addingTimeInterval(1)))
        store.receive(update(2_000, last: 2_000, at: date.addingTimeInterval(2)))
        XCTAssertEqual(store.currentTurnTokenUsage, 12_000)
        store.receive(update(2_000, last: 2_000, at: date.addingTimeInterval(3)))
        XCTAssertEqual(store.currentTurnTokenUsage, 12_000)
        store.receive(update(1_000, last: 1_000, at: date))
        store.receive(update(5_000, last: 3_000, at: date.addingTimeInterval(4)))
        XCTAssertEqual(store.currentTurnTokenUsage, 15_000)
        await store.stop()
    }

    @MainActor
    func testOverflowCannotPoisonNextLegacyDelta() async {
        let store = store()
        store.receive(update(100, last: 100))
        store.receive(update(0, last: 0))
        store.receive(update(Int64.max, last: 0))
        XCTAssertEqual(store.currentTurnTokenUsage, 100)
        store.receive(update(200, last: 100))
        XCTAssertEqual(store.currentTurnTokenUsage, 300)
        await store.stop()
    }

    @MainActor
    func testDirectTotalsWinMixedStreamsDuplicatesAndTerminalFreeze() async {
        let store = store()
        store.receive(update(348_097, last: 348_097))
        store.receive(CodexActivityEvent(event: .stop, sessionHash: session, turnHash: turn))
        store.receive(CodexActivityEvent(event: .userPromptSubmit, sessionHash: session, turnHash: "second"))
        store.receive(update(1_003_450, last: 100, turn: "second"))
        XCTAssertEqual(store.currentTurnTokenUsage, 655_353)
        store.receive(update(2_000_000, last: 100, direct: 1_003_450, turn: "second"))
        XCTAssertEqual(store.currentTurnTokenUsage, 1_003_450)
        store.receive(update(3_000_000, last: 200, turn: "second"))
        store.receive(update(2_000_000, last: 100, direct: 1_003_450, turn: "second"))
        store.receive(update(2_000_000, last: 100, direct: 151_228, turn: "second"))
        XCTAssertEqual(store.currentTurnTokenUsage, 1_003_450)
        store.receive(CodexActivityEvent(event: .stop, sessionHash: session, turnHash: "second"))
        store.receive(update(4_000_000, last: 200, direct: 2_000_000, turn: "second"))
        XCTAssertEqual(store.currentTurnTokenUsage, 1_003_450)
        store.receive(CodexActivityEvent(event: .userPromptSubmit, sessionHash: session, turnHash: "third"))
        store.receive(update(4_000_000, last: 200, direct: 2_000_000, turn: "second"))
        XCTAssertNil(store.currentTurnTokenUsage)
        store.receive(update(100, last: 100, direct: 100, turn: "third"))
        XCTAssertEqual(store.currentTurnTokenUsage, 100)
        await store.stop()
    }

    @MainActor
    func testFirstDirectTotalCorrectsFallbackOverestimate() async {
        let store = store()
        store.receive(update(20_000, last: 20_000))
        store.receive(update(30_000, last: 100, direct: 10_000))
        XCTAssertEqual(store.currentTurnTokenUsage, 10_000)
        await store.stop()
    }

    @MainActor
    func testCompactionAndAsyncQuestionsPreserveTurnProgressAndUsage() async throws {
        var decoder = CodexLocalRolloutLineDecoder(sessionHash: session)
        let store = store()
        _ = decoder.decode(line: try startLine())
        store.receive(CodexActivityEvent(
            event: .preToolUse, sessionHash: session, turnHash: turn,
            planProgress: CodexActivityPlanProgress(completedSteps: 1, inProgressSteps: 1, pendingSteps: 2),
            source: .localRollout, planSource: .localRollout
        ))
        store.receive(update(20_000, last: 100, direct: 10_000))
        let progress = store.snapshot?.approximateProgressFraction
        for type in ["item_started", "item_completed"] {
            let record = try XCTUnwrap(decoder.decode(line: try line("event_msg", [
                "type": type, "thread_id": "thread", "turn_id": "turn",
                "item": ["type": "ContextCompaction", "id": "private-compaction"]
            ])))
            guard case .activity(let event) = record.update else { return XCTFail("Expected compaction") }
            store.receive(event)
            XCTAssertEqual(store.snapshot?.state, type == "item_started" ? .compactingContext : .thinking)
            XCTAssertEqual(store.currentTurnTokenUsage, 10_000)
            XCTAssertEqual(store.snapshot?.approximateProgressFraction, progress)
            XCTAssertEqual(store.lifecycle, .active)
        }
        XCTAssertNil(decoder.decode(line: try line("compacted", ["window_id": "private-window", "message": "private"])))
        for name in ["new_context", "request_user_input_async"] {
            let record = try XCTUnwrap(decoder.decode(line: try line("response_item", [
                "type": "function_call", "name": name, "arguments": "{}"
            ])))
            guard case .activity(let event) = record.update else { return XCTFail("Expected tool") }
            store.receive(event)
            XCTAssertEqual(store.lifecycle, .active)
            XCTAssertNotEqual(store.snapshot?.state, .awaitingConfirmation)
            XCTAssertFalse(store.isConfirmationReminderActive)
            XCTAssertEqual(store.currentTurnTokenUsage, 10_000)
        }
        XCTAssertNil(decoder.decode(line: try line("event_msg", [
            "type": "item_completed", "thread_id": "thread", "turn_id": "turn",
            "item": ["type": "AgentMessage", "phase": "final_answer", "delivery": "async", "questions": [["title": "private"]]]
        ])))
        store.receive(update(22_000, last: 2_000, direct: 12_000))
        XCTAssertEqual(store.currentTurnTokenUsage, 12_000)
        await store.stop()
    }

    func testBootstrapKeepsDirectUsageWithoutOrdinalsAndDoesNotReplayCompletion() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sessions = root.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = sessions.appendingPathComponent("rollout.jsonl")
        var data = Data()
        for record in [
            try line("session_meta", ["id": "thread", "cwd": "/private/widget"]),
            try startLine(),
            try legacyLine(100, last: 100),
            try directLine(151_228),
            try line("compacted", ["window_id": "private-window"]),
            try directLine(1_003_450),
            try legacyLine(200, last: 100)
        ] { data.append(record); data.append(0x0A) }
        try data.write(to: file)
        let sink = TokenCompatibilitySink()
        let replayed = expectation(description: "Automatic startup replay")
        replayed.expectedFulfillmentCount = 4
        let client = CodexLocalRolloutActivityClient(configuration: .init(isEnabled: true, codexHomeURL: root))
        // start() already schedules polling. Driving a second poll while its
        // async handler is suspended can replay the same bootstrap twice.
        await client.start(handler: { record, _ in
            await sink.append(record)
            replayed.fulfill()
        }, connectionStateHandler: { _ in })
        await fulfillment(of: [replayed], timeout: 3)
        await client.stop()
        let records = await sink.records
        let totals = records.compactMap { record -> Int64? in
            guard case .tokenUsage(let update) = record.update else { return nil }
            return update.directTurnTotalTokens
        }
        XCTAssertEqual(totals, [1_003_450])
        let legacy = records.compactMap { record -> Int64? in
            guard case .tokenUsage(let update) = record.update, update.directTurnTotalTokens == nil else { return nil }
            return update.cumulativeTotalTokens
        }
        XCTAssertEqual(legacy, [100, 200])
        var completed = data
        completed.append(try line("event_msg", ["type": "task_complete", "turn_id": "turn"]))
        completed.append(0x0A)
        try completed.write(to: file)
        let completedSink = TokenCompatibilitySink()
        let unexpectedReplay = expectation(description: "No historical completion replay")
        unexpectedReplay.isInverted = true
        let completedClient = CodexLocalRolloutActivityClient(configuration: .init(isEnabled: true, codexHomeURL: root))
        await completedClient.start(handler: { record, _ in
            await completedSink.append(record)
            unexpectedReplay.fulfill()
        }, connectionStateHandler: { _ in })
        await fulfillment(of: [unexpectedReplay], timeout: 0.6)
        await completedClient.stop()
        let completedRecords = await completedSink.records
        XCTAssertTrue(completedRecords.isEmpty)
    }
}

private actor TokenCompatibilitySink {
    var records: [CodexLocalRolloutDecodedRecord] = []
    func append(_ record: CodexLocalRolloutDecodedRecord) { records.append(record) }
}
