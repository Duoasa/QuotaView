import Darwin
import Foundation
import XCTest
import QuotaViewActivityHookSupport
@testable import QuotaView

final class NativeAgentExpansionTests: XCTestCase {
    func testOfficialHookMappingFiltersPrivateDataAndSubagentStops() throws {
        let cases: [(String, String, [String: Any], String)] = [
            ("cursor", "beforeSubmitPrompt", ["conversation_id": "s", "generation_id": "g"], "UserPromptSubmit"),
            ("cursor", "stop", ["conversation_id": "s", "status": "completed"], "Stop"),
            ("cursor", "stop", ["conversation_id": "s", "status": "aborted"], "Interrupt"),
            ("cursor", "stop", ["conversation_id": "s", "status": "error"], "StopFailure"),
            ("geminiCLI", "BeforeAgent", ["session_id": "s"], "UserPromptSubmit"),
            ("geminiCLI", "AfterAgent", ["session_id": "s"], "Stop"),
            ("geminiCLI", "Notification", ["session_id": "s", "notification_type": "ToolPermission"], "PermissionRequest"),
            ("copilotCLI", "userPromptSubmitted", ["sessionId": "s"], "UserPromptSubmit"),
            ("copilotCLI", "agentStop", ["sessionId": "s", "stopReason": "end_turn"], "Stop"),
            ("copilotCLI", "errorOccurred", ["sessionId": "s", "recoverable": false], "StopFailure"),
            ("copilotCLI", "notification", ["sessionId": "s", "notification_type": "permission_prompt"], "PermissionRequest"),
            ("kimiCode", "Stop", ["session_id": "s", "agent_id": "child"], "Stop")
        ]
        for (provider, event, values, expected) in cases {
            var input = values
            for key in ["prompt", "prompt_response", "tool_input", "toolArgs", "transcript_path", "apiKey", "message", "cwd"] { input[key] = "PRIVATE_SENTINEL" }
            let output = try XCTUnwrap(NativeAgentHookNormalizer.normalize(input, provider: provider, event: event))
            XCTAssertEqual(output["hook_event_name"] as? String, expected)
            XCTAssertEqual(output["session_id"] as? String, "s")
            XCTAssertFalse(String(decoding: try JSONSerialization.data(withJSONObject: output), as: UTF8.self).contains("PRIVATE_SENTINEL"))
        }
        XCTAssertNil(NativeAgentHookNormalizer.normalize(["sessionId":"s"], provider: "copilotCLI", event: "subagentStop"))
        XCTAssertNil(NativeAgentHookNormalizer.normalize(["conversation_id":"s"], provider: "cursor", event: "subagentStop"))
        XCTAssertNil(NativeAgentHookNormalizer.normalize(["sessionId":"s", "recoverable":true], provider: "copilotCLI", event: "errorOccurred"))
        XCTAssertNil(NativeAgentHookNormalizer.normalize(["conversation_id":"s"], provider: "cursor", event: "stop"))
        XCTAssertNil(NativeAgentHookNormalizer.normalize(["sessionId":"s", "notification_type":"agent_completed"], provider: "copilotCLI", event: "notification"))
        let metadata = NativeAgentHookNormalizer.normalize(["session_id":"s", "llm_request":["model":"gemini", "messages":["PRIVATE"]]], provider:"geminiCLI", event:"BeforeModel")
        XCTAssertEqual(metadata?["model"] as? String, "gemini")
        XCTAssertNil(metadata?["llm_request"])
        for provider in ["cursor", "geminiCLI", "copilotCLI"] {
            let data = try XCTUnwrap(NativeAgentHookNormalizer.neutralOutput(provider: provider, event: "BeforeTool"))
            XCTAssertEqual(String(decoding: data, as: UTF8.self), "{}\n")
        }
    }

    func testInstallIsIdempotentAndDisablePreservesForeignConfiguration() throws {
        for provider: IslandAgentProvider in [.cursor, .geminiCLI, .openCode, .copilotCLI] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let home = root.appendingPathComponent("home"), support = root.appendingPathComponent("support")
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            let helper = root.appendingPathComponent("helper")
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: helper); chmod(helper.path, 0o700)
            let installer = NativeAgentInstaller(provider:provider,socketURL:root.appendingPathComponent("events.sock"),authenticationToken:"fixture",
                homeOverride:home,supportOverride:support,helperOverride:helper)
            let file: URL
            switch provider {
            case .cursor: file = home.appendingPathComponent("hooks.json")
            case .geminiCLI: file = home.appendingPathComponent("settings.json")
            case .openCode: file = home.appendingPathComponent("plugins/" + installer.marker + ".js")
            default: file = home.appendingPathComponent("hooks/" + installer.marker + ".json")
            }
            let foreign: [String: Any] = provider == .geminiCLI ? ["matcher":"Bash", "hooks":[["type":"command", "command":"foreign-command"]]] : ["command":"foreign-command"]
            let event = provider == .geminiCLI ? "BeforeTool" : "stop"
            if provider == .cursor || provider == .geminiCLI {
                try JSONSerialization.data(withJSONObject:["hooks":[event:[foreign]], "userPreference":"preserve"]).write(to:file)
            }
            XCTAssertEqual(try installer.configure(enabled:true).map(\.path), [home.path])
            let once = try Data(contentsOf:file)
            _ = try installer.configure(enabled:true)
            XCTAssertEqual(try Data(contentsOf:file), once)
            XCTAssertEqual((try FileManager.default.attributesOfItem(atPath:installer.route.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
            _ = try installer.configure(enabled:false)
            _ = try installer.configure(enabled:false)
            if provider == .cursor || provider == .geminiCLI {
                let clean = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:file)) as? [String:Any])
                XCTAssertEqual(clean["userPreference"] as? String, "preserve")
                let hooks = try XCTUnwrap(clean["hooks"] as? [String:[[String:Any]]])
                XCTAssertEqual(hooks.count, 1)
                XCTAssertEqual(hooks[event]?.count, 1)
                XCTAssertTrue(String(decoding:try Data(contentsOf:file),as:UTF8.self).contains("foreign-command"))
                XCTAssertFalse(String(decoding:try Data(contentsOf:file),as:UTF8.self).contains("--agent-hook"))
            } else { XCTAssertFalse(FileManager.default.fileExists(atPath:file.path)) }
            XCTAssertTrue(FileManager.default.isExecutableFile(atPath:installer.helper.path), "Cached sessions retain a fail-open helper")
        }
    }

    func testMalformedOrForeignConfigurationIsNotOverwritten() throws {
        for provider: IslandAgentProvider in [.cursor,.geminiCLI,.openCode,.copilotCLI] {
            let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at:root) }
            try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
            let installer=NativeAgentInstaller(provider:provider,socketURL:root.appendingPathComponent("socket"),authenticationToken:"fixture",homeOverride:root,supportOverride:root.appendingPathComponent("support"),helperOverride:URL(fileURLWithPath:"/bin/true"))
            let name: String
            switch provider {
            case .cursor: name="hooks.json"
            case .geminiCLI: name="settings.json"
            case .openCode: name="plugins/"+installer.marker+".js"
            default: name="hooks/"+installer.marker+".json"
            }
            let file=root.appendingPathComponent(name), data=Data("USER_OWNED_INVALID_CONFIG".utf8)
            try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
            try data.write(to:file)
            XCTAssertThrowsError(try installer.configure(enabled:true))
            XCTAssertEqual(try Data(contentsOf:file),data)
            XCTAssertFalse(FileManager.default.fileExists(atPath:installer.route.path))
        }
    }

    func testOpenCodePluginDeliversOrderedEventsAndKeepsChildAndFailureSeparate() async throws {
        let root=URL(fileURLWithPath:"/private/tmp/qv-open-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let route=String(data:try JSONEncoder().encode(root.appendingPathComponent("route.json").path),encoding:.utf8)!
        try NativeAgentOpenCodePlugin.source.replacingOccurrences(of:"__ROUTE_PATH__",with:route)
            .write(to:root.appendingPathComponent("adapter.mjs"),atomically:true,encoding:.utf8)
        let script = #"""
import {createServer} from 'node:net';
import {writeFileSync} from 'node:fs';
import assert from 'node:assert/strict';
import {QuotaView} from './adapter.mjs';
const messages=[];
const path=new URL('./events.sock',import.meta.url).pathname;
const server=createServer(socket=>{let body='';socket.on('data',chunk=>{body+=chunk;if(body.endsWith('\n')){messages.push(JSON.parse(body));socket.end('{"accepted":true}\n');}});});
await new Promise(r=>server.listen(path,r));
writeFileSync(new URL('./route.json',import.meta.url),JSON.stringify({version:1,socketPath:path,authenticationToken:'fixture',agentProvider:'openCode'}),{mode:0o600});
try {
 const plugin=await QuotaView();
 const event=async(type,properties)=>plugin.event({event:{type,properties}});
 await event('session.created',{info:{id:'parent',title:'Public title'}});
 await event('session.status',{sessionID:'parent',status:{type:'busy'}});
 await plugin['tool.execute.before']({sessionID:'parent',tool:'bash',callID:'call',args:'PRIVATE_ARGS'});
 await event('permission.asked',{id:'permission',sessionID:'parent',permission:'bash',metadata:'PRIVATE_META'});
 await event('permission.replied',{sessionID:'parent',requestID:'permission',reply:'once'});
 await plugin['tool.execute.after']({sessionID:'parent',tool:'bash',callID:'call',args:'PRIVATE_ARGS'}, {output:'PRIVATE_OUTPUT'});
 await event('session.created',{info:{id:'child',parentID:'parent',title:'Child'}});
 await event('session.status',{sessionID:'child',status:{type:'busy'}});
 await event('session.idle',{sessionID:'child'});
 await event('session.error',{sessionID:'parent',error:{name:'APIError',message:'PRIVATE_ERROR'}});
 await event('session.idle',{sessionID:'parent'});
 await event('session.status',{sessionID:'parent',status:{type:'busy'}});
 await event('session.status',{sessionID:'parent',status:{type:'idle'}});
 await event('session.idle',{sessionID:'parent'});
 const deadline=Date.now()+4000;
 while(messages.length<12&&Date.now()<deadline) await new Promise(r=>setTimeout(r,10));
 assert.equal(messages.length,12);
 const parent=messages.map(m=>m.payload).filter(m=>m.session_id==='parent');
 assert.deepEqual(parent.map(m=>m.hook_event_name),['Metadata','TurnStarted','PreToolUse','PermissionRequest','PermissionResult','PostToolUse','StopFailure','TurnStarted','Stop']);
 assert.notEqual(parent[1].turn_id,parent[7].turn_id);
 assert.equal(parent[3].tool_use_id,parent[4].tool_use_id);
 assert.ok(messages.filter(m=>m.payload.session_id==='child').every(m=>m.payload.parent_session_id==='parent'));
 assert.ok(messages.every(m=>m.awaitDecision===false));
 assert.ok(!JSON.stringify(messages).includes('PRIVATE_'));
 await event('server.instance.disposed',{});
 await event('session.status',{sessionID:'after-dispose',status:{type:'busy'}});
 await new Promise(r=>setTimeout(r,20));
 assert.equal(messages.length,12);
 console.log(JSON.stringify({events:messages.length,childIsolation:true,errorNotOverwrittenByIdle:true,privateDataExcluded:true}));
} finally {server.close();}
"""#
        let file=root.appendingPathComponent("smoke.mjs")
        try script.write(to:file,atomically:true,encoding:.utf8)
        let process=Process(), output=Pipe()
        process.executableURL=URL(fileURLWithPath:"/usr/bin/env")
        process.arguments=["node",file.path]; process.standardOutput=output; process.standardError=output
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning:$0.terminationStatus) }
            do { try process.run() } catch { continuation.resume(throwing:error) }
        }
        let result=String(decoding:output.fileHandleForReading.readDataToEndOfFile(),as:UTF8.self)
        XCTAssertEqual(status,0,result)
        XCTAssertTrue(result.contains("\"events\":12"),result)
    }
}
