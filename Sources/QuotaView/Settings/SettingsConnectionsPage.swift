import AppKit
import QuotaViewCore
import SwiftUI

extension SettingsView {
    // Both providers remain visible at a glance; their settings stay independent.
    private var connectionStageVisual: some View {
        HStack(spacing: 16) {
            SettingsConnectionSummary(provider: .codex,
                status: activityRuntime.connectionPresentation.automaticStatusTitle(copy),
                color: appServerStageColor,
                detail: copy.text("本机自动连接", "Automatic local connection"))
            ClaudeCodeConnectionStage(runtime: activityRuntime.claudeCode, copy: copy)
        }
    }

    private var appServerStageColor: Color {
        if activityRuntime.isNativeActivityConnected { return SettingsStagePalette.live }
        return activityRuntime.localHealth.hasReadError ? SettingsStagePalette.failure : SettingsStagePalette.faint
    }

    func connectionSettings(selected: IslandAgentProvider?, openAgent: @escaping (IslandAgentProvider) -> Void,
                            detailsExpanded: Binding<Bool>) -> some View {
        AgentIntegrationSettings(preferences: preferences, runtime: activityRuntime, selected: selected,
                                 openAgent: openAgent) {
            codexConnectionSettings(detailsExpanded: detailsExpanded)
        }
    }

    private func codexConnectionSettings(detailsExpanded: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            NativeSettingsRow(
                title: copy.text("连接 Codex", "Connect Codex"),
                subtitle: activityRuntime.connectionPresentation.automaticSubtitle(copy)
            ) {
                HStack(spacing: 10) {
                    NativeSettingsConnectionStatus(
                        title: activityRuntime.connectionPresentation.automaticStatusTitle(copy),
                        color: activityRuntime.isNativeActivityConnected
                            ? Color(nsColor: .systemGreen)
                            : activityRuntime.localHealth.hasReadError
                                ? Color(nsColor: .systemRed)
                                : Color(nsColor: .tertiaryLabelColor)
                    )
                    Button(copy.text("重新检查", "Recheck")) { activityRuntime.recheckAutomaticConnection() }
                        .controlSize(.small)
                        .disabled(activityRuntime.isChangingDataDirectory || activityRuntime.hookOperation != .idle)
                        .help(copy.text("只读检查当前目录，不修改 Hook。", "Check the current directory without changing Hooks."))
                }
            }
            NativeSettingsDivider()
            NativeSettingsRow(
                title: copy.text("数据目录", "Data directory"),
                subtitle: activityRuntime.dataDirectoryURL.path
            ) {
                Menu {
                    Button(copy.text("选择目录…", "Choose Directory…")) { activityRuntime.chooseDataDirectory() }
                    Button(copy.text("恢复默认目录", "Restore Default Directory")) { activityRuntime.selectDataDirectory(nil) }
                        .disabled(!activityRuntime.usesCustomDataDirectory)
                } label: { Text(copy.text("更改目录", "Change Directory")) }
                    .controlSize(.small)
                    .disabled(activityRuntime.isChangingDataDirectory || activityRuntime.hookOperation != .idle)
            }
            if activityRuntime.directorySelectionFailed {
                NativeSettingsNote(text: copy.text(
                    "所选目录缺少可读取的 sessions 文件夹。",
                    "The selected directory needs a readable sessions folder."
                ))
            }
            NativeSettingsDivider()
            NativeSettingsRow(
                title: copy.text("任务事件连接", "Task event connection"),
                subtitle: codexActivityConnectionSubtitle
            ) {
                HStack(spacing: 10) {
                    NativeSettingsConnectionStatus(title: codexActivityConnectionStatusTitle, color: codexActivityConnectionColor)
                    codexHookAction
                }
            }
            if activityRuntime.canConfigureSharedAnswers || activityRuntime.canUseNativeQuestionInput {
                NativeSettingsDivider()
                NativeSettingsRow(title: copy.text("选择题回答", "Question replies"), subtitle: answerLaunchSubtitle) {
                    if !activityRuntime.desktopIgnoresDaemonPreference && (!activityRuntime.canUseNativeQuestionInput || activityRuntime.answerLaunchState != .idle) {
                        switch activityRuntime.answerLaunchState {
                        case .waitingForQuit:
                            Button(copy.text("取消", "Cancel")) { activityRuntime.cancelAnswerLaunch() }
                                .nativeSettingsActionStyle().controlSize(.small)
                        case .requested, .opening:
                            ProgressView().controlSize(.small)
                        case .opened:
                            EmptyView()
                        case .idle, .failed:
                            Button(copy.text("连接回答", "Connect replies")) { activityRuntime.requestSharedAnswers() }
                                .nativeSettingsActionStyle().controlSize(.small)
                                .disabled(activityRuntime.hookOperation != .idle)
                        }
                    }
                }
            }
            if activityRuntime.hasCompatibilityHook,
               activityRuntime.hookConnectionStatus != .connected,
               activityRuntime.hookConnectionStatus != .awaitingFirstEvent {
                NativeSettingsDivider()
                NativeSettingsRow(
                    title: copy.text("停用任务事件连接", "Disable task event connection"),
                    subtitle: copy.text("自动读取任务记录继续工作。", "Automatic task record reading stays active.")
                ) {
                    Button(copy.text("停用", "Disable")) { activityRuntime.disableCompatibilityHook() }
                        .nativeSettingsActionStyle()
                        .controlSize(.small)
                        .disabled(activityRuntime.hookOperation != .idle || activityRuntime.isChangingDataDirectory)
                }
            }
            NativeSettingsDivider()
            NativeSettingsConnectionDetails(copy: copy, isExpanded: detailsExpanded) {
                NativeSettingsNote(text: copy.text(
                    "任务与用量来自本机 Codex。任务事件通过 Hook 补充，首次使用需在 Codex 中授权。停用只移除 QuotaView 的 Hook。",
                    "Tasks and usage come from local Codex. Hooks provide additional task events and require authorization in Codex on first use. Disabling removes only QuotaView hooks."
                ), horizontalPadding: 0)
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent(copy.text("Hook 配置目录", "Hook Configuration Directory"),
                                   value: activityRuntime.hookDirectoryPath)
                    LabeledContent(copy.text("Codex 版本", "Codex version"), value: codexEnvironmentSubtitle)
                    LabeledContent(copy.text("活动支持", "Activity support"), value: codexHooksFeatureTitle)
                    LabeledContent(copy.text("本地连接", "Local connection"), value: codexActivityBridgeStatusTitle)
                    Text(codexActivityBridgeSubtitle).foregroundStyle(.tertiary)
                    LabeledContent(copy.text("诊断日志", "Diagnostic log"), value: activityRuntime.diagnosticLogPath)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.bottom, 10)
            }
        }
        .onAppear { activityRuntime.refreshConnectionStatus() }
    }

    private var answerLaunchSubtitle: String {
        if activityRuntime.canUseNativeQuestionInput && activityRuntime.answerLaunchState == .idle {
            return copy.text("在岛上选择或输入答案，确认后发送到 Codex 当前打开的问题卡。", "Choose or type an answer in the island to send it to the open Codex question card.")
        }
        if activityRuntime.desktopIgnoresDaemonPreference {
            return copy.text("当前 Codex 版本以独占模式打开本地会话，请在原对话中回答。", "This Codex version opens local chats in exclusive mode. Answer in the original chat.")
        }
        return switch activityRuntime.answerLaunchState {
        case .idle:
            copy.text("以共享模式打开 Codex，可在灵动岛回答本次会话中的选择题。", "Open Codex in shared mode to answer questions in the island during this launch.")
        case .requested, .opening:
            copy.text("正在准备共享回答连接…", "Preparing the shared reply connection…")
        case .waitingForQuit:
            copy.text("保存工作并退出 Codex，QuotaView 会以共享模式重新打开它。", "Save your work and quit Codex. QuotaView will reopen it in shared mode.")
        case .opened:
            activityRuntime.automaticConnection.sharedState == .connected
                ? copy.text("共享服务可用。岛内出现可选按钮时，才可回答该题。", "Shared service available. A question can be answered when its choices become interactive in the island.")
                : copy.text("Codex 已打开，正在等待共享服务。", "Codex is open. Waiting for the shared service.")
        case .failed:
            copy.text("共享启动未完成。请检查 Codex 桌面版后重试。", "Shared launch did not finish. Check the Codex desktop app and retry.")
        }
    }

    private var codexHookAction: some View {
        Button {
            switch activityRuntime.hookConnectionStatus {
            case .notInstalled:
                activityRuntime.enableCompatibilityHook()
            case .abnormal:
                activityRuntime.refreshConnectionStatus()
            case .installedNeedsRestart, .awaitingTrust:
                activityRuntime.openCodexSecurityReview()
            case .awaitingFirstEvent, .connected:
                activityRuntime.disableCompatibilityHook()
            }
        } label: {
            if activityRuntime.isConfiguring || activityRuntime.isOpeningSecurityReview {
                ProgressView().controlSize(.small)
            } else {
                Text(codexActivityActionTitle)
            }
        }
        .nativeSettingsActionStyle()
        .controlSize(.small)
        .disabled(activityRuntime.hookOperation != .idle || activityRuntime.isChangingDataDirectory)
        .help(codexActivityActionHelp)
        .accessibilityLabel(codexActivityActionTitle)
    }

    private var codexActivityActionTitle: String {
        if activityRuntime.isConfiguring { return copy.text("正在配置", "Configuring") }
        if activityRuntime.isOpeningSecurityReview { return copy.text("正在授权", "Authorizing") }
        return switch activityRuntime.hookConnectionStatus {
        case .notInstalled: copy.text("启用 Hook", "Enable Hooks")
        case .abnormal: copy.text("重新检查", "Recheck")
        case .installedNeedsRestart, .awaitingTrust: copy.text("授权连接", "Authorize")
        case .awaitingFirstEvent, .connected: copy.text("停用 Hook", "Disable Hooks")
        }
    }

    private var codexActivityActionHelp: String {
        switch activityRuntime.hookConnectionStatus {
        case .installedNeedsRestart, .awaitingTrust:
            copy.text("通过 Codex 授权 QuotaView 的任务事件 Hook。", "Authorize QuotaView task event Hooks through Codex.")
        case .awaitingFirstEvent, .connected:
            copy.text("停用 Hook，App Server 连接继续工作。", "Disable Hooks; the App Server connection keeps working.")
        case .notInstalled, .abnormal:
            copy.text("检查并维护 QuotaView Hook，不更改其他 Hook。", "Check and maintain QuotaView Hooks while preserving other Hooks.")
        }
    }

    private var codexActivityConnectionSubtitle: String {
        if activityRuntime.isConfiguring { return copy.text("正在检查并自动配置…", "Checking and configuring automatically…") }
        if activityRuntime.isOpeningSecurityReview { return copy.text("正在通过 Codex 验证授权…", "Verifying authorization through Codex…") }
        return switch activityRuntime.hookConnectionStatus {
        case .notInstalled: copy.text("Hook 已停用，可随时重新启用。", "Hooks are off. Enable them at any time.")
        case .installedNeedsRestart, .awaitingTrust:
            copy.text("授权后可接收任务事件，并准备以共享模式打开 Codex 以回答选择题。", "Authorize to receive task events and prepare to open Codex in shared mode for question replies.")
        case .awaitingFirstEvent: copy.text("Codex 已确认授权，等待新的任务事件。", "Authorization verified by Codex; waiting for task activity.")
        case .connected: copy.text("已接收任务事件，补充任务与上下文压缩状态。", "Receiving task events for task and context compaction updates.")
        case .abnormal(let message): message
        }
    }

    private var codexActivityConnectionStatusTitle: String {
        if activityRuntime.isConfiguring { return copy.text("正在配置", "Configuring") }
        if activityRuntime.isOpeningSecurityReview { return copy.text("正在授权", "Authorizing") }
        return switch activityRuntime.hookConnectionStatus {
        case .notInstalled: copy.text("已停用", "Disabled")
        case .installedNeedsRestart, .awaitingTrust: copy.text("待授权", "Authorization Needed")
        case .awaitingFirstEvent: copy.text("已授权", "Authorized")
        case .connected: copy.text("已连接", "Connected")
        case .abnormal: copy.text("需要处理", "Needs Attention")
        }
    }

    private var codexActivityConnectionColor: Color {
        if activityRuntime.isConfiguring || activityRuntime.isOpeningSecurityReview { return Color(nsColor: .systemBlue) }
        return switch activityRuntime.hookConnectionStatus {
        case .connected: Color(nsColor: .systemGreen)
        case .installedNeedsRestart, .awaitingTrust, .awaitingFirstEvent: Color(nsColor: .systemOrange)
        case .abnormal: Color(nsColor: .systemRed)
        case .notInstalled: Color(nsColor: .tertiaryLabelColor)
        }
    }

    private var codexEnvironmentSubtitle: String {
        activityRuntime.codexVersion ?? copy.text(
            "检测版本中…",
            "Checking version…"
        )
    }

    private var codexHooksFeatureTitle: String {
        return switch activityRuntime.hooksFeatureStatus {
        case .checking:
            copy.text("检测中", "Checking")
        case .enabled:
            copy.text("Hooks 已启用", "Hooks Enabled")
        case .disabled:
            copy.text("Hooks 未启用", "Hooks Disabled")
        case .unavailable:
            copy.text("Hooks 不可用", "Hooks Unavailable")
        }
    }

    private var codexActivityBridgeSubtitle: String {
        return switch activityRuntime.bridgeStatus {
        case .listening:
            copy.text(
                "通过本地连接接收任务事件。",
                "Receives task events through a local connection."
            )
        case .stopped:
            copy.text(
                "事件桥接尚未启动。",
                "The event bridge is not running."
            )
        case .failed(let message):
            message
        }
    }

    private var codexActivityBridgeStatusTitle: String {
        return switch activityRuntime.bridgeStatus {
        case .listening:
            copy.text("监听中", "Listening")
        case .stopped:
            copy.text("已停止", "Stopped")
        case .failed:
            copy.text("不可用", "Unavailable")
        }
    }

    private var codexActivityBridgeColor: Color {
        return switch activityRuntime.bridgeStatus {
        case .listening:
            Color(nsColor: .systemGreen)
        case .stopped:
            Color(nsColor: .tertiaryLabelColor)
        case .failed:
            Color(nsColor: .systemRed)
        }
    }
}

// Stage colours come from the island itself: true black, the #202020 card
// line, and the island's own completed / attention / failure hues.
private enum SettingsStagePalette {
    static let primary = Color.white.opacity(0.92)
    static let secondary = Color.white.opacity(0.58)
    static let faint = Color.white.opacity(0.3)
    static let live = Color(red: 0.36, green: 0.80, blue: 0.55)
    static let attention = Color(red: 1, green: 0.76, blue: 0.44)
    static let failure = Color(red: 0.95, green: 0.43, blue: 0.42)
}

struct SettingsConnectionSummary: View {
    let provider: IslandAgentProvider
    let status: String
    let color: Color
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                if let icon = IslandProviderIcon.image(for: provider) {
                    Image(nsImage: icon).resizable().scaledToFit().frame(width: 16, height: 16)
                        .accessibilityHidden(true)
                }
                Text(provider.displayName).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SettingsStagePalette.primary).fixedSize()
                Spacer(minLength: 6)
                Circle().fill(color).frame(width: 5, height: 5).accessibilityHidden(true)
                Text(status).font(.system(size: 11)).foregroundStyle(SettingsStagePalette.secondary)
                    .lineLimit(1)
            }
            Text(detail).font(.system(size: 10)).foregroundStyle(SettingsStagePalette.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(Color(white: 0.05).opacity(0.77), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(white: 0.16), lineWidth: 1))
        .help([provider.displayName, status, detail].joined(separator: " · "))
        .accessibilityElement(children: .combine)
    }
}
