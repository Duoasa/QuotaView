import CryptoKit
import Foundation

/// Pure wire-compatible rules shared by the short-lived hook and Core.
/// No domain model, transport capability, account state or user body is exposed.
public enum CodexActivityPrivacyRules {
    /// Compatibility for already installed definitions that omitted --queue.
    /// An unknown socket cannot silently route into a stable writable queue.
    public static func legacyQueuePath(socketPath: String, applicationSupportPath: String?, userID: UInt32) -> String? {
        guard let applicationSupportPath else { return nil }
        let base = URL(fileURLWithPath: applicationSupportPath).standardizedFileURL
        let channels = [("QuotaView", "com.quotaview"), ("QuotaView-073-Development", "com.quotaview.development073")]
        for (directory, identifier) in channels {
            if socketPath == base.appendingPathComponent(directory).appendingPathComponent("codex-activity.sock").path {
                return "/tmp/\(identifier).codex-activity-\(userID)"
            }
        }
        return nil
    }

    public static func hashIdentifier(_ identifier: String) -> String {
        SHA256.hash(data: Data(identifier.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public static func workspaceName(from path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        let name = URL(fileURLWithPath: path).standardizedFileURL.lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : String(name.prefix(80))
    }

    public static func toolCategoryRawValue(for name: String?) -> String? {
        guard let name, !name.isEmpty else { return nil }
        if name == "Bash" || name == "exec_command" { return "shell" }
        if ["apply_patch", "Edit", "Write"].contains(name) { return "fileEdit" }
        if name == "Agent" || name == "spawn_agent" || name.contains("subagent") { return "subagent" }
        if ["create_goal", "get_goal", "update_goal"].contains(name)
            || name.hasSuffix("__create_goal") || name.hasSuffix("__get_goal")
            || name.hasSuffix("__update_goal") { return "goal" }
        if name.hasPrefix("mcp__") { return "mcp" }
        return "localTool"
    }
}
