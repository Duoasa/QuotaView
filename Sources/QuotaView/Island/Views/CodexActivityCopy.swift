import Foundation
import QuotaViewCore


enum CodexActivityTurnTokenUsagePresentationContract {
    static func showsCompletionReceipt(
        visualState: CodexActivityVisualState,
        operationKey: CodexActivityOperationKey,
        totalTokens: Int64?
    ) -> Bool {
        visualState == .completed
            && operationKey == .turnCompleted
            && totalTokens != nil
    }
}

enum CodexActivityTokenUsageFormatter {
    static func string(for totalTokens: Int64) -> String {
        let tokens = max(totalTokens, 0)
        if tokens >= 1_000_000_000 {
            return compact(Double(tokens) / 1_000_000_000, suffix: "B")
        }
        if tokens >= 1_000_000 {
            return compact(
                Double(tokens) / 1_000_000,
                suffix: "M"
            )
        }
        if tokens >= 1_000 {
            return compact(Double(tokens) / 1_000, suffix: "K")
        }
        return String(tokens)
    }

    private static func compact(
        _ value: Double,
        suffix: String
    ) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded.rounded() == rounded {
            return "\(Int64(rounded))\(suffix)"
        }
        return String(
            format: "%.1f%@",
            locale: Locale(identifier: "en_US_POSIX"),
            rounded,
            suffix
        )
    }
}

struct CodexActivityCopy {
    let language: AppPreferences.Language
    private var copy: AppCopy { AppCopy(language: language) }

    func taskTitle(resolvedTitle: String?, workspaceName: String?) -> String {
        for candidate in [resolvedTitle, workspaceName] {
            if let title = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty { return title }
        }
        return copy.text("未命名任务", "Untitled task")
    }
    func tokenUsageTitle(totalTokens: Int64) -> String {
        let count = CodexActivityTokenUsageFormatter.string(for: totalTokens)
        return copy.text("本次 \(count) tokens", "This turn \(count) tokens")
    }
    func completionTokenUsageDetail(totalTokens: Int64) -> String {
        let count = CodexActivityTokenUsageFormatter.string(for: totalTokens)
        return copy.text("本次消耗 \(count) tokens", "\(count) tokens this turn")
    }
    func completionQuotaAccessibilitySuffix(remainingPercent: Int?) -> String {
        guard let remainingPercent else {
            return copy.text("，当前额度剩余不可用", ", current quota remaining unavailable")
        }
        let percent = min(max(remainingPercent, 0), 100)
        return copy.text("，当前额度剩余 \(percent)%", ", current quota remaining: \(percent) percent")
    }
    func statusTitle(for state: CodexActivityVisualState) -> String {
        switch state {
        case .disconnectedCodex: return copy.text("未连接 Codex", "Codex Not Connected")
        case .standby: return copy.text("空闲", "Idle")
        case .thinking: return copy.text("思考中", "Thinking")
        case .working: return copy.text("工作中", "Working")
        case .compactingContext: return copy.text("正在压缩上下文", "Compacting Context")
        case .awaitingConfirmation: return copy.text("待确认", "Awaiting Confirmation")
        case .completed: return copy.text("已完成", "Completed")
        case .error: return copy.text("失败", "Failed")
        case .unavailable: return copy.text("未载入", "Not Loaded")
        }
    }
    func disconnectedOperation(for status: CodexActivityConnectionStatus, isConfiguring: Bool, compactionOnly: Bool = false) -> String {
        if isConfiguring { return copy.text("正在准备 Codex 灵动岛连接", "Preparing the Codex island connection") }
        if status == .awaitingFirstEvent, compactionOnly {
            return copy.text("等待 Codex 自然压缩上下文", "Waiting for natural Codex context compaction")
        }
        switch status {
        case .notInstalled: return copy.text("在 QuotaView 设置中连接 Codex 灵动岛", "Connect the Codex island in QuotaView Settings")
        case .installedNeedsRestart: return copy.text("请在设置中重新检查 Hook 授权", "Recheck Hook authorization in Settings")
        case .awaitingTrust: return copy.text("请在 QuotaView 设置中授权 Hook 连接", "Authorize the Hook connection in QuotaView Settings")
        case .awaitingFirstEvent: return copy.text("向 Codex 发送一条新消息以完成连接", "Send a new Codex message to finish connecting")
        case .connected: return copy.text("Codex 灵动岛连接已激活", "Codex activity is active")
        case .abnormal: return copy.text("连接遇到问题，请返回 QuotaView 设置", "Connection needs attention in QuotaView Settings")
        }
    }
    func operation(for key: CodexActivityOperationKey) -> String {
        switch key {
        case .connectingSession: return copy.text("正在连接 Codex 会话", "Connecting to the Codex session")
        case .sessionEnded: return copy.text("Codex 会话已结束", "The Codex session ended")
        case .analyzingRequest: return copy.text("正在分析新的任务", "Analyzing the new task")
        case .executingShell: return copy.text("正在执行终端操作", "Running a terminal operation")
        case .editingFiles: return copy.text("正在修改项目文件", "Editing project files")
        case .callingExternalTool: return copy.text("正在调用外部工具", "Calling an external tool")
        case .coordinatingSubagent: return copy.text("正在协调子任务", "Coordinating a subtask")
        case .usingLocalTool: return copy.text("正在执行本地工具", "Running a local tool")
        case .executingPlan: return copy.text("正在执行多步骤计划", "Executing a multi-step plan")
        case .managingGoal: return copy.text("正在更新长期目标", "Updating the long-running goal")
        case .followingGoal: return copy.text("正在跟进长期目标", "Following the long-running goal")
        case .goalPaused: return copy.text("长期目标已暂停", "The long-running goal is paused")
        case .goalBlocked: return copy.text("长期目标需要处理", "The long-running goal needs attention")
        case .goalLimited: return copy.text("长期目标暂受用量限制", "The long-running goal is usage-limited")
        case .goalCompleted: return copy.text("长期目标已完成", "The long-running goal is complete")
        case .usingTool: return copy.text("正在执行工具操作", "Running a tool")
        case .awaitingApproval: return copy.text("有一项操作需要你的批准", "An operation needs your approval")
        case .awaitingUserInput: return copy.text("任务正在等待你的输入", "The task is waiting for your input")
        case .reviewingToolResult: return copy.text("正在检查工具执行结果", "Reviewing the tool result")
        case .compactingContext: return copy.text("正在整理较早消息以释放上下文空间", "Condensing earlier messages to free context")
        case .continuingAfterCompaction: return copy.text("上下文整理完成，正在继续任务", "Context compacted; continuing the task")
        case .subagentStarted: return copy.text("子任务已启动", "A subtask started")
        case .subagentStopped: return copy.text("正在汇总子任务结果", "Summarizing subtask results")
        case .turnCompleted: return copy.text("当前任务已完成", "The current task is complete")
        case .turnInterrupted: return copy.text("当前任务已中断", "The current task was interrupted")
        case .turnFailed: return copy.text("当前任务执行失败", "The current task failed")
        case .bridgeUnavailable: return copy.text("Codex 灵动岛连接不可用", "The Codex island connection is unavailable")
        case .malformedEvent: return copy.text("收到无法识别的 Codex 状态事件", "Received an unrecognized Codex status event")
        }
    }
    func accessibilityLabel(windowTitle: String, statusTitle: String, operation: String,
                            approximateProgressFraction: Double?, tokenUsageTitle: String? = nil) -> String {
        let text: String
        if let fraction = approximateProgressFraction {
            let progress = String(Int((min(max(fraction, 0), 1) * 100).rounded()))
            text = copy.text("\(windowTitle)，状态：\(statusTitle)，近似进度：\(progress)%，当前操作：\(operation)",
                             "\(windowTitle), status: \(statusTitle), approximate progress: \(progress)%, current operation: \(operation)")
        } else {
            text = copy.text("\(windowTitle)，状态：\(statusTitle)，当前操作：\(operation)",
                             "\(windowTitle), status: \(statusTitle), current operation: \(operation)")
        }
        guard let tokenUsageTitle else { return text }
        return text + copy.text("，\(tokenUsageTitle)", ", \(tokenUsageTitle)")
    }
    func presentationAccessibilityValue(_ presentation: CodexActivityIslandPresentation) -> String {
        switch presentation {
        case .expanded: return copy.text("展开", "Expanded")
        case .compact: return copy.text("紧凑", "Compact")
        }
    }
}
