'use strict';

const { EventEmitter } = require('node:events');
const { execFile } = require('node:child_process');
const path = require('node:path');
const net = require('node:net');
const crypto = require('node:crypto');
const F = require('./integration-files.cjs');
const { locateCodexExecutable, CodexError } = require('./codex-rpc.cjs');
const { EVENTS } = require('./codex-hook.cjs');
const OWNER = 'quotaview-windows-codex-hooks';

function hookCommand({ executable, helperPath, routePath, packaged = false, electronMainPath, platform = process.platform }) {
  const args = packaged || electronMainPath ? [...(electronMainPath ? [electronMainPath] : []), '--quotaview-codex-hook'] : [helperPath];
  args.push('--configuration', routePath);
  const values = [executable, ...args];
  if (values.some(value => typeof value !== 'string' || !value || /[\r\n\0]/.test(value))) throw new CodexError('invalid_hook_command');
  if (platform === 'win32') {
    // Codex's Windows command hooks use the native command shell. Quoted args
    // are safe only without cmd variable/quote expansion. Refuse unusual paths.
    if (values.some(value => /["%!]/.test(value))) throw new CodexError('unsupported_hook_path_characters');
    return values.map(value => `"${value}"`).join(' ');
  }
  return values.map(value => `'${value.replaceAll("'", "'\\''")}'`).join(' ');
}
function parseFeatureList(output) {
  let legacy = null;
  for (const line of output.split(/\r?\n/)) {
    const fields = line.trim().split(/\s+/), name = fields[0], state = fields.at(-1);
    if (!['hooks', 'codex_hooks'].includes(name) || !['true', 'false'].includes(state)) continue;
    const feature = { name, enabled: state === 'true' };
    if (name === 'hooks') return feature;
    legacy = feature;
  }
  return legacy;
}
function nativeRun(executable, args, { home, env = process.env } = {}) {
  return new Promise((resolve, reject) => {
    execFile(executable, args, { cwd: home, env: { ...env, CODEX_HOME: home }, shell: false, windowsHide: true, timeout: 8000, maxBuffer: 65536, encoding: 'utf8' }, (error, stdout) => {
      if (error) reject(new CodexError(error.killed ? 'hook_inspection_timed_out' : 'hook_inspection_failed'));
      else resolve(stdout);
    });
  });
}
function validateHooks(root) {
  if (!F.object(root)) throw new CodexError('invalid_hooks_file');
  if (root.hooks === undefined) return;
  if (!F.object(root.hooks) || !Object.values(root.hooks).every(groups => Array.isArray(groups) && groups.every(group => F.object(group) && Array.isArray(group.hooks) && group.hooks.every(F.object)))) throw new CodexError('invalid_hooks_file');
}
function removeOwned(root, commands) {
  if (!root.hooks) return;
  for (const [event, groups] of Object.entries(root.hooks)) {
    // Only exact commands recorded for this install. A product-name substring
    // never proves ownership, and other matchers/options survive unchanged.
    root.hooks[event] = groups.map(group => ({ ...group, hooks: group.hooks.filter(hook => !commands.has(hook.command)) })).filter(group => group.hooks.length > 0);
    if (!root.hooks[event].length) delete root.hooks[event];
  }
}

class CodexHooks extends EventEmitter {
  constructor(options = {}) {
    super(); this.options = options; this.home = path.resolve(options.home);
    this.directory = options.dataDir ? path.join(options.dataDir, 'integrations', 'codex', F.hash(this.home).slice(0, 16)) : null;
    this.routePath = this.directory && path.join(this.directory, 'route.json');
    this.manifestPath = this.directory && path.join(this.directory, 'installation.json');
    this.hooksPath = path.join(this.home, 'hooks.json');
    this.run = options.runCommand || nativeRun;
    this.runtime = null; this.enabled = false; this.queue = Promise.resolve(); this.revision = 0;
    this.state = { configured: false, connected: false, message: 'hooks_disabled' };
  }
  async inspect() {
    const executable = await locateCodexExecutable({ executable: this.options.executable, env: this.options.env });
    if (!executable) throw new CodexError('codex_not_found');
    const version = (await this.run(executable, ['--version'], { home: this.home, env: this.options.env })).trim();
    if (!version || version.length > 512) throw new CodexError('invalid_codex_version');
    const feature = parseFeatureList(await this.run(executable, ['features', 'list'], { home: this.home, env: this.options.env }));
    if (!feature) throw new CodexError('hooks_feature_unavailable');
    return { version, featureName: feature.name, featureEnabled: feature.enabled, executable };
  }
  async readManifest() {
    if (!this.manifestPath) return null;
    const manifest = await F.json(this.manifestPath, null, 65536);
    if (!manifest) return null;
    if (!F.object(manifest) || manifest.version !== 1 || manifest.owner !== OWNER || manifest.home !== this.home || !Array.isArray(manifest.commands) || manifest.commands.length > 8 || manifest.commands.some(command => typeof command !== 'string' || command.length > 32768 || !command.includes('--configuration') || !command.includes(this.routePath))) throw new CodexError('invalid_hook_installation');
    return manifest;
  }
  currentCommand() {
    return hookCommand({ executable: this.options.hookExecutable || process.execPath, helperPath: this.options.helperPath || path.join(__dirname, 'codex-hook.cjs'), routePath: this.routePath, packaged: this.options.packaged, electronMainPath: this.options.electronMainPath });
  }
  configure(options = {}) {
    const operation = this.queue.catch(() => {}).then(() => this.configureNow(options));
    this.queue = operation; return operation;
  }
  async configureNow({ activityHooks, enableFeature = false, scope = 'all' } = {}) {
    if (!this.directory) throw new CodexError('hook_data_directory_required');
    if (typeof activityHooks !== 'boolean' || !['all', 'compaction'].includes(scope)) throw new CodexError('invalid_hook_configuration');
    let inspection = null;
    if (activityHooks) {
      inspection = await this.inspect();
      if (!inspection.featureEnabled) {
        if (enableFeature !== true) throw new CodexError('hooks_feature_enable_requires_opt_in');
        // The native CLI owns TOML changes. Never silently rewrite config.toml.
        const configPath = path.join(this.home, 'config.toml');
        const before = await F.read(configPath);
        if (before) {
          const backup = configPath + '.quotaview-' + F.hash(before).slice(0, 12) + '.backup';
          const fs = require('node:fs/promises');
          try { await fs.writeFile(backup, before, { flag: 'wx', mode: 0o600 }); } catch (error) { if (error.code !== 'EEXIST') throw error; }
        }
        await this.run(inspection.executable, ['features', 'enable', inspection.featureName], { home: this.home, env: this.options.env });
        inspection = await this.inspect();
        if (!inspection.featureEnabled) throw new CodexError('hooks_feature_still_disabled');
        inspection.didEnableFeature = true;
      }
    }
    const manifest = await F.withLock(this.directory, async () => {
      const prior = await this.readManifest();
      const before = await F.read(this.hooksPath);
      const root = before ? JSON.parse(F.decode(before)) : {};
      validateHooks(root);
      const command = this.currentCommand();
      const owned = new Set([...(prior?.commands || []), command]);
      removeOwned(root, owned);
      if (activityHooks) {
        root.hooks ||= {};
        for (const event of scope === 'compaction' ? ['PreCompact', 'PostCompact'] : EVENTS) {
          root.hooks[event] ||= [];
          root.hooks[event].push({ hooks: [{ type: 'command', command, timeout: 2 }] });
        }
      }
      const next = { version: 1, owner: OWNER, home: this.home, enabled: activityHooks, scope, command, commands: [...owned].slice(-8), installationId: F.hash(command), versionDetected: inspection?.version ?? prior?.versionDetected ?? null };
      // Record ownership first so a later disk error never leaves untracked
      // entries. A prepared record does not authorize starting the bridge.
      await F.atomic(this.manifestPath, JSON.stringify({ ...next, enabled: false, prepared: true }, null, 2));
      await F.atomic(this.hooksPath, JSON.stringify(root, null, 2) + '\n', { expected: before, backup: true });
      await F.atomic(this.manifestPath, JSON.stringify(next, null, 2));
      return next;
    });
    if (activityHooks && this.enabled) await this.startBridge(manifest);
    else await this.stopBridge();
    this.state = { configured: activityHooks, connected: false, message: activityHooks ? 'hooks_awaiting_trust_or_event' : 'hooks_disabled', scope, version: inspection?.version ?? manifest.versionDetected, didEnableFeature: inspection?.didEnableFeature === true };
    this.emit('change'); return this.getState();
  }
  async start() {
    this.enabled = true;
    if (!this.directory || this.options.activityHooks !== true) return;
    try {
      const manifest = await this.readManifest();
      if (manifest?.enabled) {
        if (manifest.command !== this.currentCommand()) {
          this.state = { configured: true, connected: false, scope: manifest.scope, message: 'hooks_reconfiguration_required', error: 'hook_executable_moved' };
        } else { await this.startBridge(manifest); this.state = { configured: true, connected: false, scope: manifest.scope, message: 'hooks_awaiting_trust_or_event', version: manifest.versionDetected }; }
      }
    } catch (error) { this.state = { configured: false, connected: false, error: error.code || 'hook_start_failed', message: 'hooks_need_attention' }; }
    this.emit('change');
  }
  async startBridge(manifest) {
    await this.stopBridge();
    const revision = this.revision;
    const token = crypto.randomBytes(32).toString('hex');
    const runtime = { token, server: null, sockets: new Set(), seen: new Set(), installationId: manifest.installationId };
    const server = net.createServer(socket => {
      if (runtime.sockets.size >= 32) { socket.destroy(); return; }
      runtime.sockets.add(socket); socket.on('close', () => runtime.sockets.delete(socket)); socket.on('error', () => {});
      socket.setTimeout(1000, () => socket.destroy()); let buffer = Buffer.alloc(0), handled = false;
      socket.on('data', chunk => {
        if (handled || buffer.length + chunk.length > 8192) { socket.destroy(); return; }
        buffer = Buffer.concat([buffer, chunk]); const index = buffer.indexOf(10); if (index < 0) return; handled = true;
        let envelope; try { envelope = JSON.parse(buffer.subarray(0, index)); } catch { socket.destroy(); return; }
        const payload = envelope?.payload;
        if (!F.object(envelope) || typeof envelope.authenticationToken !== 'string' || !/^[a-f0-9]{64}$/.test(envelope.authenticationToken) || !crypto.timingSafeEqual(Buffer.from(token), Buffer.from(envelope.authenticationToken)) || envelope.installationId !== runtime.installationId || typeof envelope.eventId !== 'string' || !/^[a-zA-Z0-9._:-]{1,128}$/.test(envelope.eventId) || runtime.seen.has(envelope.eventId) || !F.object(payload) || !EVENTS.has(payload.event) || typeof payload.sessionId !== 'string' || payload.sessionId.length < 1 || Buffer.byteLength(payload.sessionId) > 1024 || /[\x00-\x1f\x7f]/.test(payload.sessionId) || (payload.turnId != null && (typeof payload.turnId !== 'string' || payload.turnId.length < 1 || Buffer.byteLength(payload.turnId) > 1024 || /[\x00-\x1f\x7f]/.test(payload.turnId))) || this.runtime !== runtime || !this.enabled) { socket.destroy(); return; }
        for (const key of ['toolUseId', 'toolName']) {
          if (payload[key] != null && (typeof payload[key] !== 'string' || !payload[key].length || Buffer.byteLength(payload[key]) > 1024 || /[\x00-\x1f\x7f]/.test(payload[key]))) { socket.destroy(); return; }
        }
        runtime.seen.add(envelope.eventId); if (runtime.seen.size > 4096) runtime.seen.delete(runtime.seen.values().next().value);
        const event = { event: payload.event, sessionId: payload.sessionId, turnId: payload.turnId ?? null, toolUseId: payload.toolUseId ?? null, toolName: payload.toolName ?? null, observedAt: Date.now() };
        this.state.connected = true; this.state.message = 'hooks_connected'; this.state.lastEventAt = event.observedAt;
        socket.end(JSON.stringify({ eventId: envelope.eventId, accepted: true }) + '\n');
        this.emit('observation', event); this.emit('change');
      });
    });
    runtime.server = server;
    await new Promise((resolve, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', () => { server.removeListener('error', reject); resolve(); }); });
    if (!this.enabled || revision !== this.revision) { await new Promise(resolve => server.close(resolve)); return; }
    server.on('error', () => { if (this.runtime === runtime) { this.state.connected = false; this.state.error = 'hook_bridge_failed'; this.emit('change'); } });
    this.runtime = runtime;
    try {
      await F.atomic(this.routePath, JSON.stringify({ version: 1, provider: 'codex', enabled: true, host: '127.0.0.1', port: server.address().port, authenticationToken: token, installationId: manifest.installationId }));
    } catch (error) { await this.stopBridge(); throw error; }
  }
  async stopBridge() {
    this.revision++;
    const runtime = this.runtime; this.runtime = null;
    if (runtime) { for (const socket of runtime.sockets) socket.destroy(); await new Promise(resolve => runtime.server.close(resolve)); }
    if (this.routePath) {
      try { const before = await F.read(this.routePath); if (before) { const route = JSON.parse(F.decode(before)); await F.atomic(this.routePath, JSON.stringify({ ...route, enabled: false }), { expected: before }); } } catch {}
    }
    this.state.connected = false;
  }
  async stop() { this.enabled = false; await this.stopBridge(); this.emit('change'); }
  getState() { return { ...this.state }; }
}

module.exports = { CodexHooks, OWNER, hookCommand, parseFeatureList, nativeRun, validateHooks, removeOwned };
