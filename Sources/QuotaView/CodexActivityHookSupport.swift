import Darwin
import Foundation
import QuotaViewCore


enum CodexHookOperation: Equatable {
    case idle, inspecting, installing, removing, reviewing, restarting
    var isConfiguring: Bool { [.inspecting, .installing, .removing, .restarting].contains(self) }
}

struct CodexActivityConnectionEvidence: Equatable {
    var observedInstallationID: String?
    var connectedInstallationID: String?

    mutating func record(
        event: CodexActivityHookEvent,
        installationID: String,
        compactionOnly: Bool = false
    ) {
        if compactionOnly, ![.preCompact, .postCompact].contains(event) { return }
        observedInstallationID = installationID
        connectedInstallationID = installationID
    }

    func status(
        for installationID: String
    ) -> CodexActivityConnectionStatus {
        if connectedInstallationID == installationID {
            return .connected
        }
        if observedInstallationID == installationID {
            return .awaitingFirstEvent
        }
        return .awaitingTrust
    }
}

struct CodexActivityEnvironmentInspection: Sendable {
    let version: String
    let hooksEnabled: Bool
    let didEnableHooks: Bool
    let hooksFeatureName: String

    init(version: String, hooksEnabled: Bool, didEnableHooks: Bool,
         hooksFeatureName: String = "hooks") {
        self.version = version
        self.hooksEnabled = hooksEnabled
        self.didEnableHooks = didEnableHooks
        self.hooksFeatureName = hooksFeatureName
    }
}

struct CodexActivityEnvironmentInspector: Sendable {
    enum InspectionError: LocalizedError {
        case codexUnavailable
        case commandFailed(String)
        case commandTimedOut
        case hooksFeatureUnavailable
        case hooksFeatureDisabled

        var errorDescription: String? {
            switch self {
            case .codexUnavailable:
                "找不到支持 Hooks 的 Codex 安装。"
            case .commandFailed(let message):
                "检测 Codex 环境失败：\(message)"
            case .commandTimedOut:
                "检测 Codex 环境超时。"
            case .hooksFeatureUnavailable:
                "当前 Codex 版本未提供 Hooks 功能。"
            case .hooksFeatureDisabled:
                "Codex 配置已明确禁用 Hooks；请在 Codex 中启用后重试。"
            }
        }
    }

    private struct CommandResult {
        let standardOutput: String
        let standardError: String
    }

    let executablePath: String?
    let timeout: TimeInterval
    let environment: [String: String]
    let dataDirectoryURL: URL

    init(
        executablePath: String? = CodexExecutableLocator.locate(),
        timeout: TimeInterval = 8,
        dataDirectoryURL: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.executablePath = executablePath
        self.timeout = max(timeout, 1)
        self.dataDirectoryURL = dataDirectoryURL
            ?? environment["CODEX_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
        var configuredEnvironment = environment
        configuredEnvironment["CODEX_HOME"] = self.dataDirectoryURL.path
        self.environment = configuredEnvironment
    }

    func inspect() throws -> CodexActivityEnvironmentInspection {
        guard let executablePath else {
            throw InspectionError.codexUnavailable
        }
        let versionResult = try run(
            executablePath: executablePath,
            arguments: ["--version"]
        )
        let version = versionResult.standardOutput
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !version.isEmpty else {
            throw InspectionError.commandFailed(
                versionResult.standardError
            )
        }

        let featureResult = try run(
            executablePath: executablePath,
            arguments: ["features", "list"]
        )
        guard let feature = Self.hooksFeature(in: featureResult.standardOutput) else {
            throw InspectionError.hooksFeatureUnavailable
        }
        return CodexActivityEnvironmentInspection(
            version: version,
            hooksEnabled: feature.enabled,
            didEnableHooks: false,
            hooksFeatureName: feature.name
        )
    }

    func inspectAndEnableHooksIfNeeded()
        throws -> CodexActivityEnvironmentInspection
    {
        let current = try inspect()
        guard !current.hooksEnabled else { return current }
        guard !hasExplicitlyDisabledHooks else {
            throw InspectionError.hooksFeatureDisabled
        }
        guard let executablePath else {
            throw InspectionError.codexUnavailable
        }

        _ = try run(
            executablePath: executablePath,
            arguments: ["features", "enable", current.hooksFeatureName]
        )
        let updated = try inspect()
        guard updated.hooksEnabled else {
            throw InspectionError.hooksFeatureUnavailable
        }
        return CodexActivityEnvironmentInspection(
            version: updated.version,
            hooksEnabled: true,
            didEnableHooks: true,
            hooksFeatureName: updated.hooksFeatureName
        )
    }

    private func run(executablePath: String, arguments: [String]) throws -> CommandResult {
        let process = Process(), standardOutput = Pipe(), standardError = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = standardOutput
        process.standardError = standardError
        let outputDescriptor = standardOutput.fileHandleForReading.fileDescriptor
        let errorDescriptor = standardError.fileHandleForReading.fileDescriptor
        guard fcntl(outputDescriptor, F_SETFL, O_NONBLOCK) == 0,
              fcntl(errorDescriptor, F_SETFL, O_NONBLOCK) == 0 else {
            throw InspectionError.commandFailed("Unable to capture Codex output")
        }
        defer {
            try? standardOutput.fileHandleForReading.close()
            try? standardError.fileHandleForReading.close()
        }
        do { try process.run() }
        catch { throw InspectionError.commandFailed(error.localizedDescription) }

        func stopWithinDeadline() {
            guard process.isRunning else { return }
            process.terminate()
            let terminationDeadline = Date().addingTimeInterval(0.2)
            while process.isRunning, Date() < terminationDeadline { Thread.sleep(forTimeInterval: 0.01) }
            if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
            // Do not wait on descendant processes or their inherited pipe ends.
        }
        defer { stopWithinDeadline() }
        var outputData = Data(), errorData = Data()
        func drain(_ descriptor: Int32, into data: inout Data) throws {
            var bytes = [UInt8](repeating: 0, count: 4_096)
            while true {
                let count = Darwin.read(descriptor, &bytes, bytes.count)
                if count > 0 {
                    guard data.count + count <= 65_536 else {
                        throw InspectionError.commandFailed("Codex output exceeded 64 KiB")
                    }
                    data.append(bytes, count: count)
                } else if count < 0, errno == EINTR { continue }
                else { break }
            }
        }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            try drain(outputDescriptor, into: &outputData)
            try drain(errorDescriptor, into: &errorData)
            guard Date() < deadline else { throw InspectionError.commandTimedOut }
            Thread.sleep(forTimeInterval: 0.01)
        }
        try drain(outputDescriptor, into: &outputData)
        try drain(errorDescriptor, into: &errorData)
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let error = String(data: errorData, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            let message = error.trimmingCharacters(in: .whitespacesAndNewlines)
            throw InspectionError.commandFailed(message.isEmpty ? "exit \(process.terminationStatus)" : message)
        }
        return CommandResult(standardOutput: output, standardError: error)
    }

    private static func hooksFeature(in output: String) -> (name: String, enabled: Bool)? {
        var legacy: (name: String, enabled: Bool)?
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard let name = fields.first, ["hooks", "codex_hooks"].contains(String(name)),
                  let enabled = fields.last.flatMap({ Bool(String($0)) }) else { continue }
            if name == "hooks" { return (String(name), enabled) }
            legacy = (String(name), enabled)
        }
        return legacy
    }

    // Enabling a legacy default-off feature is an explicit action. A user's
    // persistent opt-out must never be overridden by QuotaView's repair path.
    private var hasExplicitlyDisabledHooks: Bool {
        let configURL = dataDirectoryURL.appendingPathComponent("config.toml")
        guard let data = try? Data(contentsOf: configURL), data.count <= 1_048_576,
              let config = String(data: data, encoding: .utf8) else { return false }
        var inFeatures = false
        for rawLine in config.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                inFeatures = line.range(of: #"^\[\s*(?:features|"features"|'features')\s*\]\s*(?:#.*)?$"#,
                                        options: .regularExpression) != nil
                continue
            }
            let pattern = inFeatures
                ? #"^(?:hooks|codex_hooks|"hooks"|"codex_hooks"|'hooks'|'codex_hooks')\s*=\s*false\s*(?:#.*)?$"#
                : #"^features\.(?:hooks|codex_hooks)\s*=\s*false\s*(?:#.*)?$"#
            if line.range(of: pattern, options: .regularExpression) != nil { return true }
        }
        return false
    }

}

struct CodexActivityHookInstaller: Sendable {
    enum InstallationError: LocalizedError {
        case helperUnavailable
        case invalidHooksFile
        case helperInstallationFailed
        case invalidRouteConfiguration
        case hooksFileChanged

        var errorDescription: String? {
            switch self {
            case .helperUnavailable: "当前 QuotaView 构建中缺少活动 Hook 辅助程序。"
            case .invalidHooksFile: "现有 Codex hooks.json 不是有效的 JSON 对象。"
            case .helperInstallationFailed: "无法将 Codex 灵动岛 Helper 安装到固定路径。"
            case .invalidRouteConfiguration: "无法读取 QuotaView 的私有 Hook 连接配置。"
            case .hooksFileChanged: "Codex Hook 配置正在被其他程序更新；请稍后重试。"
            }
        }
    }

    struct InstallationResult: Sendable {
        let hookDefinitionChanged: Bool
        let helperRepaired: Bool
        let routeRepaired: Bool
    }

    private static let commandMarker = "QuotaViewActivityHook"
    private static let eventNames = CodexActivityHookEvent.allCases.map(\.rawValue)

    enum Scope: Equatable, Sendable {
        case all, compaction

        var eventNames: [String] {
            switch self {
            case .all: CodexActivityHookInstaller.eventNames
            case .compaction: [CodexActivityHookEvent.preCompact.rawValue,
                               CodexActivityHookEvent.postCompact.rawValue]
            }
        }
    }

    let socketURL: URL
    let queueURL: URL
    let authenticationToken: String
    let hooksURL: URL
    let bundledHelperURL: URL
    let installedHelperURL: URL
    let configurationURL: URL
    let channelIdentifier: String

    init(
        socketURL: URL,
        authenticationToken: String,
        queueURL: URL? = nil,
        dataDirectoryURL: URL? = nil,
        hooksURL: URL? = nil,
        helperURL: URL? = nil,
        installedHelperURL: URL? = nil,
        configurationURL: URL? = nil,
        channelIdentifier: String = Bundle.main.bundleIdentifier ?? "com.quotaview"
    ) {
        self.socketURL = socketURL
        self.authenticationToken = authenticationToken
        self.channelIdentifier = channelIdentifier
        self.queueURL = queueURL ?? URL(fileURLWithPath:
            "/tmp/\(channelIdentifier).codex-activity-\(getuid())", isDirectory: true)
        let codexHome = dataDirectoryURL
            ?? ProcessInfo.processInfo.environment["CODEX_HOME"].flatMap {
                $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true)
            }
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex", isDirectory: true)
        self.hooksURL = (hooksURL ?? codexHome.appendingPathComponent("hooks.json"))
            .standardizedFileURL.resolvingSymlinksInPath()
        self.bundledHelperURL = helperURL ?? Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers")
            .appendingPathComponent(Self.commandMarker)
        let rootIdentifier = CodexActivityPrivacy.hashIdentifier(self.hooksURL.path)
        let supportURL = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first!
            .appendingPathComponent("QuotaView", isDirectory: true)
            .appendingPathComponent("Channels", isDirectory: true)
            .appendingPathComponent(channelIdentifier, isDirectory: true)
            .appendingPathComponent(String(rootIdentifier.prefix(16)), isDirectory: true)
        if let installedHelperURL {
            self.installedHelperURL = installedHelperURL
        } else if hooksURL != nil || helperURL != nil {
            // Explicit fixture paths remain contained in the supplied directory.
            self.installedHelperURL = self.bundledHelperURL
        } else {
            self.installedHelperURL = supportURL.appendingPathComponent(Self.commandMarker)
        }
        self.configurationURL = configurationURL
            ?? self.installedHelperURL.deletingLastPathComponent()
                .appendingPathComponent("QuotaViewActivityHook-\(String(rootIdentifier.prefix(16))).json")
    }

    // Auth and transport details live in a mode-0600 file. Refreshing a socket,
    // token or helper binary does not change Codex's approved hook definition.
    var hookCommand: String {
        [shellQuote(installedHelperURL.path), "--configuration",
         shellQuote(configurationURL.path)].joined(separator: " ")
    }

    var installationIdentifier: String {
        CodexActivityPrivacy.hashIdentifier(hookCommand)
    }

    func isInstalled() throws -> Bool { try installedScope() != nil }

    func installedScope() throws -> Scope? {
        guard FileManager.default.isExecutableFile(atPath: installedHelperURL.path),
              routeIsCurrent else { return nil }
        let installed = try installedEventNames()
        if installed == Set(Scope.all.eventNames) { return .all }
        if installed == Set(Scope.compaction.eventNames) { return .compaction }
        return nil
    }

    private func installedEventNames() throws -> Set<String> {
        guard FileManager.default.fileExists(atPath: hooksURL.path) else { return [] }
        return try installedEventNames(in: readHooks(from: readRoot()))
    }

    private func installedEventNames(in hooks: [String: Any]) -> Set<String> {
        var installed = Set<String>()
        for (eventName, value) in hooks {
            let owned = (value as? [[String: Any]] ?? []).flatMap { handlers(in: $0) }
                .filter { owns(command(in: $0)) }
            guard !owned.isEmpty else { continue }
            let expectedTimeout = 2
            guard owned.count == 1,
                  owned[0]["type"] as? String == "command",
                  command(in: owned[0]) == hookCommand,
                  owned[0]["timeout"] as? Int == expectedTimeout else { return [] }
            installed.insert(eventName)
        }
        return installed
    }

    func hasQuotaViewHandlers() throws -> Bool {
        guard FileManager.default.fileExists(atPath: hooksURL.path) else { return false }
        let hooks = try readHooks(from: readRoot())
        return hooks.values.contains { value in
            (value as? [[String: Any]] ?? []).contains { group in
                handlers(in: group).contains { owns(command(in: $0)) }
            }
        }
    }

    func install(scope: Scope = .all) throws -> InstallationResult {
        try withHooksLock { try installLocked(scope: scope) }
    }

    private func installLocked(scope: Scope) throws -> InstallationResult {
        guard FileManager.default.isExecutableFile(atPath: bundledHelperURL.path) else {
            throw InstallationError.helperUnavailable
        }
        var helperRepaired = false, routeRepaired = false
        // Re-read and merge if another channel edits the user file while the
        // helper is being repaired. Never publish a stale source snapshot.
        for _ in 0..<3 {
            let snapshot = try readRootSnapshot(allowMissing: true)
            var root = snapshot.root
            let originalHooks = try readHooks(from: root)
            let hookDefinitionChanged = installedEventNames(in: originalHooks) != Set(scope.eventNames)
            helperRepaired = try installHelper() || helperRepaired
            routeRepaired = try writeRouteIfNeeded() || routeRepaired
            if hookDefinitionChanged {
                var hooks = removingOwnedHandlers(from: originalHooks)
                for eventName in scope.eventNames {
                    var groups = hooks[eventName] as? [[String: Any]] ?? []
                    groups.append(["hooks": [["type": "command", "command": hookCommand,
                        "timeout": 2]]])
                    hooks[eventName] = groups
                }
                root["hooks"] = hooks
                do { try writeRoot(root, expectedRevision: snapshot.revision) }
                catch InstallationError.hooksFileChanged { continue }
            }
            return InstallationResult(hookDefinitionChanged: hookDefinitionChanged,
                                      helperRepaired: helperRepaired, routeRepaired: routeRepaired)
        }
        throw InstallationError.hooksFileChanged
    }

    func uninstall() throws {
        try withHooksLock { try uninstallLocked() }
    }

    private func uninstallLocked() throws {
        for attempt in 0..<3 {
            let snapshot = try readRootSnapshot()
            var root = snapshot.root
            let hooks = try readHooks(from: root)
            let cleaned = removingOwnedHandlers(from: hooks)
            if !NSDictionary(dictionary: hooks).isEqual(to: cleaned) {
                root["hooks"] = cleaned
                do { try writeRoot(root, expectedRevision: snapshot.revision) }
                catch InstallationError.hooksFileChanged {
                    if attempt == 2 { throw InstallationError.hooksFileChanged }
                    continue
                }
            }
            break
        }
        if FileManager.default.fileExists(atPath: configurationURL.path) {
            try FileManager.default.removeItem(at: configurationURL)
        }
        if installedHelperURL != bundledHelperURL,
           FileManager.default.fileExists(atPath: installedHelperURL.path) {
            try FileManager.default.removeItem(at: installedHelperURL)
        }
    }

    private func withHooksLock<T>(_ operation: () throws -> T) throws -> T {
        let directory = hooksURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let lockURL = directory.appendingPathComponent(".quotaview-hooks.lock")
        let descriptor = open(lockURL.path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw InstallationError.hooksFileChanged }
        defer { close(descriptor) }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0, metadata.st_uid == getuid(),
              metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_mode & (S_IRWXG | S_IRWXO) == 0 else {
            throw InstallationError.hooksFileChanged
        }
        let deadline = Date().addingTimeInterval(1)
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK || errno == EAGAIN || errno == EINTR,
                  Date() < deadline else { throw InstallationError.hooksFileChanged }
            Thread.sleep(forTimeInterval: 0.01)
        }
        defer { _ = flock(descriptor, LOCK_UN) }
        return try operation()
    }

    private var routeObject: [String: Any] {
        ["version": 1, "socketPath": socketURL.path, "queuePath": queueURL.path,
         "authenticationToken": authenticationToken,
         "installationIdentifier": installationIdentifier]
    }

    private var routeIsCurrent: Bool {
        guard let data = try? Data(contentsOf: configurationURL), data.count <= 16_384,
              let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              NSDictionary(dictionary: routeObject).isEqual(to: existing),
              let attributes = try? FileManager.default.attributesOfItem(atPath: configurationURL.path),
              (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600,
              attributes[.type] as? FileAttributeType == .typeRegular else { return false }
        return true
    }

    private func writeRouteIfNeeded() throws -> Bool {
        guard !routeIsCurrent else { return false }
        let directory = configurationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        chmod(directory.path, S_IRWXU)
        try writePrivateData(JSONSerialization.data(withJSONObject: routeObject, options: [.sortedKeys]),
                             to: configurationURL)
        return true
    }

    private func readRoot(allowMissing: Bool = false) throws -> [String: Any] {
        try readRootSnapshot(allowMissing: allowMissing).root
    }

    private func readRootSnapshot(allowMissing: Bool = false) throws -> (root: [String: Any], revision: Data?) {
        guard FileManager.default.fileExists(atPath: hooksURL.path) else {
            return (allowMissing ? ["description": "User-level Codex hooks, including QuotaView activity."] : [:], nil)
        }
        let data = try Data(contentsOf: hooksURL)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InstallationError.invalidHooksFile
        }
        return (object, data)
    }

    private func readHooks(from root: [String: Any]) throws -> [String: Any] {
        guard let value = root["hooks"] else { return [:] }
        guard let hooks = value as? [String: Any] else { throw InstallationError.invalidHooksFile }
        for value in hooks.values {
            guard let groups = value as? [[String: Any]] else { throw InstallationError.invalidHooksFile }
            for group in groups {
                guard group["hooks"] as? [[String: Any]] != nil else {
                    throw InstallationError.invalidHooksFile
                }
            }
        }
        return hooks
    }

    func writeRoot(_ root: [String: Any], expectedRevision: Data?) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: hooksURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try validateSourceRevision(expectedRevision)
        if manager.fileExists(atPath: hooksURL.path) {
            let backup = hooksURL.appendingPathExtension("quotaview-backup")
            if !manager.fileExists(atPath: backup.path) { try manager.copyItem(at: hooksURL, to: backup) }
        }
        try writePrivateData(JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]),
                             to: hooksURL, beforeReplacing: { try validateSourceRevision(expectedRevision) })
    }

    private func validateSourceRevision(_ expected: Data?) throws {
        if FileManager.default.fileExists(atPath: hooksURL.path) {
            guard try Data(contentsOf: hooksURL) == expected else { throw InstallationError.hooksFileChanged }
        } else if expected != nil { throw InstallationError.hooksFileChanged }
    }

    private func writePrivateData(_ data: Data, to destination: URL,
                                  beforeReplacing: (() throws -> Void)? = nil) throws {
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".quotaview-\(UUID().uuidString).tmp")
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                              S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw InstallationError.invalidRouteConfiguration }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close(); try? FileManager.default.removeItem(at: temporary) }
        try handle.write(contentsOf: data)
        try handle.close()
        try beforeReplacing?()
        guard rename(temporary.path, destination.path) == 0 else {
            throw InstallationError.invalidRouteConfiguration
        }
    }

    private func installHelper() throws -> Bool {
        if bundledHelperURL == installedHelperURL {
            guard FileManager.default.isExecutableFile(atPath: installedHelperURL.path) else {
                throw InstallationError.helperInstallationFailed
            }
            return false
        }
        if FileManager.default.isExecutableFile(atPath: installedHelperURL.path),
           let installed = try? Data(contentsOf: installedHelperURL),
           installed == (try Data(contentsOf: bundledHelperURL)) { return false }
        let manager = FileManager.default
        let directory = installedHelperURL.deletingLastPathComponent()
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        chmod(directory.path, S_IRWXU)
        let temporary = directory.appendingPathComponent(".\(Self.commandMarker)-\(UUID().uuidString)")
        do {
            try manager.copyItem(at: bundledHelperURL, to: temporary)
            chmod(temporary.path, S_IRWXU)
            guard rename(temporary.path, installedHelperURL.path) == 0,
                  manager.isExecutableFile(atPath: installedHelperURL.path) else {
                throw InstallationError.helperInstallationFailed
            }
            return true
        } catch {
            try? manager.removeItem(at: temporary)
            throw InstallationError.helperInstallationFailed
        }
    }

    private func removingOwnedHandlers(from hooks: [String: Any]) -> [String: Any] {
        var result = hooks
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            result[event] = groups.compactMap { group -> [String: Any]? in
                let original = handlers(in: group)
                let remaining = original.filter { !owns(command(in: $0)) }
                guard remaining.count != original.count else { return group }
                guard !remaining.isEmpty else { return nil }
                var updated = group
                updated["hooks"] = remaining
                return updated
            }
        }
        return result
    }

    private func owns(_ command: String) -> Bool {
        if command == hookCommand { return true }
        // Legacy installations are migrated only when both their private token
        // and socket belong to this channel, never by a broad helper-name match.
        guard let arguments = shellWords(command), arguments.count == 7,
              URL(fileURLWithPath: arguments[0]).lastPathComponent == Self.commandMarker,
              arguments[1] == "--socket", arguments[2] == socketURL.path,
              arguments[3] == "--token", arguments[4] == authenticationToken,
              arguments[5] == "--installation-id" else { return false }
        return true
    }

    private func shellWords(_ command: String) -> [String]? {
        var words = [String](), word = "", quote: Character?, escaped = false, hasWord = false
        for character in command {
            if escaped { word.append(character); escaped = false; hasWord = true; continue }
            if character == "\\", quote != "'" { escaped = true; hasWord = true; continue }
            if let current = quote {
                if character == current { quote = nil } else { word.append(character) }
                hasWord = true
            } else if character == "'" || character == "\"" {
                quote = character; hasWord = true
            } else if character.isWhitespace {
                if hasWord { words.append(word); word = ""; hasWord = false }
            } else {
                if ";|&<>`$()".contains(character) { return nil }
                word.append(character); hasWord = true
            }
        }
        guard quote == nil, !escaped else { return nil }
        if hasWord { words.append(word) }
        return words
    }

    private func handlers(in group: [String: Any]) -> [[String: Any]] {
        group["hooks"] as? [[String: Any]] ?? []
    }

    private func command(in handler: [String: Any]) -> String { handler["command"] as? String ?? "" }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
