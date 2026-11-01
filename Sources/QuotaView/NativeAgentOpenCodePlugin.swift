import Foundation

/// Adapter for the official OpenCode 1.x plugin/event API. No SDK dependency,
/// transcript reads, shell execution or permission decisions.
enum NativeAgentOpenCodePlugin {
    static let source = #"""
import { connect } from 'node:net';
import { readFile, lstat } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { dirname, join } from 'node:path';
const routePath = __ROUTE_PATH__;
export const QuotaView = async () => {
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
  async function send(payload) {
    try {
      const info = await lstat(routePath);
      if (!info.isFile() || info.uid !== process.getuid() || (info.mode & 0o077) || info.size > 65536) return;
      const route = JSON.parse(await readFile(routePath,'utf8'));
      if (route.version !== 1 || route.agentProvider !== 'openCode') return;
      const line = JSON.stringify({authenticationToken:route.authenticationToken,eventID:randomUUID(),kind:'hook',awaitDecision:false,payload})+'\n';
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
    const batch = [...(inFlight ? [inFlight] : []), ...pending];
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
    if (!s.active) return;
    emit(id,s,name); s.active = false; flushTerminal();
  }
  return {
    event: async ({event}) => {
      if (stopped || !event) return;
      if (event.type === 'server.instance.disposed') { flushTerminal(); stopped=true; pending.length=0; sessions.clear(); return; }
      const p = event.properties ?? {}, info = p.info ?? {};
      const id = text(p.sessionID ?? info.sessionID ?? info.id);
      if (!id) return;
      const s = state(id); if (!s) return;
      switch (event.type) {
        case 'session.created': case 'session.updated':
          s.title=text(info.title); s.parent=text(info.parentID); emit(id,s,'Metadata'); break;
        case 'message.updated':
          if (info.role === 'assistant') { s.model=text(info.modelID); emit(id,s,'Metadata'); } break;
        case 'session.status':
          if (p.status?.type === 'busy' || p.status?.type === 'retry') start(id,s);
          else if (p.status?.type === 'idle') finish(id,s,'Stop'); break;
        case 'session.idle': finish(id,s,'Stop'); break;
        case 'session.error': finish(id,s,p.error?.name === 'MessageAbortedError' ? 'Interrupt' : 'StopFailure'); break;
        case 'session.deleted': emit(id,s,'SessionEnd'); sessions.delete(id); break;
        case 'session.compacted': emit(id,s,'PostCompact'); break;
        case 'permission.asked': case 'permission.v2.asked':
          start(id,s); emit(id,s,'PermissionRequest',{tool_name:text(p.permission ?? p.action),tool_use_id:text(p.id)}); break;
        case 'permission.replied': case 'permission.v2.replied':
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
