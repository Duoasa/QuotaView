import Foundation
import XCTest
@testable import QuotaView
@testable import QuotaViewCore

@MainActor
final class SharedQuestionAnswerSmokeTests: XCTestCase {
    private var root: URL!
    private var process: Process!
    private var client: CodexSharedAppServerActivityClient!
    override func setUp() async throws {
        root = URL(fileURLWithPath: "/private/tmp/qv-answers-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try state([:])
        process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        process.arguments = [repository.appendingPathComponent("Tests/Fixtures/codex-shared-answers/server.py").path, root.path]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.standardError
        try process.run()
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: root.appendingPathComponent("rpc.sock").path) { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        client = CodexSharedAppServerActivityClient(configuration: .init(isEnabled: true,
            socketURL: root.appendingPathComponent("rpc.sock"), executablePath: nil,
            requestTimeoutSeconds: 0.2, subscriptionPollSeconds: 60))
        let connected = expectation(description: "isolated same-server connection")
        await client.start(handler: { _ in }, connectionStateHandler: { state in if state == .connected { connected.fulfill() } })
        await fulfillment(of: [connected], timeout: 3)
    }
    override func tearDown() async throws {
        await client?.stop()
        if process?.isRunning == true { process.terminate(); process.waitUntilExit() }
        if let root { try? FileManager.default.removeItem(at: root) }
    }
    private func state(_ value: [String: Any]) throws {
        try JSONSerialization.data(withJSONObject: value).write(to: root.appendingPathComponent("state.json"), options: .atomic)
    }
    private func handles(turn: String = "turn") async throws -> [CodexSharedQuestionHandle] {
        try await client.questionHandles(threadID: "conversation", turnHash: CodexActivityPrivacy.hashIdentifier(turn))
    }
    private func steers() throws -> [[String: Any]] {
        try String(contentsOf: root.appendingPathComponent("requests.jsonl"), encoding: .utf8)
            .split(separator: "\n").compactMap { try JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
            .filter { $0["method"] as? String == "turn/steer" }
    }
    func testNativeSocketSymlinkChecksBothPrivateDirectories() throws {
        let linkDirectory = root.appendingPathComponent("published")
        try FileManager.default.createDirectory(at: linkDirectory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let link = linkDirectory.appendingPathComponent("control.sock")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root.appendingPathComponent("rpc.sock"))
        XCTAssertEqual(try CodexSharedAppServerActivityClient.sharedSocketTarget(link).lastPathComponent, "rpc.sock")
        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: linkDirectory.path)
        XCTAssertThrowsError(try CodexSharedAppServerActivityClient.sharedSocketTarget(link))
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: linkDirectory.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: root.path)
        XCTAssertThrowsError(try CodexSharedAppServerActivityClient.sharedSocketTarget(link))
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        let chain = linkDirectory.appendingPathComponent("chain.sock")
        try FileManager.default.createSymbolicLink(at: chain, withDestinationURL: link)
        XCTAssertThrowsError(try CodexSharedAppServerActivityClient.sharedSocketTarget(chain))
    }

    func testBundledRuntimeInlineHistoryFallback() async throws {
        try state(["inlineOnly": true])
        let available = try await handles()
        let handle = try XCTUnwrap(available.first)
        try await client.submitQuestion(handle: handle, answers: ["B"])
        XCTAssertEqual(try steers().count, 1)
    }

    func testNativeIsolatedRuntimeQuestionAndAnswer() async throws {
        guard let path = ProcessInfo.processInfo.environment["QV_SHARED_NATIVE_FIXTURE"] else {
            throw XCTSkip("Run only against the isolated native mock-model fixture")
        }
        let fixtureURL = URL(fileURLWithPath: path).standardizedFileURL
        guard fixtureURL.path.hasPrefix("/private/tmp/qv-shared-native-") || fixtureURL.path.hasPrefix("/tmp/qv-shared-native-") else { throw CodexDesktopIPCError.peerMismatch }
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as? [String: String])
        let thread = try XCTUnwrap(fixture["thread"]), turn = try XCTUnwrap(fixture["turn"])
        let native = CodexSharedAppServerActivityClient(configuration: .init(isEnabled: true,
            socketURL: fixtureURL.deletingLastPathComponent().appendingPathComponent("server.sock"), executablePath: nil,
            subscriptionPollSeconds: 60, maximumMessageBytes: 8 * 1_048_576))
        let connected = expectation(description: "native isolated service")
        await native.start(handler: { _ in }, connectionStateHandler: { if $0 == .connected { connected.fulfill() } })
        await fulfillment(of: [connected], timeout: 5)
        do {
            let available = try await native.questionHandles(threadID: thread, turnHash: CodexActivityPrivacy.hashIdentifier(turn))
            let handle = try XCTUnwrap(available.first)
            XCTAssertEqual(handle.sourceItemID, "fixture-call")
            XCTAssertEqual(handle.questions.map(\.title), ["Fixture choice?"])
            try await native.submitQuestion(handle: handle, answers: ["B"])
            let current = await native.isCurrentQuestionHandle(handle)
            XCTAssertFalse(current)
            await native.stop()
        } catch { await native.stop(); throw error }
    }

    func testNativeIdentitySameTurnAndExactlyOneDispatch() async throws {
        let available = try await handles()
        let handle = try XCTUnwrap(available.first)
        let refreshed = try await handles()
        XCTAssertEqual(refreshed, [handle], "Ordinary polls preserve capabilities and drafts")
        try await client.submitQuestion(handle: handle, answers: ["B"])
        do { try await client.submitQuestion(handle: handle, answers: ["B"]); XCTFail("Duplicate sent") } catch {}
        let writes = try steers(); XCTAssertEqual(writes.count, 1)
        let params = try XCTUnwrap(writes.first?["params"] as? [String: Any])
        XCTAssertEqual(params["threadId"] as? String, "conversation")
        XCTAssertEqual(params["expectedTurnId"] as? String, "turn")
        let text = try XCTUnwrap((params["input"] as? [[String: Any]])?.first?["text"] as? String)
        XCTAssertTrue(text.contains("request_user_input_async")); XCTAssertTrue(text.contains("Fixture choice?")); XCTAssertTrue(text.contains("\"answer\":\"B\""))
        let remaining = try await handles(); XCTAssertTrue(remaining.isEmpty)
    }
    func testTurnChangeAndSameTextDifferentSourceCannotUseOldHandle() async throws {
        let available = try await handles()
        let handle = try XCTUnwrap(available.first)
        try state(["call": "other-call"])
        do { try await client.submitQuestion(handle: handle, answers: ["A"]); XCTFail("Different source accepted") } catch {}
        try state(["turn": "new-turn"])
        do { try await client.submitQuestion(handle: handle, answers: ["A"]); XCTFail("Different turn accepted") } catch {}
        XCTAssertTrue(try steers().isEmpty)
    }
    func testNativeAcceptedAnswerPreventsDispatchIncludingPartialGroups() async throws {
        try state(["twoQuestions": true])
        let available = try await handles()
        let handle = try XCTUnwrap(available.first)
        XCTAssertEqual(handle.questions.count, 2)
        try state(["twoQuestions": true, "answered": true])
        do { try await client.submitQuestion(handle: handle, answers: ["A", "C"]); XCTFail("Repeated existing answer") } catch {}
        XCTAssertTrue(try steers().isEmpty)
    }
    func testIncompleteUnloadedInternalOrTerminalStateCannotGrantCapability() async throws {
        for fixture: [String: Any] in [["cursorLoop": true], ["unloaded": true], ["source": ["subAgent": "fixture"]], ["terminal": true]] {
            try state(fixture)
            do { let result = try await handles(); XCTAssertTrue(result.isEmpty) } catch {}
        }
        XCTAssertTrue(try steers().isEmpty)
    }
    func testLostAcknowledgementCannotRetryOrRemintAfterReconnect() async throws {
        let available = try await handles()
        let handle = try XCTUnwrap(available.first)
        try state(["dropReply": true])
        do { try await client.submitQuestion(handle: handle, answers: ["A"]); XCTFail("Missing ACK accepted") }
        catch { XCTAssertEqual(error as? CodexDesktopIPCError, .outcomeUnknown) }
        do { try await client.submitQuestion(handle: handle, answers: ["A"]); XCTFail("Retried uncertain result") } catch {}
        XCTAssertEqual(try steers().count, 1)
        let valid = await client.isCurrentQuestionHandle(handle); XCTAssertFalse(valid)
    }
    func testMismatchingAcknowledgementIsUnknownAndSingleDispatch() async throws {
        let available = try await handles()
        let handle = try XCTUnwrap(available.first)
        try state(["wrongAck": true])
        do { try await client.submitQuestion(handle: handle, answers: ["A"]); XCTFail("Wrong turn ACK accepted") }
        catch { XCTAssertEqual(error as? CodexDesktopIPCError, .outcomeUnknown) }
        XCTAssertEqual(try steers().count, 1)
    }
    func testLocalObservationNeedsExactGroupAndRetainsDraftIdentityOnUpgrade() async throws {
        let available = try await handles()
        let handle = try XCTUnwrap(available.first)
        let session = CodexActivityPrivacy.hashIdentifier("conversation"), turn = CodexActivityPrivacy.hashIdentifier("turn")
        let model = IslandLiveStore()
        model.receiveLegacy(.init(event: .userPromptSubmit, sessionHash: session, turnHash: turn, sessionKind: .user, source: .appServer))
        let args = String(decoding: try JSONSerialization.data(withJSONObject: ["questions": [["title": "Fixture choice?", "options": ["A", "B"]]]]), as: UTF8.self)
        let line = try JSONSerialization.data(withJSONObject: ["type": "response_item", "payload": ["type": "function_call", "name": "functions.request_user_input_async", "call_id": "call", "arguments": args]])
        let content = try XCTUnwrap(CodexLocalPublicContent.decode(line, sessionHash: session, activeTurnHash: turn))
        model.receiveLocalContent(content)
        let requestID = try XCTUnwrap(model.tasks.first?.requests.first?.value.id)
        model.responseCapability = { $0.sharedQuestionHandle != nil }
        let dispatched = expectation(description: "island dispatch")
        model.respond = { [client] wire, result in
            let handle = try XCTUnwrap(wire.sharedQuestionHandle)
            let answers = wire.questions.map { result["answers"][$0.id]["answers"].array.first?.text ?? "" }
            try await client!.submitQuestion(handle: handle, answers: answers)
            dispatched.fulfill()
        }
        model.updateSharedQuestionCapabilities(threadID: "conversation", handles: [handle])
        XCTAssertEqual(model.tasks[0].requests.first?.value.id, requestID)
        XCTAssertEqual(model.tasks[0].requests.first?.value.canRespond, true)
        let wire = try XCTUnwrap(model.tasks[0].requests.first?.value.protocolRequest)
        XCTAssertFalse(wire.observationOnly)
        let other = try IslandCodexApprovalRequest(localQuestions: [["id": "q", "question": "Fixture choice?", "options": [["label": "A"], ["label": "B"]]]], callID: "other", sessionHash: session, turnHash: turn, asynchronous: true)
        XCTAssertNil(other.attachingSharedQuestionHandle(handle).sharedQuestionHandle)
        var draft = IslandApprovalDraft()
        draft.selectAnswer("B", for: wire.questions[0])
        let result = try XCTUnwrap(draft.result(for: wire))
        model.submit(model.tasks[0].id, requestID: requestID, decision: .reply(result))
        model.submit(model.tasks[0].id, requestID: requestID, decision: .reply(result))
        await fulfillment(of: [dispatched], timeout: 3)
        XCTAssertEqual(try steers().count, 1)
        XCTAssertEqual(model.tasks[0].requests.count, 1, "Dispatch acknowledgement is not accepted-answer settlement")
        model.updateSharedQuestionCapabilities(handles: [])
        XCTAssertEqual(model.tasks[0].requests.first?.value.canRespond, false)
        XCTAssertEqual(model.tasks[0].requests.first?.value.id, requestID)
    }
}
