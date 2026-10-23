import { EventEmitter } from "events";
import { call, receive, receivers } from "./bridge.js";
let serial = 0;
export class Socket extends EventEmitter {
  constructor(id) {
    super();
    this.id = id || "socket-" + ++serial;
    this.destroyed = false;
    this.writable = true;
    this.queue = Buffer.alloc(0);
    this.encoding = null;
    receive(this.id, (e) => this.native(e));
  }
  native(e) {
    if (e.type === "data") {
      const b = Buffer.from(e.data, "base64");
      this.touch();
      if (this.listenerCount("data"))
        this.emit("data", this.encoding ? b.toString(this.encoding) : b);
      else this.queue = Buffer.concat([this.queue, b]);
      this.emit("readable");
    } else if (e.type === "error") {
      this.emit("error", Object.assign(new Error(e.error), { code: e.code }));
    } else {
      if (e.type === "close") {
        this.destroyed = true;
        this.writable = false;
        clearTimeout(this.timer);
        receivers.delete(this.id);
      }
      this.emit(e.type, e.value);
    }
  }
  setEncoding(enc) {
    this.encoding = enc;
    return this;
  }
  on(name, fn) {
    super.on(name, fn);
    if (name === "data" && this.queue?.length)
      queueMicrotask(() => {
        const b = this.queue;
        this.queue = Buffer.alloc(0);
        if (b.length)
          this.emit("data", this.encoding ? b.toString(this.encoding) : b);
      });
    return this;
  }
  write(data, encoding, callback) {
    if (this.destroyed) return false;
    call(
      "socket.write",
      this.id,
      Buffer.from(
        data,
        typeof encoding === "string" ? encoding : undefined,
      ).toString("base64"),
    );
    this.touch();
    if (typeof encoding === "function") encoding();
    callback?.();
    return true;
  }
  read(count) {
    if (this.queue.length < count) return null;
    const b = this.queue.subarray(0, count);
    this.queue = this.queue.subarray(count);
    return b;
  }
  end(data) {
    if (data !== undefined) this.write(data);
    call("socket.end", this.id);
    this.writable = false;
    return this;
  }
  destroy() {
    if (!this.destroyed) {
      this.destroyed = true;
      this.writable = false;
      clearTimeout(this.timer);
      call("socket.close", this.id);
    }
    return this;
  }
  setTimeout(ms, fn) {
    this.timeout = ms;
    if (fn) this.once("timeout", fn);
    this.touch();
    return this;
  }
  touch() {
    clearTimeout(this.timer);
    if (this.timeout)
      this.timer = setTimeout(() => this.emit("timeout"), this.timeout);
  }
  pipe(other) {
    this.on("data", (d) => other.write(d));
    this.on("end", () => other.end());
    return other;
  }
  resume() {
    return this;
  }
  pause() {
    return this;
  }
  unref() {
    return this;
  }
  setNoDelay() {
    return this;
  }
}
export class Server extends EventEmitter {
  constructor(listener) {
    super();
    this.id = "server-" + ++serial;
    this.listening = false;
    if (listener) this.on("connection", listener);
    receive(this.id, (e) => {
      if (e.type === "connection") {
        const s = new Socket(e.socket);
        s.remoteAddress = e.remoteAddress;
        this.emit("connection", s);
        call("socket.resume", s.id);
      } else if (e.type === "error") this.emit("error", new Error(e.error));
    });
  }
  listen(port, host, fn) {
    if (typeof host === "function") {
      fn = host;
      host = "127.0.0.1";
    }
    try {
      this.port = call("server.listen", this.id, port, host || "127.0.0.1");
      this.listening = true;
      queueMicrotask(() => {
        this.emit("listening");
        fn?.();
      });
    } catch (e) {
      queueMicrotask(() => this.emit("error", e));
    }
    return this;
  }
  address() {
    return { address: "127.0.0.1", family: "IPv4", port: this.port };
  }
  close(fn) {
    call("server.close", this.id);
    this.listening = false;
    receivers.delete(this.id);
    queueMicrotask(() => {
      this.emit("close");
      fn?.();
    });
    return this;
  }
  unref() {
    return this;
  }
}
export function connect(options, fn) {
  const socket = new Socket();
  if (fn) socket.once("connect", fn);
  call(
    "socket.connect",
    socket.id,
    options.host || "127.0.0.1",
    options.port,
    !!options.secure,
  );
  return socket;
}
export const net = {
  connectCodexDesktop: () => {
    const socket = new Socket();
    call("socket.codexDesktop", socket.id);
    return socket;
  },
  createServer: (options, listener) =>
    new Server(typeof options === "function" ? options : listener),
  connect,
  createConnection: connect,
  isIP: (s) => (s.includes(":") ? 6 : /^\d+\.\d+\.\d+\.\d+$/.test(s) ? 4 : 0),
};
export const tls = {
  connect: (options) => connect({ ...options, secure: true }),
};
export const http = {
  createServer: (listener) => {
    const server = new Server();
    server.on("connection", (s) => {
      let bytes = Buffer.alloc(0);
      const parse = (d) => {
        bytes = Buffer.concat([bytes, d]);
        if (bytes.length > 32768) {
          s.destroy();
          return;
        }
        const end = bytes.indexOf("\r\n\r\n");
        if (end < 0) return;
        s.removeListener("data", parse);
        const rows = bytes.subarray(0, end).toString("latin1").split("\r\n"),
          first = rows.shift().split(" "),
          headers = {};
        for (const row of rows) {
          const n = row.indexOf(":");
          if (n > 0)
            headers[row.slice(0, n).toLowerCase()] = row.slice(n + 1).trim();
        }
        const req = { method: first[0], url: first[1], headers };
        if (req.method === "CONNECT")
          server.emit("connect", req, s, bytes.subarray(end + 4));
        else {
          let status = 405;
          listener(req, {
            writeHead: (n) => (status = n),
            end: () =>
              s.end(
                `HTTP/1.1 ${status} Method Not Allowed\r\nConnection: close\r\n\r\n`,
              ),
          });
        }
      };
      s.on("data", parse);
    });
    return server;
  },
};
class Input extends EventEmitter {
  constructor(id) {
    super();
    this.id = id;
    this.writable = true;
  }
  write(data, cb) {
    call("process.write", this.id, Buffer.from(data).toString("base64"));
    cb?.();
    return true;
  }
  end(data) {
    if (data !== undefined) this.write(data);
    call("process.end", this.id);
    this.writable = false;
  }
}
class Output extends EventEmitter {
  setEncoding(e) {
    this.encoding = e;
    return this;
  }
  data(b) {
    this.emit("data", this.encoding ? b.toString(this.encoding) : b);
  }
}
export function spawn(executable, args = [], options = {}) {
  const child = new EventEmitter();
  child.id = "process-" + ++serial;
  child.stdin = new Input(child.id);
  child.stdout = new Output();
  child.stderr = new Output();
  child.kill = () => {
    call("process.kill", child.id);
    child.killed = true;
  };
  child.unref = () => child;
  receive(child.id, (e) => {
    if (e.type === "stdout" || e.type === "stderr")
      child[e.type].data(Buffer.from(e.data, "base64"));
    else if (e.type === "error")
      child.emit("error", Object.assign(new Error(e.error), { code: e.code }));
    else if (e.type === "close") {
      child.stdin.writable = false;
      child.exitCode = e.value;
      child.emit("exit", e.value);
      child.emit("close", e.value);
      receivers.delete(child.id);
    }
  });
  try {
    child.pid = call("process.spawn", child.id, executable, args, options);
  } catch (e) {
    queueMicrotask(() => child.emit("error", e));
  }
  return child;
}
export function execFile(exe, args, options, cb) {
  if (typeof options === "function") {
    cb = options;
    options = {};
  }
  const child = spawn(exe, args, options);
  let out = "",
    err = "",
    done = false;
  const finish = (error) => {
    if (done) return;
    done = true;
    clearTimeout(timer);
    cb(error, out, err);
  };
  const timer = options?.timeout
    ? setTimeout(() => {
        child.kill();
        finish(Error("Process timeout"));
      }, options.timeout)
    : null;
  child.stdout.setEncoding("utf8").on("data", (x) => {
    out += x;
    if (out.length > (options?.maxBuffer || 1048576)) {
      child.kill();
      finish(Error("Process output too large"));
    }
  });
  child.stderr.setEncoding("utf8").on("data", (x) => {
    err = (err + x).slice(-65536);
  });
  child.once("error", finish);
  child.once("close", (code) =>
    finish(code ? Error("Process exited " + code) : null),
  );
  return child;
}
export const child_process = { spawn, execFile };
