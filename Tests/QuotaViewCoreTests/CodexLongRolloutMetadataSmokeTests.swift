import Foundation
import SQLite3
import XCTest
@testable import QuotaViewCore

final class CodexLongRolloutMetadataSmokeTests: XCTestCase {
    private func hash(_ text: String) -> String { CodexActivityPrivacy.hashIdentifier(text) }
    private func root() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        return root
    }
    private func line(_ type: String, _ payload: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: ["type": type, "payload": payload])
        data.append(10); return data
    }
    private func sql(_ root: URL, _ statement: String) throws {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(root.appendingPathComponent("state_5.sqlite").path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        XCTAssertEqual(sqlite3_exec(database, statement, nil, nil, nil), SQLITE_OK)
    }
    private func writeThread(_ root: URL, source: Any = "vscode", long: Bool = false, busy: Bool = false, oldStartInsideTail: Bool = false) throws -> URL {
        let file = root.appendingPathComponent("sessions/user.jsonl")
        var data = try line("session_meta", ["id": "user", "source": source, "cwd": "/fixture/widget"])
        if long {
            data.append(try line("event_msg", ["type": "task_started", "turn_id": "active"]))
            data.append(try direct(999, turn: "old"))
            // Put the authoritative start outside the bounded one-MiB tail;
            // the oversized line must also remain indivisible at that boundary.
            data.append(Data(repeating: 32, count: 2 * 1_048_576)); data.append(10)
        }
        if oldStartInsideTail { data.append(try line("event_msg", ["type": "task_started", "turn_id": "old"])) }
        data.append(try context("active"))
        data.append(try direct(123))
        if busy {
            for index in 0..<250 {
                data.append(try line("response_item", ["type": "function_call", "name": "exec_command", "call_id": "tool-\(index)", "arguments": "{}"] ))
            }
            data.append(try line("response_item", ["type": "function_call_output", "call_id": "tool-249", "output": "Public result"]))
            data.append(try line("response_item", ["type": "message", "role": "assistant", "channel": "commentary",
                "content": [["type": "output_text", "text": "Recovered public progress"]]]))
            let question = "{\"questions\":[{\"title\":\"Historical question\",\"options\":[\"A\",\"B\"]}]}"
            data.append(try line("response_item", ["type": "function_call", "name": "functions.request_user_input_async", "call_id": "old-question", "arguments": question]))
        }
        try data.write(to: file)
        return file
    }
    private func context(_ turn: String, thread: String? = nil) throws -> Data {
        var payload: [String: Any] = ["turn_id": turn, "model": "gpt-6.1-sol", "effort": "ultra"]
        if let thread { payload["thread_id"] = thread }
        return try line("turn_context", payload)
    }
    private func direct(_ total: Int, turn: String = "active") throws -> Data {
        try line("token_usage_record", ["thread_id": "user", "turn_id": turn,
            "usage": ["total_tokens": 3], "turn_token_usage": ["total_tokens": total],
            "thread_token_usage": ["total_tokens": total + 10_000]])
    }
    private func metadataSQL(_ file: URL, optional: String = "title TEXT,name TEXT,model TEXT,reasoning_effort TEXT,tokens_used INTEGER",
                             values: String = "'First prompt','Real thread title','gpt-6.1-sol','ultra',987654") -> String {
        let path = file.path.replacingOccurrences(of: "'", with: "''")
        return "CREATE TABLE threads(id TEXT,rollout_path TEXT,cwd TEXT,source TEXT,thread_source TEXT,archived INTEGER,updated_at_ms INTEGER,\(optional)); INSERT INTO threads VALUES('user','\(path)','/fixture/widget','vscode','user',0,1,\(values));"
    }

    func testVerifiedDatabaseDisplayMetadataDoesNotRequireAnActiveTail() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let file = try writeThread(root)
        try sql(root, metadataSQL(file))
        let sink = LongMetadataSink()
        let ready = expectation(description: "quiet candidate ready")
        let client = CodexLocalRolloutActivityClient(configuration: .init(isEnabled: true, codexHomeURL: root, pollIntervalSeconds: 10))
        await client.start(handler: { record, _ in await sink.append(record) }, connectionStateHandler: { _ in },
            healthHandler: { if $0 == .ready { ready.fulfill() } })
        await fulfillment(of: [ready], timeout: 3)
        await client.stop()
        let records = await sink.records
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.update, .sessionMetadata)
        let metadata = try XCTUnwrap(records.first?.threadIdentity?.threadMetadata)
        XCTAssertEqual(metadata.title, "Real thread title")
        XCTAssertTrue(metadata.titleIsExplicitName)
        XCTAssertEqual(metadata.model, "gpt-6.1-sol")
        XCTAssertEqual(metadata.reasoningEffort, "ultra")
        XCTAssertEqual(metadata.cumulativeTotalTokens, 987654)
    }

    func testOptionalDatabaseColumnsAreIndependentAndLegacySourceStillValidates() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let file = try writeThread(root)
        try sql(root, "CREATE TABLE threads(id TEXT,rollout_path TEXT,cwd TEXT,archived INTEGER,updated_at_ms INTEGER,name TEXT,tokens_used INTEGER); INSERT INTO threads VALUES('user','\(file.path)','/fixture/widget',0,1,'Custom name',321);")
        let discovery = CodexLocalRolloutDiscovery(codexHomeURL: root, maximumCandidateCount: 24, fileManager: .default)
        let candidate = try XCTUnwrap(discovery.recentCandidates().first)
        XCTAssertEqual(candidate.sessionKind, .user)
        XCTAssertEqual(candidate.threadMetadata?.title, "Custom name")
        XCTAssertEqual(candidate.threadMetadata?.cumulativeTotalTokens, 321)
        XCTAssertNil(candidate.threadMetadata?.model)
    }

    func testTurnContextNeedsAnExactAdmittedExecutionAndRevokesOnDifferentTurn() throws {
        var unowned = CodexLocalRolloutLineDecoder(sessionHash: hash("user"), sessionKind: .user)
        XCTAssertNil(unowned.decode(line: try context("active")))
        XCTAssertNil(unowned.decode(line: try direct(123)))
        var owned = CodexLocalRolloutLineDecoder(sessionHash: hash("user"), sessionKind: .user, metadataRecoveryTurnHash: hash("active"))
        XCTAssertNil(owned.decode(line: try context("active", thread: "foreign")))
        XCTAssertNil(owned.activeTurnHash)
        XCTAssertNil(owned.decode(line: try context("old")))
        XCTAssertNil(owned.activeTurnHash)
        XCTAssertNil(owned.decode(line: try context("active")))
        XCTAssertEqual(owned.activeTurnHash, hash("active"))
        XCTAssertTrue(owned.isMetadataRecoveredTurn)
        XCTAssertNotNil(owned.decode(line: try direct(123)))
        XCTAssertNil(owned.decode(line: try context("old")))
        XCTAssertNil(owned.activeTurnHash)
        XCTAssertNil(owned.decode(line: try direct(456)))
    }

    func testBoundedLongTailRestoresExactTokensAndModelWithoutLifecycleOrHistoricalQuestions() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let file = try writeThread(root, long: true, busy: true)
        try sql(root, metadataSQL(file))
        let sink = LongMetadataSink()
        let token = expectation(description: "exact known execution tokens")
        let model = expectation(description: "model retained beyond output replay cap")
        let progress = expectation(description: "complete public progress replay received")
        let client = CodexLocalRolloutActivityClient(configuration: .init(isEnabled: true, codexHomeURL: root,
            pollIntervalSeconds: 10, startupTailBytes: 1_048_576))
        let expected = CodexLocalExecutionMetadata.Execution(sessionHash: hash("user"), turnHash: hash("active"))
        await client.setActiveExecutionProvider { [expected] }
        await client.setPublicContentHandler { content in
            await sink.append(content)
            if let fields = (try? JSONSerialization.jsonObject(with: content.data)) as? [String: Any],
               fields["type"] as? String == "metadata" { model.fulfill() }
            if let fields = (try? JSONSerialization.jsonObject(with: content.data)) as? [String: Any],
               fields["text"] as? String == "Recovered public progress" { progress.fulfill() }
        }
        await client.start(handler: { record, _ in
            await sink.append(record)
            if case .tokenUsageReplay = record.update { token.fulfill() }
        }, connectionStateHandler: { _ in })
        await fulfillment(of: [token, model, progress], timeout: 3)
        await client.stop()
        let records = await sink.records
        XCTAssertFalse(records.contains { if case .activity = $0.update { return true }; return false })
        let replay = try XCTUnwrap(records.first { if case .tokenUsageReplay = $0.update { return true }; return false })
        XCTAssertTrue(replay.requiresLiveConfirmation)
        guard case .tokenUsageReplay(let updates) = replay.update else { return XCTFail("usage expected") }
        XCTAssertEqual(updates.compactMap(\.directTurnTotalTokens), [123])
        XCTAssertTrue(updates.allSatisfy { $0.turnHash == expected.turnHash && $0.sessionHash == expected.sessionHash })
        let content = await sink.contents
        XCTAssertGreaterThan(content.count, 1, "Same-turn public progress is restored")
        XCTAssertLessThanOrEqual(content.count, 201, "Keep the existing bounded replay plus independent metadata")
        let recovered = content.dropFirst().compactMap { try? JSONSerialization.jsonObject(with: $0.data) as? [String: Any] }
        XCTAssertTrue(recovered.allSatisfy { $0["presentationRecovery"] as? Bool == true })
        XCTAssertFalse(recovered.contains { $0["type"] as? String == "questionRequest" || $0["type"] as? String == "questionReply" })
        XCTAssertTrue(recovered.contains { $0["text"] as? String == "Recovered public progress" })
        let fields = try XCTUnwrap(try JSONSerialization.jsonObject(with: content[0].data) as? [String: Any])
        XCTAssertEqual(fields["type"] as? String, "metadata")
        XCTAssertEqual(fields["model"] as? String, "gpt-6.1-sol")
        XCTAssertEqual(content[0].turnHash, expected.turnHash)
    }

    func testLateLiveAdmissionRevisitsTheSameEOFWithoutRequiringAnotherAppend() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let file = try writeThread(root, long: true, oldStartInsideTail: true)
        try sql(root, metadataSQL(file))
        let eof = try XCTUnwrap((FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.uint64Value)
        let provider = LongMetadataActiveProvider()
        let sink = LongMetadataSink()
        let ready = expectation(description: "initial EOF established")
        let token = expectation(description: "late admission triggers bounded recovery")
        let client = CodexLocalRolloutActivityClient(configuration: .init(isEnabled: true, codexHomeURL: root,
            pollIntervalSeconds: 0.1, startupTailBytes: 1_048_576))
        await client.setActiveExecutionProvider { await provider.executions }
        await client.start(handler: { record, _ in
            await sink.append(record)
            if case .tokenUsageReplay = record.update { token.fulfill() }
        }, connectionStateHandler: { _ in }, healthHandler: { if $0 == .ready { ready.fulfill() } })
        await fulfillment(of: [ready], timeout: 3)
        let before = await sink.records
        XCTAssertEqual(before.count, 2)
        XCTAssertEqual(before.first?.update, .sessionMetadata)
        guard case .activity(let oldStart) = before.last?.update else { return XCTFail("old historical decoder start expected") }
        XCTAssertEqual(oldStart.turnHash, hash("old"))
        XCTAssertTrue(before.last?.requiresLiveConfirmation == true)
        await provider.set([.init(sessionHash: hash("user"), turnHash: hash("active"))])
        // .ready precedes release of pollingGeneration. If this manual poll is
        // skipped as reentrant, maintenance must revisit the same EOF in time.
        await client.pollOnceForTesting()
        await fulfillment(of: [token], timeout: 3)
        await client.pollOnceForTesting()
        await client.stop()
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.uint64Value, eof)
        let after = await sink.records
        XCTAssertEqual(after.filter { if case .tokenUsageReplay = $0.update { return true }; return false }.count, 1)
        XCTAssertEqual(after.filter { if case .activity = $0.update { return true }; return false }.count, 1,
            "The old decoder must not prevent exact new-turn recovery at EOF, or replay another lifecycle start")
    }

    func testNewPublicAppendWorksAfterMetadataTurnBinding() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let file = try writeThread(root, long: true)
        let sink = LongMetadataSink()
        let initial = expectation(description: "initial recovery")
        let progress = expectation(description: "new public append")
        let client = CodexLocalRolloutActivityClient(configuration: .init(isEnabled: true, codexHomeURL: root,
            pollIntervalSeconds: 10, startupTailBytes: 1_048_576))
        let expected = CodexLocalExecutionMetadata.Execution(sessionHash: hash("user"), turnHash: hash("active"))
        await client.setActiveExecutionProvider { [expected] }
        await client.setPublicContentHandler { content in
            await sink.append(content)
            if let fields = (try? JSONSerialization.jsonObject(with: content.data)) as? [String: Any],
               fields["type"] as? String == "message" { progress.fulfill() }
        }
        await client.start(handler: { record, _ in if case .tokenUsageReplay = record.update { initial.fulfill() } },
            connectionStateHandler: { _ in })
        await fulfillment(of: [initial], timeout: 3)
        let message = try line("response_item", ["type": "message", "role": "assistant", "channel": "commentary",
            "content": [["type": "output_text", "text": "Fresh public progress"]]])
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd(); try handle.write(contentsOf: message); try handle.close()
        await client.pollOnceForTesting()
        await fulfillment(of: [progress], timeout: 3)
        await client.stop()
        let contents = await sink.contents
        let content = try XCTUnwrap(contents.last)
        XCTAssertEqual(content.turnHash, expected.turnHash)
        let fields = try XCTUnwrap(try JSONSerialization.jsonObject(with: content.data) as? [String: Any])
        XCTAssertEqual(fields["text"] as? String, "Fresh public progress")
        XCTAssertNil(fields["presentationRecovery"], "A new append is fresh public observation")
    }

    func testWrongTurnProviderAndSpecializedTasksDoNotRecoverUserActivity() async throws {
        for (source, providerTurn) in [("vscode" as Any, "old"), (["internal": "memory_consolidation"] as Any, "active"), (["internal": "guardian"] as Any, "active")] {
            let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
            let file = try writeThread(root, source: source, long: true)
            try sql(root, metadataSQL(file))
            let sink = LongMetadataSink()
            let settled = expectation(description: "bounded scan settles")
            let client = CodexLocalRolloutActivityClient(configuration: .init(isEnabled: true, codexHomeURL: root,
                pollIntervalSeconds: 10, startupTailBytes: 1_048_576))
            let expected = CodexLocalExecutionMetadata.Execution(sessionHash: hash("user"), turnHash: hash(providerTurn))
            await client.setActiveExecutionProvider { [expected] }
            await client.start(handler: { record, _ in await sink.append(record) }, connectionStateHandler: { _ in },
                healthHandler: { if $0 == .ready || $0 == .waitingForRecords { settled.fulfill() } })
            await fulfillment(of: [settled], timeout: 3)
            await client.stop()
            let records = await sink.records
            XCTAssertTrue(records.allSatisfy { $0.update == .sessionMetadata })
            if let identity = records.first?.threadIdentity, !(source is String) { XCTAssertEqual(identity.sessionKind, .memoryConsolidation) }
        }
    }

    func testRecoveredBindingIsRevokedWhenLiveAdmissionDisappears() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let file = try writeThread(root, long: true)
        let provider = LongMetadataActiveProvider()
        await provider.set([.init(sessionHash: hash("user"), turnHash: hash("active"))])
        let sink = LongMetadataSink()
        let token = expectation(description: "initial recovery")
        let client = CodexLocalRolloutActivityClient(configuration: .init(isEnabled: true, codexHomeURL: root,
            pollIntervalSeconds: 10, startupTailBytes: 1_048_576))
        await client.setActiveExecutionProvider { await provider.executions }
        await client.start(handler: { record, _ in
            await sink.append(record)
            if case .tokenUsageReplay = record.update { token.fulfill() }
        }, connectionStateHandler: { _ in })
        await fulfillment(of: [token], timeout: 3)
        await provider.set([])
        await client.pollOnceForTesting()
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd(); try handle.write(contentsOf: direct(456)); try handle.close()
        await client.pollOnceForTesting()
        await client.stop()
        let records = await sink.records
        XCTAssertEqual(records.count, 1)
        guard case .tokenUsageReplay(let updates) = records[0].update else { return XCTFail("only initial recovery expected") }
        XCTAssertEqual(updates.compactMap(\.directTurnTotalTokens), [123])
    }

    func testLatestSameTurnPublicMessageSurvivesToolBurstWithinTheSharedBudget() {
        var replay = CodexLocalPublicReplayBuffer()
        func content(_ text: String, turn: String = "active") -> CodexLocalPublicContent {
            .init(sessionHash: hash("user"), turnHash: hash(turn), data: Data(text.utf8), occurredAt: .distantPast)
        }
        replay.append(content("Older progress"), isAssistantMessage: true)
        replay.append(content("Latest public progress"), isAssistantMessage: true)
        for index in 0..<250 { replay.append(content("tool-\(index)"), isAssistantMessage: false) }
        XCTAssertEqual(replay.contents.count, 200)
        XCTAssertEqual(String(decoding: replay.contents.first!.data, as: UTF8.self), "Latest public progress")
        XCTAssertFalse(replay.contents.contains { String(decoding: $0.data, as: UTF8.self) == "Older progress" })
        XCTAssertLessThanOrEqual(replay.byteCount, 2_097_152)
        // A different turn may not preserve an earlier turn's protected text.
        replay.selectTurn(hash("next"))
        for index in 0..<200 { replay.append(content("next-tool-\(index)", turn: "next"), isAssistantMessage: false) }
        XCTAssertTrue(replay.contents.allSatisfy { $0.turnHash == hash("next") })
    }

    func testLatestPublicMessageProtectionDoesNotExceedTheByteBudget() {
        var replay = CodexLocalPublicReplayBuffer()
        let session = hash("user"), turn = hash("active")
        let message = CodexLocalPublicContent(sessionHash: session, turnHash: turn,
            data: Data(repeating: 65, count: 600_000), occurredAt: .distantPast)
        replay.append(message, isAssistantMessage: true)
        for _ in 0..<4 {
            replay.append(.init(sessionHash: session, turnHash: turn,
                data: Data(repeating: 66, count: 600_000), occurredAt: .distantPast), isAssistantMessage: false)
        }
        XCTAssertEqual(replay.contents.count, 3)
        XCTAssertEqual(replay.contents.first?.data, message.data)
        XCTAssertEqual(replay.byteCount, 1_800_000)
        XCTAssertLessThanOrEqual(replay.byteCount, 2_097_152)
        replay.append(.init(sessionHash: session, turnHash: turn,
            data: Data(repeating: 67, count: 2_097_153), occurredAt: .distantPast), isAssistantMessage: true)
        XCTAssertEqual(replay.byteCount, 0, "A sole oversized protected message must also be rejected")
        XCTAssertTrue(replay.contents.isEmpty)
    }

    func testBoundedThreadMetadataRejectsInvalidDisplayValues() {
        let metadata = CodexLocalRolloutThreadMetadata(title: String(repeating: "x", count: 513), titleIsExplicitName: true,
            model: String(repeating: "x", count: 257), reasoningEffort: " ", cumulativeTotalTokens: -1)
        XCTAssertTrue(metadata.isEmpty)
        XCTAssertFalse(metadata.titleIsExplicitName)
        XCTAssertNil(metadata.cumulativeTotalTokens)
    }
}

private actor LongMetadataSink {
    var records: [CodexLocalRolloutDecodedRecord] = []
    var contents: [CodexLocalPublicContent] = []
    func append(_ record: CodexLocalRolloutDecodedRecord) { records.append(record) }
    func append(_ content: CodexLocalPublicContent) { contents.append(content) }
}
private actor LongMetadataActiveProvider {
    var executions: [CodexLocalExecutionMetadata.Execution] = []
    func set(_ value: [CodexLocalExecutionMetadata.Execution]) { executions = value }
}
