import { Buffer } from "buffer";
globalThis.Buffer = Buffer;
export function call(method, ...args) {
  const r = JSON.parse(
    chrome.webview.hostObjects.sync.native.Request(
      JSON.stringify({ method, args }),
    ),
  );
  if (r.error) {
    const e = new Error(r.error);
    e.code = r.code;
    throw e;
  }
  return r.value;
}
let sequence = 0;
const pending = new Map();
export const receivers = new Map();
export function later(method, ...args) {
  const id = "request-" + ++sequence;
  return new Promise((resolve, reject) => {
    pending.set(id, { resolve, reject });
    try {
      call("async", id, method, args);
    } catch (e) {
      pending.delete(id);
      reject(e);
    }
  });
}
export function receive(id, fn) {
  receivers.set(id, fn);
  return () => receivers.delete(id);
}
export const bootstrap = call("bootstrap");
globalThis.process = {
  ...bootstrap.process,
  env: bootstrap.env,
  cwd: () => bootstrap.cwd,
  nextTick: (fn) => queueMicrotask(fn),
  kill: (pid, signal) => call("process.check", pid, signal),
  exit: (code) => call("app.exit", code),
  stdout: { write: (s) => call("log", String(s)) },
  stderr: { write: (s) => call("log", String(s)) },
};
globalThis.global = globalThis;
globalThis.setImmediate = (fn) => setTimeout(fn, 0);
globalThis.clearImmediate = clearTimeout;
// Existing business code uses Node timer handles, but all timers run in V8.
for (const name of ["setTimeout", "setInterval"]) {
  const start = globalThis[name].bind(globalThis);
  globalThis[name] = (...args) => {
    const id = start(...args);
    return {
      unref() {
        return this;
      },
      ref() {
        return this;
      },
      [Symbol.toPrimitive]() {
        return id;
      },
    };
  };
}
chrome.webview.addEventListener("message", (event) => {
  for (const e of event.data) {
    try {
      if (e.type === "result") {
        const p = pending.get(e.id);
        pending.delete(e.id);
        if (p)
          e.error
            ? p.reject(Object.assign(new Error(e.error), { code: e.code }))
            : p.resolve(e.value);
      } else receivers.get(e.id)?.(e);
    } catch (error) {
      console.error(error);
      call("log", String(error.stack || error));
    }
  }
});
for (const name of ["log", "warn", "error"]) {
  const original = console[name].bind(console);
  console[name] = (...a) => {
    original(...a);
    call("log", a.map((v) => v?.stack || String(v)).join(" "));
  };
}
window.addEventListener("error", (e) =>
  call("log", String(e.error?.stack || e.message)),
);
window.addEventListener("unhandledrejection", (e) =>
  call("log", String(e.reason?.stack || e.reason)),
);
