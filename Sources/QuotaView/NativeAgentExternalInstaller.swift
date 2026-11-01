import Darwin
import Foundation
import QuotaViewCore

extension NativeAgentInstaller {
    /// Called under the per-channel/provider installation lock. Only our exact
    /// commands are removed; another application's hooks and preferences survive.
    func configureExternal(enabled: Bool) throws -> [URL] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: home.path) else {
            if enabled { throw Failure.missingInstallation }
            return []
        }
        let destination: URL
        switch provider {
        case .devinDesktop, .devinCLI: destination = home.appendingPathComponent("config.json")
        case .cursor: destination = home.appendingPathComponent("hooks.json")
        case .geminiCLI: destination = home.appendingPathComponent("settings.json")
        case .copilotCLI: destination = home.appendingPathComponent("hooks/" + marker + ".json")
        case .openCode: destination = home.appendingPathComponent("plugins/" + marker + ".js")
        default: throw Failure.invalidConfiguration
        }
        // Do not replace a symlink or another user's file at a managed path.
        let attributes = try? fm.attributesOfItem(atPath: destination.path)
        if let attributes, attributes[.type] as? FileAttributeType != .typeRegular ||
            (attributes[.ownerAccountID] as? NSNumber)?.uint32Value != getuid() {
            throw Failure.invalidConfiguration
        }
        let original = try read(destination)
        let result: Data?
        if provider == .openCode {
            let signature = "// " + marker + "\n"
            if let original, !String(decoding: original, as: UTF8.self).hasPrefix(signature) {
                throw Failure.invalidConfiguration
            }
            result = enabled ? Data((signature + NativeAgentOpenCodePlugin.source
                .replacingOccurrences(of: "__ROUTE_PATH__", with: jsonString(route.path))).utf8) : nil
        } else {
            result = try externalJSON(original, enabled: enabled)
        }
        // Validate everything before writing a route or modifying client config.
        if enabled {
            guard fm.isExecutableFile(atPath: bundledHelper.path) else { throw Failure.missingHelper }
            try privateWrite(Data(contentsOf: bundledHelper), to: helper, mode: 0o700)
            try privateWrite(JSONSerialization.data(withJSONObject: ["version": 1, "socketPath": socketURL.path,
                "authenticationToken": authenticationToken, "interactiveApprovals": false,
                "agentProvider": provider.rawValue], options: [.sortedKeys]), to: route)
        }
        guard original != result else { return enabled ? [home] : [] }
        guard try read(destination) == original else { throw Failure.configurationChanged }
        if let original {
            let hash = String(CodexActivityPrivacy.hashIdentifier(String(decoding: original, as: UTF8.self)).prefix(12))
            // Backups live outside hooks/plugins directories so clients cannot load them.
            let backup = support.appendingPathComponent("configuration-" + hash + ".backup")
            if !fm.fileExists(atPath: backup.path) { try privateWrite(original, to: backup) }
        }
        if let result {
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let permissions = (attributes?[.posixPermissions] as? NSNumber)?.uint16Value ?? 0o600
            try privateWrite(result, to: destination, mode: mode_t(permissions))
        } else if original != nil { try fm.removeItem(at: destination) }
        return enabled ? [home] : []
    }

    private var externalEvents: [String] {
        switch provider {
        // Cursor's preToolUse is a policy hook. Observe post-tool events instead
        // of supplying an allow decision that might change the permission flow.
        case .cursor: ["sessionStart", "sessionEnd", "beforeSubmitPrompt", "postToolUse", "postToolUseFailure", "preCompact", "stop"]
        case .geminiCLI: ["SessionStart", "SessionEnd", "BeforeAgent", "AfterAgent", "BeforeTool", "AfterTool", "BeforeModel", "Notification", "PreCompress"]
        // notification reports an actual prompt; permissionRequest fires before
        // policy evaluation and does not mean the user must approve anything.
        case .copilotCLI: ["sessionStart", "sessionEnd", "userPromptSubmitted", "preToolUse", "postToolUse", "postToolUseFailure", "agentStop", "errorOccurred", "preCompact", "notification"]
        case .devinDesktop, .devinCLI: ["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop", "PostCompaction"]
        default: []
        }
    }
    private func hookCommand(_ event: String) -> String {
        quote(helper.path) + " --agent-hook --configuration " + quote(route.path) + " --event " + quote(event)
    }
    private func externalJSON(_ original: Data?, enabled: Bool) throws -> Data? {
        if provider.isDevin {
            return try DevinHookConfiguration.update(original, commands: Dictionary(uniqueKeysWithValues: externalEvents.map { ($0, hookCommand($0)) }), enabled: enabled)
        }
        var object: [String: Any] = [:]
        if let original {
            guard let parsed = try? JSONSerialization.jsonObject(with: original) as? [String: Any] else {
                throw Failure.invalidConfiguration
            }
            object = parsed
        }
        if let version = object["version"], provider != .geminiCLI, (version as? Int) != 1 {
            throw Failure.invalidConfiguration
        }
        if object["hooks"] != nil && !(object["hooks"] is [String: Any]) { throw Failure.invalidConfiguration }
        var hooks = object["hooks"] as? [String: Any] ?? [:]
        let commands = Set(externalEvents.map(hookCommand))
        for (event, value) in hooks {
            guard let entries = value as? [[String: Any]] else { throw Failure.invalidConfiguration }
            var kept: [[String: Any]] = []
            for var entry in entries {
                if provider == .geminiCLI {
                    guard let children = entry["hooks"] as? [[String: Any]] else { throw Failure.invalidConfiguration }
                    let filtered = children.filter { !commands.contains($0["command"] as? String ?? "") }
                    if filtered.count == children.count { kept.append(entry) }
                    else if !filtered.isEmpty { entry["hooks"] = filtered; kept.append(entry) }
                } else if !commands.contains((entry["command"] ?? entry["bash"]) as? String ?? "") { kept.append(entry) }
            }
            if kept.count != entries.count || provider == .geminiCLI {
                if kept.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = kept }
            }
        }
        // The dedicated Copilot file must not contain foreign hooks or settings.
        if provider == .copilotCLI && (!hooks.isEmpty || !Set(object.keys).subtracting(["version", "hooks"]).isEmpty) {
            throw Failure.invalidConfiguration
        }
        if enabled {
            for event in externalEvents {
                var entries = hooks[event] as? [[String: Any]] ?? []
                switch provider {
                case .geminiCLI:
                    entries.append(["hooks": [["name": marker, "type": "command", "command": hookCommand(event), "timeout": 2000]]])
                case .copilotCLI:
                    entries.append(["type": "command", "bash": hookCommand(event), "timeoutSec": 2])
                default:
                    entries.append(["command": hookCommand(event), "timeout": 2])
                }
                hooks[event] = entries
            }
            object["hooks"] = hooks
            if provider != .geminiCLI { object["version"] = 1 }
        } else {
            if provider == .copilotCLI { return nil }
            if hooks.isEmpty { object.removeValue(forKey: "hooks") } else { object["hooks"] = hooks }
            if original == nil { return nil }
        }
        // Preserve original bytes when the semantic result has not changed.
        if let original, let parsed = try? JSONSerialization.jsonObject(with: original) as? NSDictionary,
           parsed.isEqual(to: object) { return original }
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }
}

/// Edits only QuotaView-owned command nodes. The client's JSONC comments,
/// unknown settings and foreign hook bytes survive enable/disable operations.
private struct DevinHookConfiguration {
    final class Node {
        let range: Range<Int>
        let value: Any
        let members: [String: Node]
        let children: [Node]
        let commas: [Int]
        init(_ range: Range<Int>, _ value: Any, members: [String: Node] = [:], children: [Node] = [], commas: [Int] = []) {
            self.range = range; self.value = value; self.members = members; self.children = children; self.commas = commas
        }
    }
    var bytes: [UInt8]
    var position = 0
    mutating func trivia() throws {
        while position < bytes.count {
            if [9, 10, 13, 32].contains(bytes[position]) { position += 1; continue }
            guard position + 1 < bytes.count, bytes[position] == 47 else { break }
            if bytes[position + 1] == 47 {
                position += 2
                while position < bytes.count && bytes[position] != 10 { position += 1 }
            } else if bytes[position + 1] == 42 {
                position += 2
                while position + 1 < bytes.count && !(bytes[position] == 42 && bytes[position + 1] == 47) { position += 1 }
                guard position + 1 < bytes.count else { throw NativeAgentInstaller.Failure.invalidConfiguration }
                position += 2
            } else { break }
        }
    }
    mutating func parse(depth: Int = 0) throws -> Node {
        try trivia()
        guard depth < 64, position < bytes.count else { throw NativeAgentInstaller.Failure.invalidConfiguration }
        let start = position, opening = bytes[position]
        if opening == 123 || opening == 91 {
            position += 1
            let closing: UInt8 = opening == 123 ? 125 : 93
            var members: [String: Node] = [:], children: [Node] = [], commas: [Int] = []
            try trivia()
            while position < bytes.count && bytes[position] != closing {
                if opening == 123 {
                    let key = try parse(depth: depth + 1)
                    guard let name = key.value as? String, members[name] == nil else { throw NativeAgentInstaller.Failure.invalidConfiguration }
                    try trivia()
                    guard position < bytes.count, bytes[position] == 58 else { throw NativeAgentInstaller.Failure.invalidConfiguration }
                    position += 1
                    members[name] = try parse(depth: depth + 1)
                } else { children.append(try parse(depth: depth + 1)) }
                try trivia()
                guard position < bytes.count else { throw NativeAgentInstaller.Failure.invalidConfiguration }
                if bytes[position] == closing { break }
                guard bytes[position] == 44 else { throw NativeAgentInstaller.Failure.invalidConfiguration }
                commas.append(position); position += 1; try trivia()
            }
            guard position < bytes.count, bytes[position] == closing else { throw NativeAgentInstaller.Failure.invalidConfiguration }
            position += 1
            let value: Any = opening == 123 ? members.mapValues(\.value) : children.map(\.value)
            return Node(start..<position, value, members: members, children: children, commas: commas)
        }
        if opening == 34 {
            position += 1
            while position < bytes.count {
                let byte = bytes[position]; position += 1
                if byte == 34 { break }
                if byte == 92 { position += 1 }
            }
        } else {
            while position < bytes.count && ![9, 10, 13, 32, 44, 93, 125, 47].contains(bytes[position]) { position += 1 }
        }
        guard position <= bytes.count, position > start,
              let value = try? JSONSerialization.jsonObject(with: Data(bytes[start..<position]), options: .fragmentsAllowed)
        else { throw NativeAgentInstaller.Failure.invalidConfiguration }
        return Node(start..<position, value)
    }
    static func document(_ bytes: [UInt8]) throws -> Node {
        var parser = Self(bytes: bytes)
        let root = try parser.parse()
        try parser.trivia()
        guard parser.position == bytes.count, root.value is [String: Any] else { throw NativeAgentInstaller.Failure.invalidConfiguration }
        return root
    }
    static func update(_ original: Data?, commands: [String: String], enabled: Bool) throws -> Data? {
        var bytes = Array(original ?? Data("{}".utf8))
        var root = try document(bytes)
        let owned = Set(commands.values)
        var removals: [Range<Int>] = [], counts: [String: Int] = [:]
        func remove(_ indices: Set<Int>, from array: Node) {
            guard !indices.isEmpty else { return }
            for index in indices { removals.append(array.children[index].range) }
            let kept = array.children.indices.filter { !indices.contains($0) }
            for (index, comma) in array.commas.enumerated() where indices.contains(index) || index == kept.last {
                removals.append(comma..<(comma + 1))
            }
        }
        if let hooks = root.members["hooks"] {
            guard hooks.value is [String: Any] else { throw NativeAgentInstaller.Failure.invalidConfiguration }
            for (event, array) in hooks.members {
                guard array.value is [Any] else { throw NativeAgentInstaller.Failure.invalidConfiguration }
                var removedEntries: Set<Int> = []
                for (index, entry) in array.children.enumerated() {
                    guard entry.value is [String: Any], let children = entry.members["hooks"], children.value is [Any],
                          children.children.allSatisfy({ $0.value is [String: Any] }) else { throw NativeAgentInstaller.Failure.invalidConfiguration }
                    let indices = Set(children.children.indices.filter {
                        guard let command = children.children[$0].members["command"]?.value as? String else { return false }
                        if owned.contains(command) { counts[event, default: 0] += 1; return true }
                        return false
                    })
                    if !indices.isEmpty && indices.count == children.children.count { removedEntries.insert(index) }
                    else { remove(indices, from: children) }
                }
                remove(removedEntries, from: array)
            }
        }
        if enabled && commands.keys.allSatisfy({ counts[$0] == 1 }) && counts.values.reduce(0, +) == commands.count { return original }
        if !enabled && removals.isEmpty { return original }
        for range in removals.sorted(by: { $0.lowerBound > $1.lowerBound }) { bytes.removeSubrange(range) }
        if enabled {
            // Reparse after removal so insertion offsets and commas are exact.
            root = try document(bytes)
            func encoded(_ value: Any) throws -> String {
                String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]), as: UTF8.self)
            }
            let entries = commands.mapValues { ["hooks": [["type": "command", "command": $0, "timeout": 2]]] as [String: Any] }
            var insertions: [(Int, String)] = []
            func append(_ content: String, to node: Node, hasValues: Bool) {
                // An existing trailing comma is legal JSONC; reuse it.
                let needsComma = hasValues && node.commas.count < (node.value is [String: Any] ? node.members.count : node.children.count)
                insertions.append((node.range.upperBound - 1, (needsComma ? "," : "") + "\n" + content + "\n"))
            }
            if let hooks = root.members["hooks"] {
                var missing: [String] = []
                for event in commands.keys.sorted() {
                    if let array = hooks.members[event] { append(try encoded(entries[event]!), to: array, hasValues: !array.children.isEmpty) }
                    else { missing.append(try encoded(event) + ": [" + encoded(entries[event]!) + "]") }
                }
                if !missing.isEmpty { append(missing.joined(separator: ",\n"), to: hooks, hasValues: !hooks.members.isEmpty) }
            } else {
                append("\"hooks\": " + (try encoded(entries.mapValues { [$0] })), to: root, hasValues: !root.members.isEmpty)
            }
            for (offset, text) in insertions.sorted(by: { $0.0 > $1.0 }) { bytes.insert(contentsOf: text.utf8, at: offset) }
        }
        _ = try document(bytes)
        return Data(bytes)
    }
}
