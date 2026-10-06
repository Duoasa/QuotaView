import Foundation
import CoreFoundation

/// One transient JSON decode and timestamp parse feeds both lifecycle and the
/// privacy-filtered public projection. Raw envelopes are never retained in replay.
struct CodexLocalRolloutEnvelope {
    let line: Data
    let object: [String: Any]
    let payload: [String: Any]
    let type: String
    let timestamp: Date?

    init?(_ line: Data) {
        guard !line.isEmpty, line.count <= CodexLocalRolloutLineDecoder.maximumLineBytes,
              let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              let payload = object["payload"] as? [String: Any], let type = object["type"] as? String else { return nil }
        self.line = line; self.object = object; self.payload = payload; self.type = type
        if let raw = object["timestamp"] as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            timestamp = formatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
        } else { timestamp = nil }
    }
}

/// Public rollout material only. Ordinary user prompts and private reasoning never cross this boundary.
/// Accepted native question replies carry only identity and question hashes for settlement.
public struct CodexLocalPublicContent: Sendable {
    public let sessionHash: String
    public let turnHash: String
    public let data: Data
    public let occurredAt: Date
    // Scalar projection tags avoid decoding our own sanitized JSON for replay.
    var projectionKind: String? = nil
    var projectionCallID: String? = nil

    static func decode(_ line: Data, sessionHash: String, activeTurnHash: String?, asynchronousQuestionCallIDs: Set<String> = []) -> Self? {
        guard let envelope = CodexLocalRolloutEnvelope(line) else { return nil }
        return decode(envelope, sessionHash: sessionHash, activeTurnHash: activeTurnHash,
                      asynchronousQuestionCallIDs: asynchronousQuestionCallIDs)
    }

    static func decode(_ envelope: CodexLocalRolloutEnvelope, sessionHash: String, activeTurnHash: String?, asynchronousQuestionCallIDs: Set<String> = []) -> Self? {
        guard let activeTurnHash else { return nil }
        let type = envelope.type, payload = envelope.payload
        var clean: [String: Any]
        if type == "turn_context" {
            guard let turn = payload["turn_id"] as? String,
                  CodexActivityPrivacy.hashIdentifier(turn) == activeTurnHash else { return nil }
            clean = ["type": "metadata", "model": payload["model"] as? String ?? "",
                     "effort": payload["effort"] as? String ?? payload["reasoning_effort"] as? String ?? ""]
        } else if type == "response_item" {
            switch payload["type"] as? String {
            case "message":
                if payload["role"] as? String == "user" {
                    guard let replies = CodexLocalAsyncReplyContent.proofs(payload) else { return nil }
                    clean = ["type": "questionReply", "replies": replies]
                    break
                }
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
                    clean = ["type": "questionRequest", "id": id, "questions": questions, "userInputMode": CodexUserInputMode.forToolName(name)!.rawValue, "asynchronous": CodexLocalQuestionContent.isAsynchronous(name)]
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
        let date = envelope.timestamp ?? .distantPast
        if clean["id"] == nil { clean["id"] = CodexActivityPrivacy.hashIdentifier(String(decoding: envelope.line, as: UTF8.self)) }
        guard let data = try? JSONSerialization.data(withJSONObject: clean, options: [.sortedKeys]) else { return nil }
        return .init(sessionHash: sessionHash, turnHash: activeTurnHash, data: data, occurredAt: date,
                     projectionKind: clean["type"] as? String, projectionCallID: clean["id"] as? String)
    }
}


/// Only the documented, public question fields cross the observation boundary.
/// This projection carries a call ID, not an app-server response capability.
enum CodexLocalQuestionContent {
    static func isQuestionTool(_ name: String) -> Bool { CodexUserInputMode.forToolName(name) != nil }
    static func isAsynchronous(_ name: String) -> Bool { CodexUserInputMode.forToolName(name) == .asynchronous }

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
            // The native async panel always accepts a custom response. Its
            // title/string-choice schema does not carry a synchronous isOther flag.
            if asynchronous { clean["isOther"] = true }
            result.append(clean)
        }
        return result
    }
}

/// Only a complete native reply envelope can settle an already observed async
/// question. Neither its answer nor the surrounding user message is published.
public enum CodexLocalAsyncReplyContent {
    public static func identityHash(source: String, index: Int) -> String? {
        guard !source.isEmpty, source.utf8.count <= 1024, (0..<32).contains(index),
              let data = try? JSONSerialization.data(withJSONObject: ["request_user_input_async", source, index],
                  options: [.fragmentsAllowed, .withoutEscapingSlashes]),
              let identity = String(data: data, encoding: .utf8) else { return nil }
        return CodexActivityPrivacy.hashIdentifier(identity)
    }
    static func proofs(_ payload: [String: Any]) -> [[String: String]]? {
        guard let content = payload["content"] as? [[String: Any]], content.count == 1,
              ["input_text", "text"].contains(content[0]["type"] as? String ?? ""),
              let text = content[0]["text"] as? String, text.utf8.count <= 131_072 else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let opening = CodexDesktopRequestProjector.asyncReplyOpeningTag
        let closing = CodexDesktopRequestProjector.asyncReplyClosingTag
        guard trimmed.hasPrefix(opening), trimmed.hasSuffix(closing),
              let decoded = try? JSONSerialization.jsonObject(with: Data(trimmed.dropFirst(opening.count).dropLast(closing.count).utf8)) else { return nil }
        let values: [[String: Any]]
        if let array = decoded as? [[String: Any]] { values = array }
        else if let object = decoded as? [String: Any] { values = [object] }
        else { return nil }
        guard (1...32).contains(values.count) else { return nil }
        var seen = Set<String>(), result: [[String: String]] = []
        for value in values {
            guard let identity = value["questionItemId"] as? String, identity.utf8.count <= 2048,
                  let tuple = try? JSONSerialization.jsonObject(with: Data(identity.utf8)) as? [Any], tuple.count == 3,
                  tuple[0] as? String == "request_user_input_async", let source = tuple[1] as? String,
                  let index = tuple[2] as? NSNumber, CFGetTypeID(index) != CFBooleanGetTypeID(),
                  index.doubleValue == Double(index.intValue), let id = identityHash(source: source, index: index.intValue),
                  CodexActivityPrivacy.hashIdentifier(identity) == id,
                  seen.insert(id).inserted, let question = value["question"] as? String,
                  !question.isEmpty, question.utf8.count <= 16_384, let answer = value["answer"] as? String,
                  !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, answer.utf8.count <= 65_536 else { return nil }
            result.append(["questionItemHash": id, "questionHash": CodexActivityPrivacy.hashIdentifier(question)])
        }
        return result
    }
}
