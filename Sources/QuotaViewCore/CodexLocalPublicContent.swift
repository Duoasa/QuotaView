import Foundation

/// Public rollout material only. User prompts and private reasoning never cross this boundary.
public struct CodexLocalPublicContent: Sendable {
    public let sessionHash: String
    public let turnHash: String
    public let data: Data
    public let occurredAt: Date

    static func decode(_ line: Data, sessionHash: String, activeTurnHash: String?) -> Self? {
        guard let activeTurnHash, line.count <= 1_048_576,
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = object["type"] as? String,
              let payload = object["payload"] as? [String: Any] else { return nil }
        var clean: [String: Any]
        if type == "turn_context" {
            guard let turn = payload["turn_id"] as? String,
                  CodexActivityPrivacy.hashIdentifier(turn) == activeTurnHash else { return nil }
            clean = ["type": "metadata", "model": payload["model"] as? String ?? "",
                     "effort": payload["effort"] as? String ?? payload["reasoning_effort"] as? String ?? ""]
        } else if type == "response_item" {
            switch payload["type"] as? String {
            case "message":
                guard payload["role"] as? String == "assistant",
                      ["commentary", "final"].contains(payload["channel"] as? String ?? "final") else { return nil }
                let content = (payload["content"] as? [[String: Any]] ?? []).compactMap { part -> String? in
                    guard ["output_text", "text"].contains(part["type"] as? String ?? "") else { return nil }
                    return part["text"] as? String
                }.joined(separator: "\n")
                guard !content.isEmpty else { return nil }
                clean = ["type": "message", "text": content, "channel": payload["channel"] as? String ?? "final"]
            case "function_call", "custom_tool_call":
                guard let id = payload["call_id"] as? String, let name = payload["name"] as? String else { return nil }
                clean = ["type": "tool", "id": id, "name": name,
                         "text": payload["arguments"] as? String ?? payload["input"] as? String ?? ""]
            case "function_call_output", "custom_tool_call_output":
                guard let id = payload["call_id"] as? String else { return nil }
                let output: String
                if let value = payload["output"] as? String { output = value }
                else if let value = payload["output"], let encoded = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
                        let text = String(data: encoded, encoding: .utf8) { output = text }
                else { return nil }
                clean = ["type": "output", "id": id, "text": output]
            default: return nil
            }
        } else { return nil }
        let date = (object["timestamp"] as? String).flatMap {
            let format = ISO8601DateFormatter(); format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return format.date(from: $0) ?? ISO8601DateFormatter().date(from: $0)
        } ?? .distantPast
        if clean["id"] == nil { clean["id"] = CodexActivityPrivacy.hashIdentifier(String(decoding: line, as: UTF8.self)) }
        guard let data = try? JSONSerialization.data(withJSONObject: clean, options: [.sortedKeys]) else { return nil }
        return .init(sessionHash: sessionHash, turnHash: activeTurnHash, data: data, occurredAt: date)
    }
}
