"use strict";
const { test } = require("node:test"),
  assert = require("node:assert/strict"),
  fs = require("node:fs/promises"),
  os = require("node:os"),
  path = require("node:path"),
  net = require("node:net"),
  { spawn } = require("node:child_process");
const executable = process.env.QUOTAVIEW_HELPER || path.resolve(__dirname, "../dist/helper/quotaview-hook.exe");
const windows = process.platform === "win32";
function run(args, input = "") {
  return new Promise((resolve, reject) => {
    const child = spawn(executable, args, {
      windowsHide: true,
      stdio: ["pipe", "pipe", "pipe"],
    });
    let out = "",
      err = "";
    const timer = setTimeout(() => {
      child.kill();
      reject(Error("Helper exceeded test deadline"));
    }, 8000);
    child.on("error", reject);
    child.stdout.on("data", (b) => (out += b));
    child.stderr.on("data", (b) => (err += b));
    child.stdin.on("error", () => {});
    child.stdin.end(input);
    child.on("close", (code) => {
      clearTimeout(timer);
      resolve({ code, out, err });
    });
  });
}
async function route(t, provider, callback, extra = {}) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "qv-native-"));
  const file = path.join(root, "route.json");
  const sockets = new Set();
  const server = net.createServer((s) => {
    sockets.add(s);
    s.on("error", () => {});
    s.on("close", () => sockets.delete(s));
    let b = "";
    s.on("data", (d) => {
      b += d;
      const i = b.indexOf("\n");
      if (i >= 0) {
        const envelope = JSON.parse(b.slice(0, i));
        b = b.slice(i + 1);
        callback(s, envelope);
      }
    });
  });
  await new Promise((r) => server.listen(0, "127.0.0.1", r));
  t.after(async () => {
    for (const s of sockets) s.destroy();
    await new Promise((r) => server.close(r));
    await fs.rm(root, { recursive: true, force: true });
  });
  await fs.writeFile(
    file,
    JSON.stringify({
      version: 1,
      provider,
      enabled: true,
      host: "127.0.0.1",
      port: server.address().port,
      authenticationToken: "a".repeat(64),
      installationId: "fixture",
      decisionTimeoutMs: 80,
      ...extra,
    }),
  );
  return file;
}
test(
  "native helper self-test and fail-open invalid route",
  { skip: !windows },
  async () => {
    const smoke = await run(["--helper-smoke-test"]);
    assert.equal(smoke.code, 0);
    assert.equal(JSON.parse(smoke.out).ok, true);
    const failed = await run(
      ["--quotaview-hook", "--configuration", path.join(os.tmpdir(), `quotaview-missing-${process.pid}-${Date.now()}`, "route.json")],
      "{}",
    );
    assert.equal(failed.code, 0);
    assert.equal(failed.out, "");
  },
);
test(
  "native Codex wire preserves event IDs and excludes content",
  { skip: !windows },
  async (t) => {
    let payload;
    const file = await route(t, "codex", (s, e) => {
      payload = e.payload;
      assert.equal(e.installationId, "fixture");
      s.end(JSON.stringify({ eventId: e.eventId, accepted: true }) + "\n");
    });
    const result = await run(
      ["--quotaview-codex-hook", "--configuration", file],
      JSON.stringify({
        hook_event_name: "PermissionRequest",
        tool_name: "Bash",
        tool_use_id: "tool-invocation",
        session_id: "session",
        turn_id: "turn",
        prompt: "private",
        tool_input: { secret: true },
      }),
    );
    assert.equal(result.code, 0);
    assert.equal(result.out, "");
    assert.deepEqual(payload, {
      event: "PermissionRequest",
      toolName: "Bash",
      toolUseId: "tool-invocation",
      sessionId: "session",
      turnId: "turn",
    });
  },
);
test(
  "native Claude emits only a correlated live permission decision",
  { skip: !windows },
  async (t) => {
    const file = await route(t, "claude", (s, e) => {
      assert.equal(e.awaitDecision, true);
      assert.equal(e.payload.prompt_id, "current");
      s.write(
        JSON.stringify({ eventID: e.eventID, accepted: true, pending: true }) +
          "\n",
      );
      s.end(
        JSON.stringify({
          eventID: e.eventID,
          decision: {
            behavior: "deny",
            message: "Fixture denial",
            interrupt: true,
          },
        }) + "\n",
      );
    });
    const result = await run(
      ["--quotaview-hook", "--configuration", file],
      JSON.stringify({
        hook_event_name: "PermissionRequest",
        session_id: "s",
        prompt_id: "current",
        tool_input: { command: "fixture" },
      }),
    );
    assert.equal(result.code, 0);
    assert.equal(
      JSON.parse(result.out).hookSpecificOutput.decision.behavior,
      "deny",
    );
  },
);
test(
  "native mismatched decision and timeout never approve",
  { skip: !windows },
  async (t) => {
    for (const mode of ["mismatch", "timeout"]) {
      const file = await route(t, "claude", (s, e) => {
        s.write(
          JSON.stringify({
            eventID: e.eventID,
            accepted: true,
            pending: true,
          }) + "\n",
        );
        if (mode === "mismatch")
          s.end(
            JSON.stringify({
              eventID: "other",
              decision: { behavior: "allow" },
            }) + "\n",
          );
      });
      const result = await run(
        ["--quotaview-hook", "--configuration", file],
        JSON.stringify({
          hook_event_name: "PermissionRequest",
          session_id: "s",
          tool_input: {},
        }),
      );
      assert.equal(result.code, 0);
      assert.equal(result.out, "");
    }
  },
);
test(
  "native statusline keeps original command, arguments, Unicode input and output",
  { skip: !windows },
  async (t) => {
    const file = await route(
      t,
      "claude",
      (s, e) =>
        s.end(JSON.stringify({ eventID: e.eventID, accepted: true }) + "\n"),
      {
        originalStatusLine: {
          command: process.execPath,
          args: [
            "-e",
            'process.stdin.setEncoding("utf8");let s="";process.stdin.on("data",b=>s+=b);process.stdin.on("end",()=>process.stdout.write(JSON.parse(s).model.display_name+":"+process.argv[1]));',
            'quoted "value" \\',
          ],
        },
      },
    );
    const result = await run(
      ["--quotaview-hook", "--configuration", file, "--mode", "statusline"],
      JSON.stringify({ session_id: "s", model: { display_name: "模型" } }),
    );
    assert.equal(result.code, 0);
    assert.equal(result.out, '模型:quoted "value" \\');
  },
);
