import Darwin
import Foundation

/// Maps documented hook payloads to a small, observation-only event envelope.
/// Prompts, tool arguments/results, transcripts and credentials never cross IPC.
public enum NativeAgentHookNormalizer {
    public static func normalize(_ object: [String: Any], provider: String, event override: String? = nil) -> [String: Any]? {
        let sourceEvent = override ?? object["hook_event_name"] as? String ?? ""
        let sessionKey = provider == "cursor" ? "conversation_id" : provider == "copilotCLI" ? "sessionId" : "session_id"
        guard let session = object[sessionKey] as? String, !session.isEmpty, session.utf8.count <= 256 else { return nil }
        var name: String?
        switch provider {
        case "cursor":
            switch sourceEvent {
            case "sessionStart": name = "SessionStart"
            case "sessionEnd": name = "SessionEnd"
            case "beforeSubmitPrompt": name = "UserPromptSubmit"
            case "postToolUse": name = "PostToolUse"
            case "postToolUseFailure": name = "PostToolUseFailure"
            case "preCompact": name = "PreCompact"
            case "stop":
                switch object["status"] as? String {
                case "completed": name = "Stop"
                case "error": name = "StopFailure"
                case "aborted": name = "Interrupt"
                default: return nil
                }
            default: return nil
            }
        case "geminiCLI":
            switch sourceEvent {
            case "SessionStart", "SessionEnd": name = sourceEvent
            case "BeforeAgent": name = "UserPromptSubmit"
            case "AfterAgent": name = "Stop"
            case "BeforeModel": name = "Metadata"
            case "BeforeTool": name = "PreToolUse"
            case "AfterTool": name = "PostToolUse"
            case "PreCompress": name = "PreCompact"
            case "Notification":
                guard object["notification_type"] as? String == "ToolPermission" else { return nil }
                name = "PermissionRequest"
            default: return nil
            }
        case "copilotCLI":
            switch sourceEvent {
            case "sessionStart": name = "SessionStart"
            case "sessionEnd": name = "SessionEnd"
            case "userPromptSubmitted": name = "UserPromptSubmit"
            case "preToolUse": name = "PreToolUse"
            case "postToolUse": name = "PostToolUse"
            case "postToolUseFailure": name = "PostToolUseFailure"
            case "agentStop":
                guard object["stopReason"] as? String == "end_turn" else { return nil }
                name = "Stop"
            case "errorOccurred":
                guard object["recoverable"] as? Bool == false else { return nil }
                name = "StopFailure"
            case "preCompact": name = "PreCompact"
            case "notification":
                guard object["notification_type"] as? String == "permission_prompt" else { return nil }
                name = "PermissionRequest"
            default: return nil // A subagent stop must never finish the parent.
            }
        case "devinDesktop", "devinCLI":
            switch sourceEvent {
            case "SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "Stop": name = sourceEvent
            case "PostToolUse":
                name = (object["tool_response"] as? [String: Any])?["success"] as? Bool == false ? "PostToolUseFailure" : "PostToolUse"
            case "PostCompaction": name = "PostCompact"
            default: return nil
            }
        case "kimiCode", "openCode":
            let allowed = ["SessionStart", "SessionEnd", "UserPromptSubmit", "TurnStarted", "PreToolUse", "PostToolUse", "PostToolUseFailure",
                           "PermissionRequest", "PermissionResult", "PreCompact", "PostCompact", "Stop", "StopFailure", "Interrupt", "Metadata"]
            guard allowed.contains(sourceEvent) else { return nil }
            name = sourceEvent
        default: return nil
        }
        guard let name else { return nil }
        var payload: [String: Any] = ["session_id": session, "hook_event_name": name]
        func put(_ key: String, _ value: Any?) {
            if let value = value as? String, !value.isEmpty { payload[key] = String(value.prefix(256)) }
        }
        put("tool_name", object[provider == "copilotCLI" ? "toolName" : "tool_name"])
        for key in ["tool_use_id", "tool_call_id", "model"] { put(key, object[key]) }
        if provider == "devinDesktop" || provider == "devinCLI" { put("turn_id", object["prompt_id"]) }
        if provider == "cursor" { put("turn_id", object["generation_id"]); put("model", object["model_id"] ?? object["model"]) }
        if provider == "geminiCLI" { put("model", (object["llm_request"] as? [String: Any])?["model"]) }
        if provider == "kimiCode" {
            for key in ["turn_id", "prompt_id", "agent_id", "session_title", "source", "reason"] { put(key, object[key]) }
        }
        if provider == "openCode" {
            for key in ["turn_id", "session_title", "parent_session_id", "source_epoch"] { put(key, object[key]) }
            if let sequence = object["source_sequence"] as? Int, sequence >= 0 { payload["source_sequence"] = sequence }
        }
        return payload
    }

    /// No tool or permission decision. Cursor's prompt hook requires `continue`;
    /// this only declines to veto sending the prompt, never grants tool access.
    public static func neutralOutput(provider: String, event: String?) -> Data? {
        if provider == "cursor", event == "beforeSubmitPrompt" { return Data("{\"continue\":true}\n".utf8) }
        if ["cursor", "geminiCLI", "copilotCLI"].contains(provider) { return Data("{}\n".utf8) }
        return nil
    }
}

/// Runs the user's existing status line in a separate process group. One total
/// deadline covers input, output EOF and process exit; descendants share cleanup.
public enum BoundedStatusLineCommand {
    public static func run(command: String, input: Data, timeoutSeconds: TimeInterval = 5,
                           maximumOutputBytes: Int = 65_536) -> Data? {
        let deadline = ProcessInfo.processInfo.systemUptime + max(0.01, timeoutSeconds)
        var inputPipe: [Int32] = [-1, -1], outputPipe: [Int32] = [-1, -1]
        guard pipe(&inputPipe) == 0 else { return nil }
        guard pipe(&outputPipe) == 0 else { inputPipe.forEach { Darwin.close($0) }; return nil }
        var inputOpen = true
        defer {
            if inputOpen { Darwin.close(inputPipe[1]) }
            Darwin.close(outputPipe[0])
        }
        for fd in inputPipe + outputPipe { _ = fcntl(fd, F_SETFD, FD_CLOEXEC) }
        _ = fcntl(inputPipe[1], F_SETNOSIGPIPE, 1)
        var actions: posix_spawn_file_actions_t?, attributes: posix_spawnattr_t?
        guard posix_spawn_file_actions_init(&actions) == 0 else {
            Darwin.close(inputPipe[0]); Darwin.close(outputPipe[1]); return nil
        }
        defer { posix_spawn_file_actions_destroy(&actions) }
        guard posix_spawnattr_init(&attributes) == 0 else {
            Darwin.close(inputPipe[0]); Darwin.close(outputPipe[1]); return nil
        }
        defer { posix_spawnattr_destroy(&attributes) }
        let prepared = [
            posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP)),
            posix_spawnattr_setpgroup(&attributes, 0),
            posix_spawn_file_actions_adddup2(&actions, inputPipe[0], STDIN_FILENO),
            posix_spawn_file_actions_adddup2(&actions, outputPipe[1], STDOUT_FILENO),
            posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0),
            posix_spawn_file_actions_addclose(&actions, inputPipe[1]),
            posix_spawn_file_actions_addclose(&actions, outputPipe[0])
        ].allSatisfy { $0 == 0 }
        let commandArguments: [String] = ["/bin/sh", "-c", command]
        var arguments: [UnsafeMutablePointer<CChar>?] = commandArguments.map { strdup($0) }
        arguments.append(nil)
        var environment = ProcessInfo.processInfo.environment.map { strdup($0.key + "=" + $0.value) } + [nil]
        defer { arguments.forEach { free($0) }; environment.forEach { free($0) } }
        var pid: pid_t = 0
        let spawned = prepared ? arguments.withUnsafeMutableBufferPointer { argv in
            environment.withUnsafeMutableBufferPointer { env in
                posix_spawn(&pid, "/bin/sh", &actions, &attributes, argv.baseAddress!, env.baseAddress!)
            }
        } : EINVAL
        Darwin.close(inputPipe[0]); Darwin.close(outputPipe[1])
        guard spawned == 0 else { return nil }
        var exited = false, status: Int32 = 0
        defer {
            // The group is created atomically by spawn, so no unrelated shell
            // or QuotaView process can become a termination target.
            kill(-pid, SIGKILL)
            if !exited {
                while waitpid(pid, &status, 0) < 0 && errno == EINTR { }
            }
        }
        guard fcntl(inputPipe[1], F_SETFL, O_NONBLOCK) == 0,
              fcntl(outputPipe[0], F_SETFL, O_NONBLOCK) == 0 else { return nil }
        var written = 0, output = Data(), eof = false
        var bytes = [UInt8](repeating: 0, count: 8_192)
        while ProcessInfo.processInfo.systemUptime < deadline {
            if inputOpen, written == input.count { Darwin.close(inputPipe[1]); inputOpen = false }
            if !exited {
                let result = waitpid(pid, &status, WNOHANG)
                if result == pid { exited = true }
                else if result < 0 && errno != EINTR { return nil }
            }
            if exited && eof { return output }
            var descriptors = [pollfd(fd: eof ? -1 : outputPipe[0], events: Int16(POLLIN), revents: 0),
                               pollfd(fd: inputOpen ? inputPipe[1] : -1, events: Int16(POLLOUT), revents: 0)]
            let remaining = max(1, (deadline - ProcessInfo.processInfo.systemUptime) * 1_000)
            let ready = poll(&descriptors, 2, Int32(min(20, remaining)))
            if ready < 0 { if errno == EINTR { continue }; return nil }
            if inputOpen, descriptors[1].revents != 0 {
                let count = input.withUnsafeBytes { Darwin.write(inputPipe[1], $0.baseAddress!.advanced(by: written), input.count - written) }
                if count > 0 { written += count }
                else if count < 0 && ![EINTR, EAGAIN, EWOULDBLOCK].contains(errno) {
                    Darwin.close(inputPipe[1]); inputOpen = false
                }
            }
            if !eof, descriptors[0].revents != 0 {
                let count = Darwin.read(outputPipe[0], &bytes, bytes.count)
                if count == 0 { eof = true }
                else if count > 0 {
                    guard count <= maximumOutputBytes - output.count else { return nil }
                    output.append(bytes, count: count)
                } else if ![EINTR, EAGAIN, EWOULDBLOCK].contains(errno) { return nil }
            }
        }
        return nil
    }
}

/// Shared Devin hooks run in both clients. Classify the launching process chain
/// locally; never trust a provider label in stdin or forward process paths.
public enum DevinHookSource {
    public static func provider(ancestorPaths: [String], complete: Bool) -> String? {
        var sawCLI = false
        for path in ancestorPaths {
            let name = URL(fileURLWithPath: path).lastPathComponent.lowercased()
            // A CLI launched inside the desktop's integrated terminal remains CLI.
            if sawCLI && ["sh", "bash", "zsh", "fish", "nu", "pwsh"].contains(name) { return "devinCLI" }
            if ["devin", "devin-cli"].contains(name) { sawCLI = true }
            for app in ["Devin.app", "Devin Desktop.app"] {
                if path.contains("/" + app + "/Contents/MacOS/") || path.contains("/" + app + "/Contents/Frameworks/") {
                    return "devinDesktop"
                }
            }
        }
        // An unreadable/truncated chain cannot prove that the desktop is absent.
        return complete ? "devinCLI" : nil
    }
    public static func currentProvider() -> String? {
        var pid = getppid(), visited: Set<pid_t> = [], paths: [String] = []
        for _ in 0..<32 {
            if pid <= 1 { return provider(ancestorPaths: paths, complete: true) }
            guard visited.insert(pid).inserted else { break }
            var info = proc_bsdinfo(), buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
                  proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { break }
            paths.append(String(cString: buffer)); pid = pid_t(info.pbi_ppid)
        }
        return provider(ancestorPaths: paths, complete: false)
    }
    /// Devin imports Claude hooks by default. Its payload omits the transcript
    /// field that Claude supplies; do not turn inherited hooks into Claude tasks.
    public static func isInheritedClaudeHook(_ payload: [String: Any], environment: [String: String]) -> Bool {
        environment["DEVIN_PROJECT_DIR"] != nil && payload["transcript_path"] == nil
    }
}
