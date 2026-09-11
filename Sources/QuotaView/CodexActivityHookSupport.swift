import Foundation
import QuotaViewCore


enum CodexHookOperation: Equatable {
    case idle, inspecting, installing, removing, reviewing, restarting
    var isConfiguring: Bool { [.installing, .removing, .restarting].contains(self) }
}

enum CodexActivitySetupResult {
    case installed(
        environment: CodexActivityEnvironmentInspection,
        hookDefinitionChanged: Bool
    )
}

struct CodexActivityConnectionEvidence: Equatable {
    var observedInstallationID: String?
    var connectedInstallationID: String?

    mutating func record(
        event: CodexActivityHookEvent,
        installationID: String
    ) {
        observedInstallationID = installationID
        if event == .userPromptSubmit {
            connectedInstallationID = installationID
        }
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

struct CodexActivityRestartRequirement: Equatable {
    let baselineProcessIdentifier: Int

    func isSatisfied(
        currentProcessIdentifier: pid_t?
    ) -> Bool {
        guard let currentProcessIdentifier else { return false }
        return Int(currentProcessIdentifier)
            != baselineProcessIdentifier
    }
}

struct CodexActivitySetupStatusResolver {
    static func resolve(
        evidenceStatus: CodexActivityConnectionStatus,
        reviewConfirmed: Bool,
        requiresRestart: Bool
    ) -> CodexActivityConnectionStatus {
        if requiresRestart {
            return reviewConfirmed
                ? .installedNeedsRestart
                : .awaitingTrust
        }
        if evidenceStatus == .awaitingTrust, reviewConfirmed {
            return .awaitingFirstEvent
        }
        return evidenceStatus
    }
}

struct CodexActivityEnvironmentInspection: Sendable {
    let version: String
    let hooksEnabled: Bool
    let didEnableHooks: Bool
}

struct CodexActivityEnvironmentInspector: Sendable {
    enum InspectionError: LocalizedError {
        case codexUnavailable
        case commandFailed(String)
        case commandTimedOut
        case hooksFeatureUnavailable

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
            }
        }
    }

    private struct CommandResult {
        let standardOutput: String
        let standardError: String
    }

    let executablePath: String?
    let timeout: TimeInterval

    init(
        executablePath: String? = CodexExecutableLocator.locate(),
        timeout: TimeInterval = 8
    ) {
        self.executablePath = executablePath
        self.timeout = max(timeout, 1)
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
        guard let hooksEnabled = Self.hooksEnabled(
            in: featureResult.standardOutput
        ) else {
            throw InspectionError.hooksFeatureUnavailable
        }
        return CodexActivityEnvironmentInspection(
            version: version,
            hooksEnabled: hooksEnabled,
            didEnableHooks: false
        )
    }

    func inspectAndEnableHooksIfNeeded()
        throws -> CodexActivityEnvironmentInspection
    {
        let current = try inspect()
        guard !current.hooksEnabled else { return current }
        guard let executablePath else {
            throw InspectionError.codexUnavailable
        }

        _ = try run(
            executablePath: executablePath,
            arguments: ["features", "enable", "hooks"]
        )
        let updated = try inspect()
        guard updated.hooksEnabled else {
            throw InspectionError.hooksFeatureUnavailable
        }
        return CodexActivityEnvironmentInspection(
            version: updated.version,
            hooksEnabled: true,
            didEnableHooks: true
        )
    }

    private func run(
        executablePath: String,
        arguments: [String]
    ) throws -> CommandResult {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = standardOutput
        process.standardError = standardError

        do {
            try process.run()
        } catch {
            throw InspectionError.commandFailed(
                error.localizedDescription
            )
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        guard !process.isRunning else {
            process.terminate()
            process.waitUntilExit()
            throw InspectionError.commandTimedOut
        }

        let outputData = standardOutput.fileHandleForReading
            .readDataToEndOfFile()
        let errorData = standardError.fileHandleForReading
            .readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let error = String(data: errorData, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            let message = error
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw InspectionError.commandFailed(
                message.isEmpty ? "exit \(process.terminationStatus)" : message
            )
        }
        return CommandResult(
            standardOutput: output,
            standardError: error
        )
    }

    private static func hooksEnabled(in output: String) -> Bool? {
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.first == "hooks" else { continue }
            if fields.last == "true" { return true }
            if fields.last == "false" { return false }
        }
        return nil
    }
}

struct CodexSecurityReviewLauncher: Sendable {
    enum LaunchError: LocalizedError {
        case codexUnavailable
        case expectUnavailable
        case couldNotPrepareLauncher
        case couldNotOpenTerminal

        var errorDescription: String? {
            switch self {
            case .codexUnavailable:
                "找不到可用于安全确认的 Codex CLI。"
            case .expectUnavailable:
                "当前系统缺少打开 Codex 安全确认所需的终端组件。"
            case .couldNotPrepareLauncher:
                "无法准备 Codex 安全确认窗口。"
            case .couldNotOpenTerminal:
                "无法打开 Codex 安全确认窗口。"
            }
        }
    }

    let codexExecutablePath: String?
    let launcherDirectoryURL: URL
    let reviewCompletionURL: URL

    init(
        codexExecutablePath: String?,
        launcherDirectoryURL: URL? = nil,
        reviewCompletionURL: URL? = nil
    ) {
        self.codexExecutablePath = codexExecutablePath
        let resolvedLauncherDirectoryURL: URL
        if let launcherDirectoryURL {
            resolvedLauncherDirectoryURL = launcherDirectoryURL
        } else {
            resolvedLauncherDirectoryURL = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
                .appendingPathComponent("QuotaView", isDirectory: true)
                .appendingPathComponent("Launchers", isDirectory: true)
        }
        self.launcherDirectoryURL = resolvedLauncherDirectoryURL
        self.reviewCompletionURL = reviewCompletionURL
            ?? resolvedLauncherDirectoryURL.appendingPathComponent(
                "QuotaViewHookReviewComplete"
            )
    }

    func prepareLauncher() throws -> URL {
        guard let codexExecutablePath,
              FileManager.default.isExecutableFile(
                atPath: codexExecutablePath
              )
        else {
            throw LaunchError.codexUnavailable
        }
        guard FileManager.default.isExecutableFile(
            atPath: "/usr/bin/expect"
        ) else {
            throw LaunchError.expectUnavailable
        }

        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(
                at: launcherDirectoryURL,
                withIntermediateDirectories: true
            )
            chmod(launcherDirectoryURL.path, S_IRWXU)

            let expectURL = launcherDirectoryURL
                .appendingPathComponent("QuotaViewHookReview.exp")
            let launcherURL = launcherDirectoryURL
                .appendingPathComponent("Open Codex Security Review.command")
            if fileManager.fileExists(
                atPath: reviewCompletionURL.path
            ) {
                try fileManager.removeItem(at: reviewCompletionURL)
            }
            let expectScript = """
            #!/usr/bin/expect -f
            set timeout 180
            set codex_path [lindex $argv 0]
            set completion_path [lindex $argv 1]
            proc write_result {path value} {
                set result_file [open $path w]
                puts $result_file $value
                close $result_file
                file attributes $path -permissions 0600
            }
            spawn -noecho $codex_path
            expect {
                -re {›} {
                }
                timeout {
                    write_result $completion_path "failed:prompt-timeout"
                    puts stderr "Timed out waiting for the Codex prompt."
                    exit 124
                }
                eof {
                    catch wait result
                    exit [lindex $result 3]
                }
            }

            set setup_deadline [expr {[clock milliseconds] + 240000}]
            set review_ready 0
            for {set attempt 0} {$attempt < 6 && !$review_ready} {incr attempt} {
                set quiet_deadline [expr {[clock milliseconds] + 3000}]
                while {[clock milliseconds] < $setup_deadline} {
                    set timeout 1
                    expect {
                        -re {.+} {
                            set quiet_deadline [expr {[clock milliseconds] + 3000}]
                        }
                        timeout {
                        }
                        eof {
                            catch wait result
                            exit [lindex $result 3]
                        }
                    }
                    if {[clock milliseconds] >= $quiet_deadline} {
                        break
                    }
                }

                send -- "/hooks\\r"
                set timeout 15
                expect {
                    -re {Press t to trust all} {
                        set review_ready 1
                    }
                    -re {Press enter to view hooks} {
                        write_result $completion_path "confirmed"
                        close
                        catch wait
                        exit 0
                    }
                    timeout {
                    }
                    eof {
                        catch wait result
                        exit [lindex $result 3]
                    }
                }
            }
            if {!$review_ready} {
                write_result $completion_path "failed:review-timeout"
                puts stderr "Timed out opening the Codex hook review."
                exit 125
            }

            interact {
                -re {[tT]} {
                    send -- $interact_out(0,string)
                    set timeout 30
                    expect {
                        -re {Press enter to view hooks} {
                            write_result $completion_path "confirmed"
                            close
                            catch wait
                            exit 0
                        }
                        timeout {
                            write_result $completion_path "failed:trust-not-confirmed"
                            puts stderr "Codex did not confirm hook trust."
                            exit 126
                        }
                        eof {
                            catch wait result
                            exit [lindex $result 3]
                        }
                    }
                }
            }
            """
            let launcherScript = """
            #!/bin/zsh
            exec /usr/bin/expect \
            \(Self.shellQuote(expectURL.path)) \
            \(Self.shellQuote(codexExecutablePath)) \
            \(Self.shellQuote(reviewCompletionURL.path))
            """

            try Data(expectScript.utf8).write(
                to: expectURL,
                options: .atomic
            )
            try Data(launcherScript.utf8).write(
                to: launcherURL,
                options: .atomic
            )
            chmod(expectURL.path, S_IRUSR | S_IWUSR | S_IXUSR)
            chmod(launcherURL.path, S_IRUSR | S_IWUSR | S_IXUSR)
            return launcherURL
        } catch {
            throw LaunchError.couldNotPrepareLauncher
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(
            of: "'",
            with: "'\\''"
        ) + "'"
    }
}

struct CodexActivityHookInstaller: Sendable {
    enum InstallationError: LocalizedError {
        case helperUnavailable
        case invalidHooksFile
        case helperInstallationFailed

        var errorDescription: String? {
            switch self {
            case .helperUnavailable:
                "当前 QuotaView 构建中缺少活动 Hook 辅助程序。"
            case .invalidHooksFile:
                "现有 Codex hooks.json 不是有效的 JSON 对象。"
            case .helperInstallationFailed:
                "无法将 Codex 灵动岛 Helper 安装到固定路径。"
            }
        }
    }

    struct InstallationResult: Sendable {
        let hookDefinitionChanged: Bool
    }

    private static let commandMarker = "QuotaViewActivityHook"
    private static let eventNames = CodexActivityHookEvent.allCases
        .map(\.rawValue)

    let socketURL: URL
    let authenticationToken: String
    let hooksURL: URL
    let bundledHelperURL: URL
    let installedHelperURL: URL

    init(
        socketURL: URL,
        authenticationToken: String,
        hooksURL: URL? = nil,
        helperURL: URL? = nil,
        installedHelperURL: URL? = nil
    ) {
        self.socketURL = socketURL
        self.authenticationToken = authenticationToken
        self.hooksURL = hooksURL
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex", isDirectory: true)
                .appendingPathComponent("hooks.json")
        self.bundledHelperURL = helperURL
            ?? Bundle.main.bundleURL
                .appendingPathComponent("Contents/Helpers")
                .appendingPathComponent(Self.commandMarker)
        if let installedHelperURL {
            self.installedHelperURL = installedHelperURL
        } else if hooksURL != nil || helperURL != nil {
            self.installedHelperURL = self.bundledHelperURL
        } else {
            self.installedHelperURL = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
                .appendingPathComponent("QuotaView", isDirectory: true)
                .appendingPathComponent("Helpers", isDirectory: true)
                .appendingPathComponent(Self.commandMarker)
        }
    }

    var installationIdentifier: String {
        CodexActivityPrivacy.hashIdentifier(baseHookCommand())
    }

    func isInstalled() throws -> Bool {
        guard FileManager.default.fileExists(atPath: hooksURL.path) else {
            return false
        }
        let root = try readRoot()
        let hooks = try readHooks(from: root)
        let expectedCommand = hookCommand()
        return Self.eventNames.allSatisfy { eventName in
            guard let groups = hooks[eventName] as? [[String: Any]]
            else {
                return false
            }
            return groups.contains { group in
                handlers(in: group).contains {
                    command(in: $0) == expectedCommand
                }
            }
        }
    }

    func hasQuotaViewHandlers() throws -> Bool {
        guard FileManager.default.fileExists(atPath: hooksURL.path) else {
            return false
        }
        let hooks = try readHooks(from: readRoot())
        return hooks.values.contains { value in
            guard let groups = value as? [[String: Any]] else {
                return false
            }
            return groups.contains { group in
                handlers(in: group).contains {
                    command(in: $0).contains(Self.commandMarker)
                }
            }
        }
    }

    func install() throws -> InstallationResult {
        guard FileManager.default.isExecutableFile(
            atPath: bundledHelperURL.path
        )
        else {
            throw InstallationError.helperUnavailable
        }

        let hookDefinitionChanged = try !isInstalled()
        try installHelper()

        var root = try readRoot(allowMissing: true)
        var hooks = try readHooks(from: root)
        hooks = removingQuotaViewHandlers(from: hooks)

        let command = hookCommand()

        for eventName in Self.eventNames {
            var groups = hooks[eventName] as? [[String: Any]] ?? []
            let timeout = eventName == HookEventName.sessionEnd ? 1 : 2
            groups.append([
                "hooks": [[
                    "type": "command",
                    "command": command,
                    "timeout": timeout
                ]]
            ])
            hooks[eventName] = groups
        }

        root["hooks"] = hooks
        try writeRoot(root)
        return InstallationResult(
            hookDefinitionChanged: hookDefinitionChanged
        )
    }

    func uninstall() throws {
        if FileManager.default.fileExists(atPath: hooksURL.path) {
            var root = try readRoot()
            let hooks = try readHooks(from: root)
            root["hooks"] = removingQuotaViewHandlers(from: hooks)
            try writeRoot(root)
        }
        if installedHelperURL != bundledHelperURL,
           FileManager.default.fileExists(atPath: installedHelperURL.path)
        {
            try FileManager.default.removeItem(at: installedHelperURL)
        }
    }

    private func readRoot(
        allowMissing: Bool = false
    ) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: hooksURL.path) else {
            if allowMissing {
                return [
                    "description":
                        "User-level Codex hooks, including QuotaView activity."
                ]
            }
            return [:]
        }

        let data = try Data(contentsOf: hooksURL)
        guard let object = try JSONSerialization.jsonObject(with: data)
            as? [String: Any]
        else {
            throw InstallationError.invalidHooksFile
        }
        return object
    }

    private func readHooks(
        from root: [String: Any]
    ) throws -> [String: Any] {
        guard let value = root["hooks"] else {
            return [:]
        }
        guard let hooks = value as? [String: Any] else {
            throw InstallationError.invalidHooksFile
        }

        for value in hooks.values {
            guard let groups = value as? [[String: Any]] else {
                throw InstallationError.invalidHooksFile
            }
            for group in groups {
                guard group["hooks"] as? [[String: Any]] != nil else {
                    throw InstallationError.invalidHooksFile
                }
            }
        }
        return hooks
    }

    private func writeRoot(_ root: [String: Any]) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: hooksURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if fileManager.fileExists(atPath: hooksURL.path) {
            let backupURL = hooksURL.appendingPathExtension(
                "quotaview-backup"
            )
            if !fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.copyItem(at: hooksURL, to: backupURL)
            }
        }

        let data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: hooksURL, options: .atomic)
        chmod(hooksURL.path, S_IRUSR | S_IWUSR)
    }

    private func installHelper() throws {
        if bundledHelperURL == installedHelperURL {
            guard FileManager.default.isExecutableFile(
                atPath: installedHelperURL.path
            ) else {
                throw InstallationError.helperInstallationFailed
            }
            return
        }

        let fileManager = FileManager.default
        let directoryURL = installedHelperURL
            .deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        chmod(directoryURL.path, S_IRWXU)

        let temporaryURL = directoryURL.appendingPathComponent(
            ".\(Self.commandMarker)-\(UUID().uuidString)",
            isDirectory: false
        )
        do {
            try fileManager.copyItem(
                at: bundledHelperURL,
                to: temporaryURL
            )
            chmod(temporaryURL.path, S_IRWXU)
            if fileManager.fileExists(atPath: installedHelperURL.path) {
                _ = try fileManager.replaceItemAt(
                    installedHelperURL,
                    withItemAt: temporaryURL
                )
            } else {
                try fileManager.moveItem(
                    at: temporaryURL,
                    to: installedHelperURL
                )
            }
            chmod(installedHelperURL.path, S_IRWXU)
            guard fileManager.isExecutableFile(
                atPath: installedHelperURL.path
            ) else {
                throw InstallationError.helperInstallationFailed
            }
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            if error is InstallationError {
                throw error
            }
            throw InstallationError.helperInstallationFailed
        }
    }

    private func removingQuotaViewHandlers(
        from hooks: [String: Any]
    ) -> [String: Any] {
        var result = hooks
        for (eventName, value) in hooks {
            guard let groups = value as? [[String: Any]] else {
                continue
            }

            let cleanedGroups = groups.compactMap { group -> [String: Any]? in
                let remaining = handlers(in: group).filter {
                    !command(in: $0).contains(Self.commandMarker)
                }
                guard !remaining.isEmpty else { return nil }
                var updated = group
                updated["hooks"] = remaining
                return updated
            }
            result[eventName] = cleanedGroups
        }
        return result
    }

    private func handlers(
        in group: [String: Any]
    ) -> [[String: Any]] {
        group["hooks"] as? [[String: Any]] ?? []
    }

    private func command(in handler: [String: Any]) -> String {
        handler["command"] as? String ?? ""
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func hookCommand() -> String {
        [
            baseHookCommand(),
            "--installation-id",
            shellQuote(installationIdentifier)
        ].joined(separator: " ")
    }

    private func baseHookCommand() -> String {
        [
            shellQuote(installedHelperURL.path),
            "--socket",
            shellQuote(socketURL.path),
            "--token",
            shellQuote(authenticationToken)
        ].joined(separator: " ")
    }

    private enum HookEventName {
        static let sessionEnd = "SessionEnd"
    }
}
