import AppKit
import XCTest
@testable import QuotaView
@testable import QuotaViewCore

final class IslandSubagentProgressSmokeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 200)
    private func content(_ session: String, turn: String = "turn", _ payload: [String: Any]) throws -> CodexLocalPublicContent {
        .init(sessionHash: session, turnHash: turn, data: try JSONSerialization.data(withJSONObject: payload), occurredAt: now)
    }
    @MainActor private func children(_ model: IslandLiveStore, privacy: Bool = false) -> [IslandSubagentPresentation] {
        let display = model.display(english: false, remaining: nil, enabled: true, privacy: privacy, at: now)
        return display.sessionMetadata[model.tasks.first?.id ?? 0]?.subagents ?? []
    }
    @MainActor private func startParent(_ model: IslandLiveStore) {
        model.receiveLegacy(.init(event: .userPromptSubmit, sessionHash: CodexActivityPrivacy.hashIdentifier("parent"),
                                 turnHash: "parent-turn", sessionKind: .user, occurredAt: now))
    }
    @MainActor private func startChild(_ model: IslandLiveStore, id: String, title: String) throws -> String {
        let relation = try XCTUnwrap(CodexActivitySubagentIdentity(threadID: id, parentThreadID: "parent", nickname: "Random nickname", title: title))
        model.receiveSubagentIdentity(relation)
        model.receiveSubagentActivity(.init(event: .userPromptSubmit, sessionHash: relation.sessionHash,
            turnHash: "turn", sessionKind: .subagent, source: .localRollout, occurredAt: now))
        return relation.sessionHash
    }

    @MainActor func testThreeChildrenUseParentCardAndOwnMetadataWithoutAddingConversations() throws {
        let model = IslandLiveStore(); startParent(model)
        for (index, title) in ["Memory identity review", "Approval copy audit", "Memory v2 diagnosis"].enumerated() {
            let session = try startChild(model, id: "child-\(index)", title: title)
            try model.receiveLocalContent(content(session, ["type": "metadata", "model": "6.1 Sol", "effort": "Ultra"]))
        }
        XCTAssertEqual(model.tasks.count, 1)
        XCTAssertEqual(children(model).map(\.title).sorted(), ["Memory identity review", "Approval copy audit", "Memory v2 diagnosis"].sorted())
        XCTAssertEqual(Set(children(model).map(\.model)), ["6.1 Sol · Ultra"])
        XCTAssertTrue(children(model).allSatisfy { $0.avatar != nil }, "Native thread identity supplies each Codex avatar")
        let display = model.display(english: false, remaining: nil, enabled: true, privacy: false, at: now)
        XCTAssertTrue(display.state.tasks.first!.renderState.operation.contains("Memory identity review"))
        XCTAssertTrue(display.activeRequestIDs.isEmpty)
        XCTAssertTrue(children(model, privacy: true).isEmpty)
    }

    @MainActor func testParentRelationAloneNeverFabricatesRunningOrInheritsParentModel() throws {
        let model = IslandLiveStore(); startParent(model)
        let relation = try XCTUnwrap(CodexActivitySubagentIdentity(threadID: "child", parentThreadID: "parent", title: "Audit"))
        model.receiveSubagentIdentity(relation)
        XCTAssertTrue(children(model).isEmpty)
        model.receiveSubagentActivity(.init(event: .postToolUse, sessionHash: relation.sessionHash, turnHash: "turn", occurredAt: now))
        XCTAssertTrue(children(model).isEmpty)
        model.receiveSubagentActivity(.init(event: .preToolUse, sessionHash: relation.sessionHash, turnHash: "turn", source: .hook, occurredAt: now))
        XCTAssertEqual(children(model).count, 1)
        XCTAssertEqual(children(model).first?.model, "")
        let conflict = try XCTUnwrap(CodexActivitySubagentIdentity(threadID: "child", parentThreadID: "other"))
        model.receiveSubagentIdentity(conflict)
        XCTAssertEqual(children(model).count, 1)
    }

    @MainActor func testChildCompletionOldTurnAndSourceLossRemainScoped() throws {
        let model = IslandLiveStore(); startParent(model)
        let key = try startChild(model, id: "child", title: "Audit")
        model.receiveSubagentActivity(.init(event: .stop, sessionHash: key, turnHash: "old", source: .localRollout, occurredAt: now))
        XCTAssertEqual(children(model).count, 1)
        model.receiveSubagentSourceUnavailable(.hook)
        XCTAssertNotEqual(children(model).first?.status, "状态待更新")
        model.receiveSubagentSourceUnavailable(.localRollout)
        XCTAssertEqual(children(model).first?.status, "状态待更新")
        XCTAssertFalse(model.display(english: false, remaining: nil, enabled: true, privacy: false, at: now)
            .state.tasks.first!.renderState.operation.contains("正在工作"))
        model.receiveSubagentActivity(.init(event: .stop, sessionHash: key, turnHash: "turn", source: .localRollout,
            turnCompletionStatus: .completed, occurredAt: now))
        XCTAssertTrue(children(model).isEmpty)
        model.receiveSubagentActivity(.init(event: .preToolUse, sessionHash: key, turnHash: "turn", occurredAt: now))
        XCTAssertTrue(children(model).isEmpty)
        model.reset(); XCTAssertTrue(model.subagents.isEmpty)
    }

    @MainActor func testMemoryExecutionWithdrawsChildAndRevocationCannotReplayItsOldTurn() throws {
        let model = IslandLiveStore(); startParent(model)
        let key = try startChild(model, id: "child", title: "Audit")
        model.receiveExecutionSessionKind(.memoryConsolidation, session: key)
        XCTAssertTrue(children(model).isEmpty)
        model.receiveExecutionSessionKind(.user, session: key)
        XCTAssertTrue(children(model).isEmpty)
        model.receiveSubagentActivity(.init(event: .preToolUse, sessionHash: key, turnHash: "turn", occurredAt: now))
        XCTAssertTrue(children(model).isEmpty)
        model.receiveSubagentActivity(.init(event: .userPromptSubmit, sessionHash: key, turnHash: "new", occurredAt: now))
        XCTAssertEqual(children(model).count, 1)
        model.setSessionKind(.internalTask, for: key)
        XCTAssertTrue(children(model).isEmpty)
    }

    @MainActor func testPublicProgressSurvivesToolCompletionAndNewTurnClearsIt() throws {
        let model = IslandLiveStore(); startParent(model)
        let key = CodexActivityPrivacy.hashIdentifier("parent")
        try model.receiveLocalContent(content(key, turn: "parent-turn", ["type": "message", "id": "message", "text": "正在核对来源与父子关系。\n随后验证状态同步。", "channel": "commentary"]))
        model.receiveLegacy(.init(event: .preToolUse, sessionHash: key, turnHash: "parent-turn", occurredAt: now))
        try model.receiveLocalContent(content(key, turn: "parent-turn", ["type": "tool", "id": "tool", "name": "exec", "text": "read sources"]))
        try model.receiveLocalContent(content(key, turn: "parent-turn", ["type": "output", "id": "tool", "text": "done"]))
        let display = model.display(english: false, remaining: nil, enabled: true, privacy: false, at: now)
        XCTAssertEqual(display.state.tasks.first?.renderState.operation, "正在核对来源与父子关系。 随后验证状态同步。")
        XCTAssertEqual(model.display(english: false, remaining: nil, enabled: true, privacy: true).state.tasks.first?.renderState.operation, "")
        model.receiveLegacy(.init(event: .userPromptSubmit, sessionHash: key, turnHash: "next", occurredAt: now))
        XCTAssertEqual(model.tasks.first?.publicProgress, "")
    }

    @MainActor func testPrivateAgentMessagesCannotReplacePublicProgress() throws {
        let model = IslandLiveStore(); startParent(model)
        let key = try startChild(model, id: "child", title: "Audit")
        try model.receiveLocalContent(content(key, ["type": "message", "text": "公开进展"]))
        let wireTurn = "native-turn"
        model.receiveSubagentActivity(.init(event: .userPromptSubmit, sessionHash: key,
            turnHash: CodexActivityPrivacy.hashIdentifier(wireTurn), occurredAt: now))
        let privateMessage: [String: Any] = ["method": "item/started", "params": ["threadId": "child", "turnId": wireTurn, "item": ["type": "agent_message", "text": "private inter-agent secret"]]]
        // The public bridge is already gated by Store's item whitelist. A raw
        // rollout agent_message also has no public decoder and cannot cross it.
        let raw = try JSONSerialization.data(withJSONObject: ["type": "response_item", "payload": ["type": "agent_message", "content": [["type": "input_text", "text": "private inter-agent secret"]]]])
        XCTAssertNil(CodexLocalPublicContent.decode(raw, sessionHash: key, activeTurnHash: "turn"))
        model.receiveSubagentPublicMessage(try JSONSerialization.data(withJSONObject: privateMessage))
        XCTAssertFalse(children(model).first?.detail.contains("private inter-agent secret") == true)
    }

    @MainActor func testNativeOnlyChildSnapshotRetainsOwnTitleModelAndExactTurn() throws {
        let model = IslandLiveStore(); startParent(model)
        let relation = try XCTUnwrap(CodexActivitySubagentIdentity(threadID: "native-child", parentThreadID: "parent", nickname: "Random name"))
        model.receiveSubagentIdentity(relation)
        model.receiveSubagentActivity(.init(event: .userPromptSubmit, sessionHash: relation.sessionHash,
            turnHash: CodexActivityPrivacy.hashIdentifier("native-turn"), source: .appServer, occurredAt: now))
        let params: [String: Any] = ["thread": ["id": "native-child", "name": "Actual audit", "model": "6 Luna", "reasoningEffort": "Medium"],
                                   "currentTurn": ["id": "native-turn", "status": "inProgress"]]
        model.receiveSubagentPublicMessage(try JSONSerialization.data(withJSONObject: ["method": "thread/snapshot", "params": params]))
        XCTAssertEqual(children(model).first?.title, "Actual audit")
        XCTAssertEqual(children(model).first?.model, "6 Luna · Medium")
        func deliver(_ method: String, _ extra: [String: Any]) throws {
            var fields = extra; fields["threadId"] = "native-child"; fields["turnId"] = "native-turn"
            model.receiveSubagentPublicMessage(try JSONSerialization.data(withJSONObject: ["method": method, "params": fields]))
        }
        try deliver("item/started", ["item": ["id": "public", "type": "agentMessage", "text": ""]])
        try deliver("item/agentMessage/delta", ["itemId": "public", "delta": "正在核对 "])
        try deliver("item/agentMessage/delta", ["itemId": "public", "delta": "当前来源"])
        XCTAssertEqual(children(model).first?.detail, "正在核对 当前来源")
        try deliver("item/agentMessage/delta", ["itemId": "different", "delta": "wrong item"])
        try deliver("item/commandExecution/outputDelta", ["itemId": "public", "delta": "stdout is not a progress summary"])
        XCTAssertEqual(children(model).first?.detail, "正在核对 当前来源")
        var stale = params; stale["currentTurn"] = ["id": "old", "status": "inProgress"]
        stale["thread"] = ["id": "native-child", "name": "Stale title", "model": "wrong"]
        model.receiveSubagentPublicMessage(try JSONSerialization.data(withJSONObject: ["method": "thread/snapshot", "params": stale]))
        XCTAssertEqual(children(model).first?.title, "Actual audit")
        XCTAssertEqual(children(model).first?.model, "6 Luna · Medium")
    }

    @MainActor func testChildGroupGeometryIsBoundedAndIncludedInScrollLayout() {
        let child = IslandSubagentPresentation(id: "id", title: "Audit", status: "思考中", visualState: .thinking, model: "6.1 Sol · Ultra", duration: "<1m", detail: "")
        var metadata = IslandSessionMetadata(modelName: "6.1 Sol", reasoningEffort: "Ultra", elapsedSeconds: 2,
                                             subagents: Array(repeating: child, count: 3))
        let row = metadata.taskGroupHeight(width: 600)
        XCTAssertEqual(metadata.cardHeight(width: 600), IslandVibeLayout.rowHeight, "Children never resize the card or its Metal canvas")
        XCTAssertEqual(row, IslandVibeLayout.rowHeight + 28)
        let layout = IslandTaskListLayout(taskIDs: [1, 2], detailID: nil, rowHeights: [1: row])
        XCTAssertTrue(layout.visibleElements(offset: row - 1, viewport: 20).contains(.task(1)))
        metadata.subagents = Array(repeating: child, count: 100)
        XCTAssertEqual(metadata.cardHeight(width: 320), IslandVibeLayout.rowHeight)
        XCTAssertEqual(metadata.taskGroupHeight(width: 320), row, "Overflow stays in a single separate row")
        XCTAssertEqual(metadata.subagents.count, 100, "The horizontal strip includes every admitted agent")
    }

    @MainActor func testNativeAvatarPaletteIsPackagedAndAttachedToChildActivity() throws {
        let avatars = Set((0..<1024).map { CodexActivitySubagentAvatar(threadID: "avatar-\($0)") })
        XCTAssertEqual(avatars.count, 28)
        for avatar in avatars {
            let image = try XCTUnwrap(IslandSubagentAvatarImages.image(for: avatar), avatar.assetName)
            XCTAssertGreaterThan(image.size.width, 0)
            let child = IslandSubagentPresentation(id: "id", title: "Arendt", status: "工作中", visualState: .working,
                model: "6.1 Sol · Ultra", duration: "2m", detail: "", avatar: avatar)
            let line = IslandSubagentStrip.activityText([child])
            XCTAssertTrue(line.string.contains("Arendt (6.1 Sol · Ultra) 工作中 · 2m"))
            XCTAssertTrue(line.attribute(.islandInlineImage, at: 0, effectiveRange: nil) is NSImage)
        }
    }

    @MainActor func testBoardGeometryCacheTracksLiveChildMembershipOnSameCard() throws {
        let model = IslandLiveStore(); startParent(model)
        let board = IslandBoardState()
        func refresh() { board.update(model.display(english: false, remaining: nil, enabled: true, privacy: false, at: now), reduceMotion: true) }
        refresh()
        let parent = try XCTUnwrap(board.visibleTasks.first)
        XCTAssertEqual(board.rowHeight(parent), IslandVibeLayout.rowHeight)
        var keys: [String] = []
        for index in 0..<3 { keys.append(try startChild(model, id: "child-\(index)", title: "Audit \(index)")) }
        refresh()
        XCTAssertEqual(board.rowHeight(parent), IslandVibeLayout.rowHeight + 28)
        XCTAssertEqual(board.rowHeights[parent.id], IslandVibeLayout.rowHeight + 28)
        for key in keys { model.receiveSubagentActivity(.init(event: .stop, sessionHash: key, turnHash: "turn", occurredAt: now)) }
        refresh()
        XCTAssertEqual(board.rowHeight(parent), IslandVibeLayout.rowHeight)
    }
}
