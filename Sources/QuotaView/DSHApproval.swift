import Foundation

/// Complete, bounded arguments live only in transient approval state.
enum DSHApproval {
    static func request(eventID: String, sessionKey: String, turnKey: String,
                        payload: [String: Any]) throws -> IslandCodexApprovalRequest {
        guard let tool = payload["tool_name"] as? String,
              let input = payload["tool_input"] as? [String: Any],
              JSONSerialization.isValidJSONObject(input),
              let call = payload["tool_use_id"] as? String, !call.isEmpty,
              let command = input["command"] as? String, !command.isEmpty else { throw CocoaError(.coderInvalidValue) }
        switch tool {
        case "bash":
            guard Set(input.keys).isSubset(of: ["command", "description", "timeoutMs", "workdir", "run_in_background", "sandbox_permissions", "justification"]),
                  !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CocoaError(.coderInvalidValue) }
        case "str_replace_editor":
            guard Set(input.keys).isSubset(of: ["command", "path", "file_text", "insert_line", "new_str", "old_str", "view_range"]),
                  let path = input["path"] as? String, !path.isEmpty else { throw CocoaError(.coderInvalidValue) }
            switch command {
            case "create": guard input["file_text"] is String else { throw CocoaError(.coderInvalidValue) }
            case "str_replace": guard let old = input["old_str"] as? String, !old.isEmpty,
                input["new_str"] == nil || input["new_str"] is String else { throw CocoaError(.coderInvalidValue) }
            case "insert": guard input["new_str"] is String, let line = input["insert_line"] as? Int, line >= 0 else { throw CocoaError(.coderInvalidValue) }
            default: throw CocoaError(.coderInvalidValue)
            }
        default: throw CocoaError(.coderInvalidValue)
        }
        let data = try JSONSerialization.data(withJSONObject: input, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        guard data.count <= 65_536 else { throw CocoaError(.coderInvalidValue) }
        let reason = payload["reason"] as? String ?? ""
        let cwd = payload["cwd"] as? String ?? ""
        guard reason.utf8.count <= 4096, cwd.utf8.count <= 4096 else { throw CocoaError(.coderInvalidValue) }
        return try IslandCodexApprovalRequest(data: JSONSerialization.data(withJSONObject: [
            "id": "dsh:" + eventID, "method": "item/commandExecution/requestApproval",
            "params": ["dsh": true, "threadId": sessionKey, "turnId": turnKey, "itemId": call,
                "toolName": tool, "command": "cwd: " + cwd + "\n" + String(decoding: data, as: UTF8.self), "cwd": cwd, "reason": reason,
                "availableDecisions": ["accept", "decline", "dshDelegate"]]]))
    }
    static func eventID(of wire: IslandCodexApprovalRequest) -> String? {
        guard wire.isDSH, wire.rpcID.text.hasPrefix("dsh:") else { return nil }
        return String(wire.rpcID.text.dropFirst(4))
    }
}
