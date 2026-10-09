import Foundation
import XCTest
@testable import QuotaView

final class NativeAgentDSHPluginTests: XCTestCase {
    func testAcknowledgedEventsDrainAndRetainNamespacesWithoutPrivateContent() async throws {
        // Darwin's Unix-domain socket path limit is 104 bytes.
        let root = URL(fileURLWithPath: "/private/tmp/qv-dsh-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let route = root.appendingPathComponent("route.json")
        let routeLiteral = String(data: try JSONEncoder().encode(route.path), encoding: .utf8)!
        try NativeAgentDSHPlugin.source.replacingOccurrences(of: "__ROUTE_PATH__", with: routeLiteral)
            .write(to: root.appendingPathComponent("adapter.mjs"), atomically: true, encoding: .utf8)
        let script = #"""
        import {createServer} from 'node:net';
        import {writeFileSync} from 'node:fs';
        import assert from 'node:assert/strict';
        import {apply} from './adapter.mjs';
        const messages=[], callbacks=[], cleanup=[];
        const path=new URL('./events.sock',import.meta.url).pathname;
        const server=createServer(socket=>{
          let body=''; socket.on('data',chunk=>{
            body+=chunk;
            if(body.endsWith('\n')) { messages.push(JSON.parse(body)); socket.end('{"accepted":true}\n'); }
          });
        });
        await new Promise(resolve=>server.listen(path,resolve));
        writeFileSync(new URL('./route.json',import.meta.url),JSON.stringify({
          version:1,socketPath:path,authenticationToken:'fixture',interactiveApprovals:false
        }),{mode:0o600});
        try {
          const context=()=>({on:(_,fn)=>callbacks.push(fn),effect:fn=>cleanup.push(fn())});
          apply(context(),{sourceNamespace:'a'.repeat(64)});
          apply(context(),{sourceNamespace:'b'.repeat(64)});
          const session={header:{id:'same-session',origin:'subagent',parentSession:'parent'}};
          const events=[['turn/start',{turn:1,prompt:'PRIVATE_PROMPT'}],
            ['request/header',{header:{config:{model:'fixture-model'},apiKey:'PRIVATE_KEY'}}],
            ['session/title',{title:'Public title'}],
            ['tool/call',{name:'Bash',callId:'call-1',arguments:'PRIVATE_ARGUMENTS'}],
            ['approval/asked',{id:'approval',callId:'call-1',toolName:'Bash'}],
            ['approval/decided',{id:'approval',decision:'allow'}],
            ['assistant/message',{usage:{totalTokens:123},content:'PRIVATE_ANSWER'}],
            ['compaction/start',{}],['compaction/end',{}],
            ['turn/end',{reason:'completed'}],['turn/end',{reason:{kind:'error'}}],
            ['turn/end',{reason:'interrupted'}]];
          const expected=['TurnStarted','Metadata','Metadata','PreToolUse','PermissionRequest',
            'PermissionResult','Usage','PreCompact','PostCompact','Stop','StopFailure','Interrupt'];
          const start=Date.now();
          for(const callback of callbacks) events.forEach(([type,data],seq)=>callback(session,{type,data,seq}));
          // A non-draining socket takes nine seconds for each twelve-event queue.
          // Allow ample scheduling slack while detecting that per-message timeout.
          while(messages.length<24 && Date.now()-start<4000) await new Promise(r=>setTimeout(r,10));
          assert.equal(messages.length,24,'Acknowledgements must not stall the event queue');
          for(const namespace of ['a'.repeat(64),'b'.repeat(64)]) {
            const batch=messages.map(m=>m.payload).filter(m=>m.source_namespace===namespace);
            assert.deepEqual(batch.map(m=>m.hook_event_name),expected);
            assert.deepEqual(batch.map(m=>m.source_sequence),events.map((_,i)=>i));
            assert.ok(batch.every(m=>m.parent_session_id==='parent'));
            assert.equal(batch[6].tokens,123);
            assert.equal(batch[5].tool_use_id,'call-1');
          }
          assert.ok(messages.every(m=>m.awaitDecision===false));
          assert.ok(!JSON.stringify(messages).includes('PRIVATE_'));
          cleanup.forEach(fn=>fn());
          callbacks[0](session,{type:'turn/start',data:{turn:2},seq:999});
          await new Promise(r=>setTimeout(r,30));
          assert.equal(messages.length,24,'Disposed adapters must stop forwarding');
          console.log(JSON.stringify({events:messages.length,namespaces:2,elapsedMs:Date.now()-start}));
        } finally { cleanup.forEach(fn=>fn()); server.close(); }
        """#
        let file = root.appendingPathComponent("smoke.mjs")
        try script.write(to: file, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", file.path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
        let result = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(status, 0, result)
        XCTAssertTrue(result.contains("\"events\":24"), result)
    }
}
