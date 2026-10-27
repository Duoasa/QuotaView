'use strict';

// A separate, read-only quota connection. It never owns the desktop's turns and
// must never be used to answer their approvals, resume threads or consume resets.
// Protocol: https://developers.openai.com/codex/app-server/
const { EventEmitter } = require('node:events');
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const fsp = fs.promises;
const os = require('node:os');
const path = require('node:path');
const { LineBuffer, MAX_LINE, object, integer, text } = require('./codex-rollout.cjs');

class CodexError extends Error {
  constructor(code, message = code) { super(message); this.name = 'CodexError'; this.code = code; }
}

async function locateCodexExecutable({ executable, env = process.env, platform = process.platform, arch = process.arch } = {}) {
  const explicit = executable || env.CODEX_EXECUTABLE;
  const candidates = [];
  const executableName = platform === 'win32' ? 'codex.exe' : 'codex';
  if (explicit) candidates.push(explicit);
  else {
    for (const directory of (env.PATH || env.Path || env.path || '').split(platform === 'win32' ? ';' : path.delimiter)) {
      // Never search the process CWD from an empty PATH segment.
      if (directory && path.isAbsolute(directory)) candidates.push(path.join(directory, executableName));
    }
    if (platform === 'win32') {
      const npm = env.APPDATA && path.join(env.APPDATA, 'npm');
      const triple = arch === 'arm64' ? 'aarch64-pc-windows-msvc' : 'x86_64-pc-windows-msvc';
      const packages = [npm, env.LOCALAPPDATA && path.join(env.LOCALAPPDATA, 'npm')].filter(Boolean);
      for (const root of packages) {
        candidates.push(path.join(root, 'node_modules', '@openai', `codex-win32-${arch === 'arm64' ? 'arm64' : 'x64'}`, 'vendor', triple, 'codex', 'codex.exe'));
        candidates.push(path.join(root, 'node_modules', '@openai', 'codex', 'vendor', triple, 'codex', 'codex.exe'));
        candidates.push(path.join(root, 'node_modules', '@openai', 'codex', 'node_modules', '@openai', `codex-win32-${arch === 'arm64' ? 'arm64' : 'x64'}`, 'vendor', triple, 'codex', 'codex.exe'));
      }
      // Desktop extracts its signed CLI into bounded version directories. Do not
      // invoke PowerShell, install a CLI, or inspect protected WindowsApps trees.
      if (env.LOCALAPPDATA) {
        for (const product of ['Codex', 'ChatGPT']) {
          const bin = path.join(env.LOCALAPPDATA, 'OpenAI', product, 'bin');
          let directory;
          try {
            directory = await fsp.opendir(bin);
            const versions = [];
            for (let i = 0; i < 128; i++) { const entry = await directory.read(); if (!entry) break; if (entry.isDirectory() && !entry.isSymbolicLink()) { const target = path.join(bin, entry.name, 'codex.exe'); try { versions.push([target, (await fsp.stat(target)).mtimeMs]); } catch {} } }
            versions.sort((a, b) => b[1] - a[1]); candidates.push(...versions.map(([file]) => file));
          } catch {} finally { await directory?.close().catch(() => {}); }
        }
      }
    }
  }
  for (const candidate of candidates) {
    // Windows .cmd/.bat shims require shell interpretation. Locate native vendor
    // binaries instead; an override must name the executable, not shell syntax.
    if (typeof candidate !== 'string' || !path.isAbsolute(candidate) || /[\r\n\0]/.test(candidate)) continue;
    if (platform === 'win32' && path.extname(candidate).toLowerCase() !== '.exe') continue;
    try {
      const resolved = await fsp.realpath(candidate);
      const stat = await fsp.stat(resolved);
      if (!stat.isFile() || stat.size === 0) continue;
      await fsp.access(resolved, platform === 'win32' ? fs.constants.F_OK : fs.constants.X_OK);
      return resolved;
    } catch {}
  }
  return null;
}

const READ_METHODS = new Set(['account/read', 'account/rateLimits/read', 'account/usage/read', 'thread/list']);
class CodexAppServer extends EventEmitter {
  constructor(options = {}) {
    super(); this.options = options; this.child = null; this.initialized = false;
    this.pending = new Map(); this.nextID = 1; this.epoch = 0; this.connecting = null;
    this.timeout = options.requestTimeout || 15000;
    this.startupTimeout = options.startupTimeout || 45000;
    this.spawnProcess = options.spawnProcess || spawn;
    this.maxLine = options.maxLine || MAX_LINE;
  }
  async connect() {
    if (this.initialized && this.child) return;
    if (this.connecting) return this.connecting;
    const connection = this._connect(); this.connecting = connection;
    try { await connection; } finally { if (this.connecting === connection) this.connecting = null; }
  }
  async _connect() {
    this.stop();
    const epoch = this.epoch;
    const env = { ...process.env, ...this.options.env };
    const executable = await locateCodexExecutable({ executable: this.options.executable, env });
    if (epoch !== this.epoch) throw new CodexError('cancelled');
    if (!executable) throw new CodexError('codex_not_found');
    if (this.options.home) env.CODEX_HOME = this.options.home;
    let child;
    try { child = this.spawnProcess(executable, ['app-server'], { cwd: this.options.home || os.homedir(), env, shell: false, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] }); }
    catch { throw new CodexError('codex_launch_failed'); }
    this.child = child;
    const lines = new LineBuffer(this.maxLine);
    child.on('error', () => { if (this.epoch === epoch) this.stop(new CodexError('codex_launch_failed')); });
    child.on('close', () => { if (this.epoch === epoch) this.stop(new CodexError('connection_closed')); });
    child.stdin.on('error', () => { if (this.epoch === epoch) this.stop(new CodexError('connection_closed')); });
    child.stdout.on('data', chunk => {
      if (this.epoch !== epoch) return;
      lines.push(Buffer.from(chunk), line => this.handleLine(line, epoch));
      if (lines.rejected && this.epoch === epoch) this.stop(new CodexError('protocol_message_too_large'));
    });
    // Drain diagnostics without retaining or publishing possibly sensitive text.
    child.stderr.on('data', () => {});
    try {
      await this._request('initialize', { clientInfo: { name: 'quotaview_windows', title: 'QuotaView', version: this.options.version || '0.1.0' } }, this.startupTimeout);
      if (this.epoch !== epoch) throw new CodexError('connection_closed');
      this._write({ method: 'initialized', params: {} });
      this.initialized = true;
    } catch (error) { if (this.epoch === epoch) this.stop(); throw error; }
  }
  _write(message) {
    if (!this.child?.stdin?.writable) throw new CodexError('connection_closed');
    const encoded = JSON.stringify(message);
    if (Buffer.byteLength(encoded) > this.maxLine) throw new CodexError('protocol_message_too_large');
    this.child.stdin.write(encoded + '\n');
  }
  _request(method, params, timeout = this.timeout) {
    if (this.pending.size >= 16) return Promise.reject(new CodexError('too_many_requests'));
    const id = this.nextID++;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id); reject(new CodexError('request_timed_out'));
        this.stop(new CodexError('request_timed_out'));
      }, timeout);
      this.pending.set(id, { resolve, reject, timer, method });
      try { this._write({ id, method, params: params ?? null }); }
      catch (error) { clearTimeout(timer); this.pending.delete(id); reject(error); }
    });
  }
  async request(method, params = null) {
    if (!READ_METHODS.has(method)) throw new CodexError('read_only_connection');
    await this.connect();
    return this._request(method, params);
  }
  handleLine(line, epoch = this.epoch) {
    if (epoch !== this.epoch) return;
    let message;
    try { message = JSON.parse(line.toString()); } catch { this.stop(new CodexError('invalid_protocol_message')); return; }
    if (!object(message)) { this.stop(new CodexError('invalid_protocol_message')); return; }
    // Server requests are not responses to our quota reads, even if their IDs
    // happen to collide. Never mint approvals from this independent connection.
    if (typeof message.method === 'string') {
      if (Object.hasOwn(message, 'id')) {
        if (typeof message.id === 'string' || Number.isSafeInteger(message.id)) {
          try { this._write({ id: message.id, error: { code: -32601, message: 'Read-only QuotaView connection does not handle server requests' } }); } catch {}
        }
        return;
      }
      if (message.method === 'account/rateLimits/updated' && object(message.params)) this.emit('rateLimits', message.params);
      return;
    }
    // Exact numeric type prevents a string ID from settling another request.
    if (!Number.isSafeInteger(message.id)) return;
    const request = this.pending.get(message.id); if (!request) return;
    this.pending.delete(message.id); clearTimeout(request.timer);
    const hasResult = Object.hasOwn(message, 'result'), hasError = Object.hasOwn(message, 'error');
    if (hasResult === hasError) { request.reject(new CodexError('invalid_protocol_message')); return; }
    if (hasError) {
      const code = Number.isSafeInteger(message.error?.code) ? message.error.code : null;
      // Never expose server error text, which can include auth headers or paths.
      const error = new CodexError(code === -32601 ? 'method_unsupported' : code === -32602 ? 'invalid_parameters' : 'codex_request_failed');
      error.rpcCode = code; request.reject(error);
    } else if (!object(message.result)) request.reject(new CodexError('invalid_protocol_message'));
    else request.resolve(message.result);
  }
  stop(error = new CodexError('connection_closed')) {
    this.epoch++; this.initialized = false; this.connecting = null;
    for (const request of this.pending.values()) { clearTimeout(request.timer); request.reject(error); }
    this.pending.clear();
    const child = this.child; this.child = null;
    if (child) { try { child.stdin.end(); child.kill(); } catch {} }
  }
}

function normalizeAccount(value) {
  const account = value?.account;
  if (!object(account)) return null;
  return { email: text(account.email, 320), plan: text(account.planType, 128), type: text(account.type, 64) };
}
function normalizeRateLimits(raw, account = null, now = Date.now()) {
  if (!object(raw)) throw new CodexError('invalid_rate_limits');
  const map = object(raw.rateLimitsByLimitId) ? raw.rateLimitsByLimitId : null;
  const primary = object(map?.codex) ? map.codex : raw.rateLimits;
  if (!object(primary)) throw new CodexError('invalid_rate_limits');
  const windows = [];
  const entries = map ? Object.entries(map).slice(0, 32) : [['codex', primary]];
  if (map && !Object.hasOwn(map, 'codex')) entries.unshift(['codex', primary]);
  for (const [limitId, limits] of entries) {
    if (!object(limits)) continue;
    for (const slot of ['primary', 'secondary']) {
      const value = limits[slot]; if (!object(value)) continue;
      const percent = typeof value.usedPercent === 'number' && Number.isFinite(value.usedPercent) && value.usedPercent >= 0 && value.usedPercent <= 100 ? value.usedPercent : null;
      windows.push({ name: `${limitId}:${slot}`, limitId: text(limitId, 128), label: text(limits.limitName, 256), slot, usedPercent: percent, resetAt: integer(value.resetsAt) !== null && value.resetsAt <= 8640000000000 ? value.resetsAt * 1000 : null, windowMinutes: integer(value.windowDurationMins) });
    }
  }
  const quota = { provider: 'codex', updatedAt: now, account: { ...(account || {}), plan: text(primary.planType, 128) ?? account?.plan ?? null }, windows, source: 'codex-app-server' };
  if (object(primary.credits)) quota.credits = { balance: text(primary.credits.balance, 128), unlimited: typeof primary.credits.unlimited === 'boolean' ? primary.credits.unlimited : null, hasCredits: typeof primary.credits.hasCredits === 'boolean' ? primary.credits.hasCredits : null };
  if (integer(raw.rateLimitResetCredits?.availableCount) !== null) quota.resetCredits = { availableCount: raw.rateLimitResetCredits.availableCount, demonstrationOnly: true };
  if (object(primary.individualLimit)) quota.individualLimit = { limit: text(primary.individualLimit.limit, 128), used: text(primary.individualLimit.used, 128), remainingPercent: integer(primary.individualLimit.remainingPercent), resetAt: integer(primary.individualLimit.resetsAt) !== null ? primary.individualLimit.resetsAt * 1000 : null };
  return quota;
}
function normalizeAccountUsage(raw, now = Date.now()) {
  if (!object(raw) || !object(raw.summary)) return null;
  const summary = {};
  for (const key of ['lifetimeTokens', 'peakDailyTokens', 'longestRunningTurnSec', 'currentStreakDays', 'longestStreakDays']) summary[key] = integer(raw.summary[key]);
  const days = [];
  if (Array.isArray(raw.dailyUsageBuckets)) {
    for (const row of raw.dailyUsageBuckets.slice(0, 3660)) {
      if (!object(row) || typeof row.startDate !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(row.startDate) || !Number.isFinite(Date.parse(row.startDate)) || new Date(row.startDate).toISOString().slice(0, 10) !== row.startDate || integer(row.tokens) === null) continue;
      days.push({ date: row.startDate, input: null, output: null, cached: null, total: row.tokens, cost: null });
    }
  }
  return { provider: 'codex', days, summary, updatedAt: now, source: 'codex-account', costBasis: 'unavailable', partial: raw.dailyUsageBuckets == null };
}

module.exports = { CodexError, locateCodexExecutable, CodexAppServer, READ_METHODS, normalizeAccount, normalizeRateLimits, normalizeAccountUsage };
