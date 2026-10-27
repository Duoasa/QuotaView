'use strict';

// Codex invokes this helper with JSON on stdin. It emits no blocking decision,
// command output, user content or credentials and always fails open.
const fs = require('node:fs/promises');
const net = require('node:net');
const crypto = require('node:crypto');
const EVENTS = new Set(['SessionStart', 'SessionEnd', 'UserPromptSubmit', 'PreToolUse', 'PermissionRequest', 'PostToolUse', 'PreCompact', 'PostCompact', 'SubagentStart', 'SubagentStop', 'Interrupt', 'Stop']);
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const id = value => typeof value === 'string' && value.length > 0 && Buffer.byteLength(value) <= 1024 && !/[\x00-\x1f\x7f]/.test(value) ? value : null;

function selectPayload(input) {
  if (!object(input) || !EVENTS.has(input.hook_event_name) || !id(input.session_id)) return null;
  const output = { event: input.hook_event_name, sessionId: input.session_id };
  if (input.turn_id != null) { if (!id(input.turn_id)) return null; output.turnId = input.turn_id; }
  for (const [inputKey, outputKey] of [["tool_use_id", "toolUseId"], ["tool_name", "toolName"]]) {
    if (input[inputKey] != null) { if (!id(input[inputKey])) return null; output[outputKey] = input[inputKey]; }
  }
  // Only tool identity is included; no cwd, prompt, arguments, output or answers.
  return output;
}
async function readRoute(file) {
  const stat = await fs.lstat(file);
  if (!stat.isFile() || stat.isSymbolicLink() || stat.size < 1 || stat.size > 16384) throw new Error('invalid_hook_route');
  if (process.platform !== 'win32' && ((stat.mode & 0o077) !== 0 || stat.uid !== process.getuid())) throw new Error('nonprivate_hook_route');
  const route = JSON.parse(await fs.readFile(file, 'utf8'));
  if (!object(route) || route.version !== 1 || route.provider !== 'codex' || route.host !== '127.0.0.1' || !Number.isInteger(route.port) || route.port < 1 || route.port > 65535 || !/^[a-f0-9]{64}$/.test(route.authenticationToken) || typeof route.installationId !== 'string') throw new Error('invalid_hook_route');
  return route;
}
function readInput(stream = process.stdin, limit = 1024 * 1024) {
  return new Promise((resolve, reject) => {
    const chunks = []; let length = 0;
    const cleanup = () => { clearTimeout(timer); stream.removeListener('data', data); stream.removeListener('end', end); stream.removeListener('error', fail); };
    const fail = error => { cleanup(); reject(error); };
    const end = () => { cleanup(); resolve(Buffer.concat(chunks)); };
    const data = chunk => { length += chunk.length; if (length > limit) { stream.pause(); fail(new Error('hook_input_too_large')); } else chunks.push(chunk); };
    const timer = setTimeout(() => fail(new Error('hook_input_timed_out')), 800);
    stream.on('data', data); stream.once('end', end); stream.once('error', fail); stream.resume();
  });
}
function send(route, payload, { timeout = 700, eventId = crypto.randomUUID() } = {}) {
  if (route.enabled !== true) return Promise.resolve(false);
  return new Promise(resolve => {
    let settled = false, buffer = Buffer.alloc(0);
    const socket = net.createConnection({ host: '127.0.0.1', port: route.port });
    const finish = value => { if (settled) return; settled = true; clearTimeout(timer); socket.destroy(); resolve(value); };
    const timer = setTimeout(() => finish(false), timeout);
    socket.on('error', () => finish(false)); socket.on('end', () => finish(false)); socket.on('close', () => finish(false));
    socket.on('connect', () => socket.write(JSON.stringify({ authenticationToken: route.authenticationToken, installationId: route.installationId, eventId, payload }) + '\n'));
    socket.on('data', chunk => {
      if (buffer.length + chunk.length > 4096) return finish(false);
      buffer = Buffer.concat([buffer, chunk]); const index = buffer.indexOf(10); if (index < 0) return;
      try { const ack = JSON.parse(buffer.subarray(0, index)); finish(ack.eventId === eventId && ack.accepted === true); } catch { finish(false); }
    });
  });
}
async function main(args = process.argv.slice(2), { input = process.stdin } = {}) {
  try {
    const index = args.indexOf('--configuration'); if (index < 0 || typeof args[index + 1] !== 'string') return;
    const route = await readRoute(args[index + 1]); if (!route.enabled) return;
    const data = await readInput(input); const payload = selectPayload(JSON.parse(data.toString('utf8')));
    if (payload) await send(route, payload);
  } catch { /* Hook observation never overrides Codex behavior or approval flow. */ }
}
if (require.main === module) main().then(() => { process.exitCode = 0; });
module.exports = { EVENTS, selectPayload, readRoute, readInput, send, main };
