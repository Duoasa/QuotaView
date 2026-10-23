"use strict";
const { test } = require("node:test"),
  assert = require("node:assert/strict"),
  fs = require("node:fs/promises"),
  os = require("node:os"),
  path = require("node:path");
const { IntegrationService } = require("../src/core/integrations.cjs");
const { cleanupIntegrations } = require("../src/core/cleanup.cjs");
async function fixture(t) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "qv-config-"));
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const home = path.join(root, "claude");
  await fs.mkdir(home);
  const options = {
    dataDir: path.join(root, "data"),
    home: root,
    env: {},
    settings: { claudeHome: home, providers: { claude: false } },
    executable: process.execPath,
    hookPath: path.resolve(__dirname, "../src/core/hook.cjs"),
  };
  return { home, options };
}
test("Claude enable/reconfigure/uninstall preserves unrelated hooks, settings and original statusline", async (t) => {
  const { home, options } = await fixture(t),
    file = path.join(home, "settings.json");
  const original = {
    model: "user-choice",
    hooks: {
      Stop: [
        {
          matcher: "*",
          hooks: [{ type: "command", command: "user-owned-command" }],
        },
      ],
    },
    statusLine: {
      type: "command",
      command: "user-status",
      args: ["with spaces"],
    },
  };
  await fs.writeFile(file, JSON.stringify(original));
  const service = new IntegrationService(options);
  await service.configure("claude", true, { statusLine: true });
  await service.configure("claude", true, { statusLine: true });
  const installed = JSON.parse(await fs.readFile(file, "utf8"));
  assert.equal(installed.hooks.Stop.length, 2);
  assert.equal(installed.model, "user-choice");
  assert.notEqual(installed.statusLine.command, "user-status");
  const result = await cleanupIntegrations(options);
  assert.equal(result.ok, true);
  const restored = JSON.parse(await fs.readFile(file, "utf8"));
  assert.deepEqual(restored, original);
  assert.ok((await fs.readdir(home)).some((n) => n.endsWith(".backup")));
});
test("uninstall refuses malformed owned configuration and preserves original bytes", async (t) => {
  const { home, options } = await fixture(t),
    file = path.join(home, "settings.json"),
    service = new IntegrationService(options);
  await service.configure("claude", true);
  await fs.writeFile(file, "{broken user edit");
  const result = await cleanupIntegrations(options);
  assert.equal(result.ok, false);
  assert.equal(await fs.readFile(file, "utf8"), "{broken user edit");
});
