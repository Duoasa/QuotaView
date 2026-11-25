import Foundation
import ApplicationServices
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
        var nativeCard: AntigravityDesktopApproval.Card?
        var pressed: [AXUIElement] = []
        var answers: [String] = []
        let runtime = NativeAgentRuntime(provider: .antigravity, preferences: prefs, island: island, defaults: defaults, installer: installer,
            readApprovalCards: { sessions in
                guard let nativeCard, sessions.contains(nativeCard.conversation) else { return [:] }
                return [nativeCard.conversation: nativeCard]
            }, pressApprovalButton: { card, allowed in
                guard let deny = card.deny else { return false }
                pressed.append(allowed ? card.allow : deny)
                return true
            }, answerNativeQuestion: { _, answer, current in
                guard current() else { return false }
                answers.append(answer)
                nativeCard = nil
                return true
            })
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
        for tool in ["read_file", "run_command", "write_to_file", "ask_permission"] {
            payload["toolCall"] = ["name": tool, "args": ["Path": "/fixture", "CommandLine": "fixture", "Cwd": "/fixture"]]
            payload["stepIdx"] = 10
            try await send("PreToolUse")
            XCTAssertTrue(island.model.tasks.first?.requests.isEmpty == true)
            try await send("PostToolUse")
        }
        let savedRoute = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: installer.route)) as? [String: Any])
        XCTAssertEqual(savedRoute["interactiveApprovals"] as? Bool, false)
        let conversation = try XCTUnwrap(UUID(uuidString: id))
        let allow = AXUIElementCreateApplication(1001), deny = AXUIElementCreateApplication(1002)
        func card(_ content: String, scope: AntigravityDesktopApproval.Scope = .once) -> AntigravityDesktopApproval.Card {
            .init(conversation: conversation, content: content, scope: scope, element: AXUIElementCreateApplication(1000), allow: allow, deny: deny)
        }
        for (mode, answer) in [("choose", "Orange"), ("type", "A different fruit"), ("superseded", "Apple")] {
            let question = AntigravityDesktopApproval.NativeQuestion(options: [
                .init(label: "Orange", radio: allow), .init(label: "Apple", radio: deny)],
                writeInRadio: AXUIElementCreateApplication(1237), field: AXUIElementCreateApplication(1238))
            nativeCard = .init(conversation: conversation, content: "Fruit? " + mode,
                scope: nil, element: AXUIElementCreateApplication(1239), allow: allow, deny: nil, question: question)
            try await waitFor { island.model.tasks.first?.requests.first?.value.protocolRequest?.kind == .questions }
            let task = try XCTUnwrap(island.model.tasks.first), pending = try XCTUnwrap(task.requests.first?.value)
            let wire = try XCTUnwrap(pending.protocolRequest), q = try XCTUnwrap(wire.questions.first)
            XCTAssertNil(wire.questionSkipResult)
            XCTAssertEqual(IslandApprovalLayout(wire), .questions)
            var draft = IslandApprovalDraft()
            if mode == "type" { draft.setAnswer(answer, for: q) } else { draft.selectAnswer(answer, for: q) }
            if mode == "superseded" { nativeCard = nil }
            island.model.submit(task.id, requestID: pending.id, decision: .reply(try XCTUnwrap(draft.result(for: wire))))
            try await waitFor { island.model.tasks.first?.requests.isEmpty == true }
        }
        XCTAssertEqual(answers, ["Orange", "A different fruit"])
        for choice in ["stale", "changed", "accept", "scoped", "decline", "native", "disable"] {
            nativeCard = card("Exact native target: " + choice, scope: choice == "scoped" ? .project : .once)
            try await waitFor { island.model.tasks.first?.requests.first?.value.protocolRequest?.isAntigravity == true }
            let task = try XCTUnwrap(island.model.tasks.first)
            let display = island.model.display(english: true, remaining: nil, enabled: true, privacy: false)
            let request = try XCTUnwrap(display.taskDetails[task.id]?.confirmation)
            let wire = try XCTUnwrap(request.protocolRequest)
            XCTAssertTrue(request.canRespond)
            XCTAssertEqual(wire.params["command"].text, nativeCard?.content)
            XCTAssertEqual(wire.actions.first?.label.english, nativeCard?.scope?.label.english)
            XCTAssertEqual(wire.actions.map { $0.result["decision"].text }, ["accept", "decline"])
            if choice == "disable" { prefs.antigravityInteractiveApprovals = false }
            else if choice == "native" { nativeCard = nil }
            else {
                if choice == "stale" { nativeCard = nil }
                if choice == "changed" { nativeCard = card("Updated target", scope: .always) }
                island.model.submit(task.id, requestID: request.id, decision: .reply(.object(["decision": .string(choice == "decline" ? "decline" : "accept")])))
            }
            try await waitFor { island.model.tasks.first?.requests.isEmpty == true }
            if choice == "stale" || choice == "changed" { XCTAssertTrue(pressed.isEmpty) }
        }
        XCTAssertEqual(pressed, [allow, allow, deny])
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

    func testAntigravityPermissionCardRequiresNativeScopeAndAction() {
        let session = UUID(), node = AXUIElementCreateApplication(1000)
        func item(_ role: String, _ label: String, value: String? = nil, enabled: Bool = true) -> AntigravityDesktopApproval.Control {
            .init(element: node, role: role, label: label, value: value, enabled: enabled)
        }
        let prefix = [item("AXStaticText", "Runtime permission"), item("AXStaticText", "Allow reading this file?"),
                      item("AXTextArea", "Edit permission target", value: "/fixture/file"),
                      item("AXRadioGroup", "Permission approval scope")]
        let deny = item("AXButton", "Deny"), allow = item("AXButton", "Allow once")
        func parse(_ controls: [AntigravityDesktopApproval.Control]) -> String? {
            AntigravityDesktopApproval.parse(controls, conversation: session, element: node)?.content
        }
        XCTAssertEqual(parse(prefix + [deny, allow]), "Allow reading this file?\n/fixture/file")
        XCTAssertNil(parse([deny, allow]))
        var rule = item("AXRadioButton", "Yes, save rule for /fixture/* globally")
        rule.selected = true
        XCTAssertEqual(parse(prefix + [rule, deny, item("AXButton", "Always allow")]),
                       "Allow reading this file?\n/fixture/file\nYes, save rule for /fixture/* globally")
        XCTAssertNil(parse(prefix + [deny, item("AXButton", "Always allow")]))
        XCTAssertNil(parse(prefix + [deny, item("AXButton", "Allow once", enabled: false)]))
        XCTAssertNil(parse(prefix + [deny, allow, allow]))
        XCTAssertNil(parse(prefix + [deny, allow, item("AXButton", "Open Subagent: other")]))
    }

    func testAntigravitySingleQuestionRequiresNativeWriteInAndCollapsibleForm() throws {
        typealias Approval = AntigravityDesktopApproval
        let root = AXUIElementCreateApplication(1240), session = UUID()
        func control(_ role: String, _ label: String, _ id: String? = nil) -> Approval.Control {
            .init(element: root, role: role, label: label, value: nil, enabled: true, domID: id)
        }
        let items = [control("AXStaticText", "Pick one"), control("AXButton", "Collapse questionnaire"),
            control("AXRadioGroup", ""), control("AXRadioButton", "A Orange", "ask-opt-r1-A"),
            control("AXRadioButton", "B", "ask-opt-r1-__write_in__"), control("AXTextArea", "Other (write your answer)"),
            control("AXButton", "Submit↵")]
        func parse(_ items: [Approval.Control]) -> Approval.Card? {
            Approval.parseSingleQuestion(items, conversation: session, element: root)
        }
        XCTAssertEqual(parse(items)?.question?.options.map(\.label), ["A Orange"])
        XCTAssertNil(parse(items)?.scope)
        XCTAssertNil(parse(items + [control("AXButton", "Next question")]))
        XCTAssertNil(parse(items + [control("AXTextArea", "Edit permission target")]))
        XCTAssertNil(parse(items.filter { $0.label != "Collapse questionnaire" }))
        XCTAssertNil(parse(items + [control("AXCheckBox", "More")]))
        XCTAssertNil(parse(items + [control("AXButton", "Submit")]))
        XCTAssertNil(Approval.parseQuestionnaire(items, conversation: session, element: root))
    }

    func testAntigravityCommandQuestionnaireUsesSelectedScopeAndNativeButtons() throws {
        typealias Approval = AntigravityDesktopApproval
        let session = UUID(), root = AXUIElementCreateApplication(1000)
        let submit = AXUIElementCreateApplication(1001), skip = AXUIElementCreateApplication(1002)
        let target = "for url in https://example.org; do\n  printf '%s' \"$url\"\ndone"
        let title = "Allow network connectivity test?"
        let inlineClasses: Set<String> = ["no-focus-agent-input", "border-warning/40", "bg-card", "rounded-xl"]
        let formClasses: Set<String> = ["outline-none", "flex", "flex-col", "no-focus-ring", "no-focus-agent-input", "gap-2"]
        XCTAssertEqual(Approval.Surface(classes: formClasses), .questionnaire)
        XCTAssertEqual(Approval.Surface(classes: inlineClasses), .inline)
        XCTAssertNil(Approval.Surface(classes: ["flex", "flex-col"]))

        func item(_ role: String, _ label: String, _ value: String? = nil) -> Approval.Control {
            .init(element: root, role: role, label: label, value: value, enabled: true)
        }
        let controls = [
            item("AXStaticText", title), item("AXTextArea", "Edit permission target", target),
            item("AXRadioGroup", ""), item("AXRadioButton", "1 Yes, allow this time"),
            item("AXRadioButton", "2 Yes, and always allow 'printf' in this conversation"),
            item("AXRadioButton", "3 Yes, and always allow 'printf'"), item("AXRadioButton", "4 No"),
            item("AXTextArea", "(tell the agent what to do instead)", ""),
            Approval.Control(element: skip, role: "AXButton", label: "Skip", value: nil, enabled: true),
            Approval.Control(element: submit, role: "AXButton", label: "Submit↵", value: nil, enabled: true)
        ]
        func parse(_ items: [Approval.Control]) -> Approval.Card? {
            Approval.parseQuestionnaire(items, conversation: session, element: root)
        }
        for (index, scope) in [(3, Approval.Scope.once), (4, .conversation), (5, .always)] {
            var items = controls
            items[index].selected = true
            let card = try XCTUnwrap(parse(items))
            XCTAssertEqual(card.scope, scope)
            XCTAssertEqual(card.content, title + "\n" + target + "\n" + String(items[index].label.dropFirst(2)))
            XCTAssertEqual(card.allow, submit)
            XCTAssertEqual(card.deny, skip)
        }

        var items = controls
        XCTAssertNil(parse(items))
        items[3].selected = true
        XCTAssertNil(parse(items.filter { $0.label != "Edit permission target" }))
        XCTAssertNil(parse(items + [items[9]]))
        XCTAssertNil(parse(items.filter { $0.label != "Skip" }))
        items[7] = item("AXTextArea", "Deny note", "please do something else")
        XCTAssertNil(parse(items))
        items = controls
        items[6].selected = true
        XCTAssertNil(parse(items))
        items[3].selected = true
        XCTAssertNil(parse(items))
        items = controls
        items[5] = item("AXRadioButton", "3 Yes, and always allow")
        items[5].selected = true
        XCTAssertNil(parse(items))
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
            XCTAssertFalse(live.windows.isEmpty, "The live quota check requires at least one measured window")
        }
    }

    func testAGYMeasuredWindowsAndDesktopFallback() throws {
        let json = #"""
        {"status":"SUCCESS","command":{"name":"usage","data":{"groups":[{"name":"Claude and GPT models","buckets":[
          {"window":"weekly","remaining_fraction":0,"reset_time":"2026-11-30T06:05:21Z"},
          {"window":"5h","remaining_fraction":1},{"window":"missing"},{"window":"bad","remaining_fraction":true},
          {"window":"disabled","remaining_fraction":1,"disabled":true}]}]}}}
        """#
        let account = try XCTUnwrap(AntigravityCLI.decode(Data(json.utf8)))
        XCTAssertEqual(account.windows.map(\.remaining), [0, 100])
        XCTAssertEqual(account.windows.map(\.title), ["Claude/GPT weekly", "Claude/GPT 5-hour"])
        XCTAssertNotNil(account.windows.first?.resetsAt)
        XCTAssertNil(account.plan)
        XCTAssertNil(AntigravityCLI.decode(Data(json.replacingOccurrences(of: "SUCCESS", with: "ERROR").utf8)))
        XCTAssertEqual(AntigravityAccount.read(cli: { account }, desktop: { _ in
            XCTFail("A valid CLI result should keep the desktop untouched"); return nil
        }), account)
        XCTAssertEqual(AntigravityAccount.read(manual: true, cli: { nil }, desktop: { manual in
            XCTAssertTrue(manual); return account
        }), account)
    }

    func testBundledAGYUsesPassiveEnvironmentAndInstalledBinaryTakesPriority() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let apps = home.appendingPathComponent("Applications")
        let bundled = apps.appendingPathComponent("Gemini.app/Contents/Helpers/agy")
        let installed = home.appendingPathComponent(".local/bin/agy")
        defer { try? FileManager.default.removeItem(at: home) }
        let script = """
        #!/bin/sh
        [ "$AGY_CLI_DISABLE_AUTO_UPDATE" = true ] && [ "$BROWSER" -ef "./open" ] || exit 1
        [ "$(command -v open)" -ef "./open" ] && [ "$(command -v xdg-open)" -ef "./xdg-open" ] || exit 2
        [ "$1" = --version ] && { echo 'agy 1.5.14'; exit 0; }
        [ "$*" = '-p /usage --output-format json' ] || exit 3
        echo '{"status":"SUCCESS","command":{"name":"usage","data":{"groups":[{"name":"Gemini Models","buckets":[{"window":"weekly","remaining_fraction":0.42}]}]}}}'
        """
        for executable in [bundled, installed] {
            try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(script.utf8).write(to: executable)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
            let located = AntigravityCLI.executable(home: home, path: "", systemBins: [], systemApplications: apps)
            XCTAssertEqual(located, executable)
            XCTAssertEqual(AntigravityCLI.read(executable: executable)?.windows.first?.remaining, 42)
        }
    }

    func testNativeQuotaSourcesUseAccountEndpointsAndMeasuredValues() async throws {
        typealias Object = [String: Any]
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let directory = home.appendingPathComponent(".gemini")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try JSONSerialization.data(withJSONObject: ["access_token": "fixture"]).write(to: directory.appendingPathComponent("oauth_creds.json"))
        let cases: [(IslandAgentProvider, String, Object, [Int])] = [
            (.dsh, "api.deepseek.com/user/balance", ["balance_infos": [["currency": "CNY", "total_balance": "1.23"]]], []),
            (.kimiCode, "api.kimi.com/coding/v1/usages", ["usages": ["limit_5h": ["used_ratio": 0], "limit_7d": ["used_ratio": 1]]], [100, 0]),
            (.openCode, "opencode.ai/zen/go/v1/usage", ["usage": ["rolling": ["usagePercent": 1], "monthly": ["usedMicroCents": 37, "limitMicroCents": 100]]], [99, 63]),
            (.copilotCLI, "api.github.com/copilot_internal/user", ["quota_snapshots": ["chat": ["entitlement": 80, "remaining": 20]]], [25]),
            (.cursor, "cursor.com/api/usage-summary", ["individualUsage": ["plan": ["totalPercentUsed": 42]]], [58]),
            (.geminiCLI, "cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota", ["buckets": [["modelId": "gemini-pro", "remainingFraction": 0.5]]], [50]),
            (.devinDesktop, "app.devin.ai/api/org/test-org/billing/quota/usage", ["daily_percentage": 0.3, "weekly_percentage": 1], [70, 99])
        ]
        for (provider, endpoint, json, expected) in cases {
            let client = NativeQuotaClient(home: home, environment: [:]) { request in
                let url = try XCTUnwrap(request.url)
                XCTAssertEqual(url.scheme, "https")
                if url.path.hasSuffix("loadCodeAssist") {
                    return try JSONSerialization.data(withJSONObject: ["cloudaicompanionProject": "fixture-project"])
                }
                if provider == .cursor, url.path != "/api/usage-summary" { throw URLError(.resourceUnavailable) }
                XCTAssertEqual((url.host ?? "") + url.path, endpoint)
                if provider == .geminiCLI {
                    let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: String])
                    XCTAssertEqual(body["project"], "fixture-project")
                }
                return try JSONSerialization.data(withJSONObject: json)
            }
            let input = try JSONEncoder().encode(["credential": "fixture", "organization": "test-org"])
            let report = try await client.fetch(provider, credentialData: input)
            XCTAssertEqual(report.windows.map(\.remaining), expected, provider.displayName)
            XCTAssertEqual(report.provider, provider.quotaSource)
            if provider == .dsh { XCTAssertEqual(report.balance, "1.23 CNY") }
            XCTAssertNil(NativeQuotaResponse.report(for: provider, json: [:]))
        }
        XCTAssertEqual(IslandAgentProvider.devinCLI.quotaSource, IslandAgentProvider.devinDesktop.quotaSource)
    }

    private func cursorFixture(_ home: URL, token: String) throws {
        let path = home.appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_open(path.path, &db), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(db, "CREATE TABLE IF NOT EXISTS ItemTable(key TEXT PRIMARY KEY, value TEXT)", nil, nil, nil), SQLITE_OK)
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        XCTAssertEqual(sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO ItemTable VALUES ('cursorAuth/accessToken', ?)", -1, &statement, nil), SQLITE_OK)
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, token, -1, transient)
        XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE)
    }

    func testDeepSeekBalanceUsesDSHStoreAndPreservesExplicitPriority() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let directory = home.appendingPathComponent("custom-dsh")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let credentials = directory.appendingPathComponent(".credentials.yaml")
        let yaml = """
        version: 1
        refs:
          OPENAI_API_KEY: unrelated
          DEEPSEEK_API_KEY: 'sk-dsh-fixture'  # active DeepSeek reference
        records: {}
        """
        try Data(yaml.utf8).write(to: credentials)
        for (saved, env, expected) in [(nil, nil, "sk-dsh-fixture"), (nil, "env", "env"), ("saved", "env", "saved")] as [(String?, String?, String)] {
            var environment = ["DSH_HOME": directory.path]
            environment["DEEPSEEK_API_KEY"] = env
            let client = NativeQuotaClient(home: home, environment: environment, load: { request in
                XCTAssertEqual(request.url?.absoluteString, "https://api.deepseek.com/user/balance")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer " + expected)
                return Data(#"{"balance_infos":[{"currency":"CNY","total_balance":"1.23"}]}"#.utf8)
            })
            let manual = try saved.map { try JSONEncoder().encode(["credential": $0]) } ?? Data()
            let balance = try await client.fetch(.dsh, credentialData: manual)
            XCTAssertEqual(balance.balance, "1.23 CNY")
        }
    }

    func testDeepSeekDiscardsRotatedKeyAndIgnoresOtherProviders() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let directory = home.appendingPathComponent(".dsh")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let credentials = directory.appendingPathComponent(".credentials.yaml")
        let active = "version: 1\nrefs: {DEEPSEEK_API_KEY: sk-old}\n"
        let unrelated = "version: 1\nrefs: {OPENAI_API_KEY: sk-other}\nrecords: {unrelated: {DEEPSEEK_API_KEY: sk-nested}}"
        try Data(active.utf8).write(to: credentials)
        let rotates = NativeQuotaClient(home: home, environment: [:], load: { _ in
            try Data(active.replacingOccurrences(of: "sk-old", with: "sk-new").utf8).write(to: credentials)
            return Data(#"{"balance_infos":[{"currency":"CNY","total_balance":"1.23"}]}"#.utf8)
        })
        do { _ = try await rotates.fetch(.dsh, credentialData: Data()); XCTFail("Discard stale account balance") }
        catch let error as URLError { XCTAssertEqual(error.code, .userAuthenticationRequired) }

        for (yaml, environment) in [(unrelated, [:]), (active, ["DEEPSEEK_BASE_URL": "https://example.invalid"]),
                                    ("version: 2\nrefs: {DEEPSEEK_API_KEY: sk-other}", [:]),
                                    ("version: 1\nrefs: {DEEPSEEK_API_KEY: sk-a, DEEPSEEK_API_KEY: sk-b}", [:])] {
            try Data(yaml.utf8).write(to: credentials)
            let client = NativeQuotaClient(home: home, environment: environment, load: { _ in
                XCTFail("Missing or ambiguous DeepSeek identity must not make a request")
                throw URLError(.badURL)
            })
            do { _ = try await client.fetch(.dsh, credentialData: Data()); XCTFail("Expected missing login") }
            catch let error as URLError { XCTAssertEqual(error.code, .userAuthenticationRequired) }
        }
    }

    func testInstalledDSHBalanceWhenRequested() async throws {
        guard ProcessInfo.processInfo.environment["QV_VERIFY_INSTALLED_DSH_BALANCE"] == "1" else {
            throw XCTSkip("Requires an explicitly requested read of this Mac's DeepSeek balance")
        }
        let report = try await NativeQuotaClient().fetch(.dsh, credentialData: Data())
        XCTAssertTrue(report.balance?.isEmpty == false)
    }

    func testCursorUsesLocalLoginWithoutCopyingItToQuotaView() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        try cursorFixture(home, token: "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiAiYXV0aDB8Zml4dHVyZS11c2VyIn0.fixture")
        let client = NativeQuotaClient(home: home, environment: [:], readSecret: { _, _ in
            XCTFail("A desktop login must not fall through to another account"); return nil
        }) { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "WorkosCursorSessionToken=fixture-user%3A%3AeyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiAiYXV0aDB8Zml4dHVyZS11c2VyIn0.fixture")
            if request.url?.path != "/api/usage-summary" { throw URLError(.resourceUnavailable) }
            return Data(#"{"individualUsage":{"plan":{"totalPercentUsed":42}}}"#.utf8)
        }
        let report = try await client.fetch(.cursor, credentialData: Data())
        XCTAssertEqual(report.windows.first?.remaining, 58)
    }

    func testSavedQuotaCredentialsKeepPriorityOverAutomaticDiscovery() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for provider in [IslandAgentProvider.cursor, .copilotCLI] {
            let client = NativeQuotaClient(home: home, environment: [:], readSecret: { _, _ in
                XCTFail("Explicit credentials must retain priority"); return nil
            }) { request in
                if provider == .cursor {
                    XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "fixture-saved")
                    if request.url?.path != "/api/usage-summary" { throw URLError(.resourceUnavailable) }
                    return Data(#"{"individualUsage":{"plan":{"totalPercentUsed":42}}}"#.utf8)
                }
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "token fixture-saved")
                return Data(#"{"quota_snapshots":{"chat":{"entitlement":10,"remaining":3}}}"#.utf8)
            }
            _ = try await client.fetch(provider, credentialData: JSONEncoder().encode(["credential": "fixture-saved"]))
        }
    }

    func testCursorDiscardsResponseWhenLocalAccountChanges() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        try cursorFixture(home, token: "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiAiYXV0aDB8b2xkLWFjY291bnQifQ.fixture")
        let client = NativeQuotaClient(home: home, environment: [:]) { request in
            if request.url?.path != "/api/usage-summary" { throw URLError(.resourceUnavailable) }
            try self.cursorFixture(home, token: "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiAiYXV0aDB8bmV3LWFjY291bnQifQ.fixture")
            return Data(#"{"individualUsage":{"plan":{"totalPercentUsed":42}}}"#.utf8)
        }
        do { _ = try await client.fetch(.cursor, credentialData: Data()); XCTFail("Old-account data must not publish") }
        catch { XCTAssertEqual((error as? URLError)?.code, .userAuthenticationRequired) }
    }

    func testCopilotReusesItsOwnKeychainLoginAndRestrictsBackgroundPrompts() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var permissions: [Bool] = []
        let client = NativeQuotaClient(home: home, environment: [:], readSecret: { service, prompt in
            XCTAssertEqual(service, "copilot-cli"); permissions.append(prompt); return "fixture-login"
        }, allowCredentialPrompt: true) { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "token fixture-login")
            return Data(#"{"quota_snapshots":{"chat":{"entitlement":10,"remaining":3}}}"#.utf8)
        }
        let result = try await client.fetch(.copilotCLI, credentialData: Data())
        XCTAssertEqual(result.windows.first?.remaining, 30)
        XCTAssertEqual(permissions, [true, false])
    }

    func testEnterpriseCopilotLoginNeverGoesToPublicGitHub() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let dir = home.appendingPathComponent(".copilot")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try Data(#"{"last_logged_in_user":{"host":"https://github.example.test","login":"fixture"}}"#.utf8)
            .write(to: dir.appendingPathComponent("config.json"))
        let client = NativeQuotaClient(home: home, environment: [:], readSecret: { _, _ in
            XCTFail("Enterprise credentials must not be selected"); return nil
        }) { _ in XCTFail("Must not send enterprise credentials to public GitHub"); return Data() }
        do { _ = try await client.fetch(.copilotCLI, credentialData: Data()); XCTFail("Unsupported enterprise source") }
        catch { XCTAssertEqual((error as? URLError)?.code, .userAuthenticationRequired) }
    }

    func testGeminiQuotaUsesTheSameCustomHomeAsItsTaskIntegration() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let dir = root.appendingPathComponent("custom/.gemini")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(#"{"access_token":"fixture-custom"}"#.utf8).write(to: dir.appendingPathComponent("oauth_creds.json"))
        let client = NativeQuotaClient(home: root, environment: ["GEMINI_CLI_HOME": root.appendingPathComponent("custom").path]) { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-custom")
            if request.url?.path.hasSuffix("loadCodeAssist") == true { return Data(#"{"cloudaicompanionProject":"fixture"}"#.utf8) }
            return Data(#"{"buckets":[{"modelId":"gemini-pro","remainingFraction":0.5}]}"#.utf8)
        }
        let result = try await client.fetch(.geminiCLI, credentialData: Data())
        XCTAssertEqual(result.windows.first?.remaining, 50)
    }

    @MainActor
    func testOneStepQuotaSetupKeepsOptOutAndSharesDevinPreference() {
        let suite = "QuotaView.OneStep." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults), island = IslandSession()
        defer { island.stop() }
        let store = AgentQuotaStore(preferences: preferences, defaults: defaults, island: island)
        store.connect(.cursor)
        XCTAssertTrue(store.isEnabled(.cursor))
        store.enable(false, for: .cursor)
        store.connect(.cursor)
        XCTAssertFalse(store.isEnabled(.cursor))
        store.connect(.devinCLI)
        XCTAssertTrue(store.isEnabled(.devinDesktop))
        store.enable(false, for: .devinDesktop)
        store.connect(.devinCLI)
        XCTAssertFalse(store.isEnabled(.devinCLI))
        XCTAssertFalse(preferences.claudeCodeStatusLineEnabled)
    }

    func testNativeQuotaNeverInventsRemainingAllowance() async {
        XCTAssertNil(NativeQuotaResponse.report(for: .copilotCLI, json: ["quota_snapshots":
            ["chat": ["entitlement": 0, "remaining": 0, "percent_remaining": 100]]]))
        XCTAssertNil(NativeQuotaResponse.report(for: .cursor, json: ["sand": ["usagePercent": 0]]))
        XCTAssertNil(NativeQuotaResponse.report(for: .kimiCode, json: ["usages": ["limit_5h": ["used_ratio": false]]]))
        let emptyHome = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let client = NativeQuotaClient(home: emptyHome, environment: [:], load: { _ in
            XCTFail("Request without credentials")
            return Data()
        })
        do {
            _ = try await client.fetch(.dsh, credentialData: Data())
            XCTFail("Missing credentials must leave quota unavailable")
        } catch { XCTAssertEqual((error as? URLError)?.code, .userAuthenticationRequired) }
    }

    func testAGYLocatorRecognizesUserInstall() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bin = home.appendingPathComponent(".local/bin")
        let exe = bin.appendingPathComponent("agy")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try Data().write(to: exe)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: exe.path)
        XCTAssertNotEqual(AntigravityCLI.executable(home: home, path: ""), exe)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: exe.path)
        XCTAssertEqual(AntigravityCLI.executable(home: home, path: ""), exe)
    }

    func testAntigravityDesktopQuotaRows() throws {
        typealias Row = AntigravityDesktopQuota.PageItem
        let now = Date()
        let rows: [Row] = [
            .init(heading: true, text: "Plan"),
            .init(heading: false, text: "Your Plan: "), .init(heading: false, text: "Google AI Pro"),
            .init(heading: true, text: "Gemini Models"),
            .init(heading: false, text: "Weekly Limit Remaining"),
            .init(heading: false, text: "You have used some of your weekly limit, it will fully refresh in 6 days, 5 hours."),
            .init(heading: false, text: "98%"), .init(heading: false, text: "Five Hour Limit Remaining"),
            .init(heading: false, text: "94%"), .init(heading: true, text: "Claude and GPT models"),
            .init(heading: false, text: "Weekly Limit Remaining"), .init(heading: false, text: "100%"),
            .init(heading: false, text: "Five Hour Limit Remaining"), .init(heading: false, text: "0%"),
            .init(heading: true, text: "Gemini 4 Argon"),
            .init(heading: false, text: "Gemini 4 Argon Weekly Limit"), .init(heading: false, text: "85%"),
            .init(heading: true, text: "Other usage"), .init(heading: false, text: "50%")
        ]
        let result = try XCTUnwrap(AntigravityDesktopQuota.parse(rows, at: now))
        XCTAssertEqual(result.plan, "Google AI Pro")
        XCTAssertEqual(result.windows.map(\.remaining), [98, 94, 100, 0, 85])
        XCTAssertEqual(result.windows.first?.resetsAt, now.addingTimeInterval(149 * 3600))
        XCTAssertNil(AntigravityDesktopQuota.parse([.init(heading: true, text: "Gemini Models"),
            .init(heading: false, text: "Weekly Limit Used"), .init(heading: false, text: "100%")], at: now))
    }

    func testAntigravityDirectDesktopAccountWhenRequested() throws {
        guard ProcessInfo.processInfo.environment["QV_SMOKE_ANTIGRAVITY_DESKTOP"] == "1" else {
            throw XCTSkip("Requires a signed-in Antigravity desktop window and Accessibility")
        }
        let result = try XCTUnwrap(AntigravityDesktopQuota.read(manual: ProcessInfo.processInfo.environment["QV_DESKTOP_AUTOMATIC"] != "1"))
        XCTAssertFalse(result.windows.isEmpty)
        print("Desktop quota:", result.windows.map { "\($0.title) \($0.remaining)%" }.joined(separator: ", "))
    }

    func testAntigravityOfflineQuotaIgnoresPlaceholder() throws {
        let json = #"[{"provider":"antigravity","source":"offline","usage":{"updatedAt":"2026-11-23T03:43:28Z","loginMethod":"offline","primary":null,"extraRateWindows":[{"id":"antigravity-offline-conversations","title":"Offline · 10 conversations","usageKnown":false,"window":{"usedPercent":0}}]}}]"#
        let account = try XCTUnwrap(AntigravityAccount.decode(Data(json.utf8)))
        XCTAssertNil(account.displayPlan)
        XCTAssertTrue(account.windows.isEmpty)
    }

    func testAntigravityKnownWindowAtFullQuota() throws {
        let json = #"[{"provider":"antigravity","usage":{"updatedAt":"2026-11-23T03:43:28Z","extraRateWindows":[{"title":"Unknown","usageKnown":false,"window":{"usedPercent":0}},{"title":"Gemini weekly","usageKnown":true,"window":{"usedPercent":0}}]}}]"#
        let account = try XCTUnwrap(AntigravityAccount.decode(Data(json.utf8)))
        XCTAssertEqual(account.windows.map(\.title), ["Gemini weekly"])
        XCTAssertEqual(account.windows.map(\.remaining), [100])
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
    func testOpenCodeOwnerReceivesSingleAnswerAndPermission() async throws {
        try await verifyOpenCodeReplies(typedAPI: false)
    }

    @MainActor
    func testOpenCodeTypedOwnerFallbackReceivesSingleAnswerAndPermission() async throws {
        try await verifyOpenCodeReplies(typedAPI: true)
    }

    @MainActor
    private func verifyOpenCodeReplies(typedAPI: Bool) async throws {
        let root=URL(fileURLWithPath:"/private/tmp/qv-ask-"+UUID().uuidString.prefix(8))
        try FileManager.default.createDirectory(at:root.appendingPathComponent("config"),withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let suite="QuotaView.OpenCodeExitSmoke."+UUID().uuidString
        let defaults=try XCTUnwrap(UserDefaults(suiteName:suite))
        defer { defaults.removePersistentDomain(forName:suite) }
        let preferences=AppPreferences(defaults:defaults), island=IslandSession()
        preferences.openCodeEnabled=true; preferences.codexActivityIslandEnabled=true
        preferences.openCodeInteractionsEnabled=true
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
        const replies=[];
        const raw={post:async opts=>{replies.push([opts.url,opts.body]);return {data:true,response:{ok:true}};}};
        const typed=type=>({reply:async ({requestID,...body})=>raw.post({url:'/'+type+'/'+requestID+'/reply',body})});
        let client=\(typedAPI ? "{permission:typed('permission'),question:typed('question')}" : "{_client:raw}");
        if (\(typedAPI) && process.env.QV_OPENCODE_SDK) {
          const {createOpencodeClient}=await import(process.env.QV_OPENCODE_SDK);
          client=createOpencodeClient({baseUrl:'http://fixture.invalid',directory:'/isolated',fetch:async req=>{
            const url=new URL(req.url);
            if(url.hostname!=='fixture.invalid' || req.headers.get('x-opencode-directory')!==encodeURIComponent('/isolated')) throw Error('Wrong instance');
            replies.push([url.pathname,await req.json()]);
            return Response.json(true);
          }});
        }
        const plugin=await QuotaView({client});
        const emit=(type,properties)=>plugin.event({event:{type,properties:{sessionID:'session1',...properties}}});
        await emit('session.status',{status:{type:'busy'}});
        await emit('question.asked',{id:'que_1',questions:[{question:'Choose a color',options:[{label:'Blue'},{label:'Orange'}]}]});
        await emit('permission.asked',{id:'per_2',permission:'read',patterns:['file.txt']});
        for(let i=0;i<300 && replies.length!==2;i++) await new Promise(r=>setTimeout(r,20));
        const expected=[['/permission/per_2/reply',{reply:'reject'}],['/question/que_1/reply',{answers:[['Orange']]}]];
        if(JSON.stringify(replies.sort())!==JSON.stringify(expected)) throw Error(JSON.stringify(replies));
        await emit('session.idle',{});
        """
        let file = root.appendingPathComponent("owner.mjs")
        try script.write(to: file, atomically: true, encoding: .utf8)
        async let run = execute(URL(fileURLWithPath: "/usr/bin/env"), arguments: ["node",file.path])
        for kind in [IslandCodexApprovalRequest.Kind.questions, .command] {
            try await waitFor { island.model.tasks.contains { task in task.requests.contains { $0.value.protocolRequest?.kind == kind } } }
            let task = try XCTUnwrap(island.model.tasks.first)
            let pending = try XCTUnwrap(task.requests.first { $0.value.protocolRequest?.kind == kind })
            let wire = try XCTUnwrap(pending.value.protocolRequest)
            let result: IslandApprovalJSON
            if kind == .questions {
                var draft = IslandApprovalDraft()
                draft.selectAnswer("Orange", for: try XCTUnwrap(wire.questions.first))
                result = try XCTUnwrap(draft.result(for: wire))
            } else { result = try XCTUnwrap(wire.actions.first { $0.result["decision"].text == "decline" }?.result) }
            island.model.submit(task.id, requestID: pending.value.id, decision: .reply(result))
        }
        let outcome = try await run
        XCTAssertEqual(outcome.0, 0, outcome.1)
        try await waitFor { island.model.tasks.allSatisfy { $0.requests.isEmpty } }
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
