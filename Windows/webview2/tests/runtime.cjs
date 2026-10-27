// Executes in the private WebView2 backend, against the real .NET adapters.
const fs = require("node:fs"),
  path = require("node:path"),
  os = require("node:os"),
  net = require("node:net"),
  { spawn } = require("node:child_process");
const F = require("../../windows/src/core/integration-files.cjs");
const {
  IntegrationService,
  safeParseConfig,
} = require("../../windows/src/core/integrations.cjs");
const { QuotaProxy } = require("../../windows/src/core/proxy.cjs");
const {
  RolloutDiscovery,
} = require("../../windows/src/core/codex-rollout.cjs");
const results = [];
const assert = (value, message) => {
  if (!value) throw Error(message);
};
const deadline = (promise, ms = 12000) =>
  Promise.race([
    promise,
    new Promise((_, reject) =>
      setTimeout(() => reject(Error("Test timeout")), ms),
    ),
  ]);
const run = (args, input = "") =>
  deadline(
    new Promise((resolve, reject) => {
      const child = spawn(process.execPath, args);
      let out = "";
      child.stdout.setEncoding("utf8").on("data", (s) => (out += s));
      child.on("error", reject);
      child.on("close", (code) =>
        code ? reject(Error("Helper exit " + code)) : resolve(out),
      );
      child.stdin.end(input);
    }),
  );
const test = async (name, fn) => {
  try {
    await deadline(fn());
    results.push({ name, ok: true });
  } catch (error) {
    results.push({ name, ok: false, error: String(error.stack || error) });
  }
};
(async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "qv-webview-test-"));
  await test("file handles, Unicode, directory enumeration and SHA256", async () => {
    const file = path.join(root, "你好.json");
    await F.atomic(file, '{"value":"量子"}', { expected: null });
    assert((await F.json(file)).value === "量子", "UTF8 file roundtrip");
    const dir = await fs.promises.opendir(root);
    assert((await dir.read()).name === "你好.json", "Directory enumeration");
    await dir.close();
    assert(
      F.hash("abc") ===
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
      "SHA256",
    );
  });
  await test("configuration conflicts and live/stale locks", async () => {
    const file = path.join(root, "guard.json");
    await F.atomic(file, "before");
    let rejected = false;
    try {
      await F.atomic(file, "bad", { expected: Buffer.from("wrong") });
    } catch {
      rejected = true;
    }
    assert(
      rejected && fs.readFileSync(file, "utf8") === "before",
      "Revision guard",
    );
    const locks = path.join(root, "locks");
    await F.withLock(locks, async () => {
      let locked = false;
      try {
        await F.withLock(locks, async () => {});
      } catch {
        locked = true;
      }
      assert(locked, "Live lock protected");
    });
    fs.writeFileSync(
      path.join(locks, "install.lock"),
      JSON.stringify({ pid: 2147483647 }),
    );
    await F.withLock(locks, async () => {});
  });
  await test("TOML and YAML validation in WebView2", async () => {
    safeParseConfig('name = "example"\n', "toml");
    safeParseConfig("- name: example\n", "yaml");
    let bad = false;
    try {
      safeParseConfig("[bad", "toml");
    } catch {
      bad = true;
    }
    assert(bad, "Malformed TOML rejected");
  });
  await test(".NET headless helper stdio and fail-open route", async () => {
    assert(
      JSON.parse(await run(["--helper-smoke-test"])).ok,
      ".NET helper self test",
    );
    assert(
      (await run(
        [
          "--quotaview-hook",
          "--configuration",
          path.join(root, "missing.json"),
        ],
        "{}",
      )) === "",
      "Missing route preserves agent defaults",
    );
  });
  await test("persistent child receives flushed stdin before EOF", async () => {
    const child = spawn(process.execPath, ["--stdio-adapter-test"]);
    try {
      const line = await deadline(
        new Promise((resolve, reject) => {
          child.stdout.once("data", (b) => resolve(b.toString()));
          child.once("error", reject);
          child.stdin.write("live-pipe\n");
        }),
        3000,
      );
      assert(line.trim() === "live-pipe", "Persistent RPC stdin flush");
    } finally {
      child.kill();
    }
  });
  await test("TCP ordered writes and half-close", async () => {
    const server = net.createServer({ allowHalfOpen: true }, (s) => {
      let value = "";
      s.on("error", () => {});
      s.on("data", (b) => (value += b));
      s.on("end", () => {
        s.write("reply:");
        s.end(value);
      });
    });
    await new Promise((r) => server.listen(0, "127.0.0.1", r));
    try {
      const answer = await deadline(
        new Promise((resolve, reject) => {
          const c = net.connect(
            { port: server.address().port, host: "127.0.0.1" },
            () => {
              c.write("one");
              c.end("two");
            },
          );
          let text = "";
          c.on("data", (b) => (text += b));
          c.on("end", () => resolve(text));
          c.on("error", reject);
        }),
      );
      assert(answer === "reply:onetwo", "Ordered half-open roundtrip");
    } finally {
      server.close();
    }
  });
  await test("authenticated HTTP CONNECT proxy preserves payload", async () => {
    const echo = net.createServer((s) => {
      s.on("error", () => {});
      s.on("data", (b) => s.write(b));
      s.on("end", () => s.end());
    });
    await new Promise((r) => echo.listen(0, "127.0.0.1", r));
    const proxy = new QuotaProxy(async () => "DIRECT");
    const url = new URL(await proxy.start({ mode: "system" }));
    try {
      const answer = await deadline(
        new Promise((resolve, reject) => {
          const c = net.connect(
            { host: "127.0.0.1", port: Number(url.port) },
            () =>
              c.write(
                `CONNECT 127.0.0.1:${echo.address().port} HTTP/1.1\r\nProxy-Authorization: ${proxy.authorization}\r\n\r\n`,
              ),
          );
          let text = "",
            sent = false;
          c.on("error", reject);
          c.on("data", (b) => {
            text += b;
            if (!sent && text.includes("\r\n\r\n")) {
              sent = true;
              c.write("proxy-payload");
            }
            if (text.endsWith("proxy-payload")) {
              c.destroy();
              resolve(text);
            }
          });
        }),
      );
      assert(answer.startsWith("HTTP/1.1 200"), "CONNECT success");
    } finally {
      await proxy.stop();
      echo.close();
    }
  });
  await test("Claude install, live native hook, and configuration restoration", async () => {
    const home = path.join(root, "claude");
    fs.mkdirSync(home);
    const file = path.join(home, "settings.json");
    const original = {
      model: "user-choice",
      hooks: {
        Stop: [{ hooks: [{ type: "command", command: "user-command" }] }],
      },
    };
    fs.writeFileSync(file, JSON.stringify(original));
    const service = new IntegrationService({
      dataDir: path.join(root, "data"),
      home: root,
      env: {},
      settings: { claudeHome: home, providers: { claude: false } },
      executable: process.execPath,
      packaged: true,
    });
    try {
      await service.start();
      await service.configure("claude", true);
      await run(
        ["--quotaview-hook", "--configuration", service.routePath("claude")],
        JSON.stringify({
          hook_event_name: "SessionStart",
          session_id: "migration-fixture",
          cwd: root,
        }),
      );
      assert(
        service.getSnapshot().tasks.some((t) => t.provider === "claude"),
        "Native hook reached live JS integration",
      );
      await service.configure("claude", false);
      assert(
        JSON.stringify(JSON.parse(fs.readFileSync(file, "utf8"))) ===
          JSON.stringify(original),
        "Unrelated hooks preserved",
      );
    } finally {
      await service.stop();
    }
  });
  const report = {
    ok: results.every((x) => x.ok),
    runtime: "WebView2 + .NET",
    tests: results,
  };
  const output = process.argv
    .find((x) => x.startsWith("--adapter-report="))
    ?.slice(17);
  if (output) fs.writeFileSync(output, JSON.stringify(report, null, 2));
  console.log(JSON.stringify(report));
  process.exit(report.ok ? 0 : 1);
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
