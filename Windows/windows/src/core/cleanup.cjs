"use strict";
const fs = require("node:fs/promises"),
  path = require("node:path");
const { IntegrationService } = require("./integrations.cjs");
const { CodexHooks } = require("./codex-hooks.cjs");
const F = require("./integration-files.cjs");
// Called only by explicit uninstall, never by normal quit or upgrade. Existing
// ownership manifests drive cleanup; user configuration and backups survive.
async function cleanupIntegrations(options) {
  const integrations = new IntegrationService(options),
    failures = [];
  for (const provider of ["claude", "dsh", "kimi"]) {
    try {
      if (!(await F.json(integrations.manifestPath(provider)))) continue;
      await integrations.configure(provider, false);
      const manifest = await integrations.readManifest(provider);
      if (manifest?.configs?.length) failures.push(provider);
    } catch {
      failures.push(provider);
    }
  }
  const root = path.join(options.dataDir, "integrations", "codex");
  const entries = await fs.readdir(root, { withFileTypes: true }).catch((e) => {
    if (e.code !== "ENOENT") failures.push("codex");
    return [];
  });
  for (const entry of entries) {
    if (!entry.isDirectory() || !/^\w{16}$/.test(entry.name)) continue;
    try {
      const manifest = await F.json(
        path.join(root, entry.name, "installation.json"),
      );
      if (!manifest) continue;
      if (
        typeof manifest.home !== "string" ||
        F.hash(path.resolve(manifest.home)).slice(0, 16) !== entry.name
      )
        throw Error("Invalid installation record");
      const hooks = new CodexHooks({ ...options, home: manifest.home });
      await hooks.configure({ activityHooks: false });
    } catch {
      failures.push("codex");
    }
  }
  return { ok: failures.length === 0, failures: [...new Set(failures)] };
}
module.exports = { cleanupIntegrations };
