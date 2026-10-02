import AppKit
import Foundation
import SwiftUI
import XCTest
@testable import QuotaView
@testable import QuotaViewCore

@MainActor
final class CompactTitleLayoutSmokeTests: XCTestCase {
    private func nativeTitle(in view: NSView) -> IslandScrollingTextHost? {
        if let title = view as? IslandScrollingTextHost { return title }
        return view.subviews.lazy.compactMap { self.nativeTitle(in: $0) }.first
    }
    private func display(title: String) -> CodexMultitaskDisplay {
        let active = CodexActivityRenderState(visualState: .compactingContext, approximateProgressFraction: nil,
            windowTitle: title, statusTitle: "", operation: "", accessibilityLabel: title)
        let other = CodexActivityRenderState(visualState: .thinking, approximateProgressFraction: nil,
            windowTitle: "另一任务", statusTitle: "思考中", operation: "", accessibilityLabel: "另一任务")
        var value = CodexMultitaskDisplay(state: .init(tasks: [
            .init(id: 1, renderState: active, hasPendingRequest: true),
            .init(id: 2, renderState: other)
        ], selectedID: 1, allCompleted: false, compact: true, receiptStartedAt: nil),
            english: false, effect: .dropField, totalTokens: nil, remainingPercent: nil)
        value.playbackEnabled = false
        value.automaticPopupEnabled = false
        return value
    }
    func testActualCompactHostCentersFittingTitleAndUsesRealSpaceForOverflow() throws {
        _ = NSApplication.shared
        for (title, overflowing) in [("短标题", false), (String(repeating: "QuotaView 0.7.3 继续开发 ", count: 3), true)] {
            let board = IslandBoardState()
            board.setGeometry(.init(frame: CGRect(x: 0, y: 0, width: 1400, height: 900)))
            board.update(display(title: title), reduceMotion: true)
            board.collapse()
            let size = CGSize(width: board.surfaceWidth, height: board.geometry.bandHeight)
            let host = NSHostingView(rootView: IslandBoardView(state: board, compactContent: true)
                .frame(width: size.width, height: size.height))
            host.frame = CGRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            let native = try XCTUnwrap(nativeTitle(in: host))
            let frame = host.convert(native.bounds, from: native)
            XCTAssertEqual(host.fittingSize.width, size.width, accuracy: 1)
            XCTAssertEqual(host.fittingSize.height, size.height, accuracy: 1)
            XCTAssertGreaterThanOrEqual(frame.minX, 20 + 30 + IslandVibeLayout.compactContentGap - 1)
            XCTAssertLessThanOrEqual(frame.maxX, size.width - 20)
            if overflowing {
                XCTAssertEqual(frame.minX, 20 + 30 + IslandVibeLayout.compactContentGap, accuracy: 1,
                    "Long titles start beside the real Orb slot, without a hidden statistics copy")
                XCTAssertGreaterThan(frame.width, 120, "The title must use the space reclaimed from the empty left region")
            } else {
                XCTAssertEqual(frame.midX, size.width / 2, accuracy: 1,
                    "A fitting title keeps its existing centering across the whole island")
            }
            XCTAssertEqual(board.attentionCount, 1,
                "Compaction does not by itself answer a separately pending request")
            XCTAssertEqual(board.statusCounts.first(where: { $0.state == .compactingContext })?.count, 1)
        }
    }
}
