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
        default: []
        }
    }
    private func hookCommand(_ event: String) -> String {
        quote(helper.path) + " --agent-hook --configuration " + quote(route.path) + " --event " + quote(event)
    }
    private func externalJSON(_ original: Data?, enabled: Bool) throws -> Data? {
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
