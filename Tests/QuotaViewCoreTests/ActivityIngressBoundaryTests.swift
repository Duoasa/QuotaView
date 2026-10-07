import Foundation
import XCTest
@testable import QuotaView
@testable import QuotaViewCore

@MainActor
final class ActivityIngressBoundaryTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_790_888_000)
    private func hash(_ value: String) -> String { CodexActivityPrivacy.hashIdentifier(value) }
    private func json(_ method: String, _ params: [String: Any], id: Any? = nil, emittedAt: Date? = nil) -> Data {
        var value: [String: Any] = ["method": method, "params": params]
        if let id { value["id"] = id }
        if let emittedAt { value["emittedAtMs"] = emittedAt.timeIntervalSince1970 * 1_000 }
        return try! JSONSerialization.data(withJSONObject: value)
    }
    private func disabledShared() -> CodexSharedAppServerActivityClient {
        .init(configuration: .init(isEnabled: false, socketURL: URL(fileURLWithPath: "/tmp/unused-ingress.sock"), executablePath: nil))
    }
    private func makeStore(shared: CodexSharedAppServerActivityClient? = nil, root: URL? = nil,
                           localEnabled: Bool = false) -> CodexActivityStore {
        let directory = root ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return CodexActivityStore(titleClient: CodexAppServerClient(executablePath: nil),
            sharedActivityClient: shared ?? disabledShared(),
            localRolloutActivityClient: .init(configuration: .init(isEnabled: localEnabled, codexHomeURL: directory,
                pollIntervalSeconds: 0.1, candidateRefreshSeconds: 0.1)),
            sessionDirectory: directory, sessionKindResolver: { event in event.sessionKind ?? .user })
    }
    private func wire(_ store: CodexActivityStore, _ island: IslandLiveStore) {
        store.admittedActivityDidReceive = { island.receiveLegacy($0) }
        store.publicMessageDidReceive = { island.receive($0) }
        store.localPublicContentDidReceive = { island.receiveLocalContent($0) }
        island.nativeRequestSettlementDidReceive = { store.receiveRequestSettlement($0) }
    }
    private func bind(_ client: CodexSharedAppServerActivityClient, _ store: CodexActivityStore) async {
        await client.setScopedPublicMessageHandler { data, epoch in
            await store.receiveScopedPublicMessage(data, connectionEpoch: epoch)
        }
    }
    private func localStart(_ store: CodexActivityStore, session: String = "task", turn: String, at date: Date) {
        store.receive(.init(event: .userPromptSubmit, sessionHash: hash(session), turnHash: hash(turn),
            sessionKind: .user, source: .localRollout, occurredAt: date))
    }
    private func question(_ call: String = "question", session: String = "task", turn: String,
                          asynchronous: Bool = false, at date: Date) throws -> CodexLocalPublicContent {
        let values: [[String: Any]] = asynchronous ? [["title": "选择范围", "options": ["当前模块", "整个应用"]]]
            : [["id": "scope", "question": "选择范围", "options": [["label": "当前模块"], ["label": "整个应用"]]]]
        let args = String(decoding: try JSONSerialization.data(withJSONObject: ["questions": values]), as: UTF8.self)
        let format = ISO8601DateFormatter(); format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let data = try JSONSerialization.data(withJSONObject: ["type": "response_item", "timestamp": format.string(from: date),
            "payload": ["type": "function_call", "name": asynchronous ? "functions.request_user_input_async" : "functions.request_user_input",
                "call_id": call, "arguments": args]])
        return try XCTUnwrap(CodexLocalPublicContent.decode(data, sessionHash: hash(session), activeTurnHash: hash(turn)))
    }
    private func approval(_ thread: String, turn: String, call: String, rpc: Any) -> Data {
        json("item/commandExecution/requestApproval", ["threadId": thread, "turnId": turn, "itemId": call,
            "command": "swift build", "availableDecisions": ["accept", "decline"]], id: rpc)
    }
    private func snapshot(_ thread: String = "task", turn: String?, flags: [String] = [], at date: Date) -> Data {
        var params: [String: Any] = ["thread": ["id": thread, "source": "cli", "status": ["type": "active", "activeFlags": flags]]]
        if let turn { params["currentTurn"] = ["id": turn, "status": "inProgress", "startedAtMs": date.timeIntervalSince1970 * 1_000] }
        return json("thread/snapshot", params)
    }

    func testOldNativeStartWithOrWithoutTimestampCannotReplaceDurableCurrentTurn() async throws {
        let client = disabledShared(), island = IslandLiveStore()
        let store = makeStore(shared: client); wire(store, island); await bind(client, store)
        localStart(store, turn: "current", at: base)
        store.receiveLocalPublicContent(try question(turn: "current", at: base.addingTimeInterval(1)))
        try await client.handleJSONMessage(json("thread/started", ["thread": ["id": "task", "source": "cli", "status": ["type": "idle"]]]))
        for timestamp in [nil, base.addingTimeInterval(-10)] {
            try await client.handleJSONMessage(json("turn/started", ["threadId": "task", "turn": ["id": "unseen-old"]], emittedAt: timestamp))
            XCTAssertEqual(store.snapshot?.taskIdentity?.turnHash, hash("current"))
            XCTAssertEqual(island.tasks.first?.turnKey, hash("current"))
            XCTAssertEqual(island.tasks.first?.requests.count, 1)
        }
        localStart(store, turn: "current", at: base.addingTimeInterval(2))
        XCTAssertEqual(island.tasks.first?.requests.count, 1, "A rejected native turn cannot mark the real turn as prior")
        store.receive(.init(event: .stop, sessionHash: hash("task"), turnHash: hash("current"),
            sessionKind: .user, source: .localRollout, turnCompletionStatus: .completed, occurredAt: base.addingTimeInterval(3)))
        try await client.handleJSONMessage(json("turn/started", ["threadId": "task", "turn": ["id": "unseen-old"]]))
        XCTAssertEqual(island.tasks.first?.status, .completed, "A lower-authority late start cannot revive a completed durable turn")
        await store.stop()
    }

    func testExplicitCurrentSnapshotReleasesOnlyMatchingBufferedNativeRequest() async throws {
        let store = makeStore(), island = IslandLiveStore(); wire(store, island)
        localStart(store, turn: "old", at: base)
        await store.receiveScopedPublicMessage(approval("task", turn: "next", call: "next-call", rpc: 7), connectionEpoch: 1, at: base.addingTimeInterval(2))
        XCTAssertTrue(island.tasks[0].requests.isEmpty)
        await store.receiveScopedPublicMessage(snapshot(turn: nil, flags: ["waitingOnApproval"], at: base), connectionEpoch: 1, at: base.addingTimeInterval(3))
        XCTAssertEqual(island.tasks[0].turnKey, hash("old"), "A bare active snapshot cannot establish the next turn")
        await store.receiveScopedPublicMessage(snapshot(turn: "next", flags: ["waitingOnApproval"], at: base.addingTimeInterval(1)), connectionEpoch: 1, at: base.addingTimeInterval(4))
        XCTAssertEqual(store.snapshot?.taskIdentity?.turnHash, hash("next"))
        XCTAssertEqual(island.tasks[0].turnKey, hash("next"))
        XCTAssertEqual(island.tasks[0].requests.count, 1)
        XCTAssertEqual(island.tasks[0].requests[0].value.protocolRequest?.kind, .command)
        XCTAssertFalse(island.tasks[0].requests[0].value.canRespond)
        await store.stop()
    }

    func testNoThreadResolutionIsScopedToObservedTypedRPC() async throws {
        let client = disabledShared(), store = makeStore(shared: client), island = IslandLiveStore()
        wire(store, island); await bind(client, store)
        for thread in ["first", "second"] {
            try await client.handleJSONMessage(json("thread/started", ["thread": ["id": thread, "source": "cli"]]))
        }
        try await client.handleJSONMessage(approval("first", turn: "turn", call: "a", rpc: 7))
        try await client.handleJSONMessage(approval("second", turn: "turn", call: "b", rpc: "7"))
        try await client.handleJSONMessage(json("serverRequest/resolved", ["requestId": 7]))
        XCTAssertEqual(island.tasks.first(where: { $0.key == hash("first") })?.requests.count, 0)
        XCTAssertEqual(island.tasks.first(where: { $0.key == hash("second") })?.requests.count, 1)
        try await client.handleJSONMessage(json("serverRequest/resolved", ["requestId": 999]))
        XCTAssertEqual(island.tasks.first(where: { $0.key == hash("second") })?.requests.count, 1)
        await store.stop()
    }

    func testAmbiguousObservedRPCNeverBroadcastsResolution() async throws {
        let client = disabledShared(), store = makeStore(shared: client), island = IslandLiveStore()
        wire(store, island); await bind(client, store)
        for thread in ["first", "second"] {
            try await client.handleJSONMessage(json("thread/started", ["thread": ["id": thread, "source": "cli"]]))
            try await client.handleJSONMessage(approval(thread, turn: "turn", call: thread, rpc: 7))
        }
        try await client.handleJSONMessage(json("serverRequest/resolved", ["requestId": 7]))
        XCTAssertEqual(island.tasks.map { $0.requests.count }, [1, 1])
        await store.stop()
    }

    func testRPCIDReuseAfterConnectionChangeRejectsOldEpochResolution() async throws {
        let store = makeStore(), island = IslandLiveStore(); wire(store, island)
        await store.receiveScopedPublicMessage(approval("task", turn: "turn", call: "old-call", rpc: 7), connectionEpoch: 10, at: base)
        await store.receiveScopedPublicMessage(approval("task", turn: "turn", call: "new-call", rpc: 7), connectionEpoch: 11, at: base.addingTimeInterval(1))
        await store.receiveScopedPublicMessage(json("serverRequest/resolved", ["threadId": "task", "turnId": "turn", "requestId": 7]), connectionEpoch: 10, at: base.addingTimeInterval(2))
        XCTAssertNotNil(island.tasks[0].requests.first { $0.value.protocolRequest?.params["itemId"].text == "new-call" })
        await store.receiveScopedPublicMessage(json("serverRequest/resolved", ["threadId": "task", "turnId": "turn", "requestId": 7]), connectionEpoch: 11, at: base.addingTimeInterval(3))
        XCTAssertNil(island.tasks[0].requests.first { $0.value.protocolRequest?.params["itemId"].text == "new-call" })
        await store.stop()
    }

    func testKnownNativeWaitContinuationResumesCoreWithoutResolvingAsyncQuestion() async throws {
        let store = makeStore(), island = IslandLiveStore(); wire(store, island)
        localStart(store, turn: "turn", at: base)
        store.receiveLocalPublicContent(try question(turn: "turn", asynchronous: true, at: base.addingTimeInterval(1)))
        let flags: (Bool) -> Data = { wait in self.json("thread/status/changed", ["threadId": "task",
            "status": ["type": "active", "activeFlags": wait ? ["waitingOnUserInput"] : []]]) }
        await store.receiveScopedPublicMessage(flags(false), connectionEpoch: 1, at: base.addingTimeInterval(2))
        XCTAssertEqual(island.tasks[0].requests.count, 1)
        await store.receiveScopedPublicMessage(flags(true), connectionEpoch: 1, at: base.addingTimeInterval(3))
        XCTAssertEqual(store.snapshot?.state, .awaitingConfirmation)
        await store.receiveScopedPublicMessage(flags(false), connectionEpoch: 1, at: base.addingTimeInterval(4))
        XCTAssertNotEqual(store.snapshot?.state, .awaitingConfirmation)
        XCTAssertNotEqual(island.tasks[0].status, .waiting)
        XCTAssertEqual(island.tasks[0].requests.count, 1, "Thread continuation is not an answer to an optional async question")
        await store.stop()
    }

    func testExactRPCSettlementResumesCoreAfterLastBlockerAndPreservesAsyncQuestion() async throws {
        let client = disabledShared(), store = makeStore(shared: client), island = IslandLiveStore()
        wire(store, island); await bind(client, store)
        localStart(store, turn: "turn", at: base)
        store.receiveLocalPublicContent(try question("optional-question", turn: "turn", asynchronous: true,
            at: base.addingTimeInterval(1)))
        try await client.handleJSONMessage(json("thread/started", ["thread": ["id": "task", "source": "cli"]]))
        try await client.handleJSONMessage(approval("task", turn: "turn", call: "a", rpc: 7))
        try await client.handleJSONMessage(approval("task", turn: "turn", call: "b", rpc: 8))
        try await client.handleJSONMessage(json("thread/status/changed", ["threadId": "task",
            "status": ["type": "active", "activeFlags": ["waitingOnApproval"]]]))
        XCTAssertEqual(store.snapshot?.state, .awaitingConfirmation)
        try await client.handleJSONMessage(json("serverRequest/resolved", ["requestId": 7]))
        XCTAssertEqual(store.snapshot?.state, .awaitingConfirmation, "The other blocker still needs confirmation")
        XCTAssertEqual(island.tasks[0].status, .waiting)
        try await client.handleJSONMessage(json("serverRequest/resolved", ["requestId": 8]))
        XCTAssertNotEqual(store.snapshot?.state, .awaitingConfirmation, "Exact settlement must also recover the Core snapshot")
        XCTAssertNotEqual(island.tasks[0].status, .waiting)
        XCTAssertFalse(store.isConfirmationReminderActive)
        XCTAssertEqual(island.tasks[0].requests.count, 1)
        XCTAssertEqual(island.tasks[0].requests[0].callHash, hash("optional-question"))
        XCTAssertEqual(island.tasks[0].requests[0].mode, .asynchronous)
        await store.stop()
    }

    func testUnknownRPCResolutionCannotReleaseCoreWait() async throws {
        let client = disabledShared(), store = makeStore(shared: client), island = IslandLiveStore()
        wire(store, island); await bind(client, store)
        try await client.handleJSONMessage(json("thread/started", ["thread": ["id": "task", "source": "cli"]]))
        try await client.handleJSONMessage(approval("task", turn: "turn", call: "a", rpc: 7))
        XCTAssertEqual(store.snapshot?.state, .awaitingConfirmation)
        try await client.handleJSONMessage(json("serverRequest/resolved", ["threadId": "task", "turnId": "turn", "requestId": 999]))
        XCTAssertEqual(store.snapshot?.state, .awaitingConfirmation)
        XCTAssertEqual(island.tasks[0].requests.count, 1)
        // Exercise the admitted raw boundary too: an unknown resolution cannot
        // manufacture the exact-match proof produced by RequestLifecycle.
        await store.receiveScopedPublicMessage(json("serverRequest/resolved", ["threadId": "task", "turnId": "turn", "requestId": 999]),
            connectionEpoch: 0)
        XCTAssertEqual(store.snapshot?.state, .awaitingConfirmation)
        XCTAssertEqual(island.tasks[0].requests.count, 1)
        try await client.handleJSONMessage(json("serverRequest/resolved", ["requestId": 7]))
        XCTAssertNotEqual(store.snapshot?.state, .awaitingConfirmation)
        XCTAssertTrue(island.tasks[0].requests.isEmpty)
        await store.stop()
    }

    func testOldEpochRPCSettlementCannotReleaseReusedCurrentRPCWait() async throws {
        let store = makeStore(), island = IslandLiveStore(); wire(store, island)
        let resolved = json("serverRequest/resolved", ["threadId": "task", "turnId": "turn", "requestId": 7])
        await store.receiveScopedPublicMessage(approval("task", turn: "turn", call: "old", rpc: 7),
            connectionEpoch: 10, at: base)
        await store.receiveScopedPublicMessage(resolved, connectionEpoch: 10, at: base.addingTimeInterval(1))
        XCTAssertNotEqual(store.snapshot?.state, .awaitingConfirmation)
        await store.receiveScopedPublicMessage(approval("task", turn: "turn", call: "current", rpc: 7),
            connectionEpoch: 11)
        XCTAssertEqual(store.snapshot?.state, .awaitingConfirmation)
        await store.receiveScopedPublicMessage(resolved, connectionEpoch: 10)
        XCTAssertEqual(store.snapshot?.state, .awaitingConfirmation)
        XCTAssertEqual(island.tasks[0].requests.count, 1)
        // The Core gate rejects delayed typed proof even if an old Island
        // callback was retained by a caller across a connection replacement.
        store.receiveRequestSettlement(.init(sessionHash: hash("task"), turnHash: hash("turn"),
            connectionEpoch: 10, stillWaiting: false))
        XCTAssertEqual(store.snapshot?.state, .awaitingConfirmation)
        await store.receiveScopedPublicMessage(resolved, connectionEpoch: 11)
        XCTAssertNotEqual(store.snapshot?.state, .awaitingConfirmation)
        XCTAssertNotEqual(island.tasks[0].status, .waiting)
        XCTAssertFalse(store.isConfirmationReminderActive)
        XCTAssertTrue(island.tasks[0].requests.isEmpty)
        await store.stop()
    }

    func testPausedBootstrapUsesBoundedCurrentTurnEndpointAndPreservesRealQuestion() async throws {
        try await verifyPausedBootstrap(unsupportedCurrentTurn: false)
    }
    func testUnsupportedCurrentTurnEndpointKeepsUnconfirmedHistoryHidden() async throws {
        try await verifyPausedBootstrap(unsupportedCurrentTurn: true)
    }

    private func verifyPausedBootstrap(unsupportedCurrentTurn: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("qv-ingress-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        let socket = URL(fileURLWithPath: "/tmp/qvi-" + String(UUID().uuidString.prefix(8)) + ".sock")
        let server = Process()
        defer {
            if server.isRunning { server.terminate() }
            try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: socket)
        }
        let format = ISO8601DateFormatter(); format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let old = Date().addingTimeInterval(-120)
        var lines: [[String: Any]] = [
            ["type": "session_meta", "payload": ["id": "task", "source": "cli"]],
            ["type": "event_msg", "timestamp": format.string(from: old), "payload": ["type": "task_started", "turn_id": "paused-turn"]]
        ]
        let args = String(decoding: try JSONSerialization.data(withJSONObject: ["questions": [["id": "scope", "question": "选择范围", "options": [["label": "当前模块"]]]]]), as: UTF8.self)
        lines.append(["type": "response_item", "timestamp": format.string(from: old.addingTimeInterval(1)),
            "payload": ["type": "function_call", "call_id": "paused-question", "name": "functions.request_user_input", "arguments": args]])
        var rollout = Data()
        for line in lines { rollout.append(try JSONSerialization.data(withJSONObject: line)); rollout.append(10) }
        try rollout.write(to: root.appendingPathComponent("sessions/task.jsonl"))
        let script = root.appendingPathComponent("server.py"), log = root.appendingPathComponent("requests.jsonl")
        try Self.serverScript.write(to: script, atomically: true, encoding: .utf8)
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = [script.path, socket.path, log.path, unsupportedCurrentTurn ? "unsupported" : "supported", String(old.timeIntervalSince1970)]
        server.standardInput = FileHandle.nullDevice; server.standardOutput = FileHandle.nullDevice; server.standardError = FileHandle.nullDevice
        try server.run()
        try await waitUntil { FileManager.default.fileExists(atPath: socket.path) }
        let shared = CodexSharedAppServerActivityClient(configuration: .init(isEnabled: true, socketURL: socket,
            executablePath: nil, startupTimeoutSeconds: 2, requestTimeoutSeconds: 1))
        let store = makeStore(shared: shared, root: root, localEnabled: true), island = IslandLiveStore(); wire(store, island)
        var forwarded: [Data] = []
        store.publicMessageDidReceive = { data in forwarded.append(data); island.receive(data) }
        store.startNativeActivityNotifications()
        if unsupportedCurrentTurn {
            try await waitUntil { store.localHealth == .ready && store.nativeConnectionState == .connected }
            try await Task.sleep(nanoseconds: 150_000_000)
            XCTAssertTrue(island.tasks.isEmpty, "A bare active snapshot cannot promote old disk history")
        } else {
            try await waitUntil { island.tasks.first?.requests.first?.value.protocolRequest?.questions.first?.title == "选择范围" }
            XCTAssertEqual(island.tasks[0].turnKey, hash("paused-turn"))
            XCTAssertEqual(store.snapshot?.state, .awaitingConfirmation)
            XCTAssertFalse(island.tasks[0].requests[0].value.canRespond)
            XCTAssertTrue(forwarded.allSatisfy { !String(decoding: $0, as: UTF8.self).contains("PRIVATE-FIXTURE") })
        }
        let requests = try String(contentsOf: log, encoding: .utf8).split(separator: "\n").compactMap {
            try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
        }
        let turnRequest = try XCTUnwrap(requests.first { $0["method"] as? String == "thread/turns/list" })
        let params = try XCTUnwrap(turnRequest["params"] as? [String: Any])
        XCTAssertEqual(params["limit"] as? Int, 1); XCTAssertEqual(params["itemsView"] as? String, "notLoaded")
        XCTAssertFalse(requests.contains { ($0["params"] as? [String: Any])?["includeTurns"] as? Bool == true })
        await store.stop()
    }
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertTrue(condition(), "Timed out waiting for isolated ingress fixture")
    }
    private static let serverScript = #"""
import socket, sys, json, struct, hashlib, base64
path, log, mode, started = sys.argv[1:]
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(path); s.listen(1); s.settimeout(10)
c, _ = s.accept(); c.settimeout(10)
header = b''
while b'\r\n\r\n' not in header: header += c.recv(4096)
key = next(line.split(b':', 1)[1].strip() for line in header.split(b'\r\n') if line.lower().startswith(b'sec-websocket-key:'))
accept = base64.b64encode(hashlib.sha1(key + b'258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest())
c.sendall(b'HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ' + accept + b'\r\n\r\n')
def exact(n):
    data = b''
    while len(data) < n:
        part = c.recv(n-len(data))
        if not part: raise EOFError()
        data += part
    return data
def read():
    a, b = exact(2); n = b & 127
    if n == 126: n = struct.unpack('!H', exact(2))[0]
    elif n == 127: n = struct.unpack('!Q', exact(8))[0]
    mask = exact(4) if b & 128 else None
    data = exact(n)
    if mask: data = bytes(v ^ mask[i % 4] for i, v in enumerate(data))
    return json.loads(data)
def send(value):
    data = json.dumps(value).encode(); n = len(data)
    prefix = bytes([129, n]) if n < 126 else bytes([129, 126]) + struct.pack('!H', n)
    c.sendall(prefix + data)
try:
    while True:
        request = read()
        with open(log, 'a') as f: f.write(json.dumps(request) + '\n')
        if 'id' not in request: continue
        method = request.get('method')
        if method == 'initialize': result = {}
        elif method == 'thread/loaded/list': result = {'data': ['task'], 'nextCursor': None}
        elif method in ['thread/resume', 'thread/read']:
            result = {'thread': {'id': 'task', 'source': 'cli', 'name': 'Paused task',
                'status': {'type': 'active', 'activeFlags': ['waitingOnUserInput']},
                'preview': 'PRIVATE-FIXTURE', 'turns': [{'items': [{'type': 'reasoning', 'text': 'PRIVATE-FIXTURE'}]}]}}
        elif method == 'thread/turns/list':
            if mode == 'unsupported':
                send({'id': request['id'], 'error': {'code': -32601, 'message': 'Unsupported endpoint'}}); continue
            result = {'data': [{'id': 'paused-turn', 'status': 'inProgress', 'startedAt': float(started),
                'itemsView': 'notLoaded', 'items': []}], 'nextCursor': None}
        else: result = {}
        send({'id': request['id'], 'result': result})
except (EOFError, OSError): pass
finally: c.close(); s.close()
"""#
}
