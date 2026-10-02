import AppKit
import Foundation
import SwiftUI
import XCTest
@testable import QuotaView

@MainActor
final class QuestionPresentationLayoutSmokeTests: XCTestCase {
    func testQuestionContentFitsMeasuredHostForSingleLineLongAndHeaderTitles() throws {
        _ = NSApplication.shared
        let variants = [
            ("此弹窗是否正常显示？", ""),
            (String(repeating: "请选择最适合当前任务的处理方式，并确认是否需要保留原来的行为。", count: 3), ""),
            ("请选择最适合当前任务的处理方式，并确认是否需要保留原来的行为。", "处理方式"),
            (String(repeating: "Choose the best response for this task and preserve the original behavior. ", count: 3),
                "Confirmation for the current task")
        ]
        for width in [CGFloat(380), CGFloat(610)] {
            for (title, header) in variants {
                let envelope: [String: Any] = ["id": "layout", "method": "item/tool/requestUserInput",
                    "params": ["threadId": "layout-task", "turnId": "layout-turn", "questions": [
                        ["id": "q", "question": title, "header": header, "isOther": true,
                            "options": [["label": "显示正常"], ["label": "显示异常"]]]]]]
                let data = try JSONSerialization.data(withJSONObject: envelope)
                let wire = try IslandCodexApprovalRequest(data: data)
                let question = try XCTUnwrap(wire.questions.first)
                let heading = NSHostingView(rootView: IslandApprovalQuestionHeading(question: question, number: 1, width: width)
                    .frame(width: width).fixedSize(horizontal: false, vertical: true))
                heading.layoutSubtreeIfNeeded()
                XCTAssertEqual(heading.fittingSize.height, IslandApprovalMetrics.questionHeader(question, width: width), accuracy: 1)
                XCTAssertEqual(heading.fittingSize.width, width, accuracy: 1)
                let model = IslandLiveStore()
                model.receive(wire.raw)
                let display = model.display(english: false, remaining: nil, enabled: true, privacy: false)
                let task = try XCTUnwrap(display.state.tasks.first)
                let request = try XCTUnwrap(display.taskDetails[task.id]?.confirmation)
                let metrics = IslandApprovalMetrics(request: request, width: width, english: false, maximumViewportHeight: 300)
                let view = IslandApprovalView(task: task, metadata: nil, request: request, metrics: metrics,
                    english: false, visible: false, playbackEnabled: false, reduceMotion: true, scrollLink: .init(),
                    draft: .constant(.init()), onDecision: { _, _ in XCTFail("Layout cannot send a response") })
                let content = NSHostingView(rootView: view.requestContent.frame(width: width).fixedSize(horizontal: false, vertical: true))
                content.layoutSubtreeIfNeeded()
                XCTAssertEqual(content.fittingSize.height, metrics.contentHeight - IslandVibeLayout.rowSpacing, accuracy: 3)
                XCTAssertEqual(content.fittingSize.width, width, accuracy: 1)
                if title.count > 80 {
                    XCTAssertGreaterThan(heading.fittingSize.height, IslandApprovalMetrics.questionNumberSize)
                }
            }
            let input = NSHostingView(rootView: IslandApprovalInput(placeholder: "自行输入…", secret: false,
                value: .constant("已有的回答草稿"), selected: true).frame(width: width))
            input.layoutSubtreeIfNeeded()
            XCTAssertEqual(input.fittingSize.height, IslandApprovalMetrics.inputHeight, accuracy: 1)
            XCTAssertEqual(input.fittingSize.width, width, accuracy: 1)
        }
    }
}
