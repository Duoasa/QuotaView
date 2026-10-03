import Foundation
import SwiftUI
import XCTest
@testable import QuotaView

@MainActor
final class IslandApprovalSemanticsSmokeTests: XCTestCase {
    private func request(schema: [String: Any], mode: String = "form",
                         message: String = "Allow Computer Use to use \"DeepViewer Dev\"?") throws -> IslandCodexApprovalRequest {
        let envelope: [String: Any] = ["id": "approval", "method": "mcpServer/elicitation/request", "params": [
            "threadId": "conversation", "turnId": "turn", "serverName": "computer-use", "mode": mode,
            "message": message, "requestedSchema": schema]]
        return try .init(data: JSONSerialization.data(withJSONObject: envelope))
    }

    private func view(_ wire: IslandCodexApprovalRequest, draft: IslandApprovalDraft = .init(),
                      english: Bool = false, phase: IslandConfirmation.Phase = .ready) throws -> IslandApprovalView {
        let model = IslandLiveStore()
        model.receive(wire.raw)
        let display = model.display(english: english, remaining: nil, enabled: true, privacy: false)
        let task = try XCTUnwrap(display.state.tasks.first)
        let confirmation = IslandConfirmation(question: .init(wire.detail), impact: .init(""), phase: phase,
            protocolRequest: wire, canRespond: true)
        return .init(task: task, metadata: nil, request: confirmation,
            metrics: .init(request: confirmation, width: 610, english: english, maximumViewportHeight: 300),
            english: english, visible: false, playbackEnabled: false, reduceMotion: true, scrollLink: .init(),
            draft: .constant(draft), onDecision: { _, _ in XCTFail("Reading presentation must not submit") })
    }

    func testEmptyMCPFormUsesApprovalPresentationWithoutChangingWireResponse() throws {
        for mode in ["form", "openai/form", "openaiForm"] {
            let wire = try request(schema: ["type": "object", "properties": [:], "required": []], mode: mode)
            XCTAssertEqual(wire.kind, .mcpForm, "Presentation semantics must preserve the MCP response protocol")
            XCTAssertTrue(wire.supportedForm)
            XCTAssertTrue(wire.isApprovalOnlyForm)
            XCTAssertEqual(IslandApprovalLayout(wire), .toolApproval)
            let result = try XCTUnwrap(IslandApprovalDraft().result(for: wire))
            XCTAssertEqual(result, .object(["action": .string("accept"), "content": .object([:]), "_meta": .null]))
            XCTAssertTrue(wire.permits(result))
            XCTAssertFalse(wire.permits(.object(["action": .string("accept"), "content": .object(["invented": .bool(true)]), "_meta": .null])))
            XCTAssertEqual(wire.actions.map { $0.result["action"].text }, ["decline", "cancel"])
            XCTAssertEqual(try view(wire).primaryAction?.label.value(false), "批准")
            XCTAssertEqual(try view(wire, english: true).primaryAction?.label.value(true), "Approve")
            XCTAssertEqual(try view(wire).footerStatus, "批准后继续")
            XCTAssertEqual(try view(wire, english: true).footerStatus, "Resumes after approval")
            XCTAssertEqual(try view(wire, phase: .submitting(.reply(result))).footerStatus, "批准中…")
            XCTAssertEqual(try view(wire, english: true, phase: .submitting(.reply(result))).footerStatus, "Approving…")
        }
    }

    func testObjectSchemaWithoutDeclaredFieldsStillRepresentsConsent() throws {
        let wire = try request(schema: ["type": "object"])
        XCTAssertTrue(wire.isApprovalOnlyForm)
        XCTAssertEqual(IslandApprovalLayout(wire), .toolApproval)
        XCTAssertNotNil(IslandApprovalDraft().result(for: wire))
    }

    func testRealRequiredFormKeepsParameterCopyAndValidation() throws {
        let wire = try IslandApprovalFixtures.request("mcpForm")
        XCTAssertFalse(wire.isApprovalOnlyForm)
        XCTAssertEqual(IslandApprovalLayout(wire), .form)
        XCTAssertNil(IslandApprovalDraft().result(for: wire))
        XCTAssertEqual(try view(wire).primaryAction?.label.value(false), "提交参数")
        XCTAssertEqual(try view(wire, english: true).primaryAction?.label.value(true), "Submit form")
        XCTAssertEqual(try view(wire).primaryAction?.result, .null)
        XCTAssertEqual(try view(wire).footerStatus, "请填写必填项并检查格式")
        var draft = IslandApprovalDraft()
        draft.values = ["copies": "2", "format": "PDF", "includeNotes": "true"]
        XCTAssertNotNil(draft.result(for: wire))
        XCTAssertEqual(try view(wire, draft: draft).footerStatus, "参数已就绪")
        draft.values["copies"] = "11"
        XCTAssertNil(draft.result(for: wire), "The presentation change cannot bypass numeric constraints")
    }

    func testOptionalFieldsStayEditableRegardlessOfApprovalWordsInMessage() throws {
        let wire = try request(schema: ["type": "object", "properties": ["note": ["type": "string"]]],
            message: "Allow Computer Use to use DeepViewer Dev?")
        XCTAssertTrue(wire.supportedForm)
        XCTAssertFalse(wire.isApprovalOnlyForm)
        XCTAssertEqual(IslandApprovalLayout(wire), .form)
        XCTAssertEqual(try view(wire).primaryAction?.label.value(false), "提交参数")
        var draft = IslandApprovalDraft()
        draft.values["note"] = "Preserve my input"
        XCTAssertEqual(draft.result(for: wire)?["content"]["note"], .string("Preserve my input"))
    }

    func testMalformedOrUnsupportedSchemasNeverBecomeApprovalOnly() throws {
        let schemas: [[String: Any]] = [
            ["properties": [:]],
            ["type": "object", "properties": NSNull()],
            ["type": "object", "properties": [], "required": []],
            ["type": "object", "properties": [:], "required": ["missing"]],
            ["type": "object", "properties": [:], "allOf": [["type": "object"]]],
            ["type": "object", "properties": ["nested": ["type": "object"]]]
        ]
        for schema in schemas {
            let wire = try request(schema: schema)
            XCTAssertFalse(wire.supportedForm)
            XCTAssertFalse(wire.isApprovalOnlyForm)
            XCTAssertEqual(IslandApprovalLayout(wire), .verification)
            XCTAssertNil(IslandApprovalDraft().result(for: wire))
        }
    }
}
