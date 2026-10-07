import Darwin
import Foundation
import XCTest
@testable import QuotaView
@testable import QuotaViewCore

final class ClaudeCodeSupportTests: XCTestCase {
    private var temporary: URL!

    override func setUpWithError() throws {
        temporary = FileManager.default.temporaryDirectory.appendingPathComponent("qv-claude-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporary)
    }

    private func line(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    // MARK: Pricing

    func testPricingRecognizesFamiliesVersionsAndUnknownModels() {
        XCTAssertEqual(ClaudeCodePricing.rates(for: "claude-opus-5-5-20260101")?.input, 4)
        XCTAssertEqual(ClaudeCodePricing.rates(for: "claude-opus-5")?.output, 25)
        XCTAssertEqual(ClaudeCodePricing.rates(for: "claude-opus-4-5-20251101")?.cacheRead, 0.5)
        XCTAssertEqual(ClaudeCodePricing.rates(for: "claude-opus-4-1-20250805")?.input, 15)
        XCTAssertEqual(ClaudeCodePricing.rates(for: "claude-sonnet-4-20250514")?.input, 3)
        XCTAssertEqual(ClaudeCodePricing.rates(for: "us.anthropic.claude-sonnet-5-5-v1:0")?.input, 2)
        XCTAssertEqual(ClaudeCodePricing.rates(for: "claude-3-5-haiku-20241022")?.input, 0.8)
        XCTAssertEqual(ClaudeCodePricing.rates(for: "claude-haiku-4-5")?.cacheWrite1h, 2)
        XCTAssertEqual(ClaudeCodePricing.rates(for: "claude-fable-5-1")?.cacheRead, 0.25)
        XCTAssertEqual(ClaudeCodePricing.rates(for: "claude-fable-5")?.cacheRead, 1.0)
        XCTAssertNil(ClaudeCodePricing.rates(for: "claude-3-haiku-20240307"))
        XCTAssertNil(ClaudeCodePricing.rates(for: "gpt-5"))
        XCTAssertEqual(ClaudeCodePricing.displayName(for: "claude-opus-5-5-20260101"), "Opus 5.5")
        XCTAssertEqual(ClaudeCodePricing.displayName(for: "custom-model"), "custom-model")
        let usage = ClaudeCodeTokenUsage(input: 1_000_000, output: 1_000_000, cacheWrite5m: 1_000_000, cacheWrite1h: 1_000_000, cacheRead: 1_000_000)
        XCTAssertEqual(ClaudeCodePricing.cost(model: "claude-sonnet-5", usage: usage)!, 2 + 10 + 2.5 + 4 + 0.2, accuracy: 0.0001)
    }

    func testTokenUsageSplitsCacheWritesAndRejectsNegativeCounters() throws {
        let split = try XCTUnwrap(ClaudeCodeTokenUsage(usage: [
            "input_tokens": 10, "output_tokens": 5, "cache_creation_input_tokens": 30, "cache_read_input_tokens": 7,
            "cache_creation": ["ephemeral_5m_input_tokens": 10, "ephemeral_1h_input_tokens": 20]
        ]))
        XCTAssertEqual(split, ClaudeCodeTokenUsage(input: 10, output: 5, cacheWrite5m: 10, cacheWrite1h: 20, cacheRead: 7))
        XCTAssertEqual(split.total, 52)
        XCTAssertEqual(ClaudeCodeTokenUsage(usage: ["input_tokens": 1, "cache_creation_input_tokens": 4])?.cacheWrite5m, 4)
        XCTAssertNil(ClaudeCodeTokenUsage(usage: ["input_tokens": -1]))
    }

    // MARK: Transcript

    func testTranscriptDecoderProjectsPublicRecordsOnly() {
        XCTAssertEqual(ClaudeCodeTranscriptDecoder.records(line(["type": "custom-title", "customTitle": "Fix login"])), [.customTitle("Fix login")])
        XCTAssertEqual(ClaudeCodeTranscriptDecoder.records(line(["type": "user", "message": ["role": "user", "content": "Add tests"]])),
                       [.userPrompt("Add tests")])
        XCTAssertEqual(ClaudeCodeTranscriptDecoder.records(line(["type": "user", "message": ["role": "user", "content": "[Request interrupted by user]"]])),
                       [.interrupted])
        XCTAssertEqual(ClaudeCodeTranscriptDecoder.records(line(["type": "user", "isMeta": true, "message": ["role": "user", "content": "meta"]])), [])
        XCTAssertEqual(ClaudeCodeTranscriptDecoder.records(line(["type": "user", "message": ["role": "user", "content": "<command-name>/model</command-name>"]])), [])
        XCTAssertEqual(ClaudeCodeTranscriptDecoder.records(line(["type": "user", "isSidechain": true, "message": ["role": "user", "content": "child"]])), [])
        XCTAssertEqual(ClaudeCodeTranscriptDecoder.records(line(["type": "user", "message": ["role": "user", "content": [
            ["type": "tool_result", "tool_use_id": "toolu_1", "content": [["type": "text", "text": "ok"]], "is_error": false]
        ]]])), [.toolResult(toolUseID: "toolu_1", text: "ok", isError: false)])

        let assistant = ClaudeCodeTranscriptDecoder.records(line([
            "type": "assistant", "uuid": "line-1", "requestId": "req_1",
            "message": ["id": "msg_1", "model": "claude-opus-5-5", "content": [
                ["type": "thinking", "thinking": "private"],
                ["type": "text", "text": "Running tests"],
                ["type": "tool_use", "id": "toolu_2", "name": "Bash", "input": ["command": "swift test"]]
            ], "usage": ["input_tokens": 3, "output_tokens": 4]]
        ]))
        XCTAssertEqual(assistant.count, 3)
        XCTAssertEqual(assistant[0], .assistantText(messageID: "line-1", text: "Running tests"))
        XCTAssertEqual(assistant[1], .toolUse(id: "toolu_2", name: "Bash", input: #"{"command":"swift test"}"#))
        guard case let .usage(key, model, usage, _) = assistant[2] else { return XCTFail("missing usage") }
        XCTAssertEqual(key, "msg_1:req_1"); XCTAssertEqual(model, "claude-opus-5-5"); XCTAssertEqual(usage.total, 7)
        XCTAssertFalse(assistant.contains { if case .assistantText(_, let text) = $0 { return text.contains("private") }; return false })
    }

    func testTranscriptTailReadsAppendedCompleteLinesAndRestartsAfterTruncation() throws {
        let url = temporary.appendingPathComponent("t.jsonl")
        try Data("{\"a\":1}\n{\"b\":".utf8).write(to: url)
        var tail = ClaudeCodeTranscriptTail(path: url.path)
        XCTAssertEqual(tail.readLines().map { String(decoding: $0, as: UTF8.self) }, [#"{"a":1}"#])
        let handle = try FileHandle(forWritingTo: url); try handle.seekToEnd(); try handle.write(contentsOf: Data("2}\n".utf8)); try handle.close()
        XCTAssertEqual(tail.readLines().map { String(decoding: $0, as: UTF8.self) }, [#"{"b":2}"#])
        XCTAssertEqual(tail.readLines(), [])
        try Data("{\"c\":3}\n".utf8).write(to: url)
        XCTAssertEqual(tail.readLines().map { String(decoding: $0, as: UTF8.self) }, [#"{"c":3}"#])
    }

    // MARK: Usage

    func testUsageScannerDeduplicatesStreamedResponsesAndMarksUnpricedDays() async throws {
        let project = temporary.appendingPathComponent("projects/demo", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        func assistant(_ id: String, model: String, at timestamp: String, tokens: Int) -> String {
            String(decoding: line(["type": "assistant", "requestId": "r-" + id, "timestamp": timestamp,
                "message": ["id": id, "model": model, "content": [], "usage": ["input_tokens": tokens, "output_tokens": 0]]]), as: UTF8.self)
        }
        let first = [assistant("m1", model: "claude-sonnet-5", at: "2026-10-01T10:00:00Z", tokens: 1_000_000),
                     assistant("m1", model: "claude-sonnet-5", at: "2026-10-01T10:00:01Z", tokens: 1_000_000),
                     assistant("m2", model: "mystery-model", at: "2026-10-02T10:00:00Z", tokens: 5)].joined(separator: "\n") + "\n"
        try Data(first.utf8).write(to: project.appendingPathComponent("a.jsonl"))
        // A resumed session copies an earlier response into another file.
        try Data((assistant("m1", model: "claude-sonnet-5", at: "2026-10-01T10:00:00Z", tokens: 1_000_000) + "\n").utf8)
            .write(to: project.appendingPathComponent("b.jsonl"))
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let scanner = ClaudeCodeUsageScanner(projectsURL: temporary.appendingPathComponent("projects"))
        let summary = await scanner.scan()
        XCTAssertEqual(summary.lifetimeTokens, 1_000_005)
        XCTAssertTrue(summary.complete)
        XCTAssertEqual(summary.days.count, 2)
        XCTAssertEqual(summary.days.first?.estimatedCost ?? -1, 2, accuracy: 0.0001)
        XCTAssertNil(summary.days.last?.estimatedCost)
        for day in summary.days { XCTAssertEqual(utc.startOfDay(for: day.date), day.date) }

        let handle = try FileHandle(forWritingTo: project.appendingPathComponent("b.jsonl")); try handle.seekToEnd()
        try handle.write(contentsOf: Data((assistant("m3", model: "claude-sonnet-5", at: "2026-10-01T11:00:00Z", tokens: 10) + "\n").utf8))
        try handle.close()
        let incremental = await scanner.scan()
        XCTAssertEqual(incremental.lifetimeTokens, 1_000_015)
    }

    func testRateLimitSnapshotDecodesWindowsAndResetTimes() throws {
        let data = line(["capturedAt": 1_791_000_000, "rate_limits": [
            "five_hour": ["used_percentage": 12.4, "resets_at": 1_791_003_600],
            "seven_day": ["used_percentage": 140, "resets_at": "2026-10-10T00:00:00Z"]
        ]])
        let limits = try XCTUnwrap(ClaudeCodeRateLimits.decode(snapshot: data))
        XCTAssertEqual(limits.fiveHour?.remainingPercent, 88)
        XCTAssertEqual(limits.fiveHour?.resetsAt, Date(timeIntervalSince1970: 1_791_003_600))
        XCTAssertEqual(limits.sevenDay?.remainingPercent, 0)
        XCTAssertNotNil(limits.sevenDay?.resetsAt)
        XCTAssertNil(ClaudeCodeRateLimits.decode(snapshot: line(["capturedAt": 1, "rate_limits": [:]])))

        let presentation = try XCTUnwrap(ClaudeCodeRuntime.presentation(rateLimits: limits, usage: nil, now: Date(timeIntervalSince1970: 1_791_000_000)))
        XCTAssertEqual(presentation.quotaState, .available)
        XCTAssertEqual(presentation.presentation.availability, .exhausted)
        XCTAssertEqual(presentation.presentation.quotaWindows.map(\.windowDurationMinutes), [300, 10_080])
        XCTAssertNil(presentation.presentation.sparkQuota)
        XCTAssertNil(presentation.presentation.availableResetCredits)
        XCTAssertNil(ClaudeCodeRuntime.presentation(rateLimits: nil, usage: nil))
    }

    func testModelPricedDailyCostIsNotReplacedByGenericEstimate() {
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = utc.startOfDay(for: Date())
        let priced = EstimatedCostChartModel(activity: [DailyTokenActivity(date: day, tokens: 100, modelPriced: true, estimatedCost: 1.25)], endingAt: day)
        XCTAssertEqual(priced.latestCost, 1.25)
        let unpriced = EstimatedCostChartModel(activity: [DailyTokenActivity(date: day, tokens: 100, modelPriced: true, estimatedCost: nil)], endingAt: day)
        XCTAssertNil(unpriced.latestCost)
        let legacy = EstimatedCostChartModel(activity: [DailyTokenActivity(date: day, tokens: 1_000_000)], endingAt: day)
        XCTAssertNotNil(legacy.latestCost)
    }

    // MARK: Installer

    private func installer() throws -> ClaudeCodeInstaller {
        let helper = temporary.appendingPathComponent("bundle/QuotaViewActivityHook")
        try FileManager.default.createDirectory(at: helper.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: helper)
        chmod(helper.path, 0o755)
        return ClaudeCodeInstaller(socketURL: temporary.appendingPathComponent("s.sock"), authenticationToken: "token",
            configurationDirectory: temporary.appendingPathComponent("claude", isDirectory: true),
            supportDirectory: temporary.appendingPathComponent("support", isDirectory: true), helperURL: helper, environment: [:])
    }

    private func settings(_ installer: ClaudeCodeInstaller) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: installer.settingsURL)) as? [String: Any])
    }

    func testInstallerAddsOwnedHooksPreservesUserEntriesAndRestoresStatusLine() throws {
        let installer = try installer()
        try FileManager.default.createDirectory(at: installer.configurationDirectory, withIntermediateDirectories: true)
        let original: [String: Any] = [
            "model": "opus",
            "statusLine": ["type": "command", "command": "~/bin/status.sh"],
            "hooks": ["PreToolUse": [["matcher": "Bash", "hooks": [["type": "command", "command": "~/bin/guard.sh"]]]]]
        ]
        try JSONSerialization.data(withJSONObject: original).write(to: installer.settingsURL)

        try installer.install(.init(interactiveApprovals: true, statusLine: true))
        var root = try settings(installer)
        XCTAssertEqual(root["model"] as? String, "opus")
        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        XCTAssertEqual(Set(hooks.keys), Set(ClaudeCodeInstaller.eventNames))
        let preTool = try XCTUnwrap(hooks["PreToolUse"] as? [[String: Any]])
        XCTAssertEqual(preTool.count, 2)
        XCTAssertEqual((preTool[0]["hooks"] as? [[String: Any]])?.first?["command"] as? String, "~/bin/guard.sh")
        let permission = try XCTUnwrap((hooks["PermissionRequest"] as? [[String: Any]])?.first)
        XCTAssertEqual(permission["matcher"] as? String, "*")
        XCTAssertEqual((permission["hooks"] as? [[String: Any]])?.first?["timeout"] as? Int, 3_600)
        XCTAssertNil((hooks["Stop"] as? [[String: Any]])?.first?["matcher"])
        XCTAssertEqual((root["statusLine"] as? [String: Any])?["command"] as? String, installer.statusLineCommand)
        XCTAssertTrue(FileManager.default.fileExists(atPath: installer.settingsURL.path + ".quotaview-backup"))
        let state = installer.state()
        XCTAssertTrue(state.hooksInstalled); XCTAssertTrue(state.statusLineInstalled)

        let routeData = try Data(contentsOf: installer.routeURL)
        let route = try XCTUnwrap(JSONSerialization.jsonObject(with: routeData) as? [String: Any])
        XCTAssertEqual(route["statusLineForwardCommand"] as? String, "~/bin/status.sh")
        XCTAssertEqual(route["authenticationToken"] as? String, "token")
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: installer.routeURL.path)[.posixPermissions] as? Int, 0o600)

        // Reinstalling is idempotent and never records our own status line as the user's.
        try installer.install(.init(interactiveApprovals: false, statusLine: true))
        root = try settings(installer)
        XCTAssertEqual(((root["hooks"] as? [String: Any])?["PreToolUse"] as? [[String: Any]])?.count, 2)

        try installer.install(.init(interactiveApprovals: false, statusLine: false))
        root = try settings(installer)
        XCTAssertEqual((root["statusLine"] as? [String: Any])?["command"] as? String, "~/bin/status.sh")

        try installer.uninstall()
        root = try settings(installer)
        XCTAssertEqual(Set((root["hooks"] as? [String: Any] ?? [:]).keys), ["PreToolUse"])
        XCTAssertEqual((root["statusLine"] as? [String: Any])?["command"] as? String, "~/bin/status.sh")
        XCTAssertFalse(FileManager.default.fileExists(atPath: installer.routeURL.path))
        XCTAssertFalse(installer.state().hasOwnedHooks)
    }

    func testInstallerRejectsInvalidSettingsWithoutWriting() throws {
        let installer = try installer()
        try FileManager.default.createDirectory(at: installer.configurationDirectory, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: installer.settingsURL)
        XCTAssertThrowsError(try installer.install(.init(interactiveApprovals: true, statusLine: false)))
        XCTAssertEqual(try String(contentsOf: installer.settingsURL, encoding: .utf8), "{not json")
        XCTAssertFalse(installer.owns("'/usr/local/bin/QuotaViewActivityHook' --claude-code --configuration '/x'"))
    }

    // MARK: Approvals

    func testApprovalRequestsMapClaudeToolsToTypedKinds() throws {
        let bash = try ClaudeCodeApproval.request(eventID: "e1", sessionKey: "s", turnKey: "t", toolName: "Bash",
            toolInput: ["command": "rm -rf build", "description": "Clean"], toolUseID: "toolu_1", cwd: "/repo", hasSuggestions: true)
        XCTAssertTrue(bash.isClaudeCode)
        XCTAssertEqual(bash.kind, .command)
        XCTAssertEqual(bash.detail, "rm -rf build")
        XCTAssertEqual(bash.actions.map { $0.result["decision"].text }, ["accept", "acceptForSession", "acceptAlways", "decline", "cancel"])
        XCTAssertEqual(ClaudeCodeApproval.eventID(of: bash), "e1")

        let edit = try ClaudeCodeApproval.request(eventID: "e2", sessionKey: "s", turnKey: "t", toolName: "Edit",
            toolInput: ["file_path": "/repo/a.swift", "old_string": "a", "new_string": "b"], toolUseID: "toolu_2", cwd: nil, hasSuggestions: false)
        XCTAssertEqual(edit.kind, .fileChange)
        XCTAssertEqual(edit.detail, "/repo/a.swift\n-a\n+b")
        XCTAssertEqual(edit.actions.map { $0.result["decision"].text }, ["accept", "decline", "cancel"])

        let question = try ClaudeCodeApproval.request(eventID: "e3", sessionKey: "s", turnKey: "t", toolName: "AskUserQuestion",
            toolInput: ["questions": [["question": "Which DB?", "header": "DB", "multiSelect": false,
                                       "options": [["label": "SQLite", "description": "local"], ["label": "Postgres", "description": "server"]]]]],
            toolUseID: "toolu_3", cwd: nil, hasSuggestions: false)
        XCTAssertEqual(question.kind, .questions)
        XCTAssertTrue(question.supportedQuestions)
        XCTAssertEqual(question.questions.first?.title, "Which DB?")

        let other = try ClaudeCodeApproval.request(eventID: "e4", sessionKey: "s", turnKey: "t", toolName: "WebFetch",
            toolInput: ["url": "https://example.com"], toolUseID: "toolu_4", cwd: nil, hasSuggestions: false)
        XCTAssertEqual(other.detail, "WebFetch · https://example.com")
    }

    func testApprovalDecisionsMapToClaudeHookOutput() throws {
        let bash = try ClaudeCodeApproval.request(eventID: "e1", sessionKey: "s", turnKey: "t", toolName: "Bash",
            toolInput: ["command": "ls"], toolUseID: "u", cwd: nil, hasSuggestions: true)
        let suggestions: [Any] = [["type": "addRules", "destination": "localSettings", "behavior": "allow",
                                   "rules": [["toolName": "Bash", "ruleContent": "ls"]]]]
        func decide(_ decision: String) -> [String: Any]? {
            ClaudeCodeApproval.decision(for: bash, result: .object(["decision": .string(decision)]), toolInput: ["command": "ls"], suggestions: suggestions)
        }
        XCTAssertEqual(decide("accept")?["behavior"] as? String, "allow")
        XCTAssertEqual(((decide("acceptForSession")?["updatedPermissions"] as? [[String: Any]])?.first)?["destination"] as? String, "session")
        XCTAssertEqual(((decide("acceptAlways")?["updatedPermissions"] as? [[String: Any]])?.first)?["destination"] as? String, "localSettings")
        XCTAssertEqual(decide("decline")?["behavior"] as? String, "deny")
        XCTAssertNil(decide("decline")?["interrupt"])
        XCTAssertEqual(decide("cancel")?["interrupt"] as? Bool, true)
        XCTAssertNil(decide("bogus"))

        let question = try ClaudeCodeApproval.request(eventID: "e3", sessionKey: "s", turnKey: "t", toolName: "AskUserQuestion",
            toolInput: ["questions": [["question": "Which DB?", "options": [["label": "SQLite"]]]]], toolUseID: "q", cwd: nil, hasSuggestions: false)
        let answer = IslandApprovalJSON.object(["answers": .object(["Which DB?": .object(["answers": .array([.string("SQLite")])])])])
        XCTAssertTrue(question.permits(answer))
        let allowed = try XCTUnwrap(ClaudeCodeApproval.decision(for: question, result: answer,
            toolInput: ["questions": [["question": "Which DB?"]]], suggestions: []))
        XCTAssertEqual(allowed["behavior"] as? String, "allow")
        XCTAssertEqual((allowed["updatedInput"] as? [String: Any])?["answers"] as? [String: String], ["Which DB?": "SQLite"])
        XCTAssertNotNil((allowed["updatedInput"] as? [String: Any])?["questions"])
        let skipped = ClaudeCodeApproval.decision(for: question, result: try XCTUnwrap(question.questionSkipResult), toolInput: [:], suggestions: [])
        XCTAssertEqual(skipped?["behavior"] as? String, "deny")
    }

    // MARK: Island

    @MainActor
    func testIslandRoutesClaudeRequestsIndependentlyOfCodexTransport() async throws {
        let store = IslandLiveStore()
        let session = ClaudeCodeRuntime.sessionKey("abc")
        let turn = CodexActivityPrivacy.hashIdentifier("turn-1")
        store.setProvider(.claudeCode, for: session)
        store.receiveLegacy(.init(event: .userPromptSubmit, sessionHash: session, turnHash: turn, workspaceName: "repo", source: .hook))
        var answered: [IslandApprovalJSON] = []
        store.claudeResponseCapability = { $0.isClaudeCode }
        store.claudeRespond = { _, result in answered.append(result) }
        store.responseCapability = { _ in false }
        let wire = try ClaudeCodeApproval.request(eventID: "e1", sessionKey: session, turnKey: turn, toolName: "Bash",
            toolInput: ["command": "ls"], toolUseID: "u1", cwd: nil, hasSuggestions: false)
        store.observeClaudeRequest(wire, sessionKey: session, turnKey: turn,
            callHash: CodexActivityPrivacy.hashIdentifier("claude-tool:u1"), interactive: true)
        // A Codex App Server disconnect must not revoke a Claude Hook's answer capability.
        store.setConnection(.disabled)
        var display = store.display(english: true, remaining: nil, enabled: true, privacy: false)
        let task = try XCTUnwrap(display.state.tasks.first)
        XCTAssertEqual(task.provider, .claudeCode)
        XCTAssertTrue(task.hasPendingRequest)
        XCTAssertEqual(task.renderState.visualState, .awaitingConfirmation)
        let confirmation = try XCTUnwrap(display.taskDetails[task.id]?.confirmation)
        XCTAssertEqual(confirmation.provider, .claudeCode)
        XCTAssertTrue(confirmation.canRespond)

        store.submit(task.id, requestID: confirmation.id, decision: .reply(.object(["decision": .string("accept")])))
        for _ in 0..<20 where answered.isEmpty { await Task.yield() }
        XCTAssertEqual(answered, [.object(["decision": .string("accept")])])

        store.resolveClaudeRequest(sessionKey: session, rpcID: wire.rpcID)
        display = store.display(english: true, remaining: nil, enabled: true, privacy: true)
        XCTAssertFalse(try XCTUnwrap(display.state.tasks.first).hasPendingRequest)
        XCTAssertEqual(display.state.tasks.first?.title, "Claude Code task")
    }

    @MainActor
    func testReadOnlyClaudeRequestCannotBeAnsweredFromIsland() throws {
        let store = IslandLiveStore()
        let session = ClaudeCodeRuntime.sessionKey("ro"), turn = "turn"
        store.receiveLegacy(.init(event: .preToolUse, sessionHash: session, turnHash: turn, source: .hook))
        store.claudeResponseCapability = { _ in true }
        store.claudeRespond = { _, _ in XCTFail("read-only request answered") }
        let wire = try ClaudeCodeApproval.request(eventID: "e", sessionKey: session, turnKey: turn, toolName: "Bash",
            toolInput: ["command": "ls"], toolUseID: "u", cwd: nil, hasSuggestions: false)
        store.observeClaudeRequest(wire, sessionKey: session, turnKey: turn, callHash: nil, interactive: false)
        let display = store.display(english: false, remaining: nil, enabled: true, privacy: false)
        let task = try XCTUnwrap(display.state.tasks.first)
        let confirmation = try XCTUnwrap(display.taskDetails[task.id]?.confirmation)
        XCTAssertFalse(confirmation.canRespond)
        store.submit(task.id, requestID: confirmation.id, decision: .reply(.object(["decision": .string("accept")])))
    }

    // MARK: Bridge

    func testBridgeAcknowledgesHoldsAndResolvesPermissionConnections() throws {
        let socket = URL(fileURLWithPath: "/tmp/qv-cc-\(UUID().uuidString.prefix(8)).sock")
        let bridge = ClaudeCodeBridge(socketURL: socket, authenticationToken: "secret")
        let received = expectation(description: "message")
        received.assertForOverFulfill = false
        let disconnected = expectation(description: "disconnect")
        let box = MessageBox()
        try bridge.start(onMessage: { message in box.append(message); received.fulfill() },
                         onDisconnect: { id in if id == "held-2" { disconnected.fulfill() } })
        defer { bridge.stop(); unlink(socket.path + ".lock") }

        func connect() throws -> Int32 {
            let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
            _ = withUnsafeMutableBytes(of: &address.sun_path) { buffer in
                socket.path.utf8CString.withUnsafeBytes { buffer.copyMemory(from: $0) }
            }
            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
            }
            XCTAssertEqual(result, 0)
            var timeout = timeval(tv_sec: 2, tv_usec: 0)
            setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            return descriptor
        }
        func send(_ descriptor: Int32, _ object: [String: Any]) {
            var data = try! JSONSerialization.data(withJSONObject: object); data.append(0x0A)
            _ = data.withUnsafeBytes { Darwin.send(descriptor, $0.baseAddress, $0.count, 0) }
        }
        func readLine(_ descriptor: Int32) -> [String: Any]? {
            var data = Data(); var byte: UInt8 = 0
            while Darwin.recv(descriptor, &byte, 1, 0) == 1 { if byte == 0x0A { break }; data.append(byte) }
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }

        let rejected = try connect()
        send(rejected, ["authenticationToken": "wrong", "eventID": "x", "kind": "hook", "awaitDecision": false, "payload": [:]])
        XCTAssertNil(readLine(rejected)); Darwin.close(rejected)

        let held = try connect()
        send(held, ["authenticationToken": "secret", "eventID": "held-1", "kind": "hook", "awaitDecision": true,
                    "payload": ["hook_event_name": "PermissionRequest", "session_id": "s"]])
        XCTAssertEqual(readLine(held)?["pending"] as? Bool, true)
        wait(for: [received], timeout: 2)
        XCTAssertEqual(box.messages.first?.awaitsDecision, true)
        bridge.resolve(eventID: "held-1", decision: ["behavior": "allow"])
        let decision = readLine(held)
        XCTAssertEqual(decision?["eventID"] as? String, "held-1")
        XCTAssertEqual((decision?["decision"] as? [String: Any])?["behavior"] as? String, "allow")
        Darwin.close(held)

        let abandoned = try connect()
        send(abandoned, ["authenticationToken": "secret", "eventID": "held-2", "kind": "hook", "awaitDecision": true, "payload": [:]])
        XCTAssertEqual(readLine(abandoned)?["pending"] as? Bool, true)
        Darwin.close(abandoned)
        wait(for: [disconnected], timeout: 2)
    }
}

extension ClaudeCodeSupportTests {
    private static func send(_ object: [String: Any], to socket: URL) -> [String: Any]? {
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        defer { Darwin.close(descriptor) }
        var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
        _ = withUnsafeMutableBytes(of: &address.sun_path) { buffer in socket.path.utf8CString.withUnsafeBytes { buffer.copyMemory(from: $0) } }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { return nil }
        var data = try! JSONSerialization.data(withJSONObject: object); data.append(0x0A)
        _ = data.withUnsafeBytes { Darwin.send(descriptor, $0.baseAddress, $0.count, 0) }
        var reply = Data(); var byte: UInt8 = 0
        while Darwin.recv(descriptor, &byte, 1, 0) == 1, byte != 0x0A { reply.append(byte) }
        return (try? JSONSerialization.jsonObject(with: reply)) as? [String: Any]
    }

    @MainActor
    func testRuntimeProjectsHookEventsAndTranscriptIntoIsland() async throws {
        let suite = "QuotaView.ClaudeRuntime.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        preferences.claudeCodeEnabled = true
        let helper = temporary.appendingPathComponent("bundle/QuotaViewActivityHook")
        try FileManager.default.createDirectory(at: helper.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: helper); chmod(helper.path, 0o755)
        let socket = URL(fileURLWithPath: "/tmp/qv-cr-\(UUID().uuidString.prefix(8)).sock")
        let installer = ClaudeCodeInstaller(socketURL: socket, authenticationToken: "tok",
            configurationDirectory: temporary.appendingPathComponent("claude"), supportDirectory: temporary.appendingPathComponent("support"),
            helperURL: helper, environment: [:])
        let island = IslandSession()
        let runtime = ClaudeCodeRuntime(preferences: preferences, island: island, defaults: defaults, installer: installer)
        runtime.start()
        defer { runtime.stop(); island.stop(); unlink(socket.path + ".lock") }

        // An earlier turn precedes the current one in the transcript backlog.
        let transcript = temporary.appendingPathComponent("session.jsonl")
        func record(_ object: [String: Any]) -> String { String(decoding: line(object), as: UTF8.self) + "\n" }
        var backlog = record(["type": "user", "message": ["role": "user", "content": "Old task"]])
        backlog += record(["type": "assistant", "uuid": "old", "message": ["id": "m0", "content": [["type": "text", "text": "Old answer"]]]])
        backlog += record(["type": "user", "message": ["role": "user", "content": "[Request interrupted by user]"]])
        backlog += record(["type": "custom-title", "customTitle": "Release prep"])
        backlog += record(["type": "user", "message": ["role": "user", "content": "Current task"]])
        try Data(backlog.utf8).write(to: transcript)

        func hook(_ event: String, _ extra: [String: Any] = [:], wait: Bool = false) -> [String: Any]? {
            var payload: [String: Any] = ["hook_event_name": event, "session_id": "sess-1", "cwd": "/tmp/repo", "transcript_path": transcript.path]
            payload.merge(extra) { $1 }
            return Self.send(["authenticationToken": "tok", "eventID": UUID().uuidString, "kind": "hook", "awaitDecision": wait, "payload": payload], to: socket)
        }
        func settle() async { for _ in 0..<20 { try? await Task.sleep(nanoseconds: 20_000_000) } }

        XCTAssertEqual(hook("PreToolUse", ["tool_name": "Bash", "tool_use_id": "toolu_1", "tool_input": ["command": "swift test"]])?["accepted"] as? Bool, true)
        await settle()
        let key = ClaudeCodeRuntime.sessionKey("sess-1")
        var task = try XCTUnwrap(island.model.tasks.first { $0.key == key })
        XCTAssertEqual(task.title, "Release prep")
        XCTAssertEqual(island.model.provider(for: key), .claudeCode)
        XCTAssertFalse(task.entries.contains { $0.text.chinese.contains("Old answer") })
        XCTAssertFalse(task.terminal, "an interrupt marker from an earlier turn must not cancel the current one")

        let handle = try FileHandle(forWritingTo: transcript); try handle.seekToEnd()
        try handle.write(contentsOf: Data((record(["type": "assistant", "uuid": "a1", "requestId": "r1", "message": ["id": "m1", "model": "claude-opus-5-5",
            "content": [["type": "text", "text": "All tests pass."]], "usage": ["input_tokens": 100, "output_tokens": 20]]])).utf8))
        try handle.close()
        _ = hook("Stop")
        await settle()
        task = try XCTUnwrap(island.model.tasks.first { $0.key == key })
        XCTAssertEqual(task.activityStatus, .completed)
        XCTAssertEqual(task.tokens, 120)
        XCTAssertEqual(task.model, "Opus 5.5")
        XCTAssertEqual(task.entries.last { $0.kind == .result }?.text.chinese, "All tests pass.")

        // A held permission prompt is withdrawn when the helper disconnects.
        XCTAssertEqual(hook("UserPromptSubmit")?["accepted"] as? Bool, true)
        let reply = hook("PermissionRequest", ["tool_name": "Bash", "tool_use_id": "toolu_2", "tool_input": ["command": "rm -rf build"]], wait: true)
        XCTAssertEqual(reply?["pending"] as? Bool, true)
        await settle()
        task = try XCTUnwrap(island.model.tasks.first { $0.key == key })
        XCTAssertTrue(task.requests.isEmpty, "closing the helper connection hands the prompt back to the terminal")
        XCTAssertEqual(runtime.status, .connected)
    }
}

private final class MessageBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ClaudeCodeBridgeMessage] = []
    func append(_ message: ClaudeCodeBridgeMessage) { lock.lock(); storage.append(message); lock.unlock() }
    var messages: [ClaudeCodeBridgeMessage] { lock.lock(); defer { lock.unlock() }; return storage }
}
