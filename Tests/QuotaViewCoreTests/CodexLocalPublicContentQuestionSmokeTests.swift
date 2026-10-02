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
}
