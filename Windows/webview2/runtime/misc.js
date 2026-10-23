import { call, bootstrap } from "./bridge.js";
export const os = {
  homedir: () => bootstrap.home,
  tmpdir: () => bootstrap.temp,
  release: () => bootstrap.osRelease,
  platform: () => "win32",
  arch: () => "x64",
  EOL: "\r\n",
};
export const crypto = {
  randomUUID: () => globalThis.crypto.randomUUID(),
  randomBytes: (n) =>
    Buffer.from(globalThis.crypto.getRandomValues(new Uint8Array(n))),
  timingSafeEqual: (a, b) => {
    if (a.length !== b.length) throw Error("Length mismatch");
    let x = 0;
    for (let i = 0; i < a.length; i++) x |= a[i] ^ b[i];
    return x === 0;
  },
  createHash: (algorithm) => {
    const parts = [];
    const h = {
      update: (d) => {
        parts.push(Buffer.from(d));
        return h;
      },
      digest: (encoding) => {
        const b = Buffer.from(
          call("hash", algorithm, Buffer.concat(parts).toString("base64")),
          "base64",
        );
        return encoding ? b.toString(encoding) : b;
      },
    };
    return h;
  },
};
export const url = {
  fileURLToPath: (u) =>
    decodeURIComponent(new URL(u).pathname)
      .replace(/^\/([a-z]:)/i, "$1")
      .replace(/\//g, "\\"),
  pathToFileURL: (p) =>
    new URL(
      "file:///" +
        p
          .replace(/\\/g, "/")
          .split("/")
          .map((x, i) => (i === 0 ? x : encodeURIComponent(x)))
          .join("/"),
    ),
};
export const util = {
  TextDecoder: globalThis.TextDecoder,
  TextEncoder: globalThis.TextEncoder,
  promisify:
    (fn) =>
    (...args) =>
      new Promise((resolve, reject) =>
        fn(...args, (err, value) => (err ? reject(err) : resolve(value))),
      ),
};
