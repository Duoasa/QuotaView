import Foundation
import XCTest
import Darwin
@testable import QuotaViewCore

final class CodexDesktopIPCClientTests: XCTestCase {
    func testLengthFramingHandlesFragmentationCoalescingAndBounds() throws {
        let a = Data("{\"a\":1}".utf8), b = Data("{\"b\":2}".utf8)
        let first = try CodexDesktopIPCFrameDecoder.frame(a, maximumFrameBytes: 1024)
        let second = try CodexDesktopIPCFrameDecoder.frame(b, maximumFrameBytes: 1024)
        var decoder = CodexDesktopIPCFrameDecoder(maximumFrameBytes: 1024)
        XCTAssertEqual(try decoder.append(first.prefix(2)), [])
        XCTAssertEqual(try decoder.append(first.dropFirst(2) + second), [a, b])
        XCTAssertThrowsError(try decoder.append(Data([0, 0, 0, 0])))
        var oversized = CodexDesktopIPCFrameDecoder(maximumFrameBytes: 1024)
        XCTAssertThrowsError(try oversized.append(Data([1, 4, 0, 0])))
    }

    func testOwnerDiscoveryTimeoutRecoversWithoutAStatusBroadcastOrNewActivity() async throws {
        let fixture = CodexDesktopIPCFixture(state: Self.state(requests: [Self.request(id: "approval")]))
        fixture.setOwnerDiscoveryReady(false)
        let client = fixture.client(timeout: 0.05), recorder = CodexDesktopIPCSnapshotRecorder()
        await client.start(snapshotHandler: { await recorder.record($0) }, stateHandler: { await recorder.recordState($0) })
        try await recorder.waitForConnection()
        do { try await client.follow(conversationID: "conversation"); XCTFail("Unready owner must time out") }
        catch { XCTAssertEqual(error as? CodexDesktopIPCError, .unavailable) }
        XCTAssertEqual(fixture.discoveryMessages.count, 1)
        fixture.setOwnerDiscoveryReady(true)
        let snapshot = try await recorder.wait(after: 0)
        XCTAssertEqual(snapshot.ownerClientID, "fixture-owner")
        XCTAssertEqual(snapshot.requests.count, 1)
        XCTAssertGreaterThanOrEqual(fixture.discoveryMessages.count, 2)
        XCTAssertTrue(fixture.submissions.isEmpty, "Only discovery/follow can be retried")
        await client.stop()
    }

    func testNativeFollowingStatusRequestFormallyDiscoversOwnerOutsideReader() async throws {
        let fixture = CodexDesktopIPCFixture(state: Self.state(requests: [Self.request(id: "approval")]))
        fixture.setOwnerDiscoveryReady(false)
        let client = fixture.client(timeout: 0.05), recorder = CodexDesktopIPCSnapshotRecorder()
        await client.start(snapshotHandler: { await recorder.record($0) }, stateHandler: { await recorder.recordState($0) })
        try await recorder.waitForConnection()
        do { try await client.follow(conversationID: "conversation"); XCTFail("Unready owner must time out") } catch { }
        fixture.setOwnerDiscoveryReady(true)
        fixture.emitFollowingStatusRequested()
        let snapshot = try await recorder.wait(after: 0)
        XCTAssertEqual(snapshot.requests.count, 1)
        XCTAssertTrue(fixture.discoveryMessages.contains { $0["targetClientId"] as? String == "fixture-owner" })
        XCTAssertTrue(fixture.submissions.isEmpty)
        await client.stop()
    }

    func testUnfollowAndStopCancelUnreadyOwnerRecovery() async throws {
        for stopping in [false, true] {
            let fixture = CodexDesktopIPCFixture(state: Self.state(requests: [Self.request(id: "approval")]))
            fixture.setOwnerDiscoveryReady(false)
            let client = fixture.client(timeout: 0.05), recorder = CodexDesktopIPCSnapshotRecorder()
            await client.start(snapshotHandler: { await recorder.record($0) }, stateHandler: { await recorder.recordState($0) })
            try await recorder.waitForConnection()
            do { try await client.follow(conversationID: "conversation"); XCTFail("Unready owner must time out") } catch { }
            if stopping { await client.stop() } else { await client.unfollow(conversationID: "conversation") }
            let attempts = fixture.discoveryMessages.count
            fixture.setOwnerDiscoveryReady(true); fixture.emitFollowingStatusRequested()
            try await Task.sleep(nanoseconds: 600_000_000)
            XCTAssertEqual(fixture.discoveryMessages.count, attempts)
            let snapshots = await recorder.count
            XCTAssertEqual(snapshots, 0)
            XCTAssertTrue(fixture.submissions.isEmpty)
            await client.stop()
        }
    }

    func testOwnerCapabilityDoesNotGuessMissingTaskSourceBeforeStoreAdmission() async throws {
        var state = Self.state(requests: [Self.request(id: "approval")])
        state.removeValue(forKey: "source")
        let fixture = CodexDesktopIPCFixture(state: state)
        let (client, _, snapshot) = try await fixture.connectedClient()
        let projection = try CodexDesktopRequestProjector.project(conversationID: snapshot.conversationID,
            conversationStateData: snapshot.conversationState)
        XCTAssertEqual(projection.sourceKind, .unknown)
        XCTAssertTrue(snapshot.supportsUntrustedAppInput, "Owner capability and Store user-task admission are separate proofs")
        XCTAssertEqual(snapshot.requests.count, 1)
        XCTAssertEqual(snapshot.requests.first?.requestID, .string("approval"))
        XCTAssertTrue(fixture.submissions.isEmpty)
        await client.stop()
    }

    func testOversizedConversationRevokesOnlyItsHandlesAndOtherTaskRemainsInteractive() async throws {
        let first = Self.state(requests: [Self.request(id: "first")])
        let fixture = CodexDesktopIPCFixture(state: first)
        var second = Self.state(requests: [Self.request(id: "second")]); second["id"] = "other"
        var request = Self.request(id: "second"), params = request["params"] as! [String: Any]
        params["threadId"] = "other"; request["params"] = params; second["requests"] = [request]
        fixture.setAdditionalState(second, conversationID: "other", revision: 7, emit: false)
        let client = fixture.client(), recorder = CodexDesktopIPCSnapshotRecorder()
        await client.start(snapshotHandler: { await recorder.record($0) }, stateHandler: { await recorder.recordState($0) },
            invalidationHandler: { await recorder.recordInvalidation($0) })
        try await client.follow(conversationID: "conversation")
        let original = try await recorder.wait(after: 0)
        try await client.follow(conversationID: "other")
        let other = try await recorder.wait(after: 1)
        var huge = first; huge["unprojectedHistory"] = String(repeating: "x", count: CodexDesktopRequestProjector.maximumStateBytes)
        fixture.setState(huge, revision: 8)
        let invalidation = try await recorder.waitForInvalidation(after: 0)
        XCTAssertEqual(invalidation.conversationID, "conversation")
        XCTAssertEqual(invalidation.connectionEpoch, original.connectionEpoch)
        XCTAssertEqual(invalidation.reason, .resourceLimit)
        do { _ = try await client.submit(handle: try XCTUnwrap(original.requests.first), result: Self.data(["decision": "accept"])); XCTFail("Affected handle must be revoked") }
        catch { XCTAssertEqual(error as? CodexDesktopIPCError, .staleRequest) }
        _ = try await client.submit(handle: try XCTUnwrap(other.requests.first), result: Self.data(["decision": "accept"]))
        XCTAssertEqual(fixture.submissions.count, 1)
        XCTAssertEqual((fixture.submissions[0]["params"] as? [String: Any])?["conversationId"] as? String, "other")
        let connected = await recorder.isConnected
        XCTAssertTrue(connected, "One bounded conversation cannot stop the healthy stream")
        let follows = fixture.followingCount
        fixture.setState(first, revision: 9); fixture.emitFollowingStatusRequested()
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(fixture.followingCount, follows, "Automatic refresh cannot loop on resource-blocked history")
        await client.start(snapshotHandler: { await recorder.record($0) }, stateHandler: { await recorder.recordState($0) },
            invalidationHandler: { await recorder.recordInvalidation($0) })
        let resumed = try await recorder.wait(after: 2)
        XCTAssertEqual(resumed.conversationID, "conversation")
        XCTAssertEqual(resumed.requests.count, 1)
        await client.stop()
    }

    func testRetainedBudgetRevokesIncomingConversationWithoutRemovingOtherCapability() async throws {
        var first = Self.state(requests: [Self.request(id: "first")]); first["history"] = String(repeating: "x", count: 2400)
        var request = Self.request(id: "second"), params = request["params"] as! [String: Any]
        params["threadId"] = "other"; request["params"] = params
        var second = Self.state(requests: [request]); second["id"] = "other"; second["history"] = String(repeating: "x", count: 2400)
        let fixture = CodexDesktopIPCFixture(state: first)
        fixture.setAdditionalState(second, conversationID: "other", revision: 7, emit: false)
        let client = fixture.client(maximumFrameBytes: 4096, maximumRetainedStateBytes: 4096), recorder = CodexDesktopIPCSnapshotRecorder()
        await client.start(snapshotHandler: { await recorder.record($0) }, stateHandler: { await recorder.recordState($0) },
            invalidationHandler: { await recorder.recordInvalidation($0) })
        try await client.follow(conversationID: "conversation")
        let original = try await recorder.wait(after: 0)
        try await client.follow(conversationID: "other")
        let invalidation = try await recorder.waitForInvalidation(after: 0)
        XCTAssertEqual(invalidation.conversationID, "other")
        XCTAssertEqual(invalidation.hostID, "local")
        let snapshots = await recorder.count
        XCTAssertEqual(snapshots, 1)
        _ = try await client.submit(handle: try XCTUnwrap(original.requests.first), result: Self.data(["decision": "decline"]))
        XCTAssertEqual(fixture.submissions.count, 1)
        let connected = await recorder.isConnected
        XCTAssertTrue(connected)
        await client.stop()
    }

    func testOversizedFrameHeaderSuspendsWithoutProtocolMismatchOrAutomaticReconnect() async throws {
        let fixture = CodexDesktopIPCFixture(state: Self.state(requests: [Self.request(id: "approval")]))
        let client = fixture.client(frameDrainTimeoutSeconds: 0.05), recorder = CodexDesktopIPCSnapshotRecorder()
        await client.start(snapshotHandler: { await recorder.record($0) }, stateHandler: { await recorder.recordState($0) },
            invalidationHandler: { await recorder.recordInvalidation($0) })
        try await client.follow(conversationID: "conversation")
        let original = try await recorder.wait(after: 0)
        fixture.emitFrameHeader(length: 9_437_185)
        let invalidation = try await recorder.waitForInvalidation(after: 0)
        XCTAssertNil(invalidation.conversationID); XCTAssertNil(invalidation.hostID)
        XCTAssertEqual(invalidation.reason, .resourceLimit)
        try await recorder.waitForDisconnect()
        let initializations = fixture.initializeCount
        try await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertEqual(fixture.initializeCount, initializations, "Resource pressure must not cause repeated reconnects")
        await client.start(snapshotHandler: { await recorder.record($0) }, stateHandler: { await recorder.recordState($0) },
            invalidationHandler: { await recorder.recordInvalidation($0) })
        let restarted = try await recorder.wait(after: 1)
        XCTAssertGreaterThan(restarted.connectionEpoch, original.connectionEpoch)
        XCTAssertEqual(restarted.requests.count, 1, "Explicit start can recover from resources; protocol is still compatible")
        await client.stop()
    }

    func testAsyncQuestionCountIsScopedResourceLimitRatherThanProtocolMismatch() async throws {
        let first = Self.state(requests: [Self.request(id: "approval")])
        let fixture = CodexDesktopIPCFixture(state: first), client = fixture.client(), recorder = CodexDesktopIPCSnapshotRecorder()
        await client.start(snapshotHandler: { await recorder.record($0) }, stateHandler: { await recorder.recordState($0) },
            invalidationHandler: { await recorder.recordInvalidation($0) })
        try await client.follow(conversationID: "conversation")
        _ = try await recorder.wait(after: 0)
        let questions = (0...CodexDesktopRequestProjector.maximumAsyncQuestions).map { ["title": "Question \($0)", "options": ["A"]] as [String: Any] }
        fixture.setState(Self.state(requests: [], items: [["id": "message", "type": "agentMessage", "questions": questions]]), revision: 8)
        let invalidation = try await recorder.waitForInvalidation(after: 0)
        XCTAssertEqual(invalidation.conversationID, "conversation")
        XCTAssertEqual(invalidation.reason, .resourceLimit)
        let connected = await recorder.isConnected
        XCTAssertTrue(connected)
        await client.stop()
    }

    func testJSONNodeAndDepthLimitsPauseAsResourcesAndExplicitStartRecovers() async throws {
        for nodeBudget in [false, true] {
            let first = Self.state(requests: [Self.request(id: "approval")])
            let fixture = CodexDesktopIPCFixture(state: first), client = fixture.client(), recorder = CodexDesktopIPCSnapshotRecorder()
            await client.start(snapshotHandler: { await recorder.record($0) }, stateHandler: { await recorder.recordState($0) },
                invalidationHandler: { await recorder.recordInvalidation($0) })
            try await client.follow(conversationID: "conversation")
            _ = try await recorder.wait(after: 0)
            var huge = first
            if nodeBudget { huge["unprojectedHistory"] = Array(repeating: "x", count: 100_001) }
            else {
                var deep: Any = "x"
                for _ in 0..<66 { deep = [deep] }
                huge["unprojectedHistory"] = deep
            }
            fixture.setState(huge, revision: 8)
            let invalidation = try await recorder.waitForInvalidation(after: 0)
            XCTAssertEqual(invalidation.conversationID, "conversation", "A complete unique native envelope attributes tree pressure safely")
            XCTAssertEqual(invalidation.reason, .resourceLimit)
            let connected = await recorder.isConnected
            XCTAssertTrue(connected)
            fixture.setState(first, revision: 9, emit: false)
            await client.start(snapshotHandler: { await recorder.record($0) }, stateHandler: { await recorder.recordState($0) },
                invalidationHandler: { await recorder.recordInvalidation($0) })
            let resumed = try await recorder.wait(after: 1)
            XCTAssertEqual(resumed.requests.count, 1)
            XCTAssertTrue(fixture.submissions.isEmpty)
            await client.stop()
        }
    }

    func testOversizedWireFrameDrainsWholeEnvelopeThenOnlyQuarantinesItsFollow() async throws {
        let first = Self.state(requests: [Self.request(id: "first")])
        let fixture = CodexDesktopIPCFixture(state: first), client = fixture.client(maximumFrameBytes: 1024)
        let recorder = CodexDesktopIPCSnapshotRecorder()
        await client.start(snapshotHandler: { await recorder.record($0) }, stateHandler: { await recorder.recordState($0) },
            invalidationHandler: { await recorder.recordInvalidation($0) })
        try await client.follow(conversationID: "conversation")
        let original = try await recorder.wait(after: 0)
        let payload = Self.data(["type": "broadcast", "method": "thread-stream-state-changed", "sourceClientId": "fixture-owner",
            "targetClientIds": ["fixture-client"], "version": 11,
            "params": ["conversationId": "conversation", "hostId": "local", "change": ["type": "snapshot", "revision": 8,
                "conversationState": ["text": String(repeating: "\\\"}\n{quoted}", count: 1000)]]]])
        fixture.emitRawPayload(payload, chunkBytes: 17)
        let invalidation = try await recorder.waitForInvalidation(after: 0)
        XCTAssertEqual(invalidation.conversationID, "conversation")
        XCTAssertEqual(invalidation.connectionEpoch, original.connectionEpoch)
        let connected = await recorder.isConnected
        XCTAssertTrue(connected)
        var otherRequest = Self.request(id: "question"), params = otherRequest["params"] as! [String: Any]
        params["threadId"] = "other"; otherRequest["params"] = params
        var other = Self.state(requests: [otherRequest]); other["id"] = "other"
        fixture.setAdditionalState(other, conversationID: "other", revision: 7, emit: false)
        try await client.follow(conversationID: "other")
        let healthy = try await recorder.wait(after: 1)
        _ = try await client.submit(handle: XCTUnwrap(healthy.requests.first), result: Self.data(["decision": "accept"]))
        XCTAssertEqual(fixture.submissions.count, 1)
        XCTAssertEqual(fixture.initializeCount, 1)
        await client.stop()
    }

    func testOversizedForeignAudienceAndUnfollowedEnvelopesCannotRevokeHealthyCapability() async throws {
        for excluded in ["foreign", "audience", "unfollowed"] {
            let fixture = CodexDesktopIPCFixture(state: Self.state(requests: [Self.request(id: "first")]))
            let client = fixture.client(maximumFrameBytes: 1024), recorder = CodexDesktopIPCSnapshotRecorder()
            await client.start(snapshotHandler: { await recorder.record($0) }, stateHandler: { await recorder.recordState($0) },
                invalidationHandler: { await recorder.recordInvalidation($0) })
            try await client.follow(conversationID: "conversation")
            let original = try await recorder.wait(after: 0)
            let envelope: [String: Any] = ["type": "broadcast", "method": "thread-stream-state-changed",
                "sourceClientId": excluded == "foreign" ? "foreign-owner" : "fixture-owner", "version": 99,
                "targetClientIds": [excluded == "audience" ? "different-client" : "fixture-client"],
                "params": ["conversationId": excluded == "unfollowed" ? "unfollowed" : "conversation", "hostId": "local",
                    "change": ["conversationState": ["text": String(repeating: "x", count: 4096)]]]]
            fixture.emitRawPayload(Self.data(envelope), chunkBytes: 71)
            fixture.setState(Self.state(requests: [Self.request(id: "first")]), revision: 8)
            _ = try await recorder.wait(after: 1)
            _ = try await client.submit(handle: XCTUnwrap(original.requests.first), result: Self.data(["decision": "decline"]))
            XCTAssertEqual(fixture.submissions.count, 1, excluded)
            let connected = await recorder.isConnected
            XCTAssertTrue(connected, excluded)
            await client.stop()
        }
    }

    func testDuplicateDecodedRoutingOrUnknownScopeCannotChooseAConversation() async throws {
        let body = String(repeating: "x", count: 4096)
        let badParams = [
            "\"conversationId\":\"conversation\",\"conversation\\u0049d\":\"other\",\"hostId\":\"local\"",
            "\"conversationId\":\"conversation\"",
            "\"conversationId\":false,\"hostId\":\"local\""
        ]
        for routing in badParams {
            let fixture = CodexDesktopIPCFixture(state: Self.state(requests: [Self.request(id: "first")]))
            let client = fixture.client(maximumFrameBytes: 1024), recorder = CodexDesktopIPCSnapshotRecorder()
            await client.start(snapshotHandler: { await recorder.record($0) }, stateHandler: { await recorder.recordState($0) },
                invalidationHandler: { await recorder.recordInvalidation($0) })
            try await client.follow(conversationID: "conversation")
            _ = try await recorder.wait(after: 0)
            let text = "{\"type\":\"broadcast\",\"method\":\"thread-stream-state-changed\",\"sourceClientId\":\"fixture-owner\",\"params\":{\(routing),\"change\":{\"body\":\"\(body)\"}},\"version\":11}"
            fixture.emitRawPayload(Data(text.utf8), chunkBytes: 19)
            let invalidation = try await recorder.waitForInvalidation(after: 0)
            XCTAssertNil(invalidation.conversationID)
            try await recorder.waitForDisconnect()
            XCTAssertEqual(fixture.initializeCount, 1)
            await client.stop()
        }
    }

    func testPartialHeaderAndOversizedBodyDeadlinesSuspendWithoutMoreBytes() async throws {
        for bytes in [Data([1]), Data([1, 0]), Data([1, 0, 0]), Data([0, 16, 0, 0]) + Data("{\"type\":".utf8)] {
            let fixture = CodexDesktopIPCFixture(state: Self.state(requests: [Self.request(id: "first")]))
            let client = fixture.client(maximumFrameBytes: 1024, frameDrainTimeoutSeconds: 0.05)
            let recorder = CodexDesktopIPCSnapshotRecorder()
            await client.start(snapshotHandler: { await recorder.record($0) }, stateHandler: { await recorder.recordState($0) },
                invalidationHandler: { await recorder.recordInvalidation($0) })
            try await client.follow(conversationID: "conversation")
            _ = try await recorder.wait(after: 0)
            fixture.emitRawBytes(bytes)
            let invalidation = try await recorder.waitForInvalidation(after: 0)
            XCTAssertNil(invalidation.conversationID)
            try await recorder.waitForDisconnect()
            await client.stop()
        }
    }

    func testNativeWireHardcapSuspendsAtHeaderWithoutAllocatingItsBody() async throws {
        let fixture = CodexDesktopIPCFixture(state: Self.state(requests: [Self.request(id: "first")]))
        let client = fixture.client(), recorder = CodexDesktopIPCSnapshotRecorder()
        await client.start(snapshotHandler: { await recorder.record($0) }, stateHandler: { await recorder.recordState($0) },
            invalidationHandler: { await recorder.recordInvalidation($0) })
        try await client.follow(conversationID: "conversation")
        _ = try await recorder.wait(after: 0)
        fixture.emitFrameHeader(length: 268_435_457)
        let invalidation = try await recorder.waitForInvalidation(after: 0)
        XCTAssertNil(invalidation.conversationID)
        try await recorder.waitForDisconnect()
        await client.stop()
    }

    func testOldUnscopedInvalidationCallbackCannotCloseRestartedConnection() async throws {
        let fixture = CodexDesktopIPCFixture(state: Self.state(requests: [Self.request(id: "question")]))
        let client = fixture.client(frameDrainTimeoutSeconds: 0.05), recorder = CodexDesktopIPCSnapshotRecorder()
        let gate = CodexDesktopResourceCallbackGate()
        await client.start(snapshotHandler: { await recorder.record($0) }, stateHandler: { await recorder.recordState($0) },
            invalidationHandler: { value in
                await recorder.recordInvalidation(value)
                await gate.pause()
            })
        try await client.follow(conversationID: "conversation")
        let old = try await recorder.wait(after: 0)
        fixture.emitFrameHeader(length: 9_437_185)
        try await gate.waitForEntry()
        await client.stop()
        await client.start(snapshotHandler: { await recorder.record($0) }, stateHandler: { await recorder.recordState($0) },
            invalidationHandler: { await recorder.recordInvalidation($0) })
        try await client.follow(conversationID: "conversation")
        let fresh = try await recorder.wait(after: 1)
        XCTAssertGreaterThan(fresh.connectionEpoch, old.connectionEpoch)
        await gate.release()
        try await gate.waitForExit()
        await Task.yield()
        fixture.setState(Self.state(requests: [Self.request(id: "question")]), revision: 8)
        let continued = try await recorder.wait(after: 2)
        XCTAssertEqual(continued.connectionEpoch, fresh.connectionEpoch)
        _ = try await client.submit(handle: XCTUnwrap(continued.requests.first), result: Self.data(["decision": "accept"]))
        XCTAssertEqual(fixture.submissions.count, 1)
        await client.stop()
    }

    func testTypedIDsRetainStringIntegerAndRejectBoolean() throws {
        let decoder = JSONDecoder(), encoder = JSONEncoder()
        XCTAssertNotEqual(try decoder.decode(CodexDesktopIPCRequestID.self, from: Data("42".utf8)),
                          try decoder.decode(CodexDesktopIPCRequestID.self, from: Data("\"42\"".utf8)))
        XCTAssertEqual(try encoder.encode(CodexDesktopIPCRequestID.integer(42)), Data("42".utf8))
        XCTAssertThrowsError(try decoder.decode(CodexDesktopIPCRequestID.self, from: Data("true".utf8)))
    }

    func testSocketPeerChecksRejectForeignUIDWritableDirectoryAndSymlink() throws {
        let root = URL(fileURLWithPath: "/tmp/qv-ipc-peer-" + String(UUID().uuidString.prefix(8)))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let endpoint = root.appendingPathComponent("ipc.sock")
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(fd, 0); defer { Darwin.close(fd) }
        var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes = Array(endpoint.path.utf8) + [0]
        XCTAssertLessThanOrEqual(bytes.count, MemoryLayout.size(ofValue: address.sun_path))
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        XCTAssertEqual(result, 0)
        XCTAssertNoThrow(try CodexDesktopIPCTransport.verifyPeer(endpoint))
        XCTAssertThrowsError(try CodexDesktopIPCTransport.verifyPeer(endpoint, expectedUID: getuid() + 1))
        XCTAssertEqual(chmod(root.path, 0o722), 0)
        XCTAssertThrowsError(try CodexDesktopIPCTransport.verifyPeer(endpoint))
        XCTAssertEqual(chmod(root.path, 0o700), 0)
        let link = root.appendingPathComponent("alias.sock")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: endpoint)
        XCTAssertThrowsError(try CodexDesktopIPCTransport.verifyPeer(link))
    }

    func testFiveNativeRPCVerbsPreserveExactOwnerMethodAndRequestID() async throws {
        let methods: [(String, String, [String: Any])] = [
            ("item/commandExecution/requestApproval", "thread-follower-command-approval-decision", ["decision": "accept"]),
            ("item/fileChange/requestApproval", "thread-follower-file-approval-decision", ["decision": "decline"]),
            ("item/permissions/requestApproval", "thread-follower-permissions-request-approval-response", ["permissions": [:], "scope": "turn"]),
            ("item/tool/requestUserInput", "thread-follower-submit-user-input", ["answers": ["q": ["answers": ["A"]]]]),
            ("mcpServer/elicitation/request", "thread-follower-submit-mcp-server-elicitation-response", ["action": "cancel", "content": NSNull()])
        ]
        for (index, tuple) in methods.enumerated() {
            let rawID: Any = index == 0 ? 42 : "42"
            let fixture = CodexDesktopIPCFixture(state: Self.state(requests: [Self.request(id: rawID, method: tuple.0)]))
            let (client, recorder, snapshot) = try await fixture.connectedClient()
            let handle = try XCTUnwrap(snapshot.requests.first)
            XCTAssertEqual(handle.kind, .serverRequest)
            let outcome = try await client.submit(handle: handle, result: Self.data(tuple.2))
            XCTAssertEqual(outcome, .acceptedForDispatch)
            let sent = try XCTUnwrap(fixture.submissions.first)
            XCTAssertEqual(sent["method"] as? String, tuple.1)
            XCTAssertEqual(sent["targetClientId"] as? String, "fixture-owner")
            XCTAssertEqual(sent["version"] as? Int, 1)
            let params = try XCTUnwrap(sent["params"] as? [String: Any])
            XCTAssertEqual(params["conversationId"] as? String, "conversation")
            XCTAssertEqual(try JSONSerialization.data(withJSONObject: params["requestId"]!, options: .fragmentsAllowed),
                           try JSONSerialization.data(withJSONObject: rawID, options: .fragmentsAllowed))
            // The acknowledgement must not remove the request before stream proof.
            let latest = await recorder.latest
            XCTAssertEqual(latest?.requests.first?.requestID, handle.requestID)
            await client.stop()
        }
    }

    func testUnprovenOwnerAndRemoteHostCannotSubmit() async throws {
        let fixture = CodexDesktopIPCFixture(state: Self.state(requests: [Self.request()]), supportsInput: false)
        let (client, _, snapshot) = try await fixture.connectedClient()
        XCTAssertFalse(snapshot.supportsUntrustedAppInput)
        await assertSubmissionError(.staleRequest, client: client, handle: try XCTUnwrap(snapshot.requests.first))
        XCTAssertTrue(fixture.submissions.isEmpty)
        await client.stop()
        let remote = CodexDesktopIPCFixture(state: Self.state(requests: [Self.request()]))
        let (remoteClient, recorder, _) = try await remote.connectedClient()
        let count = await recorder.count
        try await remoteClient.follow(conversationID: "conversation", hostID: "remote")
        let remoteSnapshot = try await recorder.wait(after: count)
        XCTAssertEqual(remoteSnapshot.hostID, "remote")
        XCTAssertFalse(remoteSnapshot.supportsUntrustedAppInput)
        await assertSubmissionError(.staleRequest, client: remoteClient, handle: try XCTUnwrap(remoteSnapshot.requests.first))
        XCTAssertTrue(remote.submissions.isEmpty)
        await remoteClient.stop()
    }

    func testTokenPatchKeepsHandleButRequestRemovalAndTurnChangeInvalidateIt() async throws {
        let fixture = CodexDesktopIPCFixture(state: Self.state(requests: [Self.request()]))
        let (client, recorder, initial) = try await fixture.connectedClient()
        let old = try XCTUnwrap(initial.requests.first)
        var count = await recorder.count
        fixture.patch([["op": "add", "path": ["latestTokenUsageInfo"], "value": ["total": 300]]], baseRevision: 7, revision: 8)
        let updated = try await recorder.wait(after: count)
        XCTAssertEqual(updated.requests.first, old)
        count = await recorder.count
        fixture.patch([["op": "remove", "path": ["requests", 0]]], baseRevision: 8, revision: 9)
        let removed = try await recorder.wait(after: count)
        XCTAssertTrue(removed.requests.isEmpty)
        await assertSubmissionError(.staleRequest, client: client, handle: old)
        count = await recorder.count
        fixture.setState(Self.state(requests: [Self.request(turn: "prior-turn")]), revision: 10)
        let staleTurn = try await recorder.wait(after: count)
        XCTAssertTrue(staleTurn.requests.isEmpty)
        XCTAssertTrue(fixture.submissions.isEmpty)
        await client.stop()
    }

    func testOutOfSequencePatchesRequireFreshSnapshotBeforeWrites() async throws {
        let fixture = CodexDesktopIPCFixture(state: Self.state(requests: [Self.request()]))
        let (client, recorder, initial) = try await fixture.connectedClient()
        let old = try XCTUnwrap(initial.requests.first)
        fixture.setAutomaticSnapshots(false)
        fixture.patch([["op": "replace", "path": ["title"], "value": "Changed"]], baseRevision: 99, revision: 100)
        try await fixture.waitForFollowingCount(2)
        await assertSubmissionError(.staleRequest, client: client, handle: old)
        let count = await recorder.count
        fixture.setState(Self.state(requests: [Self.request()]), revision: 101)
        let fresh = try await recorder.wait(after: count)
        XCTAssertNotEqual(fresh.requests.first, old)
        XCTAssertTrue(fixture.submissions.isEmpty)
        await client.stop()
    }

    func testTimeoutAndForeignAcknowledgementNeverRetryOrReportSettlement() async throws {
        for acknowledge in [false, true] {
            let fixture = CodexDesktopIPCFixture(state: Self.state(requests: [Self.request()]))
            fixture.setSubmissionAcknowledgement(acknowledge, owner: "foreign-owner")
            let (client, _, snapshot) = try await fixture.connectedClient(timeout: 0.1)
            let handle = try XCTUnwrap(snapshot.requests.first)
            await assertSubmissionError(.outcomeUnknown, client: client, handle: handle)
            await assertSubmissionError(.alreadySubmitted, client: client, handle: handle)
            XCTAssertEqual(fixture.submissions.count, 1)
            await client.stop()
        }
    }

    func testStreamGapCannotRearmPreviouslySubmittedIdentityWithNewNonce() async throws {
        let fixture = CodexDesktopIPCFixture(state: Self.state(requests: [Self.request()]))
        let (client, recorder, initial) = try await fixture.connectedClient()
        let handle = try XCTUnwrap(initial.requests.first)
        _ = try await client.submit(handle: handle, result: Self.data(["decision": "accept"]))
        fixture.setAutomaticSnapshots(false)
        fixture.patch([["op": "replace", "path": ["title"], "value": "Gap"]], baseRevision: 99, revision: 100)
        try await fixture.waitForFollowingCount(2)
        let count = await recorder.count
        fixture.setState(Self.state(requests: [Self.request()]), revision: 101)
        let restored = try await recorder.wait(after: count)
        let newHandle = try XCTUnwrap(restored.requests.first)
        XCTAssertNotEqual(handle, newHandle)
        await assertSubmissionError(.alreadySubmitted, client: client, handle: newHandle)
        XCTAssertEqual(fixture.submissions.count, 1)
        await client.stop()
    }

    func testVersionMismatchAndStopInvalidatePreviouslyMintedHandles() async throws {
        let fixture = CodexDesktopIPCFixture(state: Self.state(requests: [Self.request()]))
        let (client, recorder, snapshot) = try await fixture.connectedClient()
        let handle = try XCTUnwrap(snapshot.requests.first)
        fixture.emitState(version: 12)
        try await recorder.waitForDisconnect()
        await assertSubmissionError(.unavailable, client: client, handle: handle)
        XCTAssertTrue(fixture.submissions.isEmpty)
        await client.stop()
        await assertSubmissionError(.unavailable, client: client, handle: handle)
    }

    func testAsyncAnswerUsesFreshIdentityRestrictedNativeTagAndStreamProof() async throws {
        let question: [String: Any] = ["type": "agentMessage", "id": "question-source", "questions": [["title": "Which?", "options": ["A", "B"]]]]
        let fixture = CodexDesktopIPCFixture(state: Self.state(requests: [], items: [question]))
        let (client, recorder, initial) = try await fixture.connectedClient()
        let handle = try XCTUnwrap(initial.requests.first)
        XCTAssertEqual(handle.kind, .asynchronousQuestion)
        guard case .string(let id) = handle.requestID else { return XCTFail("Expected native question identity") }
        let result = Self.data(["answers": [id: ["answers": ["A"]]]])
        let outcome = try await client.submit(handle: handle, result: result)
        XCTAssertEqual(outcome, .acceptedForDispatch)
        XCTAssertEqual(fixture.followingCount, 2)
        let sent = try XCTUnwrap(fixture.submissions.first)
        XCTAssertEqual(sent["method"] as? String, "thread-follower-steer-turn")
        let params = try XCTUnwrap(sent["params"] as? [String: Any])
        XCTAssertNil(params["requestId"]); XCTAssertNil(params["expectedTurnId"])
        let input = try XCTUnwrap(params["input"] as? [[String: Any]])
        let text = try XCTUnwrap(input.first?["text"] as? String)
        XCTAssertTrue(text.hasPrefix(CodexDesktopRequestProjector.asyncReplyOpeningTag + "\n"))
        let latest = await recorder.latest
        XCTAssertEqual(latest?.requests.first?.requestID, handle.requestID)
        await assertSubmissionError(.alreadySubmitted, client: client, handle: handle, response: result)
        let count = await recorder.count
        let reply: [String: Any] = ["type": "steeringUserMessage", "id": "reply", "status": "accepted", "input": input]
        fixture.setState(Self.state(requests: [], items: [question, reply]), revision: 8)
        let resolved = try await recorder.wait(after: count)
        XCTAssertTrue(resolved.requests.isEmpty)
        await assertSubmissionError(.staleRequest, client: client, handle: handle, response: result)
        XCTAssertEqual(fixture.submissions.count, 1)
        await client.stop()
    }

    func testSynchronousQuestionSkipReturnsNativeEmptyAnswersAndWaitsForOwnerSettlement() async throws {
        let fixture = CodexDesktopIPCFixture(state: Self.state(requests: [Self.request(id: "question-rpc", method: "item/tool/requestUserInput")]))
        let (client, recorder, snapshot) = try await fixture.connectedClient()
        let handle = try XCTUnwrap(snapshot.requests.first)
        let outcome = try await client.submit(handle: handle, result: Self.data(["answers": [:]]))
        XCTAssertEqual(outcome, .acceptedForDispatch)
        let sent = try XCTUnwrap(fixture.submissions.first)
        XCTAssertEqual(sent["method"] as? String, "thread-follower-submit-user-input")
        let params = try XCTUnwrap(sent["params"] as? [String: Any])
        XCTAssertEqual(params["requestId"] as? String, "question-rpc")
        let response = try XCTUnwrap(params["response"] as? [String: Any])
        XCTAssertTrue(try XCTUnwrap(response["answers"] as? [String: Any]).isEmpty)
        let latest = await recorder.latest
        XCTAssertEqual(latest?.requests.first?.requestID, handle.requestID)
        fixture.setState(Self.state(requests: []), revision: 8)
        let settled = try await recorder.wait(after: 1)
        XCTAssertTrue(settled.requests.isEmpty)
        await client.stop()
    }

    func testAsyncCustomAnswerPreservesNativeIdentityAndExactUserText() async throws {
        let question: [String: Any] = ["type": "agentMessage", "id": "question-source", "questions": [["title": "Which?", "options": ["A", "B"]]]]
        let fixture = CodexDesktopIPCFixture(state: Self.state(requests: [], items: [question]))
        let (client, _, snapshot) = try await fixture.connectedClient()
        let handle = try XCTUnwrap(snapshot.requests.first)
        guard case .string(let id) = handle.requestID else { return XCTFail("Expected native question identity") }
        let answer = "自定义选择\n包含 \"引号\" 与 <tag>"
        let result = Self.data(["answers": [id: ["answers": [answer]]]])
        _ = try await client.submit(handle: handle, result: result)
        let sent = try XCTUnwrap(fixture.submissions.first)
        let params = try XCTUnwrap(sent["params"] as? [String: Any])
        let input = try XCTUnwrap(params["input"] as? [[String: Any]])
        let text = try XCTUnwrap(input.first?["text"] as? String)
        let body = text.dropFirst(CodexDesktopRequestProjector.asyncReplyOpeningTag.count)
            .dropLast(CodexDesktopRequestProjector.asyncReplyClosingTag.count)
        let replies = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [[String: Any]])
        XCTAssertEqual(replies.count, 1)
        XCTAssertEqual(replies[0]["questionItemId"] as? String, id)
        XCTAssertEqual(replies[0]["question"] as? String, "Which?")
        XCTAssertEqual(replies[0]["answer"] as? String, answer)
        await client.stop()
    }

    func testAsyncSkipCannotBeEncodedAsAnEmptyAnswerOrFabricatedNativeReply() async throws {
        let question: [String: Any] = ["type": "agentMessage", "id": "question-source", "questions": [["title": "Which?", "options": ["A", "B"]]]]
        let fixture = CodexDesktopIPCFixture(state: Self.state(requests: [], items: [question]))
        let (client, _, snapshot) = try await fixture.connectedClient()
        let handle = try XCTUnwrap(snapshot.requests.first)
        guard case .string(let id) = handle.requestID else { return XCTFail("Expected native question identity") }
        for result in [Self.data(["answers": [:]]), Self.data(["answers": [id: ["answers": [""]]]])] {
            await assertSubmissionError(.invalidResponse, client: client, handle: handle, response: result)
        }
        XCTAssertTrue(fixture.submissions.isEmpty)
        await client.stop()
    }

    func testAsyncFreshSnapshotRejectsChangedQuestionAndResultOnDifferentTurnIsUnknown() async throws {
        let item: [String: Any] = ["type": "agentMessage", "id": "source", "questions": [["title": "Original?", "options": ["A"]]]]
        let fixture = CodexDesktopIPCFixture(state: Self.state(requests: [], items: [item]))
        let (client, _, snapshot) = try await fixture.connectedClient()
        let handle = try XCTUnwrap(snapshot.requests.first)
        guard case .string(let id) = handle.requestID else { return XCTFail("Expected native question identity") }
        // Change owner state without publishing: refresh during submit must catch it.
        let changed: [String: Any] = ["type": "agentMessage", "id": "source", "questions": [["title": "Changed?", "options": ["A"]]]]
        fixture.setState(Self.state(requests: [], items: [changed]), revision: 8, emit: false)
        await assertSubmissionError(.staleRequest, client: client, handle: handle, response: Self.data(["answers": [id: ["answers": ["A"]]]]))
        XCTAssertTrue(fixture.submissions.isEmpty)
        await client.stop()
        let other = CodexDesktopIPCFixture(state: Self.state(requests: [], items: [item]))
        other.setSteerResultTurn("different-turn")
        let (otherClient, _, otherSnapshot) = try await other.connectedClient()
        let otherHandle = try XCTUnwrap(otherSnapshot.requests.first)
        await assertSubmissionError(.outcomeUnknown, client: otherClient, handle: otherHandle, response: Self.data(["answers": [id: ["answers": ["A"]]]]))
        XCTAssertEqual(other.submissions.count, 1)
        await otherClient.stop()
    }

    private func assertSubmissionError(_ expected: CodexDesktopIPCError, client: CodexDesktopIPCClient,
                                       handle: CodexDesktopIPCRequestHandle, response: Data = Data("{\"decision\":\"accept\"}".utf8)) async {
        do { _ = try await client.submit(handle: handle, result: response); XCTFail("Expected \(expected)") }
        catch { XCTAssertEqual(error as? CodexDesktopIPCError, expected, "Actual: \(error)") }
    }
    static func data(_ object: Any) -> Data { try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) }
    static func request(id: Any = 42, method: String = "item/commandExecution/requestApproval", turn: String = "turn") -> [String: Any] {
        ["id": id, "method": method, "params": ["threadId": "conversation", "turnId": turn, "itemId": "item", "command": "fixture command",
            "questions": [["id": "q", "question": "Choose", "options": [["label": "A", "description": ""]]]], "mode": "form", "requestedSchema": ["type": "object", "properties": [:]]]]
    }
    static func state(requests: [[String: Any]], items: [[String: Any]] = []) -> [String: Any] {
        ["id": "conversation", "title": "Fixture", "source": "appServer", "cwd": "/fixture/project", "requests": requests,
         "turns": [["turnId": "turn", "status": "inProgress", "turnStartedAtMs": 1000, "items": items]]]
    }
}

/// Shared isolated fixture: capabilities are obtained through real adapter frames.
/// No tests manufacture handles or connect to the user's desktop/configuration.
final class CodexDesktopIPCFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var state: [String: Any]
    let conversationID: String
    private var additionalStates: [String: (state: [String: Any], revision: Int64)] = [:]
    private var revision: Int64 = 7
    private var supportsInput: Bool
    private var continuation: AsyncStream<Data>.Continuation?
    private var messages: [[String: Any]] = []
    private var automaticSnapshots = true
    private var acknowledgeSubmissions = true
    private var acknowledgementOwner = "fixture-owner"
    private var steerResultTurn = "turn"
    private var host = "local"
    private var ownerDiscoveryReady = true
    init(state: [String: Any], supportsInput: Bool = true) { self.state = state; self.supportsInput = supportsInput; conversationID = state["id"] as? String ?? "conversation" }
    var submissions: [[String: Any]] { lock.withLock { messages.filter { ($0["method"] as? String)?.hasPrefix("thread-follower-") == true } } }
    var followingCount: Int { lock.withLock { messages.filter { $0["method"] as? String == "thread-stream-following-changed" }.count } }
    var initializeCount: Int { lock.withLock { messages.filter { $0["method"] as? String == "initialize" }.count } }
    var discoveryMessages: [[String: Any]] { lock.withLock { messages.filter { $0["method"] as? String == "thread-owner-discovery" } } }
    func setOwnerDiscoveryReady(_ ready: Bool) { lock.withLock { ownerDiscoveryReady = ready } }
    func emitFollowingStatusRequested() {
        lock.withLock { emitLocked(["type": "broadcast", "method": "thread-stream-following-status-requested",
            "sourceClientId": "fixture-owner", "version": 1,
            "params": ["conversationId": conversationID, "hostId": host]]) }
    }
    func setAutomaticSnapshots(_ enabled: Bool) { lock.withLock { automaticSnapshots = enabled } }
    func setSubmissionAcknowledgement(_ enabled: Bool, owner: String = "fixture-owner") { lock.withLock { acknowledgeSubmissions = enabled; acknowledgementOwner = owner } }
    func setSteerResultTurn(_ turn: String) { lock.withLock { steerResultTurn = turn } }
    func setState(_ state: [String: Any], revision: Int64, emit: Bool = true) {
        lock.withLock { self.state = state; self.revision = revision; if emit { emitStateLocked() } }
    }
    func setAdditionalState(_ state: [String: Any], conversationID: String, revision: Int64, emit: Bool = true) {
        lock.withLock {
            additionalStates[conversationID] = (state, revision)
            if emit { emitStateLocked(conversationID: conversationID) }
        }
    }
    func emitFrameHeader(length: UInt32) {
        lock.withLock { continuation?.yield(Data([UInt8(length & 255), UInt8((length >> 8) & 255), UInt8((length >> 16) & 255), UInt8((length >> 24) & 255)])) }
    }
    func emitRawBytes(_ bytes: Data) { lock.withLock { continuation?.yield(bytes) } }
    func emitRawPayload(_ payload: Data, chunkBytes: Int) {
        let size = UInt32(payload.count)
        let framed = Data([UInt8(truncatingIfNeeded: size), UInt8(truncatingIfNeeded: size >> 8),
            UInt8(truncatingIfNeeded: size >> 16), UInt8(truncatingIfNeeded: size >> 24)]) + payload
        lock.withLock {
            for offset in stride(from: 0, to: framed.count, by: chunkBytes) {
                continuation?.yield(Data(framed[offset..<min(framed.count, offset + chunkBytes)]))
            }
        }
    }
    func emitState(version: Int = 11) { lock.withLock { emitStateLocked(version: version) } }
    func patch(_ patches: [[String: Any]], baseRevision: Int64, revision: Int64) {
        lock.withLock { emitLocked(["type": "broadcast", "method": "thread-stream-state-changed", "sourceClientId": "fixture-owner", "version": 11,
            "params": ["conversationId": conversationID, "hostId": host, "change": ["type": "patches", "baseRevision": baseRevision, "revision": revision, "patches": patches]]]) }
    }
    func client(timeout: TimeInterval = 0.2, maximumFrameBytes: Int = 9_437_184,
                maximumRetainedStateBytes: Int = 33_554_432, frameDrainTimeoutSeconds: TimeInterval = 5) -> CodexDesktopIPCClient {
        .init(configuration: .init(socketURL: URL(fileURLWithPath: "/fixture/ipc.sock"), requestTimeoutSeconds: timeout,
            maximumFrameBytes: maximumFrameBytes, maximumRetainedStateBytes: maximumRetainedStateBytes,
            frameDrainTimeoutSeconds: frameDrainTimeoutSeconds), connector: { [self] _ in makeTransport() })
    }
    func connectedClient(timeout: TimeInterval = 0.2) async throws -> (CodexDesktopIPCClient, CodexDesktopIPCSnapshotRecorder, CodexDesktopConversationSnapshot) {
        let client = client(timeout: timeout), recorder = CodexDesktopIPCSnapshotRecorder()
        await client.start(snapshotHandler: { await recorder.record($0) }, stateHandler: { await recorder.recordState($0) })
        try await client.follow(conversationID: conversationID)
        return (client, recorder, try await recorder.wait(after: 0))
    }
    func waitForFollowingCount(_ count: Int) async throws {
        for _ in 0..<500 { if followingCount >= count { return }; try await Task.sleep(nanoseconds: 10_000_000) }
        throw CodexDesktopIPCError.unavailable
    }
    private func makeTransport() -> CodexDesktopIPCTransport {
        let stream = AsyncStream<Data>.makeStream()
        lock.withLock { continuation = stream.continuation }
        return .init(chunks: stream.stream, write: { [self] data in try receive(data) }, close: { stream.continuation.finish() })
    }
    private func receive(_ data: Data) throws {
        var decoder = CodexDesktopIPCFrameDecoder(maximumFrameBytes: 9_437_184)
        for payload in try decoder.append(data) {
            let message = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
            lock.withLock {
                messages.append(message)
                let method = message["method"] as? String
                if message["type"] as? String == "request", let id = message["requestId"] as? String {
                    if method == "initialize" { response(id: id, method: method!, owner: "fixture-client", result: ["clientId": "fixture-client"]) }
                    else if method == "thread-owner-discovery" {
                        guard ownerDiscoveryReady else { return }
                        if let candidate = message["targetClientId"] as? String, candidate != "fixture-owner" {
                            emitLocked(["type": "response", "requestId": id, "resultType": "error", "error": "no-client-found"])
                        } else { response(id: id, method: method!, owner: "fixture-owner", result: ["supportsUntrustedAppInput": supportsInput]) }
                    } else if acknowledgeSubmissions, let method {
                        response(id: id, method: method, owner: acknowledgementOwner,
                            result: method == "thread-follower-steer-turn" ? ["result": ["turnId": steerResultTurn]] : ["ok": true])
                    }
                } else if method == "thread-stream-following-changed", let params = message["params"] as? [String: Any], params["following"] as? Bool == true {
                    host = params["hostId"] as? String ?? "local"
                    if automaticSnapshots { emitStateLocked(conversationID: params["conversationId"] as? String) }
                }
            }
        }
    }
    private func response(id: String, method: String, owner: String, result: [String: Any]) {
        emitLocked(["type": "response", "requestId": id, "resultType": "success", "method": method, "handledByClientId": owner, "result": result])
    }
    private func emitStateLocked(version: Int = 11, conversationID requested: String? = nil) {
        let selected = requested ?? conversationID
        let content: (state: [String: Any], revision: Int64)? = selected == conversationID ? (state: state, revision: revision) : additionalStates[selected]
        guard let content else { return }
        emitLocked(["type": "broadcast", "method": "thread-stream-state-changed", "sourceClientId": "fixture-owner", "version": version,
            "params": ["conversationId": selected, "hostId": host, "change": ["type": "snapshot", "revision": content.revision, "conversationState": content.state]]])
    }
    private func emitLocked(_ message: [String: Any]) {
        let payload = try! JSONSerialization.data(withJSONObject: message, options: [.sortedKeys])
        continuation?.yield(try! CodexDesktopIPCFrameDecoder.frame(payload, maximumFrameBytes: 9_437_184))
    }
}

actor CodexDesktopIPCSnapshotRecorder {
    private var values: [CodexDesktopConversationSnapshot] = []
    private var states: [CodexDesktopIPCConnectionState] = []
    private var invalidations: [CodexDesktopIPCInvalidation] = []
    var latest: CodexDesktopConversationSnapshot? { values.last }
    var count: Int { values.count }
    var isConnected: Bool { states.last == .connected }
    func recordInvalidation(_ value: CodexDesktopIPCInvalidation) { invalidations.append(value) }
    func waitForInvalidation(after count: Int) async throws -> CodexDesktopIPCInvalidation {
        for _ in 0..<500 { if invalidations.count > count, let value = invalidations.last { return value }; try await Task.sleep(nanoseconds: 10_000_000) }
        throw CodexDesktopIPCError.unavailable
    }
    func record(_ value: CodexDesktopConversationSnapshot) { values.append(value) }
    func recordState(_ value: CodexDesktopIPCConnectionState) { states.append(value) }
    func wait(after count: Int) async throws -> CodexDesktopConversationSnapshot {
        for _ in 0..<500 { if values.count > count, let value = values.last { return value }; try await Task.sleep(nanoseconds: 10_000_000) }
        throw CodexDesktopIPCError.unavailable
    }
    func waitForConnection() async throws {
        for _ in 0..<500 { if states.contains(.connected) { return }; try await Task.sleep(nanoseconds: 10_000_000) }
        throw CodexDesktopIPCError.unavailable
    }
    func waitForDisconnect() async throws {
        for _ in 0..<500 { if states.contains(.disconnected) { return }; try await Task.sleep(nanoseconds: 10_000_000) }
        throw CodexDesktopIPCError.unavailable
    }
}

/// Controls only the old callback's reentrant boundary, never real desktop IPC.
private actor CodexDesktopResourceCallbackGate {
    private var entered = false
    private var exited = false
    private var continuation: CheckedContinuation<Void, Never>?
    func pause() async {
        entered = true
        await withCheckedContinuation { continuation = $0 }
        exited = true
    }
    func release() { continuation?.resume(); continuation = nil }
    func waitForEntry() async throws {
        for _ in 0..<500 { if entered { return }; try await Task.sleep(nanoseconds: 10_000_000) }
        throw CodexDesktopIPCError.unavailable
    }
    func waitForExit() async throws {
        for _ in 0..<500 { if exited { return }; try await Task.sleep(nanoseconds: 10_000_000) }
        throw CodexDesktopIPCError.unavailable
    }
}
