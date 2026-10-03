import AppKit
import Foundation
import XCTest
@testable import QuotaView
@testable import QuotaViewCore

final class CodexSubagentEvictionSmokeTests: XCTestCase {
    @MainActor
    func testRegistryEvictionWithdrawsChildAndSparseSharedStartRestoresSameRelation() async throws {
        let harness = try SubagentEvictionHarness()
        defer { try? FileManager.default.removeItem(at: harness.root) }
        try await harness.connect()
        try await harness.startParent()
        try await harness.send("thread/started", ["thread": harness.childMetadata])
        try await harness.send("thread/snapshot", ["thread": harness.childMetadata,
            "currentTurn": ["id": "child-turn", "status": "inProgress", "startedAtMs": Date().timeIntervalSince1970 * 1000]])
        XCTAssertEqual(harness.children.count, 1)
        XCTAssertEqual(harness.children.first?.model, "6.1 Sol · Ultra")
        // Parent remains selected; 127 background executions force the other
        // observed child out of Registry's 128 slots without evicting UI's child cache.
        for index in 0..<127 {
            let id = "memory-\(index)"
            try await harness.send("thread/started", ["thread": ["id": id, "source": ["subAgent": "memory_consolidation"]]])
            try await harness.send("turn/started", ["threadId": id, "turn": ["id": "memory-turn-\(index)"]])
        }
        XCTAssertTrue(harness.children.isEmpty)
        XCTAssertEqual(harness.withdrawn, [CodexActivityPrivacy.hashIdentifier("child")])
        XCTAssertEqual(harness.model.subagents[CodexActivityPrivacy.hashIdentifier("child")]?.title, "Own audit")
        // Parent relation alone and end-only activity cannot fabricate running.
        try await harness.send("thread/started", ["thread": ["id": "child", "source": "unknown"]])
        try await harness.send("thread/status/changed", ["threadId": "child", "turnId": "child-turn",
            "status": ["type": "active", "activeFlags": []]])
        XCTAssertTrue(harness.children.isEmpty)
        // A real start is sparse in the native protocol. Shared retains and
        // attaches verified parent scope; Store must never use user fallback.
        try await harness.send("turn/started", ["threadId": "child", "turn": ["id": "child-turn"]])
        XCTAssertEqual(harness.children.map(\.title), ["Own audit"])
        XCTAssertEqual(harness.children.first?.model, "6.1 Sol · Ultra")
        XCTAssertEqual(harness.model.tasks.count, 1)
        XCTAssertEqual(harness.store.multitask.entries.count, 1)
        XCTAssertEqual(harness.userEvents, 1)
        XCTAssertTrue(harness.model.display(english: false, remaining: nil, enabled: true, privacy: false).activeRequestIDs.isEmpty)
        await harness.shutdown()
        XCTAssertTrue(harness.children.isEmpty, "Stop revokes every execution without reporting fake completion")
    }

    @MainActor
    func testBoundedOriginEvictionRequiresVerifiedSharedScopeBeforeReadmission() async throws {
        let harness = try SubagentEvictionHarness()
        defer { try? FileManager.default.removeItem(at: harness.root) }
        try await harness.connect()
        try await harness.startParent()
        try await harness.send("thread/started", ["thread": harness.childMetadata])
        XCTAssertTrue(harness.children.isEmpty)
        // These metadata-only internal threads occupy no Registry slots. They
        // exercise the independent 1024-origin LRU instead of the 128 execution LRU.
        for index in 0..<1024 {
            let data = try JSONSerialization.data(withJSONObject: ["method": "thread/started",
                "params": ["thread": ["id": "internal-\(index)", "source": ["internal": "guardian"]]]])
            await harness.store.receiveScopedPublicMessage(data, connectionEpoch: 0)
        }
        XCTAssertEqual(harness.withdrawn, [CodexActivityPrivacy.hashIdentifier("child")])
        // Store no longer has child origin. This bare Shared event must carry the
        // connection's native proof and restore only the read-only child channel.
        try await harness.send("turn/started", ["threadId": "child", "turn": ["id": "new-turn"]])
        XCTAssertEqual(harness.children.map(\.title), ["Own audit"])
        XCTAssertEqual(harness.model.tasks.count, 1)
        XCTAssertEqual(harness.store.multitask.entries.count, 1)
        XCTAssertEqual(harness.userEvents, 1)
        await harness.shutdown()
    }

    func testChildRegistryNeedsPositiveEvidenceAfterSlotLoss() throws {
        var registry = CodexActivityTaskRegistry()
        let session = CodexActivityPrivacy.hashIdentifier("child")
        let continuation = CodexActivityEvent(event: .postToolUse, sessionHash: session,
            turnHash: "turn", sessionKind: .subagent, source: .appServer)
        XCTAssertNil(registry.admit(continuation, kind: .subagent, selectedSession: nil))
        XCTAssertNil(registry.executionIdentity(for: session))
        let start = CodexActivityEvent(event: .userPromptSubmit, sessionHash: session,
            turnHash: "turn", sessionKind: .subagent, source: .appServer)
        let admitted = try XCTUnwrap(registry.admit(start, kind: .subagent, selectedSession: nil))
        XCTAssertFalse(admitted.selectsTask)
        XCTAssertNotNil(registry.subagentIdentity(for: session))
        XCTAssertNil(registry.currentIdentity(for: session))
    }
}

@MainActor
private final class SubagentEvictionHarness {
    let root: URL
    let store: CodexActivityStore
    let shared: CodexSharedAppServerActivityClient
    let model = IslandLiveStore()
    var userEvents = 0
    var withdrawn: [String] = []
    var childMetadata: [String: Any] {
        ["id": "child", "name": "Own audit", "model": "6.1 Sol", "reasoningEffort": "Ultra",
         "source": ["subAgent": ["thread_spawn": ["parent_thread_id": "parent", "depth": 1]]],
         "threadSource": "subagent", "status": ["type": "active"]]
    }
    var children: [IslandSubagentPresentation] {
        let display = model.display(english: false, remaining: nil, enabled: true, privacy: false)
        return display.sessionMetadata[model.tasks.first?.id ?? 0]?.subagents ?? []
    }
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        shared = .init(configuration: .init(isEnabled: false,
            socketURL: root.appendingPathComponent("unused.sock"), executablePath: nil))
        store = CodexActivityStore(titleClient: .init(executablePath: nil), sessionDirectory: root,
            sessionKindResolver: { $0.sessionKind ?? .unknown })
        store.setMultitaskEnabled(true)
        store.admittedActivityDidReceive = { [weak self] in self?.userEvents += 1; self?.model.receiveLegacy($0) }
        store.activitySessionKindDidResolve = { [weak self] in self?.model.setSessionKind($1, for: $0) }
        store.activityExecutionKindDidResolve = { [weak self] in self?.model.receiveExecutionSessionKind($1, session: $0) }
        store.subagentIdentityDidReceive = { [weak self] in self?.model.receiveSubagentIdentity($0) }
        store.subagentActivityDidReceive = { [weak self] in self?.model.receiveSubagentActivity($0) }
        store.subagentPublicMessageDidReceive = { [weak self] in self?.model.receiveSubagentPublicMessage($0) }
        store.subagentObservationDidWithdraw = { [weak self] session in
            self?.withdrawn.append(session); self?.model.withdrawSubagentObservation(for: session)
        }
    }
    func connect() async throws {
        let store = self.store
        await shared.start(handler: { event in
            await store.receiveClassified(.init(source: .liveSocket, activity: event))
        }, connectionStateHandler: { _ in })
        await shared.setScopedPublicMessageHandler { data, epoch in
            await store.receiveScopedPublicMessage(data, connectionEpoch: epoch)
        }
    }
    func startParent() async throws {
        try await send("thread/started", ["thread": ["id": "parent", "source": "vscode", "name": "Parent"]])
        try await send("turn/started", ["threadId": "parent", "turn": ["id": "parent-turn"]])
    }
    func send(_ method: String, _ params: [String: Any]) async throws {
        try await shared.handleJSONMessage(JSONSerialization.data(withJSONObject: ["method": method, "params": params]))
    }
    func shutdown() async { await shared.stop(); await store.stop() }
}
