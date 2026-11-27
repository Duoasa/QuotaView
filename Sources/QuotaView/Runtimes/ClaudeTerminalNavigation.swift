import AppKit
import Carbon
#if SWIFT_PACKAGE
import QuotaViewActivityHookSupport
#endif

enum ClaudeTerminalNavigation {
    typealias Terminal = ClaudeConversationHost.Terminal
    typealias Application = ClaudeConversationHost.Application

    // Only an authenticated local hook can bind an island session to a terminal.
    // Switching sessions in the same CLI process invalidates the previous card.
    @MainActor private static var bindings: [UUID: Terminal] = [:]

    @MainActor static func bind(_ terminal: Terminal?, to session: UUID) {
        if let terminal, terminal.valid {
            if terminal.agentProvider == nil {
                bindings = bindings.filter { $0.value.pid != terminal.pid || $0.key == session }
            }
            bindings[session] = terminal
        } else { bindings.removeValue(forKey: session) }
    }

    @MainActor static func binding(for session: UUID) -> Terminal? {
        guard let target = bindings[session] else { return nil }
        // A multi-session TUI can host two chats in one process. A pane
        // alone cannot distinguish them even if one hook fired more recently.
        if target.agentProvider != nil && bindings.contains(where: { id, peer in
            id != session && peer.pid == target.pid && peer.started == target.started && peer.tty == target.tty
        }) { return nil }
        return target
    }

    @MainActor static func removeClaudeBindings() { bindings = bindings.filter { $0.value.agentProvider != nil } }

    static func session(in url: URL) -> UUID? {
        guard ["quotaview-claude-terminal", "quotaview-agent-terminal"].contains(url.scheme), url.host == "session",
              let id = UUID(uuidString: String(url.path.dropFirst())),
              url.absoluteString == link(for: id, nativeAgent: url.scheme == "quotaview-agent-terminal").absoluteString else { return nil }
        return id
    }

    static func link(for session: UUID, nativeAgent: Bool = false) -> URL {
        let scheme = nativeAgent ? "quotaview-agent-terminal" : "quotaview-claude-terminal"
        return URL(string: scheme + "://session/" + session.uuidString.lowercased())!
    }

    enum Permission {
        case granted, firstUse, denied, notRunning, unavailable
    }

    static func permission(_ app: Application, prompt: Bool = false) -> Permission {
        let instances = NSRunningApplication.runningApplications(withBundleIdentifier: app.rawValue)
        guard !instances.isEmpty else { return .notRunning }
        guard instances.count == 1 else { return .unavailable }
        let target = NSAppleEventDescriptor(bundleIdentifier: app.rawValue)
        switch AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, prompt) {
        case noErr: return .granted
        case OSStatus(procNotFound): return .notRunning
        case OSStatus(errAEEventWouldRequireUserConsent): return .firstUse
        case OSStatus(errAEEventNotPermitted): return .denied
        default: return .unavailable
        }
    }

    /// Called by an explicit settings action. A terminal must be running for
    /// macOS to present its Apple Events consent dialog.
    @MainActor static func requestPermission(
        _ app: Application, startIfNeeded: Bool,
        launch: (Application) async throws -> Void = launchForPermission,
        authorize: @escaping (Application, Bool) -> Permission = permission
    ) async -> Permission {
        if startIfNeeded {
            do { try await launch(app) } catch { return .unavailable }
        }
        return await Task.detached(priority: .userInitiated) { authorize(app, true) }.value
    }

    @MainActor private static func launchForPermission(_ app: Application) async throws {
        if !NSRunningApplication.runningApplications(withBundleIdentifier: app.rawValue).isEmpty { return }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.rawValue) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    private static func current(_ target: Terminal) -> Bool {
        guard target.isCurrent() else { return false }
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: target.application.rawValue)
        guard apps.count == 1, let app = apps.first else { return false }
        return target.appPID.map { app.processIdentifier == $0 } ?? (target.application == .iTerm && target.pane != nil)
    }

    @MainActor static func perform(_ id: UUID, select: Bool,
                                   inspect: @escaping (Terminal) -> Bool = current,
                                   authorize: @escaping (Application, Bool) -> Permission = permission,
                                   runScript: @escaping (Terminal, Bool) -> Bool = script) async -> Bool {
        guard let target = binding(for: id) else { return false }
        let access = await Task.detached(priority: .userInitiated) {
            guard inspect(target) else { return Permission.unavailable }
            return authorize(target.application, select)
        }.value
        guard binding(for: id) == target, !Task.isCancelled else { return false }
        if access == .firstUse { return !select }
        guard access == .granted else { return false }
        return await Task.detached(priority: .userInitiated) {
            inspect(target) && runScript(target, select)
        }.value
    }

    private static func script(_ target: Terminal, select: Bool) -> Bool {
        let source = target.application == .terminal ? terminalScript : iTermScript
        let args = ["-e", source, "/dev/" + target.tty, select ? "select" : "find", target.pane?.uuidString ?? ""]
        let output = BoundedStatusLineCommand.execute("/usr/bin/osascript", arguments: args, timeoutSeconds: 5, maximumOutputBytes: 128)
        return output.flatMap { String(data: $0, encoding: .utf8) }?.trimmingCharacters(in: .whitespacesAndNewlines) == "found"
    }

    static let terminalScript = """
    on run argv
        set targetTTY to item 1 of argv
        set shouldSelect to (item 2 of argv is "select")
        with timeout of 4 seconds
            if application id "com.apple.Terminal" is not running then return "missing"
            tell application id "com.apple.Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is targetTTY then
                            if shouldSelect then
                                if miniaturized of w then set miniaturized of w to false
                                set selected of t to true
                                set index of w to 1
                                activate
                            end if
                            return "found"
                        end if
                    end repeat
                end repeat
            end tell
        end timeout
        return "missing"
    end run
    """

    static let iTermScript = """
    on run argv
        set targetTTY to item 1 of argv
        set shouldSelect to (item 2 of argv is "select")
        set paneID to item 3 of argv
        with timeout of 4 seconds
            if application id "com.googlecode.iterm2" is not running then return "missing"
            tell application id "com.googlecode.iterm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is targetTTY and (paneID is "" or unique id of s is paneID) then
                                if shouldSelect then
                                    if miniaturized of w then set miniaturized of w to false
                                    select w
                                    select t
                                    select s
                                    activate
                                end if
                                return "found"
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
        end timeout
        return "missing"
    end run
    """
}
