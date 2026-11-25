import Foundation

/// Adapter for the official OpenCode 1.x plugin/event API. No SDK dependency,
/// transcript reads or shell commands for approvals. Replies use the originating client.
enum NativeAgentOpenCodePlugin {
    static let source = #"""
import { connect } from 'node:net';
import { readFile, lstat } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { dirname, join } from 'node:path';
const routePath = __ROUTE_PATH__;
export const QuotaView = async ({client} = {}) => {
  const epoch = randomUUID(), sessions = new Map(), pending = [];
  let sequence = 0, draining = false, stopped = false, inFlight;
  const text = v => typeof v === 'string' && v.length ? v.slice(0,256) : undefined;
  function state(id) {
    if (!sessions.has(id)) {
      if (sessions.size >= 512) {
        const idle = [...sessions].find(([,s]) => !s.active);
        if (!idle) return;
        sessions.delete(idle[0]);
      }
      sessions.set(id, {active:false});
    }
    return sessions.get(id);
  }
  const interactions = new Map();
  const validID = v => typeof v === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(v);
  function forget(item) {
    if (interactions.get(item.key) !== item) return;
    clearTimeout(item.timeout);
    interactions.delete(item.key);
    item.socket?.destroy();
  }
  async function report(item,event) {
    await send({session_id:item.sessionID,source_epoch:epoch,turn_id:item.turn,
      hook_event_name:event,interaction_id:item.eventID});
  }
  function withdraw(sessionID, requestID) {
    for (const item of interactions.values()) {
      if (item.sessionID === sessionID && (!requestID || item.id === requestID)) {
        void report(item,'OpenCodeReleased');
        forget(item);
      }
    }
  }
  function present(sessionID, s, type, props) {
    if (!validID(props.id) || interactions.size >= 32) return false;
    // Bind one transport on the originating plugin client before presenting.
    // A failed or ambiguous delivery must never be replayed through another API.
    const raw = client?._client;
    const api = client?.[type];
    let reply;
    if (typeof raw?.post === 'function') {
      reply = (body, options) => raw.post({url:'/'+type+'/'+props.id+'/reply', body,
        headers:{'Content-Type':'application/json'}, ...options});
    } else if (typeof api?.reply === 'function') {
      reply = (body, options) => api.reply({requestID:props.id, ...body}, options);
    } else { return false; }
    const key = JSON.stringify([sessionID,type,props.id]);
    if (interactions.has(key)) return true;
    const fields = {interaction_type:type, native_id:props.id};
    if (type === 'question') {
      const questions = props.questions;
      if (!Array.isArray(questions) || !questions.length || questions.length > 32 ||
          questions.some(q => !q?.question || q.multiple || !Array.isArray(q.options) ||
            q.options.some(o => typeof o?.label !== 'string' || !o.label))) return false;
      fields.questions = questions.map((q,i) => ({id:String(i),question:q.question,header:q.header,
        options:q.options.map(o => ({label:o.label,description:o.description})),isOther:q.custom !== false}));
    } else {
      if (typeof props.permission !== 'string' || !Array.isArray(props.patterns) ||
          !props.patterns.length || props.patterns.some(p => typeof p !== 'string' || !p)) return false;
      fields.command = [props.permission,...props.patterns].join('\n');
    }
    if (Buffer.byteLength(JSON.stringify(fields)) > 48000) return false;
    const item = {id:props.id, sessionID, type, key, reply, eventID:randomUUID(), turn:s.turn};
    item.timeout = setTimeout(() => forget(item), 300000);
    item.timeout.unref?.();
    interactions.set(key,item);
    emit(sessionID,s,'OpenCodeInteraction',{...fields,interaction_key:key,interaction_id:item.eventID});
    return true;
  }
  // Return control to the event queue after admission. Only this pending
  // socket can answer this request, and native settlement invalidates it.
  function waitForChoice(route, line, item, payload) {
    return new Promise(ready => {
      const socket = connect({path:route.socketPath}, () => socket.write(line));
      item.socket = socket;
      let buffer = '', submitted = false;
      socket.setEncoding('utf8');
      socket.setTimeout(1500, () => socket.destroy());
      socket.on('error', () => socket.destroy());
      socket.on('close', () => { ready(); if (!submitted) forget(item); });
      socket.on('data', chunk => {
        buffer += chunk;
        if (Buffer.byteLength(buffer) > 65536) return socket.destroy();
        let newline;
        while ((newline = buffer.indexOf('\n')) !== -1) {
          const packet = buffer.slice(0,newline); buffer = buffer.slice(newline+1);
          let message;
          try { message = JSON.parse(packet); } catch { return socket.destroy(); }
          if (message.eventID !== item.eventID || interactions.get(item.key) !== item) return socket.destroy();
          if (message.admitted) { socket.setTimeout(300000); ready(); continue; }
          if (!message.decision || submitted) continue;
          let body;
          if (item.type === 'permission' && ['once','reject'].includes(message.decision.reply)) {
            body = {reply:message.decision.reply};
          } else if (item.type === 'question' && Array.isArray(message.decision.answers)
              && message.decision.answers.length === payload.questions.length
              && message.decision.answers.every((a,i) => Array.isArray(a) && a.length === 1
                && typeof a[0] === 'string' && a[0].trim()
                && (payload.questions[i].isOther || payload.questions[i].options.some(o => o.label === a[0])))) {
            body = {answers:message.decision.answers};
          } else { return socket.destroy(); }
          submitted = true;
          // The plugin SDK retains the owning instance and its directory/auth headers.
          void (async () => {
            try {
              const result = await item.reply(body, {throwOnError:true, signal:AbortSignal.timeout(5000)});
              if (!result?.response?.ok || result.error) throw Error('Reply not acknowledged');
              await report(item,'OpenCodeReleased');
              forget(item);
            } catch {
              await report(item,'OpenCodeDeliveryFailed');
              // Keep the native request identity until it is answered there or expires.
            }
          })();
        }
      });
    });
  }
  async function send(payload) {
    try {
      const info = await lstat(routePath);
      if (!info.isFile() || info.uid !== process.getuid() || (info.mode & 0o077) || info.size > 65536) return;
      const route = JSON.parse(await readFile(routePath,'utf8'));
      if (route.version !== 1 || route.agentProvider !== 'openCode') return;
      const interactive = payload.hook_event_name === 'OpenCodeInteraction';
      const item = interactive ? interactions.get(payload.interaction_key) : undefined;
      if (interactive && !route.interactiveApprovals) {
        if (item) forget(item);
        if (payload.interaction_type === 'permission') await send({...payload,hook_event_name:'PermissionRequest',
          command:undefined,questions:undefined,tool_use_id:payload.native_id});
        return;
      }
      if (interactive && (!item || item.eventID !== payload.interaction_id)) return;
      const line = JSON.stringify({authenticationToken:route.authenticationToken,eventID:item?.eventID ?? randomUUID(),kind:'hook',awaitDecision:interactive,payload})+'\n';
      if (item) { await waitForChoice(route,line,item,payload); return; }
      await new Promise(resolve => {
        const socket = connect({path:route.socketPath}, () => socket.end(line));
        socket.resume(); socket.on('error',() => socket.destroy()); socket.on('close',resolve);
        socket.setTimeout(750,() => socket.destroy());
      });
    } catch { /* Fail open; the agent owns all decisions. */ }
  }
  async function drain() {
    if (draining) return;
    draining = true;
    try {
      while (!stopped && pending.length) {
        inFlight = pending.shift(); await send(inFlight); inFlight = undefined;
      }
    } finally { draining = false; inFlight = undefined; }
  }
  function flushTerminal() {
    // OpenCode's event dispatcher does not await plugins before process.exit.
    // Re-send the in-flight event too; epoch/sequence dedup keeps order intact.
    const batch = [...(inFlight ? [inFlight] : []), ...pending].filter(p => p.hook_event_name !== 'OpenCodeInteraction');
    if (!batch.length) return;
    try {
      const result = spawnSync(join(dirname(routePath),'QuotaViewActivityHook'),
        ['--agent-hook','--configuration',routePath,'--event','Flush'],
        {input:JSON.stringify(batch),encoding:'utf8',timeout:1500,maxBuffer:65536,stdio:['pipe','pipe','ignore']});
      if (result.status === 0 && JSON.parse(result.stdout).forwarded === batch.length) pending.length = 0;
    } catch { /* An unavailable observer must not hold up client shutdown. */ }
  }
  function emit(id, s, name, fields={}) {
    if (stopped) return;
    const payload = {session_id:id,hook_event_name:name,turn_id:s.turn,source_epoch:epoch,source_sequence:sequence++,
      session_title:s.title,model:s.model,parent_session_id:s.parent,...fields};
    if (pending.length >= 256) pending.shift();
    pending.push(payload); void drain();
  }
  function start(id,s) {
    if (s.active) return;
    s.active = true; s.turn = randomUUID(); emit(id,s,'TurnStarted');
  }
  function finish(id,s,name) {
    withdraw(id);
    if (!s.active) return;
    emit(id,s,name); s.active = false; flushTerminal();
  }
  return {
    event: async ({event}) => {
      if (stopped || !event) return;
      if (event.type === 'server.instance.disposed') { for (const item of interactions.values()) forget(item); flushTerminal(); stopped=true; pending.length=0; sessions.clear(); return; }
      const p = event.properties ?? {}, info = p.info ?? {};
      const id = text(p.sessionID ?? info.sessionID ?? info.id);
      if (!id) return;
      const s = state(id); if (!s) return;
      switch (event.type) {
        case 'session.created': case 'session.updated':
          s.title=text(info.title); s.parent=text(info.parentID); emit(id,s,'Metadata'); break;
        case 'message.updated':
          if (info.role === 'assistant') {
            s.model=text(info.modelID); emit(id,s,'Metadata');
            if (s.turn && Number.isSafeInteger(info.tokens?.output) && info.time?.completed > info.time?.created)
              emit(id,s,'Usage',{usage_id:text(info.id), output_tokens:info.tokens.output,
                rate_start_ms:info.time.created, rate_end_ms:info.time.completed});
          } break;
        case 'session.status':
          if (p.status?.type === 'busy' || p.status?.type === 'retry') start(id,s);
          else if (p.status?.type === 'idle') finish(id,s,'Stop'); break;
        case 'session.idle': finish(id,s,'Stop'); break;
        case 'session.error': finish(id,s,p.error?.name === 'MessageAbortedError' ? 'Interrupt' : 'StopFailure'); break;
        case 'session.deleted': withdraw(id); emit(id,s,'SessionEnd'); sessions.delete(id); break;
        case 'session.compacted': emit(id,s,'PostCompact'); break;
        case 'question.asked':
          start(id,s); present(id,s,'question',p); break;
        case 'question.replied': case 'question.rejected':
          if (validID(p.requestID)) withdraw(id,p.requestID); break;
        case 'permission.asked': case 'permission.v2.asked':
          start(id,s);
          if (present(id,s,'permission',p)) break;
          start(id,s); emit(id,s,'PermissionRequest',{tool_name:text(p.permission ?? p.action),tool_use_id:text(p.id)}); break;
        case 'permission.replied': case 'permission.v2.replied':
          if (validID(p.requestID)) withdraw(id,p.requestID);
          emit(id,s,'PermissionResult',{tool_use_id:text(p.requestID)}); break;
      }
    },
    'tool.execute.before': async input => {
      const id=text(input.sessionID); if (!id || stopped) return;
      const s=state(id); if (!s) return; start(id,s);
      emit(id,s,'PreToolUse',{tool_name:text(input.tool),tool_use_id:text(input.callID)});
    },
    'tool.execute.after': async input => {
      const id=text(input.sessionID), s=sessions.get(id); if (!s || !s.active || stopped) return;
      emit(id,s,'PostToolUse',{tool_name:text(input.tool),tool_use_id:text(input.callID)});
    }
  };
};
"""#
}
