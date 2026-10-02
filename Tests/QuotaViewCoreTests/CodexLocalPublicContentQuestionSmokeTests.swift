import Foundation
import XCTest
@testable import QuotaViewCore

final class CodexLocalPublicContentQuestionSmokeTests: XCTestCase {
    func testAsyncQuestionProjectionIncludesCustomResponseWithoutGrantingCapability() throws {
        for options in [["A", "B"], []] {
            let result = try XCTUnwrap(CodexLocalQuestionContent.questions([
                "name": "functions.request_user_input_async",
                "arguments": String(decoding: try JSONSerialization.data(withJSONObject: ["questions": [[
                    "title": "Which?", "options": options, "isOther": false
                ]]]), as: UTF8.self)
            ]))
            XCTAssertEqual(result.count, 1)
            XCTAssertEqual(result[0]["isOther"] as? Bool, true)
            XCTAssertEqual((result[0]["options"] as? [[String: String]])?.map { $0["label"] }, options)
            XCTAssertNil(result[0]["requestId"])
            XCTAssertNil(result[0]["ownerClientId"])
        }
    }

    func testSynchronousQuestionRespectsExplicitCustomResponseFlag() throws {
        let result = try XCTUnwrap(CodexLocalQuestionContent.questions([
            "name": "functions.request_user_input",
            "arguments": String(decoding: try JSONSerialization.data(withJSONObject: ["questions": [[
                "id": "original", "question": "Which?", "options": [["label": "A"]], "isOther": false
            ]]]), as: UTF8.self)
        ]))
        XCTAssertEqual(result[0]["isOther"] as? Bool, false)
        XCTAssertEqual(result[0]["id"] as? String, "original")
    }

    private func identity(source: String = "call-fixture", index: Int = 0) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: ["request_user_input_async", source, index],
            options: [.withoutEscapingSlashes]), as: UTF8.self)
    }
    private func reply(_ identity: String, title: String = "Private question text", answer: String = "Private answer token") -> [String: Any] {
        ["questionItemId": identity, "question": title, "answer": answer]
    }
    private func wrapper(_ body: Any) throws -> String {
        CodexDesktopRequestProjector.asyncReplyOpeningTag + "\n"
            + String(decoding: try JSONSerialization.data(withJSONObject: body, options: [.fragmentsAllowed]), as: UTF8.self)
            + "\n" + CodexDesktopRequestProjector.asyncReplyClosingTag
    }
    private func decodeUser(_ text: String, role: String = "user", additional: [[String: Any]] = []) throws -> CodexLocalPublicContent? {
        let line = try JSONSerialization.data(withJSONObject: ["type": "response_item", "payload": [
            "type": "message", "role": role, "content": [["type": "input_text", "text": text]] + additional]])
        return CodexLocalPublicContent.decode(line, sessionHash: "session", activeTurnHash: "turn")
    }

    func testCompleteNativeReplyPublishesOnlyIdentityAndQuestionHashes() throws {
        let id = try identity(), title = "Private question text", answer = "Private answer token"
        let result = try XCTUnwrap(decodeUser(" \n" + wrapper([reply(id, title: title, answer: answer)]) + "\n "))
        let clean = try XCTUnwrap(JSONSerialization.jsonObject(with: result.data) as? [String: Any])
        let proofs = try XCTUnwrap(clean["replies"] as? [[String: String]])
        XCTAssertEqual(clean["type"] as? String, "questionReply")
        XCTAssertEqual(Set(clean.keys), ["type", "id", "replies"])
        XCTAssertEqual(proofs, [["questionItemHash": CodexActivityPrivacy.hashIdentifier(id),
                                 "questionHash": CodexActivityPrivacy.hashIdentifier(title)]])
        XCTAssertEqual(proofs[0]["questionItemHash"]?.count, CodexActivityPrivacy.hashIdentifier("").count)
        let publicText = String(decoding: result.data, as: UTF8.self)
        for privateText in [id, "call-fixture", title, answer, "questionItemId", "answer"] {
            XCTAssertFalse(publicText.contains(privateText))
        }
    }

    func testSingletonNativeReplyAndCanonicalUnicodeIdentityAreAccepted() throws {
        let source = "call/问题-\"雪\"", id = try identity(source: source, index: 2)
        let result = try XCTUnwrap(decodeUser(wrapper(reply(id))))
        let clean = try XCTUnwrap(JSONSerialization.jsonObject(with: result.data) as? [String: Any])
        let proofs = try XCTUnwrap(clean["replies"] as? [[String: String]])
        XCTAssertEqual(proofs[0]["questionItemHash"], CodexLocalAsyncReplyContent.identityHash(source: source, index: 2))
    }

    func testOrdinaryUserPromptAndSurroundingPromptNeverBecomeSettlementProof() throws {
        let native = try wrapper([reply(identity())])
        for text in ["ordinary private prompt", "private prompt\n" + native, native + "\nprivate prompt", native + native] {
            XCTAssertNil(try decodeUser(text))
        }
        XCTAssertNil(try decodeUser(native, role: "system"))
        XCTAssertNil(try decodeUser(native, additional: [["type": "input_text", "text": "private prompt"]]))
    }

    func testMalformedOrNoncanonicalTupleDoesNotMatchNativeQuestionIdentity() throws {
        let invalidIDs = [
            "[\"request_user_input_async\", \"call-fixture\",0]",
            "[\"request_user_input_async\",\"call-fixture\",0.0]",
            "[\"request_user_input_async\",\"call-fixture\",true]",
            "[\"request_user_input_async\",\"call-fixture\",0.5]",
            "[\"request_user_input_async\",\"call-fixture\",32]",
            "[\"request_user_input\",\"call-fixture\",0]",
            "[\"request_user_input_async\",\"\",0]",
            "[\"request_user_input_async\",\"call\\/fixture\",0]"
        ]
        for id in invalidIDs { XCTAssertNil(try decodeUser(wrapper([reply(id)])), id) }
    }

    func testDuplicateOrIncompleteRepliesAreRejectedWithoutPublishingPartialProof() throws {
        let valid = reply(try identity())
        var missingAnswer = valid; missingAnswer.removeValue(forKey: "answer")
        var emptyAnswer = valid; emptyAnswer["answer"] = " \n "
        var emptyQuestion = valid; emptyQuestion["question"] = ""
        var longQuestion = valid; longQuestion["question"] = String(repeating: "q", count: 16_385)
        for body in [[valid, valid], [valid, missingAnswer], [emptyAnswer], [emptyQuestion], [longQuestion], []] {
            XCTAssertNil(try decodeUser(wrapper(body)))
        }
    }
}
