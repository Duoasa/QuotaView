import AppKit
import SwiftUI
import XCTest
@testable import QuotaView

@MainActor
final class IslandApprovalPreviewSmokeTests: XCTestCase {
    private func wire(command: String) throws -> IslandCodexApprovalRequest {
        try .init(data: JSONSerialization.data(withJSONObject: ["id": "long-command",
            "method": "item/commandExecution/requestApproval", "params": [
                "threadId": "preview-thread", "turnId": "preview-turn", "itemId": "item",
                "command": command, "cwd": "/private/tmp", "availableDecisions": [
                    "accept", ["acceptWithExecpolicyAmendment": ["execpolicy_amendment": [command]]],
                    "decline", "cancel"]]]))
    }
    private func assertMeasuredContent(_ wire: IslandCodexApprovalRequest, width: CGFloat, english: Bool) throws {
        _ = NSApplication.shared
        let store = IslandLiveStore(); store.receive(wire.raw)
        let display = store.display(english: english, remaining: nil, enabled: true, privacy: false)
        let task = try XCTUnwrap(display.state.tasks.first)
        let confirmation = try XCTUnwrap(display.taskDetails[task.id]?.confirmation)
        let metrics = IslandApprovalMetrics(request: confirmation, width: width, english: english, maximumViewportHeight: 2_000)
        let view = IslandApprovalView(task: task, metadata: nil, request: confirmation, metrics: metrics,
            english: english, visible: false, playbackEnabled: false, reduceMotion: true, scrollLink: .init(),
            draft: .constant(.init()), onDecision: { _, _ in XCTFail("Measuring a preview cannot approve") })
        let host = NSHostingView(rootView: view.requestContent.frame(width: width).fixedSize(horizontal: false, vertical: true))
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.fittingSize.height, metrics.contentHeight - IslandVibeLayout.rowSpacing, accuracy: 3)
        XCTAssertEqual(host.fittingSize.width, width, accuracy: 1)
        XCTAssertLessThanOrEqual(metrics.viewportHeight, 440)
        XCTAssertLessThanOrEqual(metrics.height, 440 + IslandApprovalMetrics.fixedHeight)
    }
    func testLongCommandAndRememberedRuleUseBoundedMeasuredPreviewWithoutChangingApproval() throws {
        let command = (1...120).map { "echo 'line \($0): preserve the entire original command and remembered rule'" }.joined(separator: "\n")
        let request = try wire(command: command)
        let rule = try XCTUnwrap(IslandApprovalDecisionChoices.options(request).first(where: \.isRule))
        for width: CGFloat in [380, 610] {
            XCTAssertTrue(IslandApprovalCodePreview.isTruncated(command, width: width - 24))
            XCTAssertLessThan(IslandApprovalTypedMetrics.code(command, caption: "/private/tmp", width: width), 300)
            XCTAssertLessThan(IslandApprovalDecisionChoices.optionHeight(rule, width: width, english: false), 100)
            for english in [false, true] { try assertMeasuredContent(request, width: width, english: english) }
        }
        XCTAssertEqual(request.detail, command)
        XCTAssertEqual(rule.detail.value(false), command)
        XCTAssertEqual(rule.action.result["decision"]["acceptWithExecpolicyAmendment"]["execpolicy_amendment"].array.map(\.text), [command])
        XCTAssertTrue(request.permits(rule.action.result))
    }
    func testLongQuestionOptionKeepsExactSelectionValueWhileItsMeasuredSlotStaysShort() throws {
        let label = String(repeating: "保留所有原始数据并使用当前批准范围。", count: 50)
        let description = String(repeating: "The original response must reach Codex without display truncation. ", count: 50)
        let request = try IslandCodexApprovalRequest(data: JSONSerialization.data(withJSONObject: [
            "id": "long-option", "method": "item/tool/requestUserInput", "params": [
                "threadId": "preview-thread", "turnId": "preview-turn", "questions": [[
                    "id": "q", "question": "请选择处理方式", "isOther": true,
                    "options": [["label": label, "description": description]]]]]]))
        for width: CGFloat in [380, 610] {
            XCTAssertLessThan(IslandApprovalMetrics.optionHeight(label, description: description, width: width), 100)
            try assertMeasuredContent(request, width: width, english: false)
        }
        var draft = IslandApprovalDraft(); draft.selections["q"] = [label]
        XCTAssertEqual(draft.result(for: request)?["answers"]["q"]["answers"].array.map(\.text), [label])
    }
    func testShortCommandsStayUnabridgedAndSmallDisplaysRespectTheirOwnHeight() throws {
        let value = "git status --short"
        XCTAssertEqual(IslandApprovalCodePreview.text(value), value)
        XCTAssertFalse(IslandApprovalCodePreview.isTruncated(value, width: 580))
        let request = try wire(command: value)
        let confirmation = IslandConfirmation(question: .init(request.detail), impact: .init(""), protocolRequest: request)
        for available: CGFloat in [0, 120, 300] {
            let metrics = IslandApprovalMetrics(request: confirmation, width: 380, english: false, maximumViewportHeight: available)
            XCTAssertLessThanOrEqual(metrics.viewportHeight, available)
        }
    }
}
