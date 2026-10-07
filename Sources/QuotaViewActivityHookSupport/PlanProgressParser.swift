import Foundation

public struct CodexActivitySanitizedPlanProgress: Equatable, Sendable {
    public let completedSteps: Int
    public let inProgressSteps: Int
    public let pendingSteps: Int

    public init(
        completedSteps: Int,
        inProgressSteps: Int,
        pendingSteps: Int
    ) {
        self.completedSteps = completedSteps
        self.inProgressSteps = inProgressSteps
        self.pendingSteps = pendingSteps
    }
}

public enum CodexActivityPlanInputParser {
    private static let maximumSourceBytes = 1_048_576
    private static let wrappedToolNames: Set<String> = [
        "exec",
        "functions.exec",
        "functions__exec"
    ]

    public static func parse(
        toolName: String?,
        toolInput: Any?
    ) -> CodexActivitySanitizedPlanProgress? {
        guard let toolName else { return nil }
        if toolName == "update_plan" {
            return directPlanProgress(from: toolInput)
        }
        guard wrappedToolNames.contains(toolName),
              let source = wrappedSource(from: toolInput),
              source.utf8.count <= maximumSourceBytes
        else {
            return nil
        }
        return JavaScriptPlanScanner(source: source).lastValidPlanProgress()
    }

    private static func directPlanProgress(
        from toolInput: Any?
    ) -> CodexActivitySanitizedPlanProgress? {
        guard let input = toolInput as? [String: Any],
              let plan = input["plan"] as? [[String: Any]],
              (1...100).contains(plan.count)
        else {
            return nil
        }

        var counts = MutablePlanCounts()
        for item in plan {
            guard let status = item["status"] as? String,
                  counts.record(status: status)
            else {
                return nil
            }
        }
        return counts.sanitized
    }

    private static func wrappedSource(from toolInput: Any?) -> String? {
        if let source = toolInput as? String {
            return source
        }
        guard let input = toolInput as? [String: Any] else {
            return nil
        }
        for key in ["input", "source", "code"] {
            if let source = input[key] as? String {
                return source
            }
        }
        return nil
    }
}

private struct MutablePlanCounts {
    var completed = 0
    var inProgress = 0
    var pending = 0

    mutating func record(status: String) -> Bool {
        switch status {
        case "completed": completed += 1
        case "in_progress", "inProgress": inProgress += 1
        case "pending": pending += 1
        default: return false
        }
        return true
    }

    var sanitized: CodexActivitySanitizedPlanProgress {
        CodexActivitySanitizedPlanProgress(
            completedSteps: completed,
            inProgressSteps: inProgress,
            pendingSteps: pending
        )
    }
}

private struct JavaScriptPlanScanner {
    private let bytes: [UInt8]

    init(source: String) {
        bytes = Array(source.utf8)
    }

    func lastValidPlanProgress()
        -> CodexActivitySanitizedPlanProgress?
    {
        var latest: CodexActivitySanitizedPlanProgress?
        var index = 0
        while index < bytes.count {
            if let next = endOfStringOrComment(startingAt: index) {
                index = next
                continue
            }
            if let argumentStart = updatePlanArgumentStart(at: index) {
                var parser = JavaScriptPlanArgumentParser(
                    bytes: bytes,
                    index: argumentStart
                )
                if let counts = parser.parsePlanArgument(),
                   parser.consumeClosingCallParenthesis()
                {
                    latest = counts
                    index = max(parser.index, index + 1)
                    continue
                }
            }
            index += 1
        }
        return latest
    }

    private func updatePlanArgumentStart(at start: Int) -> Int? {
        guard matchesIdentifier("tools", at: start) else {
            return nil
        }
        var cursor = start + 5
        skipTrivia(at: &cursor)
        guard consume(byte: 46, at: &cursor) else { return nil }
        skipTrivia(at: &cursor)
        guard matchesIdentifier("update_plan", at: cursor) else {
            return nil
        }
        cursor += 11
        skipTrivia(at: &cursor)
        guard consume(byte: 40, at: &cursor) else { return nil }
        skipTrivia(at: &cursor)
        return cursor
    }

    private func matchesIdentifier(_ value: String, at index: Int) -> Bool {
        let token = Array(value.utf8)
        guard index >= 0, index + token.count <= bytes.count,
              Array(bytes[index..<(index + token.count)]) == token
        else {
            return false
        }
        if index > 0, Self.isIdentifierByte(bytes[index - 1]) {
            return false
        }
        let end = index + token.count
        if end < bytes.count, Self.isIdentifierByte(bytes[end]) {
            return false
        }
        return true
    }

    private func skipTrivia(at index: inout Int) {
        while index < bytes.count {
            if Self.isWhitespace(bytes[index]) {
                index += 1
                continue
            }
            if bytes[index] == 47, index + 1 < bytes.count {
                if bytes[index + 1] == 47 {
                    index += 2
                    while index < bytes.count,
                          bytes[index] != 10,
                          bytes[index] != 13
                    {
                        index += 1
                    }
                    continue
                }
                if bytes[index + 1] == 42 {
                    index += 2
                    while index + 1 < bytes.count,
                          !(bytes[index] == 42 && bytes[index + 1] == 47)
                    {
                        index += 1
                    }
                    index = min(index + 2, bytes.count)
                    continue
                }
            }
            return
        }
    }

    private func consume(byte: UInt8, at index: inout Int) -> Bool {
        guard index < bytes.count, bytes[index] == byte else {
            return false
        }
        index += 1
        return true
    }

    private func endOfStringOrComment(startingAt index: Int) -> Int? {
        guard index < bytes.count else { return nil }
        let byte = bytes[index]
        if byte == 34 || byte == 39 || byte == 96 {
            var cursor = index + 1
            while cursor < bytes.count {
                if bytes[cursor] == 92 {
                    cursor = min(cursor + 2, bytes.count)
                } else if bytes[cursor] == byte {
                    return cursor + 1
                } else {
                    cursor += 1
                }
            }
            return bytes.count
        }
        guard byte == 47, index + 1 < bytes.count else {
            return nil
        }
        if bytes[index + 1] == 47 {
            var cursor = index + 2
            while cursor < bytes.count,
                  bytes[cursor] != 10,
                  bytes[cursor] != 13
            {
                cursor += 1
            }
            return cursor
        }
        if bytes[index + 1] == 42 {
            var cursor = index + 2
            while cursor + 1 < bytes.count,
                  !(bytes[cursor] == 42 && bytes[cursor + 1] == 47)
            {
                cursor += 1
            }
            return min(cursor + 2, bytes.count)
        }
        return nil
    }

    fileprivate static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 9 || byte == 10 || byte == 13 || byte == 32
    }

    fileprivate static func isIdentifierByte(_ byte: UInt8) -> Bool {
        (byte >= 48 && byte <= 57)
            || (byte >= 65 && byte <= 90)
            || (byte >= 97 && byte <= 122)
            || byte == 95
            || byte == 36
    }
}

private struct JavaScriptPlanArgumentParser {
    let bytes: [UInt8]
    var index: Int

    mutating func parsePlanArgument()
        -> CodexActivitySanitizedPlanProgress?
    {
        skipTrivia()
        guard consume(123) else { return nil }
        var parsedPlan: CodexActivitySanitizedPlanProgress?

        while true {
            skipTrivia()
            if consume(125) {
                return parsedPlan
            }
            guard let key = parsePropertyKey() else { return nil }
            skipTrivia()
            guard consume(58) else { return nil }
            skipTrivia()

            if key == "plan" {
                guard let plan = parsePlanArray() else { return nil }
                parsedPlan = plan
            } else if !skipValue() {
                return nil
            }

            skipTrivia()
            if consume(125) {
                return parsedPlan
            }
            guard consume(44) else { return nil }
        }
    }

    mutating func consumeClosingCallParenthesis() -> Bool {
        skipTrivia()
        return consume(41)
    }

    private mutating func parsePlanArray()
        -> CodexActivitySanitizedPlanProgress?
    {
        guard consume(91) else { return nil }
        var counts = MutablePlanCounts()
        var itemCount = 0

        while true {
            skipTrivia()
            if consume(93) {
                guard (1...100).contains(itemCount) else {
                    return nil
                }
                return counts.sanitized
            }
            guard itemCount < 100,
                  let status = parsePlanItem(),
                  counts.record(status: status)
            else {
                return nil
            }
            itemCount += 1
            skipTrivia()
            if consume(93) {
                return counts.sanitized
            }
            guard consume(44) else { return nil }
        }
    }

    private mutating func parsePlanItem() -> String? {
        guard consume(123) else { return nil }
        var status: String?

        while true {
            skipTrivia()
            if consume(125) {
                return status
            }
            guard let key = parsePropertyKey() else { return nil }
            skipTrivia()
            guard consume(58) else { return nil }
            skipTrivia()
            if key == "status" {
                guard let literal = parseStringLiteral() else {
                    return nil
                }
                status = literal
            } else if !skipValue() {
                return nil
            }
            skipTrivia()
            if consume(125) {
                return status
            }
            guard consume(44) else { return nil }
        }
    }

    private mutating func parsePropertyKey() -> String? {
        skipTrivia()
        guard index < bytes.count else { return nil }
        if bytes[index] == 34 || bytes[index] == 39 {
            return parseStringLiteral()
        }
        guard JavaScriptPlanScanner.isIdentifierByte(bytes[index]),
              !(bytes[index] >= 48 && bytes[index] <= 57)
        else {
            return nil
        }
        let start = index
        index += 1
        while index < bytes.count,
              JavaScriptPlanScanner.isIdentifierByte(bytes[index])
        {
            index += 1
        }
        return String(decoding: bytes[start..<index], as: UTF8.self)
    }

    private mutating func parseStringLiteral() -> String? {
        guard index < bytes.count,
              bytes[index] == 34 || bytes[index] == 39
        else {
            return nil
        }
        let quote = bytes[index]
        index += 1
        var value: [UInt8] = []
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            if byte == quote {
                return String(decoding: value, as: UTF8.self)
            }
            if byte == 92 {
                guard index < bytes.count else { return nil }
                let escaped = bytes[index]
                index += 1
                switch escaped {
                case 34, 39, 47, 92: value.append(escaped)
                case 98: value.append(8)
                case 102: value.append(12)
                case 110: value.append(10)
                case 114: value.append(13)
                case 116: value.append(9)
                default: return nil
                }
            } else {
                value.append(byte)
            }
        }
        return nil
    }

    private mutating func skipValue() -> Bool {
        var stack: [UInt8] = []
        var consumedAny = false
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 34 || byte == 39 || byte == 96 {
                guard skipQuoted(byte) else { return false }
                consumedAny = true
                continue
            }
            if byte == 47, index + 1 < bytes.count {
                if bytes[index + 1] == 47 {
                    skipLineComment()
                    continue
                }
                if bytes[index + 1] == 42 {
                    guard skipBlockComment() else { return false }
                    continue
                }
            }
            if stack.isEmpty, byte == 44 || byte == 125 {
                return consumedAny
            }
            switch byte {
            case 40: stack.append(41)
            case 91: stack.append(93)
            case 123: stack.append(125)
            case 41, 93, 125:
                guard stack.last == byte else { return false }
                stack.removeLast()
            default:
                if !JavaScriptPlanScanner.isWhitespace(byte) {
                    consumedAny = true
                }
            }
            index += 1
        }
        return false
    }

    private mutating func skipTrivia() {
        while index < bytes.count {
            if JavaScriptPlanScanner.isWhitespace(bytes[index]) {
                index += 1
                continue
            }
            if bytes[index] == 47, index + 1 < bytes.count {
                if bytes[index + 1] == 47 {
                    skipLineComment()
                    continue
                }
                if bytes[index + 1] == 42 {
                    guard skipBlockComment() else { return }
                    continue
                }
            }
            return
        }
    }

    private mutating func skipQuoted(_ quote: UInt8) -> Bool {
        index += 1
        while index < bytes.count {
            if bytes[index] == 92 {
                index = min(index + 2, bytes.count)
            } else if bytes[index] == quote {
                index += 1
                return true
            } else {
                index += 1
            }
        }
        return false
    }

    private mutating func skipLineComment() {
        index += 2
        while index < bytes.count,
              bytes[index] != 10,
              bytes[index] != 13
        {
            index += 1
        }
    }

    private mutating func skipBlockComment() -> Bool {
        index += 2
        while index + 1 < bytes.count {
            if bytes[index] == 42, bytes[index + 1] == 47 {
                index += 2
                return true
            }
            index += 1
        }
        return false
    }

    private mutating func consume(_ byte: UInt8) -> Bool {
        guard index < bytes.count, bytes[index] == byte else {
            return false
        }
        index += 1
        return true
    }
}
