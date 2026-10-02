import Foundation

/// Public rollout material only. User prompts and private reasoning never cross this boundary.
public struct CodexLocalPublicContent: Sendable {
    public let sessionHash: String
    public let turnHash: String
    public let data: Data
    public let occurredAt: Date

    static func decode(_ line: Data, sessionHash: String, activeTurnHash: String?, asynchronousQuestionCallIDs: Set<String> = []) -> Self? {
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
                if CodexLocalQuestionContent.isQuestionTool(name),
                   !id.isEmpty, id.utf8.count <= 1024,
                   let questions = CodexLocalQuestionContent.questions(payload) {
                    clean = ["type": "questionRequest", "id": id, "questions": questions, "asynchronous": CodexLocalQuestionContent.isAsynchronous(name)]
                    break
                }
                clean = ["type": "tool", "id": id, "name": name,
                         "text": payload["arguments"] as? String ?? payload["input"] as? String ?? ""]
            case "function_call_output", "custom_tool_call_output":
                guard let id = payload["call_id"] as? String else { return nil }
                let output: String
                if let value = payload["output"] as? String { output = value }
                else if let value = payload["output"], let encoded = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
                        let text = String(data: encoded, encoding: .utf8) { output = text }
                else { return nil }
                clean = ["type": "output", "id": id, "text": output, "asynchronous": asynchronousQuestionCallIDs.contains(id)]
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


/// Only the documented, public question fields cross the observation boundary.
/// This projection carries a call ID, not an app-server response capability.
enum CodexLocalQuestionContent {
    static func isQuestionTool(_ name: String) -> Bool {
        ["request_user_input", "request_user_input_async"].contains(name.split(separator: ".").last.map(String.init) ?? "")
    }

    static func isAsynchronous(_ name: String) -> Bool {
        name.split(separator: ".").last == "request_user_input_async"
    }

    static func questions(_ payload: [String: Any]) -> [[String: Any]]? {
        guard let raw = payload["arguments"] as? String ?? payload["input"] as? String,
              raw.utf8.count <= 131_072, let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let values = object["questions"] as? [[String: Any]], (1...32).contains(values.count)
        else { return nil }
        var ids = Set<String>()
        var result: [[String: Any]] = []
        func valid(_ value: String) -> Bool { value.utf8.count <= 16_384 }
        let asynchronous = (payload["name"] as? String).map(isAsynchronous) == true
        for (index, value) in values.enumerated() {
            // Async questions use title/string choices and have no response IDs.
            // The generated index identifies only this local call's presentation.
            let id = value["id"] as? String ?? (asynchronous ? "question-\(index + 1)" : "")
            let question = (asynchronous ? value["title"] : value["question"]) as? String ?? ""
            guard !id.isEmpty, valid(id), ids.insert(id).inserted, !question.isEmpty, valid(question)
            else { return nil }
            var clean: [String: Any] = ["id": id, "question": question]
            if let header = value["header"] as? String {
                guard valid(header) else { return nil }; clean["header"] = header
            }
            if let options = value["options"] {
                var cleaned: [[String: String]] = []
                if asynchronous {
                    guard let labels = options as? [String], labels.count <= 32,
                          labels.allSatisfy({ !$0.isEmpty && valid($0) }) else { return nil }
                    cleaned = labels.map { ["label": $0] }
                } else {
                    guard let options = options as? [[String: Any]], options.count <= 32 else { return nil }
                    for option in options {
                        guard let label = option["label"] as? String, !label.isEmpty, valid(label) else { return nil }
                        var item = ["label": label]
                        if let description = option["description"] as? String {
                            guard valid(description) else { return nil }; item["description"] = description
                        }
                        cleaned.append(item)
                    }
                }
                clean["options"] = cleaned
            }
            for flag in ["isOther", "isSecret"] {
                if let enabled = value[flag] as? Bool { clean[flag] = enabled }
            }
            result.append(clean)
        }
        return result
    }
}
