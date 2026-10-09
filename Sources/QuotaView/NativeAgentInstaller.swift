import AppKit
import Darwin
import Foundation
import QuotaViewCore

/// Owns only QuotaView's marked integration blocks. Other tools' hooks remain intact.
struct NativeAgentInstaller: Sendable {
    let provider: IslandAgentProvider
    let socketURL: URL
    let authenticationToken: String
    let home: URL
    let support: URL
    let bundledHelper: URL

    init(provider: IslandAgentProvider, socketURL: URL, authenticationToken: String) {
        self.provider = provider; self.socketURL = socketURL; self.authenticationToken = authenticationToken
        let environment = ProcessInfo.processInfo.environment
        let userHome = FileManager.default.homeDirectoryForCurrentUser
        let key = provider == .dsh ? "DSH_HOME" : "KIMI_CODE_HOME"
        home = environment[key].flatMap {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil
                : URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath).resolvingSymlinksInPath()
        }
            ?? userHome.appendingPathComponent(provider == .dsh ? ".dsh" : ".kimi-code")
        support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("QuotaView/Channels/" + ClaudeCodeChannel.identifier + "/" + provider.rawValue)
        bundledHelper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/QuotaViewActivityHook")
    }

    var route: URL { support.appendingPathComponent("route.json") }
    var helper: URL { support.appendingPathComponent("QuotaViewActivityHook") }
    var plugin: URL { support.appendingPathComponent("quotaview-dsh.mjs") }
    var marker: String { "quotaview-" + ClaudeCodeChannel.identifier + "-" + provider.rawValue }
    private var begin: String { "# >>> " + marker + " >>>" }
    private var end: String { "# <<< " + marker + " <<<" }

    enum Failure: Error { case missingInstallation, invalidConfiguration, configurationChanged, missingHelper, listenerUnavailable }

    /// Returns the homes configured during this pass. The ledger also remembers
    /// earlier profiles so disabling can remove our block after a client moves.
    func configure(enabled: Bool, additionalHomes: [URL] = []) throws -> [URL] {
        let fm = FileManager.default
        try fm.createDirectory(at: support, withIntermediateDirectories: true)
        chmod(support.path, 0o700)
        let lock = Darwin.open(support.appendingPathComponent("install.lock").path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard lock >= 0 else { throw Failure.invalidConfiguration }
        defer { flock(lock, LOCK_UN); Darwin.close(lock) }
        guard flock(lock, LOCK_EX) == 0 else { throw Failure.invalidConfiguration }
        let discovered = configurationFiles(additionalHomes: additionalHomes)
        let ledger = support.appendingPathComponent("installed-profiles.json")
        let recorded: [String]
        if provider == .dsh, let data = try read(ledger) {
            guard let paths = try? JSONDecoder().decode([String].self, from: data), paths.count <= 512,
                  paths.allSatisfy({ $0.hasPrefix("/") && URL(fileURLWithPath: $0).lastPathComponent == "cordis.patch.yml" })
            else { throw Failure.invalidConfiguration }
            recorded = paths
        } else { recorded = [] }
        let currentPaths = Set(discovered.map { $0.path.path })
        guard Set(recorded).union(currentPaths).count <= 512 else { throw Failure.invalidConfiguration }
        let stale = recorded.filter { !currentPaths.contains($0) && fm.fileExists(atPath: $0) }
            .map { Destination(path: URL(fileURLWithPath: $0), home: URL(fileURLWithPath: $0).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()) }
        let destinations = discovered + stale
        if enabled {
            guard !discovered.isEmpty else { throw Failure.missingInstallation }
            guard fm.isExecutableFile(atPath: bundledHelper.path) else { throw Failure.missingHelper }
            try privateWrite(Data(contentsOf: bundledHelper), to: helper, mode: 0o700)
            let data = try JSONSerialization.data(withJSONObject: ["version": 1, "socketPath": socketURL.path,
                "authenticationToken": authenticationToken, "interactiveApprovals": false, "agentProvider": provider.rawValue], options: [.sortedKeys])
            try privateWrite(data, to: route)
            if provider == .dsh {
                let source = NativeAgentDSHPlugin.source.replacingOccurrences(of: "__ROUTE_PATH__", with: jsonString(route.path))
                try privateWrite(Data(source.utf8), to: plugin)
            }
        }
        // Prepare every edit before changing a profile. No partial update for malformed input.
        let edits = try destinations.map { destination -> (URL, Data?, String) in
            let path = destination.path
            let original = try read(path)
            let text = original.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            if original != nil && String(data: original!, encoding: .utf8) == nil { throw Failure.invalidConfiguration }
            var result = try removingBlock(text)
            if enabled && currentPaths.contains(path.path) {
                if provider == .kimiCode && result.range(of: #"(?m)^\s*hooks\s*="# , options: .regularExpression) != nil {
                    throw Failure.invalidConfiguration
                }
                // A standalone empty YAML array cannot precede insert entries.
                if provider == .dsh {
                    let body = result.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
                        .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    if body == "[]" {
                        result = result.replacingOccurrences(of: #"(?m)^\s*\[\]\s*$"#, with: "", options: .regularExpression)
                    } else if !body.isEmpty && !body.hasPrefix("-") {
                        throw Failure.invalidConfiguration
                    }
                }
                result += "\n" + begin + "\n" + block(home: destination.home) + "\n" + end + "\n"
            }
            return (path, original, result)
        }
        // Record intent first: a partial write failure must remain removable.
        if provider == .dsh {
            let paths = Set(recorded).union(enabled ? currentPaths : [])
            try privateWrite(JSONEncoder().encode(paths.sorted()), to: ledger)
        }
        for (path, original, result) in edits where original != Data(result.utf8) && !(original == nil && result.isEmpty) {
            guard try read(path) == original else { throw Failure.configurationChanged }
            if let original {
                let backup = path.appendingPathExtension("quotaview-" + String(CodexActivityPrivacy.hashIdentifier(String(decoding: original, as: UTF8.self)).prefix(12)) + ".backup")
                if !fm.fileExists(atPath: backup.path) { try privateWrite(original, to: backup) }
            }
            let permissions = (try? fm.attributesOfItem(atPath: path.path)[.posixPermissions] as? NSNumber)?.uint16Value ?? 0o600
            try privateWrite(Data(result.utf8), to: path, mode: mode_t(permissions))
        }
        // Installed helpers stay available for sessions that have cached a hook.
        // A stopped listener fails open; deleting an executable would break those sessions.
        if provider == .dsh {
            // Retain unavailable paths for cleanup when their volume returns.
            let unavailable = recorded.filter { !fm.fileExists(atPath: $0) }
            try privateWrite(JSONEncoder().encode(Set(unavailable).union(enabled ? currentPaths : []).sorted()), to: ledger)
        }
        return enabled ? Array(Set(discovered.map(\.home))).sorted { $0.path < $1.path } : []
    }

    private struct Destination { let path: URL; let home: URL }

    private func configurationFiles(additionalHomes: [URL]) -> [Destination] {
        if provider == .kimiCode {
            guard FileManager.default.fileExists(atPath: home.path) else { return [] }
            return [Destination(path: home.appendingPathComponent("config.toml").resolvingSymlinksInPath(), home: home)]
        }
        let fm = FileManager.default
        let standardHome = fm.homeDirectoryForCurrentUser.appendingPathComponent(".dsh")
        var homes = [home, standardHome] + additionalHomes
        // Desktop wrappers commonly put DSH_HOME directly under their app data
        // directory. Inspect only this bounded shape, never recursive backups,
        // sessions, credentials, or app-specific brand names.
        if let applicationSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
           let apps = try? fm.contentsOfDirectory(at: applicationSupport, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
            for app in apps where !Self.isArchive(app) {
                for name in ["harness-home", "harness", ".dsh"] {
                    let candidate = app.appendingPathComponent(name).resolvingSymlinksInPath()
                    if !Self.isArchive(candidate) { homes.append(candidate) }
                }
            }
        }
        var seen = Set<String>()
        return Set(homes.map { $0.resolvingSymlinksInPath().standardizedFileURL }).sorted { $0.path < $1.path }
            .flatMap { root in Self.dshProfiles(in: root).compactMap { profile in
                let path = profile.appendingPathComponent("cordis.patch.yml").resolvingSymlinksInPath()
                return !Self.isArchive(path) && seen.insert(path.path).inserted ? Destination(path: path, home: root) : nil
            }}
    }

    /// Accept a DSH home or its profiles/profile directory from the directory picker.
    static func dshHome(for selection: URL) -> URL? {
        let url = selection.resolvingSymlinksInPath().standardizedFileURL
        let candidates = [url, url.deletingLastPathComponent(), url.deletingLastPathComponent().deletingLastPathComponent(),
                          url.appendingPathComponent("harness-home"), url.appendingPathComponent("harness"), url.appendingPathComponent(".dsh")]
        return candidates.first { !dshProfiles(in: $0).isEmpty }
    }

    private static func isArchive(_ url: URL) -> Bool {
        url.pathComponents.contains { component in
            let name = component.lowercased()
            return ["backup", "migration", "archive", "snapshot", ".trash"].contains { name.contains($0) }
        }
    }

    private static func dshProfiles(in home: URL) -> [URL] {
        let fm = FileManager.default
        let root = home.appendingPathComponent("profiles")
        let profiles = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        return profiles.map { $0.resolvingSymlinksInPath() }.filter { profile in
            guard !isArchive(profile), fm.fileExists(atPath: profile.appendingPathComponent("cordis.yml").path),
                  let attributes = try? fm.attributesOfItem(atPath: profile.path),
                  (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
                  let size = try? profile.appendingPathComponent("package.json").resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  size <= 262_144,
                  let data = try? Data(contentsOf: profile.appendingPathComponent("package.json")),
                  let manifest = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let dsh = manifest["dsh"] as? [String: Any], dsh["profile"] is [String: Any] else { return false }
            return true
        }.sorted { $0.path < $1.path }
    }

    private func block(home: URL) -> String {
        if provider == .dsh {
            let namespace = CodexActivityPrivacy.hashIdentifier(home.resolvingSymlinksInPath().standardizedFileURL.path)
            return "- insert:\n    - id: " + marker + "\n      name: " + jsonString(plugin.path)
                + "\n      config:\n        sourceNamespace: " + jsonString(namespace)
        }
        let command = quote(helper.path) + " --agent-hook --configuration " + quote(route.path)
        let events = ["SessionStart", "SessionEnd", "UserPromptSubmit", "TurnStarted", "PreToolUse", "PostToolUse", "PostToolUseFailure",
                      "PermissionRequest", "PermissionResult", "PreCompact", "PostCompact", "Stop", "StopFailure", "Interrupt"]
        return events.map { "[[hooks]]\nevent = " + jsonString($0) + "\ncommand = " + jsonString(command) + "\ntimeout = 2\n" }.joined(separator: "\n")
    }
    private func removingBlock(_ text: String) throws -> String {
        var result = text
        while let start = result.range(of: "(?m)^" + NSRegularExpression.escapedPattern(for: begin) + "$", options: .regularExpression) {
            guard let finish = result.range(of: "(?m)^" + NSRegularExpression.escapedPattern(for: end) + "(?:\\n|$)", options: .regularExpression, range: start.upperBound..<result.endIndex) else { throw Failure.invalidConfiguration }
            let lower = start.lowerBound > result.startIndex && result[result.index(before: start.lowerBound)] == "\n"
                ? result.index(before: start.lowerBound) : start.lowerBound
            result.removeSubrange(lower..<finish.upperBound)
        }
        if result.contains(end) { throw Failure.invalidConfiguration }
        return result
    }
    private func read(_ path: URL) throws -> Data? {
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        let size = try path.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 4_194_304 else { throw Failure.invalidConfiguration }
        return try Data(contentsOf: path)
    }
    private func privateWrite(_ data: Data, to url: URL, mode: mode_t = 0o600) throws {
        try data.write(to: url, options: .atomic); chmod(url.path, mode)
    }
    private func quote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    private func jsonString(_ text: String) -> String {
        String(data: try! JSONEncoder().encode(text), encoding: .utf8)!
    }
}
