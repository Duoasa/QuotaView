// Original DSH public session/event adapter. Observation only; no prompts or tool content.
import { connect } from 'node:net';
import { readFile, lstat } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
const supported = new Set(['turn/start', 'turn/end', 'tool/call', 'tool/result', 'request/header', 'assistant/message', 'approval/asked', 'approval/decided', 'compaction/start', 'compaction/end', 'session/title']);
export function apply(ctx, config = {}) {
  if (typeof config.routePath !== 'string' || !/^[a-f0-9]{64}$/.test(config.sourceNamespace)) return;
  const epoch = randomUUID(), namespace = config.sourceNamespace;
  let stopped = false, draining = false;
  const pending = [], models = new Map(), approvals = new Map(), titles = new Map();
  const text = value => typeof value === 'string' ? value.slice(0, 256) : undefined;
  const remember = (map, key, value) => { map.set(key, value); if (map.size > 512) map.delete(map.keys().next().value); };
  async function send(payload) {
    if (stopped) return;
    try {
      const stat = await lstat(config.routePath);
      if (!stat.isFile() || stat.isSymbolicLink() || stat.size > 65536) return;
      if (process.platform !== 'win32' && (stat.uid !== process.getuid() || (stat.mode & 0o077))) return;
      const route = JSON.parse(await readFile(config.routePath, 'utf8'));
      if (route.version !== 1 || route.provider !== 'dsh' || route.enabled === false || route.host !== '127.0.0.1' || !Number.isInteger(route.port) || route.port < 1 || route.port > 65535 || !/^[a-f0-9]{64}$/.test(route.authenticationToken)) return;
      const message = JSON.stringify({ authenticationToken: route.authenticationToken, eventID: randomUUID(), kind: 'hook', awaitDecision: false, payload });
      if (Buffer.byteLength(message) > 16384 || stopped) return;
      await new Promise(resolve => {
        const socket = connect({ host: '127.0.0.1', port: route.port }, () => socket.end(message + '\n'));
        socket.resume(); socket.on('error', () => socket.destroy()); socket.once('close', resolve); socket.setTimeout(750, () => socket.destroy());
      });
    } catch { /* Never interrupt an agent turn for observation. */ }
  }
  async function drain() {
    if (draining || stopped) return;
    draining = true;
    try { while (!stopped && pending.length) await send(pending.shift()); } finally { draining = false; }
  }
  ctx.on('session/event', (session, event) => {
    if (stopped || !supported.has(event?.type)) return;
    const header = session.header ?? session.meta ?? {}, id = text(header.id ?? session.id), d = event.data ?? {};
    if (!id || !Number.isSafeInteger(event.seq) || event.seq < 0) return;
    if (event.type === 'request/header') remember(models, id, text(d.header?.config?.model));
    if (event.type === 'session/title') remember(titles, id, text(d.title));
    const approvalKey = id + ':' + d.id;
    if (event.type === 'approval/asked') remember(approvals, approvalKey, { call: text(d.callId) ?? 'approval:' + text(d.id), tool: text(d.toolName) });
    const approval = approvals.get(approvalKey);
    const map = { 'turn/start': 'TurnStarted', 'turn/end': 'Stop', 'tool/call': 'PreToolUse', 'tool/result': 'PostToolUse', 'approval/asked': 'PermissionRequest', 'approval/decided': 'PermissionResult', 'compaction/start': 'PreCompact', 'compaction/end': 'PostCompact', 'assistant/message': 'Usage', 'request/header': 'Metadata', 'session/title': 'Metadata' };
    const payload = { hook_event_name: map[event.type], session_id: id, turn_id: d.turn == null ? undefined : String(d.turn).slice(0, 256), source_namespace: namespace, source_epoch: epoch, source_sequence: event.seq, model: models.get(id), session_title: titles.get(id), tool_name: approval?.tool ?? text(d.name), tool_use_id: approval?.call ?? text(d.callId ?? d.message?.toolCallId), parent_session_id: header.origin === 'subagent' ? text(header.parentSession) : undefined };
    if (event.type === 'approval/decided') approvals.delete(approvalKey);
    if (event.type === 'turn/end') { const reason = typeof d.reason === 'string' ? d.reason : d.reason?.kind; payload.hook_event_name = reason === 'completed' ? 'Stop' : ['error', 'max-tokens'].includes(reason) ? 'StopFailure' : 'Interrupt'; }
    if (event.type === 'assistant/message' && d.usage) {
      const usage = d.usage, count = n => Number.isSafeInteger(n) && n >= 0 && n <= 1e9 ? n : 0;
      const supplied = ['totalTokens', 'inputTokens', 'outputTokens', 'cacheReadTokens', 'cacheWriteTokens'].some(key => Number.isSafeInteger(usage[key]) && usage[key] >= 0);
      if (supplied) payload.tokens = Number.isSafeInteger(usage.totalTokens) && usage.totalTokens >= 0 ? Math.min(usage.totalTokens, 1e9) : count(usage.inputTokens) + count(usage.outputTokens) + count(usage.cacheReadTokens) + count(usage.cacheWriteTokens);
    }
    if (pending.length >= 256) pending.shift(); pending.push(payload); void drain();
  });
  ctx.effect(() => () => { stopped = true; pending.length = 0; models.clear(); approvals.clear(); titles.clear(); });
}
