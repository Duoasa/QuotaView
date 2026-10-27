import { call } from "./bridge.js";
const wrap = (s) =>
  s && {
    ...s,
    isFile: () => s.kind === "file",
    isDirectory: () => s.kind === "directory",
    isSymbolicLink: () => !!s.link,
  };
export const constants = { O_RDONLY: 0, O_NOFOLLOW: 0x20000, F_OK: 0, X_OK: 1 };
export const existsSync = (p) => call("fs.exists", String(p));
export const statSync = (p) => wrap(call("fs.stat", String(p))),
  lstatSync = statSync;
export const realpathSync = (p) => call("fs.realpath", String(p));
export const readFileSync = (p, opt) => {
  const b = Buffer.from(call("fs.read", String(p)), "base64");
  const enc = typeof opt === "string" ? opt : opt?.encoding;
  return enc ? b.toString(enc) : b;
};
export const writeFileSync = (p, data, opt) =>
  call(
    "fs.write",
    String(p),
    Buffer.from(data).toString("base64"),
    typeof opt === "object" ? opt : {},
  );
export const mkdirSync = (p, opt) => call("fs.mkdir", String(p), opt || {});
export const mkdtempSync = (p) => call("fs.mkdtemp", String(p));
export const renameSync = (a, b) => call("fs.rename", String(a), String(b));
export const unlinkSync = (p) => call("fs.unlink", String(p));
export const copyFileSync = (a, b) => call("fs.copy", String(a), String(b));
export const readdirSync = (p, opt) => {
  const rows = call("fs.readdir", String(p));
  return opt?.withFileTypes ? rows.map(wrap) : rows.map((x) => x.name);
};
export const promises = {};
for (const [name, fn] of Object.entries({
  stat: statSync,
  lstat: lstatSync,
  realpath: realpathSync,
  readFile: readFileSync,
  writeFile: writeFileSync,
  mkdir: mkdirSync,
  mkdtemp: mkdtempSync,
  rename: renameSync,
  unlink: unlinkSync,
  copyFile: copyFileSync,
  readdir: readdirSync,
  access: (p) => {
    statSync(p);
  },
}))
  promises[name] = async (...args) => fn(...args);
promises.opendir = async (p) => {
  const id = call("fs.opendir", String(p));
  return {
    read: async () => wrap(call("fs.dirnext", id)),
    close: async () => call("fs.dirclose", id),
  };
};
promises.open = async (p, flags) => {
  const id = call("fs.open", String(p), flags);
  return {
    stat: async () => wrap(call("fs.fstat", id)),
    read: async (buffer, offset, length, position) => {
      const b = Buffer.from(call("fs.fread", id, length, position), "base64");
      buffer.set(b, offset);
      return { bytesRead: b.length, buffer };
    },
    readFile: async () =>
      Buffer.from(call("fs.fread", id, 4194305, null), "base64"),
    writeFile: async (data) =>
      call("fs.fwrite", id, Buffer.from(data).toString("base64")),
    sync: async () => call("fs.fsync", id),
    close: async () => call("fs.close", id),
  };
};
export default {
  constants,
  promises,
  existsSync,
  statSync,
  lstatSync,
  realpathSync,
  readFileSync,
  writeFileSync,
  mkdirSync,
  mkdtempSync,
  renameSync,
  unlinkSync,
  copyFileSync,
  readdirSync,
};
