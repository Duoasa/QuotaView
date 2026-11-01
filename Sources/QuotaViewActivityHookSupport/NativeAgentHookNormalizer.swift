import Foundation

/// Maps documented hook payloads to a small, observation-only event envelope.
/// Prompts, tool arguments/results, transcripts and credentials never cross IPC.
public enum NativeAgentHookNormalizer {
    public static func normalize(_ object: [String: Any], provider: String, event override: String? = nil) -> [String: Any]? {
        let sourceEvent = override ?? object["hook_event_name"] as? String ?? ""
        let sessionKey = provider == "cursor" ? "conversation_id" : provider == "copilotCLI" ? "sessionId" : "session_id"
        guard let session = object[sessionKey] as? String, !session.isEmpty, session.utf8.count <= 256 else { return nil }
        var name: String?
        switch provider {
        case "cursor":
            switch sourceEvent {
            case "sessionStart": name = "SessionStart"
            case "sessionEnd": name = "SessionEnd"
            case "beforeSubmitPrompt": name = "UserPromptSubmit"
            case "postToolUse": name = "PostToolUse"
            case "postToolUseFailure": name = "PostToolUseFailure"
            case "preCompact": name = "PreCompact"
            case "stop":
                switch object["status"] as? String {
                case "completed": name = "Stop"
                case "error": name = "StopFailure"
                case "aborted": name = "Interrupt"
                default: return nil
                }
            default: return nil
            }
        case "geminiCLI":
            switch sourceEvent {
            case "SessionStart", "SessionEnd": name = sourceEvent
            case "BeforeAgent": name = "UserPromptSubmit"
            case "AfterAgent": name = "Stop"
            case "BeforeModel": name = "Metadata"
            case "BeforeTool": name = "PreToolUse"
            case "AfterTool": name = "PostToolUse"
            case "PreCompress": name = "PreCompact"
            case "Notification":
                guard object["notification_type"] as? String == "ToolPermission" else { return nil }
                name = "PermissionRequest"
            default: return nil
            }
        case "copilotCLI":
            switch sourceEvent {
            case "sessionStart": name = "SessionStart"
            case "sessionEnd": name = "SessionEnd"
            case "userPromptSubmitted": name = "UserPromptSubmit"
            case "preToolUse": name = "PreToolUse"
            case "postToolUse": name = "PostToolUse"
            case "postToolUseFailure": name = "PostToolUseFailure"
            case "agentStop":
                guard object["stopReason"] as? String == "end_turn" else { return nil }
                name = "Stop"
            case "errorOccurred":
                guard object["recoverable"] as? Bool == false else { return nil }
                name = "StopFailure"
            case "preCompact": name = "PreCompact"
            case "notification":
                guard object["notification_type"] as? String == "permission_prompt" else { return nil }
                name = "PermissionRequest"
            default: return nil // A subagent stop must never finish the parent.
            }
        case "kimiCode", "openCode":
            let allowed = ["SessionStart", "SessionEnd", "UserPromptSubmit", "TurnStarted", "PreToolUse", "PostToolUse", "PostToolUseFailure",
                           "PermissionRequest", "PermissionResult", "PreCompact", "PostCompact", "Stop", "StopFailure", "Interrupt", "Metadata"]
            guard allowed.contains(sourceEvent) else { return nil }
            name = sourceEvent
        default: return nil
        }
        guard let name else { return nil }
        var payload: [String: Any] = ["session_id": session, "hook_event_name": name]
        func put(_ key: String, _ value: Any?) {
            if let value = value as? String, !value.isEmpty { payload[key] = String(value.prefix(256)) }
        }
        put("tool_name", object[provider == "copilotCLI" ? "toolName" : "tool_name"])
        for key in ["tool_use_id", "tool_call_id", "model"] { put(key, object[key]) }
        if provider == "cursor" { put("turn_id", object["generation_id"]); put("model", object["model_id"] ?? object["model"]) }
        if provider == "geminiCLI" { put("model", (object["llm_request"] as? [String: Any])?["model"]) }
        if provider == "kimiCode" {
            for key in ["turn_id", "prompt_id", "agent_id", "session_title", "source", "reason"] { put(key, object[key]) }
        }
        if provider == "openCode" {
            for key in ["turn_id", "session_title", "parent_session_id", "source_epoch"] { put(key, object[key]) }
            if let sequence = object["source_sequence"] as? Int, sequence >= 0 { payload["source_sequence"] = sequence }
        }
        return payload
    }

    /// No tool or permission decision. Cursor's prompt hook requires `continue`;
    /// this only declines to veto sending the prompt, never grants tool access.
    public static func neutralOutput(provider: String, event: String?) -> Data? {
        if provider == "cursor", event == "beforeSubmitPrompt" { return Data("{\"continue\":true}\n".utf8) }
        if ["cursor", "geminiCLI", "copilotCLI"].contains(provider) { return Data("{}\n".utf8) }
        return nil
    }
}
