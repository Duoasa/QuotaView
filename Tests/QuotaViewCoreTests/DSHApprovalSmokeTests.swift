import Foundation
import XCTest
import QuotaViewCore
@testable import QuotaView

final class DSHApprovalSmokeTests: XCTestCase {
    func testBoundedCompleteInvocationAndOneShotVocabulary() throws {
        var payload: [String: Any] = ["tool_name": "bash", "tool_use_id": "call", "tool_input": ["command": "echo fixture", "workdir": "/fixture"]]
        let wire = try DSHApproval.request(eventID: "id", sessionKey: "session", turnKey: "turn", payload: payload)
        XCTAssertTrue(wire.isDSH); XCTAssertFalse(wire.isClaudeCode)
        XCTAssertEqual(wire.actions.map { $0.result["decision"].text }, ["accept", "decline", "dshDelegate"])
        XCTAssertFalse(wire.permits(.object(["decision": .string("acceptAlways")])))
        XCTAssertEqual(IslandApprovalLayout(wire), .dshTool)
        payload["tool_input"] = ["command": String(repeating: "x", count: 70_000)]
        XCTAssertThrowsError(try DSHApproval.request(eventID: "id", sessionKey: "s", turnKey: "t", payload: payload))
        payload["tool_name"] = "unknown_plugin"; payload["tool_input"] = ["command": "echo fixture"]
        XCTAssertThrowsError(try DSHApproval.request(eventID: "id", sessionKey: "s", turnKey: "t", payload: payload))
        payload["tool_name"] = "str_replace_editor"; payload["tool_input"] = ["command": "str_replace", "path": "/fixture/a", "old_str": "old", "new_str": "new"]
        let file = try DSHApproval.request(eventID: "id", sessionKey: "s", turnKey: "t", payload: payload)
        XCTAssertTrue(file.detail.contains("old")); XCTAssertTrue(file.detail.contains("new"))
        payload["tool_input"] = ["command": "insert", "path": "/fixture/a", "new_str": "new"]
        XCTAssertThrowsError(try DSHApproval.request(eventID: "id", sessionKey: "s", turnKey: "t", payload: payload))
    }

    @MainActor
    private func waitFor(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<400 { if condition() { return }; try await Task.sleep(nanoseconds: 10_000_000) }
        XCTFail("DSH smoke timed out", file: file, line: line)
        throw CocoaError(.executableRuntimeMismatch)
    }

    @MainActor
    func testPluginSocketRuntimeDecisionsCancellationHandoffAndShutdown() async throws {
        let root = URL(fileURLWithPath: "/private/tmp/qv-dsh-" + UUID().uuidString.prefix(8))
        let profile = root.appendingPathComponent("home/profiles/desktop")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("[]\n".utf8).write(to: profile.appendingPathComponent("cordis.yml"))
        try Data(#"{"dsh":{"profile":{}}}"#.utf8).write(to: profile.appendingPathComponent("package.json"))
        let cache = root.appendingPathComponent("home/storages/session_projcache/sessions")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data(#"{"version":7,"record":{"rows":{"title":{"ver":1,"val":"Recovered session title"}}}}"#.utf8)
            .write(to: cache.appendingPathComponent("same-session.json"))
        XCTAssertEqual(NativeAgentRuntime.dshCachedTitle(home: root.appendingPathComponent("home"), sessionID: "same-session"), "Recovered session title")
        XCTAssertNil(NativeAgentRuntime.dshCachedTitle(home: root.appendingPathComponent("home"), sessionID: "../same-session"))
        let suite = "QuotaView.DSHSmoke." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults), island = IslandSession()
        preferences.dshEnabled = true
        let installer = NativeAgentInstaller(provider: .dsh, socketURL: root.appendingPathComponent("events.sock"), authenticationToken: "fixture",
            homeOverride: root.appendingPathComponent("home"), supportOverride: root.appendingPathComponent("support"), helperOverride: URL(fileURLWithPath: "/usr/bin/true"))
        let runtime = NativeAgentRuntime(provider: .dsh, preferences: preferences, island: island, defaults: defaults, installer: installer)
        defer { runtime.stop(); island.stop() }
        runtime.start(); try await waitFor { runtime.status == .waiting }
        XCTAssertEqual(runtime.configuredHomes, [installer.home])
        XCTAssertTrue(try String(contentsOf: profile.appendingPathComponent("cordis.patch.yml"), encoding: .utf8).contains("interactiveProfile: true"))
        try Data(CodexActivityPrivacy.hashIdentifier(installer.home.resolvingSymlinksInPath().standardizedFileURL.path).utf8).write(to: root.appendingPathComponent("namespace"))
        let file = root.appendingPathComponent("smoke.mjs")
        try Self.script.write(to: file, atomically: true, encoding: .utf8)
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env"); process.arguments = ["node", file.path]
        process.standardOutput = output; process.standardError = output
        let completion = Task { () throws -> Int32 in
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
                do { try process.run() } catch { continuation.resume(throwing: error) }
            }
        }
        defer { if process.isRunning { process.terminate() } }
        func pending(_ call: String) -> (Int, IslandConfirmation)? {
            for task in island.model.tasks {
                if let request = task.requests.first(where: { $0.value.protocolRequest?.params["itemId"].text == call }) {
                    return (task.id, request.value)
                }
            }
            return nil
        }
        for (call, decision) in [("allow", "accept"), ("deny", "decline"), ("delegate", "dshDelegate"), ("file", "accept")] {
            try await waitFor { pending(call)?.1.canRespond == true }
            XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("namespace"), encoding: .utf8), CodexActivityPrivacy.hashIdentifier(installer.home.resolvingSymlinksInPath().standardizedFileURL.path))
            try await waitFor { island.model.tasks.contains { $0.title == "Recovered session title" } }
            let (id, _) = try XCTUnwrap(pending(call))
            let display = island.model.display(english: false, remaining: nil, enabled: true, privacy: false)
            let request = try XCTUnwrap(display.taskDetails[id]?.confirmation)
            XCTAssertEqual(request.provider, .dsh)
            XCTAssertTrue(request.canRespond, "Final presentation must preserve the live DSH approval capability")
            XCTAssertEqual(request.protocolRequest?.actions.count, 3)
            XCTAssertEqual(island.model.tasks.first?.requests.count, 1, "Observer and interactive requests must merge")
            // A Codex transport change cannot revoke the DSH connection.
            island.model.setConnection(.connected)
            island.model.setConnection(.discovering)
            XCTAssertTrue(try XCTUnwrap(pending(call)).1.canRespond)
            island.model.submit(id, requestID: request.id, decision: .reply(.object(["decision": .string(decision)])))
        }
        try await waitFor {
            island.model.tasks.flatMap(\.requests).filter { $0.value.protocolRequest?.params["itemId"].text == "parallel" && $0.value.canRespond }.count == 2
        }
        let parallel = island.model.tasks.compactMap { task -> (Int, IslandConfirmation)? in
            guard let request = task.requests.first(where: { $0.value.protocolRequest?.params["itemId"].text == "parallel" }) else { return nil }
            return (task.id, request.value)
        }
        XCTAssertEqual(Set(parallel.map { $0.0 }).count, 2, "Copied session/call IDs in different DSH homes must remain separate")
        for (task, request) in parallel {
            let decision = request.protocolRequest?.detail.contains("echo A") == true ? "accept" : "decline"
            island.model.submit(task, requestID: request.id, decision: .reply(.object(["decision": .string(decision)])))
        }
        try await waitFor { island.model.display(english: false, remaining: nil, enabled: true, privacy: false).taskDetails.values.contains { $0.finalResponse != nil } }
        let completed = island.model.display(english: false, remaining: nil, enabled: true, privacy: false)
        let results = completed.taskDetails.values.compactMap(\.finalResponse)
        XCTAssertEqual(results.count, 1, "Failed peer turn must not publish an answer")
        let answer = try XCTUnwrap(results.first)
        XCTAssertTrue(answer.text.english.hasPrefix("# Final answer"))
        XCTAssertFalse(answer.text.english.contains("PRIVATE_REASONING"))
        XCTAssertEqual(answer.publicItem?.sourceTruncated, true)
        XCTAssertLessThanOrEqual(answer.text.english.utf8.count, 65_536)
        try Data().write(to: root.appendingPathComponent("next-turn"))
        try await waitFor { pending("cancel") != nil }
        XCTAssertTrue(island.model.display(english: false, remaining: nil, enabled: true, privacy: false).taskDetails.values.allSatisfy { $0.finalResponse == nil }, "New turn must clear the previous answer")
        let cancelled = try XCTUnwrap(pending("cancel"))
        let cancelledWire = try XCTUnwrap(cancelled.1.protocolRequest)
        try Data().write(to: root.appendingPathComponent("cancel"))
        try await waitFor { pending("disable") != nil }
        XCTAssertFalse(island.model.dshResponseCapability?(cancelledWire) ?? true)
        island.model.submit(cancelled.0, requestID: cancelled.1.id, decision: .reply(.object(["decision": .string("accept")])))
        preferences.dshInteractiveApprovals = false
        try await waitFor { pending("disable") == nil }
        let handedOff = island.model.display(english: false, remaining: nil, enabled: true, privacy: false)
        XCTAssertFalse(handedOff.taskDetails.values.contains { $0.confirmation?.canRespond == true })
        XCTAssertFalse(island.model.tasks.flatMap(\.requests).contains { $0.value.protocolRequest != nil }, "Handoff must erase private arguments")
        try await waitFor { FileManager.default.fileExists(atPath: root.appendingPathComponent("disabled-done").path) }
        preferences.dshInteractiveApprovals = true
        try Data().write(to: root.appendingPathComponent("resume"))
        try await waitFor { pending("dispose") != nil }
        try Data().write(to: root.appendingPathComponent("dispose"))
        try await waitFor { pending("shutdown") != nil || !process.isRunning }
        if pending("shutdown") == nil {
            let log = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            XCTFail(log); return
        }
        runtime.stop()
        let status = try await completion.value
        let log = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(status, 0, log)
        XCTAssertTrue(log.contains("DSH_SMOKE_PASS"), log)
        if ProcessInfo.processInfo.environment["QV_DSH_APPROVAL_PACKAGES"] != nil { XCTAssertTrue(log.contains("actualService=true"), log) }
        XCTAssertFalse(island.model.tasks.contains { island.model.provider(for: $0.key) == .dsh })
    }

    private static let script = #"""
    import assert from 'node:assert/strict';
    import {existsSync,writeFileSync,readFileSync} from 'node:fs';
    import {randomUUID} from 'node:crypto';
    import {pathToFileURL} from 'node:url';
    import {apply} from './support/quotaview-dsh.mjs';
    const deadline=setTimeout(()=>{console.error('Fixture deadline');process.exit(2)},20000);
    const base=new URL('.',import.meta.url), cleanup=[];
    const pause=ms=>new Promise(r=>setTimeout(r,ms));
    async function gate(name){while(!existsSync(new URL(name,base)))await pause(10)}
    const actual=process.env.QV_DSH_APPROVAL_PACKAGES;
    async function context(){
    let ctx, service;
    if(actual){
      const {Context}=await import(pathToFileURL(actual+'/cordis/lib/index.js'));
      const {default:Approval}=await import(pathToFileURL(actual+'/dsh-user-approval/lib/index.js'));
      ctx=new Context();await ctx.plugin(Approval);service=ctx.approval;
    }else{
      const listeners=new Map();
      ctx={on(name,fn){const list=listeners.get(name)??[];list.push(fn);listeners.set(name,list);return ()=>listeners.set(name,(listeners.get(name)??[]).filter(x=>x!==fn))},
        emit(name,...args){for(const fn of listeners.get(name)??[])fn(...args)}};
      service={async request(req){const id=randomUUID();req.agent.session.append('approval/asked',{id,callId:req.callId,toolName:req.toolName});
        const callbacks=[...(listeners.get('approval/request')??[])];
        const next=()=>Promise.resolve((callbacks.shift()??(()=> 'unavailable'))(req,next));
        const outcome=await next();req.agent.session.append('approval/decided',{id,outcome});return outcome}};
    }
    return {ctx,service};
    }
    const {ctx,service}=await context();
    ctx.on('approval/request',(req,next)=>req.callId==='policy'?'rejected':next());
    const adapter={on:ctx.on.bind(ctx),effect:fn=>cleanup.push(fn())};
    const namespace=readFileSync(new URL('namespace',base),'utf8');
    apply(adapter,{sourceNamespace:namespace,interactiveProfile:true});
    let fallbacks=0;
    const fallback=async()=>{fallbacks++;await pause(100);return 'rejected'};
    let removeFallback=ctx.on('approval/request',fallback);
    let turn=1;
    function newSession(ctx){
    let seq=0;const events=[];
    const session={header:{id:'same-session',cwd:'/fixture/workspace'},get seq(){return events.length},eventAt:i=>events[i],
      append(type,data){const event={type,data,seq:seq++};events.push(event);ctx.emit('session/event',session,event);return event}};
    return session;
    }
    const session=newSession(ctx), agent={session};
    session.append('turn/start',{turn});
    const outcomes={};
    async function run(name, tool='bash', input={command:'echo PRIVATE_FIXTURE',description:'Fixture only'}){
      const controller=new AbortController();
      session.append('tool/call',{turn,callId:name,name:tool,arguments:JSON.stringify(input)});
      const waiting=service.request({agent,callId:name,toolName:tool,reason:'Isolated smoke; no tool executes',signal:controller.signal});
      if(name==='cancel'){await gate('cancel');controller.abort()}
      if(name==='dispose'){await gate('dispose');cleanup.at(-1)()}
      const result=await waiting;outcomes[name]=result;
      session.append('tool/result',{turn,callId:name,message:{toolCallId:name}});
      if(name==='disable'){writeFileSync(new URL('disabled-done',base),'');await gate('resume')}
      await pause(30);
      return result;
    }
    assert.equal(await run('allow'),'allowed-once');
    assert.equal(await run('deny'),'rejected');
    assert.equal(await run('delegate'),'rejected');
    assert.equal(await run('file','str_replace_editor',{command:'str_replace',path:'/fixture/a',old_str:'old',new_str:'new'}),'allowed-once');
    const peer=await context(), peerCleanup=[];
    apply({on:peer.ctx.on.bind(peer.ctx),effect:fn=>peerCleanup.push(fn())},{sourceNamespace:'b'.repeat(64),interactiveProfile:true});
    peer.ctx.on('approval/request',fallback);
    const peerSession=newSession(peer.ctx);peerSession.append('turn/start',{turn});
    async function parallel(currentSession, approval, command){
      currentSession.append('tool/call',{turn,callId:'parallel',name:'bash',arguments:JSON.stringify({command})});
      const outcome=await approval.request({agent:{session:currentSession},callId:'parallel',toolName:'bash',signal:new AbortController().signal});
      currentSession.append('tool/result',{turn,callId:'parallel',message:{toolCallId:'parallel'}});return outcome;
    }
    assert.deepEqual(await Promise.all([parallel(session,service,'echo A'),parallel(peerSession,peer.service,'echo B')]),['allowed-once','rejected']);
    peerSession.append('assistant/message',{turn,message:{role:'assistant',content:[{type:'text',text:'Not a completed answer'}]}});
    peerSession.append('turn/end',{turn,reason:'error'});for(const dispose of peerCleanup)dispose();
    session.append('assistant/message',{turn,message:{role:'assistant',content:[{type:'reasoning',text:'PRIVATE_REASONING'},{type:'text',text:'# Final answer\n\n'+ 'x'.repeat(70000)}]}});
    session.append('turn/end',{turn,reason:'completed'});
    await gate('next-turn');turn=2;session.append('turn/start',{turn});
    assert.equal(await run('cancel'),'cancelled');
    assert.equal(await run('disable'),'rejected');
    assert.equal(await run('policy'),'rejected');
    assert.equal(await run('unknown','unknown_tool'),'rejected');
    assert.equal(await run('large','bash',{command:'x'.repeat(70000)}),'rejected');
    assert.equal(await run('dispose'),'rejected');
    removeFallback();
    apply(adapter,{sourceNamespace:namespace,interactiveProfile:true});
    removeFallback=ctx.on('approval/request',fallback);
    turn=3;session.append('turn/start',{turn});
    assert.equal(await run('shutdown'),'rejected');
    for(const dispose of cleanup)dispose();
    clearTimeout(deadline);
    console.log('DSH_SMOKE_PASS actualService='+Boolean(actual)+' '+JSON.stringify({outcomes,fallbacks}));
    """#
}
