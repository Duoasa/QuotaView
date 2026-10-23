"use strict";
const {test}=require("node:test"), assert=require("node:assert/strict"), {EventEmitter}=require("node:events");
const {CodexDesktop}=require("../src/core/codex-desktop.cjs");
const P=require("../src/core/codex-desktop-state.cjs");
const thread="desktop-thread", turn="turn-1";
const command=(id=10)=>({id,method:"item/commandExecution/requestApproval",params:{threadId:thread,turnId:turn,command:"echo approval-test",cwd:"C:/test",availableDecisions:["accept","decline"]}});
const state=(requests=[command()])=>({id:thread,title:"Approval test",cwd:"C:/test",requests,turns:[{turnId:turn,status:"inProgress",items:[]}]});
function fixture(t,initial=state()) {
  const socket=new EventEmitter(); socket.destroy=()=>{};
  let data=initial,revision=0,writeHook=null; const sent=[];
  const deliver=(m,split=false)=>{
    const body=Buffer.from(JSON.stringify(m)),h=Buffer.alloc(4);h.writeUInt32LE(body.length);
    const frame=Buffer.concat([h,body]);
    if(split){socket.emit("data",frame.subarray(0,2));socket.emit("data",frame.subarray(2,8));socket.emit("data",frame.subarray(8));}
    else socket.emit("data",frame);
  };
  const snapshot=()=>deliver({type:"broadcast",method:"thread-stream-state-changed",version:11,sourceClientId:"owner",targetClientIds:["follower"],params:{conversationId:thread,hostId:"local",change:{type:"snapshot",revision:++revision,conversationState:structuredClone(data)}}},true);
  socket.write=(b)=>{
    const m=JSON.parse(b.subarray(4));sent.push(m);
    setImmediate(()=>{
      if(writeHook?.(m)===false)return;
      if(m.type==="request")deliver({type:"response",requestId:m.requestId,method:m.method,resultType:"success",handledByClientId:"owner",result:m.method==="initialize"?{clientId:"follower"}:m.method==="thread-owner-discovery"?{supportsUntrustedAppInput:true}:m.method==="thread-follower-steer-turn"?{result:{turnId:turn}}:{ok:true}});
      else if(m.method==="thread-stream-following-changed"&&m.params.following)snapshot();
    });
  };
  const client=new CodexDesktop({connector:()=>{setImmediate(()=>socket.emit("connect"));return socket;}});
  client.sync([thread]);client.start();t.after(()=>client.stop());
  return {client,sent,socket,snapshot,deliver,setState:v=>{data=v;},onWrite:fn=>{writeHook=fn;},get data(){return data;},approval:()=>client.overlay(null,thread)?.approval};
}
async function until(fn){for(let i=0;i<100;i++){if(fn())return;await new Promise(r=>setTimeout(r,5));}throw Error("condition not reached");}
test("desktop approval is owner-scoped, refreshed before dispatch, and sent exactly once",async t=>{
  const f=fixture(t);await until(()=>f.approval()?.canRespond);
  const id=f.approval().id;assert.equal(f.client.overlay(null,thread).status,"waiting");
  const result=await f.client.respond(id,"accept");assert.equal(result.accepted,true);
  const sent=f.sent.filter(m=>m.method==="thread-follower-command-approval-decision");
  assert.equal(sent.length,1);assert.deepEqual(sent[0].params,{conversationId:thread,requestId:10,decision:"accept"});assert.equal(sent[0].targetClientId,"owner");
  await assert.rejects(f.client.respond(id,"accept"),/already_submitted/);
  assert.equal(f.approval().canRespond,false);
  f.data.requests=[];f.snapshot();assert.equal(f.approval(),null);assert.equal(f.client.overlay(null,thread).status,"working");
});
test("desktop rejection preserves string request IDs and never grants session permission",async t=>{
  const f=fixture(t,state([command("10")]));await until(()=>f.approval());
  await assert.rejects(f.client.respond(f.approval().id,"acceptForSession"),/invalid_approval/);
  await f.client.respond(f.approval().id,"decline");
  const m=f.sent.find(m=>m.method==="thread-follower-command-approval-decision");assert.equal(m.params.requestId,"10");assert.equal(m.params.decision,"decline");
});
test("stale, forged, changed-turn, changed-content, and disconnected requests cannot dispatch",async t=>{
  for(const change of [s=>{s.requests=[];},s=>{s.turns[0].turnId="next";},s=>{s.requests[0].params.command="different";}]){
    const f=fixture(t);await until(()=>f.approval());const id=f.approval().id;
    change(f.data);await assert.rejects(f.client.respond(id,"accept"),/stale_request/);
    assert.equal(f.sent.some(m=>m.method.includes("approval-decision")),false);f.client.stop();
  }
  const f=fixture(t);await until(()=>f.approval());const id=f.approval().id;
  await assert.rejects(f.client.respond("codex-observed:fake","accept"),/stale_request/);
  f.socket.emit("close");await assert.rejects(f.client.respond(id,"accept"),/stale_request/);
});
test("question responses validate complete answers then return them to the owning desktop",async t=>{
  const request={id:20,method:"item/tool/requestUserInput",params:{threadId:thread,turnId:turn,questions:[{id:"q",question:"Which?",options:[{label:"A"},{label:"B"}],isOther:false}]}};
  const f=fixture(t,state([request]));await until(()=>f.approval());const id=f.approval().id;
  await assert.rejects(f.client.respond(id,{answers:{}}),/invalid_question/);
  await assert.rejects(f.client.respond(id,{answers:{q:"C"}}),/invalid_question_option/);
  await f.client.respond(id,{answers:{q:"B"}});
  assert.deepEqual(f.sent.find(m=>m.method==="thread-follower-submit-user-input").params.response,{answers:{q:{answers:["B"]}}});
});
test("async question uses native follower steering and accepted reply settles only its question",async t=>{
  const s=state([]);s.turns[0].items=[{id:"question-item",type:"agentMessage",questions:[{title:"Continue?",options:["Yes","No"]}]}];
  const f=fixture(t,s);await until(()=>f.approval());const q=f.approval().questions[0];
  await f.client.respond(f.approval().id,{answers:{[q.id]:"Yes"}});
  const m=f.sent.find(m=>m.method==="thread-follower-steer-turn");
  assert.equal(m.targetClientId,"owner");assert.match(m.params.input[0].text,/<send_user_message_question_reply>/);
  assert.equal(m.params.restoreMessage.context.turnTrigger,"send_user_message_async_question");
  f.data.turns[0].items.push({type:"steeringUserMessage",status:"accepted",input:m.params.input});f.snapshot();assert.equal(f.approval(),null);
});
test("wrong peer and broken patch revisions invalidate response authority without replay",async t=>{
  const f=fixture(t);await until(()=>f.approval());const id=f.approval().id;
  f.deliver({type:"broadcast",method:"thread-stream-state-changed",version:11,sourceClientId:"stranger",params:{conversationId:thread,hostId:"local",change:{type:"snapshot",revision:999,conversationState:state([])}}});
  assert.equal(f.approval().id,id);
  f.onWrite(m=>m.method==="thread-stream-following-changed"?false:undefined);
  f.deliver({type:"broadcast",method:"thread-stream-state-changed",version:11,sourceClientId:"owner",params:{conversationId:thread,hostId:"local",change:{type:"patches",baseRevision:999,revision:1000,patches:[]}}});
  await assert.rejects(f.client.respond(id,"accept"),/stale_request/);
});
test("canonical current turn and patch application follow desktop ordering, fail closed on unsafe paths",()=>{
  const s=state();s.turns=[];s.turnHistory={kind:"canonical",history:{islands:[{newerBoundary:{status:"exhausted"},entries:[{value:"t"}]}],entitiesByKey:{t:{turnId:turn,status:"inProgress",items:[]}}}};
  assert.equal(P.project(s,thread).requests.length,1);
  P.applyPatches(s,[{op:"replace",path:["requests",0,"params","command"],value:"new"}]);assert.equal(s.requests[0].params.command,"new");
  assert.throws(()=>P.applyPatches(s,[{op:"add",path:["__proto__","polluted"],value:true}]));assert.equal({}.polluted,undefined);
  s.turnHistory.history.islands[0].entries.push({value:"missing"});assert.equal(P.project(s,thread).authoritative,false);
});
test("unacknowledged submission is not retried and permissions denial sends an empty grant",async t=>{
  const s=state([{id:30,method:"item/permissions/requestApproval",params:{threadId:thread,turnId:turn,permissions:{network:{enabled:true}}}}]);
  const f=fixture(t,s);await until(()=>f.approval());
  f.onWrite(m=>{if(m.method==="thread-follower-permissions-request-approval-response"){f.deliver({type:"response",requestId:m.requestId,method:m.method,resultType:"success",handledByClientId:"wrong",result:{ok:true}});return false;}});
  const id=f.approval().id;await assert.rejects(f.client.respond(id,"decline"),/outcome_unknown/);
  await assert.rejects(f.client.respond(id,"decline"),/already_submitted/);
  assert.deepEqual(f.sent.find(m=>m.method==="thread-follower-permissions-request-approval-response").params.response,{permissions:{},scope:"turn"});
});
