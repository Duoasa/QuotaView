"use strict";
const { test } = require("node:test"),
  assert = require("node:assert/strict"),
  fs = require("node:fs/promises"),
  os = require("node:os"),
  path = require("node:path");
const state = require("../shared/task-state.js");
const { selectRelease, compareVersions } = require("../src/core/updates.cjs");
const {
  roundedRegion,
  materialFor,
} = require("../src/core/window-material.cjs");
const { transcriptPreview } = require("../src/core/claude-data.cjs");
test("canonical progress preserves the active step, caps running tasks, and requires verified completion", () => {
  const progress = { fraction: 0.55, completed: 1, total: 2 };
  assert.equal(state.progressValue({ progress }), 0.55);
  assert.equal(state.presentationProgress({ progress }).percent, 0.55 * 100);
  assert.equal(
    state.progressValue({ progress: { completed: 2, total: 2 } }),
    0.95,
  );
  assert.equal(state.progressValue({ status: "completed", verified: true }), 1);
  assert.equal(
    state.progressValue({ status: "completed", verified: false }),
    null,
  );
  assert.equal(
    state.advancePlan(progress, { fraction: 0.25, completed: 0, total: 4 })
      .fraction,
    0.55,
  );
  assert.equal(
    state.progressValue({ progress: { completed: 0, total: 0 } }),
    null,
  );
});
test("stale observation freezes state but preserves a live approval and terminal proof", () => {
  assert.equal(
    state.freshTask({ status: "working", updatedAt: 1 }, 400000).status,
    "unknown",
  );
  assert.equal(
    state.freshTask(
      { status: "waiting", updatedAt: 1, approval: { canRespond: true } },
      400000,
    ).status,
    "waiting",
  );
  assert.equal(
    state.freshTask({ status: "completed", updatedAt: 1 }, 400000).status,
    "completed",
  );
});
test("legacy effects versions remain updateable and malformed current versions fail visibly", () => {
  const tag = "v0.8.4-win.1";
  assert.equal(
    selectRelease(
      [
        {
          tag_name: tag,
          html_url:
            "https://github.com/Duoasa/QuotaView/releases/tag/" + tag,
        },
      ],
      "0.8.3-win.1.effects.2",
    ).available,
    true,
  );
  assert.equal(compareVersions("0.8.3-win.2", "0.8.3-win.1.effects.99"), 1);
  assert.throws(() => selectRelease([], "garbage"));
  assert.equal(
    selectRelease(
      [{ tag_name: tag, html_url: "https://example.test" }],
      "0.8.3-win.1",
    ).available,
    false,
  );
});
test("rounded clipping stays inside the native window, with explicit backdrop fallbacks", () => {
  const region = roundedRegion(
    { x: 0, y: 0, width: 270, height: 66, topRadius: 0, bottomRadius: 24 },
    { width: 270, height: 66 },
  );
  assert.equal(region[0].width, 270);
  assert.ok(region.at(-1).width < 270);
  for (const r of region)
    assert.ok(r.x >= 0 && r.x + r.width <= 270 && r.y + r.height <= 66);
  assert.throws(() => roundedRegion({ x: NaN }, { width: 270, height: 66 }));
  const supported = {
    platform: "win32",
    release: "10.0.22621",
    enabled: true,
    regionReady: true,
  };
  assert.equal(materialFor(supported), "acrylic");
  assert.equal(materialFor({ ...supported, settings: true }), "mica");
  for (const patch of [
    { platform: "darwin" },
    { release: "10.0.19045" },
    { transparency: false },
    { highContrast: true },
    { regionReady: false },
  ])
    assert.equal(materialFor({ ...supported, ...patch }), "none");
});
test("Claude new turn never inherits old answers, interruption, or token usage", async (t) => {
  const home = await fs.mkdtemp(path.join(os.tmpdir(), "qv-claude-"));
  t.after(() => fs.rm(home, { recursive: true, force: true }));
  await fs.mkdir(path.join(home, "projects"));
  const file = path.join(home, "projects", "session.jsonl");
  const now = Date.now();
  const old = [
    {
      type: "user",
      uuid: "old",
      timestamp: new Date(now - 10000).toISOString(),
      message: { content: "Previous prompt" },
    },
    {
      type: "assistant",
      message: { content: [{ type: "text", text: "Old answer" }] },
    },
    { type: "user", message: { content: "[Request interrupted by user]" } },
  ];
  await fs.writeFile(file, old.map(JSON.stringify).join("\n") + "\n");
  const boundary = { startedAt: now, promptId: "current", requireMatch: true };
  assert.equal(await transcriptPreview(home, file, { boundary }), null);
  await fs.appendFile(
    file,
    JSON.stringify({
      type: "user",
      uuid: "current",
      timestamp: new Date(now - 50).toISOString(),
      message: { content: "Current prompt" },
    }) + "\n",
  );
  let preview = await transcriptPreview(home, file, { boundary });
  assert.equal(preview.interrupted, false);
  assert.equal(preview.publicText, "");
  assert.equal(preview.tokens, undefined);
  await fs.appendFile(
    file,
    JSON.stringify({
      type: "assistant",
      message: { content: [{ type: "text", text: "New answer" }] },
    }) + "\n",
  );
  preview = await transcriptPreview(home, file, { boundary });
  assert.equal(preview.publicText, "New answer");
  assert.equal(
    await transcriptPreview(home, file, {
      boundary: { startedAt: now + 100, requireMatch: true },
    }),
    null,
  );
});

test("proxy settings keep only a usable endpoint and discard removed reset preferences", () => {
  const { cleanSettings } = require("../src/core/settings.cjs");
  assert.equal(
    cleanSettings({ proxy: { mode: "manual", url: "http://localhost:7890/" } })
      .proxy.url,
    "http://localhost:7890",
  );
  assert.equal(
    cleanSettings({ proxy: { mode: "manual", url: "socks5://[::1]:1080" } })
      .proxy.url,
    "socks5://[::1]:1080",
  );
  for (const url of [
    "http://u:p@host:80",
    "http://host/path",
    "http://host/?token=secret",
  ])
    assert.equal(
      cleanSettings({ proxy: { mode: "manual", url } }).proxy.url,
      "",
    );
  assert.equal(
    "showResetAction" in cleanSettings({ showResetAction: true }),
    false,
  );
});

test("pending requests unify display status without changing execution state", () => {
  const task = {
    id: "task",
    status: "working",
    tool: "wait",
    compacting: true,
    approval: {
      id: "question",
      kind: "question",
      asynchronous: true,
      canRespond: false,
      questions: [{ answered: false }],
    },
  };
  assert.equal(state.displayState(task), "waiting");
  assert.equal(state.needsAttention(task), true);
  assert.equal(state.attentionKey(task), "task:question");
  assert.equal(task.status, "working");
  assert.equal(
    state.displayState({ ...task, status: "completed" }),
    "completed",
  );
  assert.equal(state.needsAttention({ ...task, status: "completed" }), false);
  assert.equal(
    state.displayState({ ...task, approval: undefined }),
    "compacting",
  );
  assert.equal(
    state.needsAttention({
      ...task,
      approval: { ...task.approval, questions: [{ answered: true }] },
    }),
    false,
  );
});
