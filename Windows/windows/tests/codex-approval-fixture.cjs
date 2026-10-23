"use strict";
// Isolated Codex event producer: no model turn or shell command is executed.
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const { spawn } = require("node:child_process");
const { CodexService } = require("../src/core/codex.cjs");
exports.create = async function ({ root, executable }) {
  const home = path.join(root, "codex-home"),
    session = crypto.randomUUID(),
    turn = crypto.randomUUID();
  const directory = path.join(home, "sessions");
  fs.mkdirSync(directory, { recursive: true });
  const file = path.join(directory, "approval-fixture.jsonl");
  let rows = "";
  function append(type, payload) {
    rows += JSON.stringify({timestamp:new Date().toISOString(),type,payload}) + "\n";
    fs.writeFileSync(file, rows);
  }
  append("session_meta", {
    id: session,
    source: "appServer",
    title: "[模拟审批] Codex 等待确认",
    cwd: root,
  });
  append("event_msg", { type: "task_started", turn_id: turn });
  const service = new CodexService({
    home,
    desktopEnabled: false,
    dataDir: path.join(root, "codex-data"),
    hookExecutable: executable,
    executable,
    packaged: true,
    activityHooks: true,
    externalQuotaRefresh: true,
    rpcClient: {
      on() {},
      stop() {},
      async request() {
        throw Error("Isolated fixture has no account");
      },
    },
    runCommand: async (_exe, args) =>
      args[0] === "--version" ? "codex-isolated-fixture" : "hooks stable true",
  });
  await service.start();
  await service.configure({ activityHooks: true, scope: "all" });
  function hook(event, extra = {}) {
    return new Promise((resolve, reject) => {
      const child = spawn(
        executable,
        ["--quotaview-codex-hook", "--configuration", service.hooks.routePath],
        { windowsHide: true, stdio: ["pipe", "pipe", "pipe"] },
      );
      let output = "";
      const timer = setTimeout(() => {
        child.kill();
        reject(Error("Codex fixture hook timeout"));
      }, 5000);
      child.stdout.on("data", (b) => (output += b));
      child.stderr.on("data", () => {});
      child.stdin.on("error", () => {});
      child.on("error", (e) => {
        clearTimeout(timer);
        reject(e);
      });
      child.on("close", (code) => {
        clearTimeout(timer);
        if (code || output)
          reject(Error("Observation hook returned a decision or failed"));
        else resolve();
      });
      child.stdin.end(
        JSON.stringify({
          session_id: session,
          turn_id: turn,
          hook_event_name: event,
          tool_name: "Bash",
          ...extra,
        }),
      );
    });
  }
  return { service, hook, append, turn, session, stop: () => service.stop() };
};
