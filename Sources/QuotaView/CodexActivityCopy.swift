import Foundation
import QuotaViewCore

struct CodexActivityCopy {
    let language: AppPreferences.Language

    func statusTitle(for state: CodexActivityVisualState) -> String {
        switch (language, state) {
        case (.simplifiedChinese, .disconnectedCodex):
            "未连接 Codex"
        case (.simplifiedChinese, .standby): "空闲"
        case (.simplifiedChinese, .thinking): "思考中"
        case (.simplifiedChinese, .working): "工作中"
        case (.simplifiedChinese, .compactingContext): "正在压缩上下文"
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
        case (.simplifiedChinese, .usingTool):
            "正在执行工具操作"
        case (.simplifiedChinese, .awaitingApproval):
            "有一项操作需要你的批准"
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
        case (.english, .usingTool):
            "Running a tool"
        case (.english, .awaitingApproval):
            "An operation needs your approval"
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
        case (.english, .bridgeUnavailable):
            "The Codex island connection is unavailable"
        case (.english, .malformedEvent):
            "Received an unrecognized Codex status event"
        }
    }

    func accessibilityLabel(
        windowTitle: String,
        statusTitle: String,
        operation: String
    ) -> String {
        switch language {
        case .simplifiedChinese:
            "\(windowTitle)，状态：\(statusTitle)，当前操作：\(operation)"
        case .english:
            "\(windowTitle), status: \(statusTitle), current operation: \(operation)"
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
