import Foundation
import XCTest
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
