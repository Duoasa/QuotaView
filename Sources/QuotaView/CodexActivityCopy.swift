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

    func tokenUsageTitle(totalTokens: Int64) -> String {
        let count = CodexActivityTokenUsageFormatter.string(
            for: totalTokens
        )
        return switch language {
        case .simplifiedChinese: "本次 \(count) tokens"
        case .english: "This turn \(count) tokens"
        }
    }

    func completionTokenUsageDetail(totalTokens: Int64) -> String {
        let count = CodexActivityTokenUsageFormatter.string(
            for: totalTokens
        )
        return switch language {
        case .simplifiedChinese: "本次消耗 \(count) tokens"
        case .english: "\(count) tokens this turn"
        }
    }

    func completionQuotaAccessibilitySuffix(
        remainingPercent: Int?
    ) -> String {
        switch (language, remainingPercent) {
        case (.simplifiedChinese, .some(let remainingPercent)):
            "，当前额度剩余 \(min(max(remainingPercent, 0), 100))%"
        case (.simplifiedChinese, .none):
            "，当前额度剩余不可用"
        case (.english, .some(let remainingPercent)):
            ", current quota remaining: "
                + "\(min(max(remainingPercent, 0), 100)) percent"
        case (.english, .none):
            ", current quota remaining unavailable"
        }
    }

    func statusTitle(for state: CodexActivityVisualState) -> String {
        switch (language, state) {
        case (.simplifiedChinese, .disconnectedCodex):
            "未连接 Codex"
        case (.simplifiedChinese, .standby): "空闲"
        case (.simplifiedChinese, .thinking): "思考中"
        case (.simplifiedChinese, .working): "工作中"
        case (.simplifiedChinese, .compactingContext):
            "正在压缩上下文"
        case (.simplifiedChinese, .awaitingConfirmation): "待确认"
        case (.simplifiedChinese, .completed): "已完成"
        case (.simplifiedChinese, .error): "失败"
        case (.simplifiedChinese, .unavailable): "未载入"
        case (.english, .disconnectedCodex): "Codex Not Connected"
        case (.english, .standby): "Idle"
        case (.english, .thinking): "Thinking"
        case (.english, .working): "Working"
        case (.english, .compactingContext): "Compacting Context"
        case (.english, .awaitingConfirmation): "Awaiting Confirmation"
        case (.english, .completed): "Completed"
        case (.english, .error): "Failed"
        case (.english, .unavailable): "Not Loaded"
        }
    }

    func disconnectedOperation(
        for status: CodexActivityConnectionStatus,
        isConfiguring: Bool
    ) -> String {
        if isConfiguring {
            return switch language {
            case .simplifiedChinese:
                "正在准备 Codex 灵动岛连接"
            case .english:
                "Preparing the Codex island connection"
            }
        }

        return switch (language, status) {
        case (.simplifiedChinese, .notInstalled):
            "在 QuotaView 设置中连接 Codex 灵动岛"
        case (.simplifiedChinese, .installedNeedsRestart):
            "完成安全确认后重新启动 Codex"
        case (.simplifiedChinese, .awaitingTrust):
            "请在打开的 Codex 窗口完成安全确认"
        case (.simplifiedChinese, .awaitingFirstEvent):
            "向 Codex 发送一条新消息以完成连接"
        case (.simplifiedChinese, .connected):
            "Codex 灵动岛连接已激活"
        case (.simplifiedChinese, .abnormal):
            "连接遇到问题，请返回 QuotaView 设置"
        case (.english, .notInstalled):
            "Connect the Codex island in QuotaView Settings"
        case (.english, .installedNeedsRestart):
            "Restart Codex after completing the security review"
        case (.english, .awaitingTrust):
            "Complete the security review in the opened Codex window"
        case (.english, .awaitingFirstEvent):
            "Send a new Codex message to finish connecting"
        case (.english, .connected):
            "Codex activity is active"
        case (.english, .abnormal):
            "Connection needs attention in QuotaView Settings"
        }
    }

    func operation(for key: CodexActivityOperationKey) -> String {
        switch (language, key) {
        case (.simplifiedChinese, .connectingSession):
            "正在连接 Codex 会话"
        case (.simplifiedChinese, .sessionEnded):
            "Codex 会话已结束"
        case (.simplifiedChinese, .analyzingRequest):
            "正在分析新的任务"
        case (.simplifiedChinese, .executingShell):
            "正在执行终端操作"
        case (.simplifiedChinese, .editingFiles):
            "正在修改项目文件"
        case (.simplifiedChinese, .callingExternalTool):
            "正在调用外部工具"
        case (.simplifiedChinese, .coordinatingSubagent):
            "正在协调子任务"
        case (.simplifiedChinese, .usingLocalTool):
            "正在执行本地工具"
        case (.simplifiedChinese, .executingPlan):
            "正在执行多步骤计划"
        case (.simplifiedChinese, .managingGoal):
            "正在更新长期目标"
        case (.simplifiedChinese, .followingGoal):
            "正在跟进长期目标"
        case (.simplifiedChinese, .goalPaused):
            "长期目标已暂停"
        case (.simplifiedChinese, .goalBlocked):
            "长期目标需要处理"
        case (.simplifiedChinese, .goalLimited):
            "长期目标暂受用量限制"
        case (.simplifiedChinese, .goalCompleted):
            "长期目标已完成"
        case (.simplifiedChinese, .usingTool):
            "正在执行工具操作"
        case (.simplifiedChinese, .awaitingApproval):
            "有一项操作需要你的批准"
        case (.simplifiedChinese, .awaitingUserInput):
            "任务正在等待你的输入"
        case (.simplifiedChinese, .reviewingToolResult):
            "正在检查工具执行结果"
        case (.simplifiedChinese, .compactingContext):
            "正在整理较早消息以释放上下文空间"
        case (.simplifiedChinese, .continuingAfterCompaction):
            "上下文整理完成，正在继续任务"
        case (.simplifiedChinese, .subagentStarted):
            "子任务已启动"
        case (.simplifiedChinese, .subagentStopped):
            "正在汇总子任务结果"
        case (.simplifiedChinese, .turnCompleted):
            "当前任务已完成"
        case (.simplifiedChinese, .turnInterrupted):
            "当前任务已中断"
        case (.simplifiedChinese, .turnFailed):
            "当前任务执行失败"
        case (.simplifiedChinese, .bridgeUnavailable):
            "Codex 灵动岛连接不可用"
        case (.simplifiedChinese, .malformedEvent):
            "收到无法识别的 Codex 状态事件"
        case (.english, .connectingSession):
            "Connecting to the Codex session"
        case (.english, .sessionEnded):
            "The Codex session ended"
        case (.english, .analyzingRequest):
            "Analyzing the new task"
        case (.english, .executingShell):
            "Running a terminal operation"
        case (.english, .editingFiles):
            "Editing project files"
        case (.english, .callingExternalTool):
            "Calling an external tool"
        case (.english, .coordinatingSubagent):
            "Coordinating a subtask"
        case (.english, .usingLocalTool):
            "Running a local tool"
        case (.english, .executingPlan):
            "Executing a multi-step plan"
        case (.english, .managingGoal):
            "Updating the long-running goal"
        case (.english, .followingGoal):
            "Following the long-running goal"
        case (.english, .goalPaused):
            "The long-running goal is paused"
        case (.english, .goalBlocked):
            "The long-running goal needs attention"
        case (.english, .goalLimited):
            "The long-running goal is usage-limited"
        case (.english, .goalCompleted):
            "The long-running goal is complete"
        case (.english, .usingTool):
            "Running a tool"
        case (.english, .awaitingApproval):
            "An operation needs your approval"
        case (.english, .awaitingUserInput):
            "The task is waiting for your input"
        case (.english, .reviewingToolResult):
            "Reviewing the tool result"
        case (.english, .compactingContext):
            "Condensing earlier messages to free context"
        case (.english, .continuingAfterCompaction):
            "Context compacted; continuing the task"
        case (.english, .subagentStarted):
            "A subtask started"
        case (.english, .subagentStopped):
            "Summarizing subtask results"
        case (.english, .turnCompleted):
            "The current task is complete"
        case (.english, .turnInterrupted):
            "The current task was interrupted"
        case (.english, .turnFailed):
            "The current task failed"
        case (.english, .bridgeUnavailable):
            "The Codex island connection is unavailable"
        case (.english, .malformedEvent):
            "Received an unrecognized Codex status event"
        }
    }

    func accessibilityLabel(
        windowTitle: String,
        statusTitle: String,
        operation: String,
        approximateProgressFraction: Double?,
        tokenUsageTitle: String? = nil
    ) -> String {
        let progressText = approximateProgressFraction.map {
            String(Int((min(max($0, 0), 1) * 100).rounded()))
        }
        switch language {
        case .simplifiedChinese:
            if let progressText {
                return "\(windowTitle)，状态：\(statusTitle)，"
                    + "近似进度：\(progressText)%，当前操作：\(operation)"
                    + tokenUsageAccessibilitySuffix(tokenUsageTitle)
            }
            return "\(windowTitle)，状态：\(statusTitle)，"
                + "当前操作：\(operation)"
                + tokenUsageAccessibilitySuffix(tokenUsageTitle)
        case .english:
            if let progressText {
                return "\(windowTitle), status: \(statusTitle), "
                    + "approximate progress: \(progressText)%, "
                    + "current operation: \(operation)"
                    + tokenUsageAccessibilitySuffix(tokenUsageTitle)
            }
            return "\(windowTitle), status: \(statusTitle), "
                + "current operation: \(operation)"
                + tokenUsageAccessibilitySuffix(tokenUsageTitle)
        }
    }

    private func tokenUsageAccessibilitySuffix(
        _ tokenUsageTitle: String?
    ) -> String {
        guard let tokenUsageTitle else { return "" }
        return switch language {
        case .simplifiedChinese: "，\(tokenUsageTitle)"
        case .english: ", \(tokenUsageTitle)"
        }
    }

    func presentationAccessibilityValue(
        _ presentation: CodexActivityIslandPresentation
    ) -> String {
        switch (language, presentation) {
        case (.simplifiedChinese, .expanded): "展开"
        case (.simplifiedChinese, .compact): "紧凑"
        case (.english, .expanded): "Expanded"
        case (.english, .compact): "Compact"
        }
    }
}
