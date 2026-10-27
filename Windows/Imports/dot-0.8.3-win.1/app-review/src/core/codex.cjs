'use strict';

const { EventEmitter } = require('node:events');
const fs = require('node:fs');
const fsp = fs.promises;
const path = require('node:path');
const os = require('node:os');
const rollout = require('./codex-rollout.cjs');
const rpc = require('./codex-rpc.cjs');
const { CodexHooks } = require('./codex-hooks.cjs');
const { RolloutParser, RolloutDiscovery, LineBuffer, allowedFile, readMetadata, addUsage, estimateCost, integer, object, text } = rollout;
const { CodexAppServer, CodexError, normalizeAccount, normalizeRateLimits, normalizeAccountUsage } = rpc;

// The Windows desktop's private coordination pipe does not have a published,
// versioned ownership/peer-identity contract. Quota stdio is NOT that pipe. This
// explicit capability prevents observational IDs from becoming write authority.
const DESKTOP_CAPABILITY = Object.freeze({ status: 'unsupported', reason: 'windows_desktop_ownership_transport_unverified', approvals: false, questionResponses: false, interrupt: false });

class CodexService extends EventEmitter {
  constructor(options = {}) {
    super();
    this.options = options;
    this.home = path.resolve(options.home || process.env.CODEX_HOME || path.join(os.homedir(), '.codex'));
    this.pollInterval = Math.max(500, options.pollInterval || 1500);
    this.quotaInterval = Math.max(15000, options.quotaInterval || 60000);
    this.clock = options.clock || Date.now;
    this.discovery = new RolloutDiscovery(this.home, options);
    this.rpc = options.rpcClient || new CodexAppServer({ ...options, home: this.home });
    this.hooks = new CodexHooks({ ...options, home: this.home });
    this.pendingHooks = new Map();
    this.cursors = new Map(); this.enabled = false; this.generation = 0;
    this.activityPending = null; this.quotaPending = null;
    this.quota = null; this.accountUsage = null; this.localUsage = null; this.account = null;
    this.state = { enabled: false, connected: false, message: 'disabled', capabilities: DESKTOP_CAPABILITY };
    this.maxInitialBytes = Math.max(65536, Math.min(16 * 1024 * 1024, options.maxInitialBytes || 2 * 1024 * 1024));
    this.maxPollBytes = Math.max(65536, Math.min(32 * 1024 * 1024, options.maxPollBytes || 8 * 1024 * 1024));
    this.maxFileBytesPerPoll = Math.max(65536, Math.min(this.maxPollBytes, options.maxFileBytesPerPoll || 2 * 1024 * 1024));
    this.rpc.on?.('rateLimits', raw => {
      if (!this.enabled) return;
      try { this.quota = normalizeRateLimits(raw, this.account, this.clock()); this.state.quotaConnected = true; delete this.state.quotaError; this.publish(); } catch {}
    });
    this.hooks.on('change', () => { this.state.hooks = this.hooks.getState(); this.emit('change'); });
    this.hooks.on('observation', event => this.observeHook(event));
  }

  async start() {
    if (this.enabled) return;
    this.enabled = true; const generation = ++this.generation;
    this.state = { enabled: true, connected: false, message: 'connecting', capabilities: DESKTOP_CAPABILITY };
    await this.refreshActivity();
    if (!this.enabled || generation !== this.generation) return;
    await this.hooks.start();
    if (!this.enabled || generation !== this.generation) return;
    this.activityTimer = setInterval(() => { void this.refreshActivity(); }, this.pollInterval);
    this.quotaTimer = setInterval(() => { void this.refreshQuota(); }, this.quotaInterval);
    this.activityTimer.unref?.(); this.quotaTimer.unref?.();
    // The activity reader must not wait for account networking or login failures.
    void this.refreshQuota();
  }

  async stop() {
    this.enabled = false; this.generation++;
    clearInterval(this.activityTimer); clearInterval(this.quotaTimer);
    clearTimeout(this.hookTimer); this.hookTimer = null; this.pendingHooks.clear();
    this.activityTimer = null; this.quotaTimer = null;
    this.rpc.stop(); const closedDiscovery = this.discovery.close();
    this.discovery = new RolloutDiscovery(this.home, this.options);
    this.activityPending = null; this.quotaPending = null;
    this.cursors.clear(); this.localUsage = null;
    this.state = { enabled: false, connected: false, message: 'disabled', capabilities: DESKTOP_CAPABILITY };
    this.emit('change');
    await Promise.all([closedDiscovery, this.hooks.stop()]);
  }

  async inspectHooks() {
    const inspected = await this.hooks.inspect();
    // The native executable path is implementation state, not an authority token.
    return { version: inspected.version, featureName: inspected.featureName, featureEnabled: inspected.featureEnabled, ...this.hooks.getState() };
  }

  async configure(options = {}) {
    await this.hooks.configure(options);
    if (typeof options.activityHooks === 'boolean') { this.options.activityHooks = options.activityHooks; this.hooks.options.activityHooks = options.activityHooks; }
    this.state.hooks = this.hooks.getState(); this.emit('change');
    return this.getSnapshot();
  }

  observeHook(event) {
    if (!this.enabled || !this.hooks.enabled) return;
    // Coalesce bursts without creating an unbounded promise/listener backlog.
    if (this.pendingHooks.size < 128 || this.pendingHooks.has(event.sessionId)) this.pendingHooks.set(event.sessionId, event);
    if (this.hookTimer) return;
    const generation = this.generation;
    this.hookTimer = setTimeout(async () => {
      this.hookTimer = null;
      const events = [...this.pendingHooks.values()]; this.pendingHooks.clear();
      await this.refreshActivity();
      if (!this.enabled || generation !== this.generation) return;
      for (const observation of events) {
        if (!['PreCompact', 'PostCompact'].includes(observation.event) || !observation.turnId) continue;
        for (const cursor of this.cursors.values()) {
          const parser = cursor.parser;
          if (parser.threadId !== observation.sessionId || parser.turnId !== observation.turnId || !parser.task || rollout.TERMINAL.has(parser.task.status)) continue;
          parser.task.compacting = observation.event === 'PreCompact';
          parser.task.compactionSource = 'authenticated-native-hook';
        }
      }
      this.publish();
    }, 50);
    this.hookTimer.unref?.();
  }

  async refresh() {
    if (!this.enabled) return this.getSnapshot();
    await Promise.all([this.refreshActivity(), this.refreshQuota()]);
    return this.getSnapshot();
  }

  async refreshActivity() {
    if (!this.enabled) return;
    if (this.activityPending) return this.activityPending;
    const pending = this._refreshActivity(this.generation); this.activityPending = pending;
    try { await pending; } finally { if (this.activityPending === pending) this.activityPending = null; }
  }

  async _refreshActivity(generation) {
    const discovery = this.discovery;
    try {
      const candidates = await discovery.scan();
      if (!this.enabled || generation !== this.generation) return;
      let remaining = this.maxPollBytes, observed = 0;
      const retained = new Set(candidates);
      for (const file of this.cursors.keys()) if (!retained.has(file)) this.cursors.delete(file);
      for (const file of candidates) {
        if (remaining <= 0 || !this.enabled || generation !== this.generation) break;
        const admitted = await allowedFile(discovery.root, file);
        if (!this.enabled || generation !== this.generation) return;
        if (!admitted) { this.cursors.delete(file); continue; }
        let cursor = this.cursors.get(file);
        if (cursor && (cursor.ino !== admitted.stat.ino || cursor.dev !== admitted.stat.dev || cursor.offset > admitted.stat.size)) {
          this.cursors.delete(file); cursor = null;
        }
        if (!cursor) {
          const first = await readMetadata(discovery.root, file);
          if (!this.enabled || generation !== this.generation) return;
          if (!first) continue;
          const parser = new RolloutParser(first.metadata, { clock: this.clock, truncated: first.stat.size > this.maxInitialBytes });
          if (['internal', 'unknown'].includes(parser.kind)) continue;
          const offset = Math.max(0, first.stat.size - this.maxInitialBytes);
          const lines = new LineBuffer();
          if (offset) lines.discarding = true; // skip a partial initial tail line
          cursor = { parser, offset, lines, bootstrapSize: first.stat.size, ino: first.stat.ino, dev: first.stat.dev, path: first.path, mtime: first.stat.mtimeMs };
          this.cursors.set(file, cursor);
        }
        observed++;
        let handle;
        try {
          handle = await fsp.open(cursor.path, fs.constants.O_RDONLY | (fs.constants.O_NOFOLLOW || 0));
          const stat = await handle.stat();
          if (!this.enabled || generation !== this.generation) return;
          if (!stat.isFile() || cursor.ino !== stat.ino || cursor.dev !== stat.dev || stat.size < cursor.offset) { this.cursors.delete(file); continue; }
          const target = Math.min(stat.size, cursor.offset + Math.min(remaining, this.maxFileBytesPerPoll));
          const data = Buffer.alloc(Math.min(65536, Math.max(1, target - cursor.offset)));
          while (cursor.offset < target && this.enabled && generation === this.generation) {
            // Split at bootstrap boundary so old on-disk bytes cannot become live
            // because another process appended to the file during initial replay.
            let length = Math.min(data.length, target - cursor.offset);
            const live = cursor.offset >= cursor.bootstrapSize;
            if (!live) length = Math.min(length, cursor.bootstrapSize - cursor.offset);
            const { bytesRead } = await handle.read(data, 0, length, cursor.offset);
            if (!bytesRead) break;
            cursor.offset += bytesRead; remaining -= bytesRead;
            cursor.lines.push(data.subarray(0, bytesRead), line => cursor.parser.feed(line, { live }));
          }
          cursor.mtime = stat.mtimeMs;
        } catch { if (this.enabled && generation === this.generation) this.state.activityError = 'rollout_unreadable'; }
        finally { await handle?.close().catch(() => {}); }
      }
      if (!this.enabled || generation !== this.generation) return;
      this.localUsage = this.collectUsage();
      this.state.activityConnected = observed > 0;
      if (discovery.readError) this.state.activityError = discovery.readError;
      else if (observed) delete this.state.activityError;
      this.publish();
    } catch {
      if (this.enabled && generation === this.generation) { this.state.activityError = 'rollout_scan_failed'; this.state.activityConnected = false; this.publish(); }
    }
  }

  async refreshQuota() {
    if (!this.enabled) return;
    if (this.quotaPending) return this.quotaPending;
    const pending = this._refreshQuota(this.generation); this.quotaPending = pending;
    try { await pending; } finally { if (this.quotaPending === pending) this.quotaPending = null; }
  }
  async _refreshQuota(generation) {
    try {
      // Account usage is optional on older Codex versions. A successful quota
      // response remains valid if that method is unsupported or account-scoped.
      const [limits, account, usage, metadata] = await Promise.allSettled([
        this.rpc.request('account/rateLimits/read'),
        this.rpc.request('account/read', { refreshToken: false }),
        this.rpc.request('account/usage/read'),
        this.rpc.request('thread/list', { limit: 100, sortKey: 'updated_at', archived: false }),
      ]);
      if (!this.enabled || generation !== this.generation) return;
      if (account.status === 'fulfilled') this.account = normalizeAccount(account.value);
      if (limits.status === 'rejected') throw limits.reason;
      this.quota = normalizeRateLimits(limits.value, this.account, this.clock());
      if (usage.status === 'fulfilled') this.accountUsage = normalizeAccountUsage(usage.value, this.clock());
      this.state.usageAvailable = usage.status === 'fulfilled' && this.accountUsage !== null;
      if (metadata.status === 'fulfilled' && Array.isArray(metadata.value.data)) {
        const byId = new Map([...this.cursors.values()].map(cursor => [cursor.parser.threadId, cursor.parser]));
        for (const row of metadata.value.data.slice(0, 100)) {
          if (!object(row)) continue;
          const parser = byId.get(row.id); if (!parser) continue;
          // Public name/title only; preview is an ordinary user prompt.
          const update = { id: row.id, source: row.source, thread_source: row.threadSource ?? row.thread_source, name: text(row.name ?? row.title), parentThreadId: row.parentThreadId };
          parser.updateMetadata(update);
        }
      }
      this.state.quotaConnected = true; delete this.state.quotaError;
      this.publish();
    } catch (error) {
      if (!this.enabled || generation !== this.generation) return;
      this.state.quotaConnected = false;
      this.state.quotaError = error instanceof CodexError ? error.code : 'quota_unavailable';
      if (this.quota) this.quota = { ...this.quota, stale: true, error: this.state.quotaError };
      this.publish();
    }
  }

  collectUsage() {
    const models = new Map();
    let partial = false;
    for (const cursor of this.cursors.values()) {
      if (cursor.parser.kind === 'memory') continue;
      partial ||= cursor.parser.truncated;
      for (const row of cursor.parser.history.values()) {
        const key = `${row.date}:${row.model}`;
        const existing = models.get(key);
        models.set(key, { ...row, ...existing ? addUsage(existing, row) : {}, maxInput: Math.max(existing?.maxInput ?? 0, row.maxInput ?? 0) });
      }
    }
    const days = new Map();
    for (const row of models.values()) {
      const cost = estimateCost(row.model, row, row.maxInput);
      const existing = days.get(row.date);
      const model = { model: row.model, input: row.input, output: row.output, cached: row.cached, total: row.total, cost };
      days.set(row.date, {
        date: row.date, ...existing ? addUsage(existing, row) : { input: row.input, output: row.output, cached: row.cached, total: row.total },
        cost: existing ? existing.cost === null || cost === null ? null : existing.cost + cost : cost,
        models: [...(existing?.models || []), model],
      });
    }
    return { provider: 'codex', days: [...days.values()].sort((a, b) => a.date.localeCompare(b.date)).slice(-366), updatedAt: this.clock(), source: 'local-rollouts', partial: true, tailTruncated: partial, costBasis: 'standard-api-equivalent', pricingVerifiedAt: '2026-10-21', pricingSource: 'https://developers.openai.com/api/docs/pricing' };
  }

  publish() {
    this.state.connected = !!(this.state.activityConnected || this.state.quotaConnected);
    const tasks = [...this.cursors.values()].map(cursor => cursor.parser.getTask()).filter(Boolean);
    this.state.lastEventAt = tasks.reduce((latest, task) => Math.max(latest || 0, task.updatedAt || 0), 0) || null;
    this.state.message = this.state.connected ? 'connected' : this.state.quotaError === 'codex_not_found' ? 'codex_not_found' : this.state.activityError || this.state.quotaError || 'waiting_for_codex';
    this.state.error = this.state.activityError || this.state.quotaError || null;
    this.emit('change');
  }

  getSnapshot() {
    const tasks = this.enabled ? [...this.cursors.values()].map(cursor => cursor.parser.getTask(this.clock(), this.options.staleAfter || 300000)).filter(Boolean).sort((a, b) => (b.updatedAt || 0) - (a.updatedAt || 0)) : [];
    // Account totals and local estimates have different scopes: never add them.
    // Keep account totals authoritative and expose local detail separately.
    const usage = this.accountUsage ? { ...this.accountUsage, localDays: this.localUsage?.days || [], localPartial: true } : this.localUsage;
    return structuredClone({ tasks, quota: this.enabled ? this.quota : null, usage: this.enabled ? usage : null, state: this.state });
  }

  async respond() {
    // Neither the local parser nor the independent quota server can mint an
    // owned desktop request. Fail closed for forged, stale and observed IDs.
    throw new CodexError('desktop_response_unsupported', 'This request must be answered in Codex; Windows desktop request ownership has not been verified.');
  }
}

module.exports = { CodexService, DESKTOP_CAPABILITY, ...rollout, ...rpc };
