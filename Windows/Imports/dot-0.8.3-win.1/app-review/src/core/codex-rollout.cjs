'use strict';

// Read-only projection of Codex's native JSONL. No prompt, reasoning, tool
// arguments, credentials or response capability is retained by this module.
const fs = require('node:fs');
const fsp = fs.promises;
const path = require('node:path');
const crypto = require('node:crypto');
const { wrappedPlan } = require('./codex-plan.cjs');
const MAX_LINE = 1024 * 1024;
const TERMINAL = new Set(['completed', 'failed', 'interrupted']);
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const integer = value => Number.isSafeInteger(value) && value >= 0 ? value : null;
const text = (value, limit = 512) => typeof value === 'string' && value.trim() && Buffer.byteLength(value) <= limit ? value.trim().replace(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/g, '') : null;
const identifier = value => typeof value === 'string' && value.length > 0 && Buffer.byteLength(value) <= 1024 && !/[\x00-\x1f\x7f]/.test(value) ? value : null;
const hash = value => crypto.createHash('sha256').update(String(value)).digest('hex').slice(0, 32);
const taskID = value => `codex:${hash(value)}`;
const parseObject = value => { if (object(value)) return value; if (typeof value !== 'string' || Buffer.byteLength(value) > MAX_LINE) return null; try { const parsed = JSON.parse(value); return object(parsed) ? parsed : null; } catch { return null; } };
const eventTime = value => typeof value === 'string' && Number.isFinite(Date.parse(value)) ? Date.parse(value) : null;

function sourceObject(source) { return parseObject(source); }
function childIdentity(meta) {
  if (!object(meta) || !identifier(meta.id)) return null;
  const source = sourceObject(meta.source);
  const tags = source ? ['internal', 'subagent', 'subAgent'].filter(k => Object.hasOwn(source, k)) : [];
  if ((meta.threadSource ?? meta.thread_source) === 'memory_consolidation' || tags.includes('internal') || tags.length > 1) return null;
  let spawn = null;
  if (tags.length) {
    const subtype = source[tags[0]];
    if (Object.keys(source).length !== 1 || !object(subtype) || Object.keys(subtype).length !== 1 || !object(subtype.thread_spawn)) return null;
    spawn = subtype.thread_spawn;
  }
  const direct = meta.parentThreadId ?? meta.parent_thread_id;
  const nested = spawn?.parent_thread_id;
  if (direct != null && nested != null && direct !== nested) return null;
  const parent = identifier(direct ?? nested);
  if (!parent || parent === meta.id) return null;
  const depth = spawn?.depth;
  if (depth != null && (integer(depth) === null || depth > 1024)) return null;
  let avatarIndex = 0;
  // Codex's native palette hash is over UTF-16 code units, not code points.
  for (let i = 0; i < meta.id.length; i++) avatarIndex = (avatarIndex * 31 + meta.id.charCodeAt(i)) % 2147483647;
  return { parentId: taskID(parent), depth: depth ?? null, nickname: text(meta.agentNickname ?? meta.agent_nickname ?? spawn?.agent_nickname, 256), role: text(meta.agentRole ?? meta.agent_role ?? spawn?.agent_role, 256), avatarIndex: avatarIndex % 28 };
}

function classifySession(meta) {
  const source = sourceObject(meta.source);
  const threadSource = meta.threadSource ?? meta.thread_source;
  const tags = source ? ['internal', 'subagent', 'subAgent'].filter(k => Object.hasOwn(source, k)) : [];
  if (tags.length > 1) return 'internal';
  if (threadSource === 'memory_consolidation' || tags.some(tag => source[tag] === 'memory_consolidation')) return 'memory';
  const child = childIdentity(meta);
  if (tags.includes('internal')) return 'internal';
  if (tags.length && !child) return 'internal';
  if (threadSource && !['user', 'agent_created_thread', 'subagent'].includes(threadSource)) return 'internal';
  if (child) return 'subagent';
  if (threadSource === 'subagent' || (typeof meta.source === 'string' && /subagent/i.test(meta.source))) return 'internal';
  if (['user', 'agent_created_thread'].includes(threadSource) || ['cli', 'exec', 'vscode', 'appServer', 'app-server'].includes(meta.source)) return 'user';
  return 'unknown';
}

function normalizePlan(raw) {
  const value = parseObject(raw);
  if (!value || !Array.isArray(value.plan) || value.plan.length < 1 || value.plan.length > 100) return null;
  const steps = [];
  for (const item of value.plan) {
    if (!object(item)) return null;
    const status = item.status === 'inProgress' ? 'in_progress' : item.status;
    if (!['completed', 'in_progress', 'pending'].includes(status)) return null;
    const label = text(item.step ?? item.text, 2048);
    if (!label) return null;
    steps.push({ text: label, status });
  }
  const completed = steps.filter(x => x.status === 'completed').length;
  const active = steps.filter(x => x.status === 'in_progress').length;
  return { completed, total: steps.length, steps, fraction: Math.min(.95, (completed + active * .1) / steps.length), source: 'native-plan' };
}

function normalizeQuestions(raw, asynchronous = false) {
  const value = parseObject(raw);
  if (!value || !Array.isArray(value.questions) || value.questions.length < 1 || value.questions.length > 32) return null;
  const result = [], ids = new Set();
  for (const [index, item] of value.questions.entries()) {
    if (!object(item)) return null;
    const id = identifier(item.id ?? (asynchronous ? `question-${index + 1}` : null));
    const question = text(asynchronous ? item.title : item.question, 16384);
    if (!id || !question || ids.has(id)) return null;
    ids.add(id);
    const out = { id, question, header: text(item.header, 128), isSecret: item.isSecret === true, isOther: asynchronous || item.isOther === true };
    if (item.options != null) {
      if (!Array.isArray(item.options) || item.options.length > 32) return null;
      out.options = [];
      for (const option of item.options) {
        const label = text(asynchronous ? option : option?.label, 16384);
        if (!label) return null;
        out.options.push({ label, description: asynchronous ? null : text(option.description, 16384) });
      }
    }
    result.push(out);
  }
  return result;
}

function asyncReplyIndices(payload, callId, questions) {
  if (!Array.isArray(payload.content) || payload.content.length !== 1 || !['input_text', 'text'].includes(payload.content[0]?.type)) return null;
  const raw = payload.content[0].text;
  if (typeof raw !== 'string' || Buffer.byteLength(raw) > 131072) return null;
  const opening = '<send_user_message_question_reply>', closing = '</send_user_message_question_reply>';
  const trimmed = raw.trim();
  if (!trimmed.startsWith(opening) || !trimmed.endsWith(closing)) return null;
  let body;
  try { body = JSON.parse(trimmed.slice(opening.length, -closing.length)); } catch { return null; }
  const entries = Array.isArray(body) ? body : [body];
  if (entries.length < 1 || entries.length > 32) return null;
  const indices = new Set();
  for (const entry of entries) {
    if (!object(entry) || typeof entry.questionItemId !== 'string' || Buffer.byteLength(entry.questionItemId) > 2048 || !text(entry.answer, 65536)) return null;
    let tuple; try { tuple = JSON.parse(entry.questionItemId); } catch { return null; }
    if (!Array.isArray(tuple) || tuple.length !== 3 || tuple[0] !== 'request_user_input_async' || tuple[1] !== callId || integer(tuple[2]) === null || tuple[2] >= questions.length || JSON.stringify(tuple) !== entry.questionItemId || indices.has(tuple[2]) || entry.question !== questions[tuple[2]].question) return null;
    indices.add(tuple[2]);
  }
  return [...indices];
}

function tokens(raw) {
  if (!object(raw)) return null;
  const result = {};
  for (const [dest, key] of Object.entries({ input: 'input_tokens', output: 'output_tokens', cached: 'cached_input_tokens', total: 'total_tokens' })) {
    const value = raw[key] ?? (dest === 'cached' ? raw.input_tokens_details?.cached_tokens : undefined);
    if (value != null && integer(value) === null) return null;
    result[dest] = value == null ? null : value;
  }
  if (result.total === null && result.input !== null && result.output !== null) result.total = integer(result.input + result.output);
  if (result.total === null || (result.cached !== null && result.input !== null && result.cached > result.input)) return null;
  if (result.input !== null && result.output !== null && result.input + result.output !== result.total) return null;
  return result;
}

function subtractUsage(total, previous) {
  if (!previous || total.total < previous.total) return null;
  const delta = {};
  for (const key of ['input', 'output', 'cached', 'total']) {
    delta[key] = total[key] !== null && previous[key] !== null && total[key] >= previous[key] ? total[key] - previous[key] : null;
  }
  return delta;
}
function addUsage(a, b) {
  const sum = {};
  for (const key of ['input', 'output', 'cached', 'total']) sum[key] = a[key] == null || b[key] == null ? null : integer(a[key] + b[key]);
  return sum;
}

// Standard API-equivalent estimates, not subscription charges. Verified 2026-10-21:
// https://developers.openai.com/api/docs/pricing (gpt-5.3-codex)
// https://developers.openai.com/api/docs/models/gpt-5.4 (standard short context).
// Unknown/new models and incomplete counters deliberately have no estimate.
const PRICE_RATES = Object.freeze({
  'gpt-5.3-codex': Object.freeze({ input: 1.75, cached: .175, output: 14 }),
  'gpt-5.4': Object.freeze({ input: 2.5, cached: .25, output: 15, longContext: 272000 }),
});
function estimateCost(model, usage, maxInput = null) {
  const rate = PRICE_RATES[model];
  if (!rate || !usage || ['input', 'output', 'cached'].some(key => integer(usage[key]) === null) || usage.cached > usage.input) return null;
  if (rate.longContext && (integer(maxInput) === null || maxInput > rate.longContext)) return null;
  return ((usage.input - usage.cached) * rate.input + usage.cached * rate.cached + usage.output * rate.output) / 1e6;
}

class RolloutParser {
  constructor(metadata, options = {}) {
    if (!object(metadata) || !identifier(metadata.id)) throw new Error('invalid_session_metadata');
    this.threadId = metadata.id;
    this.kind = classifySession(metadata);
    this.child = childIdentity(metadata);
    this.metadata = { title: text(metadata.name ?? metadata.title), cwd: text(metadata.cwd, 4096), model: text(metadata.model, 256) };
    this.task = null;
    this.turnId = null;
    this.cumulative = null;
    this.turnBaseline = null;
    this.hasDirectUsage = false;
    this.history = new Map();
    this.truncated = options.truncated === true;
    this.maxDays = options.maxDays || 366;
    this.clock = options.clock || Date.now;
    this.liveWindow = options.liveWindow || 120000;
    this.lastLiveAt = null;
    this.disposition = null;
    this.maxInput = null;
    this.seen = new Set();
  }

  updateMetadata(meta) {
    if (meta.id !== this.threadId) return false;
    const kind = classifySession(meta);
    if (kind === 'internal') { this.kind = kind; this.task = null; return false; }
    if (kind !== 'unknown' && this.kind !== 'memory' && !(this.kind === 'subagent' && kind === 'user')) this.kind = kind;
    this.child = childIdentity(meta) ?? this.child;
    if (text(meta.name ?? meta.title)) this.metadata.title = text(meta.name ?? meta.title);
    if (this.task) {
      this.task.sessionKind = this.kind;
      this.task.title = this.kind === 'memory' ? 'Memory consolidation' : this.metadata.title ?? this.task.title;
      if (this.child) Object.assign(this.task, this.child);
      if (this.kind === 'memory') { delete this.task.publicText; delete this.task.result; delete this.task.approval; delete this.task.progress; }
    }
    return true;
  }

  feed(line, { live = false } = {}) {
    if ((typeof line !== 'string' && !Buffer.isBuffer(line)) || Buffer.byteLength(line) > MAX_LINE) return false;
    let envelope;
    try { envelope = JSON.parse(line.toString()); } catch { return false; }
    if (!object(envelope) || !object(envelope.payload)) return false;
    const p = envelope.payload;
    if (envelope.type === 'session_meta') return this.updateMetadata(p);
    if (this.kind === 'internal' || this.kind === 'unknown') return false;
    if (p.thread_id != null && p.thread_id !== this.threadId) return false;
    const at = eventTime(envelope.timestamp);
    const now = this.clock();
    const fresh = live && at !== null && at <= now + 30000 && at >= now - this.liveWindow;
    // Stable native ordinals are a stronger replay key than timestamps/content.
    if (integer(envelope.ordinal) !== null) {
      const key = `${envelope.ordinal}:${envelope.type}:${p.type ?? ''}`;
      if (this.seen.has(key)) return false;
      this.seen.add(key);
      if (this.seen.size > 4096) this.seen.delete(this.seen.values().next().value);
    }
    if (envelope.type === 'event_msg' && p.type === 'task_started') {
      if (!identifier(p.turn_id)) return false;
      if (p.turn_id === this.turnId) return false;
      if (at !== null && this.task?.startedAt != null && at < this.task.startedAt) return false;
      this.turnId = p.turn_id;
      this.turnBaseline = this.cumulative;
      this.hasDirectUsage = false;
      this.firstUsageInTurn = true;
      this.disposition = 'thinking';
      this.lastLiveAt = fresh ? now : null;
      const cwd = this.metadata.cwd;
      const workspace = cwd ? path.win32.basename(cwd.replaceAll('/', '\\')) : null;
      this.task = {
        id: taskID(this.threadId), provider: 'codex', title: this.kind === 'memory' ? 'Memory consolidation' : this.metadata.title ?? this.child?.nickname ?? workspace ?? 'Codex',
        status: fresh ? 'thinking' : 'unknown', startedAt: at, updatedAt: at, model: this.metadata.model,
        cwd, source: 'codex-rollout', verified: true, sessionKind: this.kind, turnId: hash(p.turn_id),
        live: fresh, ...(this.child || {}),
      };
      return true;
    }
    if (envelope.type === 'turn_context') {
      if (!this.task && identifier(p.turn_id)) {
        // A bounded tail may omit task_started. Context can identify a dormant
        // row, but it cannot supply a start time or evidence of live execution.
        this.turnId = p.turn_id;
        this.firstUsageInTurn = true;
        this.disposition = 'thinking';
        const cwd = this.metadata.cwd;
        this.task = { id: taskID(this.threadId), provider: 'codex', title: this.kind === 'memory' ? 'Memory consolidation' : this.metadata.title ?? this.child?.nickname ?? (cwd ? path.win32.basename(cwd.replaceAll('/', '\\')) : 'Codex'),
          status: 'unknown', startedAt: null, updatedAt: at, cwd, source: 'codex-rollout', verified: true,
          sessionKind: this.kind, turnId: hash(p.turn_id), live: false, contextOnly: true, ...(this.child || {}) };
      }
      if (!this.task || p.turn_id !== this.turnId) return false;
      const model = text(p.model, 256);
      if (model) { this.task.model = model; this.metadata.model = model; }
      this.task.reasoningEffort = text(p.effort ?? p.reasoning_effort, 64);
      // turn_context by itself is never evidence of a live turn.
      return true;
    }
    if (!this.task || TERMINAL.has(this.task.status)) return false;
    if (p.turn_id != null && p.turn_id !== this.turnId) return false;
    let changed = false;
    if (envelope.type === 'event_msg') {
      if (['task_complete', 'turn_aborted', 'turn_failed'].includes(p.type)) {
        // Exact completion identity is mandatory. Legacy abort has no turn ID.
        if (p.type !== 'turn_aborted' && p.turn_id !== this.turnId) return false;
        this.task.status = p.type === 'task_complete' ? 'completed' : p.type === 'turn_aborted' ? 'interrupted' : 'failed';
        this.task.completedAt = at;
        this.task.live = false;
        this.task.approval = undefined;
        if (this.kind !== 'memory' && p.type === 'task_complete' && text(p.last_agent_message, 32768)) this.task.result = text(p.last_agent_message, 32768);
        if (this.task.progress && p.type === 'task_complete') this.task.progress.fraction = 1;
        changed = true;
      } else if (p.type === 'token_count') {
        const total = tokens(p.info?.total_token_usage), last = tokens(p.info?.last_token_usage);
        if (!total || !last || total.total < last.total) return false;
        changed = this.recordUsage(total, last, null, at);
      } else if (['item_started', 'item_completed'].includes(p.type) && p.item?.type === 'ContextCompaction') {
        this.task.compacting = p.type === 'item_started'; changed = true;
      }
    } else if (envelope.type === 'token_usage_record') {
      if (p.thread_id !== this.threadId || p.turn_id !== this.turnId) return false;
      const direct = tokens(p.turn_token_usage), total = tokens(p.thread_token_usage), last = tokens(p.usage);
      if (!direct || !total || !last || total.total < direct.total || direct.total < last.total) return false;
      changed = this.recordUsage(total, last, direct, at);
    } else if (envelope.type === 'response_item') {
      if (p.type === 'message' && p.role === 'user' && this.task.approval?.asynchronous) {
        const indices = asyncReplyIndices(p, this.questionCall, this.task.approval.questions);
        if (!indices) return false;
        for (const index of indices) this.task.approval.questions[index].answered = true;
        if (this.task.approval.questions.every(question => question.answered)) { delete this.task.approval; this.questionCall = null; }
        // Native reply proof settles display only. User input is not execution
        // evidence, and neither answer text nor the containing prompt is kept.
        return true;
      } else if (p.type === 'message' && p.role === 'assistant' && ['commentary', 'final'].includes(p.channel ?? 'final')) {
        if (this.kind === 'memory') return false;
        const content = Array.isArray(p.content) ? p.content.slice(0, 128).filter(x => object(x) && ['output_text', 'text'].includes(x.type)).map(x => typeof x.text === 'string' ? x.text : '').join('\n') : '';
        const value = text(content.slice(0, 32768), 131072);
        if (!value) return false;
        if (p.channel === 'commentary') this.task.publicText = value;
        else this.task.result = value;
        // A final message is content, not a completion signal.
        changed = true;
      } else if (['function_call', 'custom_tool_call'].includes(p.type)) {
        const name = text(p.name, 256);
        if (!name || !identifier(p.call_id)) return false;
        this.task.tool = name;
        this.disposition = 'working';
        if (this.kind !== 'memory' && ['update_plan', 'functions.update_plan', 'exec', 'functions.exec', 'functions__exec'].includes(name)) {
          const wrapped = ['exec', 'functions.exec', 'functions__exec'].includes(name);
          const plan = normalizePlan(wrapped ? wrappedPlan(p.input ?? p.arguments) : p.arguments ?? p.input);
          if (plan) this.task.progress = plan;
        }
        if (this.kind !== 'memory' && ['request_user_input', 'functions.request_user_input', 'request_user_input_async', 'functions.request_user_input_async'].includes(name)) {
          const asynchronous = name.endsWith('_async');
          const questions = normalizeQuestions(p.arguments ?? p.input, asynchronous);
          if (questions) {
            this.task.approval = { id: `codex-observed:${hash(`${this.threadId}:${this.turnId}:${p.call_id}`)}`, kind: 'question', title: questions[0].question, questions, canRespond: false, asynchronous, reason: 'desktop_transport_unverified', source: 'read-only-rollout' };
            this.questionCall = p.call_id;
            if (!asynchronous) this.disposition = 'waiting';
          }
        }
        changed = true;
      } else if (['function_call_output', 'custom_tool_call_output'].includes(p.type)) {
        if (p.call_id === this.questionCall && !this.task.approval?.asynchronous) {
          delete this.task.approval; this.questionCall = null; this.disposition = 'working'; changed = true;
        }
        // Tool output is not public assistant prose and never copied into UI.
      }
    }
    if (changed) {
      if (at !== null) this.task.updatedAt = Math.max(this.task.updatedAt ?? at, at);
      if (fresh && !TERMINAL.has(this.task.status)) { this.lastLiveAt = now; this.task.live = true; this.task.status = this.disposition; }
    }
    return changed;
  }

  recordUsage(total, last, direct, at) {
    // Newer rollout formats can emit both native and legacy counters. High-water
    // cumulative deltas deduplicate the two without summing repeated snapshots.
    if (direct && this.hasDirectUsage && direct.total < this.task.tokens.total) return false;
    if (this.cumulative && total.total < this.cumulative.total && this.firstUsageInTurn) {
      // Older Codex releases reset their supposedly cumulative counter per turn.
      this.cumulative = null; this.turnBaseline = null;
    }
    let delta = subtractUsage(total, this.cumulative);
    if (!this.cumulative) delta = last;
    else if (total.total < this.cumulative.total) return false;
    this.cumulative = total;
    this.firstUsageInTurn = false;
    if (last.input !== null) this.maxInput = Math.max(this.maxInput ?? 0, last.input);
    if (direct) { this.task.tokens = direct; this.hasDirectUsage = true; }
    else if (!this.hasDirectUsage) this.task.tokens = subtractUsage(total, this.turnBaseline) ?? { ...last, partial: true };
    if (delta && delta.total > 0 && at !== null) {
      const date = new Date(at).toISOString().slice(0, 10);
      const model = this.task.model || 'unknown';
      const key = `${date}:${model}`;
      const previous = this.history.get(key);
      this.history.set(key, { date, model, ...previous ? addUsage(previous, delta) : delta, maxInput: Math.max(previous?.maxInput ?? 0, last.input ?? 0), partial: this.truncated || !this.turnBaseline });
      while (this.history.size > this.maxDays * 8) this.history.delete(this.history.keys().next().value);
    }
    return true;
  }

  getTask(now = this.clock(), staleAfter = 300000) {
    if (!this.task) return null;
    const task = structuredClone(this.task);
    if (!TERMINAL.has(task.status) && (!this.lastLiveAt || now - this.lastLiveAt > staleAfter)) {
      task.status = 'unknown'; task.live = false;
    }
    if (task.tokens) { task.estimatedCost = estimateCost(task.model, task.tokens, this.maxInput); task.costBasis = 'standard-api-equivalent'; }
    return task;
  }
}

class LineBuffer {
  constructor(maximum = MAX_LINE) { this.maximum = maximum; this.pending = Buffer.alloc(0); this.discarding = false; this.rejected = 0; }
  push(chunk, consume) {
    let start = 0;
    for (let i = 0; i < chunk.length; i++) {
      if (chunk[i] !== 10) continue;
      if (!this.discarding) {
        const piece = chunk.subarray(start, i);
        if (this.pending.length + piece.length <= this.maximum) {
          const line = this.pending.length ? Buffer.concat([this.pending, piece]) : piece;
          if (line.length) consume(line[line.length - 1] === 13 ? line.subarray(0, -1) : line);
        } else this.rejected++;
      }
      this.pending = Buffer.alloc(0); this.discarding = false; start = i + 1;
    }
    const tail = chunk.subarray(start);
    if (!this.discarding && tail.length) {
      if (this.pending.length + tail.length > this.maximum) { this.pending = Buffer.alloc(0); this.discarding = true; this.rejected++; }
      else this.pending = Buffer.concat([this.pending, tail]);
    }
  }
}

function inside(root, target) {
  const relative = path.relative(root, target);
  return relative !== '' && !relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative);
}

async function allowedFile(root, file) {
  if (!inside(root, path.resolve(file)) || path.extname(file).toLowerCase() !== '.jsonl') return null;
  try {
    const stat = await fsp.lstat(file);
    if (!stat.isFile() || stat.isSymbolicLink()) return null;
    const resolved = await fsp.realpath(file);
    if (!inside(root, resolved)) return null;
    // Reject symlink/junction ancestors even when they happen to resolve inside.
    let parent = path.dirname(file);
    while (parent !== root && inside(root, parent)) {
      if ((await fsp.lstat(parent)).isSymbolicLink()) return null;
      parent = path.dirname(parent);
    }
    return { path: resolved, stat };
  } catch { return null; }
}

async function allowedDirectory(root, directory) {
  if (directory !== root && !inside(root, directory)) return false;
  try {
    const resolved = await fsp.realpath(directory);
    if (resolved !== root && !inside(root, resolved)) return false;
    let current = directory;
    while (true) {
      const stat = await fsp.lstat(current);
      if (!stat.isDirectory() || stat.isSymbolicLink()) return false;
      if (current === root) return true;
      current = path.dirname(current);
      if (current !== root && !inside(root, current)) return false;
    }
  } catch { return false; }
}

async function readMetadata(root, file) {
  const admitted = await allowedFile(root, file);
  if (!admitted) return null;
  let handle;
  try {
    handle = await fsp.open(admitted.path, fs.constants.O_RDONLY | (fs.constants.O_NOFOLLOW || 0));
    const opened = await handle.stat();
    if (!opened.isFile() || opened.ino !== admitted.stat.ino || opened.dev !== admitted.stat.dev) return null;
    const data = Buffer.alloc(Math.min(MAX_LINE + 1, opened.size));
    const { bytesRead } = await handle.read(data, 0, data.length, 0);
    const newline = data.subarray(0, bytesRead).indexOf(10);
    if (newline < 1 || newline > MAX_LINE) return null;
    const envelope = JSON.parse(data.subarray(0, newline).toString());
    if (envelope.type !== 'session_meta' || !object(envelope.payload) || !identifier(envelope.payload.id)) return null;
    return { metadata: envelope.payload, stat: opened, path: admitted.path };
  } catch { return null; } finally { await handle?.close(); }
}

class RolloutDiscovery {
  constructor(home, { maximumCandidates = 128, entriesPerPoll = 512 } = {}) {
    this.sessions = path.resolve(home, 'sessions'); this.root = null;
    this.maximumCandidates = Math.max(1, Math.min(512, maximumCandidates));
    this.entriesPerPoll = Math.max(1, Math.min(4096, entriesPerPoll));
    this.queue = []; this.current = null; this.known = new Map(); this.readError = null;
  }
  async scan() {
    this.readError = null;
    try {
      const st = await fsp.lstat(this.sessions);
      if (!st.isDirectory() || st.isSymbolicLink()) { this.readError = 'sessions_directory_unsafe'; return []; }
      this.root = await fsp.realpath(this.sessions);
    } catch (error) { if (error.code !== 'ENOENT') this.readError = 'sessions_unreadable'; return []; }
    if (!this.current && !this.queue.length) this.queue.push(this.root);
    for (let i = 0; i < this.entriesPerPoll; i++) {
      if (!this.current) {
        const next = this.queue.shift(); if (!next) break;
        if (!await allowedDirectory(this.root, next)) continue;
        try { this.current = { path: next, dir: await fsp.opendir(next, { bufferSize: 32 }) }; }
        catch { this.readError = 'sessions_unreadable'; continue; }
      }
      let entry;
      try { entry = await this.current.dir.read(); } catch { this.readError = 'sessions_unreadable'; }
      if (!entry) { await this.current.dir.close().catch(() => {}); this.current = null; continue; }
      if (entry.isSymbolicLink() || entry.name.startsWith('.')) continue;
      const target = path.join(this.current.path, entry.name);
      if (entry.isDirectory() && this.queue.length < 4096) this.queue.push(target);
      if (entry.isFile() && entry.name.endsWith('.jsonl')) {
        try { this.known.set(target, (await fsp.stat(target)).mtimeMs); } catch {}
      }
    }
    // Dated fast path prevents a long history walk from hiding new live tasks.
    for (const offset of [0, -86400000]) {
      const date = new Date(Date.now() + offset).toISOString().slice(0, 10).replaceAll('-', path.sep);
      const directory = path.join(this.root, date);
      let dir;
      try {
        if (!await allowedDirectory(this.root, directory)) continue;
        dir = await fsp.opendir(directory);
        for (let i = 0; i < 128; i++) { const entry = await dir.read(); if (!entry) break; if (entry.isFile() && entry.name.endsWith('.jsonl')) { const target = path.join(directory, entry.name); this.known.set(target, (await fsp.stat(target)).mtimeMs); } }
      } catch {} finally { await dir?.close().catch(() => {}); }
    }
    for (const file of this.known.keys()) {
      try { const stat = await fsp.lstat(file); if (!stat.isFile() || stat.isSymbolicLink()) this.known.delete(file); else this.known.set(file, stat.mtimeMs); } catch { this.known.delete(file); }
    }
    const ordered = [...this.known.entries()].sort((a, b) => b[1] - a[1]);
    this.known = new Map(ordered.slice(0, 1024));
    return ordered.slice(0, this.maximumCandidates).map(([file]) => file);
  }
  async close() { if (this.current) await this.current.dir.close().catch(() => {}); this.current = null; this.queue = []; }
}

module.exports = { MAX_LINE, TERMINAL, object, integer, text, identifier, hash, taskID, parseObject, eventTime, childIdentity, classifySession, normalizePlan, normalizeQuestions, tokens, subtractUsage, addUsage, PRICE_RATES, estimateCost, RolloutParser, LineBuffer, inside, allowedFile, allowedDirectory, readMetadata, RolloutDiscovery };
