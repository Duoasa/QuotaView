"use strict";
const fs = require("node:fs");
const path = require("node:path");
const DEFAULTS = Object.freeze({
  language: "system",
  theme: "dark",
  material: "solid",
  effect: "quantum",
  islandWidth: 680,
  showCapsule: true,
  privacy: false,
  autoExpand: true,
  alwaysOnTop: true,
  startAtLogin: false,
  display: "active",
  refreshSeconds: 60,
  notifications: true,
  autoCheckUpdates: false,
  providers: { codex: true, claude: false, dsh: false, kimi: false },
  codexPath: "",
  codexHome: "",
  claudeHome: "",
  dshRoots: [],
  reduceMotion: false,
  showTokens: true,
  showCost: true,
  showActivity: true,  collapseDelaySeconds: 15,
  lowQuotaNotifications: true,
  completionNotifications: true,
  proxy: { mode: "system", url: "" },
  tokenActivityRange: "month",
  showRemainingQuota: true,
  showResetCountdown: true,
  showUsageSummary: true,
  showSparkQuota: true,
  showCreditBalance: true,
  showDailyTokens: true,
  showThirtyDayTokens: true,
  showLifetimeTokens: true,  codexActivityHooks: false,
  codexHookScope: "all",
});
const bools = [
  "showCapsule",
  "privacy",
  "autoExpand",  "autoCheckUpdates",  "showCost",
  "showActivity",  "codexActivityHooks",];
function cleanSettings(input = {}) {
  const s = structuredClone(DEFAULTS);
  for (const key of bools)
    if (typeof input[key] === "boolean") s[key] = input[key];
  const enums = {
    language: ["system", "en", "zh"],
    theme: ["system", "light", "dark"],
    effect: ["quantum"],
    codexHookScope: ["all", "compaction"],
    tokenActivityRange: ["week", "month", "threeMonths", "sixMonths"],
  };
  for (const [k, values] of Object.entries(enums))
    if (values.includes(input[k])) s[k] = input[k];
  for (const [k, min, max] of [
    ["islandWidth", 520, 800],
    ["refreshSeconds", 15, 3600],
    ["collapseDelaySeconds", 5, 60],  ])
    if (Number.isFinite(input[k]))
      s[k] = Math.max(min, Math.min(max, input[k]));
  if (
    ["active", "primary"].includes(input.display) ||
    /^\d+$/.test(String(input.display))
  )
    s.display = String(input.display);
  for (const p of Object.keys(s.providers))
    if (typeof input.providers?.[p] === "boolean")
      s.providers[p] = input.providers[p];
  for (const p of ["codexPath", "codexHome", "claudeHome"])
    if (typeof input[p] === "string" && !/[\x00\r\n]/.test(input[p]))
      s[p] = input[p].slice(0, 4096);
  if (Array.isArray(input.dshRoots))
    s.dshRoots = [
      ...new Set(
        input.dshRoots.filter(
          (x) =>
            typeof x === "string" && x.length < 4096 && !/[\x00\r\n]/.test(x),
        ),
      ),
    ].slice(0, 32);
  if (["system", "direct", "manual"].includes(input.proxy?.mode))
    s.proxy.mode = input.proxy.mode;
  if (typeof input.proxy?.url === "string" && input.proxy.url.length < 2048) {
    try {
      const u = new URL(input.proxy.url);
      if (
        ["http:", "https:", "socks5:", "socks4:"].includes(u.protocol) &&
        u.hostname &&
        !u.username &&
        !u.password &&
        (!u.pathname || u.pathname === "/") &&
        !u.search &&
        !u.hash
      )
        s.proxy.url = `${u.protocol}//${u.host}`;
    } catch {}
  }
  s.theme = "dark";
  return s;
}
class SettingsStore {
  constructor(dir) {
    this.file = path.join(dir, "preferences.json");
    this.error = null;
    this.value = cleanSettings();
  }
  load() {
    try {
      const data = fs.readFileSync(this.file, "utf8");
      if (data.length > 65536) throw Error("Preferences exceed size limit");
      this.value = cleanSettings(JSON.parse(data));
    } catch (e) {
      if (e.code !== "ENOENT")
        this.error =
          "Preferences could not be read; defaults are in use. Existing file was preserved.";
    }
    return this.value;
  }
  update(patch) {
    if (!patch || typeof patch !== "object" || Array.isArray(patch))
      throw Error("Invalid preferences");
    const next = cleanSettings({
      ...this.value,
      ...patch,
      providers: { ...this.value.providers, ...patch.providers },
      proxy: { ...this.value.proxy, ...patch.proxy },
    });
    fs.mkdirSync(path.dirname(this.file), { recursive: true, mode: 0o700 });
    const tmp = this.file + ".tmp";
    fs.writeFileSync(tmp, JSON.stringify(next, null, 2), { mode: 0o600 });
    fs.renameSync(tmp, this.file);
    this.value = next;
    this.error = null;
    return next;
  }
}
module.exports = { DEFAULTS, cleanSettings, SettingsStore };
