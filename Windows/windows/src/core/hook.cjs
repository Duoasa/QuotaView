'use strict';
// Fail-open, bounded hook transport. Also runs under ELECTRON_RUN_AS_NODE=1.
const fs = require('node:fs/promises');
const net = require('node:net');
const crypto = require('node:crypto');
const { spawn } = require('node:child_process');
const MAX_INPUT = 8 * 1024 * 1024, MAX_WIRE = 1024 * 1024;
const isObject = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const bounded = (value, limit = 4096) => typeof value === 'string' ? Buffer.from(value).subarray(0, limit).toString('utf8').replace(/\ufffd$/, '') : undefined;
async function readRoute(file) {
  const stat = await fs.lstat(file);
  if (!stat.isFile() || stat.isSymbolicLink() || stat.size > 65536 || stat.size < 1) throw new Error('Invalid route');
  if (process.platform !== 'win32' && ((stat.mode & 0o077) || stat.uid !== process.getuid())) throw new Error('Non-private route');
  const route = JSON.parse((await require('./integration-files.cjs').read(file,65536)).toString('utf8'));
  if (route.version !== 1 || route.host !== '127.0.0.1' || !Number.isInteger(route.port) || route.port < 1 || route.port > 65535 || !/^[a-f0-9]{64}$/.test(route.authenticationToken) || !['claude', 'dsh', 'kimi'].includes(route.provider)) throw new Error('Invalid route');
  return route;
}
function readInput(stream = process.stdin, max = MAX_INPUT) {
  return new Promise((resolve, reject) => {
    let length = 0; const chunks = [];
    const finish = value => { cleanup(); resolve(value); };
    const fail = error => { cleanup(); reject(error); };
    const cleanup = () => { clearTimeout(timer); stream.removeListener('data', data); stream.removeListener('end', end); stream.removeListener('error', fail); };
    const data = chunk => { length += chunk.length; if (length > max) { stream.pause(); fail(new Error('Input too large')); } else chunks.push(chunk); };
    const end = () => finish(Buffer.concat(chunks));
    const timer = setTimeout(() => fail(new Error('Input timed out')), 5000);
    stream.on('data', data); stream.once('end', end); stream.once('error', fail); stream.resume();
  });
}
function selectPayload(input, provider) {
  if (!isObject(input) || typeof input.hook_event_name !== 'string' || typeof input.session_id !== 'string' || !input.session_id || input.session_id.length > 256) return null;
  const keys = ['hook_event_name', 'session_id', 'turn_id', 'prompt_id', 'tool_name', 'tool_use_id', 'tool_call_id', 'model', 'session_title', 'agent_id', 'agent_type', 'source', 'reason', 'stop_reason'];
  const result = {};
  for (const key of keys) if (typeof input[key] === 'string') result[key] = bounded(input[key], 256);
  if (provider === 'claude') {
    for (const key of ['transcript_path', 'agent_transcript_path', 'cwd', 'notification_type', 'title', 'message', 'last_assistant_message', 'error']) if (typeof input[key] === 'string') result[key] = bounded(input[key], key === 'last_assistant_message' ? 65536 : 4096);
    for (const key of ['stop_hook_active', 'is_interrupt']) if (typeof input[key] === 'boolean') result[key] = input[key];
    for (const [key, limit] of [['tool_input', 262144], ['permission_suggestions', 65536]]) {
      if (input[key] !== undefined) {
        const serialized = JSON.stringify(input[key]);
        result[key] = Buffer.byteLength(serialized) <= limit ? input[key] : { _quotaViewTruncated: true };
      }
    }
    if (typeof input.effort === 'string') result.effort = bounded(input.effort, 64);
    else if (isObject(input.effort)) result.effort = bounded(input.effort.level, 64);
  }
  return result;
}
function send(route, payload, { kind = 'hook', awaitDecision = false, eventID = crypto.randomUUID() } = {}) {
  if (route.enabled === false) return Promise.resolve(null);
  return new Promise(resolve => {
    let finished = false, buffer = '', pending = false; const decoder=new (require('node:string_decoder').StringDecoder)('utf8');
    const socket = net.createConnection({ host: '127.0.0.1', port: route.port });
    const finish = value => { if (finished) return; finished = true; clearTimeout(timer); socket.destroy(); resolve(value); };
    let timer = setTimeout(() => finish(null), route.provider === 'kimi' ? 750 : 1500);
    const envelope = JSON.stringify({ authenticationToken: route.authenticationToken, eventID, kind, awaitDecision, payload });
    if (Buffer.byteLength(envelope) > MAX_WIRE) { finish(null); return; }
    socket.on('connect', () => socket.write(envelope + '\n'));
    socket.on('error', () => finish(null)); socket.on('end', () => finish(null)); socket.on('close', () => finish(null));
    socket.on('data', data => {
      buffer += decoder.write(data); if (Buffer.byteLength(buffer) > MAX_WIRE) { finish(null); return; }
      let index;
      while ((index = buffer.indexOf('\n')) >= 0) {
        const line = buffer.slice(0, index); buffer = buffer.slice(index + 1);
        let reply; try { reply = JSON.parse(line); } catch { finish(null); return; }
        if (reply.eventID !== eventID) { finish(null); return; }
        if (!pending) {
          if (reply.accepted !== true || !awaitDecision || reply.pending !== true) { finish(null); return; }
          pending = true; clearTimeout(timer);
          timer = setTimeout(() => finish(null), Math.min(3600000, Math.max(50, Number(route.decisionTimeoutMs) || 3540000)));
        } else { finish(isObject(reply.decision) ? reply.decision : null); return; }
      }
    });
  });
}
function decisionOutput(decision) {
  if (!isObject(decision) || !['allow', 'deny'].includes(decision.behavior)) return '';
  const result = { behavior: decision.behavior };
  if (decision.behavior === 'allow') {
    if (isObject(decision.updatedInput)) result.updatedInput = decision.updatedInput;
    if (Array.isArray(decision.updatedPermissions)) result.updatedPermissions = decision.updatedPermissions;
  } else {
    if (typeof decision.message === 'string') result.message = bounded(decision.message, 4096);
    if (decision.interrupt === true) result.interrupt = true;
  }
  const text = JSON.stringify({ hookSpecificOutput: { hookEventName: 'PermissionRequest', decision: result } });
  return Buffer.byteLength(text) <= MAX_WIRE ? text : '';
}
function statusPayload(input) {
  const result = { capturedAt: Date.now() / 1000 };
  for (const key of ['session_id', 'version', 'rate_limits', 'cost', 'model', 'context_window', 'exceeds_200k_tokens']) {
    if (input[key] !== undefined && Buffer.byteLength(JSON.stringify(input[key])) <= 16384) result[key] = input[key];
  }
  return result;
}
async function forwardStatusLine(route, input) {
  const original = route.originalStatusLine;
  if (!original || typeof original.command !== 'string' || !original.command.trim() || original.command.length > 16384) return Promise.resolve(null);
  let bash;
  if(process.platform==='win32'&&original.shell!=='powershell'){for(const candidate of [process.env.CLAUDE_CODE_GIT_BASH_PATH,process.env.ProgramFiles&&require('node:path').join(process.env.ProgramFiles,'Git','bin','bash.exe'),process.env['ProgramFiles(x86)']&&require('node:path').join(process.env['ProgramFiles(x86)'],'Git','bin','bash.exe')].filter(Boolean)){if((await fs.stat(candidate).catch(()=>null))?.isFile()){bash=candidate;break;}}}
  return new Promise(resolve => {
    let command, args;
    if(Array.isArray(original.args)&&original.args.length<=256&&original.args.every(x=>typeof x==='string'&&x.length<=16384)){command=original.command;args=original.args;}
    else if (process.platform === 'win32' && original.shell !== 'bash' && !bash) { command = 'powershell.exe'; args = ['-NoLogo', '-NoProfile', '-NonInteractive', '-Command', original.command]; }
    else { command = process.platform === 'win32' ? (bash || 'bash.exe') : '/bin/sh'; args = ['-c', original.command]; }
    let child; try { child = spawn(command, args, { windowsHide: true, stdio: ['pipe', 'pipe', 'ignore'] }); } catch { resolve(null); return; }
    let settled = false, length = 0; const chunks = [];
    const done = value => { if (settled) return; settled = true; clearTimeout(timer); resolve(value); };
    const timer = setTimeout(() => { child.kill(); done(null); }, 5000);
    child.on('error', () => done(null)); child.on('close', code => done(code === 0 ? Buffer.concat(chunks).toString('utf8') : null));
    child.stdout.on('data', chunk => { length += chunk.length; if (length > 262144) { child.kill(); done(null); } else chunks.push(chunk); });
    child.stdin.on('error', () => {}); child.stdin.end(input);
  });
}
function compactStatus(input) {
  const parts = []; if (typeof input.model?.display_name === 'string') parts.push(bounded(input.model.display_name, 256));
  for (const [key, title] of [['five_hour', '5h'], ['seven_day', '7d']]) {
    const n = input.rate_limits?.[key]?.used_percentage; if (typeof n === 'number' && Number.isFinite(n)) parts.push(title + ' ' + Math.round(n) + '%');
  }
  return parts.join(' · ');
}
async function main(args = process.argv.slice(2), { input = process.stdin, output = process.stdout } = {}) {
  try {
    const value = flag => { const i = args.indexOf(flag); return i < 0 ? undefined : args[i + 1]; };
    const route = await readRoute(value('--configuration'));
    const bytes = await readInput(input, value('--mode') === 'statusline' ? 2097152 : MAX_INPUT);
    const payload = JSON.parse(bytes.toString('utf8'));
    if (!isObject(payload)) return;
    if (value('--mode') === 'statusline') {
      if (route.provider !== 'claude') return;
      await send(route, statusPayload(payload), { kind: 'statusLine' });
      const text = await forwardStatusLine(route, bytes); output.write(text ?? compactStatus(payload)); return;
    }
    const safe = selectPayload(payload, route.provider); if (!safe) return;
    const decision = await send(route, safe, { awaitDecision: route.provider === 'claude' && route.interactiveApprovals !== false && safe.hook_event_name === 'PermissionRequest' });
    if (route.provider === 'claude') { const text = decisionOutput(decision); if (text) output.write(text); }
  } catch { /* Never alter the agent's default approval or exit behavior. */ }
}
if (require.main === module) main().then(() => { process.exitCode = 0; });
module.exports = { main, readRoute, readInput, selectPayload, send, decisionOutput, statusPayload, compactStatus, forwardStatusLine };
