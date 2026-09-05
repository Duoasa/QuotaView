import Foundation
import XCTest
import SQLite3
@testable import QuotaViewCore
@testable import QuotaView

final class CodexActivityTaskContractTests: XCTestCase {
    private func event(_ type: CodexActivityHookEvent, session: String = "user", turn: String? = "one",
                       source: CodexActivityEventSource = .localRollout, at: Date = Date()) -> CodexActivityEvent {
        .init(event: type, sessionHash: session, turnHash: turn, source: source, occurredAt: at)
    }

    func testEverySourceRejectsInternalExecutionUnitsAndUnownedTerminals() {
        for source: CodexActivityEventSource in [.hook, .appServer, .localRollout] {
            for type in CodexActivityHookEvent.allCases {
                var registry = CodexActivityTaskRegistry()
                XCTAssertNil(registry.admit(event(type, source: source), kind: .internalTask, selectedSession: nil))
            }
            var registry = CodexActivityTaskRegistry()
            XCTAssertNil(registry.admit(event(.stop, source: source), kind: .user, selectedSession: nil))
        }
    }

    func testMetadataClassifiesExecutionKindRatherThanGuardianName() {
        XCTAssertEqual(CodexActivitySessionKind.classify(source: ["subagent": ["other": "reviewer"]]), .internalTask)
        XCTAssertEqual(CodexActivitySessionKind.classify(source: "vscode", threadSource: "guardian_review"), .internalTask)
        XCTAssertEqual(CodexActivitySessionKind.classify(source: "{\"subagent\":\"fork\"}"), .internalTask)
        XCTAssertEqual(CodexActivitySessionKind.classify(source: "vscode", threadSource: "user"), .user)
        XCTAssertEqual(CodexActivitySessionKind.classify(source: "future-host"), .unknown)
    }

    func testUnscopedOrWeakerTerminalCannotCloseNativeTurn() {
        var registry = CodexActivityTaskRegistry()
        _ = registry.admit(event(.userPromptSubmit), kind: .user, selectedSession: nil)
        XCTAssertNil(registry.admit(event(.stop, turn: nil), kind: .user, selectedSession: "user"))
        XCTAssertNil(registry.admit(event(.stop, source: .hook), kind: .user, selectedSession: "user"))
        XCTAssertNotNil(registry.admit(event(.stop), kind: .user, selectedSession: "user"))
        XCTAssertNil(registry.admit(event(.userPromptSubmit), kind: .user, selectedSession: "user"))
    }

    func testUnknownTaskCannotSelectOverVerifiedUserButCanSettleInBackground() {
        var registry = CodexActivityTaskRegistry()
        _ = registry.admit(event(.userPromptSubmit, session: "legacy", source: .hook), kind: .unknown, selectedSession: nil)
        _ = registry.admit(event(.userPromptSubmit), kind: .user, selectedSession: "legacy")
        let background = registry.admit(event(.preToolUse, session: "legacy", source: .hook), kind: .unknown, selectedSession: "user")
        XCTAssertEqual(background?.selectsTask, false)
        let terminal = registry.admit(event(.stop, session: "legacy", source: .hook), kind: .unknown, selectedSession: "user")
        XCTAssertEqual(terminal?.selectsTask, false)
        XCTAssertNil(registry.admit(event(.permissionRequest, session: "legacy", turn: nil, source: .hook), kind: .unknown, selectedSession: "user"))
    }

    @MainActor
    func testActiveToActiveTaskSwitchResetsProductionProgressBinding() async throws {
        let store = CodexActivityStore(titleClient: CodexAppServerClient(executablePath: nil))
        store.receive(event(.userPromptSubmit))
        store.receive(.init(event: .preToolUse, sessionHash: "user", turnHash: "one",
                            planProgress: .init(completedSteps: 3, inProgressSteps: 1, pendingSteps: 0),
                            source: .localRollout, planSource: .localRollout))
        let first = try XCTUnwrap(store.snapshot?.taskIdentity)
        var projection = CodexActivityStateSmokeProgressProjection()
        XCTAssertTrue(projection.bindTask(first))
        _ = projection.resolve(approximateProgressFraction: 0.775, elapsed: 1, reduceMotion: true)
        XCTAssertFalse(projection.bindTask(first))
        XCTAssertEqual(projection.displayedFrontPosition, 0.775)
        store.receive(event(.userPromptSubmit, turn: "two"))
        let second = try XCTUnwrap(store.snapshot?.taskIdentity)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(store.lifecycle, .active)
        XCTAssertNil(store.snapshot?.approximateProgressFraction)
        XCTAssertTrue(projection.bindTask(second))
        XCTAssertNil(projection.displayedFrontPosition)
        XCTAssertLessThan(projection.resolve(approximateProgressFraction: 0.025, elapsed: 0.016, reduceMotion: false), 0.025)
        await store.stop()
    }

    @MainActor
    func testLateSessionStartAndWeakerClockDoNotResetCurrentTurn() async {
        let store = CodexActivityStore(titleClient: CodexAppServerClient(executablePath: nil))
        let date = Date()
        store.receive(event(.userPromptSubmit, at: date))
        store.receive(event(.permissionRequest, source: .hook, at: date.addingTimeInterval(10)))
        // Arrival-time Hook clocks cannot suppress a newer native turn fact.
        store.receive(event(.userPromptSubmit, turn: "two", at: date.addingTimeInterval(1)))
        XCTAssertEqual(store.snapshot?.taskIdentity?.turnHash, "two")
        store.receive(.init(event: .sessionStart, sessionHash: "user", sessionStartSource: .resume, source: .hook,
                            occurredAt: date.addingTimeInterval(11)))
        XCTAssertEqual(store.lifecycle, .active)
        XCTAssertEqual(store.snapshot?.taskIdentity?.turnHash, "two")
        await store.stop()
    }

    func testRegistryBoundsSessionsWithoutEvictingSelectedTask() {
        var registry = CodexActivityTaskRegistry()
        _ = registry.admit(event(.userPromptSubmit), kind: .user, selectedSession: nil)
        var evicted: [String] = []
        for i in 0..<256 {
            evicted += registry.admit(event(.userPromptSubmit, session: "background-\(i)"), kind: .user,
                                      selectedSession: "user")?.evictedSessions ?? []
        }
        XCTAssertEqual(evicted.count, 129)
        XCTAssertFalse(evicted.contains("user"))
        XCTAssertNotNil(registry.admit(event(.stop), kind: .user, selectedSession: "user"))
    }

    func testLegacySessionMetadataThenPromptCreatesActiveTurnAndOverflowIsRejected() {
        var registry = CodexActivityTaskRegistry()
        _ = registry.admit(event(.sessionStart, turn: nil, source: .hook), kind: .unknown, selectedSession: nil)
        let start = registry.admit(event(.userPromptSubmit, turn: nil, source: .hook), kind: .unknown, selectedSession: "user")
        XCTAssertEqual(start?.startsTurn, true)
        XCTAssertEqual(start?.duplicateStart, false)
        XCTAssertNil(CodexActivityPlanProgress(completedSteps: Int.max, inProgressSteps: 1, pendingSteps: 1).approximateFraction)
    }

    func testHookClassifierUsesLocalMetadataBeforeAdmission() async throws {
        let root = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(root.appendingPathComponent("state_5.sqlite").path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, "CREATE TABLE threads(id TEXT,source TEXT,thread_source TEXT,updated_at_ms INTEGER); INSERT INTO threads VALUES('internal','vscode','guardian_review',1);", nil, nil, nil), SQLITE_OK)
        let classifier = CodexActivitySessionClassifier(codexHome: root)
        let incoming = event(.userPromptSubmit, session: CodexActivityPrivacy.hashIdentifier("internal"), source: .hook)
        let kind = await classifier.kind(for: incoming)
        XCTAssertEqual(kind, .internalTask)
        var registry = CodexActivityTaskRegistry()
        XCTAssertNil(registry.admit(incoming, kind: kind, selectedSession: nil))
    }

    func testLocalReaderStopRestartDuringCallbackCannotPublishOldRemainder() async throws {
        let root = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try rollout([start(), token(100), token(200)]).write(to: root.appendingPathComponent("sessions/user.jsonl"))
        let oldSink = ContractRecordSink(), newSink = ContractRecordSink()
        let replay = expectation(description: "new generation startup and token segments")
        replay.expectedFulfillmentCount = 2
        let client = CodexLocalRolloutActivityClient(configuration: .init(isEnabled: true, codexHomeURL: root))
        await client.start(handler: { record, _ in
            await oldSink.append(record)
            await client.stop()
            await client.start(handler: { record, _ in
                await newSink.append(record)
                replay.fulfill()
            }, connectionStateHandler: { _ in })
        }, connectionStateHandler: { _ in })
        await fulfillment(of: [replay], timeout: 3)
        await client.stop()
        let oldCount = await oldSink.records.count
        let newCount = await newSink.records.count
        XCTAssertEqual(oldCount, 1)
        XCTAssertEqual(newCount, 2)
        let recovered = await newSink.records.last
        guard case .tokenUsageReplay(let segments) = recovered?.update else { return XCTFail("recovered segments expected") }
        XCTAssertEqual(segments.map(\.cumulativeTotalTokens), [100, 200])
    }

    func testReentrantPollCannotReplayCommittedBootstrapOrDuplicateAppend() async throws {
        let root = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("sessions/user.jsonl")
        try rollout([start()]).write(to: file)
        let sink = ContractRecordSink()
        let replay = expectation(description: "one start and one appended update")
        replay.expectedFulfillmentCount = 2
        let client = CodexLocalRolloutActivityClient(configuration: .init(isEnabled: true, codexHomeURL: root))
        let appended = try jsonLine(token(100))
        await client.start(handler: { record, _ in
            await sink.append(record)
            if case .activity = record.update {
                let handle = try! FileHandle(forWritingTo: file)
                try! handle.seekToEnd(); try! handle.write(contentsOf: appended); try! handle.close()
                await client.pollOnceForTesting()
            }
            replay.fulfill()
        }, connectionStateHandler: { _ in })
        await fulfillment(of: [replay], timeout: 3)
        await client.pollOnceForTesting()
        await client.stop()
        let count = await sink.records.count
        XCTAssertEqual(count, 2)
    }

    func testDirectorySymlinkOutsideSessionsIsNotReadableActivity() async throws {
        let root = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = root.appendingPathComponent("outside.jsonl")
        try rollout([start()]).write(to: outside)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("sessions/escape.jsonl"), withDestinationURL: outside)
        let unexpected = expectation(description: "no escaped rollout or false connected health")
        unexpected.isInverted = true
        let client = CodexLocalRolloutActivityClient(configuration: .init(isEnabled: true, codexHomeURL: root))
        await client.start(handler: { _, _ in unexpected.fulfill() }, connectionStateHandler: { state in
            if state == .connected { unexpected.fulfill() }
        })
        await fulfillment(of: [unexpected], timeout: 0.25)
        await client.stop()
    }

    func testSharedNotificationIngressRequiresThreadMetadataAndRejectsInternalTasks() async throws {
        let sink = ContractRecordSink()
        let client = CodexSharedAppServerActivityClient(configuration: .init(
            isEnabled: false, socketURL: URL(fileURLWithPath: "/tmp/unused-quotaview-test.sock"), executablePath: nil
        ))
        await client.start(handler: { event in
            await sink.append(.init(eventID: nil, update: .activity(event)))
        }, connectionStateHandler: { _ in })
        func notify(_ method: String, _ params: [String: Any]) async throws {
            try await client.handleJSONMessage(JSONSerialization.data(withJSONObject: ["method": method, "params": params]))
        }
        try await notify("turn/started", ["threadId": "unclassified", "turn": ["id": "one"]])
        for (id, source) in [("internal", ["subagent": ["other": "reviewer"]] as Any), ("user", "vscode" as Any)] {
            try await notify("thread/started", ["thread": ["id": id, "source": source]])
            try await notify("turn/started", ["threadId": id, "turn": ["id": "one"]])
            try await notify("turn/completed", ["threadId": id, "turn": ["id": "one", "status": "completed"]])
        }
        await client.stop()
        let records = await sink.records
        XCTAssertEqual(records.count, 2)
        for record in records {
            guard case .activity(let event) = record.update else { return XCTFail("activity expected") }
            XCTAssertEqual(event.sessionHash, CodexActivityPrivacy.hashIdentifier("user"))
            XCTAssertEqual(event.sessionKind, .user)
        }
    }

    func testOversizedIncrementalLineCannotDecodeAValidJSONSuffix() async throws {
        let root = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("sessions/user.jsonl")
        try rollout([start()]).write(to: file)
        let sink = ContractRecordSink()
        let replay = expectation(description: "start plus valid update after discarded oversized line")
        replay.expectedFulfillmentCount = 2
        var appended = Data(repeating: 32, count: 2 * 1_048_576 + 1)
        appended.append(try jsonLine(token(999)))
        appended.append(try jsonLine(token(100)))
        let bytes = appended
        let client = CodexLocalRolloutActivityClient(configuration: .init(isEnabled: true, codexHomeURL: root))
        await client.start(handler: { record, _ in
            await sink.append(record)
            if case .activity = record.update {
                let handle = try! FileHandle(forWritingTo: file)
                try! handle.seekToEnd(); try! handle.write(contentsOf: bytes); try! handle.close()
            }
            replay.fulfill()
        }, connectionStateHandler: { _ in })
        await fulfillment(of: [replay], timeout: 3)
        await client.stop()
        let records = await sink.records
        XCTAssertEqual(records.count, 2)
        guard case .tokenUsage(let usage) = records.last?.update else { return XCTFail("usage expected") }
        XCTAssertEqual(usage.cumulativeTotalTokens, 100)
    }

    @MainActor
    func testRecoveryUsesLiveTokenRulesAndPublishesOnlyOnce() async {
        let store = CodexActivityStore(titleClient: CodexAppServerClient(executablePath: nil))
        store.receive(event(.userPromptSubmit))
        var notifications = 0
        store.stateDidChange = { notifications += 1 }
        let updates = [(100, 100), (400, 300), (100, 100), (150, 50)].map { total, last in
            CodexActivityTokenUsageUpdate(sessionHash: "user", turnHash: "one",
                cumulativeTotalTokens: Int64(total), lastReportedTotalTokens: Int64(last))
        }
        store.receiveTokenReplay(updates)
        XCTAssertEqual(store.currentTurnTokenUsage, 550)
        XCTAssertEqual(notifications, 1)
        await store.stop()
    }

    func testSharedUsageRejectsBooleansFractionsAndOverflowLikeLocalUsage() throws {
        for total: Any in [true, -1, 1.5, "100", 9_223_372_036_854_775_808.0] {
            let data = try JSONSerialization.data(withJSONObject: [
                "method": "thread/tokenUsage/updated", "params": ["threadId": "user", "turnId": "one",
                "tokenUsage": ["total": ["totalTokens": total], "last": ["totalTokens": 0]]]
            ])
            XCTAssertNil(CodexAppServerActivityNotificationDecoder.decodeTokenUsage(data: data))
        }
    }

    func testSharedStopCallbackCanRestartWithoutLosingNewRunHandler() async {
        let closed = expectation(description: "new generation retains its connection callback")
        let client = CodexSharedAppServerActivityClient(configuration: .init(
            isEnabled: true, socketURL: URL(fileURLWithPath: "/tmp/nonexistent-quotaview-test.sock"), executablePath: nil
        ))
        await client.start(handler: { _ in }, connectionStateHandler: { state in
            guard state == .disabled else { return }
            await client.start(handler: { _ in }, connectionStateHandler: { next in
                if next == .disabled { closed.fulfill() }
            })
        })
        await client.stop()
        await client.stop()
        await fulfillment(of: [closed], timeout: 1)
    }

    private func fixtureDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        return root
    }
    private func start() -> [String: Any] {
        ["type": "event_msg", "payload": ["type": "task_started", "turn_id": "one"]]
    }
    private func token(_ total: Int) -> [String: Any] {
        ["type": "event_msg", "payload": ["type": "token_count", "info": ["total_token_usage": ["total_tokens": total], "last_token_usage": ["total_tokens": 100]]]]
    }
    private func jsonLine(_ object: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: object); data.append(10); return data
    }
    private func rollout(_ records: [[String: Any]]) throws -> Data {
        var data = try jsonLine(["type": "session_meta", "payload": ["id": "user", "source": "vscode"]])
        for record in records { data.append(try jsonLine(record)) }
        return data
    }
}

private actor ContractRecordSink {
    var records: [CodexLocalRolloutDecodedRecord] = []
    func append(_ record: CodexLocalRolloutDecodedRecord) { records.append(record) }
}
