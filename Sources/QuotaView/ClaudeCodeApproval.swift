import Foundation
import QuotaViewCore

/// Maps a Claude Code PermissionRequest onto the island's typed request model,
/// and the island's chosen result back onto Claude Code's Hook decision.
enum ClaudeCodeApproval {
    static func request(eventID: String, sessionKey: String, turnKey: String, toolName: String,
                        toolInput: [String: Any], toolUseID: String, cwd: String?,
                        hasSuggestions: Bool) throws -> IslandCodexApprovalRequest {
        var params: [String: Any] = ["threadId": sessionKey, "turnId": turnKey, "itemId": toolUseID, "claudeCode": true]
        if let cwd { params["cwd"] = cwd }
        let method: String
        var context: [String: Any]?
        switch toolName {
        case "AskUserQuestion":
            method = "item/tool/requestUserInput"
            params["questions"] = (toolInput["questions"] as? [[String: Any]] ?? []).map { question -> [String: Any] in
                let text = question["question"] as? String ?? ""
                return ["id": text, "question": text, "header": question["header"] as? String ?? "",
                        "options": (question["options"] as? [[String: Any]] ?? []).map {
                            ["label": $0["label"] as? String ?? "", "description": $0["description"] as? String ?? ""]
                        },
                        "multiSelect": question["multiSelect"] as? Bool ?? false, "isOther": true]
            }
        case "Edit", "MultiEdit", "Write", "NotebookEdit":
            method = "item/fileChange/requestApproval"
            params["availableDecisions"] = decisions(hasSuggestions)
            let path = toolInput["file_path"] as? String ?? toolInput["notebook_path"] as? String ?? ""
            params["reason"] = toolName
            context = ["changes": [["path": path, "diff": diff(toolName, input: toolInput)]]]
        case "Bash":
            method = "item/commandExecution/requestApproval"
            params["availableDecisions"] = decisions(hasSuggestions)
            params["command"] = toolInput["command"] as? String ?? ""
            if let description = toolInput["description"] as? String, !description.isEmpty { params["reason"] = description }
        default:
            method = "item/commandExecution/requestApproval"
            params["availableDecisions"] = decisions(hasSuggestions)
            params["command"] = summary(toolName, input: toolInput)
            params["reason"] = toolName
        }
        let data = try JSONSerialization.data(withJSONObject: ["method": method, "id": "claude:" + eventID, "params": params],
                                              options: [.sortedKeys])
        var wire = try IslandCodexApprovalRequest(data: data)
        if let context { wire.contextItem = try IslandApprovalJSON(any: context) }
        return wire
    }

    static func eventID(of wire: IslandCodexApprovalRequest) -> String? {
        let id = wire.rpcID.text
        return id.hasPrefix("claude:") ? String(id.dropFirst(7)) : nil
    }

    /// Hook `decision` object, or nil for a result the island should not have produced.
    static func decision(for wire: IslandCodexApprovalRequest, result: IslandApprovalJSON,
                         toolInput: [String: Any], suggestions: [Any]) -> [String: Any]? {
        if wire.kind == .questions {
            let answers = result["answers"].object ?? [:]
            guard !answers.isEmpty else {
                return ["behavior": "deny", "message": "The user skipped these questions in QuotaView."]
            }
            var mapped: [String: String] = [:]
            for question in wire.questions {
                guard let answer = answers[question.id]?["answers"].array.first?.text, !answer.isEmpty else { return nil }
                mapped[question.title] = answer
            }
            var updated = toolInput
            updated["answers"] = mapped
            return ["behavior": "allow", "updatedInput": updated]
        }
        switch result["decision"].text {
        case "accept": return ["behavior": "allow"]
        case "acceptAlways": return ["behavior": "allow", "updatedPermissions": suggestions]
        case "acceptForSession":
            return ["behavior": "allow", "updatedPermissions": suggestions.map { suggestion -> Any in
                guard var object = suggestion as? [String: Any] else { return suggestion }
                object["destination"] = "session"
                return object
            }]
        case "decline": return ["behavior": "deny", "message": "The user declined this request in QuotaView."]
        case "cancel": return ["behavior": "deny", "message": "The user cancelled this request in QuotaView.", "interrupt": true]
        default: return nil
        }
    }

    private static func decisions(_ hasSuggestions: Bool) -> [String] {
        ["accept"] + (hasSuggestions ? ["acceptForSession", "acceptAlways"] : []) + ["decline", "cancel"]
    }

    private static func summary(_ toolName: String, input: [String: Any]) -> String {
        for key in ["url", "command", "file_path", "path", "pattern", "query", "prompt", "description"] {
            if let value = input[key] as? String, !value.isEmpty { return toolName + " · " + value }
        }
        guard JSONSerialization.isValidJSONObject(input),
              let data = try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys, .prettyPrinted]) else { return toolName }
        return toolName + "\n" + String(decoding: data.prefix(4_096), as: UTF8.self)
    }

    private static func diff(_ toolName: String, input: [String: Any]) -> String {
        func lines(_ prefix: String, _ text: String) -> String {
            text.split(separator: "\n", omittingEmptySubsequences: false).map { prefix + $0 }.joined(separator: "\n")
        }
        let body: String
        switch toolName {
        case "Edit":
            body = lines("-", input["old_string"] as? String ?? "") + "\n" + lines("+", input["new_string"] as? String ?? "")
        case "MultiEdit":
            body = (input["edits"] as? [[String: Any]] ?? []).map {
                lines("-", $0["old_string"] as? String ?? "") + "\n" + lines("+", $0["new_string"] as? String ?? "")
            }.joined(separator: "\n@@\n")
        case "Write":
            body = lines("+", input["content"] as? String ?? "")
        default:
            body = lines("+", input["new_source"] as? String ?? "")
        }
        return ClaudeCodeTextBound.prefix(body, bytes: 65_536)
    }
}

enum ClaudeCodeTextBound {
    static func prefix(_ value: String, bytes: Int) -> String {
        guard value.utf8.count > bytes else { return value }
        var text = String(decoding: value.utf8.prefix(bytes), as: UTF8.self)
        if text.hasSuffix("\u{FFFD}") { text.removeLast() }
        return text
    }
}
