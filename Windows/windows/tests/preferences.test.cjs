const { test } = require("node:test");
const assert = require("node:assert/strict");
const { cleanSettings } = require("../src/core/settings.cjs");
test("legacy Windows-only preferences cannot hide the island or disable the retained effects", () => {
  const value = cleanSettings({
    effect: "wave",
    hiddenDelaySeconds: 1,
    compactDelaySeconds: 0,
    hoverTransparency: true,
    autoExpandOnStart: false,
    reduceMotion: true,
    showTokens: false,
    showUsageSummary: false,
    showDailyTokens: false,
    showRemainingQuota: false,
  });
  assert.equal(value.effect, "quantum");
  for (const key of [
    "hiddenDelaySeconds",
    "compactDelaySeconds",
    "hoverTransparency",
    "autoExpandOnStart",
  ])
    assert.equal(key in value, false);
  assert.equal(value.reduceMotion, false);
  for (const key of [
    "showTokens",
    "showUsageSummary",
    "showDailyTokens",
    "showRemainingQuota",
  ])
    assert.equal(value[key], true);
});
test("mac-aligned preferences retain optional modules, material, privacy and screen selection", () => {
  const value = cleanSettings({
    showCost: false,
    showActivity: false,
    privacy: true,
    material: "solid",
    autoExpand: false,
    display: "123",
    islandWidth: 10000,
    collapseDelaySeconds: 0,
  });
  assert.equal(value.showCost, false);
  assert.equal(value.showActivity, false);
  assert.equal(value.privacy, true);
  assert.equal(value.material, "solid");
  assert.equal(value.autoExpand, false);
  assert.equal(value.display, "123");
  assert.equal(value.islandWidth, 800);
  assert.equal(value.collapseDelaySeconds, 5);
});

test("legacy glass preferences always migrate to opaque Windows surfaces", () => {
  for (const material of ["glass", "solid", "invalid", undefined]) {
    const value = cleanSettings({ material, blackRatio: 0.2, theme: "light" });
    assert.equal(value.material, "solid");
    assert.equal(value.theme, "dark");
    assert.equal("blackRatio" in value, false);
  }
});
