"use strict";
var __getOwnPropNames = Object.getOwnPropertyNames;
var __commonJS = (cb, mod) => function __require() {
  try {
    return mod || (0, cb[__getOwnPropNames(cb)[0]])((mod = { exports: {} }).exports, mod), mod.exports;
  } catch (e) {
    throw mod = 0, e;
  }
};

// src/core/integration-files.cjs
var require_integration_files = __commonJS({
  "src/core/integration-files.cjs"(exports2, module2) {
    "use strict";
    var fs2 = require("node:fs/promises");
    var path = require("node:path");
    var crypto = require("node:crypto");
    var { TextDecoder } = require("node:util");
    var LIMIT = 4 * 1024 * 1024;
    var hash = (value) => crypto.createHash("sha256").update(value).digest("hex");
    var object = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
    async function read(file, limit = LIMIT) {
      let handle;
      try {
        const info = await fs2.lstat(file);
        if (!info.isFile() || info.isSymbolicLink() || info.size > limit) throw new Error("Unsafe or oversized configuration: " + file);
        handle = await fs2.open(file, require("node:fs").constants.O_RDONLY | (require("node:fs").constants.O_NOFOLLOW || 0));
        const actual = await handle.stat();
        if (!actual.isFile() || actual.size > limit) throw new Error("Configuration changed while reading");
        const data = await handle.readFile();
        if (data.length > limit) throw new Error("Configuration exceeds size limit");
        return data;
      } catch (error) {
        if (error.code === "ENOENT") return null;
        throw error;
      } finally {
        await handle?.close();
      }
    }
    function decode(data) {
      return data === null ? "" : new TextDecoder("utf-8", { fatal: true }).decode(data);
    }
    async function json(file, fallback = null, limit = LIMIT) {
      const data = await read(file, limit);
      return data === null ? fallback : JSON.parse(decode(data));
    }
    async function atomic(file, data, { expected, backup = false, privateFile = true } = {}) {
      data = Buffer.isBuffer(data) ? data : Buffer.from(data);
      await fs2.mkdir(path.dirname(file), { recursive: true, mode: 448 });
      const before = await read(file);
      if (expected !== void 0 && !(expected === null && before === null) && !(expected && before && before.equals(expected))) throw new Error("Configuration changed; retry without overwriting another editor");
      if (before?.equals(data)) return;
      let mode = privateFile ? 384 : (await fs2.stat(file).catch(() => null))?.mode & 511;
      if (!mode) mode = 384;
      if (backup && before) {
        const backupFile = file + ".quotaview-" + hash(before).slice(0, 12) + ".backup";
        try {
          await fs2.writeFile(backupFile, before, { flag: "wx", mode: 384 });
        } catch (error) {
          if (error.code !== "EEXIST") throw error;
        }
      }
      const temporary = path.join(path.dirname(file), ".quotaview-" + crypto.randomUUID() + ".tmp");
      try {
        const handle = await fs2.open(temporary, "wx", mode);
        try {
          await handle.writeFile(data);
          await handle.sync();
        } finally {
          await handle.close();
        }
        if (expected !== void 0) {
          const current = await read(file);
          if (!(expected === null && current === null) && !(expected && current && current.equals(expected))) throw new Error("Configuration changed; retry without overwriting another editor");
        }
        await fs2.rename(temporary, file);
      } finally {
        await fs2.unlink(temporary).catch(() => {
        });
      }
    }
    async function withLock(directory, operation) {
      await fs2.mkdir(directory, { recursive: true, mode: 448 });
      const file = path.join(directory, "install.lock");
      let handle;
      try {
        handle = await fs2.open(file, "wx", 384);
      } catch (error) {
        if (error.code !== "EEXIST") throw error;
        const previous = await read(file, 4096);
        let owner;
        try {
          owner = JSON.parse(decode(previous));
        } catch {
        }
        let dead = false;
        if (Number.isSafeInteger(owner?.pid) && owner.pid > 0) {
          try {
            process.kill(owner.pid, 0);
          } catch (cause) {
            dead = cause.code === "ESRCH";
          }
        }
        if (!dead) throw new Error("Integration configuration is locked by another operation. Retry after it finishes.");
        const current = await read(file, 4096);
        if (!previous || !current?.equals(previous)) throw new Error("Integration lock changed; retry");
        await fs2.unlink(file);
        handle = await fs2.open(file, "wx", 384);
      }
      try {
        await handle.writeFile(JSON.stringify({ pid: process.pid, createdAt: Date.now() }));
        return await operation();
      } finally {
        await handle.close();
        await fs2.unlink(file).catch(() => {
        });
      }
    }
    function removeBlock(text, marker) {
      const begin = "# >>> " + marker + " >>>", end = "# <<< " + marker + " <<<";
      const lines = text.split(/(?<=\n)/), result = [];
      let inBlock = false;
      for (const line of lines) {
        const stripped = line.replace(/\r?\n$/, "");
        if (stripped === begin) {
          if (inBlock) throw new Error("Malformed QuotaView marker block");
          inBlock = true;
          continue;
        }
        if (stripped === end) {
          if (!inBlock) throw new Error("Orphaned QuotaView marker block");
          inBlock = false;
          continue;
        }
        if (!inBlock) result.push(line);
      }
      if (inBlock) throw new Error("Unclosed QuotaView marker block");
      return result.join("");
    }
    function appendBlock(text, marker, body) {
      return text + (text && !text.endsWith("\n") ? "\n" : "") + "# >>> " + marker + " >>>\n" + body + "\n# <<< " + marker + " <<<\n";
    }
    async function canonical(file) {
      return fs2.realpath(file).catch(() => path.resolve(file));
    }
    function contained(root, file) {
      const relative = path.relative(root, file);
      return relative !== ".." && !relative.startsWith(".." + path.sep) && !path.isAbsolute(relative);
    }
    module2.exports = { read, decode, json, atomic, withLock, hash, object, removeBlock, appendBlock, canonical, contained };
  }
});

// src/core/hook.cjs
var require_hook = __commonJS({
  "src/core/hook.cjs"(exports2, module2) {
    "use strict";
    var fs2 = require("node:fs/promises");
    var net = require("node:net");
    var crypto = require("node:crypto");
    var { spawn } = require("node:child_process");
    var MAX_INPUT = 8 * 1024 * 1024;
    var MAX_WIRE = 1024 * 1024;
    var isObject = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
    var bounded = (value, limit = 4096) => typeof value === "string" ? Buffer.from(value).subarray(0, limit).toString("utf8").replace(/\ufffd$/, "") : void 0;
    async function readRoute(file) {
      const stat = await fs2.lstat(file);
      if (!stat.isFile() || stat.isSymbolicLink() || stat.size > 65536 || stat.size < 1) throw new Error("Invalid route");
      if (process.platform !== "win32" && (stat.mode & 63 || stat.uid !== process.getuid())) throw new Error("Non-private route");
      const route = JSON.parse((await require_integration_files().read(file, 65536)).toString("utf8"));
      if (route.version !== 1 || route.host !== "127.0.0.1" || !Number.isInteger(route.port) || route.port < 1 || route.port > 65535 || !/^[a-f0-9]{64}$/.test(route.authenticationToken) || !["claude", "dsh", "kimi"].includes(route.provider)) throw new Error("Invalid route");
      return route;
    }
    function readInput(stream = process.stdin, max = MAX_INPUT) {
      return new Promise((resolve, reject) => {
        let length = 0;
        const chunks = [];
        const finish = (value) => {
          cleanup();
          resolve(value);
        };
        const fail = (error) => {
          cleanup();
          reject(error);
        };
        const cleanup = () => {
          clearTimeout(timer);
          stream.removeListener("data", data);
          stream.removeListener("end", end);
          stream.removeListener("error", fail);
        };
        const data = (chunk) => {
          length += chunk.length;
          if (length > max) {
            stream.pause();
            fail(new Error("Input too large"));
          } else chunks.push(chunk);
        };
        const end = () => finish(Buffer.concat(chunks));
        const timer = setTimeout(() => fail(new Error("Input timed out")), 5e3);
        stream.on("data", data);
        stream.once("end", end);
        stream.once("error", fail);
        stream.resume();
      });
    }
    function selectPayload(input, provider) {
      if (!isObject(input) || typeof input.hook_event_name !== "string" || typeof input.session_id !== "string" || !input.session_id || input.session_id.length > 256) return null;
      const keys = ["hook_event_name", "session_id", "turn_id", "prompt_id", "tool_name", "tool_use_id", "tool_call_id", "model", "session_title", "agent_id", "agent_type", "source", "reason", "stop_reason"];
      const result = {};
      for (const key of keys) if (typeof input[key] === "string") result[key] = bounded(input[key], 256);
      if (provider === "claude") {
        for (const key of ["transcript_path", "agent_transcript_path", "cwd", "notification_type", "title", "message", "last_assistant_message", "error"]) if (typeof input[key] === "string") result[key] = bounded(input[key], key === "last_assistant_message" ? 65536 : 4096);
        for (const key of ["stop_hook_active", "is_interrupt"]) if (typeof input[key] === "boolean") result[key] = input[key];
        for (const [key, limit] of [["tool_input", 262144], ["permission_suggestions", 65536]]) {
          if (input[key] !== void 0) {
            const serialized = JSON.stringify(input[key]);
            result[key] = Buffer.byteLength(serialized) <= limit ? input[key] : { _quotaViewTruncated: true };
          }
        }
        if (typeof input.effort === "string") result.effort = bounded(input.effort, 64);
        else if (isObject(input.effort)) result.effort = bounded(input.effort.level, 64);
      }
      return result;
    }
    function send(route, payload, { kind = "hook", awaitDecision = false, eventID = crypto.randomUUID() } = {}) {
      if (route.enabled === false) return Promise.resolve(null);
      return new Promise((resolve) => {
        let finished = false, buffer = "", pending = false;
        const decoder = new (require("node:string_decoder")).StringDecoder("utf8");
        const socket = net.createConnection({ host: "127.0.0.1", port: route.port });
        const finish = (value) => {
          if (finished) return;
          finished = true;
          clearTimeout(timer);
          socket.destroy();
          resolve(value);
        };
        let timer = setTimeout(() => finish(null), route.provider === "kimi" ? 750 : 1500);
        const envelope = JSON.stringify({ authenticationToken: route.authenticationToken, eventID, kind, awaitDecision, payload });
        if (Buffer.byteLength(envelope) > MAX_WIRE) {
          finish(null);
          return;
        }
        socket.on("connect", () => socket.write(envelope + "\n"));
        socket.on("error", () => finish(null));
        socket.on("end", () => finish(null));
        socket.on("close", () => finish(null));
        socket.on("data", (data) => {
          buffer += decoder.write(data);
          if (Buffer.byteLength(buffer) > MAX_WIRE) {
            finish(null);
            return;
          }
          let index;
          while ((index = buffer.indexOf("\n")) >= 0) {
            const line = buffer.slice(0, index);
            buffer = buffer.slice(index + 1);
            let reply;
            try {
              reply = JSON.parse(line);
            } catch {
              finish(null);
              return;
            }
            if (reply.eventID !== eventID) {
              finish(null);
              return;
            }
            if (!pending) {
              if (reply.accepted !== true || !awaitDecision || reply.pending !== true) {
                finish(null);
                return;
              }
              pending = true;
              clearTimeout(timer);
              timer = setTimeout(() => finish(null), Math.min(36e5, Math.max(50, Number(route.decisionTimeoutMs) || 354e4)));
            } else {
              finish(isObject(reply.decision) ? reply.decision : null);
              return;
            }
          }
        });
      });
    }
    function decisionOutput(decision) {
      if (!isObject(decision) || !["allow", "deny"].includes(decision.behavior)) return "";
      const result = { behavior: decision.behavior };
      if (decision.behavior === "allow") {
        if (isObject(decision.updatedInput)) result.updatedInput = decision.updatedInput;
        if (Array.isArray(decision.updatedPermissions)) result.updatedPermissions = decision.updatedPermissions;
      } else {
        if (typeof decision.message === "string") result.message = bounded(decision.message, 4096);
        if (decision.interrupt === true) result.interrupt = true;
      }
      const text = JSON.stringify({ hookSpecificOutput: { hookEventName: "PermissionRequest", decision: result } });
      return Buffer.byteLength(text) <= MAX_WIRE ? text : "";
    }
    function statusPayload(input) {
      const result = { capturedAt: Date.now() / 1e3 };
      for (const key of ["session_id", "version", "rate_limits", "cost", "model", "context_window", "exceeds_200k_tokens"]) {
        if (input[key] !== void 0 && Buffer.byteLength(JSON.stringify(input[key])) <= 16384) result[key] = input[key];
      }
      return result;
    }
    async function forwardStatusLine(route, input) {
      const original = route.originalStatusLine;
      if (!original || typeof original.command !== "string" || !original.command.trim() || original.command.length > 16384) return Promise.resolve(null);
      let bash;
      if (process.platform === "win32" && original.shell !== "powershell") {
        for (const candidate of [process.env.CLAUDE_CODE_GIT_BASH_PATH, process.env.ProgramFiles && require("node:path").join(process.env.ProgramFiles, "Git", "bin", "bash.exe"), process.env["ProgramFiles(x86)"] && require("node:path").join(process.env["ProgramFiles(x86)"], "Git", "bin", "bash.exe")].filter(Boolean)) {
          if ((await fs2.stat(candidate).catch(() => null))?.isFile()) {
            bash = candidate;
            break;
          }
        }
      }
      return new Promise((resolve) => {
        let command, args;
        if (Array.isArray(original.args) && original.args.length <= 256 && original.args.every((x) => typeof x === "string" && x.length <= 16384)) {
          command = original.command;
          args = original.args;
        } else if (process.platform === "win32" && original.shell !== "bash" && !bash) {
          command = "powershell.exe";
          args = ["-NoLogo", "-NoProfile", "-NonInteractive", "-Command", original.command];
        } else {
          command = process.platform === "win32" ? bash || "bash.exe" : "/bin/sh";
          args = ["-c", original.command];
        }
        let child;
        try {
          child = spawn(command, args, { windowsHide: true, stdio: ["pipe", "pipe", "ignore"] });
        } catch {
          resolve(null);
          return;
        }
        let settled = false, length = 0;
        const chunks = [];
        const done = (value) => {
          if (settled) return;
          settled = true;
          clearTimeout(timer);
          resolve(value);
        };
        const timer = setTimeout(() => {
          child.kill();
          done(null);
        }, 5e3);
        child.on("error", () => done(null));
        child.on("close", (code) => done(code === 0 ? Buffer.concat(chunks).toString("utf8") : null));
        child.stdout.on("data", (chunk) => {
          length += chunk.length;
          if (length > 262144) {
            child.kill();
            done(null);
          } else chunks.push(chunk);
        });
        child.stdin.on("error", () => {
        });
        child.stdin.end(input);
      });
    }
    function compactStatus(input) {
      const parts = [];
      if (typeof input.model?.display_name === "string") parts.push(bounded(input.model.display_name, 256));
      for (const [key, title] of [["five_hour", "5h"], ["seven_day", "7d"]]) {
        const n = input.rate_limits?.[key]?.used_percentage;
        if (typeof n === "number" && Number.isFinite(n)) parts.push(title + " " + Math.round(n) + "%");
      }
      return parts.join(" \xB7 ");
    }
    async function main2(args = process.argv.slice(2), { input = process.stdin, output = process.stdout } = {}) {
      try {
        const value = (flag) => {
          const i = args.indexOf(flag);
          return i < 0 ? void 0 : args[i + 1];
        };
        const route = await readRoute(value("--configuration"));
        const bytes = await readInput(input, value("--mode") === "statusline" ? 2097152 : MAX_INPUT);
        const payload = JSON.parse(bytes.toString("utf8"));
        if (!isObject(payload)) return;
        if (value("--mode") === "statusline") {
          if (route.provider !== "claude") return;
          await send(route, statusPayload(payload), { kind: "statusLine" });
          const text = await forwardStatusLine(route, bytes);
          output.write(text ?? compactStatus(payload));
          return;
        }
        const safe = selectPayload(payload, route.provider);
        if (!safe) return;
        const decision = await send(route, safe, { awaitDecision: route.provider === "claude" && route.interactiveApprovals !== false && safe.hook_event_name === "PermissionRequest" });
        if (route.provider === "claude") {
          const text = decisionOutput(decision);
          if (text) output.write(text);
        }
      } catch {
      }
    }
    if (require.main === module2) main2().then(() => {
      process.exitCode = 0;
    });
    module2.exports = { main: main2, readRoute, readInput, selectPayload, send, decisionOutput, statusPayload, compactStatus, forwardStatusLine };
  }
});

// src/core/codex-hook.cjs
var require_codex_hook = __commonJS({
  "src/core/codex-hook.cjs"(exports2, module2) {
    "use strict";
    var fs2 = require("node:fs/promises");
    var net = require("node:net");
    var crypto = require("node:crypto");
    var EVENTS = /* @__PURE__ */ new Set(["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "PostToolUse", "PreCompact", "PostCompact", "SubagentStart", "SubagentStop", "Interrupt", "Stop"]);
    var object = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
    var id = (value) => typeof value === "string" && value.length > 0 && Buffer.byteLength(value) <= 1024 && !/[\x00-\x1f\x7f]/.test(value) ? value : null;
    function selectPayload(input) {
      if (!object(input) || !EVENTS.has(input.hook_event_name) || !id(input.session_id)) return null;
      const output = { event: input.hook_event_name, sessionId: input.session_id };
      if (input.turn_id != null) {
        if (!id(input.turn_id)) return null;
        output.turnId = input.turn_id;
      }
      return output;
    }
    async function readRoute(file) {
      const stat = await fs2.lstat(file);
      if (!stat.isFile() || stat.isSymbolicLink() || stat.size < 1 || stat.size > 16384) throw new Error("invalid_hook_route");
      if (process.platform !== "win32" && ((stat.mode & 63) !== 0 || stat.uid !== process.getuid())) throw new Error("nonprivate_hook_route");
      const route = JSON.parse(await fs2.readFile(file, "utf8"));
      if (!object(route) || route.version !== 1 || route.provider !== "codex" || route.host !== "127.0.0.1" || !Number.isInteger(route.port) || route.port < 1 || route.port > 65535 || !/^[a-f0-9]{64}$/.test(route.authenticationToken) || typeof route.installationId !== "string") throw new Error("invalid_hook_route");
      return route;
    }
    function readInput(stream = process.stdin, limit = 1024 * 1024) {
      return new Promise((resolve, reject) => {
        const chunks = [];
        let length = 0;
        const cleanup = () => {
          clearTimeout(timer);
          stream.removeListener("data", data);
          stream.removeListener("end", end);
          stream.removeListener("error", fail);
        };
        const fail = (error) => {
          cleanup();
          reject(error);
        };
        const end = () => {
          cleanup();
          resolve(Buffer.concat(chunks));
        };
        const data = (chunk) => {
          length += chunk.length;
          if (length > limit) {
            stream.pause();
            fail(new Error("hook_input_too_large"));
          } else chunks.push(chunk);
        };
        const timer = setTimeout(() => fail(new Error("hook_input_timed_out")), 800);
        stream.on("data", data);
        stream.once("end", end);
        stream.once("error", fail);
        stream.resume();
      });
    }
    function send(route, payload, { timeout = 700, eventId = crypto.randomUUID() } = {}) {
      if (route.enabled !== true) return Promise.resolve(false);
      return new Promise((resolve) => {
        let settled = false, buffer = Buffer.alloc(0);
        const socket = net.createConnection({ host: "127.0.0.1", port: route.port });
        const finish = (value) => {
          if (settled) return;
          settled = true;
          clearTimeout(timer);
          socket.destroy();
          resolve(value);
        };
        const timer = setTimeout(() => finish(false), timeout);
        socket.on("error", () => finish(false));
        socket.on("end", () => finish(false));
        socket.on("close", () => finish(false));
        socket.on("connect", () => socket.write(JSON.stringify({ authenticationToken: route.authenticationToken, installationId: route.installationId, eventId, payload }) + "\n"));
        socket.on("data", (chunk) => {
          if (buffer.length + chunk.length > 4096) return finish(false);
          buffer = Buffer.concat([buffer, chunk]);
          const index = buffer.indexOf(10);
          if (index < 0) return;
          try {
            const ack = JSON.parse(buffer.subarray(0, index));
            finish(ack.eventId === eventId && ack.accepted === true);
          } catch {
            finish(false);
          }
        });
      });
    }
    async function main2(args = process.argv.slice(2), { input = process.stdin } = {}) {
      try {
        const index = args.indexOf("--configuration");
        if (index < 0 || typeof args[index + 1] !== "string") return;
        const route = await readRoute(args[index + 1]);
        if (!route.enabled) return;
        const data = await readInput(input);
        const payload = selectPayload(JSON.parse(data.toString("utf8")));
        if (payload) await send(route, payload);
      } catch {
      }
    }
    if (require.main === module2) main2().then(() => {
      process.exitCode = 0;
    });
    module2.exports = { EVENTS, selectPayload, readRoute, readInput, send, main: main2 };
  }
});

// scripts/helper-entry.cjs
var fs = require("node:fs");
var sea = require("node:sea");
var integrationHook = require_hook();
var codexHook = require_codex_hook();
async function main(args = process.argv.slice(1)) {
  if (args.includes("--helper-smoke-test")) {
    const report = {
      ok: true,
      sea: sea.isSea(),
      platform: process.platform,
      arch: process.arch,
      node: process.versions.node,
      entrypoints: ["--quotaview-hook", "--quotaview-codex-hook"],
      headless: true
    };
    const file = args.find((value) => value.startsWith("--helper-smoke-report="))?.slice("--helper-smoke-report=".length);
    if (file) fs.writeFileSync(file, JSON.stringify(report, null, 2));
    process.stdout.write(JSON.stringify(report) + "\n");
    return;
  }
  const codex = args.indexOf("--quotaview-codex-hook");
  const integration = args.indexOf("--quotaview-hook");
  if (codex >= 0 && integration < 0) await codexHook.main(args.slice(codex + 1));
  else if (integration >= 0 && codex < 0) await integrationHook.main(args.slice(integration + 1));
}
if (require.main === module || sea.isSea()) {
  main().then(() => {
    process.exitCode = 0;
  }, () => {
    process.exitCode = 0;
  });
}
module.exports = { main };
