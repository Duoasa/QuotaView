import Foundation
import XCTest
import SQLite3
import QuotaViewCore
@testable import QuotaView

final class NativeAgentRuntimeSmokeTests: XCTestCase {
    @MainActor
    private func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(condition(), "The native event did not reach the expected runtime state")
    }
    private func execute(_ executable: URL, arguments: [String], input: Data? = nil, environment: [String:String]? = nil, directory: URL? = nil) async throws -> (Int32, String) {
        let process=Process(), output=Pipe(), stdin=Pipe()
        process.executableURL=executable; process.arguments=arguments; process.currentDirectoryURL=directory
        if let environment { process.environment=environment }
        process.standardOutput=output; process.standardError=output
        if let input { process.standardInput=stdin; stdin.fileHandleForWriting.write(input); try stdin.fileHandleForWriting.close() }
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler={ continuation.resume(returning:$0.terminationStatus) }
            do { try process.run() } catch { continuation.resume(throwing:error) }
        }
        return (status,String(decoding:output.fileHandleForReading.readDataToEndOfFile(),as:UTF8.self))
    }
    @MainActor
    func testInstalledCommandHooksReachIslandAndDisableWithdrawsOnlyTheirCards() async throws {
        let root=URL(fileURLWithPath:"/private/tmp/qv-native-"+UUID().uuidString.prefix(8))
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let helper=URL(fileURLWithPath:ProcessInfo.processInfo.environment["QV_NATIVE_HELPER"] ?? FileManager.default.currentDirectoryPath+"/.build/debug/QuotaViewActivityHook")
        guard FileManager.default.isExecutableFile(atPath:helper.path) else { throw XCTSkip("Build QuotaViewActivityHook before the native IPC smoke") }
        let suite="QuotaView.NativeAgentSmoke."+UUID().uuidString
        let defaults=try XCTUnwrap(UserDefaults(suiteName:suite))
        defer { defaults.removePersistentDomain(forName:suite) }
        let preferences=AppPreferences(defaults:defaults), island=IslandSession()
        defer { island.stop() }
        var runtimes:[NativeAgentRuntime]=[]
        defer { runtimes.forEach { $0.stop() } }
        let cases:[(IslandAgentProvider,String,String,String,String)] = [
            (.cursor,"hooks.json","beforeSubmitPrompt","stop","conversation_id"),
            (.geminiCLI,"settings.json","BeforeAgent","AfterAgent","session_id"),
            (.copilotCLI,"","userPromptSubmitted","agentStop","sessionId")
        ]
        for (provider,filename,start,stop,sessionKey) in cases {
            let home=root.appendingPathComponent(provider.rawValue)
            try FileManager.default.createDirectory(at:home,withIntermediateDirectories:true)
            let installer=NativeAgentInstaller(provider:provider,socketURL:root.appendingPathComponent(provider.rawValue+".sock"),authenticationToken:"fixture",
                homeOverride:home,supportOverride:root.appendingPathComponent(provider.rawValue+"-support"),helperOverride:helper)
            switch provider {
            case .cursor: preferences.cursorEnabled=true
            case .geminiCLI: preferences.geminiCLIEnabled=true
            case .copilotCLI: preferences.copilotCLIEnabled=true
            default: XCTFail()
            }
            let runtime=NativeAgentRuntime(provider:provider,preferences:preferences,island:island,defaults:defaults,installer:installer)
            runtimes.append(runtime); runtime.start()
            try await waitFor { runtime.status == .waiting }
            let file=home.appendingPathComponent(filename.isEmpty ? "hooks/"+installer.marker+".json" : filename)
            let config=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:file)) as? [String:Any])
            let hooks=try XCTUnwrap(config["hooks"] as? [String:[[String:Any]]])
            func command(_ event:String) throws -> String {
                let entry=try XCTUnwrap(hooks[event]?.last)
                if provider == .geminiCLI { return try XCTUnwrap((entry["hooks"] as? [[String:Any]])?.first?["command"] as? String) }
                return try XCTUnwrap((entry["command"] ?? entry["bash"]) as? String)
            }
            let session="same-session"
            var payload:[String:Any]=[sessionKey:session,"hook_event_name":start,"generation_id":"turn","prompt":"PRIVATE_SMOKE_PROMPT"]
            let started=try await execute(URL(fileURLWithPath:"/bin/sh"),arguments:["-c",try command(start)],input:JSONSerialization.data(withJSONObject:payload))
            XCTAssertEqual(started.0,0,started.1)
            let key=CodexActivityPrivacy.hashIdentifier(provider.rawValue+":"+session)
            try await waitFor { runtime.status == .connected && island.model.tasks.contains { $0.key == key && !$0.terminal } }
            XCTAssertEqual(island.model.provider(for:key),provider)
            payload["hook_event_name"]=stop; payload["status"]="completed"; payload["stopReason"]="end_turn"
            let ended=try await execute(URL(fileURLWithPath:"/bin/sh"),arguments:["-c",try command(stop)],input:JSONSerialization.data(withJSONObject:payload))
            XCTAssertEqual(ended.0,0,ended.1)
            try await waitFor { island.model.tasks.contains { $0.key == key && $0.status == .completed } }
        }
        XCTAssertEqual(island.model.tasks.count,3,"Identical external session IDs must remain separate by provider")
        preferences.cursorEnabled=false
        try await waitFor { runtimes[0].status == .disabled }
        XCTAssertFalse(island.model.tasks.contains { island.model.provider(for:$0.key) == .cursor })
        XCTAssertEqual(island.model.tasks.count,2)
        let hooks=try String(contentsOf:root.appendingPathComponent("cursor/hooks.json"),encoding:.utf8)
        XCTAssertFalse(hooks.contains("--agent-hook"))
    }

    @MainActor
    func testAntigravityInvocationAndBackgroundStop() async throws {
        let root = URL(fileURLWithPath: "/private/tmp/qv-ag-" + UUID().uuidString.prefix(8))
        let home = root.appendingPathComponent("config")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = home.appendingPathComponent("hooks.json")
        try Data(#"{"other":{"enabled":false}}"#.utf8).write(to: config)
        let suite = "QuotaView.AntigravitySmoke." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = AppPreferences(defaults: defaults), island = IslandSession()
        let helper = URL(fileURLWithPath: ProcessInfo.processInfo.environment["QV_NATIVE_HELPER"] ?? FileManager.default.currentDirectoryPath + "/.build/debug/QuotaViewActivityHook")
        let installer = NativeAgentInstaller(provider: .antigravity, socketURL: root.appendingPathComponent("hook.sock"), authenticationToken: "fixture", homeOverride: home, supportOverride: root.appendingPathComponent("support"), helperOverride: helper)
        let runtime = NativeAgentRuntime(provider: .antigravity, preferences: prefs, island: island, defaults: defaults, installer: installer)
        defer { runtime.stop(); island.stop() }
        prefs.antigravityEnabled = true
        runtime.start()
        try await waitFor { runtime.status == .waiting }
        let groups = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: config)) as? [String: Any])
        let hooks = try XCTUnwrap(groups[installer.marker] as? [String: Any])
        let id = UUID().uuidString
        let relative = "antigravity/brain/" + id + "/.system_generated/logs/"
        let dir = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let database = root.appendingPathComponent("antigravity/conversation_summaries.db")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(database.path, &db), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(db, "CREATE TABLE conversation_summaries(conversation_id TEXT PRIMARY KEY, title TEXT, preview TEXT); INSERT INTO conversation_summaries VALUES ('" + id + "', '', 'Preview title')", nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)
        let stamp = ISO8601DateFormatter().string(from: Date())
        let record: [String: Any] = ["step_index": 7, "type": "PLANNER_RESPONSE", "status": "DONE", "created_at": stamp,
            "content": "Public answer", "thinking": "private reasoning", "input_tokens": 100, "cache_read_tokens": 50, "output_tokens": 24]
        let older: [String: Any] = ["step_index": 1, "type": "PLANNER_RESPONSE", "status": "DONE", "created_at": stamp,
            "content": "Earlier turn", "input_tokens": 10, "output_tokens": 5]
        var lines = Data()
        for row in [older, record] { lines.append(try JSONSerialization.data(withJSONObject: row)); lines.append(10) }
        try lines.write(to: dir.appendingPathComponent("transcript_full.jsonl"))
        let chunks = dir.appendingPathComponent("chunks/transcript_full")
        try FileManager.default.createDirectory(at: chunks, withIntermediateDirectories: true)
        try lines.write(to: chunks.appendingPathComponent("00000000.jsonl"))
        var payload: [String: Any] = ["conversationId": id, "initialNumSteps": 5, "invocationNum": 0, "modelName": "fixture-model", "transcriptPath": FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gemini/" + relative + "transcript.jsonl").path]
        func send(_ event: String) async throws {
            var entry = try XCTUnwrap((hooks[event] as? [[String: Any]])?.first)
            if let handlers = entry["hooks"] as? [[String: Any]] { entry = try XCTUnwrap(handlers.first) }
            let command = try XCTUnwrap(entry["command"] as? String)
            let result = try await execute(URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", command], input: JSONSerialization.data(withJSONObject: payload))
            XCTAssertEqual(result.0, 0)
            if event == "PreToolUse" {
                XCTAssertEqual(try JSONSerialization.jsonObject(with: Data(result.1.utf8)) as? [String: String], ["decision": "allow"])
            }
        }
        try await send("PreInvocation")
        try await waitFor { island.model.tasks.first?.model == "fixture-model" }
        try await waitFor { island.model.tasks.first?.title == "Preview title" }
        payload.removeValue(forKey: "initialNumSteps")
        payload.removeValue(forKey: "transcriptPath")
        try await send("PostInvocation")
        try await send("PostInvocation")
        try await waitFor { island.model.tasks.first?.tokens == 174 && island.model.tasks.first?.outputRate != nil }
        payload["toolCall"] = ["name": "view_file"]
        try await send("PreToolUse"); try await send("PostToolUse")
        let preEntry = try XCTUnwrap((hooks["PreToolUse"] as? [[String: Any]])?.first)
        let handler = try XCTUnwrap((preEntry["hooks"] as? [[String: Any]])?.first)
        let command = try XCTUnwrap(handler["command"] as? String)
        let readPath = "/fixture/.bash_profile"
        let reviewCases: [(tool: String, args: [String: String], display: String, choice: String, decision: String)] = [
            ("run_command", ["CommandLine": "echo fixture", "Cwd": "/fixture"], "echo fixture", "accept", "auto_approve"),
            ("read_file", ["Path": readPath], readPath, "accept", "auto_approve"),
            ("read_file", ["Path": readPath], readPath, "decline", "deny"),
            ("view_file", ["AbsolutePath": readPath], readPath, "antigravityDelegate", "ask"),
            ("run_command", ["CommandLine": "echo fixture", "Cwd": "/fixture"], "echo fixture", "disable", "ask")
        ]
        for (index, review) in reviewCases.enumerated() {
            let hook: [String: Any] = ["conversationId": id, "stepIdx": 10 + index,
                "toolCall": ["name": review.tool, "args": review.args]]
            let data = try JSONSerialization.data(withJSONObject: hook)
            async let reply = execute(URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", command], input: data)
            try await waitFor { island.model.tasks.first?.requests.first?.value.protocolRequest?.isAntigravity == true }
            let task = try XCTUnwrap(island.model.tasks.first)
            let display = island.model.display(english: true, remaining: nil, enabled: true, privacy: false)
            let request = try XCTUnwrap(display.taskDetails[task.id]?.confirmation)
            XCTAssertTrue(request.canRespond)
            let wire = try XCTUnwrap(request.protocolRequest)
            XCTAssertEqual(wire.params["toolName"].text, review.tool)
            XCTAssertTrue(wire.detail.contains(review.display))
            XCTAssertEqual(wire.actions.map { $0.result["decision"].text }, ["accept", "decline", "antigravityDelegate"])
            if review.choice == "disable" { prefs.antigravityInteractiveApprovals = false }
            else { island.model.submit(task.id, requestID: request.id, decision: .reply(.object(["decision": .string(review.choice)]))) }
            let result = try await reply
            XCTAssertEqual(result.0, 0)
            XCTAssertEqual(try JSONSerialization.jsonObject(with: Data(result.1.utf8)) as? [String: String], ["decision": review.decision])
            XCTAssertTrue(island.model.tasks.first?.requests.isEmpty == true)
        }
        let savedRoute = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: installer.route)) as? [String: Any])
        XCTAssertEqual(savedRoute["interactiveApprovals"] as? Bool, false)
        payload["toolCall"] = ["name": "ask_permission", "args": ["Action": "read", "Target": "/fixture", "Reason": "fixture"]]
        payload["stepIdx"] = 20
        try await send("PreToolUse")
        try await waitFor { island.model.tasks.first?.requests.isEmpty == false }
        XCTAssertFalse(island.model.tasks.first?.requests.first?.value.canRespond == true)
        try await send("PostToolUse")
        try await waitFor { island.model.tasks.first?.requests.isEmpty == true }
        payload["terminationReason"] = "EXECUTOR_TERMINATION_REASON_NO_TOOL_CALL"; payload["fullyIdle"] = false
        try await send("Stop")
        XCTAssertNotEqual(island.model.tasks.first?.status, .completed)
        payload["fullyIdle"] = true
        try await send("Stop")
        try await waitFor { island.model.tasks.first?.status == .completed }
        XCTAssertEqual(island.model.tasks.first?.tokens, 174)
        XCTAssertNotNil(island.model.tasks.first?.averageOutputRate)
        try await waitFor { island.model.tasks.first?.entries.contains { $0.kind == .result && $0.text.chinese == "Public answer" } == true }
        XCTAssertFalse(island.model.tasks.flatMap(\.entries).contains { ["private reasoning", "Earlier turn"].contains($0.text.chinese) })
        await runtime.refreshAntigravityUsage()
        var display = island.model.display(english: true, remaining: nil, enabled: true, privacy: false)
        XCTAssertEqual(display.taskDetails.values.first?.finalResponse?.text.chinese, "Public answer")
        display.antigravityUsage = island.antigravityUsage
        let board = IslandBoardState()
        board.update(display, reduceMotion: true)
        board.usageProvider = .antigravity
        XCTAssertEqual(board.effectiveUsageProvider, .antigravity)
        board.openUsage(); board.openReset()
        XCTAssertFalse(board.showsReset)
        display.antigravityUsage = nil
        board.update(display, reduceMotion: true)
        XCTAssertEqual(board.effectiveUsageProvider, .codex)
        XCTAssertEqual(island.antigravityUsage?.total, 189)
        XCTAssertEqual(island.antigravityUsage?.days.count, 1)
        prefs.antigravityEnabled = false
        try await waitFor { runtime.status == .disabled }
        XCTAssertNil(island.antigravityUsage)
        let remaining = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: config)) as? [String: Any])
        XCTAssertEqual(Set(remaining.keys), ["other"])
    }

    func testAntigravityAccountWindows() throws {
        let json = #"[{"provider":"antigravity","usage":{"updatedAt":"2026-11-18T07:15:39Z","loginMethod":"Antigravity Starter Quota","primary":{"usedPercent":4},"extraRateWindows":[{"title":"Claude/GPT weekly","window":{"usedPercent":37.1}},{"title":"Gemini weekly","window":{"usedPercent":3.8,"resetsAt":"2026-11-25T01:00:46Z"}},{"title":"Invalid","window":{"usedPercent":-8}}]}}]"#
        let account = try XCTUnwrap(AntigravityAccount.decode(Data(json.utf8)))
        XCTAssertEqual(account.plan, "Antigravity Starter Quota")
        XCTAssertEqual(account.displayPlan, "Starter")
        XCTAssertEqual(account.windows.map(\.title), ["Gemini weekly", "Claude/GPT weekly"])
        XCTAssertEqual(account.windows.map(\.remaining), [96, 63])
        XCTAssertNotNil(account.windows[0].resetsAt)
        XCTAssertNil(account.windows[1].resetsAt)
        XCTAssertNil(AntigravityAccount.decode(Data("[]".utf8)))
        if ProcessInfo.processInfo.environment["QV_SMOKE_ANTIGRAVITY_ACCOUNT"] == "1" {
            let live = try XCTUnwrap(AntigravityAccount.read())
            XCTAssertNotNil(live.plan)
            XCTAssertFalse(live.windows.isEmpty)
        }
    }

    func testAntigravityHistoryReadOnlyReplay() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["QV_ANTIGRAVITY_REPLAY_ROOT"],
              let expected = environment["QV_ANTIGRAVITY_REPLAY_TOKENS"].flatMap(Int64.init) else {
            throw XCTSkip("Requires a local Antigravity replay directory and independent token total")
        }
        let root = URL(fileURLWithPath: path, isDirectory: true)
        let scanner = AntigravityUsageScanner()
        let usage = await scanner.scan(root: root)
        XCTAssertEqual(usage.total, expected)
        let rescanned = await scanner.scan(root: root)
        XCTAssertEqual(rescanned, usage)
        let client = root.appendingPathComponent("antigravity")
        let sessions = try FileManager.default.contentsOfDirectory(atPath: client.appendingPathComponent("brain").path)
            .filter { UUID(uuidString: $0) != nil }
        XCTAssertFalse(sessions.isEmpty)
        for session in sessions {
            let logs = try XCTUnwrap(AntigravityHistory.logs(root: root, session: session, client: nil))
            XCTAssertNotNil(AntigravityHistory.title(database: client.appendingPathComponent("conversation_summaries.db"), session: session))
            let replies = AntigravityHistory.replies(logs: logs, firstStep: nil, start: .distantPast, end: Date())
            XCTAssertFalse(replies.isEmpty)
        }
    }

    func testAntigravityReplyFollowingIntermediateStep() throws {
        let folder = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        let file = folder.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        // Desktop transcript metadata only. No user or assistant content.
        let rows = """
        {"step_index":4,"type":"PLANNER_RESPONSE","created_at":"2026-11-18T01:14:42Z","output_tokens":7}
        {"step_index":5,"type":"GENERIC","created_at":"2026-11-18T01:15:09Z"}
        {"step_index":6,"type":"PLANNER_RESPONSE","created_at":"2026-11-18T01:15:09Z","input_tokens":100,"output_tokens":850}
        """
        try Data(rows.utf8).write(to: file)
        let start = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-18T01:15:09Z"))
        let usage = try XCTUnwrap(NativeAgentRuntime.antigravityUsage(file, step: 5, start: start, end: start.addingTimeInterval(8)))
        XCTAssertEqual(usage.step, 6)
        XCTAssertEqual(usage.output, 850)
        XCTAssertEqual(usage.total, 950)
        XCTAssertNil(NativeAgentRuntime.antigravityUsage(file, step: 7, start: start, end: start.addingTimeInterval(8)))
    }

    @MainActor
    func testOfficialOpenCodeClientLoadsPluginAndCompletesIslandTask() async throws {
        guard let script=ProcessInfo.processInfo.environment["QV_OPENCODE_SMOKE_SCRIPT"],
              let fixture=ProcessInfo.processInfo.environment["QV_OPENCODE_SMOKE_ROOT"] else {
            throw XCTSkip("Opt-in official-client smoke uses an isolated local model server")
        }
        let root=URL(fileURLWithPath:fixture)
        try FileManager.default.createDirectory(at:root.appendingPathComponent("config"),withIntermediateDirectories:true)
        let suite="QuotaView.OpenCodeOfficialSmoke."+UUID().uuidString
        let defaults=try XCTUnwrap(UserDefaults(suiteName:suite))
        defer { defaults.removePersistentDomain(forName:suite) }
        let preferences=AppPreferences(defaults:defaults), island=IslandSession()
        preferences.openCodeEnabled=true
        let installer=NativeAgentInstaller(provider:.openCode,socketURL:root.appendingPathComponent("events.sock"),authenticationToken:"fixture",
            homeOverride:root.appendingPathComponent("config"),supportOverride:root.appendingPathComponent("support"),helperOverride:URL(fileURLWithPath:FileManager.default.currentDirectoryPath+"/.build/debug/QuotaViewActivityHook"))
        let runtime=NativeAgentRuntime(provider:.openCode,preferences:preferences,island:island,defaults:defaults,installer:installer)
        defer { runtime.stop(); island.stop() }
        var observed:[String]=[]
        island.model.onChange = { observed.append(contentsOf:island.model.tasks.map { $0.status.rawValue }) }
        runtime.start(); try await waitFor { runtime.status == .waiting }
        let result=try await execute(URL(fileURLWithPath:"/usr/bin/python3"),arguments:[script,root.path])
        XCTAssertEqual(result.0,0,result.1)
        try await waitFor { runtime.status == .connected && observed.contains("completed") }
        let evidence:[String:Any]=["runtimeConnected":runtime.status == .connected,"observedStates":observed,"clientResult":result.1]
        try JSONSerialization.data(withJSONObject:evidence,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("island-evidence.json"))
        XCTAssertTrue(observed.contains("thinking") || observed.contains("working"))
        XCTAssertTrue(island.model.tasks.allSatisfy { island.model.provider(for:$0.key) == .openCode })
    }

    @MainActor
    func testOpenCodeTerminalDeliverySurvivesImmediateProcessExit() async throws {
        let root=URL(fileURLWithPath:"/private/tmp/qv-exit-"+UUID().uuidString.prefix(8))
        try FileManager.default.createDirectory(at:root.appendingPathComponent("config"),withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let suite="QuotaView.OpenCodeExitSmoke."+UUID().uuidString
        let defaults=try XCTUnwrap(UserDefaults(suiteName:suite))
        defer { defaults.removePersistentDomain(forName:suite) }
        let preferences=AppPreferences(defaults:defaults), island=IslandSession()
        preferences.openCodeEnabled=true
        let installer=NativeAgentInstaller(provider:.openCode,socketURL:root.appendingPathComponent("events.sock"),authenticationToken:"fixture",
            homeOverride:root.appendingPathComponent("config"),supportOverride:root.appendingPathComponent("support"),
            helperOverride:URL(fileURLWithPath:FileManager.default.currentDirectoryPath+"/.build/debug/QuotaViewActivityHook"))
        let runtime=NativeAgentRuntime(provider:.openCode,preferences:preferences,island:island,defaults:defaults,installer:installer)
        defer { runtime.stop(); island.stop() }
        runtime.start(); try await waitFor { runtime.status == .waiting }
        let plugin=installer.home.appendingPathComponent("plugins/"+installer.marker+".js")
        let literal=String(data:try JSONEncoder().encode(plugin.absoluteString),encoding:.utf8)!
        let script = """
        const {QuotaView}=await import(\(literal));
        const plugin=await QuotaView();
        for (const [type,properties] of [
          ['session.created',{info:{id:'exit-session',title:'Exit smoke'}}],
          ['session.status',{sessionID:'exit-session',status:{type:'busy'}}],
          ['session.idle',{sessionID:'exit-session'}]
        ]) await plugin.event({event:{type,properties}});
        process.exit(0);
        """
        let file=root.appendingPathComponent("exit.mjs")
        try script.write(to:file,atomically:true,encoding:.utf8)
        let result=try await execute(URL(fileURLWithPath:"/usr/bin/env"),arguments:["node",file.path])
        XCTAssertEqual(result.0,0,result.1)
        try await waitFor { island.model.tasks.contains { $0.status == .completed } }
        XCTAssertEqual(island.model.tasks.count,1,"Replayed in-flight events must not duplicate tasks")
    }
}
