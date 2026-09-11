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
        case .checking: copy.text("正在只读检查 Codex 本地记录，无需配置或信任 Hook。", "Checking local Codex records without changes; no Hook setup or trust is required.")
        case .waitingForRecords: copy.text("尚无可读取的任务记录。请在 Codex 中运行一条任务，随后自动连接。", "No readable task records yet. Run a task in Codex to connect automatically.")
        case .ready: copy.text("本地记录可读取；新任务活动到达后显示灵动岛。", "Local records are readable. New task activity will show the island.")
        case .receiving: copy.text("已读取到有效任务活动。空闲时灵动岛可以保持隐藏。", "Valid task activity has been received. The island can stay hidden while idle.")
        case .unreadable: copy.text("请检查目录路径和读取权限，然后重新检查或选择 Codex 数据目录。", "Check the directory path and read permissions, then recheck or choose the Codex data directory.")
        case .unsupported: copy.text("发现不支持的任务元数据结构。可重新检查或手动使用兼容选项。", "An unsupported task metadata structure was found. Recheck or use the optional compatibility setup.")
        case .disabled: copy.text("本地记录自动读取已禁用。", "Automatic local record reading is disabled.")
        }
        if connection.sharedState == .connected, ![.ready, .receiving].contains(connection.localHealth) {
            let connected = copy.text("Codex 本地服务已连接，可接收任务活动。", "The local Codex service is connected and can receive task activity.")
            return connection.localHealth.hasReadError ? connected + " " + localDescription : connected
        }
        return localDescription
    }
}

/// All automatic readers use the same directory environment. Account/quota clients
/// and existing Hook installations are outside this automatic-reader configuration.
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
