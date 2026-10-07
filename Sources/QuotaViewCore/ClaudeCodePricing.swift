import Foundation

/// Token counts reported by one Claude API response in a Claude Code transcript.
public struct ClaudeCodeTokenUsage: Equatable, Sendable {
    public var input: Int64
    public var output: Int64
    public var cacheWrite5m: Int64
    public var cacheWrite1h: Int64
    public var cacheRead: Int64

    public init(input: Int64 = 0, output: Int64 = 0, cacheWrite5m: Int64 = 0,
                cacheWrite1h: Int64 = 0, cacheRead: Int64 = 0) {
        self.input = input; self.output = output
        self.cacheWrite5m = cacheWrite5m; self.cacheWrite1h = cacheWrite1h; self.cacheRead = cacheRead
    }

    public var total: Int64 { input + output + cacheWrite5m + cacheWrite1h + cacheRead }

    public static func + (lhs: Self, rhs: Self) -> Self {
        .init(input: lhs.input + rhs.input, output: lhs.output + rhs.output,
              cacheWrite5m: lhs.cacheWrite5m + rhs.cacheWrite5m,
              cacheWrite1h: lhs.cacheWrite1h + rhs.cacheWrite1h, cacheRead: lhs.cacheRead + rhs.cacheRead)
    }

    /// Decodes an Anthropic `usage` object. Missing counters are zero; a
    /// malformed or negative counter rejects the whole record.
    public init?(usage: [String: Any]) {
        func count(_ key: String, in object: [String: Any] = usage) -> Int64?? {
            guard let value = object[key] else { return .some(nil) }
            guard let number = CodexActivityNumeric.nonnegativeInteger(value) else { return nil }
            return .some(number)
        }
        guard let input = count("input_tokens"), let output = count("output_tokens"),
              let creation = count("cache_creation_input_tokens"), let read = count("cache_read_input_tokens") else { return nil }
        var write5m = creation ?? 0, write1h: Int64 = 0
        if let split = usage["cache_creation"] as? [String: Any],
           let short = count("ephemeral_5m_input_tokens", in: split),
           let long = count("ephemeral_1h_input_tokens", in: split), short != nil || long != nil {
            write5m = short ?? 0; write1h = long ?? 0
        }
        self.init(input: input ?? 0, output: output ?? 0, cacheWrite5m: write5m, cacheWrite1h: write1h, cacheRead: read ?? 0)
    }
}

/// Published Anthropic list prices in USD per million tokens. An unknown model
/// has no estimate rather than a guessed price.
public enum ClaudeCodePricing {
    public struct Rates: Equatable, Sendable {
        public let input: Double, output: Double, cacheWrite5m: Double, cacheWrite1h: Double, cacheRead: Double
        public init(_ input: Double, _ output: Double, _ cacheWrite5m: Double, _ cacheWrite1h: Double, _ cacheRead: Double) {
            self.input = input; self.output = output; self.cacheWrite5m = cacheWrite5m
            self.cacheWrite1h = cacheWrite1h; self.cacheRead = cacheRead
        }
    }

    public static func rates(for model: String) -> Rates? {
        guard let model = ModelIdentity(model) else { return nil }
        let version = model.version
        func atLeast(_ minimum: [Int]) -> Bool {
            for (left, right) in zip(version, minimum) where left != right { return left > right }
            return version.count >= minimum.count
        }
        switch model.family {
        case "fable", "mythos":
            if atLeast([5, 1]) { return .init(10, 50, 12.5, 20, 0.25) }
            if version.first == 5 { return .init(10, 50, 12.5, 20, 1.00) }
        case "opus":
            if atLeast([5, 5]) { return .init(4, 20, 5, 8, 0.20) }
            if atLeast([4, 5]) { return .init(5, 25, 6.25, 10, 0.50) }
            if version.first == 4 || version.first == 3 { return .init(15, 75, 18.75, 30, 1.50) }
        case "sonnet":
            if version.first == 5 { return .init(2, 10, 2.5, 4, 0.20) }
            if version.first == 4 || version.first == 3 { return .init(3, 15, 3.75, 6, 0.30) }
        case "haiku":
            if atLeast([4, 5]) { return .init(1, 5, 1.25, 2, 0.10) }
            if version == [3, 5] { return .init(0.8, 4, 1, 1.6, 0.08) }
        default: break
        }
        return nil
    }

    public static func cost(model: String, usage: ClaudeCodeTokenUsage) -> Double? {
        guard let rates = rates(for: model) else { return nil }
        let total = Double(usage.input) * rates.input + Double(usage.output) * rates.output
            + Double(usage.cacheWrite5m) * rates.cacheWrite5m + Double(usage.cacheWrite1h) * rates.cacheWrite1h
            + Double(usage.cacheRead) * rates.cacheRead
        return total / 1_000_000
    }

    /// `claude-opus-5-5-20260101` → `Opus 5.5`; unrecognized identifiers stay verbatim.
    public static func displayName(for model: String) -> String {
        guard let identity = ModelIdentity(model) else { return model }
        return identity.family.capitalized + " " + identity.version.map(String.init).joined(separator: ".")
    }

    /// `claude-opus-5-5-20260101`,`claude-3-5-haiku-latest` and
    /// `us.anthropic.claude-sonnet-4-5-v1:0` all name a family and version.
    struct ModelIdentity {
        let family: String
        let version: [Int]

        init?(_ raw: String) {
            let lowered = raw.lowercased()
            let tokens = lowered.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            guard let index = tokens.firstIndex(where: { ["fable", "mythos", "opus", "sonnet", "haiku"].contains($0) }) else { return nil }
            func numbers(_ slice: ArraySlice<String>) -> [Int] {
                var result: [Int] = []
                for token in slice {
                    // Dates and provider revisions end the version.
                    guard token.count <= 2, let value = Int(token) else { break }
                    result.append(value)
                }
                return result
            }
            var version = numbers(tokens[(index + 1)...])
            if version.isEmpty {
                // Legacy `claude-3-5-haiku` places the version before the family.
                let before = tokens[..<index].reversed().prefix { $0.count <= 2 && Int($0) != nil }
                version = before.reversed().compactMap { Int($0) }
            }
            guard !version.isEmpty else { return nil }
            family = tokens[index]
            self.version = version
        }
    }
}
