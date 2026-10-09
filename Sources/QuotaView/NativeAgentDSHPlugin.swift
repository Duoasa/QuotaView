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
const epoch = randomUUID();
export function apply(ctx, config = {}) {
  // The installer supplies the canonical home identity for custom DSH clients,
  // including those whose boot code overrides DSH_HOME internally.
  let home = process.env.DSH_HOME?.trim() || join(homedir(), '.dsh');
  if (home === '~' || home.startsWith('~/')) home = join(homedir(), home.slice(2));
  home = resolve(home);
  try { home = realpathSync(home); } catch { /* Existing sessions can outlive their data root. */ }
  const namespace = typeof config?.sourceNamespace === 'string' && /^[a-f0-9]{64}$/.test(config.sourceNamespace)
    ? config.sourceNamespace : createHash('sha256').update(home).digest('hex');
  let stopped = false, draining = false;
  const pending = [], models = new Map(), approvals = new Map(), titles = new Map();
  const text = value => typeof value === 'string' ? value.slice(0, 256) : undefined;
  async function send(payload) {
    if (stopped) return;
    try {
      const info = await stat(routePath);
      if (info.uid !== process.getuid() || (info.mode & 0o077) || info.size > 65536) return;
      const route = JSON.parse(await readFile(routePath, 'utf8'));
      const data = JSON.stringify({authenticationToken: route.authenticationToken, eventID: randomUUID(), kind: 'hook',
        awaitDecision: false, payload});
      if (Buffer.byteLength(data) > 16384) return;
      await new Promise(resolve => {
        const socket = connect({path: route.socketPath}, () => socket.end(data + '\n'));
        socket.on('error', () => socket.destroy());
        socket.on('close', resolve);
        socket.setTimeout(750, () => socket.destroy());
      });
    } catch { /* Observation must not affect the agent loop. */ }
  }
  async function drain() {
    if (draining) return;
    draining = true;
    try { while (!stopped && pending.length) await send(pending.shift()); }
    finally { draining = false; }
  }
  ctx.on('session/event', (session, event) => {
    if (stopped || !supported.has(event?.type)) return;
    const header = session.header ?? session.meta ?? {};
    const id = text(header.id ?? session.id);
    if (!id) return;
    const d = event.data ?? {};
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
      approvals.set(approvalKey, {call: text(d.callId) ?? 'approval:' + text(d.id), tool: text(d.toolName)});
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
    if (event.type === 'approval/decided') approvals.delete(approvalKey);
    if (event.type === 'turn/end') {
      const kind = typeof d.reason === 'string' ? d.reason : d.reason?.kind;
      payload.hook_event_name = kind === 'completed' ? 'Stop' : kind === 'error' || kind === 'max-tokens' ? 'StopFailure' : 'Interrupt';
    }
    if (event.type === 'assistant/message' && d.usage) {
      const u = d.usage;
      const count = n => Number.isSafeInteger(n) && n >= 0 ? n : 0;
      payload.tokens = Number.isSafeInteger(u.totalTokens) && u.totalTokens >= 0 ? u.totalTokens
        : count(u.inputTokens) + count(u.outputTokens) + count(u.cacheReadTokens) + count(u.cacheWriteTokens);
      payload.usage_id = String(event.seq);
    }
    // Only public session titles and coarse state; never forward prompts, assistant content, tool arguments/results, credentials or workspace paths.
    if (pending.length >= 256) pending.shift();
    pending.push(payload); void drain();
  });
  ctx.effect(() => () => { stopped = true; pending.length = 0; models.clear(); approvals.clear(); titles.clear(); });
}
"""#
}
