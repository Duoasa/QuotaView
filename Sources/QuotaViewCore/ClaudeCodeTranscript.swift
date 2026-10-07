import Darwin
import Foundation

/// A privacy-bounded projection of one Claude Code transcript line.
public enum ClaudeCodeTranscriptRecord: Equatable, Sendable {
    case customTitle(String)
    case summary(String)
    /// A typed user prompt. Tool results, meta and interrupt markers are excluded.
    case userPrompt(String)
    case interrupted
    case assistantText(messageID: String, text: String)
    case toolUse(id: String, name: String, input: String)
    case toolResult(toolUseID: String, text: String, isError: Bool)
    case usage(key: String, model: String, usage: ClaudeCodeTokenUsage, timestamp: Date?)
}

public enum ClaudeCodeTranscriptDecoder {
    public static let maximumLineBytes = 4_194_304
    static let maximumTextBytes = 65_536

    /// Main-thread records only; sidechain (subagent) lines belong to the agent transcript.
    public static func records(_ line: Data, includeSidechain: Bool = false) -> [ClaudeCodeTranscriptRecord] {
        guard !line.isEmpty, line.count <= maximumLineBytes,
              let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              let type = object["type"] as? String else { return [] }
        if !includeSidechain, object["isSidechain"] as? Bool == true { return [] }
        switch type {
        case "custom-title":
            return text(object["customTitle"] ?? object["title"]).map { [.customTitle($0)] } ?? []
        case "summary":
            return text(object["summary"]).map { [.summary($0)] } ?? []
        case "user":
            return userRecords(object)
        case "assistant":
            return assistantRecords(object)
        default:
            return []
        }
    }

    private static func userRecords(_ object: [String: Any]) -> [ClaudeCodeTranscriptRecord] {
        guard let message = object["message"] as? [String: Any] else { return [] }
        let meta = object["isMeta"] as? Bool == true || object["isCompactSummary"] as? Bool == true
        if let content = message["content"] as? String {
            if isInterrupt(content) { return [.interrupted] }
            guard !meta, !isCommandEnvelope(content), let prompt = text(content) else { return [] }
            return [.userPrompt(prompt)]
        }
        var records: [ClaudeCodeTranscriptRecord] = []
        var promptParts: [String] = []
        for part in message["content"] as? [[String: Any]] ?? [] {
            switch part["type"] as? String {
            case "tool_result":
                guard let id = part["tool_use_id"] as? String, !id.isEmpty else { continue }
                records.append(.toolResult(toolUseID: id, text: bounded(resultText(part["content"])),
                                           isError: part["is_error"] as? Bool == true))
            case "text":
                guard let value = part["text"] as? String else { continue }
                if isInterrupt(value) { records.append(.interrupted) }
                else if !meta, !isCommandEnvelope(value) { promptParts.append(value) }
            default: continue
            }
        }
        if let prompt = text(promptParts.joined(separator: "\n")) { records.insert(.userPrompt(prompt), at: 0) }
        return records
    }

    private static func assistantRecords(_ object: [String: Any]) -> [ClaudeCodeTranscriptRecord] {
        guard let message = object["message"] as? [String: Any] else { return [] }
        let messageID = message["id"] as? String ?? object["uuid"] as? String ?? ""
        var records: [ClaudeCodeTranscriptRecord] = []
        var texts: [String] = []
        for part in message["content"] as? [[String: Any]] ?? [] {
            switch part["type"] as? String {
            case "text":
                if let value = part["text"] as? String, !value.isEmpty { texts.append(value) }
            case "tool_use":
                guard let id = part["id"] as? String, !id.isEmpty, let name = part["name"] as? String else { continue }
                let input: String
                if let value = part["input"], JSONSerialization.isValidJSONObject(["v": value]),
                   let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed]) {
                    input = bounded(String(decoding: data, as: UTF8.self))
                } else { input = "" }
                records.append(.toolUse(id: id, name: name, input: input))
            default: continue // Thinking blocks are private reasoning.
            }
        }
        // One response streams as several lines; each line's uuid names its own blocks.
        let textID = object["uuid"] as? String ?? messageID
        if !textID.isEmpty, let joined = text(texts.joined(separator: "\n"), limit: maximumTextBytes) {
            records.insert(.assistantText(messageID: textID, text: joined), at: 0)
        }
        let model = message["model"] as? String ?? ""
        if let usageObject = message["usage"] as? [String: Any], let usage = ClaudeCodeTokenUsage(usage: usageObject),
           model != "<synthetic>" {
            // Streaming repeats one response's usage on several lines.
            let request = object["requestId"] as? String ?? ""
            let key = messageID.isEmpty && request.isEmpty ? "" : messageID + ":" + request
            if !key.isEmpty { records.append(.usage(key: key, model: model, usage: usage, timestamp: timestamp(object["timestamp"]))) }
        }
        return records
    }

    static func timestamp(_ value: Any?) -> Date? {
        guard let raw = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }

    private static func resultText(_ value: Any?) -> String {
        if let text = value as? String { return text }
        return (value as? [[String: Any]] ?? []).compactMap { part in
            part["type"] as? String == "text" ? part["text"] as? String : nil
        }.joined(separator: "\n")
    }

    static func isInterrupt(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[Request interrupted by user")
    }

    private static func isCommandEnvelope(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return ["<command-name>", "<command-message>", "<local-command-", "<bash-input>", "<bash-stdout>",
                "<bash-stderr>", "<system-reminder>", "<user-prompt-submit-hook>", "Caveat:"].contains { trimmed.hasPrefix($0) }
    }

    private static func text(_ value: Any?, limit: Int = 4_096) -> String? {
        guard let raw = value as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : bounded(trimmed, limit: limit)
    }

    static func bounded(_ value: String, limit: Int = maximumTextBytes) -> String {
        guard value.utf8.count > limit else { return value }
        var prefix = String(decoding: value.utf8.prefix(limit), as: UTF8.self)
        // A cut inside a multi-byte scalar decodes as one replacement character.
        if prefix.hasSuffix("\u{FFFD}") { prefix.removeLast() }
        return prefix
    }
}

/// Reads appended JSONL lines from one private, regular transcript file.
/// A truncated or replaced file restarts at its beginning.
public struct ClaudeCodeTranscriptTail: Sendable {
    public let path: String
    public private(set) var offset: UInt64
    private var partial = Data()
    private var identity: (device: dev_t, inode: ino_t)?

    public init(path: String, offset: UInt64 = 0) {
        self.path = path
        self.offset = offset
    }

    public static func fileSize(_ path: String) -> UInt64? {
        var metadata = stat()
        guard stat(path, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG, metadata.st_uid == getuid() else { return nil }
        return UInt64(metadata.st_size)
    }

    /// Up to `maximumBytes` of complete lines. Lines larger than the decoder
    /// budget are skipped rather than buffered without bound.
    public mutating func readLines(maximumBytes: Int = 4_194_304) -> [Data] {
        let descriptor = Darwin.open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return [] }
        defer { Darwin.close(descriptor) }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0, metadata.st_uid == getuid(),
              metadata.st_mode & S_IFMT == S_IFREG else { return [] }
        let size = UInt64(metadata.st_size)
        if let identity, identity.device != metadata.st_dev || identity.inode != metadata.st_ino {
            offset = 0; partial.removeAll()
        }
        identity = (metadata.st_dev, metadata.st_ino)
        if size < offset { offset = 0; partial.removeAll() }
        guard size > offset, lseek(descriptor, off_t(offset), SEEK_SET) >= 0 else { return [] }
        var remaining = Int(min(UInt64(maximumBytes), size - offset))
        var buffer = [UInt8](repeating: 0, count: 65_536)
        var lines: [Data] = []
        while remaining > 0 {
            let count = Darwin.read(descriptor, &buffer, min(buffer.count, remaining))
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { break }
            offset += UInt64(count); remaining -= count
            var start = 0
            for index in 0..<count where buffer[index] == 0x0A {
                if partial.count <= ClaudeCodeTranscriptDecoder.maximumLineBytes {
                    partial.append(contentsOf: buffer[start..<index])
                    if partial.count <= ClaudeCodeTranscriptDecoder.maximumLineBytes, !partial.isEmpty { lines.append(partial) }
                }
                partial = Data(); start = index + 1
            }
            if start < count, partial.count <= ClaudeCodeTranscriptDecoder.maximumLineBytes {
                partial.append(contentsOf: buffer[start..<count])
            }
        }
        return lines
    }

    /// The first bytes, for title discovery without replaying a long history.
    public static func headLines(_ path: String, maximumBytes: Int = 262_144) -> [Data] {
        var tail = ClaudeCodeTranscriptTail(path: path)
        return tail.readLines(maximumBytes: maximumBytes)
    }
}
