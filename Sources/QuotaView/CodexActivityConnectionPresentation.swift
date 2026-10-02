import Foundation
import QuotaViewCore


enum CodexActivityConnectionStatus: Equatable {
    case notInstalled
    case installedNeedsRestart
    case awaitingTrust
    case awaitingFirstEvent
    case connected
    case abnormal(String)
}

/// A single snapshot owns automatic connection facts. Availability is derived,
/// never stored independently from local read health and shared-service state.
struct CodexAutomaticActivityConnection: Equatable, Sendable {
    var localHealth: CodexLocalActivityHealth = .disabled
    var sharedState: CodexSharedAppServerConnectionState = .disabled

    var nativeState: CodexSharedAppServerConnectionState {
        if sharedState == .connected || [.ready, .receiving].contains(localHealth) { return .connected }
        if sharedState == .discovering || localHealth != .disabled { return .discovering }
        return .disabled
    }
}

/// Presentation contains no discovery or Hook side effects.
struct CodexActivityConnectionPresentation {
    let connection: CodexAutomaticActivityConnection
    let hookStatus: CodexActivityConnectionStatus

    func showsHookSetupIsland(explicitlyRequested: Bool) -> Bool {
        explicitlyRequested && connection.nativeState != .connected && hookStatus != .connected
    }

    func automaticStatusTitle(_ copy: AppCopy) -> String {
        if connection.sharedState == .connected, ![.ready, .receiving].contains(connection.localHealth) {
            return copy.text("服务已连接", "Service Connected")
        }
        return switch connection.localHealth {
        case .checking: copy.text("正在检查", "Checking")
        case .waitingForRecords: copy.text("等待首次任务", "Waiting for First Task")
        case .ready: copy.text("已就绪，等待任务", "Ready, Waiting for Task")
        case .receiving: copy.text("已收到任务活动", "Task Activity Received")
        case .unreadable: copy.text("无法读取目录", "Directory Unreadable")
        case .unsupported: copy.text("记录格式不支持", "Unsupported Record Format")
        case .disabled: connection.sharedState == .discovering
            ? copy.text("正在发现服务", "Discovering Service")
            : copy.text("自动读取已禁用", "Automatic Reading Disabled")
        }
    }

    func automaticSubtitle(_ copy: AppCopy) -> String {
        let localDescription = switch connection.localHealth {
        case .checking: copy.text("正在检查 Codex 本地任务记录。", "Checking local Codex task records.")
        case .waitingForRecords: copy.text("尚无任务记录，请在 Codex 中运行任务。", "No task records yet. Run a task in Codex.")
        case .ready: copy.text("任务记录可读取，等待新活动。", "Task records are readable; waiting for activity.")
        case .receiving: copy.text("已收到有效任务活动。", "Codex task activity received.")
        case .unreadable: copy.text("请检查目录与读取权限，或重新选择数据目录。", "Check the directory and read permissions, or choose another data directory.")
        case .unsupported: copy.text("任务记录格式不兼容，请重新检查或启用 Hook 兼容连接。", "Unsupported task record format. Recheck or enable the Hook compatibility connection.")
        case .disabled: copy.text("自动读取已关闭。", "Automatic reading is off.")
        }
        if connection.sharedState == .connected, ![.ready, .receiving].contains(connection.localHealth) {
            let connected = copy.text("已连接 Codex 本地服务。", "Connected to the local Codex service.")
            return connection.localHealth.hasReadError ? connected + " " + localDescription : connected
        }
        return localDescription
    }
}

/// Activity readers and Hook configuration share the selected Codex data directory.
/// Account/quota clients keep their independent account configuration.
enum CodexActivityDirectoryEnvironment {
    static func make(root: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = root.path
        environment["CODEX_APP_SERVER_USE_LOCAL_DAEMON"] = "0"
        return environment
    }
}

enum CodexHooksFeatureStatus: Equatable {
    case checking
    case enabled
    case disabled
    case unavailable
}

enum CodexActivityBridgeStatus: Equatable {
    case stopped
    case listening
    case failed(String)
}
