'use strict';
const { EventEmitter } = require('node:events');
const fs = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');
const net = require('node:net');
const crypto = require('node:crypto');
const { pathToFileURL } = require('node:url');
const F = require('./integration-files.cjs');
const Claude = require('./claude-data.cjs');
const PROVIDERS = ['claude', 'dsh', 'kimi'];
const CLAUDE_EVENTS = ['SessionStart','SessionEnd','UserPromptSubmit','PreToolUse','PostToolUse','PostToolUseFailure','PermissionRequest','Notification','Stop','StopFailure','SubagentStart','SubagentStop','PreCompact','PostCompact'];
const NATIVE_EVENTS = ['SessionStart','SessionEnd','UserPromptSubmit','TurnStarted','PreToolUse','PostToolUse','PostToolUseFailure','PermissionRequest','PermissionResult','PreCompact','PostCompact','Stop','StopFailure','Interrupt','SubagentStart','SubagentStop'];
const EVENTS = new Set([...CLAUDE_EVENTS, ...NATIVE_EVENTS, 'Usage', 'Metadata']);
const terminal = status => ['completed','failed','interrupted'].includes(status);
const clip = (value, max = 256) => typeof value === 'string' ? value.slice(0, max) : undefined;
const clone = value => JSON.parse(JSON.stringify(value));
const qPS = value => "'" + value.replace(/'/g, "''") + "'";
const qSH = value => "'" + value.replace(/'/g, "'\\''") + "'";
const expandHome = (value,home) => value.replace(/^~(?=[\\/]|$)/,home);
function approvalSummary(tool,input) {
  if (!F.object(input)) return undefined;
  if (typeof input.command === 'string') return clip(input.command,65536);
  if (['Edit','MultiEdit','Write','NotebookEdit'].includes(tool)) {
    const lines = (prefix,text) => String(text??'').split('\n').map(line=>prefix+line).join('\n');
    const diff = tool==='Edit' ? lines('-',input.old_string)+'\n'+lines('+',input.new_string) : tool==='MultiEdit' ? (Array.isArray(input.edits)?input.edits:[]).map(edit=>lines('-',edit.old_string)+'\n'+lines('+',edit.new_string)).join('\n@@\n') : lines('+',input.content??input.new_source);
    return clip(tool+' · '+(input.file_path??input.notebook_path??'')+'\n'+diff,65536);
  }
  for(const key of ['url','file_path','path','pattern','query','description']) if(typeof input[key]==='string')return clip(tool+' · '+input[key],4096);
  return clip(tool+'\n'+JSON.stringify(input,null,2),4096);
}

function commandFor({ executable, hookPath, packaged, platform = process.platform, provider, routePath, mode = 'hook', electronMainPath }) {
  const args = packaged || electronMainPath ? [...(electronMainPath ? [electronMainPath] : []), '--quotaview-hook'] : [hookPath];
  args.push('--configuration', routePath, '--mode', mode);
  if (platform === 'win32' && provider === 'claude') return '& ' + [executable, ...args].map(qPS).join(' ');
  if (platform === 'win32') {
    // cmd.exe quoted paths: reject expansion/metacharacters rather than interpolate them.
    if ([executable, ...args].some(v => /[\r\n"%!]/.test(v))) throw new Error('This Windows installation path contains unsupported command-shell characters');
    return [executable, ...args].map(v => '"' + v + '"').join(' ');
  }
  return [executable, ...args].map(qSH).join(' ');
}
function validateClaude(root) {
  if (!F.object(root)) throw new Error('Claude settings must be a JSON object');
  if (root.hooks !== undefined && (!F.object(root.hooks) || !Object.values(root.hooks).every(groups => Array.isArray(groups) && groups.every(group => F.object(group) && Array.isArray(group.hooks) && group.hooks.every(F.object))))) throw new Error('Cannot safely preserve malformed Claude hooks');
  if (root.statusLine !== undefined && !F.object(root.statusLine)) throw new Error('Cannot safely preserve Claude statusLine');
}
function removeClaudeOwned(root, commands) {
  if (root.hooks === undefined) return;
  const hooks = {};
  for (const [name, groups] of Object.entries(root.hooks)) {
    const clean = groups.map(group => ({ ...group, hooks: group.hooks.filter(hook => !commands.has(hook.command)) })).filter(group => group.hooks.length);
    if (clean.length) hooks[name] = clean;
  }
  if (Object.keys(hooks).length) root.hooks = hooks; else delete root.hooks;
}
function safeParseConfig(text, kind) {
  if (kind === 'toml') { const data = require('@iarna/toml').parse(text); if (data.hooks !== undefined && !Array.isArray(data.hooks)) throw new Error('Kimi hooks must use [[hooks]] array syntax'); return data; }
  const doc = require('yaml').parseDocument(text, { uniqueKeys: true, maxAliasCount: 100 });
  if (doc.errors.length) throw new Error('Invalid DSH YAML: ' + doc.errors[0].message);
  const data = doc.toJS({ maxAliasCount: 100 }); if (data !== null && !Array.isArray(data)) throw new Error('DSH patch must contain a YAML sequence'); return data;
}
function archive(file) { return file.split(/[\\/]/).some(part => /backup|migration|archive|snapshot|\.trash/i.test(part)); }
async function discoverDSH({ roots = [], home = os.homedir(), env = process.env, appData = [env.APPDATA, env.LOCALAPPDATA].filter(Boolean) } = {}) {
  const candidates = [path.join(home, '.dsh'), ...(env.DSH_HOME ? [env.DSH_HOME] : []), ...roots.slice(0,32)];
  for (const base of appData) {
    const apps = (await fs.readdir(base, { withFileTypes: true }).catch(() => [])).slice(0,512);
    for (const app of apps) if (app.isDirectory() && !archive(app.name)) for (const name of ['harness-home','harness','.dsh']) candidates.push(path.join(base, app.name, name));
  }
  const result = [], seen = new Set();
  for (const raw of candidates) {
    const selected = await F.canonical(raw.replace(/^~(?=[\\/]|$)/, home));
    const possible = [selected, path.dirname(selected), path.dirname(path.dirname(selected)), ...['harness-home','harness','.dsh'].map(x => path.join(selected,x))];
    for (const root of possible) {
      if (archive(root)) continue;
      const profiles = (await fs.readdir(path.join(root,'profiles'), { withFileTypes: true }).catch(() => [])).slice(0,512);
      for (const entry of profiles) {
        if (!entry.isDirectory() || archive(entry.name)) continue;
        const profile = await F.canonical(path.join(root,'profiles',entry.name)), config = path.join(profile,'cordis.patch.yml');
        if (seen.has(config) || archive(profile)) continue;
        try {
          const stat = await fs.lstat(profile); if (process.platform !== 'win32' && stat.uid !== process.getuid()) continue;
          if (!(await fs.stat(path.join(profile,'cordis.yml'))).isFile()) continue;
          const manifest = await F.json(path.join(profile,'package.json'), null, 262144); if (!F.object(manifest?.dsh?.profile)) continue;
          seen.add(config); result.push({ path: config, home: await F.canonical(root), namespace: F.hash(await F.canonical(root)) });
          if (result.length >= 512) return result;
        } catch { /* Only known, valid profiles qualify. */ }
      }
      if (profiles.length) break;
    }
  }
  return result;
}
class IntegrationService extends EventEmitter {
  constructor(options = {}) {
    super();
    if (!options.dataDir) throw new Error('Integration dataDir is required');
    this.options = options; this.settings = options.settings ?? {}; this.home = options.home ?? os.homedir(); this.env = options.env ?? process.env;
    this.root = path.join(options.dataDir, 'integrations'); this.states = Object.fromEntries(PROVIDERS.map(p => [p, { enabled: false, connected: false, message: 'Disabled' }]));
    this.tasks = new Map(); this.sessions = new Map(); this.pending = new Map(); this.runtime = new Map(); this.revisions = new Map(); this.operations = new Map(); this.quota = null; this.usage = null; this.running = false;
  }
  directory(provider) { return path.join(this.root, provider); }
  routePath(provider) { return path.join(this.directory(provider), 'route.json'); }
  manifestPath(provider) { return path.join(this.directory(provider), 'installation.json'); }
  claudeHome(options = {}) { return path.resolve(expandHome(options.home || this.settings.claudeHome || this.env.CLAUDE_CONFIG_DIR || path.join(this.home,'.claude'),this.home)); }
  emitChange() { this.emit('change'); }
  getSnapshot() { return clone({ tasks: [...this.tasks.values()].sort((a,b) => b.updatedAt - a.updatedAt), quota: this.quota, usage: this.usage, states: this.states }); }
  async start() {
    if (this.running) return; this.running = true;
    for (const provider of PROVIDERS) {
      try {
        const manifest = await this.readManifest(provider);
        if (!this.settings.providers?.[provider]) { if(manifest?.configs?.length)this.states[provider]={enabled:false,connected:false,message:'Cleanup pending',error:'Some integration configuration remains recorded. Disable this connection again to retry cleanup.'};continue; }
        if (!manifest?.enabled) { this.states[provider] = { enabled: true, connected: false, error: 'Enable this connection to install its hooks.', message: 'Needs setup' }; continue; }
        await this.startProvider(provider, manifest);
      } catch (error) { this.states[provider] = { enabled: true, connected: false, error: error.message, message: 'Needs attention' }; }
    }
    await this.refresh(); this.emitChange();
  }
  async stop() { this.running = false; await Promise.all(PROVIDERS.map(p => this.stopProvider(p))); }
  async readManifest(provider) {
    const value = await F.json(this.manifestPath(provider), null);
    if (value === null) return null;
    if (!F.object(value) || value.version !== 1 || value.provider !== provider || !Array.isArray(value.configs) || value.configs.length > 512 || value.configs.some(x => !F.object(x) || typeof x.path !== 'string' || !path.isAbsolute(x.path))) throw new Error('Invalid integration installation record');
    return value;
  }
  async startProvider(provider, manifest) {
    await this.stopProvider(provider); if (!this.running) return;
    const token = crypto.randomBytes(32).toString('hex'), sockets = new Set();
    const runtime = { token, sockets, manifest, server: null, generation: crypto.randomUUID(), eventIDs: new Set() };
    const server = net.createServer({ allowHalfOpen: true }, socket => {
      if (sockets.size >= 64) { socket.destroy(); return; }
      sockets.add(socket); socket.on('error', () => {}); socket.on('close', () => { sockets.delete(socket); for (const [id,pending] of this.pending) if (pending.socket === socket) this.releasePending(id, 'Client disconnected'); });
      socket.on('end',()=>{for(const [id,pending]of this.pending)if(pending.socket===socket)this.releasePending(id,'Client disconnected');socket.end();});
      let bytes = Buffer.alloc(0), handled = false; socket.setTimeout(2000, () => socket.destroy());
      socket.on('data', data => {
        if (handled) { socket.destroy(); return; }
        if (bytes.length + data.length > 1048576) { socket.destroy(); return; }
        bytes = Buffer.concat([bytes,data]); const index = bytes.indexOf(10); if (index < 0) return; handled = true;
        let envelope; try { envelope = JSON.parse(bytes.subarray(0,index).toString('utf8')); } catch { socket.destroy(); return; }
        if (!F.object(envelope) || typeof envelope.authenticationToken !== 'string' || !/^[a-f0-9]{64}$/.test(envelope.authenticationToken) || !crypto.timingSafeEqual(Buffer.from(envelope.authenticationToken),Buffer.from(token)) || typeof envelope.eventID !== 'string' || !/^[a-zA-Z0-9:._-]{1,128}$/.test(envelope.eventID) || !F.object(envelope.payload) || this.runtime.get(provider) !== runtime || !this.states[provider].enabled || runtime.eventIDs.has(envelope.eventID)) { socket.destroy(); return; }
        runtime.eventIDs.add(envelope.eventID); if (runtime.eventIDs.size > 4096) runtime.eventIDs.delete(runtime.eventIDs.values().next().value);
        socket.setTimeout(0);
        let pending;
        try { pending = this.receive(provider, envelope, socket); } catch { socket.destroy(); return; }
        if (socket.destroyed) return;
        socket.write(JSON.stringify({ eventID: envelope.eventID, accepted: true, ...(pending ? { pending: true } : {}) }) + '\n');
        if (!pending) socket.end();
      });
    });
    runtime.server = server;
    await new Promise((resolve,reject) => { server.once('error', reject); server.listen(0,'127.0.0.1', () => { server.removeListener('error',reject); resolve(); }); });
    server.on('error', error => { if (this.runtime.get(provider) === runtime) { this.states[provider].error = error.message; this.states[provider].connected = false; this.emitChange(); } });
    this.runtime.set(provider,runtime);
    const route = { version: 1, provider, enabled: true, host: '127.0.0.1', port: server.address().port, authenticationToken: token, interactiveApprovals: manifest.interactiveApprovals !== false, decisionTimeoutMs: this.options.decisionTimeoutMs ?? 3540000, originalStatusLine: manifest.originalStatusLine ?? null };
    try { await F.atomic(this.routePath(provider),JSON.stringify(route)); } catch(error) { this.runtime.delete(provider); for(const socket of sockets)socket.destroy(); await new Promise(resolve=>server.close(resolve)); throw error; }
    this.states[provider] = { enabled: true, connected: false, message: 'Waiting for session', configuredHomes: [...new Set(manifest.configs.map(x => x.home))] };
  }
  async stopProvider(provider) {
    this.revisions.set(provider, crypto.randomUUID());
    for (const [id,pending] of this.pending) if (pending.provider === provider) this.releasePending(id, 'Connection stopped');
    const runtime = this.runtime.get(provider); this.runtime.delete(provider);
    if (runtime) { for (const socket of runtime.sockets) socket.destroy(); await new Promise(resolve => runtime.server.close(resolve)); }
    for (const [id,task] of this.tasks) if (task.provider === provider) { this.tasks.delete(id); this.sessions.delete(id); }
    if (provider === 'claude') { this.quota = null; this.usage = null; }
    this.states[provider] = { enabled: false, connected: false, message: 'Disabled' };
    try { const route = await F.json(this.routePath(provider),null,65536); if (route) await F.atomic(this.routePath(provider),JSON.stringify({...route,enabled:false})); } catch { /* A stale token is rejected because its listener is stopped. */ }
    this.emitChange();
  }
  configure(provider, enabled, options = {}) {
    if (!PROVIDERS.includes(provider)) return Promise.reject(new Error('Unsupported integration provider'));
    const previous = this.operations.get(provider) ?? Promise.resolve();
    const operation = previous.catch(() => {}).then(() => this.configureNow(provider, !!enabled, options)); this.operations.set(provider,operation); return operation;
  }
  async configureNow(provider,enabled,options) {
    const existing=this.runtime.get(provider);
    const preserve=provider==='claude'&&enabled&&existing&&existing.manifest.configs.some(x=>x.home===this.claudeHome(options));
    const previousState={...this.states[provider]};
    if(!preserve)await this.stopProvider(provider);
    else if(options.interactiveApprovals===false){existing.manifest.interactiveApprovals=false;for(const [id,pending]of this.pending)if(pending.provider==='claude')this.releasePending(id,'Continue in Claude Code; island approvals are disabled.');}
    this.states[provider] = { ...previousState, enabled, connected:preserve?previousState.connected:false, message:'Configuring' }; this.emitChange();
    try {
      const manifest = await F.withLock(this.directory(provider), async () => {
        const prior = await this.readManifest(provider);
        const result = provider === 'claude' ? await this.configureClaude(enabled,options,prior) : await this.configureNative(provider,enabled,options,prior);
        await F.atomic(this.manifestPath(provider),JSON.stringify(result,null,2)); return result;
      });
      this.settings.providers = { ...this.settings.providers, [provider]: enabled };
      if (provider === 'claude' && options.home) this.settings.claudeHome = options.home;
      if (provider === 'dsh' && options.roots) this.settings.dshRoots = options.roots.slice(0,32);
      if(preserve&&this.runtime.get(provider)===existing){
        existing.manifest=manifest;const route=await F.json(this.routePath(provider),null,65536);await F.atomic(this.routePath(provider),JSON.stringify({...route,interactiveApprovals:manifest.interactiveApprovals!==false,originalStatusLine:manifest.originalStatusLine??null}));if(!manifest.statusLine)this.quota=null;this.states[provider]={...previousState,enabled:true,error:undefined,message:previousState.connected?'Received local session events':'Waiting for session'};
      }else if (enabled && this.running) await this.startProvider(provider,manifest);
      else this.states[provider] = { enabled,connected:false,message: enabled ? 'Waiting for application start' : manifest.configs.length ? 'Cleanup pending' : 'Disabled',...(!enabled&&manifest.configs.length?{error:'Unavailable configuration paths remain recorded for cleanup. Retry when their location is available.'}:{}) };
      if (provider === 'claude' && enabled) await this.refresh(); this.emitChange(); return this.getSnapshot();
    } catch (error) { this.states[provider] = { enabled,connected:false,error:error.message,message:'Needs attention' }; this.emitChange(); throw error; }
  }
  helperCommand(provider,mode='hook') { return commandFor({ executable: this.options.executable ?? process.execPath, hookPath: this.options.hookPath ?? path.join(__dirname,'hook.cjs'), packaged:this.options.packaged ?? false, electronMainPath:this.options.electronMainPath, platform:this.options.platform ?? process.platform, provider, routePath:this.routePath(provider), mode }); }
  async configureClaude(enabled,options,prior) {
    const home = this.claudeHome(options), destination = path.join(home,'settings.json'), command = this.helperCommand('claude'), statusCommand = this.helperCommand('claude','statusline');
    const owned = new Set([...(prior?.commands ?? []), command, statusCommand]);
    const paths = [...new Set([...(prior?.configs.map(x=>x.path) ?? []), ...(enabled ? [destination] : [])])];
    let originalStatusLine = prior?.originalStatusLine ?? null;
    const edits = [], configRecords = [];
    const interactiveApprovals = options.interactiveApprovals ?? prior?.interactiveApprovals ?? true;
    const statusLine = options.statusLine ?? prior?.statusLine ?? false;
    for (const file of paths) {
      if (path.basename(file) !== 'settings.json') throw new Error('Unexpected Claude configuration path');
      const before = await F.read(file); const root = before && F.decode(before).trim() ? JSON.parse(F.decode(before)) : {}; validateClaude(root); removeClaudeOwned(root,owned);
      const priorConfig = prior?.configs.find(x=>x.path===file); const originalForFile = priorConfig?.originalStatusLine ?? prior?.originalStatusLine;
      if (root.statusLine && owned.has(root.statusLine.command)) { if (originalForFile) root.statusLine = originalForFile; else delete root.statusLine; }
      if (enabled && file === destination) {
        const hooks = root.hooks ?? {};
        for (const event of CLAUDE_EVENTS) {
          const hook = { type:'command',command,timeout:event === 'PermissionRequest' ? 3600 : 5 };
          if ((this.options.platform ?? process.platform) === 'win32') hook.shell='powershell';
          const group = { hooks:[hook] }; if (['PreToolUse','PostToolUse','PostToolUseFailure','PermissionRequest'].includes(event)) group.matcher='*';
          hooks[event] = [...(hooks[event] ?? []),group];
        }
        root.hooks = hooks;
        if (statusLine) { originalStatusLine = root.statusLine ?? null; root.statusLine = {type:'command',command:statusCommand,padding:0,...((this.options.platform ?? process.platform) === 'win32' ? {shell:'powershell'} : {})}; }
      }
      configRecords.push({path:file,home:path.dirname(file),originalStatusLine:enabled&&file===destination?originalStatusLine:originalForFile??null});
      const after = JSON.stringify(root,null,2)+'\n'; edits.push({file,before,after});
    }
    const manifest = {version:1,provider:'claude',enabled,configs:enabled ? configRecords.filter(x=>x.path===destination) : [],commands:[...owned].slice(-32),interactiveApprovals,statusLine,originalStatusLine};
    // Persist intent before edits: cleanup remains possible after a partial write.
    await F.atomic(this.manifestPath('claude'),JSON.stringify({...manifest,configs:configRecords},null,2));
    for (const edit of edits) if (edit.before !== null || enabled) await F.atomic(edit.file,edit.after,{expected:edit.before,backup:true,privateFile:false});
    return manifest;
  }
  async configureNative(provider,enabled,options,prior) {
    const marker = 'quotaview-windows-' + F.hash(this.root).slice(0,12) + '-' + provider;
    const home = path.resolve(expandHome(options.home || this.settings.kimiHome || this.env.KIMI_CODE_HOME || path.join(this.home,'.kimi-code'),this.home));
    const discovered = !enabled ? [] : provider === 'dsh' ? await discoverDSH({roots:options.roots ?? this.settings.dshRoots ?? [],home:this.home,env:this.env,appData:this.options.appData}) : [{path:path.join(home,'config.toml'),home}];
    if (enabled && !discovered.length) throw new Error('No valid DSH profile found. Choose a data root containing profiles/<name>/cordis.yml and package.json.');
    if (enabled && provider === 'kimi' && !(await fs.stat(home).catch(()=>null))?.isDirectory()) throw new Error('Kimi data directory does not exist. Start Kimi once or choose its existing data directory.');
    const active = new Map(discovered.map(x=>[x.path,x]));
    const all = [...new Map([...(prior?.configs ?? []),...discovered].map(x=>[x.path,x])).values()];
    const plugin = path.join(this.directory('dsh'),'quotaview-dsh.mjs');
    if (enabled && provider === 'dsh') await F.atomic(plugin,await fs.readFile(path.join(__dirname,'dsh-plugin.mjs')));
    const edits = [];
    for (const config of all) {
      if (path.basename(config.path) !== (provider === 'dsh' ? 'cordis.patch.yml' : 'config.toml')) throw new Error('Unexpected integration configuration path');
      const before = await F.read(config.path); let text = F.removeBlock(F.decode(before),marker);
      safeParseConfig(text,provider === 'dsh' ? 'yaml' : 'toml');
      if (active.has(config.path)) {
        if (provider === 'dsh') {
          // Empty YAML sequence needs to become a block sequence before appending.
          text = text.replace(/^\s*\[\]\s*$/m,'');
          const entry = active.get(config.path); const body = '- insert:\n    - id: '+marker+'\n      name: '+JSON.stringify(pathToFileURL(plugin).href)+'\n      config:\n        routePath: '+JSON.stringify(this.routePath(provider))+'\n        sourceNamespace: '+JSON.stringify(entry.namespace);
          text = F.appendBlock(text,marker,body);
        } else {
          const body = NATIVE_EVENTS.map(event=>'[[hooks]]\nevent = '+JSON.stringify(event)+'\ncommand = '+JSON.stringify(this.helperCommand('kimi'))+'\ntimeout = 2').join('\n\n'); text = F.appendBlock(text,marker,body);
        }
        safeParseConfig(text,provider === 'dsh' ? 'yaml' : 'toml');
      }
      edits.push({config,before,text});
    }
    const manifest = {version:1,provider,enabled,configs:discovered,marker};
    await F.atomic(this.manifestPath(provider),JSON.stringify({...manifest,configs:all},null,2));
    const unavailable = [];
    for (const {config,before,text} of edits) { if (before === null && !active.has(config.path)) { unavailable.push(config); continue; } await F.atomic(config.path,text,{expected:before,backup:true,privateFile:false}); }
    manifest.configs = [...discovered,...unavailable]; return manifest;
  }
  receive(provider,envelope,socket) {
    const payload=envelope.payload, runtime=this.runtime.get(provider); if (!runtime) return false;
    if (provider === 'claude' && envelope.kind === 'statusLine') {
      if (runtime.manifest.statusLine !== true) return false;
      const quota=Claude.normalizeQuota(payload); if (quota) { this.quota=quota; void F.atomic(path.join(this.directory('claude'),'statusline.json'),JSON.stringify({capturedAt:payload.capturedAt,rate_limits:payload.rate_limits})).catch(()=>{}); this.markConnected(provider); this.emitChange(); }
      return false;
    }
    if (envelope.kind !== 'hook' || !EVENTS.has(payload.hook_event_name) || typeof payload.session_id !== 'string' || !payload.session_id || payload.session_id.length>256) return false;
    const name=payload.hook_event_name;
    let prefix=provider+':';
    if (provider === 'dsh') {
      if (!/^[a-f0-9]{64}$/.test(payload.source_namespace) || !runtime.manifest.configs.some(x=>x.namespace===payload.source_namespace)) return false;
      prefix+=payload.source_namespace+':';
    }
    const agent=provider !== 'dsh' && typeof payload.agent_id === 'string' && payload.agent_id && payload.agent_id !== 'main' ? clip(payload.agent_id) : null;
    const rawSession=payload.session_id+(agent ? ':agent:'+agent : ''), key=F.hash(prefix+rawSession);
    let session=this.sessions.get(key);
    if(!session&&(agent||payload.parent_session_id)&&[...this.tasks.values()].filter(x=>x.parentId).length>=128)return false;
    if (!session) {
      if (this.sessions.size >= 512) { const oldest=[...this.tasks.values()].filter(x=>terminal(x.status)||x.status==='unknown').sort((a,b)=>a.updatedAt-b.updatedAt)[0]; if (!oldest) return false; this.sessions.delete(oldest.id); this.tasks.delete(oldest.id); }
      session={active:false,nativeTurn:null,turn:null,tokens:0}; this.sessions.set(key,session);
    }
    if (provider === 'dsh') {
      if (typeof payload.source_epoch !== 'string' || payload.source_epoch.length>128 || !Number.isSafeInteger(payload.source_sequence) || payload.source_sequence<0) return false;
      if (session.epoch===payload.source_epoch && payload.source_sequence<=session.sequence) return false;
      session.epoch=payload.source_epoch; session.sequence=payload.source_sequence;
    }
    const nativeTurn=clip(payload.turn_id), starting=['UserPromptSubmit','TurnStarted'].includes(name), activeEvent=['PreToolUse','PermissionRequest','PreCompact','SubagentStart'].includes(name);
    let task=this.tasks.get(key);
    const startNew=starting&&(provider==='claude'||!session.active||(nativeTurn&&session.nativeTurn&&nativeTurn!==session.nativeTurn));
    if (startNew || !session.active && activeEvent) {
      if (!starting && nativeTurn && nativeTurn===session.nativeTurn) return false;
      if (startNew || !session.active) {
        this.cancelSession(key,'New turn'); session.active=true; session.nativeTurn=nativeTurn ?? null; session.turn=crypto.randomUUID(); session.tokens=0;
        task={id:key,provider,title:clip(payload.session_title)||task?.title||({claude:'Claude Code',dsh:'DSH',kimi:'Kimi Code'}[provider]+' task'),status:'thinking',startedAt:Date.now(),updatedAt:Date.now(),source:'Local '+provider+' event',verified:true};
      }
    }
    if(starting&&nativeTurn)session.nativeTurn=nativeTurn;
    if (!task) task={id:key,provider,title:clip(payload.session_title)||({claude:'Claude Code',dsh:'DSH',kimi:'Kimi Code'}[provider]+' session'),status:'unknown',startedAt:Date.now(),updatedAt:Date.now(),source:'Local '+provider+' event',verified:true};
    if (nativeTurn && session.nativeTurn && nativeTurn!==session.nativeTurn && !starting) return false;
    const parent=agent ? payload.session_id : clip(payload.parent_session_id);
    if (parent && parent!==rawSession) task.parentId=F.hash(prefix+parent);
    if (typeof payload.session_title==='string' && payload.session_title.trim()) task.title=payload.session_title.replace(/[\r\n]+/g,' ').slice(0,256);
    if (typeof payload.model==='string') task.model=clip(payload.model,128);
    if (provider==='claude' && typeof payload.cwd==='string') task.cwd=clip(payload.cwd,4096);
    task.updatedAt=Date.now(); this.markConnected(provider);
    if (name==='SessionEnd') { this.cancelSession(key,'Session ended'); this.tasks.delete(key); this.sessions.delete(key); this.emitChange(); return false; }
    if (name==='SubagentStart' && !agent) { this.tasks.set(key,task); this.emitChange(); return false; }
    const call=clip(payload.tool_use_id ?? payload.tool_call_id), tool=clip(payload.tool_name,128);
    let pending=false;
    switch(name) {
      case 'UserPromptSubmit': case 'TurnStarted': task.status='thinking'; break;
      case 'PreToolUse': task.status='working'; if(tool) task.tool=tool; break;
      case 'PermissionRequest': {
        task.status='waiting'; if(tool) task.tool=tool;
        const request=this.makeApproval(provider,envelope,task,session,call,socket);
        task.approval=request.approval; pending=request.pending; break;
      }
      case 'PostToolUse': case 'PostToolUseFailure': case 'PermissionResult':
        this.cancelSession(key,'Tool result',call); delete task.approval; if(session.active) task.status='thinking'; break;
      case 'Notification':
        if(payload.notification_type==='permission_prompt' && !task.approval) { task.status='waiting'; task.approval={id:'notice:'+envelope.eventID,kind:'notice',title:clip(payload.title)||'Return to Claude Code',reason:clip(payload.message,4096),canRespond:false}; } break;
      case 'PreCompact': task.status='working'; task.tool='Compacting context'; break;
      case 'PostCompact': if(session.active) task.status='thinking'; delete task.tool; break;
      case 'Stop': case 'StopFailure': case 'Interrupt': case 'SubagentStop':
        this.cancelSession(key,'Turn ended'); delete task.approval; delete task.tool; session.active=false;
        task.status=name==='StopFailure' ? 'failed' : name==='Interrupt'||payload.is_interrupt===true||/interrupt|cancel/i.test(payload.stop_reason??'') ? 'interrupted' : 'completed'; task.completedAt=Date.now();
        if(provider==='kimi' && name==='Stop') { task.verified=false; task.completionNote='Kimi Stop is a pre-completion notification; later hooks may still block completion.'; }
        if(provider==='claude' && typeof payload.last_assistant_message==='string') { task.result=clip(payload.last_assistant_message,65536); task.publicText=task.result; }
        break;
      case 'Usage':
        if(provider==='dsh'&&session.active&&Number.isSafeInteger(payload.tokens)&&payload.tokens>=0&&payload.tokens<=1e9) { session.tokens=Math.min(1e12,session.tokens+payload.tokens); task.tokens={total:session.tokens}; } break;
      default: break;
    }
    this.tasks.set(key,task);
    if(provider==='claude') {
      const transcript=agent ? payload.agent_transcript_path ?? payload.transcript_path : payload.transcript_path;
      if(typeof transcript==='string') { session.transcript=transcript; void this.refreshPreview(key,runtime.generation); }
    }
    this.emitChange(); return pending;
  }
  markConnected(provider) { this.states[provider]={...this.states[provider],enabled:true,connected:true,lastEventAt:Date.now(),message:'Received local session events'}; delete this.states[provider].error; }
  makeApproval(provider,envelope,task,session,call,socket) {
    const payload=envelope.payload, input=payload.tool_input, tool=clip(payload.tool_name,128)||'Permission request', runtime=this.runtime.get(provider), id='claude:'+envelope.eventID;
    // The card exposes one actionable request. Never leave an older, hidden helper blocked.
    if(provider==='claude')this.cancelSession(task.id,'A newer permission request is shown; continue the earlier request in Claude Code.');
    const safe=F.object(input)&&!input._quotaViewTruncated;
    let canRespond=provider==='claude'&&runtime.manifest.interactiveApprovals!==false&&envelope.awaitDecision===true&&safe&&this.pending.size<64;
    let questions;
    if(tool==='AskUserQuestion') {
      questions=Array.isArray(input?.questions) ? input.questions.slice(0,16).filter(F.object).map(q=>({id:clip(q.question,4096),question:clip(q.question,4096),title:clip(q.question,4096),header:clip(q.header,128),multiSelect:q.multiSelect===true,options:Array.isArray(q.options)?q.options.slice(0,32).filter(F.object).map(o=>({label:clip(o.label,256),description:clip(o.description,1024)})):[]})) : [];
      if(!questions.length||!Array.isArray(input?.questions)||input.questions.length>4||input.questions.some(q=>!F.object(q)||typeof q.question!=='string'||!q.question.trim()||q.question.length>4096||!Array.isArray(q.options)||!q.options.length||q.options.length>32||q.options.some(o=>!F.object(o)||typeof o.label!=='string'||!o.label||o.label.length>256))||new Set(questions.map(q=>q.id)).size!==questions.length) canRespond=false;
    }
    const suggestions=Array.isArray(payload.permission_suggestions)&&payload.permission_suggestions.length<=64?payload.permission_suggestions.filter(F.object):[];
    const approval={id:provider==='claude'?id:'notice:'+envelope.eventID,kind:canRespond?(tool==='AskUserQuestion'?'question':tool==='Bash'||tool==='PowerShell'?'command':'permission'):'notice',title:tool,canRespond, ...(provider==='claude'?{command:tool==='AskUserQuestion'?undefined:approvalSummary(tool,input),cwd:task.cwd,reason:clip(input?.description,4096),scope:suggestions.length?clone(suggestions):'once',questions}:{}), decisions:canRespond?['accept',...(suggestions.length?['acceptForSession','acceptAlways']:[]),'decline','cancel']:[]};
    if(!canRespond) { approval.reason=provider==='claude'?'Continue in Claude Code. This request cannot be answered here.':'Confirm in the original agent. This connection is notice-only.'; return {approval,pending:false}; }
    const timer=setTimeout(()=>this.releasePending(id,'Approval timed out'),Math.min(3600000,Math.max(50,this.options.decisionTimeoutMs??3540000)));
    this.pending.set(id,{id,eventID:envelope.eventID,provider,sessionKey:task.id,turn:session.turn,socket,timer,tool,input:clone(input),suggestions:clone(suggestions),questions,call});
    return {approval,pending:true};
  }
  releasePending(id,reason) {
    const pending=this.pending.get(id); if(!pending)return;
    this.pending.delete(id); clearTimeout(pending.timer);
    if(!pending.socket.destroyed) pending.socket.end(JSON.stringify({eventID:pending.eventID,released:true})+'\n');
    const task=this.tasks.get(pending.sessionKey); if(task?.approval?.id===id) { task.approval={...task.approval,kind:'notice',canRespond:false,reason,decisions:[]}; this.emitChange(); }
  }
  cancelSession(key,reason,call) { for(const [id,pending] of this.pending) if(pending.sessionKey===key&&(!call||!pending.call||pending.call===call))this.releasePending(id,reason); }
  async respond(id,decision) {
    if(typeof id!=='string'||!id.startsWith('claude:'))throw new Error('Only live Claude permission requests can be answered');
    const pending=this.pending.get(id),runtime=this.runtime.get('claude');
    if(!pending||!runtime||runtime.manifest.interactiveApprovals===false||!this.states.claude.enabled||pending.socket.destroyed)throw new Error('This approval is no longer active. Continue in Claude Code.');
    const supplied=typeof decision==='string'?{decision}:decision;
    if(!F.object(supplied))throw new Error('Invalid approval decision');
    let result; const choice=supplied.decision ?? supplied.behavior;
    if(pending.tool==='AskUserQuestion'&&supplied.answers) {
      const answers=Object.create(null); for(const question of pending.questions) { const value=supplied.answers[question.id]; const selections=typeof value==='string'?[value]:Array.isArray(value)?value:value?.answers; if(!Array.isArray(selections)||!selections.length||selections.length>32||(!question.multiSelect&&selections.length!==1)||selections.some(answer=>typeof answer!=='string'||!answer.trim()||answer.length>4096))throw new Error('Answer every question before submitting'); answers[question.id]=[...new Set(selections)].join(', '); }
      result={behavior:'allow',updatedInput:{...pending.input,answers}};
    } else if(['accept','allow','allowOnce'].includes(choice)) {
      if(pending.tool==='AskUserQuestion')throw new Error('Question answers are required'); result={behavior:'allow'};
    } else if(['acceptForSession','allowSession','acceptAlways','allowAlways'].includes(choice)) {
      if(!pending.suggestions.length||pending.tool==='AskUserQuestion')throw new Error('This request did not supply permission rules');
      result={behavior:'allow',updatedPermissions:['acceptForSession','allowSession'].includes(choice)?pending.suggestions.map(x=>({...x,destination:'session'})):pending.suggestions};
    } else if(['decline','deny'].includes(choice))result={behavior:'deny',message:'The user declined this request in QuotaView.'};
    else if(choice==='cancel')result={behavior:'deny',message:'The user cancelled this request in QuotaView.',interrupt:true};
    else if(choice==='passthrough') { this.releasePending(id,'Continue in Claude Code'); return {accepted:true}; }
    else throw new Error('Unsupported approval decision');
    this.pending.delete(id);clearTimeout(pending.timer);
    pending.socket.end(JSON.stringify({eventID:pending.eventID,decision:result})+'\n');
    const task=this.tasks.get(pending.sessionKey);if(task?.approval?.id===id){delete task.approval;task.status='thinking';task.updatedAt=Date.now();} this.emitChange();return {accepted:true};
  }
  async refreshPreview(key,generation) {
    const runtime=this.runtime.get('claude'),session=this.sessions.get(key);if(!runtime||runtime.generation!==generation||!session?.transcript||session.reading)return;
    session.reading=true; const turn=session.turn;
    try {
      const home=runtime.manifest.configs.find(x=>x.home)?.home??this.claudeHome(), preview=await Claude.transcriptPreview(home,session.transcript,{includeSidechain:!!this.tasks.get(key)?.parentId});
      const task=this.tasks.get(key);if(preview&&task&&this.runtime.get('claude')===runtime&&this.sessions.get(key)?.turn===turn){
        if(preview.title)task.title=preview.title;if(preview.model)task.model=preview.model;if(preview.tokens)task.tokens=preview.tokens;if(preview.publicText){task.publicText=preview.publicText;if(task.status==='completed')task.result=preview.publicText;}
        if(preview.interrupted&&session.active){task.status='interrupted';session.active=false;task.completedAt=Date.now();this.cancelSession(key,'Interrupted');delete task.approval;}this.emitChange();
      }
    }catch{/* A missing/unreadable transcript leaves hook state intact. */}finally{session.reading=false;}
  }
  async refresh() {
    const runtime=this.runtime.get('claude');if(!runtime||!this.states.claude.enabled)return;
    if(runtime.refreshing)return runtime.refreshing;
    const generation=runtime.generation,home=runtime.manifest.configs.find(x=>x.home)?.home??this.claudeHome();
    runtime.refreshing=(async()=>{
      const cancelled=()=>this.runtime.get('claude')!==runtime||!this.states.claude.enabled;
      const usage=await Claude.scanUsage(home,{cancelled,cache:runtime.usageCache??(runtime.usageCache=new Map())});if(cancelled())return;this.usage=usage;
      if(runtime.manifest.statusLine){let snapshot;try{snapshot=await F.json(path.join(this.directory('claude'),'statusline.json'),null,65536);}catch{}const quota=Claude.normalizeQuota(snapshot);if(quota&&(!this.quota||quota.updatedAt>this.quota.updatedAt))this.quota=quota;}
      const account=await Claude.accountInfo(home,!!(this.settings.claudeHome||this.env.CLAUDE_CONFIG_DIR||home!==path.join(this.home,'.claude')));if(cancelled())return;if(account&&this.quota)this.quota.account=account;
      await Promise.all([...this.sessions.keys()].filter(key=>this.tasks.get(key)?.provider==='claude').map(key=>this.refreshPreview(key,generation)));if(!cancelled())this.emitChange();
    })().finally(()=>{runtime.refreshing=null;});return runtime.refreshing;
  }
}
module.exports={IntegrationService,commandFor,validateClaude,removeClaudeOwned,discoverDSH,safeParseConfig,CLAUDE_EVENTS,NATIVE_EVENTS};
