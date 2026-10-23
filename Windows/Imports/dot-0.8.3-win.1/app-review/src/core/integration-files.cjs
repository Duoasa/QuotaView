'use strict';
// Integration edits are revision-checked, backed up, and restricted to owned entries.
const fs = require('node:fs/promises');
const path = require('node:path');
const crypto = require('node:crypto');
const { TextDecoder } = require('node:util');
const LIMIT = 4 * 1024 * 1024;
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
async function read(file, limit = LIMIT) {
  let handle;
  try {
    const info = await fs.lstat(file);
    if (!info.isFile() || info.isSymbolicLink() || info.size > limit) throw new Error('Unsafe or oversized configuration: ' + file);
    handle = await fs.open(file, require('node:fs').constants.O_RDONLY | (require('node:fs').constants.O_NOFOLLOW || 0));
    const actual = await handle.stat();
    if (!actual.isFile() || actual.size > limit) throw new Error('Configuration changed while reading');
    const data = await handle.readFile();
    if (data.length > limit) throw new Error('Configuration exceeds size limit');
    return data;
  } catch (error) { if (error.code === 'ENOENT') return null; throw error; }
  finally { await handle?.close(); }
}
function decode(data) { return data === null ? '' : new TextDecoder('utf-8', { fatal: true }).decode(data); }
async function json(file, fallback = null, limit = LIMIT) { const data = await read(file, limit); return data === null ? fallback : JSON.parse(decode(data)); }
async function atomic(file, data, { expected, backup = false, privateFile = true } = {}) {
  data = Buffer.isBuffer(data) ? data : Buffer.from(data);
  await fs.mkdir(path.dirname(file), { recursive: true, mode: 0o700 });
  const before = await read(file);
  if (expected !== undefined && !(expected === null && before === null) && !(expected && before && before.equals(expected))) throw new Error('Configuration changed; retry without overwriting another editor');
  if (before?.equals(data)) return;
  let mode = privateFile ? 0o600 : (await fs.stat(file).catch(() => null))?.mode & 0o777;
  if (!mode) mode = 0o600;
  if (backup && before) {
    const backupFile = file + '.quotaview-' + hash(before).slice(0, 12) + '.backup';
    try { await fs.writeFile(backupFile, before, { flag: 'wx', mode: 0o600 }); }
    catch (error) { if (error.code !== 'EEXIST') throw error; }
  }
  const temporary = path.join(path.dirname(file), '.quotaview-' + crypto.randomUUID() + '.tmp');
  try {
    const handle = await fs.open(temporary, 'wx', mode);
    try { await handle.writeFile(data); await handle.sync(); } finally { await handle.close(); }
    if (expected !== undefined) {
      const current = await read(file);
      if (!(expected === null && current === null) && !(expected && current && current.equals(expected))) throw new Error('Configuration changed; retry without overwriting another editor');
    }
    await fs.rename(temporary, file);
  } finally { await fs.unlink(temporary).catch(() => {}); }
}
async function withLock(directory, operation) {
  await fs.mkdir(directory, { recursive: true, mode: 0o700 });
  const file = path.join(directory, 'install.lock');
  let handle;
  try { handle = await fs.open(file, 'wx', 0o600); }
  catch (error) {
    if (error.code !== 'EEXIST') throw error;
    // Recover only a positively dead owner, never steal a live or unparseable lock.
    const previous = await read(file, 4096); let owner; try { owner=JSON.parse(decode(previous)); } catch {}
    let dead=false;if(Number.isSafeInteger(owner?.pid)&&owner.pid>0){try{process.kill(owner.pid,0);}catch(cause){dead=cause.code==='ESRCH';}}
    if(!dead)throw new Error('Integration configuration is locked by another operation. Retry after it finishes.');
    const current=await read(file,4096);if(!previous||!current?.equals(previous))throw new Error('Integration lock changed; retry');
    await fs.unlink(file);handle=await fs.open(file,'wx',0o600);
  }
  try { await handle.writeFile(JSON.stringify({ pid: process.pid, createdAt: Date.now() })); return await operation(); }
  finally { await handle.close(); await fs.unlink(file).catch(() => {}); }
}
function removeBlock(text, marker) {
  const begin = '# >>> ' + marker + ' >>>', end = '# <<< ' + marker + ' <<<';
  const lines = text.split(/(?<=\n)/), result = []; let inBlock = false;
  for (const line of lines) {
    const stripped = line.replace(/\r?\n$/, '');
    if (stripped === begin) { if (inBlock) throw new Error('Malformed QuotaView marker block'); inBlock = true; continue; }
    if (stripped === end) { if (!inBlock) throw new Error('Orphaned QuotaView marker block'); inBlock = false; continue; }
    if (!inBlock) result.push(line);
  }
  if (inBlock) throw new Error('Unclosed QuotaView marker block');
  return result.join('');
}
function appendBlock(text, marker, body) { return text + (text && !text.endsWith('\n') ? '\n' : '') + '# >>> ' + marker + ' >>>\n' + body + '\n# <<< ' + marker + ' <<<\n'; }
async function canonical(file) { return fs.realpath(file).catch(() => path.resolve(file)); }
function contained(root, file) { const relative = path.relative(root, file); return relative !== '..' && !relative.startsWith('..' + path.sep) && !path.isAbsolute(relative); }
module.exports = { read, decode, json, atomic, withLock, hash, object, removeBlock, appendBlock, canonical, contained };
