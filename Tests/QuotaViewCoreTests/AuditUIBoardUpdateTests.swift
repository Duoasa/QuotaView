import Foundation
import XCTest
@testable import QuotaView
@testable import QuotaViewCore

@MainActor final class AuditUIBoardUpdateTests: XCTestCase {
    private func task(_ id: Int, state: CodexActivityVisualState = .completed) -> CodexMultitaskRenderTask {
        .init(id: id, renderState: .init(taskIdentity: .init(sessionHash: "s\(id)", turnHash: "turn"),
            visualState: state, approximateProgressFraction: state == .completed ? 1 : nil,
            windowTitle: "Fixture \(id)", statusTitle: "fixture", operation: "", accessibilityLabel: "fixture"))
    }
    private func display(_ count: Int) -> CodexMultitaskDisplay {
        var display = CodexMultitaskDisplay(state: .init(tasks: (0..<count).map { task($0) }, selectedID: 0,
            allCompleted: true, compact: true, receiptStartedAt: nil), english: false, effect: .dropField)
        display.automaticPopupEnabled = false
        return display
    }
    func testIdenticalHistoryDoesNotRepublishAndSingleChangeRemainsLinear() {
        for count in [128, 1_000, 4_096] {
            let board = IslandBoardState(); var calls = 0
            board.onChange = { calls += 1 }
            let value = display(count)
            board.update(value, reduceMotion: true)
            XCTAssertFalse(board.showsCompletionQuota, "Initial historical sync is a baseline")
            calls = 0
            var samples = [Double]()
            for _ in 0..<24 {
                let start = DispatchTime.now().uptimeNanoseconds
                board.update(value, reduceMotion: true)
                samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000)
            }
            XCTAssertEqual(calls, 0)
            var changed = value; changed.state.tasks[0] = task(0, state: .thinking)
            var changedSamples = [Double]()
            for iteration in 0..<24 {
                let start = DispatchTime.now().uptimeNanoseconds
                board.update(iteration.isMultiple(of: 2) ? changed : value, reduceMotion: true)
                changedSamples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000)
            }
            func metric(_ values: [Double]) -> String {
                let sorted = values.sorted()
                return "P50=\(sorted[12])us P95=\(sorted[22])us MAX=\(sorted.last!)us"
            }
            print("AUDIT011 N=\(count) unchanged \(metric(samples)); oneChanged \(metric(changedSamples))")
            XCTAssertEqual(board.tasks.count, count)
            XCTAssertEqual(calls, 24)
            board.update(.init(state: .init(tasks: [], selectedID: 0, allCompleted: false, compact: true, receiptStartedAt: nil),
                english: false, effect: .dropField), reduceMotion: true)
        }
    }
    func testNoCompletedTasksNeverRotateAndCompletionBurstExtendsSingleQuotaPresentation() {
        let board = IslandBoardState()
        var value = display(2); value.state.tasks = [task(0, state: .thinking), task(1, state: .working)]
        value.state.allCompleted = false
        board.update(value, reduceMotion: true)
        XCTAssertFalse(board.showsCompletedStatistic); XCTAssertFalse(board.showsCompletionQuota)
        value.state.tasks[0] = task(0)
        board.update(value, reduceMotion: true)
        XCTAssertTrue(board.showsCompletedStatistic); XCTAssertTrue(board.showsCompletionQuota)
        value.state.tasks[1] = task(1)
        board.update(value, reduceMotion: true)
        XCTAssertTrue(board.showsCompletionQuota)
        XCTAssertEqual(board.completedCount, 2)
        board.update(.init(state: .init(tasks: [], selectedID: 0, allCompleted: false, compact: true, receiptStartedAt: nil),
            english: false, effect: .dropField), reduceMotion: true)
        XCTAssertFalse(board.showsCompletedStatistic); XCTAssertFalse(board.showsCompletionQuota)
    }
}
