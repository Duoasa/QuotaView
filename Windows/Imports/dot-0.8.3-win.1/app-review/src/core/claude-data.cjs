'use strict';
const fs = require('node:fs/promises');
const path = require('node:path');
const { read, json, contained, canonical, object } = require('./integration-files.cjs');
const MAX_LINE = 4 * 1024 * 1024;
function tokens(usage) {
  if (!object(usage)) return null;
  const count = value => value === undefined ? 0 : Number.isSafeInteger(value) && value >= 0 && value <= 1e9 ? value : null;
  const input = count(usage.input_tokens), output = count(usage.output_tokens), cached = count(usage.cache_read_input_tokens);
  let write5m = count(usage.cache_creation_input_tokens), write1h = 0;
  if (object(usage.cache_creation) && (usage.cache_creation.ephemeral_5m_input_tokens !== undefined || usage.cache_creation.ephemeral_1h_input_tokens !== undefined)) { write5m = count(usage.cache_creation.ephemeral_5m_input_tokens); write1h = count(usage.cache_creation.ephemeral_1h_input_tokens); }
  if ([input, output, cached, write5m, write1h].includes(null)) return null;
  return { input, output, cached, write5m, write1h, total: input + output + cached + write5m + write1h };
}
// Snapshot of the upstream QuotaView model price table, not live account billing.
function rates(model) {
  if (typeof model !== 'string') return null;
  const parts = model.toLowerCase().split(/[^a-z0-9]+/), index = parts.findIndex(x => ['fable', 'mythos', 'opus', 'sonnet', 'haiku'].includes(x));
  if (index < 0) return null;
  const version = []; for (const x of parts.slice(index + 1)) { if (!/^\d{1,2}$/.test(x)) break; version.push(Number(x)); }
  if (!version.length) { for (const x of parts.slice(0, index).reverse()) { if (!/^\d{1,2}$/.test(x)) break; version.unshift(Number(x)); } }
  const [major, minor = 0] = version, at = (a, b) => major > a || major === a && minor >= b;
  switch (parts[index]) {
    case 'fable': case 'mythos': return major === 5 ? [10, 50, 12.5, 20, minor >= 1 ? .25 : 1] : null;
    case 'opus': return at(5, 5) && major === 5 ? [4,20,5,8,.2] : at(4,5) && major <= 5 ? [5,25,6.25,10,.5] : [3,4].includes(major) ? [15,75,18.75,30,1.5] : null;
    case 'sonnet': return major === 5 ? [2,10,2.5,4,.2] : [3,4].includes(major) ? [3,15,3.75,6,.3] : null;
    case 'haiku': return major === 4 && minor >= 5 ? [1,5,1.25,2,.1] : major === 3 && minor === 5 ? [.8,4,1,1.6,.08] : null;
    default: return null;
  }
}
function cost(model, usage) { const r = rates(model); return r ? (usage.input*r[0] + usage.output*r[1] + usage.write5m*r[2] + usage.write1h*r[3] + usage.cached*r[4]) / 1e6 : null; }
function parseLine(line) { if (!line || Buffer.byteLength(line) > MAX_LINE) return null; try { const data = JSON.parse(line); return object(data) ? data : null; } catch { return null; } }
function usageRecord(item) {
  if (item?.type !== 'assistant' || !object(item.message) || item.message.model === '<synthetic>') return null;
  const usage = tokens(item.message.usage), messageID = typeof item.message.id === 'string' ? item.message.id : typeof item.uuid === 'string' ? item.uuid : '', request = typeof item.requestId === 'string' ? item.requestId : '';
  const timestamp = Date.parse(item.timestamp);
  if (!usage || (!messageID && !request) || messageID.length>256 || request.length>256 || !Number.isFinite(timestamp)) return null;
  return { key: messageID + ':' + request, model: typeof item.message.model==='string'?item.message.model.slice(0,256):'', usage, timestamp };
}
function normalizeQuota(snapshot) {
  if (!object(snapshot) || !object(snapshot.rate_limits)) return null;
  const captured = Number(snapshot.capturedAt); if (!Number.isFinite(captured) || captured <= 0) return null;
  const windows = [];
  for (const [key, name, minutes] of [['five_hour','5h',300], ['seven_day','7d',10080]]) {
    const item = snapshot.rate_limits[key]; if (!object(item)) continue;
    const used = item.used_percentage ?? item.used_percent ?? item.utilization;
    if (typeof used !== 'number' || !Number.isFinite(used) || used < 0) continue;
    const raw = item.resets_at ?? item.reset_at; const resetAt = typeof raw === 'number' ? raw > 1e11 ? raw : raw * 1000 : Date.parse(raw);
    windows.push({ name, usedPercent: used, windowMinutes: minutes, ...(Number.isFinite(resetAt) && resetAt > 0 ? { resetAt } : {}) });
  }
  return windows.length ? { provider: 'claude', windows, updatedAt: captured > 1e11 ? captured : captured * 1000, source: 'Claude Code status line' } : null;
}
async function lines(file, callback, { cancelled = () => false, maximumBytes = 256 * 1024 * 1024, startOffset = 0 } = {}) {
  const stat = await fs.lstat(file); if (!stat.isFile() || stat.isSymbolicLink()) return 0;
  const handle = await fs.open(file, 'r'); let bytes = 0, partial = Buffer.alloc(0), skipping = startOffset > 0;
  try {
    const chunk = Buffer.alloc(65536);
    while (!cancelled() && bytes < maximumBytes) {
      const { bytesRead } = await handle.read(chunk, 0, Math.min(chunk.length, maximumBytes - bytes), startOffset + bytes); if (!bytesRead) break; bytes += bytesRead;
      let start = 0;
      for (let i = 0; i < bytesRead; i++) if (chunk[i] === 10) {
        if (!skipping && partial.length + i - start <= MAX_LINE) callback(Buffer.concat([partial, chunk.subarray(start, i)]).toString('utf8'));
        partial = Buffer.alloc(0); skipping = false; start = i + 1;
      }
      if (!skipping) { if (partial.length + bytesRead - start > MAX_LINE) { skipping = true; partial = Buffer.alloc(0); } else partial = Buffer.concat([partial, chunk.subarray(start, bytesRead)]); }
    }
    if (!cancelled() && !skipping && partial.length) callback(partial.toString('utf8'));
  } finally { await handle.close(); }
  return bytes;
}
async function scanUsage(home, { now = Date.now(), cancelled = () => false, cache = new Map() } = {}) {
  const root = path.join(home, 'projects'), files = [], stack = [[root, 0]]; let incomplete = false;
  while (stack.length && files.length < 4096 && !cancelled()) {
    const [directory, depth] = stack.pop();
    const entries = await fs.readdir(directory, { withFileTypes: true }).catch(error => { if (error.code !== 'ENOENT') incomplete = true; return []; });
    for (const entry of entries) { if (entry.isSymbolicLink()) continue; const file = path.join(directory, entry.name); if (entry.isDirectory() && depth < 4) stack.push([file, depth + 1]); else if (entry.isFile() && entry.name.endsWith('.jsonl')) files.push(file); if (files.length >= 4096) { incomplete = true; break; } }
  }
  const records = new Map(), since = now - 180 * 86400000; let bytes = 0;
  const metadata=[];for(const file of files){if(cancelled())break;try{const stat=await fs.lstat(file);if(stat.isFile()&&!stat.isSymbolicLink())metadata.push({file,stat});}catch{incomplete=true;}}
  metadata.sort((a,b)=>b.stat.mtimeMs-a.stat.mtimeMs);
  const add=record=>{if(!record||record.timestamp<since||record.timestamp>now+86400000)return;const previous=records.get(record.key);if(!previous&&records.size>=262144){incomplete=true;return;}if(!previous||record.usage.total>=previous.usage.total)records.set(record.key,record);};
  const currentFiles=new Set(metadata.map(x=>x.file));for(const key of cache.keys())if(!currentFiles.has(key))cache.delete(key);
  for (const {file,stat} of metadata) {
    if (cancelled() || bytes >= 256 * 1024 * 1024) { incomplete = true; break; }
    try {
      const budget=256*1024*1024-bytes,fingerprint=[stat.dev,stat.ino,stat.size,stat.mtimeMs].join(':');
      const prior=cache.get(file);
      if(prior?.fingerprint===fingerprint&&stat.size<=budget){bytes+=stat.size;for(const record of prior.records)add(record);continue;}
      if(stat.size>budget)incomplete=true;
      const parsed=[];let cacheable=stat.size<=budget;
      bytes+=await lines(file,line=>{const record=usageRecord(parseLine(line));add(record);if(record){if(parsed.length<4096)parsed.push(record);else cacheable=false;}},{cancelled,maximumBytes:budget,startOffset:Math.max(0,stat.size-budget)});
      if(!cancelled()&&cacheable){cache.set(file,{fingerprint,records:parsed});while(cache.size>128)cache.delete(cache.keys().next().value);}else cache.delete(file);
    } catch { incomplete = true;cache.delete(file); }
  }
  const days = new Map();
  for (const record of records.values()) {
    const local=new Date(record.timestamp),date=[local.getFullYear(),String(local.getMonth()+1).padStart(2,'0'),String(local.getDate()).padStart(2,'0')].join('-'), usage = record.usage;
    const day = days.get(date) ?? { date, input: 0, output: 0, cached: 0, total: 0, cost: 0, models: [] };
    day.input += usage.input; day.output += usage.output; day.cached += usage.cached + usage.write5m + usage.write1h; day.total += usage.total;
    const estimated = cost(record.model, usage); day.cost = estimated === null || day.cost === null ? null : day.cost + estimated;
    if (!day.models.includes(record.model)) day.models.push(record.model); days.set(date, day);
  }
  return { provider: 'claude', days: [...days.values()].sort((a,b) => a.date.localeCompare(b.date)), updatedAt: now, source: 'Local Claude Code transcripts; estimated list-price cost, not account billing', incomplete };
}
async function transcriptPreview(home, file, { includeSidechain = false } = {}) {
  if (typeof file !== 'string' || file.length > 4096) return null;
  const root = await canonical(path.join(home, 'projects')), resolved = await canonical(file);
  if (!contained(root, resolved)) return null;
  const stat = await fs.lstat(file).catch(() => null); if (!stat?.isFile() || stat.isSymbolicLink()) return null;
  const handle = await fs.open(file, 'r'); const length = Math.min(stat.size, 1048576), buffer = Buffer.alloc(length);
  try { await handle.read(buffer, 0, length, stat.size - length); } finally { await handle.close(); }
  const text = buffer.toString('utf8').split('\n'); if (stat.size > length) text.shift();
  const items = text.map(parseLine).filter(item => item && (includeSidechain || item.isSidechain !== true));
  let start = 0, title, publicText = '', interrupted = false, model; const usages = new Map(), publicBlocks = new Map();
  for (let i = 0; i < items.length; i++) {
    const item = items[i]; if (item.type === 'custom-title' && typeof (item.customTitle ?? item.title) === 'string') title = (item.customTitle ?? item.title).slice(0,256);
    const content = item.message?.content;
    const prompt=typeof content==='string'?content:Array.isArray(content)?content.filter(x=>x.type==='text'&&typeof x.text==='string').map(x=>x.text).join('\n'):'';
    if (item.type === 'user' && !item.isMeta && !item.isCompactSummary && prompt.trim() && !/^(<|\[Request interrupted|Caveat:)/.test(prompt.trim())) { start = i; if(!title)title=prompt.trim().replace(/[\r\n]+/g,' ').slice(0,256); }
  }
  for (const item of items.slice(start)) {
    if (item.type === 'user' && typeof item.message?.content === 'string' && item.message.content.startsWith('[Request interrupted')) interrupted = true;
    if (item.type !== 'assistant') continue;
    if (typeof item.message?.model === 'string') model = item.message.model;
    const blocks=[];for (const part of Array.isArray(item.message?.content) ? item.message.content : []) if (part.type === 'text' && typeof part.text === 'string') blocks.push(part.text);if(blocks.length)publicBlocks.set(item.uuid??item.message?.id??String(publicBlocks.size),blocks.join('\n'));
    publicText=[...publicBlocks.values()].join('\n').slice(-65536);
    const record = usageRecord(item); if (record) usages.set(record.key, record.usage);
  }
  const total = { input: 0, output: 0, cached: 0, total: 0 }; for (const usage of usages.values()) { total.input += usage.input; total.output += usage.output; total.cached += usage.cached + usage.write5m + usage.write1h; total.total += usage.total; }
  return { ...(title ? { title } : {}), ...(model ? { model } : {}), publicText: publicText.trim(), interrupted, ...(usages.size ? { tokens: total } : {}) };
}
async function accountInfo(home, custom = false) {
  const file = path.join(custom ? home : path.dirname(home), '.claude.json');
  let data; try { data = await json(file, null, 4*1024*1024); } catch { return null; }
  const account = data?.oauthAccount; if (!object(account)) return null;
  const types = { claude_pro: 'Claude Pro', claude_max: 'Claude Max', claude_team: 'Claude Team', claude_enterprise: 'Claude Enterprise' };
  let plan = types[account.organizationType]; const tier = account.userRateLimitTier ?? account.organizationRateLimitTier;
  if (plan === 'Claude Max' && typeof tier === 'string') plan += tier.includes('20x') ? ' 20x' : tier.includes('5x') ? ' 5x' : '';
  return plan ? { plan } : null; // Do not retain OAuth/account identifiers or secrets.
}
module.exports = { tokens, rates, cost, parseLine, usageRecord, normalizeQuota, scanUsage, transcriptPreview, accountInfo, lines };
