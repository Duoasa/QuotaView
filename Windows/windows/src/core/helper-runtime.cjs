'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
// Portable Electron extracts into a temporary folder. Hook configuration must
// point at an immutable, per-user headless runtime that survives that folder.
function materializeHelper(resourcesPath, dataDir) {
  const source = path.join(resourcesPath, 'helper', 'quotaview-hook.exe');
  const bytes = fs.readFileSync(source);
  if (bytes.length < 1024 || bytes[0] !== 0x4d || bytes[1] !== 0x5a) throw Error('Packaged hook runtime is missing or invalid.');
  const hash = crypto.createHash('sha256').update(bytes).digest('hex');
  const directory = path.join(dataDir, 'bin', hash.slice(0, 20));
  fs.mkdirSync(directory, { recursive: true });
  const target = path.join(directory, 'quotaview-hook.exe');
  if (!fs.existsSync(target) || crypto.createHash('sha256').update(fs.readFileSync(target)).digest('hex') !== hash) {
    const temporary = target + '.tmp-' + process.pid;
    fs.writeFileSync(temporary, bytes, { flag: 'wx' });
    try { fs.renameSync(temporary, target); } finally { try { fs.unlinkSync(temporary); } catch {} }
  }
  for (const name of ['LICENSE.node.txt', 'helper-manifest.json']) {
    const file = path.join(resourcesPath, 'helper', name);
    if (fs.existsSync(file)) fs.copyFileSync(file, path.join(directory, name));
  }
  return target;
}
module.exports = { materializeHelper };
