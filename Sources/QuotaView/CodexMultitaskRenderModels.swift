import AppKit
import Foundation
import QuotaViewCore

struct CodexMultitaskRenderTask: Equatable {
    let id: Int
    let renderState: CodexActivityRenderState
    var playbackEnabled = true
    var hasPendingRequest = false
    var title: String { renderState.windowTitle }
    var color: NSColor {
        renderState.visualState == .completed ? .systemGreen : renderState.visualState.activityAccentColor
    }
}
/// A bounded background summary, independent of user selection, counts and popups.
struct IslandMemoryActivity: Equatable {
    let snapshot: CodexActivitySnapshot
    let count: Int
    init?(snapshots: [CodexActivitySnapshot]) {
        guard let representative = snapshots.sorted(by: {
            let lhs = Self.isInFlight($0), rhs = Self.isInFlight($1)
            if lhs != rhs { return lhs }
            if $0.occurredAt != $1.occurredAt { return $0.occurredAt > $1.occurredAt }
            return $0.sessionHash < $1.sessionHash
        }).first else { return nil }
        snapshot = representative; count = snapshots.count
    }
    private static func isInFlight(_ snapshot: CodexActivitySnapshot) -> Bool {
        [.thinking, .working, .compactingContext, .awaitingConfirmation, .unavailable, .disconnectedCodex].contains(snapshot.state)
    }
    var visualState: CodexActivityVisualState { snapshot.state }
    var playbackEnabled: Bool {
        [.thinking, .working, .compactingContext, .awaitingConfirmation].contains(snapshot.state)
    }
    func label(english: Bool) -> String {
        let copy = AppCopy(language: english ? .english : .simplifiedChinese)
        let status: String
        switch snapshot.state {
        case .thinking, .working, .compactingContext: status = copy.text("正在整理", "Organizing")
        case .awaitingConfirmation: status = copy.text("等待处理", "Awaiting action")
        case .completed: status = copy.text("整理完成", "Completed")
        case .error: status = copy.text("整理失败", "Failed")
        case .unavailable, .disconnectedCodex: status = copy.text("状态待更新", "Status unavailable")
        case .standby:
            status = snapshot.operationKey == .turnInterrupted
                ? copy.text("已中断", "Interrupted") : copy.text("待运行", "Idle")
        }
        let title = copy.text("记忆整理", "Memory consolidation") + " · " + status
        return count > 1 ? title + copy.text("（\(count) 个后台任务）", " (\(count) background tasks)") : title
    }
}

struct CodexMultitaskDisplay: Equatable {
    struct State: Equatable {
        var tasks: [CodexMultitaskRenderTask]
        var selectedID: Int
        var allCompleted: Bool
        var compact: Bool
        var receiptStartedAt: TimeInterval?
    }
    var state: State
    var english: Bool
    var effect: AppPreferences.CodexActivityProgressEffect
    var visible = true
    var playbackEnabled = true
    var totalTokens: Int64?
    var remainingPercent: Int?
    var weeklyRemainingPercent: Int? = nil
    var quotaResetsAt: Date? = nil
    var usageSnapshot: CurrentCodexPresentation? = nil
    var usageState: IslandUsagePresentation.State = .loading
    var usageOptions = IslandUsageOptions()
    var automaticPopupEnabled = true
    var automaticPopupDuration = AppPreferences.CodexActivityAutomaticPopupTiming.defaultDuration
    var sessionMetadata: [Int: IslandSessionMetadata] = [:]
    var taskDetails: [Int: IslandTaskDetailData] = [:]
    var connectionTitle: String = ""
    var privacyMode = false
    var activeRequestIDs: Set<UUID> = []
    // Background memory work has its own lifecycle and never becomes a session row.
    var backgroundMemorySnapshots: [CodexActivitySnapshot] = []
}
