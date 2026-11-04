import Foundation

/// Original adapter against DSH's public session/event API. No VibeIsland code or assets are bundled.
enum NativeAgentDSHPlugin {
    static let source = #"""
import { connect } from 'node:net';
import { readFile, stat } from 'node:fs/promises';
import { randomUUID, createHash } from 'node:crypto';
import { realpathSync } from 'node:fs';
import { homedir } from 'node:os';
import { resolve, join } from 'node:path';
const routePath = __ROUTE_PATH__;
const supported = new Set(['turn/start', 'turn/end', 'tool/call', 'tool/result', 'request/header', 'assistant/message',
  'approval/asked', 'approval/decided', 'compaction/start', 'compaction/end', 'session/title']);
export function apply(ctx, config = {}) {
  const epoch = randomUUID();
  // The installer supplies the canonical home identity for custom DSH clients,
  // including those whose boot code overrides DSH_HOME internally.
  let home = process.env.DSH_HOME?.trim() || join(homedir(), '.dsh');
  if (home === '~' || home.startsWith('~/')) home = join(homedir(), home.slice(2));
  home = resolve(home);
  try { home = realpathSync(home); } catch { /* Existing sessions can outlive their data root. */ }
  const namespace = typeof config?.sourceNamespace === 'string' && /^[a-f0-9]{64}$/.test(config.sourceNamespace)
    ? config.sourceNamespace : createHash('sha256').update(home).digest('hex');
  let stopped = false, draining;
  const pending = [], models = new Map(), approvals = new Map(), titles = new Map(), turns = new Map();
  const decisions = new Map(), slots = new Set();
  const hydrated = new WeakSet();
  const text = value => typeof value === 'string' ? value.slice(0, 256) : undefined;
  function hydrateMetadata(session, id) {
    if (hydrated.has(session)) return;
    hydrated.add(session);
    // Restored sessions do not re-emit their existing title/header events.
    // Read only public metadata; never copy history into the observation queue.
    try {
      let model = text(session.requestHeader?.()?.config?.model), title;
      if (Number.isSafeInteger(session.seq) && typeof session.eventAt === 'function') {
        for (let i = session.seq - 1, floor = Math.max(0, session.seq - 8192); i >= floor; i--) {
          const event = session.eventAt(i);
          if (title === undefined && event?.type === 'session/title') title = text(event.data?.title);
          if (model === undefined && event?.type === 'request/header') model = text(event.data?.header?.config?.model);
          if (title !== undefined && model !== undefined) break;
        }
      }
      if (title !== undefined) titles.set(id, title);
      if (model !== undefined) models.set(id, model);
      if (titles.size > 512) titles.delete(titles.keys().next().value);
      if (models.size > 512) models.delete(models.keys().next().value);
    } catch { /* Missing metadata never changes execution or approvals. */ }
  }
  function finalResponse(session, turn) {
    if (!Number.isSafeInteger(turn) || !Number.isSafeInteger(session.seq) || typeof session.eventAt !== 'function') return;
    for (let i = session.seq - 1, floor = Math.max(0, session.seq - 8192); i >= floor; i--) {
      const event = session.eventAt(i), d = event?.data;
      if (event?.type === 'turn/start') break;
      if (event?.type !== 'assistant/message' || d?.turn !== turn) continue;
      // Only the last assistant message of a successfully completed turn is a
      // final answer. Never substitute earlier narration or reasoning.
      const parts = d.message?.content;
      if (d.interrupted || d.message?.role !== 'assistant' || !Array.isArray(parts)
          || parts.some(p => p.type === 'tool-call')) return;
      const blocks = parts.filter(p => p.type === 'text' && typeof p.text === 'string').map(p => p.text);
      let text = '', bytes = 0, truncated = false;
      outer: for (let n = 0; n < blocks.length; n++) {
        for (const char of (n ? '\n\n' : '') + blocks[n]) {
          const size = Buffer.byteLength(char);
          if (bytes + size > 65536) { truncated = true; break outer; }
          text += char; bytes += size;
        }
      }
      return text.trim() ? {id:String(event.seq), text, truncated} : undefined;
    }
  }
  async function route() {
    const info = await stat(routePath);
    if (info.uid !== process.getuid() || (info.mode & 0o077) || !info.isFile() || info.size > 65536) throw Error('Invalid route');
    return JSON.parse(await readFile(routePath, 'utf8'));
  }
  async function send(payload) {
    if (stopped) return;
    try {
      const target = await route();
      const data = JSON.stringify({authenticationToken: target.authenticationToken, eventID: randomUUID(), kind: 'hook',
        awaitDecision: false, payload});
      if (Buffer.byteLength(data) > (payload.final_response ? 524288 : 16384)) return;
      await new Promise(resolve => {
        const socket = connect({path: target.socketPath}, () => socket.end(data + '\n'));
        // Drain the observation acknowledgement so EOF closes the socket now,
        // rather than serializing every queued event behind the 750 ms timeout.
        socket.resume();
        socket.on('error', () => socket.destroy());
        socket.on('close', resolve);
        socket.setTimeout(750, () => socket.destroy());
      });
    } catch { /* Observation must not affect the agent loop. */ }
  }
  function drain() {
    if (!pending.length && !draining) return Promise.resolve();
    return draining ??= (async () => {
      try { while (!stopped && pending.length) await send(pending.shift()); }
      finally { draining = undefined; }
    })();
  }
  function enqueue(payload) {
    if (stopped) return;
    if (pending.length >= 256) pending.shift();
    pending.push(payload); void drain();
  }
  // Read only this open turn's correlated call. Never retain a general argument
  // cache, or silently approve a truncated/missing invocation.
  function inputFor(session, request, turn) {
    if (!['bash', 'str_replace_editor'].includes(request.toolName) || typeof request.callId !== 'string') return;
    if (!Number.isSafeInteger(session.seq) || typeof session.eventAt !== 'function') return;
    for (let i = session.seq - 1, floor = Math.max(0, session.seq - 2048); i >= floor; i--) {
      const event = session.eventAt(i);
      if (event?.type === 'turn/start' || event?.type === 'turn/end') break;
      const d = event?.data;
      if (event?.type !== 'tool/call' || d?.callId !== request.callId) continue;
      if (d.turn !== turn || d.name !== request.toolName || typeof d.arguments !== 'string'
          || Buffer.byteLength(d.arguments) > 65536) return;
      const input = JSON.parse(d.arguments);
      if (!input || Array.isArray(input) || typeof input !== 'object') return;
      return input;
    }
  }
  async function askIsland(payload, signal, eventID) {
    let target;
    try { target = await route(); } catch { return; }
    if (stopped || signal?.aborted || target.interactiveApprovals !== true) return;
    const body = JSON.stringify({authenticationToken: target.authenticationToken, eventID, kind:'hook', awaitDecision:true, payload});
    if (Buffer.byteLength(body) > 131072) return;
    return new Promise(resolve => {
      let done = false, buffer = '', admitted = false;
      const socket = connect({path:target.socketPath}, () => socket.write(body + '\n'));
      const finish = outcome => {
        if (done) return; done = true;
        clearTimeout(timer); signal?.removeEventListener('abort', abort);
        decisions.delete(eventID); socket.destroy(); resolve(outcome);
      };
      const abort = () => finish();
      let timer = setTimeout(abort, 1500);
      decisions.set(eventID, abort);
      socket.on('error', abort); socket.on('close', abort);
      signal?.addEventListener('abort', abort, {once:true});
      if (stopped || signal?.aborted) { abort(); return; }
      socket.on('data', chunk => {
        buffer += chunk.toString('utf8');
        if (buffer.length > 8192) { abort(); return; }
        while (buffer.includes('\n')) {
          const end = buffer.indexOf('\n'), line = buffer.slice(0,end); buffer = buffer.slice(end+1);
          try {
            const reply = JSON.parse(line);
            if (reply.eventID !== eventID) { abort(); return; }
            if (reply.admitted === true) {
              admitted = true; clearTimeout(timer); timer = setTimeout(abort, 600000);
            } else if (reply.decision) {
              const outcome = reply.decision.outcome;
              finish(admitted && ['allowed-once','rejected'].includes(outcome) ? outcome : undefined);
            } else if (reply.pending !== true) { abort(); return; }
          } catch { abort(); return; }
        }
      });
    });
  }
  // Normal waterfall order preserves existing answerers. Never prepend ahead
  // of another policy or race next() against a still-answerable local request.
  ctx.on('approval/request', async (request, next) => {
    if (stopped || config.interactiveProfile !== true || slots.size >= 32) return next();
    const session = request?.agent?.session, header = session?.header ?? session?.meta ?? {};
    const id = text(header.id ?? session?.id), turn = turns.get(id);
    if (!id || header.origin === 'subagent' || turn == null || request.signal?.aborted) return next();
    let input;
    try { input = inputFor(session, request, turn); } catch { return next(); }
    if (!input || (request.reason != null && (typeof request.reason !== 'string' || Buffer.byteLength(request.reason) > 4096))) return next();
    const matches = [...approvals.values()].filter(a => a.session === session && a.turn === turn && a.call === request.callId);
    if (matches.length !== 1 || matches[0].eventID) return next();
    const approval = matches[0], eventID = randomUUID();
    approval.eventID = eventID;
    const identity = {session_id:id, turn_id:String(turn), source_namespace:namespace, source_epoch:epoch,
      request_id:eventID, approval_id:approval.id, tool_use_id:request.callId};
    slots.add(eventID);
    let outcome, syncTimer;
    try {
      // A backed-up observation queue cannot indefinitely hold native approval.
      const synced = await Promise.race([drain().then(() => true),
        new Promise(resolve => { syncTimer = setTimeout(() => resolve(false), 1500); })]);
      if (synced && turns.get(id) === turn && !stopped) outcome = await askIsland({...identity, hook_event_name:'DSHApprovalRequest',
        tool_name:request.toolName, tool_input:input, reason:request.reason, cwd:header.cwd}, request.signal, eventID);
    } catch { /* Delegate on transport or serialization failure. */ }
    finally { clearTimeout(syncTimer); slots.delete(eventID); }
    if (request.signal?.aborted || (!stopped && turns.get(id) !== turn)) return 'cancelled';
    if (outcome) return outcome;
    enqueue({...identity, hook_event_name:'DSHApprovalReleased'});
    return next();
  });
  ctx.on('session/event', (session, event) => {
    if (stopped || !supported.has(event?.type)) return;
    const header = session.header ?? session.meta ?? {};
    const id = text(header.id ?? session.id);
    if (!id) return;
    hydrateMetadata(session, id);
    const d = event.data ?? {};
    if (event.type === 'turn/start' && Number.isSafeInteger(d.turn)) {
      turns.set(id, d.turn);
      if (turns.size > 512) turns.delete(turns.keys().next().value);
    }
    if (event.type === 'request/header') {
      models.set(id, text(d.header?.config?.model));
      if (models.size > 512) models.delete(models.keys().next().value);
    }
    if (event.type === 'session/title') {
      titles.set(id, text(d.title));
      if (titles.size > 512) titles.delete(titles.keys().next().value);
    }
    const approvalKey = id + ':' + d.id;
    if (event.type === 'approval/asked') {
      approvals.set(approvalKey, {id:d.id, session, turn:turns.get(id), call: text(d.callId) ?? 'approval:' + text(d.id), tool: text(d.toolName)});
      if (approvals.size > 512) approvals.delete(approvals.keys().next().value);
    }
    const approval = approvals.get(approvalKey);
    const map = {'turn/start':'TurnStarted', 'turn/end':'Stop', 'tool/call':'PreToolUse', 'tool/result':'PostToolUse',
      'approval/asked':'PermissionRequest', 'approval/decided':'PermissionResult', 'compaction/start':'PreCompact',
      'compaction/end':'PostCompact', 'assistant/message':'Usage', 'request/header':'Metadata', 'session/title':'Metadata'};
    const payload = {hook_event_name:map[event.type], session_id:id, turn_id:d.turn == null ? undefined : String(d.turn),
      source_namespace:namespace, source_epoch:epoch, source_sequence:event.seq, model:models.get(id), session_title:titles.get(id),
      tool_name:approval?.tool ?? text(d.name), tool_use_id:approval?.call ?? text(d.callId ?? d.message?.toolCallId),
      parent_session_id:header.origin === 'subagent' ? text(header.parentSession) : undefined};
    if (event.type === 'approval/decided') {
      if (approval?.eventID) enqueue({hook_event_name:'DSHApprovalSettled', session_id:id, turn_id:String(approval.turn),
        source_namespace:namespace, source_epoch:epoch, request_id:approval.eventID, approval_id:approval.id, outcome:d.outcome});
      decisions.get(approval?.eventID)?.();
      approvals.delete(approvalKey);
    }
    if (event.type === 'turn/end') {
      turns.delete(id);
      for (const [key, approval] of approvals) if (approval.session === session) {
        decisions.get(approval.eventID)?.(); approvals.delete(key);
      }
      const kind = typeof d.reason === 'string' ? d.reason : d.reason?.kind;
      payload.hook_event_name = kind === 'completed' ? 'Stop' : kind === 'error' || kind === 'max-tokens' ? 'StopFailure' : 'Interrupt';
      if (kind === 'completed' && header.origin !== 'subagent') {
        try { payload.final_response = finalResponse(session, d.turn); } catch { /* Keep completion even when answer data is unavailable. */ }
      }
    }
    if (event.type === 'assistant/message' && d.usage) {
      const u = d.usage;
      const count = n => Number.isSafeInteger(n) && n >= 0 ? n : 0;
      payload.tokens = Number.isSafeInteger(u.totalTokens) && u.totalTokens >= 0 ? u.totalTokens
        : count(u.inputTokens) + count(u.outputTokens) + count(u.cacheReadTokens) + count(u.cacheWriteTokens);
      payload.usage_id = String(event.seq);
    }
    // Only public metadata/state and the explicitly supported final answer;
    // never forward prompts, reasoning, tool outputs or account credentials.
    enqueue(payload);
  });
  ctx.effect(() => () => {
    stopped = true; for (const abort of [...decisions.values()]) abort();
    pending.length = 0; models.clear(); approvals.clear(); titles.clear(); turns.clear(); slots.clear();
  });
}
"""#
}
