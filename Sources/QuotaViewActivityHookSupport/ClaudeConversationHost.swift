import Darwin
import Foundation

/// The hook observes its own process ancestry. Never copy a host, command, or URL from hook stdin.
public struct ClaudeConversationHost: Codable, Equatable, Sendable {
    public let desktop: UUID?
    public var terminal: Terminal?

    public enum Application: String, Codable, Sendable, CaseIterable {
        case terminal = "com.apple.Terminal"
        case iTerm = "com.googlecode.iterm2"
    }

    public struct Terminal: Codable, Equatable, Sendable {
        public let application: Application
        public let appPID: Int32?
        public let pid: Int32
        public let started: Int64
        public let tty: String
        public let pane: UUID?

        public var valid: Bool {
            let digits = tty.utf8.dropFirst(4)
            let identifiedApp = appPID.map { $0 > 1 } ?? (application == .iTerm && pane != nil)
            return pid > 1 && identifiedApp && started > 0 && tty.hasPrefix("ttys") &&
                (1...5).contains(digits.count) && digits.allSatisfy { (48...57).contains($0) } &&
                (pane == nil || application == .iTerm)
        }

        func matches(_ anchor: ProcessInfoRow) -> Bool {
            anchor.pid == pid && anchor.started == started && anchor.tty == tty && anchor.foreground && anchor.isClaudeCandidate
        }

        public func isCurrent() -> Bool {
            guard valid, let anchor = ProcessInfoRow.read(pid), matches(anchor) else { return false }
            if let appPID { return ClaudeConversationHost.terminalApp(above: anchor.parent)?.pid == appPID }
            // A restored iTerm session can outlive its original GUI process.
            // The running app must confirm both its permanent pane UUID and this TTY.
            return application == .iTerm && pane != nil
        }
    }

    struct ProcessInfoRow {
        let pid: Int32
        let parent: Int32
        let started: Int64
        let tty: String?
        let path: String
        let foreground: Bool

        var executable: String { (path as NSString).lastPathComponent }
        var isClaudeCandidate: Bool {
            if ["claude", "node", "bun"].contains(executable) { return true }
            let directory = (path as NSString).deletingLastPathComponent
            return directory.hasSuffix("/claude/versions") &&
                executable.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+([-+][A-Za-z0-9.-]+)?$"#, options: .regularExpression) != nil
        }

        static func read(_ pid: Int32) -> Self? {
            var query = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.size
            guard pid > 1, sysctl(&query, 4, &info, &size, nil, 0) == 0,
                  size == MemoryLayout<kinfo_proc>.size, info.kp_proc.p_pid == pid else { return nil }
            var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
            let path = proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 ? String(cString: buffer) : ""
            var name = [CChar](repeating: 0, count: 64)
            let device = info.kp_eproc.e_tdev
            let tty = device != -1 && devname_r(device, S_IFCHR, &name, Int32(name.count)) != nil ? String(cString: name) : nil
            let time = info.kp_proc.p_starttime
            return Self(pid: pid, parent: info.kp_eproc.e_ppid,
                        started: Int64(time.tv_sec) * 1_000_000 + Int64(time.tv_usec), tty: tty, path: path,
                        foreground: info.kp_eproc.e_pgid > 0 && info.kp_eproc.e_pgid == info.kp_eproc.e_tpgid)
        }
    }

    private static func terminalApp(above parent: Int32) -> (pid: Int32, application: Application)? {
        var pid = parent
        for _ in 0..<32 {
            guard let row = ProcessInfoRow.read(pid), row.pid != row.parent else { return nil }
            if let range = row.path.range(of: ".app/Contents/") {
                let path = String(row.path[..<range.lowerBound]) + ".app"
                guard let id = Bundle(path: path)?.bundleIdentifier, let app = Application(rawValue: id) else { return nil }
                // iTerm can interpose a helper from inside its own app bundle.
                if Bundle(path: path)?.executableURL?.path == row.path { return (row.pid, app) }
            }
            pid = row.parent
        }
        return nil
    }

    public static func current() -> Self {
        let env = ProcessInfo.processInfo.environment
        let desktop = env["CLAUDE_CODE_HOST_SESSION_ID"].flatMap {
            $0.hasPrefix("local_") ? UUID(uuidString: String($0.dropFirst(6))) : nil
        }
        var host = Self(desktop: desktop, terminal: nil)
        guard env["TMUX"] == nil, env["STY"] == nil, env["SSH_CONNECTION"] == nil else { return host }
        var pid = getppid()
        for _ in 0..<10 {
            guard let row = ProcessInfoRow.read(pid) else { break }
            if row.isClaudeCandidate {
                guard let tty = row.tty else { break }
                let app = terminalApp(above: row.parent)
                var pane: UUID?
                if let raw = env["ITERM_SESSION_ID"], app?.application == .iTerm || env["TERM_PROGRAM"] == "iTerm.app" {
                    guard let suffix = raw.split(separator: ":").last, let id = UUID(uuidString: String(suffix)) else { break }
                    pane = id
                }
                guard let application = app?.application ?? (pane == nil ? nil : Application.iTerm) else { break }
                let terminal = Terminal(application: application, appPID: app?.pid, pid: row.pid, started: row.started,
                                        tty: tty, pane: application == .iTerm ? pane : nil)
                if terminal.valid { host.terminal = terminal }
                break
            }
            guard ["sh", "bash", "zsh", "dash", "fish", "env"].contains(row.executable) else { break }
            pid = row.parent
        }
        return host
    }
}
